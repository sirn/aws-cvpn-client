#!/bin/bash

set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    echo "Please run: sudo $0 <ovpn_config_file>"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <ovpn_config_file>"
    echo "Example: $0 cvpn.conf"
    exit 1
fi

# Define all command paths (these will be patched by Nix)
AWS_OPENVPN=aws-openvpn
AWS_SSO_SERVER=aws-sso-server
OPENSSL=openssl
DIG=dig
SED=sed
GREP=grep
AWK=awk
HEAD=head
CAT=cat
RM=rm
MKTEMP=mktemp

# Create temporary directory for intermediate files
TEMP_DIR=$($MKTEMP -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Set paths for temporary files
OVPN_INPUT="$1"
OVPN_CONF="$TEMP_DIR/rendered.ovpn"
SAML_RESPONSE_FILE="$TEMP_DIR/saml-response.txt"

# Clean up config from any auth directives
$SED -E 's/auth-user-pass|auth-federate|auth-retry interact|remote-random-hostname//g' "$OVPN_INPUT" > "$OVPN_CONF"

# Extract VPN host from config
VPN_HOST=$($GREP 'remote ' "$OVPN_CONF" | $AWK '{ print $2}')
PORT=443

# Generate a random hostname for connection
RAND=$($OPENSSL rand -hex 12)
SRV=$($DIG a +short "${RAND}.${VPN_HOST}" | $HEAD -n1)

# Remove remote directive since we'll provide it on command line
$SED -i -E 's/remote .*//g' "$OVPN_CONF"

echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})"
OVPN_OUT=$("$AWS_OPENVPN" --config "$OVPN_CONF" --verb 3 \
     --proto udp --remote "$SRV" "$PORT" \
     --auth-user-pass <( printf "%s\n%s\n" "N/A" "ACS::35001" ) | $GREP AUTH_FAILED,CRV1)

URL=$(echo "$OVPN_OUT" | $GREP -Eo 'https://.+')

if [ -z "$URL" ]; then
    echo "Failed to get SSO URL. Check your VPN configuration."
    exit 1
fi

echo
echo "Open the following URL in your browser to authenticate:"
echo
echo "$URL"
echo
echo "=== IMPORTANT ==="
echo "If you're running this script on a remote host (SSH),"
echo "you may need to forward port 35001 to your local machine:"
echo
echo "    ssh -L35001:127.0.0.1:35001 <remote-host>"
echo
echo "Waiting for authentication..."

# Run the AWS SSO server to capture SAML response
"$AWS_SSO_SERVER" "$SAML_RESPONSE_FILE"

# Get SID from the reply
VPN_SID=$(echo "$OVPN_OUT" | $AWK -F : '{print $7}')

if [ -z "$VPN_SID" ]; then
    echo "Failed to extract VPN session ID."
    exit 1
fi

echo "Authentication successful. Starting VPN connection..."

# Finally OpenVPN with a SAML response we got
# Delete saml-response.txt after connect
exec "$AWS_OPENVPN" --config "$OVPN_CONF" \
    --verb 3 --auth-nocache --inactive 3600 \
    --proto udp --remote "$SRV" "$PORT" \
    --script-security 2 \
    --auth-user-pass <( printf "%s\n%s\n" "N/A" "CRV1::$VPN_SID::$($CAT "$SAML_RESPONSE_FILE")" )
