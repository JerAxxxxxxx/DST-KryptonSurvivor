"""Extract user-approved pixels. Selection, rotation and scaling only; no painting."""
from pathlib import Path
import json, hashlib, math
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/art'
OUT.mkdir(parents=True, exist_ok=True)
SPEC = json.loads((ROOT/'assets/slices.json').read_text(encoding='utf8'))
manifest = {'sources': {}, 'parts': {}}

def matte(path, tolerance):
    rgb = np.asarray(Image.open(path).convert('RGB'))
    paper = np.median(np.concatenate([rgb[0],rgb[-1],rgb[:,0],rgb[:,-1]]), axis=0)
    difference = np.max(np.abs(rgb.astype(float)-paper), axis=2)
    _, labels = cv2.connectedComponents((difference < tolerance).astype(np.uint8), connectivity=4)
    exterior = np.unique(np.concatenate([labels[0],labels[-1],labels[:,0],labels[:,-1]]))
    alpha = np.where(np.isin(labels, exterior[exterior != 0]), 0, 255).astype(np.uint8)
    _, components, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
    keep = np.flatnonzero(stats[:,cv2.CC_STAT_AREA] >= 15)
    alpha[~np.isin(components,keep[keep != 0])] = 0
    distance = cv2.distanceTransform((alpha > 0).astype(np.uint8),cv2.DIST_L2,3)
    fringe = (alpha > 0) & (distance < 1.5)
    alpha[fringe] = np.minimum(alpha[fringe],np.clip(difference[fringe]/80*255,0,255)).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb,alpha]))

sources = {}
for name, item in SPEC['sources'].items():
    path = ROOT/item['path']
    sources[name] = matte(path,item['tolerance'])
    sources[name].save(OUT/f'{name}-transparent.png')
    manifest['sources'][name] = {**item, 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                                 'size': sources[name].size}

def selection(name):
    item = SPEC['selections'][name]
    source = sources[item['source']]
    sx,sy = source.width/1024,source.height/341
    points = [(round(x*sx),round(y*sy)) for x,y in item['polygon']]
    mask = Image.new('L',source.size)
    ImageDraw.Draw(mask).polygon(points,fill=255)  # alpha selection, never RGB art
    alpha = np.minimum(np.asarray(source.getchannel('A')),np.asarray(mask))
    if name in ['upper-arm','forearm','leg','bent-leg','pelvis','pelvis-side','empty-hand']:
        # Cloth behind a limb does not belong to that moving limb. Boots are
        # supplied by the separate foot symbol, not duplicated in the shin.
        rgb=np.asarray(source).astype(float)
        red_cloth=(rgb[:,:,0]-rgb[:,:,1]>25) & (rgb[:,:,0]-rgb[:,:,2]>25) & (rgb[:,:,1]<100)
        alpha[red_cloth] = 0
    if item.get('largest_component',True):
        _, labels, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8),8)
        assert len(stats)>1,name
        alpha[labels != 1+np.argmax(stats[1:,cv2.CC_STAT_AREA])] = 0
    result = source.copy();result.putalpha(Image.fromarray(alpha))
    box = result.getbbox();assert box,name
    manifest['parts'][name] = {**item,'crop':box}
    return result.crop(box), (box[0]/sx,box[1]/sy), sx,sy

def local_part(name, anchor, local_anchor, scale):
    """Keep source placement relative to a joint, without centering padding."""
    im,origin,sx,sy = selection(name)
    w,h = round(im.width/sx*scale),round(im.height/sy*scale)
    im = im.resize((w,h),Image.Resampling.LANCZOS)
    left = local_anchor[0]+(origin[0]-anchor[0])*scale
    top = local_anchor[1]+(origin[1]-anchor[1])*scale
    return im,[left+w/2,top+h/2,w,h]

def fitted(name, size, rotation=0, flip=False):
    im = selection(name)[0]
    if rotation:im=im.rotate(rotation,resample=Image.Resampling.BICUBIC,expand=True)
    if flip:im=im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return im.crop(im.getbbox()).resize(size,Image.Resampling.LANCZOS)

geometry = {}
def save(name, frame, im, bounds=None):
    key=f'{name}-{frame}';im.save(OUT/f'{key}.png')
    if bounds:geometry[key]=bounds

heads=[]
for direction in ['front','side','back']:
    cfg=SPEC['placement']['head'][direction]
    heads.append(local_part('head-'+direction,cfg['anchor'],cfg['local_anchor'],cfg['scale']))
for frame in range(5):
    im,bounds=heads[1 if frame==1 else 2 if frame==2 else 0]
    for name in ['headbase','headbase_hat']:save(name,frame,im,bounds)
for name,count in [('hair',4),('hair_hat',4),('face',33),('cheeks',2),('arm_upper_skin',3)]:
    for frame in range(count):save(name,frame,Image.new('RGBA',(2,2)))

torsos=[]
for direction in ['front','side','back']:
    cfg=SPEC['placement']['body'][direction]
    im,bounds=local_part('torso-'+direction,cfg['anchor'],cfg['local_anchor'],cfg['scale'])
    # Fill the left cape's occluded region with original right-cape pixels,
    # mirrored, instead of painting fabric where the source arm used to be.
    if direction=='front':
        cape,cb=local_part('cape-front-right',cfg['anchor'],cfg['local_anchor'],cfg['scale'])
        cape=cape.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        cl=-cb[0]-cb[2]/2;ct=cb[1]-cb[3]/2
        left=min(bounds[0]-bounds[2]/2,cl);top=min(bounds[1]-bounds[3]/2,ct)
        right=max(bounds[0]+bounds[2]/2,cl+cape.width)
        bottom=max(bounds[1]+bounds[3]/2,ct+cape.height)
        combined=Image.new('RGBA',(math.ceil(right-left),math.ceil(bottom-top)))
        combined.alpha_composite(cape,(round(cl-left),round(ct-top)))
        combined.alpha_composite(im,(round(bounds[0]-bounds[2]/2-left),round(bounds[1]-bounds[3]/2-top)))
        im=combined;bounds=[left+im.width/2,top+im.height/2,im.width,im.height]
    torsos.append((im,bounds))
for frame in range(11):
    direction=1 if frame in [3,4,5,9] else 2 if frame in [6,7,8,10] else 0
    save('torso',frame,*torsos[direction])

# Limb sprites respect the base game's joint ranges and bent-knee shapes.
for frame in range(7):
    save('arm_upper',frame,fitted('upper-arm',(32,54),rotation=10))
    if frame in [2,6]:
        lower=fitted('forearm',(18,59),rotation=8).transpose(Image.Transpose.ROTATE_270)
    else:lower=fitted('forearm',(18,59 if frame in [1,4] else 47),rotation=8)
    save('arm_lower',frame,lower)
for frame in range(20):
    grip=frame in [1,4,12,14]
    im=fitted('gripping-hand' if grip else 'empty-hand',(39,31) if grip else (31,31))
    if grip:im=im.transpose(Image.Transpose.ROTATE_90)
    save('hand',frame,im)
for frame in range(11):
    if frame in [4,6,7,8]:
        im=fitted('bent-leg',(35,44))
        if frame==4:im=im.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    else:im=fitted('leg',(18,53))
    save('leg',frame,im)
for frame in range(8):
    im=fitted('foot',(35,28),flip=frame in [1,2,5,7])
    if frame==4:im=im.rotate(-45,expand=True,resample=Image.Resampling.BICUBIC)
    save('foot',frame,im)
# Extract the front/side waist separately. Its width is supplied by the suit,
# while the compiler keeps the native vertical overlap that connects moving legs.
for placement in SPEC['placement']['pelvis'].values():
    im=selection(placement['selection'])[0]
    for frame in placement['frames']:save('torso_pelvis',frame,im)

portrait=selection('portrait')[0]
portrait.save(OUT/'portrait.png');save('SWAP_ICON',0,portrait)
avatar=heads[0][0].copy();avatar.thumbnail((280,280),Image.Resampling.LANCZOS)
canvas=Image.new('RGBA',(300,300))
canvas.alpha_composite(avatar,((300-avatar.width)//2,(300-avatar.height)//2))
canvas.save(OUT/'avatar.png')
weapon=sources['weapon'];weapon.crop(weapon.getbbox()).save(OUT/'staff.png')
for name in ['names','names_gold']:Image.open(ROOT/f'assets/ui/{name}.png').save(OUT/f'{name}.png')
(OUT/'geometry.json').write_text(json.dumps(geometry,indent=2),encoding='utf8')
(ROOT/'build/extraction-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('Extracted supplied pixels; removed baked limbs from torsos and preserved joint placement.')
