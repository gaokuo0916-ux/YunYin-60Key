package cn.fpga.score;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.text.Normalizer;
import java.util.*;

/** Read-only on-device catalog; never constructs a 95k-row view tree. */
final class ExpandedCatalog implements AutoCloseable {
    static final int COUNT=95923;
    static final String SHA256="124957fff3b6a229191ee029f0e2616713f4681dc4a2be357bfcc1c630533ef0";
    static final class Item {
        final String id,title,artist,path,license,source,md5;
        Item(Cursor c){id=c.getString(0);title=c.getString(1);artist=c.getString(2);path=c.getString(3);license=c.getString(4);source=c.getString(5);md5=c.getString(6);}
    }
    static final class Result {final int total;final List<Item> items;Result(int n,List<Item> rows){total=n;items=rows;}}
    final SQLiteDatabase database;
    ExpandedCatalog(Context context)throws Exception{
        File target=new File(context.getFilesDir(),"expanded_123_"+SHA256.substring(0,12)+".sqlite");
        if(!target.isFile()){
            File temporary=new File(context.getFilesDir(),"expanded_"+UUID.randomUUID()+".tmp");
            try{
                MessageDigest digest=MessageDigest.getInstance("SHA-256");
                try(InputStream in=context.getAssets().open("expanded_catalog.sqlite");FileOutputStream out=new FileOutputStream(temporary)){
                    byte[] buffer=new byte[65536];int n,total=0;while((n=in.read(buffer))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("目录载入已取消");if((total+=n)>40*1024*1024)throw new IOException("目录超过大小上限");digest.update(buffer,0,n);out.write(buffer,0,n);}out.getFD().sync();
                }
                StringBuilder hash=new StringBuilder();for(byte b:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",b&255));if(!hash.toString().equals(SHA256))throw new IOException("扩展目录校验未通过");
                Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
            }finally{Files.deleteIfExists(temporary.toPath());}
        }
        database=SQLiteDatabase.openDatabase(target.getAbsolutePath(),null,SQLiteDatabase.OPEN_READONLY|SQLiteDatabase.NO_LOCALIZED_COLLATORS);
    }
    Result search(String query,String category,int limit){
        return search(query,category,limit,0);
    }
    Result search(String query,String category,int limit,int offset){
        StringBuilder where=new StringBuilder("1=1");List<String> args=new ArrayList<>();
        if(!category.equals("all")){where.append(" AND category=?");args.add(category);}
        String normalized=Normalizer.normalize(query.trim().toLowerCase(Locale.ROOT),Normalizer.Form.NFKD).replaceAll("\\p{M}","");
        for(String term:normalized.split("\\s+")){if(term.isEmpty())continue;where.append(" AND search LIKE ? ESCAPE '\\'");args.add("%"+term.replace("\\","\\\\").replace("%","\\%").replace("_","\\_")+"%");}
        String[] parameters=args.toArray(new String[0]);int count;
        try(Cursor c=database.rawQuery("SELECT count(*) FROM tracks WHERE "+where,parameters)){c.moveToFirst();count=c.getInt(0);}
        List<Item> items=new ArrayList<>();try(Cursor c=database.rawQuery("SELECT id,title,artist,path,license,source,md5 FROM tracks WHERE "+where+" ORDER BY id LIMIT "+Math.min(240,Math.max(1,limit))+" OFFSET "+Math.max(0,offset),parameters)){while(c.moveToNext())items.add(new Item(c));}
        return new Result(count,items);
    }
    @Override public void close(){database.close();}
}
