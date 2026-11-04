const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{const root=path.resolve(__dirname,'../..'),out=path.join(root,'verification/practice_records_20261029/ui');await fs.mkdir(out,{recursive:true});const html=await fs.readFile(path.join(root,'app/studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});let checks=0;
 try{const page=await browser.newPage({viewport:{width:390,height:844}}),errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>actions.push({name,payload})};'));
 const update=x=>page.evaluate(v=>YY.update(v),x),last=()=>page.evaluate(()=>actions.at(-1));
 await update({page:'takes',ready:false,busy:false});assert(await page.locator('#practice-start').isDisabled());checks++;
 await update({ready:true,practiceSupported:true,practiceKnown:true,practiceCanStart:false,longState:0,practiceMessage:'旧32MiB卡，保留旧录音'});assert(await page.locator('#practice-start').isDisabled());checks++;
 await update({capabilities:0xfffb,storageState:1,practiceCanStart:true,practiceTrack:'晴天',practiceMessage:'TF目录已读取 · 新录音2/20',practiceRecords:[{id:'0_1_17000_1',name:'晴天练习',detail:'0.35 秒 · 时间未提供 · 晴天',playable:true},{id:'1_2_1000_2',name:'<img src=x onerror=alert(1)>',detail:'0.02 秒 · 手机时间 2026-10-29 +08:00',playable:true},{id:'2_0_0_0',name:'目录损坏 #3',detail:'隔离',playable:false}]});
 assert(!(await page.locator('#practice-time').isChecked()));checks++;assert(!(await page.locator('#practice-start').isDisabled()));checks++;assert.equal(await page.locator('#practice-records .take').count(),3);checks++;assert.equal(await page.locator('#practice-records img').count(),0);checks++;
 await page.locator('#practice-name').fill('练琴');await page.locator('#practice-start').click();let a=await last();assert.equal(a.name,'practice-start');assert.deepEqual(JSON.parse(a.payload),{seconds:120,name:'练琴',associate:true,phoneTime:false});checks++;
 await update({longState:2});assert(await page.locator('#practice-start').isDisabled());assert(!(await page.locator('#practice-stop').isDisabled()));assert(await page.locator('#practice-refresh').isDisabled());assert(await page.locator('#practice-records button').first().isDisabled());checks+=4;
 await page.locator('#practice-stop').click();assert.equal((await last()).name,'practice-stop');checks++;
 await update({longState:6});assert(await page.locator('#practice-stop').isDisabled());checks++;
 await update({longState:3});await page.locator('#practice-search').fill('晴天');assert.equal(await page.locator('#practice-records .take').count(),1);checks++;for(const [label,name] of [['试听','practice-play'],['导出WAV','practice-export'],['命名','practice-rename'],['删除','practice-delete']]){await page.locator('#practice-records button').filter({hasText:label}).click();assert.deepEqual(await last(),{name,payload:'0_1_17000_1'});checks++;}
 await page.locator('#practice-search').fill('');let bad=page.locator('#practice-records .take').last();assert(await bad.locator('button').first().isDisabled());assert(!(await bad.locator('button').last().isDisabled()));checks+=2;
 await page.locator('#practice-refresh').click();assert.equal((await last()).name,'practice-refresh');checks++;
 await page.locator('#page-takes details').evaluate(e=>e.open=true);assert(await page.locator('#audio-arm').isVisible());checks++;
 for(const width of [320,390,700])for(const theme of ['light','dark']){await page.setViewportSize({width,height:844});await page.emulateMedia({colorScheme:theme});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);checks++;}
 await page.setViewportSize({width:390,height:844});await page.emulateMedia({colorScheme:'light'});await page.locator('#page-takes details').evaluate(e=>e.open=false);await page.screenshot({path:path.join(out,'practice_records.png'),fullPage:true});assert.deepEqual(errors,[]);checks++;
 const result={passed:true,checks,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),physical_phone_ble_test:false};await fs.writeFile(path.join(out,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
