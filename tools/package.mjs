import { readdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const root='dist';
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
const key=${JSON.stringify(name)};
const release=${JSON.stringify(offline)};
self.addEventListener('install', event => event.waitUntil(
  caches.open(key).then(cache => cache.addAll(['./', ...release].map(url => new Request(url, {cache:'reload'})))).then(() => self.skipWaiting())
));
self.addEventListener('activate', event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(old => old.indexOf('px-sky-remake-') === 0 && old !== key).map(old => caches.delete(old))))
    .then(() => self.clients.claim())
));
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request, {cache:'no-store'}).catch(() => caches.open(key).then(cache => cache.match('./'))));
    return;
  }
  event.respondWith(caches.open(key).then(async cache => {
    const match = await cache.match(request);
    if (match) return match;
    return fetch(request);
  }));
});
`;
await writeFile(root+'/sw.js',source);
console.log('已为 '+offline.length+' 项网页资产生成离线缓存清单。');
