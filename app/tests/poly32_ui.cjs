const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/poly32');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8'),errors=[];
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=x=>page.evaluate(v=>window.YY.update(v),x);
  await update({page:'device',ready:true,capabilities:507});assert(await page.locator('[data-poly-demo="32"]').isDisabled());
  await update({capabilities:1019,polyKnown:true,polyActive:0,polyHeld:0,polyDemo:false,polySingle:false});
  assert(!(await page.locator('[data-poly-demo="32"]').isDisabled()));assert(await page.locator('#poly-release').isDisabled());
  await page.locator('[data-poly-demo="32"]').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'poly-demo',payload:'32'});
  await update({polyActive:32,polyHeld:32,polyDemo:true,polySingle:true});assert((await page.locator('#poly-status').textContent()).includes('32 / 32'));
  await page.locator('#poly-slot').selectOption({value:'5'});await page.locator('#poly-retune').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'poly-retune',payload:'5'});
  await page.locator('#poly-release').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'poly-release',payload:'5'});
  await update({polyActive:32,polyHeld:31});assert((await page.locator('#poly-status').textContent()).trim().endsWith('31'));
  await update({polyActive:31});await page.locator('[data-action="poly-stop"]').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'poly-stop',payload:''});
  await update({polyDemo:false,polyActive:0,polyHeld:0,polySingle:false});await page.locator('[data-action="poly-music"]').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'poly-music',payload:''});
  await update({polyDemo:true,polyActive:32,polyHeld:32,polySingle:false});assert(await page.locator('#poly-retune').isDisabled());
  await update({busy:true});assert(await page.locator('[data-poly-demo="32"]').isDisabled());await update({busy:false});
  await page.locator('#poly-panel').screenshot({path:path.join(out,'poly32_panel.png')});
  for(const width of [320,390,700])for(const theme of ['light','dark']){
   await page.setViewportSize({width,height:844});await page.emulateMedia({colorScheme:theme});
   for(const id of ['perform','challenge','library','device','takes']){await update({page:id});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);}
  }
  assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),physical_phone_test:false,
   checked:['old firmware guarded','32-voice command','real count display','release','retune','stop','musical mode','busy','five pages/three widths/two themes']},null,2)+'\n');
  console.log('PASS poly32 UI: commands, state readback, old firmware guards and layouts');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
