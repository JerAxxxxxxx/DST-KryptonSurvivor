"""Extract the supplied dark clothing/flight pixels into two build-only packs.

Selections and joint placements live in slices.dark_suit. The existing custom
normal build supplies compatible symbol geometry, never replacement artwork.
No native game files are read or copied by this compiler.
"""
import copy
import hashlib
import json
import zipfile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from klei_assets import read_build, read_tex, write_build, validate_build_symbols
from paths import ROOT, MOD, PREVIEWS

CONFIG = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))['dark_suit']
ART = ROOT / 'build/art/dark-suit'
ART.mkdir(parents=True, exist_ok=True)
PREVIEWS.mkdir(parents=True, exist_ok=True)
MANIFEST = {'sources': {}, 'parts': {}, 'builds': {}}


def matte(path, tolerance):
    """Extract edge-connected paper/checkerboard; preserve every RGB pixel."""
    rgb = np.asarray(Image.open(path).convert('RGB'))
    paper = np.median(np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]), axis=0)
    difference = np.max(np.abs(rgb.astype(float) - paper), axis=2)
    _, labels = cv2.connectedComponents((difference < tolerance).astype(np.uint8), connectivity=4)
    exterior = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    alpha = np.where(np.isin(labels, exterior[exterior != 0]), 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]))


SOURCES = {}
for name, item in CONFIG['sources'].items():
    path = ROOT / item['path']
    SOURCES[name] = matte(path, item['tolerance'])
    SOURCES[name].save(ART / f'{name}-transparent.png')
    MANIFEST['sources'][name] = {**item, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                 'size': list(SOURCES[name].size)}


def extract(name):
    selection = CONFIG['selections'][name]
    source = SOURCES[selection['source']]
    reference = CONFIG['sources'][selection['source']]['reference_size']
    sx, sy = source.width / reference[0], source.height / reference[1]
    mask = Image.new('L', source.size)
    ImageDraw.Draw(mask).polygon([(round(x * sx), round(y * sy)) for x, y in selection['polygon']], fill=255)
    alpha = np.minimum(np.asarray(source.getchannel('A')), np.asarray(mask))
    if selection.get('largest_component', True):
        _, labels, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
        assert len(stats) > 1, name
        alpha[labels != 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])] = 0
    result = source.copy()
    result.putalpha(Image.fromarray(alpha))
    box = result.getbbox()
    assert box, name
    result = result.crop(box)
    result.save(ART / f'{name}-source.png')
    MANIFEST['parts'][name] = {**selection, 'crop': list(box)}
    return result, (box[0] / sx, box[1] / sy), (sx, sy)


def local_part(selection, placement):
    image, origin, (sx, sy) = extract(selection)
    width, height = round(image.width / sx * placement['scale']), round(image.height / sy * placement['scale'])
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    left = placement['local_anchor'][0] + (origin[0] - placement['anchor'][0]) * placement['scale']
    top = placement['local_anchor'][1] + (origin[1] - placement['anchor'][1]) * placement['scale']
    return image, [left + width / 2, top + height / 2, width, height]


def place(image, bounds, target):
    """Place extracted pixels at their joint within the unchanged symbol box."""
    output = Image.new('RGBA', (round(target[4]), round(target[5])))
    left, top = target[2] - target[4] / 2, target[3] - target[5] / 2
    output.alpha_composite(image, (round(bounds[0] - bounds[2] / 2 - left),
                                   round(bounds[1] - bounds[3] / 2 - top)))
    return output


def limb(name, row):
    layout = CONFIG['limb_placements'][name]
    frame = row[0]
    selection = layout.get('selection_frames', {}).get(str(frame))
    if selection is None:
        selection = layout['bent_selection'] if frame in layout.get('bent_frames', []) else layout['selection']
    image = extract(selection)[0]
    rotation = layout.get('rotation', 0) + layout.get('rotation_frames', {}).get(str(frame), 0)
    if rotation:
        image = image.rotate(rotation, resample=Image.Resampling.BICUBIC, expand=True)
    if frame in layout.get('horizontal_frames', []):
        image = image.transpose(Image.Transpose.ROTATE_270)
    if frame in layout.get('flip_horizontal_frames', []):
        image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if frame in layout.get('flip_vertical_frames', []):
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    image = image.crop(image.getbbox())
    return image.resize((round(row[4]), round(row[5])), Image.Resampling.LANCZOS)


with zipfile.ZipFile(MOD / CONFIG['geometry_template']) as package:
    normal = read_build(package.read('build.bin'))
symbols = copy.deepcopy([symbol for symbol in normal['symbols'] if symbol['name'] in CONFIG['body_symbols']])
sprites = {}
for symbol in symbols:
    for row in symbol['frames']:
        name = symbol['name']
        if name == 'torso':
            direction = next(direction for direction, frames in CONFIG['torso_frames'].items() if row[0] in frames)
            placement = CONFIG['body_placements'][direction]
            image, bounds = local_part('torso-' + direction, placement)
            sprite = place(image, bounds, row)
            if 'mirror_cape' in placement:
                cape_placement = {**placement, 'local_anchor': placement.get('cape_local_anchor', placement['local_anchor'])}
                cape, cape_bounds = local_part(placement['mirror_cape'], cape_placement)
                combined = place(cape, cape_bounds, row) if placement.get('include_cape_original') else Image.new('RGBA', sprite.size)
                mirrored_bounds = [-cape_bounds[0], *cape_bounds[1:]]
                combined.alpha_composite(place(cape.transpose(Image.Transpose.FLIP_LEFT_RIGHT), mirrored_bounds, row))
                combined.alpha_composite(sprite)
                sprite = combined
            elif 'separate_cape' in placement:
                cape_placement = {**placement, 'local_anchor': placement['cape_local_anchor']}
                cape, cape_bounds = local_part(placement['separate_cape'], cape_placement)
                combined = place(cape, cape_bounds, row)
                combined.alpha_composite(sprite)
                sprite = combined
        else:
            sprite = limb(name, row)
        assert sprite.getbbox(), (name, row[0])
        sprite.save(ART / f'{name}-{row[0]}.png')
        sprites[(name, row[0])] = sprite

atlas = write_build(CONFIG['build'], symbols, sprites, MOD / CONFIG['archive'], 1024)
atlas.save(PREVIEWS / 'dark-suit-atlas.png')
assert sum(len(symbol['frames']) for symbol in symbols) == 55

with zipfile.ZipFile(MOD / CONFIG['flight_template']) as package:
    flight = read_build(package.read('build.bin'))
flight_symbols = copy.deepcopy(flight['symbols'])
assert len(flight_symbols) == 1 and flight_symbols[0]['name'] == CONFIG['flight_symbol']
flight_sprites = {}
for pose, row in zip(CONFIG['flight_poses'], flight_symbols[0]['frames']):
    assert pose['frame'] == row[0] and pose['fit'] == 'contain-bottom'
    image = extract(pose['selection'])[0]
    size = (round(row[4]), round(row[5]))
    image.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', size)
    canvas.alpha_composite(image, ((size[0] - image.width) // 2, size[1] - image.height))
    flight_sprites[(CONFIG['flight_symbol'], row[0])] = canvas
    canvas.save(ART / f'flight-{row[0]}.png')
atlas = write_build(CONFIG['flight_build'], flight_symbols, flight_sprites, MOD / CONFIG['flight_archive'], 1024)
atlas.save(PREVIEWS / 'dark-flight-atlas.png')

for relative, expected, frame_count in [(CONFIG['archive'], CONFIG['build'], 55),
                                         (CONFIG['flight_archive'], CONFIG['flight_build'], 6)]:
    path = MOD / relative
    with zipfile.ZipFile(path) as package:
        assert set(package.namelist()) == {'build.bin', 'atlas-0.tex'}, 'Build-only packs must not embed native animation.'
        build = read_build(package.read('build.bin'))
        validate_build_symbols(build)
        assert build['name'] == expected
        assert sum(len(symbol['frames']) for symbol in build['symbols']) == frame_count
        assert read_tex(package.read('atlas-0.tex')).getbbox()
    MANIFEST['builds'][relative] = {'name': expected, 'frames': frame_count,
                                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
for source in MANIFEST['sources'].values():
    assert hashlib.sha256((ROOT / source['path']).read_bytes()).hexdigest() == source['sha256']
(ROOT / 'build/dark-suit-extraction-manifest.json').write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2), encoding='utf8')
print('Compiled 55 dark clothing frames and six supplied flight poses into two build-only packs.')
