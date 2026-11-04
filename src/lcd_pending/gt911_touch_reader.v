`timescale 1ns/1ps
// GT911 only: verify product ID and 800x480 coordinate range before report ACKs.
// No panel-specific configuration blob or Flash write is sent. An unknown
// legacy GT615 device is reported unsupported, not operated as a GT911.
// Single-finger UI: additional contacts cancel the gesture until all lift.
module gt911_touch_reader #(
    parameter integer RESET_CLOCKS=1000000,STRAP_CLOCKS=2500000,
        BOOT_CLOCKS=9000000,POLL_CLOCKS=250000,RETRY_CLOCKS=50000000,
        I2C_QUARTER_CLOCKS=125
)(input wire clk,
  inout wire sda,scl,int_pin,
  output wire reset_n,
  output reg touch_valid=0,touch_down=0,
  output reg [11:0] touch_x=0,touch_y=0,
  output reg [1:0] status=0,
  output reg [23:0] product_id=0);
    reg [31:0] boot_count=0,wait_count=0;
    reg [3:0] state=0;
    assign reset_n=boot_count>=RESET_CLOCKS;
    assign int_pin=boot_count<RESET_CLOCKS+STRAP_CLOCKS?1'b0:1'bz;
    reg start=0,read_op=1;
    reg [6:0] address=7'h5d;
    reg [15:0] regaddr=16'h8140;
    reg [5:0] length=10;
    wire busy,done,error,rv;
    wire [5:0] ri;
    wire [7:0] rd;
    reg [7:0] report[0:40];
    reg blocked=0;
    reg [7:0] primary_id=0;
    integer i;
    initial for(i=0;i<41;i=i+1) report[i]=0;
    i2c_register_master #(.QUARTER_CLOCKS(I2C_QUARTER_CLOCKS)) master(
        clk,start,read_op,address,regaddr,length,8'd0,sda,scl,
        busy,done,error,rv,ri,rd);
    wire [15:0] x_now={report[3],report[2]},y_now={report[5],report[4]};
    always @(posedge clk) begin
        start<=0;touch_valid<=0;
        if(rv) report[ri]<=rd;
        if(state==0) begin
            if(boot_count==RESET_CLOCKS+STRAP_CLOCKS+BOOT_CLOCKS-1) begin state<=1;wait_count<=0;end
            else boot_count<=boot_count+1'b1;
        end else case(state)
            1:if(!busy) begin read_op<=1;regaddr<=16'h8140;length<=10;start<=1;state<=2;end
            2:if(done) begin
                product_id<={report[0],report[1],report[2]};wait_count<=0;
                if(error) begin status<=1;state<=7;end
                else if(report[0]!=8'h39 || report[1]!=8'h31 || report[2]!=8'h31) begin status<=3;state<=8;end
                else if({report[7],report[6]}!=800 || {report[9],report[8]}!=480) begin status<=3;state<=8;end
                else begin status<=2;state<=3;end
            end
            3:if(wait_count==POLL_CLOCKS-1) begin
                if(!busy) begin read_op<=1;regaddr<=16'h814e;length<=41;start<=1;state<=4;wait_count<=0;end
            end else wait_count<=wait_count+1'b1;
            4:if(done) begin
                if(error) begin
                    status<=1;state<=7;wait_count<=0;
                    touch_valid<=touch_down;touch_down<=0;blocked<=0;
                end else if(!report[0][7]) state<=3; // No new report preserves a stationary hold.
                else begin
                    read_op<=0;regaddr<=16'h814e;length<=1;start<=1;state<=5;
                    if(report[0][3:0]==0) begin touch_valid<=1;touch_down<=0;blocked<=0;end
                    else if(report[0][3:0]!=1 || x_now>=800 || y_now>=480 ||
                            (touch_down && primary_id!=report[1])) begin
                        touch_valid<=1;touch_down<=0;blocked<=1;
                    end else if(!blocked) begin
                        touch_valid<=1;touch_down<=1;touch_x<=x_now[11:0];touch_y<=y_now[11:0];primary_id<=report[1];
                    end
                end
            end
            5:if(done) begin
                if(error) begin status<=1;state<=7;wait_count<=0;touch_valid<=touch_down;touch_down<=0;blocked<=0;end
                else state<=3;
            end
            7:if(wait_count==RETRY_CLOCKS-1) begin address<=address==7'h5d ? 7'h14 : 7'h5d;state<=1;wait_count<=0;end
                else wait_count<=wait_count+1'b1;
            8:if(wait_count==RETRY_CLOCKS-1) begin state<=1;wait_count<=0;end
                else wait_count<=wait_count+1'b1;
            default:state<=0;
        endcase
    end
endmodule
