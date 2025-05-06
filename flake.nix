{
  description = "Custom OpenVPN build with AWS VPN patch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        customOpenvpn = pkgs.openvpn.overrideAttrs (oldAttrs: {
          pname = "aws-openvpn";
          version = "2.6.12";
          
          src = pkgs.fetchurl {
            url = "https://github.com/OpenVPN/openvpn/releases/download/v2.6.12/openvpn-2.6.12.tar.gz";
            hash = "sha256-HGEP3etobjTxNnw0fgJ+QY4HUjoQ9NjOSiwq8vYaGSk=";
          };

          patches = (oldAttrs.patches or []) ++ [
            (pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/botify-labs/aws-vpn-client/refs/heads/master/patches/openvpn-v2.6.12-aws.patch";
              hash = "sha256-x4Exeubh/e/oN+qtWVeY2H4OjBt/QLaDE4grMg9sfeM=";
            })
          ];

          postInstall = (oldAttrs.postInstall or "") + ''
            mv $out/sbin/openvpn $out/sbin/aws-openvpn
          '';
        });

        awsSsoServer = pkgs.buildGoModule {
          pname = "aws-sso-server";
          version = "0.1.0";
          src = ./src;
          vendorHash = null;

          buildPhase = ''
            runHook preBuild
            go build -o $GOPATH/bin/aws-sso-server ./aws-sso-server.go
            runHook postBuild
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp $GOPATH/bin/aws-sso-server $out/bin/
          '';
        };

        awsStartVpn = pkgs.runCommand "aws-start-vpn" { } ''
          mkdir -p $out/bin
          cp ${./src/aws-start-vpn.sh} $out/bin/aws-start-vpn.sh
          chmod +x $out/bin/aws-start-vpn.sh

          # Patch all command paths with their absolute Nix paths
          substituteInPlace $out/bin/aws-start-vpn.sh \
            --replace "#!/bin/bash" "#!${pkgs.bash}/bin/bash" \
            --replace "AWS_OPENVPN=aws-openvpn" "AWS_OPENVPN=${customOpenvpn}/bin/aws-openvpn" \
            --replace "AWS_SSO_SERVER=aws-sso-server" "AWS_SSO_SERVER=${awsSsoServer}/bin/aws-sso-server" \
            --replace "OPENSSL=openssl" "OPENSSL=${pkgs.openssl}/bin/openssl" \
            --replace "DIG=dig" "DIG=${pkgs.dnsutils}/bin/dig" \
            --replace "SED=sed" "SED=${pkgs.gnused}/bin/sed" \
            --replace "GREP=grep" "GREP=${pkgs.gnugrep}/bin/grep" \
            --replace "AWK=awk" "AWK=${pkgs.gawk}/bin/awk" \
            --replace "HEAD=head" "HEAD=${pkgs.coreutils}/bin/head" \
            --replace "CAT=cat" "CAT=${pkgs.coreutils}/bin/cat" \
            --replace "RM=rm" "RM=${pkgs.coreutils}/bin/rm" \
            --replace "MKTEMP=mktemp" "MKTEMP=${pkgs.coreutils}/bin/mktemp"
        '';
      in
      {
        packages = {
          default = pkgs.symlinkJoin {
            name = "aws-cvpn-tools";
            paths = [ customOpenvpn awsSsoServer awsStartVpn ];
          };
          openvpn = customOpenvpn;
          aws-sso-server = awsSsoServer;
          aws-start-vpn = awsStartVpn;
        };

        apps.default = flake-utils.lib.mkApp { 
          drv = pkgs.writeShellScriptBin "aws-cvpn" ''
            exec ${awsStartVpn}/bin/aws-start-vpn.sh "$@"
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ customOpenvpn awsSsoServer awsStartVpn ];
        };
      });
}
