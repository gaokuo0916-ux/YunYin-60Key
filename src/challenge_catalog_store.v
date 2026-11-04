`timescale 1ns/1ps
// One physical score ROM services judge, independent audio cursor and LCD.
// Every response carries its request key; stale rows never become targets.
module challenge_catalog_store(input wire clk,input wire [3:0] song,
 input wire [5:0] judge_index,music_index,input wire [3:0] preview_song,
 input wire [5:0] preview_page,output reg [35:0] judge_word=0,judge_next=0,
 output reg [35:0] music_word=0,music_next=0,
 output wire judge_ready,music_ready,output reg [127:0] preview=0,output wire preview_ready);
 reg [3:0] phase=0,tag=15;
 reg [9:0] request_key=0,response_key=0;
 reg [9:0] j0=1023,j1=1023,m0=1023,m1=1023,pkey=1023,load_key=0;
 reg [127:0] staging=0;reg loading=0;
 wire [35:0] word;
 wire [9:0] query={preview_song,preview_page};
 always @(*)begin
  case(phase)
   0:request_key={song,judge_index};
   1:request_key={song,judge_index+6'd1};
   2:request_key={song,music_index};
   3:request_key={song,music_index+6'd1};
   4:request_key=query;
   default:request_key={load_key[9:6],load_key[5:0]+(phase-4'd4)};
  endcase
 end
 challenge_catalog_rom rom(clk,request_key,word);
 assign judge_ready=j0=={song,judge_index} && j1=={song,judge_index+6'd1};
 assign music_ready=m0=={song,music_index} && m1=={song,music_index+6'd1};
 assign preview_ready=pkey==query;
 always @(posedge clk)begin
  phase<=phase+1'b1;tag<=phase;response_key<=request_key;
  if(phase==4)begin load_key<=query;loading<=query!=pkey;end
  case(tag)
   0:begin judge_word<=word;j0<=response_key;end
   1:begin judge_next<=word;j1<=response_key;end
   2:begin music_word<=word;m0<=response_key;end
   3:begin music_next<=word;m1<=response_key;end
   4,5,6,7,8,9,10:if(loading)staging[(tag-4)*16+:16]<={word[29:25],word[24:21],word[6:0]};
   11:if(loading)begin preview<={{word[29:25],word[24:21],word[6:0]},staging[111:0]};pkey<=load_key;loading<=0;end
   default:begin end
  endcase
 end
endmodule

module challenge_catalog_music(input wire clk,input wire [3:0] song,
 input wire reset,running,input wire [15:0] elapsed_ms,beat_phase,
 input wire [1:0] beat,input wire [7:0] bpm,input wire [5:0] events,
 input wire [15:0] end_ms,input wire [35:0] word,next_word,input wire ready,
 output reg [5:0] index=0,output wire [3:0] gates,output wire [27:0] notes,output wire [3:0] epochs);
 wire [15:0] next_ms=index+1<events?({2'd0,next_word[20:7]}<<2)+{2'd0,next_word[20:7]}:end_ms;
 reg [1:0] previous_beat=0;reg [3:0] bar=0;
 reg [6:0] guide=0;reg guide_gate=0,guide_epoch=0;
 wire [20:0] chord;challenge_chord_rom chords(clk,song,bar,chord);
 wire [15:0] tail=16'd60000-({8'd0,bpm}<<5)-({8'd0,bpm}<<1)-bpm;
 always @(posedge clk)begin
  previous_beat<=beat;
  if(reset)begin index<=0;bar<=0;guide_gate<=0;guide_epoch<=0;end
  else if(running)begin
   if(beat==0 && previous_beat!=0)bar<=bar+1'b1;
   if(ready)begin
    if(index<events && index+1<events && elapsed_ms>=next_ms)begin index<=index+1'b1;guide_gate<=0;end
    else if(index<events)begin
     guide<=word[6:0];
     guide_gate<=word[6:0]!=0 && elapsed_ms+16'd25<next_ms && elapsed_ms<end_ms;
     guide_epoch<=index[0];
    end else guide_gate<=0;
   end
  end
 end
 wire triple=song==3;
 assign gates=running&&!reset?{(beat==(triple?2:3) && beat_phase<tail),(beat==1 && beat_phase<tail),((beat==0 || (!triple && beat==2)) && beat_phase<tail),guide_gate}:4'd0;
 assign notes={chord[20:14],chord[13:7],chord[6:0],guide};
 assign epochs={bar[0],bar[0],beat[1],guide_epoch};
endmodule
