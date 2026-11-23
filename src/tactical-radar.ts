import type { Sortie } from './sortie';

export function mapRadar(dx:number,dz:number,cos:number,sin:number){
  return [dx*cos+dz*sin, -dx*sin+dz*cos] as const;
}
const colors={friend:'#8be7fc',foe:'#ff858b',objective:'#f1cc86',lock:'#fff0aa'};

export class TacticalRadar {
  private readonly display:HTMLCanvasElement;
  private readonly list:HTMLOListElement;
  private last:Sortie|null=null;
  private updated=-1;
  constructor(private mini:HTMLCanvasElement,private modal:HTMLDialogElement){
    this.display=modal.querySelector('canvas')!;
    this.list=modal.querySelector('ol')!;
  }
  open(){
    if(this.modal.open||!this.last)return;
    this.modal.showModal();
    this.updated=-1;
    this.draw(this.last);
  }
  close(){
    if(!this.modal.open)return false;
    this.modal.close();return true;
  }
  draw(g:Sortie){
    this.last=g;
    this.paint(this.mini,g);
    if(!this.modal.open)return;
    this.paint(this.display,g);
    if(g.time-this.updated<.31)return;
    this.updated=g.time;
    this.modal.querySelector('#tactical-status')!.textContent='探测半径 '+(g.radar/1000).toFixed(1)+' 公里 · 航向 '+Math.round(g.player.heading())+'°';
    const p=g.player,fragment=document.createDocumentFragment();
    for(const target of [g.ally,...g.enemies]){
      if(!target.alive)continue;
      const dx=target.position.x-p.position.x,dz=target.position.z-p.position.z,dy=target.position.y-p.position.y;
      const range=Math.hypot(dx,dz);
      if(range>g.radar)continue;
      const row=document.createElement('li'),name=document.createElement('b'),value=document.createElement('span');
      row.dataset.signal=target===g.ally?'friend':target===g.locked?'lock':'foe';
      name.textContent=target.type.name;
      const bearing=(Math.atan2(dx,-dz)*180/Math.PI+360)%360;
      value.textContent=(range/1000).toFixed(2)+' 公里 · '+Math.round(bearing)+'° · '+(dy>=0?'+':'−')+Math.round(Math.abs(dy))+' 米';
      row.append(name,value);fragment.append(row);
    }
    if(!fragment.childElementCount){
      const empty=document.createElement('li');empty.textContent='探测范围内暂无飞机';fragment.append(empty);
    }
    this.list.replaceChildren(fragment);
  }
  private paint(canvas:HTMLCanvasElement,g:Sortie){
    const css=Math.min(canvas.clientWidth,canvas.clientHeight);
    if(!css)return;
    const size=Math.round(css*Math.min(2.5,devicePixelRatio));
    if(canvas.width!==size||canvas.height!==size)canvas.width=canvas.height=size;
    const c=canvas.getContext('2d')!,r=g.radar,p=g.player,yaw=p.heading()*Math.PI/180,cos=Math.cos(yaw),sin=Math.sin(yaw);
    c.setTransform(size/180,0,0,size/180,0,0);c.clearRect(0,0,180,180);
    const sweep=g.time*1.31,tau=Math.PI*2;
    const dial=c.createRadialGradient(90,90,4,90,90,86);
    dial.addColorStop(0,'#102c45e8');dial.addColorStop(1,'#071427f0');
    c.beginPath();c.arc(90,90,85,0,tau);c.fillStyle=dial;c.fill();
    c.lineWidth=1;c.strokeStyle='#88b7c9ba';c.stroke();
    for(const radius of [25,50,75]){
      c.beginPath();c.arc(90,90,radius,0,tau);c.strokeStyle='#83bbd055';c.stroke();
    }
    c.beginPath();c.moveTo(90,14);c.lineTo(90,166);c.moveTo(14,90);c.lineTo(166,90);c.stroke();
    for(let i=0;i<36;i++){
      const a=i*tau/36,si=Math.sin(a),co=Math.cos(a),start=i%3===0?78:81;
      c.beginPath();c.moveTo(90+si*start,90-co*start);c.lineTo(90+si*84,90-co*84);c.strokeStyle=i%3===0?'#d3dbe4c0':'#96bbcc92';c.stroke();
    }
    c.beginPath();c.moveTo(90,90);c.arc(90,90,83,sweep-.66,sweep);c.fillStyle='#56cbe429';c.fill();
    const contact=(x:number,y:number,z:number,kind:keyof typeof colors)=>{
      const [u,v]=mapRadar(x-p.position.x,z-p.position.z,cos,sin);
      if(u*u+v*v>r*r)return;
      const sx=90+u/r*75,sy=90+v/r*75,delta=y-p.position.y;
      c.fillStyle=colors[kind];c.strokeStyle=colors[kind];
      c.beginPath();c.moveTo(sx,sy-3.6);c.lineTo(sx+3.5,sy);c.lineTo(sx,sy+3.6);c.lineTo(sx-3.5,sy);c.closePath();c.fill();
      if(kind!=='objective'&&Math.abs(delta)>500){c.beginPath();c.moveTo(sx+5.5,sy);c.lineTo(sx+5.5,sy-Math.sign(delta)*4);c.stroke();}
    };
    for(const a of g.enemies)if(a.alive)contact(a.position.x,a.position.y,a.position.z,a===g.locked?'lock':'foe');
    if(g.ally.alive)contact(g.ally.position.x,g.ally.position.y,g.ally.position.z,'friend');
    for(const t of g.targetPoints)if(t.alive)contact(t.position.x,t.position.y,t.position.z,'objective');
    const gate=g.gates[g.gate];if(gate)contact(gate.x,gate.y,gate.z,'objective');
    const threat=g.warning.threat;
    if(threat){
      const [u,v]=mapRadar(threat.position.x-p.position.x,threat.position.z-p.position.z,cos,sin);
      const angle=Math.atan2(v,u);c.beginPath();c.arc(90,90,87,angle-.15,angle+.15);c.lineWidth=3;c.strokeStyle=colors.foe;c.stroke();
    }
    c.fillStyle='#d2f5ed';c.beginPath();c.moveTo(90,83);c.lineTo(94,95);c.lineTo(90,92);c.lineTo(86,95);c.closePath();c.fill();
  }
}
