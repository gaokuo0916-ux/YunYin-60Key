`timescale 1ns/1ps
// Geometry only; shares the synchronous font ROM and the existing RGB pipeline.
module lcd_score_renderer(input wire [11:0] x,y,input wire [6:0] gates,
 input wire [3:0] flags,error_code,input wire [59:0] numbers,
 input wire [2:0] guide_state,
 output wire [23:0] background,output reg text_hit,number_hit,
 output reg [6:0] message,output reg [3:0] character,row,column,digit,output reg [3:0] palette_index);
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
 assign background=palette_rgb(palette_index);
 reg [11:0] left,top;
 integer k;
 task label_at(input [11:0] px,py,input [3:0] length,input [6:0] msg);
  begin
   if(x>=px && x<px+{4'd0,length,4'd0} && y>=py && y<py+16) begin
    text_hit=1;number_hit=0;message=msg;left=px;top=py;character=(x-px)>>4;
   end
  end
 endtask
 task count_at(input [11:0] px,py,input [15:0] value);
  begin
   if(x>=px && x<px+64 && y>=py && y<py+16) begin
    text_hit=1;number_hit=1;left=px;top=py;character=(x-px)>>4;
    case(character) 0:digit=value[15:12];1:digit=value[11:8];2:digit=value[7:4];default:digit=value[3:0];endcase
   end
  end
 endtask
 task number_at(input [11:0] px,py,input [11:0] value);
  begin
   if(x>=px && x<px+48 && y>=py && y<py+16) begin
    text_hit=1;number_hit=1;left=px;top=py;character=(x-px)>>4;
    case(character) 0:digit=value[11:8];1:digit=value[7:4];default:digit=value[3:0];endcase
   end
  end
 endtask
 always @(*) begin
  palette_index=4'd15;text_hit=0;number_hit=0;message=0;character=0;
  row=0;column=0;digit=0;left=0;top=0;
  if(y<56) palette_index=4'd15;
  if(y==55) palette_index=4'd5;
  if(x>=644 && x<788 && y>=6 && y<50) palette_index=4'd10;
  label_at(24,20,2,24);label_at(680,20,2,25);
  if(x>=224 && x<336 && y>=6 && y<50) palette_index=4'd7;
  label_at(248,20,4,64);
  label_at(384,20,4,flags[3]?31:32);
  if(x>=360 && x<372 && y>=22 && y<34) palette_index=flags[3]?4'd3:4'd12;
  if(y>=80 && y<152) begin
   if(x>=24 && x<360) palette_index=!flags[0]?4'd7:4'd10;
   if(x>=416 && x<776) palette_index=flags[0]?4'd7:flags[1]?4'd10:4'd10;
  end
  label_at(48,96,4,26);label_at(440,96,4,27);
  if(!flags[0]) label_at(48,124,3,44);else label_at(440,124,3,44);
  label_at(24,192,4,error_code!=0?35:flags[2]?33:flags[1]?34:36);
  if(error_code!=0) number_at(192,192,{8'd0,error_code});
  label_at(24,236,4,37);count_at(168,236,numbers[59:44]);
  label_at(240,236,1,46);count_at(272,236,numbers[43:28]);
  label_at(416,236,4,38);count_at(560,236,numbers[27:12]);
  label_at(24,280,5,39);number_at(192,280,numbers[11:0]);
  label_at(416,280,4,guide_state==0?40:guide_state==6?42:guide_state==5?43:41);
  if(y>=330 && y<398) begin
   if(x>=24 && x<248) palette_index=4'd7;
   if(x>=288 && x<512) palette_index=4'd10;
   if(x>=552 && x<776) palette_index=4'd13;
  end
  label_at(120,356,2,28);label_at(384,356,2,guide_state==6?45:29);label_at(648,356,2,30);
  for(k=0;k<7;k=k+1) begin
   if(x>=128+64*k && x<184+64*k && y>=436 && y<472) palette_index=gates[k]?4'd7:4'd10;
   if(x>=148+64*k && x<164+64*k && y>=446 && y<462) begin
    text_hit=1;number_hit=0;message=15;character=k;left=148+64*k;top=446;
   end
  end
  if(text_hit) begin row=y-top;column=x-left;end
 end
endmodule
