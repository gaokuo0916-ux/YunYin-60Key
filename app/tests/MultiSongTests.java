package cn.fpga.score;
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class MultiSongTests {
 static int checks;
 static void check(boolean b){checks++;if(!b)throw new AssertionError("MultiSong check "+checks);}
 interface Bad{void run()throws Exception;}
 static void rejects(Bad b)throws Exception{try{b.run();throw new AssertionError("accepted invalid song");}catch(IOException|IllegalArgumentException expected){checks++;}}
 static String base(int id){
  BigInteger v=BigInteger.ZERO;int[][] fields={{154,6,32|id},{153,1,1},{5,2,2},{3,2,ChallengeSongs.SONG_LEVELS[id]},
   {9,8,ChallengeSongs.SONG_BPM[id]},{23,6,ChallengeSongs.SONG_EVENTS[id]},{114,6,ChallengeSongs.SONG_NOTES[id]}};
  for(int[] f:fields)v=RhythmTests.put(v,f[0],f[1],f[2]);return String.format(Locale.ROOT,"%040X",v);
 }
 static final class Link implements Uploader.Link{
  Queue<String> q=new ArrayDeque<>();int id;boolean ignore;List<String> sent=new ArrayList<>();
  public void clear(){q.clear();}public String receive(long timeout){return q.poll();}
  public void send(String line){sent.add(line);if(line.startsWith("GSONG ")){if(!ignore)id=Integer.parseInt(line.substring(6))-1;q.add("OK");}
   else if(line.equals("GINFO"))q.add(RhythmTests.frame(base(id)));else if(line.equals("GPLAY"))q.add("OK");}
 }
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]);check(ChallengeSongs.SONG_TITLES.length==15);
  int[] tiers=new int[3];for(int i=0;i<15;i++){
   RhythmStatus s=RhythmStatus.decode(RhythmTests.frame(base(i)));tiers[s.level]++;
   check(s.songPack==2&&s.songId==i&&s.title().equals(ChallengeSongs.SONG_TITLES[i])&&!s.rangeMissing);
   final BigInteger value=new BigInteger(base(i),16);
   check(new RhythmStatus(String.format(Locale.ROOT,"%040X",RhythmTests.put(value,89,9,151))).deviation==151);
   rejects(()->new RhythmStatus(String.format(Locale.ROOT,"%040X",RhythmTests.put(value,89,9,152))));
   rejects(()->new RhythmStatus(String.format(Locale.ROOT,"%040X",RhythmTests.put(value,9,8,1))));
   rejects(()->new RhythmStatus(String.format(Locale.ROOT,"%040X",RhythmTests.put(value,154,6,47))));
   RhythmStatus range=new RhythmStatus(String.format(Locale.ROOT,"%040X",RhythmTests.put(value,158,1,1)));check(range.rangeMissing&&range.songId==i);
  }check(Arrays.equals(tiers,new int[]{5,5,5}));
  Set<Integer> songs=new HashSet<>(),done=new HashSet<>();int paused=0,countIn=0;
  List<String> frames=Files.readAllLines(root.resolve("../verification/multisong_20261026/protocol_frames.txt"),StandardCharsets.UTF_8);check(frames.size()>=60);
  Path dir=Files.createTempDirectory(root.resolve("verification"),"multisong_history_");File historyFile=dir.resolve("history.tsv").toFile();RhythmHistory history=new RhythmHistory(historyFile);
  // ModelSim formats %X in lowercase; the unchanged UART h4 formatter emits A..F.
  for(String recorded:frames){String line=recorded.toUpperCase(Locale.ROOT);RhythmStatus s=RhythmStatus.decode(line);songs.add(s.songId);if(s.state==3)paused++;if(s.state==1)countIn++;
   if(s.state==5){done.add(s.songId);history.add(1000+checks,s);}
   for(int chunk=1;chunk<=20;chunk++){ReplyFrames r=new ReplyFrames();List<String> got=new ArrayList<>();byte[] bytes=(line+"\r\n").getBytes(StandardCharsets.US_ASCII);
    for(int i=0;i<bytes.length;i+=chunk)got.addAll(r.feed(Arrays.copyOfRange(bytes,i,Math.min(i+chunk,bytes.length))));
    check(got.size()==1&&RhythmStatus.decode(got.get(0)).raw.equals(s.raw));}
   String bad=line.substring(0,5)+(line.charAt(5)=='0'?'1':'0')+line.substring(6);rejects(()->RhythmStatus.decode(bad));
  }
  check(songs.size()==15&&done.size()==15&&paused==15&&countIn==15);
  RhythmHistory restored=new RhythmHistory(historyFile);check(restored.entries().size()==16);
  Set<Integer> stored=new HashSet<>();for(RhythmHistory.Entry e:restored.entries())stored.add(e.result.songId);check(stored.size()==15);
  Files.delete(historyFile.toPath());Files.delete(dir);
  Link l=new Link();StudioProtocol p=new StudioProtocol(l);for(int id=0;id<15;id++){p.selectChallengeSong(id);check(p.rhythm().songId==id&&l.sent.contains("GSONG "+(id+1)));}
  rejects(()->p.selectChallengeSong(-1));rejects(()->p.selectChallengeSong(15));l.ignore=true;rejects(()->p.selectChallengeSong(0));
  String controller=Files.readString(root.resolve("src/cn/fpga/score/StudioController.java"),StandardCharsets.UTF_8);
  check(controller.contains("p.selectChallengeSong(selected-1)")&&controller.contains("(capabilities&16384)==0"));
  System.out.println("PASS MultiSongTests "+checks+" checks; 15 real RTL snapshots, fragmented CRC frames, semantic guards, song readback and per-song persisted history; not physical BLE");
 }
}
