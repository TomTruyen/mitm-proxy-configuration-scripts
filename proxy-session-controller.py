import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from mitmproxy import ctx, http
import json

class Recorder:
    def __init__(self):
        self.recording = False
        self.flows = []

    def request(self, flow: http.HTTPFlow):
        if self.recording:
            url = flow.request.pretty_url
            ctx.log.info(f"Request URL: {url}")
            if url in ControlServer.map_local:
                ctx.log.info(f"Mapping local file to URL: {ControlServer.map_local.get(url, 'No mapping found')}")
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
        if self.recording:
            self.flows.append(flow) # Store the flow to later on save as JSON

    def try_parse_json(self, content, headers):
        content_type = headers.get("content-type", "")
        if "application/json" in content_type.lower():
            try:
                return json.loads(content)
            except json.JSONDecodeError:
                return content  # fall back to raw if invalid JSON
        return content

    def save_flows_as_json(self, path="flows.json"):
        ctx.log.info(f"Saving {len(self.flows)} flows to {path}")
        data = []
        for flow in self.flows:
            if flow.response:
                req_body = flow.request.get_text()
                res_body = flow.response.get_text()

                request_content = self.try_parse_json(req_body, flow.request.headers)
                response_content = self.try_parse_json(res_body, flow.response.headers)

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
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

class ControlServer(BaseHTTPRequestHandler):
    recorder = None  # class variable
    map_local = {}  # class variable for local mapping

    def do_GET(self):
        if self.path == "/start_recording":
            ControlServer.recorder.recording = True
            ControlServer.recorder.flows = []
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Recording started")
        elif self.path == "/stop_recording":
            ControlServer.recorder.recording = False
            ControlServer.recorder.save_flows_as_json()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Recording stopped and saved")
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Unknown command")

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid JSON")
            return

        if self.path == "/map_local/enable":
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
        elif self.path == "/map_local/disable":
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
        threading.Thread(target=self.run_http_server, daemon=True).start()

    def run_http_server(self):
        server = HTTPServer(('localhost', 9999), ControlServer)
        ctx.log.info("Starting control server on http://localhost:9999")
        server.serve_forever()

    def request(self, flow):
        self.recorder.request(flow)

    def response(self, flow):
        self.recorder.response(flow)

addons = [
    RecorderAddon()
]

