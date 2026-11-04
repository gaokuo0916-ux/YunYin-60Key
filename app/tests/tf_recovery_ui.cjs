const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/tf_recovery');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1}),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const update=v=>page.evaluate(x=>window.YY.update(x),v);
  await update({page:'device',ready:true,capabilities:127,featuresIdentified:true,storageState:4,storageError:6,uploaded:true,
   storageMessage:'未识别 TF 卡，请插入 SDHC 小卡后重新上电',sdDiagnosticSupported:false});
  assert(await page.locator('#card-save').isDisabled());assert(await page.locator('#card-recall').isDisabled());
  assert(!(await page.locator('#tf-diagnostic-tools').isVisible()));assert((await page.locator('#storage-action-note').textContent()).includes('配套 TF 修复版'));
  await update({capabilities:255,sdDiagnosticSupported:true,sdCanRetry:true,sdDiagnosticMessage:'CMD0：未收到有效响应 · R1=FF · 已尝试 3 次',sdDiagnosticCode:'D000000007F80142'});
  assert(await page.locator('#tf-diagnostic-tools').isVisible());assert(!(await page.locator('#sd-retry').isDisabled()));
  assert(await page.locator('#card-save').isDisabled());await page.locator('#sd-retry').click();
  assert.deepEqual(await page.evaluate(()=>window.actions.at(-1)),{name:'sd-retry',payload:''});
  await page.locator('#tf-diagnostic-tools summary').click();await page.screenshot({path:path.join(out,'tf_failure_diagnostic.png'),fullPage:true});
  await update({storageState:0,storageError:0,sdCanRetry:false,sdDiagnosticMessage:'正在初始化 TF · 第 1 次尝试 · CMD8'});
  assert(await page.locator('#sd-retry').isDisabled());assert(await page.locator('#card-save').isDisabled());
  await update({storageState:1,uploaded:false,sdCanRetry:false});assert(await page.locator('#card-save').isDisabled());
  assert((await page.locator('#storage-action-note').textContent()).includes('先上传当前曲谱'));
  await update({uploaded:true});assert(!(await page.locator('#card-save').isDisabled()));
  await update({storageState:2});assert(await page.locator('#card-save').isDisabled());
  await update({storageState:3});assert(!(await page.locator('#card-recall').isDisabled()));
  await update({ready:false,busy:false});assert(await page.locator('#card-save').isDisabled());assert(await page.locator('#sd-info').isDisabled());
  assert.equal(errors.length,0,errors.join('\n'));
  const result={passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),tests:['old-firmware fallback and unchanged write guard','real diagnostic detail display','explicit retry action','initializing, ready/no-score, ready/uploaded, writing, saved and disconnected states'],physical_phone_or_TF_test:false};
  await fs.writeFile(path.join(out,'results.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
