`timescale 1ns/1ps
module challenge_no_bgm_tb;
 reg clk=0;always #10 clk=~clk;
 reg [59:0] keys=0;reg choose=0,play=0,pause=0;reg [3:0] song=0;
 integer checks=0,silent_frames=0,live_frames=0,audible=0,cycles=0;bit watching=0;
 guitar_penghuwan_ledguide #(.LCD_ENABLE(0),.RHYTHM_MS_CYCLES(1),.PRACTICE_COUNT_IN_BEATS(1)) dut(.sys_clk(clk),.key_data(1'b1),.key0_n(1'b1),.bt_rx(1'b1),.sd_miso(1'b1));
 task check(input bit okay,input string why);checks++;if(!okay)$fatal(1,"%s song%0d state%0d",why,song,dut.rhythm_status[2:0]);endtask
 always @(posedge clk)if(watching)begin
  check(dut.song_gates==0&&dut.song_notes==0&&dut.song_epochs==0,"no automatic music events");
  for(int k=0;k<32;k++)if(dut.u_poly.allocated[k])check(dut.u_poly.owner[k]<60||dut.u_poly.owner[k]>=128,"no background-owned voice");
  if(dut.audio_sample_tick)begin
   check(!dut.poly_deadline&&!$isunknown(dut.audio_pcm),"audio deadline/known");
   if(keys==0&&live_frames==0)begin silent_frames++;check(dut.poly_active==0&&dut.audio_pcm==0,"no-key challenge must stay silent");end
   else begin live_frames++;if(dut.audio_pcm!=0)audible++;end
  end
 end
 task select_song(input integer n);
  begin song=4'(n);choose=1;repeat(3)@(negedge clk);choose=0;repeat(80)@(negedge clk);
   check(dut.selected_song==n&&dut.rhythm_status[2:0]==0,"15 song selection retained");
   check(!dut.challenge_range_missing,"default60-key range supports song");
   play=1;@(negedge clk);play=0;repeat(3)@(negedge clk);
   check(dut.rhythm_status[2:0]==1,"countdown retained");
  end
 endtask
 initial begin
  force dut.challenge_mode=1;force dut.physical_pressed=keys;force dut.rhythm_link_song_valid=choose;force dut.rhythm_link_song=song;
  force dut.rhythm_link_play=play;force dut.rhythm_link_pause=pause;force dut.u_rhythm.unlocked=2;
  repeat(10000)@(negedge clk);watching=1;
  for(int n=0;n<15;n++)begin
   select_song(n);cycles=0;
   while(dut.rhythm_status[2:0]!=2)begin @(negedge clk);cycles++;if(cycles>10000)$fatal(1,"countdown timeout");end
   if(n==0)begin
    pause=1;@(negedge clk);pause=0;repeat(2)@(negedge clk);
    check(dut.rhythm_status[2:0]==3,"pause retained");
    begin automatic int at=dut.song_time_ms;repeat(100)@(negedge clk);check(dut.song_time_ms==at,"paused timeline freezes");end
    pause=1;@(negedge clk);pause=0;repeat(2)@(negedge clk);check(dut.rhythm_status[2:0]==2,"resume retained");
   end
   cycles=0;
   while(dut.rhythm_status[2:0]!=5)begin @(negedge clk);cycles++;if(cycles>200000)$fatal(1,"song finish timeout");end
   check(dut.u_rhythm.missed==dut.u_rhythm.notes&&dut.u_rhythm.perfect==0&&dut.u_rhythm.score_value==0,"unchanged no-key judging and song finish");
  end
  select_song(0);wait(dut.rhythm_status[2:0]==2);@(negedge clk);keys=1;
  repeat(2000)@(negedge clk);check(dut.full_note_gate==1&&dut.poly_held==1,"actual keyboard still reaches voice pool in challenge");
  repeat(800)@(posedge dut.audio_sample_tick);
  check(audible>20,"actual keyboard sound is not muted");
  $display("PASS challenge without BGM %0d checks: all15 songs/countdown/judging/end, pause/resume, %0d no-key silent frames, %0d audible live-key frames; no PNR/board test",checks,silent_frames,audible);$finish;
 end
 initial begin #100000000;$fatal(1,"watchdog");end
endmodule
