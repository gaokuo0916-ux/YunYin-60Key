`timescale 1ns/1ps
// TF streaming ring, not a complete take. No audio backpressure.
// Default 16384 x 16 bits = 32KiB; a stalled card ends recording explicitly.
// Legacy short-capture ports remain for source compatibility, but arm is ignored.
module studio_pcm_capture #(parameter integer RING_ADDRESS_BITS=14)(input wire clk,sample_tick,input wire signed [15:0] pcm,
 input wire [6:0] physical_keys,input wire arm,abort,input wire [15:0] length,
 output reg [2:0] state=0,output reg [15:0] count=0,requested=0,crc=16'hffff,
 input wire [15:0] read_address,output reg [15:0] read_data=0,
 input wire long_arm,long_stop,input wire [31:0] long_limit,consumed,
 output reg long_mode=0,output reg [31:0] produced=0,output reg overflow=0,input wire immediate_start);
 localparam integer RING_SAMPLES=1<<RING_ADDRESS_BITS;
 reg [15:0] samples[0:RING_SAMPLES-1] /* synthesis syn_ramstyle = "block_ram" */;
 reg [6:0] previous=0;reg [15:0] bits=0;reg [4:0] crc_left=0;reg finishing=0;reg [31:0] limit=0;
 wire mix=crc[15]^bits[7];
 always @(posedge clk)begin
  previous<=physical_keys;read_data<=samples[read_address[RING_ADDRESS_BITS-1:0]];
  if(long_arm)begin if(immediate_start)state<=2;else state<=1;count<=0;produced<=0;overflow<=0;requested<=0;crc<=16'hffff;crc_left<=0;finishing<=0;long_mode<=1;limit<=long_limit;end
  else if(abort)begin state<=4;crc_left<=0;finishing<=0;end
  else if(long_stop && long_mode && (state==1 || state==2))begin
   if(state==1)state<=4;
   else begin finishing<=1;if(crc_left==0)begin state<=3;finishing<=0;end end
  end else begin
   if(state==1 && |(physical_keys&~previous))state<=2;
   if(state==2 && sample_tick && !finishing)begin
    if(produced-consumed>=RING_SAMPLES-1)begin state<=4;overflow<=1;end
    else begin
     samples[produced[RING_ADDRESS_BITS-1:0]]<=pcm;count<=count+1'b1;produced<=produced+1'b1;
     bits<={pcm[15:8],pcm[7:0]};crc_left<=16;
     if(produced==limit-1'b1)finishing<=1;
    end
   end
   if(crc_left!=0)begin
    crc<={crc[14:0],1'b0}^(mix?16'h1021:16'd0);
    if(crc_left==9)bits<={8'd0,bits[15:8]};else bits[7:0]<={bits[6:0],1'b0};
    crc_left<=crc_left-1'b1;
    if(crc_left==1 && finishing)begin state<=3;finishing<=0;end
   end
  end
 end
endmodule
