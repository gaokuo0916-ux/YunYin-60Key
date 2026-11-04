package cn.fpga.score;
import android.app.*;
import android.content.*;
import android.media.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.nio.file.*;
import java.text.SimpleDateFormat;
import java.util.*;
/** Android UI/cache coordinator. The TF directory is always the record index. */
final class PracticeRecorderController {
 private final MainActivity a;
 private volatile List<PracticeRecords.Entry> entries=Collections.emptyList();
 private volatile PracticeRecords.Capabilities cap;
 private volatile boolean supported,known;
 private volatile String message="连接新版乐器后读取TF练习记录",currentSong="";
 private BleLink session;
 private final Map<String,File> cache=new java.util.concurrent.ConcurrentHashMap<>();
 private String scope=UUID.randomUUID().toString();
 private MediaPlayer player;private File exporting;
 private PracticeRecords.Entry pendingCard;private boolean pendingPlay;
 private boolean awaitingSave;private long expectedGeneration;
 private static final int OPEN_CARD=310,EXPORT_WAV=311;
 PracticeRecorderController(MainActivity host){a=host;}
 void connecting(){stop();supported=false;known=false;cap=null;entries=Collections.emptyList();message="连接后从TF重读目录";session=null;cache.clear();scope=UUID.randomUUID().toString();awaitingSave=false;}
 void connected(BleLink l,boolean support){
  supported=support;if(!support){message="当前固件未提供练习记录目录；原有录音功能仍可使用";return;}
  try{refresh(l);}catch(Exception e){a.main.post(()->{if(a.currentLink()==l){known=false;message="读取TF目录失败："+e.getMessage();a.refresh();}});}
 }
 private Uploader.Progress progress(){return(sent,total,stage)->a.main.post(()->{a.percent=sent*100/Math.max(1,total);a.progressMessage=stage;a.refresh();});}
 private Uploader.Progress downloadProgress(){
  final long begin=System.nanoTime();return(sent,total,stage)->a.main.post(()->{
   a.percent=sent*100/Math.max(1,total);a.progressMessage=AudioTransferProgress.describe(stage,sent,total,(System.nanoTime()-begin)/1000000);a.refresh();
  });
 }
 private void refresh(BleLink l)throws Exception{
  if(session!=l){session=l;cache.clear();scope=UUID.randomUUID().toString();}
  PracticeRecords p=new PracticeRecords(l);PracticeRecords.Capabilities c=p.capabilities();
  List<PracticeRecords.Entry> rows=Collections.unmodifiableList(p.list(c,progress()));
  int count=0,bad=0;for(PracticeRecords.Entry e:rows)if(e.id<20){if(e.state==3)bad++;else count++;}
  final String status=c.mode==0?"TF尚未就绪":c.mode==1?"旧32MiB容器：旧录音可读；新增独立记录需兼容扩容":
   "TF目录已读取 · 新录音 "+count+"/20"+(bad>0?" · 隔离损坏槽 "+bad:"");
  a.main.post(()->{if(a.currentLink()!=l||!l.isReady())return;cap=c;known=true;entries=rows;message=status;a.refresh();});
 }
 private static String date(PracticeRecords.Entry e){
  if(!e.hasDate)return "时间未提供";
  SimpleDateFormat f=new SimpleDateFormat("yyyy-MM-dd HH:mm:ss XXX",Locale.ROOT);
  f.setTimeZone(new SimpleTimeZone(e.zoneMinutes*60000,"手机时区"));
  return "手机时间 "+f.format(new Date(e.timeMillis));
 }
 void describe(JSONObject j,String song)throws JSONException{
  currentSong=song==null?"":song;
  j.put("practiceSupported",a.ready()&&supported);j.put("practiceKnown",a.ready()&&known);
  j.put("practiceCanStart",a.ready()&&supported&&known&&cap!=null&&cap.mode==2);
  j.put("practiceMessage",a.ready()?message:"连接乐器后从TF重新读取记录");
  j.put("practiceTrack",currentSong);
  JSONArray rows=new JSONArray();
  if(a.ready())for(PracticeRecords.Entry e:entries){
   String detail=e.state==3?"目录损坏：不能试听/导出，可明确删除释放":
    String.format(Locale.ROOT,"%.2f 秒 · %s",e.seconds(),date(e));
   if(!e.track.isEmpty())detail+=" · "+e.track;if(!e.warning.isEmpty())detail+=" · "+e.warning;
   rows.put(new JSONObject().put("id",e.key()).put("name",e.name).put("detail",detail).put("playable",e.playable()));
  }
  j.put("practiceRecords",rows);
 }
 private BleLink require()throws IOException{
  if(!a.ready()||!supported)throw new IOException("请连接支持练习记录的新版琴端");
  return a.currentLink();
 }
 private PracticeRecords.Entry find(String key)throws IOException{
  for(PracticeRecords.Entry e:entries)if(e.key().equals(key))return e;
  throw new IOException("列表已变化，请先刷新TF目录");
 }
 void observe(StudioProtocol.LongAudio audio){
  if(!awaitingSave||audio==null||a.busy||!a.ready())return;
  if(audio.state==4){awaitingSave=false;message=PracticeRecords.error(audio.error)+"；已有记录保留";a.refresh();}
  else if(audio.state==3&&audio.generation==expectedGeneration&&audio.count>0){
   awaitingSave=false;BleLink l=a.currentLink();a.progressMessage="录音已提交，重读卡端目录";a.run(()->refresh(l));
  }
 }
 void action(String name,String value)throws Exception{
  if(name.equals("practice-help")){
   new AlertDialog.Builder(a).setTitle("保留旧数据后启用练习记录")
    .setMessage("首版使用256MiB YUNYIN.BIN，含20个最长120秒的独立新录音槽。旧32MiB里的曲谱和录音须保留。\n\n请在电脑运行工程 tools/prepare_practice_storage.py，指定卡内旧文件为 --source、不同新路径为 --output。工具生成新文件并校验旧区相同；不要把空白初始化文件覆盖旧卡。备份旧文件后再把核对好的新文件放到卡根目录。固件会检查FAT32连续分配。\n\n目录和声音保存在TF，手机重装后可重新读取。")
    .setPositiveButton("知道了",null).show();return;
  }
  BleLink l=require();
  if(name.equals("practice-refresh")){a.progressMessage="读取TF练习记录";a.run(()->refresh(l));return;}
  if(name.equals("practice-start")){
   JSONObject data=new JSONObject(value);int seconds=data.optInt("seconds",120);String title=data.optString("name","").trim();
   String track=data.optBoolean("associate",true)?PracticeRecords.fitTrack(currentSong):"";
   boolean withTime=data.optBoolean("phoneTime",false);long time=withTime?System.currentTimeMillis():0;
   int zone=withTime?TimeZone.getDefault().getOffset(time)/60000:0;
   a.progressMessage="准备独立录音槽";
   a.run(()->{
    new PracticeRecords(l).start(seconds,title,track,withTime,time,zone);
    StudioProtocol.LongAudio started=new StudioProtocol(l).audio();
    a.main.post(()->{if(a.currentLink()!=l)return;awaitingSave=true;expectedGeneration=started.generation;message="琴端正在录制；停止或到时后写入校验并提交目录";a.progressMessage=message;a.refresh();});
   });return;
  }
  if(name.equals("practice-stop")){
   a.progressMessage="结束录音并等待TF提交";
   a.run(()->{
    new PracticeRecords(l).stop();long end=System.nanoTime()+90000000000L;StudioProtocol.LongAudio state;
    do{Thread.sleep(100);state=new StudioProtocol(l).audio();
     if(state.state==4)throw new IOException(PracticeRecords.error(state.error));
     if(System.nanoTime()>end)throw new IOException("琴端仍在提交，请稍后刷新目录确认；不要假定本段已保存");
    }while(state.state==1||state.state==2||state.state==5||state.state==6);
    if(state.state!=3||state.count==0)throw new IOException("没有已提交的非空录音");
    a.main.post(()->awaitingSave=false);refresh(l);
   });return;
  }
  PracticeRecords.Entry e=find(value);
  if(name.equals("practice-rename")){
   if(!e.playable())throw new IOException("损坏目录项请先导出可恢复内容或明确删除");
   EditText text=new EditText(a);text.setSingleLine();text.setText(e.name);
   new AlertDialog.Builder(a).setTitle("重命名卡端记录").setView(text).setMessage("最多64个UTF8字节，约21个汉字；保留原曲目关联和已提供日期。")
    .setNegativeButton("取消",null).setPositiveButton("保存",(d,w)->{
     String title=text.getText().toString().trim();a.progressMessage="写入并核对新名称";
     a.run(()->{new PracticeRecords(l).rename(e,title);refresh(l);});
    }).show();return;
  }
  if(name.equals("practice-delete")){
   new AlertDialog.Builder(a).setTitle("删除这条TF练习记录？").setMessage(e.name+"\n确认后提交删除标记，再释放该槽供新录音使用。其他记录保留。")
    .setNegativeButton("保留",null).setPositiveButton("删除",(d,w)->{stop();a.progressMessage="提交并核对删除标记";a.run(()->{new PracticeRecords(l).delete(e);cache.remove(e.key());refresh(l);});}).show();return;
  }
  if(name.equals("practice-play")||name.equals("practice-export")){
   if(!e.playable())throw new IOException("损坏目录项不能试听或导出");
   boolean play=name.equals("practice-play");File cached=cache.get(e.key());
   if(cached!=null&&cached.isFile()){a.run(()->{if(!new PracticeRecords(l).load(e.id).same(e))throw new IOException("卡端记录已变化，请刷新");a.main.post(()->finishAudio(cached,e,play));});return;}
   new AlertDialog.Builder(a).setTitle(play?"取得录音后试听":"取得录音后导出")
    .setMessage(String.format(Locale.ROOT,"本段录音 %.2f 秒，%.1f KB。\n",e.seconds(),e.count*2.0/1024)+"可用读卡器打开对应YUNYIN.BIN读取所选记录。新版整页无损回传在38400串口下理想数据发送约"+AudioTransferProgress.idealTime(e.count)+"，不含蓝牙等待与重试，实际取决于连接；回传中按实际速度更新剩余时间。旧固件会自动使用较慢的兼容方式。长录音推荐手机OTG读卡器。两种方式均校验整段PCM。")
    .setNegativeButton("取消",null).setNeutralButton("读卡器打开文件",(d,w)->{
     pendingCard=e;pendingPlay=play;Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");a.startActivityForResult(i,OPEN_CARD);
    }).setPositiveButton("蓝牙回传",(d,w)->{a.percent=0;a.progressMessage="回传所选TF录音";a.run(()->{byte[] pcm=new PracticeRecords(l).download(e,downloadProgress());File file=save(e,pcm);a.main.post(()->finishAudio(file,e,play));});}).show();return;
  }
  throw new IOException("未知练习记录操作");
 }
 private File save(PracticeRecords.Entry e,byte[] pcm)throws Exception{
  File dir=new File(a.getCacheDir(),"practice_audio");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建试听缓存");
  File file=new File(dir,"cache_"+scope+"_"+e.key()+".wav"),partial=new File(dir,file.getName()+".partial");
  try{Files.write(partial.toPath(),StudioProtocol.wav(pcm));Files.move(partial.toPath(),file.toPath(),StandardCopyOption.REPLACE_EXISTING);}
  finally{Files.deleteIfExists(partial.toPath());}
  cache.put(e.key(),file);
  File[] all=dir.listFiles((d,n)->n.startsWith("cache_")&&n.endsWith(".wav"));if(all!=null){
   Arrays.sort(all,(x,y)->Long.compare(y.lastModified(),x.lastModified()));
   for(int n=2;n<all.length;n++)Files.deleteIfExists(all[n].toPath());
  }
  return file;
 }
 private void finishAudio(File file,PracticeRecords.Entry entry,boolean play){
  try{
   if(play){stop();player=new MediaPlayer();player.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());player.setDataSource(file.getAbsolutePath());player.setOnPreparedListener(MediaPlayer::start);player.setOnCompletionListener(p->stop());player.setOnErrorListener((p,w,e)->{stop();a.showError(new IOException("无法播放已校验的WAV"));return true;});player.prepareAsync();}
   else {exporting=file;Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("audio/wav");
    i.putExtra(Intent.EXTRA_TITLE,entry.name.replaceAll("[\\\\/:*?\"<>|]","_")+"_"+entry.id+"_"+entry.sequence+".wav");a.startActivityForResult(i,EXPORT_WAV);}
  }catch(Exception e){a.showError(e);}
 }
 boolean result(int request,int result,Intent data){
  if(request!=OPEN_CARD&&request!=EXPORT_WAV)return false;
  if(result!=Activity.RESULT_OK||data==null||data.getData()==null){pendingCard=null;exporting=null;return true;}Uri uri=data.getData();
  if(request==OPEN_CARD){
   PracticeRecords.Entry entry=pendingCard;boolean play=pendingPlay;pendingCard=null;if(entry==null)return true;
   a.progressMessage="只读校验所选TF录音";a.percent=0;
   a.run(()->{
    try(ParcelFileDescriptor fd=a.getContentResolver().openFileDescriptor(uri,"r")){
     if(fd==null)throw new IOException("无法打开卡文件");
     try(FileInputStream in=new FileInputStream(fd.getFileDescriptor())){
      byte[] pcm=CardRecordingFile.extract(new CardRecordingFile.ChannelSource(in.getChannel()),entry,progress());
      File file=save(entry,pcm);a.main.post(()->finishAudio(file,entry,play));
     }
    }
   });
  }else{
   File file=exporting;exporting=null;if(file==null)return true;a.progressMessage="导出校验后的WAV";
   a.run(()->{try(InputStream in=new FileInputStream(file);OutputStream out=a.getContentResolver().openOutputStream(uri,"wt")){
    if(out==null)throw new IOException("无法写入导出位置");byte[] b=new byte[8192];int n;
    while((n=in.read(b))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消导出");out.write(b,0,n);}
   }a.main.post(()->{a.progressMessage="WAV已导出，TF原录音保留";a.refresh();});});
  }
  return true;
 }
 private void stop(){if(player!=null){player.release();player=null;}}
 void visible(boolean value){if(!value)stop();}
 void close(){stop();}
}
