package cn.fpga.score;
import java.nio.file.*;
import java.util.*;
/** Explicit network smoke test; excluded from offline regressions. */
public final class OnlineSmoke {
    public static void main(String[] args)throws Exception{
        Path out=Paths.get(args[0]);
        List<OnlineCatalog.Item> items=OnlineCatalog.parse(OnlineCatalog.indexText(OnlineCatalog.download(OnlineCatalog.INDEX,1024*1024)));
        OnlineCatalog.Item selected=OnlineCatalog.search(items,"生日快乐").get(0);
        byte[] data=OnlineCatalog.download(selected.url,8*1024*1024);
        MusicXmlImport music=MusicXmlImport.read(data);
        if(music.tracks.isEmpty())throw new AssertionError("No online melody tracks");
        Files.write(out.resolve("java_network_download.mxl"),data);
        System.out.println("PASS online: Java HTTPS fetched "+items.size()+" catalog entries and downloaded/parsed "+selected.title+" ("+data.length+" bytes, "+music.tracks.size()+" voices). URL="+selected.url);
    }
}
