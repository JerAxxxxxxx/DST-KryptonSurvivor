"""Preview decoded dark packs against installed motions, kept in ignored build/.

Native ANIM files are read into memory only. No native pixels or animation data
are emitted, packaged or copied. All visible sprites are the user's artwork.
"""
import json
import zipfile

from PIL import Image, ImageDraw

from klei_assets import crop_symbol, read_anim, read_build, read_tex
from paths import ROOT, MOD, PREVIEWS, game_anim_dir

CONFIG = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))['dark_suit']
GAME = game_anim_dir()
PREVIEWS.mkdir(parents=True, exist_ok=True)


def sprites_from(relative):
    with zipfile.ZipFile(MOD / relative) as package:
        build = read_build(package.read('build.bin'))
        atlas = read_tex(package.read('atlas-0.tex'))
    return {(symbol['hash'], row[0]): (crop_symbol(build, atlas, symbol, row[0]), row)
            for symbol in build['symbols'] for row in symbol['frames']}


normal_sprites = sprites_from('anim/krypton_survivor.zip')
dark_sprites = {**normal_sprites, **sprites_from(CONFIG['archive'])}
weapon_sprites = sprites_from('anim/krypton_staff_build.zip')
with zipfile.ZipFile(MOD / 'anim/krypton_staff_build.zip') as package:
    weapon_build = read_build(package.read('build.bin'))
weapon_hash = next(symbol['hash'] for symbol in weapon_build['symbols'] if symbol['name'] == 'swap_cane')
weapon_sprite = weapon_sprites[(weapon_hash, 0)]

animations, names = [], {}
for archive in ['player_basic.zip', 'player_attacks.zip', 'player_idles.zip']:
    with zipfile.ZipFile(GAME / archive) as package:
        rows, table = read_anim(package.read('anim.bin'))
        animations.extend(rows)
        names.update(table)


def render(animation, index, sprites, equipped=True):
    canvas = Image.new('RGBA', (640, 640), (224, 218, 199, 255))
    for element in sorted(animation['frames'][index]['elements'], key=lambda element: element[9], reverse=True):
        name, layer = names.get(element[0]), names.get(element[2])
        if layer == ('ARM_normal' if equipped else 'ARM_carry') or name in ['headbase_hat', 'hair_hat']:
            continue
        sprite = weapon_sprite if equipped and name == 'swap_object' else sprites.get((element[0], element[1]))
        if sprite is None:
            continue
        image, row = sprite
        a, b, c, d, tx, ty, _ = element[3:]
        determinant = a * d - b * c
        if abs(determinant) < .001:
            continue
        tx += 320
        ty += 540
        left, top = row[2] - row[4] / 2, row[3] - row[5] / 2
        inverse = (d / determinant, -c / determinant, (-d * tx + c * ty) / determinant - left,
                   -b / determinant, a / determinant, (b * tx - a * ty) / determinant - top)
        canvas.alpha_composite(image.transform(canvas.size, Image.Transform.AFFINE, inverse, Image.Resampling.BICUBIC))
    return canvas.convert('RGB')


sheet = Image.new('RGB', (1920, 1920), (224, 218, 199))
report = {'body': [], 'flight': [], 'note': 'Compiled source pixels with installed ANIM in memory; not a live game render.'}
for action_index, action in enumerate(['idle_loop', 'run_loop', 'atk']):
    for column, (facing, direction) in enumerate([(8, 'front'), (5, 'side'), (2, 'back')]):
        animation = next(row for row in animations if row['name'] == action and row['facing'] == facing)
        frames = [render(animation, index, dark_sprites) for index in range(len(animation['frames']))]
        frames[0].save(PREVIEWS / f'dark-{action}-{direction}.gif', save_all=True, append_images=frames[1:],
                       duration=round(1000 / animation['rate']), loop=0)
        sheet.paste(frames[0], (column * 640, action_index * 640))
        ImageDraw.Draw(sheet).text((column * 640 + 20, action_index * 640 + 15), f'{action} / {direction}', fill=(40, 40, 40))
        contact = Image.new('RGB', (1280, ((len(frames) + 3) // 4) * 320), (224, 218, 199))
        for index, frame in enumerate(frames):
            contact.paste(frame.resize((320, 320), Image.Resampling.LANCZOS), ((index % 4) * 320, (index // 4) * 320))
        contact.save(PREVIEWS / f'dark-{action}-{direction}-contact.png')
        report['body'].append({'action': action, 'direction': direction, 'frames': len(frames)})
sheet.resize((960, 960), Image.Resampling.LANCZOS).save(PREVIEWS / 'dark-suit-compiled.png')

flight_sprites = sprites_from(CONFIG['flight_archive'])
normal_flight_sprites = sprites_from(CONFIG['flight_template'])
with zipfile.ZipFile(MOD / CONFIG['flight_template']) as package:
    flight_animations, flight_names = read_anim(package.read('anim.bin'))
names.update(flight_names)
flight_sheet = Image.new('RGB', (1920, 1280), (224, 218, 199))
comparison = Image.new('RGB', (3840, 1280), (224, 218, 199))
for index, animation in enumerate(flight_animations):
    frames = [render(animation, frame, flight_sprites, False) for frame in range(len(animation['frames']))]
    pose = CONFIG['flight_poses'][index]
    frames[0].save(PREVIEWS / f'dark-{pose["selection"]}.gif', save_all=True, append_images=frames[1:],
                   duration=round(1000 / animation['rate']), loop=0)
    flight_sheet.paste(frames[0], ((index % 3) * 640, (index // 3) * 640))
    comparison.paste(render(animation, 0, normal_flight_sprites, False), (index * 640, 0))
    comparison.paste(frames[0], (index * 640, 640))
    report['flight'].append({'selection': pose['selection'], 'frames': len(frames)})
flight_sheet.resize((960, 640), Image.Resampling.LANCZOS).save(PREVIEWS / 'dark-flight-compiled.png')
comparison.resize((1920, 640), Image.Resampling.LANCZOS).save(PREVIEWS / 'dark-flight-comparison.png')
(PREVIEWS / 'dark-suit-compiled.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print('Rendered compiled dark idle/run/attack in three directions and all six original flight loops.')
