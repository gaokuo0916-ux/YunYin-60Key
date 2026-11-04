`timescale 1ns/1ps
// Three independently retained performance dimensions: dynamics, per-note bend,
// and vibrato depth. Only the most recently pressed, still-held note bends.
module performance_control(input wire clk,sample_tick,input wire [6:0] gates,
 input wire [23:0] settings,input wire [223:0] base_steps,
 output reg [223:0] phase_steps={32'd43442435,32'd38702809,32'd34480283,
                               32'd30718441,32'd28994347,32'd25831027,32'd23012829},
 output reg [15:0] level_q15=16'd32768,output reg [5:0] space_amount=0,
 output wire [6:0] bend_target);
 reg [6:0] previous=0;
 reg [2:0] selected=0;
 wire [6:0] rises=gates&~previous;
 assign bend_target=gates[selected]?(7'b1<<selected):7'd0;
 integer i;
 always @(posedge clk) begin
  previous<=gates;
  if(rises!=0) begin for(i=0;i<7;i=i+1) if(rises[i]) selected<=i[2:0];end
  else if(!gates[selected]) begin for(i=0;i<7;i=i+1) if(gates[i]) selected<=i[2:0];end
 end
 reg [23:0] lfo_phase=0;
 wire signed [8:0] triangle=(lfo_phase[23]==lfo_phase[22])?
    $signed({lfo_phase[23],lfo_phase[23:16]}):
    (9'sd127-$signed({1'b0,lfo_phase[23:16]}));
 reg signed [15:0] vibrato_product=0;
 reg signed [9:0] pitch_offset=0;
 reg [7:0] pitch_index=80;
 wire [15:0] level_target=settings[23:18]==0?16'd0:
    ({10'd0,settings[23:18]}+16'd1)<<9;
 always @(posedge clk) begin
  vibrato_product<=triangle*$signed({1'b0,settings[11:6]});
  pitch_offset<=($signed({1'b0,settings[17:12]})-10'sd32)*10'sd2+(vibrato_product>>>8);
  if(pitch_offset< -80) pitch_index<=0;
  else if(pitch_offset>80) pitch_index<=160;
  else pitch_index<=8'd80+pitch_offset[7:0];
  if(sample_tick) begin
   lfo_phase<=lfo_phase+24'd1718; // 4.9997 Hz at 50MHz/1024.
   space_amount<=settings[5:0];
   if(level_q15>level_target)
    level_q15<=level_q15-level_target<=512?level_target:level_q15-16'd512;
   else if(level_q15<level_target)
    level_q15<=level_target-level_q15<=512?level_target:level_q15+16'd512;
  end
 end
 reg [2:0] voice=0;
 reg [6:0] frame_gates=0;
 reg [2:0] frame_selected=0;
 reg [7:0] frame_index=80;
 reg [1:0] stage=0;
 reg updating=0;
 wire [31:0] table_step;
 wire [7:0] effective_index=(frame_gates[voice] && voice==frame_selected)?frame_index:8'd80;
 performance_pitch_table pitch_rom(clk,{voice,effective_index},table_step);
 always @(posedge clk) begin
  if(sample_tick) begin
   voice<=0;stage<=0;updating<=1;
   frame_gates<=gates;frame_selected<=selected;frame_index<=pitch_index;
  end
  else if(updating) begin
   if(stage==2) begin
    if(frame_gates[voice]) phase_steps[32*voice +:32]<=effective_index==80?base_steps[32*voice +:32]:table_step;
    if(voice==6) updating<=0;else begin voice<=voice+1'b1;stage<=0;end
   end else stage<=stage+1'b1;
  end
 end
endmodule
