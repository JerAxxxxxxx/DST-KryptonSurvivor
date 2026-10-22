"""Package the generated status icons without drawing or changing the sources.

Only alpha-bound extraction and aspect-preserving scaling are used for artwork.
The ignored preview is a UI composition, not a captured in-game screenshot.
"""
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from klei_assets import read_tex, write_tex
from paths import MOD, PREVIEWS, ROOT


def verify_mips(data, size):
    magic, header = struct.unpack_from('<4sI', data)
    count = (header >> 13) & 31
    assert magic == b'KTEX' and (header >> 4) & 31 == 4
    expected = []
    width, height = size
    while True:
        expected.append((width, height))
        if width == height == 1:
            break
        width, height = max(1, width // 2), max(1, height // 2)
    assert count == len(expected), 'Missing complete mipmap chain'
    byte_count = 8 + count * 10
    for index, (width, height) in enumerate(expected):
        w, h, pitch, size = struct.unpack_from('<HHHI', data, 8 + index * 10)
        assert (w, h, pitch, size) == (width, height, width * 4, width * height * 4)
        byte_count += size
    assert byte_count == len(data), 'Incorrect mipmap payload'
    return count


def preview_icons(decoded):
    canvas = Image.new('RGB', (768, 232), '#282c32')
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 18)
    for index, (name, icon) in enumerate(decoded.items()):
        x = index * 256
        canvas.paste(icon, (x + 64, 30), icon)
        draw.text((x + 128, 174), name, fill='#ede9df', font=font, anchor='mt')
    draw.text((384, 212), 'Decoded KTEX icons | 128 px with full mipmaps',
              fill='#c1c5ce', font=font, anchor='mm')
    canvas.save(PREVIEWS / 'ability-icons-compiled.png')


def preview_hud(decoded):
    """Show the six-row UI, including skill feedback and replicated form."""
    scenarios = [
        ('Ready', ['飞行：已开启', '护符：保护生效', '复活：已就绪'],
         ['Flight: Enabled', 'Amulet: Protected', 'Revive: Ready'], [True, True, True],
         ['热视线 [R]：就绪', '吐息 [X]：就绪'], ['Heat [R]: Ready', 'Frost [X]: Ready'], ['ready', 'ready']),
        ('Casting / cooldown', ['飞行：已开启', '护符：保护生效', '复活：冷却 08:00'],
         ['Flight: Enabled', 'Amulet: Protected', 'Revive: Cooldown 08:00'], [True, True, True],
         ['热视线 [R]：冷却中', '吐息 [X]：施放中'], ['Heat [R]: Cooldown', 'Frost [X]: Casting'], ['cooldown', 'casting']),
        ('Not equipped', ['飞行：已关闭', '护符：未装备', '复活：未装备'],
         ['Flight: Disabled', 'Amulet: Not equipped', 'Revive: Not equipped'], [False, False, False],
         ['热视线 [R]：就绪', '吐息 [X]：就绪'], ['Heat [R]: Ready', 'Frost [X]: Ready'], ['ready', 'ready']),
        ('Custom keys / unavailable', ['飞行：骑乘中暂停', '护符：保护生效', '复活：已就绪'],
         ['Flight: Riding', 'Amulet: Protected', 'Revive: Ready'], [False, True, True],
         ['热视线 [G]：不可用', '吐息 [N]：服务器关闭'], ['Heat [G]: Unavailable', 'Frost [N]: Server off'], ['unavailable', 'server_off']),
        ('Local keys off', ['飞行：已开启', '护符：保护生效', '复活：已就绪'],
         ['Flight: Enabled', 'Amulet: Protected', 'Revive: Ready'], [True, True, True],
         ['热视线 [-]：按键关闭', '吐息 [-]：按键关闭'], ['Heat [-]: Key off', 'Frost [-]: Key off'], ['key_off', 'key_off']),
        ('Dark form', ['飞行：已开启', '护符：保护生效', '复活：已就绪'],
         ['Flight: Enabled', 'Amulet: Protected', 'Revive: Ready'], [True, True, True],
         ['热视线 [R]：就绪', '吐息 [X]：就绪'], ['Heat [R]: Ready', 'Frost [X]: Ready'], ['ready', 'ready']),
        ('Syncing', ['飞行：同步中…', '护符：同步中…', '复活：同步中…'],
         ['Flight: Syncing...', 'Amulet: Syncing...', 'Revive: Syncing...'], [False, False, False],
         ['热视线 [R]：同步中…', '吐息 [X]：同步中…'], ['Heat [R]: Syncing...', 'Frost [X]: Syncing...'], ['syncing', 'syncing']),
    ]
    zh_font_path, en_font_path = 'C:/Windows/Fonts/msyh.ttc', 'C:/Windows/Fonts/arial.ttf'
    fonts = [ImageFont.truetype(zh_font_path, 22), ImageFont.truetype(en_font_path, 18)]
    skill_fonts = [ImageFont.truetype(zh_font_path, 18), ImageFont.truetype(en_font_path, 18)]
    titles = [ImageFont.truetype(zh_font_path, 23), ImageFont.truetype(en_font_path, 23)]
    label_font = ImageFont.truetype(en_font_path, 14)
    canvas = Image.new('RGBA', (592, 70 + len(scenarios) * 259), '#34383e')
    draw = ImageDraw.Draw(canvas)
    draw.text((296, 18), 'UI composition preview - not a game screenshot',
              fill='#eeeeee', font=label_font, anchor='mt')
    colors = ['#66c2ff', '#75e897', '#75e897']
    panels = []
    for index, (label, zh, en, enabled, skills_zh, skills_en, states) in enumerate(scenarios):
        top = 70 + index * 259
        for column, texts in enumerate([zh, en]):
            left = 30 + column * 282
            draw.text((left, top - 23), label + (' / ZH' if column == 0 else ' / EN'),
                      fill='#eeeeee', font=label_font)
            draw.rectangle((left, top, left + 249, top + 216), fill=(14, 17, 20, 255))
            draw.text((left + 10, top + 22), '超能力' if column == 0 else 'Abilities',
                      fill='#e8e0c7', font=titles[column], anchor='lm')
            for row, (name, icon) in enumerate(decoded.items()):
                cy = top + 51 + row * 27
                small = icon.resize((28, 28), Image.Resampling.LANCZOS)
                if not enabled[row]:
                    small.putalpha(small.getchannel('A').point(lambda value: round(value * .35)))
                canvas.alpha_composite(small, (left + 10, cy - 14))
                color = colors[row] if enabled[row] else '#a6abb3'
                if index == 1 and row == 2:
                    color = '#ffc963'
                assert draw.textlength(texts[row], font=fonts[column]) <= 196, \
                    f'Preview text overflows row region: {texts[row]}'
                draw.text((left + 44, cy), texts[row], fill=color, font=fonts[column], anchor='lm')
            # Native coordinates y=-77/-104, with the unchanged top edge y=66.
            skill_texts = skills_zh if column == 0 else skills_en
            for row, (text, state) in enumerate(zip(skill_texts, states)):
                assert draw.textlength(text, font=skill_fonts[column]) <= 230, \
                    f'Preview skill text overflows row region: {text}'
                rgba = (117, 232, 151, 255) if state == 'ready' else (
                    (102, 194, 255, 255) if state == 'casting' else (166, 171, 179, 191))
                layer = Image.new('RGBA', canvas.size)
                ImageDraw.Draw(layer).text((left + 10, top + 143 + row * 27), text,
                                           fill=rgba, font=skill_fonts[column], anchor='lm')
                canvas.alpha_composite(layer)
            form_key = 'K' if label == 'Custom keys / unavailable' else ('-' if label == 'Local keys off' else 'H')
            form_dark = label in ('Dark form', 'Casting / cooldown')
            form_state = ('同步中…' if column == 0 else 'Syncing...') if label == 'Syncing' else (
                ('黑暗' if column == 0 else 'Dark') if form_dark else ('正常' if column == 0 else 'Normal'))
            form_text = f'形态 [{form_key}]：{form_state}' if column == 0 else f'Form [{form_key}]: {form_state}'
            assert draw.textlength(form_text, font=skill_fonts[column]) <= 230, \
                f'Preview form text overflows row region: {form_text}'
            form_rgba = (196, 153, 255, 255) if form_dark else (232, 224, 199, 255)
            if label == 'Syncing':
                form_rgba = (166, 171, 179, 255)
            if label in ('Syncing', 'Local keys off', 'Custom keys / unavailable'):
                form_rgba = (*form_rgba[:3], 191)
            layer = Image.new('RGBA', canvas.size)
            ImageDraw.Draw(layer).text((left + 10, top + 197), form_text,
                                      fill=form_rgba, font=skill_fonts[column], anchor='lm')
            canvas.alpha_composite(layer)
            if index == 1:
                panels.append(canvas.crop((left, top, left + 250, top + 217)))
    canvas.convert('RGB').save(PREVIEWS / 'ability-status-ui-composition.png')
    # Show both languages with the longest revival timer and new skill states
    # at all three supported HUD scales. These are decoded UI pixel composites.
    scales = (.8, 1, 1.2)
    scaled = Image.new('RGBA', (846, 636), '#34383e')
    scale_draw = ImageDraw.Draw(scaled)
    scale_draw.text((423, 14), 'UI scale composition: 80% / 100% / 120% (not a game screenshot)',
                    fill='#eeeeee', font=label_font, anchor='mt')
    for column, scale in enumerate(scales):
        x = 24 + sum(round(250 * previous) + 24 for previous in scales[:column])
        for row, panel in enumerate(panels):
            y = 55 + row * 290
            scale_draw.text((x, y - 20), f'{"ZH" if row == 0 else "EN"} {round(scale * 100)}%',
                            fill='#eeeeee', font=label_font)
            scaled.alpha_composite(panel.resize((round(250 * scale), round(217 * scale)),
                                                 Image.Resampling.LANCZOS), (x, y))
    scaled.convert('RGB').save(PREVIEWS / 'ability-status-ui-scale-preview.png')


def compile_assets():
    spec = json.loads((ROOT / 'assets/slices.json').read_text(encoding='utf8'))['hud_icons']
    provenance = json.loads((ROOT / 'assets/source/ui/prompts-and-provenance.json').read_text(encoding='utf8'))
    output = MOD / 'images/abilityicons'
    output.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    decoded, manifest = {}, {'placement': spec, 'icons': {}}
    for name, item in spec['icons'].items():
        path = ROOT / item['source']
        source_bytes = path.read_bytes()
        digest = hashlib.sha256(source_bytes).hexdigest()
        assert digest == provenance['assets'][name]['sha256'], 'Authoritative artwork changed'
        source = Image.open(path).convert('RGBA')
        alpha = source.getchannel('A')
        assert alpha.getextrema() == (0, 255), 'True transparent alpha required'
        bounds = alpha.getbbox()
        assert bounds, 'Empty icon'
        artwork = source.crop(bounds)
        artwork.thumbnail(tuple(spec['fit_size']), Image.Resampling.LANCZOS)
        image = Image.new('RGBA', tuple(spec['size']))
        center = spec['center']
        image.alpha_composite(artwork, (round(center[0] - artwork.width / 2),
                                        round(center[1] - artwork.height / 2)))
        element = item['element']
        assert Path(element).name == element and element.endswith('.tex')
        texture_path = output / element
        data = write_tex(image)
        texture_path.write_bytes(data)
        mip_count = verify_mips(data, image.size)
        texture_path.with_suffix('.xml').write_text(
            f'<Atlas><Texture filename="{element}"/><Elements>'
            f'<Element name="{element}" u1="0" u2="1" v1="0" v2="1"/>'
            '</Elements></Atlas>\n', encoding='utf8', newline='\n')
        icon = read_tex(data)
        assert icon.size == tuple(spec['size']) and icon.getchannel('A').getextrema() == (0, 255)
        assert icon.getchannel('A').getbbox() is not None
        decoded[name] = icon
        manifest['icons'][name] = {
            'source': item['source'], 'sha256': digest, 'alpha_crop': list(bounds),
            'fitted_size': list(artwork.size), 'compiled': texture_path.relative_to(ROOT).as_posix(),
            'size': list(icon.size), 'mipmaps': mip_count,
        }
        assert path.read_bytes() == source_bytes, 'Source pixels were modified'
    preview_icons(decoded)
    preview_hud(decoded)
    (ROOT / 'build/ability-ui-extraction-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print('Compiled 3 unchanged generated icons with full RGBA mipmaps; decoded-icon and bilingual UI composition previews saved.')


if __name__ == '__main__':
    compile_assets()
