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
    page.on("console",lambda m:(errors.append(m.text),print("console",m.text[:3200],flush=True)) if m.type=="error" else None)
    page.add_init_script("""if(!localStorage.getItem("pixel-sky-af-v4"))localStorage.setItem("pixel-sky-af-v4",JSON.stringify({
      credits:2600,unlocked:['j20','f16','hornet','dr1','a10','j10','spitfire'],records:[],campaign:%s,selected:%s,
      settings:{backend:%s,quality:'medium',mute:true} }));""" % (3 if args.armory else 4,json.dumps(args.airframe or ("j20" if args.armory else "f16")),json.dumps(args.backend)))
    page.goto(BASE,wait_until="domcontentloaded")
    ready(page,"home")
    assert page.locator("#application").get_attribute("data-backend")==args.backend
    print("backend",args.backend,page.evaluate("""()=>({canvas:[document.querySelector('canvas').width,document.querySelector('canvas').height],
         platform:navigator.userAgent, adapter:flightQA.engine.graphicsDevice.adapterInfo})"""),flush=True)
    outcomes={}
    record(page,"a-lobby",outcomes)
    if args.armory:
        page.locator('.sortie-action').tap()
        ready(page,'sortieprep')
        assert page.locator('[data-confirm-sortie]').is_enabled()
        assert '340' in page.locator('.briefing-flight').inner_text()
        page.screenshot(path=OUT/'factory-briefing.png',timeout=70000)
        page.locator('.briefing-flight [data-configure="bomb"]').tap()
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
        assert '炸弹' in page.locator('.briefing-flight').inner_text()
        page.locator('[data-confirm-sortie]').tap()
        ready(page,'flight')
        assert page.locator('#gun').is_visible()
        assert page.locator('#bomb').is_visible()
        assert page.evaluate("flightQA.sortie.player.bombs===2 && flightQA.sortie.player.missiles===6")
        for shot,index in enumerate([0,3],1):
            page.evaluate("""index=>{
              const g=flightQA,s=g.sortie,p=s.player,v=s.targetPoints[index].position;
              g.state='pause';g.input.on=true;
              const altitude=130,fall=(-5+Math.sqrt(25+19.62*altitude))/9.81;
              p.position.set(v.x+21,v.y+altitude+.57,v.z+128*fall-.55);
              p.previous.copyFrom(p.position);p.forward.set(0,0,-1);p.orientation.set(0,0,0,1);
              p.previousOrientation.copyFrom(p.orientation);p.velocity.set(0,0,-128);
              p.angular.setAll(0);p.speed=128;p.bombAt=0;g.world.cameraReset=true;
            }""",index)
            page.locator('#bomb').tap()
            result=page.evaluate("""()=>{
              const g=flightQA,s=g.sortie;
              const command=g.input.read(1/90,true,false,1);
              s.step(1/90,command);
              for(let i=0;i<600 && s.groups.bomb.some(q=>q.live);i++){s.time+=1/90;s.project(1/90);}
              return {released:s.stats.bomb,hit:s.stats.bombHit,targets:s.stats.kills,state:s.reason};
            }""")
            assert result["released"]==shot and result["hit"]==shot,result
        page.screenshot(path=OUT/'ground-strike.png',timeout=70000)
        page.evaluate("()=>{flightQA.state='flight';flightQA.input.on=true}")
        ready(page,'result')
        assert page.evaluate("flightQA.sortie.stats.kills===5 && flightQA.sortie.stats.bombHit===2 && flightQA.p.campaign===4")
        assert page.locator('.promotion.earned').is_visible()
        page.screenshot(path=OUT/'campaign-result.png',timeout=70000)
        page.locator('[data-do="leave"]').tap()
        ready(page,'home')
        page.locator('#navigation [data-nav="hangar"]').tap()
        ready(page,'hangar')
        assert '对地弹药' in page.locator('.air-spec').inner_text()
        page.locator('#section [data-nav="weapons"]').tap()
        ready(page,'weapons')
        page.locator('[data-gear="bomb"]').tap()
        page.locator('[data-unmount="bomb"]').tap()
        page.wait_for_function("flightQA.p.inventory.bomb===1 && flightQA.p.loadouts.j20.bomb==='none'")
        assert page.locator('[data-mount="bomb"]').is_visible()
        print("J-20 shop, purchase, install, reload, s03, bombs, promotion and detach passed",flush=True)
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
        if args.sights:
            page.evaluate("""()=>{
                const p=flightQA.p;
                p.inventory.bomb=1;p.loadouts.j20={...p.loadouts.j20,bomb:'bomb'};
            }""")
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
            assert page.evaluate("flightQA.sortie.weapons.length===3 && flightQA.sortie.enemies.every(a=>!a.alive)")
            check_sight="""()=> {
              const g=flightQA,s=g.sortie,aim=document.querySelector('#aim');
              const r=aim.getBoundingClientRect(),canvas=g.world.entry.canvas.getBoundingClientRect();
              const pose=g.playerPose,point=pose.position.clone().addInPlace(pose.forward.scale(650));
              g.world.camera.project(point,point,canvas.width,canvas.height);
              return {width:r.width,height:r.height,position:[r.x+r.width/2,r.y+r.height/2],error:Math.hypot(r.x+r.width/2-(point.x+canvas.left),r.y+r.height/2-(point.y+canvas.top)),mode:s.weapon};
            }"""
            sight=[]
            for mode in ('gun','missile','bomb'):
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
            page.wait_for_function("id=>flightQA.pilot.loaded===id && flightQA.pilot.pivot.enabled",arg=subject,timeout=40000)
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
