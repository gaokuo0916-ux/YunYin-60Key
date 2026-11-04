`timescale 1ns/1ps
// Ten cascaded HC165s, mixed5/mixed7 times five.
// The farthest serial input is high; missing chips must not create notes.
module keyboard60_full60_chain_tb;
 reg clk=0;always #10 clk=~clk;
 reg [59:0] physical=0;reg [79:0] serial={80{1'b1}};
 wire load_n,key_clk,led,hp_bck,hp_ws,hp_din,pa_en;
 tri1 panel_sda,panel_scl,touch_sda,touch_scl,touch_int;
 wire [7:0] r,g,b;wire pclk,hs,vs,de,bk,rst;
 int led_order[12]='{0,1,2,3,4,5,6,7,8,9,10,11};
 function integer serial_bit(input integer k);
  static int bits[12]='{7,6,5,4,3,15,14,13,12,11,10,9};
  return k/12*16+bits[k%12];
 endfunction
 always @(negedge load_n)begin
  serial={80{1'b1}};
  for(int k=0;k<60;k++)serial[serial_bit(k)]=!physical[k];
 end
 always @(posedge key_clk)serial={1'b1,serial[79:1]};
 guitar_penghuwan_ledguide dut(.sys_clk(clk),.key_data(serial[0]),.key0_n(1'b1),
  .key_load_n(load_n),.key_clk(key_clk),.led_data(led),.hp_bck(hp_bck),
  .hp_ws(hp_ws),.hp_din(hp_din),.pa_en(pa_en),.lcd_r(r),.lcd_g(g),.lcd_b(b),
  .lcd_pclk(pclk),.lcd_hs(hs),.lcd_vs(vs),.lcd_de(de),.lcd_bk(bk),
  .touch_rst_n(rst),.touch_sda(touch_sda),.touch_scl(touch_scl),.touch_int(touch_int),
  .bt_rx(1'b1),.sd_miso(1'b1),.panel_sda(panel_sda),.panel_scl(panel_scl));
 defparam dut.u_keys.PERIOD_CYCLES=1024;
 defparam dut.u_keys.HALF_CYCLES=4;
 defparam dut.u_keys.PRESS_SCANS=2;
 defparam dut.u_keys.RELEASE_SCANS=2;
 defparam dut.u_leds.FRAME_CYCLES=120000;
 integer checks=0,pcm_nonzero=0,hp_nonzero=0,sample_count=0;
 task check(input bit ok,input string why);if(!ok)$fatal(1,"full60_chain: %s",why);checks++;endtask
 always @(negedge clk)if(dut.audio_sample_tick)begin
  sample_count++;
  if(dut.audio_pcm!=0)pcm_nonzero++;
  check(!dut.poly_deadline&&!$isunknown(dut.audio_pcm),"real LCD-enabled production PCM finite and on schedule");
 end
 reg [15:0] hp_word=0;integer hp_bits=0;
 always @(posedge hp_bck)begin
  hp_word={hp_word[14:0],hp_din};hp_bits++;
  if(hp_bits==16)begin if(!pa_en&&hp_word!=0)hp_nonzero++;hp_bits=0;end
 end
 reg [23:0] words[0:60],word=0;integer bit_count=0,pixels=0;time high_at=0;
 always @(posedge led)high_at=$time;
 always @(negedge led)if(high_at!=0)begin
  check($time-high_at==300||$time-high_at==600,"actual top LED pulse widths");
  word={word[22:0],($time-high_at==600)};bit_count++;
  if(bit_count==24)begin check(pixels<61,"no LED word overrun");words[pixels]=word;pixels++;bit_count=0;end
 end
 always @(posedge dut.led_frame_latched)begin
  check(pixels==61&&bit_count==0&&words[0]==0,"one onboard black word plus sixty external words");pixels=0;
 end
 task settle;repeat(13)begin @(posedge dut.key_scan_valid);@(negedge clk);end endtask
 task led_frame;repeat(2)begin @(posedge dut.led_frame_latched);@(negedge clk);end endtask
 task frames(input int n);repeat(n)begin @(posedge dut.audio_sample_tick);@(negedge clk);end endtask
 initial begin
  // Production audio/LCD, accelerated scan/debounce and LED inter-frame interval: LCD on, TF absent, ADS7828 absent. No force statements.
  repeat(1100000)@(negedge clk);
  check(!pa_en&&bk&&dut.guide_state==0,"startup mute clears; LCD/free-play active without TF or ADC");
  check(dut.performance_settings[23:18]==63&&dut.performance_level!=0,"full LCD default volume does not mute audio");
  settle;check(dut.physical_pressed==0,"ten released chips leave all keys released");
  led_frame;for(int p=0;p<61;p++)check(words[p]==0,"released keyboard all dark");
  for(int k=0;k<60;k++)begin
   physical=60'd1<<k;settle;
   check(dut.physical_pressed==(60'd1<<k),$sformatf("real partial wire key %0d",k));
   check(dut.full_note_gate==(60'd1<<k),"scanner reaches free-play gate with no missing-board dependency");
   physical=0;settle;check(dut.physical_pressed==0,"partial key release");
  end
  for(int probe=0;probe<12;probe++)begin
   static int indices[12]='{0,4,5,11,12,23,24,35,36,47,48,59};
   int k;k=indices[probe];
   physical=60'd1<<k;settle;pcm_nonzero=0;hp_nonzero=0;frames(600);led_frame;
   check(pcm_nonzero>100&&hp_nonzero>100,"pressed key produces actual PCM and unmuted onboard DAC serial words");
   for(int p=0;p<60;p++)check(words[p+1]==(p/12*12+led_order[p%12]==k?24'h00FF00:24'h000000),"only corresponding actual LED is full brightness");
   physical=0;settle;frames(50);
  end
  physical=60'h000000000000011;settle;frames(100);check(dut.poly_held==2,"partial keyboard chord keeps two independent voices");
  physical=0;settle;check(dut.full_note_gate==0,"last release ends all physical gates");
  $display("PASS full60_chain LCD-on %0d checks, %0d production samples: ten HC165s, all60 keys, last-key59 LED, full chain boundaries, missing TF/ADC fallback, full255 LEDs and actual unmuted PT8211 words; no physical board",checks,sample_count);
  $finish;
 end
 initial begin #1000000000;$fatal(1,"full60_chain timeout");end
endmodule

