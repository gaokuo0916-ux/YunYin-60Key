// Own bundled WebView HTML only. Mock bridge records actions; no device commands.
const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
(async()=>{
 const root=path.resolve(__dirname,'..'),html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 new vm.Script(html.match(/<script>([\s\S]*?)<\/script>/)[1]);
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:1,reducedMotion:'reduce'});
  const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html);await page.evaluate(()=>{window.bridgeActions=[];window.YunYin={action:(name,payload)=>window.bridgeActions.push({name,payload})}});
  const game={enabled:true,state:2,level:2,unlocked:2,countIn:0,bpm:100,degree:3,nextDegree:2,cursor:13,events:24,score:45,combo:8,maxCombo:8,perfect:9,good:3,wrong:1,missed:0,extra:0,best:82,notes:24,passed:false,round:4,phase:'挑战中',judgement:'提前',deviation:-48};
  const completed={...game,state:5,phase:'本轮结束',passed:true,score:82,unlocked:3,perfect:18,good:3,wrong:1,missed:2,combo:3,maxCombo:12,cursor:24,degree:0,nextDegree:0};
  const update=async fields=>page.evaluate(v=>window.YY.update(v),fields);
  await update({page:'challenge',ready:true,featuresIdentified:true,mappingKnown:true,capabilities:127,busy:false,rhythm:game,challengeHistory:[{...completed,time:1792479600000}]});
  assert.equal(await page.locator('#game-score').textContent(),'45');
  assert.equal(await page.locator('.exercise-note.current').evaluate(n=>n.firstChild.textContent),'3');
  assert.equal(await page.locator('.exercise-note').count(),8);
  // The notation sent to a person must match the actual FPGA exercise ROM,
  // including rests, page boundaries and eighth-note strokes.
  const rom=await fs.readFile(path.join(root,'../src/training_score_rom.v'),'utf8');
  const songs=JSON.parse(await fs.readFile(path.join(root,'../config/challenge_songs.json'),'utf8')).songs;
  for(let level=1;level<=3;level++){
   const song=songs[level-1],block=rom.split(`2'd${level-1}:begin`)[1].split(/2'd\d:begin/)[0];
   const notes=[...block.matchAll(/6'd(\d+):begin (?:pitch=\d+;next_pitch=\d+;)?degree=(\d);next_degree=\d;onset_units=(\d+);due_ms=(\d+);duration_units=(\d+);end/g)].map(m=>({degree:+m[2],onset:+m[3],due_ms:+m[4],units:+m[5]}));
   assert.deepEqual(notes,song.events.map(({degree,onset,due_ms,units})=>({degree,onset,due_ms,units})));
   for(let start=0;start<notes.length;start+=8){
    const cursor=Math.min(start+5,notes.length-1);
    await update({capabilities:2047,rhythm:{...game,songPack:1,songTitle:song.title,level,unlocked:3,bpm:song.bpm,degree:notes[cursor].degree,nextDegree:notes[cursor+1]?.degree||0,events:notes.length,notes:song.notes,cursor}});
    assert.equal(await page.locator('#game-levels button').nth(level-1).locator('strong').textContent(),song.title);
    const visible=await page.locator('.exercise-note').evaluateAll(ns=>ns.map(n=>({degree:+n.firstChild.textContent,eighth:n.classList.contains('eighth'),measure:n.classList.contains('measure')})));
    assert.deepEqual(visible.map(n=>n.degree),notes.slice(start,start+8).map(n=>n.degree));
    visible.forEach((n,i)=>{assert.equal(n.eighth,notes[start+i].units===1);assert.equal(n.measure,i>0&&notes[start+i].onset%8===0);});
    assert.equal(+(await page.locator('.exercise-note.current').evaluate(n=>n.firstChild.textContent)),notes[cursor].degree);
   }
  }
  await page.screenshot({path:path.join(root,'verification/song_challenges_phone.png'),fullPage:true});
  await update({capabilities:127,rhythm:game});
  assert.equal(await page.locator('#game-levels button').nth(0).locator('strong').textContent(),'跟稳拍子','old FPGA must not pretend to play songs');
  await update({rhythm:game});
  assert.equal(await page.locator('#game-levels button').nth(2).isDisabled(),true);
  await page.locator('#game-levels button').nth(1).click();await page.locator('#game-play').click();
  assert.deepEqual((await page.evaluate(()=>window.bridgeActions)).slice(-2),[{name:'challenge-select',payload:'2'},{name:'challenge-play',payload:'2'}]);
  assert.equal(await page.locator('#game-score').textContent(),'45','button must not invent a score');
  await page.evaluate(()=>{window.savedLevel=document.querySelector('#game-levels button');window.savedHistory=document.querySelector('.game-history')});
  await update({rhythm:{...game,combo:9}});
  assert.equal(await page.evaluate(()=>window.savedLevel===document.querySelector('#game-levels button')&&window.savedHistory===document.querySelector('.game-history')),true,'score refresh must not replace tappable level controls or unchanged history');
  await update({rhythm:game});
  await page.screenshot({path:path.join(root,'verification/game_phone.png'),fullPage:true});
  await page.screenshot({path:path.join(root,'verification/game_phone_viewport.png'),fullPage:false});
  await update({rhythm:{...game,state:3,phase:'已暂停'}});assert.match(await page.locator('#game-pause').textContent(),/继续/);
  await page.locator('#game-pause').click();assert.equal((await page.evaluate(()=>window.bridgeActions.at(-1))).name,'challenge-pause');
  await update({rhythm:completed});
  assert.equal(await page.locator('.exercise-note.current').count(),0,'completed round must not suggest a live target');
  assert.equal(await page.locator('#game-result').isVisible(),true);assert.match(await page.locator('#game-result').textContent(),/下一关已解锁/);
  await page.screenshot({path:path.join(root,'verification/game_results_phone.png'),fullPage:true});
  await update({ready:false,rhythm:null});assert.equal(await page.locator('#game-play').isDisabled(),true);assert.equal(await page.locator('.game-history').count(),1);assert.equal(await page.locator('#game-score').textContent(),'—');
  await update({ready:true,capabilities:63,rhythm:null});assert.equal(await page.locator('#game-play').isDisabled(),true);assert.match(await page.locator('#game-status').textContent(),/配套游戏版固件/);
  // An unreadable optional status must not look like unsupported firmware.
  await update({ready:true,featuresIdentified:false,capabilities:0,rhythm:null,featureMessage:'功能识别超时'});
  assert.match(await page.locator('#game-status').textContent(),/重新识别琴端/);
  await update({page:'device'});assert.equal(await page.locator('#device-refresh').isDisabled(),false);
  await page.locator('#device-refresh').click();assert.equal((await page.evaluate(()=>window.bridgeActions.at(-1))).name,'device-refresh');
  await update({featuresIdentified:true,capabilities:127,queryWarning:'TF 查询暂时失败',rank:0,draftRank:0,mappingKnown:false});
  assert.equal(await page.locator('#mapping-apply').isDisabled(),false);
  assert.equal(await page.locator('#mapping-status').textContent(),'尚未读回键位');
  await update({mappingKnown:true});await page.locator('#mapping select').nth(0).selectOption('2');
  await page.locator('#mapping-apply').click();assert.deepEqual(await page.evaluate(()=>window.bridgeActions.at(-1)),{name:'apply-map',payload:'720'});
  assert.equal(await page.locator('#mapping-status').textContent(),'尚未应用到琴端','no false success before board readback');
  await update({rank:720,draftRank:720,mappingKnown:true});assert.equal(await page.locator('#mapping-status').textContent(),'琴端已确认');
  await update({page:'challenge',rhythm:null});assert.equal(await page.locator('#game-play').isDisabled(),false);
  assert.match(await page.locator('#game-status').textContent(),/TF 查询暂时失败/);
  await update({busy:true});assert.equal(await page.locator('#game-play').isDisabled(),true);
  await update({busy:false,queryWarning:'',rank:0,draftRank:0});
  await update({ready:true,capabilities:127,rhythm:game});
  for(const width of [320,390,700]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`horizontal overflow ${width}`);}
  await page.setViewportSize({width:390,height:844});await page.emulateMedia({colorScheme:'dark'});await page.screenshot({path:path.join(root,'verification/game_phone_dark.png'),fullPage:true});
  for(const id of ['perform','library','device','takes','challenge']){await update({page:id});assert.equal(await page.locator('#page-'+id).isVisible(),true);}
  assert.deepEqual(errors,[]);
  const report={passed:true,checks:'all song ROM pages and durations, legacy firmware labels, actions, real-state-only score, locked level, pause/results, disconnect/old firmware, history, capability recovery, auxiliary failure retains controls, mapping write/readback, busy guards, 320/390/700px, dark mode, existing pages',physical_phone:false,html_sha256:require('node:crypto').createHash('sha256').update(html).digest('hex')};
  await fs.writeFile(path.join(root,'verification/game_ui_results.json'),JSON.stringify(report,null,2));console.log('PASS game_ui: '+report.checks);
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
