// Exercise the actual bundled HTML with a mock Android bridge; never send BLE.
const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/multisong');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8'),songs=JSON.parse(await fs.readFile(path.join(root,'../config/challenge_catalog.json'),'utf8')).songs;
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];let checks=0;page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=v=>page.evaluate(x=>window.YY.update(x),v);
  const state=song=>({songPack:2,songId:song.id,songTitle:song.title,rangeMissing:false,enabled:true,state:0,level:song.level+1,unlocked:3,bpm:song.bpm,cursor:0,events:song.events.length,notes:song.notes,phase:'选曲就绪',judgement:'等待判定',score:0,best:0,combo:0,maxCombo:0});
  for(const song of songs){
   const g=state(song);await update({page:'challenge',ready:true,busy:false,capabilities:0x7ffb,featuresIdentified:true,keyboard60:true,keyboardKnown:true,keyboardBase:36,keyboardMask:'0000000000000000',keys:0,rhythm:g});
   assert.equal(await page.locator('#game-levels button').count(),3);checks++;
   assert.equal(await page.locator('#game-songs button').count(),5);checks++;
   assert.equal(await page.locator('#game-songs button[aria-pressed=true] strong').textContent(),song.title);checks++;
   await page.locator('#game-songs button').nth(song.id%5).click();
   assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'challenge-song',payload:String(song.id+1)});checks++;
   await page.locator('#game-play').click();assert.equal((await page.evaluate(()=>window.actions.at(-1))).name,'challenge-play');checks++;
   for(let start=0;start<song.events.length;start+=8){
    const cursor=Math.min(start+2,song.events.length-1);await update({rhythm:{...g,state:2,cursor,phase:'挑战中'}});
    const visible=await page.locator('.exercise-note').evaluateAll(ns=>ns.map(n=>({degree:+n.firstChild.textContent,time:n.title,note:n.querySelector('small').textContent})));
    assert.deepEqual(visible.map(n=>n.degree),song.events.slice(start,start+8).map(e=>e.degree));checks++;
    visible.forEach((v,i)=>{assert.equal(v.time,song.events[start+i].units/4+' 拍');checks++});
    assert((await page.locator('#exercise-page').textContent()).includes(song.title));checks++;
   }
   assert(await page.locator('#game-play').isDisabled());checks++;
   for(const b of await page.locator('#game-songs button,#game-levels button').all()){assert(await b.isDisabled());checks++;}
   await update({rhythm:{...g,state:3,phase:'已暂停'}});assert.match(await page.locator('#game-pause').textContent(),/继续/);checks++;
   await update({rhythm:{...g,state:5,passed:true,score:100,best:100,phase:'本轮结束'}});assert(!(await page.locator('#game-play').isDisabled()));checks++;
   if([0,6,12].includes(song.id))await page.screenshot({path:path.join(out,'level'+(song.level+1)+'.png'),fullPage:true});
  }
  await update({rhythm:{...state(songs[14]),rangeMissing:true}});assert(await page.locator('#game-play').isDisabled());assert.match(await page.locator('#game-status').textContent(),/退出挑战/);checks+=2;
  await update({rhythm:{...state(songs[0]),unlocked:1}});assert(await page.locator('#game-levels button').nth(1).isDisabled());checks++;
  for(const width of [320,360,390,736]){await page.setViewportSize({width,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));checks++;}
  await update({ready:false,rhythm:null});assert(await page.locator('#game-play').isDisabled());checks++;
  assert.deepEqual(errors,[]);const result={passed:true,checks,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),songs:15,songs_per_level:5,physical_phone_or_ble_test:false};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
