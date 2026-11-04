`timescale 1ns/1ps
// Optional v2.4 protocol, serialized with the existing score reply queue.
module studio_link #(parameter integer MS_CYCLES=50000,RHYTHM_ENABLE=0,POLY_ENABLE=0,PITCH_ENABLE=0,NATIVE_STORE_ENABLE=0,KEYBOARD60_ENABLE=0,MULTISONG_ENABLE=0,RECORD_ENABLE=0)(
 input wire clk,input wire [7:0] rx_data,input wire rx_valid,rx_error,
 input wire legacy_idle,uart_busy,output reg active=0,output reg pending=0,
 output reg [7:0] tx_data=0,output reg tx_start=0,
 input wire [9:0] physical_keys,input wire [2:0] guide_state,
 input wire [12:0] score_index,input wire [15:0] duration_ms,bpm,
 input wire selected_user,user_valid,uploading,
 input wire sample_tick,input wire signed [15:0] pcm,
 output wire [20:0] mapping,
 input wire storage_busy,input wire [2:0] storage_status,input wire [3:0] storage_error,
 input wire [31:0] storage_generation,input wire [13:0] storage_count,input wire [15:0] storage_crc,
 input wire [12:0] storage_rank,input wire [13:0] current_count,input wire [15:0] current_crc,
 output reg storage_save=0,storage_recall=0,
 input wire restore_map,input wire [12:0] restore_rank,output wire [12:0] configured_rank,
 input wire audio_busy,input wire [2:0] audio_status,input wire [3:0] audio_error,
 input wire [31:0] audio_generation,audio_samples,input wire [15:0] audio_crc,
 output reg audio_start=0,audio_stop=0,output reg [6:0] audio_seconds=30,
 input wire capture_long_arm,capture_long_stop,capture_long_abort,input wire [31:0] capture_limit,consumed,
 output wire [2:0] capture_state,output wire [31:0] produced,output wire [15:0] capture_crc,output wire capture_overflow,
 input wire [15:0] capture_address,output wire [15:0] capture_data,
 output reg audio_client_request=0,output reg [31:0] audio_client_offset=0,output reg [7:0] audio_client_index=0,
 input wire audio_client_ready,input wire [3:0] audio_client_error,input wire [15:0] audio_client_data,
 input wire [159:0] rhythm_status,input wire rhythm_enabled,
 output reg rhythm_enter=0,rhythm_play=0,rhythm_pause=0,rhythm_exit=0,
 output reg rhythm_level_valid=0,output reg [1:0] rhythm_level=0,
 input wire [63:0] sd_diagnostic,output reg sd_reinitialize=0,
 // 0=piano, 1=guitar, 2=accordion. Reply only after the selector applies it.
 input wire [1:0] selected_timbre,
 output reg timbre_request=0,output reg [1:0] timbre_id=0,
 input wire poly_ready,poly_done,poly_ok,poly_demo,poly_deadline,
 input wire [5:0] poly_active,poly_held,input wire [31:0] poly_active_mask,poly_held_mask,
 output reg poly_valid=0,output reg [2:0] poly_op=0,
 output reg [15:0] poly_a=0,poly_b=0,
 input wire native_score,input wire [7:0] pitch_code,input wire native_ready,native_missing,
 input wire [59:0] keyboard_keys,input wire [6:0] keyboard_base,
 output reg octave_request=0,output reg [2:0] octave_value=2,
 output reg rhythm_song_valid=0,output reg [3:0] rhythm_song=0,
 output reg record_request=0,output reg [3:0] record_operation=0,output reg [47:0] record_arguments=0,
 input wire record_done,input wire [3:0] record_error,input wire [95:0] record_info,
 input wire [15:0] record_word,input wire capture_immediate);

 // One existing 512-byte card cache, streamed without a second packet RAM.
 reg fast_frame=0,fast_ready=0,fast_last=0;
 reg [1:0] fast_phase=0,fast_group_index=0,fast_fill=0;
 reg [2:0] fast_footer=0;
 reg [8:0] fast_length=0;
 reg [9:0] fast_byte=0;
 reg [23:0] fast_bits=0;
 wire [7:0] fast_input=fast_byte[0]?audio_client_data[15:8]:audio_client_data[7:0];
 function [7:0] b64(input [5:0] n);
 begin b64=n<26?8'd65+n:n<52?8'd97+(n-26):n<62?8'd48+(n-52):n==62?8'd43:8'd47;end
 endfunction
 reg selecting_song=0;
 wire game_idle=!rhythm_enabled || rhythm_status[2:0]==0 || rhythm_status[2:0]==5;
 wire any_key=KEYBOARD60_ENABLE ? (|keyboard_keys) : (|physical_keys[6:0]);
 wire all_idle=!any_key && physical_keys[9:7]==0;
 wire line_valid,line_error;wire [47:0] command;wire [63:0] args;wire [2:0] argc;
 // Replicate this measured high-fanout data decode; protocol timing is unchanged.
 wire argc_zero /* synthesis syn_maxfan = 64 */ = argc==0;
 wire [15:0] a=args[15:0],b=args[31:16];
 bluetooth_command_rx parser(clk,rx_data,rx_valid,rx_error,line_valid,line_error,command,args,argc);
 reg map_request=0,map_silent=0;wire map_busy,map_done;reg [12:0] map_rank=0;reg [12:0] requested_rank=0;
 assign configured_rank=map_rank;
 studio_keymap keymap(clk,map_request,requested_rank,map_busy,map_done,mapping);
 wire [2:0] rec_state;
 assign capture_state=rec_state;
 // Only the TF writer can arm this ring. Unused legacy ports are constants;
 // no separate short-take memory or capture controller remains in this link.
 studio_pcm_capture recording(.clk(clk),.sample_tick(sample_tick),.pcm(pcm),
  .physical_keys(KEYBOARD60_ENABLE?{6'd0,any_key}:physical_keys[6:0]),.arm(1'b0),.abort(capture_long_abort),.length(16'd0),
  .state(rec_state),.count(),.requested(),.crc(capture_crc),
  .read_address(capture_address),.read_data(capture_data),
  .long_arm(capture_long_arm),.long_stop(capture_long_stop),.long_limit(capture_limit),
  .consumed(consumed),.long_mode(),.produced(produced),.overflow(capture_overflow),.immediate_start(RECORD_ENABLE?capture_immediate:1'b0));
 reg [7:0] message[0:47];reg [15:0] packet_words[0:15];reg packet_frame=0;reg [6:0] size=0,position=0;integer p;
 reg [3:0] work=0;reg [2:0] wait_cycles=0;
 reg [159:0] game_snapshot=0;
 reg [15:0] game_crc=16'hffff;
 reg [4:0] game_byte=0;
 integer game_i;
 // GINFO already has an immutable snapshot for its CRC. Share that snapshot
 // with the serial formatter instead of writing a second 48-byte ASCII copy.
 wire [6:0] game_data_position=position-7'd2;
 wire [4:0] game_read_index=work==7?game_byte:game_data_position[5:1];
 wire [7:0] game_read_byte=game_snapshot[159-{game_read_index,3'b000}-:8];
 reg [15:0] packet_crc=0;
 reg metadata_packet=0,record_reply=0,game_reply=0;reg [1:0] record_reply_kind=0;
 wire [15:0] packet_data=metadata_packet?record_word:audio_client_data;
 wire [31:0] long_offset={a,b};
 wire [31:0] long_remaining=audio_samples-long_offset;reg [4:0] packet_length=0,packet_index=0;
 wire [6:0] data_position=position-7'd14;
 wire [15:0] stream_word=packet_words[data_position[5:2]];
 reg [3:0] packet_nibble;
 always @(*)case(data_position[1:0])
  0:packet_nibble=stream_word[7:4];1:packet_nibble=stream_word[3:0];
  2:packet_nibble=stream_word[15:12];3:packet_nibble=stream_word[11:8];
 endcase
 wire [6:0] crc_position=data_position-{packet_length,2'b00}-7'd1;
 reg [3:0] crc_nibble;
 always @(*)case(crc_position[1:0])
  0:crc_nibble=packet_crc[15:12];1:crc_nibble=packet_crc[11:8];
  2:crc_nibble=packet_crc[7:4];3:crc_nibble=packet_crc[3:0];
 endcase
 reg [15:0] hold_counter=0,last_held=0,last_expected=0,expected_latched=0;
 reg [15:0] ms_count=0;reg [2:0] previous_state=0;
 wire ms_tick=ms_count==MS_CYCLES-1;
 function [7:0] hex(input [3:0] n);hex=n<10?8'd48+{4'd0,n}:8'd55+{4'd0,n};endfunction
 function [15:0] crcbyte(input [15:0] c,input [7:0] b);
  integer n;reg [15:0] v;begin v=c^{b,8'd0};for(n=0;n<8;n=n+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end
 endfunction
 task put(input [7:0] c);begin message[p]<=c;p=p+1;end endtask
 task h4(input [15:0] v);begin put(hex(v[15:12]));put(hex(v[11:8]));put(hex(v[7:4]));put(hex(v[3:0]));end endtask
 task h2(input [7:0] v);begin put(hex(v[7:4]));put(hex(v[3:0]));end endtask
 task finish;begin game_reply<=0;record_reply<=0;put(10);size<=p[6:0];position<=0;pending<=1;packet_frame<=0;end endtask
 task ok;begin p=0;put("O");put("K");finish;end endtask
 task err;begin p=0;put("E");put("R");put("R");put(" ");put("3");finish;end endtask
 task tone_reply;begin p=0;put("T");put("O");put("N");put("E");put(" ");put(hex({2'd0,selected_timbre}));finish;end endtask
 task poly_issue(input [2:0] op);begin poly_op<=op;poly_a<=a;poly_b<=b;poly_valid<=1;work<=10;end endtask
 // Manager info/error remain stable until the next serialized REC request.
 // Stream new replies instead of expanding writes to message[0:47].
 function [7:0] record_char(input [6:0] ix);
 reg [3:0] digit;begin
  record_char=32;digit=0;
  if(record_reply_kind==0)begin
   case(ix)
    0:record_char="N";2:record_char=hex(record_info[7:4]);3:record_char=hex(record_info[3:0]);
    5:record_char=hex(record_info[15:12]);6:record_char=hex(record_info[11:8]);30:record_char=10;
   endcase
   if(ix>=8 && ix<16)begin digit=record_info[47-(ix-8)*4-:4];record_char=hex(digit);end
   if(ix>=17 && ix<25)begin digit=record_info[79-(ix-17)*4-:4];record_char=hex(digit);end
   if(ix>=26 && ix<30)begin digit=record_info[95-(ix-26)*4-:4];record_char=hex(digit);end
  end else if(record_reply_kind==1)begin
   case(ix)
    0:record_char="Q";2:record_char=hex(record_info[15:12]);3:record_char=hex(record_info[11:8]);
    5:record_char=hex(record_info[7:4]);6:record_char=hex(record_info[3:0]);
    8:record_char=hex(record_info[23:20]);9:record_char=hex(record_info[19:16]);
    11:record_char=hex(record_info[31:28]);12:record_char=hex(record_info[27:24]);13:record_char=10;
   endcase
  end else begin
   case(ix)0:record_char="E";2:record_char="0";3:record_char=hex(record_error);4:record_char=10;endcase
  end
 end endfunction
 task record_finish(input [1:0] kind,input [6:0] length);
 begin game_reply<=0;record_reply<=1;record_reply_kind<=kind;size<=length;position<=0;pending<=1;packet_frame<=0;end endtask
 always @(posedge clk)begin
  tx_start<=0;map_request<=0;storage_save<=0;storage_recall<=0;audio_start<=0;audio_stop<=0;audio_client_request<=0;record_request<=0;previous_state<=guide_state;
  rhythm_enter<=0;rhythm_play<=0;rhythm_pause<=0;rhythm_exit<=0;rhythm_level_valid<=0;rhythm_song_valid<=0;sd_reinitialize<=0;timbre_request<=0;octave_request<=0;
  if(ms_tick)ms_count<=0;else ms_count<=ms_count+1'b1;
  if(guide_state==3 && previous_state!=3)begin hold_counter<=0;expected_latched<=duration_ms;end
  else if(guide_state==3 && ms_tick && hold_counter!=16'hffff)hold_counter<=hold_counter+1'b1;
  if(previous_state==3 && guide_state!=3)begin last_held<=hold_counter;last_expected<=expected_latched;end
  if(guide_state==0 || (guide_state==1 && previous_state!=1 && score_index==0))begin last_held<=0;last_expected<=0;end
  // Score replies always finish first; one message owns the UART until LF.
  if(pending && !active && legacy_idle && !uart_busy)begin active<=1;pending<=0;end
  if(active && !uart_busy && !tx_start)begin
   if(fast_frame)begin
    if(fast_phase==0)begin
     tx_data<=message[position];tx_start<=1;
     if(position==15)begin fast_phase<=1;position<=0;end else position<=position+1'b1;
    end else if(fast_phase==1 && fast_ready)begin
     case(fast_group_index)
      0:tx_data<=b64(fast_bits[23:18]);1:tx_data<=b64(fast_bits[17:12]);
      2:tx_data<=fast_fill>=2?b64(fast_bits[11:6]):8'd61;
      3:tx_data<=fast_fill==3?b64(fast_bits[5:0]):8'd61;
     endcase
     tx_start<=1;
     if(fast_group_index==3)begin
      fast_ready<=0;fast_group_index<=0;
      if(fast_last)begin fast_phase<=2;fast_footer<=0;end
      else begin fast_fill<=0;fast_bits<=0;wait_cycles<=0;end
     end else fast_group_index<=fast_group_index+1'b1;
    end else if(fast_phase==2)begin
     case(fast_footer)
      0:tx_data<=32;1:tx_data<=hex(packet_crc[15:12]);2:tx_data<=hex(packet_crc[11:8]);
      3:tx_data<=hex(packet_crc[7:4]);4:tx_data<=hex(packet_crc[3:0]);5:tx_data<=10;
     endcase
     tx_start<=1;
     if(fast_footer==5)begin active<=0;fast_frame<=0;work<=0;end
     else fast_footer<=fast_footer+1'b1;
    end
   end else begin
   if(game_reply)begin
    case(position)
     0:tx_data<="G";1,42:tx_data<=32;
     43:tx_data<=hex(game_crc[15:12]);44:tx_data<=hex(game_crc[11:8]);
     45:tx_data<=hex(game_crc[7:4]);46:tx_data<=hex(game_crc[3:0]);47:tx_data<=10;
     default:tx_data<=hex(game_data_position[0]?game_read_byte[3:0]:game_read_byte[7:4]);
    endcase
   end else if(record_reply)tx_data<=record_char(position);
   else if(!packet_frame || position<14)tx_data<=message[position];
   else if(position<14+{packet_length,2'b00})tx_data<=hex(packet_nibble);
   else if(position==14+{packet_length,2'b00})tx_data<=32;
   else if(position==size-1'b1)tx_data<=10;
   else tx_data<=hex(crc_nibble);
   tx_start<=1;
   if(position==size-1'b1)active<=0;else position<=position+1'b1;
   end
  end
  if(work==13 && audio_client_ready)begin
   if(audio_client_error!=0)begin fast_frame<=0;err;work<=0;end
   else begin work<=14;wait_cycles<=0;pending<=1;position<=0;end
  end
  if(work==14 && !fast_ready)begin
   if(wait_cycles!=2)wait_cycles<=wait_cycles+1'b1;
   else begin
    case(fast_fill)0:fast_bits[23:16]<=fast_input;1:fast_bits[15:8]<=fast_input;2:fast_bits[7:0]<=fast_input;endcase
    packet_crc<=crcbyte(packet_crc,fast_input);
    fast_fill<=fast_fill+1'b1;fast_byte<=fast_byte+1'b1;
    if(fast_byte[0])audio_client_index<=audio_client_index+1'b1;
    wait_cycles<=0;
    if(fast_fill==2 || fast_byte+1'b1=={fast_length,1'b0})begin
     fast_ready<=1;fast_last<=fast_byte+1'b1=={fast_length,1'b0};
     if(fast_byte+1'b1=={fast_length,1'b0})work<=15;
    end
   end
  end
  if(work==1 && map_done)begin map_rank<=requested_rank;if(!map_silent)ok;work<=0;map_silent<=0;end
  if(restore_map && !map_busy)begin requested_rank<=restore_rank;map_request<=1;map_silent<=1;work<=1;end
  if(work==2)begin
   if(wait_cycles!=2)wait_cycles<=wait_cycles+1'b1;
   else begin
    packet_words[packet_index[3:0]]<=packet_data;
    packet_crc<=crcbyte(crcbyte(packet_crc,packet_data[7:0]),packet_data[15:8]);
    if(packet_index+1'b1==packet_length)work<=3;
    else begin packet_index<=packet_index+1'b1;audio_client_index<=audio_client_index+1'b1;wait_cycles<=0;end
   end
  end
  if(work==4 && audio_client_ready)begin if(audio_client_error!=0)begin err;work<=0;end else begin work<=2;wait_cycles<=0;end end
  if(work==3)begin game_reply<=0;record_reply<=0;size<=20+{packet_length,2'b00};position<=0;pending<=1;packet_frame<=1;work<=0;end
  // Allow top-level mode selection to settle before selecting its exercise.
  if(work==5)begin
   if(wait_cycles!=2)wait_cycles<=wait_cycles+1'b1;
   else begin if(selecting_song)rhythm_song_valid<=1;else rhythm_level_valid<=1;work<=6;wait_cycles<=0;end
  end
  if(work==6)begin
   if(wait_cycles!=2)wait_cycles<=wait_cycles+1'b1;
   else begin ok;work<=0;end
  end
  if(work==7)begin
   game_crc<=crcbyte(game_crc,game_read_byte);
   if(game_byte==19)work<=8;else game_byte<=game_byte+1'b1;
  end
  if(work==8)begin
   game_reply<=1;record_reply<=0;size<=48;position<=0;
   pending<=1;packet_frame<=0;work<=0;
  end
  // The pulse crosses one sequential selector boundary. A delayed acknowledgement
  // reports the actual instrument, so a rejected request cannot look successful.
  if(work==9)begin
   if(wait_cycles!=2)wait_cycles<=wait_cycles+1'b1;
   else begin if(selected_timbre==timbre_id)tone_reply;else err;work<=0;end
  end
  // Hold valid until the shared allocator accepts it. Legacy key events can
  // begin while the ASCII command is being decoded; a one-clock pulse loses it.
  if(work==10&&poly_ready)begin poly_valid<=0;work<=11;end
  if(work==11&&poly_done)begin if(poly_ok)ok;else err;work<=0;end
  if(work==12 && record_done)begin
   if(record_error!=0)begin record_finish(2,5);work<=0;
   end else if(record_operation==0)begin record_finish(1,14);work<=0;
   end else if(record_operation==1)begin record_finish(0,31);work<=0;
   end else if(record_operation==8)begin
    metadata_packet<=1;audio_client_index<=record_arguments[7:0];
    packet_index<=0;packet_length<=16;wait_cycles<=0;work<=2;
    p=0;put("J");put(" ");h4(16'd0);h4(record_arguments[15:0]);put(" ");h2(8'd16);put(" ");
    packet_crc<=crcbyte(crcbyte(crcbyte(crcbyte(crcbyte(16'hffff,record_arguments[7:0]),record_arguments[15:8]),8'd0),8'd0),8'd16);
   end else begin ok;work<=0;end
  end
  if(line_valid && !line_error && !active && !pending && work==0)begin
   case(command)
    "FEAT":if(argc_zero)begin p=0;put("F");put("2");put("4");put(" ");h4((RHYTHM_ENABLE?16'h05fb:16'h01bb)|(POLY_ENABLE?16'h0200:16'd0)|(PITCH_ENABLE?16'h0800:16'd0)|(NATIVE_STORE_ENABLE?16'h1000:16'd0)|(KEYBOARD60_ENABLE?16'h2000:16'd0)|(MULTISONG_ENABLE?16'h4000:16'd0)|(RECORD_ENABLE?16'h8000:16'd0));put(" ");h4(16'hffff);finish;end else err;
    "REC":if(RECORD_ENABLE && argc>=1 && a<=9 &&
      ((a==0||a==2||a==6||a==7||a==9)?argc==1:(a==1||a==5||a==8)?argc==2:a==3?argc==3:argc==4))begin
     if(a!=0 && (storage_busy || audio_busy || uploading))begin p=0;put("E");put(" ");h2(8'd4);finish;end
     else begin record_operation<=a[3:0];record_arguments<=args[63:16];record_request<=1;work<=12;end
    end else begin p=0;put("E");put(" ");h2(8'd8);finish;end
    "KINFO":if(KEYBOARD60_ENABLE && argc_zero)begin
     p=0;put("K");put(" ");h2({1'b0,keyboard_base});put(" ");h2(8'd60);put(" ");
     h4({4'd0,keyboard_keys[59:48]});h4(keyboard_keys[47:32]);h4(keyboard_keys[31:16]);h4(keyboard_keys[15:0]);finish;
    end else err;
    "KOCT":if(KEYBOARD60_ENABLE && argc==1 && a<=4 && all_idle && !uploading && !storage_busy && !audio_busy && !rhythm_enabled && (guide_state==0||guide_state==5))begin
     octave_value<=a[2:0];octave_request<=1;ok;
    end else err;
    "MINFO":if(PITCH_ENABLE && argc_zero)begin
     p=0;put("N");put(" ");put(native_score?"1":"0");put(" ");put(selected_user?"1":"0");put(" ");
     h4({3'd0,score_index});put(" ");h2(native_ready?pitch_code:8'd0);put(" ");put(native_ready?"1":"0");put(" ");put(native_ready&&native_missing?"1":"0");finish;
    end else err;
    "PINFO":if(POLY_ENABLE&&argc_zero)begin
     p=0;put("P");put(" ");h2({2'd0,poly_active});put(" ");h2({2'd0,poly_held});put(" ");
     h4(poly_active_mask[31:16]);h4(poly_active_mask[15:0]);put(" ");h4(poly_held_mask[31:16]);h4(poly_held_mask[15:0]);
     put(" ");put(poly_demo?"1":"0");put(" ");put(poly_deadline?"1":"0");finish;
    end else err;
    "PCLR":if(POLY_ENABLE&&argc_zero)poly_issue(0);else err;
    "PDEMO":if(POLY_ENABLE&&argc==2&&a<=32&&b<=1&&all_idle&&!uploading&&!storage_busy&&!audio_busy&&!rhythm_enabled&&(guide_state==0||guide_state==5))poly_issue(3);else err;
    "PON":if(POLY_ENABLE&&argc==2&&a<=127&&b>=1&&b<=127&&!uploading&&!storage_busy&&!audio_busy&&!poly_demo)poly_issue(1);else err;
    "POFF":if(POLY_ENABLE&&argc==1&&a<=127)poly_issue(2);else err;
    "PMUTE":if(POLY_ENABLE&&argc==1&&a<32)poly_issue(4);else err;
    "PTUNE":if(POLY_ENABLE&&argc==2&&a<32&&b>=1&&b<512)poly_issue(5);else err;
    "TINFO":if(argc_zero && selected_timbre<=2)tone_reply;else err;
    "TONE":if(argc==1 && a<=2 && all_idle && !uploading && !storage_busy && !audio_busy)begin
     timbre_id<=a[1:0];timbre_request<=1;wait_cycles<=0;work<=9;
    end else err;
    "GINFO":if(RHYTHM_ENABLE && argc_zero)begin game_snapshot<=rhythm_status;game_crc<=16'hffff;game_byte<=0;work<=7;end else err;
    "GSEL":if(RHYTHM_ENABLE && argc==1 && a>=1 && a<=3 && a<=({14'd0,rhythm_status[6:5]}+16'd1) && !storage_busy && !uploading && !audio_busy && all_idle && (!MULTISONG_ENABLE || game_idle))begin
     selecting_song<=0;rhythm_enter<=1;rhythm_level<=a-1'b1;wait_cycles<=0;work<=5;
    end else err;
    "GSONG":if(MULTISONG_ENABLE && RHYTHM_ENABLE && argc==1 && a>=1 && a<=15 &&
      (a<=5 || (a<=10 && rhythm_status[6:5]>=1) || rhythm_status[6:5]>=2) && game_idle &&
      !storage_busy && !uploading && !audio_busy && all_idle)begin
      selecting_song<=1;rhythm_enter<=1;rhythm_song<=a-1'b1;wait_cycles<=0;work<=5;
     end else err;
    "GPLAY":if(RHYTHM_ENABLE && argc_zero && rhythm_enabled && !uploading && ((!storage_busy && !audio_busy) ||
      (audio_busy && (audio_status==1 || audio_status==2) && (storage_status==1 || storage_status==3))) && all_idle && (!MULTISONG_ENABLE || (game_idle && !rhythm_status[158])))begin rhythm_play<=1;ok;end else err;
    "GPAUSE":if(RHYTHM_ENABLE && argc_zero && rhythm_enabled && (rhythm_status[2:0]==1 || rhythm_status[2:0]==2 || rhythm_status[2:0]==3))begin rhythm_pause<=1;ok;end else err;
    "GEXIT":if(RHYTHM_ENABLE && argc_zero)begin rhythm_exit<=1;ok;end else err;
    "MAPGET":if(argc_zero)begin p=0;put("M");put("A");put("P");put(" ");h4({3'd0,map_rank});finish;end else err;
    "MAP":if(argc==1 && a<5040 && !storage_busy && all_idle && (guide_state==0 || guide_state==5) && !uploading)begin requested_rank<=a[12:0];map_request<=1;map_silent<=0;work<=1;end else err;
    "STATE":if(argc_zero)begin
     p=0;put("T");put(" ");h4({3'd0,score_index});put(" ");put(hex({1'b0,guide_state}));put(" ");h2({1'b0,physical_keys[6:0]});put(" ");h4(last_held);put(" ");h4(last_expected);put(" ");h4({3'd0,map_rank});put(" ");h4(bpm);put(" ");put(selected_user?"1":"0");put(" ");put(user_valid?"1":"0");finish;
    end else err;
    // Retired 1.34s RAM takes. TF ALARM/ALSTOP remain the recording interface.
    "RARM":err;
    "RSTOP":err;
    // Harmless idle reply for older clients; short capture is not advertised.
    "RINFO":if(argc_zero)begin p=0;put("R");put(" ");put("0");put(" ");h4(16'd0);put(" ");h4(16'd0);put(" ");h4(16'hffff);finish;end else err;
    "CINFO":if(argc_zero)begin p=0;put("S");put(" ");put(hex({1'b0,storage_status}));put(" ");h2({4'd0,storage_error});put(" ");h4(storage_generation[31:16]);h4(storage_generation[15:0]);put(" ");h4({2'd0,storage_count});put(" ");h4(storage_crc);put(" ");h4({3'd0,storage_rank});finish;end else err;
    "SDINFO":if(argc_zero)begin p=0;put("S");put("D");put(" ");h4(sd_diagnostic[63:48]);h4(sd_diagnostic[47:32]);h4(sd_diagnostic[31:16]);h4(sd_diagnostic[15:0]);finish;end else err;
    "SDINIT":if(argc_zero && !storage_busy && !audio_busy && !uploading && all_idle &&
       (guide_state==0 || guide_state==5) && !rhythm_enabled && !sd_diagnostic[61] && sd_diagnostic[8:4]==5'd20)begin sd_reinitialize<=1;ok;end else err;
    "CHECK":if(argc_zero)begin p=0;put("C");put(" ");h4({2'd0,current_count});put(" ");h4(current_crc);finish;end else err;
    "STORE":if((!native_score || NATIVE_STORE_ENABLE) && argc==1 && a==current_crc && user_valid && !storage_busy && (storage_status==1 || storage_status==3 || storage_status==4) && all_idle && (guide_state==0 || guide_state==5) && !uploading && storage_error!=6)begin storage_save<=1;ok;end else err;
    "RECALL":if(argc_zero && !storage_busy && all_idle && (guide_state==0 || guide_state==5) && !uploading && storage_error!=6)begin storage_recall<=1;ok;end else err;
    "ALARM":if(argc==1 && a>=1 && a<=120 && !storage_busy && rec_state!=1 && rec_state!=2 && !any_key && !uploading && (storage_status==1 || storage_status==3))begin audio_seconds<=a[6:0];audio_start<=1;ok;end else err;
    "ALSTOP":if(argc_zero)begin audio_stop<=1;ok;end else err;
    "ALINFO":if(argc_zero)begin
     p=0;put("A");put(" ");put(hex((audio_status==2 && rec_state==3)?4'd6:{1'b0,audio_status}));put(" ");h2({4'd0,audio_error});put(" ");h4(audio_generation[31:16]);h4(audio_generation[15:0]);put(" ");
     if(audio_status==2 || audio_status==6)begin h4(produced[31:16]);h4(produced[15:0]);end
     else if(audio_status==1 || audio_status==5)begin h4(0);h4(0);end
     else begin h4(audio_samples[31:16]);h4(audio_samples[15:0]);end
     put(" ");h4(audio_crc);finish;
    end else err;
    "ALPAGE":if(argc==2 && !audio_busy && audio_samples!=0 && long_offset<audio_samples && b[7:0]==0)begin
     fast_frame<=1;fast_phase<=0;fast_ready<=0;fast_last<=0;fast_fill<=0;fast_bits<=0;fast_byte<=0;fast_group_index<=0;
     fast_length<=long_remaining>=256?9'd256:long_remaining[8:0];
     audio_client_offset<=long_offset;audio_client_index<=0;audio_client_request<=1;work<=13;
     p=0;put("B");put(" ");h4(a);h4(b);put(" ");h4(long_remaining>=256?16'd256:long_remaining[15:0]);put(" ");
     packet_crc<=crcbyte(crcbyte(crcbyte(crcbyte(crcbyte(crcbyte(16'hffff,b[7:0]),b[15:8]),a[7:0]),a[15:8]),long_remaining>=256?8'd0:long_remaining[7:0]),long_remaining>=256?8'd1:8'd0);
    end else err;
    "ALCAP":if(argc_zero)begin p=0;put("B");put("6");put("4");finish;end else err;
    "ALGET":if(argc==2 && !audio_busy && audio_samples!=0 && long_offset<audio_samples && b[3:0]==0)begin
     metadata_packet<=0;packet_index<=0;packet_length<=long_remaining>=16?5'd16:long_remaining[4:0];
     audio_client_offset<=long_offset;audio_client_index<=b[7:0];audio_client_request<=1;work<=4;
     p=0;put("L");put(" ");h4(a);h4(b);put(" ");h2(long_remaining>=16?8'd16:long_remaining);put(" ");
     packet_crc<=crcbyte(crcbyte(crcbyte(crcbyte(crcbyte(16'hffff,b[7:0]),b[15:8]),a[7:0]),a[15:8]),long_remaining>=16?8'd16:long_remaining);
    end else err;
    "RGET":err;
   endcase
  end
 end
endmodule
