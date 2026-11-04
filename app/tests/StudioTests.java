package cn.fpga.score;
import java.util.*;
import java.io.*;
public final class StudioTests {
 static int checks;static void check(boolean b){checks++;if(!b)throw new AssertionError("check "+checks);}
 interface Bad{void run()throws Exception;}static void rejects(Bad b)throws Exception{try{b.run();throw new AssertionError("accepted invalid data");}catch(IllegalArgumentException|IOException expected){checks++;}}
 static final class Link implements Uploader.Link{
  final Queue<String> replies=new ArrayDeque<>();final List<String> sent=new ArrayList<>();int rank;boolean old;
  public void clear(){replies.clear();}public String receive(long ms){return replies.poll();}
  public void send(String s){sent.add(s);switch(s){case "FEAT":replies.add(old?"ERR 1":"F24 000F FFFF");break;case "ABORT":replies.add("OK");break;case "MAPGET":replies.add(String.format(Locale.ROOT,"MAP %04X",rank));break;default:if(s.startsWith("MAP ")){rank=Integer.parseInt(s.substring(4));replies.add("OK");}}}
 }
 static String packet(int offset,byte[] pcm){int crc=StudioProtocol.crcByte(StudioProtocol.crcByte(StudioProtocol.crcByte(65535,offset),offset>>8),pcm.length/2);StringBuilder s=new StringBuilder(String.format(Locale.ROOT,"D %04X %02X ",offset,pcm.length/2));for(byte b:pcm){s.append(String.format(Locale.ROOT,"%02X",b&255));crc=StudioProtocol.crcByte(crc,b);}return s.append(String.format(Locale.ROOT," %04X",crc)).toString();}
 public static void main(String[] args)throws Exception{
  for(int r=0;r<5040;r++){int[] map=KeyMapping.decode(r);check(KeyMapping.encode(map)==r);for(int key=0;key<7;key++){int[] swapped=KeyMapping.swap(map,key,(key+r)%7+1);check(swapped[key]==(key+r)%7+1);check(KeyMapping.encode(KeyMapping.decode(KeyMapping.encode(swapped)))==KeyMapping.encode(swapped));}}
  rejects(()->KeyMapping.decode(5040));rejects(()->KeyMapping.encode(new int[]{1,1,2,3,4,5,6}));
  byte[] samples={0,0,-1,127,0,-128,-1,-1};check(Arrays.equals(samples,StudioProtocol.decodeBlock(packet(16,samples),16,4)));
  rejects(()->StudioProtocol.decodeBlock(packet(16,samples),0,4));rejects(()->StudioProtocol.decodeBlock(packet(16,samples),16,3));rejects(()->StudioProtocol.decodeBlock(packet(16,samples).replace("FFFF","FFFE"),16,4));
  byte[] wav=StudioProtocol.wav(samples);check(wav.length==52);check(new String(wav,0,4,"US-ASCII").equals("RIFF"));check(wav[22]==1&&wav[34]==16);check(Arrays.equals(Arrays.copyOfRange(wav,44,wav.length),samples));rejects(()->StudioProtocol.wav(new byte[1]));
  Link link=new Link();StudioProtocol p=new StudioProtocol(link);check(p.capabilities()==15);p.mapping(5039);check(p.mapping()==5039);link.old=true;check(p.capabilities()==0);check(link.sent.get(link.sent.size()-1).equals("ABORT"));
  StudioProtocol.State t=new StudioProtocol.State("T 1FFF 3 7F 00FA 00FF 13AF 0078 1 1");check(t.index==8191&&t.keys==127&&t.held==250&&t.expected==255&&t.rank==5039&&t.bpm==120&&t.user&&t.valid);
  rejects(()->new StudioProtocol.State("T 0000 9 00 0000 0000 0000 0078 1 1"));
  ReplyFrames frames=new ReplyFrames();String block=packet(16,samples);List<String> received=new ArrayList<>();byte[] bytes=(block+"\n").getBytes("US-ASCII");for(byte b:bytes)received.addAll(frames.feed(new byte[]{b}));check(received.equals(Arrays.asList(block)));
  System.out.println("PASS StudioTests "+checks+" checks");
 }
}
