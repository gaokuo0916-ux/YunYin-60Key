`timescale 1ns / 1ps
module guitar_synth_7 #(parameter integer RUNTIME_ADSR=0)(
    input wire sys_clk,
    input wire sample_tick,
    input wire [6:0] pressed,
    input wire [223:0] phase_steps,
    output reg signed [15:0] pcm=16'sd0,
    input wire [74:0] adsr_coefficients
);
    wire signed [15:0] voice0;
    guitar_voice #(.INITIAL_STEP(32'd23012829),.PITCH_SLEW_STEP(32'd108754),.RUNTIME_ADSR(RUNTIME_ADSR)) c4
        (sys_clk,sample_tick,pressed[0],phase_steps[0 +:32],voice0,adsr_coefficients);
    wire signed [15:0] voice1;
    guitar_voice #(.INITIAL_STEP(32'd25831027),.PITCH_SLEW_STEP(32'd122072),.RUNTIME_ADSR(RUNTIME_ADSR)) d4
        (sys_clk,sample_tick,pressed[1],phase_steps[32 +:32],voice1,adsr_coefficients);
    wire signed [15:0] voice2;
    guitar_voice #(.INITIAL_STEP(32'd28994347),.PITCH_SLEW_STEP(32'd137021),.RUNTIME_ADSR(RUNTIME_ADSR)) e4
        (sys_clk,sample_tick,pressed[2],phase_steps[64 +:32],voice2,adsr_coefficients);
    wire signed [15:0] voice3;
    guitar_voice #(.INITIAL_STEP(32'd30718441),.PITCH_SLEW_STEP(32'd145169),.RUNTIME_ADSR(RUNTIME_ADSR)) f4
        (sys_clk,sample_tick,pressed[3],phase_steps[96 +:32],voice3,adsr_coefficients);
    wire signed [15:0] voice4;
    guitar_voice #(.INITIAL_STEP(32'd34480283),.PITCH_SLEW_STEP(32'd162947),.RUNTIME_ADSR(RUNTIME_ADSR)) g4
        (sys_clk,sample_tick,pressed[4],phase_steps[128 +:32],voice4,adsr_coefficients);
    wire signed [15:0] voice5;
    guitar_voice #(.INITIAL_STEP(32'd38702809),.PITCH_SLEW_STEP(32'd182902),.RUNTIME_ADSR(RUNTIME_ADSR)) a4
        (sys_clk,sample_tick,pressed[5],phase_steps[160 +:32],voice5,adsr_coefficients);
    wire signed [15:0] voice6;
    guitar_voice #(.INITIAL_STEP(32'd43442435),.PITCH_SLEW_STEP(32'd205300),.RUNTIME_ADSR(RUNTIME_ADSR)) b4
        (sys_clk,sample_tick,pressed[6],phase_steps[192 +:32],voice6,adsr_coefficients);
    // Balanced signed adder tree. 20 bits cover seven full-scale voices.
    wire signed [19:0] pair0 = $signed({{4{voice0[15]}},voice0}) +
                                    $signed({{4{voice1[15]}},voice1});
    wire signed [19:0] pair1 = $signed({{4{voice2[15]}},voice2}) +
                                    $signed({{4{voice3[15]}},voice3});
    wire signed [19:0] pair2 = $signed({{4{voice4[15]}},voice4}) +
                                    $signed({{4{voice5[15]}},voice5});
    wire signed [19:0] pair3 = $signed({{4{voice6[15]}},voice6});
    wire signed [19:0] group0 = pair0 + pair1;
    wire signed [19:0] group1 = pair2 + pair3;
    wire signed [19:0] mixed = group0 + group1;
    // Half-volume leaves headroom even with all seven notes held.
    wire signed [19:0] attenuated = mixed >>> 1;
    wire signed [19:0] colored;
    wire color_ready;
    reg [12:0] valid = 13'd0;
    guitar_body_color body_color(sys_clk,valid[12],attenuated,colored,color_ready);
    always @(posedge sys_clk) begin
        valid <= {valid[11:0],sample_tick};
        if (color_ready) begin
            if (colored > 20'sd32767) pcm <= 16'sd32767;
            else if (colored < -20'sd32768) pcm <= -16'sd32768;
            else pcm <= colored[15:0];
        end
    end
endmodule

// Three shared, peak-normalized design body bands inspired by the selected KS audition.
// Parameters are designed, not an identified acoustic-guitar impulse response.
module guitar_body_color(input wire clk,strobe,input wire signed [19:0] dry,
 output reg signed [19:0] colored=0,output wire ready);
 reg [3:0] valid=0;assign ready=valid[3];
 reg signed [19:0] x1=0,x2=0,dry_q=0;
 wire signed [20:0] difference=$signed({dry[19],dry})-$signed({x2[19],x2});
 reg [13:0] quiet_samples=0;
 wire clear_tail=dry==0&&quiet_samples==8191;
 reg signed [26:0] y1[0:2],y2[0:2];
 reg signed [44:0] product_a[0:2],product_b[0:2];
 reg signed [38:0] drive_product[0:2];
 reg signed [45:0] recurrence[0:2];
 wire signed [31:0] next_y[0:2];
 genvar k;
 generate for(k=0;k<3;k=k+1)begin:mode
  localparam signed [17:0] A=k==0?18'sd130750:k==1?18'sd130557:18'sd128160;
  localparam signed [17:0] B=k==0?18'sd65228:k==1?18'sd65074:18'sd63325;
  localparam signed [17:0] G=k==0?18'sd54:k==1?18'sd65:18'sd200;
  initial begin y1[k]=0;y2[k]=0;product_a[k]=0;product_b[k]=0;drive_product[k]=0;recurrence[k]=0;end
  assign next_y[k]=((recurrence[k]+46'sd32768)>>>16)+(drive_product[k]>>>10);
  always @(posedge clk)begin
   if(strobe)begin product_a[k]<=clear_tail?45'sd0:y1[k]*A;product_b[k]<=clear_tail?45'sd0:y2[k]*B;drive_product[k]<=clear_tail?39'sd0:difference*G;end
   if(valid[0])recurrence[k]<=$signed({product_a[k][44],product_a[k]})-$signed({product_b[k][44],product_b[k]});
   if(valid[1])begin
    y2[k]<=y1[k];
    if(next_y[k]>32'sd67108863)y1[k]<=27'sd67108863;
    else if(next_y[k]< -32'sd67108864)y1[k]<=-27'sd67108864;
    else y1[k]<=next_y[k][26:0];
   end
  end
 end endgenerate
 wire signed [22:0] sum=$signed({{3{dry_q[19]}},dry_q})+
  ($signed({{3{y1[0][26]}},y1[0]})>>>6)+($signed({{3{y1[1][26]}},y1[1]})>>>6)+($signed({{3{y1[2][26]}},y1[2]})>>>6);
 always @(posedge clk)begin
  valid<={valid[2:0],strobe};
  if(strobe)begin x2<=x1;x1<=dry;dry_q<=dry;if(dry!=0)quiet_samples<=0;else if(quiet_samples<8191)quiet_samples<=quiet_samples+1'b1;end
  if(valid[2])begin
   if(sum>23'sd524287)colored<=20'sd524287;
   else if(sum< -23'sd524288)colored<=-20'sd524288;
   else colored<=sum[19:0];
  end
 end
endmodule
