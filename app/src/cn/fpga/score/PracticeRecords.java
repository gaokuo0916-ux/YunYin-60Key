package cn.fpga.score;
import java.io.*;
import java.nio.*;
import java.nio.charset.*;
import java.util.*;
/** Card-authoritative practice directory; no phone-only index or invented time. */
public final class PracticeRecords {
 public static final int CAPABILITY=32768,SLOTS=20,LEGACY=2,MAX_SECONDS=120,MAX_SAMPLES=5859375;
 private final Uploader.Link link;private final StudioProtocol audio;
 public PracticeRecords(Uploader.Link l){link=l;audio=new StudioProtocol(l);}
 public static String error(int code){switch(code){
  case 1:return "TF读写失败，未提交本次更改";case 2:return "录音或目录校验失败，未提交本次更改";
  case 4:return "琴端TF正忙，请稍后重试";case 5:return "写卡未能跟上，32KiB缓存已溢出，本段未保存";
  case 6:return "TF练习录音槽已满，请先删除不需要的记录";case 7:return "目录损坏，该槽已隔离";
  case 8:return "录音参数或当前记录状态无效";case 9:return "需先兼容扩容为256MiB练习记录容器，旧数据不应覆盖";
  case 11:return "目录序号已耗尽，不能安全覆盖记录";default:return "琴端录音操作失败："+code;
 }}
 private String command(String text,String prefix)throws Exception{
  if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消操作");
  link.clear();link.send(text);long end=System.nanoTime()+6500000000L;
  while(System.nanoTime()<end){String s=link.receive(200);if(s==null)continue;
   if(s.startsWith("!"))throw new IOException(s.substring(1));
   if(s.matches("E [0-9A-F]{2}"))throw new IOException(error(Integer.parseInt(s.substring(2),16)));
   if(s.startsWith("ERR "))throw new IOException("琴端未执行录音目录命令："+s);
   if(s.startsWith(prefix))return s;
   throw new IOException("录音目录回执与操作不符："+s);
  }throw new IOException("等待录音目录回执超时；请刷新卡端目录确认，勿假定写入成功");
 }
 public static final class Capabilities{
  public final int mode,slots,seconds,legacy;
  public Capabilities(String line)throws IOException{
   if(!line.matches("Q [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2}"))throw new IOException("录音能力格式错误");
   String[] s=line.split(" ");mode=Integer.parseInt(s[1],16);slots=Integer.parseInt(s[2],16);
   seconds=Integer.parseInt(s[3],16);legacy=Integer.parseInt(s[4],16);
   if(mode>2||slots!=20||seconds!=120||legacy!=2)throw new IOException("不支持的录音目录版本");
  }
 }
 public static final class Entry{
  public final int id,state,count,crc;public final long sequence,sourceSequence,timeMillis;public final int zoneMinutes;
  public final String name,track,warning;public final boolean hasDate;
  Entry(int i,int st,long seq,int n,int check,long source,String title,String song,boolean date,long time,int zone,String warn){
   id=i;state=st;sequence=seq;count=n;crc=check;sourceSequence=source;
   name=title==null||title.isEmpty()?(st==3?"目录损坏 #":i>=20?"旧录音 #":"练习记录 #")+(i+1):title;
   track=song==null?"":song;hasDate=date;timeMillis=time;zoneMinutes=zone;warning=warn==null?"":warn;
  }
  public boolean playable(){return (state==1||state==4)&&count>0;}
  public double seconds(){return count/48828.125;}
  public String key(){return id+"_"+sequence+"_"+count+"_"+crc;}
  public boolean same(Entry e){return e!=null&&id==e.id&&state==e.state&&sequence==e.sequence&&count==e.count&&crc==e.crc;}
 }
 static long u32(byte[] b,int at){return (b[at]&255L)|((b[at+1]&255L)<<8)|((b[at+2]&255L)<<16)|((b[at+3]&255L)<<24);}
 static int u16(byte[] b,int at){return(b[at]&255)|((b[at+1]&255)<<8);}
 static long u64(byte[] b,int at){return u32(b,at)|(u32(b,at+4)<<32);}
 static void le(byte[] b,int at,long value,int size){for(int i=0;i<size;i++){b[at+i]=(byte)value;value>>>=8;}}
 private static String utf8(byte[] b,int at,int n)throws CharacterCodingException{
  return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(b,at,n)).toString();
 }
 static Entry decode(int id,int state,long sequence,int count,int crc,byte[] meta)throws IOException{
  if(id<0||id>=22||state<0||state>4||sequence<0||sequence>0xffffffffL||count<0||count>MAX_SAMPLES)throw new IOException("目录字段超界");
  if(state==0||state==2||state==3)return new Entry(id,state,sequence,count,crc,0,"","",false,0,0,"");
  if(count==0||meta==null||meta.length<192)throw new IOException("有效录音缺少内容或元数据");
  if(!new String(meta,0,8,StandardCharsets.US_ASCII).equals("YY26REC1")||(meta[8]&255)!=1||(meta[9]&255)!=165||
   (meta[10]&255)!=id||u32(meta,12)!=sequence||u32(meta,20)!=count||u16(meta,24)!=crc)throw new IOException("目录分包与当前记录不一致");
  int nl=meta[17]&255,tl=meta[18]&255,flags=meta[19]&255;
  if(nl>64||tl>64||flags>1)throw new IOException("名称或时间标志超界");
  String name="",track="",warning="";
  try{name=utf8(meta,64,nl);}catch(CharacterCodingException bad){warning="名称编码损坏，可重新命名";}
  try{track=utf8(meta,128,tl);}catch(CharacterCodingException bad){warning+=" 曲目名称编码损坏";}
  long time=u64(meta,32);int zone=(short)u16(meta,40);
  boolean date=(flags&1)!=0&&time>=946684800000L&&time<4133980800000L&&zone>=-840&&zone<=840;
  if((flags&1)!=0&&!date)warning+=" 手机时间无效";
  return new Entry(id,state,sequence,count,crc,u32(meta,28),name,track,date,date?time:0,date?zone:0,warning.trim());
 }
 public Capabilities capabilities()throws Exception{return new Capabilities(command("REC 0","Q "));}
 public Entry load(int id)throws Exception{
  if(id<0||id>=22)throw new IOException("录音槽号超界");
  String s=command("REC 1 "+id,"N ");
  if(!s.matches("N [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{8} [0-9A-F]{8} [0-9A-F]{4}"))throw new IOException("目录回执格式错误");
  String[] f=s.split(" ");int actual=Integer.parseInt(f[1],16),state=Integer.parseInt(f[2],16);
  long seq=Long.parseLong(f[3],16),samples=Long.parseLong(f[4],16);int crc=Integer.parseInt(f[5],16);
  if(actual!=id||samples>MAX_SAMPLES)throw new IOException("目录槽号或长度不符");
  byte[] meta=null;
  if(state==1||state==4){
   meta=new byte[192];
   for(int word=0;word<96;word+=16){
    String packet=command("REC 8 "+word,"J ");
    if(!packet.startsWith("J "))throw new IOException("元数据分包类型错误");
    byte[] b=StudioProtocol.decodeLongBlock("L "+packet.substring(2),word,16);
    System.arraycopy(b,0,meta,word*2,b.length);
   }
  }
  return decode(id,state,seq,(int)samples,crc,meta);
 }
 public List<Entry> list(Capabilities cap,Uploader.Progress progress)throws Exception{
  List<Entry> result=new ArrayList<>();if(cap.mode==0)return result;
  int start=cap.mode==2?0:20;
  for(int id=start;id<22;id++){
   Entry e=load(id);if(e.state==1||e.state==3||e.state==4)result.add(e);
   if(progress!=null)progress.update(id-start+1,22-start,"读取TF练习记录目录");
  }
  return result;
 }
 public static String fitTrack(String s){if(s==null)return "";while(s.getBytes(StandardCharsets.UTF_8).length>64)s=s.substring(0,s.offsetByCodePoints(s.length(),-1));return s;}
 private void stage(String name,String track,boolean date,long time,int zone,boolean cleared)throws Exception{
  byte[] n=name.getBytes(StandardCharsets.UTF_8),t=track.getBytes(StandardCharsets.UTF_8);
  if(n.length>64||t.length>64)throw new IOException("名称/曲目最多64个UTF8字节（汉字通常约21字）");
  if(date&&(time<946684800000L||time>=4133980800000L||zone< -840||zone>840))throw new IOException("手机时间无效，请取消附带日期");
  byte[] b=new byte[192];System.arraycopy(n,0,b,64,n.length);System.arraycopy(t,0,b,128,t.length);
  if(date){le(b,32,time,8);le(b,40,zone&65535,2);}
  for(int word=16;word<96;word++)if(word<=23||word>=32){
   int value=u16(b,word*2);if(!cleared||value!=0)command("REC 3 "+word+" "+value,"OK");
  }
  command("REC 4 "+n.length+" "+t.length+" "+(date?1:0),"OK");
 }
 public void start(int seconds,String name,String track,boolean date,long time,int zone)throws Exception{
  if(seconds<1||seconds>120)throw new IOException("录音最长1～120秒");
  if(capabilities().mode!=2)throw new IOException(error(9));
  command("REC 2","OK");stage(name,fitTrack(track),date,time,zone,true);
  command("REC 5 "+seconds,"OK");
 }
 private Entry checked(Entry expected)throws Exception{
  Entry now=load(expected.id);if(!now.same(expected))throw new IOException("卡端记录已变化，请刷新后重试");return now;
 }
 public void rename(Entry expected,String title)throws Exception{
  Entry e=checked(expected);if(!e.playable())throw new IOException("该目录项不可更名");
  stage(title,e.track,e.hasDate,e.timeMillis,e.zoneMinutes,false);command("REC 6","OK");
  Entry next=load(e.id);if(next.sequence!=e.sequence+1||!next.name.equals(title.isEmpty()?(next.id>=20?"旧录音 #":"练习记录 #")+(next.id+1):title))throw new IOException("更名未获卡端确认");
 }
 public void delete(Entry expected)throws Exception{
  Entry e=checked(expected);command("REC 7","OK");if(load(e.id).state!=2)throw new IOException("删除未获卡端墓碑确认");
 }
 public byte[] download(Entry expected,Uploader.Progress progress)throws Exception{
  Entry e=checked(expected);if(!e.playable())throw new IOException("目录损坏的记录不能导出");
  command("REC 9","OK");StudioProtocol.LongAudio take=audio.audio();
  if(take.count!=e.count||take.crc!=e.crc||take.generation!=e.sequence)throw new IOException("所选录音与导出信息不符");
  return audio.downloadAudio(take,progress==null?(sent,total,stage)->{}:progress);
 }
 public void stop()throws Exception{audio.stopAudio();}
}
