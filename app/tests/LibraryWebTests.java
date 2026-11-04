package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
public final class LibraryWebTests {
 static int checks;
 interface Work{void run()throws Exception;}
 static void check(boolean okay,String message){checks++;if(!okay)throw new AssertionError(message);}
 static void reject(Work task,String part)throws Exception{try{task.run();}catch(IOException e){check(e.getMessage().contains(part),e.getMessage());return;}throw new AssertionError("Accepted invalid input: "+part);}
 static byte[] b(String text){return text.getBytes(StandardCharsets.UTF_8);}
 static final class Reply extends HttpURLConnection {
  final int status;final byte[] body;final Map<String,String> response=new HashMap<>(),sent=new HashMap<>();boolean closed;long length;
  Reply(String url,int code,byte[] bytes)throws Exception{super(new URL(url));status=code;body=bytes;length=bytes.length;}
  public int getResponseCode(){return status;}public InputStream getInputStream(){return new ByteArrayInputStream(body);}
  public String getHeaderField(String name){return response.get(name);}public String getContentType(){return response.get("Content-Type");}
  public long getContentLengthLong(){return length;}public void setRequestProperty(String key,String value){sent.put(key,value);}
  public void disconnect(){closed=true;}public void connect(){}public boolean usingProxy(){return false;}
 }
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]);
  check(ScoreWebImport.extractUrl("115566")==null,"Plain score stays text");
  check(ScoreWebImport.extractUrl("谱：https://example.com/a.mid）。").equals("https://example.com/a.mid"),"Share URL strips Chinese punctuation");
  check(ScoreWebImport.normalize("https://github.com/a/b/blob/main/a.mid").equals("https://raw.githubusercontent.com/a/b/main/a.mid"),"GitHub file page becomes raw");
  check(ScoreWebImport.normalize("https://github.com/a/b/blob/main/README.md").contains("/blob/"),"Non-score GitHub pages stay pages");
  reject(()->ScoreWebImport.normalize("file:///secret"),"HTTPS");reject(()->ScoreWebImport.normalize("javascript:alert(1)"),"HTTPS");
  reject(()->ScoreWebImport.normalize("https://u:p@example.com/a.mid"),"HTTPS");reject(()->ScoreWebImport.normalize("https://example.com/a.mid\nX:"),"无效");
  check(ScoreWebImport.fileLink("https://example.com/a.MXL?token=x"),"Extension with query");
  check(!ScoreWebImport.fileLink("https://example.com/songs/123"),"Ordinary webpage is not a file link");
  check(ScoreWebImport.name("https://example.com/download","attachment; filename*=UTF-8''%E8%8A%B1%E6%B5%B7.mid").equals("花海.mid"),"RFC 5987 filename");
  check(ScoreWebImport.name("https://example.com/download","attachment; filename=\"../../a.mid\"").equals("a.mid"),"Filename cannot supply a path");
  check(ScoreWebImport.classify(b("MThdabc"),"text/html","x")==ScoreWebImport.Kind.MIDI,"Magic beats MIME");
  check(ScoreWebImport.classify(b("<!doctype html><html>login</html>"),"audio/midi","x.mid")==ScoreWebImport.Kind.PAGE,"Login HTML not treated as MIDI");
  check(ScoreWebImport.classify(b("<?xml version='1.0'?><score-partwise/>"),null,"x")==ScoreWebImport.Kind.XML,"XML sniffing");
  check(ScoreWebImport.classify(new byte[]{80,75,3,4},null,"x")==ScoreWebImport.Kind.MXL,"Compressed score is parsed by MXL reader");
  check(ScoreWebImport.classify(b("BPM=120\n1,4\n"),null,"x")==ScoreWebImport.Kind.TEXT,"Numbered score");
  check(ScoreWebImport.classify(b("# comment\nBPM=120\n1,4\n"),null,"x.txt")==ScoreWebImport.Kind.TEXT,"Commented text keeps compatibility");
  check(ScoreWebImport.classify(new byte[]{(byte)137,80,78,71},null,"x")==ScoreWebImport.Kind.IMAGE,"PNG route");
  check(ScoreWebImport.classify(new byte[]{(byte)255,(byte)216,0,0},null,"x")==ScoreWebImport.Kind.IMAGE,"JPEG route");
  reject(()->ScoreWebImport.classify(b("%PDF-1.7"),null,"x.pdf"),"PDF");reject(()->ScoreWebImport.classify(b("ID3audio"),null,"x.mp3"),"MP3");reject(()->ScoreWebImport.classify(new byte[0],null,"x"),"为空");
  Reply redirect=new Reply("https://a.test/download",302,new byte[0]);redirect.response.put("Location","https://b.test/actual.mid");
  Reply midi=new Reply("https://b.test/actual.mid",200,b("MThdabc"));
  Queue<Reply> chain=new ArrayDeque<>(Arrays.asList(redirect,midi));
  ScoreWebImport.Download downloaded=ScoreWebImport.fetch("https://a.test/download","test-agent","session=private","https://a.test/page",url->chain.remove());
  check(downloaded.kind==ScoreWebImport.Kind.MIDI&&downloaded.url.equals("https://b.test/actual.mid"),"Follows bounded HTTPS redirects");
  check("session=private".equals(redirect.sent.get("Cookie"))&&!midi.sent.containsKey("Cookie")&&!midi.sent.containsKey("Referer"),"Credentials do not cross origins");
  check(redirect.closed&&midi.closed,"Connections closed after redirects");
  Reply oversized=new Reply("https://a.test/file",200,b("MThdabc"));oversized.length=ScoreWebImport.LIMIT+1L;
  reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->oversized),"8 MB");check(oversized.closed,"Oversized response closed");
  Reply forbidden=new Reply("https://a.test/file",403,new byte[0]);reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->forbidden),"HTTP 403");
  Reply limited=new Reply("https://a.test/file",429,new byte[0]);reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->limited),"限制下载频率");check(limited.closed,"Rate-limited response closed");
  Reply downgrade=new Reply("https://a.test/file",302,new byte[0]);downgrade.response.put("Location","http://a.test/file");
  reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->downgrade),"HTTPS");
  Reply loop=new Reply("https://a.test/file",302,new byte[0]);loop.response.put("Location","/file");reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->loop),"跳转次数");
  Thread.currentThread().interrupt();try{reject(()->ScoreWebImport.fetch("https://a.test/file",null,null,null,url->midi),"取消");}finally{Thread.interrupted();}
  check(SongShare.musicLink("https://t3.kugou.com/song.html?x=1"),"Recognize Kugou shares");check(!SongShare.musicLink("https://kugou.com.evil.test/a"),"Exact music host boundary");
  check(SongShare.title("分享周杰伦的单曲《花海》 https://t3.kugou.com/x").equals("花海"),"Title is a search hint");check(SongShare.title("https://t3.kugou.com/x").isEmpty(),"Do not invent a title for URL-only shares");
  List<OpenCatalog.Item> items=OpenCatalog.read(Files.newInputStream(root.resolve("vendor/open_catalog.tsv")));
  check(items.size()==6858,"Actual new catalog count");Set<String> ids=new HashSet<>(),sha=new HashSet<>();
  for(OpenCatalog.Item item:items){check(ids.add(item.id)&&sha.add(item.sha1),"Unique file identity");check(item.sha1.matches("[a-f0-9]{40}"),"Valid SHA1");check(item.page.startsWith("https://commons.wikimedia.org/"),"Original file page retained");}
  for(String query:new String[]{"Bach","Mozart","Beethoven","民歌",""})for(OpenCatalog.Item item:OpenCatalog.search(items,query))check(item.search.contains(OpenCatalog.normalize(query)),"Search terms match returned row");
  int pages=0,seen=0;
  for(int total:new int[]{0,1,59,60,61,909,6858,95923,103803}){
   Set<Integer> visited=new HashSet<>();for(int page=0;page<Math.max(1,(total+59)/60);page++){
    CatalogPager pager=new CatalogPager(total,page);check(pager.to-pager.from<=60,"Page window bounded");for(int i=pager.from;i<pager.to;i++)check(visited.add(i),"No duplicate or skipped page rows");pages++;
   }
   check(visited.size()==total,"Entire catalog is reachable");check(new CatalogPager(total,Integer.MAX_VALUE).page==Math.max(0,(total-1)/60),"Page clamps safely");seen+=total;
  }
  System.out.println("PASS library_web: "+checks+" checks; "+items.size()+" new source records; "+pages+" page windows covering "+seen+" rows; file/page/image routing, shared song titles, redirects, credential boundaries, cancellation and malformed inputs.");
 }
}
