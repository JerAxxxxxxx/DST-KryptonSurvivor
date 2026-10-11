"""Extract supplied eating heads and package only an original BILD/KTEX build.

Source pixels are masked, cropped and scaled; no facial artwork is drawn.
Installed native eating animation data is read only for ignored local previews.
It is never copied into the distributable archive.
"""
import hashlib
import json
import zipfile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from klei_assets import crop_symbol, hash_name, read_anim, read_build, read_tex, write_build, validate_build_symbols
from paths import ROOT, MOD, PREVIEWS, game_anim_dir

SPEC = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))
CONFIG = SPEC['eating']
ART = ROOT / 'build/art/eating'
ART.mkdir(parents=True, exist_ok=True)
PREVIEWS.mkdir(parents=True, exist_ok=True)


def matte(path, tolerance):
    """Use the existing edge-connected JPG-paper/checker alpha extraction."""
    rgb = np.asarray(Image.open(path).convert('RGB'))
    paper = np.median(np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]), axis=0)
    difference = np.max(np.abs(rgb.astype(float) - paper), axis=2)
    _, labels = cv2.connectedComponents((difference < tolerance).astype(np.uint8), connectivity=4)
    exterior = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    alpha = np.where(np.isin(labels, exterior[exterior != 0]), 0, 255).astype(np.uint8)
    _, components, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
    keep = np.flatnonzero(stats[:, cv2.CC_STAT_AREA] >= 15)
    alpha[~np.isin(components, keep[keep != 0])] = 0
    distance = cv2.distanceTransform((alpha > 0).astype(np.uint8), cv2.DIST_L2, 3)
    fringe = (alpha > 0) & (distance < 1.5)
    alpha[fringe] = np.minimum(alpha[fringe], np.clip(difference[fringe] / 80 * 255, 0, 255)).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]))


item = SPEC['sources']['eating']
source_path = ROOT / item['path']
source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
source = matte(source_path, item['tolerance'])
source.save(ART / 'source-transparent.png')
sx, sy = source.width / 1024, source.height / 341
manifest = {'sources': {'eating': {**item, 'sha256': source_hash, 'size': list(source.size)}}, 'parts': {}}
symbols, sprites = [], {}

for pose in CONFIG['poses']:
    name = pose['selection']
    selection = SPEC['selections'][name]
    assert selection['source'] == 'eating'
    mask = Image.new('L', source.size)
    ImageDraw.Draw(mask).polygon([(round(x * sx), round(y * sy)) for x, y in selection['polygon']], fill=255)
    alpha = np.minimum(np.asarray(source.getchannel('A')), np.asarray(mask))
    if selection.get('largest_component', True):
        _, components, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
        assert len(stats) > 1, name
        alpha[components != 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])] = 0
    extracted = source.copy()
    extracted.putalpha(Image.fromarray(alpha))
    box = extracted.getbbox()
    assert box, name
    extracted = extracted.crop(box)
    extracted.save(ART / f'{name}-source.png')
    width, height = round(extracted.width / sx * pose['scale']), round(extracted.height / sy * pose['scale'])
    sprite = extracted.resize((width, height), Image.Resampling.LANCZOS)
    left = pose['local_anchor'][0] + (box[0] / sx - pose['anchor'][0]) * pose['scale']
    top = pose['local_anchor'][1] + (box[1] / sy - pose['anchor'][1]) * pose['scale']
    bounds = [left + width / 2, top + height / 2, width, height]
    symbols.append({'name': pose['symbol'], 'hash': hash_name(pose['symbol']), 'frames': [[0, 1, *bounds, 0, 0]]})
    sprites[(pose['symbol'], 0)] = sprite
    sprite.save(ART / f'{name}.png')
    manifest['parts'][name] = {**selection, 'crop': list(box), 'placement': pose, 'bounds': bounds}

archive = MOD / 'anim/krypton_eating.zip'
atlas = write_build(CONFIG['build'], symbols, sprites, archive, 512)
atlas.save(PREVIEWS / 'eating-atlas.png')
(ROOT / 'build/eating-extraction-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')

# Runtime timing and preview timing come from the same authored numeric data.
lines = ['-- Generated from assets/slices.json by tools/build_eating_assets.py.', 'return {',
         '    build = ' + json.dumps(CONFIG['build']) + ',',
         '    frames_per_second = ' + str(CONFIG['frames_per_second']) + ',', '    symbols = {']
for pose in CONFIG['poses']:
    lines.append('        %s = %s,' % (pose['pose'], json.dumps(pose['symbol'])))
lines.extend(['    },', '    timelines = {'])
for name, timeline in CONFIG['timelines'].items():
    entries = ', '.join('{ frame = %s, pose = %s }' % (frame, json.dumps(pose)) for frame, pose in timeline)
    lines.append('        %s = { %s },' % (name, entries))
lines.extend(['    },', '}'])
(MOD / 'scripts/krypton_eating_visual_data.lua').write_text('\n'.join(lines) + '\n', encoding='utf8')


def load_sprites(path):
    with zipfile.ZipFile(path) as package:
        build = read_build(package.read('build.bin'))
        texture = read_tex(package.read('atlas-0.tex'))
    frames = {}
    for symbol in build['symbols']:
        for row in symbol['frames']:
            frames[(symbol['hash'], row[0])] = (crop_symbol(build, texture, symbol, row[0]), row)
    return build, frames


compiled, eating_sprites = load_sprites(archive)
validate_build_symbols(compiled)
with zipfile.ZipFile(archive) as package:
    assert set(package.namelist()) == {'build.bin', 'atlas-0.tex'}
assert compiled['name'] == CONFIG['build']
assert len(compiled['symbols']) == 3
pose_symbols = {pose['pose']: hash_name(pose['symbol']) for pose in CONFIG['poses']}
character, character_sprites = load_sprites(MOD / 'anim/krypton_survivor.zip')
original_head = character_sprites[(hash_name('headbase'), 0)]


def placed_head(sprite, row, size=(250, 300)):
    canvas = Image.new('RGBA', size, (224, 218, 199, 255))
    canvas.alpha_composite(sprite, (round(size[0] / 2 + row[2] - row[4] / 2), round(260 + row[3] - row[5] / 2)))
    return canvas.convert('RGB')


head_sheet = Image.new('RGB', (1000, 300), (224, 218, 199))
head_sheet.paste(placed_head(*original_head), (0, 0))
for index, pose in enumerate(CONFIG['poses'], 1):
    head_sheet.paste(placed_head(*eating_sprites[(hash_name(pose['symbol']), 0)]), (index * 250, 0))
head_sheet.save(PREVIEWS / 'eating-heads.png')

# Native body/hand motion is used only while rendering these ignored previews.
with zipfile.ZipFile(game_anim_dir() / 'player_actions_eat.zip') as package:
    animations, native_names = read_anim(package.read('anim.bin'))


def pose_at(name, index):
    pose = None
    for start, entry in CONFIG['timelines'].get(name, []):
        if index < start:
            break
        pose = entry
    return pose


def render(animation, index):
    canvas = Image.new('RGBA', (640, 640), (224, 218, 199, 255))
    pose = pose_at(animation['name'], index)
    for element in sorted(animation['frames'][index]['elements'], key=lambda element: element[9], reverse=True):
        name, layer = native_names.get(element[0]), native_names.get(element[2])
        if layer == 'ARM_carry' or name in ('headbase_hat', 'hair_hat'):
            continue
        sprite = character_sprites.get((element[0], element[1]))
        if name == 'headbase' and pose is not None:
            sprite = eating_sprites[(pose_symbols[pose], 0)]
        if sprite is None:
            continue
        image, row = sprite
        a, b, c, d, tx, ty, _ = element[3:]
        det = a * d - b * c
        if abs(det) < .001:
            continue
        tx += 320
        ty += 540
        left, top = row[2] - row[4] / 2, row[3] - row[5] / 2
        inverse = (d / det, -c / det, (-d * tx + c * ty) / det - left,
                   -b / det, a / det, (b * tx - a * ty) / det - top)
        canvas.alpha_composite(image.transform(canvas.size, Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC))
    return canvas.convert('RGB')


for name in ('eat', 'quick_eat', 'quick_drink'):
    animation = next(animation for animation in animations if animation['name'] == name)
    assert animation['rate'] == CONFIG['frames_per_second']
    frames = [render(animation, index) for index in range(len(animation['frames']))]
    frames[0].save(PREVIEWS / f'{name}-supplied.gif', save_all=True, append_images=frames[1:],
                   duration=round(1000 / animation['rate']), loop=0)
    indices = sorted(set([0, len(frames) - 1] + [min(start, len(frames) - 1) for start, _ in CONFIG['timelines'][name]]))
    columns = 4
    sheet = Image.new('RGB', (320 * columns, 320 * ((len(indices) + columns - 1) // columns)), (224, 218, 199))
    for slot, index in enumerate(indices):
        sheet.paste(frames[index].resize((320, 320), Image.Resampling.LANCZOS), ((slot % columns) * 320, (slot // columns) * 320))
    sheet.save(PREVIEWS / f'{name}-supplied-contact.png')
    manifest.setdefault('native_preview', {})[name] = {'facing': animation['facing'], 'rate': animation['rate'], 'frames': len(frames), 'contact_frames': indices}
(ROOT / 'build/eating-extraction-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
assert hashlib.sha256(source_path.read_bytes()).hexdigest() == source_hash
print('Compiled three supplied eating heads, shared runtime timing and decoded native-motion previews; no native animation distributed.')
