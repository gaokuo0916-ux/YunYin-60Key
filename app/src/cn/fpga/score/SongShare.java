package cn.fpga.score;
import java.net.URI;
import java.util.regex.*;
/** Song shares supply search words only; they are not symbolic scores. */
public final class SongShare {
 public static boolean musicLink(String url){try{String host=URI.create(url).getHost().toLowerCase(java.util.Locale.ROOT);return host.equals("kugou.com")||host.endsWith(".kugou.com")||host.equals("kugou.net")||host.endsWith(".kugou.net")||host.equals("music.163.com")||host.endsWith(".y.qq.com")||host.equals("y.qq.com");}catch(Exception e){return false;}}
 public static String title(String text){Matcher m=Pattern.compile("《([^《》\\r\\n]{1,120})》").matcher(text);return m.find()?m.group(1).trim():"";}
}
