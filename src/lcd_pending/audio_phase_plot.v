`timescale 1ns/1ps
// 0/2/3: actual full-mix 16/32/64-sample delayed phase portrait.
// 1: selected actual voice's extracted fundamental versus 32-sample delay.
// 4: X = fixed C4 sine reference, Y = actual full-mix PCM (display only).
// Own-window gain, continuous Bresenham trace, cleared ping-pong bitmap.
module audio_phase_plot(
 input wire clk,sample_tick,frame_start,input wire signed [15:0] pcm,
 input wire [1:0] gain,input wire [2:0] delay_select,input wire [13:0] read_address,
 output reg pixel=0,valid=0,output reg [1:0] display_gain=3,output reg [2:0] display_delay=4,
 input wire [15:0] input_peak,
 input wire signed [15:0] mono_pcm,input wire mono_valid,mono_active,
 input wire [12:0] mono_tag,input wire [31:0] mono_step,
 input wire signed [15:0] reference_input,output wire [7:0] reference_address);
 reg bitmap[0:32767];
 reg signed [15:0] history[0:127] /* synthesis syn_ramstyle = "block_ram" */;
 reg [31:0] capture[0:511] /* synthesis syn_ramstyle = "block_ram" */;
 reg [6:0] pointer=0,warmup=0;
 reg signed [15:0] history_read=0,current=0,previous=0;
 reg [1:0] sample_pending=0;
 reg display_bank=0,write_bank=1,initial_clear=1;
 reg [14:0] clear_address=0;
 localparam CLEAR=0,WAIT_ZERO=1,CAPTURE=2,PREPARE=3,DIVIDE=4,
            READ=5,READ_WAIT=6,SCALE=7,COORD=8,LINE=9,READY=10;
 reg [3:0] state=CLEAR;
 wire clearing=state==CLEAR;
 reg [1:0] work_gain=3;reg [2:0] work_delay=4;reg [12:0] work_tag=0;reg [7:0] quiet_count=0;
 // Independent reference advances at the audio sample rate, never at key
 // changes. It has no connection back to the synthesis / DAC signal path.
 reg [31:0] reference_phase=0;
 wire signed [15:0] reference_sine=reference_input;
 reg signed [15:0] reference_current=0;
 assign reference_address=reference_phase[31:24];
 reg reference_mode=1;
 // Keep 512 stored points but cover at least one cycle at the bottom of the
 // octave range. History still advances EVERY audio sample: lag remains the
 // labelled 32 real samples. Only plotted point selection is decimated.
 reg [2:0] point_skip=0,skip_count=0;
 wire mono_mode=work_delay==1;
 wire signed [15:0] source=mono_mode?mono_pcm:pcm;
 wire [6:0] lag=work_delay==0?7'd16:work_delay==3?7'd64:7'd32;
 wire [6:0] history_address=pointer-lag;
 reg [8:0] capture_address=0,read_index=0;reg [15:0] peak=0;
 wire [15:0] abs_x=current[15]?(~current+16'd1):current;
 wire [15:0] abs_y=history_read[15]?(~history_read+16'd1):history_read;
 // Reference X has its own fixed scale. Auto gain observes ONLY audio Y;
 // a full-scale reference must not hide a quiet piano or draw on silence.
 wire [15:0] pair_peak=reference_mode?abs_x:(abs_x>abs_y?abs_x:abs_y);
 reg [31:0] capture_read=0;
 reg [23:0] dividend=0,quotient=0,scale=0;
 reg [16:0] remainder=0;reg [4:0] divide_count=0;
 wire [16:0] rem_next={remainder[15:0],dividend[23]};
 wire subtract=rem_next>={1'b0,peak};
 wire [23:0] quotient_next={quotient[22:0],subtract};
 reg signed [40:0] product_x=0,product_y=0;
 wire signed [24:0] positive_scale=$signed({1'b0,scale});
 wire signed [40:0] sx=product_x>>>16,sy=product_y>>>16;
 wire [6:0] target_x=sx>60?7'd124:sx< -60?7'd4:7'd64+sx[6:0];
 wire [6:0] target_y=sy>60?7'd4:sy< -60?7'd124:7'd64-sy[6:0];
 reg [6:0] line_x=64,line_y=64,end_x=64,end_y=64,prev_x=64,prev_y=64;
 reg previous_point=0,x_positive=0,y_positive=0;
 reg [7:0] dx=0,dy=0;reg signed [9:0] error=0;
 wire signed [10:0] twice_error=$signed(error)*2;
 wire advance_x=twice_error>=-$signed({1'b0,dy});
 wire advance_y=twice_error<=$signed({1'b0,dx});
 wire endpoint=line_x==end_x && line_y==end_y;
 wire bitmap_we=clearing || state==LINE;
 wire [14:0] bitmap_address=clearing?clear_address:{write_bank,line_y,line_x};
 always @(posedge clk)begin
  pixel<=bitmap[{display_bank,read_address}];
  if(bitmap_we)bitmap[bitmap_address]<=!clearing;
  capture_read<=capture[read_index];
  if(sample_pending!=0)sample_pending<=sample_pending==2?0:2;
  if(sample_tick)begin
   reference_phase<=reference_phase+32'd23012829;
   reference_current<=reference_sine;
   history_read<=history[history_address];
   history[pointer]<=source;pointer<=pointer+1'b1;current<=source;
   if(warmup<127)warmup<=warmup+1'b1;sample_pending<=1;
  end
  case(state)
   CLEAR:begin
    previous_point<=0;quiet_count<=0;
    if(clear_address[13:0]==16383 && (!initial_clear || clear_address[14]))begin
     if(work_delay!=delay_select || work_tag!=mono_tag)warmup<=0;
     initial_clear<=0;work_gain<=gain;work_delay<=delay_select;work_tag<=mono_tag;reference_mode<=delay_select==4;
     peak<=0;capture_address<=0;previous<=0;state<=WAIT_ZERO;
     skip_count<=0;
     point_skip <= delay_select != 1 ? 3'd0 : mono_step >= 32'd8388608 ? 3'd0 :
                 mono_step >= 32'd4194304 ? 3'd1 : mono_step >= 32'd2097152 ? 3'd3 : 3'd7;
    end else clear_address<=clear_address+1'b1;
   end
   WAIT_ZERO:begin
    if(work_delay!=delay_select || (mono_mode&&work_tag!=mono_tag))begin
     clear_address<={write_bank,14'd0};state<=CLEAR;
    end else if(mono_mode && !mono_active)begin
     line_x<=64;line_y<=64;end_x<=64;end_y<=64;dx<=0;dy<=0;error<=0;
     read_index<=511;state<=LINE;
    end else if(sample_pending==2 && warmup==127)begin
     previous<=current;
     if(mono_mode && abs_x<8)begin
      if(quiet_count<127)quiet_count<=quiet_count+1'b1;
      else begin
       line_x<=64;line_y<=64;end_x<=64;end_y<=64;dx<=0;dy<=0;error<=0;
       read_index<=511;state<=LINE;
      end
     end else begin
      quiet_count<=0;
      if(!mono_mode || (mono_valid&&previous<=0&&current>0))state<=CAPTURE;
     end
    end
   end
   CAPTURE:begin
    if(work_delay!=delay_select || (mono_mode&&(work_tag!=mono_tag || !mono_valid)))begin
     clear_address<={write_bank,14'd0};state<=CLEAR;
    end else if(sample_pending==2)begin
     if(skip_count==point_skip)begin
      skip_count<=0;capture[capture_address]<=reference_mode?{reference_current,current}:{current,history_read};
      if(pair_peak>peak)peak<=pair_peak;
      if(capture_address==511)state<=PREPARE;else capture_address<=capture_address+1'b1;
     end else skip_count<=skip_count+1'b1;
    end
   end
   PREPARE:begin
    read_index<=0;previous_point<=0;
    if(peak<8)begin
     line_x<=64;line_y<=64;end_x<=64;end_y<=64;dx<=0;dy<=0;error<=0;
     read_index<=511;state<=LINE;
    end else if(work_gain==3)begin
     dividend<=24'd3145728;quotient<=0;remainder<=0;divide_count<=0;state<=DIVIDE;
    end else begin scale<=work_gain==0?24'd128:work_gain==1?24'd512:24'd1024;state<=READ;end
   end
   DIVIDE:begin
    dividend<=dividend<<1;quotient<=quotient_next;
    remainder<=subtract?rem_next-{1'b0,peak}:rem_next;
    if(divide_count==23)begin scale<=quotient_next;state<=READ;end
    else divide_count<=divide_count+1'b1;
   end
   READ:state<=READ_WAIT;
   READ_WAIT:state<=SCALE;
   SCALE:begin
    product_x<=$signed(capture_read[31:16])*(reference_mode?25'sd96:positive_scale);
    product_y<=$signed(capture_read[15:0])*positive_scale;state<=COORD;
   end
   COORD:begin
    line_x<=previous_point?prev_x:target_x;line_y<=previous_point?prev_y:target_y;
    end_x<=target_x;end_y<=target_y;
    dx<=previous_point?(target_x>prev_x?target_x-prev_x:prev_x-target_x):0;
    dy<=previous_point?(target_y>prev_y?target_y-prev_y:prev_y-target_y):0;
    error<=previous_point?
      $signed({1'b0,(target_x>prev_x?target_x-prev_x:prev_x-target_x)})-
      $signed({1'b0,(target_y>prev_y?target_y-prev_y:prev_y-target_y)}):10'sd0;
    x_positive<=target_x>=prev_x;y_positive<=target_y>=prev_y;
    prev_x<=target_x;prev_y<=target_y;previous_point<=1;state<=LINE;
   end
   LINE:begin
    if(endpoint)begin
     if(read_index==511)state<=READY;else begin read_index<=read_index+1'b1;state<=READ;end
    end else begin
     if(advance_x)line_x<=x_positive?line_x+1'b1:line_x-1'b1;
     if(advance_y)line_y<=y_positive?line_y+1'b1:line_y-1'b1;
     error<=error-(advance_x?$signed({1'b0,dy}):10'sd0)+(advance_y?$signed({1'b0,dx}):10'sd0);
    end
   end
   READY:if(frame_start)begin
    display_bank<=write_bank;display_gain<=work_gain;display_delay<=work_delay;valid<=1;
    write_bank<=!write_bank;clear_address<={!write_bank,14'd0};state<=CLEAR;
   end
   default:state<=CLEAR;
  endcase
 end
endmodule
