const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/keyboard60');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];let checks=0;
  page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=x=>page.evaluate(v=>window.YY.update(v),x);
  await update({page:'perform',ready:true,busy:false,playing:true,paused:false,free:false,uploaded:true,capabilities:0x3ffb,featuresIdentified:true,
   keyboard60:true,keyboardKnown:true,keyboardBase:36,keyboardCount:60,keyboardMask:'0800000000000001',keys:1,
   nativePitch:true,nativeKnown:true,nativeCode:38,nativeMissing:false,notes:[[38,250]],count:1,index:0,guideState:2,telemetry:true,rank:0,rhythm:null});
  assert.equal(await page.locator('#keyboard .key').count(),60);checks++;
  assert.equal(await page.locator('#keyboard .black').count(),25);checks++;
  for(let i=0;i<60;i++){assert.equal(await page.locator('#keyboard .key').nth(i).evaluate(e=>e.classList.contains('down')),i===0||i===59);checks++;}
  assert.equal(await page.locator('#keyboard .target').getAttribute('data-pitch'),'37');checks++;
  assert((await page.locator('#keyboard-range').textContent()).includes('C2～B6'));checks++;
  assert(await page.locator('#keyboard').evaluate(e=>e.scrollWidth>e.clientWidth));checks++;
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=390));checks++;
  await page.screenshot({path:path.join(out,'perform60.png'),fullPage:true});
  await update({notes:[[37,250]],nativeCode:37,keyboardMask:'0000000000000000',rank:5039,keys:0});
  assert.equal(await page.locator('#keyboard .target').evaluate(e=>Array.from(e.parentElement.children).indexOf(e)),11);checks++;
  await update({notes:[[97,250]],nativeCode:97,nativeMissing:true});
  assert.equal(await page.locator('#keyboard .target').count(),0);checks++;
  assert(!(await page.locator('#native-skip').isDisabled()));checks++;
  assert(!(await page.locator('#feedback').textContent()).includes('当前七键'));checks++;
  await update({page:'device',playing:false,guideState:0,telemetry:false,rank:0,keys:0,keyboardBase:24});
  assert(await page.locator('#keyboard-controls').isVisible());checks++;
  assert.equal(await page.locator('#keyboard-octave').inputValue(),'1');checks++;
  await page.locator('#keyboard-octave').selectOption('2');
  assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'keyboard-octave',payload:'2'});checks++;
  for(const state of [{keys:1},{keys:0,playing:true},{playing:false,paused:true},{paused:false,busy:true},{busy:false,keyboardKnown:false}]){
   await update(state);assert(await page.locator('#keyboard-octave').isDisabled());checks++;
  }
  await update({keyboardKnown:true,keyboardBase:36,storageState:1,uploaded:true,nativePitch:true,paused:false,busy:false,keys:0});
  assert(!(await page.locator('#card-save').isDisabled()));checks++;
  await page.screenshot({path:path.join(out,'device60.png'),fullPage:true});
  await update({page:'challenge',keyboard60:true,capabilities:0x3ffb,rhythm:{songPack:1,enabled:true,state:2,level:3,unlocked:3,cursor:4,degree:1,nextDegree:1,bpm:120,phase:'演奏',judgement:'等待判定'}});
  assert.equal(await page.locator('#game-target').textContent(),'C5');checks++;assert.equal(await page.locator('#game-next').textContent(),'C5');checks++;
  await update({page:'perform',keyboard60:false,capabilities:0x1ffb,rank:0,notes:[[61,250]],nativeCode:61,nativeMissing:false});
  assert.equal(await page.locator('#keyboard .key').count(),7);checks++;
  assert.equal(errors.length,0,errors.join('\n'));
  const result={passed:true,checks,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),physical_phone_or_ble_test:false};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
