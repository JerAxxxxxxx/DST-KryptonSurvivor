"""Compile the in-game mod-list icon from existing user-supplied artwork.

Only crop and scale existing pixels. Character, clothing and weapon artwork
is never drawn, and the authoritative source file is left unchanged.
"""

import hashlib
import json
import struct
from pathlib import Path

from PIL import Image

from klei_assets import read_tex, write_tex


def verify_mip_chain(data, expected_size):
    magic, header = struct.unpack_from('<4sI', data)
    assert magic == b'KTEX' and (header >> 4) & 31 == 4
    count = (header >> 13) & 31
    expected = []
    width, height = expected_size
    while True:
        expected.append((width, height, width * 4, width * height * 4))
        if width == height == 1:
            break
        width, height = max(1, width // 2), max(1, height // 2)
    assert count == len(expected), 'Full mip chain required'
    actual = [struct.unpack_from('<HHHI', data, 8 + level * 10)
              for level in range(count)]
    assert actual == expected, 'Unexpected RGBA mip dimensions'
    assert len(data) == 8 + count * 10 + sum(level[3] for level in expected)
    return count


def main():
    root = Path(__file__).resolve().parents[1]
    slices = json.loads((root / 'assets/slices.json').read_text(encoding='utf8'))
    spec = slices['mod_icon']
    source = root / slices['sources'][spec['source']]['path']
    original = source.read_bytes()
    source_digest = hashlib.sha256(original).hexdigest()
    crop = tuple(spec['crop_pixels'])
    size = tuple(spec['output_size'])
    assert size == (128, 128), 'Expected square in-game mod-list icon'
    for name in ('atlas', 'texture', 'element'):
        assert Path(spec[name]).name == spec[name], 'Use root-level icon names'
    assert spec['atlas'].endswith('.xml') and spec['texture'].endswith('.tex')

    with Image.open(source) as image:
        left, top, right, bottom = crop
        assert 0 <= left < right <= image.width and 0 <= top < bottom <= image.height
        source_size = list(image.size)
        icon = image.crop(crop).convert('RGBA').resize(size, Image.Resampling.LANCZOS)
    data = write_tex(icon)
    mips = verify_mip_chain(data, size)
    texture = root / 'mod' / spec['texture']
    atlas = root / 'mod' / spec['atlas']
    texture.write_bytes(data)
    atlas.write_text(
        f'<Atlas><Texture filename="{spec["texture"]}"/><Elements>'
        f'<Element name="{spec["element"]}" u1="0" u2="1" v1="0" v2="1"/>'
        '</Elements></Atlas>\n', encoding='utf8', newline='\n')

    decoded = read_tex(texture.read_bytes())
    assert decoded.size == size and decoded.tobytes() == icon.tobytes()
    assert decoded.getchannel('A').getextrema() == (255, 255)
    previews = root / 'build/previews'
    previews.mkdir(parents=True, exist_ok=True)
    decoded.save(previews / 'mod-icon-compiled.png')
    decoded.resize((512, 512), Image.Resampling.NEAREST).save(
        previews / 'mod-icon-compiled-4x.png')
    assert source.read_bytes() == original, 'Authoritative artwork changed'
    manifest = {
        'source': source.relative_to(root).as_posix(),
        'source_sha256': source_digest,
        'source_size': source_size,
        'crop_pixels': list(crop),
        'output_size': list(size),
        'operations': ['crop', 'RGBA conversion', 'Lanczos scaling', 'KTEX packaging'],
        'compiled': {
            'atlas': atlas.relative_to(root).as_posix(),
            'texture': texture.relative_to(root).as_posix(),
            'element': spec['element'],
            'mipmaps': mips,
            'texture_sha256': hashlib.sha256(data).hexdigest(),
        },
        'decoded_preview': 'build/previews/mod-icon-compiled.png',
        'source_unchanged': True,
        'new_artwork_drawn': False,
    }
    (root / 'build/mod-icon-extraction-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n',
        encoding='utf8', newline='\n')
    print(f'Compiled {size[0]}x{size[1]} mod icon with {mips} RGBA mip levels; source unchanged.')


if __name__ == '__main__':
    main()
