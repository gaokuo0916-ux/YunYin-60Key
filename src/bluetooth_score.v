`timescale 1ns/1ps
// Runtime note events only. A second RAM bank protects the committed song.
// CRC16-CCITT-FALSE: header count/bpm LE16; each index LE16, degree, units.
module bluetooth_score #(
 parameter integer TIMEOUT_CLOCKS=1500000000,
 parameter integer ACTIVITY_CLOCKS=150000000
)(input wire clk,input wire [7:0] rx_data,input wire rx_valid,rx_error,
 input wire reply_ready,output reg reply_valid=0,
 output reg [3:0] reply_code=0,output reg [7:0] reply_info=0,
 input wire [1:0] ui_source,input wire ui_start,ui_pause,ui_stop,
 output reg selected_user=0,user_valid=0,uploading=0,
 output reg [3:0] error_code=0,output wire activity,
 output reg [15:0] received_bcd=0,total_bcd=0,stored_bcd=0,
 output reg [11:0] bpm_bcd=12'h120,
 input wire [12:0] read_address,output wire [2:0] degree,
 output wire [15:0] rest_ms,output wire score_ready,last_event,
 output reg start=0,pause=0,stop=0,source_changed=0,
 output reg active_bank=0);
 wire line_valid,line_error;
 wire [47:0] command;
 wire [63:0] args;
 wire [2:0] argc;
 wire [15:0] a=args[15:0],b=args[31:16],c=args[47:32];
 wire can_reply=reply_ready && !reply_valid;
 bluetooth_command_rx parser(clk,rx_data,rx_valid,rx_error,
   line_valid,line_error,command,args,argc);
 // Two 8192-event banks; writes cannot overwrite the committed song.
 reg [18:0] events[0:16383] /* synthesis syn_ramstyle = "block_ram" */;
 reg [18:0] read_event=0,write_event=0;
 reg [12:0] read_tag=0;
 reg read_bank=0,write_enable=0;
 reg [13:0] write_address=0;
 always @(posedge clk) begin
  read_event<=events[{active_bank,read_address}];
  read_tag<=read_address;read_bank<=active_bank;
  if(write_enable) events[write_address]<=write_event;
 end
 assign degree=read_event[18:16];
 assign rest_ms=read_event[15:0];
 assign score_ready=user_valid && read_bank==active_bank && read_tag==read_address;
 reg [13:0] stored_count=0,expected_count=0,received_count=0;
 assign last_event={1'b0,read_address}==stored_count-1'b1;
 reg staging_bank=1;
 reg [8:0] staging_bpm=120;
 reg [11:0] staging_bpm_bcd=12'h120;
 reg [31:0] timeout_count=0,activity_count=0;
 assign activity=activity_count!=0;
 // Long operations run serially in a few microseconds, away from audio logic.
 localparam IDLE=0,DIVIDE=1,COUNT_BCD=2,TEMPO_BCD=3,BEGIN_FINISH=4,NOTE_FINISH=5;
 reg [2:0] exec_state=IDLE;
 reg [13:0] dividend=0;
 reg [9:0] quotient=0,quarter_ms=125;
 reg [13:0] decimal_work=0;
 reg [15:0] decimal_bcd=0;
 reg [6:0] units_left=0;
 reg [2:0] pending_degree=0;
 reg [15:0] duration_sum=0;
 reg [15:0] crc=16'hffff;
 reg [31:0] crc_bytes=0;
 reg [5:0] crc_bit=0;
 reg crc_busy=0,deferred_error=0;
 wire crc_mix=crc[15]^crc_bytes[7];
 function [15:0] bcd_increment(input [15:0] value);
  begin
   bcd_increment=value;
   if(value[3:0]!=9) bcd_increment[3:0]=value[3:0]+1'b1;
   else begin bcd_increment[3:0]=0;
    if(value[7:4]!=9) bcd_increment[7:4]=value[7:4]+1'b1;
    else begin bcd_increment[7:4]=0;
     if(value[11:8]!=9) bcd_increment[11:8]=value[11:8]+1'b1;
     else begin bcd_increment[11:8]=0;bcd_increment[15:12]=value[15:12]+1'b1;end
    end
   end
  end
 endfunction
 task send_reply(input [3:0] code,input [3:0] err);
  begin reply_valid<=1;reply_code<=code;
   reply_info<={err,1'b0,uploading,user_valid,selected_user};end
 endtask
 task fail_upload(input [3:0] err);
  begin
   uploading<=0;exec_state<=IDLE;crc_busy<=0;error_code<=err;
   if(can_reply) send_reply(4,err);else deferred_error<=1;
  end
 endtask
 always @(posedge clk) begin
  // Hold a reply until the downstream queue accepts it; never overwrite one.
  if(reply_valid && reply_ready) reply_valid<=0;
  write_enable<=0;start<=0;pause<=0;stop<=0;source_changed<=0;
  if(rx_valid || rx_error) activity_count<=ACTIVITY_CLOCKS;
  else if(activity_count!=0) activity_count<=activity_count-1'b1;
  if(!uploading || rx_valid) timeout_count<=0;
  else if(timeout_count<TIMEOUT_CLOCKS) timeout_count<=timeout_count+1'b1;
  if(deferred_error && can_reply && !line_valid && exec_state==IDLE) begin
   send_reply(4,error_code);deferred_error<=0;
  end
  if(crc_busy) begin
   crc<={crc[14:0],1'b0}^(crc_mix?16'h1021:16'd0);
   if(crc_bit[2:0]==7) crc_bytes<={8'd0,crc_bytes[31:8]};
   else crc_bytes[7:0]<={crc_bytes[6:0],1'b0};
   if(crc_bit==31) crc_busy<=0;else crc_bit<=crc_bit+1'b1;
  end
  case(exec_state)
   DIVIDE:if(dividend>={5'd0,staging_bpm}) begin
     dividend<=dividend-{5'd0,staging_bpm};quotient<=quotient+1'b1;
    end else begin
     quarter_ms<=quotient;decimal_work<=expected_count;decimal_bcd<=0;exec_state<=COUNT_BCD;
    end
   COUNT_BCD,TEMPO_BCD:begin
    if(decimal_work>=1000) begin decimal_work<=decimal_work-1000;decimal_bcd[15:12]<=decimal_bcd[15:12]+1'b1;end
    else if(decimal_work>=100) begin decimal_work<=decimal_work-100;decimal_bcd[11:8]<=decimal_bcd[11:8]+1'b1;end
    else if(decimal_work>=10) begin decimal_work<=decimal_work-10;decimal_bcd[7:4]<=decimal_bcd[7:4]+1'b1;end
    else if(exec_state==COUNT_BCD) begin
     total_bcd<={decimal_bcd[15:4],decimal_work[3:0]};
     decimal_work<={5'd0,staging_bpm};decimal_bcd<=0;exec_state<=TEMPO_BCD;
    end else begin
     staging_bpm_bcd<={decimal_bcd[11:4],decimal_work[3:0]};exec_state<=BEGIN_FINISH;
    end
   end
   BEGIN_FINISH:if(!crc_busy && can_reply) begin send_reply(1,0);exec_state<=IDLE;end
   NOTE_FINISH:if(units_left!=0) begin
     duration_sum<=duration_sum+{6'd0,quarter_ms};units_left<=units_left-1'b1;
    end else if(!crc_busy) begin
     write_enable<=1;write_address<={staging_bank,received_count[12:0]};
     write_event<={pending_degree,duration_sum};
     received_count<=received_count+1'b1;received_bcd<=bcd_increment(received_bcd);exec_state<=IDLE;
    end
  endcase
  // Touch controls remain responsive during reception of the inactive RAM bank.
  if(ui_source==1) begin
   if(selected_user) begin selected_user<=0;source_changed<=1;end
  end else if(ui_source==2) begin
   if(user_valid) begin
    if(!selected_user) begin selected_user<=1;source_changed<=1;end
   end else error_code<=8;
  end
  if(ui_start) start<=1;
  if(ui_pause) pause<=1;
  if(ui_stop) stop<=1;
  if(line_valid) begin
   if(line_error) fail_upload(1);
   else if(command=="FEAT" || command=="MAPGET" || command=="MAP" || command=="STATE" || command=="RARM" || command=="RSTOP" || command=="RINFO" || command=="RGET" || command=="CINFO" || command=="STORE" || command=="RECALL" || command=="CHECK" || command=="ALARM" || command=="ALSTOP" || command=="ALINFO" || command=="ALGET") begin end
   else if(exec_state!=IDLE) fail_upload(3);
   else if(!can_reply && command!="NOTE") begin error_code<=9;deferred_error<=1;end
   else case(command)
    "PING":if(argc==0) send_reply(0,error_code);else fail_upload(1);
    "CAP":if(argc==0) send_reply(6,error_code);else fail_upload(1);
    "STATUS":if(argc==0) send_reply(5,error_code);else fail_upload(1);
    "BEGIN":if(argc!=2 || a==0 || a>8192 || b<20 || b>300) fail_upload(2);
     else begin
      uploading<=1;received_count<=0;received_bcd<=0;expected_count<=a[13:0];
      staging_bank<=~active_bank;staging_bpm<=b[8:0];error_code<=0;
      dividend<=15000;quotient<=0;exec_state<=DIVIDE;
      crc<=16'hffff;crc_bytes<={b,a};crc_bit<=0;crc_busy<=1;
     end
    "NOTE":if(!uploading) fail_upload(3);
     else if(argc!=3 || b>7 || c==0 || c>64) fail_upload(2);
     else if(a!={2'd0,received_count} || received_count>=expected_count) fail_upload(4);
     else begin
      pending_degree<=b[2:0];units_left<=c[6:0];duration_sum<=0;exec_state<=NOTE_FINISH;
      crc_bytes<={c[7:0],b[7:0],a};crc_bit<=0;crc_busy<=1;
     end
    "END":if(argc!=1 || !uploading || received_count!=expected_count) fail_upload(4);
     else if(a!=crc) fail_upload(5);
     else begin
      active_bank<=staging_bank;stored_count<=expected_count;stored_bcd<=received_bcd;
      bpm_bcd<=staging_bpm_bcd;user_valid<=1;uploading<=0;error_code<=0;send_reply(2,0);
      if(selected_user) begin source_changed<=1;stop<=1;end
     end
    "ABORT":if(argc!=0) fail_upload(1);
     else begin uploading<=0;crc_busy<=0;error_code<=0;send_reply(3,0);end
    "ROM":if(argc!=0) fail_upload(1);
     else begin
      if(selected_user) begin selected_user<=0;source_changed<=1;end
      send_reply(3,error_code);
     end
    "USER":if(argc!=0) fail_upload(1);
     else if(!user_valid) begin error_code<=8;send_reply(4,8);end
     else begin
      if(!selected_user) begin selected_user<=1;source_changed<=1;end
      send_reply(3,error_code);
     end
    "START":if(argc!=0) fail_upload(1);else begin start<=1;send_reply(3,error_code);end
    "PAUSE":if(argc!=0) fail_upload(1);else begin pause<=1;send_reply(3,error_code);end
    "STOP":if(argc!=0) fail_upload(1);else begin stop<=1;send_reply(3,error_code);end
    default:fail_upload(1);
   endcase
  end
  if(uploading && timeout_count==TIMEOUT_CLOCKS-1 && !rx_valid) fail_upload(6);
  if(rx_error) fail_upload(7);
 end
endmodule
