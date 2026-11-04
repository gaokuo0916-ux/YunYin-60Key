package cn.fpga.score;
import java.util.Locale;
/** Measured received payload rate, not a promised Bluetooth throughput. */
public final class AudioTransferProgress {
 private AudioTransferProgress(){}
 public static String idealTime(int samples){
  if(samples<=0)throw new IllegalArgumentException("samples");
  long tail=samples%256,chars=(samples/256L)*706+(tail==0?0:22+4*((tail*2+2)/3));
  long seconds=(chars*10+38399)/38400;
  return seconds<60?seconds+"秒":(seconds/60)+"分"+(seconds%60)+"秒";
 }
 public static String describe(String stage,int sent,int total,long elapsedMillis){
  if(sent<0||total<=0||sent>total||elapsedMillis<0)throw new IllegalArgumentException("progress");
  String amount=String.format(Locale.ROOT,"%.1f / %.1f KB",sent*2.0/1024,total*2.0/1024);
  if(sent==total)return amount+" · 已接收，正在校验";
  if(sent==0||elapsedMillis<2000)return stage+" · "+amount+" · 正在测算速度";
  double rate=sent*2.0*1000/elapsedMillis;
  long seconds=(long)Math.ceil((total-sent)*2.0/rate);
  String left=seconds<60?seconds+"秒":(seconds/60)+"分"+(seconds%60)+"秒";
  return String.format(Locale.ROOT,"%s · %.1f KB/s · 预计剩余%s",amount,rate/1024,left);
 }
}
