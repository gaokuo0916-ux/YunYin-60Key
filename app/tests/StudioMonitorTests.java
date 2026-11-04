package cn.fpga.score;
import java.io.*;
import java.math.BigInteger;
import java.util.*;

public final class StudioMonitorTests {
 static int checks;
 static void check(boolean b){if(!b)throw new AssertionError("Monitor regression "+checks);checks++;}
 static final class Link implements Uploader.Link {
  final Queue<String> replies=new ArrayDeque<>();final List<String> sent=new ArrayList<>();
  int caps=127,rank;boolean gameActive,failState,failGame,failAux=true,saved,failCheck;int level,state;Score score;
  public void clear(){replies.clear();}
  public String receive(long ms){return replies.poll();}
  public void send(String line)throws Exception {
   sent.add(line);
   if(line.equals("")){replies.add("ERR 1");return;}
   if(line.equals("PING")){replies.add("PONG");return;}
   if(line.equals("FEAT")){replies.add(caps==0?"ERR 1":String.format(Locale.ROOT,"F24 %04X FFFF",caps));return;}
   if(line.equals("ABORT")){replies.add("OK");return;}
   if(line.equals("STATE")){replies.add(failState?"ERR 3":String.format(Locale.ROOT,"T 0000 0 00 0000 0000 %04X 0078 0 0",rank));return;}
   if(line.equals("GINFO")){
    if(failGame){replies.add("ERR 3");return;}
    BigInteger v=new BigInteger(RhythmTests.base(level,1,state),16);
    if(!gameActive)v=v.clearBit(153);
    replies.add(RhythmTests.frame(String.format(Locale.ROOT,"%040X",v)));return;
   }
   if(line.equals("MAPGET")){replies.add(String.format(Locale.ROOT,"MAP %04X",rank));return;}
   if(line.startsWith("MAP ")){rank=Integer.parseInt(line.substring(4));replies.add("OK");return;}
   if(line.startsWith("GSEL ")){level=Integer.parseInt(line.substring(5))-1;gameActive=true;state=0;replies.add("OK");return;}
   if(line.equals("GPLAY")){state=1;replies.add("OK");return;}
   if(line.equals("RINFO")||line.equals("CINFO")||line.equals("ALINFO")){
    if(failAux)throw new IOException("辅助状态暂时不可读");
    replies.add(line.equals("RINFO")?"R 0 0000 0000 FFFF":line.equals("CINFO")?(saved?"S 3 00 00000001 0003 0000 0000":"S 4 06 00000000 0000 0000 0000"):"A 0 00 00000000 00000000 FFFF");return;
   }
   if(line.equals("CHECK")){if(failCheck)throw new IOException("曲谱校验查询暂不可读");replies.add(String.format(Locale.ROOT,"C %04X %04X",score.count(),score.crc));return;}
   throw new IOException("Unexpected command "+line);
  }
 }
 public static void main(String[] args)throws Exception {
  Link link=new Link();StudioProtocol p=new StudioProtocol(link);
  int caps=StudioMonitor.identify(p);check(caps==127);
  check(link.sent.equals(Arrays.asList("","PING","FEAT")));
  // Old connection code queried CINFO/ALINFO before publishing any capability.
  // Repeated auxiliary failures must leave both verified controls available.
  for(int i=0;i<6;i++){
   StudioMonitor.Snapshot s=StudioMonitor.read(p,caps,i%3);
   check(s.capabilities==127&&s.primaryOkay());check(s.state!=null&&s.game!=null);
   check(s.auxFailed&&s.warning().contains("查询失败"));check((s.capabilities&65)==65);
  }
  p.mapping(720);check(p.mapping()==720);
  p.selectChallenge(1);p.playChallenge();check(p.rhythm().state==1);
  link.failAux=false;link.gameActive=false;
  link.failGame=true;
  for(int i=0;i<4;i++){
   StudioMonitor.Snapshot s=StudioMonitor.read(p,caps,1);
   check(s.gameFailed&&s.game==null&&s.state!=null&&s.rank==720);
   check(s.capabilities==127&&!s.auxFailed); // GINFO failure skips extra traffic.
  }
  link.failGame=false;link.failState=true;
  StudioMonitor.Snapshot s=StudioMonitor.read(p,caps,-1);
  check(s.stateFailed&&s.state==null&&s.game!=null&&s.capabilities==127);
  link.failState=false;
  s=StudioMonitor.read(p,caps,1);check(s.primaryOkay()&&s.storage.state==4&&s.storage.error==6);
  check(s.warning().isEmpty()); // No card is a TF status, not lost controls.
  link.score=Score.parse("123",120);link.saved=true;
  s=StudioMonitor.read(p,caps,1,link.score);check(Boolean.TRUE.equals(s.scoreMatches)&&s.capabilities==127);
  link.failCheck=true;s=StudioMonitor.read(p,caps,1,link.score);
  check(s.storage!=null&&s.auxFailed&&s.scoreMatches==null&&s.capabilities==127);
  link.gameActive=true;int before=link.sent.size();s=StudioMonitor.read(p,caps,1);
  check(!link.sent.subList(before,link.sent.size()).contains("CINFO"));
  link.caps=0;check(StudioMonitor.identify(p)==0); // Genuine old firmware stays unsupported.
  check(link.sent.get(link.sent.size()-1).equals("ABORT"));
  System.out.println("PASS StudioMonitorTests "+checks+" checks; FEAT-only identification, stale-line recovery, independent TF/game/state failures, retained controls, recovery, real MAP/GSEL command paths, genuine old firmware");
 }
}
