`timescale 1ns/1ps
// Exercise notation comes from the judge ROM; no display-owned playback clock.
module lcd_rhythm_renderer #(parameter integer MULTISONG_ENABLE=0)(input wire [11:0] x,y,input wire [159:0] status,
 input wire [191:0] numbers,input wire [6:0] gates,
 output wire [23:0] background,output reg text_hit,number_hit,
 output reg [6:0] message,output reg [3:0] character,row,column,digit,input wire [127:0] challenge_preview,input wire preview_ready,output reg [3:0] palette_index);
 wire [2:0] state=status[2:0],judge=status[88:86];
 wire [1:0] level=status[4:3],unlocked=status[6:5];
 wire [5:0] cursor=status[22:17],events=status[28:23];
 wire [5:0] last_index=events==0?6'd0:events-1'b1;
 wire [5:0] page_index=(cursor<events?cursor:last_index)&6'b111000;
 wire [23:0] degrees;wire [55:0] pitches;
 wire [7:0] bar_flags,sharp_flags;wire [63:0] onsets;wire [31:0] durations;
 genvar n;
 generate for(n=0;n<8;n=n+1)begin: exercise
  wire [5:0] index=page_index+n;
  if(MULTISONG_ENABLE)begin
   assign pitches[n*7+:7]=preview_ready?challenge_preview[n*16+:7]:7'd0;
   assign durations[n*4+:4]=challenge_preview[n*16+7+:4];
   assign onsets[n*8+:8]=0;assign bar_flags[n]=challenge_preview[n*16+15];assign sharp_flags[n]=challenge_preview[n*16+14];
   assign degrees[n*3+:3]=challenge_preview[n*16+11+:3];
  end else begin
  assign bar_flags[n]=0;assign sharp_flags[n]=0;
  training_score_rom note(.level(level),.index(index),.degree(degrees[n*3+:3]),
   .onset_units(onsets[n*8+:8]),.duration_units(durations[n*4+:4]),.next_degree(),.due_ms(),.end_ms(),
   .events(),.notes(),.bpm(),.pass_score(),.pitch(pitches[n*7+:7]),.next_pitch());
 end end endgenerate
 function [2:0] degree_of(input [6:0] p);begin if(p==0)degree_of=0;else case(p%12)
 0,1:degree_of=1;2,3:degree_of=2;4:degree_of=3;5,6:degree_of=4;
 7,8:degree_of=5;9,10:degree_of=6;default:degree_of=7;endcase end endfunction
 function sharp(input [6:0] p);begin case(p%12)1,3,6,8,10:sharp=1;default:sharp=0;endcase end endfunction
 wire [3:0] song=status[157:154];
 wire [3:0] local_song=song<5?song+1'b1:song<10?song-4'd4:song-4'd9;
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
 reg zoom;
 integer k;
 function box(input integer px,py,w,h);
 begin box=x>=px && x<px+w && y>=py && y<py+h;end endfunction
 task label_at(input [11:0] px,py,input [3:0] length,input [6:0] msg);
 begin
  if(box(px,py,{length,4'd0},16))begin
   text_hit=1;number_hit=0;message=msg;left=px;top=py;character=(x-px)>>4;zoom=0;
  end
 end endtask
 task title_at(input [11:0] px,py,input [3:0] length,input [6:0] msg);
 begin
  if(box(px,py,{length,5'd0},32))begin
   text_hit=1;number_hit=0;message=msg;left=px;top=py;character=(x-px)>>5;zoom=1;
  end
 end endtask
 task number_at(input [11:0] px,py,input [11:0] value);
 begin
  if(box(px,py,48,16))begin
   text_hit=1;number_hit=1;left=px;top=py;character=(x-px)>>4;zoom=0;
   case(character)0:digit=value[11:8];1:digit=value[7:4];default:digit=value[3:0];endcase
   if((character==0 && value[11:8]==0)||(character==1 && value[11:4]==0))text_hit=0;
  end
 end endtask
 task score_at(input [11:0] px,py,input [11:0] value);
 begin
  if(box(px,py,96,32))begin
   text_hit=1;number_hit=1;left=px;top=py;character=(x-px)>>5;zoom=1;
   case(character)0:digit=value[11:8];1:digit=value[7:4];default:digit=value[3:0];endcase
   if((character==0 && value[11:8]==0)||(character==1 && value[11:4]==0))text_hit=0;
  end
 end endtask
 task note_at(input [11:0] px,py,input [3:0] value);
 begin
  if(box(px,py,32,32))begin
   text_hit=1;number_hit=1;left=px;top=py;character=0;digit=value;zoom=1;
  end
 end endtask
 always @(*)begin
  palette_index=4'd15;text_hit=0;number_hit=0;message=0;character=0;
  row=0;column=0;digit=0;left=0;top=0;zoom=0;
  title_at(24,14,4,102);label_at(464,24,3,95);number_at(516,24,numbers[11:0]);
  label_at(708,24,2,94);
  if(box(24,60,752,1) || box(24,111,752,1))palette_index=4'd5;
  for(k=0;k<3;k=k+1)begin
   label_at(36+264*k,80,MULTISONG_ENABLE?2:3,(MULTISONG_ENABLE?124:115)+k);
   if(k>unlocked)label_at(152+264*k,80,3,69);
   else if(!MULTISONG_ENABLE)begin label_at(132+264*k,80,3,95);number_at(184+264*k,80,k==0?12'h080:k==1?12'h100:12'h120);end
   if(k==level && box(24+264*k,109,224,3))palette_index=4'd1;
  end
  label_at(32,132,4,state==0?65:state==1?70:state==3?72:state==5?73:71);
  if(state==1)note_at(MULTISONG_ENABLE?112:208,124,{2'd0,status[8:7]});
  else if(state==5 && !MULTISONG_ENABLE)label_at(200,132,4,status[113]?108:112);
  if(MULTISONG_ENABLE)begin
   number_at(304,152,{8'd0,local_song});
   if(state==0 || state==5)begin
    if(box(464,124,48,40) || box(528,124,72,40))palette_index=4'd10;
    if(box(480,138,4,12)||box(484,134,4,4)||box(484,150,4,4)||box(556,138,4,12)||box(552,134,4,4)||box(552,150,4,4))palette_index=4'd1;
   end
  end
  // Eight real notation events, with rests and eighth-note strokes.
  if(box(24,174,584,1) || box(24,268,584,1) || box(624,132,1,186))palette_index=4'd5;
  for(k=0;k<8;k=k+1)begin
   if(page_index+k<events && (!MULTISONG_ENABLE || preview_ready))begin
    if(state==2 && cursor==page_index+k)begin
     if(box(28+72*k,188,64,64))palette_index=4'd7;
     if(box(28+72*k,250,64,3))palette_index=4'd1;
    end
    if(k!=0 && (MULTISONG_ENABLE?bar_flags[k]:onsets[k*8+:3]==0) && box(24+72*k,196,1,40))palette_index=4'd6;
    note_at(44+72*k,200,{1'b0,degrees[k*3+:3]});
    // The original high do in Jasmine is C5; retain its octave dot.
    if(pitches[k*7+:7]>=72 && box(57+72*k,191,4,4))palette_index=4'd0;
    if(MULTISONG_ENABLE && pitches[k*7+:7]>=84 && box(57+72*k,184,4,4))palette_index=4'd0;
    if(MULTISONG_ENABLE && pitches[k*7+:7]!=0 && pitches[k*7+:7]<60 && box(57+72*k,234,4,4))palette_index=4'd0;
    if(MULTISONG_ENABLE && pitches[k*7+:7]!=0 && pitches[k*7+:7]<48 && box(57+72*k,242,4,4))palette_index=4'd0;
    if(MULTISONG_ENABLE && sharp_flags[k] && (box(35+72*k,204,2,18)||box(39+72*k,204,2,18)||box(33+72*k,208,10,2)||box(33+72*k,215,10,2)))palette_index=4'd0;
    if(MULTISONG_ENABLE && durations[k*4+:4]==1 && box(48+72*k,244,24,2))palette_index=4'd0;
    if((MULTISONG_ENABLE?(durations[k*4+:4]==1||durations[k*4+:4]==2):durations[k*4+:4]==1) && box(48+72*k,239,24,2))palette_index=4'd0;
   end
  end
  label_at(32,290,4,104);number_at(100,290,{9'd0,status[31:29]});
  label_at(320,290,4,105);number_at(388,290,{9'd0,status[34:32]});
  label_at(648,132,4,103);score_at(648,158,numbers[23:12]);
  label_at(648,214,2,75);number_at(704,214,numbers[35:24]);
  label_at(648,246,4,76);number_at(704,270,numbers[47:36]);
  // Beat dots use the local FPGA timeline.
  for(k=0;k<4;k=k+1)begin
   if((!MULTISONG_ENABLE || song!=3 || k<3) && box(336+28*k,135,12,12))palette_index=state==2 && status[136:135]==k?4'd1:4'd5;
  end
  if(judge!=0)label_at(32,328,2,judge==1?79:judge==2||judge==3?86:judge==4?82:judge==5?83:84);
  else label_at(32,328,6,111);
  if(judge>=1 && judge<=4)begin
   label_at(88,328,2,status[97]?100:101);number_at(120,328,numbers[71:60]);label_at(176,328,2,85);
  end
  label_at(528,328,4,113);number_at(608,328,numbers[59:48]);
  if(state==5)begin
   label_at(32,364,2,79);number_at(68,364,numbers[83:72]);
   label_at(178,364,2,86);number_at(214,364,numbers[95:84]);
   label_at(324,364,2,82);number_at(360,364,numbers[107:96]);
   label_at(470,364,2,83);number_at(506,364,numbers[119:108]);
   label_at(616,364,2,84);number_at(652,364,numbers[131:120]);
  end
  if(box(24,400,224,32))palette_index=4'd7;
  if(box(288,400,224,32) || box(552,400,224,32))palette_index=4'd10;
  label_at(120,408,2,90);label_at(384,408,2,state==3?93:91);label_at(648,408,2,92);
  for(k=0;k<7;k=k+1)begin
   if(box(128+64*k,440,56,34))palette_index=gates[k]?4'd7:4'd10;
   if(status[120+k] && box(128+64*k,440,56,3))palette_index=4'd1;
   if(box(148+64*k,448,16,16))begin
    text_hit=1;number_hit=1;character=0;digit=k+1;left=148+64*k;top=448;zoom=0;
   end
  end
  if(text_hit)begin row=(y-top)>>zoom;column=(x-left)>>zoom;end
 end
endmodule
