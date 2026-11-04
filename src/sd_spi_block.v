`timescale 1ns/1ps
// SDHC (v2, block addressing), SPI mode 0. 390kHz init / 6.25MHz transfer.
// A block completes only after data CRC/read or accepted-data + not-busy/write.
module sd_spi_block #(
 parameter integer SLOW_DIV=64,FAST_DIV=4,POWER_CLOCKS=500000,
 parameter integer INIT_TIMEOUT=150000000,IO_TIMEOUT=25000000,MAX_INIT_RETRIES=2
)(input wire clk,input wire sd_miso,output reg sd_clk=0,sd_cs=1,sd_mosi=1,
 input wire request,write,input wire [31:0] sector,
 output wire [8:0] write_index,input wire [7:0] write_byte,
 output reg read_valid=0,output reg [8:0] read_index=0,output reg [7:0] read_byte=0,
 output reg initialized=0,busy=1,done=0,output reg [3:0] error=0,
 input wire reinitialize,output wire [63:0] diagnostic);
 reg miso_meta=1,miso_sync=1;
 always @(posedge clk)begin miso_meta<=sd_miso;miso_sync<=miso_meta;end
 reg byte_start=0,byte_busy=0,byte_done=0;reg [7:0] byte_tx=8'hff,byte_rx=0,shift_tx=0,shift_rx=0;
 reg [7:0] divider=0;reg [2:0] bit_index=0;
 wire [7:0] half_period=initialized?FAST_DIV:SLOW_DIV;
 always @(posedge clk)begin
  byte_done<=0;
  if(byte_start && !byte_busy)begin byte_busy<=1;divider<=0;bit_index<=0;sd_clk<=0;shift_tx<=byte_tx;shift_rx<=0;sd_mosi<=byte_tx[7];end
  else if(byte_busy)begin
   if(divider==half_period-1'b1)begin
    divider<=0;sd_clk<=~sd_clk;
    if(!sd_clk)shift_rx<={shift_rx[6:0],miso_sync};
    else if(bit_index==7)begin byte_rx<=shift_rx;byte_busy<=0;byte_done<=1;sd_mosi<=1;end
    else begin bit_index<=bit_index+1'b1;shift_tx<={shift_tx[6:0],1'b1};sd_mosi<=shift_tx[6];end
   end else divider<=divider+1'b1;
  end
 end
 localparam POWER=0,CLOCKS=1,CMD_SEND=2,CMD_WAIT=3,EXTRA=4,DISPATCH=5,
  IDLE=6,READ_TOKEN=7,READ_DATA=8,READ_CRC1=9,READ_CRC2=10,
  WRITE_GAP=11,WRITE_TOKEN=12,WRITE_DATA=13,WRITE_CRC1=14,WRITE_CRC2=15,
  WRITE_REPLY=16,WRITE_BUSY=17,TAIL=18,TAIL_WAIT=19,FAILED=20,INIT_GAP=21;
 reg [4:0] state=POWER;reg [31:0] timer=0,power_count=0;
 reg [5:0] command=0;reg [31:0] argument=0,extra=0;
 reg [2:0] command_index=0,extra_left=0;
 reg [7:0] response=8'hff;reg [5:0] response_count=0;
 reg [3:0] init_step=0,clock_bytes=0;reg write_latched=0;
 reg [1:0] retries=0;
 // Stable layout consumed by SDINFO; querying never clocks or writes the card.
 assign diagnostic={sd_cs,miso_sync,initialized,retries,extra,response,command,init_step,state,error};
 reg [1:0] write_prefetch=0;reg [8:0] data_index=0;reg [15:0] crc=0,card_crc=0;
 assign write_index=data_index;
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);integer n;reg [15:0] v;
  begin v=c^{b,8'd0};for(n=0;n<8;n=n+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end
 endfunction
 task issue(input [5:0] cmd,input [31:0] arg,input [2:0] trailing);
  begin command<=cmd;argument<=arg;command_index<=0;response_count<=0;response<=8'hff;extra_left<=trailing;extra<=0;state<=CMD_SEND;end
 endtask
 task issue_init(input [5:0] cmd,input [31:0] arg,input [2:0] trailing);
  begin
   issue(cmd,arg,trailing);
   // Finish the preceding initialization response with eight clocks while
   // deselected, then form a fresh CS boundary for the next command.
   sd_cs<=1;state<=INIT_GAP;
  end
 endtask
 task fail(input [3:0] reason);begin error<=reason;state<=TAIL;end endtask
 task sendbyte(input [7:0] b);begin byte_tx<=b;byte_start<=1;end endtask
 wire can_send=!byte_busy && !byte_start && !byte_done;
 always @(posedge clk)begin
  byte_start<=0;read_valid<=0;done<=0;
  // A timeout must win over a simultaneous command/byte completion.
  if(state!=POWER && state!=IDLE && state!=FAILED && state!=TAIL && state!=TAIL_WAIT &&
     timer==(initialized?IO_TIMEOUT:INIT_TIMEOUT))begin
   error<=initialized?4'd6:4'd7;timer<=0;state<=TAIL;
  end else begin
  if(state!=POWER && state!=IDLE && state!=FAILED && state!=TAIL && state!=TAIL_WAIT)timer<=timer+1'b1;
  case(state)
   POWER:if(power_count==POWER_CLOCKS-1)begin state<=CLOCKS;timer<=0;end else power_count<=power_count+1'b1;
   CLOCKS:begin
    if(can_send)sendbyte(8'hff);
    if(byte_done)begin if(clock_bytes==9)begin sd_cs<=0;init_step<=0;issue(0,0,0);end else clock_bytes<=clock_bytes+1'b1;end
   end
   CMD_SEND:begin
    if(can_send)case(command_index)
     0:sendbyte({2'b01,command});1:sendbyte(argument[31:24]);2:sendbyte(argument[23:16]);
     3:sendbyte(argument[15:8]);4:sendbyte(argument[7:0]);default:sendbyte(command==0?8'h95:command==8?8'h87:8'h01);
    endcase
    if(byte_done)begin if(command_index==5)state<=CMD_WAIT;else command_index<=command_index+1'b1;end
   end
   CMD_WAIT:begin
    if(can_send)sendbyte(8'hff);
    if(byte_done)begin
     if(!byte_rx[7])begin response<=byte_rx;state<=extra_left!=0?EXTRA:DISPATCH;end
     else if(response_count==31)fail(2);else response_count<=response_count+1'b1;
    end
   end
   INIT_GAP:begin
    if(can_send)sendbyte(8'hff);
    if(byte_done)begin sd_cs<=0;state<=CMD_SEND;end
   end
   EXTRA:begin if(can_send)sendbyte(8'hff);if(byte_done)begin extra<={extra[23:0],byte_rx};extra_left<=extra_left-1'b1;if(extra_left==1)state<=DISPATCH;end end
   DISPATCH:if(!initialized)begin
    case(init_step)
     0:if(response==1)begin init_step<=1;issue_init(8,32'h1aa,4);end else fail(1);
     1:if(response==1 && extra[11:0]==12'h1aa)begin init_step<=2;issue_init(55,0,0);end else fail(1);
     2:if(response==1 || response==0)begin init_step<=3;issue_init(41,32'h40000000,0);end else fail(1);
     3:if(response==0)begin init_step<=4;issue_init(58,0,4);end else if(response==1)begin init_step<=2;issue_init(55,0,0);end else fail(1);
     4:if(response==0 && extra[31:30]==2'b11)begin initialized<=1;error<=0;state<=TAIL;end else fail(1);
     default:fail(1);
    endcase
   end else if(response!=0)fail(2);
   else begin timer<=0;data_index<=0;crc<=0;state<=write_latched?WRITE_GAP:READ_TOKEN;end
   IDLE:if(request)begin busy<=1;sd_cs<=0;error<=0;timer<=0;write_latched<=write;issue(write?6'd24:6'd17,sector,0);end
   READ_TOKEN:begin if(can_send)sendbyte(8'hff);if(byte_done)begin if(byte_rx==8'hfe)begin state<=READ_DATA;timer<=0;end else if(byte_rx!=8'hff)fail(3);end end
   READ_DATA:begin if(can_send)sendbyte(8'hff);if(byte_done)begin
    read_valid<=1;read_byte<=byte_rx;read_index<=data_index;crc<=crcbyte(crc,byte_rx);
    if(data_index==511)state<=READ_CRC1;else data_index<=data_index+1'b1;
   end end
   READ_CRC1:begin if(can_send)sendbyte(8'hff);if(byte_done)begin card_crc[15:8]<=byte_rx;state<=READ_CRC2;end end
   READ_CRC2:begin if(can_send)sendbyte(8'hff);if(byte_done)begin if({card_crc[15:8],byte_rx}!=crc)error<=4;state<=TAIL;end end
   WRITE_GAP:begin if(can_send)sendbyte(8'hff);if(byte_done)state<=WRITE_TOKEN;end
   WRITE_TOKEN:begin if(can_send)sendbyte(8'hfe);if(byte_done)begin state<=WRITE_DATA;write_prefetch<=2;end end
   WRITE_DATA:begin if(write_prefetch!=0)write_prefetch<=write_prefetch-1'b1;else if(can_send)sendbyte(write_byte);if(byte_done)begin crc<=crcbyte(crc,byte_tx);if(data_index==511)state<=WRITE_CRC1;else begin data_index<=data_index+1'b1;write_prefetch<=2;end end end
   WRITE_CRC1:begin if(can_send)sendbyte(crc[15:8]);if(byte_done)state<=WRITE_CRC2;end
   WRITE_CRC2:begin if(can_send)sendbyte(crc[7:0]);if(byte_done)begin state<=WRITE_REPLY;response_count<=0;end end
   WRITE_REPLY:begin if(can_send)sendbyte(8'hff);if(byte_done)begin
    if(byte_rx[4:0]==5'b00101)begin state<=WRITE_BUSY;timer<=0;end
    else if(byte_rx!=8'hff || response_count==31)fail(5);else response_count<=response_count+1'b1;
   end end
   WRITE_BUSY:begin if(can_send)sendbyte(8'hff);if(byte_done && byte_rx==8'hff)state<=TAIL;end
   TAIL:if(can_send)begin sd_cs<=1;sendbyte(8'hff);state<=TAIL_WAIT;end
   TAIL_WAIT:if(byte_done)begin busy<=0;done<=1;timer<=0;state<=initialized?IDLE:FAILED;end
   FAILED:begin
    busy<=0;
    // Only an uninitialized card reaches FAILED. No mounted filesystem or
    // data write can be interrupted by either kind of retry.
    if(reinitialize || retries<MAX_INIT_RETRIES)begin
     retries<=reinitialize?2'd0:retries+1'b1;error<=0;busy<=1;timer<=0;power_count<=0;
     clock_bytes<=0;init_step<=0;command<=0;argument<=0;response<=8'hff;extra<=0;
     sd_cs<=1;state<=POWER;
    end
   end
  endcase
  end
 end
endmodule
