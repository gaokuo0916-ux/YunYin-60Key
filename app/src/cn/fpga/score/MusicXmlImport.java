package cn.fpga.score;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import javax.xml.parsers.*;
import org.w3c.dom.*;
import org.xml.sax.InputSource;

/** MusicXML/MXL -> explicitly chosen single voice, with user-reviewed transposition. */
public final class MusicXmlImport {
    public static final class Note {
        public double at,duration;public int pitch;public boolean tieIn,tieOut;
        Note(double a,double d,int p,boolean in,boolean out){at=a;duration=d;pitch=p;tieIn=in;tieOut=out;}
    }
    public static final class Track {
        public final String name;public final List<Note> notes=new ArrayList<>();
        Track(String value){name=value;}
    }
    public final String title;
    public final List<Track> tracks=new ArrayList<>();
    public int bpm=120,tonic=0;
    public final List<String> warnings=new ArrayList<>();
    MusicXmlImport(String name){title=name;}
    private static List<Element> children(Element parent,String name){
        List<Element> out=new ArrayList<>();for(Node n=parent.getFirstChild();n!=null;n=n.getNextSibling())
            if(n instanceof Element && (name==null || tag((Element)n).equals(name)))out.add((Element)n);return out;
    }
    private static String tag(Element e){String s=e.getTagName();return s.contains(":")?s.substring(s.indexOf(':')+1):s;}
    private static Element child(Element e,String name){List<Element> c=children(e,name);return c.isEmpty()?null:c.get(0);}
    private static String text(Element e,String name,String fallback){Element c=child(e,name);return c==null?fallback:c.getTextContent().trim();}
    private static double num(Element e,String name,double fallback){try{return Double.parseDouble(text(e,name,""));}catch(NumberFormatException x){return fallback;}}
    private static byte[] readBounded(InputStream in,int max)throws IOException{
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[8192];int n;
        while((n=in.read(b))!=-1){if(out.size()+n>max)throw new IOException("解压后曲谱过大");out.write(b,0,n);}return out.toByteArray();
    }
    public static MusicXmlImport read(byte[] input)throws Exception{
        if(input.length>8*1024*1024)throw new IOException("曲谱超过 8 MB");
        byte[] xml=input;
        if(input.length>2 && input[0]=='P' && input[1]=='K'){
            Map<String,byte[]> files=new LinkedHashMap<>();int total=0,count=0;
            try(ZipInputStream z=new ZipInputStream(new ByteArrayInputStream(input))){
                ZipEntry e;while((e=z.getNextEntry())!=null){
                    if(++count>100)throw new IOException("MXL 压缩项过多");
                    if(e.isDirectory())continue;
                    byte[] data=readBounded(z,8*1024*1024-total);total+=data.length;files.put(e.getName(),data);
                }
            }
            String wanted=null;byte[] container=files.get("META-INF/container.xml");
            if(container!=null){Document d=document(container);NodeList roots=d.getElementsByTagName("rootfile");
                if(roots.getLength()>0)wanted=((Element)roots.item(0)).getAttribute("full-path");}
            xml=wanted==null?null:files.get(wanted);
            if(xml==null)for(Map.Entry<String,byte[]> entry:files.entrySet())
                if(!entry.getKey().startsWith("META-INF/") && (entry.getKey().endsWith(".xml") || entry.getKey().endsWith(".musicxml"))){xml=entry.getValue();break;}
            if(xml==null)throw new IOException("MXL 内没有找到 MusicXML 主文件");
        }
        Document doc=document(xml);Element root=doc.getDocumentElement();
        if(!tag(root).equals("score-partwise"))throw new IOException("当前支持 score-partwise MusicXML，请从制谱软件导出此格式");
        String title=text(root,"movement-title","导入曲谱");Element work=child(root,"work");if(work!=null)title=text(work,"work-title",title);
        MusicXmlImport result=new MusicXmlImport(title);
        Map<String,String> names=new HashMap<>();Element partList=child(root,"part-list");
        if(partList!=null)for(Element e:children(partList,"score-part"))names.put(e.getAttribute("id"),text(e,"part-name",e.getAttribute("id")));
        Map<String,Track> tracks=new LinkedHashMap<>();int eventCount=0;boolean tempoSet=false,keySet=false,repeat=false;
        for(Element part:children(root,"part")){
            String partId=part.getAttribute("id");double divisions=1,measureAt=0;int beats=4,beatType=4;
            for(Element measure:children(part,"measure")){
                double cursor=0,longest=0,previousStart=0;
                for(Element e:children(measure,null)){
                    String type=tag(e);
                    if(type.equals("attributes")){
                        divisions=num(e,"divisions",divisions);if(!Double.isFinite(divisions) || divisions<=0 || divisions>10000000)throw new IOException("无效的 MusicXML divisions");
                        Element time=child(e,"time");if(time!=null){beats=(int)num(time,"beats",beats);beatType=(int)num(time,"beat-type",beatType);}
                        if(beats<1 || beats>64 || beatType<1 || beatType>128)throw new IOException("无效或不支持的拍号");
                        Element key=child(e,"key");if(key!=null && !keySet){int fifths=(int)num(key,"fifths",0);result.tonic=((fifths*7)%12+12)%12;keySet=true;}
                    }else if(type.equals("direction")){
                        Element sound=child(e,"sound");if(sound!=null && sound.hasAttribute("tempo")){
                            try{double speed=Double.parseDouble(sound.getAttribute("tempo"));if(!Double.isFinite(speed))throw new NumberFormatException();
                                int rounded=(int)Math.round(speed);
                                if(!tempoSet){result.bpm=rounded;tempoSet=true;}
                                else if(rounded!=result.bpm && !result.warnings.contains("谱内变速未展开，当前全曲使用首个速度，请核对"))result.warnings.add("谱内变速未展开，当前全曲使用首个速度，请核对");
                            }catch(NumberFormatException ignored){result.warnings.add("原谱含无效速度，请在确认页设定 BPM");}
                        }
                    }else if(type.equals("backup") || type.equals("forward")){
                        double movement=num(e,"duration",0)/divisions;
                        if(!Double.isFinite(movement) || movement<0 || movement>1600)throw new IOException("无效的声部时间位置");
                        cursor+=type.equals("backup")?-movement:movement;
                        if(cursor<-.00001)throw new IOException("声部时间位置早于小节开始");longest=Math.max(longest,cursor);
                    }
                    else if(type.equals("note")){
                        if(child(e,"grace")!=null){if(!result.warnings.contains("装饰音未展开，请在确认页按需要补入"))result.warnings.add("装饰音未展开，请在确认页按需要补入");continue;}
                        double duration=num(e,"duration",0)/divisions;
                        Element rest=child(e,"rest");if(duration<=0 && rest!=null && "yes".equals(rest.getAttribute("measure")))duration=beats*4.0/beatType;
                        if(Double.isNaN(duration) || Double.isInfinite(duration) || duration>1600)throw new IOException("曲谱包含超长或无效时值");
                        if(duration<=0)continue;
                        boolean chord=child(e,"chord")!=null;double at=measureAt+(chord?previousStart:cursor);
                        if(!chord){previousStart=cursor;cursor+=duration;}longest=Math.max(longest,at-measureAt+duration);
                        int pitch=-1;Element p=child(e,"pitch");
                        if(p!=null){String step=text(p,"step","");int ix="C D EF G A B".indexOf(step);
                            if(step.length()!=1 || ix<0)throw new IOException("不支持的音高记号");
                            double alter=num(p,"alter",0);if(alter!=Math.rint(alter))throw new IOException("当前七键不支持微分音");
                            pitch=12*((int)num(p,"octave",4)+1)+ix+(int)alter;
                        }else if(rest==null)continue;
                        boolean tieIn=false,tieOut=false;for(Element tie:children(e,"tie")){tieIn|=tie.getAttribute("type").equals("stop");tieOut|=tie.getAttribute("type").equals("start");}
                        String voice=text(e,"voice","1"),staff=text(e,"staff","1"),id=partId+":"+staff+":"+voice;
                        Track track=tracks.get(id);if(track==null){track=new Track(names.getOrDefault(partId,partId)+" · 谱表 "+staff+" · 声部 "+voice);tracks.put(id,track);}
                        track.notes.add(new Note(at,duration,pitch,tieIn,tieOut));
                        if(++eventCount>10000)throw new IOException("原始谱面过大，请分文件导入");
                    }else if(type.equals("barline") && (!children(e,"repeat").isEmpty() || !children(e,"ending").isEmpty()))repeat=true;
                }
                measureAt+=longest>0?longest:beats*4.0/beatType;
            }
        }
        result.tracks.addAll(tracks.values());if(result.tracks.isEmpty())throw new IOException("没有可导入的音符");
        if(repeat)result.warnings.add("反复和跳房子未展开，当前按谱面书写顺序导入，请核对段落");
        if(result.bpm<20 || result.bpm>300){result.bpm=120;result.warnings.add("原速度超出当前范围，暂设 120 BPM，请修改");}
        return result;
    }
    private static Document document(byte[] bytes)throws Exception{
        String text=new String(bytes,StandardCharsets.UTF_8);
        if(text.toUpperCase(Locale.ROOT).contains("<!ENTITY"))throw new IOException("不支持包含自定义实体的 XML");
        DocumentBuilderFactory f=DocumentBuilderFactory.newInstance();f.setExpandEntityReferences(false);
        try{f.setFeature(javax.xml.XMLConstants.FEATURE_SECURE_PROCESSING,true);}catch(ParserConfigurationException ignored){}
        for(String feature:new String[]{"http://xml.org/sax/features/external-general-entities","http://xml.org/sax/features/external-parameter-entities","http://apache.org/xml/features/nonvalidating/load-external-dtd"}){
            try{f.setFeature(feature,false);}catch(ParserConfigurationException ignored){}
        }
        DocumentBuilder b=f.newDocumentBuilder();b.setEntityResolver((pub,sys)->new InputSource(new StringReader("")));
        return b.parse(new ByteArrayInputStream(bytes));
    }
    public String draft(int index,int selectedTonic,List<String> notices){
        List<Note> raw=new ArrayList<>(tracks.get(index).notes);raw.sort(Comparator.comparingDouble(n->n.at));
        List<Note> melody=new ArrayList<>();boolean chord=false,timing=false;int unsupported=0;
        for(Note n:raw){
            if(!melody.isEmpty()){
                Note previous=melody.get(melody.size()-1);
                if(Math.abs(previous.at-n.at)<.00001){if(n.pitch>previous.pitch){previous.pitch=n.pitch;previous.duration=n.duration;}chord=true;continue;}
                if(previous.pitch==n.pitch && previous.tieOut && n.tieIn && Math.abs(previous.at+previous.duration-n.at)<.00001){previous.duration+=n.duration;previous.tieOut=n.tieOut;continue;}
            }
            melody.add(new Note(n.at,n.duration,n.pitch,n.tieIn,n.tieOut));
        }
        StringBuilder out=new StringBuilder("BPM="+bpm+"\n");double cursor=0;boolean longNote=false;
        boolean overlap=false;
        for(int i=0;i<melody.size();i++){
            Note n=melody.get(i);
            if(i+1<melody.size() && n.at+n.duration>melody.get(i+1).at+.00001){n.duration=melody.get(i+1).at-n.at;overlap=true;}
            if(n.at>cursor+.02)append(out,"0",Math.max(1,(int)Math.round((n.at-cursor)*4)));
            int units=Math.max(1,(int)Math.round(n.duration*4));if(Math.abs(units-n.duration*4)>.05)timing=true;
            if(units>64 && n.pitch>=0)longNote=true;
            String degree="0";
            if(n.pitch>=0){int pc=((n.pitch-selectedTonic)%12+12)%12;int d=Arrays.asList(0,2,4,5,7,9,11).indexOf(pc)+1;degree=d==0?"?":Integer.toString(d);if(d==0)unsupported++;}
            append(out,degree,units);cursor=Math.max(cursor,n.at+n.duration);if(out.length()>150000)throw new IllegalArgumentException("旋律过长，请分文件导入");
        }
        notices.addAll(warnings);notices.add("已将所选调的 do 映射为琴上固定 C，合并高低八度");
        if(chord)notices.add("所选声部含和弦，同一时刻保留最高音作为单旋律，请核对");
        if(overlap)notices.add("所选声部含交叠音，已在下一音起点截断前音用于单旋律跟弹，请核对");
        if(timing)notices.add("含当前最小单位不能精确表达的时值，已量化到十六分音符，请核对");
        if(longNote)notices.add("超过 16 拍的长音已拆成多次事件，跟弹会再次提示按键，请核对");
        if(unsupported>0)notices.add("有 "+unsupported+" 个升降音无法用七个固定键表达，已用 ? 标出，需改编后才能保存上传");
        return out.toString();
    }
    private static void append(StringBuilder s,String degree,int units){if(units>6400)throw new IllegalArgumentException("出现过长空白或延音，请检查原谱");while(units>64){s.append(degree).append(",64\n");units-=64;}s.append(degree).append(',').append(units).append('\n');}
}
