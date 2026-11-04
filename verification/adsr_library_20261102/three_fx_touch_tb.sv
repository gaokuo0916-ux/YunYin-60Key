`timescale 1ns/1ps
module three_fx_touch_tb;
 reg clk=0;always #10 clk=~clk;reg [9:0] divider=0;always @(posedge clk)divider<=divider+1'b1;
 reg tv=0,td=0;reg [11:0] tx=0,ty=0;tri1 sda,scl,irq;
 reg [5:0] p2=0;wire [1:0] mode;wire [5:0] depth;
 lcd_adsr_panel dut(.clk(clk),.sample_tick(divider==1023),.selected_timbre(2'd0),.note_gate(7'd0),
 .touch_sda(sda),.touch_scl(scl),.touch_int(irq),.audio_pcm(16'd0),
 .selected_user(1'b0),.user_valid(1'b0),.uploading(1'b0),.bt_activity(1'b0),.upload_error(4'd0),
 .received_bcd(16'd0),.total_bcd(16'd0),.stored_bcd(16'd0),.score_bpm_bcd(12'h120),.guide_state(3'd0),
 .rhythm_mode(1'b0),.rhythm_status(160'd0),.native_missing(1'b0),.visual_pcm(32'd0),.visual_step(32'd0),
 .visual_tag(13'd0),.visual_active(1'b0),.full_keys(60'd0),.full_target(60'd0),.keyboard_base(7'd36),
 .challenge_preview(128'd0),.preview_ready(1'b1),.panel_edit(2'd0),.panel_values(12'd0),.panel_bend(p2),
 .pressure_mode(mode),.pressure_depth(depth));
 integer checks=0;reg [23:0] before_settings;
 task check(input bit yes,input string why);if(!yes)$fatal(1,"FX touch %s",why);checks++;endtask
 task event_at(input bit pressed,input int x,y);begin
  @(negedge clk);tx=x;ty=y;tv=1;td=pressed;@(negedge clk);tv=0;repeat(5)@(negedge clk);
 end endtask
 task tap(input int x,y);begin event_at(1,x,y);event_at(0,x,y);end endtask
 initial begin
  force dut.tv=tv;force dut.td=td;force dut.tx=tx;force dut.ty=ty;
  repeat(12)@(negedge clk);check(mode==1&&depth==0,"default reverb/depth");before_settings=dut.performance_settings;
  tap(40,400);check(mode==1,"parameter page cannot change pressure role");
  tap(250,25);check(dut.live_page,"existing page control");
  for(int m=2;m<=3;m++)begin
   tap(40,400);check(mode==m,"row4 label cycles three effects");
   check(dut.performance_settings==before_settings,"effect choice preserves manual settings");
  end
  tap(40,400);check(mode==1,"delay returns directly to reverb");
  tap(128,400);check(depth==0,"row4 depth minimum");
  tap(640,400);check(depth==63,"row4 depth maximum");
  event_at(1,40,400);for(int j=0;j<5;j++)event_at(1,40,400);check(mode==2,"hold cycles only once");event_at(0,40,400);
  tap(40,300);check(mode==2,"manual pitch label cannot switch effect");
  tap(128,300);check(dut.performance_settings[17:12]==0&&depth==63,"manual screen pitch independent of FX depth");
  tap(700,25);check(mode==1&&depth==0&&dut.performance_settings==before_settings,"restore defaults to reverb and original manual pitch");
  tap(40,70);tap(40,70);check(dut.graph_mode==2,"existing FFT page");
  check(dut.spectrum_zoom==0,"3k default");
  tap(580,70);check(dut.spectrum_zoom==4,"8k inserted after3k");
  tap(580,70);check(dut.spectrum_zoom==1,"12k retained");
  tap(580,70);check(dut.spectrum_zoom==2,"24k retained");
  tap(580,70);check(dut.spectrum_zoom==3,"low range retained");
  tap(580,70);check(dut.spectrum_zoom==0,"range cycle returns3k");
  tap(40,400);check(mode==1,"FFT plot cannot accidentally switch pressure role");
  tap(40,70);tap(40,70);tap(40,70);tap(128,400);check(depth==0,"screen baseline zero");
  for(int p=0;p<32;p++)begin
   p2=6'(p);repeat(5)@(negedge clk);
   check(dut.displayed_performance[5:0]==(p*2+(p>=16?1:0)),"existing row shows pressure contribution");
  end
  p2=0;repeat(5)@(negedge clk);check(dut.performance_values[15:0]==0,"release visual returns baseline");
  tap(640,400);check(dut.performance_values[15:0]==16'h0100,"screen full100percent");
  $display("PASS pressure-role UI %0d checks: same touch coordinates,3 modes/default reverb,hold guard,depth,manual bend,restore and3/8/12/24/0.76k range cycle",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"touch timeout");end
endmodule
