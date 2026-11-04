`timescale 1ns/1ps
// One shared pool of 32 independently controlled musical voices.
// Commands: 0=all off, 1=note on, 2=note off, 3=demo, 4=release slot,
// 5=retune slot. Event IDs 0..6 belong to the legacy keyboard; 128..255 UART.
module poly32_synth #(parameter integer KEY_COUNT=7)(input wire clk,sample_tick,input wire [KEY_COUNT-1:0] legacy_gates,
 input wire [KEY_COUNT*32-1:0] legacy_steps,input wire [1:0] selected_timbre,
 input wire [74:0] piano_adsr,guitar_adsr,accordion_adsr,
 input wire command_valid,input wire [2:0] command_op,
 input wire [15:0] argument_a,argument_b,
 output wire command_ready,output reg command_done=0,command_ok=0,
 output reg [5:0] active_count=0,held_count=0,output wire [31:0] active_mask,held_mask,
 output reg demo_mode=0,output wire deadline_missed,
 output wire signed [15:0] piano_pcm,guitar_pcm,accordion_pcm,
 output reg signed [17:0] mixed_pcm=0,output wire frame_done,
 output wire [1023:0] voice_samples,
 input wire [3:0] music_gates,input wire [27:0] music_notes,input wire [3:0] music_epochs,
 output wire signed [31:0] visual_pcm,output wire [31:0] visual_step,
 output wire [12:0] visual_tag,output wire visual_active,
 input wire [6:0] keyboard_base,input wire [31:0] keyboard_step,
 output wire [5:0] keyboard_read_key,input wire panel_sustain);
 localparam integer MUSIC_OWNER=KEY_COUNT==60?64:8;
 reg [31:0] allocated=0,gates=0,test_sine=0;reg [255:0] generations=0;
 // Pedal holds only physical-key voices; UART/music release semantics stay intact.
 wire sustain_on=panel_sustain===1'b1;
 reg [31:0] pedal_held=0;
 reg [31:0] steps[0:31];reg [7:0] owner[0:31],velocity[0:31];
 reg [6:0] notes[0:31];reg [2:0] models[0:31];reg [1:0] timbres[0:31];
 reg [15:0] ages[0:31];reg [15:0] serial=0;
 wire [31:0] idle;wire [255:0] seen_gen;wire [511:0] levels;
 wire [1023:0] step_bus;wire [95:0] model_bus;wire [63:0] timbre_bus;wire [255:0] velocity_bus;
 wire [1:0] lane_busy,lane_done,lane_deadline;
 wire signed [31:0] lane_p[0:1],lane_g[0:1],lane_a[0:1];
 reg [4:0] visual_select=0;
 wire signed [31:0] lane_visual_pcm[0:1];wire [31:0] lane_visual_step[0:1];
 wire [7:0] lane_visual_generation[0:1];wire [3:0] lane_visual_slot[0:1];
 wire [1:0] lane_visual_gate;
 wire [7:0] visual_generation=visual_select[4]?lane_visual_generation[1]:lane_visual_generation[0];
 wire [3:0] sampled_slot=visual_select[4]?lane_visual_slot[1]:lane_visual_slot[0];
 wire visual_eligible=allocated[visual_select]&&gates[visual_select]&&
                      (owner[visual_select]<KEY_COUNT||owner[visual_select][7]);
 assign visual_pcm=visual_select[4]?lane_visual_pcm[1]:lane_visual_pcm[0];
 assign visual_step=visual_select[4]?lane_visual_step[1]:lane_visual_step[0];
 assign visual_tag={visual_select,visual_generation};
 assign visual_active=visual_eligible&&sampled_slot==visual_select[3:0]&&
                      lane_visual_gate[visual_select[4]]&&
                      visual_generation==generations[visual_select*8+:8];
 integer init_i;
 initial for(init_i=0;init_i<32;init_i=init_i+1)begin
  steps[init_i]=0;owner[init_i]=255;velocity[init_i]=128;notes[init_i]=60;
  models[init_i]=0;timbres[init_i]=0;ages[init_i]=0;
 end
 genvar g;
 generate for(g=0;g<32;g=g+1)begin: buses
  assign step_bus[g*32+:32]=steps[g];assign model_bus[g*3+:3]=models[g];
  assign timbre_bus[g*2+:2]=timbres[g];assign velocity_bus[g*8+:8]=velocity[g];
 end
 for(g=0;g<2;g=g+1)begin: lanes
  poly32_lane engine(clk,sample_tick,gates[g*16+:16],generations[g*128+:128],test_sine[g*16+:16],
   step_bus[g*512+:512],model_bus[g*48+:48],timbre_bus[g*32+:32],velocity_bus[g*128+:128],
   piano_adsr,guitar_adsr,accordion_adsr,lane_busy[g],lane_done[g],lane_deadline[g],
   lane_p[g],lane_g[g],lane_a[g],idle[g*16+:16],seen_gen[g*128+:128],levels[g*256+:256],voice_samples[g*512+:512],
   visual_select[3:0],lane_visual_pcm[g],lane_visual_step[g],
   lane_visual_generation[g],lane_visual_gate[g],lane_visual_slot[g]);
 end endgenerate
 assign deadline_missed=|lane_deadline;
 assign frame_done=&lane_done;
 assign active_mask=allocated;assign held_mask=gates&allocated;
 wire signed [32:0] pwide=($signed({lane_p[0][31],lane_p[0]})+$signed({lane_p[1][31],lane_p[1]}))>>>1;
 wire signed [32:0] gwide=($signed({lane_g[0][31],lane_g[0]})+$signed({lane_g[1][31],lane_g[1]}))>>>1;
 wire signed [32:0] awide=$signed({lane_a[0][31],lane_a[0]})+$signed({lane_a[1][31],lane_a[1]});
 wire signed [19:0] guitar_dry=gwide>524287?20'sd524287:gwide< -524288?-20'sd524288:gwide[19:0];
 wire signed [19:0] guitar_colored;wire color_done;
 guitar_body_color body(clk,frame_done,guitar_dry,guitar_colored,color_done);
 assign piano_pcm=pwide>32767?16'sd32767:pwide< -32768?-16'sd32768:pwide[15:0];
 assign guitar_pcm=guitar_colored>32767?16'sd32767:guitar_colored< -32768?-16'sd32768:guitar_colored[15:0];
 assign accordion_pcm=awide>32767?16'sd32767:awide< -32768?-16'sd32768:awide[15:0];
 wire signed [33:0] wide_mix=$signed({pwide[32],pwide})+$signed({awide[32],awide})+$signed({{14{guitar_colored[19]}},guitar_colored});
 always @(posedge clk)if(color_done)begin
  if(wide_mix>131071)mixed_pcm<=18'sd131071;
  else if(wide_mix< -131072)mixed_pcm<=-18'sd131072;
  else mixed_pcm<=wide_mix[17:0];
 end
 function [31:0] note_step(input [6:0] note);
  begin case(note)
   7'd0:note_step=32'd719151;
   7'd1:note_step=32'd761914;
   7'd2:note_step=32'd807220;
   7'd3:note_step=32'd855219;
   7'd4:note_step=32'd906073;
   7'd5:note_step=32'd959951;
   7'd6:note_step=32'd1017033;
   7'd7:note_step=32'd1077509;
   7'd8:note_step=32'd1141581;
   7'd9:note_step=32'd1209463;
   7'd10:note_step=32'd1281381;
   7'd11:note_step=32'd1357576;
   7'd12:note_step=32'd1438302;
   7'd13:note_step=32'd1523828;
   7'd14:note_step=32'd1614439;
   7'd15:note_step=32'd1710439;
   7'd16:note_step=32'd1812147;
   7'd17:note_step=32'd1919903;
   7'd18:note_step=32'd2034066;
   7'd19:note_step=32'd2155018;
   7'd20:note_step=32'd2283162;
   7'd21:note_step=32'd2418926;
   7'd22:note_step=32'd2562762;
   7'd23:note_step=32'd2715152;
   7'd24:note_step=32'd2876604;
   7'd25:note_step=32'd3047655;
   7'd26:note_step=32'd3228878;
   7'd27:note_step=32'd3420877;
   7'd28:note_step=32'd3624293;
   7'd29:note_step=32'd3839805;
   7'd30:note_step=32'd4068132;
   7'd31:note_step=32'd4310035;
   7'd32:note_step=32'd4566323;
   7'd33:note_step=32'd4837851;
   7'd34:note_step=32'd5125525;
   7'd35:note_step=32'd5430304;
   7'd36:note_step=32'd5753207;
   7'd37:note_step=32'd6095311;
   7'd38:note_step=32'd6457757;
   7'd39:note_step=32'd6841755;
   7'd40:note_step=32'd7248587;
   7'd41:note_step=32'd7679610;
   7'd42:note_step=32'd8136263;
   7'd43:note_step=32'd8620071;
   7'd44:note_step=32'd9132647;
   7'd45:note_step=32'd9675702;
   7'd46:note_step=32'd10251050;
   7'd47:note_step=32'd10860609;
   7'd48:note_step=32'd11506414;
   7'd49:note_step=32'd12190621;
   7'd50:note_step=32'd12915513;
   7'd51:note_step=32'd13683509;
   7'd52:note_step=32'd14497173;
   7'd53:note_step=32'd15359220;
   7'd54:note_step=32'd16272527;
   7'd55:note_step=32'd17240142;
   7'd56:note_step=32'd18265294;
   7'd57:note_step=32'd19351405;
   7'd58:note_step=32'd20502099;
   7'd59:note_step=32'd21721217;
   7'd60:note_step=32'd23012829;
   7'd61:note_step=32'd24381242;
   7'd62:note_step=32'd25831027;
   7'd63:note_step=32'd27367019;
   7'd64:note_step=32'd28994347;
   7'd65:note_step=32'd30718441;
   7'd66:note_step=32'd32545054;
   7'd67:note_step=32'd34480283;
   7'd68:note_step=32'd36530588;
   7'd69:note_step=32'd38702809;
   7'd70:note_step=32'd41004198;
   7'd71:note_step=32'd43442435;
   7'd72:note_step=32'd46025656;
   7'd73:note_step=32'd48762484;
   7'd74:note_step=32'd51662052;
   7'd75:note_step=32'd54734038;
   7'd76:note_step=32'd57988693;
   7'd77:note_step=32'd61436880;
   7'd78:note_step=32'd65090107;
   7'd79:note_step=32'd68960566;
   7'd80:note_step=32'd73061175;
   7'd81:note_step=32'd77405619;
   7'd82:note_step=32'd82008396;
   7'd83:note_step=32'd86884869;
   7'd84:note_step=32'd92051312;
   7'd85:note_step=32'd97524968;
   7'd86:note_step=32'd103324105;
   7'd87:note_step=32'd109468076;
   7'd88:note_step=32'd115977386;
   7'd89:note_step=32'd122873760;
   7'd90:note_step=32'd130180214;
   7'd91:note_step=32'd137921133;
   7'd92:note_step=32'd146122350;
   7'd93:note_step=32'd154811237;
   7'd94:note_step=32'd164016792;
   7'd95:note_step=32'd173769738;
   7'd96:note_step=32'd184102625;
   7'd97:note_step=32'd195049936;
   7'd98:note_step=32'd206648209;
   7'd99:note_step=32'd218936151;
   7'd100:note_step=32'd231954772;
   7'd101:note_step=32'd245747521;
   7'd102:note_step=32'd260360429;
   7'd103:note_step=32'd275842266;
   7'd104:note_step=32'd292244700;
   7'd105:note_step=32'd309622474;
   7'd106:note_step=32'd328033585;
   7'd107:note_step=32'd347539477;
   7'd108:note_step=32'd368205249;
   7'd109:note_step=32'd390099873;
   7'd110:note_step=32'd413296419;
   7'd111:note_step=32'd437872302;
   7'd112:note_step=32'd463909545;
   7'd113:note_step=32'd491495042;
   7'd114:note_step=32'd520720858;
   7'd115:note_step=32'd551684531;
   7'd116:note_step=32'd584489400;
   7'd117:note_step=32'd619244949;
   7'd118:note_step=32'd656067170;
   7'd119:note_step=32'd695078954;
   7'd120:note_step=32'd736410499;
   7'd121:note_step=32'd780199746;
   7'd122:note_step=32'd826592837;
   7'd123:note_step=32'd875744605;
   7'd124:note_step=32'd927819089;
   7'd125:note_step=32'd982990083;
   7'd126:note_step=32'd1041441715;
   7'd127:note_step=32'd1103369062;
   default:note_step=0;
  endcase end
 endfunction
 function [2:0] guitar_register(input [6:0] note);
  begin guitar_register=note<48?0:note<60?1:note<72?2:note<84?3:note<96?4:note<108?5:6;end
 endfunction
 function [2:0] note_model(input [6:0] note);
  reg [3:0] pc;begin
   pc=note%12;
   case(pc)0,1:note_model=0;2,3:note_model=1;4:note_model=2;5,6:note_model=3;7,8:note_model=4;9,10:note_model=5;default:note_model=6;endcase
  end
 endfunction
 function [6:0] legacy_note(input [2:0] key_id);
  begin case(key_id)0:legacy_note=60;1:legacy_note=62;2:legacy_note=64;3:legacy_note=65;4:legacy_note=67;5:legacy_note=69;default:legacy_note=71;endcase end
 endfunction
 reg [2:0] state=0;reg [4:0] scan=0,chosen=0,weakest=0,oldest=0;
 reg found=0,has_released=0;reg [15:0] weakest_level=16'hffff,oldest_age=0;
 reg [7:0] event_owner=0;reg [6:0] event_note=0;reg [7:0] event_velocity=128;
 reg [31:0] event_step=0;reg [1:0] event_timbre=0;reg event_on=0,remote_event=0;
 reg [35:0] music_seen=0;reg [1:0] music_slot=0;
 wire [8:0] music_event={music_epochs[music_slot],music_gates[music_slot],music_notes[music_slot*7+:7]};
 // One synchronous block ROM replaces the separate combinational MIDI
 // tables. Ordinary events read it during their existing 32-slot scan.
 // Retune and demo commands explicitly wait for the synchronous read.
 reg [31:0] pitch_rom[0:127] /* synthesis syn_romstyle = "block_rom" */;
 integer pitch_init;initial for(pitch_init=0;pitch_init<128;pitch_init=pitch_init+1)pitch_rom[pitch_init]=note_step(pitch_init);
 reg [4:0] retune_slot=0;reg [6:0] retune_note=0;
 wire [6:0] lookup_note=state==3||state==7 ? 7'd48+{2'd0,scan} : state==4||state==5 ? retune_note : event_note;
 reg [31:0] lookup_step=0;
 always @(posedge clk)lookup_step<=pitch_rom[lookup_note];
 reg [KEY_COUNT-1:0] legacy_seen=0;reg [5:0] legacy_key=0;reg [4:0] refresh=0;
 // One synchronous read port services refresh or the keyboard event under
 // examination. Event scanning lasts 32 clocks, so its value is settled well
 // before commit. Owner tags reject a refresh if a slot was replaced meanwhile.
 assign keyboard_read_key=state==1&&event_owner<KEY_COUNT?event_owner[5:0]:owner[refresh][5:0];
 reg [4:0] refresh_q=0;reg [7:0] refresh_owner=255;reg refresh_valid=0;
 always @(posedge clk)begin
  refresh_q<=refresh;refresh_owner<=owner[refresh];
  refresh_valid<=state!=1&&allocated[refresh]&&gates[refresh]&&!pedal_held[refresh]&&owner[refresh]<KEY_COUNT;
 end
 reg [5:0] demo_count=0;reg demo_pure=0;
 assign command_ready=state==0;
 function [5:0] count_voices(input [31:0] mask);
  integer j;begin count_voices=0;for(j=0;j<32;j=j+1)count_voices=count_voices+{5'd0,mask[j]};end
 endfunction
 wire [5:0] ac=count_voices(allocated),hc=count_voices(allocated&gates);
 // Keep the 32-way selection separate from the balanced 16-bit comparison.
 // Each nibble predicate has identical unsigned ordering to the original <.
 wire [15:0] scanned_level /* synthesis syn_keep=1 */ = levels[scan*16+:16];
 wire [3:0] level_less /* synthesis syn_keep=1 */;
 wire [3:0] level_equal /* synthesis syn_keep=1 */;
 genvar nibble;generate for(nibble=0;nibble<4;nibble=nibble+1)begin:weak_compare
  assign level_less[nibble]=scanned_level[nibble*4+:4]<weakest_level[nibble*4+:4];
  assign level_equal[nibble]=scanned_level[nibble*4+:4]==weakest_level[nibble*4+:4];
 end endgenerate
 wire weaker_level=level_less[3] | (level_equal[3]&level_less[2]) |
  (level_equal[3]&level_equal[2]&level_less[1]) |
  (level_equal[3]&level_equal[2]&level_equal[1]&level_less[0]);
 integer i;
 // Observer selection has no feedback into allocation or sound synthesis.
 always @(posedge clk)begin
  if(!visual_eligible&&allocated[refresh]&&gates[refresh]&&
     (owner[refresh]<KEY_COUNT||owner[refresh][7]))visual_select<=refresh;
  if(state==2&&event_on&&(event_owner<KEY_COUNT||event_owner[7]))
   visual_select<=found?chosen:has_released?weakest:oldest;
 end
 always @(posedge clk)begin
  command_done<=0;command_ok<=0;active_count<=ac;held_count<=hc;
  refresh<=refresh+1'b1;
  // Constant per-slot enables avoid routing an indexed 32-way read/modify/
  // write chain back across the pool. Still service exactly the same one slot.
  for(i=0;i<32;i=i+1)if(refresh==i)begin
   if(!sustain_on && pedal_held[i])begin gates[i]<=0;pedal_held[i]<=0;end
   if(allocated[i]&&!gates[i]&&idle[i]&&seen_gen[i*8+:8]==generations[i*8+:8])allocated[i]<=0;
  end
  if(KEY_COUNT==60)begin
   // Constant local write enables avoid a global owner/gate mux feeding
   // all 1024 step-register enables. The same slot and priority are retained.
   for(i=0;i<32;i=i+1)if(refresh_valid&&refresh_q==i&&allocated[i]&&gates[i]&&!pedal_held[i]&&owner[i]==refresh_owner)
    steps[i]<=keyboard_step;
  end else if(allocated[refresh]&&gates[refresh]&&owner[refresh]<KEY_COUNT)
   steps[refresh]<=legacy_steps[owner[refresh]*32+:32];
  case(state)
   0:begin
    legacy_key<=legacy_key==KEY_COUNT-1?6'd0:legacy_key+1'b1;music_slot<=music_slot+1'b1;
    if(command_valid)begin
     if(command_op==0)begin
      gates<=0;allocated<=0;pedal_held<=0;for(i=0;i<32;i=i+1)generations[i*8+:8]<=generations[i*8+:8]+1'b1;demo_mode<=0;legacy_seen<=legacy_gates;
      command_done<=1;command_ok<=1;
     end else if(command_op==3)begin
      gates<=0;allocated<=0;pedal_held<=0;for(i=0;i<32;i=i+1)generations[i*8+:8]<=generations[i*8+:8]+1'b1;legacy_seen<=legacy_gates;
      demo_mode<=argument_a!=0;demo_count<=argument_a[5:0];demo_pure<=argument_b[0];scan<=0;
      if(argument_a==0)begin command_done<=1;command_ok<=1;end else state<=3;
     end else if(command_op==4)begin gates[argument_a[4:0]]<=0;command_done<=1;command_ok<=allocated[argument_a[4:0]];end
     else if(command_op==5)begin
      if(argument_a<32&&allocated[argument_a[4:0]]&&(test_sine[argument_a[4:0]]?(argument_b>=1&&argument_b<512):argument_b<128))begin
       if(test_sine[argument_a[4:0]])begin steps[argument_a[4:0]]<=({16'd0,argument_b}<<22);command_done<=1;command_ok<=1;end
       else begin retune_slot<=argument_a[4:0];retune_note<=argument_b[6:0];state<=4;end
      end else command_done<=1;
     end else begin
      event_owner<={1'b1,argument_a[6:0]};event_note<=argument_a[6:0];event_step<=0;
      event_velocity<=argument_b==127?8'd128:{1'b0,argument_b[6:0]};event_timbre<=selected_timbre;
      event_on<=command_op==1;remote_event<=1;state<=1;scan<=0;found<=0;has_released<=0;weakest_level<=16'hffff;oldest_age<=0;
     end
    end else if(!demo_mode&&legacy_gates[legacy_key]!=legacy_seen[legacy_key])begin
     legacy_seen[legacy_key]<=legacy_gates[legacy_key];event_owner<={2'd0,legacy_key};
     event_note<=KEY_COUNT==60?keyboard_base+legacy_key:legacy_note(legacy_key[2:0]);event_step<=KEY_COUNT==60?32'd0:legacy_steps[legacy_key*32+:32];event_velocity<=128;
     event_timbre<=selected_timbre;event_on<=legacy_gates[legacy_key];remote_event<=0;
     state<=1;scan<=0;found<=0;has_released<=0;weakest_level<=16'hffff;oldest_age<=0;
    end else if(!demo_mode&&music_seen[music_slot*9+:9]!=music_event)begin
     music_seen[music_slot*9+:9]<=music_event;
     event_owner<=MUSIC_OWNER+music_slot;event_note<=music_notes[music_slot*7+:7];
     event_step<=0;
     event_velocity<=music_slot==0?8'd40:music_slot==1?8'd56:8'd36;
     event_timbre<=music_slot<2?2'd0:2'd1;event_on<=music_gates[music_slot];remote_event<=0;
     state<=1;scan<=0;found<=0;has_released<=0;weakest_level<=16'hffff;oldest_age<=0;
    end
   end
   1:begin
    if(event_on)begin
     // Rearticulation of a music slot releases its previous held voice only.
     if(event_owner>=MUSIC_OWNER&&event_owner<MUSIC_OWNER+4&&allocated[scan]&&owner[scan]==event_owner)gates[scan]<=0;
     if(!allocated[scan]&&!found)begin chosen<=scan;found<=1;end
     if(allocated[scan]&&!gates[scan]&&(!has_released||weaker_level))begin
      weakest<=scan;weakest_level<=scanned_level;has_released<=1;
     end
     if(serial-ages[scan]>=oldest_age)begin oldest_age<=serial-ages[scan];oldest<=scan;end
    end else if(allocated[scan]&&gates[scan]&&owner[scan]==event_owner&&!pedal_held[scan])begin
     if(sustain_on && event_owner<KEY_COUNT)pedal_held[scan]<=1;else gates[scan]<=0;
     found<=1;
    end
    if(scan==31)begin
     if(event_on)begin
      if(event_owner<KEY_COUNT)begin if(KEY_COUNT==60)event_step<=keyboard_step;end
      else event_step<=lookup_step;
     end
     state<=2;
    end else scan<=scan+1'b1;
   end
   2:begin
    if(event_on)begin
     // Resolve the choice after the final scan's nonblocking updates settle.
     allocated[found?chosen:has_released?weakest:oldest]<=1;
     pedal_held[found?chosen:has_released?weakest:oldest]<=0;
     gates[found?chosen:has_released?weakest:oldest]<=1;
     test_sine[found?chosen:has_released?weakest:oldest]<=0;
     generations[(found?chosen:has_released?weakest:oldest)*8+:8]<=generations[(found?chosen:has_released?weakest:oldest)*8+:8]+1'b1;
     owner[found?chosen:has_released?weakest:oldest]<=event_owner;
     notes[found?chosen:has_released?weakest:oldest]<=event_note;
     steps[found?chosen:has_released?weakest:oldest]<=event_step;
     models[found?chosen:has_released?weakest:oldest]<=event_timbre==1?guitar_register(event_note):note_model(event_note);
     timbres[found?chosen:has_released?weakest:oldest]<=event_timbre;
     velocity[found?chosen:has_released?weakest:oldest]<=event_velocity;
     ages[found?chosen:has_released?weakest:oldest]<=serial;serial<=serial+1'b1;
    end
    if(remote_event)begin command_done<=1;command_ok<=event_on||found;end
    state<=0;
   end
   3:state<=7;
   4:state<=5;
   5:begin steps[retune_slot]<=lookup_step;command_done<=1;command_ok<=1;state<=0;end
   7:begin
    allocated[scan]<=1;gates[scan]<=1;test_sine[scan]<=demo_pure;
    owner[scan]<=128+scan;notes[scan]<=48+scan;
    models[scan]<=selected_timbre==1?guitar_register(48+scan):note_model(48+scan);
    timbres[scan]<=selected_timbre;velocity[scan]<=128;
    steps[scan]<=demo_pure?((32'd8+{25'd0,scan,2'b00})<<22):lookup_step;
    ages[scan]<=serial;serial<=serial+1'b1;
    if({1'b0,scan}+1'b1==demo_count)begin state<=0;command_done<=1;command_ok<=1;end else begin scan<=scan+1'b1;state<=3;end
   end
  endcase
 end
endmodule
