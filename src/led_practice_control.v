`timescale 1ns/1ps
// Self-paced practice: the LED must latch before a fresh correct press counts.
// Keys 0..6 play fixed C4..B4. Keys 7/8/9 restart, pause, exit.
module led_practice_control #(
    parameter integer KEY_COUNT=7, SCORE_BITS=3, MS_CYCLES=50000,
    parameter integer REST_MS=250,
    parameter integer EXTERNAL_CONTROL=0,
    parameter integer METRONOME_ENABLE=0,
    parameter integer COUNT_IN_BEATS=3
)(
    input wire sys_clk,
    input wire [KEY_COUNT+2:0] keys,
    input wire [SCORE_BITS-1:0] score_degree,
    input wire score_last,
    input wire led_frame_latched,
    input wire led_frame_valid,
    input wire [12:0] led_frame_index,
    output reg [12:0] score_index=13'd0,
    output wire [KEY_COUNT-1:0] note_gate,
    output wire [KEY_COUNT-1:0] target_mask,
    output reg [KEY_COUNT-1:0] wrong_mask=0,
    output reg [2:0] state=3'd0,
    input wire remote_start,remote_pause,remote_stop,source_changed,
    input wire score_ready,uploaded_selected,
    input wire [15:0] score_rest_ms,
    input wire [15:0] tempo_bpm,
    output reg [1:0] count_in=0,
    output reg [1:0] beat_index=0,
    output wire beat_flash,
    output wire metronome_active,
    input wire score_missing_key,remote_skip
);
    localparam FREE=3'd0,CUE=3'd1,READY=3'd2,HELD=3'd3,
               REST=3'd4,DONE=3'd5,PAUSED=3'd6;
    reg [KEY_COUNT+2:0] previous=0;
    wire [KEY_COUNT+2:0] rise=keys & ~previous;
    reg [15:0] ms_counter=16'd0;
    wire ms_tick=(ms_counter==MS_CYCLES-1);
    reg [15:0] rest_count=16'd0;
    reg [7:0] error_ms=8'd0;
    reg cue_lit=1'b0;
    wire stop_request=rise[KEY_COUNT+2] || (EXTERNAL_CONTROL && (remote_stop || source_changed));
    wire start_request=rise[KEY_COUNT] || (EXTERNAL_CONTROL && remote_start);
    wire pause_request=(rise[KEY_COUNT+1] || (EXTERNAL_CONTROL && remote_pause)) && state!=FREE && state!=DONE;
    wire preparing=METRONOME_ENABLE && count_in!=0;
    reg [15:0] session_bpm=120,beat_phase=0;
    reg [6:0] flash_ms=0;
    wire [15:0] next_phase=beat_phase+session_bpm;
    assign metronome_active=METRONOME_ENABLE && state!=FREE && state!=DONE && state!=PAUSED;
    assign beat_flash=metronome_active && flash_ms!=0;
    // Millisecond fractional accumulator: never round 60000/BPM per beat.
    // All timing is local; neither UART nor the audio pipeline waits for it.
    // Count-in is a preparation state, not a delayed response to a played note.
    always @(posedge sys_clk) begin
        if(!METRONOME_ENABLE || stop_request) begin
            count_in<=0;beat_index<=0;beat_phase<=0;flash_ms<=0;
        end else if(start_request) begin
            session_bpm<=(tempo_bpm>=20 && tempo_bpm<=300)?tempo_bpm:16'd120;
            count_in<=COUNT_IN_BEATS;beat_index<=0;beat_phase<=0;flash_ms<=80;
        end else if(state==DONE) begin
            count_in<=0;beat_index<=0;beat_phase<=0;flash_ms<=0;
        end else if(pause_request) begin
            // Retain phase/count-in on pause, without replaying an old flash.
            flash_ms<=0;
        end else if(metronome_active && ms_tick) begin
            if(flash_ms!=0) flash_ms<=flash_ms-1'b1;
            if(next_phase>=60000) begin
                beat_phase<=next_phase-16'd60000;flash_ms<=80;
                if(count_in!=0) begin count_in<=count_in-1'b1;beat_index<=0;end
                else beat_index<=beat_index+1'b1;
            end else beat_phase<=next_phase;
        end
    end
    reg [SCORE_BITS-1:0] decoded_degree=0;
    reg [KEY_COUNT-1:0] expected=0;
    always @(posedge sys_clk)begin
        decoded_degree<=score_degree;
        expected<=(score_degree==0 || score_degree>KEY_COUNT)?0:
                  ({{(KEY_COUNT-1){1'b0}},1'b1}<<(score_degree-1'b1));
    end
    // A changed degree cannot publish a frame with the previous decoded mask.
    wire ready=(EXTERNAL_CONTROL?score_ready:1'b1) && decoded_degree==score_degree;
    wire [15:0] rest_duration=(EXTERNAL_CONTROL && uploaded_selected)?score_rest_ms:REST_MS;
    assign target_mask=(ready && !preparing && ((state==CUE)||(state==READY)||(state==HELD)))?expected:{KEY_COUNT{1'b0}};
    assign note_gate=(state==FREE)?keys[KEY_COUNT-1:0]:
                     ((state==HELD)?(keys[KEY_COUNT-1:0]&expected):{KEY_COUNT{1'b0}});
    always @(posedge sys_clk) begin
        previous<=keys;
        if(ms_tick) ms_counter<=16'd0;
        else ms_counter<=ms_counter+1'b1;
        if(ms_tick && error_ms!=0) begin
            error_ms<=error_ms-1'b1;
            if(error_ms==1) wrong_mask<={KEY_COUNT{1'b0}};
        end
        if(stop_request) begin
            state<=FREE; cue_lit<=0; wrong_mask<=0; error_ms<=0;
        end else if(start_request) begin
            score_index<=0; state<=CUE; cue_lit<=0;
            wrong_mask<=0; error_ms<=0; rest_count<=0;
        end else if(pause_request) begin
            if(state==PAUSED) begin state<=CUE; cue_lit<=0; rest_count<=0; end
            else state<=PAUSED;
        end else if(remote_skip && EXTERNAL_CONTROL && uploaded_selected && score_missing_key && ready &&
                    !preparing && keys[KEY_COUNT-1:0]==0 && (state==CUE || state==READY)) begin
            if(score_last)state<=DONE;else begin score_index<=score_index+1'b1;state<=CUE;end
            cue_lit<=0;wrong_mask<=0;error_ms<=0;rest_count<=0;
        end else begin
            case(state)
                FREE: begin cue_lit<=0; end
                CUE: if(ready && !preparing) begin
                    if(score_missing_key && uploaded_selected) begin state<=READY;cue_lit<=0;end
                    else if(score_degree==0) begin state<=REST; rest_count<=0; end
                    else begin
                        if(led_frame_latched && led_frame_valid && led_frame_index==score_index)
                            cue_lit<=1;
                        // A key held before the cue must be released first.
                        if(cue_lit && keys[KEY_COUNT-1:0]==0) state<=READY;
                    end
                end
                READY: if(|rise[KEY_COUNT-1:0]) begin
                    if(keys[KEY_COUNT-1:0]==expected && |(rise[KEY_COUNT-1:0]&expected)) begin
                        state<=HELD; wrong_mask<=0; error_ms<=0;
                    end else begin
                        wrong_mask<=keys[KEY_COUNT-1:0]&~expected; error_ms<=8'd180;
                    end
                end
                HELD: begin
                    if(|(rise[KEY_COUNT-1:0]&~expected)) begin
                        wrong_mask<=keys[KEY_COUNT-1:0]&~expected; error_ms<=8'd180;
                    end
                    // Advance only after all sounding keys are released.
                    if(keys[KEY_COUNT-1:0]==0) begin
                        if(score_last) state<=DONE;
                        else begin score_index<=score_index+1'b1; state<=CUE; end
                        cue_lit<=0; wrong_mask<=0; error_ms<=0;
                    end
                end
                REST: if(ms_tick) begin
                    if(rest_count==rest_duration-1'b1) begin
                        if(score_last) state<=DONE;
                        else begin score_index<=score_index+1'b1; state<=CUE; end
                        cue_lit<=0;
                    end else rest_count<=rest_count+1'b1;
                end
                DONE: begin end
                PAUSED: begin end
                default: state<=FREE;
            endcase
        end
    end
endmodule
