package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.MidiSystem;
public final class FreeMidiTests {
 static int checks;interface Work{void run()throws Exception;}
 static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
 static void reject(Work work)throws Exception{try{work.run();}catch(IOException e){checks++;return;}throw new AssertionError("Accepted invalid free-source input");}
 static LibraryWebTests.Reply reply(String url,int code,byte[] data)throws IOException{try{return new LibraryWebTests.Reply(url,code,data);}catch(Exception e){throw new IOException(e);}}
 static String text(Path p)throws IOException{return new String(Files.readAllBytes(p),StandardCharsets.UTF_8);}
 static void preserved(OriginalScore source,OriginalScoreStore store,String title,String origin)throws Exception{
  OriginalScoreStore.Entry saved=store.save(null,title,origin,source);OriginalScore loaded=store.load(saved);
  check(Arrays.equals(source.bytes(),loaded.bytes()),"MIDI bytes, tracks, chromatic pitches and octaves unchanged");
  check(MidiSystem.getSequence(new ByteArrayInputStream(loaded.bytes())).getTracks().length>0,"Independent JDK MIDI reader");
  check(source.noteCount==loaded.noteCount&&source.noteCount>0,"All notes retained");
  for(int t=0;t<source.parsed.tracks.size();t++){
   List<MusicXmlImport.Note> a=source.parsed.tracks.get(t).notes,b=loaded.parsed.tracks.get(t).notes;check(a.size()==b.size(),"Voice note count");
   for(int n=0;n<a.size();n++)check(a.get(n).pitch==b.get(n).pitch&&a.get(n).at==b.get(n).at&&a.get(n).duration==b.get(n).duration,"Every note unchanged");
  }
 }
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),v=root.getParent().resolve("verification/free_sources_20261024"),f=v.resolve("fixtures");
  OriginalScoreStore store=new OriginalScoreStore(Files.createTempDirectory(v,"roundtrip_").toFile());
  if(args.length>1&&args[1].equals("--live")){
   FreeMidiSource.Page search=FreeMidiSource.fetch("",0);check(search.items.size()>0,"Live free catalog");
   for(String slug:new String[]{"queen-bohemian-rhapsody-mid","never-gonna-give-you-up-3-mid","pirates-of-the-caribbean-hes-a-pirate-3-mid"}){
    FreeMidiSource.Item selected=search.items.stream().filter(x->x.page.equals("https://bitmidi.com/"+slug)).findFirst().orElseThrow(()->new IOException("Known sample missing from live catalog"));
    Thread.sleep(2500);OriginalScore document=FreeMidiSource.download(selected);
    preserved(document,store,slug,"https://bitmidi.com/"+slug);
    System.out.println("LIVE "+slug+" notes="+document.noteCount+" voices="+document.parsed.tracks.size()+" sha256="+document.sha256());
   }
   System.out.println("PASS live free MIDI: "+checks+" checks; real HTTPS search/download, production original parser, full-file store/readback; not Android/BLE");return;
  }
  check(FreeMidiSource.search("",0).equals("https://bitmidi.com/?page=0"),"Explicit page on popular catalog");
  String query="周杰伦 & A/B +#?";String url=FreeMidiSource.search(query,3);Map<String,String> params=new HashMap<>();for(String pair:URI.create(url).getRawQuery().split("&")){String[] s=pair.split("=",2);params.put(s[0],URLDecoder.decode(s[1],"UTF-8"));}
  check(params.size()==2&&params.get("q").equals(query)&&params.get("page").equals("3"),"Query encoded without injected parameters");
  reject(()->FreeMidiSource.search("x\ny",0));reject(()->FreeMidiSource.search("",-1));reject(()->FreeMidiSource.search("",10001));reject(()->FreeMidiSource.search(String.join("",Collections.nCopies(121,"x")),0));
  for(String bad:new String[]{"http://bitmidi.com/a","https://bitmidi.com.evil.test/a","https://evil.test/?h=bitmidi.com","https://u:p@bitmidi.com/a","https://bitmidi.com:444/a"})check(!FreeMidiSource.owns(bad),"Origin guarded");
  FreeMidiSource.Page home=FreeMidiSource.parse(text(f.resolve("bit-home.html"))),page=FreeMidiSource.parse(text(f.resolve("bit-page1.html"))),result=FreeMidiSource.parse(text(f.resolve("bit-bohemian.html"))),empty=FreeMidiSource.parse(text(f.resolve("bit-chinese.html")));
  check(home.total==113229&&home.items.size()==15&&home.next,"Actual public catalog rows");check(page.total==home.total&&page.next&&!home.items.get(0).page.equals(page.items.get(0).page),"Actual next page, not repeated first page");
  check(result.total==7&&result.items.size()==7&&!result.next,"Actual Bohemian search");check(empty.total==0&&empty.items.isEmpty()&&!empty.next,"Actual Chinese no-results page");
  check(home.items.stream().anyMatch(i->i.title.equals("Queen - Bohemian Rhapsody.mid")),"Names decoded");
  check(FreeMidiSource.text("<b>A &#39; &amp; &#x1f3b5;</b>").equals("A ' & 🎵"),"Entities, no markup");
  String one="<a href='/a-mid'><h2>A &amp; B.mid</h2></a><small>1 results</small>\"url\":\"/a-mid\",\"downloadUrl\":\"/uploads/1.mid\"";check(FreeMidiSource.parse(one).items.size()==1,"Attribute order independent");
  reject(()->FreeMidiSource.parse("<html>sign in or pay</html>"));reject(()->FreeMidiSource.parse("1 results"));reject(()->FreeMidiSource.parse("<a href='https://evil.test/a-mid'><h2>X</h2></a>1 results"));
  String file="https://bitmidi.com/uploads/87216.mid",detail="https://bitmidi.com/queen-bohemian-rhapsody-mid";
  check(FreeMidiSource.downloadLink(text(f.resolve("queen.html")),detail).equals(file),"Visible actual download anchor");
  reject(()->FreeMidiSource.downloadLink("<a href='https://evil.test/x.mid'>Download</a>",detail));reject(()->FreeMidiSource.downloadLink("<a href='/uploads/1.mid'>Play</a>",detail));reject(()->FreeMidiSource.downloadLink(text(f.resolve("queen.html")),"https://evil.test/a"));
  byte[] html=Files.readAllBytes(f.resolve("queen.html")),raw=Files.readAllBytes(f.resolve("queen.mid"));List<String> requests=new ArrayList<>();
  OriginalScore downloaded=FreeMidiSource.download(new FreeMidiSource.Item("Queen",detail),address->{requests.add(address.toString());return reply(address.toString(),200,address.toString().equals(detail)?html:raw);});
  FreeMidiSource.Item linked=home.items.stream().filter(x->x.page.equals(detail)).findFirst().get();requests.clear();
  OriginalScore direct=FreeMidiSource.download(linked,address->{requests.add(address.toString());return reply(address.toString(),200,raw);});
  check(requests.equals(Arrays.asList(file))&&Arrays.equals(raw,direct.bytes()),"Search public file metadata avoids a redundant website request");
  requests.clear();FreeMidiSource.download(new FreeMidiSource.Item("Queen",detail),address->{requests.add(address.toString());return reply(address.toString(),200,address.toString().equals(detail)?html:raw);});
  check(requests.equals(Arrays.asList(detail,file)),"Two public GETs, no account/payment/private endpoint");check(Arrays.equals(downloaded.bytes(),raw),"Production direct downloader retains all MIDI bytes");
  reject(()->FreeMidiSource.download(new FreeMidiSource.Item("Queen",detail),address->reply(address.toString(),200,html)));
  reject(()->FreeMidiSource.download(new FreeMidiSource.Item("Queen",detail),address->reply(address.toString(),403,html)));
  reject(()->FreeMidiSource.download(new FreeMidiSource.Item("Queen",detail),address->reply(address.toString(),200,address.toString().equals(detail)?html:new byte[]{'M','T','h','d'})));
  for(String name:new String[]{"queen","never","pirate","chinafolk","mutopia","oga","海阔天空","情人","失恋阵线联盟"}){
   OriginalScore source=OriginalScore.read(Files.readAllBytes(f.resolve(name+".mid")),name+".mid");preserved(source,store,name,"free HTTPS real sample");
   System.out.println("FILE "+name+" notes="+source.noteCount+" voices="+source.parsed.tracks.size());
  }
  String web=text(root.resolve("studio.html")),feature=text(root.resolve("src/cn/fpga/score/FeaturePanel.java"));
  check(web.contains("免费搜谱")&&web.contains("send('free-midi'"),"Visible free search routes to native downloader");
  check(web.contains("search(value,source='all')")&&web.contains("'chinese','bundled','pop','expanded','all'"),"Free source shortcut preserves query and category");
  check(feature.contains("public void freeMidi")&&feature.contains("FreeMidiSource.download(item)")&&feature.contains("originalReview(document,item.title,item.page,null)"),"Actual import handoff, not just website bookmark");
  check(feature.contains("public void original")&&feature.contains("导入乐器"),"Native-pitch upload still available");
  System.out.println("PASS free MIDI: "+checks+" checks; live-page fixtures, paged public search, 9 real MIDI originals retained, download rejection; not Android/BLE");
 }
}
