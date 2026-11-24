import { waves } from './wave-field';
import { heightPerByte, oceanSize, swellPeriod, wakeExtent } from './ocean-solver';

const shared=['eye','sunDir','horizon','zenith','sunColor','sea','clock','cover','cloudBase','quality','clouds','exposure','waveHeight'] as const;
const vectorNames=new Set(['eye','sunDir','horizon','zenith','sunColor','sea']);

export function environmentSource(gpu:boolean,ocean:boolean){
  const v2=gpu?'vec2f':'vec2',v3=gpu?'vec3f':'vec3',v4=gpu?'vec4f':'vec4',f=gpu?'f32':'float';
  const m4=gpu?'mat4x4f':'mat4';
  const u=(name:string)=>gpu?'uniform.'+name:name;
  const type=(name:string)=>vectorNames.has(name)?v3:f;
  const let_=(name:string,t:string,value:string,mutable=false)=>gpu?
    (mutable?'var ':'let ')+name+':'+t+'='+value+';':t+' '+name+'='+value+';';
  const fn=(name:string,args:[string,string][],t:string,body:string)=>gpu?
    'fn '+name+'('+args.map(([n,v])=>n+':'+v).join(',')+')->'+t+'{'+body+'}':
    t+' '+name+'('+args.map(([n,v])=>v+' '+n).join(',')+'){'+body+'}';
  const sample=(name:string,uv:string,level?:string)=>gpu?
    (level===undefined?'textureSample':'textureSampleLevel')+'('+name+','+name+'Sampler,'+uv+(level===undefined?'':','+level)+')':
    'texture2D('+name+','+uv+')';
  const num=(n:number)=>Number.isInteger(n)?n.toFixed(1):String(n);
  const waterSamplers=['spectrumTex','pressureTex'];
  const textures=(names:string[])=>names.map(n=>gpu?`var ${n}:texture_2d<f32>;\nvar ${n}Sampler:sampler;\n`:`uniform sampler2D ${n};`).join('');
  const pressureCoords=(point:string,origin:string)=>`(${point}-${origin}.xy)/${num(wakeExtent)}+${v2}(.5/${num(oceanSize)})`;
  const bandCoords=(point:string)=>`${point}/${num(swellPeriod)}+${v2}(.5/${num(oceanSize)})`;
  const height=(channel:string)=>`(${channel}*255.-128.)*${heightPerByte}`;
  const waveCode=waves.map((w,i)=>{
    const mag=Math.hypot(w.x,w.z);
    return let_('w'+i,f,`dot(p,${v2}(${num(w.x)},${num(w.z)}))-${u('clock')}*${num(w.rate)}`)+
      `point.y+=sin(w${i})*${w.height}*${u('waveHeight')};point.x+=cos(w${i})*${num(w.height*w.steepness*w.x/mag)}*${u('waveHeight')};`+
      `point.z+=cos(w${i})*${num(w.height*w.steepness*w.z/mag)}*${u('waveHeight')};`;
  }).join('');
  const pos=gpu?'input.position':'position',world=u('matrix_model'),vp=u('matrix_viewProjection');
  const vertexBody=let_('point',v3,pos,true)+(ocean?let_('p',v2,`(${world}*${v4}(point,1.)).xz`)+waveCode+
    let_('surface',v4,sample('spectrumTex',bandCoords('p'),'0.'))+
    let_('localWave',v4,sample('pressureTex',pressureCoords('p',u('pressureOrigin')),'0.'))+
    `point.y+=${height('surface.r')}*${u('waveHeight')}+${height('localWave.r')}*${u('pressureOrigin')}.z;`:'')+
    (gpu?'output.vWorld':'vWorld')+`=(${world}*${v4}(point,1.)).xyz;`+
    (gpu?'output.position':'gl_Position')+`=${vp}*${world}*${v4}(point,1.);`;
  const vertex=gpu?`
    attribute position:${v3};
    uniform matrix_model:${m4};
    uniform matrix_viewProjection:${m4};
    ${ocean?'uniform clock:f32;\n    uniform waveHeight:f32;\n    uniform pressureOrigin:vec3f;'+textures(waterSamplers):''}
    varying vWorld:${v3};
    @vertex fn vertexMain(input:VertexInput)->VertexOutput{
      var output:VertexOutput;
      ${vertexBody}
      return output;
    }`:
    `precision highp float;attribute ${v3} position;uniform ${m4} matrix_model;uniform ${m4} matrix_viewProjection;
    ${ocean?'uniform float clock;uniform float waveHeight;uniform vec3 pressureOrigin;'+textures(waterSamplers):''}varying ${v3} vWorld;void main(){${vertexBody}}`;
  const samplers=ocean?['weatherTex','depthTex','waveTex',...waterSamplers]:['weatherTex','deckDome','deckMountains'];
  const declarations=textures(samplers)+(ocean?(gpu?'uniform pressureOrigin:vec3f;\nuniform washCenter:vec4f;\nuniform washTrack:vec2f;':
    'uniform vec3 pressureOrigin;uniform vec4 washCenter;uniform vec2 washTrack;'):'');
  const floatHead=shared.map(n=>gpu?'uniform '+n+':'+type(n)+';\n':'uniform '+type(n)+' '+n+';').join('');
  const sky=fn('airRadiance',[['dir',v3],['sun',v3],['low',v3],['high',v3],['solar',v3]],v3,`
    ${let_('angle',f,'clamp(dot(dir,sun),-1.,1.)')}
    ${let_('altitude',f,'max(dir.y,0.)')}
    ${let_('airmass',f,'1./(altitude+.134+sqrt(altitude+.022)*.31)')}
    ${let_('rayleigh',f,'.75*(1.+angle*angle)')}
    ${let_('mie',f,'.039/pow(max(.016,1. + .7225 - 1.7*angle),1.5)')}
    ${let_('glow',f,'mie*(.16+.035*airmass)')}
    ${let_('slant',f,'1.-exp(-airmass*.24)')}
    return mix(high*high*(.81+.12*rayleigh),low*low*.84,slant)*(.81+.19*rayleigh)+solar*solar*glow;
  `);
  const drift=`${v2}(.00014,-.000085)*clock`;
  const cloud=fn('cloudVolume',[['ray',v3],['eye',v3],['sun',v3],['solar',v3],['clock',f],['cover',f],['baseHeight',f],['quality',f]],v4,`
    ${let_('sgn',f,'step(0.,ray.y)*2.-1.')}
    ${let_('invY',f,'sgn/max(abs(ray.y),.034)')}
    ${let_('thickness',f,'mix(880.,1530.,smoothstep(400.,900.,baseHeight))')}
    ${let_('a',f,'(baseHeight-eye.y)*invY')}
    ${let_('b',f,'(baseHeight+thickness-eye.y)*invY')}
    ${let_('start',f,'max(0.,min(a,b))')}
    ${let_('stop',f,'min(31500.,max(a,b))')}
    if(stop<=start){return ${v4}(0.);}
    ${let_('stepCount',f,'2.+step(.78,quality)+2.*step(1.06,quality)-step(15500.,start)*step(.78,quality)')}
    ${let_('segment',f,'(stop-start)/stepCount')}
    ${let_('optical',f,'0.',true)}
    ${let_('result',v3,`${v3}(0.)`,true)}
    ${let_('toward',f,'clamp(dot(ray,sun),0.,1.)')}
    ${let_('forward',f,'pow(toward,9.)*.32')}
    ${let_('samples',f,'0.',true)}
    for(${gpu?'var i:i32=0':'int i=0'};i<5;i++){
      if(samples>=stepCount||optical>.98){break;}
      ${let_('p',v3,'eye+ray*(start+(samples+.48+.12*sin(samples*2.1))*segment)')}
      ${let_('h',f,'clamp((p.y-baseHeight)/thickness,0.,1.)')}
      ${let_('q',v2,`p.xz*.000105+${drift}+${v2}(.175+h*.072,.286-h*.044)`)}
      ${let_('volume',v3,sample('weatherTex','q','min(2.,(start+samples*segment)*.000075)')+'.rgb')}
      ${let_('erosion',f,'volume.g',true)}
      if(quality>1.06){erosion=${sample('weatherTex',`q*2.37+${v2}(.43,h*.23)`,'0.0')}.g;}
      ${let_('shaping',f,'smoothstep(0.,.22,h)*(1.-smoothstep(.53,1.,h))')}
      ${let_('density',f,'smoothstep(.385+cover*.88,.616+cover*.88,volume.r+(volume.g-.48)*.20+(erosion-.48)*.35+(volume.b-.49)*.10)*shaping')}
      ${let_('upper',f,sample('weatherTex',`q+sun.xz*.041+${v2}(.015,-.006)`,'1.0')+'.r')}
      ${let_('edge',f,'clamp(.19+(volume.r-upper)*4.2+h*.48+forward+.16*(1.-optical),0.,1.)')}
      ${let_('alpha',f,'(1.-exp(-density*min(segment,5300.)*.00155))*(1.-smoothstep(21500.,32000.,start))')}
      ${let_('light',v3,`mix(${v3}(.078,.127,.197),mix(${v3}(.74,.81,.93),solar*solar*.91,.20+toward*.38),edge)`)}
      result+=light*alpha*(1.-optical);optical+=alpha*(1.-optical);samples+=1.;
    }
    return ${v4}(result,optical);
  `);
  const skyBody=`
    ${let_('dir',v3,'normalize(coords-eye)')}
    if(cloudBase<600.){
      ${let_('heading',f,gpu?'atan2(dir.z,dir.x)':'atan(dir.z,dir.x)')}
      ${let_('panorama',v2,`${v2}(fract(heading*.159154943+1.),.5-asin(clamp(dir.y,-1.,1.))*.318309886)`)}
      ${let_('skyPlate',v3,sample('deckDome','panorama')+'.rgb')}
      ${let_('elevation',f,'asin(clamp(dir.y,-1.,1.))')}
      ${let_('matte',v4,sample('deckMountains',v2+'(panorama.x,clamp((.23-elevation)/.31,0.,1.))'))}
      ${let_('blend',f,'matte.a*step(-.08,elevation)*step(elevation,.23)')}
      return ${v4}(pow(mix(skyPlate,matte.rgb,blend),${v3}(2.2)),1.);
    }
    ${let_('height',f,'dir.y')}
    ${let_('toward',f,'clamp(dot(dir,sunDir),0.,1.)')}
    ${let_('lit',v3,'airRadiance(dir,sunDir,horizon,zenith,sunColor)',true)}
    ${let_('disk',f,'smoothstep(.99978,.99991,toward)')}
    ${let_('crest',v2,`(eye.xz+dir.xz*(4250.-eye.y)/max(.045,height))*.000043+${drift}*.61+${v2}(.65,.33)`)}
    ${let_('high',f,sample('weatherTex','crest','1.0')+'.g')}
    ${let_('bands',f,sample('weatherTex',`crest*${v2}(.48,1.42)+${v2}(.37,-.06)`,'2.0')+'.r')}
    ${let_('density',f,'high*.64+bands*.36')}
    ${let_('feather',f,'smoothstep(.486+cover*.58,.639+cover*.67,density)*smoothstep(-.016,.067,height)*.69*clouds')}
    ${let_('backlit',v3,`mix(${v3}(.025,.043,.078),sunColor*sunColor*.59,smoothstep(-.18,.22,high-bands+toward*.11))`)}
    lit=mix(lit,mix(sunColor*sunColor*.54+${v3}(.08,.11,.15),backlit,.21),feather);
    ${let_('volume',v4,`${v4}(0.)`,true)}
    if(clouds>.5){volume=cloudVolume(dir,eye,sunDir,sunColor,clock,cover,cloudBase,quality);}
    lit+=sunColor*sunColor*(disk*3.2);
    lit=lit*(1.-volume.a)+volume.rgb;
    return ${v4}(lit*exposure,1.);
  `;
  const slope=waves.map((w,i)=>
    let_('wave'+i,f,`cos(dot(p,${v2}(${num(w.x)},${num(w.z)}))-clock*${w.rate})`)+
    `gradient+=waveHeight*wave${i}*${v2}(${num(w.x*w.height*1.6)},${num(w.z*w.height*1.6)});`).join('');
  const seaBody=`
    ${let_('p',v2,'coords.xz')}
    ${let_('hinge',v2,`clamp((p/48000.+${v2}(.5))*(1024./1025.)+${v2}(.5/1025.),${v2}(0.),${v2}(1.))`)}
    ${let_('atlas',v3,sample('depthTex','hinge')+'.rgb')}
    ${let_('bed',f,'(atlas.r*65280.+atlas.g*255.-32768.)*.25')}
    ${let_('shore',f,'(atlas.b-.5)*520.')}
    ${let_('depth',f,'max(.0,coords.y-bed)')}
    ${let_('offset',v3,'eye-coords')}
    ${let_('range',f,'length(offset)')}
    ${let_('view',v3,'offset/max(1.,range)')}
    ${let_('wind',v3,sample('weatherTex',`p*.000138+${drift}+${v2}(.177,.291)`)+'.rgb')}
    ${let_('footprint',f,"length("+(gpu?'abs(dpdx(p))+abs(dpdy(p))':'fwidth(p)')+")")}
    ${let_('detail',f,'1.-smoothstep(1.4,11.5,footprint)')}
    ${let_('swell',v2,sample('waveTex',`p/420.+${v2}(.0023,.0041)*clock`)+`.rg-${v2}(.5)`)}
    ${let_('cap',v2,sample('waveTex',`p.yx*${v2}(-.0049,.0041)+${v2}(-.0077,.004)*clock`)+`.rg-${v2}(.5)`)}
    ${let_('ripple',v2,sample('waveTex',`(p+${v2}(p.y*.31,-p.x*.17))/28.+${v2}(.014,-.019)*clock`)+`.rg-${v2}(.5)`)}
    ${let_('gradient',v2,'swell*(.057+.09*wind.b)+cap*.093*detail+ripple*.064*detail*detail',true)}
    ${slope}
    ${let_('spectrum',v4,sample('spectrumTex',bandCoords('p')))}
    ${let_('localWave',v4,sample('pressureTex',pressureCoords('p',u('pressureOrigin'))))}
    ${let_('wakeMask',f,`${u('pressureOrigin')}.z*(1.-smoothstep(200.,980.,range))`)}
    gradient+=(spectrum.ba*255.-${v2}(128.))*.0018*waveHeight+(localWave.ba*255.-${v2}(128.))*.0035*wakeMask;
    ${let_('norm',v3,`normalize(${v3}(-gradient.x,1.,-gradient.y))`)}
    ${let_('reflected',v3,'reflect(-view,norm)')}
    ${let_('fresnel',f,'.026+.866*pow(1.-clamp(dot(norm,view),.0,1.),5.)')}
    ${let_('spark',f,'max(dot(sunDir,reflected),0.)')}
    ${let_('rough',f,'1.-detail')}
    ${let_('glint',f,'pow(spark,27.+16.*rough)*.18+pow(spark,105.+45.*detail)*(.52+.21*smoothstep(.28,.71,wind.g))')}
    ${let_('seaBed',v3,`${v3}(.151,.152,.090)*exp(-depth*${v3}(.29,.119,.075))`)}
    ${let_('volume',v3,`mix(${v3}(.022,.079,.067),sea*sea*1.45,1.-exp(-depth*.061))`)}
    ${let_('cloudRay',v2,`(p+reflected.xz*(1470./max(abs(reflected.y),.09)))*.000105+${drift}+${v2}(.22,.26)`)}
    ${let_('cloudReflect',f,sample('weatherTex','cloudRay','2.0')+'.r')}
    ${let_('returnSky',v3,`mix(airRadiance(reflected,sunDir,horizon,zenith,sunColor),${v3}(.35,.42,.55)*.57+sunColor*sunColor*.16,clouds*smoothstep(.51+cover,.83+cover,cloudReflect)*.56)`)}
    ${let_('cloudShadow',f,'1.-clouds*smoothstep(.48+cover,.78+cover,wind.r)*.24')}
    ${let_('wash',f,'sin(shore*.062+clock*1.12+swell.r*7.1+cap.r*3.4)')}
    ${let_('foam',f,'(1.-smoothstep(3.,35.,depth))*(1.-smoothstep(8.,155.,abs(shore)))*smoothstep(.68,.96,wash)*smoothstep(.36,.72,wind.g+cap.r*.38)*(1.-smoothstep(580.,1550.,range)*.67)')}
    ${let_('breakers',f,'smoothstep(.071,.167,cap.r+swell.g*.32+ripple.g*.15)*smoothstep(.39,.67,wind.g)*detail*(1.-smoothstep(180.,1430.,range))*(.27+.36*waveHeight)')}
    ${let_('water',v3,`(seaBed+volume)*cloudShadow*(1.-fresnel)+returnSky*fresnel+.41*glint*sunColor*sunColor+${v3}(.48,.66,.76)*(foam*.57+breakers*.48)`)}
    ${let_('wakeFoam',f,'wakeMask*smoothstep(.075,.78,localWave.g+.41*abs(localWave.r-.502))')}
    ${let_('wakePosition',v2,`p-${u('washCenter')}.xy`)}
    ${let_('along',f,`dot(wakePosition,${u('washCenter')}.zw)`)}
    ${let_('crosswind',f,`dot(wakePosition,${v2}(${u('washCenter')}.w,-${u('washCenter')}.z))`)}
    ${let_('across',f,'abs(crosswind)')}
    ${let_('pulseRadius',f,`length(${v2}(crosswind*.83,along*.92-16.))+swell.r*7.2+cap.g*4.2+2.6*sin(crosswind*.077+along*.032)`)}
    ${let_('edgeWidth',f,'abs(across-(13.+max(0.,-along)*.38+cap.r*4.2))')}
    ${let_('rippleFade',f,'1.-smoothstep(1.4,6.4,footprint)')}
    ${let_('pressureRings',f,'pow(.5+.5*sin(pulseRadius*.40-clock*5.8+wind.g*.42),3.)*smoothstep(18.,30.,pulseRadius)*(1.-smoothstep(48.,100.,pulseRadius))*smoothstep(-38.,14.,along)')}
    ${let_('slipstream',f,'pow(.5+.5*cos(edgeWidth*.53),3.)*(1.-smoothstep(3.,12.,edgeWidth))*(1.-smoothstep(2.,16.,along))*smoothstep(-170.,-17.,along)')}
    ${let_('brokenCrests',f,'mix(.43,1.,smoothstep(-.17,.18,cap.g+ripple.r*.58+.15*sin(pulseRadius*.18+crosswind*.15)))')}
    ${let_('airWash',f,`${u('washTrack')}.x*exp(-max(0.,clock-${u('washTrack')}.y)*2.1)*smoothstep(.3,2.6,depth)*rippleFade*(pressureRings*.78*brokenCrests+slipstream*.73)`)}
    ${let_('foamLit',v3,`water+${v3}(.48,.70,.84)*(wakeFoam*.88+airWash*.67)+${v3}(.30,.43,.50)*spectrum.g*detail*.24`)}
    ${let_('veil',f,'(1.-exp(-range*.000043))*(1.-smoothstep(400.,4900.,eye.y)*.38)')}
    return ${v4}(mix(foamLit,airRadiance(-view,sunDir,horizon,zenith,sunColor),veil)*exposure,1.);
  `;
  const args:[string,string][]=[['coords',v3],...shared.map(n=>[n,type(n)] as [string,string])];
  const shade=fn('renderWorld',args,v4,ocean?seaBody:skyBody);
  const params=[gpu?'input.vWorld':'vWorld',...shared.map(u)].join(',');
  const head=gpu?'varying vWorld:'+v3+';\n':'precision highp float;varying vec3 vWorld;';
  const main=gpu?`@fragment fn fragmentMain(input:FragmentInput)->FragmentOutput{var output:FragmentOutput;output.color=renderWorld(${params});return output;}`:
    `void main(){gl_FragColor=renderWorld(${params});}`;
  return {vertex,fragment:head+declarations+floatHead+sky+(ocean?'':cloud)+shade+main,samplers};
}
