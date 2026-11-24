"""Run recovery checks against an instrumented Vite build using local static fixtures."""
from argparse import ArgumentParser
import json
from mimetypes import guess_type
from pathlib import Path
from statistics import median
from time import perf_counter
from urllib.parse import unquote, urlparse

from playwright.sync_api import sync_playwright

parser = ArgumentParser()
parser.add_argument("root", type=Path)
parser.add_argument("out", type=Path)
parser.add_argument("scenario", choices=("gl", "gpu", "loading", "gpu-stall", "device-loss", "shader", "gl-loss", "gl-restore", "no-device", "asset", "module"))
parser.add_argument("--baseline", action="store_true")
args = parser.parse_args()
root = args.root.resolve()
args.out.mkdir(parents=True, exist_ok=True)
base = "https://recovery-flight.test/"
blocked = {"asset": args.scenario == "asset", "module": args.scenario == "module"}
held = []
hold_terrain = args.scenario == "loading"


def serve(route):
    path = unquote(urlparse(route.request.url).path).strip("/")
    file = (root / (path or "index.html")).resolve()
    if blocked["asset"] and path == "world/sundown.height":
        route.fulfill(status=404)
    elif hold_terrain and path == "world/sundown.height":
        held.append(route)
    elif blocked["module"] and path.startswith("assets/index-") and file.suffix == ".js":
        route.fulfill(status=200, content_type="text/html", body="<html>Previous shell</html>")
    elif file.is_relative_to(root) and file.is_file():
        route.fulfill(path=str(file), content_type={".glb": "model/gltf-binary"}.get(file.suffix, guess_type(file)[0] or "application/octet-stream"))
    else:
        route.fulfill(status=404)


def ready(page, state, backend):
    try:
        page.wait_for_function("""([state,engine])=>document.querySelector('#application').dataset.screen===state&&
            document.querySelector('#application').dataset.backend===engine&&document.querySelector('#boot').hidden""",
            arg=[state, backend], timeout=56000)
    except Exception:
        print("startup diagnostic", page.evaluate("""()=>({url:location.href,state:document.querySelector('#application').dataset.screen,
            engine:document.querySelector('#application').dataset.backend,boot:document.querySelector('#boot-text').textContent,
            detail:document.querySelector('#boot-error').textContent,hidden:document.hidden,frames:window.flightProfile?.sample()})"""), flush=True)
        raise


with sync_playwright() as playwright:
    browser = playwright.chromium.launch(executable_path="/usr/bin/chromium", args=["--enable-unsafe-webgpu", "--ignore-gpu-blocklist",
        "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--enable-features=Vulkan", "--use-vulkan=swiftshader", "--disable-dev-shm-usage"])
    context = browser.new_context(viewport={"width": 800, "height": 360}, is_mobile=True, has_touch=True, service_workers="block")
    context.route(base + "**", serve)
    external = set()

    def reject_external(route):
        external.add(route.request.url)
        print("unexpected external asset", route.request.url, flush=True)
        route.abort()

    context.route(lambda url: url.startswith("https://") and not url.startswith(base), reject_external)
    drm = "gpu" if args.scenario in ("gpu", "gpu-stall", "device-loss", "shader") else "gl"
    context.add_init_script("""if(!localStorage.getItem('pixel-sky-af-v4'))localStorage.setItem('pixel-sky-af-v4',JSON.stringify({
        credits:2687,unlocked:['j20','f16'],selected:'j20',campaign:4,settings:{backend:'%s',quality:'medium',mute:true}}));""" % drm)
    if args.scenario == "gpu-stall":
        context.add_init_script("if(navigator.gpu) navigator.gpu.requestAdapter=()=>new Promise(()=>{});")
    if args.scenario == "no-device":
        context.add_init_script("""const original=HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext=function(kind,...args){return kind.startsWith('webgl')?null:original.call(this,kind,...args);};""")
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda m: print(m.type, m.text[:450], flush=True) if m.type in ("warning", "error") else None)
    started = perf_counter()
    page.goto(base, wait_until="domcontentloaded")

    if args.scenario == "loading":
        page.wait_for_function("document.querySelector('#boot-progress').value===23", timeout=25000)
        assert page.locator('#boot').is_visible()
        assert page.locator('#boot h1 img').get_attribute('alt') == '苍穹锋刃'
        assert not page.locator('#boot h1').inner_text().strip()
        page.screenshot(path=args.out / 'loading-landscape.png', timeout=30000)
        page.set_viewport_size({'width':390,'height':844})
        assert page.locator('#boot').is_visible()
        page.screenshot(path=args.out / 'loading-portrait.png', timeout=30000)
        page.set_viewport_size({'width':800,'height':360})
        hold_terrain = False
        assert held
        for route in held:
            serve(route)
        ready(page, 'home', 'gl')
        assert page.locator('#boot-progress').evaluate('e=>e.value') == 100
        assert not errors,errors
        print('loading passed, actual terrain wait 23% and valid first frame 100%',flush=True)
        browser.close()
        raise SystemExit(0)

    if args.scenario == "no-device":
        page.wait_for_url("**graphics=safe**")
        page.locator("#boot-actions").wait_for(state="visible", timeout=30000)
        assert "安全模式" in page.locator("#boot-error").inner_text()
        before=page.url
        page.wait_for_timeout(2000)
        assert page.url==before and not errors,errors
        print("no-device passed, recovery offer remains visible",flush=True)
        context.close()
        browser.close()
        raise SystemExit(0)

    if args.scenario in ("asset", "module"):
        page.locator("#boot-actions").wait_for(state="visible", timeout=35000)
        assert page.locator("#boot-safe").is_visible()
        assert "载入" in page.locator("#boot-text").inner_text() or page.locator("#boot-error").is_visible()
        page.screenshot(path=args.out / f"{args.scenario}-failure.png", timeout=50000)
        blocked[args.scenario] = False
        page.locator("#boot-retry").tap()
        ready(page, "home", "gl")
    elif args.scenario == "gpu-stall":
        ready(page, "home", "gl")
        assert page.evaluate("Boolean(navigator.gpu)")
        assert perf_counter() - started >= 9.0
    else:
        ready(page, "home", drm)
        if not args.baseline:
            assert page.locator('#application').get_attribute('data-render-path')=='framegraph'
        if args.scenario=="gl-restore":
            frame=page.evaluate("""()=>{
                const current=flightProfile.sample().frames;
                const extension=document.querySelector('#scene').getContext('webgl2').getExtension('WEBGL_lose_context');
                extension.loseContext();setTimeout(()=>extension.restoreContext(),1200);
                return current;
            }""")
            page.locator('#graphics-status').wait_for(state='visible',timeout=8000)
            page.locator('#graphics-status').wait_for(state='hidden',timeout=25000)
            page.wait_for_function('previous=>flightProfile.sample().frames>previous+2',arg=frame,timeout=15000)
            assert page.url==base
        elif args.scenario in ("device-loss", "shader", "gl-loss"):
            if args.scenario == "device-loss":
                page.evaluate("flightQA.engine.device._device.destroy()")
                page.wait_for_url("**graphics=compat**")
            elif args.scenario == "shader":
                page.evaluate("flightQA.engine.device._device.createShaderModule({code:'invalid shader fixture'}) && null")
                page.wait_for_url("**graphics=compat**")
            else:
                page.evaluate("document.querySelector('#scene').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext()")
                page.wait_for_url("**graphics=safe**")
            ready(page, "home", "gl")
        else:
            page.screenshot(path=args.out / f"{drm}-lobby.png", timeout=50000)
            page.locator('#navigation [data-nav="hangar"]').tap()
            ready(page, "hangar", drm)
            assert page.locator(".fleet-strip button.on").is_visible()
            page.locator('[data-back]').tap()
            ready(page, "home", drm)
            page.evaluate("()=>flightQA.begin('free',0,false,{region:0,weather:1,lighting:0})")
            ready(page, "flight", drm)
            page.evaluate("""()=>new Promise(resolve=>{
                const game=flightQA,s=game.sortie,p=s.player;
                game.state='pause';game.input.on=false;
                game.clock=4;s.time=9;
                p.reset(54,155,3970,.075,p.type.trim*.95);
                game.art.clear();game.world.cameraReset=true;
                game.engine.once('postrender',()=>{game.ui.telemetry(s,game.world,game.targetAnchors,game.playerPose);resolve();});
            })""")
            page.screenshot(path=args.out / f"{drm}-coast.png", timeout=50000)
            coast = page.evaluate("""async()=>{
                const results=[];
                for(let i=0;i<7;i++){
                    await new Promise(resolve=>flightQA.engine.once('postrender',resolve));
                    results.push(flightProfile.sample());
                }
                return results;
            }""")
            (args.out/'coast-metrics.json').write_text(json.dumps({
                'samples':coast,
                'medianCPUms':median(s['cpuFrameMs'] for s in coast if s.get('cpuFrameMs') is not None),
                'medianGPUms':median([s['gpuFrameMs'] for s in coast if s.get('gpuFrameMs') is not None]) if any(s.get('gpuFrameMs') is not None for s in coast) else None,
            },indent=2))
            assert page.evaluate("flightQA.sortie.enemies.some(e=>e.alive)")
            page.evaluate("()=>{flightQA.state='flight';flightQA.input.on=true;}")
            page.locator('#gun').tap()
            page.wait_for_function("flightQA.sortie.stats.fired>0", timeout=20000)
            page.locator('#view').tap()
            page.wait_for_function("flightQA.world.view===1", timeout=15000)
            page.screenshot(path=args.out / f"{drm}-cockpit.png", timeout=50000)
            page.evaluate("flightQA.leave()")
            ready(page, "home", drm)
            if not args.baseline:
                page.locator('#navigation [data-nav="settings"]').tap()
                rate=page.locator('select[data-setting="frameRate"]')
                assert rate.locator('option').evaluate_all('options=>options.map(o=>o.value)')==['60','90']
                rate.select_option('90')
                assert page.evaluate('flightQA.p.settings.frameRate')==90
                page.locator('[data-back]').tap()
                ready(page,'home',drm)

    assert page.evaluate("flightQA.p.credits===2687&&flightQA.p.campaign===4")
    assert not errors, errors
    print(args.scenario, "passed", round(perf_counter() - started, 2), "seconds", page.evaluate("flightProfile.sample()"),
          "KTX2", page.evaluate("flightQA.world.assets?.compressedCount?.()??null"), "external", sorted(external), flush=True)
    if not args.baseline:
        assert not external, sorted(external)
    context.close()
    browser.close()
