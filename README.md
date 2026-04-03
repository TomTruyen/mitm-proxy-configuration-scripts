# mitmproxy Emulator & Simulator Integration

This repository contains helper scripts and a `mitmproxy` addon to easily intercept HTTP(S) traffic from Android emulators and iOS simulators using `mitmproxy`. It also provides control endpoints to start/stop recording and dynamically map local responses to specific request URLs.

---

## Requirements

- `mitmproxy` (v12+ recommended)
- Android Emulator with **root access**
- iOS Simulator (via Xcode)
- macOS or Linux

---

## Installation

### macOS

```bash
brew install mitmproxy
```

### Linux (Debian/Ubuntu)

```bash
# The apt version is extremely outdated, use pipx instead:
pipx install mitmproxy
```

Verify installation:

```bash
mitmdump --version
```

---

## Quick Start (Local Development)

Two convenience scripts are provided to quickly set up a local proxy environment. They will create a dedicated emulator/simulator if one isn't running, start mitmproxy, and install certificates automatically.

> **Warning:** These scripts have not been fully tested and may require minor modifications to work on your machine.

### Android

```bash
./quick-start-android.sh
```

This script will:
- Check for a running emulator, or create and launch one named `proxy-emulator` (API 36, Pixel 7 Pro)
- Start mitmproxy with the session-recording-controller addon
- Install certificates and configure proxy settings via `android-cert-install.sh`

Configuration (editable at the top of the script):

| Variable         | Default          | Description                          |
|------------------|------------------|--------------------------------------|
| `AVD_NAME`       | `proxy-emulator` | Name of the AVD to create/reuse      |
| `API_LEVEL`      | `36`             | Android API level                    |
| `ABI`            | `arm64-v8a`      | Architecture (`x86_64` for Intel/CI) |
| `DEVICE_PROFILE` | `pixel_7_pro`    | Hardware profile                     |

### iOS

```bash
./quick-start-ios.sh
```

This script will:
- Check for a booted simulator, or create and launch one named `Proxy Simulator` (iPhone 17, iOS 26.4)
- Start mitmproxy with the session-recording-controller addon
- Install certificates and configure proxy settings via `ios-cert-install.sh`

Configuration (editable at the top of the script):

| Variable         | Default           | Description            |
|------------------|-------------------|------------------------|
| `SIMULATOR_NAME` | `Proxy Simulator` | Name of the simulator  |
| `DEVICE_TYPE`    | `iPhone 17`       | Simulator device model |
| `RUNTIME`        | `iOS26.4`         | iOS runtime version    |

---

## Android Emulator Setup (Manual)

### Requirements:
- Emulator must be rooted (use images that support root, typically those WITHOUT Google Play Services).
- Emulator must be started using `-writable-system` flag to be able to perform an `adb remount`
- Android SDK + ADB installed and configured in your `$PATH`.

### Setup Steps:

1. Launch emulator with writable system

```bash
# Find name of AVD
emulator -list-avds

emulator -avd <name of avd> -writable-system
```

2. Run the script:

```bash
chmod +x android-cert-install.sh
./android-cert-install.sh
```

This script will:
- Ensure the mitmproxy CA certificate exists as `~/.mitmproxy/mitmproxy-ca-cert.cer`
- Push the certificate to the emulator's system certificate store (using the correct method for Android version)
- Configure proxy settings to forward traffic to mitmproxy on host (`10.0.2.2:8080`)
- Reboot the emulator to apply changes

---

## iOS Simulator Setup (Manual)

### Requirements:
- `xcode-select` must point to an installed Xcode
- You **may** need to manually trust the certificate in:
  `Settings > General > About > Certificate Trust Settings`

If `simctl` fails:
```bash
sudo xcode-select -s /Applications/Xcode.app
```

### Setup Steps:

```bash
chmod +x ios-cert-install.sh
./ios-cert-install.sh
```

This will:
- Boot or select a running iOS simulator
- Install mitmproxy CA certificate (`mitmproxy-ca-cert.pem` copied as `mitmproxy-ca-cert.crt`) into the simulator keychain
- Set system proxy on the `Ethernet` interface (used by the simulator)
- Exit with an error if automatic install fails (no manual fallback)

### (Optional) macOS System Trust:

If you want your entire macOS system to trust mitmproxy (for capturing CLI tools or other apps):

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain mitmproxy-ca-cert.crt
```

---

## mitmproxy Addon - Session Controller

The file `session-recording-controller.py` is a mitmproxy addon that:

- Records flows while a session is active
- Allows you to **start/stop recording** via HTTP API
- Lets you map specific URLs to local mock response files (supports regex patterns)
- Supports a `$defs`/`$ref` system for reusable URL mappings loaded from `map_local_mapping.json`

### Usage

Start mitmproxy with the addon:

```bash
mitmdump -p 8080 -s session-recording-controller.py --ssl-insecure
```

This starts mitmproxy with:

- Listening port: `8080`
- Control API: `http://localhost:9999`

Running mitmproxy in background with the addon:

```bash
screen -dm mitmdump -p 8080 -s session-recording-controller.py --ssl-insecure
```

**About `screen`:**

The `screen` command is a terminal multiplexer that lets you run multiple sessions within a single terminal window. By starting `mitmdump` in a detached `screen` session, you can keep it running in the background while continuing to use your terminal for other tasks.

This approach is especially useful in CI/CD environments, where you don't want a pipeline step to hang because `mitmdump` is occupying the terminal interactively.

You can re-attach to the running session at any time using:

```bash
screen -r
```

To verify if `mitmdump` is running:

```bash
pgrep mitmdump
```

---

## About IGNORED_ENDPOINTS

When using mitmproxy with emulators and simulators, a lot of background network traffic is generated by the operating system and system apps (such as Google or Apple services). Most of this traffic is not relevant for app testing or debugging and can clutter your logs.

The `IGNORED_ENDPOINTS` list in `session-recording-controller.py` contains hostnames for common Android and iOS system services that are automatically filtered out. Requests to these endpoints are not recorded or included in your output files.

**Examples of ignored endpoints:**
- Android: `gstatic.com`, `googleapis.com`, `clients4.google.com`, `play.googleapis.com`, etc.
- iOS: `apple.com`, `icloud.com`, `itunes.apple.com`, `push.apple.com`, etc.

**Why is this useful?**
- Reduces noise in your captured network logs.
- Makes it easier to focus on your app's actual API calls.
- Prevents large, irrelevant log files from being generated.

If you want to capture all traffic, you can remove or modify the `IGNORED_ENDPOINTS` list in the script.

---

## Control API Endpoints

These endpoints allow dynamic control of recording and local response mapping.

### Start Recording

```bash
# Default recording, outputs to flows.json
curl -X POST http://localhost:9999/start_recording \
  -H "Content-Type: application/json" \
  -d '{}'

# With a custom name, outputs to "output_file_name".json
curl -X POST http://localhost:9999/start_recording \
  -H "Content-Type: application/json" \
  -d '{"name": "output_file_name"}'
```

### Stop Recording and Save

```bash
curl -X POST http://localhost:9999/stop_recording
```

This saves all recorded flows to the file specified when starting the recording (e.g., `output_file_name.json`), or to `flows.json` if no name was provided.

### Load Map Local Entries for a Test

```bash
curl -X POST http://localhost:9999/map_local/load \
  -H "Content-Type: application/json" \
  -d '{"testName": "test_GIVEN_a_Xandr_ad_..."}'
```

Loads all mapping entries for the given test name from `map_local_mapping.json`, resolving any `$ref` references against `$defs`. This replaces all current mappings.

### Enable a Single Local Mapping

```bash
curl -X POST http://localhost:9999/map_local/enable \
  -H "Content-Type: application/json" \
  -d '{"url": "https://api.example.com/data", "file_path": "/absolute/path/to/response.json"}'
```

Any requests matching the URL (supports regex) will return the contents of `response.json`.

### Disable Mapping for a URL

```bash
curl -X POST http://localhost:9999/map_local/disable \
  -H "Content-Type: application/json" \
  -d '{"url": "https://api.example.com/data"}'
```

### Clear All Mappings

```bash
curl -X POST http://localhost:9999/map_local/disable \
  -H "Content-Type: application/json" \
  -d '{}'
```

---

## Map Local Mapping Format (`map_local_mapping.json`)

The mapping file uses a `$defs`/`$ref` system to avoid repeating URLs and headers across test entries.

### File Structure

```json
{
  "$defs": {
    "xandr": {
      "url": "https:\\/\\/(mediation|ib)\\.adnxs\\.com\\/ut\\/v3",
      "headers": "headers/xandr.json"
    },
    "track_vevent": {
      "url": "https:\\/\\/[a-zA-Z0-9]+-ib\\.adnxs(-simple)?\\.com\\/vevent",
      "status": 200
    }
  },
  "mappings": {
    "<testName>": [
      { "$ref": "xandr", "body": "response/xandr/some_response.json" },
      { "$ref": "track_vevent" }
    ]
  }
}
```

- `$defs`: Reusable definitions. Each key is a name that can be referenced by `$ref` in mapping entries.
- `mappings`: The test-to-mappings dictionary. Each key is a test name matching the `testName` passed to `/map_local/load`.

### Entry Fields

- `$ref (optional)`: References a definition from `$defs`. The referenced object is used as a base, and any additional properties in the entry override matching keys from the def.
- `url`: The URL pattern that will be intercepted (supports regex).
- `headers (optional)`: The path to the response headers file that will be returned. Default: None
- `body (optional)`: The path to the response body file that will be returned. Default: None
- `status (optional)`: The HTTP status code to return. Default: 200

### How `$ref` Overrides Work

When an entry uses `$ref`, the referenced def is merged with the entry's local properties.
Local properties always take precedence over properties from the def. For example:

```json
// $defs
"xandr": {
  "url": "https:\\/\\/(mediation|ib)\\.adnxs\\.com\\/ut\\/v3",
  "headers": "headers/xandr.json"
}

// Mapping entry
{ "$ref": "xandr", "url": "https://custom-url.com", "body": "response/foo.json" }

// Resolves to
{
  "url": "https://custom-url.com",
  "headers": "headers/xandr.json",
  "body": "response/foo.json"
}
```

In this example, `url` from the entry overrides the `url` from the `xandr` def, while `headers` is still inherited.

### Adding a New Response Body

To add a new response body, you can create a new JSON file and reference it in the `map_local_mapping.json` file.
You can obtain the response body by running the test locally and intercepting the traffic using: Charles, mitmproxy or
Android Studio App Inspection.

---

## Output Example: `flows.json`

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

## Use Cases

### Automated Network Testing for Android & iOS

You can integrate `mitmproxy` recording into your mobile test lifecycle to verify network behavior during test execution.

### Example Flow:

1. **Start mitmproxy with the addon** (before your test suite):

```bash
mitmdump -p 8080 -s session-recording-controller.py --ssl-insecure
```

2. **Load map local entries for the test** (before your test begins):

```bash
curl -X POST http://localhost:9999/map_local/load \
  -H "Content-Type: application/json" \
  -d '{"testName": "test_GIVEN_a_Xandr_ad_..."}'
```

3. **Start recording flows**:

```bash
curl -X POST http://localhost:9999/start_recording \
  -H "Content-Type: application/json" \
  -d '{"name": "test_output"}'
```

4. **Run your UI/E2E test** that performs network requests from the Android emulator or iOS simulator.

5. **Stop recording after the test is finished**:

```bash
curl -X POST http://localhost:9999/stop_recording
```

6. **Validate the output** in `test_output.json` using a custom validation script.

---

### Example: Test Validation Script (Python)

```python
import json

with open("test_output.json") as f:
    flows = json.load(f)

expected_url = "https://api.example.com/data"
matched = any(flow["request"]["url"] == expected_url for flow in flows)

assert matched, f"Expected request to {expected_url} not found!"
print("[OK] Network request verified.")
```

---

### Use With Your Test Framework

In your test framework (e.g., XCTest for iOS, Espresso or UIAutomator for Android), you can:

- Trigger `/map_local/load` and `/start_recording` in the test setup phase
- Run the UI interaction
- Trigger `/stop_recording` in the test teardown
- Run a validation script after the test completes

This allows you to **assert that expected network calls were made**, validate request payloads, and check response data without needing to modify your app code.

---

## Cleanup

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

---

## Contributions

Feel free to extend this tool with more proxy automation, better cert handling, or a simple UI for the control endpoints.
