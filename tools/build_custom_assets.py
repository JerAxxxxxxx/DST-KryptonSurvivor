"""Compile approved raster sprite parts into DST builds and texture atlases."""
from pathlib import Path
from PIL import Image
import zipfile
import copy
import json
from klei_assets import read_build, write_build, write_tex, read_tex
from paths import ROOT, ART, MOD, PREVIEWS, game_anim_dir

GAME = game_anim_dir()
PREVIEWS.mkdir(parents=True,exist_ok=True)
geometry=json.loads((ART/'geometry.json').read_text(encoding='utf8'))
spec=json.loads((ROOT/'assets/slices.json').read_text(encoding='utf8'))

# Eye locations share the exact head-pixel transform used by the sprite build.
# Only numeric placements are generated; no artwork is drawn or copied here.
vision=spec['heatvision']
eye_rows={}
for direction in ['front','side','back']:
    config=vision['eyes'][direction]
    source_direction=config.get('inherit',direction)
    head=spec['placement']['head'][source_direction]
    points=vision['eyes'][source_direction]['source_points']
    offsets=[[(point[i]-head['anchor'][i])*head['scale']+head['local_anchor'][i] for i in range(2)] for point in points]
    eye_rows[direction]=offsets
visual_lines=['-- Generated from assets/slices.json by tools/build_custom_assets.py.','return {']
for direction in ['front','side','back']:
    points=', '.join('{ %.6f, %.6f }' % tuple(point) for point in eye_rows[direction])
    glow='true' if vision['eyes'][direction]['glow'] else 'false'
    visual_lines.append('    %s = { eyes = { %s }, glow = %s },' % (direction,points,glow))
visual_lines.append('    beam = {')
for key,value in vision['beam'].items():visual_lines.append('        %s = %.6f,' % (key,value))
visual_lines.extend(['    },','}'])
(MOD/'scripts/krypton_heatvision_visual_data.lua').write_text('\n'.join(visual_lines)+'\n',encoding='utf8')


# Mouth anchors use the same author-pixel/head-symbol mapping as the eye data.
def write_frostbreath_data():
    frost=spec['frostbreath']
    lines=['-- Generated from assets/slices.json by tools/build_custom_assets.py.','return {']
    for direction in ['front','side','back']:
        layout=frost['mouth_points'][direction]
        source=layout.get('inherit',direction)
        head=spec['placement']['head'][source]
        point=frost['mouth_points'][source]['source_point']
        offset=[(point[i]-head['anchor'][i])*head['scale']+head['local_anchor'][i] for i in range(2)]
        lines.append('    %s = { mouth = { %.6f, %.6f } },' % (direction,*offset))
    lines.extend(['    pixels_per_unit = %.6f,' % frost['pixels_per_unit'],'}'])
    (MOD/'scripts/krypton_frostbreath_visual_data.lua').write_text('\n'.join(lines)+'\n',encoding='utf8')

write_frostbreath_data()

def image(name):
    return Image.open(ART / (name + '.png')).convert('RGBA')

def atlas(relative, art, size, element=None):
    path = MOD / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new('RGBA', size)
    art.thumbnail(size, Image.Resampling.LANCZOS)
    canvas.alpha_composite(art, ((size[0]-art.width)//2, (size[1]-art.height)//2))
    path.with_suffix('.tex').write_bytes(write_tex(canvas))
    element = element or path.stem + '.tex'
    path.with_suffix('.xml').write_text(f'<Atlas><Texture filename="{path.stem}.tex"/><Elements><Element name="{element}" u1="0" u2="1" v1="0" v2="1"/></Elements></Atlas>\n')
    assert read_tex(path.with_suffix('.tex').read_bytes()).size == size

with zipfile.ZipFile(GAME / 'wilson.zip') as z:
    build = read_build(z.read('build.bin'))
symbols = copy.deepcopy(build['symbols'])
sprites = {}
for s in symbols:
    for row in s['frames']:
        name, frame = s['name'], row[0]
        if f'{name}-{frame}' in geometry:
            row[2:6]=geometry[f'{name}-{frame}']
        if name=='arm_upper':
            row[2:6]=[-1,20,28,54]
        if name=='hand':
            row[2:6]=[0,12,34,32] if frame in [1,4,12,14] else [0,12,28,30]
        if name=='torso_pelvis':
            waist=next(layout for layout in spec['placement']['pelvis'].values() if frame in layout['frames'])
            row[2],row[4]=waist['center_x'],waist['width']
        source = image(f'{name}-{frame}')
        sprites[(name, frame)] = source.resize((max(1,round(row[4])),max(1,round(row[5]))),Image.Resampling.LANCZOS) if source.getbbox() else Image.new('RGBA',(2,2))
preview = write_build('krypton_survivor', symbols, sprites, MOD/'anim/krypton_survivor.zip')
preview.save(PREVIEWS/'character-atlas.png')
with zipfile.ZipFile(GAME/'swap_cane.zip') as z:
    build = read_build(z.read('build.bin'))
sprites = {}
for s in build['symbols']:
    for row in s['frames']:
        if s['name'] == 'grass':
            im = Image.new('RGBA',(8,8))
        else:
            row[2],row[3],row[4],row[5] = (0,-70,180,300) if s['name']=='swap_cane' else (0,-125,180,300)
            im = image('staff').resize((180,300),Image.Resampling.LANCZOS)
        sprites[(s['name'],row[0])] = im
write_build('krypton_staff_build',build['symbols'],sprites,MOD/'anim/krypton_staff_build.zip',1024)
atlas('bigportraits/krypton_survivor',image('portrait'),(512,1024))
for relative in ['images/avatars/avatar_krypton_survivor','images/avatars/avatar_ghost_krypton_survivor','images/avatars/self_inspect_krypton_survivor','images/saveslot_portraits/krypton_survivor']:
    atlas(relative,image('avatar'),(128,128))
atlas('images/selectscreen_portraits/krypton_survivor',image('portrait'),(256,512))
silho=image('portrait'); silho.paste((20,22,25),mask=silho.getchannel('A'))
atlas('images/selectscreen_portraits/krypton_survivor_silho',silho,(256,512))
for name in ['names','names_gold']:
    atlas('images/'+name+'_krypton_survivor',image(name),(512,128),'krypton_survivor.tex')
atlas('images/inventoryimages/krypton_staff',image('staff'),(128,128))
for relative, expected, count in [('anim/krypton_survivor.zip','krypton_survivor',132),('anim/krypton_staff_build.zip','krypton_staff_build',3)]:
    with zipfile.ZipFile(MOD/relative) as z:
        b=read_build(z.read('build.bin'))
        assert b['name']==expected and sum(len(s['frames']) for s in b['symbols'])==count
        assert read_tex(z.read('atlas-0.tex')).getbbox()
print('Compiled and checked 132 character parts, staff build and 10 UI atlases.')
