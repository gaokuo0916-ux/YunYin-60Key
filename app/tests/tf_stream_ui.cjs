const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/tf_stream');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8'),errors=[];
 assert(!html.includes('1.34')&&!html.includes('record-arm')&&!html.includes('record-download'));
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=v=>page.evaluate(x=>window.YY.update(x),v);
  await page.locator('#page-takes details').evaluate(e=>e.open=true);
  await update({page:'takes',ready:false,capabilities:0});assert(await page.locator('#audio-arm').isDisabled());
  await update({ready:true,capabilities:507,storageState:4,longState:0,longSaved:false});
  assert(await page.locator('#audio-arm').isDisabled());
  await update({storageState:1});assert(!(await page.locator('#audio-arm').isDisabled()));
  await page.locator('#audio-duration').selectOption('120');await page.locator('#audio-arm').click();
  assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'audio-arm',payload:'120'});
  await update({longState:1});assert(await page.locator('#audio-arm').isDisabled());assert(!(await page.locator('#audio-stop').isDisabled()));
  await update({longState:2,longMessage:'琴端录音中 · 12.0 秒'});assert(!(await page.locator('#audio-stop').isDisabled()));
  await page.locator('#audio-stop').click();assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'audio-stop',payload:''});
  await update({longState:6});assert(await page.locator('#audio-stop').isDisabled());assert(await page.locator('#audio-download').isDisabled());
  await update({longState:3,longSaved:true});assert(!(await page.locator('#audio-download').isDisabled()));
  await update({longState:4,longSaved:true,longMessage:'TF 写入未能跟上，录音缓存已满；本次录音已停止，上次完整录音仍保留'});
  assert((await page.locator('#long-state').textContent()).includes('上次完整录音仍保留'));
  assert(!(await page.locator('#audio-arm').isDisabled()));assert(!(await page.locator('#audio-download').isDisabled()));
  await page.screenshot({path:path.join(out,'recording_page.png'),fullPage:true});
  for(const width of [320,390,700])for(const theme of ['light','dark']){
   await page.setViewportSize({width,height:844});await page.emulateMedia({colorScheme:theme});
   for(const id of ['perform','challenge','library','device','takes']){
    await update({page:id});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
   }
  }
  assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),
   removed_short_recording:true,checked:['no card','ready','arm120','record','stop','flush','download','overflow/retry','five pages, three widths, two themes'],physical_phone_test:false},null,2)+'\n');
  console.log('PASS TF stream UI: retired short capture, card gating, 120s arm, stop/flush/download, overflow/retry, all pages and sizes');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
