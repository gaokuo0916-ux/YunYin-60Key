package cn.fpga.score;
import android.Manifest;
import android.app.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

/** Native shell; audio synthesis and the BLE upload protocol remain independent. */
@SuppressWarnings("deprecation")
public final class MainActivity extends Activity {
    final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final List<BluetoothDevice> devices=new ArrayList<>();
    private final List<String> deviceRows=new ArrayList<>();
    private final Set<String> seen=new HashSet<>();
    private final Deque<String> messages=new ArrayDeque<>();
    private BluetoothAdapter bluetooth;private BluetoothLeScanner scanner;private ArrayAdapter<String> deviceAdapter;private AlertDialog scanDialog;
    private volatile BleLink link;private Future<?> job;private int operation,scanGeneration;
    boolean busy,uploaded,playing,paused,free;
    Score score;String scoreName="三音检查",connectionState="尚未连接",progressMessage="选好曲谱后上传到乐器";int percent;
    FeaturePanel features;InstrumentScreen screen;StudioController studio;
    List<PopCatalog.Item> popItems=new ArrayList<>();List<OnlineCatalog.Item> classicalItems=new ArrayList<>();List<OpenCatalog.Item> openItems=new ArrayList<>();
    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);
        BluetoothManager manager=(BluetoothManager)getSystemService(BLUETOOTH_SERVICE);bluetooth=manager==null?null:manager.getAdapter();
        screen=new InstrumentScreen(this);setContentView(screen.root);
        applyBars();
        screen.root.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        try{
            popItems=PopCatalog.read(getAssets().open("pop909_catalog.tsv"));
            openItems=OpenCatalog.read(getAssets().open("open_catalog.tsv"));
            try(InputStream in=getAssets().open("online_catalog.html")){classicalItems=OnlineCatalog.parse(read(in));}
            features=new FeaturePanel(this,this::setScore);
            studio=new StudioController(this);
            if(!features.restore())setScore(Score.parse(read(getAssets().open("three_notes.bt.txt")),120),"三音检查");
        }catch(Exception e){showError(e);}
        screen.render();
        incoming(getIntent());
    }
    void applyBars(){int bg=InstrumentScreen.background(this);if(screen!=null){screen.root.setBackgroundColor(bg);screen.web.setBackgroundColor(bg);}getWindow().setStatusBarColor(bg);getWindow().setNavigationBarColor(bg);getWindow().getDecorView().setSystemUiVisibility(InstrumentScreen.dark(this)?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);}
    boolean ready(){return link!=null&&link.isReady();}
    String logs(){return String.join("\n",messages);}
    void refresh(){if(screen!=null)screen.update();}
    private void log(String value){main.post(()->{messages.addLast(value);while(messages.size()>12)messages.removeFirst();refresh();});}
    void showError(Exception e){String text=e.getMessage()==null?e.toString():e.getMessage();log(text);if(!isFinishing()&&!isDestroyed())new AlertDialog.Builder(this).setTitle("暂未完成").setMessage(text).setPositiveButton("知道了",null).show();}
    interface Work{void run()throws Exception;}
    BleLink currentLink(){return link;}
    void enqueue(Work task){worker.submit(()->{try{task.run();}catch(Exception ignored){}});}
    void run(Work task){
        if(busy)return;final int ticket=++operation;busy=true;refresh();getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        job=worker.submit(()->{try{task.run();}catch(InterruptedException e){Thread.currentThread().interrupt();log("操作已取消");}
            catch(Exception e){main.post(()->{if(ticket==operation&&!isFinishing()){progressMessage="操作未完成，请检查提示后重试";showError(e);}});}
            finally{main.post(()->{if(ticket==operation){busy=false;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);refresh();}});}});
    }
    void cancel(){if(!busy)return;++operation;if(job!=null)job.cancel(true);if(link!=null)link.close();busy=false;uploaded=false;playing=false;paused=false;connectionState="已取消，请重新连接";progressMessage="本次操作未确认完成";getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);refresh();}
    void connectionMenu(){
        if(busy)return;if(!ready()){scanWithPermission();return;}
        new AlertDialog.Builder(this).setTitle("乐器已连接").setMessage(connectionState).setPositiveButton("保持连接",null).setNeutralButton("重新扫描",(d,w)->scanWithPermission()).setNegativeButton("断开",(d,w)->{if(link!=null)link.close();uploaded=false;playing=false;paused=false;connectionState="已断开连接";refresh();}).show();
    }
    private void scanWithPermission(){
        if(bluetooth==null){showError(new IOException("这部手机未提供蓝牙功能"));return;}
        String[] permissions=Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};
        for(String p:permissions)if(checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED){requestPermissions(permissions,9);return;}
        if(!bluetooth.isEnabled()){startActivityForResult(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),8);return;}
        stopScan();final int ticket=++scanGeneration;devices.clear();deviceRows.clear();seen.clear();scanner=bluetooth.getBluetoothLeScanner();
        if(scanner==null){showError(new IOException("蓝牙扫描不可用"));return;}
        deviceAdapter=new ArrayAdapter<>(this,android.R.layout.simple_list_item_1,deviceRows);
        scanDialog=new AlertDialog.Builder(this).setTitle("选择你的蓝牙模块").setAdapter(deviceAdapter,(d,which)->{if(which<devices.size()){BluetoothDevice chosen=devices.get(which);stopScan();connect(chosen);}}).setNegativeButton("关闭",(d,w)->stopScan()).create();
        scanDialog.setOnCancelListener(d->stopScan());scanDialog.show();connectionState="正在扫描；旧版安卓需打开定位开关";refresh();
        try{scanner.startScan(null,new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);}catch(Exception e){stopScan();showError(e);}
        main.postDelayed(()->{if(ticket!=scanGeneration)return;stopScan();if(devices.isEmpty()){connectionState="未发现设备：检查供电、权限和其他 App 占用";refresh();}},12000);
    }
    private final ScanCallback scanCallback=new ScanCallback(){
        @Override public void onScanResult(int type,ScanResult result){main.post(()->{if(scanner==null||deviceAdapter==null)return;try{BluetoothDevice d=result.getDevice();if(seen.add(d.getAddress())){String name=d.getName();if(name==null&&result.getScanRecord()!=null)name=result.getScanRecord().getDeviceName();devices.add(d);deviceRows.add((name==null?"未命名设备":name)+"\n"+d.getAddress()+"  "+result.getRssi()+" dBm");deviceAdapter.notifyDataSetChanged();}}catch(SecurityException e){connectionState="请允许蓝牙附近设备权限";refresh();}});}
        @Override public void onScanFailed(int code){main.post(()->{connectionState="扫描失败："+code+"，请重试";refresh();});}
    };
    private void stopScan(){++scanGeneration;if(scanner!=null){try{scanner.stopScan(scanCallback);}catch(SecurityException ignored){}scanner=null;}}
    private void connect(BluetoothDevice device){
        if(link!=null)link.close();if(studio!=null)studio.connecting();uploaded=false;playing=false;paused=false;connectionState="正在连接乐器";refresh();
        final BleLink[] holder=new BleLink[1];BleLink current=new BleLink(new BleLink.Listener(){public void state(String s){main.post(()->{if(link!=holder[0])return;connectionState=s;if(!ready()){playing=false;paused=false;}refresh();});}public void log(String s){MainActivity.this.log(s);}});holder[0]=current;link=current;
        try{current.connect(this,device);run(()->{current.awaitReady();if(studio!=null)studio.connected(current);});}catch(Exception e){showError(e);}
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==9&&grants.length>0){for(int grant:grants)if(grant!=PackageManager.PERMISSION_GRANTED){connectionState="需要蓝牙/附近设备权限";refresh();return;}scanWithPermission();}}
    void chooseFile(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.addCategory(Intent.CATEGORY_OPENABLE);i.setType("*/*");startActivityForResult(i,10);}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);incoming(intent);}
    private void incoming(Intent intent){if(intent==null||features==null)return;String action=intent.getAction();if(!Intent.ACTION_VIEW.equals(action)&&!Intent.ACTION_SEND.equals(action))return;if(busy){Toast.makeText(this,"请等当前传输完成后再导入曲谱",Toast.LENGTH_LONG).show();return;}
        Parcelable stream=intent.getParcelableExtra(Intent.EXTRA_STREAM);Uri uri=Intent.ACTION_VIEW.equals(action)?intent.getData():stream instanceof Uri?(Uri)stream:null;
        if(uri!=null){String scheme=uri.getScheme();if(!"content".equals(scheme)&&!"file".equals(scheme)){showError(new IOException("请先下载曲谱，再用云音打开文件"));return;}String name=uri.getLastPathSegment()==null?"导入曲谱":uri.getLastPathSegment();try(Cursor c=getContentResolver().query(uri,null,null,null,null)){if(c!=null&&c.moveToFirst()){int col=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(col>=0)name=c.getString(col);}}catch(Exception ignored){}features.importFile(uri,name);}
        else{CharSequence text=intent.getCharSequenceExtra(Intent.EXTRA_TEXT);if(text!=null){try{if(text.length()>524288)throw new IOException("文本过长，请拆分后导入");features.sharedText(text.toString());}catch(Exception e){showError(e);}}}
    }
    @Override public void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(studio!=null&&studio.result(request,result,data))return;if(features!=null&&features.onActivityResult(request,result,data))return;if(request==8&&result==RESULT_OK){scanWithPermission();return;}if(request==10&&result==RESULT_OK&&data!=null&&data.getData()!=null){Uri uri=data.getData();String name="导入曲谱";try(Cursor c=getContentResolver().query(uri,null,null,null,null)){if(c!=null&&c.moveToFirst()){int column=c.getColumnIndex(OpenableColumns.DISPLAY_NAME);if(column>=0)name=c.getString(column);}}catch(Exception ignored){}if(features!=null)features.importFile(uri,name);}}
    private static String read(InputStream input)throws IOException{if(input==null)throw new IOException("无法读取文件");try(InputStream in=input;ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] bytes=new byte[4096];int n;while((n=in.read(bytes))!=-1){if(out.size()+n>1024*1024)throw new IOException("文本过大");out.write(bytes,0,n);}return new String(out.toByteArray(),StandardCharsets.UTF_8);}}
    private void setScore(Score value,String name){score=value;if(value.nativePitch)free=false;scoreName=name;uploaded=false;playing=false;paused=false;percent=0;progressMessage=value.nativePitch?"原音高曲谱已准备，等待导入乐器":"曲谱已准备，等待上传";if(screen!=null){screen.page="perform";screen.render();}if(value.nativePitch&&ready()&&!busy)primary();}
    void presets(){String[] names={"三音检查","小星星","外婆的澎湖湾 · 跟弹顺序版","原音高上传检查 · 含两个缺键音"},files={"three_notes.bt.txt","twinkle.bt.txt","penghuwan.bt.txt"};new AlertDialog.Builder(this).setTitle("内置曲谱").setItems(names,(d,n)->{try{if(n==3){features.trialScore();return;}setScore(Score.parse(read(getAssets().open(files[n])),120),names[n]);}catch(Exception e){showError(e);}}).show();}
    void paste(){LinearLayout box=new LinearLayout(this);box.setOrientation(1);int pad=screen.dp(20);box.setPadding(pad,0,pad,0);EditText content=new EditText(this);content.setMinLines(5);content.setGravity(Gravity.TOP);content.setHint("BPM=120\n1,4\n2,2\n3,2\n也可粘贴 1155665 这类简谱");box.addView(content);AlertDialog dialog=new AlertDialog.Builder(this).setTitle("粘贴数字简谱").setView(box).setNegativeButton("取消",null).setPositiveButton("预览与保存",null).create();dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{try{features.paste(content.getText().toString());dialog.dismiss();}catch(Exception e){content.setError(e.getMessage());}}));dialog.show();}
    void primary(){if(busy)return;if(!ready()){connectionMenu();return;}if(free){control("STOP");return;}if(uploaded){control(playing||paused?"PAUSE":"START");return;}upload();}
    private void upload(){BleLink current=link;Score chosen=score;if(current==null||chosen==null)return;uploaded=false;percent=0;progressMessage="准备上传…";
        run(()->{long begin=SystemClock.elapsedRealtime();new Uploader(current).upload(chosen,(sent,total,stage)->main.post(()->{if(score!=chosen||link!=current||!current.isReady())return;percent=sent*100/Math.max(1,total);progressMessage=stage+" · "+sent+"/"+total+" 个事件";refresh();}));main.post(()->{if(score==chosen&&link==current&&current.isReady()){uploaded=true;progressMessage="曲谱已存入乐器，可以开始跟弹";refresh();}});log("保存成功："+chosen.count()+" 个事件，用时 "+((SystemClock.elapsedRealtime()-begin)/1000.0)+" 秒");if(studio!=null)try{studio.connected(current);}catch(Exception e){log("曲谱已上传；功能识别未完成，可在乐器页重新识别："+e.getMessage());}});}
    void control(String command){BleLink current=link;if(current==null||!current.isReady()||busy)return;if(command.equals("START")&&!uploaded){showError(new IOException("请先上传当前曲谱"));return;}run(()->{Uploader u=new Uploader(current);if(command.equals("START"))u.startPractice();else u.control(command);main.post(()->{if(current!=link||!current.isReady())return;if(command.equals("START")){playing=true;paused=false;}else if(command.equals("PAUSE")){boolean wasPaused=paused;paused=!wasPaused;playing=wasPaused;}else if(command.equals("STOP")){playing=false;paused=false;}refresh();});log(command.equals("START")?"已启动，请等待琴键提示灯":"控制已确认："+command);});}
    void mode(boolean value){if(busy)return;free=value;if(free&&ready())control("STOP");screen.render();}
    void importMenu(){if(busy||features==null)return;new AlertDialog.Builder(this).setTitle("导入曲谱").setItems(new String[]{"拍照 / 图片识谱","MIDI / MusicXML / TXT / 图片文件","粘贴数字简谱","粘贴曲谱 / 网页链接","内置示例曲谱","保存 / 校对当前曲谱"},(d,n)->{if(n==0)features.image();if(n==1)chooseFile();if(n==2)paste();if(n==3)features.linkDialog("");if(n==4)presets();if(n==5)features.saveCurrent(score,scoreName);}).show();}
    void changeTempo(int bpm){if(busy||score==null)return;if(score.nativePitch){showError(new IOException("原谱试用版保留原时值，请先按原速度测试"));return;}if(playing||paused){showError(new IOException("先结束跟弹再修改速度"));return;}List<int[]> n=new ArrayList<>();for(int i=0;i<score.count();i++)n.add(new int[]{score.degree(i),score.units(i)});setScore(new Score(bpm,n),scoreName);}
    @Override public void onBackPressed(){if(screen!=null&&!"perform".equals(screen.page)){screen.page="perform";screen.render();applyBars();}else super.onBackPressed();}
    @Override protected void onResume(){super.onResume();if(studio!=null)studio.visible(true);}
    @Override protected void onPause(){if(studio!=null)studio.visible(false);super.onPause();}
    @Override public void onConfigurationChanged(android.content.res.Configuration config){super.onConfigurationChanged(config);screen.render();applyBars();}
    @Override public void onDestroy(){++operation;stopScan();if(scanDialog!=null)scanDialog.dismiss();if(studio!=null)studio.close();if(screen!=null)screen.close();if(features!=null)features.close();if(job!=null)job.cancel(true);if(link!=null)link.close();worker.shutdownNow();super.onDestroy();}
}
