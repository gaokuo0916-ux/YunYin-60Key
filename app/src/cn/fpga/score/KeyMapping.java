package cn.fpga.score;
import java.util.*;
/** Seven physical keys form a permutation: no lost notes or duplicate LED targets. */
public final class KeyMapping {
    private static final int[] F={1,1,2,6,24,120,720,5040};
    public static int[] decode(int rank){
        if(rank<0||rank>=5040)throw new IllegalArgumentException("键位编号超出范围");
        List<Integer> left=new ArrayList<>();for(int n=1;n<=7;n++)left.add(n);
        int[] map=new int[7];for(int n=0;n<7;n++){int f=F[6-n];map[n]=left.remove(rank/f);rank%=f;}return map;
    }
    public static int encode(int[] map){
        if(map==null||map.length!=7)throw new IllegalArgumentException("需要七个键位");
        int rank=0;boolean[] seen=new boolean[8];for(int i=0;i<7;i++){
            int v=map[i];if(v<1||v>7||seen[v])throw new IllegalArgumentException("七键必须各对应一个不同的音");
            int smaller=0;for(int k=1;k<v;k++)if(!seen[k])smaller++;rank+=smaller*F[6-i];seen[v]=true;
        }return rank;
    }
    public static int[] swap(int[] source,int key,int value){
        encode(source);if(key<0||key>6||value<1||value>7)throw new IllegalArgumentException("键位无效");
        int[] map=source.clone();for(int n=0;n<7;n++)if(map[n]==value){map[n]=map[key];break;}map[key]=value;return map;
    }
}
