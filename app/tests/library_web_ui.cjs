const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/library_web');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8'),errors=[];
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},reducedMotion:'reduce'});page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>window.actions.push({name,payload})};'));
  const last=()=>page.evaluate(()=>JSON.parse(actions.filter(a=>a.name==='list').at(-1).payload));
  const rows=(start,n)=>Array.from({length:n},(_,i)=>({id:'w:'+String(start+i),title:i===0?'示例曲谱 · Beethoven':'曲谱 '+(start+i),subtitle:'Wikimedia Commons · Public domain',local:false}));
  const reply=async(q,total,data)=>page.evaluate(({q,total,data})=>YY.library(data,total,q.category,q.query,q.page,q.request),{q,total,data});
  await page.locator('nav [data-page="library"]').click();let q=await last();assert.equal(q.category,'chinese');assert.equal(q.page,0);assert(await page.locator('#catalog-next').isDisabled());
  await reply(q,2296,rows(0,60));await page.locator('[data-category="bundled"]').click();q=await last();assert.equal(q.category,'bundled');await reply(q,18775,rows(0,60));assert.match(await page.locator('#catalog-count').textContent(),/18,775/);await page.locator('[data-category="all"]').click();q=await last();
  await reply(q,103759,rows(0,60));assert.equal(await page.locator('#song-list .row').count(),60);assert.match(await page.locator('#catalog-count').textContent(),/103,759/);assert.match(await page.locator('#catalog-page').textContent(),/1 \/ 1730/);
  await page.locator('#catalog-next').click();let next=await last();assert.equal(next.page,1);assert(await page.locator('#song-list .row').first().isDisabled());
  await reply(q,103759,rows(700,60));assert.equal((await page.locator('#song-list .row').first().textContent()).includes('700'),false,'outdated response ignored');
  await reply(next,103759,rows(60,60));await page.locator('#song-list .row').first().click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'select',payload:'w:60'});
  await page.locator('#catalog-jump').fill('1730');await page.locator('#catalog-jump-form button').click();q=await last();assert.equal(q.page,1729);
  await reply(q,103759,rows(103740,19));assert.equal(await page.locator('#song-list .row').count(),19);assert(await page.locator('#catalog-next').isDisabled());assert(!(await page.locator('#catalog-prev').isDisabled()));
  await page.locator('#search').fill('Bach');await page.waitForTimeout(240);q=await last();assert.equal(q.page,0);assert.equal(q.query,'Bach');
  await reply(q,73,rows(1,60));
  await page.locator('[data-category="open"]').click();q=await last();assert.equal(q.page,0);assert.equal(q.category,'open');assert.equal(q.query,'Bach');await reply(q,47,rows(0,47));
  await page.locator('[data-action="free-sources"]').click();assert.equal((await page.evaluate(()=>actions.at(-1))).name,'free-sources');
  await page.locator('[data-action="score-global"]').click();assert.equal((await page.evaluate(()=>actions.at(-1))).name,'score-global');
  await page.locator('#midishow-query').fill('世界赠予我的 & Adele');await page.locator('#midishow-query').press('Enter');assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'free-midi',payload:'世界赠予我的 & Adele'});
  assert.equal((await page.evaluate(()=>YY.inspect())).query,'Bach','Website query is separate from the App directory query');
  await page.locator('[data-action="free-sources"]').click();assert.equal((await page.evaluate(()=>actions.at(-1))).name,'free-sources');
  await page.locator('[data-action="score-link"]').click();assert.equal((await page.evaluate(()=>actions.at(-1))).name,'score-link');
  await page.locator('[data-action="score-sources"]').first().click();assert.equal((await page.evaluate(()=>actions.at(-1))).name,'score-sources');
  await page.evaluate(()=>YY.search('花海'));q=await last();assert.equal(q.category,'all');assert.equal(q.query,'花海');assert.equal(q.page,0);await reply(q,1,[{id:'p:751',title:'花海',subtitle:'周杰伦 · POP909',local:false}]);
  await page.locator('[data-action="search"]').click();assert.deepEqual(await page.evaluate(()=>actions.at(-1)),{name:'search',payload:'花海'});
  await page.locator('#search').fill('不存在的测试');await page.waitForTimeout(240);q=await last();await reply(q,0,[]);assert.match(await page.locator('#song-list').textContent(),/没有匹配/);assert(await page.locator('#catalog-next').isDisabled());
  await page.locator('[data-category="expanded"]').click();q=await last();await page.evaluate(q=>YY.libraryError(q.request,'目录读取失败'),q);assert(await page.locator('#catalog-retry').isVisible());await page.locator('#catalog-retry').click();assert((await last()).request>q.request);
  q=await last();await reply(q,1,[{id:'x:test',title:'<img src=x onerror=alert(1)>',subtitle:'作为文字显示',local:false}]);assert.equal(await page.locator('#song-list img').count(),0);
  await page.evaluate(()=>YY.search(''));q=await last();await reply(q,103759,rows(0,60));
  for(const theme of ['light','dark']){await page.emulateMedia({colorScheme:theme});for(const width of [320,390,700]){await page.setViewportSize({width,height:844});for(const id of ['perform','challenge','library','device','takes']){await page.evaluate(id=>YY.update({page:id}),id);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${theme} ${width} ${id}`);}}}
  await page.setViewportSize({width:390,height:844});await page.emulateMedia({colorScheme:'light'});await page.evaluate(()=>{YY.update({page:'library'});window.scrollTo(0,0)});await page.screenshot({path:path.join(out,'library.png'),fullPage:false});
  assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),physical_android_test:false,
   checks:['actual offline Chinese and full-library categories','all eight sources','60-row pagination','last page and page jump','search resets page','stale-response guard','stable selected ID','live pop/global catalog and link/source actions','song-title search','empty/error/retry','safe text rendering','five pages at 320/390/700px in two themes']},null,2)+'\n');
  console.log('PASS library_web UI: pagination, source/search/import actions, stale responses, empty/error/retry and layouts.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
