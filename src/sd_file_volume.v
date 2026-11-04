`timescale 1ns/1ps
// Mount a preallocated contiguous legacy32MiB or extended256MiB YUNYIN.BIN in a FAT32 root directory.
// Read-only FAT traversal. Writes are bounded to the verified file, never FAT/MBR.
module sd_file_volume(input wire clk,input wire initialized,io_busy,io_done,
 input wire [3:0] io_error,input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 output reg io_request=0,io_write=0,output reg [31:0] io_sector=0,
 input wire user_request,user_write,input wire [19:0] user_sector,
 output reg user_done=0,output reg [3:0] user_error=0,
 output reg mounted=0,output reg [3:0] mount_error=0,output wire mounting,output reg file_extended=0);
 localparam WAIT_INIT=0,READ_ZERO=1,ZERO_DONE=2,BOOT_DONE=3,DIR_START=4,DIR_DONE=5,
  ROOT_FAT_DONE=6,CHAIN_START=7,CHAIN_DONE=8,MARKER_DONE=9,READY=10,USER_DONE=11,FAILED=12,GEOMETRY=13,GEOMETRY2=14,EXT_DONE=15;
 reg [3:0] state=WAIT_INIT;assign mounting=state!=READY && state!=USER_DONE && state!=FAILED;
 reg [31:0] partition=0,total_sectors=0,fat_size=0,fat_start=0,data_start=0,root_cluster=0;
 reg [15:0] bytes_sector=0,reserved=0,root_entries=0,fat16=0,ext_flags=0;
 reg [7:0] sectors_cluster=0,fats=0,signature_a=0,signature_b=0,partition_type=0;
 reg [31:0] mbr_start=0,mbr_size=0;reg [3:0] cluster_shift=0;
 reg [31:0] dir_cluster=0,file_cluster=0,file_size=0,file_start=0,last_cluster=0;
 reg [31:0] fat_page=0,fat_value=0;reg [7:0] dir_sector=0,root_steps=0;
 reg found=0,dir_end=0,bad_chain=0;reg [31:0] checked_clusters=0;
 reg [87:0] entry_name=0;reg [7:0] entry_attr=0;reg [15:0] entry_low=0,entry_high=0;reg [31:0] entry_size=0;
 reg [63:0] marker=0;reg [31:0] format_version=0,format_size=0;
 // The original first32MiB marker remains byte-for-byte compatible.
 wire [19:0] file_sectors=file_size==32'h10000000 ? 20'd524288:20'd65536;
 reg ext_copy=0;reg [63:0] ext_magic=0;
 reg [31:0] ext_version=0,ext_sectors=0,ext_dir=0,ext_data=0,ext_stride=0;
 reg [15:0] ext_slots=0,ext_legacy=0,ext_crc=0,ext_inverse=0,ext_actual=16'hffff;
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);
 integer k;reg [15:0] v;begin v=c^{b,8'd0};for(k=0;k<8;k=k+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end endfunction
 wire ext_valid=ext_magic=="YY26RECS" && ext_version==1 && ext_sectors==524288 &&
  ext_dir==65538 && ext_data==65664 && ext_stride==22890 && ext_slots==20 && ext_legacy==2 &&
  ext_actual==ext_crc && (ext_crc^ext_inverse)==16'hffff;
 wire valid_bpb=bytes_sector==512 && root_entries==0 && fat16==0 && fat_size!=0 &&
  (fats==1 || fats==2) && reserved!=0 && sectors_cluster!=0 && sectors_cluster<=128 &&
  (sectors_cluster&(sectors_cluster-1'b1))==0 && root_cluster>=2 && signature_a==8'h55 && signature_b==8'haa;
 reg [31:0] overhead=0,cluster_count=0;
 // Mount geometry is not on the sample path; register each arithmetic stage.
 always @(posedge clk)begin
  overhead<={16'd0,reserved}+(fats==2?(fat_size<<1):fat_size);
  cluster_count<=(total_sectors-overhead)>>cluster_shift;
 end
 wire [1:0] partition_lane=read_index[1:0]-2'd2;
 wire [31:0] current_fat_entry=(fat_page<<7)+{25'd0,read_index[8:2]};
 task readsector(input [31:0] lba,input [3:0] next);
  begin io_sector<=lba;io_write<=0;io_request<=1;state<=next;end
 endtask
 task fail(input [3:0] reason);begin mounted<=0;mount_error<=reason;state<=FAILED;end endtask
 task clear_boot;begin bytes_sector<=0;sectors_cluster<=0;reserved<=0;root_entries<=0;fat16<=0;fat_size<=0;fats<=0;root_cluster<=0;total_sectors<=0;signature_a<=0;signature_b<=0;end endtask
 integer n;
 always @(posedge clk)begin
  io_request<=0;user_done<=0;
  if(read_valid)begin
   if(state==ZERO_DONE || state==BOOT_DONE)begin
    case(read_index)
     11:bytes_sector[7:0]<=read_byte;12:bytes_sector[15:8]<=read_byte;13:sectors_cluster<=read_byte;
     14:reserved[7:0]<=read_byte;15:reserved[15:8]<=read_byte;16:fats<=read_byte;
     17:root_entries[7:0]<=read_byte;18:root_entries[15:8]<=read_byte;
     22:fat16[7:0]<=read_byte;23:fat16[15:8]<=read_byte;
     40:ext_flags[7:0]<=read_byte;41:ext_flags[15:8]<=read_byte;
     450:if(state==ZERO_DONE)partition_type<=read_byte;510:signature_a<=read_byte;511:signature_b<=read_byte;
    endcase
    if(read_index>=32 && read_index<36)total_sectors[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=36 && read_index<40)fat_size[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=44 && read_index<48)root_cluster[read_index[1:0]*8+:8]<=read_byte;
    if(state==ZERO_DONE && read_index>=454 && read_index<458)mbr_start[partition_lane*8+:8]<=read_byte;
    if(state==ZERO_DONE && read_index>=458 && read_index<462)mbr_size[partition_lane*8+:8]<=read_byte;
   end
   if(state==DIR_DONE)begin
    case(read_index[4:0])
     0:begin if(read_byte==0)dir_end<=1;entry_name<={80'd0,read_byte};end
     1,2,3,4,5,6,7,8,9,10:entry_name<={entry_name[79:0],read_byte};
     11:entry_attr<=read_byte;20:entry_high[7:0]<=read_byte;21:entry_high[15:8]<=read_byte;
     26:entry_low[7:0]<=read_byte;27:entry_low[15:8]<=read_byte;
     28:entry_size[7:0]<=read_byte;29:entry_size[15:8]<=read_byte;30:entry_size[23:16]<=read_byte;
     31:if(!found && !dir_end && entry_name=="YUNYIN  BIN" && (entry_attr&8'h18)==0)begin
      found<=1;file_cluster<={entry_high,entry_low};file_size<={read_byte,entry_size[23:0]};
     end
    endcase
   end
   if(state==ROOT_FAT_DONE && read_index[8:2]==dir_cluster[6:0])fat_value[read_index[1:0]*8+:8]<=read_byte;
   if(state==CHAIN_DONE)begin
    fat_value[read_index[1:0]*8+:8]<=read_byte;
    if(read_index[1:0]==3 && current_fat_entry>=file_cluster && current_fat_entry<=last_cluster)begin
     checked_clusters<=checked_clusters+1'b1;
     if(current_fat_entry==last_cluster)begin if({read_byte[3:0],fat_value[23:0]}<28'hffffff8)bad_chain<=1;end
     else if({4'd0,read_byte[3:0],fat_value[23:0]}!=current_fat_entry+1'b1)bad_chain<=1;
    end
   end
   if(state==EXT_DONE)begin
    if(read_index<508)ext_actual<=crcbyte(ext_actual,read_byte);
    if(read_index<8)ext_magic<={ext_magic[55:0],read_byte};
    if(read_index>=8 && read_index<12)ext_version[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=12 && read_index<16)ext_sectors[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=16 && read_index<20)ext_dir[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=20 && read_index<24)ext_data[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=24 && read_index<28)ext_stride[read_index[1:0]*8+:8]<=read_byte;
    if(read_index==28 || read_index==29)ext_slots[read_index[0]*8+:8]<=read_byte;
    if(read_index==30 || read_index==31)ext_legacy[read_index[0]*8+:8]<=read_byte;
    if(read_index==508 || read_index==509)ext_crc[read_index[0]*8+:8]<=read_byte;
    if(read_index==510 || read_index==511)ext_inverse[read_index[0]*8+:8]<=read_byte;
   end
   if(state==MARKER_DONE)begin
    if(read_index<8)marker<={marker[55:0],read_byte};
    if(read_index>=8 && read_index<12)format_version[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=12 && read_index<16)format_size[read_index[1:0]*8+:8]<=read_byte;
   end
  end
  case(state)
   WAIT_INIT:if(initialized && !io_busy)begin clear_boot;readsector(0,ZERO_DONE);end
   ZERO_DONE:if(io_done)begin
    if(io_error!=0)fail(1);
    else if(valid_bpb)begin partition<=0;state<=DIR_START;end
    else if(signature_a==8'h55 && signature_b==8'haa && (partition_type==8'h0b || partition_type==8'h0c) && mbr_start!=0 && mbr_start<32'h10000000 && mbr_size>=65536)begin
     partition<=mbr_start;clear_boot;readsector(mbr_start,BOOT_DONE);
    end else fail(2);
   end
   BOOT_DONE:if(io_done)begin if(io_error!=0 || !valid_bpb || total_sectors>mbr_size)fail(2);else state<=DIR_START;end
   DIR_START:begin
    for(n=0;n<8;n=n+1)if(sectors_cluster==(1<<n))cluster_shift<=n;
    fat_start<=partition+{16'd0,reserved}+((ext_flags[7] && ext_flags[3:0]==1)?fat_size:32'd0);
    data_start<=partition+overhead;dir_cluster<=root_cluster;dir_sector<=0;state<=GEOMETRY;
   end
   GEOMETRY:state<=GEOMETRY2;
   GEOMETRY2:state<=READ_ZERO;
   READ_ZERO:begin
    if(total_sectors<=overhead || cluster_count<65525 || root_cluster>=cluster_count+2 || (ext_flags[7] && ext_flags[3:0]>=fats))fail(2);
    else readsector(data_start+((dir_cluster-2)<<cluster_shift),DIR_DONE);
   end
   DIR_DONE:if(io_done)begin
    if(io_error!=0)fail(1);
    else if(found)begin
     if((file_size!=32'h02000000 && file_size!=32'h10000000) || file_cluster<2 || file_cluster>=cluster_count+2)fail(3);
     else begin
      file_start<=data_start+((file_cluster-2)<<cluster_shift);
      last_cluster<=file_cluster+({12'd0,file_sectors}>>cluster_shift)-1'b1;
      fat_page<=file_cluster>>7;checked_clusters<=0;bad_chain<=0;state<=CHAIN_START;
     end
    end else if(dir_end)fail(3);
    else if(dir_sector+1'b1<sectors_cluster)begin dir_sector<=dir_sector+1'b1;readsector(data_start+((dir_cluster-2)<<cluster_shift)+{24'd0,dir_sector}+1'b1,DIR_DONE);end
    else if(root_steps==127)fail(3);
    else readsector(fat_start+(dir_cluster>>7),ROOT_FAT_DONE);
   end
   ROOT_FAT_DONE:if(io_done)begin
    if(io_error!=0)fail(1);
    else if(fat_value[27:0]<2 || fat_value[27:0]>=cluster_count+2)fail(3);
    else begin dir_cluster<={4'd0,fat_value[27:0]};dir_sector<=0;root_steps<=root_steps+1'b1;readsector(data_start+(({4'd0,fat_value[27:0]}-2)<<cluster_shift),DIR_DONE);end
   end
   CHAIN_START:if(last_cluster>=cluster_count+2 || (last_cluster>>7)>=fat_size)fail(4);else readsector(fat_start+fat_page,CHAIN_DONE);
   CHAIN_DONE:if(io_done)begin
    if(io_error!=0)fail(1);
    else if(bad_chain)fail(4);
    else if(fat_page==last_cluster>>7)begin
     if(checked_clusters!=({12'd0,file_sectors}>>cluster_shift))fail(4);
     else readsector(file_start,MARKER_DONE);
    end else begin fat_page<=fat_page+1'b1;readsector(fat_start+fat_page+1'b1,CHAIN_DONE);end
   end
   MARKER_DONE:if(io_done)begin
    if(io_error!=0)fail(1);
    else if(marker!="YY24STOR" || format_version!=1 || format_size!=65536)fail(5);
    else if(file_size==32'h10000000)begin ext_copy<=0;ext_actual<=16'hffff;readsector(file_start+32'd65536,EXT_DONE);end
    else begin mounted<=1;state<=READY;end
   end
   EXT_DONE:if(io_done)begin
    if(io_error==0 && ext_valid)begin file_extended<=1;mounted<=1;state<=READY;end
    else if(!ext_copy)begin ext_copy<=1;ext_actual<=16'hffff;readsector(file_start+32'd65537,EXT_DONE);end
    else begin file_extended<=0;mounted<=1;state<=READY;end
   end
   READY:if(user_request && !io_busy)begin
    user_error<=0;
    if(user_sector>=file_sectors || (user_sector>=65536 && !file_extended) || (user_write && (user_sector==0 || user_sector==65536 || user_sector==65537)))begin user_error<=7;user_done<=1;end
    else begin io_write<=user_write;io_sector<=file_start+{12'd0,user_sector};io_request<=1;state<=USER_DONE;end
   end
   USER_DONE:if(io_done)begin user_error<=io_error;user_done<=1;state<=READY;end
   FAILED:if(user_request)begin user_error<=8;user_done<=1;end
  endcase
 end
endmodule

