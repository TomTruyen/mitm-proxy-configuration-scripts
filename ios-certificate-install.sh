#!/bin/bash

set -e

MITM_CERT_NAME="mitmproxy-ca-cert.crt"
MITM_CERT_PATH="./$MITM_CERT_NAME"

echo "[*] Starting iOS simulator mitmproxy setup..."

# Ensure mitmproxy CA cert exists
if [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    echo "[*] Generating mitmproxy CA certificate..."
    mitmdump --set block_global=false --mode=transparent --listen-port=0 --quiet &
    sleep 2
    pkill -f mitmdump
fi

# Check if Simulator booted
BOOTED=$(xcrun simctl list devices | grep -E 'Booted' | head -1 | awk -F '[()]' '{print $2}')
if [ -z "$BOOTED" ]; then
    echo "[x] No Simulator Booted. Please boot a simulator and try again..."
    exit 1
fi

echo "[✓] Using simulator: $BOOTED"

echo "[*] Installing root certificate on $BOOTED..."

# Copy cert locally
cp ~/.mitmproxy/mitmproxy-ca-cert.pem "$MITM_CERT_PATH"

# Try installing cert into simulator keychain
if xcrun simctl keychain "$BOOTED" add-root-cert "$MITM_CERT_PATH" 2>/dev/null; then
    echo "[✓] Certificate installed into simulator keychain."
else
    echo "[!] simctl keychain not available or failed."
    echo "[*] Opening certificate manually. You may need to trust it in Settings > General > About > Certificate Trust Settings."
    open -a Simulator
    open "$MITM_CERT_PATH"
fi

echo "[✓] iOS Simulator CA setup complete."

echo "[*] Setup mitmproxy to intercept traffic:"

interface="Ethernet" # Interface on Mac -> Bitrise uses "Ethernet", locally you might use Wi-Fi. Alternatively you could loop over all interfaces on Mac and update the inferface for all of them
echo "Setting proxy on $interface"
networksetup -setwebproxy "$interface" localhost 8080
networksetup -setwebproxystate "$interface" on
networksetup -setsecurewebproxy "$interface" localhost 8080
networksetup -setsecurewebproxystate "$interface" on

echo "[✓] Proxy setup complete. You can now use mitmproxy to intercept iOS simulator traffic."
