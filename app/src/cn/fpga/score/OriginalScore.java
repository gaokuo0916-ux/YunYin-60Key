package cn.fpga.score;
import java.io.*;
import java.util.*;

/** A complete source document. Importing never quantizes, transposes or removes notes. */
public final class OriginalScore {
 private final byte[] source;
 public final String filename;public final MusicXmlImport parsed;public final int noteCount;
 private OriginalScore(byte[] bytes,String name,MusicXmlImport music){source=bytes.clone();filename=name;parsed=music;int n=0;for(MusicXmlImport.Track t:music.tracks)for(MusicXmlImport.Note v:t.notes)if(v.pitch>=0)n++;noteCount=n;}
 public static OriginalScore read(byte[] bytes,String name)throws Exception{
  ScoreWebImport.Kind kind=ScoreWebImport.classify(bytes,null,name);
  MusicXmlImport parsed;
  if(kind==ScoreWebImport.Kind.MIDI)parsed=MidiImport.read(bytes);
  else if(kind==ScoreWebImport.Kind.XML||kind==ScoreWebImport.Kind.MXL)parsed=MusicXmlImport.read(bytes);
  else throw new IOException("请选择 MIDI、MusicXML 或 MXL 原谱文件");
  String filename=name==null?"原谱":name.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]","_");if(filename.length()>190)filename=filename.substring(0,190);
  String ext=kind==ScoreWebImport.Kind.MIDI?".mid":kind==ScoreWebImport.Kind.MXL?".mxl":".musicxml";
  if(!filename.toLowerCase(Locale.ROOT).endsWith(ext)&&!(kind==ScoreWebImport.Kind.MIDI&&filename.toLowerCase(Locale.ROOT).endsWith(".midi"))&&!(kind==ScoreWebImport.Kind.XML&&filename.toLowerCase(Locale.ROOT).endsWith(".xml")))filename+=ext;
  return new OriginalScore(bytes,filename,parsed);
 }
 public byte[] bytes(){return source.clone();}
 public String sha256()throws IOException{return BundledMidiCatalog.hash(source);}
 public static String pitch(int midi){if(midi<0)return "休止";String[] names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};return names[Math.floorMod(midi,12)]+(Math.floorDiv(midi,12)-1);}
}
