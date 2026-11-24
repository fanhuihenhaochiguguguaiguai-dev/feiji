"""Extract individual plates and campaign art from the user-supplied sources."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'qa/reference'
OUT=ROOT/'public/ui-v7'
OUT.mkdir(parents=True,exist_ok=True)
manifest={}
def extract(file, basis, box, name, use, chamfer=False):
    ref=next(SOURCE.glob(file+'*.webp'))
    image=Image.open(ref).convert('RGBA')
    sx,sy=image.width/basis[0],image.height/basis[1]
    crop=tuple(round(a*(sx if i%2==0 else sy)) for i,a in enumerate(box))
    art=image.crop(crop)
    if chamfer:
        width,height=art.size
        alpha=Image.new('L',art.size)
        x,y=round(width*.12),round(height*.24)
        corners=[(x,0),(width-x,0),(width,y),(width,height-y),(width-x,height),(x,height),(0,height-y),(0,y)]
        if chamfer=='frame':
            corners=[(round(width*.19),0),(width-3,0),(width,4),(width,height),(0,height),(0,round(height*.47))]
        ImageDraw.Draw(alpha).polygon(corners,fill=255)
        art.putalpha(alpha)
    art.save(OUT/(name+'.webp'),quality=94,method=6,exact=True)
    manifest[name]={'source':ref.name,'sourceSize':list(image.size),'box':crop,
                    'size':list(art.size),'alpha':bool(chamfer),'use':use,'format':'WebP',
                    'states':'CSS focus, hover, pressed, selected and disabled' if chamfer else 'static illustration'}
for x,name in zip([63,136,283,849],
                  ['hangar','tools','missions','settings']):
    extract('03',(900,507),(x-28,82,x+28,126),name,'独立功能图案',True)
extract('03',(900,507),(34,171,164,225),'crest','指挥中心翼徽',True)
extract('03',(1672,941),(732,328,898,391),'frame-command','可伸缩香槟金指挥框','frame')
extract('03',(1672,941),(918,328,1069,391),'frame-instrument','可伸缩战术仪表框','frame')
extract('03',(1672,941),(734,398,898,458),'frame-steel','可伸缩冷银机务框','frame')
(OUT/'sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
