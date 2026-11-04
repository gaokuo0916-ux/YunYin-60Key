`timescale 1ns/1ps
// Board K0/KEY0 is active low. One cycle per debounced press (2 ms).
// New notes take the selected timbre; held notes keep their original timbre.
module timbre_select #(
    parameter integer DEBOUNCE_CYCLES=100000
)(input wire sys_clk,input wire key0_n,input wire [6:0] note_gate,
  output wire selected_piano,output wire [6:0] piano_gate,guitar_gate,
  output reg [1:0] selected_timbre=2'd0,output wire [6:0] accordion_gate,
  input wire remote_valid,input wire [1:0] remote_timbre);
    reg meta=1'b1,sync=1'b1,stable=1'b1;
    reg [16:0] count=17'd0;
    reg [6:0] previous=0;
    reg [1:0] voice_timbre[0:6];
    wire [6:0] note_rise=note_gate&~previous;
    assign selected_piano=selected_timbre==2'd0;
    genvar n;
    generate for(n=0;n<7;n=n+1) begin: route
        wire [1:0] effective=note_rise[n]?selected_timbre:voice_timbre[n];
        assign piano_gate[n]=note_gate[n] && effective==2'd0;
        assign guitar_gate[n]=note_gate[n] && effective==2'd1;
        assign accordion_gate[n]=note_gate[n] && effective==2'd2;
    end endgenerate
    integer i;
    initial for(i=0;i<7;i=i+1) voice_timbre[i]=2'd0;
    always @(posedge sys_clk) begin
        meta<=key0_n; sync<=meta;
        if(sync==stable) count<=0;
        else if(count==DEBOUNCE_CYCLES-1) begin
            stable<=sync; count<=0;
            if(!sync) selected_timbre <= (selected_timbre == 2'd2) ? 2'd0 : selected_timbre + 1'b1;
        end else count<=count+1'b1;
        // A valid phone/screen request takes priority over a simultaneous K0.
        // An unsupported ID never mutes or changes a sounding note.
        if(remote_valid && remote_timbre<2'd3) selected_timbre<=remote_timbre;
        previous<=note_gate;
        for(i=0;i<7;i=i+1) if(note_rise[i]) voice_timbre[i]<=selected_timbre;
    end
endmodule
