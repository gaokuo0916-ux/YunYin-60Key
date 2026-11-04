`timescale 1ns/1ps
module keyboard60_panel_top_tb;
 reg clk=0;always #10 clk=~clk;integer checks=0;
 task check(input bit ok,input string why);if(!ok)$fatal(1,"%s",why);checks++;endtask
 tri1 sda,scl;reg slave_low=0;assign sda=slave_low?1'b0:1'bz;
 reg [95:0] adc_values={12'd4095,12'd4095,12'd0,12'd0,12'd0,12'd0,12'd4095,12'd2048};
 reg [59:0] physical=0;reg [79:0] serial={80{1'b1}};wire load_n,key_clk;wire key_data=serial[0];
 function integer serial_bit(input integer key);
  // Independent physical contacts U1..U5, then U1..U5/U8/U7.
  static int bits[12]='{7,6,5,4,3,15,14,13,12,11,10,9};
  return key/12*16+bits[key%12];
 endfunction
 always @(negedge load_n)begin serial={80{1'b1}};for(int i=0;i<60;i++)serial[serial_bit(i)]=!physical[i];end
 always @(posedge key_clk)serial<={1'b1,serial[79:1]};
 guitar_penghuwan_ledguide #(.LCD_ENABLE(0),.PRACTICE_COUNT_IN_BEATS(0)) dut(
  .sys_clk(clk),.key_data(key_data),.key0_n(1'b1),.key_load_n(load_n),.key_clk(key_clk),
  .bt_rx(1'b1),.sd_miso(1'b1),.panel_sda(sda),.panel_scl(scl));
 defparam dut.control_adc.adc.QUARTER=5;
 defparam dut.control_adc.adc.CONVERSION_WAIT=40;
 defparam dut.control_adc.adc.RETRY=100;
 // Independent ADS7828 single-ended decoder: literal TI SBAS181C Table II.
 // Do not derive this oracle by copying the driver's encoder.
 function integer ti_physical_channel(input [2:0] select_code);
  case(select_code)
   3'b000:ti_physical_channel=0;3'b001:ti_physical_channel=2;
   3'b010:ti_physical_channel=4;3'b011:ti_physical_channel=6;
   3'b100:ti_physical_channel=1;3'b101:ti_physical_channel=3;
   3'b110:ti_physical_channel=5;3'b111:ti_physical_channel=7;
  endcase
 endfunction
 task wait_start;begin @(negedge sda);while(scl!==1'b1)@(negedge sda);end endtask
 task recv(output reg [7:0] v);begin for(int b=7;b>=0;b--)begin @(posedge scl);v[b]=sda;end end endtask
 task ack;begin @(negedge scl);slave_low=1;@(posedge scl);@(negedge scl);slave_low=0;end endtask
 task send(input [7:0] v);begin
  for(int b=7;b>=0;b--)begin slave_low=!v[b];@(posedge scl);@(negedge scl);end
  slave_low=0;@(posedge scl);@(negedge scl);
 end endtask
 reg [7:0] addr,cmd,rd;reg [11:0] captured;integer ch;
 initial forever begin
  wait_start;recv(addr);check(addr==8'h90,"top write address");ack;
  recv(cmd);ch=ti_physical_channel(cmd[6:4]);captured=adc_values[ch*12+:12];ack;
  wait_start;recv(rd);check(rd==8'h91,"top read address");ack;
  send({4'd0,captured[11:8]});send(captured[7:0]);
 end
 task frames(input integer n);repeat(n)begin @(posedge dut.adc_valid);repeat(50)@(negedge clk);end endtask
 task scan_settle;repeat(140000)@(negedge clk);endtask
 reg [31:0] old_c,old_d;
 initial begin
  frames(2);check(dut.adc_online&&dut.keyboard_base==36&&dut.selected_timbre==0,"initial ADS panel connects to main controls");
  check(dut.panel_controls==0,"80-bit key chain has no phantom CTRL word");
  adc_values[23:12]=2048;adc_values[35:24]=2000;adc_values[47:36]=2048;frames(5);
  check(dut.performance_settings[23:18]==32&&dut.performance_settings[11:6]==32,"headless volume/vibrato physical edits");
  check(dut.selected_timbre==1,"physical timbre knob reaches sound bank");
  // Restore vibrato to zero before measuring pressure bend pitch changes.
  adc_values[47:36]=0;frames(2);physical=60'h5;scan_settle;
  check(dut.physical_pressed==5&&dut.full_note_gate==5,"real 80-bit scanner reaches exact semitone keys");
  old_c=dut.u_performance.step_memory[0];old_d=dut.u_performance.step_memory[2];
  adc_values[71:60]=4095;frames(10);
  check(dut.adc_bend==31&&dut.effective_performance[17:12]==32,"pressure 2 collected without overriding screen pitch");
  check(dut.u_performance.step_memory[0]==old_c,"older held note unaffected by last-note bend");
  check(dut.u_performance.step_memory[2]==old_d,"pressure does not bend last pressed note");
  // Keep the real ADC and scanner active. Override only the touchscreen's
  // mode output in this headless test, after its default bend was checked.
  for(int m=1;m<=3;m++)begin
   case(m)
    1:force dut.pressure_mode=2'd1;
    2:force dut.pressure_mode=2'd2;
    3:force dut.pressure_mode=2'd3;
   endcase
   frames(3);
   check(dut.effective_performance[17:12]==32,"FX pressure must not bend pitch");
   check(dut.u_performance.step_memory[0]==old_c && dut.u_performance.step_memory[2]==old_d,"FX restores manual pitch for both held notes");
   check(dut.u_performance_mix.pressure_value==63,"physical pressure reaches shared FX engine");
   repeat(500)@(posedge dut.audio_sample_tick);
   check(dut.u_performance_mix.applied_mode==m && dut.u_performance_mix.wet_coefficient!=0,"production cadence enables selected FX");
   adc_values[71:60]=0;frames(10);
   repeat(600)@(posedge dut.audio_sample_tick);
   check(dut.u_performance_mix.wet_coefficient==0,"physical pressure release restores dry sound");
   adc_values[71:60]=4095;frames(10);
  end
  release dut.pressure_mode;
  frames(3);
  check(dut.effective_performance[17:12]==32,"default mode leaves pressure pitch disabled");
  // Screen bend remains active while pressure2 is pressed or released.
  force dut.performance_settings={6'd32,6'd50,6'd0,6'd0};
  repeat(4)@(posedge dut.audio_sample_tick);repeat(500)@(negedge clk);
  check(dut.u_performance.step_memory[0]==old_c && dut.u_performance.step_memory[2]>old_d,"screen bend retains single-note realtime pitch control");
  adc_values[71:60]=0;frames(10);
  check(dut.effective_performance[17:12]==50 && dut.u_performance.step_memory[2]>old_d,"pressure release cannot reset manual screen bend");
  release dut.performance_settings;
  adc_values[59:48]=800;frames(2);physical=0;scan_settle;
  check(dut.physical_pressed==0&&dut.poly_held>=2&&dut.u_poly.pedal_held!=0,"pressure 1 sustain connected through real scanner and allocator");
  adc_values[59:48]=0;adc_values[71:60]=0;frames(10);
  check(dut.poly_held==0&&dut.adc_bend==0,"pressure release clears hold and bend");
  // SD startup still owns configuration in this deliberately shortened test.
  // Isolate controls from that independent startup probe, then test its guard.
  force dut.configuration_busy=1;adc_values[83:72]=0;frames(5);
  check(dut.guide_state==0,"start rejected while configuration busy");
  adc_values[83:72]=4095;frames(4);force dut.configuration_busy=0;
  adc_values[83:72]=0;frames(5);check(dut.guide_state!=0,"ADC start button begins practice");
  adc_values[95:84]=0;frames(5);check(dut.guide_state==6,"ADC pause retains practice state");
  adc_values[95:84]=4095;frames(4);adc_values[95:84]=0;frames(4);check(dut.guide_state!=6,"ADC second pause press continues");
  adc_values[83:72]=4095;frames(4);adc_values[83:72]=0;frames(4);check(dut.guide_state==0,"ADC second start press stops");
  $display("PASS control-panel top: %0d checks; real I2C, 80-bit scanner, volume/timbre/vibrato, pressure pitch disabled,screen single-note bend,pressure FX,sustain and start/pause/resume/stop",checks);$finish;
 end
 initial begin #160000000;$fatal(1,"top panel timeout state=%0d",dut.guide_state);end
endmodule
