package cn.fpga.score;
import java.io.*;
import java.util.*;
import java.util.regex.*;
/** Optional v2.4 commands. Old score upload commands and their replies stay unchanged. */
public final class StudioProtocol {
    private final Uploader.Link link;private Keyboard keyboard;
    public StudioProtocol(Uploader.Link l){link=l;}
    /** A blank LF discards a stale partial command; PONG proves UART return. */
    public void synchronize()throws Exception{
        link.clear();link.send("");link.send("PING");long until=System.nanoTime()+6500000000L;
        while(System.nanoTime()<until){String s=link.receive(200);if(s==null)continue;
            if(s.startsWith("!"))throw new IOException(s.substring(1));
            if(s.equals("PONG"))return;
        }throw new IOException("蓝牙已连接，但没有收到琴端 PONG，请检查板端程序和回传");
    }
    public RhythmStatus rhythm()throws Exception{return RhythmStatus.decode(command("GINFO","G "));}
    public void selectChallenge(int level)throws Exception{
        if(level<1||level>3)throw new IllegalArgumentException("关卡范围为1至3");
        command("GSEL "+level,"OK");RhythmStatus s=rhythm();
        if(!s.enabled||s.level!=level-1||s.state!=0)throw new IOException("琴端未确认关卡选择");
    }
    public void selectChallengeSong(int song)throws Exception{
        if(song<0||song>=15)throw new IllegalArgumentException("曲目范围为0至14");
        command("GSONG "+(song+1),"OK");RhythmStatus s=rhythm();
        if(!s.enabled||s.songPack!=2||s.songId!=song||s.state!=0)throw new IOException("琴端未确认曲目选择");
    }
    public void playChallenge()throws Exception{command("GPLAY","OK");}
    public void pauseChallenge()throws Exception{command("GPAUSE","OK");}
    public void exitChallenge()throws Exception{command("GEXIT","OK");}
    public static final class Polyphony {
        public final int active,held;public final long activeMask,heldMask;public final boolean demo,deadline;
        Polyphony(String s)throws IOException{
            if(!s.matches("P [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{8} [0-9A-F]{8} [01] [01]"))throw new IOException("复音状态格式错误");
            String[] f=s.split(" ");active=hex(f[1]);held=hex(f[2]);activeMask=Long.parseLong(f[3],16);heldMask=Long.parseLong(f[4],16);demo=f[5].equals("1");deadline=f[6].equals("1");
            if(active>32||held>active||Integer.bitCount((int)activeMask)!=active||Integer.bitCount((int)heldMask)!=held||(heldMask&~activeMask)!=0)throw new IOException("复音计数与声部状态不符");
        }
    }
    public Polyphony polyphony()throws Exception{return new Polyphony(command("PINFO","P "));}
    public Polyphony polyDemo(int voices,boolean singleFrequency)throws Exception{
        if(voices<1||voices>32)throw new IllegalArgumentException("声部数为1至32");
        command("PDEMO "+voices+" "+(singleFrequency?1:0),"OK");Polyphony p=polyphony();
        if(p.active!=voices||p.held!=voices||!p.demo||p.deadline)throw new IOException("琴端尚未确认所选复音测试状态");return p;
    }
    public Polyphony polyStop()throws Exception{
        command("PCLR","OK");Polyphony p=polyphony();if(p.active!=0||p.held!=0||p.demo)throw new IOException("琴端未确认结束复音测试");return p;
    }
    public Polyphony polyRelease(int slot)throws Exception{
        if(slot<0||slot>=32)throw new IllegalArgumentException("声部编号为1至32");
        command("PMUTE "+slot,"OK");Polyphony p=polyphony();if((p.heldMask&(1L<<slot))!=0)throw new IOException("琴端未释放所选声部");return p;
    }
    public Polyphony polyRetune(int slot)throws Exception{
        if(slot<0||slot>=32)throw new IllegalArgumentException("声部编号为1至32");
        command("PTUNE "+slot+" 150","OK");return polyphony();
    }
    private String command(String text,String prefix)throws Exception{
        link.clear();link.send(text);long until=System.nanoTime()+6500000000L;
        while(System.nanoTime()<until){String s=link.receive(200);if(s==null)continue;
            if(s.startsWith("!"))throw new IOException(s.substring(1));
            if(s.startsWith("ERR "))throw new IOException("琴端未执行 "+text+"："+s);
            if(s.startsWith(prefix))return s;
            throw new IOException("琴端回执与操作不符："+s);
        }throw new IOException("等待琴端回执超时："+text);
    }
    public int capabilities()throws Exception{
        try{String s=command("FEAT","F24 ");if(!s.matches("F24 [0-9A-F]{4} [0-9A-F]{4}"))throw new IOException("功能回执格式错误");return hex(s.split(" ")[1]);}
        catch(IOException e){if(e.getMessage().contains("ERR 1")){command("ABORT","OK");return 0;}throw e;}
    }
    /** Capability 0x2000. Mask stays an exact 60-bit long, never a JS Number. */
    public static final class Keyboard {
        public final int base,count;public final long keys;public final String mask;
        public Keyboard(String text)throws IOException {
            if(!text.matches("K [0-9A-F]{2} 3C [0-9A-F]{16}"))throw new IOException("60键回执格式错误");
            String[] f=text.split(" ");base=hex(f[1]);count=hex(f[2]);mask=f[3];keys=Long.parseUnsignedLong(mask,16);
            if(base<12||base>60||base%12!=0||(keys>>>60)!=0)throw new IOException("60键音域或状态无效");
        }
        public boolean playable(int code){return code==0||(code>=base+1&&code<=base+count);}
    }
    public Keyboard keyboard()throws Exception {return keyboard=new Keyboard(command("KINFO","K "));}
    public Keyboard octave(int selected)throws Exception {
        if(selected<0||selected>4)throw new IOException("音区范围为0至4");
        command("KOCT "+selected,"OK");Keyboard actual=keyboard();
        if(actual.base!=12+12*selected)throw new IOException("琴端音区读回不符");return actual;
    }
    public int mapping()throws Exception{String s=command("MAPGET","MAP ");if(!s.matches("MAP [0-9A-F]{4}"))throw new IOException("键位回执格式错误");int n=hex(s.substring(4));KeyMapping.decode(n);return n;}
    public void mapping(int rank)throws Exception{KeyMapping.decode(rank);command("MAP "+rank,"OK");if(mapping()!=rank)throw new IOException("琴端键位读回不符，未标记成功");}
    /** Capability 0x0100: actual hardware selection, 0 piano / 1 guitar / 2 accordion. */
    private static int decodeTimbre(String reply)throws IOException{
        if(!reply.matches("TONE [0-2]"))throw new IOException("音色回执格式错误");
        return reply.charAt(5)-'0';
    }
    public int timbre()throws Exception{return decodeTimbre(command("TINFO","TONE "));}
    public int timbre(int selected)throws Exception{
        if(selected<0||selected>2)throw new IllegalArgumentException("音色范围为 0 至 2");
        if(decodeTimbre(command("TONE "+selected,"TONE "))!=selected)
            throw new IOException("琴端未确认所选音色");
        int actual=timbre();
        if(actual!=selected)throw new IOException("琴端音色读回不符，请松开全部琴键后重试");
        return actual;
    }
    public static final class State{
        public final int index,state,keys,held,expected,rank,bpm;public final boolean user,valid;
        State(String s)throws IOException{
            if(!s.matches("T [0-9A-F]{4} [0-6] [0-9A-F]{2} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [01] [01]"))throw new IOException("演奏状态格式错误");
            String[] p=s.split(" ");index=hex(p[1]);state=hex(p[2]);keys=hex(p[3]);held=hex(p[4]);expected=hex(p[5]);rank=hex(p[6]);bpm=hex(p[7]);user=p[8].equals("1");valid=p[9].equals("1");
        }
    }
    public State state()throws Exception{return new State(command("STATE","T "));}
    public static final class Pitch {
        public final boolean nativeFormat,selected,ready,missing;public final int index,code;
        public Pitch(String value)throws IOException{this(value,null);}
        private Pitch(String value,Keyboard keyboard)throws IOException{
            if(!value.matches("N [01] [01] [0-9A-F]{4} [0-9A-F]{2} [01] [01]"))throw new IOException("原音高回执格式错误");
            String[] p=value.split(" ");nativeFormat=p[1].equals("1");selected=p[2].equals("1");index=hex(p[3]);code=hex(p[4]);ready=p[5].equals("1");missing=p[6].equals("1");
            if(index>=8192||code>128||(!ready&&(code!=0||missing))||(!nativeFormat&&(code!=0||missing))||missing!=(ready&&nativeFormat&&code!=0&&(keyboard==null?OriginalPractice.keyDegree(code)==0:!keyboard.playable(code))))throw new IOException("原音高状态内容不符");
        }
    }
    public Pitch pitch()throws Exception{return new Pitch(command("MINFO","N "),keyboard);}
    public Pitch skipMissing()throws Exception{
        if((capabilities()&8192)!=0)keyboard();Pitch before=pitch();State current=state();
        if(!before.nativeFormat||!before.selected||!before.ready||!before.missing||current.index!=before.index||current.keys!=0||(current.state!=1&&current.state!=2))throw new IOException("请在缺键提示时松开全部琴键，再跳过此音");
        command("SKIP","OK");Pitch after=pitch();State result=state();
        if(after.index==before.index&&result.state!=5)throw new IOException("琴端尚未确认跳过，进度未更新");return after;
    }
    public static final class Storage {
        public final int state,error,count,crc,rank;public final long generation;
        Storage(String s)throws IOException{
            if(!s.matches("S [0-4] [0-9A-F]{2} [0-9A-F]{8} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}"))throw new IOException("TF 存储回执格式错误");
            String[] p=s.split(" ");state=hex(p[1]);error=hex(p[2]);generation=Long.parseLong(p[3],16);count=hex(p[4]);crc=hex(p[5]);rank=hex(p[6]);
        }
    }
    public Storage storage()throws Exception{return new Storage(command("CINFO","S "));}
    /** Optional capability 0x0080. Older firmware keeps its original CINFO format. */
    public static final class SdDiagnostic {
        public final String raw;public final int error,state,step,command,response,attempts,miso;
        public final long ocr;public final boolean initialized,selected;
        SdDiagnostic(String line)throws IOException{
            if(!line.matches("SD [0-9A-F]{16}"))throw new IOException("TF 初始化诊断回执格式错误");
            raw=line.substring(3);long d=Long.parseUnsignedLong(raw,16);
            error=(int)(d&15);state=(int)((d>>>4)&31);step=(int)((d>>>9)&15);
            command=(int)((d>>>13)&63);response=(int)((d>>>19)&255);
            ocr=(d>>>27)&0xffffffffL;attempts=(int)((d>>>59)&3)+1;
            initialized=((d>>>61)&1)!=0;miso=(int)((d>>>62)&1);selected=(d>>>63)==0;
        }
        public boolean canRetry(){return !initialized&&state==20;}
        public String message(){
            if(initialized)return "TF 通信初始化已完成；文件系统状态见上方提示";
            if(!canRetry())return "正在初始化 TF · 第 "+attempts+" 次尝试 · CMD"+command;
            String reason=error==2?"未收到有效响应":error==7?"初始化超时":error==1?"握手返回值不符合要求":"初始化失败（"+error+"）";
            return "CMD"+command+"："+reason+String.format(Locale.ROOT," · R1=%02X · 已尝试 %d 次",response,attempts);
        }
    }
    public SdDiagnostic sdDiagnostic()throws Exception{return new SdDiagnostic(command("SDINFO","SD "));}
    public void retrySdInitialization()throws Exception{command("SDINIT","OK");}
    public boolean matches(Score score)throws Exception{
        String s=command("CHECK","C ");if(!s.matches("C [0-9A-F]{4} [0-9A-F]{4}"))throw new IOException("曲谱校验回执格式错误");String[] p=s.split(" ");return score!=null&&hex(p[1])==score.count()&&hex(p[2])==score.crc;
    }
    public Storage persist(Score score,Uploader.Progress progress)throws Exception{
        if(score!=null&&score.nativePitch&&(capabilities()&4096)==0)throw new IOException("当前琴端不支持原音高TF保存，请更新配套固件");
        Storage before=storage();command("STORE "+score.crc,"OK");long until=System.nanoTime()+90000000000L;
        while(System.nanoTime()<until){Storage s=storage();if(s.state==4)throw new IOException(storageError(s.error));
            if(s.state==3&&s.generation!=before.generation&&s.count==score.count()&&s.crc==score.crc)return s;
            progress.update(0,1,"TF 正在写入并读回校验");Thread.sleep(300);
        }throw new IOException("TF 保存未确认完成，原来的曲谱仍保留；请检查卡后重试");
    }
    public void recall()throws Exception{command("RECALL","OK");}
    public static String storageError(int code){switch(code){
        case 1:return "TF 读写未完成，请断电检查卡片";case 2:return "TF 需使用 FAT32，或曲谱校验不符";
        case 3:return "未找到有效的 YUNYIN.BIN 文件，或保存后的校验失败";case 4:return "存储文件不连续，请在空白 FAT32 卡上重新创建 YUNYIN.BIN";
        case 5:return "TF 存储文件格式不匹配，请使用云音创建初始化文件";case 6:return "未识别 TF 卡，请插入 SDHC 小卡后重新上电";
        default:return "TF 存储暂不可用（"+code+"）";
    }}
    public void arm()throws Exception{command("RARM 65535","OK");}
    public void abortRecord()throws Exception{command("RSTOP","OK");}
    public static final class Recording{
        public final int state,count,requested,crc;
        Recording(String s)throws IOException{
            if(!s.matches("R [0-4] [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}"))throw new IOException("录音状态格式错误");
            String[] p=s.split(" ");state=hex(p[1]);count=hex(p[2]);requested=hex(p[3]);crc=hex(p[4]);
        }
    }
    public Recording recording()throws Exception{return new Recording(command("RINFO","R "));}
    public static final class LongAudio{
        public final int state,error,count,crc;public final long generation;
        LongAudio(String s)throws IOException{
            if(!s.matches("A [0-6] [0-9A-F]{2} [0-9A-F]{8} [0-9A-F]{8} [0-9A-F]{4}"))throw new IOException("TF 录音回执格式错误");
            String[] p=s.split(" ");state=hex(p[1]);error=hex(p[2]);generation=Long.parseLong(p[3],16);long n=Long.parseLong(p[4],16);if(n>5859375)throw new IOException("录音数量超出固件容量");count=(int)n;crc=hex(p[5]);
        }
    }
    public LongAudio audio()throws Exception{return new LongAudio(command("ALINFO","A "));}
    public void armAudio(int seconds)throws Exception{if(seconds<1||seconds>120)throw new IOException("录音时长为 1～120 秒");command("ALARM "+seconds,"OK");}
    public void stopAudio()throws Exception{command("ALSTOP","OK");}
    public byte[] downloadAudio(LongAudio r,Uploader.Progress progress)throws Exception{
        if((r.state!=3&&r.state!=4)||r.count==0)throw new IOException("TF 中没有已结束的录音");
        ByteArrayOutputStream out=new ByteArrayOutputStream(r.count*2);int crc=65535;
        boolean fast=false;
        try{fast=command("ALCAP","B64").equals("B64");}catch(IOException e){if(!e.getMessage().endsWith("ERR 3"))throw e;}
        int page=fast?256:16;long lastProgress=System.nanoTime();
        for(int offset=0;offset<r.count;offset+=page){byte[] block=null;Exception last=null;
            for(int attempt=0;attempt<3;attempt++)try{block=fast?decodeFastBlock(command("ALPAGE "+(offset>>>16)+" "+(offset&65535),"B "),offset,Math.min(256,r.count-offset)):decodeLongBlock(command("ALGET "+(offset>>>16)+" "+(offset&65535),"L "),offset,Math.min(16,r.count-offset));break;}catch(IOException e){last=e;}
            if(block==null&&fast){
                // Some transparent BLE bridges cannot buffer an entire page.
                // Retry the same offset using the proven small-frame protocol.
                fast=false;page=16;
                for(int attempt=0;attempt<3;attempt++)try{block=decodeLongBlock(command("ALGET "+(offset>>>16)+" "+(offset&65535),"L "),offset,Math.min(16,r.count-offset));break;}catch(IOException e){last=e;}
            }
            if(block==null)throw new IOException("录音分包未收到，未保存不完整文件",last);
            out.write(block);for(byte b:block)crc=crcByte(crc,b);long now=System.nanoTime();if(now-lastProgress>=500000000L||offset+page>=r.count){progress.update(Math.min(offset+page,r.count),r.count,fast?"蓝牙整页回传 TF 录音":"兼容回传 TF 录音");lastProgress=now;}
        }if(crc!=r.crc)throw new IOException("整段 TF 录音 CRC 不符，文件未保存");return out.toByteArray();
    }
    static byte[] decodeFastBlock(String s,int offset,int length)throws IOException{
        if(!s.matches("B [0-9A-F]{8} [0-9A-F]{4} [A-Za-z0-9+/=]{4,684} [0-9A-F]{4}"))throw new IOException("TF page format");
        String[] p=s.split(" ");
        if(length<1||length>256||Long.parseLong(p[1],16)!=offset||hex(p[2])!=length)throw new IOException("TF page index/length");
        byte[] data;try{data=Base64.getDecoder().decode(p[3]);}catch(IllegalArgumentException e){throw new IOException("TF page encoding",e);}
        if(data.length!=length*2||!Base64.getEncoder().encodeToString(data).equals(p[3]))throw new IOException("TF page size/padding");
        int crc=65535;for(int n=0;n<4;n++)crc=crcByte(crc,offset>>>(8*n));
        crc=crcByte(crc,length);crc=crcByte(crc,length>>>8);
        for(byte b:data)crc=crcByte(crc,b);
        if(crc!=hex(p[4]))throw new IOException("TF page CRC");return data;
    }
    static byte[] decodeLongBlock(String s,int offset,int length)throws IOException{
        if(!s.matches("L [0-9A-F]{8} [0-9A-F]{2} [0-9A-F]{4,64} [0-9A-F]{4}"))throw new IOException("TF 录音分包格式错误");String[] p=s.split(" ");
        if(Long.parseLong(p[1],16)!=offset||hex(p[2])!=length||p[3].length()!=length*4)throw new IOException("TF 录音分包序号或长度不符");
        byte[] data=new byte[length*2];int crc=65535;for(int n=0;n<4;n++)crc=crcByte(crc,offset>>>(n*8));crc=crcByte(crc,length);
        for(int n=0;n<data.length;n++){data[n]=(byte)hex(p[3].substring(n*2,n*2+2));crc=crcByte(crc,data[n]);}if(crc!=hex(p[4]))throw new IOException("TF 录音分包 CRC 不符");return data;
    }
    public byte[] download(Recording r,Uploader.Progress progress)throws Exception{
        if(r.state!=3||r.count==0||r.count!=r.requested)throw new IOException("琴端录音尚未完整结束");
        ByteArrayOutputStream out=new ByteArrayOutputStream(r.count*2);int crc=65535;
        for(int offset=0;offset<r.count;offset+=16){
            Exception last=null;byte[] block=null;
            for(int attempt=0;attempt<3;attempt++)try{block=decodeBlock(command("RGET "+offset,"D "),offset,Math.min(16,r.count-offset));break;}catch(IOException e){last=e;}
            if(block==null)throw new IOException("录音第 "+offset+" 个采样回传失败",last);
            out.write(block);for(byte b:block)crc=crcByte(crc,b);progress.update(Math.min(offset+16,r.count),r.count,"回传真实 PCM");
        }
        if(crc!=r.crc)throw new IOException("整段录音校验失败，文件未保存");return out.toByteArray();
    }
    static byte[] decodeBlock(String s,int offset,int length)throws IOException{
        if(!s.matches("D [0-9A-F]{4} [0-9A-F]{2} [0-9A-F]{4,64} [0-9A-F]{4}"))throw new IOException("录音分包格式错误");
        String[] p=s.split(" ");if(hex(p[1])!=offset||hex(p[2])!=length||p[3].length()!=length*4)throw new IOException("录音分包序号或长度不符");
        byte[] b=new byte[length*2];int crc=crcByte(crcByte(crcByte(65535,offset),offset>>8),length);
        for(int i=0;i<b.length;i++){b[i]=(byte)hex(p[3].substring(i*2,i*2+2));crc=crcByte(crc,b[i]);}
        if(crc!=hex(p[4]))throw new IOException("录音分包 CRC 不符");return b;
    }
    static int hex(String s){return Integer.parseInt(s,16);}
    static int crcByte(int crc,int value){crc^=(value&255)<<8;for(int n=0;n<8;n++)crc=((crc<<1)^((crc&32768)!=0?0x1021:0))&65535;return crc;}
    /** Actual final synth PCM; integer WAV sample rate differs by only 0.00026%. */
    public static byte[] wav(byte[] pcm)throws IOException{
        if(pcm.length==0||(pcm.length&1)!=0||pcm.length>11718750)throw new IOException("录音长度不合法");
        ByteArrayOutputStream out=new ByteArrayOutputStream();out.write("RIFF".getBytes("US-ASCII"));le(out,pcm.length+36,4);out.write("WAVEfmt ".getBytes("US-ASCII"));le(out,16,4);le(out,1,2);le(out,1,2);le(out,48828,4);le(out,97656,4);le(out,2,2);le(out,16,2);out.write("data".getBytes("US-ASCII"));le(out,pcm.length,4);out.write(pcm);return out.toByteArray();
    }
    private static void le(OutputStream out,int n,int bytes)throws IOException{for(int i=0;i<bytes;i++){out.write(n&255);n>>>=8;}}
}
