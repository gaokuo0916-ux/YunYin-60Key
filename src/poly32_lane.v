`timescale 1ns/1ps
// Sixteen independent voices, sixty clocks each. Two lanes cover 32 voices.
// Every voice owns its phase, ADSR, modal gains and instrument history.
// The arithmetic pipeline is reused; no PCM recordings are stored or played.
module poly32_lane(input wire clk,start,
 input wire [15:0] gates,input wire [127:0] generations,input wire [15:0] test_sine,
 input wire [511:0] steps,input wire [47:0] models,input wire [31:0] timbres,
 input wire [127:0] velocities,
 input wire [74:0] piano_adsr,guitar_adsr,accordion_adsr,
 output reg busy=0,done=0,deadline_missed=0,
 output reg signed [31:0] piano_sum=0,guitar_sum=0,accordion_sum=0,
 output reg [15:0] idle=16'hffff,output reg [127:0] seen_generation=0,
 output reg [255:0] levels=0,
 output reg [511:0] voice_samples=0,
 input wire [3:0] visual_select,
 output reg signed [31:0] visual_pcm=0,output reg [31:0] visual_step=0,
 output reg [7:0] visual_generation=0,output reg visual_gate=0,
 output reg [3:0] visual_slot=0);
 localparam IDLE=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
 reg [3:0] voice=0;reg [5:0] cycle=0;
 // Dense 32-bit words avoid a very wide shallow RAM or thousands of FF muxes.
 // Prefetch the NEXT voice at cycles 5..18; write this voice at 44..56.
 // The existing arithmetic and 60-clock voice schedule are unchanged.
 localparam [415:0] INITIAL_CONTEXT={8'd0,7'd0,17'd0,23'h6a3d51,
  24'd0,24'd0,24'd0,32'd0,32'd0,32'd0,48'd0,8'd0,1'b0,1'b0,3'd0,
  18'd1,18'd1,24'd0,24'd0,24'd1,24'd0};
 reg [31:0] context_memory[0:255] /* synthesis syn_ramstyle = "block_ram" */;
 reg [415:0] context_prefetch=INITIAL_CONTEXT;
 function [31:0] context_word(input [415:0] value,input [3:0] index);
  begin case(index)
   4'd0:context_word=value[0+:32];
   4'd1:context_word=value[32+:32];
   4'd2:context_word=value[64+:32];
   4'd3:context_word=value[96+:32];
   4'd4:context_word=value[128+:32];
   4'd5:context_word=value[160+:32];
   4'd6:context_word=value[192+:32];
   4'd7:context_word=value[224+:32];
   4'd8:context_word=value[256+:32];
   4'd9:context_word=value[288+:32];
   4'd10:context_word=value[320+:32];
   4'd11:context_word=value[352+:32];
   4'd12:context_word=value[384+:32];
   default:context_word=0;
  endcase end
 endfunction
 reg [31:0] context_read=0;
 wire [3:0] next_voice=voice+4'd1;
 wire [3:0] fetch_word=cycle>=5&&cycle<=17?cycle-6'd5:4'd0;
 wire [7:0] context_ra={next_voice,fetch_word};
 wire [3:0] store_word=cycle-6'd44;
 wire [7:0] context_wa={voice,store_word};
 integer n,w;
 initial for(n=0;n<16;n=n+1)for(w=0;w<16;w=w+1)
  context_memory[n*16+w]=context_word(INITIAL_CONTEXT,w[3:0]);
 reg gate_q=0,was_q=0,fresh=0,pure_q=0,freeze_q=0;reg [7:0] gen_q=0;
 reg [1:0] tone=0;reg [2:0] model=0,env_state=0;
 reg [7:0] velocity=128;reg [31:0] step_q=0,current_step=0;
 reg [74:0] coeff=0;
 reg [23:0] level=0,release_step=1,decay_target=0,decay_limit=0;
 reg [17:0] attack=1,decay=1;
 reg [47:0] phase_q=0,calc_phase=0;
 reg [31:0] phase_b=0,phase_c=0,calc_b=0,calc_c=0;
 reg [23:0] sg=0,mg=0,tg=0;
 reg [22:0] rnd=0;reg signed [16:0] noise_q=0;reg [6:0] pluck_left=0;
 reg [38:0] release_product=0;
 reg [23:0] next_level=0,next_release=1,next_target=0,next_limit=0;
 reg [17:0] next_attack=1,next_decay=1;reg [2:0] next_state=0;
 reg [23:0] s_distance=0,s_next=0;reg [24:0] a_sum=0;
 wire [17:0] safe_a=coeff[74:57]==0?18'd1:coeff[74:57];
 wire [17:0] safe_d=coeff[56:39]==0?18'd1:coeff[56:39];
 wire [23:0] safe_s=coeff[38:15]>8388608?24'd8388608:coeff[38:15];
 wire [14:0] release_now=release_product[38:24]+{14'd0,(|release_product[23:0])};
 reg [23:0] new_sg=0,new_mg=0,new_tg=0;
 reg [31:0] ring_product=0,mid_product=0,high_product=0;
 wire [15:0] body_amp=ring_product[30:15],mid_amp=mid_product[30:15],high_amp=high_product[30:15];
 reg [23:0] vel_product=0;reg [15:0] amplitude=0;
 wire rising=gate_q&&!was_q;
 wire [23:0] sloss=(sg>>16)==0?24'd1:sg>>16;
 wire [23:0] mloss=(mg>>14)==0?24'd1:mg>>14;
 wire [23:0] tloss=(tg>>12)==0?24'd1:tg>>12;
 wire [31:0] spread=(step_q>>9)+(step_q>>11)+(step_q>>12);
 wire [31:0] slew=(step_q>>8)+(step_q>>11)+(step_q>>12)+(step_q>>14)+(step_q>>16);
 wire signed [17:0] noise_delta=$signed({{2{rnd[15]}},rnd[15:0]})-$signed({noise_q[16],noise_q});
 wire signed [18:0] pluck_wave=pluck_left==0?19'sd0:
  ($signed({{2{noise_q[16]}},noise_q})>>>(pluck_left>64?3:pluck_left>32?4:5));
 wire issuing=busy&&cycle>=6&&cycle<(pure_q?7:tone<2?38:9);
 wire [4:0] component=cycle-6;
 wire [1:0] reed_band=step_q>=32'd713827720 ? 2'd3 : step_q>=32'd356913860 ? 2'd2 : step_q>=32'd178456930 ? 2'd1 : 2'd0;
 wire [7:0] model_slot={model,component};
 wire [15:0] model_decay;wire [23:0] model_gain;wire [31:0] model_phase;wire [21:0] model_ratio;
 wire signed [15:0] psin0,psin1,reed0,reed1;
 reg [31:0] lookup_phase=0,phase4=0;
 piano_modal_tables #(.SHARED_GUITAR(1)) tables(clk,model_slot,phase4[31:23],model_decay,model_gain,psin0,psin1,model_phase,model_ratio,tone==1);
 accordion_reed_table reeds(clk,{reed_band,lookup_phase[31:24]},reed0,reed1);
 reg [23:0] gains[0:511] /* synthesis syn_ramstyle = "block_ram" */;
 reg [23:0] gain_read=0;
 reg [11:0] valid=0;reg [4:0] tag[0:10];
 reg [23:0] gain_pipe[0:8];
 reg [21:0] ratio0=0;reg [31:0] harmonic0=0,other1=0,other2=0;
 reg [47:0] product_lo=0,product_hi=0;reg [47:0] stretched=0;
 reg [31:0] initial1=0,initial2=0;reg [55:0] frequency_product=0;
 reg [10:0] audible=0;reg [39:0] decay_product=0;reg [15:0] gain_loss2=0;
 wire [23:0] candidate_gain=pure_q?24'd131072:rising?model_gain:env_state==IDLE?24'd0:gain_read;
 wire [15:0] gain_loss=decay_product[39:24]+{15'd0,(|decay_product[23:0])};
 reg signed [15:0] base5=0,base6=0;
 reg signed [16:0] delta5=0,wave7=0;reg [7:0] fraction5=0;
 reg signed [25:0] interpolation6=0;
 reg signed [41:0] tone_product8=0;reg signed [18:0] normalized9=0;
 reg signed [35:0] amplitude_product10=0;
 reg signed [31:0] accumulator=0,reed_accumulator=0;
 reg signed [31:0] sum_p=0,sum_g=0,sum_a=0;
 // Guitar word layout: phase12 / harmonic8 / signed detune12 (Q12).
 wire [23:0] active_ratio=tone==1&&!pure_q ?
  {model_phase[19:12],16'd0}+{{8{model_phase[11]}},model_phase[11:0],4'd0} : {2'd0,ratio0};
 // Both piano and modal guitar share the existing interpolated sine ROM.
 integer k;
 initial begin for(k=0;k<11;k=k+1)tag[k]=0;for(k=0;k<9;k=k+1)gain_pipe[k]=0;end
 wire [415:0] context_write={8'd0,pluck_left,noise_q,rnd,new_tg,new_mg,new_sg,
  current_step,phase_c,phase_b,phase_q,gen_q,freeze_q,gate_q,next_state,
  next_decay,next_attack,next_limit,next_target,next_release,next_level};
 always @(posedge clk)begin
  context_read<=context_memory[context_ra];
  if(busy&&!start&&cycle>=44&&cycle<=56)
   context_memory[context_wa]<=context_word(context_write,store_word);
  if(busy&&!start)case(cycle)
    6'd6:context_prefetch[0+:32]<=context_read;
    6'd7:context_prefetch[32+:32]<=context_read;
    6'd8:context_prefetch[64+:32]<=context_read;
    6'd9:context_prefetch[96+:32]<=context_read;
    6'd10:context_prefetch[128+:32]<=context_read;
    6'd11:context_prefetch[160+:32]<=context_read;
    6'd12:context_prefetch[192+:32]<=context_read;
    6'd13:context_prefetch[224+:32]<=context_read;
    6'd14:context_prefetch[256+:32]<=context_read;
    6'd15:context_prefetch[288+:32]<=context_read;
    6'd16:context_prefetch[320+:32]<=context_read;
    6'd17:context_prefetch[352+:32]<=context_read;
    6'd18:context_prefetch[384+:32]<=context_read;
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  done<=0;valid<={valid[10:0],issuing};audible<={audible[9:0],1'b0};
  for(k=1;k<11;k=k+1)tag[k]<=tag[k-1];
  for(k=2;k<9;k=k+1)gain_pipe[k]<=gain_pipe[k-1];
  if(issuing)begin
   tag[0]<=component;ratio0<=pure_q?22'd65536:model_ratio;
   gain_read<=gains[{voice,component}];
   harmonic0<=pure_q?calc_phase[31:0]:component==0?calc_phase[31:0]:component==1?calc_b:calc_c;
  end
  if(valid[0])begin
   product_lo<=calc_phase[23:0]*active_ratio;product_hi<=calc_phase[47:24]*active_ratio;
   initial1<=pure_q?32'd0:tone==1?{model_phase[31:20],20'd0}:model_phase;other1<=harmonic0;
   gain_pipe[1]<=candidate_gain;decay_product<=candidate_gain*model_decay;
   frequency_product<=step_q*active_ratio;
  end
  if(valid[1])begin
   stretched<=product_lo+{product_hi[23:0],24'd0};
   initial2<=initial1;other2<=other1;
   audible[2]<=frequency_product<56'd140737488355328; // (step*ratio)>>16 < 2^31
   gain_loss2<=gain_loss;
  end
  if(valid[2])begin
   lookup_phase<=tone<2&&!pure_q?stretched[47:16]+initial2:other2;
   if(tone<2&&!pure_q)gains[{voice,tag[2]}]<=freeze_q?gain_pipe[2]:
     gain_pipe[2]<=gain_loss2?24'd0:gain_pipe[2]-gain_loss2;
  end
  if(valid[3])phase4<=lookup_phase;
  if(valid[4])begin
   if(pure_q||tone<2)begin
    base5<=psin0;delta5<=$signed({psin1[15],psin1})-$signed({psin0[15],psin0});fraction5<=phase4[22:15];
   end else begin
    base5<=reed0;delta5<=$signed({reed1[15],reed1})-$signed({reed0[15],reed0});fraction5<=phase4[23:16];
   end
  end
  if(valid[5])begin base6<=base5;interpolation6<=delta5*$signed({1'b0,fraction5});end
  if(valid[6])wave7<=$signed({base6[15],base6})+(interpolation6>>>8);
  if(valid[7])begin
   tone_product8<=(tone==2&&!pure_q)?wave7*$signed({1'b0,amplitude}):wave7*$signed({1'b0,gain_pipe[7]});
  end
  if(valid[8])normalized9<=tone==2&&!pure_q?(tone_product8>>>(tag[8]==0?20:19)):tone_product8>>>23;
  if(valid[9])begin
   amplitude_product10<=normalized9*$signed({1'b0,amplitude});
   if(tone==2&&!pure_q)reed_accumulator<=reed_accumulator+normalized9;
  end
  if(valid[10]&&(pure_q||tone<2))accumulator<=accumulator+
    ((pure_q||audible[10])?$signed(amplitude_product10>>>15):32'sd0);
  if(start)begin
   if(busy)deadline_missed<=1;
   busy<=1;voice<=0;cycle<=0;sum_p<=0;sum_g<=0;sum_a<=0;valid<=0;
  end else if(busy)begin
   cycle<=cycle+1'b1;
   case(cycle)
    0:begin
     gate_q<=gates[voice];gen_q<=generations[voice*8+:8];fresh<=generations[voice*8+:8]!=context_prefetch[137+:8];
     pure_q<=test_sine[voice];tone<=timbres[voice*2+:2];model<=models[voice*3+:3];
     step_q<=steps[voice*32+:32];velocity<=velocities[voice*8+:8];
     coeff<=timbres[voice*2+:2]==0?piano_adsr:timbres[voice*2+:2]==1?guitar_adsr:accordion_adsr;
     was_q<=generations[voice*8+:8]!=context_prefetch[137+:8]?1'b0:context_prefetch[135];
     level<=generations[voice*8+:8]!=context_prefetch[137+:8]?24'd0:context_prefetch[0+:24];
     env_state<=generations[voice*8+:8]!=context_prefetch[137+:8]?3'd0:context_prefetch[132+:3];
     attack<=context_prefetch[96+:18];decay<=context_prefetch[114+:18];release_step<=context_prefetch[24+:24];decay_target<=context_prefetch[48+:24];decay_limit<=context_prefetch[72+:24];
     phase_q<=generations[voice*8+:8]!=context_prefetch[137+:8]?48'd0:context_prefetch[145+:48];
     phase_b<=context_prefetch[193+:32];phase_c<=context_prefetch[225+:32];
     current_step<=generations[voice*8+:8]!=context_prefetch[137+:8]?steps[voice*32+:32]:context_prefetch[257+:32];
     sg<=generations[voice*8+:8]!=context_prefetch[137+:8]?24'd0:context_prefetch[289+:24];
     mg<=generations[voice*8+:8]!=context_prefetch[137+:8]?24'd0:context_prefetch[313+:24];
     tg<=generations[voice*8+:8]!=context_prefetch[137+:8]?24'd0:context_prefetch[337+:24];
     rnd<=generations[voice*8+:8]!=context_prefetch[137+:8]?(steps[voice*32+:23]^23'h6a3d51):context_prefetch[361+:23];
     noise_q<=generations[voice*8+:8]!=context_prefetch[137+:8]?17'sd0:context_prefetch[384+:17];
     pluck_left<=generations[voice*8+:8]!=context_prefetch[137+:8]?7'd0:context_prefetch[401+:7];
     freeze_q<=generations[voice*8+:8]!=context_prefetch[137+:8]?1'b0:context_prefetch[136];
    end
    1:begin
     release_product<=level*coeff[14:0];
     s_distance<=level>safe_s?level-safe_s:safe_s-level;
     a_sum<={1'b0,level}+{7'd0,rising?safe_a:attack};
    end
    2:begin
     s_next<=s_distance<=1?safe_s:level<safe_s?
       level+(s_distance[23:8]==0?24'd1:{8'd0,s_distance[23:8]}):
       level-(s_distance[23:8]==0?24'd1:{8'd0,s_distance[23:8]});
    end
    3:begin
     next_level<=level;next_state<=env_state;next_attack<=attack;next_decay<=decay;
     next_release<=release_step;next_target<=decay_target;next_limit<=decay_limit;
     if(rising)begin
      next_attack<=safe_a;
      if(a_sum>=8388608)begin next_level<=8388608;next_state<=DECAY;next_decay<=safe_d;next_target<=safe_s;next_limit<=safe_s+safe_d;end
      else begin next_level<=a_sum[23:0];next_state<=ATTACK;end
     end else if(!gate_q&&was_q)begin next_release<=release_now==0?24'd1:{9'd0,release_now};next_state<=level==0?IDLE:RELEASE;end
     else case(env_state)
      IDLE:next_level<=0;
      ATTACK:if(a_sum>=8388608)begin next_level<=8388608;next_state<=DECAY;next_decay<=safe_d;next_target<=safe_s;next_limit<=safe_s+safe_d;end else next_level<=a_sum[23:0];
      DECAY:if(level<=decay_limit)begin next_level<=decay_target;next_state<=SUSTAIN;end else next_level<=level-decay;
      SUSTAIN:next_level<=s_next;
      RELEASE:if(level<=release_step)begin next_level<=0;next_state<=IDLE;end else next_level<=level-release_step;
      default:begin next_level<=0;next_state<=IDLE;end
     endcase
     if(rising)freeze_q<=0;
     else if(!gate_q&&was_q)freeze_q<=coeff[14:0]<(tone==1?15'd2083:15'd1838);
    end
    4:begin
     vel_product<=next_level[23:8]*velocity;
     if(tone==0||pure_q)begin
      calc_phase<=rising&&env_state==IDLE?48'd0:phase_q;
      phase_q<=(rising&&env_state==IDLE?48'd0:phase_q)+{16'd0,step_q};
     end else if(tone==1)begin
      calc_phase<=rising&&env_state==IDLE?48'd0:phase_q;phase_q<=(rising&&env_state==IDLE?48'd0:phase_q)+{16'd0,current_step};
      if(rising)current_step<=step_q;
      else if(current_step<step_q)current_step<=step_q-current_step<=slew?step_q:current_step+slew;
      else if(current_step>step_q)current_step<=current_step-step_q<=slew?step_q:current_step-slew;
     end else if(rising&&env_state==IDLE)begin
      calc_phase<={16'd0,32'h13579bdf+model*32'h10700301};calc_b<=model*32'h17000003;calc_c<=32'h34000000+model*32'h23000501;
      phase_q<={16'd0,32'h13579bdf+model*32'h10700301};phase_b<=model*32'h17000003;phase_c<=32'h34000000+model*32'h23000501;
     end else begin
      calc_phase<={16'd0,phase_q[31:0]+(step_q>>1)};calc_b<=phase_b+step_q-spread;calc_c<=phase_c+step_q+spread;
      phase_q<={16'd0,phase_q[31:0]+(step_q>>1)};phase_b<=phase_b+step_q-spread;phase_c<=phase_c+step_q+spread;
     end
     new_sg<=sg;new_mg<=mg;new_tg<=tg;
     if(rising)begin new_sg<=8388608;new_mg<=8388608;new_tg<=8388608;pluck_left<=96;end
     else if(env_state==IDLE)begin new_sg<=0;new_mg<=0;new_tg<=0;pluck_left<=0;end
     else if(!(env_state==RELEASE&&freeze_q))begin
      new_sg<=sg<=sloss?24'd0:sg-sloss;
      if(env_state!=ATTACK)begin new_mg<=mg<=mloss?24'd0:mg-mloss;new_tg<=tg<=tloss?24'd0:tg-tloss;end
     end
     if(!rising&&pluck_left!=0)pluck_left<=pluck_left-1'b1;
     rnd<={rnd[21:0],rnd[22]^rnd[17]};noise_q<=noise_q+(noise_delta>>>2);
    end
    5:begin
     amplitude<=vel_product[23:7];accumulator<=0;reed_accumulator<=0;
     ring_product<=vel_product[23:7]*new_sg[23:8];
    end
    6:begin mid_product<=body_amp*new_mg[23:8];high_product<=body_amp*new_tg[23:8];end
    51:begin
     // Read-only display tap: reuse this voice's already computed sample.
     if(voice==visual_select)begin
      visual_pcm<=(pure_q||tone<2)?accumulator:reed_accumulator;
      visual_step<=step_q;visual_generation<=gen_q;visual_gate<=gate_q;visual_slot<=voice;
     end
     if(pure_q||tone==0)begin sum_p<=sum_p+accumulator;voice_samples[voice*32+:32]<=accumulator;end
     else if(tone==1)begin sum_g<=sum_g+accumulator;voice_samples[voice*32+:32]<=accumulator;end
     else begin sum_a<=sum_a+reed_accumulator;voice_samples[voice*32+:32]<=reed_accumulator;end
     seen_generation[voice*8+:8]<=gen_q;idle[voice]<=next_state==IDLE;levels[voice*16+:16]<=next_level[23:8];
    end
    59:begin
     cycle<=0;
     if(voice==15)begin busy<=0;done<=1;piano_sum<=sum_p;guitar_sum<=sum_g;accordion_sum<=sum_a;end
     else voice<=voice+1'b1;
    end
   endcase
  end
 end
endmodule
