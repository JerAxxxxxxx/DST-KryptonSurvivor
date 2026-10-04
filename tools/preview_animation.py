"""Preview compiled custom sprites against the installed game's motion data."""
from pathlib import Path
import zipfile
import math
from PIL import Image, ImageDraw
from klei_assets import read_build, read_anim, read_tex, crop_symbol
from paths import ROOT, PREVIEWS, game_anim_dir

root=ROOT
game=game_anim_dir()
PREVIEWS.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(root/'mod/anim/krypton_survivor.zip') as z:
    build=read_build(z.read('build.bin')); atlas=read_tex(z.read('atlas-0.tex'))
with zipfile.ZipFile(game/'player_basic.zip') as z:
    animations,names=read_anim(z.read('anim.bin'))
for archive in ['player_attacks.zip','player_idles.zip']:
    if (game/archive).exists():
        with zipfile.ZipFile(game/archive) as z:
            extra,extra_names=read_anim(z.read('anim.bin'))
            animations.extend(extra); names.update(extra_names)
sprites={}
for s in build['symbols']:
    for row in s['frames']:
        sprites[(s['hash'],row[0])] = (crop_symbol(build,atlas,s,row[0]),row)
with zipfile.ZipFile(root/'mod/anim/krypton_staff_build.zip') as z:
    staffbuild=read_build(z.read('build.bin')); staffatlas=read_tex(z.read('atlas-0.tex'))
staffsymbol=next(s for s in staffbuild['symbols'] if s['name']=='swap_cane')
staffsprite=(crop_symbol(staffbuild,staffatlas,staffsymbol,0),staffsymbol['frames'][0])

def frame_image(anim,idx,equipped=False):
    canvas=Image.new('RGBA',(640,640),(224,218,199,255))
    for e in sorted(anim['frames'][idx]['elements'],key=lambda e:e[9],reverse=True):
        name,layer=names.get(e[0]),names.get(e[2])
        if layer==('ARM_normal' if equipped else 'ARM_carry') or name in ['headbase_hat','hair_hat']:continue
        sprite=sprites.get((e[0],e[1]))
        if equipped and name=='swap_object':sprite=staffsprite
        if sprite is None:continue
        im,row=sprite
        a,b,c,d,tx,ty,_=e[3:]; det=a*d-b*c
        if abs(det)<.001:continue
        # World x=a*x+c*y+tx; y=b*x+d*y+ty, translated onto preview.
        tx+=320;ty+=540
        left,top=row[2]-row[4]/2,row[3]-row[5]/2
        inv=(d/det,-c/det,(-d*tx+c*ty)/det-left,-b/det,a/det,(b*tx-a*ty)/det-top)
        warped=im.transform(canvas.size,Image.Transform.AFFINE,inv,Image.Resampling.BICUBIC)
        canvas.alpha_composite(warped)
    return canvas
sheet=Image.new('RGBA',(1920,640))
for i,facing in enumerate([8,5,2]):
    anim=next(a for a in animations if a['name']=='run_loop' and a['facing']==facing)
    sheet.alpha_composite(frame_image(anim,0),(i*640,0))
sheet.convert('RGB').save(PREVIEWS/'run-unarmed.png')
held=Image.new('RGBA',(1920,640))
for i,facing in enumerate([8,5,2]):
    anim=next(a for a in animations if a['name']=='run_loop' and a['facing']==facing)
    held.alpha_composite(frame_image(anim,0,True),(i*640,0))
held.convert('RGB').save(PREVIEWS/'run-equipped.png')
poses=Image.new('RGBA',(1920,640))
attack=next((a for a in animations if a['name']=='atk' and a['facing']==5),None)
if attack:
    for i,idx in enumerate([0,len(attack['frames'])//2,len(attack['frames'])-1]):
        poses.alpha_composite(frame_image(attack,idx,True),(i*640,0))
    poses.convert('RGB').save(PREVIEWS/'attack.png')
idle=Image.new('RGBA',(1920,640))
for i,facing in enumerate([8,5,2]):
    anim=next((a for a in animations if a['name']=='idle_loop' and a['facing']==facing),None)
    if anim:idle.alpha_composite(frame_image(anim,0,True),(i*640,0))
if idle.getbbox():idle.convert('RGB').save(PREVIEWS/'idle.png')
for action in ['idle_loop','run_loop','atk']:
    for facing,label in [(8,'front'),(5,'side'),(2,'back')]:
        animation=next(a for a in animations if a['name']==action and a['facing']==facing)
        frames=[frame_image(animation,i,True).convert('RGB') for i in range(len(animation['frames']))]
        frames[0].save(PREVIEWS/f'{action}-{label}.gif',save_all=True,append_images=frames[1:],
                       duration=round(1000/animation['rate']),loop=0)
        if action=='atk':
            contact=Image.new('RGB',(1280,math.ceil(len(frames)/4)*320))
            for i,frame in enumerate(frames):contact.paste(frame.resize((320,320)),((i%4)*320,(i//4)*320))
            contact.save(PREVIEWS/f'attack-all-{label}.png')
with zipfile.ZipFile(game/'cane.zip') as z:
    ground_anims,ground_names=read_anim(z.read('anim.bin'))
ground=Image.new('RGBA',(480,480),(224,218,199,255))
for e in ground_anims[0]['frames'][0]['elements']:
    symbol=next(s for s in staffbuild['symbols'] if s['hash']==e[0])
    row=symbol['frames'][0]; im=crop_symbol(staffbuild,staffatlas,symbol,row[0])
    a,b,c,d,tx,ty,_=e[3:];det=a*d-b*c;tx+=240;ty+=430
    left,top=row[2]-row[4]/2,row[3]-row[5]/2
    inv=(d/det,-c/det,(-d*tx+c*ty)/det-left,-b/det,a/det,(b*tx-a*ty)/det-top)
    ground.alpha_composite(im.transform(ground.size,Image.Transform.AFFINE,inv,Image.Resampling.BICUBIC))
ground.convert('RGB').save(PREVIEWS/'ground-axe.png')
print('Rendered front, side and back from compiled game assets.')
