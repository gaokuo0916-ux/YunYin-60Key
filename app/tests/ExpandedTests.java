package cn.fpga.score;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.io.*;
public final class ExpandedTests {
    private interface Work{void run()throws Exception;}
    static void reject(Work work)throws Exception{try{work.run();}catch(IOException e){return;}throw new AssertionError("Invalid download accepted");}
    public static void main(String[] args)throws Exception{
        Path root=Paths.get(args[0]);reject(()->ExpandedDownload.url("../private.mid"));reject(()->ExpandedDownload.url("https://example.com/a.mid"));reject(()->ExpandedDownload.url("main/a/../../b.mid"));
        int samples=0,notes=0;
        for(String line:Files.readAllLines(root.resolve("verification/expanded_samples/index.tsv"),StandardCharsets.UTF_8)){
            String[] c=line.split("\t");byte[] data=Files.readAllBytes(root.resolve("verification/expanded_samples/"+c[0]+".mid"));ExpandedDownload.validate(data,c[2]);
            reject(()->ExpandedDownload.validate(data,"00000000000000000000000000000000"));
            byte[] corrupt=data.clone();corrupt[corrupt.length-1]^=1;reject(()->ExpandedDownload.validate(corrupt,c[2]));
            MusicXmlImport parsed=MidiImport.read(data);List<String> warnings=new ArrayList<>();String draft=parsed.draft(0,parsed.tonic,warnings);if(!draft.startsWith("BPM="))throw new AssertionError("No draft");
            int n=parsed.tracks.get(0).notes.size();notes+=n;samples++;System.out.println(c[3]+" / "+c[4]+": MIDI validated; selected track "+n+" notes; review required="+draft.contains("?"));
        }
        if(samples!=6)throw new AssertionError("Missing category samples");
        System.out.println("PASS expanded: six real category samples, "+notes+" selected-track notes; checksum/corruption/URL guards; raw MIDI parses and reaches seven-key review.");
        if(args.length>1){String[] row=Files.readAllLines(root.resolve("verification/expanded_samples/index.tsv"),StandardCharsets.UTF_8).get(0).split("\t");byte[] online=ExpandedDownload.download(row[1],row[2]);if(!Arrays.equals(online,Files.readAllBytes(root.resolve("verification/expanded_samples/"+row[0]+".mid"))))throw new AssertionError("Network mismatch");System.out.println("PASS expanded Java HTTPS: validated live download equals pinned sample.");}
    }
}
