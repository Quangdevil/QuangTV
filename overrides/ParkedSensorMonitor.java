package app.quangtv.car;

/** Shared by both previews. A missing status is never a parked confirmation. */
public final class ParkedSensorMonitor {
 public interface Backend {
  void connect() throws Exception;
  boolean supported(int type) throws Exception;
  boolean register(int type) throws Exception;
  Sample latest(int type) throws Exception;
  void reset();
 }
 public interface Listener { void changed(); void trace(String key,String value); }
 public static final class Sample {
  public final int type; public final float[] floats; public final byte[] bytes;
  public Sample(int type,float[] floats,byte[] bytes){this.type=type;this.floats=floats;this.bytes=bytes;}
 }
 private final Backend backend; private final Listener listener;
 private boolean connected,known,restricted=true,moving,stopped=true;
 private final boolean[] registered=new boolean[2];
 private long nextPoll;
 public ParkedSensorMonitor(Backend backend,Listener listener){this.backend=backend;this.listener=listener;}
 public boolean allowed(){return !stopped&&known&&!restricted&&!moving;}
 public String reason(){return stopped?"stopped":!known?"waiting-for-status":restricted?"restricted":moving?"moving":"parked";}
 public void resume(){stopped=false;nextPoll=0;listener.changed();}
 public void stop(){stopped=true;known=false;restricted=true;moving=false;connected=false;registered[0]=registered[1]=false;backend.reset();listener.trace("connection","stopped");listener.changed();}
 public void tick(long now){
  if(stopped||now<nextPoll)return;nextPoll=now+1000;
  if(!connected){try{backend.connect();connected=true;listener.trace("connection","ready");}
   catch(Exception e){known=false;restricted=true;listener.trace("connection",e.getClass().getSimpleName());listener.changed();return;}}
  // A failure in optional speed setup must not skip status setup or erase its sample.
  poll(11,0); if(connected)poll(2,1);listener.changed();
 }
 private void poll(int type,int index){
  try{
   boolean supported=backend.supported(type);listener.trace("sensor."+type+".supported",String.valueOf(supported));
   if(!supported){registered[index]=false;if(type==11){known=false;restricted=true;}return;}
   if(!registered[index]){registered[index]=backend.register(type);listener.trace("sensor."+type+".registered",String.valueOf(registered[index]));}
   if(!registered[index]){if(type==11){known=false;restricted=true;}return;}
   Sample sample=backend.latest(type);listener.trace("sensor."+type+".latest",sample==null?"missing":"received");
   if(sample!=null)onEvent(sample.type,sample.floats,sample.bytes);
  }catch(Exception e){registered[index]=false;listener.trace("sensor."+type+".error",e.getClass().getSimpleName());
   if(type==11){known=false;restricted=true;connected=false;backend.reset();registered[0]=registered[1]=false;}}
 }
 public void onEvent(int type,float[] floats,byte[] bytes){
  if(stopped)return;
  if(type==11){known=bytes!=null&&bytes.length>0;restricted=!known||bytes[0]!=0;listener.trace("status",known?(restricted?"restricted":"clear"):"empty");}
  else if(type==2){moving=floats==null||floats.length==0||!Float.isFinite(floats[0])||Math.abs(floats[0])>.05f;listener.trace("speed",moving?"moving-or-invalid":"stationary");}
  listener.changed();
 }
}
