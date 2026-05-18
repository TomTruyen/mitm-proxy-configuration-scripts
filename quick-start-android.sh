#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Configuration ----
AVD_NAME="proxy-emulator"
API_LEVEL=36
ABI="arm64-v8a"             # For Apple Silicon (M1/M2/M3/M4)
# ABI="x86_64"              # For Intel-based machines or CI/CD (e.g. Bitrise Linux)
SYSTEM_IMAGE="system-images;android-${API_LEVEL};google_apis;${ABI}"
DEVICE_PROFILE="pixel_7_pro"
# ------------------------

echo "[!] WARNING: This script has not been fully tested and may require minor modifications to work on your machine."
echo ""
echo "[*] Quick Start: Android Proxy Setup"
echo "============================================"

# Check if the emulator is already running
EMULATOR=$(adb devices 2>/dev/null | awk '/^emulator-.*device$/{print $1; exit}')

if [ -z "$EMULATOR" ]; then
    echo "[*] No running emulator detected. Setting up '$AVD_NAME'..."

    # Install the system image if not present
    if ! sdkmanager --list_installed 2>/dev/null | grep -q "$SYSTEM_IMAGE"; then
        echo "[*] Installing system image: $SYSTEM_IMAGE"
        sdkmanager "$SYSTEM_IMAGE"
    fi

    # Create the AVD if it doesn't exist
    if ! avdmanager list avd -c 2>/dev/null | grep -q "^${AVD_NAME}$"; then
        echo "[*] Creating AVD: $AVD_NAME (API $API_LEVEL, $ABI, $DEVICE_PROFILE)"
        echo "no" | avdmanager create avd \
            --name "$AVD_NAME" \
            --package "$SYSTEM_IMAGE" \
            --device "$DEVICE_PROFILE" \
            --force
        
        # Enable hardware keyboard
        AVD_CONFIG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
        if [ -f "$AVD_CONFIG" ]; then
            echo "[*] Enabling hardware keyboard in $AVD_CONFIG"
            sed -i '' 's/hw.keyboard=no/hw.keyboard=yes/' "$AVD_CONFIG" || sed -i 's/hw.keyboard=no/hw.keyboard=yes/' "$AVD_CONFIG"
        fi
    fi

    # Launch the emulator
    echo "[*] Launching emulator '$AVD_NAME'..."
    emulator -avd "$AVD_NAME" -writable-system -no-snapshot-save -no-audio -gpu auto &
    EMULATOR_PID=$!

    echo "[*] Waiting for emulator to boot..."
    adb wait-for-device
    # Wait until the boot animation has finished
    while [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 2
    done
    echo "[✓] Emulator booted"

    EMULATOR=$(adb devices 2>/dev/null | awk '/^emulator-.*device$/{print $1; exit}')
else
    echo "[✓] Emulator already running: $EMULATOR"
fi

# Start mitmproxy in the background
echo "[*] Starting mitmproxy..."
# Ensure port 8080 is clear
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
mitmdump -p 8080 -s "$SCRIPT_DIR/session-recording-controller.py" --ssl-insecure &
MITM_PID=$!
sleep 2

# Verify mitmproxy started
if ! kill -0 "$MITM_PID" 2>/dev/null; then
    echo "[x] mitmproxy failed to start. Is port 8080 already in use?"
    exit 1
fi
echo "[✓] mitmproxy running (PID: $MITM_PID)"

# Install certs and configure proxy on emulator
echo "[*] Installing certificates and configuring proxy on emulator..."
bash "$SCRIPT_DIR/android-cert-install.sh"

echo ""
echo "============================================"
echo "[✓] Android proxy setup complete!"
echo "    Emulator:       $EMULATOR"
echo "    mitmproxy PID:  $MITM_PID"
echo "    Control server: http://localhost:9999"
echo ""
echo "    To stop: kill $MITM_PID"
echo "============================================"
