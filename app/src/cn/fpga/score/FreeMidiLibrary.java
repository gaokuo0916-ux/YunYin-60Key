package cn.fpga.score;
import android.app.*;
import android.os.*;
import android.text.InputFilter;
import android.view.*;
import android.view.inputmethod.EditorInfo;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
/** Native free-search list: no account, payment dialog, or embedded website required. */
final class FreeMidiLibrary {
 private final Activity activity;private final Consumer<FreeMidiSource.Item> importer;
 private final ExecutorService worker=Executors.newSingleThreadExecutor();private final Handler main=new Handler(Looper.getMainLooper());
 private AlertDialog dialog;private EditText query;private TextView status;private Button previous,next,search;
 private ArrayAdapter<String> adapter;private List<FreeMidiSource.Item> shown=Collections.emptyList();
 private int generation,page;private String active="";private boolean closed;
 FreeMidiLibrary(Activity activity,Consumer<FreeMidiSource.Item> importer){this.activity=activity;this.importer=importer;}
 private Button button(LinearLayout row,String title,Runnable action){Button b=new Button(activity);b.setAllCaps(false);b.setText(title);b.setTextSize(12);b.setOnClickListener(v->action.run());row.addView(b,new LinearLayout.LayoutParams(0,-2,1));return b;}
 void show(String initial){
  LinearLayout box=new LinearLayout(activity);box.setOrientation(1);int pad=Math.round(16*activity.getResources().getDisplayMetrics().density);box.setPadding(pad,pad/2,pad,pad/2);
  TextView info=new TextView(activity);info.setText("无需登录或积分，点曲名直接读取MIDI原谱。此站以外语、游戏及较早曲目为主；华语请优先用“免费华语”目录。网站总量不等于App已收录量。");info.setTextSize(12);info.setTextColor(InstrumentScreen.ink(activity));box.addView(info);
  LinearLayout bar=new LinearLayout(activity);box.addView(bar);query=new EditText(activity);query.setSingleLine(true);query.setTextSize(14);query.setHint("英文歌名、歌手或关键词");query.setFilters(new InputFilter[]{new InputFilter.LengthFilter(120)});query.setText(initial==null?"":initial);query.setImeOptions(EditorInfo.IME_ACTION_SEARCH);bar.addView(query,new LinearLayout.LayoutParams(0,-2,3));search=button(bar,"搜索",()->load(query.getText().toString(),0));query.setOnEditorActionListener((v,n,e)->{if(n==EditorInfo.IME_ACTION_SEARCH){load(query.getText().toString(),0);return true;}return false;});
  status=new TextView(activity);status.setTextSize(12);status.setTextColor(InstrumentScreen.ink(activity));box.addView(status);
  ListView list=new ListView(activity);adapter=new ArrayAdapter<>(activity,android.R.layout.simple_list_item_1,new ArrayList<>());list.setAdapter(adapter);int height=Math.min(320,(int)(activity.getResources().getDisplayMetrics().heightPixels/activity.getResources().getDisplayMetrics().density*.36f));box.addView(list,new LinearLayout.LayoutParams(-1,Math.round(height*activity.getResources().getDisplayMetrics().density)));
  LinearLayout pages=new LinearLayout(activity);box.addView(pages);previous=button(pages,"上一页",()->load(active,page-1));next=button(pages,"下一页",()->load(active,page+1));button(pages,"重试",()->load(active,page));
  dialog=new AlertDialog.Builder(activity).setTitle("BitMidi · 免费搜谱").setView(box).setNegativeButton("关闭",null).create();dialog.setOnDismissListener(d->close());dialog.show();
  list.setOnItemClickListener((p,v,index,id)->{if(index<shown.size()){FreeMidiSource.Item item=shown.get(index);dialog.dismiss();importer.accept(item);}});load(query.getText().toString(),0);
 }
 private void load(String q,int at){
  if(closed)return;try{FreeMidiSource.search(q,at);}catch(Exception e){query.setError(e.getMessage());return;}
  active=q.trim();page=at;final int ticket=++generation;final String term=active;shown=Collections.emptyList();adapter.clear();status.setText("正在读取免费曲库…");previous.setEnabled(false);next.setEnabled(false);search.setEnabled(false);
  worker.submit(()->{try{FreeMidiSource.Page result=FreeMidiSource.fetch(term,at);main.post(()->{if(closed||ticket!=generation||activity.isFinishing())return;shown=result.items;adapter.clear();for(FreeMidiSource.Item item:shown)adapter.add(item.title+"\nMIDI原谱 · 免费读取");status.setText(result.total+" 份网站匹配 · 第 "+(at+1)+" 页"+(shown.isEmpty()?"\n没有匹配，可试英文歌名或切换免费华语目录":""));previous.setEnabled(at>0);next.setEnabled(result.next);search.setEnabled(true);});}
   catch(Exception e){main.post(()->{if(closed||ticket!=generation||activity.isFinishing())return;status.setText("未取得搜索结果："+e.getMessage()+"\n可点重试，或返回使用离线曲库。");search.setEnabled(true);});}});
 }
 void close(){if(closed)return;closed=true;generation++;if(dialog!=null&&dialog.isShowing())dialog.dismiss();worker.shutdownNow();}
}
