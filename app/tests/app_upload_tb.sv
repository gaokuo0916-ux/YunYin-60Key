`timescale 1ns/1ps
// App-generated maximum-capacity transaction through real 50MHz / 38400 UART.
module app_upload_tb;
 reg clk=0;always #10 clk=~clk;
 reg rx=1;wire tx;wire [7:0] data,out_data;wire valid,framing_error,tx_start,tx_busy;
 wire reply_valid,reply_ready;wire [3:0] code,error;wire [7:0] info;
 bluetooth_uart #(.BAUD(38400)) uart(clk,rx,data,valid,framing_error,out_data,tx_start,tx,tx_busy);
 bluetooth_reply replies(clk,reply_valid,code,info,reply_ready,out_data,tx_start,tx_busy);
 wire selected,loaded,uploading,activity,ready,last_event,start,pause,stop,changed,bank;
 wire [15:0] received_bcd,total_bcd,stored_bcd;wire [11:0] bpm_bcd;
 reg [12:0] address=0;wire [2:0] degree;wire [15:0] rest_ms;
 bluetooth_score score(clk,data,valid,framing_error,reply_ready,reply_valid,code,info,
  2'd0,1'b0,1'b0,1'b0,selected,loaded,uploading,error,activity,
  received_bcd,total_bcd,stored_bcd,bpm_bcd,address,degree,rest_ms,ready,last_event,
  start,pause,stop,changed,bank);
 wire [7:0] response_byte;wire response_valid,response_error;
 bluetooth_uart #(.BAUD(38400)) monitor(clk,tx,response_byte,response_valid,response_error,8'd0,1'b0,,);
 string response="",last_response="";integer pongs=0,readies=0,saved=0,capacities=0;
 always @(posedge clk) begin
  if(framing_error || response_error) $fatal(1,"UART framing error");
  if(response_valid) begin
   if(response_byte==10) begin
    last_response=response;
    if(response=="PONG")pongs++;
    if(response=="CAP 8192")capacities++;
    if(response=="READY")readies++;
    if(response=="SAVED")saved++;
    if(response.len()>=3 && response.substr(0,2)=="ERR")$fatal(1,"Protocol rejected app transaction: %s",response);
    response="";
   end else response={response,response_byte};
  end
 end
 task automatic send_byte(input byte value);
  @(negedge clk);rx=0;repeat(1302)@(negedge clk);
  for(integer b=0;b<8;b++)begin rx=value[b];repeat(1302)@(negedge clk);end
  rx=1;repeat(1302)@(negedge clk);
 endtask
 initial begin
  integer f,ch;
  repeat(100)@(negedge clk);
  f=$fopen("app_8192_transaction.txt","r");if(!f)$fatal(1,"Missing Java-generated app transaction");
  while(!$feof(f))begin ch=$fgetc(f);if(ch>=0)send_byte(ch[7:0]);end
  $fclose(f);
  wait(last_response=="S=0 V=1 U=0 E=0");
  if(pongs!=1 || capacities!=1 || readies!=1 || saved!=1 || !loaded || uploading || error!=0 || stored_bcd!=16'h8192)
   $fatal(1,"App transaction did not save all 8192 events");
  for(integer i=0;i<8192;i++)begin
   @(negedge clk);address=i;repeat(3)@(negedge clk);
   if(!ready || degree!=i%8 || rest_ms!=(i%64+1)*125 || last_event!=(i==8191))
    $fatal(1,"Incorrect event RAM at %0d",i);
  end
  $display("PASS app_upload_rtl: actual Java uploader transaction, 8192 events, real 50MHz/38400 8N1 RX/TX, CAP/PONG/READY/SAVED/STATUS, all RAM notes and durations verified");
  $finish;
 end
 initial begin #(64'd60000000000);$fatal(1,"App upload timeout");end
endmodule
