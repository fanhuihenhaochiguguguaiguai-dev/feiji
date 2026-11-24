import { mkdir,copyFile } from 'node:fs/promises';
import { build } from 'esbuild';

const runtime='public/runtime';
const decoder='node_modules/@babylonjs/ktx2decoder';
await mkdir(runtime,{recursive:true});
await build({entryPoints:[decoder+'/index.js'],bundle:true,minify:true,format:'iife',globalName:'KTX2DECODER',outfile:runtime+'/ktx2-decoder.js'});
for(const name of ['msc_basis_transcoder.js','msc_basis_transcoder.wasm'])await copyFile(decoder+'/wasm/'+name,runtime+'/'+name);
await copyFile(decoder+'/wasm/license.md','public/licenses/KTX2-Basis-Apache-2.0.md');
