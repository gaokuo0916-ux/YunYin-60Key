package cn.fpga.score;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Private phone library; CRC-validated data and atomic replace on updates. */
public final class LibraryStore {
    public static final class Entry {
        public final String id, title, origin;
        public final Score score;
        public final long modified;
        Entry(String key, String name, String source, Score value, long time) {
            id=key;title=name;origin=source;score=value;modified=time;
        }
    }
    private final File directory;
    public LibraryStore(File root) throws IOException {
        directory=root;
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("无法建立手机曲库");
    }
    private File path(String id) {
        if (!id.matches("[a-f0-9-]{36}")) throw new IllegalArgumentException("无效曲谱编号");
        return new File(directory,id+".score");
    }
    public synchronized Entry save(String id,String title,String origin,Score score) throws IOException {
        if (id==null) id=UUID.randomUUID().toString();
        title=title.trim(); if(title.isEmpty() || title.length()>160) throw new IllegalArgumentException("曲名需为 1～160 个字符");
        if(origin.length()>2000)origin=origin.substring(0,2000);
        File target=path(id),temp=new File(directory,id+".tmp");
        try(FileOutputStream stream=new FileOutputStream(temp);DataOutputStream out=new DataOutputStream(stream)) {
            byte[] data=score.protocol().getBytes(StandardCharsets.UTF_8);
            out.writeInt(0x59594e33);out.writeUTF(title);out.writeUTF(origin);out.writeInt(data.length);out.write(data);out.flush();stream.getFD().sync();
        }
        try { Files.move(temp.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING); }
        catch(AtomicMoveNotSupportedException e) { Files.move(temp.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING); }
        return new Entry(id,title,origin,score,target.lastModified());
    }
    public synchronized List<Entry> list() {
        List<Entry> result=new ArrayList<>();File[] files=directory.listFiles();if(files==null)return result;
        for(File f:files)if(f.getName().endsWith(".score")) {
            try(DataInputStream in=new DataInputStream(new FileInputStream(f))) {
                int magic=in.readInt();if(magic!=0x59594e32 && magic!=0x59594e33)continue;
                String title=in.readUTF(),origin=in.readUTF(),data;
                if(magic==0x59594e32)data=in.readUTF();
                else{int size=in.readInt();if(size<1 || size>524288)continue;byte[] bytes=new byte[size];in.readFully(bytes);data=new String(bytes,StandardCharsets.UTF_8);}
                result.add(new Entry(f.getName().replace(".score",""),title,origin,Score.parse(data,120),f.lastModified()));
            } catch(IOException|IllegalArgumentException ignored) { /* A corrupt entry cannot become an uploaded score. */ }
        }
        result.sort((a,b)->Long.compare(b.modified,a.modified));return result;
    }
    public synchronized void delete(String id) throws IOException { Files.deleteIfExists(path(id).toPath()); }
}
