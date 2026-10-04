"""Small original asset compiler for the BILD v6 / ANIM v4 / KTEX formats.

Layout reference: Klei ds_mod_tools buildanimation.py (public format description).
Texture format fields checked against nsimplex/ktools KTEX header specs.
This compiler retains animation anchors, not the base game's artwork.
"""
from pathlib import Path
import struct
import io
import zipfile
from PIL import Image


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def unpack(self, fmt):
        fmt = '<' + fmt
        values = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += struct.calcsize(fmt)
        return values

    def uint(self):
        return self.unpack('I')[0]

    def string(self):
        size = self.uint()
        data = self.data[self.pos:self.pos + size]
        self.pos += size
        return data.decode('utf-8')


def read_build(data):
    r = Reader(data)
    magic, version, symbol_count, frame_count = r.unpack('4sIII')
    assert magic == b'BILD' and version == 6
    name = r.string()
    textures = [r.string() for _ in range(r.uint())]
    symbols = []
    for _ in range(symbol_count):
        hashed, count = r.unpack('II')
        frames = [list(r.unpack('II4fII')) for _ in range(count)]
        symbols.append({'hash': hashed, 'frames': frames})
    verts = [r.unpack('6f') for _ in range(r.uint())]
    names = {}
    for _ in range(r.uint()):
        hashed = r.uint()
        names[hashed] = r.string()
    for symbol in symbols:
        symbol['name'] = names[symbol['hash']]
    assert r.pos == len(data)
    assert sum(len(s['frames']) for s in symbols) == frame_count
    return {'name': name, 'textures': textures, 'symbols': symbols, 'verts': verts, 'names': names}


def read_anim(data):
    r = Reader(data)
    magic, version, element_count, frame_count, event_count, anim_count = r.unpack('4s5I')
    assert magic == b'ANIM' and version == 4
    animations = []
    for _ in range(anim_count):
        name = r.string()
        facing, root, rate, count = r.unpack('BIfI')
        frames = []
        for _ in range(count):
            bbox = r.unpack('4f')
            events = [r.uint() for _ in range(r.uint())]
            elements = [r.unpack('3I7f') for _ in range(r.uint())]
            frames.append({'bbox': bbox, 'events': events, 'elements': elements})
        animations.append({'name': name, 'facing': facing, 'root': root, 'rate': rate, 'frames': frames})
    names = {}
    for _ in range(r.uint()):
        h = r.uint()
        names[h] = r.string()
    assert r.pos == len(data)
    return animations, names


def write_tex(image):
    """KTEX RGBA, full mip chain, premultiplied alpha, bottom-up texels."""
    mips = []
    im = image.convert('RGBA')
    while True:
        w, h = im.size
        raw = bytearray(im.transpose(Image.Transpose.FLIP_TOP_BOTTOM).tobytes())
        for i in range(0, len(raw), 4):
            alpha = raw[i + 3]
            for c in range(3):
                raw[i + c] = (raw[i + c] * alpha + 127) // 255
        mips.append((w, h, w * 4, bytes(raw)))
        if w == h == 1:
            break
        im = im.resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.LANCZOS)
    header = (4 << 4) | (1 << 9) | (len(mips) << 13) | (3 << 18) | (4095 << 20)
    result = bytearray(struct.pack('<4sI', b'KTEX', header))
    for w, h, pitch, raw in mips:
        result.extend(struct.pack('<HHHI', w, h, pitch, len(raw)))
    for _, _, _, raw in mips:
        result.extend(raw)
    return bytes(result)


def read_tex(data):
    magic, header = struct.unpack_from('<4sI', data)
    assert magic == b'KTEX'
    fmt = (header >> 4) & 31
    count = (header >> 13) & 31
    w, h, pitch, size = struct.unpack_from('<HHHI', data, 8)
    raw = data[8 + count * 10:8 + count * 10 + size]
    if fmt == 4:
        image = Image.frombytes('RGBA', (w, h), raw)
    else:
        assert fmt in (0, 1, 2)
        fourcc = [b'DXT1', b'DXT3', b'DXT5'][fmt]
        values = [124, 0x81007, h, w, size, 0, 1] + [0] * 11
        values += [32, 4, int.from_bytes(fourcc, 'little'), 0, 0, 0, 0, 0]
        values += [0x1000, 0, 0, 0, 0]
        image = Image.open(io.BytesIO(b'DDS ' + struct.pack('<31I', *values) + raw)).convert('RGBA')
    return image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)


def crop_symbol(build, atlas, symbol, frame):
    row = next(f for f in symbol['frames'] if f[0] == frame)
    verts = build['verts'][row[6]:row[6] + row[7]]
    # Vanilla compiler can split one sprite into multiple rectangular regions.
    w, h = max(1, round(row[4])), max(1, round(row[5]))
    image = Image.new('RGBA', (w, h))
    for i in range(0, len(verts), 6):
        quad = verts[i:i+6]
        source_atlas = atlas[round(quad[0][5])] if isinstance(atlas, list) else atlas
        left, top = min(v[0] for v in quad), min(v[1] for v in quad)
        right, bottom = max(v[0] for v in quad), max(v[1] for v in quad)
        uvleft, uvright = min(v[3] for v in quad), max(v[3] for v in quad)
        uvtop, uvbottom = 1-max(v[4] for v in quad), 1-min(v[4] for v in quad)
        region = source_atlas.crop((round(uvleft*source_atlas.width), round(uvtop*source_atlas.height),
                             round(uvright*source_atlas.width), round(uvbottom*source_atlas.height)))
        target_size = (max(1,round(right-left)), max(1,round(bottom-top)))
        region = region.resize(target_size)
        image.alpha_composite(region, (round(left-(row[2]-w/2)), round(top-(row[3]-h/2))))
    return image


def write_build(name, symbols, sprite_images, output, atlas_size=2048, extra_files=None):
    """Pack independently drawn sprites, preserving symbol hashes and frame ids."""
    atlas = Image.new('RGBA', (atlas_size, atlas_size))
    rects = {}
    x = y = line_height = 4
    for key, im in sorted(sprite_images.items(), key=lambda pair: (-pair[1].height, -pair[1].width)):
        if x + im.width + 4 > atlas_size:
            x = 4
            y += line_height + 4
            line_height = 0
        assert y + im.height + 4 <= atlas_size, 'Atlas overflow'
        atlas.alpha_composite(im, (x, y))
        rects[key] = (x, y, im.width, im.height)
        x += im.width + 4
        line_height = max(line_height, im.height)
    vertices = []
    data = bytearray(struct.pack('<4sIII', b'BILD', 6, len(symbols), sum(len(s['frames']) for s in symbols)))
    def string(value):
        value = value.encode()
        return struct.pack('<I', len(value)) + value
    data += string(name) + struct.pack('<I', 1) + string('atlas-0.tex')
    for s in symbols:
        data += struct.pack('<II', s['hash'], len(s['frames']))
        for row in s['frames']:
            frame, duration, cx, cy, w, h, _, _ = row
            ax, ay, iw, ih = rects[(s['name'], frame)]
            left, top, right, bottom = cx-w/2, cy-h/2, cx+w/2, cy+h/2
            u0, u1 = ax/atlas_size, (ax+iw)/atlas_size
            v0, v1 = 1-ay/atlas_size, 1-(ay+ih)/atlas_size
            offset = len(vertices)
            vertices += [(left,top,0,u0,v0,0), (right,top,0,u1,v0,0), (left,bottom,0,u0,v1,0),
                         (right,top,0,u1,v0,0), (right,bottom,0,u1,v1,0), (left,bottom,0,u0,v1,0)]
            data += struct.pack('<II4fII', frame, duration, cx, cy, w, h, offset, 6)
    data += struct.pack('<I', len(vertices))
    for v in vertices:
        data += struct.pack('<6f', *v)
    data += struct.pack('<I', len(symbols))
    for s in symbols:
        data += struct.pack('<I', s['hash']) + string(s['name'])
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr('build.bin', data)
        z.writestr('atlas-0.tex', write_tex(atlas))
        for key, value in (extra_files or {}).items():
            z.writestr(key, value)
    return atlas
