# aws-cvpn-client

An implementation of AWS Client VPN (cVPN) with SSO authentication, deployable via Nix Flake.

## Usage

Simply run the flake and provide your OpenVPN configuration file:

```shell
nix run github:sirn/aws-cvpn-client cvpn.ovpn
```

Follow the interactive authentication prompts to connect.

## Acknowledgements

This project builds upon the work of several existing implementations:

- [samm-git/aws-vpn-client](https://github.com/samm-git/aws-vpn-client)
- [botify-labs/aws-vpn-client](https://github.com/botify-labs/aws-vpn-client)
- [kpalang/aws-vpn-client-docker](https://github.com/kpalang/aws-vpn-client-docker)
- [pgagnidze/aws-vpn-client-docker](https://github.com/pgagnidze/aws-vpn-client-docker)