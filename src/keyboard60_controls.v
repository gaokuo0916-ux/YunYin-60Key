`timescale 1ns/1ps
// A/B=encoder, C=reserved, D=timbre button, E=start/stop rotary, F=pause.
// Active closures are decoded by scanner. G/H reserved. First frame is baseline.
module keyboard60_controls(input wire clk,valid,input wire [7:0] controls,
 input wire safe_to_transpose,input wire remote_octave,input wire [2:0] requested_octave,
 output reg [2:0] octave=2,output reg [6:0] base_midi=36,
 output reg start=0,stop=0,pause=0,timbre=0);
 reg initialized=0;reg [7:0] previous=0;reg signed [3:0] detent=0;
 reg signed [2:0] direction;
 // Register the absolute base beside the octave. A DSP multiply feeding all
 // 60-key judgement/LED logic created an unnecessarily long same-cycle path.
 function [6:0] base_of(input [2:0] value);begin case(value)
  0:base_of=12;1:base_of=24;2:base_of=36;3:base_of=48;default:base_of=60;
 endcase end endfunction
 always @(*)case({previous[1:0],controls[1:0]})
  4'b0001,4'b0111,4'b1110,4'b1000:direction=1;
  4'b0010,4'b1011,4'b1101,4'b0100:direction=-1;
  default:direction=0;
 endcase
 always @(posedge clk)begin
  start<=0;stop<=0;pause<=0;timbre<=0;
  if(remote_octave && safe_to_transpose && requested_octave<=4)begin octave<=requested_octave;base_midi<=base_of(requested_octave);detent<=0;end
  if(valid)begin
   previous<=controls;initialized<=1;
   if(initialized)begin
    timbre<=controls[3]&&!previous[3];pause<=controls[5]&&!previous[5];
    start<=controls[4]&&!previous[4];stop<=!controls[4]&&previous[4];
    if(!safe_to_transpose)detent<=0;
    else if(controls[1:0]!=previous[1:0])begin
     if(direction==0)detent<=0;
     else if(detent+direction>=4)begin if(octave<4)begin octave<=octave+1'b1;base_midi<=base_of(octave+1'b1);end detent<=0;end
     else if(detent+direction<=-4)begin if(octave>0)begin octave<=octave-1'b1;base_midi<=base_of(octave-1'b1);end detent<=0;end
     else detent<=detent+direction;
    end
   end
  end
 end
endmodule
