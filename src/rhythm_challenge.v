`timescale 1ns/1ps
// Three short, single-melody exercises. Scoring NEVER gates the audio path.
// Times are milliseconds after count-in, measured at debounced key-down.
module rhythm_challenge #(
 parameter integer KEY_COUNT=7, MS_CYCLES=50000, COUNT_IN_BEATS=3,MULTISONG_ENABLE=0
)(input wire clk,enabled,
 input wire [KEY_COUNT-1:0] keys,
 input wire start,pause,stop,
 input wire level_valid,input wire [1:0] level_request,
 output wire [159:0] status,
 output wire [KEY_COUNT-1:0] target_mask,feedback_mask,
 output wire feedback_valid,beat_flash,
 output wire [1:0] count_in,beat_index,
 output wire active,output wire [15:0] song_time_ms,input wire [6:0] keyboard_base,
 input wire song_valid,input wire [3:0] song_request,
 output reg [3:0] selected_song=0,input wire [35:0] catalog_word,catalog_next,
 input wire catalog_ready,output wire [5:0] catalog_index,
 output wire [15:0] music_phase,music_end,output wire range_missing);
 localparam IDLE=0,COUNT=1,RUN=2,PAUSED=3,CALC=4,DONE=5;
 reg [2:0] state=IDLE,resume_state=RUN;
 reg [1:0] level=0,unlocked=0,count=0,beat=0;
 reg [6:0] best0=0,best1=0,best2=0;
 reg [KEY_COUNT-1:0] previous=0;
 wire [KEY_COUNT-1:0] raw_rise=keys & ~previous;
 reg [KEY_COUNT-1:0] pending_keys=0;reg [15:0] pending_time=0;
 wire [KEY_COUNT-1:0] rise=MULTISONG_ENABLE && |pending_keys?pending_keys:raw_rise;
 wire data_ready=!MULTISONG_ENABLE || catalog_ready;
 reg [6:0] song_best[0:14];integer b;initial for(b=0;b<15;b=b+1)song_best[b]=0;
 wire [1:0] requested_level=song_request<5?0:song_request<10?1:2;
 wire idle_selection=state==IDLE || state==DONE;
 wire choose_song=MULTISONG_ENABLE && song_valid && song_request<15 && requested_level<=unlocked && idle_selection && keys==0;
 wire choose_level=level_valid && level_request<=unlocked && level_request<3 && (!MULTISONG_ENABLE || (idle_selection && keys==0));
 reg [15:0] ms_counter=0,elapsed_ms=0,beat_phase=0;
 wire ms_tick=ms_counter==MS_CYCLES-1;
 wire [7:0] bpm;
 wire [15:0] phase_next=beat_phase+{8'd0,bpm};
 reg [6:0] flash_ms=0;
 reg [7:0] feedback_ms=0;
 reg [5:0] cursor=0,combo=0,max_combo=0,perfect=0,good=0,wrong=0,missed=0;
 reg [7:0] extra=0;
 reg [12:0] points=0;
 reg [2:0] judgement=0;
 reg signed [8:0] deviation=0;
 reg [KEY_COUNT-1:0] feedback=0;
 reg passed=0;
 reg [15:0] round_id=0;
 wire [2:0] degree,next_degree;wire [6:0] actual_pitch,next_pitch;
 wire [5:0] events,notes;
 wire [6:0] pass_score;
 wire [15:0] due_ms,end_ms;
 assign catalog_index=cursor;assign music_phase=beat_phase;assign music_end=end_ms;
 wire [7:0] onset_units;
 wire [6:0] low_pitch,high_pitch;wire triple;wire [1:0] catalog_level;
 function [2:0] degree_of(input [6:0] pitch);begin
 if(pitch==0)degree_of=0;else case(pitch%12)
 0,1:degree_of=1;2,3:degree_of=2;4:degree_of=3;5,6:degree_of=4;
 7,8:degree_of=5;9,10:degree_of=6;default:degree_of=7;endcase end endfunction
 generate if(MULTISONG_ENABLE)begin:multi
  challenge_song_info info(selected_song,catalog_level,bpm,events,notes,end_ms,low_pitch,high_pitch,triple);
  assign degree=cursor<events?catalog_word[27:25]:3'd0;assign next_degree=cursor+1<events?catalog_next[27:25]:3'd0;
  assign actual_pitch=cursor<events?catalog_word[6:0]:7'd0;
  assign next_pitch=cursor+1<events?catalog_next[6:0]:7'd0;
  assign due_ms=({2'd0,catalog_word[20:7]}<<2)+{2'd0,catalog_word[20:7]};
  assign onset_units=0;assign pass_score=level==0?60:level==1?70:80;
 end else begin:legacy
  training_score_rom score(level,cursor,degree,next_degree,onset_units,due_ms,
     end_ms,events,notes,bpm,pass_score,,actual_pitch,next_pitch);
  assign low_pitch=60;assign high_pitch=72;assign triple=0;assign catalog_level=level;
 end endgenerate
 assign range_missing=MULTISONG_ENABLE && (low_pitch<keyboard_base || {1'b0,high_pitch}>={1'b0,keyboard_base}+KEY_COUNT);
 wire valid_target=data_ready && cursor<events && degree!=0;
 wire signed [16:0] delta=$signed({1'b0,(MULTISONG_ENABLE && |pending_keys?pending_time:elapsed_ms)})-$signed({1'b0,due_ms});
 wire signed [16:0] expiration_delta=$signed({1'b0,elapsed_ms})-$signed({1'b0,due_ms});
 // Reviewed peer difficulty: inclusive +/-150ms hit and +/-70ms Perfect.
 // Apply to actual MIDI pitch masks; keep pending-event timestamps and expiry
 // protection when the shared catalog ROM is refreshing.
 localparam signed [16:0] HIT_WINDOW_MS=17'sd150, PERFECT_WINDOW_MS=17'sd70;
 wire [6:0] effective_pass_score=pass_score-(pass_score>>2);
 wire in_window=valid_target && delta>=-HIT_WINDOW_MS && delta<=HIT_WINDOW_MS;
 function [6:0] midi(input [2:0] d);begin case(d)1:midi=60;2:midi=62;3:midi=64;4:midi=65;5:midi=67;6:midi=69;default:midi=71;endcase end endfunction
 wire [6:0] expected_index=KEY_COUNT==60?actual_pitch-keyboard_base:{4'd0,degree}-1'b1;
 wire [KEY_COUNT-1:0] expected=valid_target?({{(KEY_COUNT-1){1'b0}},1'b1}<<expected_index):{KEY_COUNT{1'b0}};
 wire [6:0] packed_target=valid_target?(7'b1<<(degree-1'b1)):7'd0;
 reg [6:0] packed_feedback;
 integer summary;always @(*)begin packed_feedback=0;
  for(summary=0;summary<7;summary=summary+1)packed_feedback[summary]=KEY_COUNT==60?
    ((midi(summary+1)>=keyboard_base && {1'b0,midi(summary+1)}<{1'b0,keyboard_base}+8'd60)?feedback[midi(summary+1)-keyboard_base]:1'b0):feedback[summary];
 end
 // Judge the new key-down group. A previous note can still be held (or in
 // release debounce) while the next begins; hold duration is not graded.
 wire correct=rise==expected;
 assign song_time_ms=elapsed_ms;
 assign active=enabled && (state==COUNT || state==RUN || state==PAUSED || state==CALC);
 assign target_mask=enabled && state==RUN && valid_target?expected:7'd0;
 assign feedback_mask=feedback;
 assign feedback_valid=enabled && feedback_ms!=0;
 assign beat_flash=enabled && (state==COUNT || state==RUN) && flash_ms!=0;
 assign count_in=count;
 assign beat_index=beat;

 // Sequential, bounded division: <=100 subtractions, outside the audio path.
 // Refresh the displayed score after a judgement, and wait for its last update
 // before publishing results. Extra presses are capped, so they cannot wrap.
 reg [12:0] score_points=0;
 reg [7:0] score_extra=0;
 reg [6:0] score_value=0,quotient=0;
 reg [12:0] remainder=0;
 reg score_busy=0;
 wire [12:0] penalty={1'b0,extra,4'b0}+{3'b0,extra,2'b0};
 wire score_settled=!score_busy && score_points==points && score_extra==extra;
 always @(posedge clk) begin
  if(!enabled || stop || start || (choose_level || choose_song)) begin
   score_points<=0;score_extra<=0;score_value<=0;score_busy<=0;quotient<=0;remainder<=0;
  end else if(!score_busy) begin
   if(!score_settled) begin
    score_points<=points;score_extra<=extra;quotient<=0;
    remainder<=points>penalty?points-penalty:13'd0;score_busy<=1;
   end
  end else if(remainder>={7'd0,notes} && quotient<100) begin
   remainder<=remainder-{7'd0,notes};quotient<=quotient+1'b1;
  end else begin score_value<=quotient;score_busy<=0;end
 end
 always @(posedge clk) begin
  previous<=keys;
  if(MULTISONG_ENABLE)begin
   if(!enabled || stop || start || choose_song || choose_level || state!=RUN || data_ready)pending_keys<=0;
   else if(|raw_rise && pending_keys==0)begin pending_keys<=raw_rise;pending_time<=elapsed_ms;end
  end
  if(state==COUNT || state==RUN) begin
   if(ms_tick) ms_counter<=0;else ms_counter<=ms_counter+1'b1;
  end
  if(!enabled || stop) begin
   state<=IDLE;count<=0;flash_ms<=0;feedback_ms<=0;beat_phase<=0;ms_counter<=0;
   cursor<=0;elapsed_ms<=0;beat<=0;points<=0;extra<=0;perfect<=0;good<=0;
   wrong<=0;missed<=0;combo<=0;max_combo<=0;judgement<=0;deviation<=0;passed<=0;
  end else if(choose_level || choose_song) begin
   level<=choose_song?requested_level:level_request;
   if(MULTISONG_ENABLE)selected_song<=choose_song?song_request:(level_request==0?4'd0:level_request==1?4'd5:4'd10);state<=IDLE;count<=0;elapsed_ms<=0;cursor<=0;
   points<=0;extra<=0;perfect<=0;good<=0;wrong<=0;missed<=0;
   combo<=0;max_combo<=0;judgement<=0;passed<=0;feedback_ms<=0;flash_ms<=0;
  end else if(start && (!MULTISONG_ENABLE || (idle_selection && !range_missing && keys==0))) begin
   round_id<=round_id+1'b1;
   state<=COUNT_IN_BEATS==0?RUN:COUNT;count<=COUNT_IN_BEATS;
   ms_counter<=0;elapsed_ms<=0;beat_phase<=0;beat<=0;flash_ms<=80;
   cursor<=0;points<=0;extra<=0;perfect<=0;good<=0;wrong<=0;missed<=0;
   combo<=0;max_combo<=0;judgement<=0;deviation<=0;passed<=0;feedback_ms<=0;
  end else if(pause && (state==COUNT || state==RUN || state==PAUSED)) begin
   if(state==PAUSED) state<=resume_state;
   else begin resume_state<=state;state<=PAUSED;end
   flash_ms<=0;
  end else begin
   if((state==COUNT || state==RUN) && ms_tick) begin
    if(flash_ms!=0) flash_ms<=flash_ms-1'b1;
    if(feedback_ms!=0) feedback_ms<=feedback_ms-1'b1;
    if(phase_next>=60000) begin
     beat_phase<=phase_next-16'd60000;flash_ms<=80;
     if(state==COUNT) begin
      count<=count-1'b1;beat<=0;
      if(count==1) begin state<=RUN;elapsed_ms<=0;if(MULTISONG_ENABLE)beat_phase<=0;end
     end else if(triple && beat==2)beat<=0;else beat<=beat+1'b1;
    end else beat_phase<=phase_next;
    if(state==RUN) elapsed_ms<=elapsed_ms+1'b1;
   end
   if(state==RUN) begin
    // Rests are never scoring targets. Skip immediately, allowing the next
    // note's early window to take precedence over the end of a rest.
    if(data_ready && cursor<events && degree==0) cursor<=cursor+1'b1;
    if(data_ready && |rise) begin
     feedback<=keys;feedback_ms<=160;
     if(in_window) begin
      cursor<=cursor+1'b1;deviation<=delta[8:0];
      if(correct) begin
       combo<=combo+1'b1;
       if(combo>=max_combo) max_combo<=combo+1'b1;
       if(delta>=-PERFECT_WINDOW_MS && delta<=PERFECT_WINDOW_MS) begin
        perfect<=perfect+1'b1;points<=points+13'd100;judgement<=1;
       end else begin
        good<=good+1'b1;points<=points+13'd60;judgement<=delta<0?2:3;
       end
      end else begin wrong<=wrong+1'b1;combo<=0;judgement<=4;end
     end else begin
      if(extra!=255) extra<=extra+1'b1;
      combo<=0;judgement<=6;deviation<=0;
     end
    end
    // Expire a target even if an unrelated extra key arrived this cycle.
    if(valid_target && expiration_delta>HIT_WINDOW_MS && !(|rise && in_window)) begin
     cursor<=cursor+1'b1;missed<=missed+1'b1;combo<=0;
     judgement<=5;deviation<=9'sd151;feedback<=expected;feedback_ms<=160;
    end
    if(elapsed_ms>=end_ms && cursor>=events) begin state<=CALC;flash_ms<=0;end
   end
   if(state==CALC && score_settled) begin
    state<=DONE;passed<=score_value>=effective_pass_score;
    if(score_value>=effective_pass_score && level==unlocked && unlocked<2) unlocked<=unlocked+1'b1;
    if(MULTISONG_ENABLE)begin if(score_value>song_best[selected_song])song_best[selected_song]<=score_value;end
    else case(level)
     0:if(score_value>best0) best0<=score_value;
     1:if(score_value>best1) best1<=score_value;
     2:if(score_value>best2) best2<=score_value;
    endcase
   end
  end
 end
 // Packed display snapshot. Field positions are stable and documented in
 // sim/rhythm_status.md. No framebuffer or event-history memory is needed.
 wire [5:0] pack_tag=MULTISONG_ENABLE?{1'b1,range_missing,selected_song}:6'd1;
 assign status={pack_tag,enabled,round_id,beat,feedback_valid,packed_feedback,(enabled && state==RUN?packed_target:7'd0),notes,passed,
    (MULTISONG_ENABLE?song_best[selected_song]:(level==0?best0:level==1?best1:best2)),beat_phase[15:8],deviation,judgement,
    extra,missed,wrong,good,perfect,max_combo,combo,score_value,next_degree,
    degree,events,cursor,bpm,count,unlocked,level,state};
endmodule
