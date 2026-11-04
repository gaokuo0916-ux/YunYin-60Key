package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class MidiTests {
    static int checks,compared;
    static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
    interface Work{void run()throws Exception;}
    static void reject(Work w,String why)throws Exception{try{w.run();}catch(IOException|IllegalArgumentException e){checks++;return;}throw new AssertionError("Accepted invalid input: "+why);}
    static byte[] file(int format,int division,byte[]... tracks)throws IOException{ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream d=new DataOutputStream(bytes);d.writeInt(0x4d546864);d.writeInt(6);d.writeShort(format);d.writeShort(tracks.length);d.writeShort(division);for(byte[] track:tracks){d.writeInt(0x4d54726b);d.writeInt(track.length);d.write(track);}return bytes.toByteArray();}
    static byte[] b(int... a){byte[] bytes=new byte[a.length];for(int i=0;i<a.length;i++)bytes[i]=(byte)a[i];return bytes;}
    static String draft(MusicXmlImport midi){return midi.draft(0,0,new ArrayList<>());}
    static void fixtures()throws Exception{
        byte[] t=b(0,255,3,6,'M','E','L','O','D','Y',0,255,89,2,0,0,0,144,60,90,96,128,60,0,0,144,62,90,96,62,0,0,255,47,0);
        MusicXmlImport m=MidiImport.read(file(0,96,t));check(m.tracks.get(0).name.startsWith("MELODY"),"Track name");check(draft(m).equals("BPM=120\n1,4\n2,4\n"),"SMF 0 note-off / velocity-zero / running status");
        byte[] tempo=b(0,255,81,3,7,161,32,96,255,81,3,15,66,64,0,255,47,0);
        MusicXmlImport varying=MidiImport.read(file(1,96,tempo,t));check(Math.abs(varying.tracks.get(0).notes.get(1).duration-2)<1e-8,"Global type-1 tempo map");check(draft(varying).equals("BPM=120\n1,4\n2,8\n"),"Tempo map retained in event duration");
        MusicXmlImport simple=MidiImport.read(file(0,96,b(96,144,72,90,96,128,72,0,0,255,47,0)));check(draft(simple).equals("BPM=120\n0,4\n1,4\n"),"Leading rest and octave folding");
        MusicXmlImport sharp=MidiImport.read(file(0,96,b(0,144,61,90,96,128,61,0,0,255,47,0)));String unknown=sharp.draft(0,0,new ArrayList<>());check(unknown.contains("?"),"Accidentals are not silently changed");reject(()->SongDraft.parse(unknown),"Unknown semitone blocks upload");
        MusicXmlImport overlap=new MusicXmlImport("overlap");MusicXmlImport.Track track=new MusicXmlImport.Track("MELODY");track.notes.add(new MusicXmlImport.Note(0,2,60,false,false));track.notes.add(new MusicXmlImport.Note(1,1,62,false,false));overlap.tracks.add(track);List<String> warnings=new ArrayList<>();check(overlap.draft(0,0,warnings).equals("BPM=120\n1,4\n2,4\n"),"Overlap does not lengthen the melody timeline");check(warnings.stream().anyMatch(s->s.contains("交叠")),"Overlap conversion disclosed");
        MusicXmlImport hanging=MidiImport.read(file(0,96,b(0,144,60,90,96,255,47,0)));check(hanging.warnings.stream().anyMatch(s->s.contains("结束")),"Unclosed note disclosed");
        reject(()->MidiImport.read(b(1,2,3)),"Bad header");reject(()->MidiImport.read(file(2,96,t)),"Asynchronous type 2");reject(()->MidiImport.read(file(0,0xe728,t)),"SMPTE division");reject(()->MidiImport.read(file(0,0,t)),"Zero division");reject(()->MidiImport.read(file(0,96,b(0,60,1))),"Missing running status");reject(()->MidiImport.read(file(0,96,b(128,128,128,128,128))),"Oversized VLQ");reject(()->MidiImport.read(file(0,96,b(0,255,3,127))),"Meta size overflow");reject(()->MidiImport.read(file(0,96,b(0,255,81,3,0,0,0))),"Zero tempo");reject(()->MidiImport.read(file(0,96,b(0,153,60,90,96,137,60,0))),"Drums excluded");reject(()->MidiImport.read(file(0,96,b(0,144,60))),"Truncated channel event");
    }
    static void reference(Path root)throws Exception{
        Map<String,List<double[]>> expected=new HashMap<>();
        for(String line:Files.readAllLines(root.resolve("verification/midi_samples/reference.tsv"),StandardCharsets.UTF_8)){String[] c=line.split("\t");expected.computeIfAbsent(c[0]+"|"+c[1],k->new ArrayList<>()).add(new double[]{Double.parseDouble(c[3]),Double.parseDouble(c[2]),Double.parseDouble(c[4])});}
        Comparator<double[]> order=Comparator.<double[]>comparingDouble(n->n[0]).thenComparingDouble(n->n[1]).thenComparingDouble(n->n[2]);
        for(String id:new String[]{"001","064","201","516","751"}){
            MusicXmlImport result=MidiImport.read(Files.readAllBytes(root.resolve("verification/midi_samples/"+id+".mid")));
            check(result.tracks.get(0).name.startsWith("MELODY"),id+" recommends melody first");
            for(MusicXmlImport.Track track:result.tracks){List<double[]> actual=new ArrayList<>();for(MusicXmlImport.Note n:track.notes)actual.add(new double[]{n.at*60/result.bpm,n.pitch,n.duration*60/result.bpm});List<double[]> reference=expected.remove(id+".mid|"+track.name);check(reference!=null&&reference.size()==actual.size(),id+" reference count "+track.name);actual.sort(order);reference.sort(order);for(int n=0;n<actual.size();n++){double[] a=actual.get(n),e=reference.get(n);check(a[1]==e[1]&&Math.abs(a[0]-e[0])<1e-7&&Math.abs(a[2]-e[2])<1e-7,id+" pitch/time/duration "+track.name+" "+n);compared++;}}
            List<String> notices=new ArrayList<>();String converted=result.draft(0,result.tonic,notices);check(converted.startsWith("BPM="),"Real melody converts");if(converted.contains("?"))reject(()->SongDraft.parse(converted),"Real chromatic notes require review");else check(!SongDraft.parse(converted).segments().isEmpty(),"Real seven-key events validate");
        }
        check(expected.isEmpty(),"All reference tracks consumed");
    }
    public static void main(String[] args)throws Exception{Path root=Paths.get(args[0]);fixtures();List<PopCatalog.Item> catalog=PopCatalog.read(Files.newInputStream(root.resolve("vendor/pop909_catalog.tsv")));check(catalog.size()==909,"909 actual metadata records");check(PopCatalog.search(catalog,"花海 周杰伦").size()==1,"Title and artist search");check(PopCatalog.search(catalog,"晴天").size()>=1,"Pop title exists");reference(root);System.out.println("PASS MIDI: "+checks+" checks; "+compared+" note pitches/onsets/durations match independent Mido reference across five real files; malformed inputs, tempo map, seven-key review and 909-item search checked.");}
}
