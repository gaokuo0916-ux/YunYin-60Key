package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Separate source-document storage; existing seven-key practice scores are not overwritten. */
public final class OriginalScoreStore {
 public static final class Entry {
  public final String id,title,origin,filename,sha256;public final int notes,tracks,bpm,size;public final long modified;
  Entry(String key,String name,String url,String file,String sha,int count,int parts,int speed,int bytes,long time){id=key;title=name;origin=url;filename=file;sha256=sha;notes=count;tracks=parts;bpm=speed;size=bytes;modified=time;}
 }
 private final File root;
 public OriginalScoreStore(File directory)throws IOException{root=directory;if(!root.isDirectory()&&!root.mkdirs())throw new IOException("无法建立原谱曲库");}
 private File file(String id){if(!id.matches("[a-f0-9-]{36}"))throw new IllegalArgumentException("原谱编号无效");return new File(root,id+".original");}
 private Entry header(DataInputStream in,String id,long time)throws IOException{
  if(in.readInt()!=0x59594f31)throw new IOException("原谱存储版本无效");String title=in.readUTF(),origin=in.readUTF(),name=in.readUTF(),hash=in.readUTF();int notes=in.readInt(),tracks=in.readInt(),bpm=in.readInt(),size=in.readInt();
  if(title.isEmpty()||title.length()>160||origin.length()>2000||name.length()>200||!hash.matches("[a-f0-9]{64}")||notes<0||tracks<1||size<1||size>8*1024*1024)throw new IOException("原谱存储头无效");
  return new Entry(id,title,origin,name,hash,notes,tracks,bpm,size,time);
 }
 public synchronized Entry save(String id,String title,String origin,OriginalScore score)throws IOException{
  if(id==null)id=UUID.randomUUID().toString();title=title.trim();if(title.isEmpty()||title.length()>160)throw new IllegalArgumentException("曲名需为 1～160 个字符");if(origin.length()>2000)origin=origin.substring(0,2000);
  File target=file(id),temp=new File(root,id+".tmp");byte[] bytes=score.bytes();String hash=score.sha256();
  try(FileOutputStream stream=new FileOutputStream(temp);DataOutputStream out=new DataOutputStream(stream)){out.writeInt(0x59594f31);out.writeUTF(title);out.writeUTF(origin);out.writeUTF(score.filename);out.writeUTF(hash);out.writeInt(score.noteCount);out.writeInt(score.parsed.tracks.size());out.writeInt(score.parsed.bpm);out.writeInt(bytes.length);out.write(bytes);out.flush();stream.getFD().sync();}
  try{Files.move(temp.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(AtomicMoveNotSupportedException e){Files.move(temp.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);}
  return new Entry(id,title,origin,score.filename,hash,score.noteCount,score.parsed.tracks.size(),score.parsed.bpm,bytes.length,target.lastModified());
 }
 public synchronized List<Entry> list(){List<Entry> out=new ArrayList<>();File[] files=root.listFiles();if(files!=null)for(File f:files)if(f.getName().matches("[a-f0-9-]{36}\\.original"))try(DataInputStream in=new DataInputStream(new FileInputStream(f))){Entry e=header(in,f.getName().replace(".original",""),f.lastModified());if(in.available()==e.size)out.add(e);}catch(IOException ignored){}out.sort((a,b)->Long.compare(b.modified,a.modified));return out;}
 public synchronized OriginalScore load(Entry entry)throws Exception{
  try(DataInputStream in=new DataInputStream(new FileInputStream(file(entry.id)))){Entry e=header(in,entry.id,entry.modified);byte[] bytes=new byte[e.size];in.readFully(bytes);if(in.read()!=-1||!BundledMidiCatalog.hash(bytes).equals(e.sha256))throw new IOException("原谱文件校验失败");return OriginalScore.read(bytes,e.filename);}
 }
 public synchronized void delete(String id)throws IOException{Files.deleteIfExists(file(id).toPath());}
}
