package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

/** End-to-end fixtures for persisted scores, real downloaded MXL, and rhythm pixels. */
public final class V2Tests {
    private static int checks;
    private static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
    private interface Action {void run()throws Exception;}
    private static void reject(Action action,String why)throws Exception{
        boolean failed=false;try{action.run();}catch(Exception e){failed=true;}check(failed,why);
    }
    private static String note(String step,int octave,int alter,int duration,String extra){
        return "<note>"+extra+"<pitch><step>"+step+"</step><alter>"+alter+"</alter><octave>"+octave+"</octave></pitch><duration>"+duration+"</duration><voice>1</voice></note>";
    }
    private static String xml(String body){return "<score-partwise version='4.0'><work><work-title>测试旋律</work-title></work><part-list><score-part id='P1'><part-name>Flute</part-name></score-part></part-list><part id='P1'><measure number='1'><attributes><divisions>4</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>"+body+"</measure></part></score-partwise>";}
    private static MusicXmlImport parse(String body)throws Exception{return MusicXmlImport.read(xml(body).getBytes(StandardCharsets.UTF_8));}
    private static String draft(MusicXmlImport value,int track,int tonic){return value.draft(track,tonic,new ArrayList<>());}
    private static byte[] mxl(Map<String,byte[]> entries)throws Exception{
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();try(ZipOutputStream zip=new ZipOutputStream(bytes)){
            for(Map.Entry<String,byte[]> entry:entries.entrySet()){zip.putNextEntry(new ZipEntry(entry.getKey()));zip.write(entry.getValue());zip.closeEntry();}
        }return bytes.toByteArray();
    }
    private static void library(Path app)throws Exception{
        Path root=Files.createTempDirectory(app.resolve("verification"),"library_fixture_");
        LibraryStore store=new LibraryStore(root.toFile());Score score=Score.parse("BPM=90\n1,4\n0,2\n7,8",120);
        LibraryStore.Entry e=store.save(null,"生日快乐","本地图谱",score);
        check(store.list().size()==1,"Saved in persistent library");
        LibraryStore.Entry restored=new LibraryStore(root.toFile()).list().get(0);
        check(restored.title.equals("生日快乐") && restored.origin.equals("本地图谱"),"Unicode title/origin persist after reopening");
        check(restored.score.protocol().equals(score.protocol()),"Every score event survives disk round trip");
        store.save(e.id,"修改曲名","编辑",Score.parse("1234567",100));
        check(store.list().size()==1 && store.list().get(0).score.count()==7,"Editing atomically replaces one existing entry");
        check(!Files.exists(root.resolve(e.id+".tmp")),"No temporary library record after commit");
        reject(()->store.save("../../escape","x","",score),"ID cannot escape library folder");
        reject(()->store.save(null,"   ","",score),"Empty title rejected");
        String corruptId=UUID.randomUUID().toString();
        try(DataOutputStream out=new DataOutputStream(Files.newOutputStream(root.resolve(corruptId+".score")))){
            out.writeInt(0x59594e32);out.writeUTF("损坏");out.writeUTF("test");out.writeUTF("BEGIN 1 120\nNOTE 0 1 4\nEND 0\n");
        }
        check(store.list().size()==1,"Corrupt CRC cannot become an uploadable library entry");
        Files.write(root.resolve("interrupted.tmp"),new byte[]{1,2,3});check(store.list().size()==1,"Interrupted temporary write is ignored");
        store.delete(e.id);check(store.list().isEmpty(),"Delete removes valid record; corrupt records stay hidden");
        String oldId=UUID.randomUUID().toString();
        try(DataOutputStream out=new DataOutputStream(Files.newOutputStream(root.resolve(oldId+".score")))){
            out.writeInt(0x59594e32);out.writeUTF("旧版曲库");out.writeUTF("v2");out.writeUTF(score.protocol());
        }
        check(new LibraryStore(root.toFile()).list().get(0).score.crc==score.crc,"Existing v2 private library remains readable after update");
        List<int[]> full=new ArrayList<>();for(int i=0;i<8192;i++)full.add(new int[]{i%8,i%64+1});Score maximum=new Score(120,full);
        check(maximum.protocol().getBytes(StandardCharsets.UTF_8).length>65535,"Maximum protocol really exceeds writeUTF old limit");
        store.save(oldId,"完整长谱","8192",maximum);
        check(new LibraryStore(root.toFile()).list().size()==1 && new LibraryStore(root.toFile()).list().get(0).score.protocol().equals(maximum.protocol()),"8192 events persist byte-exactly; legacy entry migrates without duplicate");
    }
    private static void longScores()throws Exception{
        StringBuilder source=new StringBuilder("BPM=90\n");for(int i=0;i<9000;i++)source.append(i%8).append(',').append(i%64+1).append('\n');
        SongDraft song=SongDraft.parse(SongDraft.importText(source.toString(),120));List<Score> pieces=song.segments();
        check(pieces.size()==2 && pieces.get(0).count()==8192 && pieces.get(1).count()==808,"9000 events split only at upgraded 8192 boundary");
        for(int i=0;i<9000;i++){String expected="NOTE "+(i%8192)+" "+(i%8)+" "+(i%64+1);check(pieces.get(i/8192).note(i%8192).equals(expected),"No event dropped or reordered across segment boundary");}
        StringBuilder digits=new StringBuilder();for(int i=0;i<1200;i++)digits.append(i%8);
        check(SongDraft.parse(SongDraft.importText(digits.toString(),110)).notes.size()==1200,"Long plain digits import, not only MusicXML");
        check(SongDraft.parse(SongDraft.importText(digits.toString(),110)).segments().size()==1,"1200-note song is now one uploadable score");
        check(SongDraft.parse(SongDraft.importText("\uFEFF1 2 | 3 # 注释\n4",120)).notes.size()==4,"Plain TXT comments/BOM/bar separators");
        Score original=Score.parse("123",90);check(SongDraft.importText(original.protocol(),120).equals(original.source()),"Checked protocol files retain their original tempo/events");
        reject(()->SongDraft.importText("BEGIN 1 120\nNOTE 0 1 4\nEND 0",120),"Bad CRC is never bypassed by long-score fallback");
        reject(()->SongDraft.parse("BPM=120\n?,4"),"Unconfirmed pitch blocks save");
        reject(()->SongDraft.parse("BPM=120\n1,?"),"Unconfirmed duration blocks save");
        reject(()->SongDraft.parse("BPM=120\n1,4\nBPM=90"),"Mid-score tempo silently changing is disallowed");
        reject(()->SongDraft.parse("BPM=120\n1,65"),"Out-of-range duration rejected");
    }
    private static void catalog(Path app)throws Exception{
        String index=Files.readString(app.resolve("vendor/online_index.html"));List<OnlineCatalog.Item> items=OnlineCatalog.parse(index);
        check(items.size()==69,"Live catalog fixture contains the 69 fetched score versions");
        for(String alias:new String[]{"卡农","致爱丽丝","生日快乐","小步舞曲"})check(!OnlineCatalog.search(items,alias).isEmpty(),"Chinese search alias: "+alias);
        check(OnlineCatalog.search(items,"unlikely_no_such_song_983").isEmpty(),"Unmatched title does not invent a result");
        reject(()->OnlineCatalog.parse("<html>Not a catalog</html>"),"Changed index markup gets clear failure");
        reject(()->OnlineCatalog.download("http://example.com/test.mxl",50),"Downloader rejects unsupported source before contacting it");
        for(String file:new String[]{"birthday.mxl","minuet.mxl","canon.mxl"}){
            MusicXmlImport parsed=MusicXmlImport.read(Files.readAllBytes(app.resolve("verification/v2_samples/"+file)));
            check(!parsed.tracks.isEmpty(),"Actual online MXL has selectable tracks: "+file);
            int notes=0;for(int t=0;t<parsed.tracks.size();t++){
                String source=draft(parsed,t,parsed.tonic);check(source.startsWith("BPM="),"Actual MXL converts to editable draft: "+file+":"+t);
                check(source.split("\n").length>1,"Nonempty imported melody");
                // Unknown chromatic pitches must remain visible; only a deliberate review can replace them.
                if(source.contains("?"))reject(()->SongDraft.parse(source),"Chromatic warning cannot be uploaded automatically");
                else notes+=SongDraft.parse(source).notes.size();
            }
            System.out.println("MXL fixture: "+file+"; title="+parsed.title+"; tracks="+parsed.tracks.size()+"; direct seven-key events="+notes);
        }
    }
    private static void musicXml()throws Exception{
        MusicXmlImport scale=parse(note("C",3,0,4,"")+note("D",4,0,2,"")+"<note><rest/><duration>2</duration></note>"+note("B",5,0,4,""));
        check(draft(scale,0,0).equals("BPM=120\n1,4\n2,2\n0,2\n7,4\n"),"Pitch/octave fold/rest/duration conversion");
        MusicXmlImport transposed=parse(note("G",4,0,4,"")+note("F",5,1,4,"")+note("A",4,0,4,""));
        check(draft(transposed,0,7).equals("BPM=120\n1,4\n7,4\n2,4\n"),"G-major melody maps into fixed C seven keys");
        check(draft(transposed,0,0).contains("?,4"),"Out-of-scale F sharp explicitly marked");
        MusicXmlImport tied=parse(note("C",4,0,4,"<tie type='start'/>")+note("C",4,0,4,"<tie type='stop'/>"));
        check(draft(tied,0,0).equals("BPM=120\n1,8\n"),"Tie is merged, no repeated LED key trigger");
        MusicXmlImport chord=parse(note("C",4,0,4,"")+note("E",4,0,4,"<chord/>")+note("G",4,0,4,""));
        List<String> notices=new ArrayList<>();String melody=chord.draft(0,0,notices);
        check(melody.equals("BPM=120\n3,4\n5,4\n") && notices.stream().anyMatch(s->s.contains("和弦")),"Chord reduces to explicit highest-note melody with warning");
        MusicXmlImport gap=parse("<forward><duration>2</duration></forward>"+note("C",4,0,4,""));
        check(draft(gap,0,0).equals("BPM=120\n0,2\n1,4\n"),"Forward gap becomes rest");
        MusicXmlImport voices=parse(note("C",4,0,4,"")+"<backup><duration>4</duration></backup>"+note("E",4,0,4,"").replace("<voice>1","<voice>2"));
        check(voices.tracks.size()==2 && draft(voices,0,0).endsWith("1,4\n") && draft(voices,1,0).endsWith("3,4\n"),"Backup/voice separation does not flatten accompaniment into melody");
        MusicXmlImport quantized=MusicXmlImport.read(xml(note("C",4,0,1,"")).replace("<divisions>4","<divisions>3").getBytes(StandardCharsets.UTF_8));
        notices.clear();quantized.draft(0,0,notices);check(notices.stream().anyMatch(s->s.contains("量化")),"Triplet quantization is disclosed");
        MusicXmlImport repeats=parse(note("C",4,0,4,"")+"<barline><repeat direction='backward'/></barline><direction><sound tempo='90'/></direction><direction><sound tempo='100'/></direction>");
        check(repeats.bpm==90 && repeats.warnings.stream().anyMatch(s->s.contains("反复")) && repeats.warnings.stream().anyMatch(s->s.contains("变速")),"Repeat and tempo-map limitations disclosed");
        String withDtd="<!DOCTYPE score-partwise SYSTEM 'http://127.0.0.1:1/never-fetch.dtd'>"+xml(note("C",4,0,4,""));
        check(MusicXmlImport.read(withDtd.getBytes(StandardCharsets.UTF_8)).tracks.size()==1,"External DTD not needed or fetched");
        reject(()->MusicXmlImport.read(("<!DOCTYPE score-partwise [<!ENTITY x SYSTEM 'file:///never-read'>]>"+xml(note("C",4,0,4,""))).getBytes(StandardCharsets.UTF_8)),"Custom XML entity rejected");
        reject(()->MusicXmlImport.read(xml(note("C",4,0,4,"")).replace("<divisions>4","<divisions>NaN").getBytes(StandardCharsets.UTF_8)),"NaN divisions rejected");
        reject(()->parse("<backup><duration>4</duration></backup>"+note("C",4,0,4,"")),"Invalid backward time rejected");
        reject(()->MusicXmlImport.read(xml(note("C",4,0,4,"")).replace("<beat-type>4","<beat-type>0").getBytes(StandardCharsets.UTF_8)),"Zero beat denominator rejected");
        Map<String,byte[]> files=new LinkedHashMap<>();files.put("META-INF/container.xml","<container><rootfiles><rootfile full-path='chosen.musicxml'/></rootfiles></container>".getBytes(StandardCharsets.UTF_8));
        files.put("ignore.xml","wrong".getBytes(StandardCharsets.UTF_8));files.put("chosen.musicxml",xml(note("D",4,0,4,"")).getBytes(StandardCharsets.UTF_8));
        check(draft(MusicXmlImport.read(mxl(files)),0,0).endsWith("2,4\n"),"MXL container selects declared root, not first XML file");
        Map<String,byte[]> many=new LinkedHashMap<>();for(int i=0;i<101;i++)many.put(i+".xml",new byte[0]);
        reject(()->MusicXmlImport.read(mxl(many)),"Excessive compressed entries rejected");
        Map<String,byte[]> huge=new LinkedHashMap<>();huge.put("score.xml",new byte[8*1024*1024+1]);
        reject(()->MusicXmlImport.read(mxl(huge)),"Decompressed-size limit prevents zip-bomb memory growth");
    }
    private static final class Pixels {
        final int w=180,h=110;final int[] gray=new int[w*h];
        Pixels(){Arrays.fill(gray,255);}
        void rect(int l,int t,int r,int b){for(int y=t;y<b;y++)for(int x=l;x<r;x++)gray[y*w+x]=0;}
        JianpuGeometry.Result analyze(List<JianpuGeometry.Glyph> glyphs){return JianpuGeometry.analyze(w,h,gray,glyphs);}
        JianpuGeometry.Glyph digit(int degree,int x,int y,float confidence){rect(x,y,x+12,y+20);return new JianpuGeometry.Glyph(degree,x,y,x+12,y+20,confidence);}
    }
    private static void rhythm()throws Exception{
        for(int bars=0;bars<=3;bars++){
            Pixels p=new Pixels();JianpuGeometry.Glyph g=p.digit(3,20,20,95);for(int n=0;n<bars;n++)p.rect(18,45+n*4,35,47+n*4);
            String expected=bars==0?"4":bars==1?"2":bars==2?"1":"?";
            check(p.analyze(Arrays.asList(g)).source.equals("3,"+expected+"\n"),"Underline rhythm rows: "+bars);
        }
        Pixels dotted=new Pixels();JianpuGeometry.Glyph g=dotted.digit(5,20,20,95);dotted.rect(35,28,38,31);
        check(dotted.analyze(Arrays.asList(g)).source.equals("5,6\n"),"Duration dot produces dotted quarter, not another note");
        Pixels dash=new Pixels();g=dash.digit(6,20,20,95);dash.rect(45,29,57,31);
        check(dash.analyze(Arrays.asList(g)).source.equals("6,8\n"),"Duration dash extends by quarter beat");
        Pixels tiny=new Pixels();g=tiny.digit(2,20,20,95);tiny.rect(18,45,35,47);tiny.rect(18,49,35,51);tiny.rect(35,28,38,31);
        check(tiny.analyze(Arrays.asList(g)).source.equals("2,?\n"),"Unrepresentable dotted sixteenth gets visible unknown, not silent rounding");
        Pixels low=new Pixels();g=low.digit(0,20,20,15);check(low.analyze(Arrays.asList(g)).source.equals("?,4\n"),"Very low-confidence OCR digit blocks automatic save");
        Pixels rest=new Pixels();g=rest.digit(0,20,20,95);check(rest.analyze(Arrays.asList(g)).source.equals("0,4\n"),"Rest digit remains a rest");
        Pixels multiple=new Pixels();List<JianpuGeometry.Glyph> rows=Arrays.asList(multiple.digit(1,20,20,95),multiple.digit(2,65,65,95));
        reject(()->multiple.analyze(rows),"Multiple rows cannot be silently interleaved");
        reject(()->JianpuGeometry.analyze(1,1,new int[]{255},Collections.emptyList()),"Empty crop result is rejected");
    }
    public static void main(String[] args)throws Exception{
        Path app=Paths.get(args[0]);library(app);longScores();catalog(app);musicXml();rhythm();
        System.out.println("PASS v2: "+checks+" checks; legacy library migration/8192-event persistence, 9000-event segmentation, real 69-item catalog and 3 MXL fixtures, voice/transposition/ties/rests, malformed XML/MXL guards, pixel rhythm/unknowns. Native Android OCR and physical BLE are not exercised by these tests.");
    }
}
