import app.quangtv.car.ParkedSensorMonitor;
public final class ParkedSensorMonitorTest {
 static class Fake implements ParkedSensorMonitor.Backend {
  int connects,registers;boolean failConnect,unsupported,failStatus,failSpeed,acceptRegister=true;byte[] status={0};
  public void connect()throws Exception{connects++;if(failConnect)throw new Exception();}
  public boolean supported(int t){return t!=11||!unsupported;}
  public boolean register(int t){registers++;return acceptRegister;}
  public ParkedSensorMonitor.Sample latest(int t)throws Exception{if((t==11&&failStatus)||(t==2&&failSpeed))throw new Exception();return t==11&&status!=null?new ParkedSensorMonitor.Sample(11,null,status):null;}
  public void reset(){}
 }
 static ParkedSensorMonitor create(Fake f){return new ParkedSensorMonitor(f,new ParkedSensorMonitor.Listener(){public void changed(){}public void trace(String k,String v){}});}
 static void check(boolean v){if(!v)throw new AssertionError();}
 public static void main(String[]args){
  Fake f=new Fake();f.failConnect=true;ParkedSensorMonitor m=create(f);m.resume();m.tick(1);check(!m.allowed());f.failConnect=false;m.tick(1001);check(m.allowed());check(f.connects==2);
  f=new Fake();f.failSpeed=true;m=create(f);m.resume();m.tick(1);check(m.allowed());
  f=new Fake();f.acceptRegister=false;f.status=new byte[]{0};m=create(f);m.resume();m.tick(1);int first=f.registers;m.tick(1001);check(f.registers>first&&!m.allowed());f.status=new byte[]{0};f.acceptRegister=true;m.tick(2001);check(m.allowed());
  f=new Fake();f.unsupported=true;m=create(f);m.resume();m.tick(1);check(!m.allowed());m.onEvent(2,new float[]{0},null);check(!m.allowed());
  f=new Fake();m=create(f);m.resume();m.tick(1);m.onEvent(2,new float[]{5},null);check(!m.allowed());m.onEvent(2,new float[]{0},null);check(m.allowed());m.onEvent(2,new float[]{Float.NaN},null);check(!m.allowed());
  f=new Fake();m=create(f);m.resume();m.tick(1);m.onEvent(11,null,new byte[]{1});check(!m.allowed());m.onEvent(11,null,new byte[0]);check(!m.allowed());
  f=new Fake();m=create(f);m.resume();m.tick(1);check(m.allowed());f.failStatus=true;m.tick(1001);check(!m.allowed());f.failStatus=false;m.tick(2001);check(m.allowed());m.stop();check(!m.allowed());m.onEvent(11,null,new byte[]{0});check(!m.allowed());m.resume();check(!m.allowed());m.tick(3001);check(m.allowed());
  System.out.println("PASS: delayed connection, retry, optional failure isolation, missing status, motion, malformed data, reconnect and lifecycle");
 }
}
