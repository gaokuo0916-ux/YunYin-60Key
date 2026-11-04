package cn.fpga.score;
import android.content.*;
import android.content.res.Configuration;
import android.webkit.*;
import android.widget.*;
import org.json.*;
import java.util.*;
/** Bundled, trusted interface. Downloads, storage and BLE remain native. */
final class InstrumentScreen {
 final MainActivity a;final LinearLayout root;final WebView web;String page="perform";
 private Score renderedScore;private boolean loaded;private String last="";private final Map<String,Runnable> items=new HashMap<>();
 private final java.util.concurrent.ExecutorService catalogWorker=java.util.concurrent.Executors.newSingleThreadExecutor();private ExpandedCatalog expanded;private BundledMidiCatalog bundled;private volatile int catalogGeneration;private volatile boolean closed;
 static boolean dark(Context c){return(c.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES;}
 static int background(Context c){return dark(c)?0xff191e1c:0xfff7f6f2;}
 static int ink(Context c){return dark(c)?0xffe7ece6:0xff263830;}
 int dp(int n){return Math.round(n*a.getResources().getDisplayMetrics().density);}
 InstrumentScreen(MainActivity host){
  a=host;root=new LinearLayout(a);root.setOrientation(1);web=new WebView(a);web.setBackgroundColor(background(a));
  WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(false);s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setBlockNetworkLoads(true);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
  web.addJavascriptInterface(new Bridge(),"YunYin");
  web.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest request){return true;}
   @Override public void onPageFinished(WebView v,String url){if(url.equals("https://app.yunyin.local/studio")){loaded=true;update();}}
  });root.addView(web,new LinearLayout.LayoutParams(-1,-1));
  try(java.io.InputStream in=a.getAssets().open("studio.html");java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream()){
   byte[] b=new byte[4096];int n;while((n=in.read(b))!=-1)out.write(b,0,n);web.loadDataWithBaseURL("https://app.yunyin.local/studio",out.toString("UTF-8"),"text/html","UTF-8",null);
  }catch(Exception e){a.showError(e);}
 }
 void render(){last="";update();}void close(){closed=true;catalogGeneration++;catalogWorker.submit(()->{if(expanded!=null)expanded.close();});catalogWorker.shutdown();web.removeJavascriptInterface("YunYin");web.destroy();}
 void searchLibrary(String query){searchLibrary(query,"all");}
 void searchLibrary(String query,String category){page="library";render();web.evaluateJavascript("window.YY&&window.YY.search("+JSONObject.quote(query)+","+JSONObject.quote(category)+")",null);}
 void update(){if(!loaded)return;try{
  JSONObject j=new JSONObject();j.put("page",page);j.put("title",a.scoreName.split(" · ",2)[0]);j.put("artist",a.scoreName.contains(" · ")?a.scoreName.split(" · ",2)[1]:"七键旋律曲谱");
  j.put("ready",a.ready());j.put("busy",a.busy);j.put("uploaded",a.uploaded);j.put("playing",a.playing);j.put("paused",a.paused);j.put("free",a.free);j.put("percent",a.percent);j.put("message",a.progressMessage);j.put("connection",a.connectionState);j.put("logs",a.logs());
  j.put("nativePitch",a.score!=null&&a.score.nativePitch);j.put("bpm",a.score==null?120:a.score.bpm);j.put("count",a.score==null?0:a.score.count());if(renderedScore!=a.score){JSONArray notes=new JSONArray();if(a.score!=null)for(int n=0;n<a.score.count();n++)notes.put(new JSONArray(new int[]{a.score.degree(n),a.score.units(n)}));j.put("notes",notes);renderedScore=a.score;}
  if(a.studio!=null)a.studio.describe(j);String json=j.toString();if(json.equals(last))return;last=json;web.evaluateJavascript("window.YY&&window.YY.update("+json+")",null);
 }catch(Exception e){a.showError(e);}}
 private static final class Row{
  final String id,title,subtitle;final boolean local;final Runnable select;
  Row(String i,String t,String s,boolean l,Runnable action){id=i;title=t;subtitle=s;local=l;select=action;}
 }
 private void library(String category,String input,int requested,int request){
  if(closed||a.features==null)return;final String query=input.substring(0,Math.min(120,input.length()));final int ticket=++catalogGeneration;
  catalogWorker.submit(()->{if(closed||ticket!=catalogGeneration)return;try{
   List<Row> small=new ArrayList<>();boolean all=category.equals("all");
   if(all||category.equals("mine"))for(OriginalScoreStore.Entry e:a.features.originalEntries())if(OpenCatalog.normalize(e.title+" "+e.origin).contains(OpenCatalog.normalize(query)))small.add(new Row("o:"+e.id,e.title,e.notes+" 个音符 · "+e.tracks+" 个声部 · 完整原谱",true,()->a.features.original(e)));
   if(all||category.equals("mine"))for(LibraryStore.Entry e:a.features.entries())if(OpenCatalog.normalize(e.title+" "+e.origin).contains(OpenCatalog.normalize(query)))small.add(new Row("m:"+e.id,e.title,e.score.count()+" 个事件 · 我的",true,()->a.features.select(e)));
   if(all||category.equals("chinese")||category.equals("bundled")){
    if(bundled==null)bundled=BundledMidiCatalog.read(a.getAssets().open("bundled_midi/catalog.tsv"));
    final BundledMidiCatalog source=bundled;
    for(BundledMidiCatalog.Item e:source.search(query,category.equals("chinese")))small.add(new Row("b:"+e.id,e.title,(BundledMidiCatalog.featured(e.id)?"精选练习":e.chinese?"华语筛选":"离线曲库")+" · 完整 MIDI 原谱",true,()->a.features.bundled(source,e)));
   }
   if(all||category.equals("pop"))for(PopCatalog.Item e:PopCatalog.search(a.popItems,query))small.add(new Row("p:"+e.id,e.title,e.artist+" · POP909"+(a.features.cached(e)?" · 已缓存":""),false,()->a.features.pop(e)));
   if(all||category.equals("classical"))for(OnlineCatalog.Item e:OnlineCatalog.search(a.classicalItems,query))small.add(new Row("c:"+a.classicalItems.indexOf(e),e.title,"MuseTrainer · MusicXML",false,()->a.features.classical(e)));
   if(all||category.equals("open"))for(OpenCatalog.Item e:OpenCatalog.search(a.openItems,query))small.add(new Row("w:"+e.id,e.title,e.artist+" · Commons · "+e.license,false,()->a.features.open(e)));
   boolean useExpanded=all||category.equals("expanded");int extra=0;
   if(useExpanded){if(expanded==null)expanded=new ExpandedCatalog(a);extra=expanded.search(query,"all",1,0).total;}
   CatalogPager pager=new CatalogPager(small.size()+extra,requested);List<Row> visible=new ArrayList<>();
   for(int i=pager.from;i<Math.min(pager.to,small.size());i++)visible.add(small.get(i));
   if(useExpanded&&pager.to>small.size())for(ExpandedCatalog.Item e:expanded.search(query,"all",pager.to-Math.max(pager.from,small.size()),Math.max(0,pager.from-small.size())).items)
    visible.add(new Row("x:"+e.id,e.title,e.artist+" · "+e.source+" · "+e.license,false,()->a.features.expandedSelection(e)));
   JSONArray result=new JSONArray();Map<String,Runnable> actions=new HashMap<>();
   for(Row row:visible){result.put(new JSONObject().put("id",row.id).put("title",row.title).put("subtitle",row.subtitle).put("local",row.local));actions.put(row.id,row.select);}
   String script="window.YY.library("+result+","+pager.total+","+JSONObject.quote(category)+","+JSONObject.quote(query)+","+pager.page+","+request+")";
   a.main.post(()->{if(closed||ticket!=catalogGeneration)return;items.clear();items.putAll(actions);web.evaluateJavascript(script,null);});
  }catch(Exception e){a.main.post(()->{if(!closed&&ticket==catalogGeneration){web.evaluateJavascript("window.YY.libraryError("+request+","+JSONObject.quote(e.getMessage())+")",null);a.showError(e);}});}});
 }
 final class Bridge{
  @JavascriptInterface public void action(String name,String payload){a.main.post(()->{
   if(name==null||name.length()>30||payload==null||payload.length()>1024)return;
   try{
    if(Arrays.asList("page","select","primary","apply-map","challenge-play").contains(name))
     web.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
    if(name.equals("page")){if(Arrays.asList("perform","challenge","library","device","takes").contains(payload)){page=payload;a.applyBars();update();}return;}
    if(name.equals("list")){JSONObject p=new JSONObject(payload);library(p.optString("category","mine"),p.optString("query",""),p.optInt("page",0),p.optInt("request",0));return;}
    if(name.equals("cancel")){a.cancel();return;}
    if(a.busy){Toast.makeText(a,"请等待当前传输完成",Toast.LENGTH_SHORT).show();return;}
    switch(name){case "connect":a.connectionMenu();break;case "primary":a.primary();break;case "stop":a.control("STOP");break;case "free":a.mode(Boolean.parseBoolean(payload));break;case "import":a.importMenu();break;
     case "select":Runnable r=items.get(payload);if(r!=null)r.run();break;case "expanded":a.features.expanded();break;case "search":a.features.webSearch(payload);break;case "free-midi":a.features.freeMidi(payload);break;case "free-sources":a.features.webSearch(payload);break;case "score-pop":a.features.midishow("","newest");break;case "midishow-search":a.features.midishow(payload,"relevance");break;case "midishow-help":a.features.midishowHelp();break;case "score-global":a.features.browse("https://musescore.com/sheetmusic");break;case "score-link":a.features.linkDialog("");break;case "score-sources":a.features.sources();break;case "review":a.features.saveCurrent(a.score,a.scoreName);break;case "manage":a.features.library();break;case "tempo":a.changeTempo(Integer.parseInt(payload));break;default:if(a.studio!=null)a.studio.action(name,payload);}
   }catch(Exception e){a.showError(e);}
  });}
 }
}
