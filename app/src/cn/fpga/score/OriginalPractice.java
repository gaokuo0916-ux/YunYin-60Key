package cn.fpga.score;
import java.io.IOException;
import java.util.*;

/** A selected voice for self-paced practice; source file and pitches stay intact. */
public final class OriginalPractice {
 public final List<Score> parts;public final int notes,missing;public final boolean overlapping;
 private OriginalPractice(List<Score> p,int n,int m,boolean o){parts=Collections.unmodifiableList(p);notes=n;missing=m;overlapping=o;}
 public static int keyIndex60(int code){return code>=37&&code<=96?code-36:0;}
 public static int keyDegree(int code){switch(code){case 61:return 1;case 63:return 2;case 65:return 3;case 66:return 4;case 68:return 5;case 70:return 6;case 72:return 7;default:return 0;}}
 public static OriginalPractice from(OriginalScore original,int voice)throws IOException{
  if(voice<0||voice>=original.parsed.tracks.size())throw new IOException("请选择一个声部");
  List<MusicXmlImport.Note> selected=new ArrayList<>(original.parsed.tracks.get(voice).notes);
  selected.sort(Comparator.comparingDouble(n->n.at));
  List<int[]> events=new ArrayList<>();long end=0,last=0;int notes=0,missing=0;boolean overlap=false;
  double unit=60000.0/original.parsed.bpm;
  for(MusicXmlImport.Note n:selected){
   if(!Double.isFinite(n.at)||!Double.isFinite(n.duration)||n.at<0||n.duration<=0||n.pitch>127||n.pitch< -1)throw new IOException("原谱包含无效的音高或时间");
   long at=Math.round(n.at*unit),finish=Math.round((n.at+n.duration)*unit);last=Math.max(last,finish);
   if(n.pitch<0)continue;
   long length=Math.max(1,finish-at);if(length>65535)throw new IOException("当前试用版单音最长65535毫秒，原谱仍可完整保存；不会截短该音");
   if(at>end)rest(events,at-end);else if(at<end)overlap=true;
   int code=n.pitch+1;events.add(new int[]{code,(int)length});notes++;if(keyIndex60(code)==0)missing++;
   end=Math.max(end,finish);
  }
  if(notes==0)throw new IOException("该声部没有可上传的音符");
  if(last>end)rest(events,last-end);
  List<Score> parts=new ArrayList<>();for(int i=0;i<events.size();i+=Score.CAPACITY)parts.add(Score.pitches(original.parsed.bpm,events.subList(i,Math.min(i+Score.CAPACITY,events.size()))));
  return new OriginalPractice(parts,notes,missing,overlap);
 }
 private static void rest(List<int[]> events,long duration)throws IOException{if(duration>86400000L)throw new IOException("休止过长，请先选择曲谱片段");while(duration>0){int n=(int)Math.min(65535,duration);events.add(new int[]{0,n});duration-=n;}}
}
