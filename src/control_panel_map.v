`timescale 1ns/1ps
// CH0 octave, CH1 volume, CH2 timbre, CH3 vibrato depth,
// CH4 sustain pressure, CH5 upward bend pressure, CH6 start/stop, CH7 pause.
// Absolute knobs issue edits only on startup or deliberate movement, so an
// unmoved physical knob cannot continually overwrite screen/App settings.
module control_panel_map(input wire clk,valid,online,input wire [95:0] samples,
 input wire safe_to_transpose,running,
 output reg octave_valid=0,output reg [2:0] octave_value=2,
 output reg timbre_valid=0,output reg [1:0] timbre_value=0,
 output reg start=0,stop=0,pause=0,
 output reg [1:0] edit=0,output reg [11:0] values=0,
 output reg sustain=0,output reg [5:0] bend=0);
 reg initialized=0;reg [11:0] volume_anchor=0,trem_anchor=0;
 reg [2:0] oct=2,oct_candidate=2;reg [1:0] tone=0,tone_candidate=0;
 reg [1:0] oct_count=0,tone_count=0;
 reg oct_pending=0;
 reg [1:0] buttons=0;reg [1:0] button_count[0:1];
 integer i;initial for(i=0;i<2;i=i+1)button_count[i]=0;
 wire [11:0] a0=samples[11:0],a1=samples[23:12],a2=samples[35:24],a3=samples[47:36];
 wire [11:0] p1=samples[59:48],p2=samples[71:60];
 wire [2:0] oct_raw=a0<819?0:a0<1638?1:a0<2457?2:a0<3276?3:4;
 wire [1:0] tone_raw=a2<1365?0:a2<2730?1:2;
 // Constant thresholds avoid inferring DSP multipliers for knob quantization.
 wire [11:0] oct_up=oct==0?851:oct==1?1670:oct==2?2489:oct==3?3308:4095;
 wire [11:0] oct_down=oct==0?0:oct==1?787:oct==2?1606:oct==3?2425:3244;
 wire oct_far=(oct_raw>oct && a0>oct_up)||(oct_raw<oct && a0<oct_down);
 wire tone_far=(tone_raw>tone && a2>(tone==0?1397:2762)) ||
               (tone_raw<tone && a2<(tone==1?1333:2698));
 wire volume_move=a1>volume_anchor?(a1-volume_anchor>=64):(volume_anchor-a1>=64);
 wire trem_move=a3>trem_anchor?(a3-trem_anchor>=64):(trem_anchor-a3>=64);
 wire [5:0] bend_target=p2<=12'd128 ? 6'd0 : {1'b0,p2[11:7]};
 always @(posedge clk)begin
  octave_valid<=0;timbre_valid<=0;start<=0;stop<=0;pause<=0;edit<=0;
  if(!online)begin initialized<=0;oct_pending<=0;sustain<=0;bend<=0;end
  else begin
   if(oct_pending && safe_to_transpose)begin octave_value<=oct;octave_valid<=1;oct_pending<=0;end
   if(valid)begin
    if(!initialized)begin
     initialized<=1;oct<=oct_raw;oct_candidate<=oct_raw;oct_pending<=1;oct_count<=0;
     tone<=tone_raw;tone_candidate<=tone_raw;tone_count<=0;timbre_value<=tone_raw;timbre_valid<=1;
     volume_anchor<=a1;trem_anchor<=a3;values<={a1[11:6],a3[11:6]};edit<=3;
     buttons<={samples[95:84]<1024,samples[83:72]<1024};
     button_count[0]<=0;button_count[1]<=0;
    end else begin
     if(volume_move)begin volume_anchor<=a1;values[11:6]<=a1[11:6];edit[0]<=1;end
     if(trem_move)begin trem_anchor<=a3;values[5:0]<=a3[11:6];edit[1]<=1;end
     if(!oct_far)oct_count<=0;
     else if(oct_candidate!=oct_raw)begin oct_candidate<=oct_raw;oct_count<=1;end
     else if(oct_count==2)begin oct<=oct_raw;oct_pending<=1;oct_count<=0;end else oct_count<=oct_count+1'b1;
     if(!tone_far)tone_count<=0;
     else if(tone_candidate!=tone_raw)begin tone_candidate<=tone_raw;tone_count<=1;end
     else if(tone_count==2)begin tone<=tone_raw;timbre_value<=tone_raw;timbre_valid<=1;tone_count<=0;end else tone_count<=tone_count+1'b1;
     for(i=0;i<2;i=i+1)begin
      if((buttons[i] && samples[72+i*12+:12]>3072)||(!buttons[i] && samples[72+i*12+:12]<1024))begin
       if(button_count[i]==2)begin
        buttons[i]<=!buttons[i];button_count[i]<=0;
        if(!buttons[i])begin
         if(i==1)pause<=1;else if(running)stop<=1;else start<=1;
        end
       end else button_count[i]<=button_count[i]+1'b1;
      end else button_count[i]<=0;
     end
    end
    if(p1>384)sustain<=1;else if(p1<256)sustain<=0;
    // Rate-limit pressure bend codes; no change to the existing pitch ROM.
    if(bend_target>bend)bend<=bend_target-bend>4?bend+6'd4:bend_target;
    else if(bend_target<bend)bend<=bend-bend_target>4?bend-6'd4:bend_target;
   end
  end
 end
endmodule
