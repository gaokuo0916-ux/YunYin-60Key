`timescale 1ns/1ps
// Direct geometry and a small monochrome font, without a full framebuffer.
// The four fixed-width phases are explicitly labelled a stage illustration.
module c63e_renderer_reference #(parameter integer RHYTHM_ENABLE=0,MULTISONG_ENABLE=0)(input wire clk,input wire [11:0] x,y,
 input wire [1:0] timbre,input wire [1:0] touch_status,
 input wire [6:0] note_gate,input wire [23:0] indices,
 input wire [63:0] values,input wire [6:0] sustain,
 output wire [23:0] rgb,
 input wire waveform_view,waveform_valid,
 input wire signed [15:0] waveform_sample,
 input wire [1:0] waveform_scale,
 input wire [15:0] output_peak,
 input wire score_page,input wire [3:0] bt_flags,upload_error,
 input wire [59:0] score_numbers,input wire [2:0] guide_state,input wire live_page,
 input wire [1:0] graph_mode,input wire [7:0] spectrum_height,
 input wire spectrum_valid,input wire [2:0] spectrum_zoom,
 input wire phase_pixel,phase_valid,input wire [1:0] phase_gain,input wire [2:0] phase_delay,
 input wire rhythm_page,input wire [159:0] rhythm_status,input wire [191:0] rhythm_numbers,
 input wire native_missing,input wire [59:0] full_keys,full_target,input wire [6:0] keyboard_base,input wire [23:0] keyboard_color,input wire [127:0] challenge_preview,input wire preview_ready,
 input wire [19:0] spectrum_peak_bcd,input wire spectrum_peak_valid,spectrum_auto,input wire [1:0] pressure_mode);
 wire [1:0] fx_mode=pressure_mode===2'd1 ?2'd1:pressure_mode===2'd2 ?2'd2:pressure_mode===2'd3 ?2'd3:2'd0;
 function [23:0] palette_rgb(input [3:0] index);begin case(index)
 4'd0:palette_rgb=24'h000000;
 4'd1:palette_rgb=24'h007aff;
 4'd2:palette_rgb=24'h303943;
 4'd3:palette_rgb=24'h34c759;
 4'd4:palette_rgb=24'hc5dcf4;
 4'd5:palette_rgb=24'hc6c6c8;
 4'd6:palette_rgb=24'hc7c7cc;
 4'd7:palette_rgb=24'hd6e9ff;
 4'd8:palette_rgb=24'he6b647;
 4'd9:palette_rgb=24'hf0f2f4;
 4'd10:palette_rgb=24'hf2f2f7;
 4'd11:palette_rgb=24'hff3b30;
 4'd12:palette_rgb=24'hff9500;
 4'd13:palette_rgb=24'hffe5e3;
 4'd14:palette_rgb=24'hfff4e5;
 4'd15:palette_rgb=24'hffffff;
 default:palette_rgb=24'hffffff;endcase end endfunction
 function [3:0] palette_code(input [23:0] rgb);begin case(rgb)
 24'h000000:palette_code=4'd0;
 24'h007aff:palette_code=4'd1;
 24'h303943:palette_code=4'd2;
 24'h34c759:palette_code=4'd3;
 24'hc5dcf4:palette_code=4'd4;
 24'hc6c6c8:palette_code=4'd5;
 24'hc7c7cc:palette_code=4'd6;
 24'hd6e9ff:palette_code=4'd7;
 24'he6b647:palette_code=4'd8;
 24'hf0f2f4:palette_code=4'd9;
 24'hf2f2f7:palette_code=4'd10;
 24'hff3b30:palette_code=4'd11;
 24'hff9500:palette_code=4'd12;
 24'hffe5e3:palette_code=4'd13;
 24'hfff4e5:palette_code=4'd14;
 24'hffffff:palette_code=4'd15;
 default:palette_code=4'd15;endcase end endfunction
 reg spectrum_text=0,spectrum_text1=0;reg [7:0] spectrum_code=0,spectrum_code1=0;
 reg [3:0] spectrum_character=0,spectrum_digit=0;reg [2:0] spectrum_mark=0;
 reg [11:0] spectrum_left=0;
 reg [3:0] background;
 reg text_hit,number_hit;
 reg zoom=0;
 reg [6:0] message;
 reg [3:0] character,row,column,digit;
 reg [11:0] left,top;
 reg [1:0] slider_row;
 reg [5:0] slider_index;
 reg [15:0] numeric;
 reg [11:0] knob,graph_y;
 reg [6:0] fraction;
 // Preserve the exact graph arithmetic; use spare DSPs instead of long LUT multipliers.
 reg [13:0] decay_line /* synthesis syn_dspstyle = "dsp" */;
 reg [13:0] release_line /* synthesis syn_dspstyle = "dsp" */;
 // Geometry, character selection and font lookup are separate timing stages.
 reg [3:0] bg1=0,bg2=0,bg3=0;
 reg hit1=0,hit2=0,hit3=0,num1=0;
 reg game1=0,game2=0,game3=0;
 reg [6:0] msg1=0;
 reg [3:0] chr1=0,row1=0,col1=0,dig1=0,row2=0,col2=0;
 reg [7:0] code2=0;
 reg wave_hit1=0;
 reg [6:0] wave_row1=0;
 reg [3:0] wave_color1=0;
 reg spectrum_hit1=0,phase_hit1=0;
 reg [8:0] spectrum_row1=0;
 reg signed [15:0] wave_scaled;
 reg [3:0] wave_shift=7;
 integer peak_bit;
 reg [3:0] peak_msb;
 always @(*)begin
  peak_msb=0;for(peak_bit=0;peak_bit<16;peak_bit=peak_bit+1)if(output_peak[peak_bit])peak_msb=peak_bit;
 end
 always @(posedge clk)case(waveform_scale)
  0:wave_shift<=9;1:wave_shift<=7;2:wave_shift<=6;
  default:wave_shift<=peak_msb>5?peak_msb-5:0;
 endcase
 wire signed [6:0] wave_limited=wave_scaled>16'sd63 ? 7'sd63 :
     wave_scaled< -16'sd64 ? 7'b1000000 : wave_scaled[6:0];
 wire [7:0] wave_y=8'd159-{{1{wave_limited[6]}},wave_limited};
 // The synchronous RAM read aligns with geometry stage 1, not stage 0.
 always @(*) wave_scaled=$signed(waveform_sample)>>>wave_shift;
 wire [7:0] digit_code;
 reg [7:0] text_code=0;
 reg [7:0] label_codes[0:2047] /* synthesis syn_ramstyle = "block_ram" */;
 initial begin
  label_codes[0]=8'd1;
  label_codes[1]=8'd2;
  label_codes[2]=8'd0;
  label_codes[3]=8'd0;
  label_codes[4]=8'd0;
  label_codes[5]=8'd0;
  label_codes[6]=8'd0;
  label_codes[7]=8'd0;
  label_codes[8]=8'd0;
  label_codes[9]=8'd0;
  label_codes[10]=8'd0;
  label_codes[11]=8'd0;
  label_codes[12]=8'd0;
  label_codes[13]=8'd0;
  label_codes[14]=8'd0;
  label_codes[15]=8'd0;
  label_codes[16]=8'd3;
  label_codes[17]=8'd4;
  label_codes[18]=8'd0;
  label_codes[19]=8'd0;
  label_codes[20]=8'd0;
  label_codes[21]=8'd0;
  label_codes[22]=8'd0;
  label_codes[23]=8'd0;
  label_codes[24]=8'd0;
  label_codes[25]=8'd0;
  label_codes[26]=8'd0;
  label_codes[27]=8'd0;
  label_codes[28]=8'd0;
  label_codes[29]=8'd0;
  label_codes[30]=8'd0;
  label_codes[31]=8'd0;
  label_codes[32]=8'd5;
  label_codes[33]=8'd6;
  label_codes[34]=8'd0;
  label_codes[35]=8'd0;
  label_codes[36]=8'd0;
  label_codes[37]=8'd0;
  label_codes[38]=8'd0;
  label_codes[39]=8'd0;
  label_codes[40]=8'd0;
  label_codes[41]=8'd0;
  label_codes[42]=8'd0;
  label_codes[43]=8'd0;
  label_codes[44]=8'd0;
  label_codes[45]=8'd0;
  label_codes[46]=8'd0;
  label_codes[47]=8'd0;
  label_codes[48]=8'd44;
  label_codes[49]=8'd45;
  label_codes[50]=8'd7;
  label_codes[51]=8'd8;
  label_codes[52]=8'd0;
  label_codes[53]=8'd0;
  label_codes[54]=8'd0;
  label_codes[55]=8'd0;
  label_codes[56]=8'd0;
  label_codes[57]=8'd0;
  label_codes[58]=8'd0;
  label_codes[59]=8'd0;
  label_codes[60]=8'd0;
  label_codes[61]=8'd0;
  label_codes[62]=8'd0;
  label_codes[63]=8'd0;
  label_codes[64]=8'd9;
  label_codes[65]=8'd10;
  label_codes[66]=8'd11;
  label_codes[67]=8'd12;
  label_codes[68]=8'd0;
  label_codes[69]=8'd0;
  label_codes[70]=8'd0;
  label_codes[71]=8'd0;
  label_codes[72]=8'd0;
  label_codes[73]=8'd0;
  label_codes[74]=8'd0;
  label_codes[75]=8'd0;
  label_codes[76]=8'd0;
  label_codes[77]=8'd0;
  label_codes[78]=8'd0;
  label_codes[79]=8'd0;
  label_codes[80]=8'd13;
  label_codes[81]=8'd14;
  label_codes[82]=8'd17;
  label_codes[83]=8'd18;
  label_codes[84]=8'd19;
  label_codes[85]=8'd0;
  label_codes[86]=8'd0;
  label_codes[87]=8'd0;
  label_codes[88]=8'd0;
  label_codes[89]=8'd0;
  label_codes[90]=8'd0;
  label_codes[91]=8'd0;
  label_codes[92]=8'd0;
  label_codes[93]=8'd0;
  label_codes[94]=8'd0;
  label_codes[95]=8'd0;
  label_codes[96]=8'd13;
  label_codes[97]=8'd14;
  label_codes[98]=8'd15;
  label_codes[99]=8'd16;
  label_codes[100]=8'd0;
  label_codes[101]=8'd0;
  label_codes[102]=8'd0;
  label_codes[103]=8'd0;
  label_codes[104]=8'd0;
  label_codes[105]=8'd0;
  label_codes[106]=8'd0;
  label_codes[107]=8'd0;
  label_codes[108]=8'd0;
  label_codes[109]=8'd0;
  label_codes[110]=8'd0;
  label_codes[111]=8'd0;
  label_codes[112]=8'd20;
  label_codes[113]=8'd21;
  label_codes[114]=8'd17;
  label_codes[115]=8'd22;
  label_codes[116]=8'd23;
  label_codes[117]=8'd0;
  label_codes[118]=8'd0;
  label_codes[119]=8'd0;
  label_codes[120]=8'd0;
  label_codes[121]=8'd0;
  label_codes[122]=8'd0;
  label_codes[123]=8'd0;
  label_codes[124]=8'd0;
  label_codes[125]=8'd0;
  label_codes[126]=8'd0;
  label_codes[127]=8'd0;
  label_codes[128]=8'd69;
  label_codes[129]=8'd70;
  label_codes[130]=8'd71;
  label_codes[131]=8'd72;
  label_codes[132]=8'd0;
  label_codes[133]=8'd0;
  label_codes[134]=8'd0;
  label_codes[135]=8'd0;
  label_codes[136]=8'd0;
  label_codes[137]=8'd0;
  label_codes[138]=8'd0;
  label_codes[139]=8'd0;
  label_codes[140]=8'd0;
  label_codes[141]=8'd0;
  label_codes[142]=8'd0;
  label_codes[143]=8'd0;
  label_codes[144]=8'd40;
  label_codes[145]=8'd30;
  label_codes[146]=8'd1;
  label_codes[147]=8'd0;
  label_codes[148]=8'd0;
  label_codes[149]=8'd0;
  label_codes[150]=8'd0;
  label_codes[151]=8'd0;
  label_codes[152]=8'd0;
  label_codes[153]=8'd0;
  label_codes[154]=8'd0;
  label_codes[155]=8'd0;
  label_codes[156]=8'd0;
  label_codes[157]=8'd0;
  label_codes[158]=8'd0;
  label_codes[159]=8'd0;
  label_codes[160]=8'd41;
  label_codes[161]=8'd31;
  label_codes[162]=8'd32;
  label_codes[163]=8'd0;
  label_codes[164]=8'd0;
  label_codes[165]=8'd0;
  label_codes[166]=8'd0;
  label_codes[167]=8'd0;
  label_codes[168]=8'd0;
  label_codes[169]=8'd0;
  label_codes[170]=8'd0;
  label_codes[171]=8'd0;
  label_codes[172]=8'd0;
  label_codes[173]=8'd0;
  label_codes[174]=8'd0;
  label_codes[175]=8'd0;
  label_codes[176]=8'd42;
  label_codes[177]=8'd33;
  label_codes[178]=8'd23;
  label_codes[179]=8'd0;
  label_codes[180]=8'd0;
  label_codes[181]=8'd0;
  label_codes[182]=8'd0;
  label_codes[183]=8'd0;
  label_codes[184]=8'd0;
  label_codes[185]=8'd0;
  label_codes[186]=8'd0;
  label_codes[187]=8'd0;
  label_codes[188]=8'd0;
  label_codes[189]=8'd0;
  label_codes[190]=8'd0;
  label_codes[191]=8'd0;
  label_codes[192]=8'd43;
  label_codes[193]=8'd34;
  label_codes[194]=8'd35;
  label_codes[195]=8'd0;
  label_codes[196]=8'd0;
  label_codes[197]=8'd0;
  label_codes[198]=8'd0;
  label_codes[199]=8'd0;
  label_codes[200]=8'd0;
  label_codes[201]=8'd0;
  label_codes[202]=8'd0;
  label_codes[203]=8'd0;
  label_codes[204]=8'd0;
  label_codes[205]=8'd0;
  label_codes[206]=8'd0;
  label_codes[207]=8'd0;
  label_codes[208]=8'd36;
  label_codes[209]=8'd37;
  label_codes[210]=8'd0;
  label_codes[211]=8'd0;
  label_codes[212]=8'd0;
  label_codes[213]=8'd0;
  label_codes[214]=8'd0;
  label_codes[215]=8'd0;
  label_codes[216]=8'd0;
  label_codes[217]=8'd0;
  label_codes[218]=8'd0;
  label_codes[219]=8'd0;
  label_codes[220]=8'd0;
  label_codes[221]=8'd0;
  label_codes[222]=8'd0;
  label_codes[223]=8'd0;
  label_codes[224]=8'd60;
  label_codes[225]=8'd0;
  label_codes[226]=8'd0;
  label_codes[227]=8'd0;
  label_codes[228]=8'd0;
  label_codes[229]=8'd0;
  label_codes[230]=8'd0;
  label_codes[231]=8'd0;
  label_codes[232]=8'd0;
  label_codes[233]=8'd0;
  label_codes[234]=8'd0;
  label_codes[235]=8'd0;
  label_codes[236]=8'd0;
  label_codes[237]=8'd0;
  label_codes[238]=8'd0;
  label_codes[239]=8'd0;
  label_codes[240]=8'd46;
  label_codes[241]=8'd41;
  label_codes[242]=8'd47;
  label_codes[243]=8'd48;
  label_codes[244]=8'd49;
  label_codes[245]=8'd40;
  label_codes[246]=8'd50;
  label_codes[247]=8'd0;
  label_codes[248]=8'd0;
  label_codes[249]=8'd0;
  label_codes[250]=8'd0;
  label_codes[251]=8'd0;
  label_codes[252]=8'd0;
  label_codes[253]=8'd0;
  label_codes[254]=8'd0;
  label_codes[255]=8'd0;
  label_codes[256]=8'd64;
  label_codes[257]=8'd65;
  label_codes[258]=8'd66;
  label_codes[259]=8'd67;
  label_codes[260]=8'd68;
  label_codes[261]=8'd39;
  label_codes[262]=8'd0;
  label_codes[263]=8'd0;
  label_codes[264]=8'd0;
  label_codes[265]=8'd0;
  label_codes[266]=8'd0;
  label_codes[267]=8'd0;
  label_codes[268]=8'd0;
  label_codes[269]=8'd0;
  label_codes[270]=8'd0;
  label_codes[271]=8'd0;
  label_codes[272]=8'd24;
  label_codes[273]=8'd25;
  label_codes[274]=8'd28;
  label_codes[275]=8'd29;
  label_codes[276]=8'd0;
  label_codes[277]=8'd0;
  label_codes[278]=8'd0;
  label_codes[279]=8'd0;
  label_codes[280]=8'd0;
  label_codes[281]=8'd0;
  label_codes[282]=8'd0;
  label_codes[283]=8'd0;
  label_codes[284]=8'd0;
  label_codes[285]=8'd0;
  label_codes[286]=8'd0;
  label_codes[287]=8'd0;
  label_codes[288]=8'd1;
  label_codes[289]=8'd75;
  label_codes[290]=8'd0;
  label_codes[291]=8'd0;
  label_codes[292]=8'd0;
  label_codes[293]=8'd0;
  label_codes[294]=8'd0;
  label_codes[295]=8'd0;
  label_codes[296]=8'd0;
  label_codes[297]=8'd0;
  label_codes[298]=8'd0;
  label_codes[299]=8'd0;
  label_codes[300]=8'd0;
  label_codes[301]=8'd0;
  label_codes[302]=8'd0;
  label_codes[303]=8'd0;
  label_codes[304]=8'd73;
  label_codes[305]=8'd74;
  label_codes[306]=8'd7;
  label_codes[307]=8'd8;
  label_codes[308]=8'd0;
  label_codes[309]=8'd0;
  label_codes[310]=8'd0;
  label_codes[311]=8'd0;
  label_codes[312]=8'd0;
  label_codes[313]=8'd0;
  label_codes[314]=8'd0;
  label_codes[315]=8'd0;
  label_codes[316]=8'd0;
  label_codes[317]=8'd0;
  label_codes[318]=8'd0;
  label_codes[319]=8'd0;
  label_codes[320]=8'd76;
  label_codes[321]=8'd77;
  label_codes[322]=8'd78;
  label_codes[323]=8'd51;
  label_codes[324]=8'd0;
  label_codes[325]=8'd0;
  label_codes[326]=8'd0;
  label_codes[327]=8'd0;
  label_codes[328]=8'd0;
  label_codes[329]=8'd0;
  label_codes[330]=8'd0;
  label_codes[331]=8'd0;
  label_codes[332]=8'd0;
  label_codes[333]=8'd0;
  label_codes[334]=8'd0;
  label_codes[335]=8'd0;
  label_codes[336]=8'd76;
  label_codes[337]=8'd77;
  label_codes[338]=8'd78;
  label_codes[339]=8'd54;
  label_codes[340]=8'd0;
  label_codes[341]=8'd0;
  label_codes[342]=8'd0;
  label_codes[343]=8'd0;
  label_codes[344]=8'd0;
  label_codes[345]=8'd0;
  label_codes[346]=8'd0;
  label_codes[347]=8'd0;
  label_codes[348]=8'd0;
  label_codes[349]=8'd0;
  label_codes[350]=8'd0;
  label_codes[351]=8'd0;
  label_codes[352]=8'd76;
  label_codes[353]=8'd77;
  label_codes[354]=8'd78;
  label_codes[355]=8'd58;
  label_codes[356]=8'd0;
  label_codes[357]=8'd0;
  label_codes[358]=8'd0;
  label_codes[359]=8'd0;
  label_codes[360]=8'd0;
  label_codes[361]=8'd0;
  label_codes[362]=8'd0;
  label_codes[363]=8'd0;
  label_codes[364]=8'd0;
  label_codes[365]=8'd0;
  label_codes[366]=8'd0;
  label_codes[367]=8'd0;
  label_codes[368]=8'd51;
  label_codes[369]=8'd45;
  label_codes[370]=8'd63;
  label_codes[371]=8'd54;
  label_codes[372]=8'd59;
  label_codes[373]=8'd79;
  label_codes[374]=8'd80;
  label_codes[375]=8'd0;
  label_codes[376]=8'd0;
  label_codes[377]=8'd0;
  label_codes[378]=8'd0;
  label_codes[379]=8'd0;
  label_codes[380]=8'd0;
  label_codes[381]=8'd0;
  label_codes[382]=8'd0;
  label_codes[383]=8'd0;
  label_codes[384]=8'd81;
  label_codes[385]=8'd82;
  label_codes[386]=8'd0;
  label_codes[387]=8'd0;
  label_codes[388]=8'd0;
  label_codes[389]=8'd0;
  label_codes[390]=8'd0;
  label_codes[391]=8'd0;
  label_codes[392]=8'd0;
  label_codes[393]=8'd0;
  label_codes[394]=8'd0;
  label_codes[395]=8'd0;
  label_codes[396]=8'd0;
  label_codes[397]=8'd0;
  label_codes[398]=8'd0;
  label_codes[399]=8'd0;
  label_codes[400]=8'd83;
  label_codes[401]=8'd84;
  label_codes[402]=8'd0;
  label_codes[403]=8'd0;
  label_codes[404]=8'd0;
  label_codes[405]=8'd0;
  label_codes[406]=8'd0;
  label_codes[407]=8'd0;
  label_codes[408]=8'd0;
  label_codes[409]=8'd0;
  label_codes[410]=8'd0;
  label_codes[411]=8'd0;
  label_codes[412]=8'd0;
  label_codes[413]=8'd0;
  label_codes[414]=8'd0;
  label_codes[415]=8'd0;
  label_codes[416]=8'd85;
  label_codes[417]=8'd86;
  label_codes[418]=8'd81;
  label_codes[419]=8'd82;
  label_codes[420]=8'd0;
  label_codes[421]=8'd0;
  label_codes[422]=8'd0;
  label_codes[423]=8'd0;
  label_codes[424]=8'd0;
  label_codes[425]=8'd0;
  label_codes[426]=8'd0;
  label_codes[427]=8'd0;
  label_codes[428]=8'd0;
  label_codes[429]=8'd0;
  label_codes[430]=8'd0;
  label_codes[431]=8'd0;
  label_codes[432]=8'd87;
  label_codes[433]=8'd88;
  label_codes[434]=8'd81;
  label_codes[435]=8'd82;
  label_codes[436]=8'd0;
  label_codes[437]=8'd0;
  label_codes[438]=8'd0;
  label_codes[439]=8'd0;
  label_codes[440]=8'd0;
  label_codes[441]=8'd0;
  label_codes[442]=8'd0;
  label_codes[443]=8'd0;
  label_codes[444]=8'd0;
  label_codes[445]=8'd0;
  label_codes[446]=8'd0;
  label_codes[447]=8'd0;
  label_codes[448]=8'd89;
  label_codes[449]=8'd90;
  label_codes[450]=8'd0;
  label_codes[451]=8'd0;
  label_codes[452]=8'd0;
  label_codes[453]=8'd0;
  label_codes[454]=8'd0;
  label_codes[455]=8'd0;
  label_codes[456]=8'd0;
  label_codes[457]=8'd0;
  label_codes[458]=8'd0;
  label_codes[459]=8'd0;
  label_codes[460]=8'd0;
  label_codes[461]=8'd0;
  label_codes[462]=8'd0;
  label_codes[463]=8'd0;
  label_codes[464]=8'd91;
  label_codes[465]=8'd92;
  label_codes[466]=8'd0;
  label_codes[467]=8'd0;
  label_codes[468]=8'd0;
  label_codes[469]=8'd0;
  label_codes[470]=8'd0;
  label_codes[471]=8'd0;
  label_codes[472]=8'd0;
  label_codes[473]=8'd0;
  label_codes[474]=8'd0;
  label_codes[475]=8'd0;
  label_codes[476]=8'd0;
  label_codes[477]=8'd0;
  label_codes[478]=8'd0;
  label_codes[479]=8'd0;
  label_codes[480]=8'd93;
  label_codes[481]=8'd94;
  label_codes[482]=8'd0;
  label_codes[483]=8'd0;
  label_codes[484]=8'd0;
  label_codes[485]=8'd0;
  label_codes[486]=8'd0;
  label_codes[487]=8'd0;
  label_codes[488]=8'd0;
  label_codes[489]=8'd0;
  label_codes[490]=8'd0;
  label_codes[491]=8'd0;
  label_codes[492]=8'd0;
  label_codes[493]=8'd0;
  label_codes[494]=8'd0;
  label_codes[495]=8'd0;
  label_codes[496]=8'd95;
  label_codes[497]=8'd96;
  label_codes[498]=8'd97;
  label_codes[499]=8'd98;
  label_codes[500]=8'd0;
  label_codes[501]=8'd0;
  label_codes[502]=8'd0;
  label_codes[503]=8'd0;
  label_codes[504]=8'd0;
  label_codes[505]=8'd0;
  label_codes[506]=8'd0;
  label_codes[507]=8'd0;
  label_codes[508]=8'd0;
  label_codes[509]=8'd0;
  label_codes[510]=8'd0;
  label_codes[511]=8'd0;
  label_codes[512]=8'd99;
  label_codes[513]=8'd100;
  label_codes[514]=8'd101;
  label_codes[515]=8'd102;
  label_codes[516]=8'd0;
  label_codes[517]=8'd0;
  label_codes[518]=8'd0;
  label_codes[519]=8'd0;
  label_codes[520]=8'd0;
  label_codes[521]=8'd0;
  label_codes[522]=8'd0;
  label_codes[523]=8'd0;
  label_codes[524]=8'd0;
  label_codes[525]=8'd0;
  label_codes[526]=8'd0;
  label_codes[527]=8'd0;
  label_codes[528]=8'd103;
  label_codes[529]=8'd104;
  label_codes[530]=8'd105;
  label_codes[531]=8'd0;
  label_codes[532]=8'd0;
  label_codes[533]=8'd0;
  label_codes[534]=8'd0;
  label_codes[535]=8'd0;
  label_codes[536]=8'd0;
  label_codes[537]=8'd0;
  label_codes[538]=8'd0;
  label_codes[539]=8'd0;
  label_codes[540]=8'd0;
  label_codes[541]=8'd0;
  label_codes[542]=8'd0;
  label_codes[543]=8'd0;
  label_codes[544]=8'd106;
  label_codes[545]=8'd18;
  label_codes[546]=8'd19;
  label_codes[547]=8'd0;
  label_codes[548]=8'd0;
  label_codes[549]=8'd0;
  label_codes[550]=8'd0;
  label_codes[551]=8'd0;
  label_codes[552]=8'd0;
  label_codes[553]=8'd0;
  label_codes[554]=8'd0;
  label_codes[555]=8'd0;
  label_codes[556]=8'd0;
  label_codes[557]=8'd0;
  label_codes[558]=8'd0;
  label_codes[559]=8'd0;
  label_codes[560]=8'd87;
  label_codes[561]=8'd88;
  label_codes[562]=8'd94;
  label_codes[563]=8'd107;
  label_codes[564]=8'd0;
  label_codes[565]=8'd0;
  label_codes[566]=8'd0;
  label_codes[567]=8'd0;
  label_codes[568]=8'd0;
  label_codes[569]=8'd0;
  label_codes[570]=8'd0;
  label_codes[571]=8'd0;
  label_codes[572]=8'd0;
  label_codes[573]=8'd0;
  label_codes[574]=8'd0;
  label_codes[575]=8'd0;
  label_codes[576]=8'd81;
  label_codes[577]=8'd82;
  label_codes[578]=8'd108;
  label_codes[579]=8'd109;
  label_codes[580]=8'd0;
  label_codes[581]=8'd0;
  label_codes[582]=8'd0;
  label_codes[583]=8'd0;
  label_codes[584]=8'd0;
  label_codes[585]=8'd0;
  label_codes[586]=8'd0;
  label_codes[587]=8'd0;
  label_codes[588]=8'd0;
  label_codes[589]=8'd0;
  label_codes[590]=8'd0;
  label_codes[591]=8'd0;
  label_codes[592]=8'd103;
  label_codes[593]=8'd104;
  label_codes[594]=8'd1;
  label_codes[595]=8'd122;
  label_codes[596]=8'd0;
  label_codes[597]=8'd0;
  label_codes[598]=8'd0;
  label_codes[599]=8'd0;
  label_codes[600]=8'd0;
  label_codes[601]=8'd0;
  label_codes[602]=8'd0;
  label_codes[603]=8'd0;
  label_codes[604]=8'd0;
  label_codes[605]=8'd0;
  label_codes[606]=8'd0;
  label_codes[607]=8'd0;
  label_codes[608]=8'd106;
  label_codes[609]=8'd110;
  label_codes[610]=8'd1;
  label_codes[611]=8'd122;
  label_codes[612]=8'd0;
  label_codes[613]=8'd0;
  label_codes[614]=8'd0;
  label_codes[615]=8'd0;
  label_codes[616]=8'd0;
  label_codes[617]=8'd0;
  label_codes[618]=8'd0;
  label_codes[619]=8'd0;
  label_codes[620]=8'd0;
  label_codes[621]=8'd0;
  label_codes[622]=8'd0;
  label_codes[623]=8'd0;
  label_codes[624]=8'd111;
  label_codes[625]=8'd112;
  label_codes[626]=8'd50;
  label_codes[627]=8'd123;
  label_codes[628]=8'd124;
  label_codes[629]=8'd0;
  label_codes[630]=8'd0;
  label_codes[631]=8'd0;
  label_codes[632]=8'd0;
  label_codes[633]=8'd0;
  label_codes[634]=8'd0;
  label_codes[635]=8'd0;
  label_codes[636]=8'd0;
  label_codes[637]=8'd0;
  label_codes[638]=8'd0;
  label_codes[639]=8'd0;
  label_codes[640]=8'd113;
  label_codes[641]=8'd114;
  label_codes[642]=8'd115;
  label_codes[643]=8'd67;
  label_codes[644]=8'd0;
  label_codes[645]=8'd0;
  label_codes[646]=8'd0;
  label_codes[647]=8'd0;
  label_codes[648]=8'd0;
  label_codes[649]=8'd0;
  label_codes[650]=8'd0;
  label_codes[651]=8'd0;
  label_codes[652]=8'd0;
  label_codes[653]=8'd0;
  label_codes[654]=8'd0;
  label_codes[655]=8'd0;
  label_codes[656]=8'd120;
  label_codes[657]=8'd121;
  label_codes[658]=8'd105;
  label_codes[659]=8'd0;
  label_codes[660]=8'd0;
  label_codes[661]=8'd0;
  label_codes[662]=8'd0;
  label_codes[663]=8'd0;
  label_codes[664]=8'd0;
  label_codes[665]=8'd0;
  label_codes[666]=8'd0;
  label_codes[667]=8'd0;
  label_codes[668]=8'd0;
  label_codes[669]=8'd0;
  label_codes[670]=8'd0;
  label_codes[671]=8'd0;
  label_codes[672]=8'd106;
  label_codes[673]=8'd91;
  label_codes[674]=8'd92;
  label_codes[675]=8'd0;
  label_codes[676]=8'd0;
  label_codes[677]=8'd0;
  label_codes[678]=8'd0;
  label_codes[679]=8'd0;
  label_codes[680]=8'd0;
  label_codes[681]=8'd0;
  label_codes[682]=8'd0;
  label_codes[683]=8'd0;
  label_codes[684]=8'd0;
  label_codes[685]=8'd0;
  label_codes[686]=8'd0;
  label_codes[687]=8'd0;
  label_codes[688]=8'd116;
  label_codes[689]=8'd117;
  label_codes[690]=8'd0;
  label_codes[691]=8'd0;
  label_codes[692]=8'd0;
  label_codes[693]=8'd0;
  label_codes[694]=8'd0;
  label_codes[695]=8'd0;
  label_codes[696]=8'd0;
  label_codes[697]=8'd0;
  label_codes[698]=8'd0;
  label_codes[699]=8'd0;
  label_codes[700]=8'd0;
  label_codes[701]=8'd0;
  label_codes[702]=8'd0;
  label_codes[703]=8'd0;
  label_codes[704]=8'd106;
  label_codes[705]=8'd118;
  label_codes[706]=8'd119;
  label_codes[707]=8'd0;
  label_codes[708]=8'd0;
  label_codes[709]=8'd0;
  label_codes[710]=8'd0;
  label_codes[711]=8'd0;
  label_codes[712]=8'd0;
  label_codes[713]=8'd0;
  label_codes[714]=8'd0;
  label_codes[715]=8'd0;
  label_codes[716]=8'd0;
  label_codes[717]=8'd0;
  label_codes[718]=8'd0;
  label_codes[719]=8'd0;
  label_codes[720]=8'd126;
  label_codes[721]=8'd127;
  label_codes[722]=8'd0;
  label_codes[723]=8'd0;
  label_codes[724]=8'd0;
  label_codes[725]=8'd0;
  label_codes[726]=8'd0;
  label_codes[727]=8'd0;
  label_codes[728]=8'd0;
  label_codes[729]=8'd0;
  label_codes[730]=8'd0;
  label_codes[731]=8'd0;
  label_codes[732]=8'd0;
  label_codes[733]=8'd0;
  label_codes[734]=8'd0;
  label_codes[735]=8'd0;
  label_codes[736]=8'd125;
  label_codes[737]=8'd0;
  label_codes[738]=8'd0;
  label_codes[739]=8'd0;
  label_codes[740]=8'd0;
  label_codes[741]=8'd0;
  label_codes[742]=8'd0;
  label_codes[743]=8'd0;
  label_codes[744]=8'd0;
  label_codes[745]=8'd0;
  label_codes[746]=8'd0;
  label_codes[747]=8'd0;
  label_codes[748]=8'd0;
  label_codes[749]=8'd0;
  label_codes[750]=8'd0;
  label_codes[751]=8'd0;
  label_codes[752]=8'd128;
  label_codes[753]=8'd129;
  label_codes[754]=8'd130;
  label_codes[755]=8'd131;
  label_codes[756]=8'd0;
  label_codes[757]=8'd0;
  label_codes[758]=8'd0;
  label_codes[759]=8'd0;
  label_codes[760]=8'd0;
  label_codes[761]=8'd0;
  label_codes[762]=8'd0;
  label_codes[763]=8'd0;
  label_codes[764]=8'd0;
  label_codes[765]=8'd0;
  label_codes[766]=8'd0;
  label_codes[767]=8'd0;
  label_codes[768]=8'd132;
  label_codes[769]=8'd112;
  label_codes[770]=8'd0;
  label_codes[771]=8'd0;
  label_codes[772]=8'd0;
  label_codes[773]=8'd0;
  label_codes[774]=8'd0;
  label_codes[775]=8'd0;
  label_codes[776]=8'd0;
  label_codes[777]=8'd0;
  label_codes[778]=8'd0;
  label_codes[779]=8'd0;
  label_codes[780]=8'd0;
  label_codes[781]=8'd0;
  label_codes[782]=8'd0;
  label_codes[783]=8'd0;
  label_codes[784]=8'd133;
  label_codes[785]=8'd1;
  label_codes[786]=8'd0;
  label_codes[787]=8'd0;
  label_codes[788]=8'd0;
  label_codes[789]=8'd0;
  label_codes[790]=8'd0;
  label_codes[791]=8'd0;
  label_codes[792]=8'd0;
  label_codes[793]=8'd0;
  label_codes[794]=8'd0;
  label_codes[795]=8'd0;
  label_codes[796]=8'd0;
  label_codes[797]=8'd0;
  label_codes[798]=8'd0;
  label_codes[799]=8'd0;
  label_codes[800]=8'd134;
  label_codes[801]=8'd1;
  label_codes[802]=8'd0;
  label_codes[803]=8'd0;
  label_codes[804]=8'd0;
  label_codes[805]=8'd0;
  label_codes[806]=8'd0;
  label_codes[807]=8'd0;
  label_codes[808]=8'd0;
  label_codes[809]=8'd0;
  label_codes[810]=8'd0;
  label_codes[811]=8'd0;
  label_codes[812]=8'd0;
  label_codes[813]=8'd0;
  label_codes[814]=8'd0;
  label_codes[815]=8'd0;
  label_codes[816]=8'd109;
  label_codes[817]=8'd136;
  label_codes[818]=8'd0;
  label_codes[819]=8'd0;
  label_codes[820]=8'd0;
  label_codes[821]=8'd0;
  label_codes[822]=8'd0;
  label_codes[823]=8'd0;
  label_codes[824]=8'd0;
  label_codes[825]=8'd0;
  label_codes[826]=8'd0;
  label_codes[827]=8'd0;
  label_codes[828]=8'd0;
  label_codes[829]=8'd0;
  label_codes[830]=8'd0;
  label_codes[831]=8'd0;
  label_codes[832]=8'd83;
  label_codes[833]=8'd84;
  label_codes[834]=8'd137;
  label_codes[835]=8'd138;
  label_codes[836]=8'd0;
  label_codes[837]=8'd0;
  label_codes[838]=8'd0;
  label_codes[839]=8'd0;
  label_codes[840]=8'd0;
  label_codes[841]=8'd0;
  label_codes[842]=8'd0;
  label_codes[843]=8'd0;
  label_codes[844]=8'd0;
  label_codes[845]=8'd0;
  label_codes[846]=8'd0;
  label_codes[847]=8'd0;
  label_codes[848]=8'd1;
  label_codes[849]=8'd38;
  label_codes[850]=8'd0;
  label_codes[851]=8'd0;
  label_codes[852]=8'd0;
  label_codes[853]=8'd0;
  label_codes[854]=8'd0;
  label_codes[855]=8'd0;
  label_codes[856]=8'd0;
  label_codes[857]=8'd0;
  label_codes[858]=8'd0;
  label_codes[859]=8'd0;
  label_codes[860]=8'd0;
  label_codes[861]=8'd0;
  label_codes[862]=8'd0;
  label_codes[863]=8'd0;
  label_codes[864]=8'd62;
  label_codes[865]=8'd0;
  label_codes[866]=8'd0;
  label_codes[867]=8'd0;
  label_codes[868]=8'd0;
  label_codes[869]=8'd0;
  label_codes[870]=8'd0;
  label_codes[871]=8'd0;
  label_codes[872]=8'd0;
  label_codes[873]=8'd0;
  label_codes[874]=8'd0;
  label_codes[875]=8'd0;
  label_codes[876]=8'd0;
  label_codes[877]=8'd0;
  label_codes[878]=8'd0;
  label_codes[879]=8'd0;
  label_codes[880]=8'd69;
  label_codes[881]=8'd70;
  label_codes[882]=8'd139;
  label_codes[883]=8'd82;
  label_codes[884]=8'd0;
  label_codes[885]=8'd0;
  label_codes[886]=8'd0;
  label_codes[887]=8'd0;
  label_codes[888]=8'd0;
  label_codes[889]=8'd0;
  label_codes[890]=8'd0;
  label_codes[891]=8'd0;
  label_codes[892]=8'd0;
  label_codes[893]=8'd0;
  label_codes[894]=8'd0;
  label_codes[895]=8'd0;
  label_codes[896]=8'd140;
  label_codes[897]=8'd141;
  label_codes[898]=8'd142;
  label_codes[899]=8'd143;
  label_codes[900]=8'd0;
  label_codes[901]=8'd0;
  label_codes[902]=8'd0;
  label_codes[903]=8'd0;
  label_codes[904]=8'd0;
  label_codes[905]=8'd0;
  label_codes[906]=8'd0;
  label_codes[907]=8'd0;
  label_codes[908]=8'd0;
  label_codes[909]=8'd0;
  label_codes[910]=8'd0;
  label_codes[911]=8'd0;
  label_codes[912]=8'd45;
  label_codes[913]=8'd62;
  label_codes[914]=8'd53;
  label_codes[915]=8'd63;
  label_codes[916]=8'd45;
  label_codes[917]=8'd55;
  label_codes[918]=8'd144;
  label_codes[919]=8'd145;
  label_codes[920]=8'd146;
  label_codes[921]=8'd0;
  label_codes[922]=8'd0;
  label_codes[923]=8'd0;
  label_codes[924]=8'd0;
  label_codes[925]=8'd0;
  label_codes[926]=8'd0;
  label_codes[927]=8'd0;
  label_codes[928]=8'd45;
  label_codes[929]=8'd62;
  label_codes[930]=8'd51;
  label_codes[931]=8'd52;
  label_codes[932]=8'd63;
  label_codes[933]=8'd52;
  label_codes[934]=8'd144;
  label_codes[935]=8'd145;
  label_codes[936]=8'd146;
  label_codes[937]=8'd0;
  label_codes[938]=8'd0;
  label_codes[939]=8'd0;
  label_codes[940]=8'd0;
  label_codes[941]=8'd0;
  label_codes[942]=8'd0;
  label_codes[943]=8'd0;
  label_codes[944]=8'd45;
  label_codes[945]=8'd62;
  label_codes[946]=8'd52;
  label_codes[947]=8'd54;
  label_codes[948]=8'd63;
  label_codes[949]=8'd54;
  label_codes[950]=8'd144;
  label_codes[951]=8'd145;
  label_codes[952]=8'd146;
  label_codes[953]=8'd0;
  label_codes[954]=8'd0;
  label_codes[955]=8'd0;
  label_codes[956]=8'd0;
  label_codes[957]=8'd0;
  label_codes[958]=8'd0;
  label_codes[959]=8'd0;
  label_codes[960]=8'd147;
  label_codes[961]=8'd148;
  label_codes[962]=8'd149;
  label_codes[963]=8'd150;
  label_codes[964]=8'd143;
  label_codes[965]=8'd0;
  label_codes[966]=8'd0;
  label_codes[967]=8'd0;
  label_codes[968]=8'd0;
  label_codes[969]=8'd0;
  label_codes[970]=8'd0;
  label_codes[971]=8'd0;
  label_codes[972]=8'd0;
  label_codes[973]=8'd0;
  label_codes[974]=8'd0;
  label_codes[975]=8'd0;
  label_codes[976]=8'd151;
  label_codes[977]=8'd152;
  label_codes[978]=8'd45;
  label_codes[979]=8'd63;
  label_codes[980]=8'd53;
  label_codes[981]=8'd53;
  label_codes[982]=8'd79;
  label_codes[983]=8'd80;
  label_codes[984]=8'd0;
  label_codes[985]=8'd0;
  label_codes[986]=8'd0;
  label_codes[987]=8'd0;
  label_codes[988]=8'd0;
  label_codes[989]=8'd0;
  label_codes[990]=8'd0;
  label_codes[991]=8'd0;
  label_codes[992]=8'd151;
  label_codes[993]=8'd152;
  label_codes[994]=8'd45;
  label_codes[995]=8'd63;
  label_codes[996]=8'd56;
  label_codes[997]=8'd56;
  label_codes[998]=8'd79;
  label_codes[999]=8'd80;
  label_codes[1000]=8'd0;
  label_codes[1001]=8'd0;
  label_codes[1002]=8'd0;
  label_codes[1003]=8'd0;
  label_codes[1004]=8'd0;
  label_codes[1005]=8'd0;
  label_codes[1006]=8'd0;
  label_codes[1007]=8'd0;
  label_codes[1008]=8'd151;
  label_codes[1009]=8'd152;
  label_codes[1010]=8'd51;
  label_codes[1011]=8'd63;
  label_codes[1012]=8'd53;
  label_codes[1013]=8'd51;
  label_codes[1014]=8'd79;
  label_codes[1015]=8'd80;
  label_codes[1016]=8'd0;
  label_codes[1017]=8'd0;
  label_codes[1018]=8'd0;
  label_codes[1019]=8'd0;
  label_codes[1020]=8'd0;
  label_codes[1021]=8'd0;
  label_codes[1022]=8'd0;
  label_codes[1023]=8'd0;
  label_codes[1024]=8'd189;
  label_codes[1025]=8'd190;
  label_codes[1026]=8'd191;
  label_codes[1027]=8'd192;
  label_codes[1028]=8'd0;
  label_codes[1029]=8'd0;
  label_codes[1030]=8'd0;
  label_codes[1031]=8'd0;
  label_codes[1032]=8'd0;
  label_codes[1033]=8'd0;
  label_codes[1034]=8'd0;
  label_codes[1035]=8'd0;
  label_codes[1036]=8'd0;
  label_codes[1037]=8'd0;
  label_codes[1038]=8'd0;
  label_codes[1039]=8'd0;
  label_codes[1040]=8'd118;
  label_codes[1041]=8'd119;
  label_codes[1042]=8'd157;
  label_codes[1043]=8'd158;
  label_codes[1044]=8'd0;
  label_codes[1045]=8'd0;
  label_codes[1046]=8'd0;
  label_codes[1047]=8'd0;
  label_codes[1048]=8'd0;
  label_codes[1049]=8'd0;
  label_codes[1050]=8'd0;
  label_codes[1051]=8'd0;
  label_codes[1052]=8'd0;
  label_codes[1053]=8'd0;
  label_codes[1054]=8'd0;
  label_codes[1055]=8'd0;
  label_codes[1056]=8'd159;
  label_codes[1057]=8'd160;
  label_codes[1058]=8'd157;
  label_codes[1059]=8'd0;
  label_codes[1060]=8'd0;
  label_codes[1061]=8'd0;
  label_codes[1062]=8'd0;
  label_codes[1063]=8'd0;
  label_codes[1064]=8'd0;
  label_codes[1065]=8'd0;
  label_codes[1066]=8'd0;
  label_codes[1067]=8'd0;
  label_codes[1068]=8'd0;
  label_codes[1069]=8'd0;
  label_codes[1070]=8'd0;
  label_codes[1071]=8'd0;
  label_codes[1072]=8'd159;
  label_codes[1073]=8'd161;
  label_codes[1074]=8'd157;
  label_codes[1075]=8'd0;
  label_codes[1076]=8'd0;
  label_codes[1077]=8'd0;
  label_codes[1078]=8'd0;
  label_codes[1079]=8'd0;
  label_codes[1080]=8'd0;
  label_codes[1081]=8'd0;
  label_codes[1082]=8'd0;
  label_codes[1083]=8'd0;
  label_codes[1084]=8'd0;
  label_codes[1085]=8'd0;
  label_codes[1086]=8'd0;
  label_codes[1087]=8'd0;
  label_codes[1088]=8'd159;
  label_codes[1089]=8'd162;
  label_codes[1090]=8'd157;
  label_codes[1091]=8'd0;
  label_codes[1092]=8'd0;
  label_codes[1093]=8'd0;
  label_codes[1094]=8'd0;
  label_codes[1095]=8'd0;
  label_codes[1096]=8'd0;
  label_codes[1097]=8'd0;
  label_codes[1098]=8'd0;
  label_codes[1099]=8'd0;
  label_codes[1100]=8'd0;
  label_codes[1101]=8'd0;
  label_codes[1102]=8'd0;
  label_codes[1103]=8'd0;
  label_codes[1104]=8'd17;
  label_codes[1105]=8'd163;
  label_codes[1106]=8'd164;
  label_codes[1107]=8'd0;
  label_codes[1108]=8'd0;
  label_codes[1109]=8'd0;
  label_codes[1110]=8'd0;
  label_codes[1111]=8'd0;
  label_codes[1112]=8'd0;
  label_codes[1113]=8'd0;
  label_codes[1114]=8'd0;
  label_codes[1115]=8'd0;
  label_codes[1116]=8'd0;
  label_codes[1117]=8'd0;
  label_codes[1118]=8'd0;
  label_codes[1119]=8'd0;
  label_codes[1120]=8'd165;
  label_codes[1121]=8'd166;
  label_codes[1122]=8'd0;
  label_codes[1123]=8'd0;
  label_codes[1124]=8'd0;
  label_codes[1125]=8'd0;
  label_codes[1126]=8'd0;
  label_codes[1127]=8'd0;
  label_codes[1128]=8'd0;
  label_codes[1129]=8'd0;
  label_codes[1130]=8'd0;
  label_codes[1131]=8'd0;
  label_codes[1132]=8'd0;
  label_codes[1133]=8'd0;
  label_codes[1134]=8'd0;
  label_codes[1135]=8'd0;
  label_codes[1136]=8'd155;
  label_codes[1137]=8'd156;
  label_codes[1138]=8'd105;
  label_codes[1139]=8'd0;
  label_codes[1140]=8'd0;
  label_codes[1141]=8'd0;
  label_codes[1142]=8'd0;
  label_codes[1143]=8'd0;
  label_codes[1144]=8'd0;
  label_codes[1145]=8'd0;
  label_codes[1146]=8'd0;
  label_codes[1147]=8'd0;
  label_codes[1148]=8'd0;
  label_codes[1149]=8'd0;
  label_codes[1150]=8'd0;
  label_codes[1151]=8'd0;
  label_codes[1152]=8'd91;
  label_codes[1153]=8'd92;
  label_codes[1154]=8'd0;
  label_codes[1155]=8'd0;
  label_codes[1156]=8'd0;
  label_codes[1157]=8'd0;
  label_codes[1158]=8'd0;
  label_codes[1159]=8'd0;
  label_codes[1160]=8'd0;
  label_codes[1161]=8'd0;
  label_codes[1162]=8'd0;
  label_codes[1163]=8'd0;
  label_codes[1164]=8'd0;
  label_codes[1165]=8'd0;
  label_codes[1166]=8'd0;
  label_codes[1167]=8'd0;
  label_codes[1168]=8'd21;
  label_codes[1169]=8'd167;
  label_codes[1170]=8'd168;
  label_codes[1171]=8'd169;
  label_codes[1172]=8'd0;
  label_codes[1173]=8'd0;
  label_codes[1174]=8'd0;
  label_codes[1175]=8'd0;
  label_codes[1176]=8'd0;
  label_codes[1177]=8'd0;
  label_codes[1178]=8'd0;
  label_codes[1179]=8'd0;
  label_codes[1180]=8'd0;
  label_codes[1181]=8'd0;
  label_codes[1182]=8'd0;
  label_codes[1183]=8'd0;
  label_codes[1184]=8'd38;
  label_codes[1185]=8'd138;
  label_codes[1186]=8'd0;
  label_codes[1187]=8'd0;
  label_codes[1188]=8'd0;
  label_codes[1189]=8'd0;
  label_codes[1190]=8'd0;
  label_codes[1191]=8'd0;
  label_codes[1192]=8'd0;
  label_codes[1193]=8'd0;
  label_codes[1194]=8'd0;
  label_codes[1195]=8'd0;
  label_codes[1196]=8'd0;
  label_codes[1197]=8'd0;
  label_codes[1198]=8'd0;
  label_codes[1199]=8'd0;
  label_codes[1200]=8'd170;
  label_codes[1201]=8'd74;
  label_codes[1202]=8'd0;
  label_codes[1203]=8'd0;
  label_codes[1204]=8'd0;
  label_codes[1205]=8'd0;
  label_codes[1206]=8'd0;
  label_codes[1207]=8'd0;
  label_codes[1208]=8'd0;
  label_codes[1209]=8'd0;
  label_codes[1210]=8'd0;
  label_codes[1211]=8'd0;
  label_codes[1212]=8'd0;
  label_codes[1213]=8'd0;
  label_codes[1214]=8'd0;
  label_codes[1215]=8'd0;
  label_codes[1216]=8'd171;
  label_codes[1217]=8'd172;
  label_codes[1218]=8'd170;
  label_codes[1219]=8'd74;
  label_codes[1220]=8'd0;
  label_codes[1221]=8'd0;
  label_codes[1222]=8'd0;
  label_codes[1223]=8'd0;
  label_codes[1224]=8'd0;
  label_codes[1225]=8'd0;
  label_codes[1226]=8'd0;
  label_codes[1227]=8'd0;
  label_codes[1228]=8'd0;
  label_codes[1229]=8'd0;
  label_codes[1230]=8'd0;
  label_codes[1231]=8'd0;
  label_codes[1232]=8'd173;
  label_codes[1233]=8'd174;
  label_codes[1234]=8'd0;
  label_codes[1235]=8'd0;
  label_codes[1236]=8'd0;
  label_codes[1237]=8'd0;
  label_codes[1238]=8'd0;
  label_codes[1239]=8'd0;
  label_codes[1240]=8'd0;
  label_codes[1241]=8'd0;
  label_codes[1242]=8'd0;
  label_codes[1243]=8'd0;
  label_codes[1244]=8'd0;
  label_codes[1245]=8'd0;
  label_codes[1246]=8'd0;
  label_codes[1247]=8'd0;
  label_codes[1248]=8'd175;
  label_codes[1249]=8'd160;
  label_codes[1250]=8'd1;
  label_codes[1251]=8'd0;
  label_codes[1252]=8'd0;
  label_codes[1253]=8'd0;
  label_codes[1254]=8'd0;
  label_codes[1255]=8'd0;
  label_codes[1256]=8'd0;
  label_codes[1257]=8'd0;
  label_codes[1258]=8'd0;
  label_codes[1259]=8'd0;
  label_codes[1260]=8'd0;
  label_codes[1261]=8'd0;
  label_codes[1262]=8'd0;
  label_codes[1263]=8'd0;
  label_codes[1264]=8'd176;
  label_codes[1265]=8'd165;
  label_codes[1266]=8'd0;
  label_codes[1267]=8'd0;
  label_codes[1268]=8'd0;
  label_codes[1269]=8'd0;
  label_codes[1270]=8'd0;
  label_codes[1271]=8'd0;
  label_codes[1272]=8'd0;
  label_codes[1273]=8'd0;
  label_codes[1274]=8'd0;
  label_codes[1275]=8'd0;
  label_codes[1276]=8'd0;
  label_codes[1277]=8'd0;
  label_codes[1278]=8'd0;
  label_codes[1279]=8'd0;
  label_codes[1280]=8'd177;
  label_codes[1281]=8'd178;
  label_codes[1282]=8'd0;
  label_codes[1283]=8'd0;
  label_codes[1284]=8'd0;
  label_codes[1285]=8'd0;
  label_codes[1286]=8'd0;
  label_codes[1287]=8'd0;
  label_codes[1288]=8'd0;
  label_codes[1289]=8'd0;
  label_codes[1290]=8'd0;
  label_codes[1291]=8'd0;
  label_codes[1292]=8'd0;
  label_codes[1293]=8'd0;
  label_codes[1294]=8'd0;
  label_codes[1295]=8'd0;
  label_codes[1296]=8'd179;
  label_codes[1297]=8'd180;
  label_codes[1298]=8'd0;
  label_codes[1299]=8'd0;
  label_codes[1300]=8'd0;
  label_codes[1301]=8'd0;
  label_codes[1302]=8'd0;
  label_codes[1303]=8'd0;
  label_codes[1304]=8'd0;
  label_codes[1305]=8'd0;
  label_codes[1306]=8'd0;
  label_codes[1307]=8'd0;
  label_codes[1308]=8'd0;
  label_codes[1309]=8'd0;
  label_codes[1310]=8'd0;
  label_codes[1311]=8'd0;
  label_codes[1312]=8'd107;
  label_codes[1313]=8'd1;
  label_codes[1314]=8'd0;
  label_codes[1315]=8'd0;
  label_codes[1316]=8'd0;
  label_codes[1317]=8'd0;
  label_codes[1318]=8'd0;
  label_codes[1319]=8'd0;
  label_codes[1320]=8'd0;
  label_codes[1321]=8'd0;
  label_codes[1322]=8'd0;
  label_codes[1323]=8'd0;
  label_codes[1324]=8'd0;
  label_codes[1325]=8'd0;
  label_codes[1326]=8'd0;
  label_codes[1327]=8'd0;
  label_codes[1328]=8'd181;
  label_codes[1329]=8'd1;
  label_codes[1330]=8'd0;
  label_codes[1331]=8'd0;
  label_codes[1332]=8'd0;
  label_codes[1333]=8'd0;
  label_codes[1334]=8'd0;
  label_codes[1335]=8'd0;
  label_codes[1336]=8'd0;
  label_codes[1337]=8'd0;
  label_codes[1338]=8'd0;
  label_codes[1339]=8'd0;
  label_codes[1340]=8'd0;
  label_codes[1341]=8'd0;
  label_codes[1342]=8'd0;
  label_codes[1343]=8'd0;
  label_codes[1344]=8'd182;
  label_codes[1345]=8'd67;
  label_codes[1346]=8'd0;
  label_codes[1347]=8'd0;
  label_codes[1348]=8'd0;
  label_codes[1349]=8'd0;
  label_codes[1350]=8'd0;
  label_codes[1351]=8'd0;
  label_codes[1352]=8'd0;
  label_codes[1353]=8'd0;
  label_codes[1354]=8'd0;
  label_codes[1355]=8'd0;
  label_codes[1356]=8'd0;
  label_codes[1357]=8'd0;
  label_codes[1358]=8'd0;
  label_codes[1359]=8'd0;
  label_codes[1360]=8'd36;
  label_codes[1361]=8'd37;
  label_codes[1362]=8'd0;
  label_codes[1363]=8'd0;
  label_codes[1364]=8'd0;
  label_codes[1365]=8'd0;
  label_codes[1366]=8'd0;
  label_codes[1367]=8'd0;
  label_codes[1368]=8'd0;
  label_codes[1369]=8'd0;
  label_codes[1370]=8'd0;
  label_codes[1371]=8'd0;
  label_codes[1372]=8'd0;
  label_codes[1373]=8'd0;
  label_codes[1374]=8'd0;
  label_codes[1375]=8'd0;
  label_codes[1376]=8'd183;
  label_codes[1377]=8'd184;
  label_codes[1378]=8'd0;
  label_codes[1379]=8'd0;
  label_codes[1380]=8'd0;
  label_codes[1381]=8'd0;
  label_codes[1382]=8'd0;
  label_codes[1383]=8'd0;
  label_codes[1384]=8'd0;
  label_codes[1385]=8'd0;
  label_codes[1386]=8'd0;
  label_codes[1387]=8'd0;
  label_codes[1388]=8'd0;
  label_codes[1389]=8'd0;
  label_codes[1390]=8'd0;
  label_codes[1391]=8'd0;
  label_codes[1392]=8'd101;
  label_codes[1393]=8'd157;
  label_codes[1394]=8'd0;
  label_codes[1395]=8'd0;
  label_codes[1396]=8'd0;
  label_codes[1397]=8'd0;
  label_codes[1398]=8'd0;
  label_codes[1399]=8'd0;
  label_codes[1400]=8'd0;
  label_codes[1401]=8'd0;
  label_codes[1402]=8'd0;
  label_codes[1403]=8'd0;
  label_codes[1404]=8'd0;
  label_codes[1405]=8'd0;
  label_codes[1406]=8'd0;
  label_codes[1407]=8'd0;
  label_codes[1408]=8'd185;
  label_codes[1409]=8'd103;
  label_codes[1410]=8'd185;
  label_codes[1411]=8'd186;
  label_codes[1412]=8'd0;
  label_codes[1413]=8'd0;
  label_codes[1414]=8'd0;
  label_codes[1415]=8'd0;
  label_codes[1416]=8'd0;
  label_codes[1417]=8'd0;
  label_codes[1418]=8'd0;
  label_codes[1419]=8'd0;
  label_codes[1420]=8'd0;
  label_codes[1421]=8'd0;
  label_codes[1422]=8'd0;
  label_codes[1423]=8'd0;
  label_codes[1424]=8'd21;
  label_codes[1425]=8'd157;
  label_codes[1426]=8'd171;
  label_codes[1427]=8'd172;
  label_codes[1428]=8'd0;
  label_codes[1429]=8'd0;
  label_codes[1430]=8'd0;
  label_codes[1431]=8'd0;
  label_codes[1432]=8'd0;
  label_codes[1433]=8'd0;
  label_codes[1434]=8'd0;
  label_codes[1435]=8'd0;
  label_codes[1436]=8'd0;
  label_codes[1437]=8'd0;
  label_codes[1438]=8'd0;
  label_codes[1439]=8'd0;
  label_codes[1440]=8'd89;
  label_codes[1441]=8'd90;
  label_codes[1442]=8'd0;
  label_codes[1443]=8'd0;
  label_codes[1444]=8'd0;
  label_codes[1445]=8'd0;
  label_codes[1446]=8'd0;
  label_codes[1447]=8'd0;
  label_codes[1448]=8'd0;
  label_codes[1449]=8'd0;
  label_codes[1450]=8'd0;
  label_codes[1451]=8'd0;
  label_codes[1452]=8'd0;
  label_codes[1453]=8'd0;
  label_codes[1454]=8'd0;
  label_codes[1455]=8'd0;
  label_codes[1456]=8'd91;
  label_codes[1457]=8'd92;
  label_codes[1458]=8'd0;
  label_codes[1459]=8'd0;
  label_codes[1460]=8'd0;
  label_codes[1461]=8'd0;
  label_codes[1462]=8'd0;
  label_codes[1463]=8'd0;
  label_codes[1464]=8'd0;
  label_codes[1465]=8'd0;
  label_codes[1466]=8'd0;
  label_codes[1467]=8'd0;
  label_codes[1468]=8'd0;
  label_codes[1469]=8'd0;
  label_codes[1470]=8'd0;
  label_codes[1471]=8'd0;
  label_codes[1472]=8'd93;
  label_codes[1473]=8'd94;
  label_codes[1474]=8'd0;
  label_codes[1475]=8'd0;
  label_codes[1476]=8'd0;
  label_codes[1477]=8'd0;
  label_codes[1478]=8'd0;
  label_codes[1479]=8'd0;
  label_codes[1480]=8'd0;
  label_codes[1481]=8'd0;
  label_codes[1482]=8'd0;
  label_codes[1483]=8'd0;
  label_codes[1484]=8'd0;
  label_codes[1485]=8'd0;
  label_codes[1486]=8'd0;
  label_codes[1487]=8'd0;
  label_codes[1488]=8'd126;
  label_codes[1489]=8'd127;
  label_codes[1490]=8'd0;
  label_codes[1491]=8'd0;
  label_codes[1492]=8'd0;
  label_codes[1493]=8'd0;
  label_codes[1494]=8'd0;
  label_codes[1495]=8'd0;
  label_codes[1496]=8'd0;
  label_codes[1497]=8'd0;
  label_codes[1498]=8'd0;
  label_codes[1499]=8'd0;
  label_codes[1500]=8'd0;
  label_codes[1501]=8'd0;
  label_codes[1502]=8'd0;
  label_codes[1503]=8'd0;
  label_codes[1504]=8'd83;
  label_codes[1505]=8'd84;
  label_codes[1506]=8'd0;
  label_codes[1507]=8'd0;
  label_codes[1508]=8'd0;
  label_codes[1509]=8'd0;
  label_codes[1510]=8'd0;
  label_codes[1511]=8'd0;
  label_codes[1512]=8'd0;
  label_codes[1513]=8'd0;
  label_codes[1514]=8'd0;
  label_codes[1515]=8'd0;
  label_codes[1516]=8'd0;
  label_codes[1517]=8'd0;
  label_codes[1518]=8'd0;
  label_codes[1519]=8'd0;
  label_codes[1520]=8'd50;
  label_codes[1521]=8'd123;
  label_codes[1522]=8'd124;
  label_codes[1523]=8'd0;
  label_codes[1524]=8'd0;
  label_codes[1525]=8'd0;
  label_codes[1526]=8'd0;
  label_codes[1527]=8'd0;
  label_codes[1528]=8'd0;
  label_codes[1529]=8'd0;
  label_codes[1530]=8'd0;
  label_codes[1531]=8'd0;
  label_codes[1532]=8'd0;
  label_codes[1533]=8'd0;
  label_codes[1534]=8'd0;
  label_codes[1535]=8'd0;
  label_codes[1536]=8'd187;
  label_codes[1537]=8'd178;
  label_codes[1538]=8'd180;
  label_codes[1539]=8'd0;
  label_codes[1540]=8'd0;
  label_codes[1541]=8'd0;
  label_codes[1542]=8'd0;
  label_codes[1543]=8'd0;
  label_codes[1544]=8'd0;
  label_codes[1545]=8'd0;
  label_codes[1546]=8'd0;
  label_codes[1547]=8'd0;
  label_codes[1548]=8'd0;
  label_codes[1549]=8'd0;
  label_codes[1550]=8'd0;
  label_codes[1551]=8'd0;
  label_codes[1552]=8'd115;
  label_codes[1553]=8'd67;
  label_codes[1554]=8'd0;
  label_codes[1555]=8'd0;
  label_codes[1556]=8'd0;
  label_codes[1557]=8'd0;
  label_codes[1558]=8'd0;
  label_codes[1559]=8'd0;
  label_codes[1560]=8'd0;
  label_codes[1561]=8'd0;
  label_codes[1562]=8'd0;
  label_codes[1563]=8'd0;
  label_codes[1564]=8'd0;
  label_codes[1565]=8'd0;
  label_codes[1566]=8'd0;
  label_codes[1567]=8'd0;
  label_codes[1568]=8'd106;
  label_codes[1569]=8'd163;
  label_codes[1570]=8'd164;
  label_codes[1571]=8'd0;
  label_codes[1572]=8'd0;
  label_codes[1573]=8'd0;
  label_codes[1574]=8'd0;
  label_codes[1575]=8'd0;
  label_codes[1576]=8'd0;
  label_codes[1577]=8'd0;
  label_codes[1578]=8'd0;
  label_codes[1579]=8'd0;
  label_codes[1580]=8'd0;
  label_codes[1581]=8'd0;
  label_codes[1582]=8'd0;
  label_codes[1583]=8'd0;
  label_codes[1584]=8'd188;
  label_codes[1585]=8'd1;
  label_codes[1586]=8'd0;
  label_codes[1587]=8'd0;
  label_codes[1588]=8'd0;
  label_codes[1589]=8'd0;
  label_codes[1590]=8'd0;
  label_codes[1591]=8'd0;
  label_codes[1592]=8'd0;
  label_codes[1593]=8'd0;
  label_codes[1594]=8'd0;
  label_codes[1595]=8'd0;
  label_codes[1596]=8'd0;
  label_codes[1597]=8'd0;
  label_codes[1598]=8'd0;
  label_codes[1599]=8'd0;
  label_codes[1600]=8'd177;
  label_codes[1601]=8'd178;
  label_codes[1602]=8'd0;
  label_codes[1603]=8'd0;
  label_codes[1604]=8'd0;
  label_codes[1605]=8'd0;
  label_codes[1606]=8'd0;
  label_codes[1607]=8'd0;
  label_codes[1608]=8'd0;
  label_codes[1609]=8'd0;
  label_codes[1610]=8'd0;
  label_codes[1611]=8'd0;
  label_codes[1612]=8'd0;
  label_codes[1613]=8'd0;
  label_codes[1614]=8'd0;
  label_codes[1615]=8'd0;
  label_codes[1616]=8'd179;
  label_codes[1617]=8'd65;
  label_codes[1618]=8'd0;
  label_codes[1619]=8'd0;
  label_codes[1620]=8'd0;
  label_codes[1621]=8'd0;
  label_codes[1622]=8'd0;
  label_codes[1623]=8'd0;
  label_codes[1624]=8'd0;
  label_codes[1625]=8'd0;
  label_codes[1626]=8'd0;
  label_codes[1627]=8'd0;
  label_codes[1628]=8'd0;
  label_codes[1629]=8'd0;
  label_codes[1630]=8'd0;
  label_codes[1631]=8'd0;
  label_codes[1632]=8'd153;
  label_codes[1633]=8'd154;
  label_codes[1634]=8'd155;
  label_codes[1635]=8'd156;
  label_codes[1636]=8'd0;
  label_codes[1637]=8'd0;
  label_codes[1638]=8'd0;
  label_codes[1639]=8'd0;
  label_codes[1640]=8'd0;
  label_codes[1641]=8'd0;
  label_codes[1642]=8'd0;
  label_codes[1643]=8'd0;
  label_codes[1644]=8'd0;
  label_codes[1645]=8'd0;
  label_codes[1646]=8'd0;
  label_codes[1647]=8'd0;
  label_codes[1648]=8'd21;
  label_codes[1649]=8'd167;
  label_codes[1650]=8'd195;
  label_codes[1651]=8'd38;
  label_codes[1652]=8'd0;
  label_codes[1653]=8'd0;
  label_codes[1654]=8'd0;
  label_codes[1655]=8'd0;
  label_codes[1656]=8'd0;
  label_codes[1657]=8'd0;
  label_codes[1658]=8'd0;
  label_codes[1659]=8'd0;
  label_codes[1660]=8'd0;
  label_codes[1661]=8'd0;
  label_codes[1662]=8'd0;
  label_codes[1663]=8'd0;
  label_codes[1664]=8'd187;
  label_codes[1665]=8'd178;
  label_codes[1666]=8'd1;
  label_codes[1667]=8'd122;
  label_codes[1668]=8'd0;
  label_codes[1669]=8'd0;
  label_codes[1670]=8'd0;
  label_codes[1671]=8'd0;
  label_codes[1672]=8'd0;
  label_codes[1673]=8'd0;
  label_codes[1674]=8'd0;
  label_codes[1675]=8'd0;
  label_codes[1676]=8'd0;
  label_codes[1677]=8'd0;
  label_codes[1678]=8'd0;
  label_codes[1679]=8'd0;
  label_codes[1680]=8'd175;
  label_codes[1681]=8'd160;
  label_codes[1682]=8'd188;
  label_codes[1683]=8'd1;
  label_codes[1684]=8'd0;
  label_codes[1685]=8'd0;
  label_codes[1686]=8'd0;
  label_codes[1687]=8'd0;
  label_codes[1688]=8'd0;
  label_codes[1689]=8'd0;
  label_codes[1690]=8'd0;
  label_codes[1691]=8'd0;
  label_codes[1692]=8'd0;
  label_codes[1693]=8'd0;
  label_codes[1694]=8'd0;
  label_codes[1695]=8'd0;
  label_codes[1696]=8'd165;
  label_codes[1697]=8'd166;
  label_codes[1698]=8'd89;
  label_codes[1699]=8'd90;
  label_codes[1700]=8'd0;
  label_codes[1701]=8'd0;
  label_codes[1702]=8'd0;
  label_codes[1703]=8'd0;
  label_codes[1704]=8'd0;
  label_codes[1705]=8'd0;
  label_codes[1706]=8'd0;
  label_codes[1707]=8'd0;
  label_codes[1708]=8'd0;
  label_codes[1709]=8'd0;
  label_codes[1710]=8'd0;
  label_codes[1711]=8'd0;
  label_codes[1712]=8'd106;
  label_codes[1713]=8'd91;
  label_codes[1714]=8'd92;
  label_codes[1715]=8'd0;
  label_codes[1716]=8'd0;
  label_codes[1717]=8'd0;
  label_codes[1718]=8'd0;
  label_codes[1719]=8'd0;
  label_codes[1720]=8'd0;
  label_codes[1721]=8'd0;
  label_codes[1722]=8'd0;
  label_codes[1723]=8'd0;
  label_codes[1724]=8'd0;
  label_codes[1725]=8'd0;
  label_codes[1726]=8'd0;
  label_codes[1727]=8'd0;
  label_codes[1728]=8'd21;
  label_codes[1729]=8'd157;
  label_codes[1730]=8'd101;
  label_codes[1731]=8'd213;
  label_codes[1732]=8'd0;
  label_codes[1733]=8'd0;
  label_codes[1734]=8'd0;
  label_codes[1735]=8'd0;
  label_codes[1736]=8'd0;
  label_codes[1737]=8'd0;
  label_codes[1738]=8'd0;
  label_codes[1739]=8'd0;
  label_codes[1740]=8'd0;
  label_codes[1741]=8'd0;
  label_codes[1742]=8'd0;
  label_codes[1743]=8'd0;
  label_codes[1744]=8'd21;
  label_codes[1745]=8'd167;
  label_codes[1746]=8'd168;
  label_codes[1747]=8'd169;
  label_codes[1748]=8'd0;
  label_codes[1749]=8'd0;
  label_codes[1750]=8'd0;
  label_codes[1751]=8'd0;
  label_codes[1752]=8'd0;
  label_codes[1753]=8'd0;
  label_codes[1754]=8'd0;
  label_codes[1755]=8'd0;
  label_codes[1756]=8'd0;
  label_codes[1757]=8'd0;
  label_codes[1758]=8'd0;
  label_codes[1759]=8'd0;
  label_codes[1760]=8'd89;
  label_codes[1761]=8'd90;
  label_codes[1762]=8'd0;
  label_codes[1763]=8'd0;
  label_codes[1764]=8'd0;
  label_codes[1765]=8'd0;
  label_codes[1766]=8'd0;
  label_codes[1767]=8'd0;
  label_codes[1768]=8'd0;
  label_codes[1769]=8'd0;
  label_codes[1770]=8'd0;
  label_codes[1771]=8'd0;
  label_codes[1772]=8'd0;
  label_codes[1773]=8'd0;
  label_codes[1774]=8'd0;
  label_codes[1775]=8'd0;
  label_codes[1776]=8'd115;
  label_codes[1777]=8'd214;
  label_codes[1778]=8'd209;
  label_codes[1779]=8'd210;
  label_codes[1780]=8'd215;
  label_codes[1781]=8'd154;
  label_codes[1782]=8'd0;
  label_codes[1783]=8'd0;
  label_codes[1784]=8'd0;
  label_codes[1785]=8'd0;
  label_codes[1786]=8'd0;
  label_codes[1787]=8'd0;
  label_codes[1788]=8'd0;
  label_codes[1789]=8'd0;
  label_codes[1790]=8'd0;
  label_codes[1791]=8'd0;
  label_codes[1792]=8'd126;
  label_codes[1793]=8'd127;
  label_codes[1794]=8'd216;
  label_codes[1795]=8'd217;
  label_codes[1796]=8'd0;
  label_codes[1797]=8'd0;
  label_codes[1798]=8'd0;
  label_codes[1799]=8'd0;
  label_codes[1800]=8'd0;
  label_codes[1801]=8'd0;
  label_codes[1802]=8'd0;
  label_codes[1803]=8'd0;
  label_codes[1804]=8'd0;
  label_codes[1805]=8'd0;
  label_codes[1806]=8'd0;
  label_codes[1807]=8'd0;
  label_codes[1808]=8'd21;
  label_codes[1809]=8'd157;
  label_codes[1810]=8'd171;
  label_codes[1811]=8'd172;
  label_codes[1812]=8'd0;
  label_codes[1813]=8'd0;
  label_codes[1814]=8'd0;
  label_codes[1815]=8'd0;
  label_codes[1816]=8'd0;
  label_codes[1817]=8'd0;
  label_codes[1818]=8'd0;
  label_codes[1819]=8'd0;
  label_codes[1820]=8'd0;
  label_codes[1821]=8'd0;
  label_codes[1822]=8'd0;
  label_codes[1823]=8'd0;
  label_codes[1824]=8'd218;
  label_codes[1825]=8'd219;
  label_codes[1826]=8'd4;
  label_codes[1827]=8'd0;
  label_codes[1828]=8'd0;
  label_codes[1829]=8'd0;
  label_codes[1830]=8'd0;
  label_codes[1831]=8'd0;
  label_codes[1832]=8'd0;
  label_codes[1833]=8'd0;
  label_codes[1834]=8'd0;
  label_codes[1835]=8'd0;
  label_codes[1836]=8'd0;
  label_codes[1837]=8'd0;
  label_codes[1838]=8'd0;
  label_codes[1839]=8'd0;
  label_codes[1840]=8'd220;
  label_codes[1841]=8'd221;
  label_codes[1842]=8'd221;
  label_codes[1843]=8'd0;
  label_codes[1844]=8'd0;
  label_codes[1845]=8'd0;
  label_codes[1846]=8'd0;
  label_codes[1847]=8'd0;
  label_codes[1848]=8'd0;
  label_codes[1849]=8'd0;
  label_codes[1850]=8'd0;
  label_codes[1851]=8'd0;
  label_codes[1852]=8'd0;
  label_codes[1853]=8'd0;
  label_codes[1854]=8'd0;
  label_codes[1855]=8'd0;
  label_codes[1856]=8'd222;
  label_codes[1857]=8'd193;
  label_codes[1858]=8'd223;
  label_codes[1859]=8'd0;
  label_codes[1860]=8'd0;
  label_codes[1861]=8'd0;
  label_codes[1862]=8'd0;
  label_codes[1863]=8'd0;
  label_codes[1864]=8'd0;
  label_codes[1865]=8'd0;
  label_codes[1866]=8'd0;
  label_codes[1867]=8'd0;
  label_codes[1868]=8'd0;
  label_codes[1869]=8'd0;
  label_codes[1870]=8'd0;
  label_codes[1871]=8'd0;
  label_codes[1872]=8'd224;
  label_codes[1873]=8'd225;
  label_codes[1874]=8'd226;
  label_codes[1875]=8'd0;
  label_codes[1876]=8'd0;
  label_codes[1877]=8'd0;
  label_codes[1878]=8'd0;
  label_codes[1879]=8'd0;
  label_codes[1880]=8'd0;
  label_codes[1881]=8'd0;
  label_codes[1882]=8'd0;
  label_codes[1883]=8'd0;
  label_codes[1884]=8'd0;
  label_codes[1885]=8'd0;
  label_codes[1886]=8'd0;
  label_codes[1887]=8'd0;
  label_codes[1888]=8'd113;
  label_codes[1889]=8'd98;
  label_codes[1890]=8'd227;
  label_codes[1891]=8'd228;
  label_codes[1892]=8'd0;
  label_codes[1893]=8'd0;
  label_codes[1894]=8'd0;
  label_codes[1895]=8'd0;
  label_codes[1896]=8'd0;
  label_codes[1897]=8'd0;
  label_codes[1898]=8'd0;
  label_codes[1899]=8'd0;
  label_codes[1900]=8'd0;
  label_codes[1901]=8'd0;
  label_codes[1902]=8'd0;
  label_codes[1903]=8'd0;
  label_codes[1904]=8'd45;
  label_codes[1905]=8'd62;
  label_codes[1906]=8'd45;
  label_codes[1907]=8'd63;
  label_codes[1908]=8'd57;
  label_codes[1909]=8'd56;
  label_codes[1910]=8'd144;
  label_codes[1911]=8'd145;
  label_codes[1912]=8'd146;
  label_codes[1913]=8'd0;
  label_codes[1914]=8'd0;
  label_codes[1915]=8'd0;
  label_codes[1916]=8'd0;
  label_codes[1917]=8'd0;
  label_codes[1918]=8'd0;
  label_codes[1919]=8'd0;
  label_codes[1920]=8'd151;
  label_codes[1921]=8'd70;
  label_codes[1922]=8'd53;
  label_codes[1923]=8'd52;
  label_codes[1924]=8'd235;
  label_codes[1925]=8'd236;
  label_codes[1926]=8'd0;
  label_codes[1927]=8'd0;
  label_codes[1928]=8'd0;
  label_codes[1929]=8'd0;
  label_codes[1930]=8'd0;
  label_codes[1931]=8'd0;
  label_codes[1932]=8'd0;
  label_codes[1933]=8'd0;
  label_codes[1934]=8'd0;
  label_codes[1935]=8'd0;
  label_codes[1936]=8'd147;
  label_codes[1937]=8'd1;
  label_codes[1938]=8'd237;
  label_codes[1939]=8'd71;
  label_codes[1940]=8'd0;
  label_codes[1941]=8'd0;
  label_codes[1942]=8'd0;
  label_codes[1943]=8'd0;
  label_codes[1944]=8'd0;
  label_codes[1945]=8'd0;
  label_codes[1946]=8'd0;
  label_codes[1947]=8'd0;
  label_codes[1948]=8'd0;
  label_codes[1949]=8'd0;
  label_codes[1950]=8'd0;
  label_codes[1951]=8'd0;
  label_codes[1952]=8'd1;
  label_codes[1953]=8'd2;
  label_codes[1954]=8'd137;
  label_codes[1955]=8'd138;
  label_codes[1956]=8'd0;
  label_codes[1957]=8'd0;
  label_codes[1958]=8'd0;
  label_codes[1959]=8'd0;
  label_codes[1960]=8'd0;
  label_codes[1961]=8'd0;
  label_codes[1962]=8'd0;
  label_codes[1963]=8'd0;
  label_codes[1964]=8'd0;
  label_codes[1965]=8'd0;
  label_codes[1966]=8'd0;
  label_codes[1967]=8'd0;
  label_codes[1968]=8'd230;
  label_codes[1969]=8'd231;
  label_codes[1970]=8'd232;
  label_codes[1971]=8'd73;
  label_codes[1972]=8'd233;
  label_codes[1973]=8'd234;
  label_codes[1974]=8'd213;
  label_codes[1975]=8'd0;
  label_codes[1976]=8'd0;
  label_codes[1977]=8'd0;
  label_codes[1978]=8'd0;
  label_codes[1979]=8'd0;
  label_codes[1980]=8'd0;
  label_codes[1981]=8'd0;
  label_codes[1982]=8'd0;
  label_codes[1983]=8'd0;
  label_codes[1984]=8'd238;
  label_codes[1985]=8'd239;
  label_codes[1986]=8'd0;
  label_codes[1987]=8'd0;
  label_codes[1988]=8'd0;
  label_codes[1989]=8'd0;
  label_codes[1990]=8'd0;
  label_codes[1991]=8'd0;
  label_codes[1992]=8'd0;
  label_codes[1993]=8'd0;
  label_codes[1994]=8'd0;
  label_codes[1995]=8'd0;
  label_codes[1996]=8'd0;
  label_codes[1997]=8'd0;
  label_codes[1998]=8'd0;
  label_codes[1999]=8'd0;
  label_codes[2000]=8'd105;
  label_codes[2001]=8'd239;
  label_codes[2002]=8'd0;
  label_codes[2003]=8'd0;
  label_codes[2004]=8'd0;
  label_codes[2005]=8'd0;
  label_codes[2006]=8'd0;
  label_codes[2007]=8'd0;
  label_codes[2008]=8'd0;
  label_codes[2009]=8'd0;
  label_codes[2010]=8'd0;
  label_codes[2011]=8'd0;
  label_codes[2012]=8'd0;
  label_codes[2013]=8'd0;
  label_codes[2014]=8'd0;
  label_codes[2015]=8'd0;
  label_codes[2016]=8'd172;
  label_codes[2017]=8'd239;
  label_codes[2018]=8'd0;
  label_codes[2019]=8'd0;
  label_codes[2020]=8'd0;
  label_codes[2021]=8'd0;
  label_codes[2022]=8'd0;
  label_codes[2023]=8'd0;
  label_codes[2024]=8'd0;
  label_codes[2025]=8'd0;
  label_codes[2026]=8'd0;
  label_codes[2027]=8'd0;
  label_codes[2028]=8'd0;
  label_codes[2029]=8'd0;
  label_codes[2030]=8'd0;
  label_codes[2031]=8'd0;
  label_codes[2032]=8'd240;
  label_codes[2033]=8'd61;
  label_codes[2034]=8'd46;
  label_codes[2035]=8'd54;
  label_codes[2036]=8'd0;
  label_codes[2037]=8'd52;
  label_codes[2038]=8'd56;
  label_codes[2039]=8'd52;
  label_codes[2040]=8'd145;
  label_codes[2041]=8'd146;
  label_codes[2042]=8'd241;
  label_codes[2043]=8'd61;
  label_codes[2044]=8'd123;
  label_codes[2045]=8'd46;
  label_codes[2046]=8'd124;
  label_codes[2047]=8'd0;
 end
 // Read from pre-register geometry: same cycle as the former msg1/chr1 decoder.
 always @(posedge clk) text_code<=label_codes[{message,character}];
 wire ink;

 lcd_panel_digit number_rom(dig1,digit_code);
 lcd_panel_font font(clk,code2,row2,col2,ink);
 wire [23:0] song_bg;wire [3:0] song_palette;
 wire song_hit,song_num;
 wire [6:0] song_msg;
 wire [3:0] song_chr,song_row,song_col,song_digit;
 lcd_score_renderer songs(x,y,note_gate,bt_flags,upload_error,score_numbers,guide_state,
   song_bg,song_hit,song_num,song_msg,song_chr,song_row,song_col,song_digit,song_palette);
 wire [23:0] rhythm_bg;wire [3:0] rhythm_palette;
 wire rhythm_hit,rhythm_num;
 wire [6:0] rhythm_msg;
 wire [3:0] rhythm_chr,rhythm_row,rhythm_col,rhythm_digit;
 lcd_rhythm_renderer #(.MULTISONG_ENABLE(MULTISONG_ENABLE)) rhythm_draw(x,y,rhythm_status,rhythm_numbers,note_gate,
   rhythm_bg,rhythm_hit,rhythm_num,rhythm_msg,rhythm_chr,rhythm_row,rhythm_col,rhythm_digit,challenge_preview,preview_ready,rhythm_palette);
 wire rhythm_view=RHYTHM_ENABLE && rhythm_page;
function [7:0] spectrum_label_code(input [2:0] label_id,input [3:0] ch);begin case({label_id,ch})
7'd0:spectrum_label_code=8'd242;
7'd1:spectrum_label_code=8'd243;
7'd2:spectrum_label_code=8'd227;
7'd3:spectrum_label_code=8'd228;
7'd16:spectrum_label_code=8'd113;
7'd17:spectrum_label_code=8'd98;
7'd18:spectrum_label_code=8'd227;
7'd19:spectrum_label_code=8'd228;
7'd32:spectrum_label_code=8'd150;
7'd33:spectrum_label_code=8'd68;
7'd34:spectrum_label_code=8'd244;
7'd35:spectrum_label_code=8'd112;
7'd36:spectrum_label_code=8'd0;
7'd37:spectrum_label_code=8'd68;
7'd38:spectrum_label_code=8'd138;
7'd48:spectrum_label_code=8'd171;
7'd49:spectrum_label_code=8'd245;
7'd50:spectrum_label_code=8'd82;
7'd51:spectrum_label_code=8'd246;
7'd52:spectrum_label_code=8'd61;
7'd53:spectrum_label_code=8'd247;
7'd64:spectrum_label_code=8'd145;
7'd65:spectrum_label_code=8'd146;
7'd80:spectrum_label_code=8'd45;
7'd81:spectrum_label_code=8'd62;
7'd82:spectrum_label_code=8'd58;
7'd83:spectrum_label_code=8'd63;
7'd84:spectrum_label_code=8'd45;
7'd85:spectrum_label_code=8'd51;
7'd86:spectrum_label_code=8'd144;
7'd87:spectrum_label_code=8'd145;
7'd88:spectrum_label_code=8'd146;
default:spectrum_label_code=0;endcase end endfunction
function [7:0] spectrum_axis_code(input [2:0] range_id,input [2:0] mark,input [3:0] ch);begin case({range_id,mark,ch})
9'd0:spectrum_axis_code=8'd45;
9'd16:spectrum_axis_code=8'd55;
9'd17:spectrum_axis_code=8'd45;
9'd18:spectrum_axis_code=8'd45;
9'd19:spectrum_axis_code=8'd145;
9'd20:spectrum_axis_code=8'd146;
9'd32:spectrum_axis_code=8'd51;
9'd33:spectrum_axis_code=8'd144;
9'd34:spectrum_axis_code=8'd145;
9'd35:spectrum_axis_code=8'd146;
9'd48:spectrum_axis_code=8'd52;
9'd49:spectrum_axis_code=8'd144;
9'd50:spectrum_axis_code=8'd145;
9'd51:spectrum_axis_code=8'd146;
9'd64:spectrum_axis_code=8'd53;
9'd65:spectrum_axis_code=8'd144;
9'd66:spectrum_axis_code=8'd145;
9'd67:spectrum_axis_code=8'd146;
9'd128:spectrum_axis_code=8'd45;
9'd144:spectrum_axis_code=8'd52;
9'd145:spectrum_axis_code=8'd144;
9'd146:spectrum_axis_code=8'd145;
9'd147:spectrum_axis_code=8'd146;
9'd160:spectrum_axis_code=8'd54;
9'd161:spectrum_axis_code=8'd144;
9'd162:spectrum_axis_code=8'd145;
9'd163:spectrum_axis_code=8'd146;
9'd176:spectrum_axis_code=8'd58;
9'd177:spectrum_axis_code=8'd144;
9'd178:spectrum_axis_code=8'd145;
9'd179:spectrum_axis_code=8'd146;
9'd192:spectrum_axis_code=8'd51;
9'd193:spectrum_axis_code=8'd52;
9'd194:spectrum_axis_code=8'd144;
9'd195:spectrum_axis_code=8'd145;
9'd196:spectrum_axis_code=8'd146;
9'd256:spectrum_axis_code=8'd45;
9'd272:spectrum_axis_code=8'd54;
9'd273:spectrum_axis_code=8'd144;
9'd274:spectrum_axis_code=8'd145;
9'd275:spectrum_axis_code=8'd146;
9'd288:spectrum_axis_code=8'd58;
9'd289:spectrum_axis_code=8'd144;
9'd290:spectrum_axis_code=8'd145;
9'd291:spectrum_axis_code=8'd146;
9'd304:spectrum_axis_code=8'd51;
9'd305:spectrum_axis_code=8'd56;
9'd306:spectrum_axis_code=8'd144;
9'd307:spectrum_axis_code=8'd145;
9'd308:spectrum_axis_code=8'd146;
9'd320:spectrum_axis_code=8'd52;
9'd321:spectrum_axis_code=8'd54;
9'd322:spectrum_axis_code=8'd144;
9'd323:spectrum_axis_code=8'd145;
9'd324:spectrum_axis_code=8'd146;
9'd384:spectrum_axis_code=8'd45;
9'd400:spectrum_axis_code=8'd51;
9'd401:spectrum_axis_code=8'd52;
9'd402:spectrum_axis_code=8'd55;
9'd403:spectrum_axis_code=8'd145;
9'd404:spectrum_axis_code=8'd146;
9'd416:spectrum_axis_code=8'd52;
9'd417:spectrum_axis_code=8'd55;
9'd418:spectrum_axis_code=8'd45;
9'd419:spectrum_axis_code=8'd145;
9'd420:spectrum_axis_code=8'd146;
9'd432:spectrum_axis_code=8'd55;
9'd433:spectrum_axis_code=8'd45;
9'd434:spectrum_axis_code=8'd45;
9'd435:spectrum_axis_code=8'd145;
9'd436:spectrum_axis_code=8'd146;
9'd448:spectrum_axis_code=8'd57;
9'd449:spectrum_axis_code=8'd55;
9'd450:spectrum_axis_code=8'd45;
9'd451:spectrum_axis_code=8'd145;
9'd452:spectrum_axis_code=8'd146;
10'd512:spectrum_axis_code=8'd45;
10'd528:spectrum_axis_code=8'd52;
10'd529:spectrum_axis_code=8'd144;
10'd544:spectrum_axis_code=8'd54;
10'd545:spectrum_axis_code=8'd144;
10'd560:spectrum_axis_code=8'd56;
10'd561:spectrum_axis_code=8'd144;
10'd576:spectrum_axis_code=8'd58;
10'd577:spectrum_axis_code=8'd144;
default:spectrum_axis_code=0;endcase end endfunction
function [7:0] spectrum_digit_code(input [3:0] d);begin case(d)
4'd0:spectrum_digit_code=8'd45;
4'd1:spectrum_digit_code=8'd51;
4'd2:spectrum_digit_code=8'd52;
4'd3:spectrum_digit_code=8'd53;
4'd4:spectrum_digit_code=8'd54;
4'd5:spectrum_digit_code=8'd55;
4'd6:spectrum_digit_code=8'd56;
4'd7:spectrum_digit_code=8'd57;
4'd8:spectrum_digit_code=8'd58;
4'd9:spectrum_digit_code=8'd59;
default:spectrum_digit_code=0;endcase end endfunction

function [7:0] pressure_label_code(input [1:0] mode,input [3:0] ch);begin case({mode,ch})
6'd16:pressure_label_code=8'd248;
6'd17:pressure_label_code=8'd249;
6'd32:pressure_label_code=8'd183;
6'd33:pressure_label_code=8'd250;
6'd48:pressure_label_code=8'd151;
6'd49:pressure_label_code=8'd152;
default:pressure_label_code=0;endcase end endfunction
 wire [3:0] timbre_color=timbre==0?4'd1:timbre==1?4'd12:4'd3;
 reg [11:0] base_bcd;always @(*)case(keyboard_base)12:base_bcd=12'h012;24:base_bcd=12'h024;48:base_bcd=12'h048;60:base_bcd=12'h060;default:base_bcd=12'h036;endcase
 integer k;
 wire [5:0] strip_key=(x-12'd128)>>3;
 wire strip_c=strip_key==0||strip_key==12||strip_key==24||strip_key==36||strip_key==48;

 always @(*) begin
    background=4'd15;text_hit=0;number_hit=0;zoom=0;
    spectrum_text=0;spectrum_code=0;spectrum_character=0;spectrum_digit=0;spectrum_mark=0;spectrum_left=0;
    message=0;character=0;row=0;column=0;digit=0;left=0;top=0;
    slider_row=0;slider_index=0;numeric=0;knob=0;graph_y=0;fraction=0;
    decay_line=0;release_line=0;
    if(y<56) background=4'd15;
    if(y==55) background=4'd5;
    if(x>=644 && x<788 && y>=8 && y<48) background=4'd10;
    if(x>=520 && x<628 && y>=8 && y<48) background=4'd10;
    if(x>=552 && x<584 && y>=20 && y<36) begin text_hit=1;message=24;left=552;top=20;end
    if(x>=24 && x<56 && y>=20 && y<36) begin text_hit=1;message=0;left=24;top=20;end
    if(x>=72 && x<(timbre==2?120:104) && y>=20 && y<36) begin text_hit=1;message=timbre==0?1:timbre==1?2:114;left=72;top=20;end
    if(x>=132 && x<212 && y>=20 && y<36) begin text_hit=1;message=3;left=132;top=20;end
    if(x>=228 && x<324 && y>=20 && y<36) begin text_hit=1;message=live_page?52:47;left=228;top=20;end
    if(x>=660 && x<724 && y>=20 && y<36) begin text_hit=1;message=4;left=660;top=20;end
    if(x>=384 && x<480 && y>=20 && y<36) begin text_hit=1;
        message=live_page?47:122;left=384;top=20;end
    if(x>=360 && x<372 && y>=22 && y<34)
        background=touch_status==2?4'd3:touch_status==3?4'd11:4'd12;
    if(x>=24 && x<88 && y>=66 && y<82) begin text_hit=1;message=graph_mode==2?55:graph_mode==3?56:waveform_view?8:17;left=24;top=66;end
    if(x>=104 && x<(graph_mode==3?264:168) && y>=66 && y<82) begin text_hit=1;message=graph_mode==3?(phase_delay==4?127:phase_delay==1?121:60):19;left=104;top=66;end
    if(waveform_view && x>=384 && x<496 && y>=66 && y<82) begin text_hit=1;message=23;left=384;top=66;end
    if(waveform_view && x>=544 && x<624 && y>=66 && y<82) begin text_hit=1;message=waveform_scale==3?118:20+waveform_scale;left=544;top=66;end
    if(graph_mode==2 && spectrum_zoom!=4 && x>=512 && x<672 && y>=66 && y<82) begin text_hit=1;message=spectrum_zoom==3?119:57+spectrum_zoom;left=512;top=66;end
    if(graph_mode==3 && x>=352 && x<(phase_delay==4?432:528) && y>=66 && y<82) begin text_hit=1;message=phase_delay==4?127:phase_delay==1?120:phase_delay==0?61:phase_delay==2?62:63;left=352;top=66;end
    if(graph_mode==3 && x>=544 && x<624 && y>=66 && y<82) begin text_hit=1;message=phase_gain==3?118:20+phase_gain;left=544;top=66;end
    if(x>=688 && x<720 && y>=66 && y<82) begin text_hit=1;message=18;left=688;top=66;end
    if(x>=688 && x<720 && y>=94 && y<=224) begin
        background=4'd10;
        if(y>=12'd224-{4'd0,output_peak[15:8]})
            background=output_peak>=32760?4'd11:4'd3;
    end
    if(graph_mode<2 && y>=235 && y<418) begin
        if(y<272) slider_row=0;
        else if(y<321) slider_row=1;
        else if(y<370) slider_row=2;
        else slider_row=3;
        // Four fixed rows need neither multipliers nor variable barrel shifts.
        case(slider_row)
          0:begin top=245;slider_index=indices[23:18];numeric=values[63:48];end
          1:begin top=294;slider_index=indices[17:12];numeric=values[47:32];end
          2:begin top=343;slider_index=indices[11:6];numeric=values[31:16];end
          3:begin top=392;slider_index=indices[5:0];numeric=values[15:0];end
        endcase
        knob=12'd128+{3'd0,slider_index,3'd0};
        if(x>=24 && x<72 && y>=top && y<top+16) begin text_hit=1;message=live_page?48+slider_row:9+slider_row;left=24;end
        if(x>=128 && x<=640 && y>=top+5 && y<top+11) background=x<=knob?4'd1:4'd10;
        if(x+5>=knob && x<=knob+5 && y>=top-2 && y<top+18) background=4'd2;
        if(x>=680 && x<744 && y>=top && y<top+16) begin
            character=(x-680)>>4;digit=numeric[15-4*character -:4];
            number_hit=1;text_hit=1;left=680;
            if((character==0 && numeric[15:12]==0) || (character==1 && numeric[15:8]==0) ||
               (character==2 && numeric[15:4]==0)) text_hit=0;
        end
        if(x>=744 && x<776 && y>=top && y<top+16) begin
            number_hit=0;text_hit=1;message=live_page?(slider_row==1?53:14):(slider_row==2?14:13);left=744;
        end
    end
    if(graph_mode>=2 && x>=96 && x<=672 && y>=94 && y<=418) begin
        background=4'd10;
        if(graph_mode==2) begin
            if(x>=128 && x<=640 && y>=144 && y<=400)begin
             background=4'd15;
             if(y==336||y==272||y==208||y==144||(spectrum_zoom==4?(x==256||x==384||x==512||x==640):(x==212||x==296||x==464||x==631)))background=4'd9;
             if(y==400||x==128)background=4'd5;
            end
        end else if(x>=256 && x<512 && y>=128 && y<384) begin
            background=4'd15;
            if(x==384 || y==256) background=4'd5;
            if(x==256 || x==511 || y==128 || y==383) background=4'd5;
            if(((x==256 || x==511) && (y==128 || y==383)) ||
               ((x==257 || x==510) && (y==128 || y==383)) ||
               ((x==256 || x==511) && (y==129 || y==382))) background=4'd10;
        end
    end
    if(graph_mode<2 && live_page && indices[17:12]<32 && x>=660 && x<676 && y>=294 && y<310) begin text_hit=1;number_hit=0;message=54;left=660;top=294;end
    if(text_hit) begin
        if(!number_hit && message!=15) character=(x-left)>>(4+zoom);
        // Message 127 packs two explicit axis labels without changing any old
        // label: "X:C4 262Hz" at 104, "Y:PCM" at 352.
        if(message==127 && x>=352)character=character+4'd10;
        row=(y-top)>>zoom;column=(x-left)>>zoom;
    end
    if(RHYTHM_ENABLE && x>=24 && x<112 && y>=432 && y<476) begin
        background=4'd7;
        if(x>=36 && x<100 && y>=448 && y<464) begin
            text_hit=1;number_hit=0;message=64;character=(x-36)>>4;row=y-448;column=x-36;
        end
    end
    if(score_page) begin
        background=song_palette;text_hit=song_hit;number_hit=song_num;
        message=song_msg;character=song_chr;row=song_row;column=song_col;digit=song_digit;
    end
    if(native_missing && !rhythm_view && x>=624 && x<776 && y>=432 && y<472)begin
        background=4'd14;text_hit=0;number_hit=0;
        if(x>=644 && x<756 && y>=444 && y<460)begin
            text_hit=1;message=123;character=(x-644)>>4;row=y-444;column=x-644;
        end
    end
     if(rhythm_view) begin
        background=rhythm_palette;text_hit=rhythm_hit;number_hit=rhythm_num;
        message=rhythm_msg;character=rhythm_chr;row=rhythm_row;column=rhythm_col;digit=rhythm_digit;
    end
    if(x>=128 && x<608 && y>=436 && y<472)begin
      text_hit=0;number_hit=0;
      background=palette_code(keyboard_color);
      if(x[2:0]==0 || y==436 || y==471)background=4'd5;
      if(strip_c && y>=466)background=4'd1;
    end

    if(live_page && graph_mode<2 && !score_page && !rhythm_view && x>=24 && x<72 && y>=392 && y<408)begin
     spectrum_text=1;text_hit=1;number_hit=0;left=24;top=392;row=y-392;column=x-24;
     spectrum_code=pressure_label_code(fx_mode,(x-24)>>4);
    end
    if(graph_mode==2 && !score_page && !rhythm_view)begin
     if(spectrum_zoom==4 && x>=512 && x<672 && y>=66 && y<82)begin
      spectrum_text=1;left=512;top=66;spectrum_code=spectrum_label_code(3'd5,(x-512)>>4);
     end
     if(x>=344&&x<496&&y>=60&&y<88)begin
      background=4'd10;
      if(x==344||x==495||y==60||y==87)background=4'd5;
     end
     if(x>=352&&x<416&&y>=66&&y<82)begin
      spectrum_text=1;left=352;top=66;spectrum_character=(x-352)>>4;
      spectrum_code=spectrum_label_code(spectrum_auto===1'b1 ? 3'd1:3'd0,spectrum_character);
     end
     if(x>=128&&x<240&&y>=112&&y<128)begin
      spectrum_text=1;left=128;top=112;spectrum_character=(x-128)>>4;
      spectrum_code=spectrum_label_code(3'd2,spectrum_character);
     end
     if(x>=336&&x<432&&y>=112&&y<128)begin
      spectrum_text=1;left=336;top=112;spectrum_character=(x-336)>>4;
      spectrum_code=spectrum_label_code(3'd3,spectrum_character);
     end
     if(x>=432&&x<512&&y>=112&&y<128)begin
      spectrum_text=1;left=432;top=112;spectrum_character=(x-432)>>4;
      case(spectrum_character)
       0:spectrum_digit=spectrum_peak_bcd[19:16];1:spectrum_digit=spectrum_peak_bcd[15:12];
       2:spectrum_digit=spectrum_peak_bcd[11:8];3:spectrum_digit=spectrum_peak_bcd[7:4];default:spectrum_digit=spectrum_peak_bcd[3:0];
      endcase
      spectrum_code=spectrum_digit_code(spectrum_digit);
      if(spectrum_peak_valid!==1'b1)spectrum_code=8'd62;
      else if((spectrum_character==0&&spectrum_peak_bcd[19:16]==0)||
              (spectrum_character==1&&spectrum_peak_bcd[19:12]==0)||
              (spectrum_character==2&&spectrum_peak_bcd[19:8]==0)||
              (spectrum_character==3&&spectrum_peak_bcd[19:4]==0))spectrum_code=0;
     end
     if(x>=512&&x<544&&y>=112&&y<128)begin
      spectrum_text=1;left=512;top=112;spectrum_character=(x-512)>>4;
      spectrum_code=spectrum_label_code(3'd4,spectrum_character);
     end
     if(y>=402&&y<418&&x>=112&&x<672)begin
      if(spectrum_zoom==4)begin
       if(x<208)begin spectrum_mark=0;spectrum_left=120;end
       else if(x<336)begin spectrum_mark=1;spectrum_left=240;end
       else if(x<464)begin spectrum_mark=2;spectrum_left=368;end
       else if(x<592)begin spectrum_mark=3;spectrum_left=496;end
       else begin spectrum_mark=4;spectrum_left=624;end
      end else if(x<160)begin spectrum_mark=0;spectrum_left=120;end
      else if(x<256)begin spectrum_mark=1;spectrum_left=(spectrum_zoom==1||spectrum_zoom==2)?180:172;end
      else if(x<384)begin spectrum_mark=2;spectrum_left=spectrum_zoom==3?256:264;end
      else if(x<560)begin spectrum_mark=3;spectrum_left=(spectrum_zoom==2||spectrum_zoom==3)?424:432;end
      else begin spectrum_mark=4;spectrum_left=spectrum_zoom==0?600:592;end
      if(x>=spectrum_left)begin
       spectrum_text=1;left=spectrum_left;top=402;spectrum_character=(x-spectrum_left)>>4;
       spectrum_code=spectrum_axis_code(spectrum_zoom,spectrum_mark,spectrum_character);
      end
     end
     if(spectrum_text)begin text_hit=1;number_hit=0;row=y-top;column=x-left;end
    end

    // Lowest MIDI note is numeric and follows the octave control, avoiding a
    // false fixed C4 label. Three decimal digits, derived without a framebuffer.
    if(x>=720 && x<768 && y>=446 && y<462 && !native_missing)begin
      text_hit=1;number_hit=1;character=(x-720)>>4;
      digit=character==0?base_bcd[11:8]:character==1?base_bcd[7:4]:base_bcd[3:0];
      row=y-446;column=x-720;
    end
    // This graph rectangle is disjoint from all later overlays except pages.
    if(!score_page && !rhythm_view && graph_mode<2 && x>=96 && x<=672 && y>=94 && y<=224) begin
        background=4'd10;
        if(x==96 || y==224) background=4'd5;
        if(((x==96 || x==672) && (y==94 || y==224)) ||
           ((x==97 || x==671) && (y==94 || y==224)) ||
           ((x==96 || x==672) && (y==95 || y==223))) background=4'd15;
        if(waveform_view) begin
            if(y==159) background=4'd5;
        end else begin
        if(x<224) graph_y=12'd224-(x-12'd96);
        else if(x<352) begin
            fraction=x-12'd224;decay_line=fraction*(7'd64-sustain);
            graph_y=12'd96+{5'd0,decay_line[13:6]};
        end else if(x<544) graph_y=12'd224-({5'd0,sustain}<<1);
        else begin fraction=x-12'd544;release_line=fraction*sustain;
            graph_y=12'd224-({5'd0,sustain}<<1)+{5'd0,release_line[13:6]};end
        if(y+1>=graph_y && y<=graph_y+1) background=timbre_color;
        end
    end

 end
 always @(posedge clk) begin
    bg1<=background;hit1<=text_hit;num1<=number_hit;msg1<=message;
    spectrum_text1<=spectrum_text;spectrum_code1<=spectrum_code;
    game1<=rhythm_view;game2<=game1;game3<=game2;
    chr1<=character;row1<=row;col1<=column;dig1<=digit;
    wave_hit1<=!rhythm_view && !score_page && waveform_view && waveform_valid && x>=128 && x<640 && y>=94 && y<=224;
    wave_row1<=y[7:1];wave_color1<=timbre_color;
    spectrum_hit1<=!rhythm_view && !score_page && graph_mode==2 && spectrum_valid &&
        x>=128 && x<640 && (spectrum_zoom==3?x[4:0]<28:x[2:0]<6) && y>=145 && y<400;
    spectrum_row1<=12'd400-y;
    phase_hit1<=!rhythm_view && !score_page && graph_mode==3 && phase_valid && x>=256 && x<512 && y>=128 && y<384;
    if(spectrum_hit1 && spectrum_row1<={1'b0,spectrum_height}) bg2<=4'd2;
    else if(phase_hit1 && phase_pixel) bg2<=4'd1;
    else bg2<=wave_hit1 && wave_row1==wave_y[7:1]?wave_color1:bg1;
    hit2<=hit1;code2<=num1?digit_code:spectrum_text1?spectrum_code1:text_code;row2<=row1;col2<=col1;
    // Match the synchronous font-row ROM's extra stage.
    bg3<=bg2;hit3<=hit2;
 end
 wire title_ink;reg title_ink2=0,title_ink3=0,title_box1=0,title_box2=0,title_box3=0;
 generate if(MULTISONG_ENABLE)begin:titles
  challenge_title_rom title_rom(clk,rhythm_status[158]?4'd15:rhythm_status[157:154],x-12'd176,y-12'd132,title_ink);
 end else begin assign title_ink=0;end endgenerate
 always @(posedge clk)begin
  title_ink2<=title_ink;title_ink3<=title_ink2;
  title_box1<=MULTISONG_ENABLE && rhythm_view && x>=176 && x<304 && y>=132 && y<148;
  title_box2<=title_box1;title_box3<=title_box2;
 end
 assign rgb=title_box3?(title_ink3?24'h000000:24'hffffff):(hit3 && ink)?24'h000000:palette_rgb(bg3);
endmodule
