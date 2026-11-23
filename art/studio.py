"""Bakes studio surface channels and periodic layered weather fields."""
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np

root=Path(__file__).resolve().parents[1]/'public'
out=root/'studio'
out.mkdir(parents=True,exist_ok=True)
surface=root/'surface'
rng=np.random.default_rng(86107)

def fractal(n,scales):
    value=np.zeros((n,n),dtype=np.float32)
    for k,w in scales:
        patch=rng.uniform(0,255,(k+2,k+2)).astype('uint8')
        patch[-1]=patch[1];patch[0]=patch[-2];patch[:,-1]=patch[:,1];patch[:,0]=patch[:,-2]
        plane=Image.fromarray(patch).resize((n+2*n//k,n+2*n//k),Image.Resampling.BICUBIC)
        value+=np.asarray(plane.crop((n//k,n//k,n+n//k,n+n//k)),dtype=np.float32)*w/255
    return value

def save(name,array,directory=out):
    Image.fromarray(np.clip(array,0,255).astype('uint8')).save(directory/name)

n=1024
x,z=np.meshgrid(np.linspace(-1,1,n),np.linspace(-1,1,n))
roughness=fractal(n,[(6,.4),(17,.30),(43,.14),(89,.10),(243,.06)])
chips=fractal(n,[(15,.21),(39,.42),(96,.22),(249,.15)])
patch=np.clip((roughness-.56)*7.2,0,1)
tan=np.sin((x*.37+z)*3.4)*.025
wet=np.clip(patch*.95+.13*np.clip(np.cos(z*5+x*7),0,1)+.39*np.exp(-((x+.24+z*.13)*5.2)**2-((z-.13)*2.4)**2),0,1)
joints=np.maximum(np.exp(-((np.mod((x+.25)*7.0+.5,1.)-.5)*132)**2),np.exp(-((np.mod((z-.10)*10.1+.5,1.)-.5)*132)**2))
skids=(np.exp(-((x-.13+z*.105)*33)**2)+np.exp(-((x+.115+z*.105)*35)**2))*.44*np.exp(-((z-.033)*2.8)**2)
skid=skids*(.57+.43*roughness)
oil=np.exp(-((x-.32)*6.4)**2-((z+.16)*11.7)**2)*np.clip((roughness-.415)*2.5,0,1)
noise=rng.normal(0,.011,(n,n))
base=.49+(roughness-.5)*.24+(chips-.5)*.15+noise+tan-joints*.21-skid*.19-oil*.17-wet*.081
rgb=np.stack((base*.96,base,base*1.07),-1)
color=Image.fromarray(np.clip(rgb*255,0,255).astype('uint8'))
ink=Image.new('RGBA',(n,n))
g=ImageDraw.Draw(ink)
g.ellipse((322,366,712,674),outline=(229,174,85,175),width=5)
g.arc((337,380,697,661),188,353,fill=(217,186,118,120),width=2)
for xp in (252,772):
    for zz in range(48,999,61):
        g.rounded_rectangle((xp,zz,xp+4,zz+35),radius=1,fill=(221,191,123,190))
for yy in (173,866):
    g.line((326,yy,698,yy),fill=(227,207,161,118),width=2)
    for xp in range(318,705,19):
        g.line((xp,yy,xp+11,yy+7),fill=(227,180,91,137),width=2)
g.line((500,260,522,260),fill=(231,212,166,150),width=2)
g.line((511,250,511,270),fill=(231,212,166,150),width=2)
color.paste(ink,mask=ink.getchannel('A'))
color.save(out/'tarmac.webp',quality=91)
relief=(chips-.5)*.085+(roughness-.5)*.09-joints*.081+noise*.6
nx=(np.roll(relief,1,1)-np.roll(relief,-1,1))*6.0
nz=(np.roll(relief,1,0)-np.roll(relief,-1,0))*6.0
normal=np.stack((.5+nx,.5+nz,np.sqrt(np.maximum(.1,1-nx*nx-nz*nz))),-1)
orm=np.stack((.95-joints*.20-oil*.14,.82-wet*.60+chips*.10,.049+wet*.21),-1)
for name,channel in [('tarmac-normal.png',normal),('tarmac-orm.png',orm)]:
    Image.fromarray(np.clip(channel*255,0,255).astype('uint8')).resize((512,512),Image.Resampling.LANCZOS).save(out/name)

n=384
main=fractal(n,[(4,.42),(8,.27),(18,.16),(36,.092),(82,.058)])
strata=fractal(n,[(5,.44),(12,.26),(23,.18),(54,.12)])
ocean=fractal(n,[(6,.37),(13,.27),(27,.19),(62,.12),(110,.05)])
save('cloud-density.png',np.stack((main,strata,ocean),-1)*255,surface)
detail=fractal(n,[(11,.30),(31,.32),(57,.22),(127,.16)])
save('rock-grain.png',np.stack((detail*.27+.70,detail*.28+.68,detail*.29+.64),-1)*255,surface)
dx=(np.roll(detail,1,1)-np.roll(detail,-1,1))*.44
dz=(np.roll(detail,1,0)-np.roll(detail,-1,0))*.44
normal=np.stack((.5+dx,.5+dz,np.sqrt(np.maximum(.1,1-4*(dx*dx+dz*dz)))),axis=-1)
save('terrain-normal.png',normal*255,surface)
def wrapped_height(n):
    axis=np.arange(n)/n
    x,z=np.meshgrid(axis,axis)
    waves=np.zeros(x.shape)
    for i in range(123):
        kx=int(rng.integers(-34,35))
        kz=int(rng.integers(1,25))
        f=np.hypot(kx,kz)
        if f<3: continue
        phase=rng.uniform(0,2*np.pi)
        direction=np.exp(-abs(kx+kz*.45)/(10+kz*.23))
        gain=direction/(f**1.37)
        waves+=gain*np.sin((kx*x+kz*z)*2*np.pi+phase)
    slope_x=np.roll(waves,-1,1)-np.roll(waves,1,1)
    slope_z=np.roll(waves,-1,0)-np.roll(waves,1,0)
    return np.stack((.5+slope_x*1.89,.5+slope_z*1.89,.5+waves*.38),-1)

save('wave-field.png',wrapped_height(256)*255,surface)
