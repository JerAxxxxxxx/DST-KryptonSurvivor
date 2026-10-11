"""Extract the user's orange energy core for the starcore amulet.

Only supplied RGBA pixels are selected, masked, cropped and scaled. No new
amulet, chain, character or clothing pixels are drawn. The installed amulets
animation is read for ignored previews and loaded by the game at runtime;
it is never copied to a distributable archive.
"""
import hashlib
import json
import zipfile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from klei_assets import (crop_symbol, hash_name, read_anim, read_build, read_tex,
                         validate_build_symbols, write_build, write_tex)
from paths import ROOT, MOD, PREVIEWS, game_anim_dir


def fitted(image, size):
    result = image.copy()
    result.thumbnail(tuple(size), Image.Resampling.LANCZOS)
    return result


def compile_assets():
    spec = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))
    config = spec['starcore']
    selection = spec['selections'][config['selection']]
    source_path = ROOT / spec['sources'][selection['source']]['path']
    source_bytes = source_path.read_bytes()
    source = Image.open(source_path).convert('RGBA')
    assert source.getchannel('A').getextrema()[0] == 0, 'Expected supplied transparent source'
    sx, sy = source.width / 1024, source.height / 341
    mask = Image.new('L', source.size)
    ImageDraw.Draw(mask).polygon([(round(x * sx), round(y * sy)) for x, y in selection['polygon']], fill=255)
    # This polygon edits only the alpha mask; source RGB stays untouched.
    alpha = np.minimum(np.asarray(source.getchannel('A')), np.asarray(mask))
    if selection.get('largest_component', False):
        count, labels, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
        assert count > 1, 'Starcore selection is empty'
        alpha[labels != 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])] = 0
    extracted = source.copy()
    extracted.putalpha(Image.fromarray(alpha))
    crop = extracted.getbbox()
    assert crop, 'Starcore selection is empty'
    extracted = extracted.crop(crop)
    art = ROOT / 'build/art/starcore'
    art.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    extracted.save(art / 'core-source.png')

    ground = fitted(extracted, config['ground']['fit_size'])
    cx, cy = config['ground']['symbol_center']
    bounds = [cx, cy, ground.width, ground.height]
    symbols = [{'name': config['symbol'], 'hash': hash_name(config['symbol']),
                'frames': [[config['frame'], 1, *bounds, 0, 0]]}]
    archive = MOD / 'anim/krypton_starcore_build.zip'
    write_build(config['build'], symbols, {(config['symbol'], config['frame']): ground}, archive,
                config['ground']['atlas_size'])

    inventory = config['inventory']
    icon = Image.new('RGBA', tuple(inventory['size']))
    core_icon = fitted(extracted, inventory['fit_size'])
    icon.alpha_composite(core_icon, (round(inventory['center'][0] - core_icon.width / 2),
                                    round(inventory['center'][1] - core_icon.height / 2)))
    icon_path = MOD / 'images/inventoryimages/krypton_starcore_amulet'
    icon_path.parent.mkdir(parents=True, exist_ok=True)
    icon_path.with_suffix('.tex').write_bytes(write_tex(icon))
    icon_path.with_suffix('.xml').write_text(
        '<Atlas><Texture filename="krypton_starcore_amulet.tex"/><Elements>'
        '<Element name="krypton_starcore_amulet.tex" u1="0" u2="1" v1="0" v2="1"/>'
        '</Elements></Atlas>\n', encoding='utf8', newline='\n')

    # Inspect decoded output rather than only the source cutout.
    with zipfile.ZipFile(archive) as package:
        assert set(package.namelist()) == {'build.bin', 'atlas-0.tex'}, 'Native animation was packaged'
        build = read_build(package.read('build.bin'))
        texture = read_tex(package.read('atlas-0.tex'))
    validate_build_symbols(build)
    assert build['name'] == config['build'] and len(build['symbols']) == 1
    symbol = build['symbols'][0]
    assert symbol['name'] == config['symbol'] and symbol['frames'][0][0] == config['frame']
    decoded = crop_symbol(build, texture, symbol, config['frame'])
    assert decoded.getbbox(), 'Compiled core sprite is blank'
    decoded.save(PREVIEWS / 'starcore-ground-sprite.png')
    decoded_icon = read_tex(icon_path.with_suffix('.tex').read_bytes())
    assert decoded_icon.size == tuple(inventory['size']) and decoded_icon.getbbox()
    decoded_icon.save(PREVIEWS / 'starcore-inventory.png')

    with zipfile.ZipFile(game_anim_dir() / 'amulets.zip') as native:
        animations, names = read_anim(native.read('anim.bin'))
    native_animation = next(animation for animation in animations
                            if animation['name'] == config['animation'])
    assert names[native_animation['root']] == config['bank']
    frames = []
    for frame in native_animation['frames']:
        preview = Image.new('RGBA', (384, 256), (224, 218, 199, 255))
        for element in sorted(frame['elements'], key=lambda value: -value[-1]):
            hashed, source_frame, _, a, b, c, d, tx, ty, _ = element
            assert hashed == symbol['hash'] and source_frame == config['frame']
            assert (a, b, c, d) == (1, 0, 0, 1), 'Native amulet transform changed'
            row = symbol['frames'][0]
            preview.alpha_composite(decoded, (round(192 + tx + row[2] - row[4] / 2),
                                              round(128 + ty + row[3] - row[5] / 2)))
        frames.append(preview.convert('RGB'))
    frames[0].save(PREVIEWS / 'starcore-ground-native.png')
    frames[0].save(PREVIEWS / 'starcore-ground-native.gif', save_all=True, append_images=frames[1:],
                   duration=round(1000 / native_animation['rate']), loop=0)
    sheet = Image.new('RGBA', (384, 256), (224, 218, 199, 255))
    large = decoded.resize((decoded.width * 2, decoded.height * 2), Image.Resampling.NEAREST)
    sheet.alpha_composite(large, (96 - large.width // 2, 128 - large.height // 2))
    sheet.alpha_composite(decoded_icon, (224, 64))
    sheet.convert('RGB').save(PREVIEWS / 'starcore-compiled-contact.png')

    manifest = {
        'sources': {selection['source']: {
            'path': str(source_path.relative_to(ROOT)).replace('\\', '/'),
            'sha256': hashlib.sha256(source_bytes).hexdigest(), 'size': list(source.size)}},
        'selection': selection, 'crop': list(crop), 'placement': config,
        'bounds': bounds, 'symbols': [symbol['name']], 'compiled_archive': str(archive.relative_to(ROOT)).replace('\\', '/'),
        'runtime_dependency': {'path': 'anim/amulets.zip', 'bank': config['bank'],
                               'animation': config['animation'], 'preview_frames': len(frames)},
        'native_animation_redistributed': False,
    }
    (ROOT / 'build/starcore-extraction-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    assert source_path.read_bytes() == source_bytes, 'Authoritative source was altered'
    print('Compiled and decoded one supplied starcore sprite, inventory atlas and native-motion preview; no native artwork/animation packaged.')


if __name__ == '__main__':
    compile_assets()
