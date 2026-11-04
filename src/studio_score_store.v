`timescale 1ns/1ps
// Two transactional score slots inside YUNYIN.BIN. Old slot survives a failed save.
// Headers at relative sectors 1 / 65; each has <=48 data sectors.
module studio_score_store(input wire clk,mounted,input wire [3:0] mount_error,
 input wire save,recall,safe,user_valid,input wire [13:0] count,input wire [15:0] bpm,original_crc,
 input wire [12:0] key_rank,
 output reg busy=0,output reg [2:0] status=0,output reg [3:0] error=0,
 output reg [31:0] generation=0,output reg [13:0] saved_count=0,
 output reg [15:0] saved_crc=0,output reg [12:0] saved_rank=0,
 output wire export_mode,output reg [12:0] export_address=0,input wire [23:0] export_data,
 output reg restore_begin=0,restore_write=0,restore_commit=0,
 output reg [12:0] restore_address=0,output reg [23:0] restore_data=0,
 output reg [13:0] restore_count=0,output reg [15:0] restore_bpm=120,restore_crc=0,
 output reg [12:0] restore_rank=0,
 output reg block_request=0,block_write=0,output reg [15:0] block_sector=0,
 input wire block_done,input wire [3:0] block_error,
 input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire [8:0] write_index,output reg [7:0] write_byte=0,
 input wire native_format,output reg restore_native=0);
 localparam WAIT=0,H0=1,H1=2,PICK=3,READ_BODY=4,CHECK_BODY=5,COMMIT=6,IDLE=7,
  ZERO_HEADER=8,INVALID_DONE=9,FILL=10,DATA_DONE=11,FILL_HEADER=12,FINAL_DONE=13,VERIFY_HEADER=14,START_BODY=15;
 reg [3:0] state=WAIT;reg saving=0,slot=0,chosen=0,tried=0,has_saved=0;reg [1:0] valid_slots=0;
 reg native_slots[0:1];
 reg [31:0] seqs[0:1];reg [13:0] counts[0:1];reg [15:0] tempos[0:1],crcs[0:1],body_crcs[0:1];reg [12:0] ranks[0:1];
 reg [63:0] magic=0;reg [31:0] version=0,seq=0,inverse=0;reg [15:0] h_count=0,h_bpm=0,h_rank=0,h_crc=0,h_original=0;reg [7:0] flag=0;
 wire header_valid=magic=="YY24SCOR" && (version==1 || version==2) && (seq^inverse)==32'hffffffff && flag==8'ha5 &&
  h_count>=1 && h_count<=8192 && h_bpm>=20 && h_bpm<=300 && h_rank<5040;
 reg [7:0] buffer[0:511] /* synthesis syn_ramstyle = "block_ram" */;
 reg [8:0] fill_index=0;reg [5:0] body_sector=0;
 reg [14:0] byte_count=0,data_length=0;reg [13:0] event_index=0;
 reg [1:0] phase=0;reg [23:0] event_cache=0;reg [2:0] fetch_wait=0;
 reg [15:0] crc=16'hffff,wanted_crc=0;reg invalid_body=0;
 reg snap_native=0;
 wire body_native=saving?snap_native:restore_native;
 reg [31:0] snap_seq=0;reg [13:0] snap_count=0;reg [15:0] snap_bpm=0,snap_original=0;reg [12:0] snap_rank=0;
 assign export_mode=busy && saving;
 wire [15:0] slot_base=slot?16'd65:16'd1;
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);integer n;reg [15:0] v;
  begin v=c^{b,8'd0};for(n=0;n<8;n=n+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end
 endfunction
 function [15:0] metacrc(input [13:0] c,input [15:0] b,input [12:0] r,input [15:0] o,input nf);reg [15:0] v;
  begin v=crcbyte(crcbyte(16'hffff,c[7:0]),{2'd0,c[13:8]});v=crcbyte(crcbyte(v,b[7:0]),b[15:8]);v=crcbyte(crcbyte(v,r[7:0]),{3'd0,r[12:8]});v=crcbyte(crcbyte(v,o[7:0]),o[15:8]);metacrc=nf?crcbyte(v,8'd2):v;end
 endfunction
 function [7:0] header_byte(input [8:0] ix);begin
  case(ix)
   0:header_byte="Y";1:header_byte="Y";2:header_byte="2";3:header_byte="4";4:header_byte="S";5:header_byte="C";6:header_byte="O";7:header_byte="R";
   8:header_byte=snap_native?2:1;12,13,14,15:header_byte=snap_seq[ix[1:0]*8+:8];
   16:header_byte=snap_count[7:0];17:header_byte={2'd0,snap_count[13:8]};18:header_byte=snap_bpm[7:0];19:header_byte=snap_bpm[15:8];
   20:header_byte=snap_rank[7:0];21:header_byte={3'd0,snap_rank[12:8]};22:header_byte=wanted_crc[7:0];23:header_byte=wanted_crc[15:8];
   24:header_byte=snap_original[7:0];25:header_byte=snap_original[15:8];
   28,29,30,31:header_byte=~snap_seq[ix[1:0]*8+:8];32:header_byte=8'ha5;default:header_byte=0;
  endcase end
 endfunction
 task request(input wr,input [15:0] sector,input [3:0] next);
  begin block_write<=wr;block_sector<=sector;block_request<=1;state<=next;end
 endtask
 task failed(input [3:0] reason);begin busy<=0;error<=reason;status<=4;state<=IDLE;end endtask
 task load_candidate(input pick);
  begin slot<=pick;busy<=1;status<=2;saving<=0;tried<=1;
   restore_native<=native_slots[pick];restore_count<=counts[pick];restore_bpm<=tempos[pick];restore_crc<=crcs[pick];restore_rank<=ranks[pick];
   crc<=metacrc(counts[pick],tempos[pick],ranks[pick],crcs[pick],native_slots[pick]);wanted_crc<=body_crcs[pick];
   data_length<=counts[pick]+(counts[pick]<<1);byte_count<=0;phase<=0;event_index<=0;invalid_body<=0;body_sector<=0;
   state<=START_BODY;
  end
 endtask
 reg [7:0] next_byte;
 always @(*)case(phase)0:next_byte=event_cache[23:16];1:next_byte=event_cache[7:0];default:next_byte=event_cache[15:8];endcase
 always @(posedge clk)begin
  write_byte<=buffer[write_index];block_request<=0;restore_begin<=0;restore_write<=0;restore_commit<=0;
  if(read_valid)begin
   if(state==H0 || state==H1 || state==VERIFY_HEADER)begin
    if(read_index<8)magic<={magic[55:0],read_byte};
    if(read_index>=8 && read_index<12)version[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=12 && read_index<16)seq[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=16 && read_index<18)h_count[read_index[0]*8+:8]<=read_byte;
    if(read_index>=18 && read_index<20)h_bpm[read_index[0]*8+:8]<=read_byte;
    if(read_index>=20 && read_index<22)h_rank[read_index[0]*8+:8]<=read_byte;
    if(read_index>=22 && read_index<24)h_crc[read_index[0]*8+:8]<=read_byte;
    if(read_index>=24 && read_index<26)h_original[read_index[0]*8+:8]<=read_byte;
    if(read_index>=28 && read_index<32)inverse[read_index[1:0]*8+:8]<=read_byte;
    if(read_index==32)flag<=read_byte;
   end
   if(state==READ_BODY && byte_count<data_length)begin
    crc<=crcbyte(crc,read_byte);byte_count<=byte_count+1'b1;
    case(phase)
     0:begin event_cache[23:16]<=read_byte;phase<=1;if(read_byte>(body_native?128:7))invalid_body<=1;end
     1:begin event_cache[7:0]<=read_byte;phase<=2;end
     2:begin
      phase<=0;event_index<=event_index+1'b1;
      if({read_byte,event_cache[7:0]}==0 || (!body_native && {read_byte,event_cache[7:0]}>48000))invalid_body<=1;
      if(!saving)begin restore_write<=1;restore_address<=event_index[12:0];restore_data<={event_cache[23:16],read_byte,event_cache[7:0]};end
     end
    endcase
   end
  end
  case(state)
   WAIT:if(mounted)begin busy<=1;status<=2;error<=0;request(0,1,H0);end
   else if(mount_error!=0)begin status<=4;error<=mount_error;end
   else begin status<=0;error<=0;end
   H0,H1:if(block_done)begin
    if(block_error!=0)failed(1);
    else begin
     valid_slots[state==H1]<=header_valid;native_slots[state==H1]<=version==2;seqs[state==H1]<=seq;counts[state==H1]<=h_count[13:0];tempos[state==H1]<=h_bpm;ranks[state==H1]<=h_rank[12:0];crcs[state==H1]<=h_original;body_crcs[state==H1]<=h_crc;
     if(state==H0)request(0,65,H1);else begin state<=PICK;tried<=0;end
    end
   end
   PICK:begin
    if(valid_slots==0)begin busy<=0;status<=1;state<=IDLE;end
    else begin
     chosen<=valid_slots[1] && (!valid_slots[0] || $signed(seqs[1]-seqs[0])>0);
     load_candidate(valid_slots[1] && (!valid_slots[0] || $signed(seqs[1]-seqs[0])>0));
    end
   end
   START_BODY:begin restore_begin<=1;request(0,slot_base+1,READ_BODY);end
   READ_BODY:if(block_done)begin
    if(block_error!=0)begin invalid_body<=1;state<=CHECK_BODY;end
    else if(byte_count>=data_length)state<=CHECK_BODY;
    else begin body_sector<=body_sector+1'b1;request(0,slot_base+2+{10'd0,body_sector},READ_BODY);end
   end
   CHECK_BODY:if(invalid_body || crc!=wanted_crc || byte_count!=data_length)begin
    if(!saving && tried && valid_slots[!slot])begin valid_slots[slot]<=0;tried<=0;load_candidate(!slot);tried<=0;end
    else failed(2);
   end else if(saving)begin fill_index<=0;state<=FILL_HEADER;end else state<=COMMIT;
   COMMIT:if(safe)begin
    restore_commit<=1;has_saved<=1;generation<=seqs[slot];saved_count<=counts[slot];saved_crc<=crcs[slot];saved_rank<=ranks[slot];busy<=0;status<=3;error<=0;chosen<=slot;state<=IDLE;
   end
   IDLE:if(recall && mounted && safe)begin busy<=1;status<=2;saving<=0;request(0,1,H0);end
   else if(save && mounted && safe && user_valid && count!=0)begin
    snap_native<=native_format;slot<=has_saved?!chosen:1'b0;snap_seq<=generation+1'b1;snap_count<=count;snap_bpm<=bpm;snap_original<=original_crc;snap_rank<=key_rank;
    fill_index<=0;busy<=1;status<=2;error<=0;saving<=1;state<=ZERO_HEADER;
    crc<=metacrc(count,bpm,key_rank,original_crc,native_format);data_length<=count+(count<<1);byte_count<=0;phase<=0;event_index<=0;export_address<=0;fetch_wait<=0;body_sector<=0;
   end
   ZERO_HEADER:begin buffer[fill_index]<=0;if(fill_index==511)request(1,slot_base,INVALID_DONE);else fill_index<=fill_index+1'b1;end
   INVALID_DONE:if(block_done)begin if(block_error!=0)failed(1);else begin fill_index<=0;state<=FILL;end end
   FILL:begin
    if(byte_count>=data_length)begin buffer[fill_index]<=0;if(fill_index==511)request(1,slot_base+1+{10'd0,body_sector},DATA_DONE);else fill_index<=fill_index+1'b1;end
    else if(phase==0 && fetch_wait<3)begin
     fetch_wait<=fetch_wait+1'b1;if(fetch_wait==2)event_cache<=export_data;
    end else begin
     buffer[fill_index]<=next_byte;crc<=crcbyte(crc,next_byte);byte_count<=byte_count+1'b1;
     if(phase==2)begin phase<=0;event_index<=event_index+1'b1;export_address<=export_address+1'b1;fetch_wait<=0;end else phase<=phase+1'b1;
     if(fill_index==511)request(1,slot_base+1+{10'd0,body_sector},DATA_DONE);else fill_index<=fill_index+1'b1;
    end
   end
   DATA_DONE:if(block_done)begin
    if(block_error!=0)failed(1);
    else if(byte_count>=data_length)begin wanted_crc<=crc;crc<=metacrc(snap_count,snap_bpm,snap_rank,snap_original,snap_native);byte_count<=0;phase<=0;event_index<=0;invalid_body<=0;body_sector<=0;request(0,slot_base+1,READ_BODY);end
    else begin fill_index<=0;body_sector<=body_sector+1'b1;state<=FILL;end
   end
   FILL_HEADER:begin buffer[fill_index]<=header_byte(fill_index);if(fill_index==511)request(1,slot_base,FINAL_DONE);else fill_index<=fill_index+1'b1;end
   FINAL_DONE:if(block_done)begin if(block_error!=0)failed(1);else request(0,slot_base,VERIFY_HEADER);end
   VERIFY_HEADER:if(block_done)begin
    if(block_error!=0 || !header_valid || version!=(snap_native?2:1) || seq!=snap_seq || h_crc!=wanted_crc || h_count!={2'd0,snap_count} || h_bpm!=snap_bpm || h_rank!={3'd0,snap_rank} || h_original!=snap_original)failed(3);
    else begin has_saved<=1;generation<=snap_seq;saved_count<=snap_count;saved_crc<=snap_original;saved_rank<=snap_rank;chosen<=slot;busy<=0;status<=3;error<=0;state<=IDLE;end
   end
  endcase
 end
endmodule
