`timescale 1ns/1ps
// LMM-style accordion: a low reed and two slightly separated middle reeds.
// Periodic reed waves are analytic harmonic sums, never recorded PCM.
// One shared, interpolated ROM serves all 21 continuously running reeds.
module accordion_synth_7(
 input wire sys_clk,sample_tick,input wire [6:0] pressed,
 input wire [223:0] phase_steps,input wire [74:0] adsr_coefficients,
 output reg signed [15:0] pcm=0);
 wire [15:0] amplitude[0:6];wire [2:0] envelope_state[0:6];
 wire [6:0] idle_modes;
 genvar g;
 generate for(g=0;g<7;g=g+1)begin: envelopes
  assign idle_modes[g]=envelope_state[g]==0;
  adsr_runtime env(sys_clk,sample_tick,pressed[g],adsr_coefficients[74:57],
   adsr_coefficients[56:39],adsr_coefficients[38:15],adsr_coefficients[14:0],
   amplitude[g],envelope_state[g]);
 end endgenerate
 reg [31:0] phase[0:20];
 reg [6:0] previous=0;
 reg busy=0;reg [2:0] stage=0,voice_index=0;
 reg [1:0] reed=0;
 reg [4:0] slot=0;
 reg [31:0] lookup_phase=0;
 wire [9:0] address=lookup_phase[31:22];
 wire signed [15:0] wave0,wave1;
 accordion_reed_table wave_rom(sys_clk,address,wave0,wave1);
 reg signed [15:0] base=0;
 reg signed [16:0] delta=0,interpolated=0;
 reg [7:0] fraction=0;
 reg [15:0] amp=0;
 reg signed [25:0] interpolation=0;
 reg signed [33:0] product=0;
 reg signed [21:0] sum=0;
 wire signed [21:0] contribution=reed==0 ? (product>>>20) : (product>>>19);
 wire signed [21:0] next_sum=sum+contribution;
 reg overflow=0,deadline_missed=0;
 integer i;reg [31:0] step_value,spread;
 initial for(i=0;i<21;i=i+1)phase[i]=0;
 always @(posedge sys_clk)begin
  if(sample_tick)begin
   if(busy)deadline_missed<=1;
   previous<=pressed;sum<=0;slot<=0;voice_index<=0;reed<=0;stage<=0;busy<=1;
   // Symmetric +/-4.64-cent middle reeds; the low reed is one octave below.
   // Phase continuity is retained through bends and legato/retriggers.
   for(i=0;i<7;i=i+1)begin
    step_value=phase_steps[i*32+:32];
    spread=(step_value>>9)+(step_value>>11)+(step_value>>12);
    if(pressed[i] && !previous[i] && idle_modes[i])begin
     phase[i*3]<=32'h13579bdf+i*32'h10700301;
     phase[i*3+1]<=32'h00000000+i*32'h17000003;
     phase[i*3+2]<=32'h34000000+i*32'h23000501;
    end else begin
     phase[i*3]<=phase[i*3]+(step_value>>1);
     phase[i*3+1]<=phase[i*3+1]+step_value-spread;
     phase[i*3+2]<=phase[i*3+2]+step_value+spread;
    end
   end
  end else if(busy)case(stage)
   0:begin lookup_phase<=phase[slot];amp<=amplitude[voice_index];stage<=1;end
   1:stage<=2; // synchronous true dual-port ROM
   2:begin
    base<=wave0;delta<=$signed({wave1[15],wave1})-$signed({wave0[15],wave0});
    fraction<=lookup_phase[21:14];stage<=3;
   end
   3:begin interpolation<=delta*$signed({1'b0,fraction});stage<=4;end
   4:begin interpolated<=$signed({base[15],base})+(interpolation>>>8);stage<=5;end
   5:begin product<=interpolated*$signed({1'b0,amp});stage<=6;end
   6:begin
    sum<=next_sum;
    if(slot==20)begin
     if(next_sum>32767 || next_sum< -32768)overflow<=1;
     if(next_sum>32767)pcm<=32767;
     else if(next_sum< -32768)pcm<=-32768;
     else pcm<=next_sum[15:0];
     busy<=0;
    end else begin
     slot<=slot+1'b1;
     if(reed==2)begin reed<=0;voice_index<=voice_index+1'b1;end else reed<=reed+1'b1;
     stage<=0;
    end
   end
   default:stage<=0;
  endcase
 end
endmodule
