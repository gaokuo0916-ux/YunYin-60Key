package cn.fpga.score;
import java.io.*;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.zip.*;

/** Actual offline MIDI files plus automatically adapted seven-key versions. */
public final class BundledMidiCatalog {
 // Existing real MIDI assets requested by the user, not new metadata-only songs.
 private static final List<String> FEATURED=Collections.unmodifiableList(Arrays.asList(
  "f3b4e0f0ed85e382031ca034449ba201dac10490331d2b7b8c7b79111edf700d",
  "156c1075b21670abfab4a70b39530579eec8150799f6cbe0f256d4b6185fdcc1",
  "3c8d81baf8240fb77143a7ce325c3efc37cdba3d7d78f3b5e5fc4c42f2a31831",
  "40393700222809330f3a0c9709e08b202c65a20b35ade93ed7e56fa97a26624b",
  "1a5bf0176fb6738f68afb02d5282fa1888354e38c40d9b1892fb07eb14222658"));
 public static boolean featured(String id){return FEATURED.contains(id);}
 private static int priority(Item item){int n=FEATURED.indexOf(item.id);return n<0?FEATURED.size():n;}
 public static final class Item {
  public final String id,title,original,category,song,path,search;
  public final boolean chinese,prepared;
  public final int notes,tracks,bpm,track,tonic,unsupported,events;
  Item(String[] c)throws IOException{
   id=c[0];title=c[1];original=c[2];category=c[3];chinese=c[4].equals("1")||featured(id);song=c[5];
   try{notes=Integer.parseInt(c[6]);tracks=Integer.parseInt(c[7]);bpm=Integer.parseInt(c[8]);track=Integer.parseInt(c[9]);tonic=Integer.parseInt(c[10]);unsupported=Integer.parseInt(c[11]);events=Integer.parseInt(c[12]);}
   catch(NumberFormatException e){throw new IOException("离线曲库目录数值无效",e);}
   prepared=c[13].equals("1");path=c[14];search=OpenCatalog.normalize(title+" "+original+" "+song);
   if(!id.matches("[a-f0-9]{64}")||title.isEmpty()||title.length()>500||notes<1||tracks<1||track<0||track>=tracks||tonic<0||tonic>11||bpm<20||bpm>300||path.startsWith("/")||Arrays.asList(path.split("/")).contains(".."))throw new IOException("离线曲库目录校验失败");
   if(prepared&&(events<1||events>Score.CAPACITY))throw new IOException("七键曲谱索引不一致");
  }
  public String source(){try{return "https://github.com/Tsundeer/MeowField_MidiLibrary/blob/main/"+URLEncoder.encode(path,"UTF-8").replace("+","%20").replace("%2F","/");}catch(UnsupportedEncodingException e){throw new AssertionError(e);}}
 }
 public final List<Item> items;public final String bundleSha;public final long bundleBytes;public final int chineseCount,preparedCount;
 private BundledMidiCatalog(List<Item> rows,String hash,long size){items=Collections.unmodifiableList(rows);bundleSha=hash;bundleBytes=size;int zh=0,ready=0;for(Item i:rows){if(i.chinese)zh++;if(i.prepared)ready++;}chineseCount=zh;preparedCount=ready;}
 public static BundledMidiCatalog read(InputStream input)throws IOException{
  try(BufferedReader r=new BufferedReader(new InputStreamReader(input,StandardCharsets.UTF_8))){
   String line=r.readLine();if(line==null)throw new IOException("离线曲库目录为空");String[] h=line.split("\t",-1);long size;
   if(h.length!=3||!h[0].equals("YUNYIN_MIDI_1")||!h[1].matches("[a-f0-9]{64}"))throw new IOException("离线曲库版本无效");
   try{size=Long.parseLong(h[2]);}catch(NumberFormatException e){throw new IOException("离线曲库大小无效",e);}
   if(size<1||size>128*1024*1024)throw new IOException("离线曲库大小超限");
   List<Item> rows=new ArrayList<>();Set<String> ids=new HashSet<>();
   while((line=r.readLine())!=null){String[] c=line.split("\t",-1);if(c.length!=15||rows.size()>=30000)throw new IOException("离线曲库目录行无效");Item i=new Item(c);if(!ids.add(i.id))throw new IOException("离线曲库编号重复");rows.add(i);}
   return new BundledMidiCatalog(rows,h[1],size);
  }
 }
 public List<Item> search(String query,boolean chineseOnly){
  String[] words=OpenCatalog.normalize(query.trim()).split("\\s+");List<Item> out=new ArrayList<>();
  for(Item i:items){if(chineseOnly&&!i.chinese)continue;boolean match=true;for(String w:words)if(!i.search.contains(w)){match=false;break;}if(match)out.add(i);}
  // Stable sorting keeps every other arrangement and the existing pagination.
  out.sort(Comparator.comparingInt(BundledMidiCatalog::priority));return out;
 }
 static String hash(byte[] bytes)throws IOException{try{StringBuilder b=new StringBuilder();for(byte x:MessageDigest.getInstance("SHA-256").digest(bytes))b.append(String.format(Locale.ROOT,"%02x",x&255));return b.toString();}catch(NoSuchAlgorithmException e){throw new IOException(e);}}
 /** Private cache is a copy of the installed asset; no network access is needed. */
 public File install(InputStream asset,File cache)throws IOException{
  if(!cache.isDirectory()&&!cache.mkdirs())throw new IOException("无法建立离线曲库缓存");
  File file=new File(cache,"library-"+bundleSha+".zip"),temp=new File(cache,"library-"+bundleSha+".tmp");
  try(InputStream in=asset){
   if(file.isFile()&&file.length()==bundleBytes)return file;
   try{MessageDigest digest=MessageDigest.getInstance("SHA-256");long size=0;
    try(FileOutputStream out=new FileOutputStream(temp)){byte[] b=new byte[32768];int n;while((n=in.read(b))!=-1){size+=n;if(size>bundleBytes)throw new IOException("离线曲库文件超出索引大小");digest.update(b,0,n);out.write(b,0,n);}out.getFD().sync();}
    StringBuilder got=new StringBuilder();for(byte x:digest.digest())got.append(String.format(Locale.ROOT,"%02x",x&255));
    if(size!=bundleBytes||!got.toString().equals(bundleSha))throw new IOException("离线曲库文件校验失败");
    Files.move(temp.toPath(),file.toPath(),StandardCopyOption.REPLACE_EXISTING);return file;
   }catch(NoSuchAlgorithmException e){throw new IOException(e);}finally{Files.deleteIfExists(temp.toPath());}
  }
 }
 private byte[] entry(File file,Item item,String suffix,int bound)throws IOException{
  try(ZipFile z=new ZipFile(file)){ZipEntry e=z.getEntry(item.id+suffix);if(e==null||e.getSize()<1||e.getSize()>bound)throw new IOException("离线曲谱文件缺失或过大");
   try(InputStream in=z.getInputStream(e);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>bound)throw new IOException("离线曲谱超过大小上限");out.write(b,0,n);}return out.toByteArray();}}
 }
 public byte[] midi(File file,Item item)throws IOException{byte[] data=entry(file,item,".mid",8*1024*1024);if(!hash(data).equals(item.id))throw new IOException("曲谱原文件校验失败");return data;}
 public Score score(File file,Item item)throws IOException{
  if(!item.prepared)throw new IOException("此曲需要先选择声部并改编");
  Score score=Score.parse(new String(entry(file,item,".bt.txt",524288),StandardCharsets.UTF_8),120);
  if(score.count()!=item.events||score.bpm!=item.bpm)throw new IOException("七键谱与目录不一致");return score;
 }
}
