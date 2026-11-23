"""Compare the supplied artwork, real gameplay captures, and fixed gameplay views."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat

parser=argparse.ArgumentParser()
parser.add_argument('reference',type=Path)
parser.add_argument('actual',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--before',type=Path)
parser.add_argument('--landscape-only',action='store_true')
a=parser.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
size=(1000,562)
lobby={'profile':(0,0,.45,.13),'navigation':(0,.88,1,1),'modes':(.75,.28,1,.83),'stage':(.22,.17,.73,.82)}
fixture={
    '01':('upgrade',{'airframe':(.18,.16,.68,.90),'parts':(.72,.11,1,.92)}),
    '02':('home-1280',lobby),
    '04':('season',{'main-art':(.15,.10,.82,.64),'reward-track':(0,.65,1,.93)}),
    '11-battle':('b-dogfight',{'reticle':(.32,.29,.68,.63),'flight-data':(.01,.09,.30,.49),'radar':(.81,.00,1,.37),'weapons':(.73,.40,1,1)}),
    '06':('quests',{'title':(0,0,1,.19),'rewards':(0,.34,1,.91)}),
    '07':('result',{'outcome':(.20,.02,.80,.39),'detailed-stats':(.08,.35,.92,.90)}),
    '08':('home-393',{'profile':(0,0,1,.12),'navigation':(0,.81,1,1)}),
    '09':('hangar',{'list':(0,.19,.20,.87),'airframe':(.20,.15,.73,.91),'details':(.74,.16,1,.92)}),
    '10':('sortieprep',{'preparation':(0,.05,1,.88)}),
    '11-research':('tree',{'branch-graph':(0,.10,1,.94)}),
    '12-tactical':('tactical',{'radar-contacts':(0,.08,1,.96)}),
}
def resize_pair(left,right):
    if left.height>left.width and right.height>right.width:
        return left.resize((450,730),Image.Resampling.LANCZOS),right.resize((450,730),Image.Resampling.LANCZOS)
    return left.resize(size,Image.Resampling.LANCZOS),right.resize(size,Image.Resampling.LANCZOS)

def compare(left,right,regions,name):
    left,right=resize_pair(left.convert('RGB'),right.convert('RGB'))
    difference=ImageChops.difference(left,right)
    blend=Image.blend(left,right,.50)
    border=ImageDraw.Draw(blend)
    report={}
    for label,f in regions.items():
        box=tuple(round(c*(left.width if k%2==0 else left.height)) for k,c in enumerate(f))
        border.rectangle(box,outline='#5ddcf3',width=2)
        border.text((box[0]+4,box[1]+3),label,fill='#5ddcf3')
        report[label]={'region':f,'meanAbsoluteRGB':round(sum(ImageStat.Stat(difference.crop(box)).mean)/3,2)}
    paired=Image.new('RGB',(left.width*2,left.height*2))
    for im,position in [(left,(0,0)),(right,(left.width,0)),(blend,(0,left.height)),(difference,(left.width,left.height))]:
        paired.paste(im,position)
    paired.save(a.output/(name+'.webp'),quality=89)
    return report

source_crops={
    '11-battle':(650/1280,0,1,296/720),
    '11-research':(997/1280,299/720,1,466/720),
    '12-tactical':(499/650,294/365,1,1),
}
reports={}
for ref,(view,regions) in fixture.items():
    if ref=='08' and a.landscape_only:continue
    match=list(a.reference.glob(ref.split('-')[0]+'*.webp'))
    actual=a.actual/(view+'.png')
    if match and actual.exists():
        source=Image.open(match[0])
        if ref in source_crops:
            source=source.crop(tuple(round(v*(source.width if k%2==0 else source.height)) for k,v in enumerate(source_crops[ref])))
        reports[ref]={'view':view,'source':match[0].name,'regions':compare(source,Image.open(actual),regions,'reference-'+ref)}
    else:
        reports[ref]={'view':view,'status':'missing capture or reference'}
if a.before:
    for name in ['cloud-deck','snow-range','island-chain','sea-level','sunset','storm-coast']:
        left=a.before/(name+'.png')
        right=a.actual/(name+'.png')
        if left.exists() and right.exists():
            reports[name]=compare(Image.open(left),Image.open(right),{'world':(0,0,1,1)},'world-'+name)
    for name in ['home-1280','hangar','upgrade','weapons','tree','quests','missions','training',
                 'freeprep','inventory','records','base','settings','activity','season','sortieprep',
                 'b-dogfight','b-cockpit','tactical','result']:
        left=a.before/(name+'.png')
        right=a.actual/(name+'.png')
        if left.exists() and right.exists():
            reports['game-'+name]=compare(Image.open(left),Image.open(right),
                {'header':(0,0,1,.17),'surfaces':(0,.17,1,.90),'controls':(0,.90,1,1)},'game-'+name)
(a.output/'comparison.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
