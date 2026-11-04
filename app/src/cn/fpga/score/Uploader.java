package cn.fpga.score;

import java.io.IOException;

/** Runs on one worker thread. Only FPGA SAVED + clean STATUS means success. */
public final class Uploader {
    public interface Link {
        void send(String line) throws Exception;
        String receive(long timeoutMs) throws Exception;
        void clear();
    }
    public interface Progress { void update(int sent, int total, String stage); }
    private final Link link;
    private final long timeout;
    public Uploader(Link transport) { this(transport, 6500); }
    public Uploader(Link transport, long timeoutMs) { link = transport; timeout = timeoutMs; }
    public void upload(Score score, Progress progress) throws Exception {
        link.clear();
        // Flush a partial command, then ABORT. ERR from that old partial line is ignored only here.
        link.send(""); link.send("ABORT"); expect("OK", true);
        link.send("PING"); expect("PONG", false);
        StudioProtocol board=new StudioProtocol(link);int boardCapabilities=score.nativePitch?board.capabilities():0;
        if(score.nativePitch && (boardCapabilities&2048)==0)throw new IOException("当前琴端尚不支持原音高上传，请先烧录配套原谱试用版FS；原谱仍保存在手机。");
        if (score.count() > 512) {
            link.send("CAP");
            long deadline = System.nanoTime() + timeout * 1000000L;
            while (true) {
                String capacity = readBefore(deadline);
                if (capacity.equals("ERR 1")) throw new IOException("板子仍是旧版 512 容量固件，请先烧录配套的 8192 版，再上传长曲谱");
                checkError(capacity);
                if (capacity.startsWith("CAP ")) {
                    String value=capacity.substring(4).trim();
                    if(!value.matches("[0-9]{1,5}") || Integer.parseInt(value)<score.count())
                        throw new IOException("板子容量不足："+capacity+"，本谱有 "+score.count()+" 个事件");
                    break;
                }
            }
        }
        progress.update(0, score.count(), "开始接收");
        link.send(score.begin()); expect("READY", false);
        for (int i = 0; i < score.count(); i++) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException("上传已取消");
            link.send(score.note(i));
            String reply;
            while ((reply = link.receive(0)) != null) checkError(reply);
            progress.update(i + 1, score.count(), "已发送，等待最终校验");
        }
        link.send(score.end()); expect("SAVED", false);
        link.send("STATUS");
        String state = expectPrefix("S=", false);
        if (!state.matches("S=[01] V=1 U=0 E=0")) throw new IOException("保存后板子状态异常：" + state);
        if(score.nativePitch&&(boardCapabilities&8192)!=0)board.keyboard();
        if(score.nativePitch && (!board.pitch().nativeFormat || !board.matches(score)))throw new IOException("琴端未确认原音高格式和完整曲谱校验，未标记上传成功");
        progress.update(score.count(), score.count(), "已校验并保存，可启动跟弹");
    }
    public void startPractice() throws Exception {
        link.clear(); link.send("USER"); expect("OK", false);
        link.send("START"); expect("OK", false);
    }
    public void control(String command) throws Exception {
        if (!command.equals("PAUSE") && !command.equals("STOP")) throw new IllegalArgumentException("无效控制命令");
        link.clear(); link.send(command); expect("OK", false);
    }
    private void expect(String wanted, boolean ignoreOldErrors) throws Exception {
        long deadline = System.nanoTime() + timeout * 1000000L;
        while (true) {
            String line = readBefore(deadline);
            if (line.equals(wanted)) return;
            if (!ignoreOldErrors) checkError(line);
        }
    }
    private String expectPrefix(String prefix, boolean ignoreOldErrors) throws Exception {
        long deadline = System.nanoTime() + timeout * 1000000L;
        while (true) {
            String line = readBefore(deadline);
            if (!ignoreOldErrors) checkError(line);
            if (line.startsWith(prefix)) return line;
        }
    }
    private String readBefore(long deadline) throws Exception {
        long remaining = (deadline - System.nanoTime()) / 1000000L;
        if (remaining <= 0) throw new IOException("等待板子回执超时；请检查 FFE1 通知与 FPGA Y22→模块 RXD 回传线路，再重新上传");
        String line = link.receive(remaining);
        if (line == null) throw new IOException("等待板子回执超时，未确认保存成功；可重新上传");
        checkDisconnect(line);
        return line;
    }
    private static void checkDisconnect(String s) throws IOException {
        if (s.startsWith("!")) throw new IOException(s.substring(1));
    }
    private static void checkError(String s) throws IOException {
        checkDisconnect(s);
        if (!s.startsWith("ERR")) return;
        String code = s.substring(3).trim();
        String reason = code.equals("4") ? "音符漏传、重复或数量不符" :
                        code.equals("5") ? "CRC 校验失败" : code.equals("6") ? "上传接收超时" :
                        code.equals("7") ? "串口停止位错误，请核对 38400 8N1" :
                        code.equals("8") ? "板子没有已保存的用户曲谱" : "曲谱协议错误";
        throw new IOException("板子返回 " + s + "：" + reason + "。请从头重传，旧曲谱保持有效");
    }
}
