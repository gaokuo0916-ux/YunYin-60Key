`timescale 1ns/1ps
// 100 kHz, open-drain I2C, 16-bit register addresses. Reads up to 41 bytes;
// single-byte writes are used only to acknowledge a verified touch report.
// Actual SCL is synchronized and checked, so clock stretching is supported.
module i2c_register_master #(
    parameter integer QUARTER_CLOCKS=125, TIMEOUT_CLOCKS=750000
)(input wire clk,start,read_op,
  input wire [6:0] address,
  input wire [15:0] register_address,
  input wire [5:0] read_length,
  input wire [7:0] write_data,
  inout wire sda,scl,
  output reg busy=0,done=0,error=0,read_valid=0,
  output reg [5:0] read_index=0,
  output reg [7:0] read_data=0);
    reg sda_low=0,scl_low=0;
    assign sda=sda_low?1'b0:1'bz;
    assign scl=scl_low?1'b0:1'bz;
    reg sm=1,ss=1,cm=1,cs=1;
    always @(posedge clk) begin sm<=sda;ss<=sm;cm<=scl;cs<=cm;end
    reg [31:0] quarter=0,timeout_count=0;
    reg [4:0] state=0;
    reg [2:0] bit_index=7,tx_kind=0;
    reg [7:0] tx=0,rx=0,wdata=0;
    reg [6:0] dev=0;
    reg [15:0] regaddr=0;
    reg [5:0] length=1;
    reg reading=0;
    always @(posedge clk) begin
        done<=0;read_valid<=0;
        if(!busy) begin
            quarter<=0;timeout_count<=0;
            if(start) begin
                busy<=1;error<=0;state<=1;tx_kind<=0;bit_index<=7;
                dev<=address;regaddr<=register_address;reading<=read_op;
                length<=(read_length==0 || read_length>41)?6'd1:read_length;
                wdata<=write_data;read_index<=0;sda_low<=0;scl_low<=0;
            end
        end else if(timeout_count==TIMEOUT_CLOCKS-1) begin
            // Release the bus on a disconnected/stuck peripheral. Audio has
            // its own pipeline and never waits for this transaction.
            sda_low<=0;scl_low<=0;busy<=0;error<=1;done<=1;state<=0;
        end else begin
            timeout_count<=timeout_count+1'b1;
            if(quarter==QUARTER_CLOCKS-1) begin
                quarter<=0;
                case(state)
                    1: begin sda_low<=0;scl_low<=0;if(cs && ss) state<=2;end
                    2: begin sda_low<=1;state<=3;end
                    3: begin scl_low<=1;tx<=tx_kind==3?{dev,1'b1}:{dev,1'b0};bit_index<=7;state<=4;end
                    4: begin scl_low<=1;sda_low<=!tx[bit_index];state<=5;end
                    5: begin scl_low<=0;state<=6;end
                    6: if(cs) state<=7;
                    7: begin scl_low<=1;if(bit_index==0) state<=8;
                        else begin bit_index<=bit_index-1'b1;state<=4;end end
                    8: begin sda_low<=0;state<=9;end
                    9: begin scl_low<=0;state<=10;end
                    10: if(cs) begin if(ss) error<=1;state<=11;end
                    11: begin
                        scl_low<=1;
                        if(error) state<=20;
                        else case(tx_kind)
                            0: begin tx_kind<=1;tx<=regaddr[15:8];bit_index<=7;state<=4;end
                            1: begin tx_kind<=2;tx<=regaddr[7:0];bit_index<=7;state<=4;end
                            2: if(reading) begin tx_kind<=3;state<=1;end
                               else begin tx_kind<=4;tx<=wdata;bit_index<=7;state<=4;end
                            3: begin bit_index<=7;rx<=0;state<=12;end
                            default:state<=20;
                        endcase
                    end
                    12: begin sda_low<=0;scl_low<=1;state<=13;end
                    13: begin scl_low<=0;state<=14;end
                    14: if(cs) begin rx[bit_index]<=ss;state<=15;end
                    15: begin scl_low<=1;if(bit_index==0) begin
                        read_data<=rx;read_valid<=1;state<=16;
                    end else begin bit_index<=bit_index-1'b1;state<=12;end end
                    16: begin sda_low<=read_index+1'b1<length;state<=17;end
                    17: begin scl_low<=0;state<=18;end
                    18: if(cs) state<=19;
                    19: begin scl_low<=1;if(read_index+1'b1==length) state<=20;
                        else begin read_index<=read_index+1'b1;bit_index<=7;rx<=0;state<=12;end end
                    20: begin scl_low<=1;sda_low<=1;state<=21;end
                    21: begin scl_low<=0;state<=22;end
                    22: if(cs) state<=23;
                    23: begin sda_low<=0;state<=24;end
                    24: begin busy<=0;done<=1;state<=0;end
                    default:begin state<=20;error<=1;end
                endcase
            end else quarter<=quarter+1'b1;
        end
    end
endmodule
