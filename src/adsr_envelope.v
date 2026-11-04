`timescale 1ns / 1ps
// Linear ADSR in Q8 amplitude units. Defaults at Fs=48828.125 Hz:
// A~=2 ms, D~=150 ms, S=30%, R~=120 ms from any release level.
module adsr_envelope #(
    parameter integer ATTACK_SAMPLES = 98,
    parameter integer DECAY_SAMPLES = 7324,
    parameter [15:0] SUSTAIN_LEVEL = 16'd9830,
    parameter integer RELEASE_SAMPLES = 5859
)(
    input wire sys_clk,
    input wire sample_tick,
    input wire gate,
    output wire [15:0] amplitude,
    output reg [2:0] state = 3'd0
);
    localparam [2:0] IDLE=0, ATTACK=1, DECAY=2, SUSTAIN=3, RELEASE=4;
    localparam [23:0] PEAK_Q8 = 24'd8388608;
    localparam [23:0] SUSTAIN_Q8 = {SUSTAIN_LEVEL,8'd0};
    localparam [23:0] ATTACK_STEP = (8388608+ATTACK_SAMPLES-1)/ATTACK_SAMPLES;
    localparam [23:0] DECAY_STEP = (8388608-SUSTAIN_Q8+DECAY_SAMPLES-1)/DECAY_SAMPLES;
    // Reciprocal with 24 fractional bits; release duration is within ~0.3 ms
    // of the requested 120 ms at normal performance levels.
    localparam [23:0] RELEASE_RECIP = (16777216+RELEASE_SAMPLES-1)/RELEASE_SAMPLES;
    reg [23:0] level_q8 = 24'd0;
    reg was_gate = 1'b0;
    reg [23:0] release_step = 24'd1;
    reg [47:0] release_product = 48'd0;
    wire [47:0] release_rounded = release_product + 48'd16777215;
    wire [23:0] release_step_now = release_rounded[47:24];
    assign amplitude = level_q8[23:8];
    // Registered product avoids placing the multiply and rounding add in one
    // 50 MHz path. level_q8 is stable between audio samples.
    always @(posedge sys_clk) release_product <= level_q8 * RELEASE_RECIP;
    always @(posedge sys_clk) begin
        if(sample_tick) begin
            was_gate <= gate;
            if(gate && !was_gate) begin
                // Retrigger from the current release level; do not jump to zero.
                if(level_q8 >= PEAK_Q8-ATTACK_STEP) begin
                    level_q8 <= PEAK_Q8;
                    state <= DECAY;
                end else begin
                    level_q8 <= level_q8 + ATTACK_STEP;
                    state <= ATTACK;
                end
            end else if(!gate && was_gate) begin
                release_step <= (release_step_now==0) ? 24'd1 : release_step_now;
                state <= (level_q8==0) ? IDLE : RELEASE;
            end else case(state)
                IDLE: level_q8 <= 24'd0;
                ATTACK: if(level_q8 >= PEAK_Q8-ATTACK_STEP) begin
                    level_q8 <= PEAK_Q8; state <= DECAY;
                end else level_q8 <= level_q8 + ATTACK_STEP;
                DECAY: if(level_q8 <= SUSTAIN_Q8+DECAY_STEP) begin
                    level_q8 <= SUSTAIN_Q8; state <= SUSTAIN;
                end else level_q8 <= level_q8 - DECAY_STEP;
                SUSTAIN: level_q8 <= SUSTAIN_Q8;
                RELEASE: if(level_q8 <= release_step) begin
                    level_q8 <= 24'd0; state <= IDLE;
                end else level_q8 <= level_q8 - release_step;
                default: begin level_q8 <= 24'd0; state <= IDLE; end
            endcase
        end
    end
endmodule
