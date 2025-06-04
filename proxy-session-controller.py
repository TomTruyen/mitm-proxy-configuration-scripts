import os
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from mitmproxy import ctx, http
import json
from urllib.parse import urlparse, parse_qs

# On Startup the Emulator/Simulator performs a lot of API calls to get the system ready. This causes in a lot of noise on the Network
# Here we list endpoints that we don't want to "capture" since they are not important for us. Doing so reduces the Noise in our Network Logs
IGNORED_ENDPOINTS = [
    # Android
    "gstatic.com",       # Google Fonts / Static resources
    "tenor.com",         # GIFs for keyboard input, Gboard
    "googleapis.com",    # System and Play Services API calls
    "mtalk.google.com",  # GCM/FCM (push notification service)
    "clients4.google.com", # Google update/checkin service
    "clients2.google.com", # Similar service to above
    "android.clients.google.com", # Device check-in, sync
    "connectivitycheck.gstatic.com", # Network status check
    "update.googleapis.com", # App / Play Store update checks
    "csi.gstatic.com",       # Google connection status indicator
    "play.googleapis.com",   # Google Play API

    # iOS
    "apple.com",          # General Apple services
    "icloud.com",         # iCloud sync / backup
    "itunes.apple.com",   # App Store or media previews
    "mzstatic.com",       # Apple media content/CDNs
    "push.apple.com",     # APNs (Push notification service)
    "configuration.apple.com", # iOS config services
    "init.ess.apple.com", # Device activation or health check
    "crashlytics.com",    # Crash reporting (often auto-integrated)
]

def _is_ignored(flow: http.HTTPFlow) -> bool:
    """
    Return True when the request host is in the IGNORED_ENDPOINTS
    This will be used to avoid endpoints that we don't care for that spam on initial boot
    """
    host = urlparse(flow.request.pretty_url).netloc.lower()
    return any(ignored in host for ignored in IGNORED_ENDPOINTS)

def log_safe(message):
    if threading.current_thread() is threading.main_thread():
        # can only be called from main thread, so if we call this in subthread it crashes
        # locally this gave no issues, but on CI/CD where I forced mitmproxy in background it caused failures
        log_safe(message)
    else:
        print(message)

def try_parse_json(content):
    try:
        return json.loads(content)
    except Exception:
        return content

class Recorder:
    def __init__(self):
        self.recording = False
        self.flows = []
        self.output_filename = "flows.json"

    def request(self, flow: http.HTTPFlow):
        if self.recording and not _is_ignored(flow):
            url = flow.request.pretty_url
            log_safe(f"Request URL: {url}")
            if url in ControlServer.map_local:
                log_safe(f"Mapping local file to URL: {ControlServer.map_local.get(url, 'No mapping found')}")
                file_path = ControlServer.map_local[url]
                try:
                    with open(file_path, 'rb') as f:
                        flow.response = http.Response.make(
                            200, 
                            f.read(),  
                            {"Content-Type": "application/json"}
                        )
                except FileNotFoundError:
                    ctx.log.error(f"File not found for URL {url}: {file_path}")

    def response(self, flow: http.HTTPFlow):
        if self.recording and not _is_ignored(flow):
            self.flows.append(flow) # Store the flow to later on save as JSON
            
    def save_flows_as_json(self):
        log_safe(f"Saving {len(self.flows)} flows to {self.output_filename}")

        dir_path = os.path.dirname(self.output_filename)
        if dir_path:
            os.makedirs(dir_path, exist_ok=True)
        
        data = []
        for flow in self.flows:
            if flow.response:
                req_body = flow.request.get_text()
                res_body = flow.response.get_text()

                request_content = try_parse_json(req_body, flow.request.headers)
                response_content = try_parse_json(res_body, flow.response.headers)

                data.append({
                    "request": {
                        "method": flow.request.method,
                        "url": flow.request.pretty_url,
                        "headers": dict(flow.request.headers),
                        "body": request_content
                    },
                    "response": {
                        "status_code": flow.response.status_code,
                        "headers": dict(flow.response.headers),
                        "body": response_content
                    }
                })
        with open(self.output_filename, "w") as f:
            json.dump(data, f, indent=2)

class ControlServer(BaseHTTPRequestHandler):
    recorder = None  # class variable
    map_local = {}  # class variable for local mapping

    def read_body(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        return json.loads(body)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/start_recording":
            payload = self.read_body()

            ControlServer.recorder.recording = True
            ControlServer.recorder.flows = []

            name = payload.get("name") or "flows"
            ControlServer.recorder.output_filename = f"{name}.json"

            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"Recording started as {name}.json".encode())
        elif path == "/stop_recording":
            ControlServer.recorder.recording = False
            ControlServer.recorder.save_flows_as_json()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Recording stopped and saved")
        elif path == "/map_local/enable":
            url = data.get("url")
            file_path = data.get("file_path")
            if url and file_path:
                ControlServer.map_local[url] = file_path
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Mapping added")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Missing 'url' or 'file_path'")
        elif path == "/map_local/disable":
            url = data.get("url")
            if url in ControlServer.map_local:
                del ControlServer.map_local[url]
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Mapping removed")
            else:
                # Clear all mappings if no URL is provided
                ControlServer.map_local.clear()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"All mappings cleared")
        else:
            self.send_response(404)
            self.end_headers()

class RecorderAddon:
    def __init__(self):
        self.recorder = Recorder()
        self.map_local = {}

    def load(self, loader):
        ControlServer.recorder = self.recorder
        log_safe("Starting control server on http://localhost:9999")
        threading.Thread(target=self.run_http_server, daemon=True).start()

    def run_http_server(self):
        server = HTTPServer(('localhost', 9999), ControlServer)
        server.serve_forever()

    def request(self, flow):
        self.recorder.request(flow)

    def response(self, flow):
        self.recorder.response(flow)

addons = [
    RecorderAddon()
]

