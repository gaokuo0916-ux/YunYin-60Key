package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;
public final class CardAudioTests{
 static int checks;static void check(boolean b){checks++;if(!b)throw new AssertionError("card check "+checks);}
 static void le(byte[] b,int p,long v,int n){for(int i=0;i<n;i++){b[p+i]=(byte)v;v>>>=8;}}
 static byte[] header(long generation,byte[] pcm){byte[] b=new byte[512];System.arraycopy("YY24AUDI".getBytes(java.nio.charset.StandardCharsets.US_ASCII),0,b,0,8);le(b,8,1,4);le(b,12,generation,4);le(b,16,pcm.length/2,4);int crc=65535;for(byte v:pcm)crc=StudioProtocol.crcByte(crc,v);le(b,20,crc,2);le(b,24,generation^0xffffffffL,4);le(b,28,50000000,4);le(b,32,1024,4);b[36]=(byte)165;crc=65535;for(int i=0;i<37;i++)if(i!=22&&i!=23)crc=StudioProtocol.crcByte(crc,b[i]);le(b,22,crc,2);return b;}
 static void put(RandomAccessFile f,int sector,byte[] bytes)throws Exception{f.seek(sector*512L);f.write(bytes);}
 public static void main(String[] args)throws Exception{
  Path path=Paths.get(args[0],"verification/card_audio_fixture.bin");byte[] old=new byte[38],newer=new byte[131080];for(int i=0;i<old.length;i++)old[i]=(byte)(i*7);for(int i=0;i<newer.length;i++)newer[i]=(byte)(i*13);
  try{
   try(RandomAccessFile f=new RandomAccessFile(path.toFile(),"rw")){f.setLength(32L*1024*1024);byte[] marker=new byte[16];System.arraycopy("YY24STOR".getBytes("US-ASCII"),0,marker,0,8);le(marker,8,1,4);le(marker,12,65536,4);f.seek(0);f.write(marker);put(f,256,header(1,old));put(f,257,old);put(f,32768,header(2,newer));put(f,32769,newer);}
   CardAudio.Take take=CardAudio.extract(path.toFile(),null);check(take.generation==2);check(Arrays.equals(take.pcm,newer));check(StudioProtocol.wav(take.pcm).length==newer.length+44);
   try(RandomAccessFile f=new RandomAccessFile(path.toFile(),"rw")){f.seek(32769L*512+22);f.write(1);}
   take=CardAudio.extract(path.toFile(),null);check(take.generation==1);check(Arrays.equals(take.pcm,old));
   try(RandomAccessFile f=new RandomAccessFile(path.toFile(),"rw")){f.seek(256L*512+36);f.write(0);}
   try{CardAudio.extract(path.toFile(),null);throw new AssertionError("corrupt audio accepted");}catch(IOException expected){checks++;}
  }finally{Files.deleteIfExists(path);}
  StudioProtocol.LongAudio a=new StudioProtocol.LongAudio("A 3 00 00000002 0059682F 1234");check(a.generation==2&&a.count==5859375);
  int offset=65536+16,length=4,crc=65535;for(int n=0;n<4;n++)crc=StudioProtocol.crcByte(crc,offset>>>(n*8));crc=StudioProtocol.crcByte(crc,length);StringBuilder body=new StringBuilder();byte[] pcm=Arrays.copyOf(old,8);for(byte v:pcm){body.append(String.format(Locale.ROOT,"%02X",v&255));crc=StudioProtocol.crcByte(crc,v);}String packet=String.format(Locale.ROOT,"L %08X %02X %s %04X",offset,length,body,crc);check(Arrays.equals(pcm,StudioProtocol.decodeLongBlock(packet,offset,4)));
  try{StudioProtocol.decodeLongBlock(packet,16,4);throw new AssertionError("high address dropped");}catch(IOException expected){checks++;}
  File rtl=Paths.get(args[0]).resolve("verification/rtl_audio_fixture.bin").toFile();
  if(!rtl.isFile())throw new IOException("Run studio_audio_store_tb to generate the actual RTL card image first");
  CardAudio.Take real=CardAudio.extract(rtl,null);check(real.generation==1&&real.pcm.length==97656*2);
  int previous=(real.pcm[0]&255)|((real.pcm[1]&255)<<8);
  for(int i=2;i<real.pcm.length;i+=2){int value=(real.pcm[i]&255)|((real.pcm[i+1]&255)<<8);check(((value-previous)&65535)==0x135);previous=value;}
  System.out.println("PASS CardAudioTests "+checks+" checks; real file layout, latest selection, body CRC fallback, corrupt header rejection, >65535 address and WAV");
 }
}
