package cn.fpga.score;
import java.util.*;

/** A phone-side editable draft can exceed a single FPGA slot. */
public final class SongDraft {
    public final int bpm;
    public final List<int[]> notes;
    private SongDraft(int speed,List<int[]> events) { bpm=speed;notes=events; }
    public static String importText(String source,int defaultBpm) {
        String clean=source.replace("\uFEFF", "").replace("\r", "").trim();
        if(clean.startsWith("BEGIN "))return Score.parse(clean,defaultBpm).source();
        if(clean.contains(",") || clean.startsWith("BPM=")){
            SongDraft draft=parse(clean);StringBuilder csv=new StringBuilder("BPM="+draft.bpm+"\n");
            for(int[] n:draft.notes)csv.append(n[0]).append(',').append(n[1]).append('\n');return csv.toString();
        }
        StringBuilder digits=new StringBuilder();for(String line:clean.split("\n"))digits.append(line.split("#",2)[0]);
        String value=digits.toString().replaceAll("[\\s|]", "");
        if(!value.matches("[0-7]{1,10000}"))throw new IllegalArgumentException("简谱需为 0～7；复杂曲谱请导入 MusicXML 或用图片识谱后校对");
        StringBuilder csv=new StringBuilder("BPM="+defaultBpm+"\n");for(char c:value.toCharArray())csv.append(c).append(",4\n");
        parse(csv.toString());return csv.toString();
    }
    public static SongDraft parse(String source) {
        int bpm=120;boolean tempo=false;List<int[]> notes=new ArrayList<>();
        for(String raw:source.replace("\r","").replace("\uFEFF","").split("\n")) {
            String line=raw.split("#",2)[0].trim();if(line.isEmpty())continue;
            if(line.startsWith("BPM=")) {
                if(tempo || !notes.isEmpty())throw new IllegalArgumentException("BPM 只能在开头出现一次");
                bpm=Integer.parseInt(line.substring(4).trim());tempo=true;
            } else {
                String[] n=line.split(",",-1);
                if(n.length!=2 || !n[0].trim().matches("[0-7]") || !n[1].trim().matches("[0-9]{1,2}"))
                    throw new IllegalArgumentException("第 "+(notes.size()+1)+" 项需校正为 音符,时值；问号表示尚未确认");
                int units=Integer.parseInt(n[1].trim());if(units<1 || units>64)throw new IllegalArgumentException("时值范围为 1～64");
                notes.add(new int[]{Integer.parseInt(n[0].trim()),units});
                if(notes.size()>10000)throw new IllegalArgumentException("手机曲谱暂限 10000 个事件，请分文件导入");
            }
        }
        if(bpm<20 || bpm>300 || notes.isEmpty())throw new IllegalArgumentException("速度需为 20～300，至少一个音符");
        return new SongDraft(bpm,notes);
    }
    public List<Score> segments() {
        List<Score> result=new ArrayList<>();
        for(int i=0;i<notes.size();i+=Score.CAPACITY)result.add(new Score(bpm,notes.subList(i,Math.min(i+Score.CAPACITY,notes.size()))));
        return result;
    }
}
