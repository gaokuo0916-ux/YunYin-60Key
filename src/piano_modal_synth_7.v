`timescale 1ns/1ps
// Seven voices x 32 nonzero additive components = 224 independent gain states.
// One slot every 4 clocks through a shared DSP pipeline: 905/1024 clocks.
// Continuous Q16 modal ratios include stretched/offset strings; no recorded PCM.
module piano_modal_synth_7 #(parameter integer RUNTIME_ADSR=0,parameter integer RUNTIME_PITCH=0)(
 input wire sys_clk,sample_tick,input wire [6:0] pressed,
 output reg signed [15:0] pcm=0,input wire [74:0] adsr_coefficients,
 input wire [223:0] runtime_phase_steps);
 wire [15:0] amplitudes[0:6];
 wire [2:0] envelope_states[0:6];
 wire [6:0] idle_modes;
 genvar v;
 generate for(v=0;v<7;v=v+1) begin: envelope
  assign idle_modes[v]=(envelope_states[v]==0);
  if(RUNTIME_ADSR) begin: adjustable
   adsr_runtime env(sys_clk,sample_tick,pressed[v],adsr_coefficients[74:57],
    adsr_coefficients[56:39],adsr_coefficients[38:15],adsr_coefficients[14:0],
    amplitudes[v],envelope_states[v]);
  end else begin: fixed_envelope
   adsr_envelope #(.ATTACK_SAMPLES(49),.DECAY_SAMPLES(7324),
    .SUSTAIN_LEVEL(16'd26214),.RELEASE_SAMPLES(5859)) env(
    sys_clk,sample_tick,pressed[v],amplitudes[v],envelope_states[v]);
  end
 end endgenerate
 function [31:0] base_step;
  input [2:0] voice;
  begin case(voice)
   0:base_step=32'd23012829;1:base_step=32'd25831027;2:base_step=32'd28994347;
   3:base_step=32'd30718441;4:base_step=32'd34480283;5:base_step=32'd38702809;
   default:base_step=32'd43442435;
  endcase end
 endfunction
 // Retain whole cycles so fractional component ratios stay phase-continuous
 // through bends. Q16 ratios need exactly 16 unwrapped cycle bits.
 reg [47:0] phases[0:6],frame_phases[0:6];
 reg signed [23:0] accum[0:6];
 reg [6:0] previous=0,trigger=0,hold_release_damping=0;
 integer i;
 initial for(i=0;i<7;i=i+1) begin phases[i]=0;frame_phases[i]=0;accum[i]=0;end
 reg busy=0,issuing=0,complete=0;
 reg [7:0] slot=0;
 reg [1:0] issue_phase=0;
 reg [31:0] lookup_phase=0;
 wire [2:0] voice_index=slot[7:5];
 wire [15:0] model_decay;
 wire [23:0] model_gain;
 wire [31:0] model_phase;
 wire [21:0] model_ratio;
 wire signed [15:0] sin0,sin1;
  piano_modal_tables tables(sys_clk,slot,lookup_phase[31:23],model_decay,
                           model_gain,sin0,sin1,model_phase,model_ratio);
 reg [45:0] phase_product_low=0,phase_product_high=0;
 reg [47:0] stretched_phase=0;
 // Simple dual-port RAM. Idle slots ignore uninitialized data; fresh notes
 // load their model gains. Writes use delayed tags, never the read address.
 reg [23:0] gain_memory[0:255] /* synthesis syn_ramstyle = "block_ram" */;
 reg [23:0] gain_read=0;
 reg gain_write=0;
 reg [7:0] gain_write_address=0;
 reg [23:0] gain_write_data=0;
 always @(posedge sys_clk) begin
  gain_read<=gain_memory[slot];
  if(gain_write) gain_memory[gain_write_address]<=gain_write_data;
 end
 reg [6:0] valid=0;
 reg [7:0] tag[0:6];
 reg [15:0] amp[0:5];
 reg [23:0] gain_pipe[0:3];
 reg [15:0] decay0=0;
 reg [2:0] freeze_gain=0;
 reg signed [15:0] base1=0,base2=0;
 reg signed [16:0] delta1=0,wave3=0;
 reg [7:0] fraction1=0;
 reg signed [25:0] interpolation2=0;
 wire signed [25:0] interpolated2=$signed({{10{base2[15]}},base2})+(interpolation2>>>8);
 reg [39:0] decay_product2=0;
 wire [15:0] gain_loss2=decay_product2[39:24]+{15'd0,(|decay_product2[23:0])};
 reg signed [41:0] tone_product4=0;
 reg signed [18:0] normalized5=0;
 reg signed [35:0] amplitude_product=0;
 wire signed [20:0] contribution=amplitude_product[35:15];
 wire signed [25:0] pair0=$signed({{2{accum[0][23]}},accum[0]})+$signed({{2{accum[1][23]}},accum[1]});
 wire signed [25:0] pair1=$signed({{2{accum[2][23]}},accum[2]})+$signed({{2{accum[3][23]}},accum[3]});
 wire signed [25:0] pair2=$signed({{2{accum[4][23]}},accum[4]})+$signed({{2{accum[5][23]}},accum[5]});
 wire signed [25:0] total=(pair0+pair1)+(pair2+$signed({{2{accum[6][23]}},accum[6]}));
 wire signed [25:0] scaled=total>>>1;
 integer p;
 initial begin
  for(p=0;p<7;p=p+1) tag[p]=0;
  for(p=0;p<6;p=p+1) amp[p]=0;
  for(p=0;p<4;p=p+1) gain_pipe[p]=0;
 end
 always @(posedge sys_clk) begin
  valid<={valid[5:0],1'b0};
  for(p=1;p<7;p=p+1) tag[p]<=tag[p-1];
  for(p=1;p<6;p=p+1) amp[p]<=amp[p-1];
  for(p=1;p<4;p=p+1) gain_pipe[p]<=gain_pipe[p-1];
  freeze_gain<={freeze_gain[1:0],1'b0};
  gain_write<=0;complete<=0;
  if(sample_tick) begin
   previous<=pressed;trigger<=pressed&~previous;
   for(i=0;i<7;i=i+1) begin
    if(pressed[i] && !previous[i] && idle_modes[i]) begin
     frame_phases[i]<=0;phases[i]<=RUNTIME_PITCH?runtime_phase_steps[32*i +:32]:base_step(i);
    end else begin frame_phases[i]<=phases[i];phases[i]<=phases[i]+(RUNTIME_PITCH?runtime_phase_steps[32*i +:32]:base_step(i));end
    if(pressed[i] && !previous[i]) hold_release_damping[i]<=0;
    else if(!pressed[i] && previous[i])
     hold_release_damping[i]<=RUNTIME_ADSR && adsr_coefficients[14:0]<15'd1838;
    accum[i]<=0;
   end
   slot<=0;issue_phase<=0;issuing<=1;busy<=1;
  end else if(issuing) begin
   case(issue_phase)
    0:issue_phase<=1;
    1:begin
     phase_product_low<=frame_phases[voice_index][23:0]*model_ratio;
     phase_product_high<=frame_phases[voice_index][47:24]*model_ratio;
     issue_phase<=2;
    end
    2:begin
     stretched_phase<={2'd0,phase_product_low}+{phase_product_high[23:0],24'd0};
     issue_phase<=3;
    end
    3:begin
     valid[0]<=1;tag[0]<=slot;
     lookup_phase<=stretched_phase[47:16]+model_phase;
     gain_pipe[0]<=trigger[voice_index]?model_gain:(idle_modes[voice_index]?24'd0:gain_read);
     amp[0]<=amplitudes[voice_index];decay0<=model_decay;
     freeze_gain[0]<=envelope_states[voice_index]==4 && hold_release_damping[voice_index];
     issue_phase<=0;
     if(slot==223) issuing<=0;else slot<=slot+1'b1;
    end
    default:issue_phase<=0;
   endcase
  end
  if(valid[0]) begin
   base1<=sin0;delta1<=$signed({sin1[15],sin1})-$signed({sin0[15],sin0});
   fraction1<=lookup_phase[22:15];decay_product2<=gain_pipe[0]*decay0;
  end
  if(valid[1]) begin
   interpolation2<=delta1*$signed({1'b0,fraction1});base2<=base1;
  end
  if(valid[2]) begin
   wave3<=interpolated2[16:0];
   gain_write<=1;gain_write_address<=tag[2];
   gain_write_data<=freeze_gain[2]?gain_pipe[2]:
                    ((gain_pipe[2]<=gain_loss2)?24'd0:gain_pipe[2]-gain_loss2);
  end
  if(valid[3]) tone_product4<=wave3*$signed({1'b0,gain_pipe[3]});
  if(valid[4]) normalized5<=tone_product4[41:23];
  if(valid[5]) amplitude_product<=normalized5*$signed({1'b0,amp[5]});
  if(valid[6]) begin
   accum[tag[6][7:5]]<=accum[tag[6][7:5]]+$signed({{3{contribution[20]}},contribution});
   if(tag[6]==223) complete<=1;
  end
  if(complete) begin
   if(scaled>26'sd32767) pcm<=16'sd32767;
   else if(scaled< -26'sd32768) pcm<= -16'sd32768;
   else pcm<=scaled[15:0];
   busy<=0;
  end
 end
endmodule
