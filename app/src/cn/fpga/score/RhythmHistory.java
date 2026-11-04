package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
/** At most 100 completed snapshots; atomic replacement keeps the previous file on failure. */
public final class RhythmHistory {
 public static final class Entry {
  public final long time;public final RhythmStatus result;
  Entry(long t,RhythmStatus s){time=t;result=s;}
 }
 private final File file;private final List<Entry> rows=new ArrayList<>();
 public RhythmHistory(File f)throws IOException{
  file=f;
  if(!f.exists())return;
  if(f.length()>65536)throw new IOException("挑战记录文件过大");
  for(String line:Files.readAllLines(f.toPath(),StandardCharsets.UTF_8)){
   String[] p=line.split("\\t",-1);
   try{if(p.length!=2)throw new IOException("格式错误");long time=Long.parseLong(p[0]);RhythmStatus s=new RhythmStatus(p[1]);if(s.state!=5||time<=0)throw new IOException("非结算记录");rows.add(new Entry(time,s));}
   catch(IOException|IllegalArgumentException invalid){throw new IOException("挑战历史损坏，原文件已保留",invalid);}
  }
  if(rows.size()>100)throw new IOException("挑战记录超过容量");
 }
 public synchronized List<Entry> entries(){return new ArrayList<>(rows);}
 public synchronized void add(long time,RhythmStatus s)throws IOException{
  if(s==null||s.state!=5||!s.enabled||s.round==0||time<=0)throw new IOException("仅保存琴端已完成的挑战");
  List<Entry> next=new ArrayList<>(rows);next.add(0,new Entry(time,s));if(next.size()>100)next.remove(next.size()-1);
  StringBuilder data=new StringBuilder();for(Entry e:next)data.append(e.time).append('\t').append(e.result.raw).append('\n');
  File temp=new File(file.getPath()+".partial");
  try{Files.write(temp.toPath(),data.toString().getBytes(StandardCharsets.UTF_8));
   try{Files.move(temp.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
   catch(AtomicMoveNotSupportedException unsupported){Files.move(temp.toPath(),file.toPath(),StandardCopyOption.REPLACE_EXISTING);}
   rows.clear();rows.addAll(next);
  }finally{Files.deleteIfExists(temp.toPath());}
 }
}
