"""Authenticated HTTP proxy, restricted to the local Android fixture only."""
import base64, select, socket, socketserver, urllib.parse
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        data=b''
        while not data.endswith(b'\r\n\r\n'):
            part=self.request.recv(1)
            if not part:return
            data+=part
            if len(data)>65536:return
        lines=data.decode('iso8859-1').split('\r\n');first=lines[0].split()
        expected='Basic '+base64.b64encode(b'fixture-user:fixture-password').decode()
        valid=any(line.lower().startswith('proxy-authorization:') and line.split(':',1)[1].strip()==expected for line in lines)
        target=urllib.parse.urlsplit(first[1])
        if not valid or target.hostname!='10.0.2.2' or target.port!=8765:
            self.request.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');return
        path=target.path or '/'
        if target.query:path+='?'+target.query
        kept=[line for line in lines[1:] if line and not line.lower().startswith(('proxy-authorization:','proxy-connection:','x-quangtv-test-proxy:'))]
        with socket.create_connection(('127.0.0.1',8765),timeout=10) as remote:
            remote.sendall((first[0]+' '+path+' HTTP/1.1\r\n'+'\r\n'.join(kept)+'\r\nX-QuangTV-Test-Proxy: authenticated-fixture\r\n\r\n').encode('iso8859-1'))
            while True:
                ready,_,_=select.select([self.request,remote],[],[],30)
                if not ready:return
                for source in ready:
                    part=source.recv(32768)
                    if not part:return
                    (remote if source is self.request else self.request).sendall(part)
class Server(socketserver.ThreadingTCPServer):allow_reuse_address=True;daemon_threads=True
Server(('0.0.0.0',8766),Handler).serve_forever()
