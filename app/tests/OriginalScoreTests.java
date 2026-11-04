package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.*;

public final class OriginalScoreTests {
 static int checks;static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
 interface Work{void run()throws Exception;}
 static void reject(Work work)throws Exception{try{work.run();}catch(IOException|IllegalArgumentException e){checks++;return;}throw new AssertionError("Accepted corrupt source");}
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),temp=Files.createTempDirectory(root.resolve("verification"),"original_fixture_");OriginalScoreStore store=new OriginalScoreStore(temp.resolve("originals").toFile());
  int pitches=0;
  for(String id:Arrays.asList("001","064","201","516","751")){
   byte[] raw=Files.readAllBytes(root.resolve("verification/midi_samples/"+id+".mid"));OriginalScore source=OriginalScore.read(raw,id);
   OriginalScoreStore.Entry entry=store.save(null,id.equals("516")?"晴天 · 周杰伦":id,"POP909 real MIDI regression",source);OriginalScore loaded=store.load(entry);
   check(Arrays.equals(raw,loaded.bytes()),"byte-for-byte preserved MIDI, including original timing, all tracks and metadata");
   check(MidiSystem.getSequence(new ByteArrayInputStream(loaded.bytes())).getTracks().length>0,"independent JDK reader opens exported bytes");
   check(source.parsed.tracks.size()==loaded.parsed.tracks.size(),"every source voice retained");
   for(int t=0;t<source.parsed.tracks.size();t++){
    List<MusicXmlImport.Note> a=source.parsed.tracks.get(t).notes,b=loaded.parsed.tracks.get(t).notes;check(a.size()==b.size(),"all events in each voice retained");
    for(int n=0;n<a.size();n++){check(a.get(n).pitch==b.get(n).pitch&&a.get(n).at==b.get(n).at&&a.get(n).duration==b.get(n).duration,"full pitch, octave, onset and duration preserved");pitches++;}
   }
   if(id.equals("516")){
    String old=source.parsed.draft(0,source.parsed.tonic,new ArrayList<>());check(old.chars().filter(c->c=='?').count()==16,"screenshot's 16 unsupported seven-key events reproduced");
    check(source.noteCount==2296&&entry.notes==2296&&entry.tracks==3,"Qing Tian saves all 2296 notes across three voices");
    check(Arrays.equals(source.bytes(),raw),"no conversion needed to save chromatic Qing Tian");
    OriginalScoreStore.Entry renamed=store.save(entry.id,"晴天原谱",entry.origin,loaded);check(Arrays.equals(store.load(renamed).bytes(),raw),"rename leaves original untouched");
   }
   byte[] modified=source.bytes();modified[0]^=1;check(Arrays.equals(source.bytes(),raw),"external byte array cannot mutate stored document");
  }
  for(String filename:Arrays.asList("birthday.mxl","minuet.mxl","canon.mxl")){
   Path f=root.resolve("verification/v2_samples/"+filename);
   byte[] raw=Files.readAllBytes(f);OriginalScore source=OriginalScore.read(raw,filename);OriginalScoreStore.Entry e=store.save(null,filename,"real MusicXML fixture",source);check(Arrays.equals(raw,store.load(e).bytes()),"MXL preserved without filtering voices");
  }
  StringBuilder xml=new StringBuilder("<score-partwise><part id='P1'><measure><attributes><divisions>1</divisions></attributes>");
  for(int i=0;i<9001;i++)xml.append("<note><pitch><step>C</step><alter>1</alter><octave>5</octave></pitch><duration>1</duration></note>");
  xml.append("</measure></part></score-partwise>");OriginalScore longSource=OriginalScore.read(xml.toString().getBytes("UTF-8"),"Long full-pitch score.musicxml");
  OriginalScoreStore.Entry longEntry=store.save(null,"Long original","test",longSource);check(store.load(longEntry).noteCount==9001,"original import is not restricted to an 8192-event practice slot");
  check(OriginalScore.pitch(61).equals("C#4")&&OriginalScore.pitch(73).equals("C#5"),"chromatic note and octave shown distinctly");
  List<OriginalScoreStore.Entry> all=store.list();check(all.size()>=5,"metadata index retains complete originals");OriginalScoreStore.Entry e=all.get(0);
  try(RandomAccessFile f=new RandomAccessFile(temp.resolve("originals/"+e.id+".original").toFile(),"rw")){f.seek(f.length()-1);int v=f.read();f.seek(f.length()-1);f.write(v^1);}
  reject(()->store.load(e));reject(()->store.delete("../../escape"));
  reject(()->OriginalScore.read("not a score".getBytes("UTF-8"),"fake.mid"));
  store.delete(e.id);check(store.list().stream().noneMatch(v->v.id.equals(e.id)),"original delete only removes selected source");
  LibraryStore legacy=new LibraryStore(temp.resolve("legacy").toFile());Score old=Score.parse("123",120);legacy.save(null,"Existing practice","old",old);check(legacy.list().get(0).score.crc==old.crc,"legacy practice data stays readable");
  System.out.println("PASS original score: "+checks+" checks; "+pitches+" real MIDI notes retain pitch/octave/onset/duration; Qing Tian's 16 chromatic events no longer block source save; five MIDI and three MXL sources, 9001-note original, export bytes, all tracks, rename, corruption and legacy coexistence checked.");
 }
}
