package cn.fpga.score;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.*;
import java.util.regex.*;
import javax.net.ssl.HttpsURLConnection;

/** Real public MusicXML catalog. No audio search masquerading as score import. */
public final class OnlineCatalog {
    public static final String INDEX="https://musetrainer.github.io/library/";
    public static final class Item {
        public final String title,url;
        Item(String name,String address){title=name;url=address;}
    }
    public static List<Item> parse(String html) throws IOException {
        List<Item> result=new ArrayList<>();
        Matcher rows=Pattern.compile("<li>\\s*(.*?)\\s*&middot;.*?<a\\s+href=\"(https://musetrainer\\.github\\.io/library/scores/[^\"]+\\.mxl)\">Download</a>",Pattern.DOTALL).matcher(html);
        while(rows.find())result.add(new Item(unescape(rows.group(1).replaceAll("<[^>]+>","").trim()),unescape(rows.group(2))));
        if(result.isEmpty())throw new IOException("曲库目录格式发生变化，暂时无法读取；可导入文件或使用图片识谱");
        return result;
    }
    private static String unescape(String s){return s.replace("&amp;","&").replace("&quot;","\"").replace("&#39;","'").replace("&apos;","'").replace("&lt;","<").replace("&gt;",">").replace("&nbsp;"," ");}
    private static String normalize(String s){return Normalizer.normalize(s,Normalizer.Form.NFD).replaceAll("\\p{M}","").toLowerCase(Locale.ROOT);}
    public static List<Item> search(List<Item> source,String query){
        Map<String,String> aliases=new HashMap<>();aliases.put("卡农","canon");aliases.put("致爱丽丝","fur elise");aliases.put("生日快乐","happy birthday");
        aliases.put("绿袖子","greensleeves");aliases.put("小步舞曲","minuet");aliases.put("月光","clair de lune");aliases.put("欢乐颂","ode to joy");
        String q=normalize(query.trim());q=aliases.containsKey(q)?aliases.get(q):q;List<Item> result=new ArrayList<>();
        for(Item item:source)if(normalize(item.title).contains(q))result.add(item);return result;
    }
    public static byte[] download(String url,int limit) throws IOException {
        if(!url.startsWith(INDEX) && !url.startsWith("https://cdn.jsdelivr.net/gh/musetrainer/library@master/"))
            throw new IOException("不支持的曲谱来源");
        IOException first;
        try{return get(url,limit);}catch(IOException e){first=e;}
        if(url.startsWith(INDEX))try{return get("https://cdn.jsdelivr.net/gh/musetrainer/library@master/"+url.substring(INDEX.length()),limit);}catch(IOException ignored){}
        throw new IOException("无法连接在线曲库，请检查手机网络，或先导入本地曲谱文件。原因："+first.getMessage(),first);
    }
    static byte[] get(String url,int limit)throws IOException{
        HttpsURLConnection connection=null;
        try{
            URL address=new URL(URI.create(url.replace(" ","%20")).toASCIIString());
            connection=(HttpsURLConnection)address.openConnection();connection.setConnectTimeout(12000);connection.setReadTimeout(15000);
            connection.setInstanceFollowRedirects(false);connection.setRequestProperty("User-Agent","YunYinScore/2.2");
            int status=connection.getResponseCode();if(status!=200)throw new IOException("HTTP "+status);
            if(connection.getContentLengthLong()>limit)throw new IOException("曲谱文件过大");
            try(InputStream input=connection.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
                byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1){
                    if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("联网已取消");
                    if(out.size()+n>limit)throw new IOException("曲谱超过大小上限");out.write(buffer,0,n);
                }return out.toByteArray();
            }
        }finally{if(connection!=null)connection.disconnect();}
    }
    public static String indexText(byte[] bytes){return new String(bytes,StandardCharsets.UTF_8);}
}
