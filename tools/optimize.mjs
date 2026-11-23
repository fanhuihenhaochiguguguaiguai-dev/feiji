import { readdir, readFile, writeFile } from 'node:fs/promises';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, meshopt, prune, reorder } from '@gltf-transform/functions';
import { MeshoptDecoder, MeshoptEncoder } from 'meshoptimizer';
await Promise.all([MeshoptDecoder.ready,MeshoptEncoder.ready]);
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
  'meshopt.decoder':MeshoptDecoder,'meshopt.encoder':MeshoptEncoder
});
const files=await readdir('public/fleet');
const picked=process.argv.filter(arg=>arg.startsWith('--airframe=')).map(arg=>arg.slice(11)+'.glb');
if(picked.some(name=>!files.includes(name)))throw new Error('Unknown airframe file');
const targets=picked.length?picked.map(name=>'public/fleet/'+name):
  process.argv.includes('--studio-only')?['public/studio/hangar-dusk.glb']:
    [...files.filter(x=>x.endsWith('.glb')).sort().map(name=>'public/fleet/'+name),'public/studio/hangar-dusk.glb'];
for (const filename of targets) {
  const before=(await readFile(filename)).byteLength;
  const document=await io.read(filename);
  await document.transform(dedup(),prune({keepExtras:true}),reorder({encoder:MeshoptEncoder}),meshopt({encoder:MeshoptEncoder,level:'medium'}));
  await io.write(filename,document);
  const after=(await readFile(filename)).byteLength;
  console.log(filename,before,after);
}
const fleet=[];
for(const name of (await readdir('art/catalog')).filter(x=>x.endsWith('.json')).sort()){
  fleet.push(JSON.parse(await readFile('art/catalog/'+name,'utf8')));
}
await writeFile('src/fleet.generated.json',JSON.stringify(fleet,null,2)+'\n');
