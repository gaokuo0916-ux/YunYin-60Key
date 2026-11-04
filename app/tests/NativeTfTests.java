package cn.fpga.score;
import java.io.*;import java.util.*;
public final class NativeTfTests {
 static int checks;static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
 interface Work{void run()throws Exception;}
 static void reject(Work work,String why)throws Exception{try{work.run();}catch(IOException expected){checks++;return;}throw new AssertionError(why);}
 static final class Link implements Uploader.Link {
  final Deque<String> q=new ArrayDeque<>();final List<String> sent=new ArrayList<>();final Score score;
  int caps=0x1ffb,reads,mode;boolean writing;
  Link(Score s){score=s;}
  public void clear(){q.clear();}
  public void send(String line){
   sent.add(line);
   if(line.equals("FEAT"))q.add(String.format("F24 %04X FFFF",caps));
   else if(line.startsWith("STORE ")){writing=true;q.add("OK");}
   else if(line.equals("RECALL"))q.add("OK");
   else if(line.equals("CINFO")){
    reads++;int state=writing?3:1,error=0,count=score.count(),crc=score.crc;long gen=writing?1:0;
    if(writing&&mode==1){state=4;error=3;}
    if(writing&&mode>=2){if(reads==2){if(mode==2)crc^=1;else if(mode==3)count--;else gen=0;}else{state=4;error=3;}}
    q.add(String.format("S %d %02X %08X %04X %04X 0000",state,error,gen,count,crc));
   }else throw new AssertionError("unexpected command: "+line);
  }
  public String receive(long timeout){return q.pollFirst();}
 }
 public static void main(String[] args)throws Exception{
  Score nativeScore=Score.pitches(120,Arrays.asList(new int[]{61,250},new int[]{62,65535},new int[]{73,500},new int[]{0,1000},new int[]{128,1}));
  Link good=new Link(nativeScore);StudioProtocol.Storage saved=new StudioProtocol(good).persist(nativeScore,(s,t,m)->{});
  check(saved.state==3&&saved.generation==1&&saved.count==5&&saved.crc==nativeScore.crc,"exact native save acknowledgement");
  check(good.sent.get(0).equals("FEAT")&&good.sent.contains("STORE "+nativeScore.crc),"native persistence capability before write");
  Link old=new Link(nativeScore);old.caps=0xffb;reject(()->new StudioProtocol(old).persist(nativeScore,(s,t,m)->{}),"old native RAM firmware must reject TF save");
  check(old.sent.stream().noneMatch(s->s.startsWith("STORE ")),"old firmware never receives unsupported native STORE");
  for(int mode=1;mode<=4;mode++){
   Link bad=new Link(nativeScore);bad.mode=mode;reject(()->new StudioProtocol(bad).persist(nativeScore,(s,t,m)->{}),"must not mark failed/mismatching generation/count/CRC saved");
   check(mode==1||bad.reads>=3,"mismatching success ignored until verified result");
  }
  Score legacy=new Score(120,Arrays.asList(new int[]{1,4},new int[]{2,2}));Link compat=new Link(legacy);compat.caps=0xfb;
  check(new StudioProtocol(compat).persist(legacy,(s,t,m)->{}).state==3,"legacy firmware and score save unchanged");
  check(!compat.sent.contains("FEAT"),"legacy path does not require new capability");
  new StudioProtocol(good).recall();check(good.sent.get(good.sent.size()-1).equals("RECALL"),"same restore command retained");
  System.out.println("PASS NativeTfTests "+checks+" checks; capability gate before writes, exact save confirmation, mismatched count/CRC/generation rejection and legacy compatibility");
 }
}
