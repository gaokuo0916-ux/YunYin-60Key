`timescale 1ns/1ps
// Read-only PCM analyser. No ready/backpressure path to the audio engine.
// Fs=50 MHz/1024=48828.125 Hz; N=1024; bin spacing=47.6837158 Hz.
// Radix-2 DIF, Hann window, 18-bit complex RAM, /2 at every FFT stage.
// One shared signed multiplier (including Hann), ten clocks per butterfly. Capture pauses
// during analysis; synthesis/output never pause. Only complete bar frames swap.
module audio_spectrum(
 input wire clk,sample_tick,frame_start,
 input wire signed [15:0] pcm,
 input wire [2:0] zoom,
 input wire [5:0] read_bar,
 output wire [7:0] height,
 output reg valid=0,
 output reg [2:0] display_zoom=0,
 output reg [19:0] peak_bcd=0,output reg peak_valid=0,
 input wire gain_auto,output reg display_auto=0);
 localparam CAP=0,CAP_WRITE=1,FFT_READ=2,FFT_DIFF=3,FFT_MUL=4,
            FFT_ROT=5,FFT_WRITE=6,MAG_READ=7,MAG_WRITE=8,WAIT_SWAP=9,
            FFT_A=10,FFT_WRITE_B=11,FFT_MUL_IS=12,FFT_MUL_RS=13,FFT_MUL_IC=14,
            BAR_WRITE=15,PEAK_BCD=16;
 reg [4:0] state=CAP;
 reg [9:0] capture_index=0,group_base=0,j=0,half_span=512;
 reg [8:0] twiddle_index=0,twiddle_stride=1;
 reg [3:0] stage=9;
 reg [8:0] bin=0;
 reg [2:0] work_zoom=0;
 reg [18:0] group_peak=0;
 reg display_bank=0;
 wire [7:0] raw_height;
 // Six measured production-cadence windows: exact zero stays zero; distant
 // quantization residue in the coherent/detuned/quiet/DC cases was <=2.
 // A display-only threshold of 4 keeps the tested quiet tone (peak18).
 // The prior front-bank bar values provide display history.
 localparam [18:0] DISPLAY_FLOOR=19'd4;
 localparam [7:0] FALL_STEP=8'd12;
 wire [7:0] history_height;
 reg history_valid=0;reg [2:0] history_zoom=0;
 reg [18:0] prepared_mag=0,frame_peak=0;reg [5:0] prepared_bar=0;
 reg last_group=0,work_auto=0,pending_peak_valid=0;
 reg [34:0] bin_numerator=0;reg [15:0] frame_hz=0;
 reg [35:0] decimal_shift=0;reg [3:0] decimal_index=0;
 reg [19:0] pending_peak_bcd=0;reg [7:0] pending_offset=0,display_offset=0;
 reg [7:0] frame_bar_peak=0;
 wire [34:0] rounded_numerator=bin_numerator+35'd524288;
 wire [7:0] previous_height=history_valid&&history_zoom==work_zoom?history_height:8'd0;
 wire [7:0] desired_height=filtered_height(prepared_mag);
 wire [7:0] falling_height=previous_height>FALL_STEP?previous_height-FALL_STEP:8'd0;
 wire [7:0] smoothed_height=desired_height>=previous_height?desired_height:
                           desired_height>falling_height?desired_height:falling_height;
 wire [8:0] gain_height={1'b0,raw_height}+{1'b0,display_offset};
 assign height=raw_height==0?8'd0:gain_height>255?8'd255:gain_height[7:0];
 function [35:0] decimal_step;
  input [35:0] value;reg [35:0] adjusted;integer d;
  begin
   adjusted=value;
   for(d=0;d<5;d=d+1)if(adjusted[16+d*4+:4]>=5)
    adjusted[16+d*4+:4]=adjusted[16+d*4+:4]+4'd3;
   decimal_step=adjusted<<1;
  end
 endfunction
 wire [35:0] decimal_next=decimal_step(decimal_shift);
 wire [15:0] window_q;
 wire signed [17:0] cosine_q,sine_q;
 visualizer_tables tables(clk,capture_index,twiddle_index,window_q,cosine_q,sine_q);
 reg signed [32:0] window_product=0;
 reg signed [17:0] real_mem[0:1023],imag_mem[0:1023];
 reg signed [17:0] real_a=0,imag_a=0,real_q=0,imag_q=0;
 reg [9:0] address;
 reg write_enable;
 reg signed [17:0] data_r,data_i;
 reg signed [18:0] sum_r=0,sum_i=0,diff_r=0,diff_i=0;
 reg signed [36:0] product_rc=0,product_is=0,product_rs=0,product_ic=0;
 reg signed [18:0] multiply_x;
 reg signed [17:0] multiply_y;
 wire signed [36:0] shared_product=multiply_x*multiply_y;
 reg signed [37:0] rotated_r=0,rotated_i=0;
 wire [9:0] reverse_bin={bin[0],bin[1],bin[2],bin[3],bin[4],bin[5],bin[6],bin[7],bin[8],1'b0};
 wire [17:0] abs_r=real_q[17] ? -real_q : real_q;
 wire [17:0] abs_i=imag_q[17] ? -imag_q : imag_q;
 wire [18:0] magnitude={1'b0,abs_r}+{1'b0,abs_i};
 // DC is deliberately omitted: it is not an audible pitch.
 wire [18:0] current_mag=bin==0 ? 19'd0 : magnitude;
 wire [18:0] next_peak=current_mag>group_peak ? current_mag:group_peak;
 reg [5:0] range8_bar=0;reg [1:0] range8_count=0;
 wire range8_short=range8_bar[2:0]==0||range8_bar[2:0]==2||range8_bar[2:0]==5;
 wire group_end=work_zoom==4 ? range8_count==(range8_short?1:2) : work_zoom==0 || work_zoom==3 || (work_zoom==1 ? bin[1:0]==3 : bin[2:0]==7);
 wire last_bin=work_zoom==4 ? bin==167 : work_zoom==3 ? bin==15 : work_zoom==0 ? bin==63 : work_zoom==1 ? bin==255 : bin==511;
 wire [5:0] output_bar=work_zoom==4 ? range8_bar : work_zoom==0 || work_zoom==3 ? bin[5:0] : work_zoom==1 ? bin[7:2] : bin[8:3];
 // Low range magnifies sixteen actual bins; it does not invent resolution.
 wire [5:0] read_index=display_zoom==3?{2'd0,read_bar[5:2]}:read_bar;
 // Relative logarithmic display: eight substeps per octave of amplitude.
 // Not a calibrated dBFS instrument. Zero input always yields zero bars.
 function [7:0] log_height;
  input [18:0] value;
  begin
   // Exact original logarithmic code, expressed as disjoint constant slices.
   // Avoid the 19-level priority chain and variable normalization shifter.
   if(|value[18:16])log_height=255;
   else casez(value[15:0]) // synthesis parallel_case full_case
    16'b1???????????????:log_height={4'd15,value[14:11]};
    16'b01??????????????:log_height={4'd14,value[13:10]};
    16'b001?????????????:log_height={4'd13,value[12:9]};
    16'b0001????????????:log_height={4'd12,value[11:8]};
    16'b00001???????????:log_height={4'd11,value[10:7]};
    16'b000001??????????:log_height={4'd10,value[9:6]};
    16'b0000001?????????:log_height={4'd9,value[8:5]};
    16'b00000001????????:log_height={4'd8,value[7:4]};
    16'b000000001???????:log_height={4'd7,value[6:3]};
    16'b0000000001??????:log_height={4'd6,value[5:2]};
    16'b00000000001?????:log_height={4'd5,value[4:1]};
    16'b000000000001????:log_height={4'd4,value[3:0]};
    16'b0000000000001???:log_height={4'd3,{value[2:0],1'd0}};
    16'b00000000000001??:log_height={4'd2,{value[1:0],2'd0}};
    16'b000000000000001?:log_height={4'd1,{value[0:0],3'd0}};
    default:log_height=0;
   endcase
  end
 endfunction
 function [7:0] filtered_height;
  input [18:0] value;reg [7:0] logarithmic;
  begin logarithmic=log_height(value);
   filtered_height=value<=DISPLAY_FLOOR||logarithmic<=32?8'd0:logarithmic-8'd32;
  end
 endfunction
 always @(*) begin
  multiply_x=(state==FFT_MUL_IS || state==FFT_MUL_IC) ? diff_i : diff_r;
  multiply_y=(state==FFT_MUL_IS || state==FFT_MUL_RS) ? sine_q : cosine_q;
  if(state==CAP) begin multiply_x={{3{pcm[15]}},pcm};multiply_y=$signed({2'b0,window_q});end
 end
 always @(*) begin
  address=group_base+j;
  write_enable=0;data_r=0;data_i=0;
  if(state==FFT_A || state==FFT_DIFF || state==FFT_WRITE_B) address=group_base+j+half_span;
  if(state==CAP_WRITE) begin
   address=capture_index;write_enable=1;
   data_r=window_product>>>15;data_i=0;
  end
  if(state==FFT_WRITE) begin
   write_enable=1;data_r=sum_r>>>1;data_i=sum_i>>>1;
  end
  if(state==FFT_WRITE_B) begin write_enable=1;data_r=rotated_r>>>17;data_i=rotated_i>>>17;end
  if(state==MAG_READ || state==MAG_WRITE) address=reverse_bin;
 end
 // Time-multiplex A/B accesses through one synchronous RAM write/read port.
 // This avoids unsupported true-dual-port read-before-write on GW5AT-60B.
 always @(posedge clk) begin
  if(write_enable) begin real_mem[address]<=data_r;imag_mem[address]<=data_i;end
  else begin real_q<=real_mem[address];imag_q<=imag_mem[address];end
 end
 // Native normal-mode true dual-port BSRAM: the inference pattern with
 // two reads replicated this 128-word memory into two SDPBs. Port A is LCD
 // read-only. Port B reads the previous front-bank height, then writes the
 // back-bank value on a later edge. Read-before-write mode is not used.
 wire [15:0] bars_do_a,bars_do_b;
 wire bars_write=state==BAR_WRITE;
 wire bars_history_read=state==MAG_WRITE&&group_end;
 wire [6:0] bars_b_address=bars_write?{!display_bank,prepared_bar}:{display_bank,output_bar};
 DPB #(.BIT_WIDTH_0(8),.BIT_WIDTH_1(8),.READ_MODE0(1'b0),.READ_MODE1(1'b0),
       .WRITE_MODE0(2'b00),.WRITE_MODE1(2'b00),.RESET_MODE("SYNC")) bars_memory(
  .DOA(bars_do_a),.DOB(bars_do_b),.DIA(16'd0),.DIB({8'd0,smoothed_height}),
  .BLKSELA(3'd0),.BLKSELB(3'd0),.ADA({4'd0,display_bank,read_index,3'd0}),
  .ADB({4'd0,bars_b_address,3'd0}),.WREA(1'b0),.WREB(bars_write),
  .CLKA(clk),.CLKB(clk),.CEA(1'b1),.CEB(bars_history_read||bars_write),
  .OCEA(1'b1),.OCEB(1'b1),.RESETA(1'b0),.RESETB(1'b0));
 assign raw_height=bars_do_a[7:0];
 assign history_height=bars_do_b[7:0];
 // synthesis translate_off
 // The vendor primitive's simulation model references an enclosing GSR.
 GSR GSR(.GSRI(1'b1));
 // synthesis translate_on
 always @(posedge clk) begin
  case(state)
   CAP:if(sample_tick) begin
    window_product<=shared_product;state<=CAP_WRITE;
   end
   CAP_WRITE:begin
    if(capture_index==1023) begin
     group_base<=0;j<=0;half_span<=512;stage<=9;
     twiddle_index<=0;twiddle_stride<=1;state<=FFT_READ;
     work_zoom<=zoom;work_auto<=gain_auto===1'b1;
     frame_peak<=0;frame_hz<=0;bin_numerator<=0;
     frame_bar_peak<=0;
    end else begin capture_index<=capture_index+1'b1;state<=CAP;end
   end
   FFT_READ:state<=FFT_A;
   FFT_A:begin real_a<=real_q;imag_a<=imag_q;state<=FFT_DIFF;end
   FFT_DIFF:begin
    sum_r<=$signed({real_a[17],real_a})+$signed({real_q[17],real_q});
    sum_i<=$signed({imag_a[17],imag_a})+$signed({imag_q[17],imag_q});
    diff_r<=$signed({real_a[17],real_a})-$signed({real_q[17],real_q});
    diff_i<=$signed({imag_a[17],imag_a})-$signed({imag_q[17],imag_q});
    state<=FFT_MUL;
   end
   FFT_MUL:begin product_rc<=shared_product;state<=FFT_MUL_IS;end
   FFT_MUL_IS:begin product_is<=shared_product;state<=FFT_MUL_RS;end
   FFT_MUL_RS:begin product_rs<=shared_product;state<=FFT_MUL_IC;end
   FFT_MUL_IC:begin product_ic<=shared_product;state<=FFT_ROT;end
   FFT_ROT:begin
    rotated_r<=$signed({product_rc[36],product_rc})-$signed({product_is[36],product_is});
    rotated_i<=$signed({product_rs[36],product_rs})+$signed({product_ic[36],product_ic});
    state<=FFT_WRITE;
   end
   FFT_WRITE:state<=FFT_WRITE_B;
   FFT_WRITE_B:begin
    state<=FFT_READ;
    if(j+1==half_span) begin
     j<=0;twiddle_index<=0;
     if(group_base+{half_span,1'b0}>=1024) begin
      group_base<=0;half_span<=half_span>>1;stage<=stage-1'b1;
      twiddle_stride<=twiddle_stride<<1;
      if(stage==0) begin bin<=0;group_peak<=0;range8_bar<=0;range8_count<=0;state<=MAG_READ;end
     end else group_base<=group_base+{half_span,1'b0};
    end else begin j<=j+1'b1;twiddle_index<=twiddle_index+twiddle_stride;end
   end
   MAG_READ:state<=MAG_WRITE;
   MAG_WRITE:begin
    if(work_zoom==4)begin if(group_end)begin range8_bar<=range8_bar+1'b1;range8_count<=0;end else range8_count<=range8_count+1'b1;end
    group_peak<=group_end ? 19'd0 : next_peak;
    if(current_mag>frame_peak)begin frame_peak<=current_mag;frame_hz<=rounded_numerator[34:20];end
    if(group_end)begin
     prepared_mag<=next_peak;prepared_bar<=output_bar;last_group<=last_bin;state<=BAR_WRITE;
    end else begin bin<=bin+1'b1;bin_numerator<=bin_numerator+35'd50000000;state<=MAG_READ;end
   end
   BAR_WRITE:begin
    if(smoothed_height>frame_bar_peak)frame_bar_peak<=smoothed_height;
    if(last_group)begin
     history_valid<=1;history_zoom<=work_zoom;
     pending_peak_valid<=frame_peak>DISPLAY_FLOOR;
     decimal_shift<={20'd0,(frame_peak>DISPLAY_FLOOR?frame_hz:16'd0)};decimal_index<=0;
     pending_offset<=work_auto&&frame_peak>DISPLAY_FLOOR?
       8'd224-(smoothed_height>frame_bar_peak?smoothed_height:frame_bar_peak):8'd0;
     state<=PEAK_BCD;
    end else begin bin<=bin+1'b1;bin_numerator<=bin_numerator+35'd50000000;state<=MAG_READ;end
   end
   PEAK_BCD:begin
    decimal_shift<=decimal_next;
    if(decimal_index==15)begin pending_peak_bcd<=decimal_next[35:16];state<=WAIT_SWAP;end
    else decimal_index<=decimal_index+1'b1;
   end
   WAIT_SWAP:if(frame_start) begin
    display_bank<=!display_bank;display_zoom<=work_zoom;valid<=1;
    peak_bcd<=pending_peak_bcd;peak_valid<=pending_peak_valid;
    display_auto<=work_auto;display_offset<=pending_offset;
    capture_index<=0;state<=CAP;
   end
   default:state<=CAP;
  endcase
 end
endmodule
