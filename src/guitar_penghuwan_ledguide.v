`timescale 1ns / 1ps

// Five mixed5(3 white+2 black) / mixed7(4 white+3 black) groups; 80 key scan bits.
// Default wire order and LED order are documented in docs/60键适配与接线.md.
module guitar_penghuwan_ledguide #(
    parameter integer LCD_ENABLE=1,
    parameter integer PRACTICE_METRONOME_ENABLE=1,
    parameter integer PRACTICE_COUNT_IN_BEATS=3,
    parameter integer RHYTHM_MS_CYCLES=50000,
    parameter integer ADC_PANEL_ENABLE=1,
    parameter integer KEYBOARD_BLACK_FIRST=1,
    parameter integer KEYBOARD_MIXED_5_7=1
)(
    input wire sys_clk,
    input wire key_data,
    input wire key0_n,
    output wire key_load_n,
    output wire key_clk,
    output wire led_data,
    output wire hp_bck,
    output wire hp_ws,
    output wire hp_din,
    output wire pa_en,
    output wire [7:0] lcd_r,lcd_g,lcd_b,
    output wire lcd_pclk,lcd_hs,lcd_vs,lcd_de,lcd_bk,touch_rst_n,
    inout wire touch_sda,touch_scl,touch_int,
    input wire bt_rx,
    output wire bt_tx,
    output wire i2s_bclk,
    output wire i2s_lrclk,
    output wire i2s_dout,
    output wire i2s_xsmt,
    input wire sd_miso,inout wire sd_clk,sd_cs,sd_mosi,
    inout wire panel_sda,panel_scl
);
    wire [2:0] guide_state;wire uploading,storage_busy;reg challenge_mode=0;
    // Eleven HC165s: ten key boards (80 bits) plus the control board (8 bits).
    wire [59:0] physical_pressed,legacy_pressed;wire [7:0] panel_controls;wire key_scan_valid;
    keyboard60_scan #(.SCAN_BITS(ADC_PANEL_ENABLE?80:88),.BLACK_FIRST(KEYBOARD_MIXED_5_7?1:KEYBOARD_BLACK_FIRST),.MIXED_5_7(0)) u_keys(sys_clk,key_data,key_load_n,key_clk,legacy_pressed,panel_controls,key_scan_valid);
    // Static wire permutation: preserve the existing scan/LED internal layout.
    // Mixed physical slot0..11 becomes canonical semitone0..11, without a mux.
    function integer legacy_slot(input integer k);
      integer pc,j;begin pc=k%12;
       if(KEYBOARD_MIXED_5_7 || KEYBOARD_BLACK_FIRST)case(pc)
        0:j=1;1:j=3;2:j=6;3:j=8;4:j=10;5:j=0;
        6:j=2;7:j=4;8:j=5;9:j=7;10:j=9;default:j=11;
       endcase
       else case(pc)
        0:j=0;1:j=2;2:j=4;3:j=5;4:j=7;5:j=9;
        6:j=11;7:j=1;8:j=3;9:j=6;10:j=8;default:j=10;
       endcase
       legacy_slot=k/12*12+j;
      end
    endfunction
    genvar wire_key;
    generate for(wire_key=0;wire_key<60;wire_key=wire_key+1)begin:mixed_scan_wires
      assign physical_pressed[wire_key]=KEYBOARD_MIXED_5_7?legacy_pressed[legacy_slot(wire_key)]:legacy_pressed[wire_key];
    end endgenerate
    wire [2:0] keyboard_octave;wire [6:0] keyboard_base;
    wire panel_start,panel_stop,panel_pause,panel_timbre,octave_request;
    wire [2:0] octave_value;
    wire [159:0] rhythm_status;
    wire adc_valid,adc_online;wire [95:0] adc_samples;wire [3:0] adc_error;
    wire adc_octave_valid,adc_timbre_valid,adc_start,adc_stop,adc_pause,pedal_sustain;
    wire [2:0] adc_octave;wire [1:0] adc_timbre,adc_edit;wire [11:0] adc_values;wire [5:0] adc_bend;
    wire transpose_safe=physical_pressed==0 && !uploading && !storage_busy && !challenge_mode && (guide_state==0 || guide_state==5);
    generate if(ADC_PANEL_ENABLE)begin:control_adc
      ads7828_panel adc(sys_clk,panel_sda,panel_scl,adc_valid,adc_online,adc_samples,adc_error);
      control_panel_map map(sys_clk,adc_valid,adc_online,adc_samples,transpose_safe,
        challenge_mode ? (rhythm_status[2:0]!=0 && rhythm_status[2:0]!=5) : (guide_state!=0 && guide_state!=5),
        adc_octave_valid,adc_octave,adc_timbre_valid,adc_timbre,adc_start,adc_stop,adc_pause,adc_edit,adc_values,pedal_sustain,adc_bend);
    end else begin:no_control_adc
      assign panel_sda=1'bz;assign panel_scl=1'bz;
      assign adc_valid=0;assign adc_online=0;assign adc_samples=0;assign adc_error=0;
      assign adc_octave_valid=0;assign adc_octave=2;assign adc_timbre_valid=0;assign adc_timbre=0;
      assign {adc_start,adc_stop,adc_pause,pedal_sustain}=0;assign adc_edit=0;assign adc_values=0;assign adc_bend=0;
    end endgenerate
    wire [59:0] mapped_keys;wire [59:0] full_note_gate,full_target,full_wrong;
    reg [59:0] synth_keys=0;
    always @(posedge sys_clk)synth_keys<=full_note_gate;
    // Compatibility telemetry keeps a seven-degree projection; sound/judgement
    // and all busy/recording guards below use the complete 60-key vector.
    wire [9:0] pressed;wire [6:0] screen_gate;
    wire [20:0] key_mapping;
    function integer mapped_key(input integer key_id);
      integer oct,pc,degree,new_pc;begin oct=key_id/12;pc=key_id%12;degree=-1;
       case(pc)0:degree=0;2:degree=1;4:degree=2;5:degree=3;7:degree=4;9:degree=5;11:degree=6;endcase
       new_pc=pc;
       if(degree>=0)case(key_mapping[degree*3+:3])
         0:new_pc=0;1:new_pc=2;2:new_pc=4;3:new_pc=5;4:new_pc=7;5:new_pc=9;default:new_pc=11;
       endcase
       mapped_key=oct*12+new_pc;
      end
    endfunction
    genvar key_number;
    generate for(key_number=0;key_number<60;key_number=key_number+1)begin:keymap60
      // Bijective permutation of seven white keys in every octave; black keys
      // retain their semitone pitches. Same permutation is stored in TF.
      assign mapped_keys[key_number]=physical_pressed[(key_number/12)*12 + inverse_pc(key_number%12)];
    end endgenerate
    function integer inverse_pc(input integer pc);
      integer j,degree;begin inverse_pc=pc;degree=-1;
       case(pc)0:degree=0;2:degree=1;4:degree=2;5:degree=3;7:degree=4;9:degree=5;11:degree=6;endcase
       if(degree>=0)for(j=0;j<7;j=j+1)if(key_mapping[j*3+:3]==degree)
         case(j)0:inverse_pc=0;1:inverse_pc=2;2:inverse_pc=4;3:inverse_pc=5;4:inverse_pc=7;5:inverse_pc=9;6:inverse_pc=11;endcase
      end
    endfunction
    assign pressed={3'b000,6'b000000,(|physical_pressed)};
    keyboard60_controls u_controls(sys_clk,key_scan_valid,panel_controls,
      transpose_safe,
      octave_request || adc_octave_valid,octave_request?octave_value:adc_octave,keyboard_octave,keyboard_base,panel_start,panel_stop,panel_pause,panel_timbre);
    function [6:0] degree_pitch(input [2:0] degree);
      begin case(degree)1:degree_pitch=60;2:degree_pitch=62;3:degree_pitch=64;4:degree_pitch=65;
       5:degree_pitch=67;6:degree_pitch=69;default:degree_pitch=71;endcase end
    endfunction
    function [6:0] key_for_degree(input [2:0] degree);
      begin key_for_degree=degree==0?0:degree_pitch(degree)-keyboard_base+1'b1;end
    endfunction
    genvar d;generate for(d=0;d<7;d=d+1)begin:screen_projection
      wire [6:0] note=degree_pitch(d+1);
      assign screen_gate[d]=note>=keyboard_base && note<keyboard_base+60 ? full_note_gate[note-keyboard_base] : 1'b0;
    end endgenerate
    wire audio_sample_tick;
    reg signed [15:0] audio_pcm=16'sd0;
    wire [6:0] note_gate,target_mask,wrong_mask;
    wire [2:0] score_degree;
    wire [12:0] score_index;
    wire score_last;
    wire led_frame_latched;
    wire led_frame_valid;
    wire [12:0] led_frame_index;
    wire [2:0] rom_degree,user_degree;
    wire user_native,user_missing,remote_skip,ui_skip;wire [7:0] user_pitch;
    wire native_ready,native_skip_allowed;
    wire rom_last,user_last,user_score_ready;
    wire [15:0] user_rest_ms;
    wire selected_user,user_valid,bt_activity,score_bank;
    wire [3:0] upload_error;
    wire [15:0] received_bcd,total_bcd,stored_bcd;
    wire [11:0] score_bpm_bcd;
    wire remote_start,remote_pause,remote_stop,source_changed;
    wire [23:0] performance_settings;
    wire [31:0] performance_step;wire [5:0] performance_read_key;
    wire [15:0] performance_level;wire [5:0] performance_space;wire [1:0] pressure_mode;wire [5:0] pressure_depth;
    wire [59:0] bend_target;
    wire [1:0] ui_source;
    wire ui_start,ui_pause,ui_stop;
    reg [9:0] mapped_pressed;
    wire rhythm_enter,rhythm_ui_start,rhythm_ui_pause,rhythm_ui_exit,rhythm_level_valid;
    wire rhythm_link_enter,rhythm_link_play,rhythm_link_pause,rhythm_link_exit,rhythm_link_level_valid;
    wire [1:0] rhythm_link_level;
    wire rhythm_link_song_valid,rhythm_ui_song_valid;wire [3:0] rhythm_link_song,rhythm_ui_song,selected_song;
    wire [5:0] judge_index,music_index,preview_page;wire [3:0] preview_song;
    wire [35:0] judge_word,judge_next,music_word,music_next;wire judge_ready,music_ready,preview_ready,challenge_range_missing;
    wire [127:0] challenge_preview;wire [15:0] music_phase,music_end;
    challenge_catalog_store u_catalog(sys_clk,selected_song,judge_index,music_index,preview_song,preview_page,
      judge_word,judge_next,music_word,music_next,judge_ready,music_ready,challenge_preview,preview_ready);
    wire [1:0] selected_timbre,timbre_id;
    wire signed [31:0] visual_pcm;wire [31:0] visual_step;
    wire [12:0] visual_tag;wire visual_active;
    wire timbre_request;
    wire poly_ready,poly_done,poly_ok,poly_demo,poly_deadline,poly_valid,poly_frame_done;
    wire [5:0] poly_active,poly_held;wire [31:0] poly_active_mask,poly_held_mask;
    wire [2:0] poly_op;wire [15:0] poly_a,poly_b;
    wire signed [17:0] poly_mixed_pcm;wire [1023:0] poly_voice_samples;
    wire [1:0] rhythm_level_request;
    reg [2:0] previous_controls=0;
    wire [2:0] control_rise=mapped_pressed[9:7]&~previous_controls;
    wire rhythm_exit=control_rise[2] || rhythm_ui_exit || rhythm_link_exit || source_changed || remote_start || remote_stop;
    always @(posedge sys_clk) begin
        previous_controls<=mapped_pressed[9:7];
        if(rhythm_exit) challenge_mode<=0;
        else if(rhythm_enter || rhythm_link_enter) challenge_mode<=1;
    end
    wire [15:0] song_time_ms;
    wire [3:0] song_gates,song_epochs;wire [27:0] song_notes;
    wire [59:0] rhythm_target,rhythm_feedback;
    wire rhythm_feedback_valid,rhythm_flash,rhythm_active;
    wire [1:0] rhythm_count,rhythm_beat;
    rhythm_challenge #(.MS_CYCLES(RHYTHM_MS_CYCLES),.COUNT_IN_BEATS(PRACTICE_COUNT_IN_BEATS),.KEY_COUNT(60),.MULTISONG_ENABLE(1))
      u_rhythm(sys_clk,challenge_mode,mapped_keys,
        control_rise[0] || rhythm_ui_start || rhythm_link_play,control_rise[1] || rhythm_ui_pause || rhythm_link_pause,rhythm_exit,
        rhythm_level_valid || rhythm_link_level_valid,rhythm_link_level_valid?rhythm_link_level:rhythm_level_request,rhythm_status,rhythm_target,rhythm_feedback,
        rhythm_feedback_valid,rhythm_flash,rhythm_count,rhythm_beat,rhythm_active,song_time_ms,keyboard_base,
        rhythm_link_song_valid||rhythm_ui_song_valid,rhythm_link_song_valid?rhythm_link_song:rhythm_ui_song,
        selected_song,judge_word,judge_next,judge_ready,judge_index,music_phase,music_end,challenge_range_missing);
    // Challenge is a keyboard-playing exercise: no automatic guide melody,
    // chord backing, or beat accompaniment is sent to the voice pool.
    // The judge/catalog/LCD keep their original timeline and preview interface.
    assign music_index=6'd0;
    assign song_gates=4'd0;
    assign song_notes=28'd0;
    assign song_epochs=4'd0;
    wire [59:0] practice_note_gate,practice_target,practice_wrong;
    wire [2:0] practice_state;
    // Actual keys always reach the synth in challenge mode, including wrong
    // notes and chords. The judge has no back-pressure or audio-enable signal.
    assign full_note_gate=challenge_mode?mapped_keys:practice_note_gate;
    assign note_gate=screen_gate;
    assign full_target=challenge_mode?rhythm_target:practice_target;
    assign target_mask=0;
    assign full_wrong=challenge_mode?60'd0:practice_wrong;
    assign wrong_mask=0;
    assign guide_state=challenge_mode?(rhythm_status[2:0]==3?3'd6:
        rhythm_status[2:0]==5?3'd5:rhythm_active?3'd1:3'd0):practice_state;
    wire [7:0] bt_rx_data,bt_tx_data,reply_info;
    wire bt_rx_valid,bt_rx_error,bt_tx_start,bt_tx_busy,reply_valid,reply_ready;
    wire [3:0] reply_code;
    bluetooth_uart #(.BAUD(38400)) u_bt_uart(sys_clk,bt_rx,bt_rx_data,bt_rx_valid,bt_rx_error,
        bt_tx_data,bt_tx_start,bt_tx,bt_tx_busy);
    wire [7:0] legacy_tx_data,studio_tx_data;
    wire legacy_tx_start,legacy_idle,studio_active,studio_pending,studio_tx_start;
    wire configuration_busy;wire [12:0] configured_rank;
    wire sd_reinitialize;wire [63:0] sd_diagnostic,sd_driver_diagnostic;
    wire sd_clk_drive,sd_cs_drive,sd_mosi_drive;wire [31:0] sd_pad_snapshot;
    sd_pin_trace u_sd_pads(sys_clk,sd_reinitialize,
        !sd_driver_diagnostic[61] && sd_driver_diagnostic[8:4]!=5'd20,
        sd_driver_diagnostic[8:4]==5'd3,
        sd_clk_drive,sd_cs_drive,sd_mosi_drive,sd_miso,
        sd_clk,sd_cs,sd_mosi,sd_pad_snapshot);
    // Before CMD0 succeeds there is no OCR/R7 value. Reuse only its empty
    // extra field for output-pad evidence; preserve SDINFO's other bits.
    assign sd_diagnostic=(!sd_driver_diagnostic[61] && sd_driver_diagnostic[18:13]==0) ?
        {sd_driver_diagnostic[63:59],sd_pad_snapshot,sd_driver_diagnostic[26:0]} : sd_driver_diagnostic;
    always @(*)begin
      mapped_pressed={{panel_stop|adc_stop,panel_pause|adc_pause,panel_start|adc_start}&{3{!configuration_busy}},screen_gate};
    end
    wire studio_owns=studio_active || studio_tx_start;
    assign bt_tx_data=studio_owns?studio_tx_data:legacy_tx_data;
    assign bt_tx_start=studio_owns?studio_tx_start:legacy_tx_start;
    bluetooth_reply_studio u_bt_reply(sys_clk,reply_valid,reply_code,reply_info,reply_ready,
        legacy_tx_data,legacy_tx_start,bt_tx_busy || studio_active || studio_tx_start,legacy_idle);
    wire [15:0] tempo_numeric;
    wire storage_save,storage_recall,export_mode,restore_begin,restore_write,restore_commit,restore_native;
    wire [2:0] storage_status;wire [3:0] storage_error;
    wire [31:0] storage_generation;wire [13:0] storage_count,current_count,restore_count;
    wire [15:0] storage_crc,current_crc,current_bpm,restore_bpm,restore_crc;
    assign tempo_numeric=current_bpm;
    wire [12:0] storage_rank,export_address,restore_address,restore_rank;
    wire [23:0] export_data,restore_data;
    wire audio_store_busy,audio_store_start,audio_store_stop,capture_long_arm,capture_long_stop,capture_long_abort;
    wire [2:0] audio_store_status,capture_state;wire [3:0] audio_store_error,audio_client_error;
    wire [31:0] audio_generation,audio_samples,capture_limit,capture_consumed,capture_produced,audio_client_offset;
    wire [15:0] audio_store_crc,capture_crc,capture_address,capture_data,audio_client_data;
    wire capture_overflow,audio_client_request,audio_client_ready;wire [7:0] audio_client_index;wire [6:0] audio_seconds;
    wire record_request,record_done,capture_immediate;wire [3:0] record_operation,record_error;
    wire [47:0] record_arguments;wire [95:0] record_info;wire [15:0] record_word;
    studio_storage u_storage(sys_clk,sd_miso,sd_clk_drive,sd_cs_drive,sd_mosi_drive,
        storage_save,storage_recall,physical_pressed==0 && (guide_state==0 || guide_state==5) && !uploading,user_valid,current_count,current_bpm,current_crc,
        configured_rank,storage_busy,storage_status,storage_error,storage_generation,storage_count,storage_crc,storage_rank,
        export_mode,export_address,export_data,restore_begin,restore_write,restore_commit,restore_address,
        restore_data,restore_count,restore_bpm,restore_crc,restore_rank,
        configuration_busy,audio_store_start,audio_store_stop,audio_seconds,audio_store_busy,audio_store_status,audio_store_error,
        audio_generation,audio_samples,audio_store_crc,capture_long_arm,capture_long_stop,capture_long_abort,capture_limit,capture_consumed,
        capture_state,capture_produced,capture_crc,capture_overflow,capture_address,capture_data,
        audio_client_request,audio_client_offset,audio_client_index,audio_client_ready,audio_client_error,audio_client_data,sd_reinitialize,sd_driver_diagnostic,user_native,restore_native,record_request,record_operation,record_arguments,record_done,record_error,record_info,record_word,capture_immediate);
    studio_link #(.RHYTHM_ENABLE(1),.POLY_ENABLE(1),.PITCH_ENABLE(1),.NATIVE_STORE_ENABLE(1),.KEYBOARD60_ENABLE(1),.MULTISONG_ENABLE(1),.RECORD_ENABLE(1)) u_studio(sys_clk,bt_rx_data,bt_rx_valid,bt_rx_error,
        legacy_idle,bt_tx_busy,studio_active,studio_pending,studio_tx_data,studio_tx_start,
        pressed,guide_state,score_index,user_rest_ms,tempo_numeric,selected_user,user_valid,uploading,
        audio_sample_tick,audio_pcm,key_mapping,
        storage_busy,storage_status,storage_error,storage_generation,storage_count,storage_crc,storage_rank,current_count,current_crc,
        storage_save,storage_recall,restore_commit,restore_rank,configured_rank,
        audio_store_busy,audio_store_status,audio_store_error,audio_generation,audio_samples,audio_store_crc,
        audio_store_start,audio_store_stop,audio_seconds,capture_long_arm,capture_long_stop,capture_long_abort,capture_limit,capture_consumed,
        capture_state,capture_produced,capture_crc,capture_overflow,capture_address,capture_data,
        audio_client_request,audio_client_offset,audio_client_index,audio_client_ready,audio_client_error,audio_client_data,
        rhythm_status,challenge_mode,rhythm_link_enter,rhythm_link_play,rhythm_link_pause,rhythm_link_exit,
        rhythm_link_level_valid,rhythm_link_level,sd_diagnostic,sd_reinitialize,
        selected_timbre,timbre_request,timbre_id,
        poly_ready,poly_done,poly_ok,poly_demo,poly_deadline,poly_active,poly_held,poly_active_mask,poly_held_mask,
        poly_valid,poly_op,poly_a,poly_b,user_native,user_pitch,native_ready,user_missing,physical_pressed,keyboard_base,octave_request,octave_value,rhythm_link_song_valid,rhythm_link_song,record_request,record_operation,record_arguments,record_done,record_error,record_info,record_word,capture_immediate);
    bluetooth_score_studio #(.KEY_COUNT(60)) u_bt_score(sys_clk,bt_rx_data,bt_rx_valid,bt_rx_error,
        reply_ready,reply_valid,reply_code,reply_info,ui_source,ui_start,ui_pause,ui_stop,
        selected_user,user_valid,uploading,upload_error,bt_activity,
        received_bcd,total_bcd,stored_bcd,score_bpm_bcd,score_index,user_degree,
        user_rest_ms,user_score_ready,user_last,remote_start,remote_pause,remote_stop,
        source_changed,score_bank,
        configuration_busy,export_mode,export_address,export_data,current_count,current_bpm,current_crc,
        restore_begin,restore_write,restore_commit,restore_address,restore_data,restore_count,restore_bpm,restore_crc,user_native,user_pitch,user_missing,native_skip_allowed,remote_skip,restore_native,keyboard_base);
    penghuwan_score_rom u_score(score_index[8:0],rom_degree,rom_last);
    assign score_degree=selected_user?user_degree:rom_degree;
    assign score_last=selected_user?user_last:rom_last;
    wire [1:0] led_frame_source;
    wire matching_led_source=led_frame_source=={selected_user,score_bank};
    wire [1:0] practice_count_in,practice_beat;
    wire practice_flash,practice_clock_active;
    wire [15:0] practice_bpm=selected_user?current_bpm:16'd120;
    assign native_ready=user_score_ready && score_index<current_count;
    assign native_skip_allowed=selected_user && user_native && user_missing && native_ready && !challenge_mode &&
        (practice_state==1 || practice_state==2) && practice_count_in==0 && physical_pressed==0;
    wire [7:0] raw_practice_key=selected_user&&user_native?
      (user_missing||user_pitch==0?8'd0:user_pitch-{1'b0,keyboard_base}):{1'b0,key_for_degree(score_degree)};
    reg [6:0] prepared_key=0;reg prepared_ready=0;
    reg [12:0] prepared_index=0;reg [1:0] prepared_source=0;
    always @(posedge sys_clk)begin
      prepared_key<=raw_practice_key[6:0];prepared_ready<=!selected_user||user_score_ready;
      prepared_index<=score_index;prepared_source<={selected_user,score_bank};
    end
    wire practice_data_ready=prepared_ready && prepared_index==score_index && prepared_source=={selected_user,score_bank} &&
                             (!selected_user || user_score_ready);
    led_practice_control #(.EXTERNAL_CONTROL(1),.METRONOME_ENABLE(PRACTICE_METRONOME_ENABLE),
        .COUNT_IN_BEATS(PRACTICE_COUNT_IN_BEATS),.KEY_COUNT(60),.SCORE_BITS(7)) u_guide(sys_clk,{mapped_pressed[9:7]&{3{!challenge_mode}},mapped_keys},
        prepared_key,score_last,
        led_frame_latched,led_frame_valid && matching_led_source,led_frame_index,
        score_index,practice_note_gate,practice_target,practice_wrong,practice_state,
        remote_start && !challenge_mode,remote_pause && !challenge_mode,remote_stop,source_changed || rhythm_enter || rhythm_link_enter,
        practice_data_ready,selected_user,user_rest_ms,
        practice_bpm,practice_count_in,practice_beat,practice_flash,practice_clock_active,
        selected_user && user_missing,(remote_skip || (ui_skip && native_skip_allowed)) && !challenge_mode);
    // Fixed seven notes; the supplied score's octave dots are folded by request.
    wire [223:0] phase_steps={32'd43442435,32'd38702809,32'd34480283,
        32'd30718441,32'd28994347,32'd25831027,32'd23012829};
    wire selected_piano;
    wire ui_timbre_valid;wire [1:0] ui_timbre_request;
    wire [6:0] piano_gate,guitar_gate,accordion_gate;
    wire signed [15:0] piano_pcm,guitar_pcm,accordion_pcm;
    wire [74:0] piano_adsr,guitar_adsr,accordion_adsr;
    timbre_select u_timbre(sys_clk,key0_n,note_gate,selected_piano,piano_gate,guitar_gate,
        selected_timbre,accordion_gate,timbre_request || ui_timbre_valid || panel_timbre || adc_timbre_valid,
        timbre_request?timbre_id:panel_timbre?(selected_timbre==2?2'd0:selected_timbre+1'b1):adc_timbre_valid?adc_timbre:ui_timbre_request);
    generate if(LCD_ENABLE) begin: screen
        lcd_adsr_panel #(.RHYTHM_ENABLE(1),.MULTISONG_ENABLE(1)) u_panel(sys_clk,audio_sample_tick,selected_timbre,note_gate,
            piano_adsr,guitar_adsr,accordion_adsr,lcd_r,lcd_g,lcd_b,lcd_pclk,lcd_hs,lcd_vs,
            lcd_de,lcd_bk,touch_rst_n,touch_sda,touch_scl,touch_int,audio_pcm,
            selected_user,user_valid,uploading,bt_activity,upload_error,
            received_bcd,total_bcd,stored_bcd,score_bpm_bcd,guide_state,
            ui_source,ui_start,ui_pause,ui_stop,performance_settings,
            challenge_mode,rhythm_status,rhythm_enter,rhythm_ui_start,rhythm_ui_pause,rhythm_ui_exit,
            rhythm_level_valid,rhythm_level_request,ui_timbre_valid,ui_timbre_request,native_skip_allowed,ui_skip,visual_pcm,visual_step,visual_tag,visual_active,full_note_gate,full_target,keyboard_base,
            challenge_preview,preview_ready,preview_song,preview_page,rhythm_ui_song_valid,rhythm_ui_song,adc_edit,adc_values,adc_bend,pressure_mode,pressure_depth);
    end else begin: no_screen
        assign piano_adsr={18'd171197,18'd311,24'd5452544,15'd1838};
        assign guitar_adsr={18'd171197,18'd801,24'd3774976,15'd2083};
        assign accordion_adsr={18'd11445,18'd223,24'd7465984,15'd3694};
        assign {lcd_r,lcd_g,lcd_b}=24'd0;
        assign {lcd_pclk,lcd_hs,lcd_vs,lcd_de,lcd_bk}=5'd0;
        assign touch_rst_n=1'b1;
        assign touch_sda=1'bz;assign touch_scl=1'bz;assign touch_int=1'bz;
        reg [23:0] headless_settings={6'd63,6'd32,6'd0,6'd0};
        always @(posedge sys_clk)begin
          if(adc_edit[0])headless_settings[23:18]<=adc_values[11:6];
          if(adc_edit[1])headless_settings[11:6]<=adc_values[5:0];
        end
        assign performance_settings=headless_settings;assign pressure_mode=1;assign pressure_depth=0;
        assign ui_source=0;assign {ui_start,ui_pause,ui_stop}=0;
        assign ui_skip=0;
        assign {rhythm_enter,rhythm_ui_start,rhythm_ui_pause,rhythm_ui_exit,rhythm_level_valid}=0;
        assign rhythm_level_request=0;assign rhythm_ui_song_valid=0;assign rhythm_ui_song=0;assign preview_song=0;assign preview_page=0;
        assign ui_timbre_valid=0;assign ui_timbre_request=0;
    end endgenerate
    // Pressure2 is FX-only. Screen single-note pitch remains independent.
    wire [23:0] effective_performance=performance_settings;
    keyboard60_performance u_performance(sys_clk,audio_sample_tick,synth_keys,effective_performance,keyboard_octave,
        performance_step,performance_level,performance_space,bend_target,performance_read_key);
    poly32_synth #(.KEY_COUNT(60)) u_poly(sys_clk,audio_sample_tick,synth_keys,1920'd0,selected_timbre,
        piano_adsr,guitar_adsr,accordion_adsr,poly_valid,poly_op,poly_a,poly_b,poly_ready,poly_done,poly_ok,
        poly_active,poly_held,poly_active_mask,poly_held_mask,poly_demo,poly_deadline,
        piano_pcm,guitar_pcm,accordion_pcm,poly_mixed_pcm,poly_frame_done,poly_voice_samples,song_gates,song_notes,song_epochs,visual_pcm,visual_step,visual_tag,visual_active,keyboard_base,performance_step,performance_read_key,pedal_sustain);
    // Wide addition; a gentle knee only acts on unusually large combined tails.
    reg signed [17:0] bank_sum=18'sd0;
    reg signed [18:0] knee_sum=0;
    wire signed [18:0] performance_pcm;
    performance_mix u_performance_mix(sys_clk,audio_sample_tick,bank_sum,performance_level,performance_space,performance_pcm,pressure_mode,{adc_bend[4:0],adc_bend[4]},pressure_depth);
    wire signed [18:0] voiced_pcm;
    tone_output_filter u_tone_finish(sys_clk,audio_sample_tick,performance_pcm,voiced_pcm);
    wire signed [18:0] gained_pcm;
    audio_output_gain u_output_gain(sys_clk,audio_sample_tick,voiced_pcm,gained_pcm);
    always @(posedge sys_clk) begin
        bank_sum<=poly_mixed_pcm;
        if(gained_pcm>19'sd24000) knee_sum<=19'sd24000+((gained_pcm-19'sd24000)>>>2);
        else if(gained_pcm< -19'sd24000) knee_sum<= -19'sd24000+((gained_pcm+19'sd24000)>>>2);
        else knee_sum<=gained_pcm;
        if(knee_sum>18'sd32767) audio_pcm<=16'sd32767;
        else if(knee_sum< -18'sd32768) audio_pcm<= -16'sd32768;
        else audio_pcm<=knee_sum[15:0];
    end
    pt8211_tx u_audio(sys_clk,audio_pcm,audio_sample_tick,hp_bck,hp_ws,hp_din,pa_en);
    // External standard-I2S DAC is fed from the same real-time PCM frame.
    // The original audio_sample_tick and onboard output remain the master.
    wire i2s_frame_tick;
    i2s_tx u_i2s(sys_clk,audio_pcm,i2s_frame_tick,i2s_bclk,i2s_lrclk,i2s_dout);
    // PCM5102A soft mute: low during the original 20ms startup mute only.
    // Keep BCLK/LRCLK running continuously; never wake the DAC per note.
    assign i2s_xsmt = ~pa_en;

    wire [59:0] physical_target,physical_wrong;
    generate for(key_number=0;key_number<60;key_number=key_number+1)begin:ledmap60
      assign physical_target[key_number]=full_target[mapped_key(key_number)];
      assign physical_wrong[key_number]=full_wrong[mapped_key(key_number)] |
       (challenge_mode && rhythm_feedback_valid && rhythm_status[88:86]>3 && rhythm_feedback[mapped_key(key_number)]);
    end endgenerate
    wire [59:0] led_keys_wired,led_target_wired,led_wrong_wired;
    genvar light_key;
    generate for(light_key=0;light_key<60;light_key=light_key+1)begin:mixed_led_wires
      assign led_keys_wired[legacy_slot(light_key)]=KEYBOARD_MIXED_5_7?physical_pressed[light_key]:physical_pressed[legacy_slot(light_key)];
      assign led_target_wired[legacy_slot(light_key)]=KEYBOARD_MIXED_5_7?physical_target[light_key]:physical_target[legacy_slot(light_key)];
      assign led_wrong_wired[legacy_slot(light_key)]=KEYBOARD_MIXED_5_7?physical_wrong[light_key]:physical_wrong[legacy_slot(light_key)];
    end endgenerate
    keyboard60_led #(.BLACK_FIRST(KEYBOARD_MIXED_5_7?1:KEYBOARD_BLACK_FIRST),.MIXED_5_7(0)) u_leds(sys_clk,led_keys_wired,led_target_wired,led_wrong_wired,guide_state,selected_timbre,
      challenge_mode?rhythm_count:practice_count_in,challenge_mode?rhythm_beat:practice_beat,
      challenge_mode?rhythm_flash:practice_flash,challenge_mode?rhythm_active:practice_clock_active,
      score_index,{selected_user,score_bank},led_data,led_frame_latched,led_frame_valid,led_frame_index,led_frame_source);
endmodule

// Digital makeup gain after the unchanged master/space/output filter.
// Q13 gain4.0 below the limiting threshold; conservative current-sample cap,
// immediate attack, ~4096-sample recovery constant. No lookahead or audio RAM.
module audio_output_gain(input wire clk,sample_tick,
 input wire signed [18:0] source,output wire signed [18:0] gained);
 localparam [15:0] MAX_GAIN=16'd32768; //4*8192
 reg signed [18:0] source_q=0;
 reg [15:0] ceiling_q=MAX_GAIN,gain_q=MAX_GAIN;
 wire [18:0] magnitude=source[18] ? -source : source;
 // Upper-bound each magnitude bucket so quantization can only reduce gain.
 //64 reciprocal mantissa bins; all divisions below are precomputed constants.
 function [15:0] gain_ceiling(input [18:0] mag);
  reg [6:0] bin;reg [3:0] shift;reg [21:0] reciprocal;
  begin
   if(mag<=19'd6000)gain_ceiling=MAX_GAIN;
   else begin
    if(mag[18])begin bin=mag[18:12];shift=12;end
    else if(mag[17])begin bin=mag[17:11];shift=11;end
    else if(mag[16])begin bin=mag[16:10];shift=10;end
    else if(mag[15])begin bin=mag[15:9];shift=9;end
    else if(mag[14])begin bin=mag[14:8];shift=8;end
    else if(mag[13])begin bin=mag[13:7];shift=7;end
    else begin bin=mag[12:6];shift=6;end
    case(bin)
     7'd64:reciprocal=22'd3024738;
     7'd65:reciprocal=22'd2978909;
     7'd66:reciprocal=22'd2934447;
     7'd67:reciprocal=22'd2891294;
     7'd68:reciprocal=22'd2849391;
     7'd69:reciprocal=22'd2808685;
     7'd70:reciprocal=22'd2769126;
     7'd71:reciprocal=22'd2730666;
     7'd72:reciprocal=22'd2693260;
     7'd73:reciprocal=22'd2656864;
     7'd74:reciprocal=22'd2621440;
     7'd75:reciprocal=22'd2586947;
     7'd76:reciprocal=22'd2553350;
     7'd77:reciprocal=22'd2520615;
     7'd78:reciprocal=22'd2488708;
     7'd79:reciprocal=22'd2457600;
     7'd80:reciprocal=22'd2427259;
     7'd81:reciprocal=22'd2397658;
     7'd82:reciprocal=22'd2368771;
     7'd83:reciprocal=22'd2340571;
     7'd84:reciprocal=22'd2313035;
     7'd85:reciprocal=22'd2286139;
     7'd86:reciprocal=22'd2259862;
     7'd87:reciprocal=22'd2234181;
     7'd88:reciprocal=22'd2209078;
     7'd89:reciprocal=22'd2184533;
     7'd90:reciprocal=22'd2160527;
     7'd91:reciprocal=22'd2137043;
     7'd92:reciprocal=22'd2114064;
     7'd93:reciprocal=22'd2091574;
     7'd94:reciprocal=22'd2069557;
     7'd95:reciprocal=22'd2048000;
     7'd96:reciprocal=22'd2026886;
     7'd97:reciprocal=22'd2006204;
     7'd98:reciprocal=22'd1985939;
     7'd99:reciprocal=22'd1966080;
     7'd100:reciprocal=22'd1946613;
     7'd101:reciprocal=22'd1927529;
     7'd102:reciprocal=22'd1908815;
     7'd103:reciprocal=22'd1890461;
     7'd104:reciprocal=22'd1872457;
     7'd105:reciprocal=22'd1854792;
     7'd106:reciprocal=22'd1837457;
     7'd107:reciprocal=22'd1820444;
     7'd108:reciprocal=22'd1803743;
     7'd109:reciprocal=22'd1787345;
     7'd110:reciprocal=22'd1771243;
     7'd111:reciprocal=22'd1755428;
     7'd112:reciprocal=22'd1739893;
     7'd113:reciprocal=22'd1724631;
     7'd114:reciprocal=22'd1709634;
     7'd115:reciprocal=22'd1694896;
     7'd116:reciprocal=22'd1680410;
     7'd117:reciprocal=22'd1666169;
     7'd118:reciprocal=22'd1652168;
     7'd119:reciprocal=22'd1638400;
     7'd120:reciprocal=22'd1624859;
     7'd121:reciprocal=22'd1611540;
     7'd122:reciprocal=22'd1598439;
     7'd123:reciprocal=22'd1585548;
     7'd124:reciprocal=22'd1572864;
     7'd125:reciprocal=22'd1560380;
     7'd126:reciprocal=22'd1548094;
     7'd127:reciprocal=22'd1536000;
     default:reciprocal=0;
    endcase
    gain_ceiling=reciprocal>>shift;
   end
  end
 endfunction
 wire [15:0] applied_gain=gain_q<ceiling_q?gain_q:ceiling_q;
 wire [15:0] recovery_distance=ceiling_q-gain_q;
 wire [15:0] recovery_step=recovery_distance[15:12]==0?16'd1:{12'd0,recovery_distance[15:12]};
 reg signed [35:0] product=0;
 assign gained=product[31:13];
 always @(posedge clk)begin
  source_q<=source;ceiling_q<=gain_ceiling(magnitude);
  product<=source_q*$signed({1'b0,applied_gain});
  if(sample_tick)begin
   if(gain_q>ceiling_q)gain_q<=ceiling_q;
   else if(gain_q<ceiling_q)gain_q<=recovery_distance<=recovery_step?ceiling_q:gain_q+recovery_step;
  end
 end
endmodule
