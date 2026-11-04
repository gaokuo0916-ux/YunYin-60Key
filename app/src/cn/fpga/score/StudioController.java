package cn.fpga.score;
import android.app.*;
import android.content.*;
import android.media.*;
import android.net.Uri;
import android.widget.Toast;
import org.json.*;
import java.io.*;
import java.nio.file.*;
import java.text.SimpleDateFormat;
import java.util.*;
/** All device operations share the activity's serial executor. */
final class StudioController {
 final MainActivity a;private final PracticeRecorderController practice;private final File dir;private final SharedPreferences prefs;
 int capabilities,rank,draftRank,recordState;String recordMessage="";boolean identified,mappingKnown;String featureMessage="连接后识别琴端功能",queryWarning="";private StudioProtocol.State state;private StudioProtocol.Storage storage;private StudioProtocol.LongAudio audio;
 private StudioProtocol.Pitch pitch;private StudioProtocol.Keyboard keyboard;
 private RhythmStatus rhythm;private StudioProtocol.SdDiagnostic sdDiagnostic;private final RhythmHistory rhythmHistory;
 private int timbre;private boolean timbreKnown;
 private StudioProtocol.Polyphony polyphony;private boolean polySingleConfirmed;
 private boolean polling,closed,visible=true;private int errors,auxiliary;private long nextAuxiliary;private MediaPlayer player;private File exporting;
 StudioController(MainActivity host)throws IOException{a=host;practice=new PracticeRecorderController(host);dir=new File(a.getFilesDir(),"takes_v24");if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建录音目录");prefs=a.getSharedPreferences("studio_v24",0);rhythmHistory=new RhythmHistory(new File(a.getFilesDir(),"rhythm_history_v1.tsv"));draftRank=prefs.getInt("mapping",0);try{KeyMapping.decode(draftRank);}catch(Exception e){draftRank=0;}a.main.postDelayed(poll,700);}
 void connecting(){practice.connecting();keyboard=null;pitch=null;polyphony=null;polySingleConfirmed=false;capabilities=0;identified=false;mappingKnown=false;timbreKnown=false;timbre=0;rank=0;state=null;storage=null;audio=null;sdDiagnostic=null;rhythm=null;recordState=0;errors=0;featureMessage="等待识别琴端功能";queryWarning="";}
 void connected(BleLink l)throws Exception{
  try{int c=StudioMonitor.identify(new StudioProtocol(l));
   a.main.post(()->{if(a.currentLink()!=l||!l.isReady())return;capabilities=c;identified=true;errors=0;nextAuxiliary=0;
    featureMessage=c==0?"琴端不支持拓展命令；基础上传可用，请烧录配套游戏版固件":String.format(Locale.ROOT,"琴端功能 0x%04X · 键位%s · 挑战%s",c,(c&1)!=0?"支持":"不支持",(c&64)!=0?"支持":"不支持");queryWarning="";a.refresh();});
   practice.connected(l,(c&32768)!=0);
  }catch(Exception e){a.main.post(()->{if(a.currentLink()!=l)return;featureMessage="琴端功能识别未完成："+e.getMessage()+"；可点重新识别琴端";a.refresh();});throw e;}
 }
 private final Runnable poll=new Runnable(){public void run(){
  if(closed)return;a.main.postDelayed(this,rhythm!=null&&rhythm.enabled&&rhythm.state!=5?250:700);if(!visible||a.busy||polling||!a.ready()||(capabilities&375)==0)return;
  final BleLink l=a.currentLink();final int caps=capabilities;final Score queryScore=a.score;polling=true;
  a.enqueue(()->{try{long now=System.nanoTime()/1000000L;int aux=now>=nextAuxiliary?auxiliary++%3:-1;
   StudioMonitor.Snapshot snapshot=StudioMonitor.read(new StudioProtocol(l),caps,aux,queryScore);if(aux>=0)nextAuxiliary=now+(snapshot.auxFailed?30000:1500);
   RhythmStatus game=snapshot.game;StudioProtocol.State t=snapshot.state;StudioProtocol.Recording r=snapshot.recording;StudioProtocol.Storage card=snapshot.storage;StudioProtocol.LongAudio take=snapshot.audio;archive(l,game);
   a.main.post(()->{polling=false;if(closed||l!=a.currentLink()||!l.isReady())return;errors=snapshot.primaryOkay()?0:errors+1;queryWarning=snapshot.warning();state=t;keyboard=snapshot.keyboard;pitch=snapshot.pitch;rhythm=game;if(snapshot.rank!=null){rank=snapshot.rank;mappingKnown=true;}else if(snapshot.stateFailed)mappingKnown=false;if(card!=null)storage=card;if(take!=null){audio=take;practice.observe(take);}if(game!=null&&game.enabled){a.playing=false;a.paused=false;}else if(t!=null){if(a.uploaded&&t.user){a.paused=t.state==6;a.playing=t.state>=1&&t.state<=4;}if(!t.user){a.playing=false;a.paused=false;}}
    if(snapshot.polyphony!=null){polyphony=snapshot.polyphony;if(!polyphony.demo)polySingleConfirmed=false;}
    if(snapshot.sdDiagnostic!=null)sdDiagnostic=snapshot.sdDiagnostic;
    if(snapshot.timbre!=null){timbre=snapshot.timbre;timbreKnown=true;}else if(snapshot.timbreFailed)timbreKnown=false;
    if(snapshot.scoreMatches!=null&&a.score==queryScore)a.uploaded=snapshot.scoreMatches;
    if(r!=null){recordState=r.state;recordMessage=r.state==1?"已准备：按下实体琴键开始录音":r.state==2?"琴端正在采集真实 PCM":r.state==3?"录音完成 · "+String.format(Locale.ROOT,"%.2f",r.count/48828.125)+" 秒，点击回传":r.state==4?"录音已取消":"尚未录音";}a.refresh();});
  }catch(Exception e){a.main.post(()->{polling=false;if(l!=a.currentLink())return;++errors;state=null;pitch=null;rhythm=null;queryWarning="状态查询失败："+e.getMessage()+"；已保留琴端确认的功能，可点重新识别琴端";a.refresh();});}});
 }};
 void describe(JSONObject j)throws JSONException{
  practice.describe(j,rhythm!=null&&rhythm.enabled?rhythm.title():a.scoreName);
  j.put("keyboard60",a.ready()&&(capabilities&8192)!=0);j.put("keyboardKnown",a.ready()&&keyboard!=null);
  j.put("keyboardBase",keyboard==null?36:keyboard.base);j.put("keyboardCount",keyboard==null?60:keyboard.count);
  j.put("keyboardMask",keyboard==null?"0000000000000000":keyboard.mask);

  j.put("capabilities",a.ready()?capabilities:0);j.put("rank",a.ready()?rank:0);j.put("draftRank",draftRank);j.put("recordState",a.ready()?recordState:0);j.put("recordMessage",recordMessage);
  j.put("featuresIdentified",a.ready()&&identified);j.put("featureMessage",a.ready()?featureMessage:"连接后识别琴端功能");j.put("queryWarning",a.ready()?queryWarning:"");j.put("mappingKnown",a.ready()&&mappingKnown);
  j.put("polySupported",a.ready()&&(capabilities&512)!=0);j.put("polyKnown",a.ready()&&polyphony!=null);j.put("polyActive",polyphony==null?0:polyphony.active);j.put("polyHeld",polyphony==null?0:polyphony.held);j.put("polyDemo",polyphony!=null&&polyphony.demo);j.put("polyDeadline",polyphony!=null&&polyphony.deadline);j.put("polySingle",polySingleConfirmed);
  j.put("timbre",timbre);j.put("timbreKnown",a.ready()&&(capabilities&256)!=0&&timbreKnown);
  boolean match=a.ready()&&state!=null&&a.uploaded&&state.user&&(rhythm==null||!rhythm.enabled);j.put("telemetry",match);j.put("index",match?state.index:0);j.put("guideState",match?state.state:0);j.put("keys",a.ready()&&state!=null?state.keys:0);j.put("held",match?state.held:0);j.put("expected",match?state.expected:0);
  j.put("storageState",storage==null?0:storage.state);j.put("storageError",storage==null?0:storage.error);j.put("persisted",storage!=null&&storage.state==3&&a.score!=null&&storage.count==a.score.count()&&storage.crc==a.score.crc&&storage.rank==rank);j.put("storageMessage",storage==null?"连接后读取 TF 状态":storage.state==4?StudioProtocol.storageError(storage.error):storage.state==3?"TF 已保存一首曲谱，断电后自动恢复":storage.state==2?"TF 正在读写校验":storage.state==1?"TF 存储就绪，尚未保存曲谱":"等待 TF 卡初始化");
  j.put("sdDiagnosticSupported",a.ready()&&(capabilities&128)!=0);
  j.put("sdDiagnosticMessage",sdDiagnostic==null?"等待琴端返回初始化详情":sdDiagnostic.message());
  j.put("sdDiagnosticCode",sdDiagnostic==null?"":sdDiagnostic.raw);
  j.put("sdRetryNote",sdDiagnostic==null?"先点读取 TF 诊断":sdDiagnostic.initialized?"TF 通信握手已完成；若文件系统报错，请按上方提示处理":!sdDiagnostic.canRetry()?"TF 正在初始化，等待琴端结果":a.playing||a.paused||(rhythm!=null&&rhythm.enabled)?"先结束跟弹或挑战，再重新初始化 TF":state!=null&&state.keys!=0?"松开全部琴键后可重新初始化 TF":"可重新初始化；此操作仅重试通信握手，不会格式化或写入曲谱");
  j.put("sdCanRetry",a.ready()&&sdDiagnostic!=null&&sdDiagnostic.canRetry()&&!a.playing&&!a.paused&&
    (state==null||state.keys==0)&&(rhythm==null||!rhythm.enabled));
  j.put("longState",a.ready()&&audio!=null?audio.state:0);j.put("longCount",audio==null?0:audio.count);j.put("longSaved",audio!=null&&(audio.state==3||audio.state==4)&&audio.count>0);j.put("longMessage",audio==null?"需要新版琴端固件和 TF 卡":audio.state==1?"已准备：按实体琴键开始录音":audio.state==2?"琴端录音中 · "+String.format(Locale.ROOT,"%.1f",audio.count/48828.125)+" 秒":audio.state==3?"TF 已保存完整录音 · "+String.format(Locale.ROOT,"%.2f",audio.count/48828.125)+" 秒":audio.state==4?(audio.error==5?"TF 写入未能跟上，录音缓存已满；本次录音已停止，上次完整录音仍保留":"本次录音未完成（"+audio.error+"），上次完整录音仍保留"):audio.state==5?"正在准备 TF 录音区域":audio.state==6?"正在写入并校验剩余录音":"TF 中尚无完整录音");
  JSONArray list=new JSONArray();for(File f:files())list.put(new JSONObject().put("id",f.getName()).put("name",f.getName().replace("take_","").replace(".wav","").replace('_',' ')).put("detail",String.format(Locale.ROOT,"%.2f 秒 · WAV · 已校验",(f.length()-44)/97656.25)));j.put("takes",list);
  boolean nativeMatch=match&&a.score!=null&&a.score.nativePitch&&pitch!=null&&pitch.nativeFormat&&pitch.selected&&pitch.ready&&state.index==pitch.index;
  j.put("nativeKnown",nativeMatch);j.put("nativeCode",nativeMatch?pitch.code:0);j.put("nativeMissing",nativeMatch&&pitch.missing);
  j.put("rhythm",a.ready()&&rhythm!=null?gameJson(rhythm):JSONObject.NULL);
  JSONArray history=new JSONArray();for(RhythmHistory.Entry e:rhythmHistory.entries())history.put(gameJson(e.result).put("time",e.time));
  j.put("challengeHistory",history);
 }
 private synchronized void archive(BleLink link,RhythmStatus game)throws IOException{
  if(game==null)return;
  String key="rhythm_last_"+link.identity(),last=prefs.getString(key,"");
  if(game.enabled&&game.state==5&&game.round!=0){
   if(!last.equals(game.raw)){rhythmHistory.add(System.currentTimeMillis(),game);prefs.edit().putString(key,game.raw).commit();}
  }else if(!last.isEmpty())prefs.edit().remove(key).apply();
 }
 private JSONObject gameJson(RhythmStatus g)throws JSONException{
  return new JSONObject().put("songPack",g.songPack).put("songTitle",g.title()).put("songId",g.songId).put("rangeMissing",g.rangeMissing).put("enabled",g.enabled).put("state",g.state).put("level",g.level+1).put("unlocked",g.unlocked+1)
   .put("countIn",g.countIn).put("bpm",g.bpm).put("degree",g.degree).put("nextDegree",g.nextDegree).put("cursor",g.cursor).put("events",g.events)
   .put("score",g.score).put("combo",g.combo).put("maxCombo",g.maxCombo).put("perfect",g.perfect).put("good",g.good)
   .put("wrong",g.wrong).put("missed",g.missed).put("extra",g.extra).put("best",g.best).put("notes",g.notes)
   .put("passed",g.passed).put("round",g.round).put("phase",g.phase()).put("judgement",g.judgementText()).put("deviation",g.deviation);
 }
 private void challengeAction(String name,String value)throws Exception{
  require(64);if(polyphony!=null&&polyphony.demo)throw new IOException("请先结束复音测试");final BleLink l=a.currentLink();final int selected=(name.equals("challenge-select")||name.equals("challenge-song")||name.equals("challenge-play"))?Integer.parseInt(value):0;
  if(name.equals("challenge-song"))require(16384);
  if(name.equals("challenge-song")?(selected<1||selected>15):(selected!=0&&(selected<1||selected>3)))throw new IOException("请选择第1至3关");
  a.progressMessage="等待琴端确认游戏操作";
  a.run(()->{StudioProtocol p=new StudioProtocol(l);
   if(name.equals("challenge-song"))p.selectChallengeSong(selected-1);
   if(name.equals("challenge-select")||(name.equals("challenge-play")&&(capabilities&16384)==0))p.selectChallenge(selected);
   if(name.equals("challenge-play"))p.playChallenge();
   if(name.equals("challenge-pause"))p.pauseChallenge();
   if(name.equals("challenge-exit"))p.exitChallenge();
   RhythmStatus result=p.rhythm();archive(l,result);
   a.main.post(()->{if(l!=a.currentLink())return;rhythm=result;a.playing=false;a.paused=false;a.progressMessage="琴端游戏状态已确认";a.refresh();});
  });
 }
 private File[] files(){File[] fs=dir.listFiles((d,n)->n.matches("take_[0-9_]+\\.wav"));if(fs==null)return new File[0];Arrays.sort(fs,(x,y)->Long.compare(y.lastModified(),x.lastModified()));return fs;}
 private File selected(String id)throws IOException{for(File f:files())if(f.getName().equals(id))return f;throw new IOException("录音文件不存在");}
 private void require(int bit)throws IOException{if(!a.ready()||(capabilities&bit)==0)throw new IOException("请连接支持此功能的新版琴端固件");}
 void action(String name,String value)throws Exception{
  if(name.startsWith("practice-")){practice.action(name,value);return;}
  if(name.equals("keyboard-octave")){require(8192);final BleLink l=a.currentLink();final int n=Integer.parseInt(value);
   a.run(()->{StudioProtocol.Keyboard result=new StudioProtocol(l).octave(n);a.main.post(()->{if(l==a.currentLink()){keyboard=result;a.refresh();}});});return;}

  if(name.equals("native-skip")){require(2048);final BleLink l=a.currentLink();a.run(()->{StudioProtocol p=new StudioProtocol(l);StudioProtocol.Pitch next=p.skipMissing();StudioProtocol.State nextState=p.state();a.main.post(()->{if(l==a.currentLink()){pitch=next;state=nextState;a.refresh();}});});return;}
  if(name.startsWith("challenge-")){if(!Arrays.asList("challenge-select","challenge-song","challenge-play","challenge-pause","challenge-exit").contains(name))throw new IOException("未知游戏操作");challengeAction(name,value);return;}switch(name){
   case "poly-demo":case "poly-music":case "poly-stop":case "poly-release":case "poly-retune":{
    require(512);if(!name.equals("poly-stop")&&(a.playing||a.paused||(rhythm!=null&&rhythm.enabled)))throw new IOException("请先结束跟弹或挑战，并松开琴键");
    if(name.equals("poly-retune")&&!polySingleConfirmed)throw new IOException("请先开始单频复音测试");
    final String action=name;final int number=value.isEmpty()?0:Integer.parseInt(value);final BleLink l=a.currentLink();
    a.progressMessage="等待琴端执行并读取真实声部状态";
    a.run(()->{StudioProtocol p=new StudioProtocol(l);StudioProtocol.Polyphony result;
     if(action.equals("poly-demo"))result=p.polyDemo(number,true);
     else if(action.equals("poly-music"))result=p.polyDemo(32,false);
     else if(action.equals("poly-stop"))result=p.polyStop();
     else if(action.equals("poly-release"))result=p.polyRelease(number);
     else result=p.polyRetune(number);
     a.main.post(()->{if(a.currentLink()!=l)return;polyphony=result;
      if(action.equals("poly-demo"))polySingleConfirmed=true;
      else if(action.equals("poly-music")||action.equals("poly-stop"))polySingleConfirmed=false;
      a.progressMessage="琴端已确认：活跃 "+result.active+" / 32，按住 "+result.held;a.refresh();});
    });break;
   }
   case "device-refresh":{if(!a.ready())throw new IOException("请先连接乐器");BleLink l=a.currentLink();a.progressMessage="重新识别琴端功能";a.run(()->connected(l));break;}
   case "timbre-set":{require(256);if(state!=null&&state.keys!=0)throw new IOException("请先松开全部琴键，再切换音色");final int selected=Integer.parseInt(value);if(selected<0||selected>2)throw new IOException("请选择钢琴、吉他或手风琴");BleLink l=a.currentLink();a.progressMessage="切换音色并读取琴端确认";a.run(()->{try{int actual=new StudioProtocol(l).timbre(selected);a.main.post(()->{if(l!=a.currentLink()||!l.isReady())return;timbre=actual;timbreKnown=true;a.progressMessage="琴端音色已确认："+new String[]{"钢琴","吉他","手风琴"}[actual];a.refresh();});}catch(Exception e){a.main.post(()->{if(l!=a.currentLink())return;timbreKnown=false;a.refresh();});throw e;}});break;}
   case "save-map":{int n=Integer.parseInt(value);KeyMapping.decode(n);draftRank=n;prefs.edit().putInt("mapping",n).apply();Toast.makeText(a,"键位配置已存手机，尚未改变琴键",Toast.LENGTH_SHORT).show();a.refresh();break;}
   case "apply-map":{require(1);if(a.playing||a.paused||(rhythm!=null&&rhythm.enabled&&rhythm.state!=0&&rhythm.state!=5))throw new IOException("请先结束当前跟弹或挑战，并松开全部琴键");int n=Integer.parseInt(value);KeyMapping.decode(n);BleLink l=a.currentLink();a.progressMessage="应用键位并读回确认";a.run(()->{new StudioProtocol(l).mapping(n);a.main.post(()->{if(l!=a.currentLink())return;rank=n;mappingKnown=true;draftRank=n;prefs.edit().putInt("mapping",n).apply();a.progressMessage="琴端键位已确认";a.refresh();});});break;}
  case "card-prepare":{new AlertDialog.Builder(a).setTitle("创建 TF 专用存储文件").setMessage("需要 FAT32 的 microSD／TF 卡。将生成 32MiB 的 YUNYIN.BIN，放到卡的根目录。建议在空白卡上创建，以保证文件连续。不会格式化卡，也不会删除其他文件。请勿覆盖需要保留的旧存储文件。").setNegativeButton("取消",null).setPositiveButton("选择保存位置",(d,w)->{Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("application/octet-stream");i.putExtra(Intent.EXTRA_TITLE,"YUNYIN.BIN");a.startActivityForResult(i,207);}).show();break;}
  case "card-save":{require(16);if(a.score!=null&&a.score.nativePitch&&(capabilities&4096)==0)throw new IOException("当前琴端仅支持原谱RAM跟弹；请更新支持原音高TF保存的配套固件");if(!a.uploaded||a.score==null)throw new IOException("先上传当前曲谱，再保存到 TF 卡");if(a.playing||a.paused)throw new IOException("先结束跟弹并松开全部琴键");BleLink l=a.currentLink();Score score=a.score;a.percent=0;a.progressMessage="准备断电保存";a.run(()->{StudioProtocol.Storage card=new StudioProtocol(l).persist(score,(sent,total,stage)->a.main.post(()->{a.progressMessage=stage;a.refresh();}));a.main.post(()->{storage=card;a.progressMessage="TF 保存与读回校验完成";a.refresh();});});break;}
  case "sd-info":{require(128);BleLink l=a.currentLink();a.progressMessage="读取琴端 TF 初始化详情";a.run(()->{StudioProtocol p=new StudioProtocol(l);StudioProtocol.SdDiagnostic d=p.sdDiagnostic();StudioProtocol.Storage card=p.storage();a.main.post(()->{if(a.currentLink()!=l)return;sdDiagnostic=d;storage=card;a.progressMessage=d.message();a.refresh();});});break;}
  case "sd-retry":{require(128);if(a.playing||a.paused||(rhythm!=null&&rhythm.enabled))throw new IOException("先结束跟弹或挑战，并松开全部琴键");BleLink l=a.currentLink();a.progressMessage="重新初始化琴端 TF 卡";a.run(()->{StudioProtocol p=new StudioProtocol(l);p.retrySdInitialization();StudioProtocol.SdDiagnostic d=p.sdDiagnostic();StudioProtocol.Storage card=p.storage();a.main.post(()->{if(a.currentLink()!=l)return;sdDiagnostic=d;storage=card;nextAuxiliary=0;auxiliary=1;a.progressMessage="已启动 TF 初始化，等待琴端回传结果";a.refresh();});});break;}
  case "card-recall":{require(16);if(a.playing||a.paused)throw new IOException("先结束跟弹并松开全部琴键");BleLink l=a.currentLink();a.progressMessage="从 TF 恢复曲谱";a.run(()->{StudioProtocol p=new StudioProtocol(l);p.recall();long until=System.nanoTime()+90000000000L;StudioProtocol.Storage card;do{Thread.sleep(300);card=p.storage();if(card.state==4)throw new IOException(StudioProtocol.storageError(card.error));}while(card.state==2&&System.nanoTime()<until);if(card.state!=3)throw new IOException("TF 中没有可恢复的有效曲谱");boolean match=p.matches(a.score);final StudioProtocol.Storage ready=card;a.main.post(()->{storage=ready;a.uploaded=match;a.progressMessage=match?"已恢复当前曲谱":"琴端已恢复 TF 曲谱，请从琴上第八键启动";a.refresh();});});break;}
  case "audio-arm":{require(32);int sec=Integer.parseInt(value);BleLink l=a.currentLink();a.progressMessage="准备 TF 录音";a.run(()->{new StudioProtocol(l).armAudio(sec);a.main.post(()->{a.progressMessage="等待琴端进入录音准备状态";a.refresh();});});break;}
  case "audio-stop":{require(32);if(audio==null||(audio.state!=1&&audio.state!=2))throw new IOException("请等待琴端进入已准备或正在录音状态");BleLink l=a.currentLink();a.progressMessage="结束并保存录音";a.run(()->new StudioProtocol(l).stopAudio());break;}
  case "audio-download":{require(32);if(audio==null||audio.count==0)throw new IOException("TF 中没有完整录音");new AlertDialog.Builder(a).setTitle("通过蓝牙回传录音").setMessage(String.format(java.util.Locale.ROOT,"本段录音 %.2f 秒，%.1f KB。\n",audio.count/48828.125,audio.count*2.0/1024)+"38400 串口回传这段录音的理想数据发送约 "+AudioTransferProgress.idealTime(audio.count)+"（未含蓝牙等待与重试），实际取决于蓝牙速度，回传中按实测速率估计剩余时间。长录音建议用手机 OTG 读卡器读取 YUNYIN.BIN，再点“从 TF 文件导入”，会快很多。回传完成会做整段校验。").setNegativeButton("暂不回传",null).setPositiveButton("开始回传",(d,w)->{BleLink l=a.currentLink();a.percent=0;a.progressMessage="读取 TF 录音信息";a.run(()->{StudioProtocol p=new StudioProtocol(l);StudioProtocol.LongAudio take=p.audio();final long begin=System.nanoTime();byte[] pcm=p.downloadAudio(take,(sent,total,stage)->a.main.post(()->{a.percent=sent*100/total;a.progressMessage=AudioTransferProgress.describe(stage,sent,total,(System.nanoTime()-begin)/1000000);a.refresh();}));savePcm(pcm);});}).show();break;}
  case "audio-import":{Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");a.startActivityForResult(i,208);break;}
  case "record-arm":case "record-cancel":case "record-download":
   throw new IOException("短片段录音已取消，请使用录到 TF 功能");
  case "take-play":{File f=selected(value);stop();player=new MediaPlayer();player.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());player.setDataSource(f.getAbsolutePath());player.setVolume(.6f,.6f);player.setOnCompletionListener(p->stop());player.setOnErrorListener((p,w,e)->{stop();return true;});player.prepare();player.start();break;}
  case "take-export":{exporting=selected(value);Intent i=new Intent(Intent.ACTION_CREATE_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("audio/wav");i.putExtra(Intent.EXTRA_TITLE,exporting.getName());a.startActivityForResult(i,206);break;}
  case "take-delete":{File f=selected(value);new AlertDialog.Builder(a).setTitle("删除这段录音？").setMessage(f.getName()).setNegativeButton("保留",null).setPositiveButton("删除",(d,w)->{stop();try{Files.delete(f.toPath());a.refresh();}catch(Exception e){a.showError(e);}}).show();break;}
  case "takes-refresh":a.refresh();break;
 }}
 boolean result(int request,int result,Intent data){
  if(practice.result(request,result,data))return true;
  if(request==208){if(result==Activity.RESULT_OK&&data!=null&&data.getData()!=null){Uri uri=data.getData();a.percent=0;a.progressMessage="读取 TF 存储文件";a.run(()->{File temp=new File(a.getCacheDir(),"take_import.bin.partial");try{try(InputStream in=a.getContentResolver().openInputStream(uri);OutputStream out=new FileOutputStream(temp)){if(in==null)throw new IOException("无法读取选择的文件");byte[] block=new byte[8192];int n,total=0;while((n=in.read(block))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消导入");total+=n;if(total>32*1024*1024)throw new IOException("文件超过 32MiB，请选择 YUNYIN.BIN");out.write(block,0,n);}}CardAudio.Take take=CardAudio.extract(temp,(sent,total,stage)->a.main.post(()->{a.percent=sent*100/total;a.progressMessage=stage;a.refresh();}));savePcm(take.pcm);}finally{Files.deleteIfExists(temp.toPath());}});}return true;}
  if(request==207){if(result==Activity.RESULT_OK&&data!=null&&data.getData()!=null){Uri uri=data.getData();a.progressMessage="创建 32MiB 存储文件";a.percent=0;a.run(()->{try(OutputStream out=a.getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException("无法创建文件");byte[] block=new byte[32768];byte[] magic="YY24STOR".getBytes("US-ASCII");System.arraycopy(magic,0,block,0,8);block[8]=1;block[14]=1;for(int i=0;i<1024;i++){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("初始化未完成，请重新创建文件");out.write(block);if(i==0)Arrays.fill(block,(byte)0);if(i%32==0){final int percent=i*100/1024;a.main.post(()->{a.percent=percent;a.refresh();});}}}a.main.post(()->{a.progressMessage="初始化文件已创建，请确认文件名为 YUNYIN.BIN 并放在 TF 根目录";Toast.makeText(a,a.progressMessage,Toast.LENGTH_LONG).show();});});}return true;}
  if(request!=206)return false;File f=exporting;exporting=null;if(result==Activity.RESULT_OK&&data!=null&&data.getData()!=null&&f!=null){Uri uri=data.getData();a.progressMessage="导出 WAV";a.run(()->{try(InputStream in=new FileInputStream(f);OutputStream out=a.getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException("无法写入导出文件");byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消导出");out.write(b,0,n);}}a.main.post(()->Toast.makeText(a,"WAV 已导出",Toast.LENGTH_SHORT).show());});}return true;}
 private void savePcm(byte[] pcm)throws Exception{byte[] wav=StudioProtocol.wav(pcm);String name="take_"+new SimpleDateFormat("yyyyMMdd_HHmmss_SSS",Locale.ROOT).format(new Date())+".wav";File temp=new File(dir,name+".partial"),f=new File(dir,name);try{Files.write(temp.toPath(),wav);if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("已取消保存");Files.move(temp.toPath(),f.toPath(),StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(temp.toPath());}a.main.post(()->{recordMessage="真实 PCM 已校验并保存到手机";a.progressMessage=recordMessage;a.refresh();});}
 private void stop(){if(player!=null){player.release();player=null;}}void visible(boolean v){practice.visible(v);visible=v;if(!v)stop();}void close(){practice.close();closed=true;a.main.removeCallbacks(poll);stop();}
}
