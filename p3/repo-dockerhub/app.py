#!/usr/bin/env python3
import http.server
import socketserver
import json
import os

PORT = 8888
VERSION = os.environ.get("VERSION", "v1")
BRAND = os.environ.get("BRAND", "")


def build_badge() -> str:
    if not BRAND:
        return ""
    return f'<div class="badge">{BRAND}</div>'

# HTML diferente para cada versión
HTML_v1 = """
<!DOCTYPE html>
<html>
<head>
    <title>Playground - v1</title>
    <style>
        body { font-family: Arial; text-align: center; margin-top: 50px; background: #e8f5e9; }
        h1 { color: #2e7d32; }
        .version { font-size: 48px; color: #1b5e20; font-weight: bold; margin: 20px; }
        .info { color: #555; margin-top: 20px; font-size: 18px; }
        code { background: #f0f0f0; padding: 10px; display: inline-block; }
        .badge { display: inline-block; margin-top: 14px; padding: 8px 14px; border-radius: 999px; background: #1b5e20; color: white; font-size: 14px; font-weight: bold; letter-spacing: 0.5px; }
    </style>
</head>
<body>
    <h1>🎮 Mlezcano Playground</h1>
    %s
    <div class="version">🟢 VERSION 1</div>
    <div class="info">Welcome to v1 - Initial Version</div>
    <code>{"status":"ok", "message":"v1"}</code>
</body>
</html>
""" % build_badge()

HTML_v2 = """
<!DOCTYPE html>
<html>
<head>
    <title>Playground - v2</title>
    <style>
        body { font-family: Arial; text-align: center; margin-top: 50px; background: #e3f2fd; }
        h1 { color: #1565c0; }
        .version { font-size: 48px; color: #0d47a1; font-weight: bold; margin: 20px; }
        .info { color: #555; margin-top: 20px; font-size: 18px; }
        code { background: #f0f0f0; padding: 10px; display: inline-block; }
        .badge { display: inline-block; margin-top: 14px; padding: 8px 14px; border-radius: 999px; background: #0d47a1; color: white; font-size: 14px; font-weight: bold; letter-spacing: 0.5px; }
    </style>
</head>
<body>
    <h1>🎮 Mlezcano Playground</h1>
    %s
    <div class="version">🔵 VERSION 2</div>
    <div class="info">Welcome to v2 - Enhanced Version</div>
    <code>{"status":"ok", "message":"v2"}</code>
</body>
</html>
""" % build_badge()


class PlaygroundHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            html = HTML_v2 if VERSION == "v2" else HTML_v1
            self.wfile.write(html.encode("utf-8"))
        else:
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            response = json.dumps({"status": "ok", "message": VERSION})
            self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        print(f"[{self.client_address[0]}] {format % args}")


if __name__ == "__main__":
    print(f"Starting Mlezcano Playground {VERSION} on port {PORT}")
    with socketserver.TCPServer(("", PORT), PlaygroundHandler) as httpd:
        print("Server running... Press Ctrl+C to stop")
        httpd.serve_forever()