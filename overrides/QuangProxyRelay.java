package app.tvviewer.player;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;

/** Loopback HTTP bridge. TLS is tunneled, never decrypted. No direct fallback. */
public final class QuangProxyRelay implements AutoCloseable {
    public final String type, host, user, password;
    public final int upstreamPort;
    private final ServerSocket server;
    private final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
    private final ExecutorService workers = Executors.newCachedThreadPool(r -> { Thread t = new Thread(r, "QuangProxy"); t.setDaemon(true); return t; });
    private final Semaphore slots = new Semaphore(64);
    private final String token = UUID.randomUUID().toString();
    private volatile boolean closed;

    public QuangProxyRelay(String type, String host, int port, String user, String password) throws IOException {
        if (!Arrays.asList("http", "https", "socks5").contains(type) || host.isEmpty() || host.contains("\r") || host.contains("\n") || port < 1 || port > 65535) throw new IOException("Invalid proxy configuration");
        this.type=type; this.host=host; this.upstreamPort=port; this.user=user; this.password=password;
        server=new ServerSocket(0, 32, InetAddress.getByName("127.0.0.1"));
        workers.execute(() -> {
            while (!closed) {
                try {
                    Socket client=server.accept();
                    if (!slots.tryAcquire()) {
                        try { client.getOutputStream().write("HTTP/1.1 503 Service Unavailable\r\nRetry-After: 1\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".getBytes(StandardCharsets.US_ASCII)); }
                        catch (IOException ignored) { /* A rejected/cancelled client must not close the relay. */ }
                        finally { try { client.close(); } catch (IOException ignored) {} }
                        continue;
                    }
                    sockets.add(client);
                    workers.execute(() -> { try { handle(client); } catch (Exception ignored) { try { client.getOutputStream().write("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".getBytes(StandardCharsets.US_ASCII)); } catch(Exception ignoredAgain) {} } finally { sockets.remove(client); try { client.close(); } catch(IOException ignored) {} slots.release(); } });
                } catch (IOException e) { if (!closed) close(); }
            }
        });
    }
    public int port() { return server.getLocalPort(); }
    public Proxy javaProxy() { return new Proxy(Proxy.Type.HTTP, new InetSocketAddress("127.0.0.1", port())); }
    public String downloadUrl(String url) throws IOException { return downloadUrl(url, URI.create(url).getHost()); }
    private String downloadUrl(String url, String cookieHost) throws IOException {
        URI uri=URI.create(url);
        if (!Arrays.asList("http", "https").contains(uri.getScheme()) || uri.getHost()==null || uri.getUserInfo()!=null) throw new IOException("Invalid media URL");
        return "http://127.0.0.1:"+port()+"/"+token+(uri.getPath()!=null&&uri.getPath().toLowerCase(Locale.ROOT).endsWith(".m3u8")?"/playlist.m3u8":"/media")+"?url="+URLEncoder.encode(url,"UTF-8")+"&scope="+URLEncoder.encode(cookieHost,"UTF-8");
    }
    private static String readHeaders(InputStream in) throws IOException {
        ByteArrayOutputStream out=new ByteArrayOutputStream(); int state=0;
        while(out.size()<65536) { int b=in.read(); if(b<0) throw new EOFException(); out.write(b); state=(state==0&&b==13)?1:(state==1&&b==10)?2:(state==2&&b==13)?3:(state==3&&b==10)?4:0; if(state==4)return out.toString("ISO-8859-1"); }
        throw new IOException("Headers too large");
    }
    private Socket upstream(String target, int port) throws IOException {
        Socket s=new Socket(Proxy.NO_PROXY); sockets.add(s);
        try {
            s.connect(new InetSocketAddress(host, upstreamPort),12000); s.setSoTimeout(120000); s.setTcpNoDelay(true);
            if(type.equals("https")) {
                SSLSocket tls=(SSLSocket)((SSLSocketFactory)SSLSocketFactory.getDefault()).createSocket(s,host,upstreamPort,true);
                SSLParameters params=tls.getSSLParameters(); params.setEndpointIdentificationAlgorithm("HTTPS"); tls.setSSLParameters(params); tls.startHandshake(); sockets.remove(s); s=tls; sockets.add(s);
            }
            if(type.equals("socks5")) {
                OutputStream out=s.getOutputStream(); DataInputStream in=new DataInputStream(s.getInputStream());
                out.write(user.isEmpty()?new byte[]{5,1,0}:new byte[]{5,1,2}); out.flush();
                if(in.readUnsignedByte()!=5)throw new IOException("SOCKS version"); int method=in.readUnsignedByte();
                if(method==2 && !user.isEmpty()) {
                    byte[] u=user.getBytes(StandardCharsets.UTF_8),p=password.getBytes(StandardCharsets.UTF_8);
                    if(u.length>255||p.length>255)throw new IOException("SOCKS credentials too long");
                    out.write(1);out.write(u.length);out.write(u);out.write(p.length);out.write(p);out.flush();
                    if(in.readUnsignedByte()!=1||in.readUnsignedByte()!=0)throw new IOException("Proxy authentication failed");
                } else if(method!=0 || !user.isEmpty())throw new IOException("Proxy authentication failed");
                String hostName=target.startsWith("[")&&target.endsWith("]")?target.substring(1,target.length()-1):target;
                boolean literal=hostName.contains(":")||hostName.matches("[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+");
                byte[] name=literal?InetAddress.getByName(hostName).getAddress():IDN.toASCII(hostName).getBytes(StandardCharsets.US_ASCII);
                if(name.length>255)throw new IOException("Host too long");
                out.write(new byte[]{5,1,0,(byte)(literal?(name.length==16?4:1):3)});
                if(!literal)out.write(name.length);
                out.write(name);out.write(port>>8);out.write(port&255);out.flush();
                if(in.readUnsignedByte()!=5||in.readUnsignedByte()!=0)throw new IOException("SOCKS connect rejected");
                in.readUnsignedByte();int addressType=in.readUnsignedByte();int count=addressType==1?4:addressType==4?16:addressType==3?in.readUnsignedByte():-1;
                if(count<0)throw new IOException("SOCKS address");byte[] bound=new byte[count+2];in.readFully(bound);
            }
            return s;
        } catch(IOException e) { sockets.remove(s);try{s.close();}catch(IOException ignored){}throw e; }
    }
    private String auth() { return user.isEmpty()?"":"Proxy-Authorization: Basic "+Base64.getEncoder().encodeToString((user+":"+password).getBytes(StandardCharsets.UTF_8))+"\r\n"; }
    private void handle(Socket client) throws Exception {
        client.setSoTimeout(120000);client.setTcpNoDelay(true);
        String[] lines=readHeaders(client.getInputStream()).split("\r\n");String[] first=lines[0].split(" ",3);
        if(first.length!=3)throw new IOException("Invalid request");
        if(first[1].startsWith("/"+token+"/") && first[1].contains("?url=") && (first[0].equals("GET")||first[0].equals("HEAD"))) { fetch(client,first,lines);return; }
        boolean connect=first[0].equals("CONNECT");
        URI destination=URI.create(connect?"https://"+first[1]:first[1]);String target=destination.getHost();
        if(target==null||(!connect&&!Arrays.asList("http","https").contains(destination.getScheme())))throw new IOException("Invalid target");
        int targetPort=destination.getPort()>0?destination.getPort():(connect||destination.getScheme().equals("https")?443:80);
        Socket remote=upstream(target,targetPort);
        try {
            OutputStream out=remote.getOutputStream();
            if(connect) {
                if(!type.equals("socks5")) {
                    out.write(("CONNECT "+first[1]+" HTTP/1.1\r\nHost: "+first[1]+"\r\n"+auth()+"\r\n").getBytes(StandardCharsets.ISO_8859_1));out.flush();
                    String response=readHeaders(remote.getInputStream());String status=response.split("\r\n",2)[0];
                    if(!status.matches("HTTP/1\\.[01] 200(?: .*|$)"))throw new IOException("Proxy connect rejected");
                }
                client.getOutputStream().write("HTTP/1.1 200 Connection Established\r\n\r\n".getBytes(StandardCharsets.US_ASCII));client.getOutputStream().flush();
            } else {
                String path=first[1];if(type.equals("socks5")) { path=destination.getRawPath();if(path==null||path.isEmpty())path="/";if(destination.getRawQuery()!=null)path+="?"+destination.getRawQuery(); }
                boolean upgrade=Arrays.stream(lines).anyMatch(line->line.equalsIgnoreCase("Upgrade: websocket"));
                StringBuilder request=new StringBuilder(first[0]+" "+path+" HTTP/1.1\r\n");
                for(int i=1;i<lines.length;i++){String key=lines[i].split(":",2)[0].toLowerCase(Locale.ROOT);if(!Arrays.asList("proxy-authorization","proxy-connection","connection").contains(key))request.append(lines[i]).append("\r\n");}
                if(!type.equals("socks5"))request.append(auth());request.append(upgrade?"Connection: Upgrade\r\n\r\n":"Connection: close\r\n\r\n");out.write(request.toString().getBytes(StandardCharsets.ISO_8859_1));out.flush();
            }
            final Socket peer=remote;
            workers.execute(() -> {try{copy(client.getInputStream(),peer.getOutputStream());peer.shutdownOutput();}catch(IOException ignored){}});
            copy(remote.getInputStream(),client.getOutputStream());client.getOutputStream().flush();
        } finally {sockets.remove(remote);remote.close();}
    }
    private void fetch(Socket client,String[] first,String[] lines) throws Exception {
        String[] query=first[1].substring(first[1].indexOf("?url=")+5).split("&scope=",2);
        String url=URLDecoder.decode(query[0],"UTF-8");
        String cookieHost=query.length==2?URLDecoder.decode(query[1],"UTF-8"):"";
        URI uri=URI.create(url);if(!Arrays.asList("http","https").contains(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null)throw new IOException("Invalid download");
        HttpURLConnection conn=(HttpURLConnection)new URL(url).openConnection(javaProxy());
        conn.setConnectTimeout(15000);conn.setReadTimeout(60000);conn.setInstanceFollowRedirects(false);conn.setRequestMethod(first[0]);
        for(String line:lines){int colon=line.indexOf(':');if(colon<=0)continue;String key=line.substring(0,colon).trim();if(key.equalsIgnoreCase("cookie")&&!uri.getHost().equalsIgnoreCase(cookieHost))continue;if(Arrays.asList("range","if-range","user-agent","referer","cookie","accept").contains(key.toLowerCase(Locale.ROOT)))conn.setRequestProperty(key,line.substring(colon+1).trim());}
        conn.setRequestProperty("Accept-Encoding","identity");
        try {
            int code=conn.getResponseCode();String location=conn.getHeaderField("Location");
            String contentType=String.valueOf(conn.getContentType()).toLowerCase(Locale.ROOT);
            if(contentType.contains("dash+xml")||contentType.contains("sstr+xml"))throw new IOException("This manifest requires Media3 with proxy");
            byte[] playlist=null;
            if(code==200 && !first[0].equals("HEAD") && (uri.getPath().toLowerCase(Locale.ROOT).endsWith(".m3u8")||contentType.contains("mpegurl"))) {
                InputStream body=conn.getInputStream();String encoding=conn.getContentEncoding();
                if("gzip".equalsIgnoreCase(encoding))body=new java.util.zip.GZIPInputStream(body);
                else if("deflate".equalsIgnoreCase(encoding))body=new java.util.zip.InflaterInputStream(body);
                try(InputStream input=body;ByteArrayOutputStream bytes=new ByteArrayOutputStream()) {
                    byte[] buffer=new byte[8192];int n;
                    while((n=input.read(buffer))!=-1){if(bytes.size()+n>2*1024*1024)throw new IOException("Playlist too large");bytes.write(buffer,0,n);}
                    playlist=rewritePlaylist(url,bytes.toString("UTF-8"),cookieHost).getBytes(StandardCharsets.UTF_8);
                }
            }
            StringBuilder response=new StringBuilder("HTTP/1.1 "+code+" Response\r\nConnection: close\r\n");
            for(Map.Entry<String,List<String>> h:conn.getHeaderFields().entrySet()) {if(h.getKey()!=null&&!Arrays.asList("connection","transfer-encoding","location").contains(h.getKey().toLowerCase(Locale.ROOT)) && !(playlist!=null&&Arrays.asList("content-length","content-encoding","content-type","etag").contains(h.getKey().toLowerCase(Locale.ROOT))))for(String value:h.getValue())response.append(h.getKey()).append(": ").append(value).append("\r\n");}
            if(playlist!=null)response.append("Content-Type: application/vnd.apple.mpegurl\r\nContent-Length: ").append(playlist.length).append("\r\n");
            if(location!=null)response.append("Location: ").append(downloadUrl(new URL(new URL(url),location).toString(),cookieHost)).append("\r\n");
            client.getOutputStream().write(response.append("\r\n").toString().getBytes(StandardCharsets.ISO_8859_1));
            if(playlist!=null)client.getOutputStream().write(playlist);
            else if(!first[0].equals("HEAD")){InputStream body=code>=400?conn.getErrorStream():conn.getInputStream();if(body!=null)try(InputStream input=body){copy(input,client.getOutputStream());}}
            client.getOutputStream().flush();
        } finally {conn.disconnect();}
    }
    private String rewritePlaylist(String base, String text, String cookieHost) throws IOException {
        if(text.startsWith("\uFEFF"))text=text.substring(1);
        StringBuilder result=new StringBuilder();
        java.util.regex.Pattern attribute=java.util.regex.Pattern.compile("URI=\"([^\"]+)\"");
        for(String line:text.split("\\r?\\n")) {
            String value=line.trim();
            if(!value.isEmpty()&&!value.startsWith("#"))line=mediaReference(base,value,cookieHost);
            else if(value.startsWith("#")) {
                java.util.regex.Matcher match=attribute.matcher(line);StringBuffer replaced=new StringBuffer();
                while(match.find())match.appendReplacement(replaced,java.util.regex.Matcher.quoteReplacement("URI=\""+mediaReference(base,match.group(1),cookieHost)+"\""));
                match.appendTail(replaced);line=replaced.toString();
            }
            result.append(line).append('\n');
        }
        return result.toString();
    }
    private String mediaReference(String base, String reference, String cookieHost) throws IOException {
        if(reference.startsWith("data:"))return reference;
        return downloadUrl(new URL(new URL(base),reference).toString(),cookieHost);
    }
    private static void copy(InputStream in, OutputStream out) throws IOException { byte[] buffer=new byte[32768]; int count; while((count=in.read(buffer))!=-1)out.write(buffer,0,count); }
    public void close() { closed=true;try{server.close();}catch(IOException ignored){}for(Socket s:sockets)try{s.close();}catch(IOException ignored){}workers.shutdownNow(); }
}
