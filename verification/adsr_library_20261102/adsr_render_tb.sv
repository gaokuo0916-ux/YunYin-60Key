`timescale 1ns/1ps
module adsr_render_tb;
 reg clk=0;always #10 clk=~clk;reg[11:0] x=0,y=0;reg[23:0] indices={6'd0,6'd10,6'd41,6'd14};reg[23:0] envelope={6'd0,6'd10,6'd41,6'd14};reg[63:0] values=64'h0001_0194_0065_0187;reg waveform=0,live=0;reg[1:0] mode=0;wire[23:0] current,original;
lcd_adsr_renderer draw(.clk(clk),.x(x),.y(y),.timbre(2'd0),.touch_status(2'd0),.note_gate(7'd1),.indices(indices),.values(values),.sustain(7'd41),.rgb(current),.waveform_view(waveform),.waveform_valid(1'b0),.waveform_sample(16'd0),.waveform_scale(2'd0),.output_peak(16'd0),.score_page(1'b0),.bt_flags(4'd0),.upload_error(4'd0),.score_numbers(60'd0),.guide_state(3'd0),.live_page(live),.graph_mode(mode),.spectrum_height(8'd0),.spectrum_valid(1'b0),.spectrum_zoom(3'd0),.phase_pixel(1'b0),.phase_valid(1'b0),.phase_gain(2'd0),.phase_delay(3'd0),.rhythm_page(1'b0),.rhythm_status(160'd0),.rhythm_numbers(192'd0),.native_missing(1'b0),.full_keys(60'd0),.full_target(60'd0),.keyboard_base(7'd36),.keyboard_color(24'hffffff),.challenge_preview(128'd0),.preview_ready(1'b0),.spectrum_peak_bcd(20'd0),.spectrum_peak_valid(1'b0),.spectrum_auto(1'b0),.pressure_mode(2'd1),.envelope_indices(envelope),.envelope_indices_valid(1'b1));
c63e_renderer_reference previous_renderer(.clk(clk),.x(x),.y(y),.timbre(2'd0),.touch_status(2'd0),.note_gate(7'd1),.indices(indices),.values(values),.sustain(7'd41),.rgb(original),.waveform_view(waveform),.waveform_valid(1'b0),.waveform_sample(16'd0),.waveform_scale(2'd0),.output_peak(16'd0),.score_page(1'b0),.bt_flags(4'd0),.upload_error(4'd0),.score_numbers(60'd0),.guide_state(3'd0),.live_page(live),.graph_mode(mode),.spectrum_height(8'd0),.spectrum_valid(1'b0),.spectrum_zoom(3'd0),.phase_pixel(1'b0),.phase_valid(1'b0),.phase_gain(2'd0),.phase_delay(3'd0),.rhythm_page(1'b0),.rhythm_status(160'd0),.rhythm_numbers(192'd0),.native_missing(1'b0),.full_keys(60'd0),.full_target(60'd0),.keyboard_base(7'd36),.keyboard_color(24'hffffff),.challenge_preview(128'd0),.preview_ready(1'b0),.spectrum_peak_bcd(20'd0),.spectrum_peak_valid(1'b0),.spectrum_auto(1'b0),.pressure_mode(2'd1));
 integer f,checks=0,differences=0,n=0;string outdir;
 initial begin
  if(!$value$plusargs("OUT_DIR=%s",outdir))$fatal;
  for(int c=0;c<6;c++)begin
   case(c)
    0:envelope={6'd0,6'd10,6'd41,6'd14};
    1:envelope[23:18]=63;
    2:begin envelope={6'd0,6'd63,6'd41,6'd14};end
    3:begin envelope={6'd0,6'd10,6'd41,6'd63};end
    4:begin envelope={6'd0,6'd10,6'd41,6'd14};indices=24'hfc003f;live=1;values=64'h0100_0000_0000_0100;end
    5:begin waveform=1;mode=1;end
   endcase
   repeat(1000)@(negedge clk);f=$fopen($sformatf("%s/adsr_%0d.rgb",outdir,c),"wb");
   for(int i=0;i<384002;i++)begin
    n=i<384000?i:0;@(negedge clk);x=n%800;y=n/800;@(posedge clk);#1;
    if($isunknown({current,original}))$fatal(1,"unknown pixel");
    if(i>=2)begin
     int px,py;px=(i-2)%800;py=(i-2)/800;
     if(current!==original)begin
      differences++;
      if(c==5||!(px>=90&&px<=680&&py>=90&&py<=228))$fatal(1,"unrequested UI change case%0d x%0d y%0d",c,px,py);
     end
     $fwrite(f,"%c%c%c",current[23:16],current[15:8],current[7:0]);checks++;
    end
   end
   $fclose(f);
  end
  if(differences<1000)$fatal(1,"ADSR curve did not move");
  $display("PASS ADSR renderer %0d pixels, %0d changed only inside original curve box; A/D/R extremes, livepage actual envelope values,waveform page unchanged versus C63E",checks,differences);$finish;
 end
 initial begin #100000000;$fatal(1,"raster timeout");end
endmodule
