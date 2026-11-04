package cn.fpga.score;
import java.io.IOException;
import java.math.BigInteger;
/** Immutable FPGA snapshot. Bit offsets match rhythm_challenge.v; no phone clock scoring. */
public final class RhythmStatus {
 public final String raw;
 public final int songPack,songId;public final boolean rangeMissing;
 public final int state,level,unlocked,countIn,bpm,cursor,events,degree,nextDegree,score,combo,maxCombo;
 public final int perfect,good,wrong,missed,extra,judgement,deviation,best,notes,round;
 public final boolean enabled,passed;
 private final BigInteger value;
 private int bits(int low,int width){return value.shiftRight(low).intValue()&((1<<width)-1);}
 public RhythmStatus(String hex)throws IOException{
  if(hex==null||!hex.matches("[0-9A-F]{40}"))throw new IOException("挑战状态长度或格式错误");
  raw=hex;value=new BigInteger(hex,16);int tag=bits(154,6);songPack=(tag&32)!=0?2:tag;songId=songPack==2?tag&15:-1;rangeMissing=songPack==2&&(tag&16)!=0;
  state=bits(0,3);level=bits(3,2);unlocked=bits(5,2);countIn=bits(7,2);bpm=bits(9,8);
  cursor=bits(17,6);events=bits(23,6);degree=bits(29,3);nextDegree=bits(32,3);
  score=bits(35,7);combo=bits(42,6);maxCombo=bits(48,6);perfect=bits(54,6);good=bits(60,6);
  wrong=bits(66,6);missed=bits(72,6);extra=bits(78,8);judgement=bits(86,3);
  int signed=bits(89,9);deviation=signed>=256?signed-512:signed;
  best=bits(106,7);passed=bits(113,1)!=0;notes=bits(114,6);round=bits(137,16);enabled=bits(153,1)!=0;
  boolean catalogOkay=songPack==2&&songId<15&&level==ChallengeSongs.SONG_LEVELS[songId]&&bpm==ChallengeSongs.SONG_BPM[songId]&&events==ChallengeSongs.SONG_EVENTS[songId]&&notes==ChallengeSongs.SONG_NOTES[songId];
  boolean legacyOkay=songPack<=1&&level<3&&bpm==(songPack==1?ChallengeSongs.BPM:new int[]{80,100,120})[level]&&events==(songPack==1?ChallengeSongs.EVENTS:new int[]{16,24,32})[level]&&notes==(songPack==1?ChallengeSongs.NOTES:new int[]{16,24,28})[level];
  if(state>5||level>2||unlocked>2||level>unlocked||countIn>3||degree>7||nextDegree>7||judgement>6||(!catalogOkay&&!legacyOkay)||
     cursor>events||score>100||best>100||combo>maxCombo||maxCombo>notes||perfect+good+wrong+missed>notes||Math.abs(deviation)>(songPack==2?151:91))
   throw new IOException("挑战状态内容超出范围");
  if(state==5&&(perfect+good+wrong+missed!=notes||score!=Math.max(0,(perfect*100+good*60-extra*20)/notes)||passed!=(score>=60+level*10)))
   throw new IOException("挑战结算统计不一致");
 }
 public static RhythmStatus decode(String line)throws IOException{
  if(line==null||!line.matches("G [0-9A-F]{40} [0-9A-F]{4}"))throw new IOException("挑战回执格式错误");
  String hex=line.substring(2,42);int crc=65535;
  for(int i=0;i<40;i+=2)crc=StudioProtocol.crcByte(crc,Integer.parseInt(hex.substring(i,i+2),16));
  if(crc!=Integer.parseInt(line.substring(43),16))throw new IOException("挑战回执校验失败，未更新分数");
  return new RhythmStatus(hex);
 }
 public String title(){return songPack==2?ChallengeSongs.SONG_TITLES[songId]:songPack==1?ChallengeSongs.TITLES[level]:"旧版节奏练习";}
 public String phase(){return !enabled?"尚未进入游戏":state==0?"选关就绪":state==1?"准备 · "+countIn:state==2?"挑战中":state==3?"已暂停":state==4?"正在结算":"本轮结束";}
 public String judgementText(){switch(judgement){case 1:return "精准";case 2:return "提前";case 3:return "拖拍";case 4:return "错音";case 5:return "漏音";case 6:return "多弹";default:return "等待判定";}}
}
