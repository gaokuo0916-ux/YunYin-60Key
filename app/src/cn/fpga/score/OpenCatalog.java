package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.*;
/** Only metadata is bundled. Original MIDI is downloaded after selection. */
public final class OpenCatalog {
 public static final class Item {
  public final String id,title,artist,url,license,page,licenseUrl,sha1;
  final String search;
  Item(String[] c){id=c[0];title=c[1];artist=c[2];url=c[3];license=c[4];page=c[5];licenseUrl=c[6];sha1=c[7];search=normalize(title+" "+artist);}
 }
 static String normalize(String text){return Normalizer.normalize(text.toLowerCase(Locale.ROOT),Normalizer.Form.NFKD).replaceAll("\\p{M}","");}
 public static List<Item> read(InputStream stream)throws IOException{
  List<Item> result=new ArrayList<>();Set<String> ids=new HashSet<>();
  try(BufferedReader reader=new BufferedReader(new InputStreamReader(stream,StandardCharsets.UTF_8))){String line;while((line=reader.readLine())!=null){
   String[] c=line.split("\t",-1);
   if(c.length!=8||!c[0].matches("[0-9]+")||c[1].isEmpty()||!c[3].startsWith("https://upload.wikimedia.org/wikipedia/commons/")||!c[5].startsWith("https://commons.wikimedia.org/")||!ids.add(c[0])||result.size()>=20000)throw new IOException("开放曲库目录校验失败");
   result.add(new Item(c));
  }}return result;
 }
 public static List<Item> search(List<Item> rows,String query){
  String[] words=normalize(query.trim()).split("\\s+");List<Item> result=new ArrayList<>();
  for(Item row:rows){boolean match=true;for(String word:words)match&=row.search.contains(word);if(match)result.add(row);}return result;
 }
}
