`timescale 1ns/1ps
// Read actual FPGA I/O pads during SD initialization. This is digital readback,
// not a voltage measurement and not proof of contact at the card socket.
module sd_pin_trace(
 input wire clk,reinitialize,enable,waiting_response,
 input wire drive_clk,drive_cs,drive_mosi,input wire miso,
 inout wire pad_clk,pad_cs,pad_mosi,
 output wire [31:0] snapshot);
 wire [2:0] pad_input;
 IOBUF clock_io(.O(pad_input[0]),.IO(pad_clk),.I(drive_clk),.OEN(1'b0));
 IOBUF select_io(.O(pad_input[1]),.IO(pad_cs),.I(drive_cs),.OEN(1'b0));
 IOBUF data_io(.O(pad_input[2]),.IO(pad_mosi),.I(drive_mosi),.OEN(1'b0));
 wire [2:0] drive={drive_mosi,drive_cs,drive_clk};
 reg [2:0] pad_meta=3'b110,pad_sync=3'b110,last_drive=3'b110;
 reg miso_meta=1,miso_sync=1,last_clock=0,waiting_meta=0,waiting_sync=0;
 reg [4:0] stable_clock=0,stable_select=0,stable_data=0;
 reg [2:0] mismatch=0;reg saw_miso_low=0;
 reg [11:0] rising_edges=0;reg [15:0] generation=1;
 // SDINFO extra field when CMD0 has not completed:
 // [31:16] accepted manual-retry generation (boot=1)
 // [15:13] sticky mismatch: CLK, CS, MOSI, checked after 320ns stable
 // [12] MISO was low while selected and awaiting a response
 // [11:0] observed pad-clock rising edges, saturating, per manual round
 assign snapshot={generation,mismatch[0],mismatch[1],mismatch[2],saw_miso_low,rising_edges};
 always @(posedge clk)begin
  pad_meta<=pad_input;pad_sync<=pad_meta;
  miso_meta<=miso;miso_sync<=miso_meta;
  waiting_meta<=waiting_response;waiting_sync<=waiting_meta;
  last_clock<=pad_sync[0];last_drive<=drive;
  if(last_drive[0]!=drive[0])stable_clock<=0;else if(stable_clock<16)stable_clock<=stable_clock+1'b1;
  if(last_drive[1]!=drive[1])stable_select<=0;else if(stable_select<16)stable_select<=stable_select+1'b1;
  if(last_drive[2]!=drive[2])stable_data<=0;else if(stable_data<16)stable_data<=stable_data+1'b1;
  if(reinitialize)begin
   generation<=generation==16'hffff ? 16'd1 : generation+1'b1;
   rising_edges<=0;mismatch<=0;saw_miso_low<=0;
   stable_clock<=0;stable_select<=0;stable_data<=0;
  end else if(enable)begin
   if(pad_sync[0] && !last_clock && rising_edges!=12'hfff)rising_edges<=rising_edges+1'b1;
   if(stable_clock==16 && last_drive[0]==drive_clk && pad_sync[0]!=drive_clk)mismatch[0]<=1;
   if(stable_select==16 && last_drive[1]==drive_cs && pad_sync[1]!=drive_cs)mismatch[1]<=1;
   if(stable_data==16 && last_drive[2]==drive_mosi && pad_sync[2]!=drive_mosi)mismatch[2]<=1;
   if(waiting_sync && !pad_sync[1] && !miso_sync)saw_miso_low<=1;
  end
 end
endmodule
