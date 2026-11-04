package cn.fpga.score;
import android.app.*;
import android.content.*;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.*;
import android.text.InputFilter;
import android.view.inputmethod.*;
import android.webkit.*;
import android.widget.*;
import java.io.*;
import java.util.concurrent.*;
/** External sites never receive the trusted interface's JavaScript/native bridge. */
@SuppressWarnings("deprecation")
public final class ScoreBrowserActivity extends Activity {
 private WebView web;private TextView status;private EditText query;
 private boolean choosing,failedPage,midi;private volatile boolean closing;
 private String order="relevance",songPage="",songTitle="";
 private final Handler main=new Handler(Looper.getMainLooper());
 private final ExecutorService worker=Executors.newSingleThreadExecutor();
 private Future<?> pending;private ProgressDialog progress;private int generation;
 @Override public void onCreate(Bundle state){
  super.onCreate(state);String initial;
  try{initial=ScoreWebImport.normalize(getIntent().getStringExtra("url"));}catch(IOException e){finish();return;}
  midi="midishow".equals(getIntent().getStringExtra("provider"))||MidiShowSource.owns(initial);
  LinearLayout root=new LinearLayout(this);root.setOrientation(1);root.setBackgroundColor(InstrumentScreen.background(this));setContentView(root);
  root.setOnApplyWindowInsetsListener((v,i)->{v.setPadding(dp(8),i.getSystemWindowInsetTop(),dp(8),i.getSystemWindowInsetBottom());return i;});
  LinearLayout bar=new LinearLayout(this);root.addView(bar);
  button(bar,"返回",()->onBackPressed());button(bar,"刷新",()->{if(web!=null)web.reload();});button(bar,"系统浏览器",this::external);
  if(midi){
   String restored=state==null?getIntent().getStringExtra("query"):state.getString("query","");
   String selected=state==null?getIntent().getStringExtra("order"):state.getString("order","relevance");
   if("newest".equals(selected)||"popular".equals(selected))order=selected;
   LinearLayout search=new LinearLayout(this);root.addView(search);
   query=new EditText(this);query.setSingleLine(true);query.setTextSize(14);query.setHint("歌名、歌手（支持华语 / 外语）");query.setText(restored==null?"":restored);
   query.setFilters(new InputFilter[]{new InputFilter.LengthFilter(120)});query.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
   search.addView(query,new LinearLayout.LayoutParams(0,-2,3));button(search,"搜谱",this::search);
   query.setOnEditorActionListener((v,action,event)->{if(action==EditorInfo.IME_ACTION_SEARCH){search();return true;}return false;});
   LinearLayout options=new LinearLayout(this);root.addView(options);
   Spinner sort=new Spinner(this);String[] modes={"relevance","newest","popular"};
   sort.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,new String[]{"综合","最新","热门"}));
   int at="newest".equals(order)?1:"popular".equals(order)?2:0;sort.setSelection(at);
   options.addView(sort,new LinearLayout.LayoutParams(0,-2,1));
   sort.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){
    public void onItemSelected(android.widget.AdapterView<?> parent,android.view.View view,int position,long id){if(!order.equals(modes[position])){order=modes[position];search();}}
    public void onNothingSelected(android.widget.AdapterView<?> parent){}
   });
   button(options,"流行曲库",()->{query.setText("");search();});button(options,"登录",()->web.loadUrl(MidiShowSource.LOGIN));button(options,"说明",this::help);
  }else{
   LinearLayout tools=new LinearLayout(this);root.addView(tools);button(tools,"导入当前文件",()->offer(web.getUrl(),web.getTitle(),null));button(tools,"下载说明",this::help);
  }
  status=new TextView(this);status.setTextSize(12);status.setTextColor(InstrumentScreen.ink(this));status.setPadding(dp(4),dp(4),dp(4),dp(4));
  status.setText(midi?"MidiShow：搜索后进入歌曲页，按网站步骤下载 MIDI；有效文件会返回云音校对。":"点击曲谱文件下载，或长按简谱图片导入。");root.addView(status);
  web=new WebView(this);root.addView(web,new LinearLayout.LayoutParams(-1,0,1));
  WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setSupportMultipleWindows(false);
  web.setWebChromeClient(new WebChromeClient());
  web.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){
    if(!request.isForMainFrame())return false;String url=request.getUrl().toString();
    try{ScoreWebImport.normalize(url);}catch(IOException e){notice("此链接需要在网站或系统浏览器中处理");return true;}
    if("GET".equals(request.getMethod())&&ScoreWebImport.fileLink(url)){offer(url,"",null);return true;}return false;
   }
   @Override public void onPageStarted(WebView view,String url,Bitmap icon){failedPage=false;status.setText("正在打开 "+Uri.parse(url).getHost()+"…");}
   @Override public void onPageFinished(WebView view,String url){
    CookieManager.getInstance().flush();
    if(MidiShowSource.owns(url)&&Uri.parse(url).getPath()!=null&&Uri.parse(url).getPath().matches("/(?:en/|zh-tw/)?midi/[^/]+\\.html")){songPage=url;songTitle=view.getTitle();}
    if(!failedPage)status.setText("在网站点击曲谱文件下载；下载失败会留在本页。当前："+Uri.parse(url).getHost());
   }
   @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){if(request.isForMainFrame()){failedPage=true;status.setText("网页暂未打开，可点刷新或使用系统浏览器；也可下载后从云音导入文件。");}}
   @Override public void onReceivedHttpError(WebView view,WebResourceRequest request,WebResourceResponse response){if(request.isForMainFrame()){failedPage=true;status.setText("网站返回 HTTP "+response.getStatusCode()+"，可稍后刷新或使用系统浏览器。");}}
  });
  web.setDownloadListener((url,agent,disposition,mime,length)->{
   if(length>ScoreWebImport.LIMIT){notice("文件超过 8 MB，请下载并分段整理后导入");return;}
   offer(url,ScoreWebImport.name(url,disposition),agent);
  });
  web.setOnLongClickListener(v->{WebView.HitTestResult hit=web.getHitTestResult();if(hit!=null&&(hit.getType()==WebView.HitTestResult.IMAGE_TYPE||hit.getType()==WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE)){offer(hit.getExtra(),"简谱图片",null);return true;}return false;});
  if(state!=null){songPage=state.getString("songPage","");songTitle=state.getString("songTitle","");}
  if(state==null||web.restoreState(state)==null)web.loadUrl(initial);
 }
 private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
 private void button(LinearLayout parent,String text,Runnable action){Button b=new Button(this);b.setAllCaps(false);b.setText(text);b.setTextSize(12);b.setOnClickListener(v->action.run());parent.addView(b,new LinearLayout.LayoutParams(0,-2,1));}
 private void search(){
  if(web==null||query==null)return;
  try{String url=MidiShowSource.search(query.getText().toString(),order);web.loadUrl(url);InputMethodManager keyboard=(InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);if(keyboard!=null)keyboard.hideSoftInputFromWindow(query.getWindowToken(),0);}catch(IOException e){query.setError(e.getMessage());}
 }
 private void external(){String url=web==null?null:web.getUrl();if(url!=null)try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(ActivityNotFoundException e){notice("没有可用的系统浏览器");}}
 private void help(){notice(midi?"搜索歌名或歌手，选择网站上的曲谱版本，进入详情页后点击“下载”，按网站提示登录和下载。网站可能消耗积分，以其确认页面为准。云音不会代替你点击网站的下载确认。\n\n下载成功并校验后会返回云音，选择旋律声部、调性，校对保存，再上传乐器跟弹。搜索包含华语及外语，流行分类不等同于纯华语。\n\n如网站限制内嵌浏览器，请使用系统浏览器下载，再从云音“导入文件”选择 MIDI。":"取得 MIDI / MusicXML 后可选声部并校对；图片可识别后校对。需要登录的网站请按其正常下载流程操作。临时 blob 文件可用系统浏览器下载，再从云音导入文件。");}
 private void notice(String text){if(!closing&&!isFinishing())new AlertDialog.Builder(this).setMessage(text).setPositiveButton("知道了",null).show();}
 private void offer(String value,String name,String agent){
  if(choosing||progress!=null||value==null)return;final String url;
  try{url=ScoreWebImport.normalize(value);}catch(IOException e){notice("此下载不是普通 HTTPS 文件链接，请使用系统浏览器保存，再从云音导入文件");return;}
  choosing=true;
  new AlertDialog.Builder(this).setTitle("读取曲谱到云音").setMessage((name==null||name.isEmpty()?"读取这个曲谱文件":name)+"\n来源："+Uri.parse(url).getHost()+"\n校验成功后进入选声部和校对；失败会留在当前网页。")
   .setNegativeButton("继续浏览",null).setPositiveButton("读取曲谱",(d,w)->download(url,name,agent)).setOnDismissListener(d->choosing=false).show();
 }
 private void download(String url,String suggested,String agent){
  final String referer=web.getUrl(),cookie=CookieManager.getInstance().getCookie(url);
  final String source=songPage.isEmpty()?referer:songPage,title=songTitle.isEmpty()?web.getTitle():songTitle;
  final String userAgent=agent==null?web.getSettings().getUserAgentString():agent;final int ticket=++generation;
  progress=ProgressDialog.show(this,"读取曲谱","正在下载并校验文件…",true,true);final ProgressDialog dialog=progress;
  dialog.setOnCancelListener(d->{generation++;if(pending!=null)pending.cancel(true);progress=null;status.setText("已取消读取，当前网页保留。");});
  pending=worker.submit(()->{File staged=null;try{
   ScoreWebImport.Download file=ScoreWebImport.fetch(url,userAgent,cookie,referer);
   String fallback=suggested==null||suggested.isEmpty()?title:suggested;
   String name=midi?MidiShowSource.filename(file.name,MidiShowSource.filename(fallback,title)):file.name;
   staged=WebScoreStage.save(getCacheDir(),file.data,name);final File ready=staged;
   main.post(()->{
    if(closing||ticket!=generation){WebScoreStage.discard(getCacheDir(),ready);return;}
    dialog.dismiss();progress=null;Intent result=new Intent();result.putExtra("staged_path",ready.getAbsolutePath());result.putExtra("name",name);result.putExtra("origin",source==null?file.url:source);setResult(RESULT_OK,result);finish();
   });
  }catch(Exception e){WebScoreStage.discard(getCacheDir(),staged);main.post(()->{
    if(closing||ticket!=generation)return;dialog.dismiss();progress=null;status.setText("下载未完成，当前网页保留。");notice(e.getMessage()==null?"下载暂未完成，请稍后重试":e.getMessage());
   });}});
 }
 @Override public void onBackPressed(){if(progress!=null){progress.cancel();return;}if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
 @Override public void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);if(web!=null)web.saveState(state);if(query!=null)state.putString("query",query.getText().toString());state.putString("order",order);state.putString("songPage",songPage);state.putString("songTitle",songTitle);}
 @Override public void onDestroy(){closing=true;generation++;if(pending!=null)pending.cancel(true);worker.shutdownNow();if(progress!=null)progress.dismiss();if(web!=null){web.stopLoading();web.destroy();}super.onDestroy();}
}
