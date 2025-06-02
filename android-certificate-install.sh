#!/bin/bash

set -e

MITM_PORT=8080
MITM_CERT_PATH="$HOME/.mitmproxy"
HOST_IP="10.0.2.2"  # This is how emulators access the host

echo "[*] Starting Android emulator mitmproxy setup..."

# Ensure mitmproxy CA cert exists
if [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.cer ]; then
    echo "[*] Generating mitmproxy CA certificate..."
    mitmdump --set block_global=false --mode=transparent --listen-port=0 --quiet &
    sleep 2
    pkill -f mitmdump
fi

# CA Certificates in Android are stored by the name of their hash, with a ‘0’ as extension (Example: c8450d0d.0)
HASHED_CERT_NAME=$(openssl x509 -inform PEM -subject_hash_old -in "$MITM_CERT_PATH/mitmproxy-ca-cert.cer" | head -1)
MITM_CERT_FINAL_NAME="$HASHED_CERT_NAME.0"
MITM_CERT_FINAL_PATH="$MITM_CERT_PATH/$MITM_CERT_FINAL_NAME"
cp "$MITM_CERT_PATH/mitmproxy-ca-cert.cer" "$MITM_CERT_FINAL_PATH"

# Set up emulator proxy
echo "[*] Setting proxy on emulator..."
adb emu network delay none
adb emu network speed full
adb shell settings put global http_proxy "$HOST_IP:$MITM_PORT"

# Install cert into system cert store
echo "[*] Installing CA cert in emulator system store..."
echo "[*] Disabling Verification..."
adb root
adb shell avbctl disable-verification
adb reboot
adb wait-for-device

echo "[*] Pushing certificate..."
adb root
adb remount
adb push "$MITM_CERT_FINAL_PATH" /system/etc/security/cacerts
adb shell chmod 644 /system/etc/security/cacerts/$MITM_CERT_FINAL_NAME

echo "[*] Rebooting emulator to apply certificate..."
adb reboot
adb wait-for-device

echo "[✓] Android emulator is now routed through mitmproxy with trusted CA."
