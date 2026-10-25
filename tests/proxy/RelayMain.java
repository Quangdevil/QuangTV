package app.tvviewer.player;
public class RelayMain {
    public static void main(String[] args) throws Exception {
        try(QuangProxyRelay relay=new QuangProxyRelay(args[0],"127.0.0.1",Integer.parseInt(args[1]),"fixture-user",args[2])) {
            System.out.println(relay.port());
            System.out.println(relay.downloadUrl("http://education.test/video.mp4"));
            System.out.flush();
            System.in.read();
        }
    }
}
