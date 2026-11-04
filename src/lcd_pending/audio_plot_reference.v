`timescale 1ns/1ps
// Display-only sine ROM; never connected to the audible synthesis mixer.
module audio_plot_reference(input wire clk,input wire [7:0] phase,
 output reg signed [15:0] sample=0);
 reg [15:0] quarter[0:64];reg [15:0] value=0;reg negative=0;
 wire [6:0] address=phase[6]?7'd64-{1'b0,phase[5:0]}:{1'b0,phase[5:0]};
 initial begin
quarter[0]=16'd0;
quarter[1]=16'd804;
quarter[2]=16'd1608;
quarter[3]=16'd2410;
quarter[4]=16'd3212;
quarter[5]=16'd4011;
quarter[6]=16'd4808;
quarter[7]=16'd5602;
quarter[8]=16'd6393;
quarter[9]=16'd7179;
quarter[10]=16'd7962;
quarter[11]=16'd8739;
quarter[12]=16'd9512;
quarter[13]=16'd10278;
quarter[14]=16'd11039;
quarter[15]=16'd11793;
quarter[16]=16'd12539;
quarter[17]=16'd13279;
quarter[18]=16'd14010;
quarter[19]=16'd14732;
quarter[20]=16'd15446;
quarter[21]=16'd16151;
quarter[22]=16'd16846;
quarter[23]=16'd17530;
quarter[24]=16'd18204;
quarter[25]=16'd18868;
quarter[26]=16'd19519;
quarter[27]=16'd20159;
quarter[28]=16'd20787;
quarter[29]=16'd21403;
quarter[30]=16'd22005;
quarter[31]=16'd22594;
quarter[32]=16'd23170;
quarter[33]=16'd23731;
quarter[34]=16'd24279;
quarter[35]=16'd24811;
quarter[36]=16'd25329;
quarter[37]=16'd25832;
quarter[38]=16'd26319;
quarter[39]=16'd26790;
quarter[40]=16'd27245;
quarter[41]=16'd27683;
quarter[42]=16'd28105;
quarter[43]=16'd28510;
quarter[44]=16'd28898;
quarter[45]=16'd29268;
quarter[46]=16'd29621;
quarter[47]=16'd29956;
quarter[48]=16'd30273;
quarter[49]=16'd30571;
quarter[50]=16'd30852;
quarter[51]=16'd31113;
quarter[52]=16'd31356;
quarter[53]=16'd31580;
quarter[54]=16'd31785;
quarter[55]=16'd31971;
quarter[56]=16'd32137;
quarter[57]=16'd32285;
quarter[58]=16'd32412;
quarter[59]=16'd32521;
quarter[60]=16'd32609;
quarter[61]=16'd32678;
quarter[62]=16'd32728;
quarter[63]=16'd32757;
quarter[64]=16'd32767;
 end
 always @(posedge clk)begin
  value<=quarter[address];negative<=phase[7];
  sample<=negative?-$signed(value):$signed(value);
 end
endmodule
