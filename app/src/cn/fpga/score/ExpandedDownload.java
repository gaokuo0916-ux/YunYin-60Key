package cn.fpga.score;
import java.io.*;
import java.security.*;

/** Single, bounded MIDI fetch; checksum and structural validation precede import. */
public final class ExpandedDownload {
    public static String url(String path)throws IOException{
        if(path==null||!path.matches("(main|study|piano-special)/[a-z0-9-]+/[a-z0-9-]+\\.mid"))throw new IOException("无效的曲谱下载路径");
        return "https://lib.midicn.com/"+path;
    }
    public static void validate(byte[] data,String checksum)throws IOException{
        if(checksum==null||!checksum.matches("[a-f0-9]{32}"))throw new IOException("曲谱校验信息无效");
        try{byte[] digest=MessageDigest.getInstance("MD5").digest(data);StringBuilder hex=new StringBuilder();for(byte b:digest)hex.append(String.format(java.util.Locale.ROOT,"%02x",b&255));if(!hex.toString().equals(checksum))throw new IOException("下载内容与曲库校验不符，请重试或等待曲库更新");}catch(NoSuchAlgorithmException e){throw new IOException(e);}
        MidiImport.read(data);
    }
    public static byte[] download(String path,String checksum)throws IOException{byte[] data=OnlineCatalog.get(url(path),8*1024*1024);validate(data,checksum);return data;}
}
