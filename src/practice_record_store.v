`timescale 1ns/1ps
// One 512-byte page, no in-FPGA directory array. Body verification precedes
// the alternating CRC-protected directory commit. No committed slot overwrite.
module practice_record_store(
 input wire clk,mounted,extended_ready,allowed,legacy_start,
 input wire request,input wire [3:0] operation,input wire [47:0] arguments,
 output reg done=0,output reg [3:0] error=0,output reg [95:0] info=0,
 output reg busy=0,output reg [3:0] last_error=0,
 output reg writer_start=0,output reg [6:0] writer_seconds=120,
 output reg managed_active=0,output reg [19:0] managed_base=0,output reg [31:0] managed_generation=0,
 input wire writer_busy,input wire [2:0] writer_status,input wire [3:0] writer_error,
 input wire writer_done,writer_ok,input wire [31:0] produced,input wire [15:0] capture_crc,
 output reg selected=0,output reg [19:0] selected_base=0,
 output reg [31:0] selected_generation=0,selected_samples=0,output reg [15:0] selected_crc=0,
 input wire [7:0] metadata_index,output wire [15:0] metadata_word,
 output reg block_request=0,block_write=0,output reg [19:0] block_sector=0,
 input wire block_done,input wire [3:0] block_error,input wire read_valid,
 input wire [8:0] read_index,input wire [7:0] read_byte,
 input wire [8:0] write_index,output reg [7:0] write_byte=0);
 localparam IDLE=0,CLEAR=1,PUT=2,RESP=3,FIRST=4,SECOND=5,PICK=6,LOAD=7,
  BASE_INIT=8,BASE_STEP=9,LEGACY=10,HEADER=11,CRC_INIT=12,CRC_WAIT=13,CRC_EVAL=14,
  PATCH0=15,PATCH1=16,WRITE=17,CHECK=18,ALLOC=19,RECORD=20,SELECT_HEADER=21;
 reg [21:0] state=22'd1<<IDLE;
 wire [15:0] a=arguments[15:0],b=arguments[31:16],c=arguments[47:32];
 reg awaiting=0,draft=0,cache_valid=0,scan=0;
 reg [7:0] entry=0,loaded_id=0,loaded_state=0,name_length=0,track_length=0,attributes=0;
 reg loaded_bank=1,read_copy=0,legacy_view=0,header_only_view=0;reg [1:0] clear_purpose=0;reg [7:0] selected_id=255;
 reg [31:0] loaded_sequence=0,loaded_samples=0,source_sequence=0;
 reg [15:0] loaded_crc=0;
 reg [19:0] loaded_base=0;
 reg [7:0] fill=0,put_address=0;reg [15:0] put_value=0;
 reg [8:0] crc_index=0;reg [15:0] calculated_crc=16'hffff;
 reg [7:0] low_byte=0;
 reg [4:0] base_count=0;reg [19:0] base_accumulator=0;
 reg found_free=0,free_bank=0;reg [7:0] free_entry=0;
 reg [19:0] scan_base=20'd65664,free_base=0;reg [31:0] max_sequence=0;
 reg [7:0] commit_state=1;reg new_take=0;
 reg [15:0] page[0:255] /* synthesis syn_ramstyle = "block_ram" */;
 reg page_we;reg [7:0] page_address;reg [15:0] page_value,page_word=0;
 wire crc_read=state[CRC_INIT] || state[CRC_WAIT] || state[CRC_EVAL];
 wire [7:0] page_read_address=crc_read?crc_index[8:1]:state[IDLE]?metadata_index:write_index[8:1];
 assign metadata_word=page_word;
 function [15:0] crcbyte(input [15:0] crc,input [7:0] value);
  integer k;reg [15:0] v;begin v=crc^{value,8'd0};
   for(k=0;k<8;k=k+1)v={v[14:0],1'b0}^(v[15]?16'h1021:16'd0);crcbyte=v;end
 endfunction
 function [15:0] header_word(input [7:0] index);
 begin case(index)
  0:header_word=16'h5959;1:header_word=16'h3632;
  2:header_word=16'h4552;3:header_word=16'h3143;
  4:header_word=16'ha501;5:header_word={8'd0,loaded_id};
  6:header_word=loaded_sequence[15:0];7:header_word=loaded_sequence[31:16];
  8:header_word={name_length,commit_state};9:header_word={attributes,track_length};
  10:header_word=loaded_samples[15:0];11:header_word=loaded_samples[31:16];
  12:header_word=loaded_crc;13:header_word=0;
  14:header_word=source_sequence[15:0];15:header_word=source_sequence[31:16];
  default:header_word=0;
 endcase end endfunction
 always @(*)begin
  page_we=0;page_address=fill;page_value=0;
  if(read_valid && state[LOAD] && read_index[0])begin
   page_we=1;page_address=read_index[8:1];page_value={read_byte,low_byte};
  end
  case(1'b1)
   state[CLEAR]:begin page_we=1;page_value=0;end
   state[PUT]:begin page_we=1;page_address=put_address;page_value=put_value;end
   state[HEADER]:begin page_we=1;page_value=header_word(fill);end
   state[PATCH0]:begin page_we=1;page_address=254;page_value=calculated_crc;end
   state[PATCH1]:begin page_we=1;page_address=255;page_value=~calculated_crc;end
  endcase
 end
 always @(posedge clk)begin
  if(page_we)page[page_address]<=page_value;
  page_word<=page[page_read_address];
  write_byte<=write_index[0]?page_word[15:8]:page_word[7:0];
 end
 // Header-only snapshots for two copies; no second page buffer.
 reg [63:0] h_magic=0;reg [31:0] h_sequence=0,h_count=0,h_source=0,h_inverse=0,h_rate=0,h_div=0,h_version=0;
 reg [15:0] h_crc=0,h_stored=0,h_tail=0,h_actual=16'hffff;
 reg [7:0] h_commit=0,h_id=0,h_reserved=0,h_state=0,h_name=0,h_track=0,h_flags=0,h_audio_flag=0;
 reg h_nonzero=0;
 reg first_valid=0,first_empty=0;reg [31:0] first_sequence=0;reg [1:0] first_state=0;
 wire metadata_valid=h_magic=="YY26REC1" && h_version==1 && h_commit==8'ha5 && h_id==entry &&
  h_reserved==0 && h_sequence!=0 && (h_state==1 || h_state==2) && h_name<=64 && h_track<=64 && h_flags<2 &&
  (h_state==2 || (h_count!=0 && h_count<=5859375)) &&
  h_actual==h_stored && (h_stored^h_tail)==16'hffff;
 wire audio_valid=h_magic=="YY24AUDI" && h_version==1 && (h_sequence^h_inverse)==32'hffffffff &&
  h_count!=0 && h_count<=5859375 && h_rate==50000000 && h_div==1024 &&
  h_audio_flag==8'ha5 && h_actual==h_stored;
 wire second_chosen=metadata_valid && (!first_valid || h_sequence>first_sequence);
 wire picked_valid=first_valid || metadata_valid;
 wire picked_bank=second_chosen;
 wire picked_empty=first_empty && !h_nonzero;
 wire [31:0] picked_sequence=second_chosen?h_sequence:first_sequence;
 wire [1:0] picked_state=second_chosen?h_state[1:0]:first_state;
 wire audio_read=state[LEGACY] || state[SELECT_HEADER];
 wire header_read=state[FIRST] || state[SECOND] || state[LOAD] || state[CHECK] || audio_read;
 wire [19:0] directory_address=20'd65538+{11'd0,entry,1'b0};
 wire [19:0] loaded_directory=20'd65538+{11'd0,loaded_id,1'b0};
 task read_block(input [19:0] address,input [4:0] next);
 begin
  block_request<=1;block_write<=0;block_sector<=address;state<=22'd1<<next;
  h_magic<=0;h_actual<=16'hffff;h_nonzero<=0;h_version<=0;
 end endtask
 task begin_item(input [7:0] id);
 begin entry<=id;read_copy<=0;first_valid<=0;first_empty<=0;
  read_block(20'd65538+{11'd0,id,1'b0},FIRST);
 end endtask
 task fail(input [3:0] code);
 begin error<=code;if(new_take || managed_active)last_error<=code;busy<=0;managed_active<=0;new_take<=0;
  if(awaiting || state[IDLE])state<=22'd1<<RESP;else state<=22'd1<<IDLE;
 end endtask
 task complete;
 begin done<=1;awaiting<=0;error<=0;info<={loaded_crc,loaded_samples,loaded_sequence,loaded_state,loaded_id};end
 endtask
 always @(posedge clk)begin
  if(read_valid)begin
   low_byte<=read_byte;
   if(header_read)begin
    if(read_byte!=0)h_nonzero<=1;
    if(audio_read)begin
     if(read_index<37 && read_index!=22 && read_index!=23)h_actual<=crcbyte(h_actual,read_byte);
    end else if(read_index<508)h_actual<=crcbyte(h_actual,read_byte);
    if(read_index<8)h_magic<={h_magic[55:0],read_byte};
    if(read_index>=12 && read_index<16)h_sequence[read_index[1:0]*8+:8]<=read_byte;
    if(audio_read)begin
     if(read_index>=8 && read_index<12)h_version[read_index[1:0]*8+:8]<=read_byte;
     if(read_index>=16 && read_index<20)h_count[read_index[1:0]*8+:8]<=read_byte;
     if(read_index==20 || read_index==21)h_crc[read_index[0]*8+:8]<=read_byte;
     if(read_index==22 || read_index==23)h_stored[read_index[0]*8+:8]<=read_byte;
     if(read_index>=24 && read_index<28)h_inverse[read_index[1:0]*8+:8]<=read_byte;
     if(read_index>=28 && read_index<32)h_rate[read_index[1:0]*8+:8]<=read_byte;
     if(read_index>=32 && read_index<36)h_div[read_index[1:0]*8+:8]<=read_byte;
     if(read_index==36)h_audio_flag<=read_byte;
    end else begin
     case(read_index)
      8:h_version<={24'd0,read_byte};9:h_commit<=read_byte;10:h_id<=read_byte;11:h_reserved<=read_byte;
      16:h_state<=read_byte;17:h_name<=read_byte;18:h_track<=read_byte;19:h_flags<=read_byte;
      24:h_crc[7:0]<=read_byte;25:h_crc[15:8]<=read_byte;
      508:h_stored[7:0]<=read_byte;509:h_stored[15:8]<=read_byte;
      510:h_tail[7:0]<=read_byte;511:h_tail[15:8]<=read_byte;
     endcase
     if(read_index>=20 && read_index<24)h_count[read_index[1:0]*8+:8]<=read_byte;
     if(read_index>=28 && read_index<32)h_source[read_index[1:0]*8+:8]<=read_byte;
    end
   end
  end
 // Explicit one-hot controls remove the shared binary-state decode fanout.
 // Control state machine shares this block with header capture (single drivers).
  done<=0;block_request<=0;writer_start<=0;
  if(legacy_start)begin selected<=0;last_error<=0;end
  // Capability query is harmless even during capture; other requests are
  // serialized and cannot replace an in-flight directory/capture operation.
  if(request && operation==0)begin
   done<=1;error<=0;
   info<={64'd0,8'd2,8'd120,(mounted?(extended_ready?8'd2:8'd1):8'd0),8'd20};
  end else if(request && !state[IDLE])begin done<=1;error<=4;end
  case(1'b1)
   state[IDLE]:if(request && operation!=0)begin
    error<=0;awaiting<=1;busy<=1;new_take<=0;
    if(!mounted || !allowed)fail(4);
    else case(operation)
     1:if(a>21)fail(8);else begin
      loaded_id<=a[7:0];cache_valid<=0;draft<=0;scan<=0;loaded_sequence<=0;
      loaded_samples<=0;loaded_crc<=0;source_sequence<=0;loaded_bank<=1;
      if(!extended_ready)begin
       if(a>=20)begin loaded_base<=a==20?20'd256:20'd32768;read_block(a==20?20'd256:20'd32768,LEGACY);end
       else begin loaded_state<=0;state<=22'd1<<RESP;end
      end else begin_item(a[7:0]);
     end
     2:begin
      draft<=1;cache_valid<=0;name_length<=0;track_length<=0;attributes<=0;
      loaded_sequence<=0;loaded_samples<=0;loaded_crc<=0;source_sequence<=0;
      fill<=0;clear_purpose<=0;state<=22'd1<<CLEAR;
     end
     3:if(!cache_valid || a>255 || !((a>=16 && a<=23)||(a>=32 && a<=95)))fail(8);
       else begin put_address<=a[7:0];put_value<=b;state<=22'd1<<PUT;end
     4:if(!cache_valid || a>64 || b>64 || c>1)fail(8);
       else begin name_length<=a[7:0];track_length<=b[7:0];attributes<=c[7:0];state<=22'd1<<RESP;end
     5:if(!extended_ready)fail(9);
       else if(!draft || !cache_valid || a<1 || a>120)fail(8);
       else begin
        last_error<=0;new_take<=1;writer_seconds<=a[6:0];
        found_free<=0;max_sequence<=0;scan<=1;scan_base<=65664;begin_item(0);
       end
     6:if(!extended_ready)fail(9);
       else if(!cache_valid || draft || (loaded_state!=1 && loaded_state!=4) || loaded_sequence==32'hffffffff)fail(8);
       else begin
        loaded_sequence<=loaded_sequence+1'b1;entry<=loaded_id;commit_state<=1;
        header_only_view<=0;fill<=0;state<=22'd1<<HEADER;
       end
     7:if(!extended_ready)fail(9);
       else if(draft || loaded_id>21 || (loaded_state!=1 && loaded_state!=2 && loaded_state!=3 && loaded_state!=4))fail(8);
       else if(loaded_state==2)state<=22'd1<<RESP;
       else if(loaded_sequence==32'hffffffff)fail(11);
       else begin
        loaded_sequence<=loaded_sequence+1'b1;entry<=loaded_id;commit_state<=2;header_only_view<=0;
        fill<=0;
        if(!cache_valid)begin
         clear_purpose<=2;name_length<=0;track_length<=0;attributes<=0;
         loaded_samples<=0;loaded_crc<=0;source_sequence<=0;state<=22'd1<<CLEAR;
        end else state<=22'd1<<HEADER;
       end
     8:if(!cache_valid || a>240)fail(8);else state<=22'd1<<RESP;
     9:if(!cache_valid || draft || (loaded_state!=1 && loaded_state!=4))fail(8);
       else read_block(loaded_base,SELECT_HEADER);
     default:fail(8);
    endcase
   end
   state[CLEAR]:if(fill==255)begin
    cache_valid<=1;fill<=0;
    if(clear_purpose==0)state<=22'd1<<RESP;
    else begin header_only_view<=clear_purpose==1;state<=22'd1<<HEADER;end
   end else fill<=fill+1'b1;
   state[PUT]:state<=22'd1<<RESP;
   state[RESP]:begin
    done<=1;awaiting<=0;busy<=0;state<=22'd1<<IDLE;
    info<={loaded_crc,loaded_samples,loaded_sequence,loaded_state,loaded_id};
   end
   state[FIRST]:if(block_done)begin
    if(block_error!=0)fail(1);
    else begin
     first_valid<=metadata_valid;first_empty<=!h_nonzero;
     first_sequence<=h_sequence;first_state<=h_state[1:0];
     read_copy<=1;read_block(directory_address+1'b1,SECOND);
    end
   end
   state[SECOND]:if(block_done)begin if(block_error!=0)fail(1);else state<=22'd1<<PICK;end
   state[PICK]:if(scan)begin
    if(picked_valid && picked_sequence>max_sequence)max_sequence<=picked_sequence;
    if(entry<20 && !found_free && ((picked_valid && picked_state==2)||picked_empty))begin
     found_free<=1;free_entry<=entry;free_bank<=picked_valid?picked_bank:1'b1;free_base<=scan_base;
    end
    if(entry==21)state<=22'd1<<ALLOC;
    else begin
     if(entry<19)scan_base<=scan_base+20'd22890;
     begin_item(entry+1'b1);
    end
   end else begin
    if(picked_valid)begin
     loaded_bank<=picked_bank;loaded_sequence<=picked_sequence;
     loaded_samples<=0;loaded_crc<=0;source_sequence<=0;
     loaded_state<=picked_state==2?8'd2:loaded_id>=20?8'd4:8'd1;
     if(picked_state==2)state<=22'd1<<RESP;
     else read_block(directory_address+{19'd0,picked_bank},LOAD);
    end else if(picked_empty && loaded_id>=20)begin
     loaded_base<=loaded_id==20?20'd256:20'd32768;
     read_block(loaded_id==20?20'd256:20'd32768,LEGACY);
    end else begin
     loaded_state<=picked_empty?8'd0:8'd3;loaded_bank<=1;
     loaded_sequence<=0;loaded_samples<=0;loaded_crc<=0;source_sequence<=0;state<=22'd1<<RESP;
    end
   end
   state[LOAD]:if(block_done)begin
    if(block_error!=0 || !metadata_valid || h_sequence!=loaded_sequence)fail(2);
    else begin
     loaded_samples<=h_count;loaded_crc<=h_crc;source_sequence<=h_source;
     name_length<=h_name;track_length<=h_track;attributes<=h_flags;state<=22'd1<<BASE_INIT;
    end
   end
   state[BASE_INIT]:begin
    base_accumulator<=65664;base_count<=loaded_id[4:0];
    if(loaded_id>=20)begin loaded_base<=loaded_id==20?20'd256:20'd32768;cache_valid<=1;state<=22'd1<<RESP;end
    else state<=22'd1<<BASE_STEP;
   end
   state[BASE_STEP]:if(base_count==0)begin loaded_base<=base_accumulator;cache_valid<=1;state<=22'd1<<RESP;end
    else begin base_accumulator<=base_accumulator+20'd22890;base_count<=base_count-1'b1;end
   state[LEGACY]:if(block_done)begin
    if(block_error!=0)fail(1);
    else if(!audio_valid)begin
     loaded_state<=h_nonzero?8'd3:8'd0;cache_valid<=0;state<=22'd1<<RESP;
    end else begin
     loaded_state<=4;loaded_sequence<=0;loaded_samples<=h_count;loaded_crc<=h_crc;
     source_sequence<=h_sequence;loaded_bank<=1;name_length<=0;track_length<=0;attributes<=0;
     commit_state<=1;fill<=0;clear_purpose<=1;state<=22'd1<<CLEAR;
    end
   end
   state[HEADER]:if(fill==15)begin
    if(header_only_view)begin cache_valid<=1;header_only_view<=0;state<=22'd1<<RESP;end
    else state<=22'd1<<CRC_INIT;
   end else fill<=fill+1'b1;
   state[CRC_INIT]:begin calculated_crc<=16'hffff;crc_index<=0;state<=22'd1<<CRC_WAIT;end
   state[CRC_WAIT]:state<=22'd1<<CRC_EVAL;
   state[CRC_EVAL]:begin
    calculated_crc<=crcbyte(calculated_crc,crc_index[0]?page_word[15:8]:page_word[7:0]);
    if(crc_index==507)state<=22'd1<<PATCH0;
    else begin crc_index<=crc_index+1'b1;state<=22'd1<<CRC_WAIT;end
   end
   state[PATCH0]:state<=22'd1<<PATCH1;
   state[PATCH1]:begin
    block_sector<=loaded_directory+{19'd0,!loaded_bank};block_write<=1;block_request<=1;state<=22'd1<<WRITE;
   end
   state[WRITE]:if(block_done)begin
    if(block_error!=0)fail(1);
    else read_block(loaded_directory+{19'd0,!loaded_bank},CHECK);
   end
   state[CHECK]:if(block_done)begin
    if(block_error!=0 || !metadata_valid || h_sequence!=loaded_sequence || h_count!=loaded_samples ||
       h_crc!=loaded_crc || h_state!=commit_state || h_source!=source_sequence ||
       h_name!=name_length || h_track!=track_length || h_flags!=attributes || h_stored!=calculated_crc)fail(2);
    else begin
     loaded_bank<=!loaded_bank;cache_valid<=1;draft<=0;busy<=0;
     loaded_state<=commit_state==2?8'd2:loaded_id>=20?8'd4:8'd1;
     if(commit_state==2)begin if(selected_id==loaded_id)selected<=0;end
     else if(new_take || (selected && selected_id==loaded_id))begin
      selected<=1;selected_id<=loaded_id;selected_base<=loaded_base;
      selected_generation<=loaded_sequence;selected_samples<=loaded_samples;selected_crc<=loaded_crc;
     end
     managed_active<=0;new_take<=0;
     if(awaiting)state<=22'd1<<RESP;else state<=22'd1<<IDLE;
    end
   end
   state[ALLOC]:if(!found_free)fail(6);
    else if(max_sequence==32'hffffffff)fail(11);
    else begin
     scan<=0;draft<=0;entry<=free_entry;loaded_id<=free_entry;loaded_bank<=free_bank;
     loaded_base<=free_base;loaded_sequence<=max_sequence+1'b1;source_sequence<=max_sequence+1'b1;
     managed_base<=free_base;managed_generation<=max_sequence+1'b1;managed_active<=1;
     writer_start<=1;state<=22'd1<<RECORD;
    end
   state[RECORD]:begin
    if(awaiting && writer_busy && (writer_status==1 || writer_status==2))complete;
    if(writer_done)begin
     if(!writer_ok)fail(writer_error!=0?writer_error:4'd4);
     else begin
      loaded_samples<=produced;loaded_crc<=capture_crc;commit_state<=1;
      header_only_view<=0;fill<=0;state<=22'd1<<HEADER;
     end
    end
   end
   state[SELECT_HEADER]:if(block_done)begin
    if(block_error!=0 || !audio_valid || h_sequence!=source_sequence || h_count!=loaded_samples || h_crc!=loaded_crc)fail(2);
    else begin
     selected<=1;selected_id<=loaded_id;selected_base<=loaded_base;
     selected_generation<=loaded_sequence;selected_samples<=loaded_samples;selected_crc<=loaded_crc;state<=22'd1<<RESP;
    end
   end
   default:begin state<=22'd1<<IDLE;busy<=0;managed_active<=0;end
  endcase
 end
endmodule
