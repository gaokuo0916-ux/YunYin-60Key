package cn.fpga.score;
import java.io.*;
import java.nio.channels.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
/** Random access to card containers; read-only. Firmware remains the writer. */
public final class CardRecordingFile {
 public interface Source {long length()throws IOException;void read(long offset,byte[] data)throws IOException;}
 public static final class FileSource implements Source,Closeable{
  private final RandomAccessFile file;
  public FileSource(File f)throws IOException{file=new RandomAccessFile(f,"r");}
  public long length()throws IOException{return file.length();}
  public void read(long offset,byte[] b)throws IOException{if(offset<0||offset>file.length()-b.length)throw new EOFException("卡文件越界");file.seek(offset);file.readFully(b);}
  public void close()throws IOException{file.close();}
 }
 public static final class ChannelSource implements Source {
  private final FileChannel channel;public ChannelSource(FileChannel c){channel=c;}
  public long length()throws IOException{return channel.size();}
  public void read(long offset,byte[] b)throws IOException{
   if(offset<0||offset>length()-b.length)throw new EOFException("卡文件越界");
   channel.position(offset);ByteBuffer out=ByteBuffer.wrap(b);
   while(out.hasRemaining()){int n=channel.read(out);if(n<0)throw new EOFException("卡文件不完整");}
  }
 }
 public static final long LEGACY_SIZE=33554432L,EXTENDED_SIZE=268435456L;
 private static byte[] read(Source s,long at,int size)throws IOException{byte[] b=new byte[size];s.read(at,b);return b;}
 private static int crc(byte[] b,int end){int c=65535;for(int i=0;i<end;i++)c=StudioProtocol.crcByte(c,b[i]);return c;}
 private static boolean magic(byte[] b,String s){return new String(b,0,8,StandardCharsets.US_ASCII).equals(s);}
 private static boolean extension(byte[] b){return magic(b,"YY26RECS")&&PracticeRecords.u32(b,8)==1&&PracticeRecords.u32(b,12)==524288&&
  PracticeRecords.u32(b,16)==65538&&PracticeRecords.u32(b,20)==65664&&PracticeRecords.u32(b,24)==22890&&
  PracticeRecords.u16(b,28)==20&&PracticeRecords.u16(b,30)==2&&crc(b,508)==PracticeRecords.u16(b,508)&&
  (PracticeRecords.u16(b,508)^PracticeRecords.u16(b,510))==65535;}
 public static boolean extended(Source s)throws IOException{
  long size=s.length();if(size!=LEGACY_SIZE&&size!=EXTENDED_SIZE)throw new IOException("请选择原32MiB或兼容扩容256MiB的YUNYIN.BIN");
  byte[] h=read(s,0,16);if(!magic(h,"YY24STOR")||PracticeRecords.u32(h,8)!=1||PracticeRecords.u32(h,12)!=65536)throw new IOException("不是兼容的云音存储容器");
  if(size==LEGACY_SIZE)return false;
  if(!extension(read(s,65536L*512,512))&&!extension(read(s,65537L*512,512)))throw new IOException("扩展存储标记校验失败；不要覆盖原文件");
  return true;
 }
 private static boolean metadata(byte[] b,int id){
  int state=b[16]&255;
  return magic(b,"YY26REC1")&&(b[8]&255)==1&&(b[9]&255)==165&&(b[10]&255)==id&&b[11]==0&&
   PracticeRecords.u32(b,12)!=0&&(state==1||state==2)&&(b[17]&255)<=64&&(b[18]&255)<=64&&(b[19]&255)<2&&
   (state==2||(PracticeRecords.u32(b,20)>0&&PracticeRecords.u32(b,20)<=PracticeRecords.MAX_SAMPLES))&&
   crc(b,508)==PracticeRecords.u16(b,508)&&(PracticeRecords.u16(b,508)^PracticeRecords.u16(b,510))==65535;
 }
 private static boolean zero(byte[] b){for(byte v:b)if(v!=0)return false;return true;}
 private static boolean audioHeader(byte[] b){
  int c=65535;for(int i=0;i<37;i++)if(i!=22&&i!=23)c=StudioProtocol.crcByte(c,b[i]);
  return magic(b,"YY24AUDI")&&PracticeRecords.u32(b,8)==1&&
   (PracticeRecords.u32(b,12)^PracticeRecords.u32(b,24))==0xffffffffL&&
   PracticeRecords.u32(b,16)>0&&PracticeRecords.u32(b,16)<=PracticeRecords.MAX_SAMPLES&&
   PracticeRecords.u32(b,28)==50000000&&PracticeRecords.u32(b,32)==1024&&(b[36]&255)==165&&c==PracticeRecords.u16(b,22);
 }
 static long base(int id){return id==20?256:id==21?32768:65664L+id*22890L;}
 private static PracticeRecords.Entry empty(int id,int state,long seq)throws IOException{return PracticeRecords.decode(id,state,seq,0,0,null);}
 private static PracticeRecords.Entry entry(Source s,int id,boolean ext)throws IOException{
  if(id<0||id>=22)throw new IOException("录音槽号超界");
  if(ext){
   byte[] a=read(s,(65538L+id*2)*512,512),b=read(s,(65539L+id*2)*512,512);
   boolean av=metadata(a,id),bv=metadata(b,id);
   if(av||bv){
    byte[] m=bv&&(!av||PracticeRecords.u32(b,12)>PracticeRecords.u32(a,12))?b:a;
    long sequence=PracticeRecords.u32(m,12);
    if((m[16]&255)==2)return empty(id,2,sequence);
    return PracticeRecords.decode(id,id>=20?4:1,sequence,(int)PracticeRecords.u32(m,20),PracticeRecords.u16(m,24),m);
   }
   if(!zero(a)||!zero(b))return empty(id,3,0);
  }
  if(id<20)return empty(id,0,0);
  byte[] h=read(s,base(id)*512,512);
  if(!audioHeader(h))return empty(id,zero(h)?0:3,0);
  byte[] m=new byte[192];System.arraycopy("YY26REC1".getBytes(StandardCharsets.US_ASCII),0,m,0,8);
  m[8]=1;m[9]=(byte)165;m[10]=(byte)id;m[16]=1;
  PracticeRecords.le(m,20,PracticeRecords.u32(h,16),4);PracticeRecords.le(m,24,PracticeRecords.u16(h,20),2);
  PracticeRecords.le(m,28,PracticeRecords.u32(h,12),4);
  return PracticeRecords.decode(id,4,0,(int)PracticeRecords.u32(h,16),PracticeRecords.u16(h,20),m);
 }
 public static List<PracticeRecords.Entry> list(Source source)throws IOException{
  boolean ext=extended(source);List<PracticeRecords.Entry> rows=new ArrayList<>();
  for(int id=ext?0:20;id<22;id++){PracticeRecords.Entry e=entry(source,id,ext);if(e.state==1||e.state==3||e.state==4)rows.add(e);}
  return rows;
 }
 public static byte[] extract(Source source,PracticeRecords.Entry expected,Uploader.Progress progress)throws Exception{
  boolean ext=extended(source);PracticeRecords.Entry e=entry(source,expected.id,ext);
  if(!expected.same(e)||!e.playable())throw new IOException("这个卡文件与所选记录不符，请重新读取目录");
  byte[] header=read(source,base(e.id)*512,512);
  if(!audioHeader(header)||PracticeRecords.u32(header,12)!=e.sourceSequence||PracticeRecords.u32(header,16)!=e.count||PracticeRecords.u16(header,20)!=e.crc)throw new IOException("录音正文头与目录不符");
  byte[] pcm=new byte[e.count*2];int check=65535;
  for(int pos=0;pos<pcm.length;){
   if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消导出");
   int n=Math.min(8192,pcm.length-pos);byte[] chunk=read(source,(base(e.id)+1)*512+pos,n);
   System.arraycopy(chunk,0,pcm,pos,n);for(byte v:chunk)check=StudioProtocol.crcByte(check,v);pos+=n;
   if(progress!=null)progress.update(pos,pcm.length,"校验所选TF练习录音");
  }
  if(check!=e.crc)throw new IOException("录音正文CRC错误，不导出损坏WAV");return pcm;
 }
}
