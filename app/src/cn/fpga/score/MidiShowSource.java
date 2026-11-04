package cn.fpga.score;
import java.io.IOException;
import java.net.*;
import java.util.Locale;
/** Normal website navigation; no private API or simulated login. */
public final class MidiShowSource {
 public static final String POP="https://www.midishow.com/midi/browse/pop-music";
 public static final String LOGIN="https://www.midishow.com/user/account/login";
 public static String search(String query,String order)throws IOException{
  String q=query==null?"":query.trim();
  if(q.length()>120||q.matches("(?s).*[\\p{Cntrl}].*"))throw new IOException("请使用不超过 120 字的歌名或歌手名");
  String sort;
  if("newest".equals(order))sort="time_desc";
  else if("popular".equals(order))sort="popularity";
  else if(order==null||"relevance".equals(order))sort="default";
  else throw new IOException("无效的曲谱排序");
  if(q.isEmpty())return POP+"?sort="+sort;
  return "https://www.midishow.com/search/result?q="+URLEncoder.encode(q,"UTF-8")+"&sort="+sort;
 }
 public static boolean owns(String value){
  try{URI u=URI.create(value);String h=u.getHost();return "https".equalsIgnoreCase(u.getScheme())&&u.getUserInfo()==null&&(u.getPort()==-1||u.getPort()==443)&&("midishow.com".equalsIgnoreCase(h)||"www.midishow.com".equalsIgnoreCase(h));}
  catch(Exception e){return false;}
 }
 public static String title(String title){
  if(title==null)return "MidiShow 曲谱";
  String s=title.replaceFirst("(?i)\\s+MIDI\\s+(?:音乐下载试听|File Download).*","").replaceFirst("(?i)\\s*::\\s*MidiShow.*","").replaceAll("[\\p{Cntrl}]","").trim();
  return s.isEmpty()?"MidiShow 曲谱":s.substring(0,Math.min(180,s.length()));
 }
 public static String filename(String name,String pageTitle){
  if(name!=null&&name.toLowerCase(Locale.ROOT).matches(".*\\.(mid|midi|xml|musicxml|mxl|txt|png|jpe?g|gif|webp)$"))return name;
  return title(pageTitle);
 }
}
