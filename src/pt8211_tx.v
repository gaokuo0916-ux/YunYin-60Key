`timescale 1ns / 1ps
// Reconstructed from audio_tb.vvp; PT8211 left-justified stereo, NOT I2S.
// 50 MHz / 32 = 1.5625 MHz BCK; 50 MHz / 1024 = 48828.125 Hz frames.
module pt8211_tx (
    input wire sys_clk,
    input wire signed [15:0] pcm,
    output wire sample_tick,
    output reg hp_bck = 1'b0,
    output reg hp_ws = 1'b1,
    output reg hp_din = 1'b0,
    output wire pa_en
);
    reg [3:0] divider = 4'd0;
    reg [4:0] bit_index = 5'd31;
    reg [31:0] shift_data = 32'd0;
    reg [19:0] startup = 20'd0;
    // Original 20 ms startup mute; pa_en is active high for mute.
    assign pa_en = (startup != 20'd999999);
    assign sample_tick = (divider == 4'd15) && hp_bck && (bit_index == 5'd31);
    always @(posedge sys_clk) begin
        if (startup != 20'd999999) startup <= startup + 1'b1;
        if (divider == 4'd15) begin
            divider <= 4'd0;
            hp_bck <= ~hp_bck;
            // Change data only on falling BCK; DAC samples on rising BCK.
            if (hp_bck) begin
                if (bit_index == 5'd31) begin
                    bit_index <= 5'd0;
                    shift_data <= {pcm, pcm};
                    hp_din <= pcm[15];
                    hp_ws <= 1'b0;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    shift_data <= {shift_data[30:0], 1'b0};
                    hp_din <= shift_data[30];
                    if (bit_index == 5'd15) hp_ws <= 1'b1;
                end
            end
        end else divider <= divider + 1'b1;
    end
endmodule
