package cn.fpga.score;
import java.io.*;import java.nio.charset.StandardCharsets;import java.nio.file.*;import java.util.*;
public final class NativeTrialTests{
 static int checks=0;
 static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
 interface Throwing{void run()throws Exception;}
 static void rejected(Throwing action,String label)throws Exception{boolean failed=false;try{action.run();}catch(Exception e){failed=true;}check(failed,label);}
 static OriginalScore xml(String notes)throws Exception{return OriginalScore.read(("<score-partwise version=\"3.1\"><part-list><score-part id=\"P1\"><part-name>Melody</part-name></score-part></part-list><part id=\"P1\"><measure number=\"1\"><attributes><divisions>2</divisions></attributes>"+notes+"</measure></part></score-partwise>").getBytes(StandardCharsets.UTF_8),"test.musicxml");}
 static String n(String step,String alter,int octave,int duration){return "<note><pitch><step>"+step+"</step><alter>"+alter+"</alter><octave>"+octave+"</octave></pitch><duration>"+duration+"</duration></note>";}
 static class Fake implements Uploader.Link{
  Deque<String> replies=new ArrayDeque<>();List<String> sent=new ArrayList<>();Score score;int caps=0xffb;boolean nativeFlag=true,badCheck=false,missing=true;int at=1,keys=0,state=2;
  Fake(Score s){score=s;}
  public void clear(){replies.clear();}
  public void send(String s){sent.add(s);if(s.equals("ABORT"))replies.add("OK");else if(s.equals("PING"))replies.add("PONG");else if(s.equals("FEAT"))replies.add(String.format("F24 %04X FFFF",caps));else if(s.equals("CAP"))replies.add("CAP 8192");else if(s.startsWith("MBEGIN ")||s.startsWith("BEGIN "))replies.add("READY");else if(s.startsWith("MEND ")||s.startsWith("END "))replies.add("SAVED");else if(s.equals("STATUS"))replies.add("S=0 V=1 U=0 E=0");else if(s.equals("CHECK"))replies.add(String.format("C %04X %04X",score.count(),score.crc^(badCheck?1:0)));else if(s.equals("MINFO"))replies.add(nativeFlag?String.format("N 1 1 %04X %02X 1 %d",at,missing?62:61,missing?1:0):"N 0 1 0000 00 1 0");else if(s.equals("STATE"))replies.add(String.format("T %04X %d %02X 0000 00FA 0000 0078 1 1",at,state,keys));else if(s.equals("SKIP")){at++;missing=false;replies.add("OK");}}
  public String receive(long timeout){return replies.pollFirst();}
 }
 public static void main(String[] args)throws Exception{
  List<int[]> every=new ArrayList<>();for(int i=0;i<128;i++)every.add(new int[]{i+1,250+i});Score all=Score.pitches(120,every);check(all.nativePitch&&all.count()==128,"all pitches");check(Score.parse(all.source(),120).crc==all.crc,"native text round trip");
  for(int i=0;i<128;i++)check(all.degree(i)==i+1&&all.units(i)==250+i,"no pitch or octave folding");
  check(!new Score(120,Arrays.asList(new int[]{1,4})).nativePitch,"legacy format unchanged");rejected(()->new Score(120,Arrays.asList(new int[]{61,250})),"legacy rejects native data");rejected(()->Score.pitches(120,Arrays.asList(new int[]{129,1})),"pitch bound");
  OriginalScore doc=xml(n("C","0",4,1)+"<note><rest/><duration>1</duration></note>"+n("C","1",4,1)+n("C","0",5,1)+n("D","0",4,2));String before=doc.sha256();OriginalPractice p=OriginalPractice.from(doc,0);Score s=p.parts.get(0);
  check(doc.sha256().equals(before)&&doc.noteCount==4,"source unchanged");check(s.count()==5&&p.notes==4&&p.missing==0,"notes plus real rest");int[] codes={61,0,62,73,63},times={250,250,250,250,500};for(int i=0;i<5;i++)check(s.degree(i)==codes[i]&&s.units(i)==times[i],"exact original pitch and millisecond time");
  new Uploader(new Fake(s),10).upload(s,(a,b,c)->{});checks++;
  Fake old=new Fake(s);old.caps=0x7fb;rejected(()->new Uploader(old,10).upload(s,(a,b,c)->{}),"old firmware rejected before native upload");check(old.sent.stream().noneMatch(x->x.startsWith("MBEGIN")),"old firmware not sent unknown upload");
  Fake wrong=new Fake(s);wrong.badCheck=true;rejected(()->new Uploader(wrong,10).upload(s,(a,b,c)->{}),"wrong board CRC never marked saved");
  Fake format=new Fake(s);format.nativeFlag=false;rejected(()->new Uploader(format,10).upload(s,(a,b,c)->{}),"wrong committed format rejected");
  Fake skip=new Fake(s);new StudioProtocol(skip).skipMissing();check(skip.at==2&&skip.sent.contains("SKIP"),"skip confirmed by board index");
  Fake paused=new Fake(s);paused.state=6;rejected(()->new StudioProtocol(paused).skipMissing(),"paused skip blocked");check(!paused.sent.contains("SKIP"),"paused skip not sent");
  Fake supported=new Fake(s);supported.missing=false;rejected(()->new StudioProtocol(supported).skipMissing(),"playable target skip blocked");
  Fake held=new Fake(s);held.keys=1;rejected(()->new StudioProtocol(held).skipMissing(),"held key skip blocked");
  rejected(()->new StudioProtocol.Pitch("N 1 1 0001 81 1 1"),"corrupt native pitch rejected");rejected(()->new StudioProtocol.Pitch("N 1 1 0001 3D 1 1"),"false missing indicator rejected");
  StringBuilder longXml=new StringBuilder();for(int i=0;i<9001;i++)longXml.append(n("C",i%2==0?"0":"1",4,1));OriginalPractice many=OriginalPractice.from(xml(longXml.toString()),0);check(many.parts.size()==2&&many.parts.get(0).count()==8192&&many.parts.get(1).count()==809,"long original split without dropping notes");
  int count=0;for(Score part:many.parts)for(int i=0;i<part.count();i++){check(part.degree(i)==(count%2==0?61:62),"every original pitch retained across segments");count++;}
  Path fixtures=Paths.get(args[0]).getParent().resolve("verification/native_trial_20261024/real_midis");
  try(java.util.stream.Stream<Path> files=Files.list(fixtures)){for(Path f:(Iterable<Path>)files::iterator){OriginalScore real=OriginalScore.read(Files.readAllBytes(f),f.getFileName().toString());String hash=real.sha256();for(int t=0;t<real.parsed.tracks.size();t++){OriginalPractice plan=OriginalPractice.from(real,t);List<Integer> pitches=new ArrayList<>();for(MusicXmlImport.Note note:real.parsed.tracks.get(t).notes)if(note.pitch>=0)pitches.add(note.pitch);pitches.clear();List<MusicXmlImport.Note> sorted=new ArrayList<>(real.parsed.tracks.get(t).notes);sorted.sort(Comparator.comparingDouble(x->x.at));for(MusicXmlImport.Note note:sorted)if(note.pitch>=0)pitches.add(note.pitch);int i=0;for(Score part:plan.parts)for(int j=0;j<part.count();j++)if(part.degree(j)>0)check(part.degree(j)-1==pitches.get(i++),"real MIDI pitch stream");check(i==pitches.size()&&real.sha256().equals(hash),"real voice and original source retained");}System.out.println("Real native fixture: "+f.getFileName()+" · "+real.noteCount+" notes");}}
  System.out.println("PASS NativeTrialTests "+checks+" checks; full pitches, real source immutability, timing/rests, 8192 segmentation, firmware gates, committed CRC and guarded manual skip");
 }
}
