package cn.fpga.score;
import java.io.*;import java.nio.file.*;import java.nio.charset.StandardCharsets;import java.util.*;
public final class PracticeRecordsTests{
 static int checks;static void check(boolean ok){checks++;if(!ok)throw new AssertionError("practice check "+checks);}
 interface Attempt{void run()throws Exception;}static void reject(Attempt x)throws Exception{try{x.run();throw new AssertionError("invalid accepted");}catch(IOException expected){checks++;}}
 static int crc(byte[] b,int n){int c=65535;for(int i=0;i<n;i++)c=StudioProtocol.crcByte(c,b[i]);return c;}
 static byte[] meta(int id,long seq,int state,byte[] pcm){byte[] m=new byte[512];System.arraycopy("YY26REC1".getBytes(StandardCharsets.US_ASCII),0,m,0,8);m[8]=1;m[9]=(byte)165;m[10]=(byte)id;m[16]=(byte)state;PracticeRecords.le(m,12,seq,4);PracticeRecords.le(m,20,pcm.length/2,4);PracticeRecords.le(m,24,crc(pcm,pcm.length),2);PracticeRecords.le(m,28,1,4);return m;}
 static void seal(byte[] b){int c=crc(b,508);PracticeRecords.le(b,508,c,2);PracticeRecords.le(b,510,c^65535,2);}
 static byte[] read(RandomAccessFile f,long at,int n)throws Exception{byte[] b=new byte[n];f.seek(at);f.readFully(b);return b;}
 static void write(RandomAccessFile f,long at,byte[] b)throws Exception{f.seek(at);f.write(b);}
 static List<PracticeRecords.Entry> list(Path f)throws Exception{try(CardRecordingFile.FileSource s=new CardRecordingFile.FileSource(f.toFile())){return CardRecordingFile.list(s);}}
 static String packet(char kind,int offset,byte[] b){int c=65535;for(int i=0;i<4;i++)c=StudioProtocol.crcByte(c,offset>>>(8*i));c=StudioProtocol.crcByte(c,b.length/2);StringBuilder t=new StringBuilder(String.format(Locale.ROOT,"%c %08X %02X ",kind,offset,b.length/2));for(byte v:b){t.append(String.format(Locale.ROOT,"%02X",v&255));c=StudioProtocol.crcByte(c,v);}return t.append(String.format(Locale.ROOT," %04X",c)).toString();}
 static final class Link implements Uploader.Link{
  String reply;List<String> sent=new ArrayList<>();byte[] m;PracticeRecords.Entry e;byte[] pcm;boolean badPacket;boolean deleted;int state=1;
  Link(PracticeRecords.Entry entry,byte[] metadata,byte[] body){e=entry;m=metadata.clone();pcm=body;}
  public void clear(){reply=null;}public String receive(long ms){String r=reply;reply=null;return r;}
  public void send(String line)throws Exception{
   sent.add(line);String[] v=line.split(" ");reply="OK";
   if(line.equals("ALCAP")){reply="ERR 3";}else if(line.equals("REC 0"))reply="Q 02 14 78 02";
   else if(v[0].equals("REC")){
    int op=Integer.parseInt(v[1]);if(op==1){int id=Integer.parseInt(v[2]);reply=String.format(Locale.ROOT,"N %02X %02X %08X %08X %04X",id,id==e.id?(deleted?2:1):0,id==e.id?e.sequence:0,id==e.id&&!deleted?e.count:0,id==e.id&&!deleted?e.crc:0);}
    if(op==2)m=new byte[192];if(op==3){int w=Integer.parseInt(v[2]),x=Integer.parseInt(v[3]);check(w>=16&&w<=23||w>=32&&w<=95);PracticeRecords.le(m,w*2,x,2);}
    if(op==4){m[17]=(byte)Integer.parseInt(v[2]);m[18]=(byte)Integer.parseInt(v[3]);m[19]=(byte)Integer.parseInt(v[4]);}
    if(op==6){PracticeRecords.le(m,12,e.sequence+1,4);e=PracticeRecords.decode(e.id,1,e.sequence+1,e.count,e.crc,m);}
    if(op==7)deleted=true;
    if(op==8){int w=Integer.parseInt(v[2]);byte[] b=Arrays.copyOfRange(m,w*2,w*2+32);reply=packet('J',w,b);if(badPacket)reply=reply.substring(0,reply.length()-1)+(reply.endsWith("0")?"1":"0");}
   }else if(v[0].equals("ALINFO"))reply=String.format(Locale.ROOT,"A 3 00 %08X %08X %04X",e.sequence,e.count,e.crc);
   else if(v[0].equals("ALGET")){int offset=Integer.parseInt(v[1])*65536+Integer.parseInt(v[2]);int n=Math.min(16,e.count-offset);reply=packet('L',offset,Arrays.copyOfRange(pcm,offset*2,offset*2+n*2));}
  }
 }
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),dir=root.resolve("verification/practice_records_20261029"),actual=dir.resolve("actual_card.bin");
  List<PracticeRecords.Entry> entries=list(actual);check(entries.size()==2);PracticeRecords.Entry a=entries.get(0),b=entries.get(1);check(a.id==0&&b.id==1&&a.name.equals("AB")&&!a.hasDate&&a.seconds()>0.34);
  byte[] pcm=Files.readAllBytes(dir.resolve("record0.pcm")),other=Files.readAllBytes(dir.resolve("record1.pcm"));
  try(CardRecordingFile.FileSource f=new CardRecordingFile.FileSource(actual.toFile())){check(Arrays.equals(pcm,CardRecordingFile.extract(f,a,null)));check(Arrays.equals(other,CardRecordingFile.extract(f,b,null)));}
  try(FileInputStream f=new FileInputStream(actual.toFile())){check(Arrays.equals(pcm,CardRecordingFile.extract(new CardRecordingFile.ChannelSource(f.getChannel()),a,null)));}
  byte[] metadata;try(RandomAccessFile f=new RandomAccessFile(actual.toFile(),"r")){metadata=read(f,65538L*512,192);}
  Link link=new Link(a,metadata,pcm);PracticeRecords p=new PracticeRecords(link);check(p.capabilities().slots==20);check(p.list(p.capabilities(),null).size()==1);check(p.load(0).same(a));check(Arrays.equals(pcm,p.download(a,null)));
  link.badPacket=true;reject(()->p.load(0));link.badPacket=false;
  p.rename(a,"练习片段");check(link.e.name.equals("练习片段")&&!link.e.hasDate&&link.e.sourceSequence==1);reject(()->p.download(a,null));p.delete(link.e);check(p.list(p.capabilities(),null).isEmpty());
  Link start=new Link(a,metadata,pcm);PracticeRecords rec=new PracticeRecords(start);rec.start(120,"新练习","曲目",false,0,0);check(start.sent.get(0).equals("REC 0"));check(start.sent.get(1).equals("REC 2"));check(start.sent.get(start.sent.size()-1).equals("REC 5 120"));check(start.m[19]==0&&PracticeRecords.u64(start.m,32)==0);
  rec.start(30,"记录","歌曲",true,1793275200000L,480);check(start.m[19]==1&&PracticeRecords.u64(start.m,32)==1793275200000L&&PracticeRecords.u16(start.m,40)==480);reject(()->rec.start(121,"","",false,0,0));reject(()->rec.start(30,"一".repeat(22),"",false,0,0));reject(()->rec.start(30,"","",true,0,0));check(PracticeRecords.fitTrack("😀".repeat(30)).getBytes(StandardCharsets.UTF_8).length==64);
  byte[] date=metadata.clone();date[19]=1;PracticeRecords.Entry missing=PracticeRecords.decode(0,1,a.sequence,a.count,a.crc,date);check(!missing.hasDate&&!missing.warning.isEmpty());
  Path scratch=dir.resolve("java_transaction_fixture.bin");Files.copy(actual,scratch,StandardCopyOption.REPLACE_EXISTING);
  try(RandomAccessFile f=new RandomAccessFile(scratch.toFile(),"rw")){
   byte[] old=read(f,65538L*512,512),renamed=old.clone();PracticeRecords.le(renamed,12,2,4);byte[] name="华语练习".getBytes(StandardCharsets.UTF_8);renamed[17]=(byte)name.length;Arrays.fill(renamed,64,128,(byte)0);System.arraycopy(name,0,renamed,64,name.length);seal(renamed);write(f,65539L*512,renamed);check(list(scratch).get(0).name.equals("华语练习"));
   try(CardRecordingFile.FileSource source=new CardRecordingFile.FileSource(scratch.toFile())){check(Arrays.equals(CardRecordingFile.extract(source,list(scratch).get(0),null),pcm));reject(()->CardRecordingFile.extract(source,a,null));}
   renamed[508]^=1;write(f,65539L*512,renamed);check(list(scratch).get(0).same(a));
   renamed[16]=2;PracticeRecords.le(renamed,12,3,4);seal(renamed);write(f,65539L*512,renamed);check(list(scratch).size()==1&&list(scratch).get(0).id==1);
   old[508]^=1;renamed[508]^=1;write(f,65538L*512,old);write(f,65539L*512,renamed);check(list(scratch).get(0).state==3);
   old[508]^=1;write(f,65538L*512,old);write(f,65539L*512,new byte[512]);long at=(65664L+1)*512;byte[] sample=read(f,at,1);f.seek(at);f.write(sample[0]^1);try(CardRecordingFile.FileSource source=new CardRecordingFile.FileSource(scratch.toFile())){reject(()->CardRecordingFile.extract(source,a,null));}write(f,at,sample);
  }finally{Files.deleteIfExists(scratch);}
  Path legacy=dir.resolve("legacy_audio_fixture.bin");check(list(legacy).size()==1);PracticeRecords.Entry old=list(legacy).get(0);check(old.id==20&&old.state==4&&!old.hasDate&&old.count==97656);try(CardRecordingFile.FileSource source=new CardRecordingFile.FileSource(legacy.toFile())){check(CardRecordingFile.extract(source,old,null).length==195312);}
  byte[] wav=StudioProtocol.wav(pcm);check(new String(wav,0,4,"US-ASCII").equals("RIFF")&&PracticeRecords.u32(wav,40)==pcm.length&&wav.length==pcm.length+44&&Arrays.equals(pcm,Arrays.copyOfRange(wav,44,wav.length)));
  check(PracticeRecords.MAX_SAMPLES*2L<=22889L*512&&PracticeRecords.MAX_SAMPLES/48828.125==120.0&&65664L+20*22890<524288);
  System.out.println("PASS PracticeRecordsTests "+checks+" checks: actual RTL PCM->App WAV exact bytes, card-authoritative reread, mirrored metadata/tombstone/torn CRC, legacy export, dates/UTF8, protocol start/rename/delete/download and max capacity bounds; no physical phone/BLE");
 }
}
