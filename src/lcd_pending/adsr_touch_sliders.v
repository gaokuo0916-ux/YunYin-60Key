`timescale 1ns/1ps
// Controller-independent touch interface. One designated primary touch only.
// No I2C address or coordinate byte order is guessed in this module.
// 800x480 design: tracks x=128..640, A/D/S/R row centers 253/302/351/400.
module adsr_touch_sliders(
    input wire clk,touch_valid,touch_down,
    input wire [11:0] touch_x,touch_y,
    output reg edit_valid=0,
    output reg [1:0] parameter_id=0,
    output reg [5:0] value_index=0
);
    reg held=0,locked=0;
    reg [1:0] locked_parameter=0;
    wire in_track=touch_x>=128 && touch_x<=640;
    wire hit_a=touch_y>=235 && touch_y<=271;
    wire hit_d=touch_y>=284 && touch_y<=320;
    wire hit_s=touch_y>=333 && touch_y<=369;
    wire hit_r=touch_y>=382 && touch_y<=418;
    wire hit=in_track && (hit_a || hit_d || hit_s || hit_r);
    wire [1:0] hit_id=hit_a?2'd0:hit_d?2'd1:hit_s?2'd2:2'd3;
    wire [11:0] dx=touch_x<=128?12'd0:touch_x>=640?12'd511:touch_x-12'd128;
    wire [5:0] index=dx[8:3];
    always @(posedge clk) begin
        edit_valid<=0;
        if(touch_valid) begin
            if(!touch_down) begin held<=0;locked<=0;end
            else if(!held) begin
                held<=1;locked<=hit;locked_parameter<=hit_id;
                if(hit) begin parameter_id<=hit_id;value_index<=index;edit_valid<=1;end
            end else if(locked) begin
                parameter_id<=locked_parameter;value_index<=index;edit_valid<=1;
            end
        end
    end
endmodule
