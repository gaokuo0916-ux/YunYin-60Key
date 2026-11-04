`timescale 1ns / 1ps
// Standard I2S: WS changes one BCLK before MSB. 32 bits/channel,
// signed 16-bit PCM in bits 31:16, zero padding in bits 15:0.
// 50MHz/16 = 3.125MHz BCLK; 64 BCLK/frame = 48828.125Hz.
// Capture phase is identical to the retained PT8211 transmitter: no extra
// audio frame, FIFO, resampling, derived internal clock, or synthesis change.
module i2s_tx (
    input wire sys_clk,
    input wire signed [15:0] pcm,
    output wire frame_tick,
    output reg bclk = 1'b0,
    output reg lrclk = 1'b1,
    output reg dout = 1'b0
);
    reg [2:0] divider = 3'd0;
    reg [5:0] bit_index = 6'd63;
    reg [31:0] shift_data = 32'd0;
    reg signed [15:0] frame_pcm = 16'sd0;

    assign frame_tick = (divider == 3'd7) && bclk && (bit_index == 6'd0);

    always @(posedge sys_clk) begin
        if (divider == 3'd7) begin
            divider <= 3'd0;
            bclk <= ~bclk;
            // Launch WS/data on falling BCLK; receiver samples rising BCLK.
            if (bclk) begin
                bit_index <= bit_index + 1'b1;
                if (bit_index == 6'd63) begin
                    lrclk <= 1'b0;
                    dout <= shift_data[31]; // previous RIGHT word LSB (zero)
                    shift_data <= {shift_data[30:0], 1'b0};
                end else if (bit_index == 6'd31) begin
                    lrclk <= 1'b1;
                    dout <= shift_data[31]; // previous LEFT word LSB (zero)
                    shift_data <= {shift_data[30:0], 1'b0};
                end else if (bit_index == 6'd0) begin
                    frame_pcm <= pcm;
                    dout <= pcm[15];
                    shift_data <= {pcm[14:0], 17'd0};
                end else if (bit_index == 6'd32) begin
                    // Same captured PCM for both channels, even if PCM changes.
                    dout <= frame_pcm[15];
                    shift_data <= {frame_pcm[14:0], 17'd0};
                end else begin
                    dout <= shift_data[31];
                    shift_data <= {shift_data[30:0], 1'b0};
                end
            end
        end else divider <= divider + 1'b1;
    end
endmodule
