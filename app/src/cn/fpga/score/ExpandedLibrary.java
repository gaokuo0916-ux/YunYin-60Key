package cn.fpga.score;
import android.app.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/** Search the local SQLite index in a worker with a bounded list and debounced input. */
final class ExpandedLibrary {
    private final Activity activity;private final Consumer<ExpandedCatalog.Item> importer;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();private final Handler main=new Handler(Looper.getMainLooper());
    private ExpandedCatalog catalog;private AlertDialog dialog;private EditText query;private TextView status;private Button more;private ArrayAdapter<String> adapter;
    private List<ExpandedCatalog.Item> shown=new ArrayList<>();private String group="china";private int generation,offset=0;private Button previous;private boolean closed;
    private final String[] groups={"all","china","piano","classical","folk","game","other"};
    ExpandedLibrary(Activity context,Consumer<ExpandedCatalog.Item> action){activity=context;importer=action;}
    void show(){
        LinearLayout box=new LinearLayout(activity);box.setOrientation(1);int pad=Math.round(18*activity.getResources().getDisplayMetrics().density);box.setPadding(pad,pad/2,pad,pad/2);
        status=new TextView(activity);status.setText("首次正在载入扩展目录…");status.setTextColor(InstrumentScreen.ink(activity));status.setTextSize(12);box.addView(status);
        query=new EditText(activity);query.setSingleLine();query.setTextSize(16);query.setHint("搜索曲名、作者、地区");query.setFilters(new InputFilter[]{new InputFilter.LengthFilter(120)});box.addView(query);
        Spinner category=new Spinner(activity);category.setAdapter(new ArrayAdapter<>(activity,android.R.layout.simple_spinner_dropdown_item,new String[]{"全部曲谱版本","中国民歌","钢琴","古典","世界民歌","游戏音乐","其他曲调"}));category.setSelection(1);box.addView(category);
        ListView list=new ListView(activity);adapter=new ArrayAdapter<>(activity,android.R.layout.simple_list_item_1,new ArrayList<>());list.setAdapter(adapter);int height=Math.min(360,(int)(activity.getResources().getDisplayMetrics().heightPixels/activity.getResources().getDisplayMetrics().density*.36f));box.addView(list,new LinearLayout.LayoutParams(-1,Math.round(height*activity.getResources().getDisplayMetrics().density)));
        LinearLayout pages=new LinearLayout(activity);box.addView(pages);previous=new Button(activity);previous.setAllCaps(false);previous.setText("上一页");pages.addView(previous,new LinearLayout.LayoutParams(0,-2,1));previous.setOnClickListener(v->{offset=Math.max(0,offset-24);schedule();});
        more=new Button(activity);more.setAllCaps(false);more.setText("下一页");pages.addView(more,new LinearLayout.LayoutParams(0,-2,1));more.setOnClickListener(v->{offset+=24;schedule();});
        dialog=new AlertDialog.Builder(activity).setTitle("扩展曲库 · 95,923 份").setView(box).setNegativeButton("关闭",null).setNeutralButton("来源说明",null).create();dialog.setOnDismissListener(d->close());dialog.setOnShowListener(d->dialog.getButton(-3).setOnClickListener(v->new AlertDialog.Builder(activity).setTitle("扩展目录来源").setMessage("来自 midicn-lib v1.23 的公开索引，筛除鼓轨来源、质量异常标记、无标题和超限条目，按文件 MD5 去重后纳入 95,923 份。\n\n这些是曲谱版本，含钢琴、民歌、古典和游戏音乐，不代表新增这么多华语流行歌曲。点选后联网下载并检查文件，再选择声部、调号和校对。\n\n逐曲来源与许可在下载确认页显示；中国民歌含自动识谱结果，仍需核对。\nhttps://github.com/midicn/midi-library").setPositiveButton("知道了",null).show()));dialog.show();
        list.setOnItemClickListener((p,v,index,id)->{if(index<shown.size()){ExpandedCatalog.Item item=shown.get(index);dialog.dismiss();importer.accept(item);}});
        query.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int after){}public void afterTextChanged(Editable e){}public void onTextChanged(CharSequence s,int a,int before,int c){offset=0;schedule();}});
        category.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onNothingSelected(AdapterView<?> p){}public void onItemSelected(AdapterView<?> p,View v,int index,long id){group=groups[index];offset=0;schedule();}});
        schedule();
    }
    private void schedule(){if(closed)return;final int ticket=++generation;final String q=query.getText().toString(),g=group;final int at=offset;status.setText("正在搜索目录…");more.setEnabled(false);previous.setEnabled(false);shown=new ArrayList<>();adapter.clear();main.postDelayed(()->{if(closed||ticket!=generation)return;worker.submit(()->{
            try{if(catalog==null)catalog=new ExpandedCatalog(activity);ExpandedCatalog.Result result=catalog.search(q,g,24,at);main.post(()->{if(closed||ticket!=generation)return;shown=result.items;adapter.clear();for(ExpandedCatalog.Item item:shown)adapter.add(item.title+"\n"+item.artist+" · "+item.source+" · 下载后校对");status.setText(result.total+" 份匹配 · 第 "+(at/24+1)+" / "+Math.max(1,(result.total+23)/24)+" 页");more.setEnabled(at+shown.size()<result.total);previous.setEnabled(at>0);});}
            catch(Exception e){main.post(()->{if(!closed&&ticket==generation)status.setText("目录未完成："+e.getMessage());});}
        });},240);}
    void close(){if(closed)return;closed=true;generation++;if(dialog!=null&&dialog.isShowing())dialog.dismiss();worker.submit(()->{if(catalog!=null)catalog.close();});worker.shutdown();}
}
