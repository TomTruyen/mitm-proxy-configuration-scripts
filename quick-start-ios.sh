#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Configuration ----
SIMULATOR_NAME="Proxy Simulator"
DEVICE_TYPE="iPhone 17"
RUNTIME="iOS26.4"
# ------------------------

echo "[!] WARNING: This script has not been fully tested and may require minor modifications to work on your machine."
echo ""
echo "[*] Quick Start: iOS Proxy Setup"
echo "============================================"

# Check if the proxy simulator is already booted
SIMULATOR_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIMULATOR_NAME" | grep -E 'Booted' | head -1 | awk -F '[()]' '{print $2}')

if [ -z "$SIMULATOR_UDID" ]; then
    echo "[*] No booted '$SIMULATOR_NAME' detected. Setting up..."

    # Check if the simulator already exists (in any state)
    EXISTING_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIMULATOR_NAME" | head -1 | awk -F '[()]' '{print $2}')

    if [ -z "$EXISTING_UDID" ]; then
        # Resolve the full runtime identifier (e.g. iOS18.4 -> com.apple.CoreSimulator.SimRuntime.iOS-18-4)
        RUNTIME_ID=$(xcrun simctl list runtimes 2>/dev/null | grep "$RUNTIME" | head -1 | awk '{print $NF}')
        if [ -z "$RUNTIME_ID" ]; then
            echo "[x] Runtime '$RUNTIME' not found. Available runtimes:"
            xcrun simctl list runtimes
            exit 1
        fi

        # Resolve the device type identifier (e.g. iPhone 16 -> com.apple.CoreSimulator.SimDeviceType.iPhone-16)
        DEVICE_TYPE_ID=$(xcrun simctl list devicetypes 2>/dev/null | grep "$DEVICE_TYPE" | head -1 | awk -F '[()]' '{print $2}')
        if [ -z "$DEVICE_TYPE_ID" ]; then
            echo "[x] Device type '$DEVICE_TYPE' not found. Available device types:"
            xcrun simctl list devicetypes
            exit 1
        fi

        echo "[*] Creating simulator: '$SIMULATOR_NAME' ($DEVICE_TYPE, $RUNTIME)"
        EXISTING_UDID=$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
        echo "[✓] Created simulator: $EXISTING_UDID"
    fi

    # Boot the simulator
    echo "[*] Booting simulator '$SIMULATOR_NAME'..."
    xcrun simctl boot "$EXISTING_UDID" 2>/dev/null || true
    open -a Simulator

    # Wait for it to be fully booted
    echo "[*] Waiting for simulator to boot..."
    while [ "$(xcrun simctl list devices 2>/dev/null | grep "$EXISTING_UDID" | grep -c 'Booted')" -eq 0 ]; do
        sleep 2
    done
    echo "[✓] Simulator booted"

    SIMULATOR_UDID="$EXISTING_UDID"
else
    echo "[✓] Simulator already running: $SIMULATOR_UDID"
fi

# Start mitmproxy in the background
echo "[*] Starting mitmproxy..."
mitmdump -p 8080 -s "$SCRIPT_DIR/session-recording-controller.py" --ssl-insecure &
MITM_PID=$!
sleep 2

# Verify mitmproxy started
if ! kill -0 "$MITM_PID" 2>/dev/null; then
    echo "[x] mitmproxy failed to start. Is port 8080 already in use?"
    exit 1
fi
echo "[✓] mitmproxy running (PID: $MITM_PID)"

# Install certs and configure proxy on simulator
echo "[*] Installing certificates and configuring proxy on simulator..."
bash "$SCRIPT_DIR/ios-cert-install.sh"

echo ""
echo "============================================"
echo "[✓] iOS proxy setup complete!"
echo "    Simulator:      $SIMULATOR_NAME ($SIMULATOR_UDID)"
echo "    mitmproxy PID:  $MITM_PID"
echo "    Control server: http://localhost:9999"
echo ""
echo "    To stop: kill $MITM_PID"
echo "    (!) Remember to reset your Mac network proxy settings after use."
echo "============================================"
