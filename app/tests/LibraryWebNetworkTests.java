package cn.fpga.score;
import java.nio.file.*;
import java.util.*;
import java.security.MessageDigest;
public final class LibraryWebNetworkTests {
 public static void main(String[] args)throws Exception{
  Path root=Paths.get(args[0]),out=root.resolve("verification/library_web/network");Files.createDirectories(out);
  List<OpenCatalog.Item> rows=OpenCatalog.read(Files.newInputStream(root.resolve("vendor/open_catalog.tsv")));
  int count=0;List<String> report=new ArrayList<>();
  try{for(int index:new int[]{0,32,256,1024,4080,6857}){
   OpenCatalog.Item item=rows.get(index);ScoreWebImport.Download file=ScoreWebImport.fetch(item.url,null,null,null);
   StringBuilder sha=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-1").digest(file.data))sha.append(String.format(Locale.ROOT,"%02x",b&255));
   if(!sha.toString().equals(item.sha1)||file.kind!=ScoreWebImport.Kind.MIDI)throw new AssertionError("Wrong source bytes "+item.id);
   MusicXmlImport parsed=MidiImport.read(file.data);List<String> notices=new ArrayList<>();String draft=parsed.draft(0,parsed.tonic,notices);
   if(!draft.startsWith("BPM="))throw new AssertionError("No score draft");
   Files.write(out.resolve(item.id+".mid"),file.data);
   report.add(item.id+"\t"+item.title+"\t"+file.data.length+"\t"+sha+"\t"+parsed.tracks.size()+"\t"+parsed.tracks.get(0).notes.size()+"\t"+draft.contains("?")+"\t"+item.url);count++;
   System.out.println("SOURCE "+item.id+" MIDI downloaded, SHA-1 verified, "+parsed.tracks.size()+" tracks parsed and review draft generated.");
  }}catch(Exception e){Files.write(out.resolve("failure.txt"),Arrays.asList(e.toString()),java.nio.charset.StandardCharsets.UTF_8);throw e;}
  finally{Files.write(out.resolve("samples.tsv"),report,java.nio.charset.StandardCharsets.UTF_8);}
  System.out.println("PASS library_web HTTPS: "+count+" live Commons files downloaded by the production Java importer, hashes verified, MIDI parsed and seven-key review reached. No physical Android test.");
 }
}
