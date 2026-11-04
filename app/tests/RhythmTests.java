package cn.fpga.score;
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class RhythmTests {
 static int checks;
 static void check(boolean b){checks++;if(!b)throw new AssertionError("Rhythm check "+checks);}
 interface Bad{void run()throws Exception;}
 static void rejects(Bad action)throws Exception{try{action.run();throw new AssertionError("accepted invalid challenge data");}catch(IOException|IllegalArgumentException expected){checks++;}}
 static BigInteger put(BigInteger v,int low,int width,int n){BigInteger mask=BigInteger.ONE.shiftLeft(width).subtract(BigInteger.ONE).shiftLeft(low);return v.andNot(mask).or(BigInteger.valueOf(n&((1<<width)-1)).shiftLeft(low));}
 static String base(int level,int round,int state)throws Exception{
  BigInteger v=BigInteger.ZERO;int[][] f={{0,3,state},{3,2,level},{5,2,2},{9,8,new int[]{80,100,120}[level]},
    {23,6,new int[]{16,24,32}[level]},{114,6,new int[]{16,24,28}[level]},{137,16,round},{153,1,1}};
  for(int[] e:f)v=put(v,e[0],e[1],e[2]);return String.format(Locale.ROOT,"%040X",v);
 }
 static String perfect(int level,int round)throws Exception{
  BigInteger v=new BigInteger(base(level,round,5),16);int notes=new int[]{16,24,28}[level];
  int[][] f={{17,6,new int[]{16,24,32}[level]},{35,7,100},{42,6,notes},{48,6,notes},{54,6,notes},{106,7,100},{113,1,1}};
  for(int[] e:f)v=put(v,e[0],e[1],e[2]);return String.format(Locale.ROOT,"%040X",v);
 }
 static String frame(String hex){int crc=65535;for(int i=0;i<40;i+=2)crc=StudioProtocol.crcByte(crc,Integer.parseInt(hex.substring(i,i+2),16));return String.format(Locale.ROOT,"G %s %04X",hex,crc);}
 static final class Link implements Uploader.Link {
  Queue<String> replies=new ArrayDeque<>();int level=0,state=0;List<String> sent=new ArrayList<>();
  public void clear(){replies.clear();}public String receive(long timeout){return replies.poll();}
  public void send(String line)throws Exception{sent.add(line);if(line.startsWith("GSEL ")){level=Integer.parseInt(line.substring(5))-1;state=0;replies.add("OK");}
   else if(line.equals("GINFO"))replies.add(frame(base(level,1,state)));
   else if(line.equals("GPLAY")){state=1;replies.add("OK");}
   else if(line.equals("GPAUSE")){state=state==3?2:3;replies.add("OK");}
   else if(line.equals("GEXIT")){state=0;replies.add("OK");}
  }
 }
 public static void main(String[] args)throws Exception {
  Path root=Paths.get(args[0]),fixtures=root.resolve("../verification/rhythm_protocol_frames.txt");
  List<String> real=new ArrayList<>(Files.readAllLines(fixtures,StandardCharsets.UTF_8));check(real.size()>=4);
  Path songFrames=root.resolve("../verification/song_challenges_20261024/protocol_frames.txt");
  if(Files.exists(songFrames)){List<String> fresh=Files.readAllLines(songFrames,StandardCharsets.UTF_8);check(fresh.size()>=4);for(String line:fresh)check(RhythmStatus.decode(line).songPack==1);real.addAll(fresh);}
  boolean done=false,paused=false;
  for(String line:real){RhythmStatus s=RhythmStatus.decode(line);done|=s.state==5;paused|=s.state==3;
   for(int chunk=1;chunk<=20;chunk++){ReplyFrames decoder=new ReplyFrames();List<String> got=new ArrayList<>();byte[] data=(line+"\r\n").getBytes("US-ASCII");for(int i=0;i<data.length;i+=chunk)got.addAll(decoder.feed(Arrays.copyOfRange(data,i,Math.min(data.length,i+chunk))));check(got.size()==1&&RhythmStatus.decode(got.get(0)).raw.equals(s.raw));}
   for(int i=2;i<42;i++){final String corrupt=line.substring(0,i)+(line.charAt(i)=='0'?'1':'0')+line.substring(i+1);rejects(()->RhythmStatus.decode(corrupt));}
  }
  check(done&&paused);
  for(int lev=0;lev<3;lev++){RhythmStatus s=RhythmStatus.decode(frame(perfect(lev,12)));check(s.score==100&&s.passed&&s.maxCombo==s.notes&&s.round==12&&s.level==lev);}
  rejects(()->RhythmStatus.decode("G 1234 0000"));
  String wrongTotals=String.format(Locale.ROOT,"%040X",put(new BigInteger(perfect(0,1),16),54,6,15));rejects(()->RhythmStatus.decode(frame(wrongTotals)));
  String wrongScore=String.format(Locale.ROOT,"%040X",put(new BigInteger(perfect(0,1),16),35,7,99));rejects(()->RhythmStatus.decode(frame(wrongScore)));
  String reserved=String.format(Locale.ROOT,"%040X",put(new BigInteger(perfect(0,1),16),154,6,2));rejects(()->RhythmStatus.decode(frame(reserved)));
  for(int lev=0;lev<3;lev++){
   BigInteger v=new BigInteger(perfect(lev,13),16);int notes=ChallengeSongs.NOTES[lev];
   int[][] fields={{154,6,1},{9,8,ChallengeSongs.BPM[lev]},{23,6,ChallengeSongs.EVENTS[lev]},{17,6,ChallengeSongs.EVENTS[lev]},
    {114,6,notes},{42,6,notes},{48,6,notes},{54,6,notes}};
   for(int[] f:fields)v=put(v,f[0],f[1],f[2]);
   RhythmStatus song=RhythmStatus.decode(frame(String.format(Locale.ROOT,"%040X",v)));check(song.songPack==1&&song.score==100&&song.notes==notes);
  }
  String featureSource=new String(Files.readAllBytes(root.resolve("src/cn/fpga/score/FeaturePanel.java")),StandardCharsets.UTF_8);
  String studioSource=new String(Files.readAllBytes(root.resolve("src/cn/fpga/score/StudioController.java")),StandardCharsets.UTF_8);
  check(featureSource.contains("startActivityForResult(intent,209)")&&featureSource.contains("if(request==209)"));
  check(studioSource.contains("if(request==207)")&&!featureSource.contains("if(request==207)"));
  Link link=new Link();StudioProtocol p=new StudioProtocol(link);p.selectChallenge(2);check(p.rhythm().level==1);p.playChallenge();check(p.rhythm().state==1);p.pauseChallenge();check(p.rhythm().state==3);p.pauseChallenge();check(p.rhythm().state==2);p.exitChallenge();rejects(()->p.selectChallenge(4));
  Path dir=Files.createTempDirectory(root.resolve("verification"),"rhythm_history_");File file=dir.resolve("scores.tsv").toFile();RhythmHistory history=new RhythmHistory(file);
  for(int i=0;i<105;i++)history.add(1000+i,new RhythmStatus(perfect(i%3,i+1)));
  check(history.entries().size()==100&&history.entries().get(0).time==1104);
  RhythmHistory reopened=new RhythmHistory(file);check(reopened.entries().size()==100&&reopened.entries().get(99).time==1005);
  byte[] saved=Files.readAllBytes(file.toPath());rejects(()->history.add(2000,new RhythmStatus(base(0,2,2))));check(Arrays.equals(saved,Files.readAllBytes(file.toPath())));
  check(!Files.exists(dir.resolve("scores.tsv.partial")));Files.delete(file.toPath());Files.delete(dir);
  System.out.println("PASS RhythmTests "+checks+" checks; real FPGA UART fixtures, arbitrary BLE splits, CRC corruption, semantic validation, commands, bounded atomic history");
 }
}
