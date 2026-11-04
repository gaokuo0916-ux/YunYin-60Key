package cn.fpga.score;
import java.io.*;import java.util.*;import java.math.BigInteger;
public final class PanelDiagnosticTests{
 static int checks;static void check(boolean b){if(!b)throw new AssertionError("panel check "+checks);checks++;}
 static String frame(BigInteger v){String h=String.format(Locale.ROOT,"%040X",v);int crc=65535;for(int n=0;n<40;n+=2)crc=StudioProtocol.crcByte(crc,Integer.parseInt(h.substring(n,n+2),16));return "D "+h+" "+String.format(Locale.ROOT,"%04X",crc);}
 interface Attempt{void run()throws Exception;}static void reject(Attempt a)throws Exception{try{a.run();throw new AssertionError("bad frame accepted");}catch(IOException e){checks++;}}
 static class Link implements Uploader.Link{String answer;Queue<String> q=new ArrayDeque<>();public void clear(){q.clear();}public void send(String s){check(s.equals("ADINFO"));q.add(answer);}public String receive(long timeout){return q.poll();}}
 public static void main(String[] args)throws Exception{
  BigInteger base=new BigInteger("41443031",16).shiftLeft(128).or(BigInteger.ONE.shiftLeft(114)).or(BigInteger.ONE.shiftLeft(102));
  for(int c=0;c<8;c++)base=base.or(BigInteger.valueOf(513*c).shiftLeft(12*c));
  for(int d=0;d<64;d++)for(int p=0;p<64;p++){
   BigInteger v=base.or(BigInteger.valueOf(d).shiftLeft(96)).or(BigInteger.valueOf(p).shiftLeft(104));
   PanelDiagnostic x=new PanelDiagnostic(frame(v));check(x.amount==Math.min(63,d+p)&&x.baseline==d&&x.pressure==p&&x.online&&x.error==0);
   for(int c=0;c<8;c++)check(x.channels[c]==513*c);
  }
  for(int m=1;m<=3;m++){
   PanelDiagnostic x=new PanelDiagnostic(frame(base.clearBit(102).or(BigInteger.valueOf(m).shiftLeft(102))));check(x.mode==m&&x.message().contains("CH5 压力2"));
  }
  PanelDiagnostic off=new PanelDiagnostic(frame(base.clearBit(114).or(BigInteger.valueOf(9).shiftLeft(110))));check(!off.online&&off.error==9);
  final BigInteger stableBase=base;String valid=frame(base);reject(()->new PanelDiagnostic(valid.substring(0,44)+"000"));
  reject(()->new PanelDiagnostic(valid+"X"));reject(()->new PanelDiagnostic(frame(stableBase.setBit(115))));reject(()->new PanelDiagnostic(frame(stableBase.clearBit(102))));reject(()->new PanelDiagnostic(frame(stableBase.xor(BigInteger.ONE.shiftLeft(128)))));
  Link l=new Link();l.answer=valid;check(new StudioProtocol(l).panelDiagnostic().raw.equals(valid.substring(2,42)));l.answer="ERR 3";reject(()->new StudioProtocol(l).panelDiagnostic());
  ReplyFrames replies=new ReplyFrames();String text=valid+"\n";List<String> got=new ArrayList<>();for(byte b:text.getBytes("US-ASCII"))got.addAll(replies.feed(new byte[]{b}));check(got.size()==1&&got.get(0).equals(valid));
  System.out.println("PASS PanelDiagnostic "+checks+" checks: all4096 sums,8 raw channels,3 modes,offline/error,strict CRC/schema,fragmentation,old-FW rejection; no hardware test");
 }
}
