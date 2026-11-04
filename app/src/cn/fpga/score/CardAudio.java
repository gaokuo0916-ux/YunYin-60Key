package cn.fpga.score;
import java.io.*;
/** Reads the bounded audio regions of a cloud-free YUNYIN.BIN via a phone card reader. */
public final class CardAudio {
    private static final long SIZE=32L*1024*1024;
    private static final int[] BASE={256,32768};
    private static final class Header{int slot,count,crc;long generation;boolean valid;}
    public static final class Take{public final byte[] pcm;public final long generation;Take(byte[] p,long g){pcm=p;generation=g;}}
    private static long u32(byte[] b,int p){return(b[p]&255L)|((b[p+1]&255L)<<8)|((b[p+2]&255L)<<16)|((b[p+3]&255L)<<24);}
    private static int u16(byte[] b,int p){return(b[p]&255)|((b[p+1]&255)<<8);}
    private static Header header(RandomAccessFile f,int slot)throws IOException{
        byte[] b=new byte[512];f.seek(BASE[slot]*512L);f.readFully(b);Header h=new Header();h.slot=slot;h.count=(int)u32(b,16);h.generation=u32(b,12);h.crc=u16(b,20);int crc=65535;
        for(int i=0;i<37;i++)if(i!=22&&i!=23)crc=StudioProtocol.crcByte(crc,b[i]);
        h.valid=new String(b,0,8,"US-ASCII").equals("YY24AUDI")&&u32(b,8)==1&&((h.generation^u32(b,24))==0xffffffffL)&&h.count>=1&&h.count<=5859375&&u32(b,28)==50000000&&u32(b,32)==1024&&(b[36]&255)==165&&crc==u16(b,22);return h;
    }
    public static Take extract(File file,Uploader.Progress progress)throws Exception{
        try(RandomAccessFile f=new RandomAccessFile(file,"r")){
            if(f.length()!=SIZE)throw new IOException("请选择琴上使用的 32MiB YUNYIN.BIN 文件");byte[] marker=new byte[16];f.readFully(marker);
            if(!new String(marker,0,8,"US-ASCII").equals("YY24STOR")||u32(marker,8)!=1||u32(marker,12)!=65536)throw new IOException("不是云音 TF 存储文件");
            Header a=header(f,0),b=header(f,1);Header first=b.valid&&(!a.valid||(int)(b.generation-a.generation)>0)?b:a,second=first==a?b:a;
            for(Header h:new Header[]{first,second})if(h.valid){
                byte[] pcm=new byte[h.count*2];f.seek((BASE[h.slot]+1L)*512);int offset=0,crc=65535;
                while(offset<pcm.length){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消读取录音");int n=Math.min(8192,pcm.length-offset);f.readFully(pcm,offset,n);for(int j=offset;j<offset+n;j++)crc=StudioProtocol.crcByte(crc,pcm[j]);offset+=n;if(progress!=null)progress.update(offset,pcm.length,"校验 TF 录音");}
                if(crc==h.crc)return new Take(pcm,h.generation);
            }
            throw new IOException("TF 中没有校验通过的完整录音；不导出损坏或未结束的录音");
        }
    }
}
