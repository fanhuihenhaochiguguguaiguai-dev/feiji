import type { FlightEvent } from './sortie';

export type FeedbackTone='supply'|'rare'|'ceremony'|'install'|'research'|'calibrate'|'denied';
type ToneKind=FeedbackTone|'gun'|'missile'|'blast'|'scrape'|'fracture'|'water'|'lock'|'warn'|'wave'|'switch'|'victory'|'counter'|'deflected'|'near';
const impulse:Partial<Record<ToneKind,[number,number,number,number]>>=
  {gun:[.11,960,240,.20],missile:[.48,1900,115,.45],blast:[1.06,440,52,.55],scrape:[.18,2800,610,.28],fracture:[1.70,610,38,.65],water:[.66,1450,330,.37],counter:[.35,2100,360,.26]};
const feedback:Record<FeedbackTone,{notes:number[];delay:number;decay:number;volume:number}>={
  supply:{notes:[440,590],delay:.068,decay:.16,volume:.077},
  rare:{notes:[392,523,659,784],delay:.073,decay:.36,volume:.086},
  ceremony:{notes:[196,392,523,659,784,1046],delay:.10,decay:.45,volume:.092},
  install:{notes:[174,312,461],delay:.06,decay:.16,volume:.077},
  research:{notes:[324,486,729,973],delay:.072,decay:.26,volume:.069},
  calibrate:{notes:[254,317,423,635],delay:.064,decay:.29,volume:.081},
  denied:{notes:[243,180],delay:.083,decay:.13,volume:.071},
};
export class FlightAudio {
  private context:AudioContext|null=null;
  private master:GainNode|null=null;private engine:OscillatorNode|null=null;
  private engineGain:GainNode|null=null;private sound:AudioBuffer|null=null;private link:GainNode|null=null;
  private wind:BiquadFilterNode|null=null;private rotor:OscillatorNode|null=null;
  private rotorGain:GainNode|null=null;private voices=0;private lastGun=-1;
  issuedBattleCue=0;
  private playedVoices=0;
  lastCue:''|ToneKind='';
  mute=false;
  activate(){
    if(this.context){void this.context.resume();return;}
    try {
      const c=this.context=new AudioContext(),master=this.master=c.createGain();
      master.gain.value=.39;
      const dynamics=c.createDynamicsCompressor();dynamics.threshold.value=-18;dynamics.knee.value=21;dynamics.ratio.value=4;
      master.connect(dynamics).connect(c.destination);
      const wave=this.engine=c.createOscillator(),motor=this.engineGain=c.createGain();
      wave.type='triangle';motor.gain.value=0;wave.connect(motor).connect(master);wave.start();
      this.rotor=c.createOscillator();this.rotor.type='sawtooth';
      const throat=c.createBiquadFilter();throat.type='lowpass';throat.frequency.value=205;throat.Q.value=.5;
      this.rotorGain=c.createGain();this.rotorGain.gain.value=0;
      this.rotor.connect(throat).connect(this.rotorGain).connect(master);this.rotor.start();
      const h=this.sound=c.createBuffer(1,c.sampleRate*2.3,c.sampleRate);
      const raw=h.getChannelData(0);let v=0;
      for(let i=0;i<raw.length;i++){v=.64*v+(Math.random()-.5)*.91;raw[i]=v;}
      const ambient=c.createBufferSource(),filter=this.wind=c.createBiquadFilter();
      filter.type='bandpass';filter.frequency.value=550;
      const g=this.link=c.createGain();g.gain.value=0;
      ambient.buffer=h;ambient.loop=true;ambient.connect(filter).connect(g).connect(master);ambient.start();
    }catch {/* Audio is optional on the current browser. */}
  }
  update(active:boolean,throttle:number,speed:number,boost:number,propeller:boolean,hangar=false){
    const c=this.context;if(!c||!this.master||!this.engineGain||!this.engine||!this.wind||!this.link)return;
    const t=c.currentTime;
    this.master.gain.setTargetAtTime(this.mute?0:.45,t,.13);
    this.engineGain.gain.setTargetAtTime(active?.017+throttle*.032+boost*.044:0,t,.09);
    this.engine.frequency.setTargetAtTime(propeller?37+throttle*37:49+speed*.18+boost*46,t,.11);
    this.rotor?.frequency.setTargetAtTime(propeller?19+throttle*22:47+throttle*35+boost*27,t,.15);
    this.rotorGain?.gain.setTargetAtTime(active?.016+throttle*.012+boost*.018:0,t,.12);
    this.wind.frequency.setTargetAtTime(active?280+speed*3.1:210,t,.12);this.link.gain.setTargetAtTime(active?Math.min(.075,speed*.00024)+boost*.025:hangar?.026:0,t,.15);
  }
  stats(){return {context:this.context?.state??'off',cues:this.issuedBattleCue,voices:this.playedVoices,last:this.lastCue};}
  battle(e:FlightEvent,range:number,bearing:number){
    const cue=e.kind==='breakup'?'fracture':e.kind==='hit'||e.kind==='impact'
      ?e.terminal?null:e.surface==='water'?'water':e.weapon==='gun'?'scrape':'blast'
      :e.kind==='warn'?(e.scale??0)>=4?'near':'warn'
      :e.kind==='gun'||e.kind==='missile'||e.kind==='lock'||e.kind==='wave'?e.kind:null;
    if(cue){
      this.lastCue=cue;this.issuedBattleCue++;
      this.play(cue,range,bearing);
    }
  }
  play(kind:ToneKind,range=0,bearing=0){
    const c=this.context,master=this.master;
    if(!c||!master||this.mute||range>5400)return;
    const now=c.currentTime,attenuation=Math.max(.04,Math.exp(-range/2800));
    if(kind==='gun'&&now-this.lastGun<.069)return;else if(kind==='gun')this.lastGun=now;
    const noise=impulse[kind];
    if(noise&&this.sound&&this.voices<19){
      const [life,start,end,amp]=noise,n=c.createBufferSource(),b=c.createBiquadFilter(),g=c.createGain();
      n.buffer=this.sound;b.type=kind==='gun'||kind==='water'||kind==='scrape'?'bandpass':'lowpass';
      b.frequency.setValueAtTime(start,now);b.frequency.exponentialRampToValueAtTime(end,now+life);
      g.gain.setValueAtTime(attenuation*amp,now);g.gain.exponentialRampToValueAtTime(.0001,now+life);
      const position=c.createStereoPanner();position.pan.value=bearing;
      n.connect(b).connect(g).connect(position).connect(master);this.voices++;this.playedVoices++;
      n.onended=()=>{this.voices--;n.disconnect();b.disconnect();g.disconnect();position.disconnect();};
      n.start(now,Math.random()*.44);n.stop(now+life+.02);return;
    }
    const cue=feedback[kind as FeedbackTone];
    const notes=cue?.notes??(kind==='victory'?[440,550,660,880]:kind==='lock'?[620,880]:kind==='near'?[920,1220,920]:kind==='deflected'?[740,495]:kind==='warn'?[780,590,780]:kind==='wave'?[430,530]:kind==='switch'?[410]:[]);
    notes.forEach((hz,i)=>{
      if(this.voices>=22)return;
      const when=now+i*(cue?.delay??.096),tail=cue?.decay??.22,n=c.createOscillator(),g=c.createGain();
      n.type='triangle';n.frequency.value=hz;g.gain.setValueAtTime(.001,when);
      g.gain.linearRampToValueAtTime((cue?.volume??.13)*attenuation,when+.015);
      g.gain.exponentialRampToValueAtTime(.0001,when+tail);
      n.connect(g).connect(master);n.start(when);n.stop(when+tail+.025);this.voices++;this.playedVoices++;
      n.onended=()=>{this.voices--;n.disconnect();g.disconnect();};
    });
  }
}
