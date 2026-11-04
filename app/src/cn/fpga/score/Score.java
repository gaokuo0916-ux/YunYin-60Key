package cn.fpga.score;

import java.util.*;

/** Immutable note events. No audio samples and no image recognition. */
public final class Score {
    public static final int CAPACITY = 8192;
    public final int bpm, crc;
    public final boolean nativePitch;
    private final List<int[]> notes;
    public Score(int tempo, List<int[]> source) { this(tempo,source,false); }
    public static Score pitches(int tempo,List<int[]> source){return new Score(tempo,source,true);}
    private Score(int tempo, List<int[]> source, boolean nativeFormat) {
        nativePitch=nativeFormat;
        if (tempo < 20 || tempo > 300) throw new IllegalArgumentException("速度必须为 20～300 BPM");
        if (source.isEmpty() || source.size() > CAPACITY) throw new IllegalArgumentException("8192 版固件支持 1～8192 个音符/休止事件");
        bpm = tempo;
        List<int[]> copy = new ArrayList<>();
        int value = crcByte(crcByte(crcByte(crcByte(65535, source.size()), source.size() >> 8), bpm), bpm >> 8);
        if(nativePitch)value=crcByte(value,0x4d);
        for (int i = 0; i < source.size(); i++) {
            int[] note = source.get(i);
            if (note.length != 2 || note[0] < 0 || note[0] > (nativePitch?128:7) || note[1] < 1 || note[1] > (nativePitch?65535:64))
                throw new IllegalArgumentException((nativePitch?"原音高编码须为0～128、时长1～65535毫秒":"音符为0～7，时值为1～64")+"；第 "+(i+1)+" 个事件有误");
            copy.add(note.clone());
            value = crcByte(crcByte(crcByte(crcByte(value, i), i >> 8), note[0]), note[1]);
            if(nativePitch)value=crcByte(value,note[1]>>8);
        }
        notes = Collections.unmodifiableList(copy);
        crc = value;
    }
    private static int crcByte(int crc, int value) {
        crc ^= (value & 255) << 8;
        for (int n = 0; n < 8; n++) crc = ((crc << 1) ^ ((crc & 32768) != 0 ? 0x1021 : 0)) & 65535;
        return crc;
    }
    public int count() { return notes.size(); }
    public int degree(int index) { return notes.get(index)[0]; }
    public int units(int index) { return notes.get(index)[1]; }
    public String begin() { return (nativePitch?"MBEGIN ":"BEGIN ") + count() + " " + bpm; }
    public String note(int index) { int[] n = notes.get(index); return (nativePitch?"MNOTE ":"NOTE ") + index + " " + n[0] + " " + n[1]; }
    public String end() { return (nativePitch?"MEND ":"END ") + crc; }
    public String source() {
        if(nativePitch)return protocol();
        StringBuilder s = new StringBuilder("BPM=" + bpm + "\n");
        for (int[] n : notes) s.append(n[0]).append(',').append(n[1]).append('\n');
        return s.toString();
    }
    public String protocol() {
        StringBuilder s = new StringBuilder(begin()).append('\n');
        for (int i = 0; i < count(); i++) s.append(note(i)).append('\n');
        return s.append(end()).append("\nSTATUS\n").toString();
    }
    public String preview() {
        StringBuilder s = new StringBuilder();
        for (int i = 0; i < Math.min(28, count()); i++) s.append(nativePitch?OriginalScore.pitch(notes.get(i)[0]-1):Integer.toString(notes.get(i)[0])).append(' ');
        if (count() > 28) s.append("…");
        return s.toString();
    }
    public static Score parse(String text, int defaultBpm) {
        if (text.length() > 524288) throw new IllegalArgumentException("曲谱文本超过 512 KB，请分文件导入");
        text = text.replace("\uFEFF", "").replace("\r", "").trim();
        List<String> lines = new ArrayList<>();
        for (String raw : text.split("\n")) {
            String line = raw.split("#", 2)[0].trim();
            if (!line.isEmpty()) lines.add(line);
        }
        if (lines.isEmpty()) throw new IllegalArgumentException("曲谱为空");
        List<int[]> notes = new ArrayList<>();
        if (lines.get(0).startsWith("BEGIN ") || lines.get(0).startsWith("MBEGIN ")) {
            boolean nativeFormat=lines.get(0).startsWith("MBEGIN ");
            String[] header = fields(lines.get(0), 3);
            int count = number(header[1]), bpm = number(header[2]);
            if (count < 1 || count > CAPACITY || lines.size() < count + 2) throw new IllegalArgumentException("曲谱事件数量不完整或超过 8192");
            for (int i = 0; i < count; i++) {
                String[] n = fields(lines.get(i + 1), 4);
                if (!n[0].equals(nativeFormat?"MNOTE":"NOTE") || number(n[1]) != i) throw new IllegalArgumentException("NOTE 必须从 0 连续编号，第 " + i + " 项有误");
                notes.add(new int[]{number(n[2]), number(n[3])});
            }
            Score result = new Score(bpm, notes,nativeFormat);
            String[] end = fields(lines.get(count + 1), 2);
            if (!end[0].equals(nativeFormat?"MEND":"END") || number(end[1]) != result.crc) throw new IllegalArgumentException("文件 CRC 校验不符，请重新生成曲谱");
            for (int i = count + 2; i < lines.size(); i++)
                if (!lines.get(i).equals("STATUS")) throw new IllegalArgumentException("结束命令后存在不支持的内容");
            return result;
        }
        if (text.contains(",") || lines.get(0).startsWith("BPM=")) {
            int bpm = defaultBpm; boolean seenBpm = false;
            for (String line : lines) {
                if (line.startsWith("BPM=")) {
                    if (seenBpm || !notes.isEmpty()) throw new IllegalArgumentException("BPM 必须只写一次，放在开头");
                    bpm = number(line.substring(4)); seenBpm = true;
                } else {
                    String[] n = line.split(",", -1);
                    if (n.length != 2) throw new IllegalArgumentException("每行格式为 音符,时值，例如 1,4");
                    notes.add(new int[]{number(n[0].trim()), number(n[1].trim())});
                }
            }
            return new Score(bpm, notes);
        }
        String digits = String.join("", lines).replaceAll("[\\s|]", "");
        if (!digits.matches("[0-7]+")) throw new IllegalArgumentException("简谱仅支持 0～7；图片、升降号和高低八度请先整理成七音事件文本");
        for (char c : digits.toCharArray()) notes.add(new int[]{c - '0', 4});
        return new Score(defaultBpm, notes);
    }
    private static String[] fields(String s, int count) {
        String[] value = s.trim().split("\\s+");
        if (value.length != count) throw new IllegalArgumentException("曲谱格式有误：" + s);
        return value;
    }
    private static int number(String s) {
        if (!s.matches("[0-9]{1,5}")) throw new IllegalArgumentException("无效数字：" + s);
        return Integer.parseInt(s);
    }
}
