from pathlib import Path
import subprocess,json,sys,re
ROOT=Path(__file__).resolve().parent
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
config=json.loads((ROOT/'toolchain.json').read_text())
java=Path(config['java_bin']);out=ROOT/'verification';classes=out/'classes';classes.mkdir(parents=True,exist_ok=True)
sources=['ChallengeSongs','Score','SongDraft','LibraryStore','OnlineCatalog','PopCatalog','MidiImport','MusicXmlImport','JianpuGeometry','Uploader','ReplyFrames','ExpandedDownload','KeyMapping','StudioProtocol','StudioMonitor','CardAudio','RhythmStatus','RhythmHistory','ScoreWebImport','OpenCatalog','CatalogPager','SongShare','MidiShowSource','WebScoreStage','BundledMidiCatalog','OriginalScore','OriginalScoreStore','OriginalPractice','FreeMidiSource']
tests=['CoreTests','V2Tests','MidiTests','ExpandedTests','StudioTests','CardAudioTests','RhythmTests','StudioMonitorTests','TfRecoveryTests','TimbreTests','PolyphonyTests','LibraryWebTests','MidiShowTests','BundledMidiTests','OriginalScoreTests','NativeTrialTests','FreeMidiTests','NativeTfTests','Keyboard60Tests','MultiSongTests']
def run(args):
 p=subprocess.run(list(map(str,args)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',errors='replace')
 if p.returncode:raise RuntimeError(p.stdout)
 return p.stdout
print(run([java/'javac.exe','-encoding','UTF-8','-d',classes]+[ROOT/'src/cn/fpga/score'/f'{s}.java' for s in sources]+[ROOT/'tests'/f'{s}.java' for s in tests]))
results={}
for test in tests:
 result=run([java/'java.exe','-Dfile.encoding=UTF-8','-cp',classes,'cn.fpga.score.'+test,ROOT]);print(result);(out/(test+'.txt')).write_text(result,encoding='utf-8');results[test]=result.strip().splitlines()[-1]
results['physical_android_or_ble_test']=False
version=re.search(r'android:versionName="([^"]+)"',(ROOT/'AndroidManifest.xml').read_text(encoding='utf-8'))[1]
(out/('v'+version.replace('.','_')+'_results.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
