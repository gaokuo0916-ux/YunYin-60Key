`timescale 1ns/1ps
// Lehmer rank 0..5039 -> a bijection. No division and no DSPs.
module studio_keymap(input wire clk,input wire request,input wire [12:0] rank,
 output reg busy=0,output reg done=0,output reg [20:0] mapping={3'd6,3'd5,3'd4,3'd3,3'd2,3'd1,3'd0});
 reg [12:0] remainder=0;reg [2:0] position=0,choice=0;reg [6:0] used=0;
 reg [20:0] staging=0;reg picking=0;
 wire [9:0] divisor=position==0?10'd720:position==1?10'd120:position==2?10'd24:position==3?10'd6:position==4?10'd2:10'd1;
 function [2:0] choose_unused(input [6:0] mask,input [2:0] digit);
  integer n,k;reg found;begin choose_unused=0;found=0;k=0;
   for(n=0;n<7;n=n+1)if(!mask[n])begin if(k==digit && !found)begin choose_unused=n;found=1;end k=k+1;end
  end
 endfunction
 wire [2:0] selected=choose_unused(used,choice);
 always @(posedge clk)begin
  done<=0;
  if(request && !busy)begin busy<=1;remainder<=rank;position<=0;choice<=0;used<=0;staging<=0;picking<=0;end
  else if(busy)begin
   if(!picking)begin
    if(remainder>={3'd0,divisor})begin remainder<=remainder-{3'd0,divisor};choice<=choice+1'b1;end
    else picking<=1;
   end else begin
    staging[position*3+:3]<=selected;used[selected]<=1;
    if(position==6)begin mapping<={selected,staging[17:0]};busy<=0;done<=1;end
    else begin position<=position+1'b1;choice<=0;picking<=0;end
   end
  end
 end
endmodule
