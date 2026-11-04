package cn.fpga.score;
import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.*;

/** Grants the camera access only to app-created capture files. */
public final class PhotoProvider extends ContentProvider {
    @Override public boolean onCreate(){return true;}
    @Override public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
        if(uri.getPathSegments().size()!=2 || !uri.getPathSegments().get(0).equals("capture"))throw new FileNotFoundException("Invalid capture URI");
        String name=uri.getLastPathSegment();if(name==null || !name.matches("[a-f0-9-]{36}\\.jpg"))throw new FileNotFoundException("Invalid capture name");
        File directory=new File(getContext().getCacheDir(),"captures");if(!directory.isDirectory() && !directory.mkdirs())throw new FileNotFoundException("Capture directory unavailable");
        return ParcelFileDescriptor.open(new File(directory,name),ParcelFileDescriptor.parseMode(mode));
    }
    @Override public String getType(Uri uri){return "image/jpeg";}
    @Override public Cursor query(Uri u,String[] p,String s,String[] a,String sort){return null;}
    @Override public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}
    @Override public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}
    @Override public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
}
