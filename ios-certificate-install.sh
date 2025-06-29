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
SIMULATOR=$(xcrun simctl list devices | grep -E 'Booted' | head -1 | awk -F '[()]' '{print $2}')
if [ -z "$SIMULATOR" ]; then
    echo "[x] No Simulator Booted. Please boot a simulator and try again..."
    exit 1
fi

echo "[✓] Using simulator: $SIMULATOR"

echo "[*] Installing root certificate on $SIMULATOR..."

# Copy cert locally
cp ~/.mitmproxy/mitmproxy-ca-cert.pem "$MITM_CERT_PATH"

# Try installing cert into simulator keychain
if xcrun simctl keychain "$SIMULATOR" add-root-cert "$MITM_CERT_PATH" 2>/dev/null; then
    echo "[✓] Certificate installed into simulator keychain."
else
    echo "[x] simctl unavailable - automatic install not possible."
    exit 1
    # Manual install -> Unused because we want it to run automatically
#    echo "[!] simctl keychain not available or failed."
#    echo "[*] Opening certificate manually. You may need to trust it in Settings > General > About > Certificate Trust Settings."
#    open -a Simulator
#    open "$MITM_CERT_PATH"
fi

echo "[✓] iOS Simulator CA setup complete."

echo "[*] Setup mitmproxy to intercept traffic..."
# Use the Interface that you device uses: Wi-Fi or Ethernet
# If you are not running this on a CI/CD environment, then be sure to reset the networksetups by updating the state values to "off" after use
interface="Ethernet"
echo "Setting proxy on $interface"
networksetup -setwebproxy "$interface" localhost 8080
networksetup -setwebproxystate "$interface" on
networksetup -setsecurewebproxy "$interface" localhost 8080
networksetup -setsecurewebproxystate "$interface" on

# Optional -> If you have issues with certain things like dependencies or general network traffic no longer working on CI/CD then use this, else don't
# echo "[*] Trusting mitmproxy CA on Mac..." # Required for xcode-test to actually download dependencies
# security create-keychain -p password build.keychain
# security import "$MITM_CERT_PATH" -k build.keychain -A
# security list-keychains -s build.keychain login.keychain
# security set-keychain-settings -t 3600 -l build.keychain
# security unlock-keychain -p password build.keychain
# Trust the certificate (for macOS 10.15+) -> sudo might not work. Can also be run as a user (without sudo)
# sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" "$MITM_CERT_PATH"

echo "[✓] Proxy setup complete. You can now use mitmproxy to intercept iOS simulator traffic."
