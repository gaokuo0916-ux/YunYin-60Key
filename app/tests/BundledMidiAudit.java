package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
/** Production parser audit of every real, downloaded MIDI, not synthetic metadata. */
public final class BundledMidiAudit {
 static String clean(String s){return s.replace('\t',' ').replace('\r',' ').replace('\n',' ');}
 static double rating(MusicXmlImport.Track t){
  String name=t.name.toLowerCase(Locale.ROOT);List<MusicXmlImport.Note> ns=new ArrayList<>(t.notes);ns.sort(Comparator.comparingDouble(n->n.at));
  int simultaneous=0;double last=-1,mean=0;for(MusicXmlImport.Note n:ns){if(Math.abs(n.at-last)<.0001)simultaneous++;last=n.at;mean+=n.pitch;}
  double score=Math.min(500,ns.size())/20.0-80.0*simultaneous/Math.max(1,ns.size())+mean/Math.max(1,ns.size())/12;
  if(name.contains("melody")||name.contains("旋律")||name.contains("vocal"))score+=100;
  if(name.contains("bass")||name.contains("伴奏")||name.contains("left")||name.contains("低音"))score-=70;
  if(ns.size()<20)score-=100;return score;
 }
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]);int good=0,bad=0,convertible=0;long notes=0;
  try(ZipFile z=new ZipFile(root.resolve("app/vendor/bundled_midi/files.zip").toFile());PrintWriter out=new PrintWriter(Files.newBufferedWriter(root.resolve("verification/chinese_import_20261023/parser_audit.tsv"),StandardCharsets.UTF_8));ZipOutputStream practice=new ZipOutputStream(Files.newOutputStream(root.resolve("verification/chinese_import_20261023/practice.zip")))){
   Enumeration<? extends ZipEntry> entries=z.entries();
   while(entries.hasMoreElements()){
    ZipEntry e=entries.nextElement();String sha=e.getName().replace(".mid","");
    try{
     byte[] data;try(InputStream in=z.getInputStream(e)){data=in.readAllBytes();}
     MusicXmlImport p=MidiImport.read(data);int best=0,count=0;
     for(int i=0;i<p.tracks.size();i++){count+=p.tracks.get(i).notes.size();if(rating(p.tracks.get(i))>rating(p.tracks.get(best)))best=i;}
     int tonic=p.tonic,miss=Integer.MAX_VALUE;Set<Integer> scale=new HashSet<>(Arrays.asList(0,2,4,5,7,9,11));
     for(int k=0;k<12;k++){int n=0;for(MusicXmlImport.Note v:p.tracks.get(best).notes)if(!scale.contains(Math.floorMod(v.pitch-k,12)))n++;if(n<miss||(n==miss&&k==p.tonic)){miss=n;tonic=k;}}
     int events=-1;String draftError="";
     try{List<String> notices=new ArrayList<>();String draft=p.draft(best,tonic,notices);if(!draft.contains("?")){SongDraft parsed=SongDraft.parse(draft);List<Score> segments=parsed.segments();events=parsed.notes.size();if(segments.size()==1){practice.putNextEntry(new ZipEntry(sha+".bt.txt"));practice.write(segments.get(0).protocol().getBytes(StandardCharsets.UTF_8));practice.closeEntry();convertible++;}}}
     catch(Exception x){draftError=clean(x.getMessage()==null?x.toString():x.getMessage());}
     out.println(sha+"\tOK\t"+p.tracks.size()+"\t"+count+"\t"+p.bpm+"\t"+best+"\t"+tonic+"\t"+miss+"\t"+events+"\t"+clean(p.tracks.get(best).name)+"\t"+draftError);good++;notes+=count;
    }catch(Exception x){bad++;out.println(sha+"\tERROR\t"+clean(x.toString()));}
    if((good+bad)%3000==0)System.out.println("Audited "+(good+bad)+" MIDI files");
   }
  }
  System.out.println("PASS downloaded MIDI audit: "+good+" parse, "+bad+" rejected, "+convertible+" convertible suggested tracks, "+notes+" notes.");
 }
}
