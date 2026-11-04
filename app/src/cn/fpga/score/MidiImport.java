package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Bounded SMF 0/1 reader. Converts note data only; never renders or plays PCM. */
public final class MidiImport {
    private static final class Cursor {
        final byte[] data; final int end; int pos;
        Cursor(byte[] bytes,int from,int to){data=bytes;pos=from;end=to;}
        int byteValue()throws IOException{if(pos>=end)throw new IOException("MIDI 数据截断");return data[pos++]&255;}
        int word()throws IOException{return byteValue()*256+byteValue();}
        long integer()throws IOException{return ((long)word()<<16)|word();}
        long variable()throws IOException{long value=0;for(int n=0;n<4;n++){int b=byteValue();value=(value<<7)|(b&127);if((b&128)==0)return value;}throw new IOException("MIDI 可变长数字超过 4 字节");}
        byte[] bytes(int n)throws IOException{if(n<0||n>end-pos)throw new IOException("MIDI 事件长度越界");byte[] out=Arrays.copyOfRange(data,pos,pos+n);pos+=n;return out;}
    }
    private static final class Raw {long at,end;int pitch;Raw(long t,int p){at=t;pitch=p;}}
    private static final class Tempo {long tick;int micros;double seconds;Tempo(long t,int m){tick=t;micros=m;}}
    private static final class Part {String name;final List<Raw> notes=new ArrayList<>();Part(String n){name=n;}}
    public static MusicXmlImport read(byte[] bytes)throws IOException{
        if(bytes.length>8*1024*1024)throw new IOException("MIDI 超过 8 MB");
        Cursor in=new Cursor(bytes,0,bytes.length);
        if(in.integer()!=0x4d546864L)throw new IOException("文件不是标准 MIDI");
        long header=in.integer();if(header<6||header>in.end-in.pos)throw new IOException("MIDI 头长度无效");
        int format=in.word(),tracks=in.word(),division=in.word();in.bytes((int)header-6);
        if(format>1||tracks<1||tracks>256||(format==0&&tracks!=1))throw new IOException("仅支持 MIDI 格式 0/1，最多 256 个音轨");
        if(division==0||(division&0x8000)!=0)throw new IOException("当前仅支持 PPQN 拍时 MIDI，请重新导出");
        List<Part> parts=new ArrayList<>();List<Tempo> tempos=new ArrayList<>();tempos.add(new Tempo(0,500000));
        int events=0,noteCount=0,key=-1;boolean percussion=false,pedal=false,unfinished=false;
        for(int ti=0;ti<tracks;ti++){
            if(in.integer()!=0x4d54726bL)throw new IOException("缺少 MIDI MTrk 音轨");
            long length=in.integer();if(length>in.end-in.pos)throw new IOException("MIDI 音轨长度越界");
            Cursor c=new Cursor(bytes,in.pos,in.pos+(int)length);in.pos=c.end;
            Map<Integer,Part> channels=new LinkedHashMap<>();Map<Integer,Deque<Raw>> active=new HashMap<>();
            String name="音轨 "+(ti+1);long tick=0;int running=0;
            while(c.pos<c.end){
                if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("解析已取消");
                if(++events>250000)throw new IOException("MIDI 事件过多，请先选择单独旋律导出");
                tick+=c.variable();if(tick>Integer.MAX_VALUE)throw new IOException("MIDI 时长过长");
                int status=c.byteValue();
                if(status<128){if(running==0)throw new IOException("MIDI running status 缺失");c.pos--;status=running;}
                if(status==255){running=0;int type=c.byteValue(),n=(int)c.variable();byte[] meta=c.bytes(n);
                    if(type==3){name=new String(meta,StandardCharsets.UTF_8).replace('\u0000',' ').trim();if(name.isEmpty())name="音轨 "+(ti+1);}
                    if(type==81){if(n!=3)throw new IOException("MIDI 速度事件长度错误");int micros=((meta[0]&255)<<16)|((meta[1]&255)<<8)|(meta[2]&255);if(micros==0||tempos.size()>8192)throw new IOException("MIDI 速度无效或变速事件过多");tempos.add(new Tempo(tick,micros));}
                    if(type==89&&n>=2&&key<0){int fifths=meta[0];if(fifths>=-7&&fifths<=7)key=Math.floorMod(fifths*7,12);}
                    if(type==47)break;
                    continue;
                }
                if(status==240||status==247){running=0;c.bytes((int)c.variable());continue;}
                if(status<128||status>=240)throw new IOException("不支持的 MIDI 系统事件");
                running=status;int channel=status&15,kind=status&240;int a=c.byteValue();int b=(kind==192||kind==208)?0:c.byteValue();
                if(a>127||b>127)throw new IOException("MIDI 数据字节越界");
                if(channel==9){if(kind==144&&b>0)percussion=true;continue;}
                if(kind==176&&a==64)pedal=true;
                if(kind==144&&b>0){
                    Part part=channels.get(channel);if(part==null){part=new Part(name+" · 通道 "+(channel+1));channels.put(channel,part);parts.add(part);}
                    Raw note=new Raw(tick,a);part.notes.add(note);active.computeIfAbsent(channel*128+a,k->new ArrayDeque<>()).addLast(note);
                    if(++noteCount>50000)throw new IOException("旋律音符过多，请分段导出");
                }else if(kind==128||(kind==144&&b==0)){
                    Deque<Raw> queue=active.get(channel*128+a);if(queue!=null&&!queue.isEmpty())queue.removeFirst().end=tick;
                }
            }
            for(Deque<Raw> queue:active.values())for(Raw note:queue){note.end=Math.max(note.at+division/4,tick);unfinished=true;}
            for(Map.Entry<Integer,Part> entry:channels.entrySet())entry.getValue().name=name+" · 通道 "+(entry.getKey()+1);
        }
        if(parts.isEmpty())throw new IOException("MIDI 中没有可用的旋律音符（鼓轨不作为七键旋律）");
        tempos.sort(Comparator.comparingLong(t->t.tick));
        List<Tempo> map=new ArrayList<>();for(Tempo t:tempos){if(!map.isEmpty()&&map.get(map.size()-1).tick==t.tick)map.set(map.size()-1,t);else map.add(t);}
        for(int i=1;i<map.size();i++){Tempo p=map.get(i-1),t=map.get(i);t.seconds=p.seconds+(t.tick-p.tick)*(p.micros/1000000.0)/division;}
        int bpm=(int)Math.round(60000000.0/map.get(0).micros);MusicXmlImport result=new MusicXmlImport("导入 MIDI");
        result.bpm=Math.max(20,Math.min(300,bpm));
        if(result.bpm!=bpm)result.warnings.add("原速度超出 20～300 BPM，已调整到支持范围，请核对");
        for(Part part:parts){MusicXmlImport.Track out=new MusicXmlImport.Track(part.name);for(Raw n:part.notes){
            if(n.end<=n.at)continue;double at=seconds(n.at,map,division)*result.bpm/60.0,end=seconds(n.end,map,division)*result.bpm/60.0;
            out.notes.add(new MusicXmlImport.Note(at,end-at,n.pitch,false,false));
        }if(!out.notes.isEmpty())result.tracks.add(out);}
        if(result.tracks.isEmpty())throw new IOException("没有有效时值的 MIDI 音符");
        result.tracks.sort(Comparator.comparingInt(t->t.name.toUpperCase(Locale.ROOT).contains("MELODY")?0:1));
        if(key<0){key=guess(result.tracks.get(0).notes);result.warnings.add("MIDI 未标明调号：建议调号按旋律估计，请对照原谱确认");}
        result.tonic=key;
        if(map.size()>1)result.warnings.add("谱内变速已换算为实际时长，再量化为当前事件时值，请核对");
        if(percussion)result.warnings.add("鼓轨已排除，请选择 MELODY 主旋律音轨");
        if(pedal)result.warnings.add("MIDI 踏板未展开，按音符起止时间生成跟弹事件");
        if(unfinished)result.warnings.add("部分音符缺少结束事件，已延续至音轨末尾，请核对");
        return result;
    }
    private static double seconds(long tick,List<Tempo> map,int ppqn){int lo=0,hi=map.size()-1;while(lo<hi){int mid=(lo+hi+1)/2;if(map.get(mid).tick<=tick)lo=mid;else hi=mid-1;}Tempo t=map.get(lo);return t.seconds+(tick-t.tick)*(t.micros/1000000.0)/ppqn;}
    private static int guess(List<MusicXmlImport.Note> notes){int best=0;double score=Double.NEGATIVE_INFINITY;List<Integer> degrees=Arrays.asList(0,2,4,5,7,9,11);for(int key=0;key<12;key++){double value=0;for(MusicXmlImport.Note n:notes){int d=Math.floorMod(n.pitch-key,12);value+=n.duration*(degrees.contains(d)?1:-4);if(d==0)value+=n.duration*.12;if(d==7)value+=n.duration*.05;}if(value>score){score=value;best=key;}}return best;}
}
