`timescale 1ns/1ps
// A bounded message FIFO decouples command execution from the slow UART TX.
module bluetooth_reply_studio(input wire clk,input wire request,
 input wire [3:0] code,input wire [7:0] info,output wire ready,
 output reg [7:0] tx_data=0,output reg tx_start=0,input wire tx_busy,output wire idle);
 reg [11:0] fifo[0:15];
 reg [3:0] wr=0,rd=0;
 reg [4:0] count=0,position=0;
 reg active=0;
 reg [3:0] current=0;
 reg [7:0] details=0;
 wire push=request && ready;
 wire pop=!active && count!=0;
 assign ready=count<16;
 assign idle=count==0 && !active && !request && !tx_start;
 reg [7:0] character;
 reg [4:0] last;
 function [7:0] hex_digit(input [3:0] n);
  hex_digit=n<10?8'd48+n:8'd55+n;
 endfunction
 always @(*) begin
  character=10;last=2;
  case(current)
   0:begin last=4;case(position) 0:character="P";1:character="O";2:character="N";
      3:character="G";default:character=10;endcase end
   1:begin last=5;case(position) 0:character="R";1:character="E";2:character="A";
      3:character="D";4:character="Y";default:character=10;endcase end
   2:begin last=5;case(position) 0:character="S";1:character="A";2:character="V";
      3:character="E";4:character="D";default:character=10;endcase end
   3:case(position) 0:character="O";1:character="K";default:character=10;endcase
   4:begin last=5;case(position) 0,1,2:character="R";3:character=" ";
      4:character=hex_digit(details[7:4]);default:character=10;endcase
      if(position==0) character="E";end
   5:begin last=15;case(position)
      0:character="S";4:character="V";8:character="U";12:character="E";
      1,5,9,13:character="=";3,7,11:character=" ";
      2:character=details[0]?"1":"0";6:character=details[1]?"1":"0";
      10:character=details[2]?"1":"0";14:character=hex_digit(details[7:4]);
      default:character=10;endcase end
   6:begin last=8;case(position)
      0:character="C";1:character="A";2:character="P";3:character=" ";
      4:character="8";5:character="1";6:character="9";7:character="2";
      default:character=10;endcase end
   default:begin character=10;last=0;end
  endcase
  // Also decode when the first message activates after power-up. The first
  // PONG has the same code/position/info as the initial idle register values.
  if(!active) begin character=0;last=0;end
 end
 always @(posedge clk) begin
  tx_start<=0;
  if(push) begin fifo[wr]<={code,info};wr<=wr+1'b1;end
  if(pop) begin {current,details}<=fifo[rd];rd<=rd+1'b1;active<=1;position<=0;end
  case({push,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
  if(active && !tx_busy && !tx_start) begin
   tx_data<=character;tx_start<=1;
   if(position==last) active<=0;else position<=position+1'b1;
  end
 end
endmodule
