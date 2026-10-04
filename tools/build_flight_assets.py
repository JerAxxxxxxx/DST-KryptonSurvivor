"""Extract the six supplied flight poses and pack original ANIM/BILD data.

Only source pixels, alpha masks, scaling and whole-pose translation are used.
No game animation is loaded and no character or weapon pixels are painted.
"""
from pathlib import Path
import hashlib
import json
import math
import zipfile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from klei_assets import crop_symbol, hash_name, read_anim, read_build, read_tex, write_anim, write_build
from paths import ROOT, MOD, PREVIEWS

SPEC = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))
CONFIG = SPEC['flight']
ART = ROOT / 'build/art/flight'
ART.mkdir(parents=True, exist_ok=True)
PREVIEWS.mkdir(parents=True, exist_ok=True)


def matte(path, tolerance):
    """Remove only background connected to an image edge, including JPG grid."""
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


source_item = SPEC['sources']['flight']
source_path = ROOT / source_item['path']
source = matte(source_path, source_item['tolerance'])
source.save(ART / 'source-transparent.png')
sx, sy = source.width / 1024, source.height / 341
manifest = {
    'sources': {'flight': {**source_item, 'sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(), 'size': list(source.size)}},
    'parts': {},
}
symbol_hash = hash_name(CONFIG['symbol'])
bank_hash = hash_name(CONFIG['bank'])
assert bank_hash == 75779832, 'Incorrect wilson bank hash'
sprites = {}
symbol_frames = []
animations = []

for pose in CONFIG['poses']:
    name = pose['selection']
    selection = SPEC['selections'][name]
    assert selection['source'] == 'flight'
    mask = Image.new('L', source.size)
    points = [(round(x * sx), round(y * sy)) for x, y in selection['polygon']]
    ImageDraw.Draw(mask).polygon(points, fill=255)  # Alpha selection only.
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
    width = round(extracted.width / sx * pose['scale'])
    height = round(extracted.height / sy * pose['scale'])
    sprite = extracted.resize((width, height), Image.Resampling.LANCZOS)
    left = pose['local_anchor'][0] + (box[0] / sx - pose['anchor'][0]) * pose['scale']
    top = pose['local_anchor'][1] + (box[1] / sy - pose['anchor'][1]) * pose['scale']
    bounds = [left + width / 2, top + height / 2, width, height]
    row = [pose['frame'], 1, *bounds, 0, 0]
    symbol_frames.append(row)
    sprites[(CONFIG['symbol'], pose['frame'])] = sprite
    sprite.save(ART / f'{name}.png')
    manifest['parts'][name] = {**selection, 'crop': list(box), 'placement': pose, 'bounds': bounds}
    frames = []
    for index in range(CONFIG['loop_frames']):
        bob = CONFIG['bob_pixels'] * math.sin(index * 2 * math.pi / CONFIG['loop_frames'])
        frames.append({
            'bbox': [bounds[0], bounds[1] + bob, width, height],
            'events': [],
            'elements': [(symbol_hash, pose['frame'], symbol_hash, 1, 0, 0, 1, 0, bob, 0)],
        })
    animations.append({'name': pose['animation'], 'facing': pose['facing'], 'root': bank_hash,
                       'rate': CONFIG['frames_per_second'], 'frames': frames})

symbols = [{'name': CONFIG['symbol'], 'hash': symbol_hash, 'frames': symbol_frames}]
animation_data = write_anim(animations, {bank_hash: CONFIG['bank'], symbol_hash: CONFIG['symbol']})
archive = MOD / 'anim/krypton_flight.zip'
atlas = write_build(CONFIG['build'], symbols, sprites, archive, 1024, {'anim.bin': animation_data})
atlas.save(PREVIEWS / 'flight-atlas.png')
(ROOT / 'build/flight-extraction-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')

# Render the compiled archive, rather than the pre-compilation cutouts.
with zipfile.ZipFile(archive) as package:
    compiled_build = read_build(package.read('build.bin'))
    compiled_atlas = read_tex(package.read('atlas-0.tex'))
    compiled_animations, compiled_names = read_anim(package.read('anim.bin'))
compiled_symbol = compiled_build['symbols'][0]
compiled_sprites = {row[0]: (crop_symbol(compiled_build, compiled_atlas, compiled_symbol, row[0]), row)
                    for row in compiled_symbol['frames']}


def render(animation, index):
    canvas = Image.new('RGBA', (640, 640), (224, 218, 199, 255))
    for element in animation['frames'][index]['elements']:
        image, row = compiled_sprites[element[1]]
        a, b, c, d, tx, ty, _ = element[3:]
        det = a * d - b * c
        tx += 320
        ty += 540
        left, top = row[2] - row[4] / 2, row[3] - row[5] / 2
        inverse = (d / det, -c / det, (-d * tx + c * ty) / det - left,
                   -b / det, a / det, (b * tx - a * ty) / det - top)
        canvas.alpha_composite(image.transform(canvas.size, Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC))
    return canvas.convert('RGB')


poses = Image.new('RGB', (1920, 1280), (224, 218, 199))
contact = Image.new('RGB', (1920, 1280), (224, 218, 199))
combined = [Image.new('RGB', (960, 640), (224, 218, 199)) for _ in range(CONFIG['loop_frames'])]
for pose_index, animation in enumerate(compiled_animations):
    frames = [render(animation, index) for index in range(len(animation['frames']))]
    pose = CONFIG['poses'][pose_index]
    label = 'idle' if pose['frame'] < 3 else 'move'
    frames[0].save(PREVIEWS / f'flight-{label}-{pose["direction"]}.gif', save_all=True,
                   append_images=frames[1:], duration=round(1000 / animation['rate']), loop=0)
    poses.paste(frames[0], ((pose_index % 3) * 640, (pose_index // 3) * 640))
    for row_index, frame_index in enumerate([0, 3, 6, 9]):
        contact.paste(frames[frame_index].resize((320, 320), Image.Resampling.LANCZOS), (pose_index * 320, row_index * 320))
    for index, frame in enumerate(frames):
        combined[index].paste(frame.resize((320, 320), Image.Resampling.LANCZOS), ((pose_index % 3) * 320, (pose_index // 3) * 320))
poses.resize((960, 640), Image.Resampling.LANCZOS).save(PREVIEWS / 'flight-poses.png')
contact.save(PREVIEWS / 'flight-contact-sheet.png')
combined[0].save(PREVIEWS / 'flight-loop.gif', save_all=True, append_images=combined[1:],
                 duration=round(1000 / CONFIG['frames_per_second']), loop=0)
assert hashlib.sha256(source_path.read_bytes()).hexdigest() == manifest['sources']['flight']['sha256']
print('Compiled six supplied flight poses and six original 12-frame loops; source pixels preserved.')
