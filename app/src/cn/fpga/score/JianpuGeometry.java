package cn.fpga.score;
import java.util.*;

/** Pixel geometry augments digit OCR with underlines, duration dots and dashes. */
public final class JianpuGeometry {
    public static final class Glyph {
        public final int degree,left,top,right,bottom;public final float confidence;
        public Glyph(int d,int l,int t,int r,int b,float c){degree=d;left=l;top=t;right=r;bottom=b;confidence=c;}
    }
    public static final class Result {
        public final String source;public final int notes,lowConfidence;
        Result(String csv,int n,int low){source=csv;notes=n;lowConfidence=low;}
    }
    private static final class Box {int left,top,right,bottom,size;Box(int x,int y){left=right=x;top=bottom=y;}}
    public static boolean[] threshold(int[] gray){
        int[] hist=new int[256];for(int x:gray)hist[Math.max(0,Math.min(255,x))]++;
        long total=0;for(int i=0;i<256;i++)total+=(long)i*hist[i];long leftSum=0;int left=0,best=127;double variance=-1;
        for(int i=0;i<255;i++){left+=hist[i];leftSum+=(long)i*hist[i];int right=gray.length-left;if(left==0 || right==0)continue;
            double d=leftSum/(double)left-(total-leftSum)/(double)right,v=(double)left*right*d*d;if(v>variance){variance=v;best=i;}}
        boolean[] ink=new boolean[gray.length];for(int i=0;i<gray.length;i++)ink[i]=gray[i]<=Math.min(best,220);return ink;
    }
    private static List<Box> components(boolean[] ink,int w,int h,int l,int t,int r,int b){
        l=Math.max(0,l);t=Math.max(0,t);r=Math.min(w,r);b=Math.min(h,b);List<Box> boxes=new ArrayList<>();
        if(r<=l || b<=t)return boxes;int cw=r-l,ch=b-t;boolean[] seen=new boolean[cw*ch];int[] queue=new int[cw*ch];
        for(int y=t;y<b;y++)for(int x=l;x<r;x++){
            int initial=(y-t)*cw+x-l;if(seen[initial] || !ink[y*w+x])continue;
            Box box=new Box(x,y);int head=0,tail=0;queue[tail++]=initial;seen[initial]=true;
            while(head<tail){int p=queue[head++],px=p%cw,py=p/cw;box.size++;box.left=Math.min(box.left,l+px);box.right=Math.max(box.right,l+px+1);box.top=Math.min(box.top,t+py);box.bottom=Math.max(box.bottom,t+py+1);
                for(int delta:new int[]{-1,1,-cw,cw}){int q=p+delta;if(q<0 || q>=cw*ch || (delta==-1 && px==0) || (delta==1 && px==cw-1) || seen[q])continue;
                    if(ink[(t+q/cw)*w+l+q%cw]){seen[q]=true;queue[tail++]=q;}}
            }boxes.add(box);
        }return boxes;
    }
    public static Result analyze(int width,int height,int[] gray,List<Glyph> recognized){
        if(width<=0 || height<=0 || (long)width*height!=gray.length || gray.length>6000000)throw new IllegalArgumentException("图像大小不支持");
        if(recognized.isEmpty())throw new IllegalArgumentException("未识别到数字音符，请放大并只框选一行音符");
        List<Glyph> glyphs=new ArrayList<>();for(Glyph g:recognized)if(g.degree>=0 && g.degree<=7 && g.right>g.left && g.bottom>g.top)glyphs.add(g);
        if(glyphs.isEmpty())throw new IllegalArgumentException("没有可用音符");glyphs.sort(Comparator.comparingInt(g->g.left));
        int[] heights=new int[glyphs.size()];for(int i=0;i<heights.length;i++)heights[i]=glyphs.get(i).bottom-glyphs.get(i).top;Arrays.sort(heights);int typical=heights[heights.length/2];
        boolean[] ink=threshold(gray);StringBuilder csv=new StringBuilder();int count=0,low=0;double baseline=0;
        for(int i=0;i<glyphs.size();i++){
            Glyph g=glyphs.get(i);int rawH=g.bottom-g.top,rawW=g.right-g.left;
            if(rawH>typical*1.5 && rawW<typical*.22)continue; // a tall barline mistaken for 1
            Box core=null;for(Box b:components(ink,width,height,g.left,g.top,g.right,g.bottom))
                if(core==null || b.bottom-b.top>core.bottom-core.top)core=b;
            if(core==null)continue;int h=Math.max(5,core.bottom-core.top),center=(g.left+g.right)/2;
            if(count==0)baseline=core.bottom;else if(Math.abs(core.bottom-baseline)>typical*.7)throw new IllegalArgumentException("选区包含多行或歌词，请一次框选一行音符");
            int half=Math.max(rawW/2,(int)(h*.25)),l=Math.max(0,center-half),r=Math.min(width,center+half+1);
            int bars=0;boolean inside=false;
            for(int y=core.bottom+1;y<Math.min(height,core.bottom+(int)(h*.72));y++){
                int black=0;for(int x=l;x<r;x++)if(ink[y*width+x])black++;
                boolean line=black>=(r-l)*.65;
                if(line && !inside)bars++;inside=line;
            }
            double units=bars==0?4:bars==1?2:bars==2?1:Double.NaN;
            int next=i+1<glyphs.size()?glyphs.get(i+1).left:width;
            int gapRight=Math.min(next-1,g.right+(int)(h*2.5));int dots=0,dashes=0;
            for(Box b:components(ink,width,height,g.right+1,core.top,gapRight,core.bottom+1)){
                int bw=b.right-b.left,bh=b.bottom-b.top;double cy=(b.top+b.bottom)/2.0;
                if(bw>=h*.42 && bh<=h*.2 && Math.abs(cy-(core.top+core.bottom)/2.0)<h*.2)dashes++;
                else if(bw<=h*.3 && bh<=h*.3 && b.left-g.right<h*.65 && cy>core.top+h*.3 && cy<core.bottom-h*.1 && b.size>=2)dots++;
            }
            if(dots>0)units*=dots==1?1.5:dots==2?1.75:Double.NaN;units+=dashes*4;
            String value=Double.isNaN(units) || units!=Math.rint(units) || units>64?"?":Integer.toString((int)units);
            String degree=g.confidence<25?"?":Integer.toString(g.degree);
            if(g.confidence<65 || value.equals("?") || degree.equals("?"))low++;
            csv.append(degree).append(',').append(value).append('\n');count++;
        }
        if(count==0)throw new IllegalArgumentException("未提取到可用数字，请重新框选");
        return new Result(csv.toString(),count,low);
    }
}
