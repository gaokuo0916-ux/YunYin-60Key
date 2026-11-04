`timescale 1ns/1ps
// Gentle sample-domain smoothing. No audio RAM, look-ahead or clock division.
// Q10 state retains quiet tails; round once at the 19-bit output boundary.
module tone_output_filter(input wire clk,sample_tick,
 input wire signed [18:0] source,output wire signed [18:0] voiced);
 reg signed [31:0] state_q10=0,difference_q10=0;
 wire signed [31:0] target_q10={{3{source[18]}},source,10'd0};
 wire signed [31:0] rounded=state_q10+32'sd512;
 assign voiced=rounded[28:10];
 always @(posedge clk) begin
  difference_q10<=target_q10-state_q10;
  if(sample_tick)state_q10<=state_q10+(difference_q10>>>1);
 end
endmodule
