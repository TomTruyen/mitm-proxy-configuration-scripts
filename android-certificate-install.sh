#!/bin/bash

# NOTE: Must use an emulator that has Root Access (x86 or ARM images with root)

set -e

MITM_PORT=8080
MITM_CERT_NAME="mitmproxy-ca-cert.crt"
MITM_CERT_PATH="./$MITM_CERT_NAME"
HOST_IP="10.0.2.2"  # This is how emulators access the host

echo "[*] Starting Android emulator mitmproxy setup..."

# Ensure mitmproxy CA cert exists
if [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    echo "[*] Generating mitmproxy CA certificate..."
    mitmdump --set block_global=false --mode=transparent --listen-port=0 --quiet &
    sleep 2
    pkill -f mitmdump
fi

# Copy cert to working directory
cp ~/.mitmproxy/mitmproxy-ca-cert.pem "$MITM_CERT_PATH"

# Set up emulator proxy
echo "[*] Setting proxy on emulator..."
adb emu network delay none
adb emu network speed full
adb shell settings put global http_proxy "$HOST_IP:$MITM_PORT"

# Install cert into system cert store
echo "[*] Installing CA cert in emulator system store..."
adb root
adb remount
adb push "$MITM_CERT_PATH" /system/etc/security/cacerts/
adb shell chmod 644 /system/etc/security/cacerts/$MITM_CERT_NAME

echo "[*] Rebooting emulator to apply certificate..."
adb reboot

adb wait-for-device

echo "[✓] Android emulator is now routed through mitmproxy with trusted CA."
