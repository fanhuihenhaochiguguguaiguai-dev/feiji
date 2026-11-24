import { readFile,stat,readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
const sourceOnly=process.argv.includes('--source-only');
const output=sourceOnly?'public':'dist';
import { build } from 'esbuild';
const {outputFiles}=await build({stdin:{contents:"export {fleet,upgrades} from './src/data'; export {items,missiles} from './src/items';",
  resolveDir:process.cwd(),loader:'ts'},bundle:true,write:false,platform:'node',format:'esm'});
const {items,missiles,fleet,upgrades}=await import('data:text/javascript;base64,'+Buffer.from(outputFiles[0].contents).toString('base64'));
assert.equal(new Set(items.map(a=>a.id)).size,items.length);
assert.equal(new Set(items.map(a=>a.visual.icon)).size,items.length);
for(const entry of items)assert((await stat('public/'+entry.visual.icon.replace(/^\.\//,''))).size>80,entry.id);
const diagrams=upgrades.map(u=>'up-'+u.id);
const signatures=new Set();
for(const id of diagrams){
  const svg=await readFile('public/items/'+id+'.webp');
  assert.equal(svg.subarray(8,12).toString(),'WEBP',id);
  signatures.add(createHash('sha256').update(svg).digest('hex'));
}
assert.equal(signatures.size,diagrams.length);
for(const name of ['coast','hangar','training']){
  const picture=await readFile(output+'/briefing/'+name+'.webp');
  assert.equal(picture.subarray(8,12).toString(),'WEBP');
  assert(picture.equals(await readFile('public/briefing/'+name+'.webp')));
}
assert.equal(new Set(Object.values(missiles).map(x=>x.shape)).size,Object.keys(missiles).length);
for(const plane of fleet){
  const blob=await readFile('public/fleet/'+plane.id+'.glb');
  assert.equal(blob.readUInt32LE(0),0x46546c67);
  const json=JSON.parse(blob.subarray(20,20+blob.readUInt32LE(12)));
  const names=new Set(json.nodes.map(n=>n.name));
  for(const name of ['Exterior','Combat','LOD',...plane.support?[]:['Cockpit']])assert(names.has(name),plane.id+':'+name);
  assert(json.extensionsUsed.includes('EXT_meshopt_compression'),plane.id);
  assert(json.extensionsRequired.includes('KHR_texture_basisu'),plane.id);
  assert(json.images.length>=2,plane.id);
  const bin=28+blob.readUInt32LE(12);
  for(const image of json.images){
    assert.equal(image.mimeType,'image/ktx2',plane.id);
    const view=json.bufferViews[image.bufferView],start=bin+(view.byteOffset??0);
    const size=plane.support?2048:4096;
    assert.equal(blob.readUInt32LE(start+20),size,plane.id);
    assert.equal(blob.readUInt32LE(start+24),size,plane.id);
    assert(blob.readUInt32LE(start+40)>1,plane.id);
  }
  assert(json.materials.some(m=>m.normalTexture&&m.occlusionTexture&&m.pbrMetallicRoughness?.metallicRoughnessTexture),plane.id);
}
for(const id of ['sundown','frost','storm']){
  const h=gunzipSync(await readFile('public/world/'+id+'.height'));
  assert.equal(h.subarray(0,4).toString(),'WF18');
  assert.equal(h.readUInt16LE(4),4097);
  assert.equal(h.length,12+1025**2*2+4097**2+6+129**2);
  assert((await stat(output+'/world/'+id+'-surface.png')).size>100000);
}
for(const name of ['charts/world.webp','charts/sundown.webp','charts/frost.webp','charts/storm.webp','studio/apron-light.webp','surface/dusk-panorama.webp','studio/hangar-dusk.glb']){
  const source=await readFile('public/'+name);
  assert(source.equals(await readFile(output+'/'+name)),name);
  assert(source.length>10000,name);
}
for(const name of ['alpine','wings','title']){
  const path='loading/'+name+'.webp';
  const source=await readFile('public/'+path);
  assert.equal(source.subarray(8,12).toString(),'WEBP',path);
  assert(source.equals(await readFile(output+'/'+path)),path);
}
const world=await readFile(output+'/charts/world.webp');
assert.equal(world.subarray(8,12).toString(),'WEBP');
const activeWorld=await readdir(output+'/world');
for(const id of ['sundown','frost','storm'])assert(!activeWorld.includes(id+'.png'),'Obsolete preview image '+id);
const art=JSON.parse(await readFile('public/ui-v7/sources.json','utf8'));
for(const [id,entry] of Object.entries(art)){
  const sheet=await readFile('qa/reference/'+entry.source);
  const source=await readFile('public/ui-v7/'+id+'.webp');
  const deployed=await readFile(output+'/ui-v7/'+id+'.webp');
  assert(sheet.subarray(8,12).toString()==='WEBP'&&source.subarray(8,12).toString()==='WEBP'&&deployed.equals(source),id);
  assert(entry.box[0]>=0&&entry.box[1]>=0&&entry.box[2]<=entry.sourceSize[0]&&entry.box[3]<=entry.sourceSize[1],id);
}
const credit=await readFile(output+'/items/credits-wallet.webp');
assert.equal(credit.subarray(8,12).toString(),'WEBP');
for(const name of ['fire-frames','smoke-frames','impact-mark','spark']){
  const source=await readFile('public/surface/'+name+'.webp');
  assert.equal(source.subarray(8,12).toString(),'WEBP');
  assert(source.equals(await readFile(output+'/surface/'+name+'.webp')));
}
for(const profile of ['airbase-atlas','day','dusk','storm','night']){
  const source=await readFile('public/surface/probe-'+profile+'.hdr');
  assert.equal(source.subarray(0,10).toString(),'#?RADIANCE');
  assert(source.equals(await readFile(output+'/surface/probe-'+profile+'.hdr')));
}
const cache=sourceOnly?'':await readFile('dist/sw.js','utf8');
const surface=await readdir(output+'/surface');
for(const name of ['dusk.hdr','flame.png','smoke.png','combustion.webp','soot.webp','pressure.webp','rock-grain.png','terrain-normal.png']){
  assert(!surface.includes(name),'obsolete effect '+name);
  assert(!cache.includes('./surface/'+name),'obsolete effect cached '+name);
}
const uiAssets=await readdir(output+'/ui-v7');
for(const name of ['inventory','radar','missile','engine','rank','reward']){
  assert(!uiAssets.includes(name+'.webp'),'unused context crop '+name);
  assert(!cache.includes('./ui-v7/'+name+'.webp'),'unused context crop cached '+name);
}
for(const layer of ['stone-color','stone-relief','stone-response']){
  const texture=await readFile('public/surface/'+layer+'.ktx2');
  assert.equal(texture.readUInt32LE(20),2048,layer);
  assert.equal(texture.readUInt32LE(24),2048,layer);
}
if(!sourceOnly){
  const dist=await readdir('dist/assets');
  assert(!dist.some(name=>name.includes('instrumentation')||name.includes('world-lab')||name.includes('field-lab')||name.includes('three')));
}
console.log('Asset registration verified:',items.length,'distinct visuals,',fleet.length,'three-LOD GLBs,',diagrams.length,'upgrade visuals.');
