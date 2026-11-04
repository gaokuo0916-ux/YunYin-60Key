`timescale 1ns/1ps
// Three timbre banks. Coefficients commit atomically at an audio frame boundary.
// A shared multiply converts D's reciprocal and the selected S to a slope;
// no divider or multiplier is added to each voice for parameter editing.
module adsr_parameter_bank(
 input wire clk,sample_tick,edit_valid,input wire [1:0] edit_timbre,input wire reset_defaults,
 input wire [1:0] parameter_id,input wire [5:0] value_index,
 output wire edit_ready,
 output reg [74:0] piano_coeff={18'd171197,18'd311,24'd5452544,15'd1838},
 output reg [74:0] guitar_coeff={18'd171197,18'd801,24'd3774976,15'd2083},
 output reg [74:0] accordion_coeff={18'd11445,18'd223,24'd7465984,15'd3694},
 output reg [23:0] piano_indices={6'd0,6'd10,6'd41,6'd14},
 output reg [23:0] guitar_indices={6'd0,6'd6,6'd28,6'd13},
 output reg [23:0] accordion_indices={6'd14,6'd4,6'd56,6'd8},
 output reg [63:0] piano_values=64'h0001_0194_0065_0187,
 output reg [63:0] guitar_values=64'h0001_0118_0045_0165,
 output reg [63:0] accordion_values=64'h0015_0085_0089_0093);
 reg [14:0] piano_d_recip=15'd1772,guitar_d_recip=15'd2912,accordion_d_recip=15'd4042;
 reg [2:0] stage=0;
 reg [1:0] bank=0;
 reg [74:0] pending_coeff=0;
 reg [23:0] pending_indices=0;
 reg [63:0] pending_values=0;
 reg [14:0] pending_d_recip=0;
 reg [23:0] difference=0;
 reg [38:0] product=0;
 wire [14:0] rounded=product[38:24]+{14'd0,(|product[23:0])};
 wire [23:0] lookup_coeff;
 wire [15:0] lookup_value;
 adsr_parameter_tables lut(parameter_id,value_index,lookup_coeff,lookup_value);
 assign edit_ready=stage==0;
 always @(posedge clk) case(stage)
  0:if((edit_valid || reset_defaults) && edit_timbre<3) begin
      bank<=edit_timbre;
      pending_coeff<=edit_timbre==0?piano_coeff:edit_timbre==1?guitar_coeff:accordion_coeff;
      pending_indices<=edit_timbre==0?piano_indices:edit_timbre==1?guitar_indices:accordion_indices;
      pending_values<=edit_timbre==0?piano_values:edit_timbre==1?guitar_values:accordion_values;
      pending_d_recip<=edit_timbre==0?piano_d_recip:edit_timbre==1?guitar_d_recip:accordion_d_recip;
      if(reset_defaults) begin
          pending_coeff<=edit_timbre==0?{18'd171197,18'd311,24'd5452544,15'd1838}:edit_timbre==1?{18'd171197,18'd801,24'd3774976,15'd2083}:{18'd11445,18'd223,24'd7465984,15'd3694};
          pending_indices<=edit_timbre==0?{6'd0,6'd10,6'd41,6'd14}:edit_timbre==1?{6'd0,6'd6,6'd28,6'd13}:{6'd14,6'd4,6'd56,6'd8};
          pending_values<=edit_timbre==0?64'h0001_0194_0065_0187:edit_timbre==1?64'h0001_0118_0045_0165:64'h0015_0085_0089_0093;
          pending_d_recip<=edit_timbre==0?15'd1772:edit_timbre==1?15'd2912:15'd4042;stage<=4;
      end else begin
          pending_indices[23-6*parameter_id -:6]<=value_index;
          pending_values[63-16*parameter_id -:16]<=lookup_value;
          case(parameter_id)
            0:pending_coeff[74:57]<=lookup_coeff[17:0];
            1:pending_d_recip<=lookup_coeff[14:0];
            2:pending_coeff[38:15]<=lookup_coeff;
            3:pending_coeff[14:0]<=lookup_coeff[14:0];
          endcase
          stage<=1;
      end
    end
  1:begin difference<=24'd8388608-pending_coeff[38:15];stage<=2;end
  2:begin product<=difference*pending_d_recip;stage<=3;end
  3:begin pending_coeff[56:39]<={3'd0,rounded};stage<=4;end
  4:if(sample_tick) begin
      case(bank)
      0:begin piano_coeff<=pending_coeff;piano_indices<=pending_indices;
          piano_values<=pending_values;piano_d_recip<=pending_d_recip;end
      1:begin guitar_coeff<=pending_coeff;guitar_indices<=pending_indices;
          guitar_values<=pending_values;guitar_d_recip<=pending_d_recip;end
      2:begin accordion_coeff<=pending_coeff;accordion_indices<=pending_indices;
          accordion_values<=pending_values;accordion_d_recip<=pending_d_recip;end
      endcase
      stage<=0;
    end
  default:stage<=0;
 endcase
endmodule
