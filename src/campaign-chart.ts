import { theatres, type Operation } from './data';
import { campaignOperations } from './campaign';
import { icon } from './icons';

// Geographic anchors for fictional operations, on a Pacific-centred WGS84 chart.
const sectors:Record<string,[longitude:number,latitude:number,labelX:number,labelY:number]> = {
  s01:[124,22,0,0],s02:[169,52,.85,-.28],s03:[99,1,-1,.18],s04:[-133,14,.28,.7],
};
const independentSectors:Record<string,string>={d01:'s01',d02:'s02',d03:'s03',d05:'s04'};
function sectorFor(id:string){
  const theatre=campaignOperations.find(stage=>stage.id===id)?.region;
  return sectors[independentSectors[id]??id]??sectors[theatre===1?'s02':theatre===2?'s04':'s01'];
}
export function chartPoint(id:string){
  const [lon,lat]=sectorFor(id);
  return [((lon+390)%360)/3.6,(90-lat)/1.8] as const;
}

export function campaignChart(operations:Operation[]){
  const route=operations.map(m=>chartPoint(m.id).map(n=>n*10).join(',')).join(' ');
  return '<svg class="chart-grid" viewBox="0 0 1000 1000" preserveAspectRatio="none" aria-hidden="true">'+
    '<defs><pattern id="chart-meridian" width="83.333" height="166.666" patternUnits="userSpaceOnUse"><path d="M83.333 0H0V166.666" fill="none" stroke="#a2c3d4" stroke-opacity=".27" vector-effect="non-scaling-stroke"/></pattern></defs>'+
    '<rect width="1000" height="1000" fill="url(#chart-meridian)"/><path d="M0 500H1000" class="chart-equator"/>'+
    (operations[0].campaign?'<polyline class="chart-route-bed" points="'+route+'"/><polyline class="chart-route" points="'+route+'"/>':'')+'</svg>'+
    '<span class="atlas-label" style="--x:40%;--y:43%">西太平洋</span>'+
    '<span class="atlas-label" style="--x:71%;--y:55%">中太平洋</span>'+
    '<span class="atlas-label" style="--x:16%;--y:69%">印度洋</span>'+
    '<span class="atlas-label" style="--x:87%;--y:63%">大西洋</span>';
}
export function chartMarker(m:Operation){
  const [x,y]=chartPoint(m.id);
  const [,,labelX,labelY]=sectorFor(m.id);
  const leader=labelX||labelY?'<svg class="chart-leader" viewBox="0 0 100 100" aria-hidden="true"><line x2="'+labelX*100+'" y2="'+labelY*100+'"/></svg>':'';
  return '<div class="chart-anchor" style="--x:'+x+'%;--y:'+y+'%;--label-x:'+labelX+';--label-y:'+labelY+'">'+leader+
    '<button type="button" class="chart-marker" data-pick="'+m.id+'" aria-label="'+m.name+'，'+theatres[m.region].name+'">'+
    '<span class="pin-medal">'+icon('target')+icon('lock')+icon('check')+'</span><span class="pin-title">'+m.name+'</span></button></div>';
}
