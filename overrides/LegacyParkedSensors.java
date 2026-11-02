package app.quangtv.car;

import android.os.Handler;
import android.os.Looper;
import com.google.android.apps.auto.sdk.CarActivity;
import com.google.android.gms.car.CarSensorManager;
import java.util.HashMap;
import java.util.Map;

/** Reacquires the legacy manager after a late connection or a disconnect. */
public final class LegacyParkedSensors {
 public final ParkedSensorMonitor monitor;
 private CarSensorManager manager;
 private int generation;
 private CarSensorManager.CarSensorEventListener events;
 public LegacyParkedSensors(CarActivity activity,ParkedSensorMonitor.Listener listener){
  Handler main=new Handler(Looper.getMainLooper());Map<String,String> previous=new HashMap<>();
  ParkedSensorMonitor.Listener deduplicated=new ParkedSensorMonitor.Listener(){
   public void changed(){listener.changed();}
   public void trace(String key,String value){if(!value.equals(previous.put(key,value)))listener.trace(key,value);}
  };
  monitor=new ParkedSensorMonitor(new ParkedSensorMonitor.Backend(){
   public void connect()throws Exception{if(manager==null){manager=(CarSensorManager)activity.a("sensor");if(manager==null)throw new IllegalStateException("sensor manager missing");final int epoch=++generation;
     events=(type,time,floats,bytes)->{float[] f=floats==null?null:floats.clone();byte[] b=bytes==null?null:bytes.clone();Runnable delivery=()->{if(epoch==generation)monitor.onEvent(type,f,b);};if(Looper.myLooper()==Looper.getMainLooper())delivery.run();else main.post(delivery);};
    }}
   public boolean supported(int type)throws Exception{return manager.isSensorSupported(type);}
   public boolean register(int type)throws Exception{return manager.registerListener(events,type,3);}
   public ParkedSensorMonitor.Sample latest(int type)throws Exception{CarSensorManager.RawEventData e=manager.getLatestSensorEvent(type);return e==null?null:new ParkedSensorMonitor.Sample(e.sensorType,e.floatValues,e.byteValues);}
   public void reset(){CarSensorManager old=manager;manager=null;++generation;if(old!=null)try{old.unregisterListener(events);}catch(Exception ignored){}}
  },deduplicated);
 }
}
