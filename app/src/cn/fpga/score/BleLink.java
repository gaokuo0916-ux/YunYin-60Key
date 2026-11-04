package cn.fpga.score;

import android.bluetooth.*;
import android.content.Context;
import android.os.Build;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** One GATT operation at a time; the notification subscription lasts for the connection. */
@SuppressWarnings("deprecation")
public final class BleLink implements Uploader.Link {
    public interface Listener { void state(String value); void log(String line); }
    private static final UUID SERVICE = uuid("ffe0"), TX = uuid("ffe2"), RX = uuid("ffe1"), CCCD = uuid("2902");
    private final Listener listener;
    private final CountDownLatch configured = new CountDownLatch(1);
    private final BlockingQueue<String> incoming = new LinkedBlockingQueue<>(128);
    private final ReplyFrames frames = new ReplyFrames();
    private volatile BluetoothGatt gatt;
    private volatile BluetoothGattCharacteristic writeChar;
    private volatile CountDownLatch writeLatch;
    private volatile int writeStatus = -1;
    private volatile boolean ready, closed;
    private volatile String failure;
    private String identity="unknown";
    String identity(){return identity;}
    public BleLink(Listener observer) { listener = observer; }
    private static UUID uuid(String value) { return UUID.fromString("0000" + value + "-0000-1000-8000-00805f9b34fb"); }
    public void connect(Context context, BluetoothDevice device) {
        identity=device.getAddress();
        gatt = device.connectGatt(context.getApplicationContext(), false, callback, BluetoothDevice.TRANSPORT_LE);
        if (gatt == null) fail("手机未能创建蓝牙连接");
    }
    public boolean isReady() { return ready && !closed && failure == null; }
    public void awaitReady() throws Exception {
        if (!configured.await(18, TimeUnit.SECONDS)) throw new IOException("蓝牙服务准备超时，请先断开其他蓝牙调试 App 再重试");
        if (!isReady()) throw new IOException(failure == null ? "蓝牙尚未就绪" : failure);
    }
    private void fail(String message) {
        failure = message; ready = false; configured.countDown();
        CountDownLatch pending = writeLatch;
        if (pending != null) pending.countDown();
        incoming.clear(); incoming.offer("!" + message);
        listener.state(message);
    }
    private final BluetoothGattCallback callback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
            if (g != gatt || closed) return;
            if (status != BluetoothGatt.GATT_SUCCESS) { fail("蓝牙连接失败，系统状态 " + status); return; }
            if (state == BluetoothProfile.STATE_CONNECTED) {
                listener.state("已连接，正在准备曲谱通道…");
                if (!g.discoverServices()) fail("无法读取蓝牙服务");
            } else if (state == BluetoothProfile.STATE_DISCONNECTED) fail("蓝牙已断开，请重新连接后从头上传");
        }
        @Override public void onServicesDiscovered(BluetoothGatt g, int status) {
            if (g != gatt || closed) return;
            if (status != 0) { fail("读取蓝牙服务失败：" + status); return; }
            BluetoothGattService service = g.getService(SERVICE);
            if (service == null) { fail("未找到 FFE0 服务，请选择已经测试成功的 BLE 兼容模块"); return; }
            writeChar = service.getCharacteristic(TX);
            BluetoothGattCharacteristic notify = service.getCharacteristic(RX);
            if (writeChar == null || (writeChar.getProperties() & BluetoothGattCharacteristic.PROPERTY_WRITE) == 0 || notify == null) {
                fail("未找到 FFE2 写入或 FFE1 回传通道"); return;
            }
            int props = notify.getProperties();
            byte[] enable = (props & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ?
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE : BluetoothGattDescriptor.ENABLE_INDICATION_VALUE;
            if ((props & (BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_INDICATE)) == 0 ||
                !g.setCharacteristicNotification(notify, true)) { fail("无法开启板子回执通知"); return; }
            BluetoothGattDescriptor descriptor = notify.getDescriptor(CCCD);
            if (descriptor == null) { fail("模块没有通知订阅描述符"); return; }
            boolean started;
            if (Build.VERSION.SDK_INT >= 33) started = g.writeDescriptor(descriptor, enable) == BluetoothStatusCodes.SUCCESS;
            else { descriptor.setValue(enable); started = g.writeDescriptor(descriptor); }
            if (!started) fail("通知订阅请求未能发出");
        }
        @Override public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) {
            if (g != gatt || closed || !d.getUuid().equals(CCCD)) return;
            if (status != 0) { fail("通知订阅失败：" + status); return; }
            ready = true; configured.countDown(); listener.state("通道就绪 · FFE2 上传 / FFE1 回执");
        }
        @Override public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            if (g != gatt || !c.getUuid().equals(TX)) return;
            writeStatus = status;
            CountDownLatch pending = writeLatch;
            if (pending != null) pending.countDown();
        }
        @Override public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
            if (g == gatt && c.getUuid().equals(RX)) accept(c.getValue());
        }
        @Override public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c, byte[] value) {
            if (g == gatt && c.getUuid().equals(RX)) accept(value);
        }
    };
    private synchronized void accept(byte[] value) {
        if (value == null || closed) return;
        try { for (String line : frames.feed(value)) {
            if (!incoming.offer(line)) { fail("回执队列溢出，请重连"); return; }
            if(!line.startsWith("B ")&&!line.startsWith("L "))listener.log("板子：" + line);
        } } catch (IOException e) { fail(e.getMessage()); }
    }
    @Override public void clear() { incoming.clear(); }
    @Override public String receive(long timeoutMs) throws Exception {
        if (failure != null && incoming.isEmpty()) throw new IOException(failure);
        return timeoutMs <= 0 ? incoming.poll() : incoming.poll(timeoutMs, TimeUnit.MILLISECONDS);
    }
    @Override public void send(String line) throws Exception {
        if (!isReady()) throw new IOException(failure == null ? "蓝牙尚未就绪" : failure);
        if(line.equals("FEAT")||line.startsWith("MAP")||line.startsWith("GSEL")||line.startsWith("GSONG")||line.equals("GPLAY")||line.equals("GPAUSE")||line.equals("GEXIT"))listener.log("手机："+line);
        byte[] bytes = (line + "\n").getBytes(StandardCharsets.US_ASCII);
        for (int offset = 0; offset < bytes.length; offset += 20) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
            byte[] packet = Arrays.copyOfRange(bytes, offset, Math.min(offset + 20, bytes.length));
            CountDownLatch pending = new CountDownLatch(1);
            writeStatus = -1; writeLatch = pending;
            boolean started;
            if (Build.VERSION.SDK_INT >= 33)
                started = gatt.writeCharacteristic(writeChar, packet, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS;
            else {
                writeChar.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
                writeChar.setValue(packet); started = gatt.writeCharacteristic(writeChar);
            }
            if (!started) { close(); throw new IOException("手机蓝牙写入未启动，请重连后重传"); }
            if (!pending.await(6, TimeUnit.SECONDS)) { close(); throw new IOException("蓝牙写入回调超时，已断开以避免重复发送"); }
            if (writeStatus != 0 || !isReady()) throw new IOException(failure == null ? "蓝牙写入失败：" + writeStatus : failure);
            writeLatch = null;
            // 20 bytes need 5.21ms on the 38400 UART; leave time for the module's UART buffer.
            Thread.sleep(20);
        }
    }
    public void close() {
        closed = true; ready = false;
        BluetoothGatt g = gatt;
        if (g != null) { try { g.disconnect(); } catch (SecurityException ignored) {} g.close(); }
        configured.countDown();
        CountDownLatch pending = writeLatch;
        if (pending != null) pending.countDown();
        incoming.clear(); incoming.offer("!连接已关闭");
    }
}
