`timescale 1ns/1ps
// Bounded ASCII lines: uppercase keyword (<=6), up to four unsigned arguments.
// CRLF and LF accepted. A faulty/overlong line is discarded up to the next LF.
module bluetooth_command_rx(input wire clk,input wire [7:0] data,
 input wire valid,framing_error,
 output reg command_valid=0,command_error=0,
 output reg [47:0] command=0,output reg [63:0] arguments=0,
 output reg [2:0] argument_count=0);
 reg [47:0] keyword=0;
 reg [63:0] args=0;
 reg [15:0] number=0;
 reg [7:0] length=0;
 reg [2:0] letters=0,nargs=0;
 reg args_mode=0,digits=0,bad=0;
 wire space=(data==8'd32 || data==8'd9);
 wire decimal_digit=(data>=8'd48 && data<=8'd57);
 wire overflow=(number>16'd6553 || (number==16'd6553 && data>8'd53));
 always @(posedge clk) begin
  command_valid<=0;command_error<=0;
  if(framing_error) bad<=1;
  else if(valid) begin
   if(data==10) begin
    if(length!=0 || bad) begin
     command<=keyword;arguments<=args;
     if(digits) case(nargs)
      0:arguments[15:0]<=number;1:arguments[31:16]<=number;
      2:arguments[47:32]<=number;3:arguments[63:48]<=number;
     endcase
     argument_count<=nargs+(digits?3'd1:3'd0);
     command_valid<=1;command_error<=bad || letters==0 || (digits && nargs>=4);
    end
    keyword<=0;args<=0;number<=0;length<=0;letters<=0;nargs<=0;
    args_mode<=0;digits<=0;bad<=0;
   end else if(data!=13) begin
    if(length<128) length<=length+1'b1;else bad<=1;
    if(!bad) begin
     if(!args_mode) begin
      if(space) begin if(letters!=0) args_mode<=1;end
      else if(data>=65 && data<=90 && letters<6) begin
       keyword<={keyword[39:0],data};letters<=letters+1'b1;
      end else bad<=1;
     end else if(space) begin
      if(digits) begin
       case(nargs)
        0:args[15:0]<=number;1:args[31:16]<=number;
        2:args[47:32]<=number;3:args[63:48]<=number;
       endcase
       if(nargs<4) nargs<=nargs+1'b1;else bad<=1;
       number<=0;digits<=0;
      end
     end else if(decimal_digit && nargs<4 && !overflow) begin
      number<=(number<<3)+(number<<1)+(data-8'd48);digits<=1;
     end else bad<=1;
    end
   end
  end
 end
endmodule
