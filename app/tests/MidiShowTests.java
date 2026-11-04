package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class MidiShowTests {
 static int checks;
 interface Work{void run()throws Exception;}
 static void check(boolean ok,String message){checks++;if(!ok)throw new AssertionError(message);}
 static void reject(Work task)throws Exception{try{task.run();}catch(IOException e){checks++;return;}throw new AssertionError("Invalid request accepted");}
 static byte[] b(String text){return text.getBytes(StandardCharsets.UTF_8);}
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),cache=Files.createTempDirectory(root.resolve("verification"),"midishow_fixture_");
  String chinese="世界赠予我的 & A/B +#?";
  String search=MidiShowSource.search(chinese,"newest");
  check(search.startsWith("https://www.midishow.com/search/result?q="),"Search has the official destination");
  Map<String,String> params=new HashMap<>();for(String pair:URI.create(search).getRawQuery().split("&")){String[] parts=pair.split("=",2);params.put(parts[0],URLDecoder.decode(parts[1],"UTF-8"));}
  check(params.size()==2&&chinese.equals(params.get("q"))&&"time_desc".equals(params.get("sort")),"Chinese and special characters do not become query parameters");
  check(MidiShowSource.search("","newest").equals(MidiShowSource.POP+"?sort=time_desc"),"Empty search browses latest pop uploads");
  check(MidiShowSource.search(" LBI利比 ","popular").contains("sort=popularity"),"Popularity order available");
  check(MidiShowSource.search("Adele","relevance").contains("q=Adele&sort=default"),"Foreign music remains searchable");
  reject(()->MidiShowSource.search("x","injected&sort=other"));reject(()->MidiShowSource.search("a\nb","relevance"));reject(()->MidiShowSource.search(String.join("",Collections.nCopies(121,"字")),"newest"));
  for(String url:new String[]{MidiShowSource.LOGIN,"https://midishow.com/midi/225788.html","https://www.midishow.com/en/midi/225788.html"})check(MidiShowSource.owns(url),"Normal site URL");
  for(String url:new String[]{"https://midishow.com.evil.test/a","https://evil.test/?site=midishow.com","http://www.midishow.com/","https://u:p@midishow.com/","https://midishow.com:444/"})check(!MidiShowSource.owns(url),"Do not treat another origin as the provider");
  check(MidiShowSource.title("跳楼机 MIDI 音乐下载试听 :: MidiShow").equals("跳楼机"),"Source title retained");
  check(MidiShowSource.filename("download","跳楼机 MIDI 音乐下载试听 :: MidiShow").equals("跳楼机"),"Dynamic endpoint can retain song title");
  check(MidiShowSource.filename("跳楼机.mid","Any title").equals("跳楼机.mid"),"Download filename retained");

  byte[] midi=new byte[]{77,84,104,100,0,0,0,6,0,0,0,1,1,(byte)224,77,84,114,107,0,0,0,13,0,(byte)144,60,100,(byte)131,96,(byte)128,60,0,0,(byte)255,47,0};
  String endpoint="https://www.midishow.com/midi/download?id=225788";
  LibraryWebTests.Reply reply=new LibraryWebTests.Reply(endpoint,200,midi);reply.response.put("Content-Disposition","attachment; filename*=UTF-8''%E8%B7%B3%E6%A5%BC%E6%9C%BA.mid");
  ScoreWebImport.Download downloaded=ScoreWebImport.fetch(endpoint,"WebView test agent","site-session=fixture","https://www.midishow.com/midi/225788.html",url->reply);
  check("site-session=fixture".equals(reply.sent.get("Cookie")),"Session reaches the same-origin download endpoint");
  check(reply.sent.get("Referer").endsWith("225788.html"),"Download retains the source page");
  File staged=WebScoreStage.save(cache.toFile(),downloaded.data,downloaded.name);
  check(staged.isFile()&&staged.length()==midi.length,"Verified file staged privately");
  byte[] restored=WebScoreStage.take(cache.toFile(),staged.getPath());
  check(Arrays.equals(restored,midi)&&!staged.exists(),"One handoff consumes and removes the staged file");
  MusicXmlImport parsed=MidiImport.read(restored);List<String> warnings=new ArrayList<>();
  Score score=SongDraft.parse(parsed.draft(0,0,warnings)).segments().get(0);
  check(score.count()==1&&score.degree(0)==1,"Returned bytes reach actual seven-key score conversion");
  reject(()->WebScoreStage.take(cache.toFile(),staged.getPath()));
  LibraryWebTests.Reply login=new LibraryWebTests.Reply(endpoint,200,b("<!DOCTYPE html><html>请登录后下载</html>"));
  ScoreWebImport.Download page=ScoreWebImport.fetch(endpoint,null,null,null,url->login);
  check(page.kind==ScoreWebImport.Kind.PAGE,"A successful HTTP response can still be a login page");
  reject(()->WebScoreStage.save(cache.toFile(),page.data,"pretend.mid"));
  reject(()->WebScoreStage.save(cache.toFile(),b("MThdgarbage"),"broken.mid"));
  reject(()->WebScoreStage.save(cache.toFile(),new byte[ScoreWebImport.LIMIT+1],"large.mid"));
  File outside=cache.resolve("score-external.download").toFile();Files.write(outside.toPath(),midi);
  reject(()->WebScoreStage.take(cache.toFile(),outside.getPath()));check(outside.isFile(),"Rejecting another path does not delete it");
  reject(()->WebScoreStage.take(cache.toFile(),cache.toFile().getPath()));
  File abandoned=WebScoreStage.save(cache.toFile(),midi,"a.mid");WebScoreStage.discard(cache.toFile(),abandoned);check(!abandoned.exists(),"Cancelled handoff cleaned up");
  Thread.currentThread().interrupt();try{reject(()->WebScoreStage.save(cache.toFile(),midi,"a.mid"));}finally{Thread.interrupted();}
  File interrupted=WebScoreStage.save(cache.toFile(),midi,"a.mid");Thread.currentThread().interrupt();try{reject(()->WebScoreStage.take(cache.toFile(),interrupted.getPath()));}finally{Thread.interrupted();}check(!interrupted.exists(),"Cancelled read cleaned up");
  File big=WebScoreStage.save(cache.toFile(),midi,"a.mid");try(RandomAccessFile file=new RandomAccessFile(big,"rw")){file.setLength(ScoreWebImport.LIMIT+1L);}reject(()->WebScoreStage.take(cache.toFile(),big.getPath()));check(!big.exists(),"Oversized staged file rejected and cleaned up");
  System.out.println("PASS MidiShow: "+checks+" checks; encoded Chinese/foreign search, sorting, same-origin session download, real MIDI-to-score handoff, login/corruption rejection, bounded private files and cancellation. Website authentication and physical Android not tested.");
 }
}
