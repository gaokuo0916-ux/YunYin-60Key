`timescale 1ns/1ps
module lcd_panel_digit(input wire [3:0] digit,output reg [7:0] code);
always @(*) case(digit)
4'd0:code=8'd45;
4'd1:code=8'd51;
4'd2:code=8'd52;
4'd3:code=8'd53;
4'd4:code=8'd54;
4'd5:code=8'd55;
4'd6:code=8'd56;
4'd7:code=8'd57;
4'd8:code=8'd58;
4'd9:code=8'd59;
default:code=0;endcase endmodule
