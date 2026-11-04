const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/native_tf');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1}),errors=[];let checks=0;
  page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=v=>page.evaluate(x=>window.YY.update(x),v);
  const disabled=async expected=>{assert.equal(await page.locator('#card-save').isDisabled(),expected);checks++;};
  await update({page:'device',ready:true,busy:false,playing:false,paused:false,keys:0,capabilities:0xffb,featuresIdentified:true,
    storageState:1,storageError:0,uploaded:true,nativePitch:true,notes:[[61,250],[62,250],[73,250],[63,500]],count:4,rhythm:null});
  await disabled(true);assert((await page.locator('#storage-action-note').textContent()).includes('更新'));checks++;
  await update({capabilities:0x1ffb});await disabled(false);
  await page.locator('#card-save').click();assert.equal((await page.evaluate(()=>window.actions.at(-1))).name,'card-save');checks++;
  for(const state of [{playing:true},{playing:false,paused:true},{paused:false,keys:1},{keys:0,busy:true},{busy:false,uploaded:false},{uploaded:true,storageState:2},{storageState:4}]){await update(state);await disabled(true);}
  await update({storageState:1,uploaded:true});await disabled(false);
  await update({storageState:3,persisted:true});assert.equal(await page.locator('#persisted-status').textContent(),'TF 已校验保存');checks++;
  assert(!(await page.locator('#card-recall').isDisabled()));checks++;
  await page.screenshot({path:path.join(out,'native_tf_saved.png'),fullPage:true});
  await update({ready:false});await disabled(true);
  await update({ready:true,nativePitch:false,capabilities:255,persisted:false});await disabled(false);
  assert.equal(errors.length,0,errors.join('\n'));
  const result={passed:true,checks,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),physical_phone_or_card_test:false};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
