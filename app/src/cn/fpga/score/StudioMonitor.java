package cn.fpga.score;
import java.io.IOException;
import java.util.*;

/** FEAT is authoritative; optional telemetry must never erase known abilities. */
public final class StudioMonitor {
    private StudioMonitor(){}
    public static int identify(StudioProtocol p)throws Exception {
        p.synchronize();
        return p.capabilities();
    }
    public static final class Snapshot {
        public final int capabilities;
        public StudioProtocol.Keyboard keyboard;
        public StudioProtocol.State state;
        public StudioProtocol.Pitch pitch;
        public StudioProtocol.Recording recording;
        public StudioProtocol.Storage storage;
        public StudioProtocol.SdDiagnostic sdDiagnostic;
        public StudioProtocol.LongAudio audio;
        public StudioProtocol.Polyphony polyphony;
        public RhythmStatus game;
        public Integer rank,timbre;
        public Boolean scoreMatches;
        public boolean stateFailed,gameFailed,auxFailed,timbreFailed;
        private final List<String> warnings=new ArrayList<>();
        Snapshot(int c){capabilities=c;}
        public boolean primaryOkay(){return !stateFailed&&!gameFailed;}
        public String warning(){return String.join("；",warnings);}
        private void failure(String name,IOException e){warnings.add(name+"："+e.getMessage());}
    }
    /** At most one auxiliary category per poll; no auxiliary failure hides controls. */
    public static Snapshot read(StudioProtocol p,int capabilities,int auxiliary)throws Exception {
        return read(p,capabilities,auxiliary,null);
    }
    public static Snapshot read(StudioProtocol p,int capabilities,int auxiliary,Score score)throws Exception {
        Snapshot s=new Snapshot(capabilities);
        if((capabilities&8192)!=0)try{s.keyboard=p.keyboard();}
            catch(IOException e){s.stateFailed=true;s.failure("60键状态查询失败",e);}
        if((capabilities&2)!=0)try{s.state=p.state();s.rank=s.state.rank;}
            catch(IOException e){s.stateFailed=true;s.failure("演奏状态查询失败",e);}
        else if((capabilities&1)!=0)try{s.rank=p.mapping();}
            catch(IOException e){s.stateFailed=true;s.failure("键位读回失败",e);}
        if((capabilities&64)!=0)try{s.game=p.rhythm();}
            catch(IOException e){s.gameFailed=true;s.failure("挑战状态查询失败",e);}
        if((capabilities&256)!=0)try{s.timbre=p.timbre();}
            catch(IOException e){s.timbreFailed=true;s.failure("音色读回失败",e);}
        if((capabilities&512)!=0)try{s.polyphony=p.polyphony();}
            catch(IOException e){s.failure("复音状态查询失败",e);}
        if((capabilities&2048)!=0&&score!=null&&score.nativePitch)try{
            s.pitch=p.pitch();s.scoreMatches=s.pitch.nativeFormat&&p.matches(score);
        }catch(IOException e){s.failure("原音高状态查询失败",e);}
        boolean gameBusy=s.game!=null&&s.game.enabled&&s.game.state!=5;
        // If game status is temporarily unreadable, avoid adding TF traffic.
        if(!gameBusy&&!s.gameFailed)try{
            if(auxiliary==0&&(capabilities&4)!=0)s.recording=p.recording();
            if(auxiliary==1&&(capabilities&16)!=0){
                s.storage=p.storage();
                if((capabilities&128)!=0)try{s.sdDiagnostic=p.sdDiagnostic();}
                    catch(IOException e){s.auxFailed=true;s.failure("TF初始化诊断查询失败",e);}
                if(s.storage.state==3&&score!=null&&!score.nativePitch)s.scoreMatches=p.matches(score);
            }
            if(auxiliary==2&&(capabilities&32)!=0)s.audio=p.audio();
        }catch(IOException e){s.auxFailed=true;s.failure(auxiliary==1?"TF状态查询失败":auxiliary==2?"TF录音查询失败":"录音状态查询失败",e);}
        return s;
    }
}
