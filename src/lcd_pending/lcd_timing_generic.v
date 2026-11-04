`timescale 1ns/1ps
// Counts pixels on a clock enable. Porch/pulse/polarity values come from the
// identified panel profile. All-zero profile deliberately produces no scan.
module lcd_timing_generic #(
    parameter integer H_ACTIVE=800,V_ACTIVE=480,
    parameter integer H_SYNC=0,H_BACK=0,H_FRONT=0,
    parameter integer V_SYNC=0,V_BACK=0,V_FRONT=0,
    parameter integer HS_ACTIVE_HIGH=0,VS_ACTIVE_HIGH=0,
    parameter integer PROFILE_CONFIRMED=0
)(input wire clk,pixel_ce,reset,
  output wire hs,vs,de,frame_start,
  output wire [11:0] x,y);
    localparam integer HT=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
    localparam integer VT=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
    localparam integer H0=H_SYNC+H_BACK,V0=V_SYNC+V_BACK;
    reg [11:0] hc=0,vc=0;
    wire active=PROFILE_CONFIRMED && hc>=H0 && hc<H0+H_ACTIVE
               && vc>=V0 && vc<V0+V_ACTIVE;
    assign de=active;
    assign hs=PROFILE_CONFIRMED?((hc<H_SYNC)==HS_ACTIVE_HIGH):1'b0;
    assign vs=PROFILE_CONFIRMED?((vc<V_SYNC)==VS_ACTIVE_HIGH):1'b0;
    assign x=active?hc-H0:12'd0;
    assign y=active?vc-V0:12'd0;
    assign frame_start=PROFILE_CONFIRMED && pixel_ce && hc==0 && vc==0;
    always @(posedge clk) begin
        if(reset || !PROFILE_CONFIRMED) begin hc<=0;vc<=0;end
        else if(pixel_ce) begin
            if(hc==HT-1) begin hc<=0;vc<=vc==VT-1?12'd0:vc+1'b1;end
            else hc<=hc+1'b1;
        end
    end
endmodule
