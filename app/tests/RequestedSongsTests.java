package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.*;

/** Actual original MIDI -> production parser -> phone persistence -> native upload. */
public final class RequestedSongsTests {
 static int checks;static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]);BundledMidiCatalog c=BundledMidiCatalog.read(Files.newInputStream(root.resolve("vendor/bundled_midi/catalog.tsv")));
  check(c.items.size()==18775,"no duplicate metadata/assets");check(c.chineseCount==2301,"five corrected Chinese entries");
  List<BundledMidiCatalog.Item> list=c.search("",true);String[] titles={"没有共产党就没有新中国","歌唱祖国","我爱你中国","茉莉花","送别"};
  File archive=root.resolve("vendor/bundled_midi/files.zip").toFile();
  Path temp=Files.createTempDirectory(root.resolve("verification"),"requested_songs_");OriginalScoreStore store=new OriginalScoreStore(temp.toFile());
  for(int i=0;i<5;i++){
   BundledMidiCatalog.Item item=list.get(i);check(item.song.equals(titles[i])&&BundledMidiCatalog.featured(item.id),"featured order "+titles[i]);
   check(c.search(titles[i],true).get(0).id.equals(item.id),"search opens chosen original");
   byte[] bytes=c.midi(archive,item);check(BundledMidiCatalog.hash(bytes).equals(item.id),"actual MIDI hash");
   check(MidiSystem.getSequence(new ByteArrayInputStream(bytes)).getTracks().length>0,"independent JDK parser");
   OriginalScore original=OriginalScore.read(bytes,item.title);check(original.noteCount>0&&original.parsed.tracks.size()==item.tracks,"production original parser");
   OriginalPractice plan=OriginalPractice.from(original,item.track);check(plan.notes>0&&!plan.parts.isEmpty(),"native instrument plan");
   int musical=0;for(Score score:plan.parts){check(score.nativePitch&&score.count()<=8192,"bounded full pitch format");check(Score.parse(score.source(),score.bpm).crc==score.crc,"native upload CRC");for(int n=0;n<score.count();n++)if(score.degree(n)>0)musical++;}
   check(musical==plan.notes,"all chosen voice notes retained");
   OriginalScoreStore.Entry saved=store.save(null,item.song,item.source(),original);OriginalScore loaded=store.load(saved);check(Arrays.equals(bytes,loaded.bytes()),"phone save/export bytes exact");
   check(loaded.noteCount==original.noteCount,"all other voices retained");
   System.out.println("SONG "+item.song+" sha="+item.id+" notes="+original.noteCount+" tracks="+item.tracks+" suggestedVoice="+item.track+" nativeNotes="+plan.notes+" missing60="+plan.missing+" voice="+original.parsed.tracks.get(item.track).name);
  }
  check(store.list().size()==5,"five documents coexist");check(c.search("不存在的歌曲_test_yy",true).isEmpty(),"search unaffected");
  if(args.length>1){
   List<String> rows=new ArrayList<>();rows.add(Integer.toString(list.size()));
   for(BundledMidiCatalog.Item i:list.subList(0,Math.min(60,list.size())))rows.add(i.id+"\t"+i.title+"\t"+(BundledMidiCatalog.featured(i.id)?"精选练习":"华语筛选")+" · 完整 MIDI 原谱");
   Files.write(Paths.get(args[1]),rows,java.nio.charset.StandardCharsets.UTF_8);
  }
  System.out.println("PASS requested songs "+checks+" checks: five real originalMIDI hashes/JDK parsing/phone persistence/native upload preparation; no Android or BLE hardware claim");
 }
}
