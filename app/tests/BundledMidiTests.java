package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import javax.sound.midi.*;

/** Checks real offline files, converted event CRCs, search and corrupt archive boundaries. */
public final class BundledMidiTests {
 static int checks;static void check(boolean v,String why){checks++;if(!v)throw new AssertionError(why);}
 interface Work{void run()throws Exception;}
 static void reject(Work w)throws Exception{try{w.run();}catch(IOException|IllegalArgumentException e){checks++;return;}throw new AssertionError("Accepted invalid library data");}
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),source=root.resolve("vendor/bundled_midi");BundledMidiCatalog catalog=BundledMidiCatalog.read(Files.newInputStream(source.resolve("catalog.tsv")));
  check(catalog.items.size()==18775,"all available MIDI files listed");check(catalog.chineseCount==2301,"positive Chinese matches");check(catalog.preparedCount==7582,"actual prepared score files");
  for(String song:Arrays.asList("跳楼机","晴天","七里香","孤勇者","起风了","第57次取消发送"))check(!catalog.search(song,true).isEmpty(),"Chinese song "+song);
  check(catalog.search("nO_sUcH_tItLe_yy",false).isEmpty(),"empty search");
  Path temp=Files.createTempDirectory(root.resolve("verification"),"bundled_fixture_");File archive;
  try(InputStream in=Files.newInputStream(source.resolve("files.zip"))){archive=catalog.install(in,temp.toFile());}
  int ready=0,independent=0;long noteEvents=0;
  // Keep the ZIP directory resident while verifying every file; otherwise repeatedly
  // closing the final handle reparses the large directory for each of 18,775 entries.
  try(ZipFile directory=new ZipFile(archive)){
  for(int i=0;i<catalog.items.size();i++){
   BundledMidiCatalog.Item item=catalog.items.get(i);byte[] data=catalog.midi(archive,item);check(data.length>14,"actual MIDI bytes");
   if(item.prepared){Score s=catalog.score(archive,item);check(s.count()<=8192,"bounded board score");check(Score.parse(s.protocol(),120).crc==s.crc,"protocol CRC round trip");ready++;noteEvents+=s.count();}
   if(i%199==0){Sequence seq=MidiSystem.getSequence(new ByteArrayInputStream(data));check(seq.getTracks().length>0,"independent JDK MIDI reader accepts sampled original");independent++;}
  }
  }
  check(ready==catalog.preparedCount,"every prepared version present");
  reject(()->BundledMidiCatalog.read(new ByteArrayInputStream("bad\n".getBytes(StandardCharsets.UTF_8))));
  reject(()->catalog.install(new ByteArrayInputStream(new byte[]{1,2,3}),temp.resolve("bad").toFile()));
  // A cache with the right length but altered entry bytes must fail per-file SHA validation.
  BundledMidiCatalog.Item first=catalog.items.get(0);Path fake=temp.resolve("corrupt.zip");
  try(ZipOutputStream z=new ZipOutputStream(Files.newOutputStream(fake))){z.putNextEntry(new ZipEntry(first.id+".mid"));z.write("MThdInvalidFile".getBytes(StandardCharsets.UTF_8));z.closeEntry();}
  reject(()->catalog.midi(fake.toFile(),first));
  LibraryStore library=new LibraryStore(temp.resolve("mine").toFile());BundledMidiCatalog.Item item=catalog.items.stream().filter(x->x.prepared&&x.chinese).findFirst().get();Score s=catalog.score(archive,item);
  LibraryStore.Entry saved=library.save(null,item.song,item.source(),s);check(library.list().get(0).score.crc==s.crc,"imported actual score persists");library.delete(saved.id);check(library.list().isEmpty(),"delete does not affect bundled originals");
  System.out.println("PASS bundled MIDI: "+checks+" checks; "+catalog.items.size()+" real MIDI hashes, "+ready+" seven-key CRC scores ("+noteEvents+" events), "+independent+" independent JDK reader samples; Chinese search, cache corruption and library save/delete checked.");
 }
}
