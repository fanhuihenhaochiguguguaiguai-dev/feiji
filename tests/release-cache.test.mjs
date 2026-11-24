import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const script=await readFile('dist/sw.js','utf8');
const version=JSON.parse(await readFile('package.json','utf8')).version;
const scope='https://flight.test/v10/';
const home=scope+'index.html';
const oldAsset=scope+'assets/old-shell.js';
const oldCache='px-sky-remake-previous';

function worker(network){
  const events=new Map(),previous=new Map([[oldAsset,new Response('previous code')]]);
  const caches=new Map([[oldCache,previous]]);
  let waiting=false;
  runInNewContext(script,{URL,Response,fetch:network,
    self:{registration:{scope},clients:{claim:async()=>{}},skipWaiting:async()=>{waiting=true;},addEventListener:(name,fn)=>events.set(name,fn)},
    caches:{keys:async()=>[...caches.keys()],delete:async key=>caches.delete(key),open:async key=>{
      if(!caches.has(key))caches.set(key,new Map());
      const entries=caches.get(key);
      return {put:async(url,value)=>entries.set(url,value),match:async url=>entries.get(url)?.clone()};
    }},
  });
  const dispatch=(type,details={})=>{
    let result;
    const handle=value=>{result=value;};
    events.get(type)({...details,waitUntil:handle,respondWith:handle});
    return result;
  };
  return {dispatch,caches,waiting:()=>waiting};
}
const networkBody=url=>new Response(url,{headers:{'content-type':url===home?'text/html':'application/octet-stream'}});

test('only a complete release is activated and offline uses the matching shell',async()=>{
  let offline=false;
  const fixture=worker(async request=>{
    if(offline)throw Error('offline');
    return networkBody(typeof request==='string'?request:request.url);
  });
  await fixture.dispatch('install');
  assert(fixture.waiting());
  await fixture.dispatch('activate');
  offline=true;
  const request=(url,mode='same-origin')=>fixture.dispatch('fetch',{request:{url,mode,method:'GET'}});
  assert.equal(await (await request(scope+'?graphics=safe','navigate')).text(),home);
  assert.equal(await (await request(scope+'world/sundown.height?release='+version)).text(),scope+'world/sundown.height');
  assert.equal(request(scope+'world/sundown.height?release=unknown'),undefined);
  assert.equal(await (await request(oldAsset)).text(),'previous code');
});

test('a chunk replaced with an HTTP 200 HTML page leaves the previous release intact',async()=>{
  const fixture=worker(async url=>url.includes('/assets/')?new Response('<html>Unrelated page</html>',{headers:{'content-type':'text/html'}}):networkBody(url));
  await assert.rejects(fixture.dispatch('install'),/Incomplete release/);
  assert(!fixture.waiting());
  assert.deepEqual([...fixture.caches.keys()],[oldCache]);
});
