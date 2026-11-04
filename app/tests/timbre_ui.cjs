const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/accordion_timbre');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1}),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=v=>page.evaluate(x=>window.YY.update(x),v),buttons=page.locator('[data-timbre]');
  await update({page:'device',ready:false,capabilities:0});
  for(const b of await buttons.all())assert(await b.isDisabled());
  await update({ready:true,capabilities:255,featuresIdentified:true});
  for(const b of await buttons.all())assert(await b.isDisabled());
  assert((await page.locator('#timbre-note').textContent()).includes('当前固件未提供音色控制'));
  assert(!(await page.locator('#mapping-apply').isDisabled())); // Existing ability retained.
  await update({capabilities:511,timbreKnown:false,keys:0,storageState:1,longState:0});
  assert.equal(await page.locator('[data-timbre][aria-pressed=true]').count(),0);
  await update({timbreKnown:true,timbre:0});
  assert.equal(await page.locator('[data-timbre="0"]').getAttribute('aria-pressed'),'true');
  await page.locator('[data-timbre="2"]').click();
  assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'timbre-set',payload:'2'});
  // A tap alone cannot invent a successful change.
  assert.equal(await page.locator('[data-timbre="2"]').getAttribute('aria-pressed'),'false');
  assert.equal(await page.locator('[data-timbre="0"]').getAttribute('aria-pressed'),'true');
  await update({busy:true});for(const b of await buttons.all())assert(await b.isDisabled());
  await update({busy:false,timbreKnown:true,timbre:2});
  assert.equal(await page.locator('[data-timbre="2"]').getAttribute('aria-pressed'),'true');
  assert((await page.locator('#timbre-status').textContent()).includes('手风琴'));
  assert.deepEqual(await page.locator('[data-timbre="2"]').evaluate(e=>({bg:getComputedStyle(e).backgroundColor,color:getComputedStyle(e).color})),{bg:'rgb(47, 84, 68)',color:'rgb(255, 249, 237)'});
  assert((await page.locator('#timbre-shortcut').textContent()).includes('手风琴'));
  await update({timbre:1});assert.equal(await page.locator('[data-timbre="1"]').getAttribute('aria-pressed'),'true');
  await update({keys:1});for(const b of await buttons.all())assert(await b.isDisabled());
  assert((await page.locator('#timbre-note').textContent()).includes('松开全部琴键'));
  await update({keys:0,storageState:2});for(const b of await buttons.all())assert(await b.isDisabled());
  await update({storageState:1,longState:2});for(const b of await buttons.all())assert(await b.isDisabled());
  await update({longState:0,timbreKnown:false});assert.equal(await page.locator('[data-timbre][aria-pressed=true]').count(),0);
  await update({timbreKnown:true,timbre:2});
  await page.screenshot({path:path.join(out,'device_accordion.png'),fullPage:true});
  for(const width of [320,390,720]){
   await page.setViewportSize({width,height:844});
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));
   for(const b of await buttons.all())assert((await b.boundingBox()).height>=44);
  }
  await page.emulateMedia({colorScheme:'dark'});await page.screenshot({path:path.join(out,'device_accordion_dark.png'),fullPage:true});
  await update({ready:false});for(const b of await buttons.all())assert(await b.isDisabled());
  assert.equal(await page.locator('[data-timbre][aria-pressed=true]').count(),0);
  assert.equal(errors.length,0,errors.join('\n'));
  const result={passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),tests:['old firmware disabled with explanation, mapping preserved','exact timbre-set action and no optimistic success','three actual readbacks and physical changes','busy, keys pressed, storage and recording guards','failed readback removes confirmation','disconnect removes confirmation','320/390/720 widths, 44px targets, light and dark'],physical_phone_or_BLE_test:false};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
