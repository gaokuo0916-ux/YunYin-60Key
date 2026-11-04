`timescale 1ns/1ps
// Dedicated 100kHz open-drain bus. TI SBAS181C command byte is
// {SD,C2,C1,C0,PD1,PD0,X,X}. In single-ended mode TI Table II maps
// C2:C1:C0 to CH0,2,4,6,1,3,5,7, so C2=channel[0].
// SD=1, PD=01 (external VREF); samples remain in physical CH0..CH7 order.
// Commit only a complete eight-channel scan; failed scans never publish stale
// partial controls. A watchdog disconnects the panel without stopping audio.
module ads7828_panel #(parameter integer QUARTER=125,TIMEOUT=750000,
 RETRY=500000,CONVERSION_WAIT=4000,parameter [6:0] ADDRESS=7'h48,parameter integer AUTO_ADDRESS=1,
 parameter [1:0] POWER_MODE=2'b01)(
 input wire clk,inout wire sda,scl,output reg valid=0,online=0,
 output reg [95:0] samples=0,output reg [3:0] error_code=0);
 localparam CW=$clog2(QUARTER+1),TW=$clog2(TIMEOUT+1),RW=$clog2(RETRY+1),VW=$clog2(CONVERSION_WAIT+1);
 reg sda_low=0,scl_low=0;assign sda=sda_low?1'b0:1'bz;assign scl=scl_low?1'b0:1'bz;
 reg sm=1,ss=1,cm=1,cs=1;always @(posedge clk)begin sm<=sda;ss<=sm;cm<=scl;cs<=cm;end
 reg [CW-1:0] quarter=0;reg [TW-1:0] timeout_count=0;
 reg [RW-1:0] retry_count=0;reg [VW-1:0] wait_count=0;
 reg [5:0] state=0;reg [2:0] bit_index=7,channel=0;
 reg [1:0] tx_kind=0;reg [7:0] tx=0,rx=0;reg [3:0] hi=0;
 reg second_byte=0;reg [95:0] pending=0;
 reg [3:0] recovery_clocks=0;
 // Probe only the four ADS7828 strap addresses; lock after a full good scan.
 reg [6:0] active_address=ADDRESS;reg address_failed=0;
 wire [7:0] command={1'b1,channel[0],channel[2:1],POWER_MODE,2'b00};
 always @(posedge clk)begin
  valid<=0;
  if(state==0)begin
   sda_low<=0;scl_low<=0;quarter<=0;timeout_count<=0;
   if(retry_count==RETRY-1)begin retry_count<=0;state<=1;channel<=0;pending<=0;tx_kind<=0;end
   else retry_count<=retry_count+1'b1;
  end else if(timeout_count==TIMEOUT-1)begin
   state<=0;sda_low<=0;scl_low<=0;online<=0;error_code<=2;timeout_count<=0;
  end else begin
   timeout_count<=timeout_count+1'b1;
   if(state==25)begin
    if(wait_count==CONVERSION_WAIT-1)begin wait_count<=0;state<=1;end else wait_count<=wait_count+1'b1;
   end else if(quarter==QUARTER-1)begin
    quarter<=0;
    case(state)
     1:begin sda_low<=0;scl_low<=0;
      if(cs && ss)state<=31;
      else if(cs && ss===1'b0)begin
       // FPGA may restart midway through an ADC byte while the ADC remains
       // powered. Nine released-data clocks and STOP clear that stale read.
       recovery_clocks<=0;state<=26;online<=0;error_code<=2;
      end
     end
     31:state<=2; // >=2 quarters repeated-START setup at standard speed.
     2:begin sda_low<=1;state<=32;end
     32:state<=3; // >=2 quarters START hold before pulling SCL down.
     3:begin scl_low<=1;tx<=tx_kind==2?{active_address,1'b1}:{active_address,1'b0};bit_index<=7;state<=4;end
     4:begin scl_low<=1;sda_low<=!tx[bit_index];state<=5;end
     5:begin scl_low<=0;state<=6;end
     6:if(cs)state<=7;
     7:begin scl_low<=1;if(bit_index==0)state<=8;else begin bit_index<=bit_index-1'b1;state<=4;end end
     8:begin sda_low<=0;state<=9;end
     9:begin scl_low<=0;state<=10;end
     10:if(cs)begin if(ss!==1'b0)begin error_code<=1;online<=0;address_failed<=(tx_kind!=1);state<=20;end else state<=11;end
     11:begin scl_low<=1;
      case(tx_kind)
       0:begin tx_kind<=1;tx<=command;bit_index<=7;state<=4;end
       1:begin tx_kind<=2;state<=25;wait_count<=0;end
       2:begin bit_index<=7;rx<=0;second_byte<=0;state<=12;end
      endcase
     end
     12:begin sda_low<=0;scl_low<=1;state<=13;end
     13:begin scl_low<=0;state<=14;end
     14:if(cs)begin rx[bit_index]<=ss;state<=15;end
     15:begin scl_low<=1;
      if(bit_index==0)begin
       if(!second_byte)hi<=rx[3:0];else pending[channel*12+:12]<={hi,rx};
       state<=16;
      end else begin bit_index<=bit_index-1'b1;state<=12;end
     end
     16:begin sda_low<=!second_byte;state<=17;end
     17:begin scl_low<=0;state<=18;end
     18:if(cs)state<=19;
     19:begin scl_low<=1;
      if(!second_byte)begin second_byte<=1;bit_index<=7;rx<=0;state<=12;end
      else begin
       // Repeated START into the next write conversion (TI Fig.3 note 1).
       timeout_count<=0;tx_kind<=0;state<=1;
       if(channel==7)begin samples<=pending;valid<=1;online<=1;error_code<=0;channel<=0;end
       else channel<=channel+1'b1;
      end
     end
     // STOP only after a NACK. Never publish an incomplete scan.
     20:begin scl_low<=1;sda_low<=1;state<=21;end
     21:begin scl_low<=0;state<=22;end
     22:if(cs)state<=23;
     23:begin sda_low<=0;state<=24;end
     24:begin state<=0;channel<=0;
      if(AUTO_ADDRESS && address_failed)active_address<={ADDRESS[6:2],active_address[1:0]+2'd1};
      address_failed<=0;
     end
     26:begin scl_low<=1;sda_low<=0;state<=27;end
     27:state<=28;
     28:begin scl_low<=0;state<=29;end
     29:if(cs)state<=30;
     30:begin scl_low<=1;
      if(recovery_clocks==8)state<=20;
      else begin recovery_clocks<=recovery_clocks+1'b1;state<=26;end
     end
     default:begin state<=0;online<=0;error_code<=3;end
    endcase
   end else quarter<=quarter+1'b1;
  end
 end
endmodule
