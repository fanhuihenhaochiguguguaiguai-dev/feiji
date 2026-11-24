import { readdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const root='dist';
const version=JSON.parse(await readFile('package.json','utf8')).version;
async function scan(dir) {
  const paths=await readdir(dir,{withFileTypes:true});
  const lists=await Promise.all(paths.map(p=>p.isDirectory()?scan(dir+'/'+p.name):[dir+'/'+p.name]));
  return lists.flat().sort();
}
const files=(await scan(root)).filter(f=>!f.endsWith('sw.js'));
const sha=createHash('sha256');
for(const file of files)sha.update(file).update(await readFile(file));
const name='px-sky-remake-'+sha.digest('hex').slice(0,12);
const offline=files.filter(name=>!name.endsWith('.json')&&!name.endsWith('.md')).map(name=>'./'+name.slice(root.length+1));
const source=`
const key=${JSON.stringify(name)}, version=${JSON.stringify(version)};
const scope=new URL(self.registration.scope);
const home=new URL('index.html',scope).href;
const files=new Set(${JSON.stringify(offline)}.map(path=>new URL(path,scope).href));
const own=name=>name.startsWith('px-sky-remake-');
const usable=(response,html)=>response.ok&&!response.redirected&&
  (response.headers.get('content-type')||'').includes('text/html')===html;

self.addEventListener('install',event=>event.waitUntil((async()=>{
  const cache=await caches.open(key),paths=[...files];
  try {
    for(let i=0;i<paths.length;i+=8){
      await Promise.all(paths.slice(i,i+8).map(async url=>{
        const response=await fetch(url,{cache:'reload'});
        if(!usable(response,url===home))throw new Error('Incomplete release: '+url);
        await cache.put(url,response);
      }));
    }
  }catch(error){await caches.delete(key);throw error;}
  await self.skipWaiting();
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  const predecessor=(await caches.keys()).filter(name=>own(name)&&name!==key);
  for(const stale of predecessor.slice(0,-1))await caches.delete(stale);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const request = event.request;
  const url=new URL(request.url);
  if(request.method!=='GET'||url.origin!==scope.origin||!url.pathname.startsWith(scope.pathname))return;
  if(request.mode==='navigate'){
    event.respondWith((async()=>{
      try {
        const response=await fetch(request,{cache:'no-store'});
        if(response.status<500)return response;
      }catch{/* Try the last complete offline release. */}
      return (await (await caches.open(key)).match(home))??Response.error();
    })());
    return;
  }
  const requestedRelease=url.searchParams.get('release');
  url.search='';
  const immutable=url.pathname.slice(scope.pathname.length).startsWith('assets/');
  if(requestedRelease&&requestedRelease!==version||!files.has(url.href)&&!immutable)return;
  event.respondWith((async()=>{
    const cache=await caches.open(key);
    const cached=await cache.match(url.href);
    if(cached&&(immutable||requestedRelease===version))return cached;
    try {
      const response=await fetch(request,immutable?undefined:{cache:'no-cache'});
      if(usable(response,false)||response.status===401||response.status===403||response.redirected)return response;
      if(!immutable)return cached??(response.ok?Response.error():response);
    }catch{if(!immutable&&cached)return cached;}
    if(immutable){
      for(const previous of (await caches.keys()).filter(name=>own(name)&&name!==key).reverse()){
        const older=await (await caches.open(previous)).match(url.href);
        if(older)return older;
      }
    }
    return cached??Response.error();
  })());
});
`;
await writeFile(root+'/sw.js',source);
console.log('已为 '+offline.length+' 项网页资产生成离线缓存清单。');
