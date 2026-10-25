"""Deterministic, authenticated proxy tests. No real account or public network."""
import base64, http.server, pathlib, select, socket, socketserver, ssl, subprocess, tempfile, threading, urllib.parse
ROOT=pathlib.Path(__file__).resolve().parents[1]
CLASSES=tempfile.mkdtemp(prefix='quang-proxy-classes-')
subprocess.run(['java','com.sun.tools.javac.Main','-d',CLASSES,str(ROOT/'overrides/QuangProxyRelay.java'),str(ROOT/'tests/proxy/RelayMain.java')],check=True)
DATA=b'QUANGTV_VIDEO_FIXTURE'*8192
seen={'http':0,'socks5':0,'dns':0,'originAuth':False,'connect':0}
class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        seen['originAuth'] |= self.headers.get('Proxy-Authorization') is not None
        start=int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0])
        data=DATA[start:]
        self.send_response(206 if start else 200);self.send_header('Content-Type','video/mp4');self.send_header('Content-Length',str(len(data)))
        if start:self.send_header('Content-Range',f'bytes {start}-{len(DATA)-1}/{len(DATA)}')
        self.end_headers();self.wfile.write(data)
    def log_message(self,*args):pass
origin=http.server.ThreadingHTTPServer(('127.0.0.1',0),Origin)
threading.Thread(target=origin.serve_forever,daemon=True).start()
def readn(sock,n):
    b=b''
    while len(b)<n:
        part=sock.recv(n-len(b))
        if not part:raise EOFError()
        b+=part
    return b
def headers(sock):
    b=b''
    while not b.endswith(b'\r\n\r\n'):
        b+=readn(sock,1)
        if len(b)>65536:raise ValueError()
    return b
def pipe(a,b):
    a.settimeout(10);b.settimeout(10)
    while True:
        ready,_,_=select.select([a,b],[],[],10)
        if not ready:return
        for source in ready:
            data=source.recv(32768)
            if not data:return
            (b if source is a else a).sendall(data)
class HTTPProxy(socketserver.BaseRequestHandler):
    def handle(self):
        raw=headers(self.request);lines=raw.decode('iso8859-1').split('\r\n');first=lines[0].split()
        expected='Basic '+base64.b64encode(b'fixture-user:fixture-password').decode()
        if not any(x.lower().startswith('proxy-authorization:') and x.split(':',1)[1].strip()==expected for x in lines):
            self.request.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');return
        seen['http']+=1
        target=urllib.parse.urlsplit('https://'+first[1] if first[0]=='CONNECT' else first[1])
        port=target.port if first[0]=='CONNECT' else origin.server_port
        with socket.create_connection(('127.0.0.1',port),timeout=5) as remote:
            if first[0]=='CONNECT':seen['connect']+=1;self.request.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            else:
                path=target.path or '/'
                kept=[x for x in lines[1:] if x and not x.lower().startswith(('proxy-authorization:','proxy-connection:'))]
                remote.sendall((first[0]+' '+path+' HTTP/1.1\r\n'+'\r\n'.join(kept)+'\r\n\r\n').encode('iso8859-1'))
            pipe(self.request,remote)
class SOCKSProxy(socketserver.BaseRequestHandler):
    def handle(self):
        assert readn(self.request,3)==b'\x05\x01\x02';self.request.sendall(b'\x05\x02')
        assert readn(self.request,1)==b'\x01';u=readn(self.request,readn(self.request,1)[0]);p=readn(self.request,readn(self.request,1)[0])
        if (u,p)!=(b'fixture-user',b'fixture-password'):self.request.sendall(b'\x01\x01');return
        self.request.sendall(b'\x01\x00');assert readn(self.request,4)==b'\x05\x01\x00\x03'
        name=readn(self.request,readn(self.request,1)[0]);port=int.from_bytes(readn(self.request,2),'big')
        assert name==b'education.test';seen['dns']+=1;seen['socks5']+=1
        with socket.create_connection(('127.0.0.1',origin.server_port),timeout=5) as remote:
            self.request.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00');pipe(self.request,remote)
class Server(socketserver.ThreadingTCPServer):allow_reuse_address=True;daemon_threads=True

def curl(args):return subprocess.run(['curl','--noproxy','','-fsS','--max-time','12',*args],capture_output=True)
for kind,handler in [('http',HTTPProxy),('socks5',SOCKSProxy)]:
    server=Server(('127.0.0.1',0),handler);threading.Thread(target=server.serve_forever,daemon=True).start()
    for password,valid in [('fixture-password',True),('wrong-password',False)]:
        process=subprocess.Popen(['java','-cp',CLASSES,'app.tvviewer.player.RelayMain',kind,str(server.server_address[1]),password],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            local=int(process.stdout.readline());download=process.stdout.readline().strip()
            result=curl(['--proxy',f'http://127.0.0.1:{local}','http://education.test/video.mp4'])
            assert (result.returncode==0)==valid,(kind,result.stderr)
            if valid:
                assert result.stdout==DATA
                result=curl(['--proxy','','-H','Range: bytes=123-',download]);assert result.returncode==0 and result.stdout==DATA[123:],result.stderr
        finally:process.stdin.write('\n');process.stdin.flush();process.wait(timeout=5)
    server.shutdown()
# HTTPS CONNECT carries encrypted bytes end-to-end. Only this self-signed fixture uses curl -k.
with tempfile.TemporaryDirectory() as temp:
    cert=str(pathlib.Path(temp)/'cert.pem');key=str(pathlib.Path(temp)/'key.pem')
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=education.test'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True)
    tls=http.server.ThreadingHTTPServer(('127.0.0.1',0),Origin);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key);tls.socket=context.wrap_socket(tls.socket,server_side=True);threading.Thread(target=tls.serve_forever,daemon=True).start()
    server=Server(('127.0.0.1',0),HTTPProxy);threading.Thread(target=server.serve_forever,daemon=True).start()
    process=subprocess.Popen(['java','-cp',CLASSES,'app.tvviewer.player.RelayMain','http',str(server.server_address[1]),'fixture-password'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
    try:
        local=int(process.stdout.readline());process.stdout.readline()
        result=curl(['-k','--proxy',f'http://127.0.0.1:{local}',f'https://education.test:{tls.server_port}/video.mp4']);assert result.returncode==0 and result.stdout==DATA,result.stderr
    finally:process.stdin.write('\n');process.stdin.flush();process.wait(timeout=5);server.shutdown();tls.shutdown()
assert seen['http']>=3 and seen['socks5']>=2 and seen['dns']>=2 and seen['connect']>=1 and not seen['originAuth'],seen
origin.shutdown()
print('QUANGTV_PROXY_RELAY_PASS httpAuth=true socksAuth=true remoteDns=true httpsTunnel=true downloadRange=true badCredentialsBlocked=true originCredentialLeak=false')
