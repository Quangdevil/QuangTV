"""Regression check for the app's native HTTP/SOCKS bridge, not a Cloudflare deployment test."""
import importlib.util, pathlib, socket, subprocess, threading, types
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('relay_fixture',root/'tests/test_proxy_relay.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class UpgradeOrigin(m.socketserver.BaseRequestHandler):
    def handle(self):
        request=m.headers(self.request).decode('iso8859-1').lower()
        assert 'upgrade: websocket\r\n' in request and 'connection: upgrade\r\n' in request
        assert 'proxy-authorization:' not in request
        self.request.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
        assert m.readn(self.request,4)==b'PING';self.request.sendall(b'PONG')
origin=m.Server(('127.0.0.1',0),UpgradeOrigin);threading.Thread(target=origin.serve_forever,daemon=True).start()
m.origin=types.SimpleNamespace(server_port=origin.server_address[1])
for kind,handler in [('http',m.HTTPProxy),('socks5',m.SOCKSProxy)]:
    proxy=m.Server(('127.0.0.1',0),handler);threading.Thread(target=proxy.serve_forever,daemon=True).start()
    process=subprocess.Popen(['java','-cp',m.CLASSES,'app.tvviewer.player.RelayMain',kind,str(proxy.server_address[1]),'fixture-password'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    try:
        port=int(process.stdout.readline());process.stdout.readline()
        with socket.create_connection(('127.0.0.1',port),timeout=5) as client:
            client.sendall(b'GET http://education.test/socket HTTP/1.1\r\nHost: education.test\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n')
            assert m.headers(client).startswith(b'HTTP/1.1 101')
            client.sendall(b'PING');assert m.readn(client,4)==b'PONG'
    finally:process.stdin.write('\n');process.stdin.flush();process.wait(timeout=5);proxy.shutdown()
origin.shutdown()
print('NATIVE_SOCKET_UPGRADE_PASS httpAndSocks=true bidirectionalBytes=true proxyCredentialsNotLeaked=true')
