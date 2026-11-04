package cn.fpga.score;
import java.io.*;
import java.util.*;

/** Hardware timbre selection requires both actual SET acknowledgement and query readback. */
public final class TimbreTests {
 static int checks;
 static void check(boolean value){if(!value)throw new AssertionError("Timbre check "+checks);checks++;}
 interface Bad {void run()throws Exception;}
 static void rejects(Bad action)throws Exception{try{action.run();throw new AssertionError("Accepted invalid timbre transaction");}catch(IOException|IllegalArgumentException expected){checks++;}}
 static final class Link implements Uploader.Link {
  final Queue<String> replies=new ArrayDeque<>();final List<String> sent=new ArrayList<>();
  int actual;boolean rejected,badAck,badRead,failRead;String malformed;
  public void clear(){replies.clear();}
  public String receive(long ms){return replies.poll();}
  public void send(String command)throws Exception {
   sent.add(command);
   if(command.startsWith("TONE ")){
    if(rejected){replies.add("ERR 3");return;}
    actual=Integer.parseInt(command.substring(5));replies.add("TONE "+(badAck?(actual+1)%3:actual));return;
   }
   if(command.equals("TINFO")){
    if(failRead)throw new IOException("readback unavailable");
    replies.add(malformed!=null?malformed:"TONE "+(badRead?(actual+1)%3:actual));return;
   }
   throw new IOException("Unexpected command "+command);
  }
 }
 public static void main(String[] args)throws Exception {
  Link l=new Link();StudioProtocol p=new StudioProtocol(l);
  for(int timbre=0;timbre<3;timbre++){
   l.sent.clear();check(p.timbre(timbre)==timbre);
   check(l.sent.equals(Arrays.asList("TONE "+timbre,"TINFO")));
   check(p.timbre()==timbre);
  }
  l.sent.clear();rejects(()->p.timbre(-1));rejects(()->p.timbre(3));check(l.sent.isEmpty());
  l.rejected=true;rejects(()->p.timbre(2));check(l.sent.equals(Arrays.asList("TONE 2")));l.rejected=false;
  l.sent.clear();l.badAck=true;rejects(()->p.timbre(1));check(!l.sent.contains("TINFO"));l.badAck=false;
  l.badRead=true;rejects(()->p.timbre(2));l.badRead=false;
  for(String invalid:Arrays.asList("TONE 3","TONE -1","TONE 02","TONE 2 extra","TONE X")){
   l.malformed=invalid;rejects(()->p.timbre());
  }
  l.malformed=null;l.actual=1;
  StudioMonitor.Snapshot s=StudioMonitor.read(p,256,-1);
  check(s.timbre==1&&!s.timbreFailed&&s.capabilities==256);
  l.actual=2;s=StudioMonitor.read(p,256,-1);check(s.timbre==2); // Physical selection readback.
  l.failRead=true;s=StudioMonitor.read(p,256,-1);
  check(s.timbre==null&&s.timbreFailed&&s.capabilities==256&&s.primaryOkay());
  check(s.warning().contains("音色读回失败"));l.failRead=false;
  l.sent.clear();s=StudioMonitor.read(p,0,-1);check(s.timbre==null&&l.sent.isEmpty());
  System.out.println("PASS TimbreTests "+checks+" checks; three IDs, exact command path, rejection/malformed/incorrect ACK and readback, physical changes, independent failure, old firmware no command");
 }
}
