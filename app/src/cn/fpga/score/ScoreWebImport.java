package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.regex.*;
import javax.net.ssl.HttpsURLConnection;

/** Shared link handling for paste, Android sharing, and the score browser. */
public final class ScoreWebImport {
 public static final int LIMIT=8*1024*1024;
 public enum Kind { MIDI,XML,MXL,TEXT,IMAGE,PAGE }
 public static final class Download {
  public final byte[] data;public final String url,name,mime;public final Kind kind;
  Download(byte[] b,String u,String n,String m)throws IOException{data=b;url=u;name=n;mime=m;kind=classify(b,m,n);}
 }
 interface Connector {HttpURLConnection open(URL url)throws IOException;}
 public static String extractUrl(String text)throws IOException{
  if(text==null)return null;
  Matcher m=Pattern.compile("https?://[^\\s<>\"\u3000]+",Pattern.CASE_INSENSITIVE).matcher(text);
  if(!m.find())return null;
  String value=m.group();while(!value.isEmpty()&&"，。；、）】》’'\"".indexOf(value.charAt(value.length()-1))>=0)value=value.substring(0,value.length()-1);
  return normalize(value);
 }
 public static String normalize(String value)throws IOException{
  if(value==null||value.length()>4096||value.matches("(?s).*[\\r\\n\\t].*"))throw new IOException("链接无效或过长");
  try{
   URI uri=new URI(value.trim().replace(" ","%20"));
   if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null)
    throw new IOException("请使用 HTTPS 曲谱链接；本地文件请从“导入文件”选择");
   String path=uri.getRawPath();
   if("github.com".equalsIgnoreCase(uri.getHost())&&path!=null&&path.matches("/[^/]+/[^/]+/blob/.+")&&fileName(path).matches("(?i).*\\.(mid|midi|mxl|musicxml|xml|txt)$"))
    return "https://raw.githubusercontent.com"+path.replaceFirst("/blob/","/");
   return uri.toASCIIString();
  }catch(URISyntaxException e){throw new IOException("链接格式有误",e);}
 }
 public static boolean fileLink(String value){
  try{return fileName(URI.create(value).getPath()).matches("(?i).*\\.(mid|midi|mxl|musicxml|xml|txt|png|jpe?g|webp|gif)$");}
  catch(Exception e){return false;}
 }
 private static String fileName(String path){if(path==null)return "曲谱";return path.substring(path.lastIndexOf('/')+1);}
 public static String name(String url,String disposition){
  String value="";
  if(disposition!=null){
   Matcher utf=Pattern.compile("(?i)filename\\*\\s*=\\s*UTF-8''([^;]+)").matcher(disposition);
   Matcher plain=Pattern.compile("(?i)filename\\s*=\\s*\"?([^\";]+)").matcher(disposition);
   try{if(utf.find())value=URLDecoder.decode(utf.group(1).trim(),"UTF-8");else if(plain.find())value=plain.group(1).trim();}catch(Exception ignored){}
  }
  if(value.isEmpty())try{value=fileName(URI.create(url).getPath());}catch(Exception ignored){}
  value=value.replace('\\','/');value=fileName(value).replaceAll("[\\p{Cntrl}]","").trim();
  return value.isEmpty()?"网上曲谱":value.substring(0,Math.min(180,value.length()));
 }
 public static Kind classify(byte[] data,String mime,String name)throws IOException{
  if(data==null||data.length==0)throw new IOException("下载内容为空");
  if(data.length>LIMIT)throw new IOException("曲谱文件超过 8 MB，请分段导入");
  String head=new String(data,0,Math.min(data.length,1024),StandardCharsets.UTF_8).replace("\uFEFF","").trim().toLowerCase(Locale.ROOT);
  if(head.startsWith("<!doctype html")||head.startsWith("<html")||head.contains("<html ")||head.contains("<html>"))return Kind.PAGE;
  if(data.length>=4&&data[0]=='M'&&data[1]=='T'&&data[2]=='h'&&data[3]=='d')return Kind.MIDI;
  if(data.length>=4&&data[0]=='%'&&data[1]=='P'&&data[2]=='D'&&data[3]=='F')throw new IOException("这是 PDF 曲谱。请导出 MIDI / MusicXML，或将谱页保存成图片后使用图片识谱");
  if(data.length>=4&&((data[0]&255)==137&&data[1]=='P'&&data[2]=='N'&&data[3]=='G'||(data[0]&255)==255&&(data[1]&255)==216||data[0]=='G'&&data[1]=='I'&&data[2]=='F')||data.length>=12&&data[0]=='R'&&data[1]=='I'&&data[2]=='F'&&data[3]=='F'&&data[8]=='W'&&data[9]=='E'&&data[10]=='B'&&data[11]=='P')return Kind.IMAGE;
  if(data.length>=2&&data[0]=='P'&&data[1]=='K')return Kind.MXL;
  if(head.startsWith("<?xml")||head.startsWith("<score-partwise")||head.startsWith("<score-timewise"))return Kind.XML;
  if(head.startsWith("bpm=")||head.startsWith("begin ")||head.startsWith("#")||head.matches("(?s)[0-7\\s|]+")||head.matches("(?s)[0-7]\\s*,.*")||name!=null&&name.toLowerCase(Locale.ROOT).endsWith(".txt"))return Kind.TEXT;
  if(mime!=null&&mime.toLowerCase(Locale.ROOT).contains("text/html"))return Kind.PAGE;
  throw new IOException("下载内容不是可识别的 MIDI、MusicXML、数字简谱或图片；网页中的播放器、MP3 和视频不能直接转成跟弹谱");
 }
 private static boolean sameOrigin(URL a,URL b){return a.getProtocol().equalsIgnoreCase(b.getProtocol())&&a.getHost().equalsIgnoreCase(b.getHost())&&a.getPort()==b.getPort();}
 public static Download fetch(String input,String agent,String cookie,String referer)throws IOException{
  return fetch(input,agent,cookie,referer,url->(HttpsURLConnection)url.openConnection());
 }
 static Download fetch(String input,String agent,String cookie,String referer,Connector connector)throws IOException{
  URL original=new URL(normalize(input)),current=original;
  for(int hop=0;hop<=5;hop++){
   if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("下载已取消");
   HttpURLConnection connection=connector.open(current);
   try{
    connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(12000);connection.setReadTimeout(15000);
    connection.setRequestProperty("User-Agent",agent==null||agent.isEmpty()?"YunYinScore/2.5.8":agent);
    if(sameOrigin(original,current)){
     if(cookie!=null&&!cookie.isEmpty()&&!cookie.contains("\r")&&!cookie.contains("\n"))connection.setRequestProperty("Cookie",cookie);
     if(referer!=null)try{URL r=new URL(referer);if(sameOrigin(original,r))connection.setRequestProperty("Referer",referer);}catch(Exception ignored){}
    }
    int status=connection.getResponseCode();
    if(status==301||status==302||status==303||status==307||status==308){
     String location=connection.getHeaderField("Location");if(location==null)throw new IOException("下载重定向缺少地址");
     current=new URL(normalize(new URL(current,location).toString()));continue;
    }
    if(status==429)throw new IOException("网站暂时限制下载频率（HTTP 429），请稍后重试");
    if(status!=200)throw new IOException("下载未成功（HTTP "+status+"）；需要登录的网站请先在搜谱浏览器中登录并点击下载");
    if(connection.getContentLengthLong()>LIMIT)throw new IOException("曲谱文件超过 8 MB");
    ByteArrayOutputStream out=new ByteArrayOutputStream();
    try(InputStream in=connection.getInputStream()){
     byte[] buffer=new byte[8192];int n;
     while((n=in.read(buffer))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("下载已取消");if(out.size()+n>LIMIT)throw new IOException("曲谱文件超过 8 MB");out.write(buffer,0,n);}
    }
    return new Download(out.toByteArray(),current.toString(),name(current.toString(),connection.getHeaderField("Content-Disposition")),connection.getContentType());
   }finally{connection.disconnect();}
  }
  throw new IOException("下载跳转次数过多，请打开最终曲谱文件链接");
 }
}
