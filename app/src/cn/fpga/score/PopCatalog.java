package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Offline searchable metadata; real MIDI is fetched on demand from pinned upstream. */
public final class PopCatalog {
    public static final String COMMIT="d83e6edba6872a704f5d3b8b32f5cb540088dae6";
    public static final String REPOSITORY="https://github.com/music-x-lab/POP909-Dataset";
    public static final class Item {
        public final String id,title,artist;
        Item(String a,String b,String c){id=a;title=b;artist=c;}
        public String relative(){return "POP909/"+id+"/"+id+".mid";}
        public String url(){return "https://raw.githubusercontent.com/music-x-lab/POP909-Dataset/"+COMMIT+"/"+relative();}
    }
    public static List<Item> read(InputStream stream)throws IOException{
        List<Item> result=new ArrayList<>();Set<String> ids=new HashSet<>();
        try(BufferedReader in=new BufferedReader(new InputStreamReader(stream,StandardCharsets.UTF_8))){String line;while((line=in.readLine())!=null){String[] c=line.split("\t",-1);if(c.length!=3||!c[0].matches("[0-9]{3}")||c[1].isEmpty()||c[2].isEmpty()||!ids.add(c[0])||result.size()>=1000)throw new IOException("流行曲库目录有误");result.add(new Item(c[0],c[1],c[2]));}}
        result.sort(Comparator.comparingInt(i->Arrays.asList("花海","晴天","告白气球","后来","童话","遇见").contains(i.title)?0:1));
        return result;
    }
    public static List<Item> search(List<Item> items,String query){String[] terms=query.trim().toLowerCase(Locale.ROOT).split("\\s+");List<Item> result=new ArrayList<>();for(Item i:items){String text=(i.title+" "+i.artist).toLowerCase(Locale.ROOT);boolean match=true;for(String term:terms)match&=text.contains(term);if(match)result.add(i);}return result;}
    public static byte[] download(Item item)throws IOException{
        IOException failure=null;
        for(String base:new String[]{"https://cdn.jsdelivr.net/gh/music-x-lab/POP909-Dataset@"+COMMIT+"/","https://raw.githubusercontent.com/music-x-lab/POP909-Dataset/"+COMMIT+"/"}){
            if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("下载已取消");
            try{byte[] data=OnlineCatalog.get(base+item.relative(),8*1024*1024);MidiImport.read(data);return data;}catch(InterruptedIOException e){if(Thread.currentThread().isInterrupted())throw e;failure=e;}catch(IOException e){failure=e;}
        }
        throw new IOException("曲谱下载未成功，请检查网络后重试，也可导入本地文件。"+(failure==null?"":failure.getMessage()),failure);
    }
}
