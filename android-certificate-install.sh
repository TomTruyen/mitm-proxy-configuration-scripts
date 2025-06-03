#!/bin/bash

set -e

MITM_PORT=8080
MITM_CERT_PATH="$HOME/.mitmproxy"
HOST_IP="10.0.2.2"  # This is how emulators access the host


# Ensure mitmproxy CA cert exists - Launching mitm will generate upon launch
if [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.cer ]; then
    echo "[*] Generating mitmproxy CA certificate..."
    mitmdump --set block_global=false --mode=transparent --listen-port=0 --quiet &
    sleep 2
    pkill -f mitmdump
fi

# Check if Emulator booted, if not just stop the script.
echo "[*] Looking for Android emulator mitmproxy setup..."
BOOTED=$(adb devices | awk '/^emulator-.*device$/{print $1; exit}')
if [ -z "$BOOTED" ]; then
    echo "[x] No Android emulator/device booted. Please start an emulator try again..."
    exit 1
fi

echo "[✓] Using emulator: $BOOTED"

echo "[*] Installing CA root certificate on $BOOTED..."

# CA Certificates in Android are stored by the name of their hash, with a ‘0’ as extension (Example: c8450d0d.0)
HASHED_CERT_NAME=$(openssl x509 -inform PEM -subject_hash_old -in "$MITM_CERT_PATH/mitmproxy-ca-cert.cer" | head -1)
MITM_CERT_FINAL_NAME="$HASHED_CERT_NAME.0"
MITM_CERT_FINAL_PATH="$MITM_CERT_PATH/$MITM_CERT_FINAL_NAME"
cp "$MITM_CERT_PATH/mitmproxy-ca-cert.cer" "$MITM_CERT_FINAL_PATH"

# Verification needs to be disabled for some specific cases
echo "[*] Disabling Verification..."
adb root
adb shell avbctl disable-verification
adb reboot
adb wait-for-device

# Install the CA Root Certificate on the Device in the System "Trusted Certificates"
ANDROID_API_LEVEL=$(adb -s "$BOOTED" shell getprop ro.build.version.sdk | tr -d '\r')
if [ "$ANDROID_API_LEVEL" -ge 34 ]; then
    # https://www.g1a55er.net/Android-14-Still-Allows-Modification-of-System-Certificates
    echo "[*] Detected Android 14+ (API $ANDROID_API_LEVEL) – using Conscrypt APEX method"

    echo "[*] Rewriting mount namespaces for system certificates..."
    adb root
    adb shell setenforce 0
    adb shell mount -o remount,exec /apex
    adb shell cp -r -p /apex/com.android.conscrypt /apex/com.android.conscrypt-bak
    adb shell umount -l /apex/com.android.conscrypt
    adb shell rm -rf /apex/com.android.conscrypt
    adb shell mv /apex/com.android.conscrypt-bak /apex/com.android.conscrypt
    adb shell killall system_server
    echo "[✓] APEX system namespaces rewritten"

    echo "[*] Pushing certificate..."
    adb push "$MITM_CERT_FINAL_PATH" /apex/com.android.conscrypt/cacerts
    adb shell chmod 644 /apex/com.android.conscrypt/cacerts/$MITM_CERT_FINAL_NAME
    echo "[✓] Certificate pushed"
else
    echo "[*] Detected Android <= 13 (API $ANDROID_API_LEVEL) – using classic /system method"
    # (Android 13 and below method)
    echo "[*] Remounting system..."
    adb root
    adb remount
    echo "[✓] System remounted"

    echo "[*] Pushing certificate..."
    adb push "$MITM_CERT_FINAL_PATH" /system/etc/security/cacerts
    adb shell chmod 644 /system/etc/security/cacerts/$MITM_CERT_FINAL_NAME
    adb shell restorecon -v /system/etc/security/cacerts/$MITM_CERT_FINAL_NAME
    echo "[✓] Certificate pushed"

    echo "[*] Rebooting emulator to apply certificate..."
    adb reboot
    adb wait-for-device
fi

echo "[*] Waiting for 10s to ensure Wi-Fi is ready..."
sleep 10

# Resetting Wifi (Toggle of and on) -> This ensure that WiFi is used instead of Mobile Data
echo "[*] Resetting emulator Wi-Fi..."
adb shell svc wifi disable
sleep 1
adb shell svc wifi enable
sleep 2
echo "[✓] Wi-Fi has been reset..."

# Configure the Proxy settings ifor the Wi-Fi
echo "[*] Setting proxy on emulator..."
adb emu network delay none
adb emu network speed full
adb shell settings put global http_proxy "$HOST_IP:$MITM_PORT"
echo "[✓] Proxy setup complete"

echo "[✓] Android emulator is now routed through mitmproxy with trusted CA."
