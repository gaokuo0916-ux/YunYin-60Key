package cn.fpga.score;
import java.io.*;
import java.util.*;
public final class TfRecoveryTests {
 static int checks;static void check(boolean b){if(!b)throw new AssertionError("TF recovery check "+checks);checks++;}
 static String frame(int error,int state,int step,int command,int response,int attempts,boolean initialized,long ocr){
  long d=(1L<<63)|(1L<<62)|((initialized?1L:0)<<61)|((long)(attempts-1)<<59)|((ocr&0xffffffffL)<<27)|((long)response<<19)|((long)command<<13)|((long)step<<9)|((long)state<<4)|error;
  return String.format(Locale.ROOT,"SD %016X",d);
 }
 static final class Link implements Uploader.Link {
  final Queue<String> replies=new ArrayDeque<>();final List<String> sent=new ArrayList<>();boolean failDiagnostic;int retries;
  public void clear(){replies.clear();}public String receive(long ms){return replies.poll();}
  public void send(String line)throws IOException{
   sent.add(line);
   if(line.equals("CINFO")){replies.add("S 4 06 00000000 0000 0000 0000");return;}
   if(line.equals("SDINFO")){if(failDiagnostic)throw new IOException("diagnostic unavailable");replies.add(frame(2,20,0,0,255,3,false,0));return;}
   if(line.equals("SDINIT")){retries++;replies.add("OK");return;}
   throw new IOException("Unexpected command "+line);
  }
 }
 public static void main(String[] args)throws Exception {
  StudioProtocol.SdDiagnostic d=new StudioProtocol.SdDiagnostic(frame(2,20,3,41,255,3,false,0));
  check(d.error==2&&d.state==20&&d.step==3&&d.command==41&&d.response==255&&d.attempts==3&&d.miso==1);
  check(d.canRetry()&&!d.initialized&&d.message().contains("CMD41")&&d.message().contains("未收到有效响应"));
  d=new StudioProtocol.SdDiagnostic(frame(7,20,3,41,1,3,false,0));check(d.message().contains("超时"));
  d=new StudioProtocol.SdDiagnostic(frame(1,20,1,8,5,1,false,0x1aa));check(d.message().contains("握手返回值"));
  d=new StudioProtocol.SdDiagnostic(frame(0,6,4,58,0,2,true,0xc0ff8000L));
  check(d.initialized&&!d.canRetry()&&d.ocr==0xc0ff8000L&&d.attempts==2&&d.message().contains("已完成"));
  d=new StudioProtocol.SdDiagnostic(frame(0,0,0,0,255,2,false,0));check(!d.canRetry()&&d.message().contains("正在初始化"));
  for(String bad:new String[]{"SD 0","SD FFFFFFFFFFFFFFFFF","SD 000000000000000g","SD ffffffffffffffff","D 0000000000000000"}){
   boolean rejected=false;try{new StudioProtocol.SdDiagnostic(bad);}catch(IOException e){rejected=true;}check(rejected);
  }
  Link l=new Link();StudioProtocol p=new StudioProtocol(l);
  StudioMonitor.Snapshot old=StudioMonitor.read(p,16,1);check(old.storage.error==6&&old.sdDiagnostic==null&&!l.sent.contains("SDINFO"));
  StudioMonitor.Snapshot newer=StudioMonitor.read(p,144,1);check(newer.storage.error==6&&newer.sdDiagnostic.canRetry()&&!newer.auxFailed);
  l.failDiagnostic=true;newer=StudioMonitor.read(p,144,1);check(newer.storage!=null&&newer.storage.error==6&&newer.sdDiagnostic==null&&newer.auxFailed);
  check(newer.capabilities==144&&newer.warning().contains("初始化诊断"));
  p.retrySdInitialization();check(l.retries==1&&l.sent.get(l.sent.size()-1).equals("SDINIT"));
  check(l.sent.stream().noneMatch(s->s.startsWith("STORE")||s.equals("RECALL")));
  System.out.println("PASS TfRecoveryTests "+checks+" checks; unsigned diagnostic decoding, command/response/error details, old-firmware fallback, independent telemetry failure, explicit retry command and no writes");
 }
}
