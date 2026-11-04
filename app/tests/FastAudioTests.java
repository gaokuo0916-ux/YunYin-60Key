package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;
public final class FastAudioTests {
 static int checks;
 static void check(boolean yes){checks++;if(!yes)throw new AssertionError("fast audio "+checks);}
 static int crc(byte[] b){int c=65535;for(byte x:b)c=StudioProtocol.crcByte(c,x);return c;}
 static String packet(int offset,byte[] b){
  int c=65535;for(int n=0;n<4;n++)c=StudioProtocol.crcByte(c,offset>>>(8*n));
  c=StudioProtocol.crcByte(c,b.length/2);c=StudioProtocol.crcByte(c,(b.length/2)>>>8);
  for(byte x:b)c=StudioProtocol.crcByte(c,x);
  return String.format(Locale.ROOT,"B %08X %04X %s %04X",offset,b.length/2,Base64.getEncoder().encodeToString(b),c);
 }
 static void reject(String s,int offset,int length)throws Exception{try{StudioProtocol.decodeFastBlock(s,offset,length);throw new AssertionError("corruption accepted");}catch(IOException expected){checks++;}}
 static class Link implements Uploader.Link {
  byte[] pcm;String reply;boolean fast,corruptOnce,corruptAll,rejectLarge;int requests;
  Link(byte[] p,boolean f){pcm=p;fast=f;}
  public void clear(){reply=null;}
  public String receive(long ms){String r=reply;reply=null;return r;}
  public void send(String text){
   if(text.equals("ALCAP")){reply=fast?"B64":"ERR 3";return;}
   String[] a=text.split(" ");int offset=(Integer.parseInt(a[1])<<16)+Integer.parseInt(a[2]);requests++;
   boolean page=a[0].equals("ALPAGE");int n=Math.min(page?256:16,pcm.length/2-offset);byte[] b=Arrays.copyOfRange(pcm,offset*2,(offset+n)*2);
   if(page)reply=packet(offset,b);
   else {int c=65535;for(int i=0;i<4;i++)c=StudioProtocol.crcByte(c,offset>>>(8*i));c=StudioProtocol.crcByte(c,n);
    StringBuilder d=new StringBuilder();for(byte x:b){d.append(String.format(Locale.ROOT,"%02X",x&255));c=StudioProtocol.crcByte(c,x);}
    reply=String.format(Locale.ROOT,"L %08X %02X %s %04X",offset,n,d,c);
   }
   if(corruptOnce||corruptAll||(rejectLarge&&page)){corruptOnce=false;reply=reply.substring(0,reply.length()-1)+(reply.endsWith("0")?"1":"0");}
  }
 }
 public static void main(String[] args)throws Exception {
  check(AudioTransferProgress.idealTime(256).equals("1秒"));
  check(AudioTransferProgress.idealTime(48828).equals("36秒"));
  check(AudioTransferProgress.describe("test",256,1000,100).contains("测算"));
  check(AudioTransferProgress.describe("test",500,1000,2000).contains("2秒"));
  check(AudioTransferProgress.describe("test",1000,1000,10000).contains("校验"));
  List<String> lines=Files.readAllLines(Paths.get(args[0]));int packets=0;
  for(String line:lines)if(line.startsWith("B ")){
   String[] p=line.split(" ");int offset=(int)Long.parseLong(p[1],16),n=Integer.parseInt(p[2],16);
   byte[] data=StudioProtocol.decodeFastBlock(line,offset,n);check(data.length==2*n);
   for(int i=0;i<n;i++){int word=((i*7919)^0xa50a)&65535;check((data[2*i]&255)==(word&255));check((data[2*i+1]&255)==(word>>>8));}
   ReplyFrames frames=new ReplyFrames();byte[] text=(line+"\n").getBytes("US-ASCII");List<String> got=new ArrayList<>();
   for(int i=0;i<text.length;i+=20)got.addAll(frames.feed(Arrays.copyOfRange(text,i,Math.min(i+20,text.length))));
   check(got.size()==1&&got.get(0).equals(line));packets++;
  }
  check(packets==260);
  Random random=new Random(20261101);
  for(int n=1;n<=256;n++){
   byte[] data=new byte[2*n];random.nextBytes(data);String s=packet(65536,data);
   check(Arrays.equals(data,StudioProtocol.decodeFastBlock(s,65536,n)));
   reject(s,0,n);reject(s,65536,n==256?255:n+1);
   reject(s.substring(0,s.length()-1)+(s.endsWith("0")?"1":"0"),65536,n);
  }
  byte[] body=new byte[(65536+257)*2];random.nextBytes(body);
  StudioProtocol.LongAudio take=new StudioProtocol.LongAudio(String.format(Locale.ROOT,"A 3 00 00000001 %08X %04X",body.length/2,crc(body)));
  for(boolean fast:new boolean[]{true,false}){
   Link link=new Link(body,fast);if(fast)link.corruptOnce=true;
   byte[] downloaded=new StudioProtocol(link).downloadAudio(take,(a,b,c)->{});
   check(Arrays.equals(body,downloaded));check(link.requests==(body.length/2+(fast?255:15))/(fast?256:16)+(fast?1:0));
   check(StudioProtocol.wav(downloaded).length==body.length+44);
  }
  Link smallOnly=new Link(body,true);smallOnly.rejectLarge=true;check(Arrays.equals(body,new StudioProtocol(smallOnly).downloadAudio(take,(a,b,c)->{})));check(smallOnly.requests==3+(body.length/2+15)/16);
  Link bad=new Link(body,true);bad.corruptAll=true;
  try{new StudioProtocol(bad).downloadAudio(take,(a,b,c)->{});throw new AssertionError("bad pages saved");}catch(IOException expected){check(bad.requests==6);}
  System.out.println("PASS fast audio "+checks+" checks: actual RTL pages, notification fragmentation, all tails, corruption, retries, high offsets, complete CRC/WAV and old firmware fallback; no physical BLE claim");
 }
}
