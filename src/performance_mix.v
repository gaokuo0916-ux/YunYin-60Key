`timescale 1ns/1ps
// Shared6144x18 live-audio RAM in three2048-word banks; same18-bit algorithms.
//1=damped-comb/allpass reverb (default),2=chorus,3=125ms feedback delay.
// Audibility calibration: same dry path/RAM; full-scale wet gain 6/4/3 respectively.
//space_amount remains an unused compatibility port; old implementation is archived.
module performance_mix(input wire clk,sample_tick,
 input wire signed [17:0] dry_input,input wire [15:0] level_q15,
 input wire [5:0] space_amount,output reg signed [18:0] mixed=0,
 input wire [1:0] pressure_mode,input wire [5:0] pressure_value,pressure_depth);
 wire [1:0] requested_mode=pressure_mode===2'd1 ?2'd1:pressure_mode===2'd2 ?2'd2:pressure_mode===2'd3 ?2'd3:2'd1;
 reg [1:0] applied_mode=1;reg switch_pending=0,clearing=1;
 reg [12:0] clear_address=0;
 reg signed [34:0] level_product=0;
 wire signed [17:0] dry=level_product[32:15];
 reg signed [17:0] memory0[0:2047] /* synthesis syn_ramstyle = "block_ram" */;
 reg signed [17:0] memory1[0:2047] /* synthesis syn_ramstyle = "block_ram" */;
 reg signed [17:0] memory2[0:2047] /* synthesis syn_ramstyle = "block_ram" */;
 reg [12:0] memory_address;reg memory_we;reg signed [17:0] memory_value;
 reg signed [17:0] memory_q0=0,memory_q1=0,memory_q2=0;reg [1:0] read_bank=0;
 wire signed [17:0] memory_q=read_bank==0?memory_q0:read_bank==1?memory_q1:memory_q2;
 localparam IDLE=0,AMOUNT=1,AMOUNT_WAIT=2,AMOUNT_USE=3,
  R_READ=4,R_WAIT=5,R_LOAD=6,R_MUL=7,R_MUL_WAIT=8,R_WRITE=9,
  AP_READ=10,AP_WAIT=11,AP_LOAD=12,AP_WRITE=13,
  C_READ_A=14,C_WAIT_A=15,C_LOAD_A=16,C_READ_B=17,C_WAIT_B=18,C_LOAD_B=19,
  C_MUL=20,C_MUL_WAIT=21,C_USE=22,C_WRITE=23,
  D_READ=24,D_WAIT=25,D_LOAD=26,D_MUL=27,D_MUL_WAIT=28,D_WRITE=29,
  WET_MUL=30,WET_WAIT=31,WET_USE=32;
 reg [5:0] state=IDLE;
 reg [1:0] tap=0;reg [10:0] comb_pointer[0:3];reg [8:0] ap_pointer[0:1];
 reg signed [17:0] lowpass[0:3];
 reg signed [19:0] comb_sum=0;
 reg signed [17:0] input_sample=0,ap_input=0,ap_output=0;
 reg signed [17:0] chorus_a=0,chorus_b=0,delay_sample=0,wet_sample=0;
 reg signed [20:0] fx_wet=0;
 reg [12:0] ring_pointer=0;
 reg [23:0] chorus_phase=0;
 wire [15:0] chorus_triangle=chorus_phase[23]?~chorus_phase[22:7]:chorus_phase[22:7];
 reg [8:0] chorus_integer=0;reg [7:0] chorus_fraction=0;
 reg [16:0] wet_coefficient=0;
 reg signed [18:0] multiply_x;reg signed [16:0] multiply_y;
 reg signed [35:0] multiply_product=0;
 // Independent controls: screen sets a baseline; pressure adds available headroom.
 // Saturate at full scale. Zero/zero is dry, either control alone can reach full FX.
 wire [6:0] amount_sum={1'b0,pressure_value}+{1'b0,pressure_depth};
 reg [5:0] amount_code=0;
 wire signed [18:0] lowpass_difference=$signed({memory_q[17],memory_q})-$signed({lowpass[tap][17],lowpass[tap]});
 function signed [17:0] clip18(input signed [38:0] value);
  begin clip18=value>39'sd131071 ?18'sd131071:value< -39'sd131072 ?-18'sd131072:value[17:0];end
 endfunction
 function signed [18:0] clip19(input signed [38:0] value);
  begin clip19=value>39'sd262143 ?19'sd262143:value< -39'sd262144 ?-19'sd262144:value[18:0];end
 endfunction
 // Toward-zero feedback avoids a negative one-LSB limit cycle after silence.
 // Legacy space multiplication/rounding is deliberately unchanged.
 function signed [38:0] feedback_q13(input signed [35:0] value);
  reg signed [36:0] biased;
  begin biased=$signed({value[35],value})+(value[35]?37'sd8191:37'sd0);feedback_q13=$signed(biased)>>>13;end
 endfunction
 function signed [17:0] half_zero(input signed [17:0] value);
  reg signed [18:0] biased;
  begin biased=$signed({value[17],value})+(value[17]?19'sd1:19'sd0);half_zero=$signed(biased)>>>1;end
 endfunction
 function [12:0] comb_base(input [1:0] n);
  begin case(n)0:comb_base=0;1:comb_base=503;2:comb_base=1204;default:comb_base=2181;endcase end
 endfunction
 function [10:0] comb_last(input [1:0] n);
  begin case(n)0:comb_last=502;1:comb_last=700;2:comb_last=976;default:comb_last=1372;endcase end
 endfunction
 function [16:0] target_coefficient(input [1:0] mode,input [5:0] amount,input quitting);
  reg [16:0] n;
  begin n={11'd0,amount}+17'd1;
   if(quitting||amount==0)target_coefficient=0;
   else case(mode)1:target_coefficient=(n<<9)+(n<<8);2:target_coefficient=n<<9;default:target_coefficient=(n<<8)+(n<<7);endcase
  end
 endfunction
 wire [16:0] coefficient_target=target_coefficient(applied_mode,amount_code,switch_pending||requested_mode!=applied_mode);
 wire chorus_second=state==C_READ_B || state==C_WAIT_B || state==C_LOAD_B;
 wire [12:0] ring_distance=applied_mode==3?13'd6104:13'd488+{4'd0,chorus_integer}+{12'd0,chorus_second};
 wire [13:0] ring_difference={1'b0,ring_pointer}-{1'b0,ring_distance};
 wire [12:0] ring_read_address=ring_difference[13]?ring_difference[12:0]+13'd6144:ring_difference[12:0];
 integer i;
 initial begin for(i=0;i<4;i=i+1)begin comb_pointer[i]=0;lowpass[i]=0;end ap_pointer[0]=0;ap_pointer[1]=0;end
 always @(*)begin
  multiply_x=0;multiply_y=0;
  case(state)
   R_MUL,R_MUL_WAIT:begin multiply_x={lowpass[tap][17],lowpass[tap]};multiply_y=17'sd6390;end
   C_MUL,C_MUL_WAIT:begin multiply_x=$signed({chorus_b[17],chorus_b})-$signed({chorus_a[17],chorus_a});multiply_y={4'd0,chorus_fraction,5'd0};end
   D_MUL,D_MUL_WAIT:begin multiply_x={delay_sample[17],delay_sample};multiply_y=17'sd4915;end
   WET_MUL,WET_WAIT:begin multiply_x={wet_sample[17],wet_sample};multiply_y=$signed(wet_coefficient);end
  endcase
 end
 // Exclusive synchronous access avoids read-before-write inference.
 always @(*)begin
  memory_address=0;memory_we=0;memory_value=0;
  if(clearing)begin memory_address=clear_address;memory_we=1;end
  else case(state)
   R_READ,R_WAIT,R_LOAD,R_MUL,R_MUL_WAIT,R_WRITE:begin
    memory_address=comb_base(tap)+{2'd0,comb_pointer[tap]};
    if(state==R_WRITE)begin memory_we=1;memory_value=clip18(($signed(input_sample)>>>3)+feedback_q13(multiply_product));end
   end
   AP_READ,AP_WAIT,AP_LOAD,AP_WRITE:begin
    memory_address=(tap[0]?13'd3703:13'd3554)+{4'd0,ap_pointer[tap[0]]};
    if(state==AP_WRITE)begin memory_we=1;memory_value=clip18($signed(ap_input)+half_zero(ap_output));end
   end
   C_READ_A,C_WAIT_A,C_LOAD_A:memory_address=ring_read_address;
   C_READ_B,C_WAIT_B,C_LOAD_B:memory_address=ring_read_address;
   C_WRITE:begin memory_address=ring_pointer;memory_we=1;memory_value=$signed(input_sample)>>>2;end
   D_READ,D_WAIT,D_LOAD,D_MUL,D_MUL_WAIT:memory_address=ring_read_address;
   D_WRITE:begin memory_address=ring_pointer;memory_we=1;memory_value=clip18(($signed(input_sample)>>>2)+feedback_q13(multiply_product));end
  endcase
 end
 always @(posedge clk)begin
  if(memory_address[12:11]==0)begin
   if(memory_we)memory0[memory_address[10:0]]<=memory_value;else memory_q0<=memory0[memory_address[10:0]];
  end
  if(memory_address[12:11]==1)begin
   if(memory_we)memory1[memory_address[10:0]]<=memory_value;else memory_q1<=memory1[memory_address[10:0]];
  end
  if(memory_address[12:11]==2)begin
   if(memory_we)memory2[memory_address[10:0]]<=memory_value;else memory_q2<=memory2[memory_address[10:0]];
  end
  if(!memory_we)read_bank<=memory_address[12:11];
  level_product<=dry_input*$signed({1'b0,level_q15});
  multiply_product<=multiply_x*multiply_y;
  mixed<=clip19($signed(dry)+$signed(fx_wet));
 end
 always @(posedge clk)begin
  if(clearing)begin
   state<=IDLE;fx_wet<=0;
   if(clear_address==6143)begin
    clearing<=0;clear_address<=0;applied_mode<=requested_mode;switch_pending<=0;
    ring_pointer<=0;chorus_phase<=0;wet_coefficient<=0;comb_sum<=0;tap<=0;
    for(i=0;i<4;i=i+1)begin comb_pointer[i]<=0;lowpass[i]<=0;end
    ap_pointer[0]<=0;ap_pointer[1]<=0;
   end else clear_address<=clear_address+1'b1;
  end else if(switch_pending && (state==IDLE&&wet_coefficient==0&&fx_wet==0))begin
   clearing<=1;clear_address<=0;state<=IDLE;
  end else begin
   if(requested_mode!=applied_mode && !switch_pending)begin switch_pending<=1;end
   begin
    if(sample_tick && state==IDLE)begin
     input_sample<=dry;state<=AMOUNT;
     chorus_integer<=chorus_triangle[15:7];chorus_fraction<={chorus_triangle[6:0],1'b0};
     if(applied_mode==2)chorus_phase<=chorus_phase+24'd256;
    end
    case(state)
     AMOUNT:begin amount_code<=amount_sum[6]?6'd63:amount_sum[5:0];state<=AMOUNT_WAIT;end
     AMOUNT_WAIT:state<=AMOUNT_USE;
     AMOUNT_USE:begin
      if(wet_coefficient>coefficient_target)wet_coefficient<=wet_coefficient-coefficient_target>128?wet_coefficient-17'd128:coefficient_target;
      else if(wet_coefficient<coefficient_target)wet_coefficient<=coefficient_target-wet_coefficient>128?wet_coefficient+17'd128:coefficient_target;
      if(applied_mode==1)begin tap<=0;comb_sum<=0;state<=R_READ;end
      else state<=applied_mode==2?C_READ_A:D_READ;
     end
     R_READ:state<=R_WAIT;
     R_WAIT:state<=R_LOAD;
     R_LOAD:begin
      comb_sum<=comb_sum+$signed(memory_q);
      if(lowpass_difference>= -19'sd3 && lowpass_difference<=19'sd3)lowpass[tap]<=memory_q;
      else lowpass[tap]<=clip18($signed(lowpass[tap])+($signed(lowpass_difference)>>>2));
      state<=R_MUL;
     end
     R_MUL:state<=R_MUL_WAIT;
     R_MUL_WAIT:state<=R_WRITE;
     R_WRITE:begin
      comb_pointer[tap]<=comb_pointer[tap]==comb_last(tap)?11'd0:comb_pointer[tap]+1'b1;
      if(tap==3)begin ap_input<=clip18($signed(comb_sum)>>>2);tap<=0;state<=AP_READ;end
      else begin tap<=tap+1'b1;state<=R_READ;end
     end
     AP_READ:state<=AP_WAIT;
     AP_WAIT:state<=AP_LOAD;
     AP_LOAD:begin ap_output<=clip18($signed(memory_q)-half_zero(ap_input));state<=AP_WRITE;end
     AP_WRITE:begin
      ap_pointer[tap[0]]<=ap_pointer[tap[0]]==(tap[0]?9'd420:9'd148)?9'd0:ap_pointer[tap[0]]+1'b1;
      if(tap==0)begin ap_input<=ap_output;tap<=1;state<=AP_READ;end
      else begin wet_sample<=ap_output;state<=WET_MUL;end
     end
     C_READ_A:state<=C_WAIT_A;
     C_WAIT_A:state<=C_LOAD_A;
     C_LOAD_A:begin chorus_a<=memory_q;state<=C_READ_B;end
     C_READ_B:state<=C_WAIT_B;
     C_WAIT_B:state<=C_LOAD_B;
     C_LOAD_B:begin chorus_b<=memory_q;state<=C_MUL;end
     C_MUL:state<=C_MUL_WAIT;
     C_MUL_WAIT:state<=C_USE;
     C_USE:begin wet_sample<=clip18($signed(chorus_a)+($signed(multiply_product)>>>13));state<=C_WRITE;end
     C_WRITE:begin ring_pointer<=ring_pointer==6143?13'd0:ring_pointer+1'b1;state<=WET_MUL;end
     D_READ:state<=D_WAIT;
     D_WAIT:state<=D_LOAD;
     D_LOAD:begin delay_sample<=memory_q;wet_sample<=memory_q;state<=D_MUL;end
     D_MUL:state<=D_MUL_WAIT;
     D_MUL_WAIT:state<=D_WRITE;
     D_WRITE:begin ring_pointer<=ring_pointer==6143?13'd0:ring_pointer+1'b1;state<=WET_MUL;end
     WET_MUL:state<=WET_WAIT;
     WET_WAIT:state<=WET_USE;
     WET_USE:begin fx_wet<=$signed(multiply_product)>>>13;state<=IDLE;end
    endcase
   end
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(sample_tick && applied_mode!=0 && !clearing && state!=IDLE)$fatal(1,"effect frame deadline");
 // synthesis translate_on
endmodule

