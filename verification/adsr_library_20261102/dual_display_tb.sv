`timescale 1ns/1ps
module dual_display_tb;
 reg [23:0] indices=0;wire [63:0] values;integer n,expected,actual;
 performance_display dut(indices,values);
 initial begin
  for(n=0;n<64;n++)begin
   indices={6'(n),6'd32,6'(n),6'(n)};#1;
   expected=(n*100+31)/63;
   actual=values[3:0]+10*values[7:4]+100*values[11:8]+1000*values[15:12];
   if(actual!=expected||values[63:48]!=values[15:0]||values[31:16]!=values[15:0]||values[47:32]!=0)$fatal(1,"UI percent n%0d actual%0d expected%0d",n,actual,expected);
  end
  if(values[15:0]!=16'h0100)$fatal(1,"100 percent endpoint");
  $display("PASS all64 screen percentages 0..100, manual pitch and volume/vibrato unchanged");$finish;
 end
endmodule
