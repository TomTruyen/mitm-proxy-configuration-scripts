# 🕵️ mitmproxy Emulator & Simulator Integration

This repository contains helper scripts and a `mitmproxy` addon to easily intercept HTTP(S) traffic from Android emulators and iOS simulators using `mitmproxy`. It also provides control endpoints to start/stop recording and dynamically map local responses to specific request URLs.

---

## 📦 Requirements

- `mitmproxy` (v9+ recommended)
- Android Emulator with **root access**
- iOS Simulator (via Xcode)
- macOS or Linux

---

## 🔧 Installation

### macOS

```bash
brew install mitmproxy
```

### Linux (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install mitmproxy
```

Verify installation:

```bash
mitmdump --version
```

---

## 📱 Android Emulator Setup

### ⚠️ Requirements:
- Emulator must be rooted (use x86 or ARM images that support root).
- Android SDK + ADB installed and configured in your `$PATH`.

### 🛠️ Setup Steps:

1. Run the script:

```bash
chmod +x android-certificate-install.sh
./android-certificate-install.sh
```

This script will:
- Ensure the mitmproxy CA certificate exists
- Push the certificate to the emulator’s system certificate store
- Configure proxy settings to forward traffic to mitmproxy on host (`10.0.2.2:8080`)
- Reboot the emulator to apply changes

---

## 🍏 iOS Simulator Setup

### ⚠️ Requirements:
- `xcode-select` must point to an installed Xcode
- You **may** need to manually trust the certificate in:
  `Settings > General > About > Certificate Trust Settings`

If `simctl` fails:
```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 🛠️ Setup Steps:

```bash
chmod +x ios-certificate-install.sh
./ios-certificate-install.sh
```

This will:
- Boot or select a running iOS simulator
- Install mitmproxy CA certificate into the simulator keychain
- Set system proxy on macOS interfaces (used by the simulator)
- Prompt you to manually trust the certificate if needed

### (Optional) macOS System Trust:

If you want your entire macOS system to trust mitmproxy (for capturing CLI tools or other apps):

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain mitmproxy-ca-cert.crt
```

---

## 🧩 mitmproxy Addon – Session Controller

The file `proxy-session-controller.py` is a mitmproxy addon that:

- Records flows while a session is active
- Allows you to **start/stop recording** via HTTP API
- Lets you map specific URLs to local mock response files

### 🚀 Usage

Start mitmproxy with the addon:

```bash
mitmdump -p 8080 -s proxy-session-controller.py
```

This starts mitmproxy with:

- Listening port: `8080`
- Control API: `http://localhost:9999`

---

## 🛠️ Control API Endpoints

These endpoints allow dynamic control of recording and local response mapping.

### ▶️ Start Recording

```bash
curl http://localhost:9999/start_recording
```

### ⏹️ Stop Recording and Save

```bash
curl http://localhost:9999/stop_recording
```

This saves all recorded flows to `flows.json`.

### 🔁 Enable Local Mapping for a URL

```bash
curl -X POST http://localhost:9999/map_local/enable \
  -H "Content-Type: application/json" \
  -d '{"url": "https://api.example.com/data", "file_path": "/absolute/path/to/response.json"}'
```

Any requests matching the URL will return the contents of `response.json`.

### 🚫 Disable Mapping for a URL

```bash
curl -X POST http://localhost:9999/map_local/disable \
  -H "Content-Type: application/json" \
  -d '{"url": "https://api.example.com/data"}'
```

### 🔄 Clear All Mappings

```bash
curl -X POST http://localhost:9999/map_local/disable
```

---

## 📎 Notes & Edge Cases

- For Android: Emulator **must be rooted** to modify `/system/etc/security/cacerts`
- For iOS:
  - `simctl keychain` may not work on all Xcode versions. If it fails, the certificate will be opened manually for trust.
  - You may need to **manually trust** the cert in the iOS Simulator settings
- For macOS:
  - You can manually install the CA cert into the system keychain to capture macOS traffic too
- The local mapping only works if the URL matches **exactly**, including protocol and query params.

---

## 📂 Output Example: `flows.json`

Each captured flow includes the method, URL, headers, and parsed JSON request/response body if possible.

```json
[
  {
    "request": {
      "method": "GET",
      "url": "https://api.example.com/data",
      "headers": { ... },
      "body": {}
    },
    "response": {
      "status_code": 200,
      "headers": { ... },
      "body": { "result": "ok" }
    }
  }
]
```

---

## 🙌 Contributions

Feel free to extend this tool with more proxy automation, better cert handling, or a simple UI for the control endpoints.

---

## 🧼 Cleanup

To reset Android emulator proxy:

```bash
adb shell settings put global http_proxy :0
```

To reset macOS proxy:

```bash
networksetup -listallnetworkservices | tail +2 | while read -r interface; do
  networksetup -setwebproxystate "$interface" off
  networksetup -setsecurewebproxystate "$interface" off
done
```
