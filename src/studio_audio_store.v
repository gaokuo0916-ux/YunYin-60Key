`timescale 1ns/1ps
// Up to 120 seconds of final PCM, streamed through a 16384-sample capture ring.
// Two file regions retain the previous complete take until the new one commits.
module studio_audio_store(input wire clk,mounted,allowed,
 input wire start,stop,input wire [6:0] seconds,
 output reg busy=0,output reg [2:0] status=0,output reg [3:0] error=0,
 output reg [31:0] generation=0,saved_samples=0,output reg [15:0] saved_crc=0,
 output reg capture_arm=0,capture_stop=0,capture_abort=0,output reg [31:0] capture_limit=0,consumed=0,
 input wire [2:0] capture_state,input wire [31:0] produced,input wire [15:0] capture_crc,input wire overflow,
 output reg [15:0] capture_address=0,input wire [15:0] capture_data,
 input wire client_request,input wire [31:0] client_offset,input wire [7:0] client_index,
 output reg client_ready=0,output reg [3:0] client_error=0,output reg [15:0] client_data=0,
 output reg block_request=0,block_write=0,output reg [19:0] block_sector=0,
 input wire block_done,input wire [3:0] block_error,
 input wire read_valid,input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire [8:0] write_index,output reg [7:0] write_byte=0,
 // Directory manager reserves a previously empty/deleted slot before arming.
 input wire managed_write,input wire [19:0] managed_base,input wire [31:0] managed_generation,
 output reg managed_done=0,managed_ok=0,
 input wire managed_read,input wire [19:0] managed_read_base,input wire [31:0] managed_read_samples);
 localparam WAIT=0,H0=1,H1=2,PICK=3,READY=4,ZERO=5,ZERO_DONE=6,ARMED=7,RUN=8,FILL=9,WRITE_DONE=10,
  VERIFY=11,HEADER=12,PATCH=13,FINAL_DONE=14,FINAL_CHECK=15,CACHE=16;
 wire managed_write_enable=(managed_write===1'b1),managed_read_enable=(managed_read===1'b1);
 reg external_take=0;reg [19:0] external_base=0,cache_base=0;
 reg [4:0] state=WAIT;reg has_saved=0,chosen=0,slot=0,cache_valid=0,abort_pending=0;
 reg [15:0] buffer[0:255] /* synthesis syn_ramstyle = "block_ram" */;
 reg [7:0] low_byte=0;reg [8:0] fill_index=0;reg [8:0] block_samples=0;reg [2:0] fetch_wait=0;
 reg [14:0] data_sector=0;reg [23:0] cache_page=0;
 reg [15:0] verify_crc=16'hffff,header_crc=16'hffff;
 reg [31:0] snap_seq=0,snap_samples=0;reg [15:0] snap_crc=0;
 reg [1:0] valid=0;reg [31:0] seqs[0:1],counts[0:1];reg [15:0] crcs[0:1];
 reg [63:0] h_magic=0;reg [31:0] h_version=0,h_seq=0,h_count=0,h_inverse=0,h_rate=0,h_div=0;
 reg [15:0] h_crc=0,h_header_crc=0,h_actual_crc=16'hffff;reg [7:0] h_flag=0;
 wire header_valid=h_magic=="YY24AUDI" && h_version==1 && (h_seq^h_inverse)==32'hffffffff && h_count!=0 && h_count<=5859375 &&
  h_rate==50000000 && h_div==1024 && h_flag==8'ha5 && h_actual_crc==h_header_crc;
 wire [31:0] available=produced-consumed;
 wire [19:0] slot_base=external_take?external_base:slot?20'd32768:20'd256;
 wire [19:0] chosen_base=managed_read_enable?managed_read_base:chosen?20'd32768:20'd256;
 wire [31:0] read_samples=managed_read_enable?managed_read_samples:saved_samples;
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);integer n;reg [15:0] v;
  begin v=c^{b,8'd0};for(n=0;n<8;n=n+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end
 endfunction
 function [31:0] sample_limit(input [6:0] sec);reg [31:0] x;begin x={25'd0,sec};sample_limit=(x<<15)+(x<<13)+(x<<12)+(x<<11)+(x<<10)+(x<<9)+(x<<7)+(x<<5)+(x<<4)+(x<<3)+(x<<2)+(x>>3);end endfunction
 function [7:0] header_byte(input [8:0] ix);begin
  case(ix)
   0:header_byte="Y";1:header_byte="Y";2:header_byte="2";3:header_byte="4";4:header_byte="A";5:header_byte="U";6:header_byte="D";7:header_byte="I";
   8:header_byte=1;12,13,14,15:header_byte=snap_seq[ix[1:0]*8+:8];16,17,18,19:header_byte=snap_samples[ix[1:0]*8+:8];
   20:header_byte=snap_crc[7:0];21:header_byte=snap_crc[15:8];24,25,26,27:header_byte=~snap_seq[ix[1:0]*8+:8];
   28:header_byte=8'h80;29:header_byte=8'hf0;30:header_byte=8'hfa;31:header_byte=2; // 50,000,000
   33:header_byte=4;36:header_byte=8'ha5;default:header_byte=0;
  endcase end
 endfunction
 reg buffer_we;reg [7:0] buffer_address;reg [15:0] buffer_value,buffer_word=0;
 wire [7:0] buffer_read_address=state==READY?client_index:write_index[8:1];
 always @(*)begin
  buffer_we=0;buffer_address=fill_index[7:0];buffer_value=0;
  if(read_valid && read_index[0])begin buffer_we=1;buffer_address=read_index[8:1];buffer_value={read_byte,low_byte};end
  case(state)
   ZERO:begin buffer_we=1;buffer_value=0;end
   FILL:if(fill_index>=block_samples)begin buffer_we=1;buffer_value=0;end
        else if(fetch_wait==3)begin buffer_we=1;buffer_value=capture_data;end
   HEADER:begin buffer_we=1;buffer_value={header_byte({fill_index[7:0],1'b1}),header_byte({fill_index[7:0],1'b0})};end
   PATCH:begin buffer_we=1;buffer_address=11;buffer_value=header_crc;end
  endcase
 end
 always @(posedge clk)begin
  if(buffer_we)buffer[buffer_address]<=buffer_value;
  buffer_word<=buffer[buffer_read_address];
 end
 task request(input wr,input [19:0] address,input [4:0] next);begin block_write<=wr;block_sector<=address;block_request<=1;state<=next;end endtask
 task fail(input [3:0] code);begin error<=code;status<=4;busy<=0;if(external_take)begin managed_done<=1;managed_ok<=0;end abort_pending<=1;state<=READY;cache_valid<=0;end endtask
 always @(posedge clk)begin
  write_byte<=write_index[0]?buffer_word[15:8]:buffer_word[7:0];
  client_data<=buffer_word;
  managed_done<=0;block_request<=0;capture_arm<=0;capture_stop<=0;capture_abort<=0;client_ready<=0;
  if(abort_pending)begin capture_abort<=1;abort_pending<=0;end
  if(stop && busy)capture_stop<=1;
  if(read_valid)begin
   low_byte<=read_byte;
   if(state==H0 || state==H1 || state==FINAL_CHECK)begin
    if(read_index<37 && read_index!=22 && read_index!=23)h_actual_crc<=crcbyte(h_actual_crc,read_byte);
    if(read_index<8)h_magic<={h_magic[55:0],read_byte};
    if(read_index>=8 && read_index<12)h_version[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=12 && read_index<16)h_seq[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=16 && read_index<20)h_count[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=20 && read_index<22)h_crc[read_index[0]*8+:8]<=read_byte;
    if(read_index>=22 && read_index<24)h_header_crc[read_index[0]*8+:8]<=read_byte;
    if(read_index>=24 && read_index<28)h_inverse[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=28 && read_index<32)h_rate[read_index[1:0]*8+:8]<=read_byte;
    if(read_index>=32 && read_index<36)h_div[read_index[1:0]*8+:8]<=read_byte;
    if(read_index==36)h_flag<=read_byte;
   end
   if(state==VERIFY && {1'b0,read_index} < (block_samples<<1))verify_crc<=crcbyte(verify_crc,read_byte);
  end
  case(state)
   WAIT:if(mounted && allowed)begin busy<=1;h_actual_crc<=16'hffff;request(0,256,H0);end
   H0,H1:if(block_done)begin
    valid[state==H1]<=block_error==0 && header_valid;seqs[state==H1]<=h_seq;counts[state==H1]<=h_count;crcs[state==H1]<=h_crc;
    if(state==H0)begin h_actual_crc<=16'hffff;request(0,32768,H1);end else state<=PICK;
   end
   PICK:begin
    busy<=0;state<=READY;
    if(valid!=0)begin
     chosen<=valid[1] && (!valid[0] || $signed(seqs[1]-seqs[0])>0);has_saved<=1;status<=3;
     generation<=seqs[valid[1] && (!valid[0] || $signed(seqs[1]-seqs[0])>0)];
     saved_samples<=counts[valid[1] && (!valid[0] || $signed(seqs[1]-seqs[0])>0)];
     saved_crc<=crcs[valid[1] && (!valid[0] || $signed(seqs[1]-seqs[0])>0)];
    end
   end
   READY:if(start && mounted && allowed && seconds>=1 && seconds<=120)begin
    slot<=has_saved?!chosen:1'b0;
    external_take<=managed_write_enable;external_base<=managed_base;
    snap_seq<=managed_write_enable?managed_generation:generation+1'b1;capture_limit<=sample_limit(seconds);
    busy<=1;status<=5;error<=0;fill_index<=0;consumed<=0;verify_crc<=16'hffff;data_sector<=0;cache_valid<=0;state<=ZERO;
   end else if(client_request)begin
    client_error<=0;
    if((!has_saved && !managed_read_enable) || client_offset>=read_samples || client_offset[3:0]!=0)begin client_error<=3;client_ready<=1;end
    else if(cache_valid && cache_page==client_offset[31:8] && cache_base==chosen_base)client_ready<=1;
    else begin cache_page<=client_offset[31:8];cache_base<=chosen_base;cache_valid<=0;busy<=1;request(0,chosen_base+1+client_offset[23:8],CACHE);end
   end
   ZERO:begin if(fill_index==255)request(1,slot_base,ZERO_DONE);else fill_index<=fill_index+1'b1;end
   ZERO_DONE:if(block_done)begin if(block_error!=0)fail(1);else begin capture_arm<=1;status<=1;fetch_wait<=0;state<=ARMED;end end
   // Allow the capture unit to accept arm before interpreting its state.
   // Otherwise a previous cancelled/failed take's state=4 aborts the new take.
   ARMED:begin
    if(fetch_wait<2)fetch_wait<=fetch_wait+1'b1;
    else if(capture_state==2)begin status<=2;state<=RUN;end
    else if(capture_state==4)fail(4);
   end
   RUN:begin
    if(capture_state==4)fail(overflow?4'd5:4'd4);
    else if(produced-consumed>=256 || (capture_state==3 && produced!=consumed))begin
     block_samples<=available>=256?9'd256:available[8:0];
     fill_index<=0;fetch_wait<=0;capture_address<=consumed[15:0];state<=FILL;
    end else if(capture_state==3 && produced==consumed)begin
     status<=6;
     if(produced==0 || verify_crc!=capture_crc)fail(2);
     else begin snap_samples<=produced;snap_crc<=capture_crc;fill_index<=0;header_crc<=16'hffff;state<=HEADER;end
    end
   end
   FILL:if(fill_index>=block_samples)begin
    if(fill_index==255)request(1,slot_base+1+{1'b0,data_sector},WRITE_DONE);else fill_index<=fill_index+1'b1;
   end else if(fetch_wait<3)fetch_wait<=fetch_wait+1'b1;
   else begin
    capture_address<=capture_address+1'b1;fetch_wait<=0;
    if(fill_index==255)request(1,slot_base+1+{1'b0,data_sector},WRITE_DONE);else fill_index<=fill_index+1'b1;
   end
   WRITE_DONE:if(block_done)begin if(block_error!=0)fail(1);else request(0,slot_base+1+{1'b0,data_sector},VERIFY);end
   VERIFY:if(block_done)begin
    if(block_error!=0)fail(1);
    else begin consumed<=consumed+{23'd0,block_samples};data_sector<=data_sector+1'b1;state<=RUN;end
   end
   HEADER:begin
    if(fill_index<18 && fill_index!=11)header_crc<=crcbyte(crcbyte(header_crc,header_byte({fill_index[7:0],1'b0})),header_byte({fill_index[7:0],1'b1}));
    else if(fill_index==18)header_crc<=crcbyte(header_crc,header_byte(36));
    if(fill_index==255)state<=PATCH;else fill_index<=fill_index+1'b1;
   end
   PATCH:begin request(1,slot_base,FINAL_DONE);end
   FINAL_DONE:if(block_done)begin if(block_error!=0)fail(1);else begin h_actual_crc<=16'hffff;request(0,slot_base,FINAL_CHECK);end end
   FINAL_CHECK:if(block_done)begin
    if(block_error!=0 || !header_valid || h_count!=snap_samples || h_crc!=snap_crc || h_seq!=snap_seq)fail(3);
    else begin
     if(external_take)begin managed_done<=1;managed_ok<=1;status<=has_saved?3'd3:3'd0;end
     else begin has_saved<=1;chosen<=slot;generation<=snap_seq;saved_samples<=snap_samples;saved_crc<=snap_crc;status<=3;end
     error<=0;busy<=0;state<=READY;
    end
   end
   CACHE:if(block_done)begin client_error<=block_error;client_ready<=1;cache_valid<=block_error==0;busy<=0;state<=READY;end
  endcase
 end
endmodule

