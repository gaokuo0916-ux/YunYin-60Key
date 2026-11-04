from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = Path(__file__).resolve().parent
config = json.loads((ROOT / 'toolchain.json').read_text(encoding='utf-8'))
JAVA = Path(config['java_bin'])
TOOLS = Path(config['build_tools'])
ANDROID = Path(config['android_jar'])
BUILD = ROOT / 'build' / datetime.now().strftime('%Y%m%d_%H%M%S')
BUILD.mkdir(parents=True, exist_ok=False)
for name in ('classes', 'dex', 'generated', 'assets', 'vendor'):
    (BUILD / name).mkdir()
DIST = ROOT / 'dist'
DIST.mkdir(exist_ok=True)

def run(*args):
    print('RUN', Path(str(args[0])).name, flush=True)
    result = subprocess.run([str(a) for a in args], cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    print(result.stdout, flush=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.returncode}')
    return result.stdout

assets = {
    'studio.html': ROOT / 'studio.html',
    'three_notes.bt.txt': ROOT / 'assets/three_notes.bt.txt',
    'twinkle.bt.txt': ROOT / 'assets/twinkle.bt.txt',
    'penghuwan.bt.txt': ROOT / 'assets/penghuwan.bt.txt',
}
for name, source in assets.items():
    shutil.copy2(source, BUILD / 'assets' / name)
(BUILD/'assets/ocr').mkdir()
shutil.copy2(ROOT/'vendor/eng.traineddata',BUILD/'assets/ocr/eng.traineddata')
shutil.copy2(ROOT/'vendor/online_index.html',BUILD/'assets/online_catalog.html')
for name in ('pop909_catalog.tsv','pop909_license.txt','pop909_source.json'):
    shutil.copy2(ROOT/'vendor'/name,BUILD/'assets'/name)
for name in ('expanded_catalog.sqlite','expanded_summary.json','expanded_LICENSE.md','expanded_NOTICE.md'):
    shutil.copy2(ROOT/'vendor'/name,BUILD/'assets'/name)
for name in ('open_catalog.tsv','open_catalog_source.json','open_catalog_NOTICE.md'):
    shutil.copy2(ROOT/'vendor'/name,BUILD/'assets'/name)
open_source=json.loads((ROOT/'vendor/open_catalog_source.json').read_text(encoding='utf-8'))
assert hashlib.sha256((ROOT/'vendor/open_catalog.tsv').read_bytes()).hexdigest()==open_source['sha256']
expanded=json.loads((ROOT/'vendor/expanded_summary.json').read_text(encoding='utf-8'))
assert hashlib.sha256((ROOT/'vendor/expanded_catalog.sqlite').read_bytes()).hexdigest()==expanded['sha256']
assert expanded['sha256'] in (ROOT/'src/cn/fpga/score/ExpandedCatalog.java').read_text(encoding='utf-8')
pop_source=json.loads((ROOT/'vendor/pop909_source.json').read_text(encoding='utf-8'))
assert pop_source['commit'] in (ROOT/'src/cn/fpga/score/PopCatalog.java').read_text(encoding='utf-8')
assert len((ROOT/'vendor/pop909_catalog.tsv').read_text(encoding='utf-8').splitlines())==909
bundled=json.loads((ROOT/'vendor/bundled_midi/summary.json').read_text(encoding='utf-8'))
assert hashlib.sha256((ROOT/'vendor/bundled_midi/files.zip').read_bytes()).hexdigest()==bundled['bundle_sha256']
assert hashlib.sha256((ROOT/'vendor/bundled_midi/catalog.tsv').read_bytes()).hexdigest()==bundled['index_sha256']
shutil.copytree(ROOT/'vendor/bundled_midi',BUILD/'assets/bundled_midi')
for name in ('tess_license.txt','traineddata_license.txt','leptonica_license.txt','libpng_license.txt','libjpeg_license.txt','THIRD_PARTY_NOTICES.txt'):
    shutil.copy2(ROOT/'vendor'/name,BUILD/'assets'/name)
for name in ('lucide_LICENSE.txt','open_props_LICENSE.txt','sources.json'):
    shutil.copy2(ROOT/'vendor/ui'/name,BUILD/'assets'/('ui_'+name))
with zipfile.ZipFile(ROOT/'vendor/tesseract4android-4.9.0.aar') as vendor:
    (BUILD/'vendor/tesseract.jar').write_bytes(vendor.read('classes.jar'))
run(TOOLS / 'aapt2.exe', 'compile', '--dir', ROOT / 'res', '-o', BUILD / 'resources.zip')
run(TOOLS / 'aapt2.exe', 'link', '-o', BUILD / 'resources.apk',
    '-I', ANDROID, '--manifest', ROOT / 'AndroidManifest.xml', BUILD / 'resources.zip',
    '--java', BUILD / 'generated', '-A', BUILD / 'assets')
sources = list((ROOT / 'src').rglob('*.java')) + list((BUILD / 'generated').rglob('*.java'))
run(JAVA / 'javac.exe', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-Xlint:-options',
    '-classpath', os.pathsep.join(map(str,[ANDROID,BUILD/'vendor/tesseract.jar'])), '-d', BUILD / 'classes', *sources)
run(JAVA / 'java.exe', '-cp', TOOLS / 'lib/d8.jar', 'com.android.tools.r8.D8',
    '--lib', ANDROID, '--min-api', '26', '--output', BUILD / 'dex', *list((BUILD / 'classes').rglob('*.class')),BUILD/'vendor/tesseract.jar')
unsigned = BUILD / 'unsigned.apk'
shutil.copy2(BUILD / 'resources.apk', unsigned)
with zipfile.ZipFile(unsigned, 'a', zipfile.ZIP_DEFLATED) as z:
    for dex in (BUILD / 'dex').glob('*.dex'):
        z.write(dex, dex.name)
    with zipfile.ZipFile(ROOT/'vendor/tesseract4android-4.9.0.aar') as vendor:
        for name in vendor.namelist():
            if name.startswith('jni/') and name.endswith('.so'):z.writestr('lib/'+name[4:],vendor.read(name))
run(TOOLS / 'zipalign.exe', '-f', '-P', '16', '4', unsigned, BUILD / 'aligned.apk')
run(TOOLS / 'zipalign.exe', '-c', '-P', '16', '4', BUILD / 'aligned.apk')
key = ROOT / 'signing/local-debug.jks'
key.parent.mkdir(exist_ok=True)
if not key.exists():
    run(JAVA / 'keytool.exe', '-genkeypair', '-noprompt', '-keystore', key,
        '-storepass', 'android', '-keypass', 'android', '-alias', 'yunyin-debug',
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650',
        '-dname', 'CN=YunYin Local Development,O=FPGA Competition,C=CN')
apk = BUILD / 'yunyin_v2_6_6_60key.apk'
run(JAVA / 'java.exe', '-jar', TOOLS / 'lib/apksigner.jar', 'sign', '--ks', key,
    '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--ks-key-alias', 'yunyin-debug',
    '--out', apk, BUILD / 'aligned.apk')
signature = run(JAVA / 'java.exe', '-jar', TOOLS / 'lib/apksigner.jar', 'verify', '--verbose', '--print-certs', apk)
assert re.search(r'Verified using v2 scheme .*: true', signature)
badging = run(TOOLS / 'aapt2.exe', 'dump', 'badging', apk)
assert "package: name='cn.fpga.score'" in badging
assert re.search(r"^(?:minSdkVersion|sdkVersion):'26'$", badging, re.M) and "targetSdkVersion:'35'" in badging
assert 'android.permission.INTERNET' in badging
with zipfile.ZipFile(apk) as z:
    assert z.testzip() is None
    assert z.getinfo('classes.dex').file_size > 10000
    assert z.getinfo('assets/ocr/eng.traineddata').file_size==4113088
    assert z.getinfo('lib/arm64-v8a/libtesseract.so').file_size>1000000
    assert hashlib.sha256(z.read('assets/expanded_catalog.sqlite')).hexdigest()==expanded['sha256']
    assert z.read('assets/open_catalog.tsv')==(ROOT/'vendor/open_catalog.tsv').read_bytes()
    assert hashlib.sha256(z.read('assets/bundled_midi/files.zip')).hexdigest()==bundled['bundle_sha256']
    assert z.read('assets/bundled_midi/catalog.tsv')==(ROOT/'vendor/bundled_midi/catalog.tsv').read_bytes()
    for name in assets:
        assert z.read('assets/' + name) == assets[name].read_bytes()
published = ROOT.parent / '安装包' / apk.name
published.parent.mkdir(exist_ok=True)
shutil.copy2(apk, published)
result = {'apk': str(published), 'bytes': published.stat().st_size,
          'sha256': hashlib.sha256(published.read_bytes()).hexdigest(),
          'android_min': '8.0 (API26)', 'target_api': 35, 'package': 'cn.fpga.score',
          'signed': True, 'signature_verified': True, 'signature_type': 'local development key',
          'internet_permission': True, 'offline_image_ocr':True,'persistent_phone_library':True,
          'event_capacity':8192, 'version':'2.6.6','fpga_rhythm_scoring':True,'phone_scoring':False,'bounded_challenge_history':100,
          'song_challenges':{'format':2,'songs':[x['title'] for x in json.loads((ROOT.parent/'config/challenge_catalog.json').read_text(encoding='utf-8'))['songs']],'accompaniment':'disabled in current firmware; live keyboard audio retained','clock':'FPGA milliseconds shared with judge','firmware_update_required':True,'physical_board_test':False},
          'online_catalog':['https://github.com/music-x-lab/POP909-Dataset','https://musetrainer.github.io/library/','https://github.com/midicn/midi-library','https://commons.wikimedia.org/'],
          'open_score_versions':open_source['score_versions'],'open_catalog_metadata_only':True,'paged_all_source_search':True,'score_browser_and_link_import':True,'music_shares_are_title_search_only':True,
          'midishow_integration':{'mode':'website session','direct_title_search':True,'sorting':['relevance','newest','popular'],'validated_file_handoff':True,'failure_retains_browser':True,'official_bulk_api':False,'website_login_download_physical_phone_verified':False},
          'free_score_search':{'native_bitmidi_public_html':True,'public_file_download_and_original_parse':True,'account_or_payment_required':False,'website_catalog_not_mirrored':True,'chinese_coverage_not_guaranteed':True},
          'live_online_score_browsing':['https://bitmidi.com/','https://lib.midicn.com/','https://www.midishow.com/midi/browse/pop-music','https://musescore.com/sheetmusic'],'website_catalog_mirrored':False,
          'original_score_import':{'preserves_entire_file':True,'chromatic_pitches_and_octaves':True,'all_tracks_and_tempo_data_preserved_in_source':True,'seven_key_conversion_required':False,'full_pitch_board_upload_implemented':True,'mode':'selected voice self-paced original pitches','missing_keys':'explicit prompt and manual skip','native_tf_persistence':True,'native_tf_capability':'0x1000'},
          'bundled_midi':bundled,'bundled_effective_chinese_versions':2301,'featured_practice_songs':['没有共产党就没有新中国','歌唱祖国','我爱你中国（海外赤子）','茉莉花','送别'],
          'pop_catalog_count':909,'pop_catalog_commit':pop_source['commit'],'midi_import':True,
          'expanded_score_versions':expanded['included'],'expanded_groups':expanded['groups'],
          'expanded_metadata_only':True,'external_search_and_file_open':True,
          'ui_design':'continuous snap record shelf, persistent telemetry controls, restrained native web animations, local Lucide icons',
          'ui_sources':json.loads((ROOT/'vendor/ui/sources.json').read_text(encoding='utf-8-sig')),
          'timbre_selection': {'capability':'0x0100','ids':['piano','guitar','accordion'],'query':'TINFO','set':'TONE n','confirmation':'actual TONE n reply plus TINFO readback','old_firmware':'selector disabled; existing functions retained'},
          'polyphony': {'capability':'0x0200','voice_pool':32,'query':'PINFO','demo':'PDEMO count mode','stop':'PCLR','release':'PMUTE slot','retune':'PTUNE slot bin','actual_board_readback_required':True,'physical_60_key_scanner_implemented':True},
          'recording': {'mode':'TF streaming multi-take practice directory','capability':'0x8000','short_ram_take_removed':True,'ring_bytes':32768,'maximum_seconds':120,'new_slots':20,'legacy_audio_views':2,'container_bytes':268435456,'legacy32MiB_preserved':True,'card_authoritative_index':True,'phone_time_opt_in':True,'metadata_page_bytes':512,'wav_export_crc_checked':True,'physical_board_test':False},
          'phone_install_or_real_ble_test_performed': False,
          'app_sources': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in list((ROOT / 'src').rglob('*.java'))+[ROOT/'studio.html',ROOT/'AndroidManifest.xml',ROOT/'build.py']+list((ROOT/'res').rglob('*.xml'))}}
(DIST / 'build_results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
(DIST / 'build_results_v2_6_6.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
(DIST / 'apk_signature.txt').write_text(signature, encoding='utf-8')
(DIST / 'apk_manifest.txt').write_text(badging, encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
