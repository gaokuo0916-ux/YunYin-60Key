package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;
/** Public BitMidi HTML and its visible MIDI download link. No login or private API. */
public final class FreeMidiSource {
 public static final String HOME="https://bitmidi.com/";
 public static final class Item {
  public final String title,page,download;
  Item(String title,String page){this(title,page,null);}
  Item(String title,String page,String download){this.title=title;this.page=page;this.download=download;}
 }
 public static final class Page {
  public final List<Item> items;public final int total;public final boolean next;
  Page(List<Item> items,int total,boolean next){this.items=Collections.unmodifiableList(items);this.total=total;this.next=next;}
 }
 public static String search(String query,int page)throws IOException{
  String q=query==null?"":query.trim();
  if(q.length()>120||q.matches("(?s).*[\\p{Cntrl}].*")||page<0||page>10000)throw new IOException("请使用不超过120字的关键词和有效页码");
  return HOME+(q.isEmpty()?"?page="+page:"search?q="+URLEncoder.encode(q,"UTF-8")+"&page="+page);
 }
 static boolean owns(String url){try{URI u=new URI(url);return "https".equalsIgnoreCase(u.getScheme())&&"bitmidi.com".equalsIgnoreCase(u.getHost())&&u.getUserInfo()==null&&(u.getPort()==-1||u.getPort()==443);}catch(Exception e){return false;}}
 private static String attr(String tag,String key){Matcher m=Pattern.compile("(?i)(?:^|\\s)"+key+"\\s*=\\s*([\"'])(.*?)\\1",Pattern.DOTALL).matcher(tag);return m.find()?m.group(2):"";}
 static String text(String value){
  String s=value.replaceAll("(?s)<[^>]*>","");
  Matcher m=Pattern.compile("&#(x[0-9a-fA-F]+|[0-9]+);").matcher(s);StringBuffer b=new StringBuffer();
  while(m.find()){String replacement="";try{String n=m.group(1);int cp=n.startsWith("x")?Integer.parseInt(n.substring(1),16):Integer.parseInt(n);if(Character.isValidCodePoint(cp)&&!(cp>=0xD800&&cp<=0xDFFF))replacement=new String(Character.toChars(cp));}catch(Exception ignored){}m.appendReplacement(b,Matcher.quoteReplacement(replacement));}m.appendTail(b);
  return b.toString().replace("&quot;","\"").replace("&#39;","'").replace("&apos;","'").replace("&nbsp;"," ").replace("&lt;","<").replace("&gt;",">").replace("&amp;","&").replaceAll("[\\p{Cntrl}]","").trim();
 }
 public static Page parse(String html)throws IOException{
  if(html==null||html.length()>1024*1024)throw new IOException("免费曲库页面过大或为空");
  Matcher count=Pattern.compile("([0-9][0-9,]*)\\s+results\\b").matcher(html);
  if(!count.find())throw new IOException("免费曲库页面格式已变化，未读取到有效结果；可重试或改用离线曲库");
  int total;try{total=Integer.parseInt(count.group(1).replace(",",""));}catch(Exception e){throw new IOException("曲库数量无效",e);}
  if(total>10000000)throw new IOException("曲库数量超限");
  LinkedHashMap<String,Item> rows=new LinkedHashMap<>();boolean next=false;
  Matcher anchors=Pattern.compile("<a\\b([^>]*)>(.*?)</a>",Pattern.CASE_INSENSITIVE|Pattern.DOTALL).matcher(html);
  while(anchors.find()){
   String href=text(attr(anchors.group(1),"href")),body=anchors.group(2);
   if(text(body).startsWith("Next")&&(href.startsWith("/?page=")||href.startsWith("/search?")))next=true;
   if(!href.matches("/[a-z0-9_-]{1,240}")||!Pattern.compile("(?is)<h2\\b").matcher(body).find())continue;
   String title=text(body);if(title.isEmpty()||title.length()>500)throw new IOException("曲名无效");
   Matcher meta=Pattern.compile("\"url\":\""+Pattern.quote(href)+"\",\"downloadUrl\":\"(/uploads/[0-9]{1,12}\\.mid)\"").matcher(html);
   if(!meta.find())throw new IOException("曲库未提供对应的公开MIDI文件地址，未误导入其他音频");
   rows.put(href,new Item(title,HOME+href.substring(1),HOME+meta.group(1).substring(1)));if(rows.size()>100)throw new IOException("单页结果过多");
  }
  if(total>0&&rows.isEmpty()||total==0&&!rows.isEmpty())throw new IOException("免费曲库列表与数量不一致，未将页面误当曲谱");
  return new Page(new ArrayList<>(rows.values()),total,next);
 }
 public static String downloadLink(String html,String page)throws IOException{
  if(!owns(page)||!URI.create(page).getPath().matches("/[a-z0-9_-]{1,240}")||html==null||html.length()>1024*1024)throw new IOException("曲谱来源或详情页无效");
  Matcher a=Pattern.compile("<a\\b([^>]*)>(.*?)</a>",Pattern.CASE_INSENSITIVE|Pattern.DOTALL).matcher(html);
  while(a.find()){String path=attr(a.group(1),"href");if(path.matches("/uploads/[0-9]{1,12}\\.mid")&&text(a.group(2)).startsWith("Download"))return HOME+path.substring(1);}
  throw new IOException("详情页没有公开的MIDI下载链接，请选其他版本；未下载播放器音频");
 }
 private static ScoreWebImport.Download get(String url,ScoreWebImport.Connector connector)throws IOException{
  if(!owns(url))throw new IOException("免费曲库地址不匹配");
  ScoreWebImport.Download d=ScoreWebImport.fetch(url,"YunYinScore/2.5.13",null,null,connector);
  if(!owns(d.url))throw new IOException("免费曲库跳转到了其他网站，已停止读取");return d;
 }
 public static Page fetch(String q,int page)throws IOException{return fetch(q,page,url->(HttpURLConnection)url.openConnection());}
 static Page fetch(String q,int page,ScoreWebImport.Connector connector)throws IOException{
  ScoreWebImport.Download d=get(search(q,page),connector);if(d.kind!=ScoreWebImport.Kind.PAGE)throw new IOException("网站没有返回搜索页面");return parse(new String(d.data,StandardCharsets.UTF_8));
 }
 public static OriginalScore download(Item item)throws IOException{return download(item,url->(HttpURLConnection)url.openConnection());}
 static OriginalScore download(Item item,ScoreWebImport.Connector connector)throws IOException{
  if(item==null||!owns(item.page))throw new IOException("尚未选择有效曲谱");String url=item.download;
  if(url==null){ScoreWebImport.Download page=get(item.page,connector);
  if(page.kind!=ScoreWebImport.Kind.PAGE)throw new IOException("未取得曲谱详情页");
  url=downloadLink(new String(page.data,StandardCharsets.UTF_8),item.page);}
  if(!owns(url)||!URI.create(url).getPath().matches("/uploads/[0-9]{1,12}\\.mid"))throw new IOException("公开MIDI下载地址无效");
  ScoreWebImport.Download d=get(url,connector);
  if(d.kind!=ScoreWebImport.Kind.MIDI)throw new IOException("下载内容不是MIDI，未导入登录页、广告或音频");
  try{return OriginalScore.read(d.data,item.title);}catch(Exception e){throw new IOException("MIDI原谱解析失败："+e.getMessage(),e);}
 }
}
