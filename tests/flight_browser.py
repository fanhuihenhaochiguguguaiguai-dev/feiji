"""Automated Chromium rendering and game-flow checks for aircraft missions."""
import argparse
import json
from mimetypes import guess_type
from pathlib import Path
from urllib.parse import urlparse, unquote
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument("root",type=Path)
parser.add_argument("out",type=Path)
parser.add_argument("--backend",choices=("gl","gpu"),required=True)
parser.add_argument("--quick",action="store_true")
parser.add_argument("--airframe",choices=("j20","f16"))
parser.add_argument("--armory",action="store_true")
parser.add_argument("--coast",action="store_true")
parser.add_argument("--sights",action="store_true")
parser.add_argument("--all-air",action="store_true")
parser.add_argument("--water-drone",action="store_true")
parser.add_argument("--migration",action="store_true")
parser.add_argument("--command-map",action="store_true")
parser.add_argument("--lobby-baseline",action="store_true")
parser.add_argument("--gallery",action="store_true")
parser.add_argument("--world",action="store_true")
parser.add_argument("--touch",action="store_true")
parser.add_argument("--settle",action="store_true")
parser.add_argument("--effects",action="store_true")
parser.add_argument("--fleet",action="store_true")
parser.add_argument("--landscape",action="store_true")
parser.add_argument("--chromium",default="/usr/bin/chromium")
args=parser.parse_args()
OUT=args.out
OUT.mkdir(parents=True,exist_ok=True)
BASE="https://px-flight.test/"
SRC=args.root.resolve()
flags=["--enable-unsafe-webgpu","--ignore-gpu-blocklist","--use-angle=swiftshader","--enable-unsafe-swiftshader",
       "--disable-dev-shm-usage","--enable-features=Vulkan","--use-vulkan=swiftshader"]

def static(route):
    pathname=unquote(urlparse(route.request.url).path).strip("/")
    file=(SRC/(pathname or "index.html")).resolve()
    if not file.is_relative_to(SRC) or not file.exists():
        route.fulfill(status=404,body="Missing asset "+pathname)
        print("404",pathname,flush=True)
        return
    route.fulfill(path=str(file),content_type={".glb":"model/gltf-binary",".hdr":"application/octet-stream"}.get(file.suffix,guess_type(file)[0] or "application/octet-stream"))

def ready(page,value):
    page.wait_for_function("v=>document.querySelector('#application').dataset.screen===v && document.querySelector('#boot').hidden",arg=value,timeout=70000)
    page.wait_for_timeout(420)

def leave(page):
    page.keyboard.press("Escape")
    page.locator('[data-do="leave"]').click()
    ready(page,"home")

def record(page,name,metrics,seconds=3.0):
    page.wait_for_timeout(620)
    before=page.evaluate("()=>({...flightProfile.sample(),time:performance.now()})")
    page.wait_for_timeout(int(seconds*1000))
    after=page.evaluate("()=>({...flightProfile.sample(),time:performance.now()})")
    after["observedFPS"]=round((after["frames"]-before["frames"])*1000/(after.pop("time")-before["time"]),2)
    metrics[name]=after
    page.screenshot(path=OUT/(name+".png"),timeout=70000)
    print(name,json.dumps(after,ensure_ascii=False),flush=True)

with sync_playwright() as p:
    browser=p.chromium.launch(executable_path=args.chromium,headless=True,args=flags)
    ctx=browser.new_context(viewport={"width":800,"height":360},is_mobile=True,has_touch=True,service_workers="block")
    ctx.route(BASE+"**",static)
    page=ctx.new_page()
    errors=[]
    page.on("pageerror",lambda e:(errors.append(str(e)),print("pageerror",str(e),flush=True)))
    def console(message):
        if message.type=="error":
            errors.append(message.text)
            print("console",message.text[:3200],flush=True)
        elif message.type=="warning" and ('WebGPU' in message.text or 'shader' in message.text.lower()):
            print('warning',message.text[:1800],flush=True)
            if 'WebGPU uncaptured error' in message.text: errors.append(message.text)
    page.on('console',console)
    page.add_init_script("""if(!sessionStorage.getItem('qa-no-journal')&&!localStorage.getItem("pixel-sky-af-v4"))localStorage.setItem("pixel-sky-af-v4",JSON.stringify({
      credits:2600,unlocked:['j20','f16','hornet','dr1','a10','j10','spitfire'],records:[],campaign:%s,selected:%s,
      settings:{backend:%s,quality:'medium',mute:true} }));""" % (30 if args.water_drone else 10 if args.all_air else 3 if args.armory else 4,json.dumps(args.airframe or ("j20" if args.armory else "f16")),json.dumps(args.backend)))
    page.goto(BASE,wait_until="domcontentloaded")
    ready(page,"home")
    assert page.locator("#application").get_attribute("data-backend")==args.backend
    print("backend",args.backend,page.evaluate("""()=>({canvas:[document.querySelector('canvas').width,document.querySelector('canvas').height],
         platform:navigator.userAgent, adapter:flightQA.engine.device.getGlInfo?.()??flightQA.engine.device.description})"""),flush=True)
    outcomes={}
    record(page,"a-lobby",outcomes)
    if args.migration:
        assert page.evaluate("flightQA.engine.device.constructor.Version")=='8.56.2'
        quality=page.evaluate("""()=>{
            const g=flightQA;g.qualityOverride='high';
            return {textures:g.world.assets.estimatedTextureBytes(),ktx2:g.world.assets.compressedCount(),gl:!g.engine.device.isWebGPU};
        }""")
        assert quality['ktx2']==2,quality
        page.wait_for_timeout(1500)
        page.screenshot(path=OUT/'hangar-high.png',timeout=70000)
        page.touchscreen.tap(400,190)
        page.evaluate("()=>{flightQA.qualityOverride=null;flightQA.audio.activate()}")
        page.wait_for_function("flightQA.audio.stats().recordedLayers===2",timeout=30000)
        print('migration PBR and sampled audio',quality,flush=True)
    if args.water_drone:
        page.wait_for_function("""()=>new Promise(resolve=>{
            const db=indexedDB.open('cangqiong-pilot',1);
            db.onsuccess=()=>{
                const get=db.result.transaction('snapshots').objectStore('snapshots').get('current');
                get.onsuccess=()=>{resolve(get.result?.savedAt>0&&JSON.parse(get.result.data).campaign===30);db.result.close();};
            };
            db.onerror=()=>resolve(false);
        })""")
        page.evaluate("()=>{sessionStorage.setItem('qa-no-journal','1');localStorage.removeItem('pixel-sky-af-v4');localStorage.removeItem('pixel-sky-af-v4-recovery')}")
        page.reload(wait_until='domcontentloaded')
        ready(page,'home')
        assert page.evaluate("flightQA.p.campaign===30 && flightQA.p.credits===2600 && flightQA.p.version===9")
        page.locator('#front [data-nav="missions"]').tap()
        ready(page,'missions')
        page.locator('[data-chapter="2"]').tap()
        page.locator('[data-stage-pick="s24"]').tap()
        page.locator('#mission-launch').tap()
        ready(page,'sortieprep')
        page.locator('[data-confirm-sortie]').tap()
        ready(page,'flight')
        contact=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie;
            return {kind:s.op.kind,ground:s.targetPoints.length,missiles:s.player.missiles,
              enemies:s.enemies.flatMap((e,i)=>e.alive?[{type:e.type.id,hp:e.hp,model:g.foes[i].loaded}]:[])};
        }""")
        assert contact['kind']=='air' and contact['ground']==0 and contact['missiles']>=10,contact
        assert any(e['type']==e['model']=='shade-drone' and e['hp']>=487 for e in contact['enemies']),contact
        page.screenshot(path=OUT/'chapter-three-drones.png',timeout=70000)
        wreck=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie,e=s.enemies.find(e=>e.alive&&e.type.id==='shade-drone');
            g.state='pause';g.input.on=false;
            e.velocity.y=0;
            const y=e.position.y;const orientation=e.orientation.clone();
            s.damage(e,e.hp,0);
            for(let i=0;i<45;i++)s.advanceWrecks(1/90);
            return {steps:s.wreckPhysics?.steps??0,drop:y-e.position.y,rotated:!orientation.equals(e.orientation)};
        }""")
        assert wreck['steps']>=45 and wreck['drop']>1 and wreck['rotated'],wreck
        print('Havok rigid wreck',wreck,flush=True)
        page.evaluate("()=>flightQA.leave()")
        ready(page,'home')
        page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:1})")
        ready(page,'flight')
        before=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie,p=s.player,w=g.world;
            let x=65,z=1890;
            if(s.world.classify(x,z)!=='water'){x=5500;z=6200;}
            p.reset(x,s.world.water(x,z,s.time)+10,z,0,p.type.trim);
            p.gear=p.gearTarget=0;p.throttle=.74;
            w.cameraReset=true;
            return {time:s.time,surface:s.world.classify(x,z),foam:w.seaFields.details().foam};
        }""")
        assert before['surface']=='water' and before['foam']==0,before
        page.wait_for_function("t=>flightQA.sortie.time>=t+1.1 && flightQA.world.seaFields.details().foam>100",arg=before['time'],timeout=45000)
        page.evaluate("()=>{flightQA.state='pause';flightQA.input.on=false}")
        wake=page.evaluate("""()=>{
            const g=flightQA,p=g.sortie.player;
            return {...g.world.seaFields.details(),altitude:p.position.y,speed:p.speed};
        }""")
        assert wake['worker'] and wake['altitude']>0,wake
        page.screenshot(path=OUT/'sea-wake.png',timeout=70000)
        (OUT/'water-drone.json').write_text(json.dumps({'before':before,'wake':wake,'chapter':contact,'wreck':wreck},ensure_ascii=False,indent=2))
        print('sea wake and chapter three',wake,contact,flush=True)
        loss=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie,p=s.player,e=s.enemies.find(e=>e.alive);
            p.reset(0,2800,0,0,0);p.hp=1;e.reset(0,2800,120,0,0);e.gunsAt=0;
            s.fire(e,'gun');
            for(let i=0;i<45&&s.active;i++)s.project(1/90);
            g.state='flight';
            return {reason:s.reason,hp:p.hp};
        }""")
        assert loss=={'reason':'战机被击落','hp':0},loss
        ready(page,'result')
        assert '战机被击落' in page.locator('.debrief-title').inner_text()
        print('enemy fire ended the sortie',loss,flush=True)
        page.locator('[data-do="leave"]').tap()
        ready(page,'home')
    if args.migration:
        page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:1})")
        ready(page,'flight')
        outside=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie,p=s.player,t=s.world;
            g.state='pause';g.input.on=false;s.time+=4;
            let pos;
            for(let i=0;i<65;i++){
                const x=27700+i*421,z=-17800+i*688;
                if(t.field(x,z)>80){pos=[x,t.field(x,z),z];break;}
            }
            p.reset(pos[0],pos[1]+2900,pos[2],.54,p.type.trim);g.world.cameraReset=true;
            return {position:pos,t:s.time};
        }""")
        assert outside['position'][0]>24000 and outside['position'][1]>80,outside
        page.wait_for_function("()=>[...flightQA.world.terrainTiles.values()].some(tile=>tile.x>=1024)",timeout=35000)
        page.screenshot(path=OUT/'generated-terrain.png',timeout=70000)
        print('generated terrain',outside,page.evaluate('flightQA.world.terrainStats()'),flush=True)
        page.evaluate("()=>flightQA.leave()")
        ready(page,'home')
    if args.armory:
        page.locator('.sortie-action').tap()
        ready(page,'sortieprep')
        assert page.locator('[data-confirm-sortie]').is_enabled()
        assert '340' in page.locator('.briefing-flight').inner_text()
        page.screenshot(path=OUT/'factory-briefing.png',timeout=70000)
        page.locator('.briefing-flight [data-configure="missile"]').tap()
        ready(page,'weapons')
        page.locator('[data-gear="cannon"]').tap()
        assert page.locator('.cannon-spec').is_visible()
        assert page.locator('[data-buy]').count()==0
        page.screenshot(path=OUT/'factory-cannon.png',timeout=70000)
        page.locator('[data-gear="bomb"]').tap()
        page.locator('[data-buy="bomb"]').tap()
        assert page.locator('#purchase-confirm').is_visible()
        page.locator('[data-buy-commit="bomb"]').tap()
        page.wait_for_function("flightQA.p.credits===2260 && flightQA.p.inventory.bomb===1")
        page.locator('[data-mount="bomb"]').tap()
        page.wait_for_function("flightQA.p.loadouts.j20.bomb==='bomb'")
        page.screenshot(path=OUT/'loadout-J20.png',timeout=70000)
        page.reload(wait_until='domcontentloaded')
        ready(page,'home')
        assert page.evaluate("flightQA.p.credits===2260 && flightQA.p.loadouts.j20.bomb==='bomb'")
        page.locator('.sortie-action').tap()
        ready(page,'sortieprep')
        assert page.locator('[data-confirm-sortie]').is_enabled()
        assert '炸弹' not in page.locator('.briefing-flight').inner_text()
        page.locator('[data-confirm-sortie]').tap()
        ready(page,'flight')
        assert page.locator('#gun').is_visible() and page.locator('#bomb').is_hidden()
        assert page.evaluate("flightQA.sortie.player.bombs===0 && flightQA.sortie.player.missiles===10 && flightQA.sortie.enemies.some(a=>a.alive)")
        leave(page)
        page.locator('#navigation [data-nav="hangar"]').tap()
        ready(page,'hangar')
        assert '对地弹药' in page.locator('.air-spec').inner_text()
        page.locator('#section [data-nav="weapons"]').tap()
        ready(page,'weapons')
        page.locator('[data-gear="bomb"]').tap()
        page.locator('[data-unmount="bomb"]').tap()
        page.wait_for_function("flightQA.p.inventory.bomb===1 && flightQA.p.loadouts.j20.bomb==='none'")
        assert page.locator('[data-mount="bomb"]').is_visible()
        print("J-20 purchase, install, reload, air-only sortie and detach passed",flush=True)
        page.locator('#section .station-heading [data-back]').tap()
        ready(page,'hangar')
        page.locator('#section .station-heading [data-back]').tap()
        ready(page,'home')
        page.locator('#front [data-nav="missions"]').tap()
        ready(page,'missions')
        assert page.locator('[data-chapter]').count()==6 and page.locator('[data-stage-pick]').count()==10
        page.set_viewport_size({"width":1280,"height":720})
        page.screenshot(path=OUT/'campaign-map.png',timeout=70000)
        page.locator('[data-chapter="5"]').click()
        assert page.locator('[data-stage-pick="s60"]').get_attribute("data-state")=="locked"
        page.locator('[data-stage-pick="s60"]').click()
        assert page.locator('#mission-launch').is_disabled()
        assert '苍穹试炼' in page.locator('#mission-details').inner_text()
        print("chapter map and locked final ace checked",flush=True)
        page.evaluate("()=>flightQA.ui.open('home')")
        ready(page,'home')
    if args.coast or args.sights:
        page.set_viewport_size({"width":1000,"height":450})
        page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:0})")
        ready(page,'flight')
        page.evaluate("""()=>new Promise(resolve=>{
            const g=flightQA,s=g.sortie,p=s.player;
            g.state='pause';g.input.on=false;
            p.reset(54,155,3970,.075,p.type.trim*.95);
            g.art.clear();g.world.cameraReset=true;
            g.engine.once('postrender',()=>{
                g.ui.telemetry(s,g.world,g.targetAnchors,g.playerPose);resolve();
            });
        })""")
        page.screenshot(path=OUT/'coast-fixed.png',timeout=70000)
        if args.sights:
            assert page.evaluate("flightQA.sortie.weapons.length===2 && flightQA.sortie.enemies.some(a=>a.alive)")
            check_sight="""()=> {
              const g=flightQA,s=g.sortie,aim=document.querySelector('#aim');
              const r=aim.getBoundingClientRect(),canvas=g.world.entry.canvas.getBoundingClientRect();
              const pose=g.playerPose,point=pose.position.clone().addInPlace(pose.forward.scale(650));
              g.world.camera.project(point,point,canvas.width,canvas.height);
              return {width:r.width,height:r.height,position:[r.x+r.width/2,r.y+r.height/2],error:Math.hypot(r.x+r.width/2-(point.x+canvas.left),r.y+r.height/2-(point.y+canvas.top)),mode:s.weapon};
            }"""
            sight=[]
            for mode in ('gun','missile'):
                page.evaluate("""mode=>new Promise(resolve=>{
                  const g=flightQA;g.sortie.weapon=mode;
                  g.engine.once('postrender',()=>{
                    g.ui.telemetry(g.sortie,g.world,g.targetAnchors,g.playerPose);resolve();
                  });
                })""",mode)
                sight.append(page.evaluate(check_sight))
            assert all(x["error"]<.75 and x["width"]>30 and x["height"]==x["width"] for x in sight),sight
            assert len({x["width"] for x in sight})==1 and len({tuple(x["position"]) for x in sight})==1,sight
            initial=page.evaluate("""()=>{
                const g=flightQA;g.sortie.weapon='gun';g.state='flight';g.input.on=true;return g.sortie.time;
            }""")
            page.wait_for_function("t=>flightQA.sortie.time>t+.42",arg=initial,timeout=45000)
            page.locator('#gun').tap()
            page.wait_for_function("flightQA.sortie.stats.fired>=1",timeout=30000)
            outcomes["coast-wake"]=page.evaluate("()=>flightProfile.sample()")
            page.screenshot(path=OUT/'coast-wake.png',timeout=70000)
            page.locator('#view').tap()
            page.wait_for_function("flightQA.world.view===1")
            page.screenshot(path=OUT/'sight-cockpit.png',timeout=70000)
            cockpit=page.evaluate(check_sight)
            assert cockpit["error"]<.75 and cockpit["width"]==sight[0]["width"],cockpit
            print("sight aligned in three weapons and cockpit",sight,cockpit,flush=True)
            (OUT/'sight.json').write_text(json.dumps({"external":sight,"cockpit":cockpit},indent=2))
        page.evaluate("()=>flightQA.leave()")
        ready(page,'home')
    if args.all_air:
        page.locator('#front [data-nav="missions"]').tap()
        ready(page,'missions')
        page.locator('[data-chapter="0"]').tap()
        for marker in ('s01','s02','s03','s04'):
            page.locator('[data-chart-home]').tap()
            page.locator(f'[data-pick="{marker}"]').tap()
            assert page.locator('#mission-launch').get_attribute('data-task')==marker
        assert page.locator('[data-chapter]').count()==6
        for chapter in range(6):
            page.locator(f'[data-chapter="{chapter}"]').tap()
            assert page.locator('[data-stage-pick]').count()==10
            assert page.locator('[data-stage-pick][data-boss="true"]').get_attribute('data-stage-pick')==f's{(chapter+1)*10:02}'
        page.locator('[data-chapter="0"]').tap()
        page.locator('[data-stage-pick="s10"]').tap()
        page.screenshot(path=OUT/'chapter-boss.png',timeout=70000)
        page.locator('#mission-launch').tap()
        ready(page,'sortieprep')
        page.locator('[data-confirm-sortie]').tap()
        ready(page,'flight')
        boss=page.evaluate("""()=>{
            const g=flightQA,s=g.sortie;g.state='pause';g.input.on=false;
            while(s.wave<s.waves.length&&s.active){
                for(const e of s.enemies)if(e.alive)s.damage(e,e.hp,0);
                s.step(1/90,g.input.read(1/90,true,false,1));
            }
            const ace=s.enemies.find(e=>e.alive&&e.ace);
            s.damage(ace,s.missile.damage,0);s.damage(ace,s.missile.damage,0);
            g.state='flight';g.input.on=true;
            return {hp:ace.hp,type:ace.type.id,total:s.total,wave:s.wave};
        }""")
        assert boss['hp']>0 and boss['type']=='mirage',boss
        page.locator('#boss-health').wait_for(state='visible')
        page.screenshot(path=OUT/'boss-flight.png',timeout=70000)
        clear_wave="""()=>{
            const s=flightQA.sortie;
            for(const e of s.enemies)if(e.alive)s.damage(e,e.hp,0);
        }"""
        page.evaluate(clear_wave)
        ready(page,'result')
        assert '任务胜利' in page.locator('.debrief-title').inner_text()
        assert page.evaluate("n=>flightQA.p.campaign===n && flightQA.p.completed.includes('s10')",30 if args.water_drone else 11)
        page.locator('[data-do="leave"]').tap()
        ready(page,'home')
        def endless():
            page.locator('#front [data-nav="freeprep"]').tap()
            ready(page,'freeprep')
            page.locator('[data-task="free"]').tap()
            ready(page,'flight')
            return page.evaluate("""()=>({opening:flightQA.sortie.opening,wave:flightQA.sortie.wave,
                hp:flightQA.sortie.enemies[0].maxHp,alive:flightQA.sortie.enemies.filter(e=>e.alive).length})""")
        first=endless()
        assert first['wave']==1 and first['alive']>0,first
        page.evaluate(clear_wave)
        page.wait_for_function("flightQA.sortie.wave===2 && flightQA.sortie.enemies.some(e=>e.alive)")
        assert page.evaluate("flightQA.sortie.enemies[0].maxHp")>first['hp']
        page.screenshot(path=OUT/'endless-flight.png',timeout=70000)
        page.locator('#pause').tap()
        page.get_by_role('button',name='结算并撤离').tap()
        ready(page,'result')
        assert '自由空战结算' in page.locator('.debrief-title').inner_text()
        page.locator('[data-do="leave"]').tap()
        ready(page,'home')
        second=endless()
        assert second['opening']!=first['opening'] and second['hp']!=first['hp'],(first,second)
        print('all-air flow',json.dumps({'boss':boss,'firstRun':first,'secondRun':second},ensure_ascii=False),flush=True)
        (OUT/'mission-loop.json').write_text(json.dumps({'boss':boss,'firstRun':first,'secondRun':second},indent=2))
        leave(page)
    if args.lobby_baseline or args.command_map:
        page.set_viewport_size({"width":1280,"height":720})
        record(page,"home-1280",outcomes,2)
    if args.command_map:
        assert page.locator('#front [data-nav="missions"]').count()==1
        assert page.locator('#navigation [data-nav]').count()==6
        destinations=page.locator('#front [data-nav],#navigation [data-nav]')
        routes=destinations.evaluate_all("nodes=>nodes.map(n=>n.dataset.nav)")
        assert len(routes)==len(set(routes))==14,routes
        for route in routes:
            page.locator('#front [data-nav="'+route+'"],#navigation [data-nav="'+route+'"]').click()
            ready(page,route)
            assert page.locator('#front').is_hidden() and page.locator('#section h2').is_visible()
            if args.gallery and route!='missions':
                page.screenshot(path=OUT/(route+".png"),timeout=70000)
            page.locator('[data-back]').click()
            ready(page,"home")
        page.locator('#navigation [data-sortie]').click()
        ready(page,"sortieprep")
        assert page.locator('[data-confirm-sortie]').is_visible()
        page.locator('[data-back]').click()
        ready(page,"home")
        page.locator('#front [data-nav="missions"]').click()
        ready(page,"missions")
        page.wait_for_function("document.querySelector('.chart-world img').naturalWidth===2880")
        page.screenshot(path=OUT/"campaign-1280.png",timeout=70000)
        page.evaluate("""()=>{flightQA.p.campaign=1;flightQA.p.completed=[];flightQA.ui.render()}""")
        assert page.locator('[data-pick="s04"]').get_attribute("data-state")=="locked"
        page.locator('[data-pick="s04"]').click()
        assert page.locator('#mission-launch').is_disabled()
        assert page.locator('#mission-chart').evaluate("el=>el.classList.contains('zoomed')")
        page.locator('[data-chart-home]').click()
        assert page.locator('#mission-chart').evaluate("el=>!el.classList.contains('zoomed')")
        page.locator('[data-mode="independent"]').click()
        assert page.locator('[data-pick="d01"]').get_attribute("aria-pressed")=="true"
        assert page.locator('.chart-route').count()==0
        page.locator('[data-mode="campaign"]').click()
        page.locator('[data-difficulty="2"]').click()
        assert page.locator('#mission-credit-rate').inner_text()=="130%"
        assert page.locator('[data-difficulty="2"]').get_attribute("aria-pressed")=="true"
        for width,height in ((800,360),(1536,691)):
            page.set_viewport_size({"width":width,"height":height})
            assert page.locator('#mission-launch').is_visible()
            bounds=page.locator('#mission-launch').bounding_box()
            assert bounds['y']+bounds['height']<height
            page.screenshot(path=OUT/("campaign-"+str(width)+".png"),timeout=70000)
        page.set_viewport_size({"width":393,"height":852})
        assert page.locator('#orientation-gate').is_visible()
        assert page.locator('#section').is_hidden()
        page.set_viewport_size({"width":800,"height":360})
        page.locator('#mission-launch').click()
        ready(page,"sortieprep")
        assert page.locator('.dispatch-options').inner_text().find('精英')>=0
        page.locator('[data-back]').click()
        ready(page,"missions")
        page.locator('[data-back]').click()
        ready(page,"home")
        print("command-map",len(routes),"lobby routes, global image, campaign lock/difficulty/prep and three landscape layouts",flush=True)
    if args.gallery and not args.command_map:
        for width,height in [(1280,720),(1536,691),(393,852)]:
            page.set_viewport_size({"width":width,"height":height})
            page.wait_for_timeout(650)
            page.screenshot(path=OUT/("home-"+str(width)+".png"),timeout=70000)
            if height>width and page.locator('#orientation-gate').count():
                assert page.locator('#orientation-gate').is_visible()
                assert page.locator('#menu').is_hidden()
            else:
                assert page.locator('.sortie-action').is_visible()
        page.set_viewport_size({"width":1280,"height":720})
        for route in ("hangar","upgrade","weapons","tree","quests","missions","activity","season","training","freeprep","inventory","records","base","settings"):
            page.evaluate("(route)=>flightQA.ui.open(route)",route)
            ready(page,route)
            assert page.locator("#section").is_visible()
            assert page.locator("#front").is_hidden()
            assert page.locator("#section h2").inner_text().strip()
            page.screenshot(path=OUT/(route+".png"),timeout=70000)
            page.locator("[data-back]").click()
            ready(page,"home")
        page.set_viewport_size({"width":800,"height":360})
    if not args.quick:
        page.locator('#front [data-nav="missions"]').click()
        page.locator('[data-pick="s01"]').click()
        page.locator('[data-task="s01"]').click()
        if page.locator('[data-confirm-sortie]').count():
            ready(page,"sortieprep")
            page.screenshot(path=OUT/"sortieprep.png",timeout=70000)
            page.locator('[data-confirm-sortie]').click()
        ready(page,"flight")
        assert page.evaluate("flightQA.sortie.enemies.filter(u=>u.alive).length")>=2
        page.wait_for_function("flightQA.sortie.lockProgress>=1",timeout=45000)
        page.locator("#missile").tap()
        page.wait_for_function("flightQA.sortie.stats.missile>=1",timeout=30000)
        record(page,"b-dogfight",outcomes)
        if page.locator("#radar-open").count():
            page.locator("#radar-open").tap()
            assert page.locator("#tactical").is_visible()
            assert page.locator("#tactical-status").inner_text().startswith("探测半径")
            page.screenshot(path=OUT/"tactical.png",timeout=70000)
            page.locator('#tactical button').tap()
            assert page.locator("#tactical").is_hidden()
            assert page.locator("#flight-stick").count()==0
        page.locator("#view").tap()
        page.wait_for_function("flightQA.world.view===1")
        record(page,"b-cockpit",outcomes)
        leave(page)
    if not args.quick and page.evaluate("typeof flightProfile.alignment==='function'"):
        page.evaluate("()=>flightQA.begin('s01',1,false,{region:0,weather:1,lighting:2},true)")
        ready(page,"flight")
        fixtures=[]
        for viewport,distance,turn in [((800,360),180,0),((1280,720),1550,.32),((1536,691),3150,-.38)]:
            width,height=viewport
            page.set_viewport_size({"width":width,"height":height})
            result=page.evaluate("""async({heading,range})=>{
                const g=flightQA,s=g.sortie,enemy=s.enemies[0],p=s.player;
                p.reset(0,2350,2900,heading,p.type.trim);
                enemy.reset(Math.sin(heading)*range+15,2410,2900-Math.cos(heading)*range,heading,enemy.type.trim);
                g.world.cameraReset=true;
                const samples=[];
                for(let frame=0;frame<4;frame++){
                    await new Promise(resolve=>g.engine.once('postrender',resolve));
                    samples.push(...flightProfile.alignment());
                }
                return samples.filter(a=>Math.abs(a.range-range)<420);
            }""",{"heading":turn,"range":distance})
            assert result and max(r["error"] for r in result)<.8,(viewport,distance,result)
            fixtures.extend(result)
            page.screenshot(path=OUT/("enemy-"+str(distance)+".png"),timeout=70000)
        (OUT/"alignment.json").write_text(json.dumps(fixtures,ensure_ascii=False,indent=2))
        print("target positions",len(fixtures),"max CSS pixel error",max(i["error"] for i in fixtures),flush=True)
        leave(page)
    if args.touch:
        page.locator('#navigation [data-nav="hangar"]').click()
        ready(page,"hangar")
        page.wait_for_function("document.querySelector('.fleet-strip button.on img')?.naturalWidth>0")
        page.screenshot(path=OUT/"hangar-final.png",timeout=70000)
        page.locator("[data-back]").click()
        ready(page,"home")
        page.set_viewport_size({"width":800,"height":360})
        page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:1},true)")
        ready(page,"flight")
        cdp=ctx.new_cdp_session(page)
        gun=page.locator("#gun").bounding_box()
        before=page.evaluate("()=>({rounds:flightQA.sortie.player.cannon,pitch:flightQA.sortie.player.forward.y})")
        p1={"x":380,"y":198,"id":1}
        p2={"x":gun["x"]+gun["width"]/2,"y":gun["y"]+gun["height"]/2,"id":2}
        cdp.send("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":[p1]})
        cdp.send("Input.dispatchTouchEvent",{"type":"touchStart","touchPoints":[p1,p2]})
        cdp.send("Input.dispatchTouchEvent",{"type":"touchMove","touchPoints":[{**p1,"y":119},p2]})
        page.wait_for_function("""prev=>flightQA.sortie.player.cannon<prev.rounds&&flightQA.sortie.player.forward.y>prev.pitch+.035""",arg=before,timeout=25000)
        during=page.evaluate("()=>({rounds:flightQA.sortie.player.cannon,pitch:flightQA.sortie.player.forward.y})")
        cdp.send("Input.dispatchTouchEvent",{"type":"touchEnd","touchPoints":[]})
        assert page.locator(".pressed").count()==0
        print("simultaneous touch pitch+fire",before,during,flush=True)
        log={"before":before,"during":during}
        (OUT/"touch.json").write_text(json.dumps(log,indent=2))
        page.screenshot(path=OUT/"touch-flight.png",timeout=70000)
        cdp.detach()
        leave(page)
    if args.settle:
        page.locator('#front [data-nav="training"]').click()
        page.locator('[data-task="t04"]').click()
        page.locator('[data-confirm-sortie]').click()
        ready(page,"flight")
        page.wait_for_function("flightQA.sortie.lockProgress>=1",timeout=40000)
        page.locator("#missile").tap()
        ready(page,"result")
        assert "任务胜利" in page.locator(".debrief-title").inner_text()
        assert page.evaluate("flightQA.p.completed.includes('t04') && flightQA.p.daily.sorties===1")
        page.screenshot(path=OUT/"result.png",timeout=70000)
        page.locator('[data-do="leave"]').click()
        ready(page,"home")
        page.locator('#front [data-nav="quests"]').click()
        ready(page,"quests")
        balance=page.evaluate("flightQA.p.credits")
        page.locator('[data-claim="daily-sortie"]').click()
        page.wait_for_function("b=>flightQA.p.credits===b+150 && flightQA.p.daily.claimed.includes('daily-sortie')",arg=balance)
        assert page.locator('[data-claim="daily-sortie"]').is_disabled()
        page.screenshot(path=OUT/"daily-claim.png",timeout=70000)
        print("training victory and persisted daily reward",flush=True)
        page.locator('[data-back]').click()
        ready(page,"home")
    if args.effects:
        page.set_viewport_size({"width":1000,"height":450})
        page.locator('#navigation [data-nav="upgrade"]').click()
        ready(page,"upgrade")
        page.locator('#section button[data-nav="weapons"]').click()
        ready(page,"weapons")
        page.locator('[data-preview-missile]').first.click()
        assert page.locator('#acquisition').is_visible()
        assert page.locator('#application').get_attribute("data-reveal")=="model"
        page.wait_for_timeout(600)
        page.screenshot(path=OUT/"component.png",timeout=70000)
        page.locator('[data-receipt-close]').click()
        page.evaluate("()=>flightQA.begin('t04',0,false,{region:0,weather:0,lighting:2},true)")
        ready(page,"flight")
        first_event=page.evaluate("flightProfile.combat().events.length")
        page.evaluate("()=>{flightQA.p.settings.mute=false;flightQA.settings()}")
        page.locator('#gun').tap()
        shot=page.evaluate("""()=> {
          const g=flightQA,s=g.sortie,p=s.player,e=s.enemies[0];
          g.state='pause';g.input.on=false;
          p.reset(35,1450,2700,0,179);
          e.reset(36,1450,2628,0,179);
          g.world.cameraReset=true;
          const input={...p.controls,gun:true};
          for(let step=0;step<27&&s.stats.hit===0;step++)s.step(1/90,input);
          return {hit:s.stats.hit,hp:e.hp,fired:s.stats.fired};
        }""")
        assert shot["hit"]>0 and shot["hp"]>0,shot
        page.screenshot(path=OUT/"cannon-contact.png",timeout=70000)
        hit=page.evaluate("()=>flightProfile.combat()")
        assert any(e["kind"]=="hit" and e["weapon"]=="gun" and e["track"] for e in hit["events"][first_event:])
        defeated=page.evaluate("""()=> {
          const g=flightQA,s=g.sortie,p=s.player,e=s.enemies[0];
          const input={...p.controls,gun:true};
          for(let step=0;step<160&&s.active;step++){
            // Reset the deterministic target track while exercising the actual
            // flight step, clock, cannon, swept response and damage pipeline.
            if(step%16===0){
              p.reset(35,1450,2700,0,179);
              const hp=e.hp;
              e.reset(36,1450,2628,0,179);
              e.hp=hp;
            }
            s.step(1/90,input);
          }
          g.state='flight';
          return {kills:s.stats.kills,win:s.win};
        }""")
        assert defeated=={"kills":1,"win":True},defeated
        page.wait_for_function("flightQA.state==='settling'||flightQA.state==='result'",timeout=50000)
        page.screenshot(path=OUT/"breakup.png",timeout=70000)
        ready(page,"result")
        result=page.evaluate("()=>flightProfile.combat()")
        result["events"]=result["events"][first_event:]
        assert len([e for e in result["events"] if e["kind"]=="breakup"])==1,result["events"]
        assert result["audio"]["cues"]>0 and result["audio"]["context"]=="running" and result["audio"]["voices"]>0
        (OUT/"contacts.json").write_text(json.dumps(result,ensure_ascii=False,indent=2))
        print("impact, breakup and audio",result["audio"],flush=True)
        page.locator('[data-do="leave"]').click()
        ready(page,"home")
    if args.fleet:
        page.set_viewport_size({"width":800,"height":360})
        page.locator('#navigation [data-nav="hangar"]').click()
        ready(page,"hangar")
        subjects=page.locator('.fleet-strip [data-air]').evaluate_all("(nodes)=>nodes.map(n=>n.dataset.air)")
        assert len(subjects)==22 and len(set(subjects))==22
        fleet_dir=OUT/"fleet"
        fleet_dir.mkdir(exist_ok=True)
        for subject in subjects:
            page.locator('[data-air="'+subject+'"]').click()
            page.wait_for_function("id=>flightQA.pilot.loaded===id && flightQA.pilot.pivot.isEnabled()",arg=subject,timeout=40000)
            await_lod=page.evaluate("""()=>new Promise(resolve=>flightQA.engine.once('postrender',()=>resolve(flightQA.pilot.lod)))""")
            assert await_lod==0
            page.screenshot(path=fleet_dir/(subject+".png"),clip={"x":185,"y":62,"width":425,"height":230},timeout=70000)
        print("real GLB fleet rendered",len(subjects),flush=True)
        page.locator('[data-back]').click()
        ready(page,"home")
    if args.landscape:
        checked=[]
        def hidden_game(station):
            page.set_viewport_size({"width":393,"height":852})
            assert page.locator("#orientation-gate").is_visible()
            visible=page.evaluate("""()=>[...document.querySelector('#application').children]
                .filter(el=>el.getBoundingClientRect().height>0).map(el=>el.id)""")
            assert visible==["orientation-gate"],(station,visible)
            checked.append(station)
            page.set_viewport_size({"width":800,"height":360})
            assert page.locator("#orientation-gate").is_hidden()
        for station in ["home","hangar","upgrade","weapons","tree","quests","missions","training","activity","season","freeprep","inventory","records","base","settings","sortieprep"]:
            page.evaluate("(value)=>flightQA.ui.open(value)",station)
            ready(page,station)
            hidden_game(station)
        page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:1},true)")
        ready(page,"flight")
        page.locator('#radar-open').tap()
        assert page.locator('#tactical').is_visible()
        page.set_viewport_size({"width":393,"height":852})
        page.wait_for_function("flightQA.state==='pause' && !document.querySelector('#tactical').open")
        assert page.locator('#hud').is_hidden()
        assert page.locator('#overlay').is_hidden()
        assert page.locator("#orientation-gate").is_visible()
        at=page.evaluate("flightQA.sortie.time")
        page.wait_for_timeout(650)
        assert page.evaluate("flightQA.sortie.time")==at
        page.screenshot(path=OUT/"rotation-gate.png",timeout=70000)
        page.set_viewport_size({"width":800,"height":360})
        page.locator('[data-do="resume"]').click()
        page.wait_for_function("flightQA.state==='flight'")
        checked.extend(["flight","tactical","pause"])
        (OUT/"orientation.json").write_text(json.dumps({"routes":checked,"pausedTime":at},indent=2))
        print("landscape-only routes and rotation pause",len(checked),flush=True)
        leave(page)
    if args.world:
        frames=[
            ("cloud-deck",1,3200,1200,4600,-.28,2,0),
            ("snow-range",1,1760,-1200,1950,-.36,1,1),
            ("island-chain",0,520,20,2420,.04,1,1),
            ("sea-level",0,29,65,1890,.05,1,1),
            ("sunset",0,490,135,2690,.72,0,2),
            ("storm-coast",2,1250,300,3400,.09,4,0),
        ]
        page.set_viewport_size({"width":1000,"height":450})
        for name,region,alt,x,z,heading,weather,lighting in frames:
            awaitConfig={"region":region,"weather":weather,"lighting":lighting}
            page.evaluate("p=>flightQA.begin('free',0,false,p,true)",awaitConfig)
            ready(page,"flight")
            results=page.evaluate("""pose=>new Promise(resolve=>{
                const g=flightQA,s=g.sortie,p=s.player;
                g.state='pause';g.input.on=false;
                p.reset(pose.x,pose.alt,pose.z,pose.heading,p.type.trim);
                g.world.cameraReset=true;
                g.engine.once('postrender',()=>resolve({altitude:p.position.y,heading:p.heading(),quality:g.world.level}));
            })""",{"x":x,"z":z,"alt":alt,"heading":heading})
            page.evaluate("()=>document.querySelector('#hud').hidden=true")
            page.wait_for_timeout(1000)
            page.screenshot(path=OUT/(name+".png"),timeout=70000)
            print(name,results,flush=True)
            page.evaluate("()=>flightQA.leave()")
            ready(page,"home")
    print("errors",errors,flush=True)
    assert not errors
    (OUT/"metrics.json").write_text(json.dumps(outcomes,ensure_ascii=False,indent=2))
    browser.close()
