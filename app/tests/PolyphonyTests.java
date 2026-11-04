package cn.fpga.score;
import java.io.*;
import java.util.*;
public final class PolyphonyTests {
 static int checks;
 static void check(boolean yes){if(!yes)throw new AssertionError("polyphony check "+checks);checks++;}
 interface Bad {void run()throws Exception;}
 static void rejects(Bad b)throws Exception{try{b.run();throw new AssertionError("invalid polyphony response accepted");}catch(IOException|IllegalArgumentException expected){checks++;}}
 static final class Link implements Uploader.Link{
  Queue<String> replies=new ArrayDeque<>();List<String> sent=new ArrayList<>();long active,held;boolean demo,reject;String override;
  public void clear(){replies.clear();}public String receive(long ms){return replies.poll();}
  public void send(String s)throws Exception{
   sent.add(s);if(reject){replies.add("ERR 3");return;}
   if(s.equals("PINFO")){replies.add(override!=null?override:String.format(Locale.ROOT,"P %02X %02X %08X %08X %d 0",Long.bitCount(active),Long.bitCount(held),active,held,demo?1:0));return;}
   if(s.startsWith("PDEMO ")){int n=Integer.parseInt(s.split(" ")[1]);active=held=(1L<<n)-1;demo=true;}
   else if(s.equals("PCLR")){active=held=0;demo=false;}
   else if(s.startsWith("PMUTE ")){int n=Integer.parseInt(s.split(" ")[1]);active&=~(1L<<n);held&=~(1L<<n);}
   else if(!s.startsWith("PTUNE "))throw new IOException("unexpected "+s);
   replies.add("OK");
  }
 }
 public static void main(String[] args)throws Exception{
  Link l=new Link();StudioProtocol p=new StudioProtocol(l);
  for(int n=1;n<=32;n++){
   l.sent.clear();StudioProtocol.Polyphony x=p.polyDemo(n,true);
   check(x.active==n&&x.held==n&&x.demo&&!x.deadline);check(l.sent.equals(Arrays.asList("PDEMO "+n+" 1","PINFO")));
  }
  check(p.polyDemo(32,false).active==32);check(l.sent.contains("PDEMO 32 0"));
  check(p.polyRetune(5).active==32);check(l.sent.contains("PTUNE 5 150"));
  check(p.polyRelease(5).held==31);check(l.sent.contains("PMUTE 5"));
  StudioMonitor.Snapshot snap=StudioMonitor.read(p,512,-1);check(snap.polyphony.active==31&&snap.capabilities==512);
  check(p.polyStop().active==0);check(!p.polyphony().demo);
  rejects(()->p.polyDemo(0,true));rejects(()->p.polyDemo(33,true));rejects(()->p.polyRelease(-1));rejects(()->p.polyRetune(32));
  for(String bad:Arrays.asList("P 21 20 FFFFFFFF FFFFFFFF 1 0","P 20 20 00000001 FFFFFFFF 1 0","P 01 02 00000001 00000003 1 0","P 01 01 00000001 00000002 1 0","P 20 20 FFFFFFFF FFFFFFFF 2 0","P 20 20 FFFFFFFF FFFFFFFF 1")){
   l.override=bad;rejects(()->p.polyphony());
  }
  l.override="P 00 00 00000000 00000000 0 0";rejects(()->p.polyDemo(32,true));l.override=null;
  l.reject=true;l.sent.clear();rejects(()->p.polyDemo(32,true));check(!l.sent.contains("PINFO"));
  l.sent.clear();snap=StudioMonitor.read(p,512,-1);check(snap.polyphony==null&&snap.capabilities==512&&snap.warning().contains("复音状态"));
  l.reject=false;l.sent.clear();snap=StudioMonitor.read(p,0,-1);check(snap.polyphony==null&&l.sent.isEmpty());
  System.out.println("PASS PolyphonyTests "+checks+" checks; real masks, 1..32 voice counts, commands/readback, corruption and rejection guards, old firmware, independent telemetry failure");
 }
}
