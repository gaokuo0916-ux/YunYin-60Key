package cn.fpga.score;
import android.content.Context;
import android.graphics.Bitmap;
import com.googlecode.tesseract.android.*;
import java.io.*;
import java.util.*;

/** Entirely on-device OCR. User chooses a note row and must review the result. */
public final class JianpuOcr {
    public static JianpuGeometry.Result recognize(Context context,Bitmap source)throws Exception{
        File base=new File(context.getFilesDir(),"ocr"),data=new File(base,"tessdata/eng.traineddata");
        if(!data.exists() || data.length()!=4113088){
            if(!data.getParentFile().isDirectory() && !data.getParentFile().mkdirs())throw new IOException("无法准备离线识谱模型");
            File temp=new File(data.getParentFile(),"eng.tmp");
            try(InputStream in=context.getAssets().open("ocr/eng.traineddata");FileOutputStream out=new FileOutputStream(temp)){
                byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)out.write(b,0,n);
            }
            if(temp.length()!=4113088 || !temp.renameTo(data))throw new IOException("离线模型复制失败");
        }
        float scale=Math.min(3f,Math.max(1f,1600f/source.getWidth()));
        int w=Math.round(source.getWidth()*scale),h=Math.round(source.getHeight()*scale);
        if((long)w*h>6000000)throw new IOException("选区太大，请只框一行音符");
        Bitmap bitmap=Bitmap.createScaledBitmap(source,w,h,true);int[] pixels=new int[w*h],gray=new int[w*h];bitmap.getPixels(pixels,0,w,0,0,w,h);
        for(int i=0;i<pixels.length;i++){int c=pixels[i];gray[i]=(((c>>16)&255)*77+((c>>8)&255)*150+(c&255)*29)>>8;}
        boolean[] ink=JianpuGeometry.threshold(gray);for(int i=0;i<pixels.length;i++)pixels[i]=ink[i]?0xff000000:0xffffffff;
        Bitmap binary=Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888);
        TessBaseAPI api=new TessBaseAPI();ResultIterator iterator=null;
        try{
            if(!api.init(base.getAbsolutePath(),"eng",TessBaseAPI.OEM_LSTM_ONLY))throw new IOException("离线识谱引擎初始化失败");
            api.setVariable(TessBaseAPI.VAR_CHAR_WHITELIST,"0123456789#bn.-|");
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_LINE);api.setImage(binary);api.getUTF8Text();
            iterator=api.getResultIterator();List<JianpuGeometry.Glyph> glyphs=new ArrayList<>();
            boolean accidental=false;
            if(iterator!=null){iterator.begin();do{
                String symbol=iterator.getUTF8Text(TessBaseAPI.PageIteratorLevel.RIL_SYMBOL);
                if("#".equals(symbol) || "b".equals(symbol) || "n".equals(symbol))accidental=true;
                if(symbol!=null && symbol.matches("[0-9]")){
                    int[] b=iterator.getBoundingBox(TessBaseAPI.PageIteratorLevel.RIL_SYMBOL);
                    if(b!=null)glyphs.add(new JianpuGeometry.Glyph(symbol.charAt(0)>'7'?0:symbol.charAt(0)-'0',b[0],b[1],b[2],b[3],accidental || symbol.charAt(0)>'7'?0:iterator.confidence(TessBaseAPI.PageIteratorLevel.RIL_SYMBOL)));
                    accidental=false;
                }
            }while(iterator.next(TessBaseAPI.PageIteratorLevel.RIL_SYMBOL));}
            return JianpuGeometry.analyze(w,h,gray,glyphs);
        }finally{if(iterator!=null)iterator.delete();api.recycle();binary.recycle();if(bitmap!=source)bitmap.recycle();}
    }
}
