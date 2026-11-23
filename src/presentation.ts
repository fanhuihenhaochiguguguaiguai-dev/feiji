import { itemById } from './items';
import { icon } from './icons';

type Feedback='reward'|'aircraft'|'research'|'upgrade'|'equip'|'paint'|'purchase'|'facility';

export interface Receipt {
  kind:Feedback;
  title:string;
  detail:string;
  prizes?:readonly [string,number][];
  art?:string;
  before?:string;
  after?:string;
  model?:string;
  spent?:number;
}

const grades={standard:'标准补给',rare:'稀有物资',elite:'珍藏嘉奖'};
const captions:Record<Feedback,string>={
  reward:'军需入库',aircraft:'战机入列',research:'研发完成',upgrade:'试车校准',
  equip:'挂载确认',paint:'蒙皮涂装',purchase:'采购回执',facility:'基地投用'
};
const counters=new WeakMap<HTMLElement,number>();
const reduced=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;

function span(text:string,className=''){
  const element=document.createElement('span');element.className=className;element.textContent=text;return element;
}
function art(path:string,className=''){
  const image=new Image();image.className=className;image.alt='';image.src=path;image.decoding='async';return image;
}

export function countTo(node:HTMLElement,from:number,to:number){
  if(from===to||reduced())return;
  const start=performance.now(),duration=530;counters.set(node,start);
  const step=(now:number)=>{
    if(!node.isConnected||counters.get(node)!==start)return;
    const weight=Math.min(1,(now-start)/duration);
    node.textContent=Math.round(from+(to-from)*(1-(1-weight)**3)).toLocaleString('zh-CN');
    if(weight<1)requestAnimationFrame(step);
    else counters.delete(node);
  };
  node.textContent=from.toLocaleString('zh-CN');requestAnimationFrame(step);
}

export class Presentation {
  private readonly layer=document.querySelector<HTMLDialogElement>('#acquisition')!;
  private readonly ribbon=document.querySelector<HTMLElement>('#receipt')!;
  private timer=0;
  private beforeFocus:HTMLElement|null=null;
  constructor(private readonly scene:(model?:string)=>void){
    this.layer.addEventListener('close',()=>{
      this.scene();this.beforeFocus?.focus({preventScroll:true});
      this.layer.replaceChildren();
    });
    this.layer.addEventListener('click',event=>{
      if((event.target as Element).closest('[data-receipt-close]'))this.layer.close();
    });
  }
  inspect(name:string,description:string,model:string){
    if(this.layer.open)return;
    const panel=document.createElement('section');panel.className='receipt-panel';
    const header=document.createElement('header');
    const title=document.createElement('h2');title.id='acquisition-title';title.textContent=name;
    const copy=document.createElement('p');copy.textContent=description;
    header.append(title,copy);panel.append(header);
    const button=document.createElement('button');button.className='gold';button.dataset.receiptClose='';
    button.textContent='返回挂载';panel.append(button);
    this.beforeFocus=document.activeElement instanceof HTMLElement?document.activeElement:null;
    this.layer.className='acquisition show-model';this.layer.replaceChildren(panel);
    this.layer.showModal();this.scene(model);
  }
  show(data:Receipt){
    const list=(data.prizes??[]).flatMap(([id,amount])=>{
      const entry=itemById[id];return entry?[{entry,amount}]:[];
    });
    const gold=list.some(x=>x.entry.grade==='elite')||data.kind==='aircraft'||data.model?.startsWith('air-');
    const rare=list.some(x=>x.entry.grade==='rare')||data.kind==='research';
    const grade=gold?'elite':rare?'rare':'standard';
    const ceremonial=data.kind==='aircraft'||data.kind==='reward'&&Boolean(data.model||gold);
    const target=ceremonial?this.layer:this.ribbon;
    const panel=document.createElement('section');
    panel.className='receipt-panel';
    const heading=document.createElement('header');
    const title=document.createElement('h2');title.id=ceremonial?'acquisition-title':'receipt-title';title.textContent=data.title;
    heading.append(span(captions[data.kind]+(ceremonial?' · '+grades[grade]:''),'caption'),title);
    const detail=document.createElement('p');detail.textContent=data.detail;heading.append(detail);
    panel.append(heading);
    if(data.art)panel.append(art(data.art,'receipt-emblem'));
    if(data.before&&data.after)panel.append(span(data.before,'reading'),span('→','receipt-arrow'),span(data.after,'reading current-reading'));
    if(list.length){
      const awards=document.createElement('div');awards.className='receipt-awards';
      for(const {entry,amount} of list){
        const card=document.createElement('article');card.className='receipt-item '+entry.grade;
        const quantity=span(amount.toLocaleString('zh-CN'),'receipt-number');
        const label=span(entry.name,'receipt-label');
        card.append(art(entry.visual.icon),label,quantity);
        awards.append(card);
        if(amount>1)requestAnimationFrame(()=>countTo(quantity,0,amount));
      }
      panel.append(awards);
    }
    if(data.spent)panel.append(span('−'+data.spent.toLocaleString('zh-CN')+' 信用点','receipt-spend'));
    if(ceremonial){
      clearTimeout(this.timer);this.ribbon.hidden=true;this.ribbon.replaceChildren();
      const button=document.createElement('button');button.className='gold';button.dataset.receiptClose='';
      button.innerHTML=icon('check')+'确认收录';panel.append(button);
      this.beforeFocus=document.activeElement instanceof HTMLElement?document.activeElement:null;
      target.replaceChildren(panel);
      this.layer.className='acquisition '+grade+' '+(data.model?'show-model':'');
      this.layer.showModal();this.scene(data.model);
    }else{
      clearTimeout(this.timer);target.replaceChildren(panel);
      target.className='receipt '+grade;target.dataset.kind=data.kind;target.hidden=false;
      this.timer=window.setTimeout(()=>this.clear(),5900);
    }
  }
  clear(){
    clearTimeout(this.timer);this.ribbon.hidden=true;this.ribbon.replaceChildren();
    if(this.layer.open)this.layer.close();
  }
}
