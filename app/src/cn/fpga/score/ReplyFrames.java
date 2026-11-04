package cn.fpga.score;
import java.io.IOException;
import java.util.*;

/** Notifications may split a reply anywhere or contain multiple reply lines. */
public final class ReplyFrames {
    private final StringBuilder partial = new StringBuilder();
    public synchronized List<String> feed(byte[] bytes) throws IOException {
        List<String> result = new ArrayList<>();
        if (bytes == null) return result;
        for (byte raw : bytes) {
            int b = raw & 255;
            if (b == 13) continue;
            if (b == 10) {
                if (partial.length() != 0) result.add(partial.toString());
                partial.setLength(0);
            } else if (b >= 32 && b <= 126 && partial.length() < 768) partial.append((char)b);
            else { partial.setLength(0); throw new IOException("板子回传包含异常字符，请核对串口配置与接线"); }
        }
        return result;
    }
}
