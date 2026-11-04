`timescale 1ns/1ps
// Runtime coefficient interface. Q8 peak = 32768 * 256.
// Coefficients are committed as a complete set in the audio clock domain.
// A/D latch at their phase entries; R latches at note-off; held S slews.
module adsr_runtime(
    input wire sys_clk, sample_tick, gate,
    input wire [17:0] attack_step_q8, decay_step_q8,
    input wire [23:0] sustain_q8,
    input wire [14:0] release_recip_q24,
    output wire [15:0] amplitude,
    output reg [2:0] state=0
);
    localparam [2:0] IDLE=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
    localparam [23:0] PEAK=24'd8388608;
    reg [23:0] level=0,release_step=1,decay_target=0,decay_limit=0;
    reg [17:0] attack_latched=1,decay_latched=1;
    reg was_gate=0;
    // 24 x 15, suitable for a single 27 x 18 DSP. No per-voice divider.
    reg [38:0] release_product=0;
    // ceil(product/2^24) without a 39-bit carry chain.
    wire [14:0] release_now=release_product[38:24]+{14'd0,(|release_product[23:0])};
    wire [17:0] safe_a=attack_step_q8==0?18'd1:attack_step_q8;
    wire [17:0] safe_d=decay_step_q8==0?18'd1:decay_step_q8;
    wire [23:0] safe_s=sustain_q8>PEAK?PEAK:sustain_q8;
    reg [23:0] s_distance_q=0,s_target_q=0,s_target_delay_q=0,s_next_q=0;
    reg s_up_q=0;
    wire [23:0] distance=level>s_target_q?level-s_target_q:s_target_q-level;
    wire [23:0] fresh_sum=level+{6'd0,safe_a};
    wire [23:0] attack_sum=level+{6'd0,attack_latched};
    // S's difference and next-level arithmetic use separate 50MHz registers.
    // The result settles long before the next 1024-clock audio frame.
    wire [15:0] s_step_q=(s_distance_q[23:8]==0)?16'd1:s_distance_q[23:8];
    assign amplitude=level[23:8];
    always @(posedge sys_clk) begin
        release_product<=level*release_recip_q24;
        s_target_q<=safe_s;s_target_delay_q<=s_target_q;
        s_distance_q<=distance;s_up_q<=level<s_target_q;
        // For distance >= 2, min(1,distance>>8) is always smaller than distance.
        if(s_distance_q<=1) s_next_q<=s_target_delay_q;
        else if(s_up_q) s_next_q<=level+{8'd0,s_step_q};
        else s_next_q<=level-{8'd0,s_step_q};
    end
    always @(posedge sys_clk) begin
        if(sample_tick) begin
            was_gate<=gate;
            if(gate && !was_gate) begin
                attack_latched<=safe_a;
                if(fresh_sum[23]) begin
                    level<=PEAK;state<=DECAY;
                    decay_latched<=safe_d;decay_target<=safe_s;decay_limit<=safe_s+safe_d;
                end else begin level<=fresh_sum;state<=ATTACK;end
            end else if(!gate && was_gate) begin
                release_step<=release_now==0?24'd1:{9'd0,release_now};
                state<=level==0?IDLE:RELEASE;
            end else case(state)
                IDLE:level<=0;
                ATTACK:if(attack_sum[23]) begin
                    level<=PEAK;state<=DECAY;
                    decay_latched<=safe_d;decay_target<=safe_s;decay_limit<=safe_s+safe_d;
                end else level<=attack_sum;
                DECAY:if(level<=decay_limit) begin
                    level<=decay_target;state<=SUSTAIN;
                end else level<=level-decay_latched;
                SUSTAIN:level<=s_next_q;
                RELEASE:if(level<=release_step) begin level<=0;state<=IDLE;end
                    else level<=level-release_step;
                default:begin level<=0;state<=IDLE;end
            endcase
        end
    end
endmodule
