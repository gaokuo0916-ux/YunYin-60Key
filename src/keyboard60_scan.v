`timescale 1ns/1ps
// MIXED_5_7=1: nearest first, mixed5(C..E), mixed7(F..B), repeat five times.
// Legacy all-white/all-black layout remains available only when MIXED_5_7=0.
// Each HC165 shifts H,G,F,E,D,C,B,A. W uses A..G, B uses A..E.
// Controls use A..H. Change constants here only after checking the actual PCB.
module keyboard60_scan #(parameter integer PERIOD_CYCLES=12500,HALF_CYCLES=50,
 PRESS_SCANS=3,RELEASE_SCANS=9,SCAN_BITS=88,BLACK_FIRST=0,MIXED_5_7=0)(input wire clk,data,
 output reg load_n=1,key_clk=0,output reg [59:0] keys=0,
 output reg [7:0] controls=0,output reg valid=0);
 reg meta=1,sync=1;always @(posedge clk)begin meta<=data;sync<=meta;end
 reg [15:0] period=0;reg [7:0] delay_count=0;
 reg [1:0] state=0;reg [6:0] index=0;reg [87:0] shifted={88{1'b1}};
 reg [87:0] raw={88{1'b1}};reg scan_done=0;
 reg [3:0] debounce[0:67];integer i;initial for(i=0;i<68;i=i+1)debounce[i]=0;
 function integer key_bit(input integer key);
  integer oct,pc,slot;begin oct=key/12;pc=key%12;
   case(pc)
    0:slot=0;2:slot=1;4:slot=2;5:slot=3;7:slot=4;9:slot=5;11:slot=6;
    1:slot=8;3:slot=9;6:slot=10;8:slot=11;default:slot=12;
   endcase
   // Both board types contain one full 8-bit HC165, irrespective of key count.
   // This is a compile-time layout choice, not an extra run-time input mux.
   if(MIXED_5_7)key_bit=oct*16+(pc<5?7-pc:20-pc);
   else key_bit=oct*16+(slot<8?(BLACK_FIRST?15:7)-slot:(BLACK_FIRST?7:15)-(slot-8));
  end
 endfunction
 wire [67:0] stable={controls,keys};wire [67:0] pressed;
 genvar k;generate for(k=0;k<60;k=k+1)begin:decode
  assign pressed[k]=~raw[key_bit(k)];
 end for(k=0;k<8;k=k+1)begin:control_decode
  assign pressed[60+k]=SCAN_BITS==88?~raw[87-k]:1'b0;
 end endgenerate
 always @(posedge clk)begin
  valid<=0;scan_done<=0;
  if(period==PERIOD_CYCLES-1)period<=0;else period<=period+1'b1;
  case(state)
   0:if(period==0)begin load_n<=0;key_clk<=0;delay_count<=0;index<=0;state<=1;end
   1:if(delay_count==HALF_CYCLES-1)begin load_n<=1;delay_count<=0;state<=2;end else delay_count<=delay_count+1'b1;
   2:if(delay_count==HALF_CYCLES-1)begin shifted[index]<=sync;key_clk<=1;delay_count<=0;state<=3;end else delay_count<=delay_count+1'b1;
   3:if(delay_count==HALF_CYCLES-1)begin
    key_clk<=0;delay_count<=0;
    if(index==SCAN_BITS-1)begin raw<=shifted;scan_done<=1;state<=0;end
    else begin index<=index+1'b1;state<=2;end
   end else delay_count<=delay_count+1'b1;
  endcase
  if(scan_done)begin
   valid<=1;
   for(i=0;i<68;i=i+1)begin
    if(pressed[i]==stable[i])debounce[i]<=0;
    else if(debounce[i]==(stable[i]?RELEASE_SCANS-1:PRESS_SCANS-1))begin
     if(i<60)keys[i]<=pressed[i];else controls[i-60]<=pressed[i];debounce[i]<=0;
    end else debounce[i]<=debounce[i]+1'b1;
   end
  end
 end
endmodule
