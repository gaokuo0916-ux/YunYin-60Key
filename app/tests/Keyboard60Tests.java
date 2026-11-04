package cn.fpga.score;
import java.io.*;import java.util.*;
public final class Keyboard60Tests {
 static int checks;static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
 interface Work{void run()throws Exception;}static void reject(Work f)throws Exception{try{f.run();}catch(IOException|IllegalArgumentException e){checks++;return;}throw new AssertionError("accepted invalid keyboard packet");}
 static final class Link implements Uploader.Link {
  Deque<String> q=new ArrayDeque<>();List<String> sent=new ArrayList<>();int base=36,code=38,index=0;boolean falseMissing=false;Score score;
  public void clear(){q.clear();}
  public String receive(long timeout){return q.pollFirst();}
  public void send(String s){sent.add(s);
   if(s.isEmpty())return;
   if(s.equals("PING"))q.add("PONG");else if(s.equals("FEAT"))q.add("F24 3FFB FFFF");
   else if(s.equals("KINFO"))q.add(String.format("K %02X 3C 0800000000000001",base));
   else if(s.startsWith("KOCT ")){base=12+12*Integer.parseInt(s.substring(5));q.add("OK");}
   else if(s.equals("MINFO")){boolean missing=code!=0&&(code<base+1||code>base+60);q.add(String.format("N 1 1 %04X %02X 1 %d",index,code,missing^falseMissing?1:0));}
   else if(s.equals("STATE"))q.add(String.format("T %04X 2 00 0000 00FA 0000 0078 1 1",index));
   else if(s.equals("SKIP")){index++;code=61;q.add("OK");}
   else if(s.equals("ABORT"))q.add("OK");else if(s.startsWith("MBEGIN "))q.add("READY");
   else if(s.startsWith("MNOTE ")){}else if(s.startsWith("MEND "))q.add("SAVED");
   else if(s.equals("STATUS"))q.add("S=0 V=1 U=0 E=0");else if(s.equals("CHECK"))q.add(String.format("C %04X %04X",score.count(),score.crc));
   else throw new AssertionError(s);
  }
 }
 public static void main(String[] args)throws Exception {
  Link l=new Link();StudioProtocol p=new StudioProtocol(l);
  check((p.capabilities()&8192)!=0,"explicit 60-key capability");
  for(int oct=0;oct<5;oct++){
   StudioProtocol.Keyboard k=p.octave(oct);check(k.base==12+12*oct&&k.count==60,"octave applied and read back");
   check(k.keys==((1L<<59)|1)&&k.mask.equals("0800000000000001"),"exact upper/lower key bits");
   for(int code=0;code<=128;code++){l.code=code;StudioProtocol.Pitch pitch=p.pitch();check(pitch.code==code&&pitch.missing==(code!=0&&(code<k.base+1||code>k.base+60)),"board range instead of seven-note assumption");}
  }
  p.octave(2);l.code=38;l.falseMissing=true;reject(()->p.pitch());l.falseMissing=false;
  for(String s:Arrays.asList("K 24 3B 0000000000000000","K 25 3C 0000000000000000","K 00 3C 0000000000000000","K 24 3C 1000000000000000","K 24 3C 8000000000000000"))reject(()->new StudioProtocol.Keyboard(s));
  reject(()->p.octave(-1));reject(()->p.octave(5));
  l.code=97;StudioProtocol.Pitch next=p.skipMissing();check(next.index==1&&!next.missing,"only truly out-of-window notes can skip");
  l.index=0;l.code=38;reject(()->p.skipMissing());
  l.score=Score.pitches(120,Arrays.asList(new int[]{38,250},new int[]{96,250}));
  new Uploader(l,20).upload(l.score,(a,b,c)->{});check(l.sent.contains("KINFO")&&l.sent.contains("MEND "+l.score.crc),"chromatic original upload confirmed with 60-key range");
  for(int code=0;code<=128;code++)check(OriginalPractice.keyIndex60(code)==(code>=37&&code<=96?code-36:0),"offline default range supports all 60 notes");
  System.out.println("PASS Keyboard60Tests "+checks+" checks; exact 60-bit state, all five octave windows, original pitch upload and guarded skip");
 }
}
