package cn.fpga.score;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.net.Uri;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.*;

/** Phone library, real online catalog, MusicXML conversion, and image-review flow. */
@SuppressWarnings("deprecation")
public final class FeaturePanel {
    public interface Host { void chosen(Score score,String name); }
    private final Activity activity;private final Host host;private final LibraryStore library;private final OriginalScoreStore originals;private OriginalScore exportingOriginal;
    private final Handler main=new Handler(Looper.getMainLooper());private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private Future<?> pending;private ProgressDialog progress;private int generation;private Score exporting;private ExpandedLibrary expanded;private FreeMidiLibrary freeMidi;
    public FeaturePanel(Activity context,Host receiver)throws IOException{activity=context;host=receiver;library=new LibraryStore(new File(context.getFilesDir(),"scores_v2"));originals=new OriginalScoreStore(new File(context.getFilesDir(),"original_scores_v1"));}
    private void choose(LibraryStore.Entry entry){activity.getSharedPreferences("library",0).edit().putString("last",entry.id).apply();host.chosen(entry.score,entry.title);}
    public boolean restore(){List<LibraryStore.Entry> entries=library.list();if(entries.isEmpty())return false;
        String id=activity.getSharedPreferences("library",0).getString("last","");for(LibraryStore.Entry e:entries)if(e.id.equals(id)){choose(e);return true;}choose(entries.get(0));return true;}
    private int dp(int n){return Math.round(n*activity.getResources().getDisplayMetrics().density);}
    private LinearLayout column(){LinearLayout box=new LinearLayout(activity);box.setOrientation(1);box.setPadding(dp(18),dp(8),dp(18),dp(8));return box;}
    private TextView text(String value){TextView t=new TextView(activity);t.setText(value);t.setTextSize(14);t.setTextColor(InstrumentScreen.ink(activity));t.setPadding(0,dp(6),0,dp(6));return t;}
    public List<LibraryStore.Entry> entries(){return library.list();}
    public List<OriginalScoreStore.Entry> originalEntries(){return originals.list();}
    public void original(OriginalScoreStore.Entry entry){background("读取完整原谱",()->originals.load(entry),document->originalReview(document,entry.title,entry.origin,entry));}
    private void originalReview(OriginalScore document,String suggested,String origin,OriginalScoreStore.Entry saved){
        originalReview(document,suggested,origin,saved,0);
    }
    private void originalReview(OriginalScore document,String suggested,String origin,OriginalScoreStore.Entry saved,int suggestedVoice){
        LinearLayout box=column();EditText title=field("曲名",suggested);title.setEnabled(saved==null);box.addView(title);
        box.addView(text(document.noteCount+" 个音符 · "+document.parsed.tracks.size()+" 个声部 · 完整原谱"));
        box.addView(text("保留升降音、八度、所有声部和原文件，不改成七键谱。下方声部选择只用于查看，不会删掉其他声部。"));
        box.addView(text("点“导入乐器”上传下方所选声部，保留升降音和八度。60键配套固件默认C2～B6，包含升降音；超出当前音区会提示缺键，可在琴屏或手机手动跳过。试用版逐音练习，同时音也依次提示，不评价持键时长；原文件及其他声部仍完整保留。上传后存于琴端RAM；在乐器页另存到TF并确认校验成功后可断电恢复。"));
        Spinner voices=new Spinner(activity);String[] labels=new String[document.parsed.tracks.size()];for(int i=0;i<labels.length;i++)labels[i]=document.parsed.tracks.get(i).name+" · "+document.parsed.tracks.get(i).notes.size()+" 项";
        voices.setAdapter(new ArrayAdapter<>(activity,android.R.layout.simple_spinner_dropdown_item,labels));voices.setSelection(Math.max(0,Math.min(labels.length-1,suggestedVoice)));box.addView(voices);
        ListView preview=new ListView(activity);box.addView(preview,new LinearLayout.LayoutParams(-1,dp(210)));List<String> rows=new ArrayList<>();ArrayAdapter<String> adapter=new ArrayAdapter<>(activity,android.R.layout.simple_list_item_1,rows);preview.setAdapter(adapter);
        LinearLayout paging=new LinearLayout(activity);Button previous=new Button(activity),next=new Button(activity);previous.setText("上一页");next.setText("下一页");paging.addView(previous,new LinearLayout.LayoutParams(0,-2,1));paging.addView(next,new LinearLayout.LayoutParams(0,-2,1));box.addView(paging);TextView page=text("");box.addView(page);final int[] at={0};
        Runnable render=()->{List<MusicXmlImport.Note> notes=document.parsed.tracks.get(Math.max(0,voices.getSelectedItemPosition())).notes;int start=at[0]*64;rows.clear();for(int i=start;i<Math.min(start+64,notes.size());i++){MusicXmlImport.Note n=notes.get(i);rows.add((i+1)+". "+OriginalScore.pitch(n.pitch)+String.format(Locale.CHINA,"　起点 %.3f 拍 · 时长 %.3f 拍",n.at,n.duration));}adapter.notifyDataSetChanged();preview.setSelection(0);page.setText("第 "+(at[0]+1)+" / "+Math.max(1,(notes.size()+63)/64)+" 页");previous.setEnabled(at[0]>0);next.setEnabled(start+64<notes.size());};
        voices.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int index,long id){at[0]=0;render.run();}public void onNothingSelected(AdapterView<?> p){}});previous.setOnClickListener(v->{at[0]--;render.run();});next.setOnClickListener(v->{at[0]++;render.run();});
        ScrollView scroll=new ScrollView(activity);scroll.addView(box);AlertDialog.Builder builder=new AlertDialog.Builder(activity).setTitle(saved==null?"保存完整原谱":"已保存的完整原谱").setView(scroll).setPositiveButton(saved==null?"保存原谱":"关闭",null);
        if(saved==null)builder.setNegativeButton("取消",null);else builder.setNegativeButton("管理",(d,w)->manageOriginal(saved));
        Button exportOriginal=new Button(activity);exportOriginal.setText("导出原文件");box.addView(exportOriginal);exportOriginal.setOnClickListener(w->{
            exportingOriginal=document;Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/octet-stream").putExtra(Intent.EXTRA_TITLE,document.filename);activity.startActivityForResult(intent,209);
        });
        builder.setNeutralButton("导入乐器",null);
        AlertDialog dialog=builder.create();dialog.setOnShowListener(d->{render.run();if(saved==null)dialog.getButton(-1).setOnClickListener(v->{String label=title.getText().toString().trim();if(label.isEmpty()||label.length()>160){title.setError("曲名需为 1～160 个字符");return;}background("保存完整原谱",()->originals.save(null,label,origin,document),entry->{dialog.dismiss();Toast.makeText(activity,"完整原谱已存入“我的”，未改动任何音符",Toast.LENGTH_LONG).show();originalReview(document,entry.title,entry.origin,entry);});});dialog.getButton(-3).setOnClickListener(v->{
            String label=title.getText().toString().trim();if(label.isEmpty()||label.length()>160){title.setError("曲名需为1～160个字符");return;}
            int voice=voices.getSelectedItemPosition();
            background("准备原音高曲谱",()->{OriginalPractice plan=OriginalPractice.from(document,voice);if(saved==null)originals.save(null,label,origin,document);return plan;},plan->{
                dialog.dismiss();String name=label+" · "+document.parsed.tracks.get(voice).name;
                if(plan.parts.size()==1)host.chosen(plan.parts.get(0),name);
                else{String[] parts=new String[plan.parts.size()];for(int i=0;i<parts.length;i++)parts[i]="第"+(i+1)+"段 · "+plan.parts.get(i).count()+"个音符/休止事件";
                    new AlertDialog.Builder(activity).setTitle("选择上传段落，原谱完整保留").setItems(parts,(x,index)->host.chosen(plan.parts.get(index),name+" · 第"+(index+1)+"段")).setNegativeButton("取消",null).show();}
            });
        });});dialog.show();
    }
    public void trialScore()throws Exception{
        String xml="<score-partwise><movement-title>原音高上传检查</movement-title><part id='P1'><measure number='1'><attributes><divisions>4</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note><note><pitch><step>C</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration></note><note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration></note><note><pitch><step>D</step><octave>4</octave></pitch><duration>4</duration></note></measure></part></score-partwise>";
        originalReview(OriginalScore.read(xml.getBytes(StandardCharsets.UTF_8),"原音高上传检查.musicxml"),"原音高上传检查","内置功能检查",null);
    }
    private void manageOriginal(OriginalScoreStore.Entry entry){
        new AlertDialog.Builder(activity).setTitle(entry.title).setItems(new String[]{"查看完整原谱 / 导出","重命名","删除"},(d,n)->{
            if(n==0)original(entry);
            if(n==1){EditText title=field("曲名",entry.title);AlertDialog rename=new AlertDialog.Builder(activity).setTitle("重命名原谱").setView(title).setNegativeButton("取消",null).setPositiveButton("保存",null).create();rename.setOnShowListener(x->rename.getButton(-1).setOnClickListener(v->{String name=title.getText().toString().trim();if(name.isEmpty()||name.length()>160){title.setError("曲名需为 1～160 个字符");return;}background("重命名",()->originals.save(entry.id,name,entry.origin,originals.load(entry)),value->{rename.dismiss();original(value);});}));rename.show();}
            if(n==2)new AlertDialog.Builder(activity).setTitle("删除这份原谱？").setMessage(entry.title).setNegativeButton("保留",null).setPositiveButton("删除",(x,y)->{try{originals.delete(entry.id);library();}catch(Exception e){error(e);}}).show();
        }).setNegativeButton("关闭",null).show();
    }
    public void expanded(){if(expanded!=null)expanded.close();expanded=new ExpandedLibrary(activity,this::expandedItem);expanded.show();}
    private void expandedItem(ExpandedCatalog.Item item){
        background("下载 "+item.title,()->{
            File file=new File(activity.getCacheDir(),"expanded_"+item.id+".mid");byte[] data=null;
            if(file.isFile()&&file.length()<=8*1024*1024)try{data=Files.readAllBytes(file.toPath());ExpandedDownload.validate(data,item.md5);}catch(IOException ignored){data=null;}
            if(data==null){data=ExpandedDownload.download(item.path,item.md5);Files.write(file.toPath(),data);}
            return OriginalScore.read(data,item.title);
        },document->originalReview(document,item.title+" · "+item.artist,ExpandedDownload.url(item.path)+" / "+item.license,null));
    }
    public void webSearch(String query){
        final String q=query==null?"":query.trim();String[] sites={"免费华语 · 手机内置2,296份编配","免费全库 · 手机内置18,775份MIDI","免费在线 · BitMidi（主要为外语/游戏）","免费在线 · midicn开放库（民歌/古典等）","免费华语选集 · POP909","其他网站（可能收费或需要积分）","粘贴曲谱文件链接"};
        new AlertDialog.Builder(activity).setTitle("免费搜谱 / 导入").setItems(sites,(d,n)->{if(n==0)searchLibrary(q,"chinese");else if(n==1)searchLibrary(q,"bundled");else if(n==2)freeMidi(q);else if(n==3)searchLibrary(q,"expanded");else if(n==4)searchLibrary(q,"pop");else if(n==5)otherSites(q);else linkDialog("");}).setNegativeButton("关闭",null).show();
    }
    private void otherSites(String q){
        String[] names={"MidiShow · 下载通常消耗积分","MuseScore · 部分下载需付费","简谱图片搜索"};
        new AlertDialog.Builder(activity).setTitle("其他网站 · 下载条件以原站为准").setItems(names,(d,n)->{if(n==0)midishow(q,"relevance");else if(n==1)browse("https://musescore.com/sheetmusic?text="+Uri.encode(q));else browse("https://www.bing.com/images/search?q="+Uri.encode(q+" 简谱"));}).setNegativeButton("返回免费搜谱",(d,n)->webSearch(q)).show();
    }
    public void freeMidi(String query){if(freeMidi!=null)freeMidi.close();freeMidi=new FreeMidiLibrary(activity,item->background("免费读取 "+item.title,()->FreeMidiSource.download(item),document->originalReview(document,item.title,item.page,null)));freeMidi.show(query);}
    public void searchLibrary(String query){searchLibrary(query,"all");}
    public void searchLibrary(String query,String category){if(activity instanceof MainActivity){MainActivity a=(MainActivity)activity;if(a.screen!=null)a.screen.searchLibrary(query,category);}}
    public void midishow(String query,String order){try{activity.startActivityForResult(new Intent(activity,ScoreBrowserActivity.class).putExtra("url",MidiShowSource.search(query,order)).putExtra("provider","midishow").putExtra("query",query).putExtra("order",order),203);}catch(Exception e){error(e);}}
    public void midishowHelp(){new AlertDialog.Builder(activity).setTitle("MidiShow 搜谱与下载").setMessage("输入华语歌名或歌手搜索，也支持外语。进入网站曲谱详情后，按网站提示登录并下载 MIDI；可能消耗站内积分，以网站页面为准。下载校验成功后，回到云音保存完整原谱，保留升降音、八度和全部声部。使用配套FS可导入选定声部的原音高，缺键时手动跳过。\n\n流行分类包含华语和外语，不是纯华语目录。网站无法打开时，可用系统浏览器下载，再从云音导入文件。").setNegativeButton("关闭",null).setPositiveButton("打开 MidiShow",(d,w)->midishow("","newest")).show();}
    public void browse(String url){try{activity.startActivityForResult(new Intent(activity,ScoreBrowserActivity.class).putExtra("url",ScoreWebImport.normalize(url)),203);}catch(Exception e){error(e);}}
    public void linkDialog(String initial){
        EditText value=field("HTTPS 文件链接或曲谱网页",initial);value.setSingleLine(false);value.setMaxLines(4);
        LinearLayout box=column();box.addView(text("文件链接会读取 MIDI、MusicXML、数字简谱或图片；普通网页进入搜谱浏览器，再点击文件下载。"));box.addView(value);
        AlertDialog dialog=new AlertDialog.Builder(activity).setTitle("从链接导入曲谱").setView(box).setNegativeButton("取消",null).setPositiveButton("打开",null).create();
        dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{try{String url=ScoreWebImport.extractUrl(value.getText().toString());if(url==null)throw new IOException("请粘贴 HTTPS 链接");dialog.dismiss();openLink(url);}catch(Exception e){value.setError(e.getMessage());}}));dialog.show();
    }
    public void sharedText(String value)throws Exception{
        String url=ScoreWebImport.extractUrl(value);
        if(url==null){paste(value);return;}
        String title=SongShare.title(value);
        if(SongShare.musicLink(url)){
            EditText query=field("输入歌曲名",title);LinearLayout box=column();box.addView(text("音乐分享链接用于查找同名曲谱；不会把原唱音频当作音符。"));box.addView(query);
            new AlertDialog.Builder(activity).setTitle("按歌曲找谱").setView(box).setNegativeButton("取消",null).setPositiveButton("搜索 MidiShow",(d,w)->midishow(query.getText().toString().trim(),"relevance")).show();return;
        }
        linkDialog(url);
    }
    public void openLink(String url){if(ScoreWebImport.fileLink(url))downloadLink(url,null,null);else browse(url);}
    private void downloadLink(String url,String agent,String referer){
        String cookie=android.webkit.CookieManager.getInstance().getCookie(url);
        background("读取网上曲谱",()->ScoreWebImport.fetch(url,agent,cookie,referer),file->{
            if(file.kind==ScoreWebImport.Kind.PAGE){browse(file.url);Toast.makeText(activity,"这是网页，请在页面点击曲谱文件下载",Toast.LENGTH_LONG).show();}
            else importBytes(file.data,file.name,file.url);
        });
    }
    public void open(OpenCatalog.Item item){
        background("下载 "+item.title,()->{
            ScoreWebImport.Download file=ScoreWebImport.fetch(item.url,null,null,null);
            StringBuilder digest=new StringBuilder();for(byte b:java.security.MessageDigest.getInstance("SHA-1").digest(file.data))digest.append(String.format(Locale.ROOT,"%02x",b&255));
            if(!digest.toString().equalsIgnoreCase(item.sha1))throw new IOException("文件与曲库索引校验不符，请从原始页面核对");
            return OriginalScore.read(file.data,item.title);
        },document->originalReview(document,item.title,item.artist+" / "+item.page+" / "+item.license+" / "+item.licenseUrl,null));
    }
    public void expandedSelection(ExpandedCatalog.Item item){expandedItem(item);}
    public void sources(){
        int open=activity instanceof MainActivity?((MainActivity)activity).openItems.size():0;
        new AlertDialog.Builder(activity).setTitle("曲谱来源").setMessage("本版离线整库：MeowField MIDI Library，实际收录 18,775 份 MIDI；所有原谱均可保留完整音高、八度及各声部，不再强制转为七键。按歌名和歌手筛出的华语有 2,296 份编配；不是歌曲去重数，也不是全华语曲库。另有 422 份解析失败，未加入可用目录。\nhttps://github.com/Tsundeer/MeowField_MidiLibrary\n\n免费搜谱：优先搜索手机内置华语、离线整库、POP909及midicn开放目录。新增BitMidi原生搜索和公开MIDI直读，不需要登录、积分或订阅；站点标称113,229份，主要为外语、游戏和较早曲目，不能当作华语歌数量，也未整库内置。https://bitmidi.com/\n\n其他网站：MidiShow下载通常消耗积分，MuseScore部分下载需付费；保留为次要入口，不列作免费直读来源。\nhttps://www.midishow.com/\nhttps://musescore.com/\n\nApp 已接入目录：\n华语选集：POP909，909 首，主要是既有曲目，不代表最新流行榜。\nhttps://github.com/music-x-lab/POP909-Dataset\n\n古典：MuseTrainer，69 份 MusicXML。\nhttps://musetrainer.github.io/library/\n\n扩展：midicn-lib v1.23，筛选后 95,923 份 MIDI 版本。\nhttps://github.com/midicn/midi-library\n\n开放：Wikimedia Commons，本版 "+open+" 份去重 MIDI，保留作者、原始页面及逐曲许可。\nhttps://commons.wikimedia.org/\n\n目录包含不同编配和片段，不能等同于歌曲数量。取得 MIDI / MusicXML 后可直接保存完整原谱，不要求转为七键；简谱图片可识别后校对。播放器和原唱音频不能直接作为跟弹谱。").setPositiveButton("知道了",null).show();
    }
    public void paste(String source){String normalized=SongDraft.importText(source,120);SongDraft.parse(normalized);review("手动简谱",normalized,"手机手动输入",null,Collections.emptyList(),null,false);}
    public void select(LibraryStore.Entry entry){choose(entry);}
    public void bundled(BundledMidiCatalog catalog,BundledMidiCatalog.Item item){
        background("载入完整原谱",()->{
            File file=catalog.install(activity.getAssets().open("bundled_midi/files.zip"),new File(activity.getCacheDir(),"bundled_midi"));
            return OriginalScore.read(catalog.midi(file,item),item.title);
        },document->originalReview(document,item.song,item.source(),null,BundledMidiCatalog.featured(item.id)?item.track:0));
    }
    public void edit(LibraryStore.Entry entry){manage(entry);}
    public boolean cached(PopCatalog.Item item){return new File(activity.getCacheDir(),"pop909_"+item.id+".mid").isFile();}
    public void pop(PopCatalog.Item item){
        background("读取 "+item.title,()->{
            File file=new File(activity.getCacheDir(),"pop909_"+item.id+".mid");byte[] data=null;
            if(file.isFile()&&file.length()<=8*1024*1024)try{data=Files.readAllBytes(file.toPath());MidiImport.read(data);}catch(Exception ignored){data=null;}
            if(data==null){data=PopCatalog.download(item);File temp=new File(activity.getCacheDir(),"pop909_"+item.id+".tmp");Files.write(temp.toPath(),data);Files.move(temp.toPath(),file.toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);}
            return OriginalScore.read(data,item.title);
        },document->originalReview(document,item.title+" · "+item.artist,item.url(),null));
    }
    public void classical(OnlineCatalog.Item item){background("下载 "+item.title,()->OnlineCatalog.download(item.url,8*1024*1024),data->originalReview(OriginalScore.read(data,item.title),item.title,item.url,null));}
    private EditText field(String hint,String value){EditText t=new EditText(activity);t.setHint(hint);t.setText(value);t.setTextSize(14);return t;}
    private void error(Throwable e){if(!activity.isFinishing())new AlertDialog.Builder(activity).setTitle("暂未完成").setMessage(e.getMessage()==null?e.toString():e.getMessage()).setPositiveButton("知道了",null).show();}
    private interface Load<T>{T get()throws Exception;}
    private interface Use<T>{void use(T value)throws Exception;}
    private <T> void background(String title,Load<T> load,Use<T> use){
        int ticket=++generation;if(pending!=null)pending.cancel(true);
        progress=ProgressDialog.show(activity,title,"请稍候…",true,true);final ProgressDialog dialog=progress;
        dialog.setOnCancelListener(d->{generation++;if(pending!=null)pending.cancel(true);});
        pending=worker.submit(()->{try{T result=load.get();main.post(()->{if(ticket!=generation || activity.isFinishing())return;dialog.dismiss();try{use.use(result);}catch(Exception e){error(e);}});}
            catch(Exception e){main.post(()->{if(ticket==generation && !activity.isFinishing()){dialog.dismiss();error(e);}});}});
    }
    public void saveCurrent(Score score,String name){
        if(score!=null&&score.nativePitch){new AlertDialog.Builder(activity).setTitle("完整原谱已保留").setMessage("当前为原音高逐音跟弹曲谱。请到曲库→我的打开原谱，可重新选声部、导出或再次导入乐器。").setPositiveButton("知道了",null).show();return;}if(score!=null)review(name,score.source(),"手机导入/编辑",null,Collections.emptyList(),null,false);}
    public void image(){activity.startActivityForResult(new Intent(activity,ImageImportActivity.class),201);}
    public boolean onActivityResult(int request,int result,Intent data){
        if(request==209){OriginalScore document=exportingOriginal;exportingOriginal=null;if(result==Activity.RESULT_OK&&data!=null&&data.getData()!=null&&document!=null){Uri uri=data.getData();background("导出完整原谱",()->{try(OutputStream out=activity.getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException("无法写入文件");out.write(document.bytes());}return true;},v->Toast.makeText(activity,"原文件已完整导出",Toast.LENGTH_LONG).show());}return true;}
        if(request==203){if(result==Activity.RESULT_OK&&data!=null){String path=data.getStringExtra("staged_path");if(path!=null){String name=data.getStringExtra("name"),origin=data.getStringExtra("origin");background("载入已下载曲谱",()->WebScoreStage.take(activity.getCacheDir(),path),bytes->importBytes(bytes,name==null?"网上曲谱":name,origin==null?"网上曲谱":origin));}else{String url=data.getStringExtra("url");if(url!=null)downloadLink(url,data.getStringExtra("agent"),data.getStringExtra("referer"));}}return true;}
        if(request==201){if(result==Activity.RESULT_OK && data!=null){
            String source=data.getStringExtra("source"),path=data.getStringExtra("preview");Bitmap preview=null;
            if(path!=null && !path.isEmpty() && path.equals(new File(activity.getCacheDir(),"score_image_review.png").getAbsolutePath())){
                BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=2;preview=BitmapFactory.decodeFile(path,options);}
            review("图片识谱 "+new java.text.SimpleDateFormat("MM-dd HH:mm",Locale.CHINA).format(new Date()),source,"图片识谱（逐行框选后已人工校对）",preview,
                Arrays.asList("识谱为辅助结果，仍请核对；高低八度合并，连音及反复需按实际谱面整理"),null,true);
        }return true;}
        if(request==202){if(result==Activity.RESULT_OK && data!=null && data.getData()!=null && exporting!=null){
            Uri uri=data.getData();Score value=exporting;exporting=null;
            background("导出曲谱",()->{try(OutputStream out=activity.getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException("无法写入导出文件");out.write(value.protocol().getBytes(StandardCharsets.UTF_8));}return true;},v->Toast.makeText(activity,"曲谱已导出",Toast.LENGTH_LONG).show());
        }return true;}return false;
    }
    public void importFile(Uri uri,String name){
        background("读取曲谱",()->{try(InputStream in=activity.getContentResolver().openInputStream(uri)){return bytes(in,8*1024*1024);}},data->{
            importBytes(data,name,"本地文件："+name);
        });
    }
    private void importBytes(byte[] data,String name,String origin)throws Exception{
        ScoreWebImport.Kind kind=ScoreWebImport.classify(data,null,name);
        if(kind==ScoreWebImport.Kind.MIDI||kind==ScoreWebImport.Kind.XML||kind==ScoreWebImport.Kind.MXL)background("读取完整原谱",()->OriginalScore.read(data,name),document->originalReview(document,name,origin,null));
        else if(kind==ScoreWebImport.Kind.IMAGE){File image=new File(activity.getCacheDir(),"score_import_image");Files.write(image.toPath(),data);activity.startActivityForResult(new Intent(activity,ImageImportActivity.class).putExtra("image_path",image.getAbsolutePath()),201);}
        else if(kind==ScoreWebImport.Kind.PAGE)throw new IOException("这是网页文件，请使用“从链接导入”打开原网页，再选择曲谱文件");
        else{String value=SongDraft.importText(new String(data,StandardCharsets.UTF_8),120);review(name,value,origin,null,Collections.emptyList(),null,false);}
    }
    private static byte[] bytes(InputStream input,int max)throws IOException{
        if(input==null)throw new IOException("无法读取文件");ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;
        while((n=input.read(b))!=-1){if(out.size()+n>max)throw new IOException("文件超过大小上限");out.write(b,0,n);}return out.toByteArray();
    }
    private void review(String name,String source,String origin,Bitmap picture,List<String> notices,LibraryStore.Entry replacing,boolean verified){
        LinearLayout box=column();EditText title=field("曲名",name);box.addView(title);
        if(picture!=null){ImageView view=new ImageView(activity);view.setImageBitmap(picture);view.setAdjustViewBounds(true);view.setScaleType(ImageView.ScaleType.FIT_CENTER);box.addView(view,new LinearLayout.LayoutParams(-1,dp(170)));}
        String intro="每行：音符,时值。0=休止；4=一拍，2=半拍，1=四分之一拍，8=两拍。8192 版固件可整谱上传；超过 8192 才分段。";
        if(!notices.isEmpty())intro+="\n• "+String.join("\n• ",notices);box.addView(text(intro));
        EditText content=field("BPM=120，每行 音符,时值",source);content.setMinLines(5);content.setMaxLines(10);content.setGravity(Gravity.TOP);content.setTypeface(android.graphics.Typeface.MONOSPACE);box.addView(content);
        CheckBox checked=new CheckBox(activity);checked.setText("已核对音符、时值和七键改编结果");checked.setChecked(verified);box.addView(checked);
        ScrollView scroll=new ScrollView(activity);scroll.addView(box);
        AlertDialog dialog=new AlertDialog.Builder(activity).setTitle("确认后保存到曲库").setView(scroll).setNegativeButton("取消",null).setPositiveButton("保存并使用",null).create();
        dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{try{
            if(!checked.isChecked())throw new IOException("请先核对，再勾选确认");
            SongDraft draft=SongDraft.parse(content.getText().toString());List<Score> segments=draft.segments();String base=title.getText().toString().trim();
            if(base.isEmpty() || base.length()>140)throw new IOException("曲名需为 1～140 个字符");
            Runnable save=()->{try{
                LibraryStore.Entry first=null;
                for(int i=0;i<segments.size();i++){
                    String label=base+(segments.size()==1?"":" · 第"+(i+1)+"/"+segments.size()+"段");
                    LibraryStore.Entry saved=library.save(replacing!=null && segments.size()==1?replacing.id:null,label,origin,segments.get(i));if(first==null)first=saved;
                }
                dialog.dismiss();choose(first);
                Toast.makeText(activity,"已存入手机曲库"+(segments.size()==1?"":"，共 "+segments.size()+" 段，当前选中第一段"),Toast.LENGTH_LONG).show();
            }catch(Exception e){error(e);}};
            if(segments.size()>1)new AlertDialog.Builder(activity).setTitle("长曲谱分段").setMessage("共 "+draft.notes.size()+" 个事件，将保存为 "+segments.size()+" 段。每次上传一段，跟弹完成后从曲库选择下一段。").setNegativeButton("返回修改",null).setPositiveButton("分段保存",(x,y)->save.run()).show();else save.run();
        }catch(Exception e){content.setError(e.getMessage());}}));dialog.show();
    }
    public void library(){
        List<LibraryStore.Entry> all=library.list();List<OriginalScoreStore.Entry> original=originals.list();
        if(all.isEmpty()&&original.isEmpty()){new AlertDialog.Builder(activity).setTitle("我的曲库").setMessage("还没有保存曲谱。MIDI / MusicXML 可以直接保存完整原谱，无需先转成七键。").setPositiveButton("知道了",null).show();return;}
        LinearLayout box=column();EditText query=field("搜索曲名","");box.addView(query);ListView list=new ListView(activity);box.addView(list,new LinearLayout.LayoutParams(-1,dp(340)));
        List<Object> shown=new ArrayList<>();List<String> rows=new ArrayList<>();ArrayAdapter<String> adapter=new ArrayAdapter<>(activity,android.R.layout.simple_list_item_1,rows);list.setAdapter(adapter);
        Runnable filter=()->{shown.clear();rows.clear();String q=query.getText().toString().trim().toLowerCase(Locale.ROOT);
            for(OriginalScoreStore.Entry e:original)if(e.title.toLowerCase(Locale.ROOT).contains(q)){shown.add(e);rows.add(e.title+"\n完整原谱 · "+e.notes+" 个音符 · "+e.tracks+" 个声部");}
            for(LibraryStore.Entry e:all)if(e.title.toLowerCase(Locale.ROOT).contains(q)){shown.add(e);rows.add(e.title+"\n"+e.score.count()+" 个事件 · 既有跟弹谱");}adapter.notifyDataSetChanged();};
        query.addTextChangedListener(watcher(filter));filter.run();
        AlertDialog dialog=new AlertDialog.Builder(activity).setTitle("我的曲库 · 长按管理 / 导出").setView(box).setNegativeButton("关闭",null).create();
        list.setOnItemClickListener((p,v,index,id)->{Object e=shown.get(index);dialog.dismiss();if(e instanceof OriginalScoreStore.Entry)original((OriginalScoreStore.Entry)e);else choose((LibraryStore.Entry)e);});
        list.setOnItemLongClickListener((p,v,index,id)->{Object e=shown.get(index);dialog.dismiss();if(e instanceof OriginalScoreStore.Entry)manageOriginal((OriginalScoreStore.Entry)e);else manage((LibraryStore.Entry)e);return true;});dialog.show();
    }
    private void manage(LibraryStore.Entry entry){
        new AlertDialog.Builder(activity).setTitle(entry.title).setMessage("来源："+entry.origin).setPositiveButton("编辑 / 改名",(d,w)->review(entry.title,entry.score.source(),entry.origin,null,Collections.emptyList(),entry,false))
            .setNeutralButton("导出文本",(d,w)->{exporting=entry.score;Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT);intent.addCategory(Intent.CATEGORY_OPENABLE);intent.setType("text/plain");intent.putExtra(Intent.EXTRA_TITLE,entry.title.replaceAll("[\\\\/:*?\"<>|]","_")+".bt.txt");activity.startActivityForResult(intent,202);})
            .setNegativeButton("删除",(d,w)->new AlertDialog.Builder(activity).setTitle("删除此曲谱？").setMessage(entry.title).setNegativeButton("保留",null).setPositiveButton("删除",(x,y)->{try{library.delete(entry.id);library();}catch(Exception e){error(e);}}).show()).show();
    }
    public void online(){
        background("连接在线曲库",()->{
            File cache=new File(activity.getCacheDir(),"online_catalog.html");String html;String state="已联网刷新目录";
            try{html=OnlineCatalog.indexText(OnlineCatalog.download(OnlineCatalog.INDEX,1024*1024));OnlineCatalog.parse(html);Files.write(cache.toPath(),html.getBytes(StandardCharsets.UTF_8));}
            catch(IOException e){state="联网未成功，显示缓存目录；下载曲谱仍需网络";
                if(cache.exists())html=new String(Files.readAllBytes(cache.toPath()),StandardCharsets.UTF_8);
                else try(InputStream in=activity.getAssets().open("online_catalog.html")){html=new String(bytes(in,1024*1024),StandardCharsets.UTF_8);}}
            return new Object[]{OnlineCatalog.parse(html),state};
        },result->{@SuppressWarnings("unchecked")List<OnlineCatalog.Item> items=(List<OnlineCatalog.Item>)result[0];catalog(items,(String)result[1]);});
    }
    private void catalog(List<OnlineCatalog.Item> all,String state){
        LinearLayout box=column();box.addView(text(state+"\n来源：MuseTrainer 公开 MusicXML 曲库。搜索范围为当前接入曲库，主要是古典曲；可试“卡农”“致爱丽丝”“生日快乐”。"));
        EditText query=field("输入曲名或英文关键词","");box.addView(query);ListView list=new ListView(activity);box.addView(list,new LinearLayout.LayoutParams(-1,dp(300)));
        List<OnlineCatalog.Item> shown=new ArrayList<>();List<String> rows=new ArrayList<>();ArrayAdapter<String> adapter=new ArrayAdapter<>(activity,android.R.layout.simple_list_item_1,rows);list.setAdapter(adapter);
        Runnable filter=()->{shown.clear();shown.addAll(OnlineCatalog.search(all,query.getText().toString()));rows.clear();for(OnlineCatalog.Item item:shown)rows.add(item.title+"\nMusicXML · 下载后选择旋律声部");if(rows.isEmpty())rows.add("当前曲库没有匹配结果，可用网页搜谱或导入自己的图片/文件");adapter.notifyDataSetChanged();};query.addTextChangedListener(watcher(filter));filter.run();
        AlertDialog dialog=new AlertDialog.Builder(activity).setTitle("联网搜索曲谱 · "+all.size()+" 个版本").setView(box).setNegativeButton("关闭",null)
            .setNeutralButton("网页搜谱",(d,w)->{String q=query.getText().toString().trim();activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://www.bing.com/images/search?q="+Uri.encode(q+" 简谱"))));})
            .setPositiveButton("刷新目录",(d,w)->online()).create();
        list.setOnItemClickListener((p,v,index,id)->{if(index>=shown.size())return;OnlineCatalog.Item chosen=shown.get(index);dialog.dismiss();
            background("下载 "+chosen.title,()->OnlineCatalog.download(chosen.url,8*1024*1024),data->originalReview(OriginalScore.read(data,chosen.title),chosen.title,chosen.url,null));});dialog.show();
    }
    private static TextWatcher watcher(Runnable action){return new TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){}public void onTextChanged(CharSequence s,int start,int before,int count){action.run();}public void afterTextChanged(Editable e){}};}
    public void close(){generation++;if(pending!=null)pending.cancel(true);if(progress!=null)progress.dismiss();if(expanded!=null)expanded.close();if(freeMidi!=null)freeMidi.close();worker.shutdownNow();}
}
