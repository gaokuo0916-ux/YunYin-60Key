package cn.fpga.score;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.io.*;

public final class CoreTests {
    private static int checks;
    private static void check(boolean condition, String message) {
        checks++; if (!condition) throw new AssertionError(message);
    }
    private interface Action { void run() throws Exception; }
    private static void reject(Action action, String reason) throws Exception {
        boolean failed = false;
        try { action.run(); } catch (IOException | IllegalArgumentException ex) { failed = true; }
        check(failed, reason);
    }
    private static final class Fake implements Uploader.Link {
        final List<String> sent = new ArrayList<>();
        final Queue<String> replies = new ArrayDeque<>();
        final Score expected;
        final String fault;
        int saved, index;
        Fake(Score score, String mode) { expected = score; fault = mode; }
        public void clear() { replies.clear(); }
        public String receive(long millis) { return replies.poll(); }
        public void send(String line) {
            sent.add(line);
            if (line.isEmpty()) replies.add("ERR 1");
            else if (line.equals("ABORT")) { index = 0; replies.add("OK"); }
            else if (line.equals("PING")) { if (!fault.equals("no-pong")) replies.add("PONG"); }
            else if (line.equals("CAP")) {
                if(!fault.equals("no-cap")) replies.add(fault.equals("legacy")?"ERR 1":fault.equals("cap512")?"CAP 512":"CAP 8192");
            }
            else if (line.startsWith("BEGIN ")) {
                check(line.equals(expected.begin()), "Header encoding");
                if (!fault.equals("no-ready")) replies.add("READY");
            } else if (line.startsWith("NOTE ")) {
                check(line.equals(expected.note(index)), "Exactly ordered note " + index);
                index++;
                if (fault.equals("err4") && index == 2) replies.add("ERR 4");
            } else if (line.startsWith("END ")) {
                check(index == expected.count() && line.equals(expected.end()), "END count and CRC");
                if (fault.equals("err5")) replies.add("ERR 5");
                else { saved++; if (!fault.equals("no-saved")) replies.add("SAVED"); }
            } else if (line.equals("STATUS")) replies.add(fault.equals("bad-status") ? "S=0 V=1 U=1 E=4" : "S=0 V=1 U=0 E=0");
            else if (line.equals("USER") || line.equals("START") || line.equals("PAUSE") || line.equals("STOP")) replies.add("OK");
            else throw new AssertionError("Unexpected command " + line);
        }
    }
    public static void main(String[] args) throws Exception {
        Path app = Paths.get(args[0]);
        Path phone = app.resolve("assets");
        Score three = Score.parse(new String(Files.readAllBytes(phone.resolve("three_notes.bt.txt")), StandardCharsets.UTF_8), 90);
        check(three.count() == 3 && three.crc == 38567, "Known three-note CRC");
        Score twinkle = Score.parse(new String(Files.readAllBytes(phone.resolve("twinkle.bt.txt")), StandardCharsets.UTF_8), 90);
        check(twinkle.count() == 42 && twinkle.crc == 60349, "Known 42-note CRC");
        Score seven = Score.parse(new String(Files.readAllBytes(phone.resolve("seven_notes.bt.txt")), StandardCharsets.UTF_8), 90);
        check(seven.count() == 9 && seven.crc == 45612, "Known 9-event CRC");
        Score penghu = Score.parse(new String(Files.readAllBytes(phone.resolve("penghuwan.bt.txt")), StandardCharsets.UTF_8), 90);
        check(penghu.count() == 260, "Existing 260-event file");
        Score csv = Score.parse("\uFEFFBPM=120\r\n1,4\r\n2,4\r\n3,8\r\n", 90);
        check(csv.crc == three.crc, "CSV/BOM/CRLF parity");
        check(Score.parse("1 1 5 | 5 6 6 5", 120).count() == 7, "Compact numeric notation");
        reject(() -> Score.parse("1 8 2",120), "Invalid degree blocked before transmission");
        reject(() -> Score.parse("BPM=400\n1,4",120), "Invalid tempo blocked");
        reject(() -> Score.parse("BPM=120\n1,65",120), "Invalid duration blocked");
        reject(() -> Score.parse("BEGIN 3 120\nNOTE 1 1 4\nNOTE 1 2 4\nNOTE 2 3 8\nEND 38567",120), "Duplicate/skip index rejected locally");
        reject(() -> Score.parse("BEGIN 3 120\nNOTE 0 1 4\nNOTE 1 2 4\nNOTE 2 3 8\nEND 0",120), "Bad imported CRC rejected locally");
        List<int[]> notes = new ArrayList<>();
        for (int i=0;i<8192;i++) notes.add(new int[]{i%8,i%64+1});
        Score maximum = new Score(120, notes);
        check(Score.parse(maximum.protocol(),90).crc==maximum.crc,"8192-event text/CRC round trip beyond old 64KB limit");
        notes.add(new int[]{1,4}); reject(() -> new Score(120,notes), "Capacity 8193 rejected");
        Score legacy = new Score(120,notes.subList(0,512));
        Score boundary = new Score(120,notes.subList(0,513));
        for (Score score : Arrays.asList(three,seven,twinkle,penghu,legacy,boundary,maximum)) {
            Fake board = new Fake(score, "ok");
            final boolean[] confirmed = {false};
            new Uploader(board, 10).upload(score,(n,total,stage)->{ if(stage.startsWith("已校验")) confirmed[0]=true; });
            check(confirmed[0] && board.saved==1 && board.index==score.count(), "Complete-file upload confirmed");
            check(board.sent.size()==score.count()+6+(score.count()>512?1:0), "Capacity query only for long scores; no retransmitted notes");
            for (String line : board.sent) check((line+"\n").getBytes(StandardCharsets.US_ASCII).length<=20,"Every current protocol line <=20 bytes");
        }
        for(String fault:Arrays.asList("legacy","cap512","no-cap")){
            Fake board=new Fake(maximum,fault);
            reject(()->new Uploader(board,10).upload(maximum,(n,total,stage)->{}),"Long upload blocked for "+fault);
            check(board.sent.stream().noneMatch(s->s.startsWith("BEGIN ")),"Never start or commit unsupported long upload");
        }
        for (String fault : Arrays.asList("no-pong","no-ready","err4","err5","no-saved","bad-status")) {
            Fake board = new Fake(three,fault);
            final boolean[] confirmed = {false};
            reject(() -> new Uploader(board,10).upload(three,(n,total,stage)->{if(stage.startsWith("已校验"))confirmed[0]=true;}),"Failure detected: "+fault);
            check(!confirmed[0],"Never report saved on "+fault);
            if(fault.equals("err4")) check(board.sent.stream().noneMatch(s->s.startsWith("END ")),"Stop before committing wrong order");
        }
        Fake controls = new Fake(three,"ok"); new Uploader(controls,10).startPractice();
        check(controls.sent.equals(Arrays.asList("USER","START")),"Select user before starting practice");
        String reply="PONG\r\nCAP 8192\nREADY\nSAVED\nS=0 V=1 U=0 E=0\n";
        byte[] bytes=reply.getBytes(StandardCharsets.US_ASCII);
        for(int size=1;size<=bytes.length;size++) {
            ReplyFrames decoder=new ReplyFrames();List<String> lines=new ArrayList<>();
            for(int offset=0;offset<bytes.length;offset+=size)lines.addAll(decoder.feed(Arrays.copyOfRange(bytes,offset,Math.min(offset+size,bytes.length))));
            check(lines.equals(Arrays.asList("PONG","CAP 8192","READY","SAVED","S=0 V=1 U=0 E=0")),"Fragmented/coalesced notifications size "+size);
        }
        reject(()->new ReplyFrames().feed(new byte[]{(byte)255}),"Corrupt notification rejected");
        Path out=app.resolve("verification");Files.createDirectories(out);
        Fake captured = new Fake(maximum, "ok");
        new Uploader(captured, 10).upload(maximum, (n,total,stage)->{});
        List<String> transaction=captured.sent;
        Files.write(out.resolve("app_8192_transaction.txt"),(String.join("\n",transaction)+"\n").getBytes(StandardCharsets.US_ASCII));
        System.out.println("PASS core: "+checks+" checks; known CRC vectors, 3/9/42/260/512/513/8192-event files, input guards, capacity handshake/legacy rejection, exact ordered send, missing/error replies, SAVED gating, fragmented notifications, USER then START");
    }
}
