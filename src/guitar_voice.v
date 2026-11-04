`timescale 1ns / 1ps
// Warm plucked acoustic-guitar style, generated in real time.
// Six live harmonics with separate low/mid/high damping and a brief pluck.
// Design voicing, not a measured guitar or stored recording.
module guitar_voice #(
    parameter [31:0] INITIAL_STEP=32'd23012829,
    parameter [31:0] PITCH_SLEW_STEP=32'd108770,
    parameter integer RUNTIME_ADSR=0
)(
    input wire sys_clk,
    input wire sample_tick,
    input wire key_pressed,
    input wire [31:0] phase_step,
    output reg signed [15:0] pcm=16'sd0,
    input wire [74:0] adsr_coefficients
);
    reg [31:0] phase=32'd0;
    reg [31:0] current_step=INITIAL_STEP;
    reg was_pressed=1'b0;
    // A long requested R must not be shortened by the fixed string damping.
    // Latch this choice at note-off; the voiced 165ms default retains natural string damping.
    reg hold_release_damping=1'b0;
    reg [11:0] valid=12'd0;
    wire [15:0] amplitude;
    wire [2:0] envelope_state;
    generate if(RUNTIME_ADSR) begin: adjustable
        adsr_runtime u_adsr(sys_clk,sample_tick,key_pressed,
            adsr_coefficients[74:57],adsr_coefficients[56:39],
            adsr_coefficients[38:15],adsr_coefficients[14:0],amplitude,envelope_state);
    end else begin: fixed_envelope
        adsr_envelope u_adsr(sys_clk,sample_tick,key_pressed,amplitude,envelope_state);
    end endgenerate
    // Q8 gains: peak=32768<<8. The string fades while the key remains down.
    // Model e-folding times at 50MHz/1024: low 1.34s, mid 336ms, high 84ms.
    reg [23:0] string_gain=24'd0, middle_gain=24'd0, treble_gain=24'd0;
    wire [23:0] string_loss=(string_gain>>16)==0?24'd1:(string_gain>>16);
    wire [23:0] middle_loss=(middle_gain>>14)==0?24'd1:(middle_gain>>14);
    wire [23:0] treble_loss=(treble_gain>>12)==0?24'd1:(treble_gain>>12);
    reg [31:0] ring_product=32'd0, middle_product=32'd0, treble_product=32'd0;
    wire [15:0] body_amplitude=ring_product[30:15];
    wire [15:0] middle_amplitude=middle_product[30:15];
    wire [15:0] treble_amplitude=treble_product[30:15];
    // Quiet, low-pass excitation for the first 96 samples (~1.97ms) only.
    // The noise cannot sustain a note; its stepped window falls before cutoff.
    reg [22:0] pluck_random=(INITIAL_STEP[22:0]^23'h6a3d51);
    reg signed [16:0] pluck_noise=0;
    reg [6:0] pluck_left=0;
    wire signed [17:0] noise_delta=$signed({{2{pluck_random[15]}},pluck_random[15:0]})-
                                  $signed({pluck_noise[16],pluck_noise});
    wire signed [18:0] pluck_wave=pluck_left==0?19'sd0:
        ($signed({{2{pluck_noise[16]}},pluck_noise})>>>
         (pluck_left>64?3:pluck_left>32?4:5));
    // One multiplier serves two spectral gains before the output stage.
    // body_amplitude is settled by valid[2]; consumers use valid[5].
    reg [31:0] spectral_product=0;
    wire [15:0] spectral_gain=valid[2]?middle_gain[23:8]:treble_gain[23:8];
    // Separate clocked products keep both gain stages off one timing path.
    always @(posedge sys_clk) begin
        ring_product<=amplitude*string_gain[23:8];
        spectral_product<=body_amplitude*spectral_gain;
        if(valid[3]) middle_product<=spectral_product;
        if(valid[4]) treble_product<=spectral_product;
        valid<={valid[10:0],sample_tick};
        if(sample_tick) begin
            was_pressed<=key_pressed;
            pluck_random<={pluck_random[21:0],pluck_random[22]^pluck_random[17]};
            pluck_noise<=pluck_noise+(noise_delta>>>2);
            if(pluck_left!=0) pluck_left<=pluck_left-1'b1;
            phase<=phase+current_step; // Never reset phase for bend/retrigger.
            if(key_pressed && !was_pressed) begin
                hold_release_damping<=1'b0;
                current_step<=phase_step;
                string_gain<=24'd8388608;
                middle_gain<=24'd8388608;
                treble_gain<=24'd8388608;
                pluck_left<=7'd96;
            end else begin
                if(!key_pressed && was_pressed)
                    hold_release_damping<=RUNTIME_ADSR && adsr_coefficients[14:0]<15'd2083;
                if(current_step<phase_step)
                    current_step<=((phase_step-current_step)<=PITCH_SLEW_STEP)?phase_step:(current_step+PITCH_SLEW_STEP);
                else if(current_step>phase_step)
                    current_step<=((current_step-phase_step)<=PITCH_SLEW_STEP)?phase_step:(current_step-PITCH_SLEW_STEP);
                if(envelope_state==0) begin string_gain<=0; middle_gain<=0; treble_gain<=0; pluck_left<=0; end
                else if(!(envelope_state==4 && hold_release_damping)) begin
                    string_gain<=(string_gain<=string_loss)?24'd0:(string_gain-string_loss);
                    if(envelope_state!=1) begin
                        middle_gain<=(middle_gain<=middle_loss)?24'd0:(middle_gain-middle_loss);
                        treble_gain<=(treble_gain<=treble_loss)?24'd0:(treble_gain-treble_loss);
                    end
                end
            end
        end
    end

    function [15:0] sine;
        input [7:0] angle;
        reg [6:0] index;
        reg signed [15:0] quarter;
        begin
            index = angle[6] ? (7'd64 - {1'b0, angle[5:0]}) :
                               {1'b0, angle[5:0]};
            case (index)
                7'd0: quarter = 16'sd0;
                7'd1: quarter = 16'sd804;
                7'd2: quarter = 16'sd1608;
                7'd3: quarter = 16'sd2410;
                7'd4: quarter = 16'sd3212;
                7'd5: quarter = 16'sd4011;
                7'd6: quarter = 16'sd4808;
                7'd7: quarter = 16'sd5602;
                7'd8: quarter = 16'sd6393;
                7'd9: quarter = 16'sd7179;
                7'd10: quarter = 16'sd7962;
                7'd11: quarter = 16'sd8739;
                7'd12: quarter = 16'sd9512;
                7'd13: quarter = 16'sd10278;
                7'd14: quarter = 16'sd11039;
                7'd15: quarter = 16'sd11793;
                7'd16: quarter = 16'sd12539;
                7'd17: quarter = 16'sd13279;
                7'd18: quarter = 16'sd14010;
                7'd19: quarter = 16'sd14732;
                7'd20: quarter = 16'sd15446;
                7'd21: quarter = 16'sd16151;
                7'd22: quarter = 16'sd16846;
                7'd23: quarter = 16'sd17530;
                7'd24: quarter = 16'sd18204;
                7'd25: quarter = 16'sd18868;
                7'd26: quarter = 16'sd19519;
                7'd27: quarter = 16'sd20159;
                7'd28: quarter = 16'sd20787;
                7'd29: quarter = 16'sd21403;
                7'd30: quarter = 16'sd22005;
                7'd31: quarter = 16'sd22594;
                7'd32: quarter = 16'sd23170;
                7'd33: quarter = 16'sd23731;
                7'd34: quarter = 16'sd24279;
                7'd35: quarter = 16'sd24811;
                7'd36: quarter = 16'sd25329;
                7'd37: quarter = 16'sd25832;
                7'd38: quarter = 16'sd26319;
                7'd39: quarter = 16'sd26790;
                7'd40: quarter = 16'sd27245;
                7'd41: quarter = 16'sd27683;
                7'd42: quarter = 16'sd28105;
                7'd43: quarter = 16'sd28510;
                7'd44: quarter = 16'sd28898;
                7'd45: quarter = 16'sd29268;
                7'd46: quarter = 16'sd29621;
                7'd47: quarter = 16'sd29956;
                7'd48: quarter = 16'sd30273;
                7'd49: quarter = 16'sd30571;
                7'd50: quarter = 16'sd30852;
                7'd51: quarter = 16'sd31113;
                7'd52: quarter = 16'sd31356;
                7'd53: quarter = 16'sd31580;
                7'd54: quarter = 16'sd31785;
                7'd55: quarter = 16'sd31971;
                7'd56: quarter = 16'sd32137;
                7'd57: quarter = 16'sd32285;
                7'd58: quarter = 16'sd32412;
                7'd59: quarter = 16'sd32521;
                7'd60: quarter = 16'sd32609;
                7'd61: quarter = 16'sd32678;
                7'd62: quarter = 16'sd32728;
                7'd63: quarter = 16'sd32757;
                7'd64: quarter = 16'sd32767;
                default: quarter = 16'sd0;
            endcase
            sine = angle[7] ? -quarter : quarter;
        end
    endfunction

    wire [31:0] phases[0:5];
    assign phases[0]=phase;
    assign phases[1]={phase[30:0],1'b0};
    assign phases[2]=phase+{phase[30:0],1'b0};
    assign phases[3]={phase[29:0],2'b0};
    assign phases[4]=phase+{phase[29:0],2'b0};
    assign phases[5]={phases[2][30:0],1'b0};
    // Six harmonic lookups/interpolations share one pipelined multiplier.
    // All six waves finish by clock 9 after tick, before the body mix.
    reg signed [16:0] waves[0:5];
    reg issuing=0;reg [2:0] issue=0,tag0=0,tag1=0,tag2=0,pv=0;
    reg [15:0] lookup=0;
    reg signed [15:0] base1=0,base2=0;
    reg signed [16:0] delta1=0;
    reg [7:0] fraction1=0;
    reg signed [25:0] interpolation2=0;
    wire signed [15:0] at0=sine(lookup[15:8]);
    wire signed [15:0] at1=sine(lookup[15:8]+8'd1);
    integer h;
    initial for(h=0;h<6;h=h+1)waves[h]=0;
    always @(posedge sys_clk) begin
        pv<={pv[1:0],issuing};
        if(sample_tick)begin issue<=0;issuing<=1;end
        else if(issuing)begin
            lookup<=phases[issue][31:16];tag0<=issue;
            if(issue==5)issuing<=0;else issue<=issue+1'b1;
        end
        if(pv[0])begin
            base1<=at0;delta1<=$signed({at1[15],at1})-$signed({at0[15],at0});
            fraction1<=lookup[7:0];tag1<=tag0;
        end
        if(pv[1])begin
            base2<=base1;interpolation2<=delta1*$signed({1'b0,fraction1});tag2<=tag1;
        end
        if(pv[2])waves[tag2]<=$signed({base2[15],base2})+(interpolation2>>>8);
    end
    reg signed [18:0] body_wave=19'sd0, middle_wave=19'sd0, treble_wave=19'sd0;
    reg signed [35:0] body_product=36'sd0, mid_product=36'sd0, bright_product=36'sd0;
    wire signed [36:0] mixed=($signed({body_product[35],body_product})>>>18)+
                            ($signed({mid_product[35],mid_product})>>>18)+
                            ($signed({bright_product[35],bright_product})>>>18);
    always @(posedge sys_clk) begin
        if(valid[9]) begin
            // A little H2 remains with the fundamental; the other partials
            // decay independently rather than keeping one fixed vowel shape.
            body_wave<=$signed({{2{waves[0][16]}},waves[0]})+
                       ($signed({{2{waves[1][16]}},waves[1]})>>>4);
            middle_wave<=($signed({{2{waves[1][16]}},waves[1]})>>>2)+
                         ($signed({{2{waves[1][16]}},waves[1]})>>>3)+
                         ($signed({{2{waves[2][16]}},waves[2]})>>>3)+
                         ($signed({{2{waves[2][16]}},waves[2]})>>>4);
            treble_wave<=($signed({{2{waves[3][16]}},waves[3]})>>>3)+
                         ($signed({{2{waves[4][16]}},waves[4]})>>>4)+
                         ($signed({{2{waves[5][16]}},waves[5]})>>>5)+pluck_wave;
        end
        if(valid[10]) begin
            body_product<=body_wave*$signed({1'b0,body_amplitude});
            mid_product<=middle_wave*$signed({1'b0,middle_amplitude});
            bright_product<=treble_wave*$signed({1'b0,treble_amplitude});
        end
        if(valid[11]) pcm<=mixed[15:0];
    end
endmodule
