"""Paint the fleet cards from the same authored, articulated mesh as the game."""
from pathlib import Path
from sys import path,argv
from mathutils import Vector
import bpy

HERE=Path(__file__).resolve().parent
path.insert(0,str(HERE))
from fleet import configure,exterior,REGISTRY

folder=HERE.parent/"public"/"cards"
def aim(o,at):
    o.rotation_euler=(Vector(at)-o.location).to_track_quat("-Z","Y").to_euler()

selected=set(argv[argv.index("--")+1:]) if "--" in argv else set()
for d in REGISTRY:
    if selected and d['id'] not in selected:continue
    configure(d)
    exterior(d,2)
    scene=bpy.context.scene;scene.frame_set(1)
    scene.render.engine="CYCLES"
    scene.cycles.samples=16;scene.cycles.use_denoising=False
    scene.render.resolution_x=336;scene.render.resolution_y=204
    scene.render.resolution_percentage=100;scene.render.film_transparent=True
    scene.render.image_settings.file_format="PNG";scene.render.image_settings.color_mode="RGBA"
    scene.view_settings.view_transform="AgX"
    scene.world=bpy.data.worlds.new("Fleet cyclorama");scene.world.color=(.21,.24,.30)
    def light(name,loc,power,color):
        data=bpy.data.lights.new(name,"AREA");data.energy=power;data.shape="DISK";data.size=d['length']*.66;data.color=color
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;aim(ob,(0,0,0))
    scale=max(d['span'],d['length'])
    light("Key",(scale*.84,-scale*.53,scale*.75),scale**2*54,(1,.86,.65))
    light("Fill",(-scale*.65,scale*.43,scale*.77),scale**2*34,(.67,.81,1))
    cam=bpy.data.objects.new("Fleet format",bpy.data.cameras.new("Fleet optics"))
    scene.collection.objects.link(cam);scene.camera=cam
    cam.location=(scale*1.08,-scale*.61,scale*.86);aim(cam,(0,0,0))
    cam.data.type="ORTHO";cam.data.ortho_scale=scale*1.28
    scene.render.filepath=str(folder/(d['id']+'.render.png'))
    bpy.ops.render.render(write_still=True)
    print("Rendered fleet icon",d["id"],flush=True)
