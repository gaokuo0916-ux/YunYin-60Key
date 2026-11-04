package cn.fpga.score;
/** Bounded page windows, including the final partial page and empty searches. */
public final class CatalogPager {
 public static final int SIZE=60;
 public final int page,pages,from,to,total;
 public CatalogPager(int count,int requested){total=Math.max(0,count);pages=Math.max(1,(total+SIZE-1)/SIZE);page=Math.max(0,Math.min(requested,pages-1));from=page*SIZE;to=Math.min(total,from+SIZE);}
}
