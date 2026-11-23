
const key="px-sky-remake-f41d99fa5463";
const release=["./assets/flight-math-Bob9GO1W.js","./assets/index-BTctMR21.css","./assets/index-FNbjNlZJ.js","./briefing/coast.webp","./briefing/hangar.webp","./briefing/training.webp","./cards/a10.webp","./cards/alphajet.webp","./cards/b2.webp","./cards/bf109.webp","./cards/c130.webp","./cards/camel.webp","./cards/dr1.webp","./cards/e2.webp","./cards/ea6b.webp","./cards/f16.webp","./cards/g91.webp","./cards/gripen.webp","./cards/hornet.webp","./cards/j10.webp","./cards/j20.webp","./cards/me262.webp","./cards/mig21.webp","./cards/mirage.webp","./cards/p51.webp","./cards/spitfire.webp","./cards/su35.webp","./cards/zero.webp","./charts/frost.webp","./charts/storm.webp","./charts/sundown.webp","./charts/world.webp","./fleet/a10.glb","./fleet/alphajet.glb","./fleet/b2.glb","./fleet/bf109.glb","./fleet/c130.glb","./fleet/camel.glb","./fleet/dr1.glb","./fleet/e2.glb","./fleet/ea6b.glb","./fleet/f16.glb","./fleet/g91.glb","./fleet/gripen.glb","./fleet/hornet.glb","./fleet/j10.glb","./fleet/j20.glb","./fleet/me262.glb","./fleet/mig21.glb","./fleet/mirage.glb","./fleet/p51.glb","./fleet/spitfire.glb","./fleet/su35.glb","./fleet/zero.glb","./icon.svg","./index.html","./items/alloy.webp","./items/bomb.webp","./items/bronze-sky.webp","./items/cannon-heavy.webp","./items/cannon-jet.webp","./items/cannon-light.webp","./items/circuit.webp","./items/credits-wallet.webp","./items/credits.webp","./items/factory.webp","./items/flarewing.webp","./items/interceptor.webp","./items/navy.webp","./items/night.webp","./items/reserve.webp","./items/sand.webp","./items/shorebolt.webp","./items/skylance.webp","./items/survey.webp","./items/tech-horizon.webp","./items/tech-power.webp","./items/tech-signal.webp","./items/tech-vectoring.webp","./items/up-armor.webp","./items/up-cadence.webp","./items/up-engine.webp","./items/up-maneuver.webp","./items/up-radar.webp","./items/up-stores.webp","./items/up-warhead.webp","./items/up-weapons.webp","./items/vector.webp","./items/veil.webp","./items/xp.webp","./licenses/playcanvas.txt","./manifest.webmanifest","./studio/apron-light.webp","./studio/hangar-dusk.glb","./studio/tarmac-normal.png","./studio/tarmac-orm.png","./studio/tarmac.webp","./surface/cloud-density.png","./surface/combustion.webp","./surface/dusk-panorama.webp","./surface/pressure.webp","./surface/probe-airbase-atlas.hdr","./surface/probe-day.hdr","./surface/probe-dusk.hdr","./surface/probe-night.hdr","./surface/probe-storm.hdr","./surface/rock-grain.png","./surface/soot.webp","./surface/spark.webp","./surface/terrain-normal.png","./surface/water.png","./surface/wave-field.png","./ui-v7/activity.webp","./ui-v7/crest.webp","./ui-v7/frame-command.webp","./ui-v7/frame-instrument.webp","./ui-v7/frame-steel.webp","./ui-v7/hangar.webp","./ui-v7/missions.webp","./ui-v7/season.webp","./ui-v7/settings.webp","./ui-v7/tools.webp","./ui-v7/tree.webp","./world/frost-surface.png","./world/frost.height","./world/storm-surface.png","./world/storm.height","./world/sundown-surface.png","./world/sundown.height"];
self.addEventListener('install', event => event.waitUntil(
  caches.open(key).then(cache => cache.addAll(['./', ...release])).then(() => self.skipWaiting())
));
self.addEventListener('activate', event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(old => old.indexOf('px-sky-remake-') === 0 && old !== key).map(old => caches.delete(old))))
    .then(() => self.clients.claim())
));
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.open(key).then(cache => cache.match('./'))));
    return;
  }
  event.respondWith(caches.open(key).then(async cache => {
    const match = await cache.match(request);
    if (match) return match;
    return fetch(request);
  }));
});
