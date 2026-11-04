`timescale 1ns/1ps
module adsr_panel_edit_tb;
 reg clk=0;always #10 clk=~clk;reg[9:0] divider=0;always@(posedge clk)divider<=divider+1'b1;
 wire tick=divider==1023;reg[1:0] timbre=0;reg tv=0,td=0,fs=0;reg[11:0] tx=0,ty=0;
 wire[74:0] p,g,a;tri1 sda,scl,intn;
 lcd_adsr_panel dut(.clk(clk),.sample_tick(tick),.selected_timbre(timbre),.note_gate(7'd0),
  .piano_coeff(p),.guitar_coeff(g),.accordion_coeff(a),.touch_sda(sda),.touch_scl(scl),.touch_int(intn),
  .audio_pcm(16'd0),.selected_user(1'b0),.user_valid(1'b0),.uploading(1'b0),.bt_activity(1'b0),.upload_error(4'd0),
  .received_bcd(16'd0),.total_bcd(16'd0),.stored_bcd(16'd0),.score_bpm_bcd(12'h120),.guide_state(3'd0),
  .rhythm_mode(1'b0),.rhythm_status(160'd0),.native_missing(1'b0),.visual_pcm(32'd0),.visual_step(32'd0),.visual_tag(13'd0),.visual_active(1'b0),
  .full_keys(60'd0),.full_target(60'd0),.keyboard_base(7'd36),.challenge_preview(128'd0),.preview_ready(1'b0),.panel_edit(2'd0),.panel_values(12'd0),.panel_bend(6'd0));
 integer checks=0;task check(input bit yes,input string why);if(!yes)$fatal(1,"%s",why);checks++;endtask
 task event_at(input bit down,input integer x,y);
  @(negedge clk);tx=x;ty=y;tv=1;td=down;@(negedge clk);tv=0;repeat(8)@(negedge clk);
 endtask
 task tap(input integer x,y);event_at(1,x,y);event_at(0,x,y);endtask
 task snapshot;
  @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(600)@(negedge clk);
 endtask
 integer before_a,before_d,before_r,before_sy;reg[23:0] actual_indices;reg[23:0] saved_times;reg[47:0] saved_ends;
 initial begin
  force dut.tv=tv;force dut.td=td;force dut.raw_x=tx;force dut.raw_y=ty;
  force dut.frame_start=fs;force dut.x=0;force dut.y=0;
  repeat(10000)@(negedge clk);tap(40,74);check(dut.graph_mode==0,"ADSR tab selected");
  for(int t=0;t<3;t++)for(int row=0;row<4;row++)begin
   timbre=t;tap(700,25);repeat(3)@(posedge tick);snapshot;
   before_a=dut.draw.graph_a-96;before_d=dut.draw.graph_d-dut.draw.graph_a;
   before_r=dut.draw.graph_r-dut.draw.graph_s;before_sy=dut.draw.graph_sy;
   tap(640,253+row*49);repeat(3)@(posedge tick);snapshot;
   actual_indices=t==0?dut.piano_indices:t==1?dut.guitar_indices:dut.accordion_indices;
   check(actual_indices[23-row*6-:6]==63,"actual touch updates selected parameter");
   case(row)
    0:check(dut.draw.graph_a-96>before_a,"actual A edit widens attack");
    1:check(dut.draw.graph_d-dut.draw.graph_a>before_d,"actual D edit widens decay");
    2:check(dut.draw.graph_sy<before_sy,"actual S edit raises plateau");
    3:check(dut.draw.graph_r-dut.draw.graph_s>before_r,"actual R edit widens release");
   endcase
   saved_times=dut.view_envelope_indices;saved_ends={dut.draw.graph_a,dut.draw.graph_d,dut.draw.graph_s,dut.draw.graph_r};
   tap(250,25);snapshot;check(dut.live_page,"expression page selected");
   check(dut.view_envelope_indices==saved_times&&{dut.draw.graph_a,dut.draw.graph_d,dut.draw.graph_s,dut.draw.graph_r}==saved_ends,"expression sliders cannot become envelope indices");
   tap(250,25);snapshot;
  end
  $display("PASS ADSR actual touch/bank/frame-snapshot/curve %0d checks,3timbres x4parameters; both pages use actual envelope indices; no hardware",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"panel ADSR timeout");end
endmodule
