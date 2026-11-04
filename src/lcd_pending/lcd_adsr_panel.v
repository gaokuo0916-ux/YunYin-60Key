`timescale 1ns/1ps
// All control and drawing logic runs on the existing 50 MHz clock.
// The external RGB pixel clock is an integer divide by two (25 MHz).
// Data/DE/HS/VS are registered on its falling edge, held for the rising edge.
// RGB timing: Embedfire companion 800x480 panel, requires board test.
module lcd_adsr_panel #(
 parameter integer H_SYNC=1,H_BACK=46,H_FRONT=22,
 parameter integer V_SYNC=1,V_BACK=23,V_FRONT=22,
 parameter integer MIRROR_X=0,MIRROR_Y=0,RHYTHM_ENABLE=0,MULTISONG_ENABLE=0
)(input wire clk,sample_tick,input wire [1:0] selected_timbre,
  input wire [6:0] note_gate,
  output wire [74:0] piano_coeff,guitar_coeff,accordion_coeff,
  output wire [7:0] lcd_r,lcd_g,lcd_b,
  output wire lcd_pclk,
  output reg lcd_hs=1,lcd_vs=1,lcd_de=0,
  output wire lcd_bk,touch_rst_n,
  inout wire touch_sda,touch_scl,touch_int,
  input wire signed [15:0] audio_pcm,
  input wire selected_user,user_valid,uploading,bt_activity,
  input wire [3:0] upload_error,
  input wire [15:0] received_bcd,total_bcd,stored_bcd,
  input wire [11:0] score_bpm_bcd,
  input wire [2:0] guide_state,
  output reg [1:0] ui_source=0,
  output reg ui_start=0,ui_pause=0,ui_stop=0,
  output reg [23:0] performance_settings={6'd63,6'd32,6'd0,6'd0},
  input wire rhythm_mode,input wire [159:0] rhythm_status,
  output reg rhythm_enter=0,rhythm_start=0,rhythm_pause=0,rhythm_exit=0,
  output reg rhythm_level_valid=0,output reg [1:0] rhythm_level_request=0,
  output reg ui_timbre_valid=0,output reg [1:0] ui_timbre_request=0,
 input wire native_missing,output reg ui_skip=0,
 input wire signed [31:0] visual_pcm,input wire [31:0] visual_step,
 input wire [12:0] visual_tag,input wire visual_active,
 input wire [59:0] full_keys,full_target,input wire [6:0] keyboard_base,
 input wire [127:0] challenge_preview,input wire preview_ready,
 output wire [3:0] preview_song,output wire [5:0] preview_page,
 output reg rhythm_song_valid=0,output reg [3:0] rhythm_song=0,
 input wire [1:0] panel_edit,input wire [11:0] panel_values,
 input wire [5:0] panel_bend,output reg [1:0] pressure_mode=1,output reg [5:0] pressure_depth=0);
    reg pixel_phase=0;
    always @(posedge clk) pixel_phase<=~pixel_phase;
    assign lcd_pclk=pixel_phase;
    assign lcd_bk=1'b1;
    wire hs,vs,de,frame_start;
    wire [11:0] x,y;
    lcd_timing_generic #(.H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_FRONT(H_FRONT),
      .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_FRONT(V_FRONT),.PROFILE_CONFIRMED(1)) raster(
      clk,!pixel_phase,1'b0,hs,vs,de,frame_start,x,y);
    wire tv,td;
    wire [11:0] raw_x,raw_y;
    wire [1:0] touch_status;
    wire [23:0] product_id;
    gt911_touch_reader touch(clk,touch_sda,touch_scl,touch_int,touch_rst_n,
      tv,td,raw_x,raw_y,touch_status,product_id);
    wire [11:0] tx=MIRROR_X?12'd799-raw_x:raw_x;
    wire [11:0] ty=MIRROR_Y?12'd479-raw_y:raw_y;
    wire edit_valid;
    wire [1:0] parameter_id;
    wire [5:0] value_index;
    reg held=0,restore=0;
    reg [1:0] edit_bank=0;
    // 1 waveform (default), 0 envelope, 2 FFT, 3 mono phase portrait.
    reg [1:0] graph_mode=1;
    wire waveform_view=graph_mode==1;
    reg [1:0] waveform_scale=3;
    // 0..3.05 kHz covers the default five-octave keyboard's fundamentals.
    // Wider ranges remain selectable for upper octave shifts and overtones.
    // Fixed C4 reference versus actual audio. All four previous modes remain
    // selectable: raw lag16, fundamental lag32, raw lag32 and raw lag64.
    reg [2:0] spectrum_zoom=0;
    reg spectrum_auto=0;
    reg [2:0] phase_delay=4;
    reg score_page=0,live_page=0,challenge_page=0;
    wire live_edit;wire [1:0] live_parameter;wire [5:0] live_index;
    adsr_touch_sliders live_sliders(clk,tv && live_page && !score_page && graph_mode<2,td,tx,ty,live_edit,live_parameter,live_index);
    always @(posedge clk) if(live_edit) begin
      case(live_parameter)
       0:performance_settings[23:18]<=live_index;
       1:performance_settings[17:12]<=live_index;
       2:performance_settings[11:6]<=live_index;
       3:pressure_depth<=live_index;
      endcase
    end else if(tv && td && !held && live_page && !score_page && tx>=644 && tx<788 && ty>=8 && ty<48)
      begin performance_settings<={6'd63,6'd32,6'd0,6'd0};pressure_depth<=0;end
    else begin
      if(panel_edit[0]===1'b1)performance_settings[23:18]<=panel_values[11:6];
      if(panel_edit[1]===1'b1)performance_settings[11:6]<=panel_values[5:0];
    end
    wire [63:0] performance_values;
    // Keep manual pitch on row2; row4 now controls the selected FX depth.
    wire [5:0] pressure_live={panel_bend[4:0],panel_bend[4]};
    wire [6:0] pressure_sum={1'b0,pressure_depth}+{1'b0,pressure_live};
    wire [5:0] displayed_fx=pressure_sum[6]?6'd63:pressure_sum[5:0];
    wire [23:0] displayed_performance={performance_settings[23:6],displayed_fx};
    performance_display performance_labels(displayed_performance,performance_values);
    always @(posedge clk) begin
        restore<=0;
        ui_timbre_valid<=0;ui_skip<=0;
        ui_source<=0;ui_start<=0;ui_pause<=0;ui_stop<=0;
        rhythm_enter<=0;rhythm_start<=0;rhythm_pause<=0;rhythm_exit<=0;rhythm_level_valid<=0;rhythm_song_valid<=0;
        // A phone GSEL enters the same page as a touch on the game button.
        if(RHYTHM_ENABLE && rhythm_mode) challenge_page<=1;
        if(RHYTHM_ENABLE && !rhythm_mode && !rhythm_enter) challenge_page<=0;
        if(tv) begin
            held<=td;
            if(td && !held) begin
                edit_bank<=selected_timbre;
                if(native_missing && tx>=624 && tx<776 && ty>=432 && ty<472)ui_skip<=1;
                if(RHYTHM_ENABLE && challenge_page) begin
                    if(tx>=644 && tx<788 && ty>=8 && ty<48) begin
                        challenge_page<=0;rhythm_exit<=1;
                    end
                    if(ty>=64 && ty<112 && (!MULTISONG_ENABLE || rhythm_status[2:0]==0 || rhythm_status[2:0]==5)) begin
                        if(tx>=24 && tx<248) begin rhythm_level_request<=0;rhythm_level_valid<=1;end
                        if(tx>=288 && tx<512) begin rhythm_level_request<=1;rhythm_level_valid<=1;end
                        if(tx>=552 && tx<776) begin rhythm_level_request<=2;rhythm_level_valid<=1;end
                    end
                    if(MULTISONG_ENABLE && ty>=124 && ty<164 && full_keys==0 && (rhythm_status[2:0]==0 || rhythm_status[2:0]==5))begin
                      if(tx>=464 && tx<512)begin rhythm_song_valid<=1;
                        rhythm_song<=rhythm_status[157:154]==0?4:rhythm_status[157:154]==5?9:rhythm_status[157:154]==10?14:rhythm_status[157:154]-1'b1;end
                      if(tx>=528 && tx<600)begin rhythm_song_valid<=1;
                        rhythm_song<=rhythm_status[157:154]==4?0:rhythm_status[157:154]==9?5:rhythm_status[157:154]==14?10:rhythm_status[157:154]+1'b1;end
                    end
                    if(ty>=400 && ty<432) begin
                        if(tx>=24 && tx<248) rhythm_start<=1;
                        if(tx>=288 && tx<512) rhythm_pause<=1;
                        if(tx>=552 && tx<776) begin challenge_page<=0;rhythm_exit<=1;end
                    end
                end else if(score_page) begin
                    if(RHYTHM_ENABLE && tx>=224 && tx<336 && ty>=8 && ty<48) begin challenge_page<=1;rhythm_enter<=1;end
                    if(tx>=644 && tx<788 && ty>=8 && ty<48) score_page<=0;
                    if(ty>=80 && ty<152) begin
                        if(tx>=24 && tx<360) ui_source<=1;
                        if(tx>=416 && tx<776) ui_source<=2;
                    end
                    if(ty>=330 && ty<398) begin
                        if(tx>=24 && tx<248) ui_start<=1;
                        if(tx>=288 && tx<512) ui_pause<=1;
                        if(tx>=552 && tx<776) ui_stop<=1;
                    end
                end else begin
                    if(tx>=64 && tx<212 && ty>=8 && ty<48) begin
                        ui_timbre_valid<=1;
                        ui_timbre_request<=selected_timbre==2?0:selected_timbre+1'b1;
                    end
                    if(RHYTHM_ENABLE && tx>=24 && tx<112 && ty>=432 && ty<476) begin
                        challenge_page<=1;score_page<=1;live_page<=0;rhythm_enter<=1;
                    end
                    if(tx>=520 && tx<628 && ty>=8 && ty<48) begin score_page<=1;live_page<=0;end
                    if(tx>=228 && tx<324 && ty>=8 && ty<48) live_page<=~live_page;
                    if(live_page && graph_mode<2 && tx>=16 && tx<96 && ty>=384 && ty<416)pressure_mode<=pressure_mode==3?2'd1:pressure_mode+1'b1;
                    if(live_page && tx>=644 && tx<788 && ty>=8 && ty<48)pressure_mode<=1;
                    if(!live_page && tx>=644 && tx<788 && ty>=8 && ty<48) restore<=1;
                    if(tx>=24 && tx<200 && ty>=60 && ty<88)
                        case(graph_mode) 1:graph_mode<=0;0:graph_mode<=2;2:graph_mode<=3;default:graph_mode<=1;endcase
                    if(tx>=544 && tx<672 && ty>=60 && ty<88) begin
                        if(graph_mode==2) spectrum_zoom<=spectrum_zoom==0?3'd4:spectrum_zoom==4?3'd1:spectrum_zoom==3?3'd0:spectrum_zoom+1'b1;
                        else waveform_scale<=waveform_scale+1'b1;
                    end
                    if(graph_mode==2 && tx>=352 && tx<496 && ty>=60 && ty<88)spectrum_auto<=!spectrum_auto;
                    if(graph_mode==3 && tx>=352 && tx<528 && ty>=60 && ty<88)
                        phase_delay<=phase_delay==4?3'd0:phase_delay+1'b1;
                end
            end
        end
    end
    // The curve page and song page never edit each other's controls.
    adsr_touch_sliders sliders(clk,tv && !score_page && !live_page && graph_mode<2,td,tx,ty,edit_valid,parameter_id,value_index);
    wire edit_ready;
    wire [23:0] piano_indices,guitar_indices,accordion_indices;
    wire [63:0] piano_values,guitar_values,accordion_values;
    adsr_parameter_bank banks(clk,sample_tick,edit_valid,edit_bank,restore,
      parameter_id,value_index,edit_ready,piano_coeff,guitar_coeff,accordion_coeff,
      piano_indices,guitar_indices,accordion_indices,piano_values,guitar_values,accordion_values);
    // Frame snapshots prevent the labels and sliders tearing mid-frame.
    reg [1:0] view_timbre=0;
    reg view_waveform=1;
    reg [1:0] view_graph_mode=1;
    reg [1:0] view_waveform_scale=3;
    reg [1:0] view_status=0;
    reg [59:0] view_full_keys=0,view_full_target=0;reg [6:0] view_base=36;
    reg [6:0] view_gate=0,view_sustain=7'd51;
    reg [23:0] view_indices={6'd0,6'd8,6'd50,6'd11};
    reg [63:0] view_values=64'h0001_0150_0080_0120;
    reg [23:0] view_envelope_indices={6'd0,6'd10,6'd41,6'd14};
    reg view_score_page=0,view_live_page=0,view_native_missing=0;reg [1:0] view_pressure_mode=0;
    reg [3:0] view_bt_flags=0,view_upload_error=0;
    reg [59:0] view_score_numbers=0;
    reg [2:0] view_guide_state=0;
    reg view_challenge=0;
    reg [159:0] view_rhythm=0;
    reg [191:0] rhythm_numbers=0;
    wire [5:0] view_cursor=view_rhythm[22:17],view_events=view_rhythm[28:23];
    assign preview_song=view_rhythm[157:154];
    // Same frame snapshot and same output cycle as decoding view_rhythm,
    // but do not chain the page decoder through catalog readiness and pixels.
    reg [5:0] preview_page_q=6'd56;
    assign preview_page=preview_page_q;
    always @(posedge clk)if(frame_start)
      preview_page_q<=(rhythm_status[22:17]<rhythm_status[28:23]?
        rhythm_status[22:17]:rhythm_status[28:23]-6'd1)&6'b111000;
    function [11:0] bcd8(input [7:0] value);
      reg [19:0] work;integer i,j;
      begin
       work={12'd0,value};
       for(i=0;i<8;i=i+1) begin
        for(j=0;j<3;j=j+1) if(work[8+4*j+:4]>=5) work[8+4*j+:4]=work[8+4*j+:4]+3;
        work=work<<1;
       end
       bcd8=work[19:8];
      end
    endfunction
    wire [8:0] deviation_abs=rhythm_status[97]?(~rhythm_status[97:89]+9'd1):rhythm_status[97:89];
    always @(posedge clk) if(frame_start) begin
        view_full_keys<=full_keys;view_full_target<=full_target;view_base<=keyboard_base;view_native_missing<=native_missing;view_timbre<=selected_timbre;view_status<=touch_status;view_gate<=note_gate;
        view_waveform<=waveform_view;view_waveform_scale<=waveform_scale;view_graph_mode<=graph_mode;
        view_indices<=live_page?displayed_performance:selected_timbre==0?piano_indices:selected_timbre==1?guitar_indices:accordion_indices;
        view_values<=live_page?performance_values:selected_timbre==0?piano_values:selected_timbre==1?guitar_values:accordion_values;
        view_envelope_indices<=selected_timbre==0?piano_indices:selected_timbre==1?guitar_indices:accordion_indices;
        view_sustain<=selected_timbre==0?piano_coeff[38:32]:selected_timbre==1?guitar_coeff[38:32]:accordion_coeff[38:32];
        view_score_page<=score_page;view_live_page<=live_page;view_pressure_mode<=pressure_mode;
        view_bt_flags<={bt_activity,uploading,user_valid,selected_user};
        view_upload_error<=upload_error;
        view_score_numbers<={received_bcd,total_bcd,stored_bcd,selected_user?score_bpm_bcd:12'h120};
        view_guide_state<=guide_state;
        view_challenge<=RHYTHM_ENABLE && challenge_page;view_rhythm<=rhythm_status;
        rhythm_numbers<={48'd0,
          bcd8({2'd0,rhythm_status[119:114]}),bcd8(rhythm_status[85:78]),
          bcd8({2'd0,rhythm_status[77:72]}),bcd8({2'd0,rhythm_status[71:66]}),
          bcd8({2'd0,rhythm_status[65:60]}),bcd8({2'd0,rhythm_status[59:54]}),
          bcd8(deviation_abs[7:0]),bcd8({1'd0,rhythm_status[112:106]}),
          bcd8({2'd0,rhythm_status[53:48]}),bcd8({2'd0,rhythm_status[47:42]}),
          bcd8({1'd0,rhythm_status[41:35]}),bcd8(rhythm_status[16:9])};
    end
    wire [23:0] render_rgb;
    wire signed [15:0] wave_sample;
    wire [15:0] wave_peak;
    wire wave_valid;
    // Separate raster counter/subtraction from the geometry decode path.
    reg [11:0] draw_x=0,draw_y=0;
    always @(posedge clk) begin draw_x<=x;draw_y<=y;end
    audio_wave_capture capture(clk,sample_tick,frame_start,audio_pcm,
        draw_x[8:0]-9'd128,wave_sample,wave_peak,wave_valid);
    wire [7:0] spectrum_height;
    wire spectrum_valid,phase_pixel,phase_valid;
    wire [2:0] spectrum_display_zoom;wire [1:0] phase_display_gain;
    wire [19:0] spectrum_peak_bcd;wire spectrum_peak_valid,spectrum_display_auto;
    wire [2:0] phase_display_delay;
    audio_spectrum spectrum(clk,sample_tick,frame_start,audio_pcm,spectrum_zoom,
        draw_x[8:3]-6'd16,spectrum_height,spectrum_valid,spectrum_display_zoom,
        spectrum_peak_bcd,spectrum_peak_valid,spectrum_auto,spectrum_display_auto);
    wire signed [15:0] fundamental_pcm,phase_reference_sample;wire fundamental_valid;
    wire [7:0] phase_reference_address;
    audio_fundamental_monitor fundamental(clk,sample_tick,visual_pcm,visual_step,visual_active,visual_tag,
      fundamental_pcm,fundamental_valid,phase_reference_address,phase_reference_sample);
    audio_phase_plot phase_plot(clk,sample_tick,frame_start,audio_pcm,waveform_scale,phase_delay,
        {draw_y[7:1]-7'd64,draw_x[7:1]},phase_pixel,phase_valid,phase_display_gain,phase_display_delay,wave_peak,
        fundamental_pcm,fundamental_valid,visual_active,visual_tag,visual_step,phase_reference_sample,phase_reference_address);
    wire [5:0] strip_index=x[8:3]-6'd16;
    localparam [59:0] BLACK_KEYS=60'h54a54a54a54a54a;
    reg [23:0] strip_color=0;
    always @(posedge clk)begin
      if(view_full_keys[strip_index])strip_color<=24'hc5dcf4;
      else if(view_full_target[strip_index])strip_color<=24'he6b647;
      else strip_color<=BLACK_KEYS[strip_index]?24'h303943:24'hf0f2f4;
    end
    lcd_adsr_renderer #(.RHYTHM_ENABLE(RHYTHM_ENABLE),.MULTISONG_ENABLE(MULTISONG_ENABLE)) draw(clk,draw_x,draw_y,view_timbre,view_status,view_gate,view_indices,
        view_values,view_sustain,render_rgb,view_waveform,wave_valid,wave_sample,view_waveform_scale,wave_peak,
        view_score_page,view_bt_flags,view_upload_error,view_score_numbers,view_guide_state,view_live_page,
        view_graph_mode,spectrum_height,spectrum_valid,spectrum_display_zoom,
        phase_pixel,phase_valid,phase_display_gain,phase_display_delay,
        view_challenge,view_rhythm,rhythm_numbers,view_native_missing,view_full_keys,view_full_target,view_base,strip_color,challenge_preview,preview_ready,
        spectrum_peak_bcd,spectrum_peak_valid,spectrum_display_auto,view_pressure_mode,view_envelope_indices,1'b1);
    reg [3:0] hs_pipe=4'b1111,vs_pipe=4'b1111,de_pipe=0;
    always @(posedge clk) begin
        hs_pipe<={hs_pipe[2:0],hs};vs_pipe<={vs_pipe[2:0],vs};de_pipe<={de_pipe[2:0],de};
    end
    reg [23:0] rgb=0;
    assign {lcd_r,lcd_g,lcd_b}=rgb;
    always @(posedge clk) if(pixel_phase) begin
        rgb<=de_pipe[3]?render_rgb:24'd0;lcd_de<=de_pipe[3];lcd_hs<=hs_pipe[3];lcd_vs<=vs_pipe[3];
    end
endmodule
