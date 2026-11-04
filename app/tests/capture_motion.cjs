// Browser recording of the real bundled UI; fixture songs, no hardware actions.
const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/ui_refresh_2_5_2');
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8');
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},reducedMotion:'no-preference'});
  await page.setContent(html.replace('<script>','<script>window.YunYin={action(){}};'));
  await page.evaluate(()=>{window.YY.update({page:'library'});window.YY.library([
   {id:'a',title:'小星星',subtitle:'传统旋律 · 已存手机',local:true},
   {id:'b',title:'外婆的澎湖湾',subtitle:'潘安邦 · 七键改编',local:true},
   {id:'c',title:'欢乐颂',subtitle:'贝多芬 · 已存手机',local:true},
   {id:'d',title:'慢弹练习',subtitle:'本地曲谱 · 80 BPM',local:true}],4,'mine','')});
  await page.waitForTimeout(400);
  const frames=[];
  const capture=async duration=>frames.push({duration,png:(await page.screenshot({clip:{x:0,y:0,width:390,height:650}})).toString('base64')});
  await capture(700);
  for(let step=0;step<2;step++){
   await page.locator('#cover-next').click();
   for(let n=0;n<9;n++){await page.waitForTimeout(35);await capture(80)}
   await capture(450);
  }
  await fs.writeFile(path.join(out,'motion_frames.json'),JSON.stringify(frames));
  console.log('Captured '+frames.length+' real UI frames.');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
