package cn.fpga.score;
import java.nio.file.*;
import java.util.*;
public final class PopOnlineSmoke {
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);List<PopCatalog.Item> items=PopCatalog.read(Files.newInputStream(root.resolve("vendor/pop909_catalog.tsv")));
        PopCatalog.Item item=PopCatalog.search(items,"花海 周杰伦").get(0);byte[] online=PopCatalog.download(item),reference=Files.readAllBytes(root.resolve("verification/midi_samples/751.mid"));
        if(!Arrays.equals(online,reference))throw new AssertionError("Downloaded MIDI differs from pinned reference");
        MusicXmlImport parsed=MidiImport.read(online);List<String> notices=new ArrayList<>();String draft=parsed.draft(0,parsed.tonic,notices);
        System.out.println("PASS real HTTPS fetch: pinned 花海 MIDI, "+online.length+" bytes; "+parsed.tracks.get(0).name+"; BPM="+parsed.bpm+"; tonic="+parsed.tonic+"; draft events="+(draft.split("\n").length-1)+"; unknowns="+draft.chars().filter(c->c=='?').count());
        Files.write(root.resolve("verification/huahai_converted.txt"),draft.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
}
