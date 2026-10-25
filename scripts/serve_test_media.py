"""HLS plus a throttled, range-capable OTA fixture for actual native download tests."""
import http.server
import json
import threading
import time
from pathlib import Path

root = Path('/tmp/quangtv-hls')
body = bytes(range(256)) * (2 * 1024 * 1024 // 256)
(root / 'ota-fixture.apk').write_bytes(body)
requests = 0
lock = threading.Lock()

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(root), **kwargs)

    def do_GET(self):
        global requests
        if self.path.startswith('/proxy-only/'):
            if self.headers.get('X-QuangTV-Test-Proxy') != 'authenticated-fixture':
                self.send_error(403, 'Authenticated proxy required'); return
            self.path = self.path[len('/proxy-only'):]
        if self.path == '/ota-metrics.json':
            data = json.dumps({'requests': requests}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path != '/ota-fixture.apk':
            return super().do_GET()
        with lock:
            requests += 1
        start = int(self.headers.get('Range', 'bytes=0-').split('=')[1].split('-')[0])
        self.send_response(206 if start else 200)
        self.send_header('Content-Type', 'application/vnd.android.package-archive')
        self.send_header('Content-Length', str(len(body) - start))
        if start:
            self.send_header('Content-Range', f'bytes {start}-{len(body)-1}/{len(body)}')
        self.end_headers()
        try:
            for offset in range(start, len(body), 16384):
                self.wfile.write(body[offset:offset+16384])
                self.wfile.flush()
                time.sleep(.08)
        except (BrokenPipeError, ConnectionResetError):
            pass

http.server.ThreadingHTTPServer(('0.0.0.0', 8765), Handler).serve_forever()
