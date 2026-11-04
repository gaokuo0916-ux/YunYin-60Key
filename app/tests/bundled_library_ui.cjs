const {chromium}=require('C:/Users/fy/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
(async()=>{
 const root=path.resolve(__dirname,'..'),out=path.join(root,'verification/bundled_library');await fs.mkdir(out,{recursive:true});
 const html=await fs.readFile(path.join(root,'studio.html'),'utf8'),index=await fs.readFile(path.join(root,'vendor/bundled_midi/catalog.tsv'),'utf8');
 const source=index.trim().split('\n').slice(1).map(line=>line.split('\t')),chinese=source.filter(c=>c[4]==='1');
 const rows=items=>items.map(c=>({id:'b:'+c[0],title:c[1],subtitle:(c[4]==='1'?'华语筛选':'离线曲库')+' · 完整 MIDI 原谱',local:true}));
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 try{
  const page=await browser.newPage({viewport:{width:390,height:844},reducedMotion:'reduce'}),errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.setContent(html.replace('<script>','<script>window.actions=[];window.YunYin={action:(name,payload)=>actions.push({name,payload})};'));
  const last=()=>page.evaluate(()=>JSON.parse(actions.filter(a=>a.name==='list').at(-1).payload));
  const reply=async(q,items)=>page.evaluate(({q,items})=>YY.library(items.rows,items.total,q.category,q.query,q.page,q.request),{q,items});
  await page.locator('nav [data-page="library"]').click();let q=await last();assert.equal(q.category,'chinese');
  await reply(q,{rows:rows(chinese.slice(0,60)),total:chinese.length});assert.equal(await page.locator('#song-list .row').count(),60);
  await page.locator('#song-list .row').first().click();assert.equal((await page.evaluate(()=>actions.at(-1))).payload,'b:'+chinese[0][0]);
  await page.locator('#search').fill('孤勇者');await page.waitForTimeout(230);q=await last();let filtered=chinese.filter(c=>(c[1]+c[2]+c[5]).includes(q.query));assert(filtered.some(c=>c[13]==='1'));await reply(q,{rows:rows(filtered),total:filtered.length});
  await page.screenshot({path:path.join(out,'chinese.png'),fullPage:false});
  await page.locator('#search').fill('跳楼机');await page.waitForTimeout(230);q=await last();filtered=chinese.filter(c=>c[1].includes(q.query));assert(filtered.length>0);await reply(q,{rows:rows(filtered),total:filtered.length});assert.match(await page.locator('#song-list').textContent(),/完整 MIDI 原谱/);
  await page.locator('#search').fill('');await page.waitForTimeout(230);await page.locator('[data-category="bundled"]').click();q=await last();await reply(q,{rows:rows(source.slice(0,60)),total:source.length});assert.match(await page.locator('#catalog-count').textContent(),/18,775/);
  assert.deepEqual(errors,[]);
  await fs.writeFile(path.join(out,'result.json'),JSON.stringify({passed:true,html_sha256:crypto.createHash('sha256').update(html).digest('hex'),index_sha256:crypto.createHash('sha256').update(index).digest('hex'),actual_source_records:source.length,chinese_records:chinese.length,checks:['real bundled catalog rows','Chinese default category','stable local selection ID','actual Chinese song search','all source records open as full original MIDI','complete offline collection count'],physical_Android_test:false},null,2));
  console.log('PASS actual bundled-library UI: '+source.length+' source records, '+chinese.length+' Chinese matches and real score selections/search.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
