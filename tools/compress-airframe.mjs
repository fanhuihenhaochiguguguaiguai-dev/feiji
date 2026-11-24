import {execFileSync} from 'node:child_process';
import {mkdtemp,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename,join} from 'node:path';
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS,KHRTextureBasisu} from '@gltf-transform/extensions';
import {dedup,meshopt,prune,reorder} from '@gltf-transform/functions';
import {MeshoptDecoder,MeshoptEncoder} from 'meshoptimizer';

const [encoder,input,output]=process.argv.slice(2);
if(!encoder||!input||!output)throw new Error('Expected encoder path, source GLB, and output GLB');
await Promise.all([MeshoptEncoder.ready,MeshoptDecoder.ready]);
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
  'meshopt.decoder':MeshoptDecoder,'meshopt.encoder':MeshoptEncoder
});
const document=await io.read(input);
const temporary=await mkdtemp(join(tmpdir(),'cangqiong-basis-'));
try{
  for(const [index,texture] of document.getRoot().listTextures().entries()){
    const normal=texture.getName().endsWith('-normal');
    const src=join(temporary,`map-${index}.png`),dst=join(temporary,`map-${index}.ktx2`);
    await writeFile(src,texture.getImage());
    const mode=normal?['-uastc','-uastc_level','1','-normal_map','-mip_renorm']:
      ['-q','215','-comp_level','2'];
    execFileSync(encoder,['-file',src,'-output_file',dst,'-ktx2','-linear','-mipmap','-no_multithreading',...mode],{stdio:'inherit'});
    texture.setImage(await readFile(dst));texture.setMimeType('image/ktx2');
  }
  document.createExtension(KHRTextureBasisu).setRequired(true);
  await document.transform(dedup(),prune({keepExtras:true}),reorder({encoder:MeshoptEncoder}),
    meshopt({encoder:MeshoptEncoder,level:'medium'}));
  await io.write(output,document);
  console.log(basename(output),(await readFile(output)).length);
}finally{await rm(temporary,{recursive:true,force:true});}
