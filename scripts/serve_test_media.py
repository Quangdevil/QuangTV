"""HLS plus a throttled, range-capable OTA fixture for actual native download tests."""
import http.server
import json
import threading
import time
import urllib.parse
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
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path.endswith(('.mp4', '.m4a', '.ts')):
            media = (root / path.lstrip('/')).resolve()
            if root.resolve() not in media.parents or not media.is_file():
                self.send_error(404); return
            total = media.stat().st_size; start = 0; end = total - 1
            requested = self.headers.get('Range')
            if requested:
                try:
                    left, right = requested.removeprefix('bytes=').split('-', 1)
                    start = int(left) if left else max(0, total-int(right))
                    end = min(total-1, int(right)) if left and right else total-1
                    if not 0 <= start <= end < total: raise ValueError()
                except ValueError:
                    self.send_response(416); self.send_header('Content-Range',f'bytes */{total}'); self.end_headers(); return
            self.send_response(206 if requested else 200)
            self.send_header('Accept-Ranges', 'bytes'); self.send_header('Content-Type', self.guess_type(str(media)))
            self.send_header('Content-Length', str(end-start+1))
            if requested: self.send_header('Content-Range', f'bytes {start}-{end}/{total}')
            self.end_headers()
            try:
                with media.open('rb') as source:
                    source.seek(start); remaining = end-start+1
                    while remaining:
                        chunk = source.read(min(65536, remaining))
                        if not chunk: break
                        self.wfile.write(chunk); remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError): pass
            return
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
