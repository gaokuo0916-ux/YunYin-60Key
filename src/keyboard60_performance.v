`timescale 1ns/1ps
// One shared ROM/multiplier visits all 60 pitches in 300 cycles per 1024-cycle frame.
// C2..B6 is the centre octave setting. Bend/vibrato affect the last held key only.
module keyboard60_performance(input wire clk,sample_tick,input wire [59:0] gates,
 input wire [23:0] settings,input wire [2:0] octave,
 output reg [31:0] phase_step=0,output reg [15:0] level_q15=32768,
 output reg [5:0] space_amount=0,output wire [59:0] bend_target,
 input wire [5:0] read_key);
 // Only the allocator's current key is read. A 1920-bit register/mux bus
 // would be unnecessarily expensive to route on this already busy device.
 reg [31:0] step_memory[0:63] /* synthesis syn_ramstyle = "block_ram" */;
 integer init_key;initial for(init_key=0;init_key<64;init_key=init_key+1)step_memory[init_key]=0;
 always @(posedge clk)phase_step<=step_memory[read_key];
 reg [59:0] previous=0;reg [5:0] selected=0;
 wire [59:0] rises=gates&~previous;
 assign bend_target=gates[selected]?(60'b1<<selected):60'd0;
 integer i;always @(posedge clk)begin
  previous<=gates;
  if(rises!=0)begin for(i=0;i<60;i=i+1)if(rises[i])selected<=i;end
  else if(!gates[selected])begin for(i=0;i<60;i=i+1)if(gates[i])selected<=i;end
 end
 reg [23:0] lfo=0;wire signed [8:0] triangle=(lfo[23]==lfo[22])?
  $signed({lfo[23],lfo[23:16]}):(9'sd127-$signed({1'b0,lfo[23:16]}));
 reg signed [15:0] vibrato_product=0;reg signed [9:0] offset=0;reg [7:0] pitch_index=80;
 wire [15:0] level_target=settings[23:18]==0?0:({10'd0,settings[23:18]}+16'd1)<<9;
 reg [59:0] frame_gates=0;reg [5:0] frame_selected=0,key_index=0;
 reg [7:0] frame_index=80;reg [2:0] frame_octave=2,stage=0;reg updating=1;
 wire [7:0] effective_index=frame_gates[key_index]&&key_index==frame_selected?frame_index:8'd80;
 wire [31:0] base_step;wire [17:0] ratio;
 keyboard60_tables tables(clk,key_index,effective_index,base_step,ratio);
 reg [49:0] product=0;reg [31:0] scaled=0;
 always @(posedge clk)begin
  vibrato_product<=triangle*$signed({1'b0,settings[11:6]});
  offset<=($signed({1'b0,settings[17:12]})-10'sd32)*10'sd2+(vibrato_product>>>8);
  if(offset< -80)pitch_index<=0;else if(offset>80)pitch_index<=160;else pitch_index<=8'd80+offset[7:0];
  if(sample_tick)begin
   lfo<=lfo+24'd1718;space_amount<=settings[5:0];
   if(level_q15>level_target)level_q15<=level_q15-level_target<=512?level_target:level_q15-16'd512;
   else if(level_q15<level_target)level_q15<=level_target-level_q15<=512?level_target:level_q15+16'd512;
   key_index<=0;stage<=0;updating<=1;frame_gates<=gates;frame_selected<=selected;frame_index<=pitch_index;frame_octave<=octave;
  end else if(updating)begin
   case(stage)
    2:product<=base_step*ratio;
    3:case(frame_octave)
     0:scaled<=product[49:18];1:scaled<=product[48:17];2:scaled<=product[47:16];
     3:scaled<=product[46:15];default:scaled<=product[45:14];
    endcase
    4:begin step_memory[key_index]<=scaled;
     if(key_index==59)updating<=0;else begin key_index<=key_index+1'b1;stage<=0;end
    end
   endcase
   if(stage!=4)stage<=stage+1'b1;
  end
 end
endmodule
