import type { Game } from './engine';
import './world-lab.css';

export function openFieldLab(game:Game){
  const dialog=document.createElement('aside');dialog.className='world-lab';
  dialog.innerHTML='<strong>渲染验收</strong><span></span><button type="button">空战验收</button><button type="button">云层</button><button type="button">海面</button><button type="button">地形</button><select aria-label="验收画质"><option value="low">兼容画质</option><option value="medium" selected>均衡画质</option><option value="high">高画质</option></select><select class="surface-inspection" aria-label="地表诊断"><option value="0">物理光照</option><option value="1">地表颜色</option><option value="2">世界法线</option><option value="3">基础粗糙度</option></select>';
  game.root.append(dialog);
  const stats=dialog.querySelector('span')!,buttons=dialog.querySelectorAll('button');
  buttons[0].onclick=()=>void game.begin('t04',0,false,{region:0,weather:0,lighting:2},true);
  buttons[1].onclick=()=>{game.world.clouds=!game.world.clouds;};
  buttons[2].onclick=()=>{game.world.ocean=!game.world.ocean;};
  buttons[3].onclick=()=>{game.world.ground=!game.world.ground;};
  const quality=dialog.querySelector('select')!;
  dialog.querySelector<HTMLSelectElement>('.surface-inspection')!.onchange=e=>game.world.inspectTerrain(Number((e.target as HTMLSelectElement).value));
  quality.onchange=()=>{game.qualityOverride=quality.value as 'low'|'medium'|'high';};
  game.engine.on('postrender',()=>{
    const d=game.engine.graphicsDevice;stats.textContent=d.deviceType+' · '+d.width+' × '+d.height+' · '+Math.round(game.budget.fps)+' 帧 · 敌机 LOD '+game.foes.filter(v=>v.pivot.enabled).map(v=>v.lod).join('/');
  });
}
