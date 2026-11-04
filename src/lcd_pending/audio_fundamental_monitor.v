`timescale 1ns/1ps
// Display only: extract amplitude/phase from real PCM by coherent I/Q filtering.
// No oscillator or filtered signal here is connected to audible outputs.
module audio_fundamental_monitor(
 input wire clk,sample_tick,input wire signed [31:0] voice_pcm,
 input wire [31:0] voice_step,input wire active,input wire [12:0] voice_tag,
 output reg signed [15:0] filtered=0,output wire valid,
 input wire [7:0] reference_address,output wire signed [15:0] reference_sample);
 reg [31:0] phase=0;reg [12:0] tag_q=13'h1fff;
 reg [10:0] warmup=0;reg [3:0] stage=0;reg signed [15:0] pcm_q=0;
 wire signed [15:0] sine,cosine;
 // The filter reads sine only in stages 4 and 7. Between samples its
 // otherwise idle ROM serves the fixed-reference plot; sample_tick latches
 // that value before the filter starts, with >1000 clocks of settling.
 wire [7:0] sine_address=stage==0?reference_address:phase[31:24];
 assign reference_sample=sine;
 audio_plot_reference sin_rom(clk,sine_address,sine);
 audio_plot_reference cos_rom(clk,phase[31:24]+8'd64,cosine);
 reg signed [31:0] mix_i=0,mix_q=0;
 reg signed [39:0] i1=0,q1=0,i2=0,q2=0;
 reg signed [47:0] reconstruction_i=0,reconstruction_q=0;
 wire signed [39:0] in_i={{8{mix_i[31]}},mix_i}<<<8;
 wire signed [39:0] in_q={{8{mix_q[31]}},mix_q}<<<8;
 wire signed [48:0] reconstructed=$signed({reconstruction_i[47],reconstruction_i})+
                                      $signed({reconstruction_q[47],reconstruction_q});
 wire signed [48:0] result=reconstructed>>>29;
 assign valid=active && tag_q==voice_tag && warmup==1024;
 always @(posedge clk)begin
  if(sample_tick)begin
   if(!active || tag_q!=voice_tag)begin
    tag_q<=voice_tag;phase<=0;warmup<=0;filtered<=0;
    i1<=0;q1<=0;i2<=0;q2<=0;stage<=0;
   end else begin
    phase<=phase+voice_step;
    pcm_q<=voice_pcm>32767?16'sd32767:voice_pcm< -32768?-16'sd32768:voice_pcm[15:0];
    if(warmup<1024)warmup<=warmup+1'b1;stage<=1;
   end
  end else if(stage!=0)begin
   stage<=stage+1'b1;
   case(stage)
    4:begin mix_i<=pcm_q*sine;mix_q<=pcm_q*cosine;end
    5:begin i1<=i1+((in_i-i1)>>>8);q1<=q1+((in_q-q1)>>>8);end
    6:begin i2<=i2+((i1-i2)>>>8);q2<=q2+((q1-q2)>>>8);end
    7:begin reconstruction_i<=$signed(i2[39:8])*sine;reconstruction_q<=$signed(q2[39:8])*cosine;end
    8:begin filtered<=result>32767?16'sd32767:result< -32768?-16'sd32768:result[15:0];stage<=0;end
   endcase
  end
 end
endmodule
