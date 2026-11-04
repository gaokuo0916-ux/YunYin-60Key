`timescale 1ns/1ps
// Observe exactly the PCM presented to the DAC at sample_tick.
// One 1024x16 synchronous RAM holds two 512-sample windows; no audio backpressure.
module audio_wave_capture(
 input wire clk,sample_tick,frame_start,
 input wire signed [15:0] pcm,
 input wire [8:0] read_address,
 output reg signed [15:0] read_sample=0,
 output reg [15:0] display_peak=0,
 output reg display_valid=0
);
 reg [15:0] samples[0:1023] /* synthesis syn_ramstyle = "block_ram" */;
 reg write_bank=0,display_bank=1,capturing=1,ready=0;
 reg [8:0] write_address=0;
 reg [15:0] running_peak=0,completed_peak=0;
 wire [15:0] magnitude=pcm[15]?(~pcm+16'd1):pcm;
 wire [15:0] next_peak=magnitude>running_peak?magnitude:running_peak;
 always @(posedge clk) begin
  read_sample<=samples[{display_bank,read_address}];
  if(sample_tick && capturing) begin
   samples[{write_bank,write_address}]<=pcm;
   running_peak<=next_peak;
   if(write_address==511) begin
    completed_peak<=next_peak;ready<=1;capturing<=0;
   end else write_address<=write_address+1'b1;
  end
  // Swap only at the display frame boundary, so the raster never tears.
  if(frame_start && ready) begin
   display_bank<=write_bank;write_bank<=~write_bank;
   display_peak<=completed_peak;
   display_valid<=1;ready<=0;capturing<=1;write_address<=0;running_peak<=0;
  end
 end
endmodule
