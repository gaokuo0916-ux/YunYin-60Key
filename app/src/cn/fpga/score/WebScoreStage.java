package cn.fpga.score;
import java.io.*;
/** Private, bounded file handoff. Large scores never travel through an Intent payload. */
public final class WebScoreStage {
 private static File directory(File cache)throws IOException{
  File base=cache.getCanonicalFile(),dir=new File(base,"web_scores");
  if(!dir.getCanonicalFile().getParentFile().equals(base))throw new IOException("下载暂存目录无效");
  if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建下载暂存目录");
  return dir.getCanonicalFile();
 }
 public static void validate(byte[] data,String name)throws IOException{
  ScoreWebImport.Kind kind=ScoreWebImport.classify(data,null,name);
  if(kind==ScoreWebImport.Kind.PAGE)throw new IOException("网站返回的是网页，请先完成登录或按网站提示下载 MIDI 文件");
  if(kind==ScoreWebImport.Kind.MIDI)MidiImport.read(data);
  else if(kind==ScoreWebImport.Kind.XML||kind==ScoreWebImport.Kind.MXL)try{MusicXmlImport.read(data);}catch(Exception e){throw new IOException("MusicXML 内容无法解析",e);}
  else if(kind==ScoreWebImport.Kind.TEXT)try{SongDraft.parse(SongDraft.importText(new String(data,java.nio.charset.StandardCharsets.UTF_8),120));}catch(Exception e){throw new IOException("数字简谱内容无法解析",e);}
 }
 public static File save(File cache,byte[] data,String name)throws IOException{
  if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("下载已取消");
  validate(data,name);File file=File.createTempFile("score-",".download",directory(cache));boolean done=false;
  try{
   try(OutputStream out=new FileOutputStream(file)){out.write(data);}
   if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("下载已取消");
   done=true;return file;
  }finally{if(!done)file.delete();}
 }
 private static File owned(File cache,String path)throws IOException{
  if(path==null)throw new IOException("下载暂存文件已失效，请重新下载");
  File file=new File(path).getCanonicalFile();
  if(!directory(cache).equals(file.getParentFile())||!file.getName().matches("score-[A-Za-z0-9_-]+\\.download"))throw new IOException("下载文件路径无效，请重新下载");
  return file;
 }
 public static byte[] take(File cache,String path)throws IOException{
  File file=owned(cache,path);
  try{
   if(!file.isFile())throw new IOException("下载暂存文件已失效，请重新下载");
   if(file.length()>ScoreWebImport.LIMIT)throw new IOException("曲谱文件超过 8 MB");
   ByteArrayOutputStream out=new ByteArrayOutputStream();
   try(InputStream in=new FileInputStream(file)){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){
    if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("读取已取消");
    if(out.size()+n>ScoreWebImport.LIMIT)throw new IOException("曲谱文件超过 8 MB");out.write(b,0,n);
   }}return out.toByteArray();
  }finally{file.delete();}
 }
 public static void discard(File cache,File file){if(file!=null)try{owned(cache,file.getPath()).delete();}catch(IOException ignored){}}
}
