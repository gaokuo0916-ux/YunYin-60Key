`timescale 1ns/1ps
// 60 external pixels; MIXED_5_7=1 uses consecutive semitone LED order.
// Dock J16 passes through one onboard WS2812 before J24.3: send one black
// transport word first. This is not an extra external key or a beat indicator.
// Set LEADING_BOARD_PIXELS=0 only for a directly wired external DIN.
// Snapshot masks and generate each GRB word serially; no 1440-bit shift mux.
module keyboard60_led #(parameter integer FRAME_CYCLES=500000,BIT_CYCLES=63,
 ZERO_HIGH=15,ONE_HIGH=30,LATCH_CYCLES=5000,LEADING_BOARD_PIXELS=1,BLACK_FIRST=0,MIXED_5_7=0)(input wire clk,
 input wire [59:0] physical_keys,physical_target,physical_wrong,
 input wire [2:0] state,input wire [1:0] timbre,count_in,beat,
 input wire flash,active,input wire [12:0] score_index,input wire [1:0] source,
 output reg data=0,output reg latched=0,frame_valid=0,
 output reg [12:0] frame_index=0,output reg [1:0] frame_source=0);
 reg [59:0] keys=0,target=0,wrong=0;reg [2:0] mode=0;reg [1:0] countdown=0;
 reg [23:0] pixel=0;reg [19:0] period=0;
 reg [12:0] latch_count=0;reg [5:0] pixel_index=0;
 reg [4:0] bit_index=23;reg [6:0] tick=0;reg sending=0,pending=0;
 function integer key_for_pixel(input integer p);
  integer oct,slot;begin oct=p/12;slot=p%12;
   if(MIXED_5_7)key_for_pixel=p;
   else if(BLACK_FIRST)begin
   case(slot)0:key_for_pixel=oct*12+1;1:key_for_pixel=oct*12+3;2:key_for_pixel=oct*12+6;
    3:key_for_pixel=oct*12+8;4:key_for_pixel=oct*12+10;5:key_for_pixel=oct*12;
    6:key_for_pixel=oct*12+2;7:key_for_pixel=oct*12+4;8:key_for_pixel=oct*12+5;
    9:key_for_pixel=oct*12+7;10:key_for_pixel=oct*12+9;default:key_for_pixel=oct*12+11;endcase
   end else case(slot)0:key_for_pixel=oct*12;1:key_for_pixel=oct*12+2;2:key_for_pixel=oct*12+4;
    3:key_for_pixel=oct*12+5;4:key_for_pixel=oct*12+7;5:key_for_pixel=oct*12+9;6:key_for_pixel=oct*12+11;
    7:key_for_pixel=oct*12+1;8:key_for_pixel=oct*12+3;9:key_for_pixel=oct*12+6;
    10:key_for_pixel=oct*12+8;default:key_for_pixel=oct*12+10;endcase
  end
 endfunction
 function [23:0] color(input [5:0] p);
  integer k;begin k=key_for_pixel(p-LEADING_BOARD_PIXELS);color=24'h000000;
   if(p<LEADING_BOARD_PIXELS)color=24'h000000;
   else begin
   // A dark background; active colour channels use the full 8-bit PWM range.
   // No dim idle, pause or completion wash over all sixty keys.
   if(countdown!=0)color=k<countdown?24'hFFFF00:24'h000000;
   else if(mode==6 || mode==5)color=keys[k]?24'h00FF00:24'h000000;
   else begin
    if(keys[k])color=24'h00FF00;
    if(target[k])color=keys[k]?24'h00FF00:24'hFFFF00;
    // An old wrong-note flash must not hide a newly pending cue of that key.
    if(wrong[k]&&!target[k])color=24'h00FFFF;
   end
   end
  end
 endfunction
 always @(posedge clk)begin
  latched<=0;
  // Publish from the captured mask; only consumed with the later latch pulse.
  frame_valid<=|target;
  if(period==FRAME_CYCLES-1)period<=0;else period<=period+1'b1;
  if(pending)begin
   if(latch_count==LATCH_CYCLES-1)begin pending<=0;latched<=1;end
   else latch_count<=latch_count+1'b1;
  end
  if(!sending)begin
   data<=0;
   if(period==0&&!pending)begin
    keys<=physical_keys;target<=physical_target;wrong<=physical_wrong;mode<=state;
    countdown<=active?count_in:2'd0;
    // First pixel is loaded after snapshot registers settle.
    pixel_index<=0;bit_index<=23;tick<=0;sending<=1;pixel<=0;
    frame_index<=score_index;frame_source<=source;
   end
  end else begin
   // Tick 0 selects a pixel; high pulse starts at tick 1 with settled colour.
   if(tick==0)pixel<=color(pixel_index);
   data<=tick>=1 && tick<1+(pixel[bit_index]?ONE_HIGH:ZERO_HIGH);
   if(tick==BIT_CYCLES-1)begin tick<=0;
    if(bit_index==0)begin bit_index<=23;
     if(pixel_index==59+LEADING_BOARD_PIXELS)begin sending<=0;pending<=1;latch_count<=0;end
     else pixel_index<=pixel_index+1'b1;
    end else bit_index<=bit_index-1'b1;
   end else tick<=tick+1'b1;
  end
 end
endmodule
