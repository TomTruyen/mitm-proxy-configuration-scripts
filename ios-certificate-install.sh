#!/bin/bash

# NOTE: If simctl does not work, then you need to select Xcode using: sudo xcode-select -s /Applications/Xcode.app

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

# Copy cert locally
cp ~/.mitmproxy/mitmproxy-ca-cert.pem "$MITM_CERT_PATH"

# Get or boot simulator
BOOTED=$(xcrun simctl list devices | grep -E 'Booted' | head -1 | awk -F '[()]' '{print $2}')
if [ -z "$BOOTED" ]; then
    echo "[*] Booting default iOS simulator..."
    DEVICE=$(xcrun simctl list devices available | grep 'iPhone' | head -1 | awk -F '[()]' '{print $2}')
    xcrun simctl boot "$DEVICE"
    BOOTED="$DEVICE"
fi

echo "[*] Using simulator: $BOOTED"

# Try installing cert into simulator keychain
if xcrun simctl keychain "$BOOTED" add-root-cert "$MITM_CERT_PATH" 2>/dev/null; then
    echo "[✓] Certificate installed into simulator keychain."
else
    echo "[!] simctl keychain not available or failed."
    echo "[*] Opening certificate manually. You may need to trust it in Settings > General > About > Certificate Trust Settings."
    open -a Simulator
    open "$MITM_CERT_PATH"
fi

# Optional: This only makes sense if you need to look at MacOS traffic as well.
# echo "[*] Setting up CA for MacOS"
# Install the CA cert into the MacOS keychain
# security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$MITM_CERT_PATH" || {
#     echo "[!] Failed to add certificate to System keychain. You may need to do this manually."
#     echo "[!] Open the certificate in Finder and add it to the System keychain."
}

echo "[✓] iOS Simulator CA setup complete."

echo "[*] Setup mitmproxy to intercept traffic:"

# NOTE: This sets it up for ALL network interfaces. If you want a specific one, you can modify the script.
interfaces="$(networksetup -listallnetworkservices | tail +2)" 

IFS=$'\n' # split on newlines in the for loops

for interface in $interfaces; do
  echo "[*] Setting proxy on $interface"
  networksetup -setwebproxy "$interface" localhost 8080
  networksetup -setwebproxystate "$interface" on
  networksetup -setsecurewebproxy "$interface" localhost 8080
  networksetup -setsecurewebproxystate "$interface" on
done

echo "[✓] Proxy setup complete. You can now use mitmproxy to intercept iOS simulator traffic."

