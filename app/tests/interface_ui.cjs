// Exercise the actual packaged document, with an action-recording native bridge.
const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/ui_refresh_2_5_2');
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1,reducedMotion:'reduce'}),errors=[],requests=[];
  page.on('pageerror',e=>errors.push(String(e)));page.on('request',r=>requests.push(r.url()));
  await fs.mkdir(out,{recursive:true});
  const old=await fs.readFile(path.join(root,'../verification/practice_records_20261029/before/app/studio.html'),'utf8');
  const notation='115566544332215544332554433211556654433221'.split('').map((n,i)=>[+n,i%7===6?8:4]);
  const initial={page:'perform',title:'小星星',artist:'七键旋律曲谱',notes:notation,count:notation.length,bpm:120,ready:false};
  const load=async content=>{await page.setContent(content.replace('<script>','<script>window.YunYin={action(){}};'));await page.evaluate(v=>window.YY.update(v),initial)};
  await load(old);await page.screenshot({path:path.join(out,'before_perform.png')});
  await load(html);await page.screenshot({path:path.join(out,'after_perform.png')});
  await page.evaluate(()=>{window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})}});
  const update=fields=>page.evaluate(v=>window.YY.update(v),fields);
  await update({ready:true,capabilities:127,featuresIdentified:true,uploaded:true,playing:true,telemetry:true,keys:1,index:0});
  await page.evaluate(()=>{window.noteNode=document.querySelector('#notes .note');window.keyNode=document.querySelector('#keyboard .key')});
  await update({keys:2,index:1});
  assert.equal(await page.evaluate(()=>window.noteNode===document.querySelector('#notes .note')&&window.keyNode===document.querySelector('#keyboard .key')),true,'telemetry must preserve score/key DOM and its transitions');
  assert.equal(await page.locator('#keyboard .down').count(),1);
  assert.equal(await page.locator('#notes .current').count(),1);
  await update({playing:false,ready:false,uploaded:false,keys:0,telemetry:false});
  await page.locator('nav [data-page="library"]').click();
  await page.locator('[data-category="mine"]').click();
  const songs=[{id:'star',title:'小星星',subtitle:'传统旋律 · 已存手机',local:true},{id:'bay',title:'外婆的澎湖湾',subtitle:'潘安邦 · 七键改编',local:true},{id:'joy',title:'欢乐颂',subtitle:'贝多芬 · 已存手机',local:true},{id:'practice',title:'慢弹练习',subtitle:'本地曲谱 · 80 BPM',local:true}];
  const library=()=>page.evaluate(data=>window.YY.library(data,data.length,'mine',''),songs);
  await library();await page.waitForTimeout(50);
  await page.screenshot({path:path.join(out,'after_library.png')});
  await page.evaluate(()=>window.firstCover=document.querySelector('#shelf .sleeve'));
  await page.locator('#cover-next').click();
  await page.waitForFunction(()=>window.YY.inspect().focus===1);
  await library();await page.waitForTimeout(40);
  assert.equal(await page.evaluate(()=>window.firstCover===document.querySelector('#shelf .sleeve')),true,'same library response must preserve native scrolling DOM');
  assert.equal(await page.evaluate(()=>window.YY.inspect().focus),1,'refresh must preserve selected record');
  await page.locator('.sleeve.is-focus').click();
  assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'select',payload:'bay'});
  await page.evaluate(()=>{document.querySelector('#shelf').scrollLeft=9999});
  await page.waitForFunction(()=>window.YY.inspect().focus===3);
  assert.equal(await page.locator('#cover-next').isDisabled(),true);
  // Check all pages, both system themes, a narrow phone and a tablet.
  for(const theme of ['light','dark']){
   await page.emulateMedia({colorScheme:theme});
   for(const width of [320,390,430,700]){
    await page.setViewportSize({width,height:844});
    for(const id of ['perform','library','challenge','device','takes']){
     await update({page:id});
     assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,theme+' overflow '+width+' '+id);
     assert.equal(await page.locator('#page-'+id).isVisible(),true);
    }
   }
  }
  await page.setViewportSize({width:390,height:844});await update({page:'library'});
  await page.screenshot({path:path.join(out,'after_library_dark.png')});
  await page.emulateMedia({colorScheme:'light',reducedMotion:'no-preference'});
  await update({page:'perform',playing:true});
  assert.equal(await page.locator('.disc').evaluate(e=>getComputedStyle(e).animationPlayState),'running');
  await update({playing:false,paused:true});
  assert.equal(await page.locator('.disc').evaluate(e=>getComputedStyle(e).animationPlayState),'paused');
  await page.evaluate(()=>window.YY.back());
  assert.equal(await page.evaluate(()=>window.YY.inspect().page),'perform');
  await update({page:'library'});await page.evaluate(()=>window.YY.back());
  assert.equal(await page.evaluate(()=>window.YY.inspect().page),'perform');
  assert.equal(await page.locator('nav button svg').count(),5);
  await update({page:'perform',ready:false,playing:false,paused:false});
  await update({percent:12});
  assert.equal(await page.locator('#primary svg').count(),1,'status polling must preserve transport icon');
  assert.equal(await page.locator('#connection svg').count(),1,'status polling must preserve connection icon');
  for(const height of [740,844]){
   await page.setViewportSize({width:390,height});await page.evaluate(()=>window.scrollTo(0,0));
   const action=await page.locator('#primary').boundingBox(),nav=await page.locator('nav').boundingBox();
   assert.ok(action.y>=0 && action.y+action.height<=nav.y,'primary action must stay above navigation '+height);
  }
  await page.evaluate(()=>{Element.prototype.getAnimations=undefined;window.YY.update({page:'device'})});
  assert.equal(await page.locator('#page-device').isVisible(),true,'older WebViews without getAnimations still navigate');
  assert.deepEqual(errors,[]);assert.deepEqual(requests,[],'bundled UI must need no remote runtime');
  const report={passed:true,checks:['persistent score/key nodes during real telemetry','record shelf continuous scroll/snap and bounds','library refresh preserves focus/DOM','real select action','five pages at 320/390/430/700 px in light/dark','record motion only while playing','back to performance','offline local SVG icons'],physical_phone:false,html_sha256:require('node:crypto').createHash('sha256').update(html).digest('hex')};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(report,null,2));console.log('PASS interface_ui: '+report.checks.join('; '));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
