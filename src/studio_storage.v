`timescale 1ns/1ps
module studio_storage(input wire clk,sd_miso,output wire sd_clk,sd_cs,sd_mosi,
 input wire save,recall,safe,user_valid,input wire [13:0] count,input wire [15:0] bpm,original_crc,
 input wire [12:0] key_rank,
 output wire busy,output wire [2:0] status,output wire [3:0] error,
 output wire [31:0] generation,output wire [13:0] saved_count,
 output wire [15:0] saved_crc,output wire [12:0] saved_rank,
 output wire export_mode,output wire [12:0] export_address,input wire [23:0] export_data,
 output wire restore_begin,restore_write,restore_commit,output wire [12:0] restore_address,
 output wire [23:0] restore_data,output wire [13:0] restore_count,
 output wire [15:0] restore_bpm,restore_crc,output wire [12:0] restore_rank,
 output wire configuration_busy,
 input wire audio_start,audio_stop,input wire [6:0] audio_seconds,
 output wire audio_busy,output wire [2:0] audio_status,output wire [3:0] audio_error,
 output wire [31:0] audio_generation,audio_samples,output wire [15:0] audio_crc,
 output wire capture_arm,capture_stop,capture_abort,output wire [31:0] capture_limit,consumed,
 input wire [2:0] capture_state,input wire [31:0] produced,input wire [15:0] capture_crc,input wire overflow,
 output wire [15:0] capture_address,input wire [15:0] capture_data,
 input wire client_request,input wire [31:0] client_offset,input wire [7:0] client_index,
 output wire client_ready,output wire [3:0] client_error,output wire [15:0] client_data,
 input wire sd_reinitialize,output wire [63:0] sd_diagnostic,
 input wire native_format,output wire restore_native,
 input wire record_request,input wire [3:0] record_operation,input wire [47:0] record_arguments,
 output wire record_done,output wire [3:0] record_error,output wire [95:0] record_info,
 output wire [15:0] record_word,output wire capture_immediate);
 wire initialized,io_busy,io_done,io_request,io_write,read_valid,mounted,mounting,store_busy;
 wire [3:0] io_error,mount_error,block_error;
 wire [31:0] io_sector;wire [8:0] write_index,read_index;wire [7:0] write_byte,read_byte;
 wire block_request,block_write,block_done;wire [19:0] block_sector;
 wire score_request,score_write,audio_request,audio_write;wire [15:0] score_sector;wire [19:0] audio_sector;wire [7:0] score_byte,audio_byte;
 wire file_extended,record_busy,record_io,record_write,managed_start,managed_active,managed_done,managed_ok,record_selected;
 wire [3:0] record_last_error,writer_error;wire [2:0] writer_status;wire writer_busy;
 wire [19:0] record_sector,managed_base,record_read_base;wire [7:0] record_byte;
 wire [6:0] managed_seconds;
 wire [31:0] managed_generation,record_generation,record_samples,writer_generation,writer_samples;
 wire [15:0] record_crc,writer_crc;
 reg [1:0] owner=0;
 always @(posedge clk)if(score_request)owner<=0;else if(audio_request)owner<=1;else if(record_io)owner<=2;
 assign block_request=score_request || audio_request || record_io;
 assign block_write=score_request?score_write:audio_request?audio_write:record_write;
 assign block_sector=score_request?{4'd0,score_sector}:audio_request?audio_sector:record_sector;
 assign write_byte=owner==2?record_byte:owner==1?audio_byte:score_byte;
 assign configuration_busy=store_busy || (mounting && io_error==0);
 assign busy=configuration_busy || audio_busy;
 sd_spi_block card(clk,sd_miso,sd_clk,sd_cs,sd_mosi,io_request,io_write,io_sector,
  write_index,write_byte,read_valid,read_index,read_byte,initialized,io_busy,io_done,io_error,sd_reinitialize,sd_diagnostic);
 sd_file_volume volume(clk,initialized,io_busy,io_done,io_error,read_valid,read_index,read_byte,
  io_request,io_write,io_sector,block_request,block_write,block_sector,block_done,block_error,mounted,mount_error,mounting,file_extended);
 wire [3:0] effective_error=mount_error!=0?mount_error:(!initialized && io_error!=0)?4'd6:4'd0;
 studio_score_store scores(clk,mounted,effective_error,save && !audio_busy,recall && !audio_busy,safe,user_valid,count,bpm,original_crc,key_rank,
  store_busy,status,error,generation,saved_count,saved_crc,saved_rank,export_mode,export_address,export_data,
  restore_begin,restore_write,restore_commit,restore_address,restore_data,restore_count,restore_bpm,restore_crc,restore_rank,
  score_request,score_write,score_sector,block_done && owner==0,block_error,read_valid && owner==0,read_index,read_byte,write_index,score_byte,native_format,restore_native);
 studio_audio_store audio(clk,mounted,!store_busy && (status==1 || status==3 || status==4),
  (audio_start && !record_busy) || managed_start,audio_stop,managed_active?managed_seconds:audio_seconds,
  writer_busy,writer_status,writer_error,writer_generation,writer_samples,writer_crc,
  capture_arm,capture_stop,capture_abort,capture_limit,consumed,capture_state,produced,capture_crc,overflow,
  capture_address,capture_data,client_request,client_offset,client_index,client_ready,client_error,client_data,
  audio_request,audio_write,audio_sector,block_done && owner==1,block_error,read_valid && owner==1,read_index,read_byte,write_index,audio_byte,
  managed_active,managed_base,managed_generation,managed_done,managed_ok,
  record_selected,record_read_base,record_samples);
 practice_record_store records(clk,mounted,file_extended,!store_busy && !writer_busy && (status==1 || status==3 || status==4),
  audio_start && !record_busy,record_request,record_operation,record_arguments,record_done,record_error,record_info,
  record_busy,record_last_error,managed_start,managed_seconds,managed_active,managed_base,managed_generation,
  writer_busy,writer_status,writer_error,managed_done,managed_ok,produced,capture_crc,
  record_selected,record_read_base,record_generation,record_samples,record_crc,
  client_index,record_word,record_io,record_write,record_sector,block_done && owner==2,block_error,
  read_valid && owner==2,read_index,read_byte,write_index,record_byte);
 assign capture_immediate=managed_active;
 assign audio_busy=writer_busy || record_busy;
 assign audio_status=record_last_error!=0 && !audio_busy ? 3'd4:
  writer_busy?writer_status:record_busy?(managed_active?3'd6:3'd5):record_selected?3'd3:writer_status;
 assign audio_error=record_last_error!=0?record_last_error:writer_error;
 assign audio_generation=managed_active?managed_generation:record_selected?record_generation:writer_generation;
 assign audio_samples=managed_active?produced:(writer_busy && (writer_status==1 || writer_status==2))?produced:
  record_selected?record_samples:writer_samples;
 assign audio_crc=managed_active?capture_crc:record_selected?record_crc:writer_crc;
endmodule
