package cn.fpga.score;
import android.app.*;
import android.content.*;
import android.graphics.*;
import android.media.ExifInterface;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.UUID;
import java.util.concurrent.*;

/** Crop one jianpu row at a time; recognized rows can be appended to one draft. */
@SuppressWarnings("deprecation")
public final class ImageImportActivity extends Activity {
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private CropView crop;private EditText output;private TextView status;private CheckBox reviewed;
    private Bitmap image;private Uri cameraUri;private boolean processing;private ProgressDialog progress;
    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(20,25,20,15);root.setBackgroundColor(InstrumentScreen.background(this));setContentView(root);
        root.setOnApplyWindowInsetsListener((v,i)->{v.setPadding(20,25+i.getSystemWindowInsetTop(),20,15+i.getSystemWindowInsetBottom());return i;});
        TextView title=new TextView(this);title.setText("图片简谱 · 离线辅助识别");title.setTextSize(21);title.setTextColor(InstrumentScreen.ink(this));root.addView(title);
        status=new TextView(this);status.setText("拖动框选一行音符，包含下划线，避开标题和歌词。可逐行识别追加；高低八度按七键合并。");root.addView(status);
        LinearLayout tools=new LinearLayout(this);root.addView(tools);
        button(tools,"选图片",()->pick());button(tools,"拍照",()->camera());button(tools,"旋转",()->rotate());
        crop=new CropView();root.addView(crop,new LinearLayout.LayoutParams(-1,0,1));
        button(root,"识别框选这一行并追加",()->recognize());
        TextView legend=new TextView(this);legend.setText("每行：音符,时值；0=休止；4=一拍，2=半拍，1=四分之一拍，8=两拍。? 需修改。");legend.setTextSize(12);root.addView(legend);
        output=new EditText(this);output.setText("BPM=120\n");output.setGravity(Gravity.TOP);output.setTextSize(14);output.setMinLines(3);output.setMaxLines(5);root.addView(output,new LinearLayout.LayoutParams(-1,-2));
        reviewed=new CheckBox(this);reviewed.setText("我已对照图片核对音符、附点、延音与时值");root.addView(reviewed);
        output.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){}public void onTextChanged(CharSequence s,int start,int before,int count){reviewed.setChecked(false);}public void afterTextChanged(android.text.Editable e){}});
        LinearLayout bottom=new LinearLayout(this);root.addView(bottom);
        button(bottom,"清空草稿",()->{output.setText("BPM=120\n");reviewed.setChecked(false);});
        button(bottom,"确认导入",()->finishDraft());
        if(saved!=null){String uri=saved.getString("cameraUri");if(uri!=null)cameraUri=Uri.parse(uri);output.setText(saved.getString("draft","BPM=120\n"));}
        String incoming=getIntent().getStringExtra("image_path");
        if(incoming!=null&&incoming.equals(new File(getCacheDir(),"score_import_image").getAbsolutePath()))load(Uri.fromFile(new File(incoming)));
    }
    @Override public void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);if(cameraUri!=null)state.putString("cameraUri",cameraUri.toString());state.putString("draft",output.getText().toString());}
    private void button(LinearLayout parent,String text,Runnable task){Button b=new Button(this);b.setText(text);b.setAllCaps(false);b.setOnClickListener(v->{if(!processing)task.run();});parent.addView(b,parent.getOrientation()==LinearLayout.HORIZONTAL?new LinearLayout.LayoutParams(0,-2,1):new LinearLayout.LayoutParams(-1,-2));}
    private void error(Throwable e){new AlertDialog.Builder(this).setTitle("暂未完成").setMessage(e.getMessage()==null?e.toString():e.getMessage()).setPositiveButton("知道了",null).show();}
    private void pick(){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT);i.setType("image/*");i.addCategory(Intent.CATEGORY_OPENABLE);startActivityForResult(i,31);}
    private void camera(){
        try{String name=UUID.randomUUID()+".jpg";cameraUri=Uri.parse("content://"+getPackageName()+".photos/capture/"+name);
            Intent intent=new Intent(MediaStore.ACTION_IMAGE_CAPTURE);intent.putExtra(MediaStore.EXTRA_OUTPUT,cameraUri);
            intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_READ_URI_PERMISSION);intent.setClipData(ClipData.newRawUri("capture",cameraUri));startActivityForResult(intent,32);
        }catch(Exception e){error(e);}
    }
    @Override public void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);if(result!=RESULT_OK)return;
        Uri uri=request==31 && data!=null?data.getData():request==32?cameraUri:null;if(uri==null)return;
        load(uri);
    }
    private void load(Uri uri){
        processing=true;progress=ProgressDialog.show(this,"读取图片","正在准备框选…",true,false);
        worker.submit(()->{try{
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
            try(InputStream in=getContentResolver().openInputStream(uri)){BitmapFactory.decodeStream(in,null,bounds);}
            if(bounds.outWidth<1 || bounds.outHeight<1)throw new IOException("无法读取图片，请选择 JPG 或 PNG");
            BitmapFactory.Options options=new BitmapFactory.Options();options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inSampleSize=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>2200)options.inSampleSize*=2;
            Bitmap bitmap;try(InputStream in=getContentResolver().openInputStream(uri)){bitmap=BitmapFactory.decodeStream(in,null,options);}
            if(bitmap==null)throw new IOException("图片解码失败");
            int orientation=ExifInterface.ORIENTATION_NORMAL;try(InputStream in=getContentResolver().openInputStream(uri)){orientation=new ExifInterface(in).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);}catch(Exception ignored){}
            Matrix matrix=new Matrix();if(orientation==6)matrix.postRotate(90);else if(orientation==3)matrix.postRotate(180);else if(orientation==8)matrix.postRotate(270);else if(orientation==2)matrix.postScale(-1,1);
            if(!matrix.isIdentity()){Bitmap changed=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);if(changed!=bitmap)bitmap.recycle();bitmap=changed;}
            final Bitmap loaded=bitmap;runOnUiThread(()->{if(isFinishing()){loaded.recycle();return;}if(image!=null)image.recycle();image=loaded;crop.reset();status.setText("拖动框出一行音符及其下划线。重新识别同一行会追加重复内容，请核对后确认。");});
        }catch(Throwable e){runOnUiThread(()->{if(!isFinishing())error(e);});}
        finally{runOnUiThread(()->{processing=false;if(progress!=null)progress.dismiss();});}});
    }
    private void rotate(){if(image==null)return;Matrix m=new Matrix();m.postRotate(90);Bitmap b=Bitmap.createBitmap(image,0,0,image.getWidth(),image.getHeight(),m,true);if(b!=image)image.recycle();image=b;crop.reset();}
    private void recognize(){
        if(image==null){error(new IOException("请先拍照或选择图片"));return;}
        Bitmap selection;try{selection=crop.selected();}catch(Exception e){error(e);return;}
        processing=true;reviewed.setChecked(false);progress=ProgressDialog.show(this,"识别音符","离线识别中，请稍候…",true,false);
        worker.submit(()->{try{
            JianpuGeometry.Result result=JianpuOcr.recognize(this,selection);
            runOnUiThread(()->{if(isFinishing())return;String old=output.getText().toString();output.setText(old+(old.endsWith("\n")?"":"\n")+result.source);
                status.setText("已追加 "+result.notes+" 个音符；其中 "+result.lowConfidence+" 项需要重点核对。? 必须修改。连音、反复和复杂符号需对照原图；这不是准确率保证。");});
        }catch(Throwable e){runOnUiThread(()->{if(!isFinishing())error(e);});}
        finally{selection.recycle();runOnUiThread(()->{processing=false;if(progress!=null)progress.dismiss();});}});
    }
    private void finishDraft(){
        if(!reviewed.isChecked()){error(new IOException("请先对照原图核对，再勾选确认"));return;}
        try{
            String text=output.getText().toString();SongDraft.parse(text);
            File preview=new File(getCacheDir(),"score_image_review.png");
            if(image!=null)try(FileOutputStream out=new FileOutputStream(preview)){if(!image.compress(Bitmap.CompressFormat.PNG,90,out))throw new IOException("图片保存失败");}
            Intent result=new Intent();result.putExtra("source",text);result.putExtra("preview",image==null?"":preview.getAbsolutePath());setResult(RESULT_OK,result);finish();
        }catch(Exception e){error(e);}
    }
    @Override public void onDestroy(){worker.shutdownNow();if(progress!=null)progress.dismiss();super.onDestroy();}
    private final class CropView extends View{
        private final Paint paint=new Paint(3);private final RectF shown=new RectF(),selection=new RectF();private float startX,startY;
        CropView(){super(ImageImportActivity.this);setBackgroundColor(InstrumentScreen.dark(ImageImportActivity.this)?0xff303329:0xffe0dccf);}
        void reset(){selection.setEmpty();invalidate();}
        @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(image==null)return;
            float scale=Math.min(getWidth()/(float)image.getWidth(),getHeight()/(float)image.getHeight()),w=image.getWidth()*scale,h=image.getHeight()*scale;
            shown.set((getWidth()-w)/2,(getHeight()-h)/2,(getWidth()+w)/2,(getHeight()+h)/2);paint.setStyle(Paint.Style.FILL);canvas.drawBitmap(image,null,shown,paint);
            if(!selection.isEmpty()){paint.setColor(0x559e4c35);canvas.drawRect(selection,paint);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(3);paint.setColor(0xff9e4c35);canvas.drawRect(selection,paint);paint.setStyle(Paint.Style.FILL);}
        }
        @Override public boolean onTouchEvent(MotionEvent event){if(image==null || processing)return true;
            float x=Math.max(shown.left,Math.min(shown.right,event.getX())),y=Math.max(shown.top,Math.min(shown.bottom,event.getY()));
            if(event.getAction()==MotionEvent.ACTION_DOWN){startX=x;startY=y;selection.setEmpty();getParent().requestDisallowInterceptTouchEvent(true);}
            else if(event.getAction()==MotionEvent.ACTION_MOVE || event.getAction()==MotionEvent.ACTION_UP){selection.set(Math.min(startX,x),Math.min(startY,y),Math.max(startX,x),Math.max(startY,y));invalidate();}return true;
        }
        Bitmap selected()throws IOException{
            if(selection.isEmpty() || shown.isEmpty())throw new IOException("请在图片上拖动框选一行音符");
            int x=Math.max(0,Math.round((selection.left-shown.left)*image.getWidth()/shown.width())),y=Math.max(0,Math.round((selection.top-shown.top)*image.getHeight()/shown.height()));
            int w=Math.min(image.getWidth()-x,Math.round(selection.width()*image.getWidth()/shown.width())),h=Math.min(image.getHeight()-y,Math.round(selection.height()*image.getHeight()/shown.height()));
            if(w<40 || h<12)throw new IOException("选区过小，请包含完整音符及下划线");return Bitmap.createBitmap(image,x,y,w,h).copy(Bitmap.Config.ARGB_8888,false);
        }
    }
}
