"""Extract two user-supplied breath heads; package only owned BILD/KTEX data.

Only edge-connected white paper is removed. Enclosed eye whites remain opaque.
All selections, isotropic scales, chin anchors and mouth anchors are authored in
assets/slices.json. No character pixels, faces or expressions are drawn.
"""
import hashlib
import json
import zipfile

import cv2
import numpy as np
from PIL import Image, ImageDraw

from klei_assets import hash_name, read_build, read_tex, validate_build_symbols, write_build
from paths import MOD, PREVIEWS, ROOT


def matte(path, tolerance):
    """Flood edge-connected near-white JPG paper without erasing eye whites."""
    rgb = np.asarray(Image.open(path).convert("RGB"))
    paper = np.median(np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]), axis=0)
    difference = np.max(np.abs(rgb.astype(float) - paper), axis=2)
    _, labels = cv2.connectedComponents((difference < tolerance).astype(np.uint8), connectivity=4)
    exterior = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    alpha = np.where(np.isin(labels, exterior[exterior != 0]), 0, 255).astype(np.uint8)
    distance = cv2.distanceTransform((alpha > 0).astype(np.uint8), cv2.DIST_L2, 3)
    fringe = (alpha > 0) & (distance < 1.5)
    alpha[fringe] = np.minimum(alpha[fringe], np.clip(difference[fringe] / 80 * 255, 0, 255)).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]))


def local_point(pose, source_point):
    return [pose["local_anchor"][axis] + (source_point[axis] - pose["anchor"][axis]) * pose["scale"]
            for axis in (0, 1)]


def main():
    spec = json.loads((ROOT / "assets/slices.json").read_text(encoding="utf8"))
    config = spec["breath_head"]
    native_frames = config["native_head_frames"]
    assert native_frames == list(range(min(native_frames), max(native_frames) + 1))
    first_frame, duration = native_frames[0], len(native_frames)
    item = spec["sources"]["breath_head"]
    path = ROOT / item["path"]
    source_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    source = matte(path, item["tolerance"])
    art = ROOT / "build/art/frostbreath"
    art.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    source.save(art / "head-source-transparent.png")
    reference_size = item["reference_size"]
    sx, sy = source.width / reference_size[0], source.height / reference_size[1]
    # The extraction and placement use source pixels at their true aspect ratio.
    assert abs(sx - sy) < 1e-6, "Do not stretch the authoritative head artwork"
    manifest = {"source": {**item, "sha256": source_hash, "size": list(source.size)},
                "method": "edge-connected white-paper alpha, polygon selection, uniform scale and placement",
                "native_animation_distributed": False, "parts": {}}
    symbols, sprites = [], {}
    lines = ["-- Generated from assets/slices.json by tools/build_frostbreath_head_assets.py.",
             "return {", "    build = " + json.dumps(config["build"]) + ",", "    poses = {"]
    for pose in config["poses"]:
        selection = spec["selections"][pose["selection"]]
        assert selection["source"] == "breath_head"
        assert selection["reference_size"] == reference_size
        mask = Image.new("L", source.size)
        ImageDraw.Draw(mask).polygon([(round(x * sx), round(y * sy)) for x, y in selection["polygon"]], fill=255)
        alpha = np.minimum(np.asarray(source.getchannel("A")), np.asarray(mask))
        if selection.get("largest_component", True):
            _, components, stats, _ = cv2.connectedComponentsWithStats((alpha > 0).astype(np.uint8), 8)
            assert len(stats) > 1, pose["selection"]
            alpha[components != 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])] = 0
        extracted = source.copy()
        extracted.putalpha(Image.fromarray(alpha))
        box = extracted.getbbox()
        assert box is not None
        extracted = extracted.crop(box)
        extracted.save(art / (pose["selection"] + "-source.png"))
        width = max(1, round(extracted.width / sx * pose["scale"]))
        height = max(1, round(extracted.height / sy * pose["scale"]))
        sprite = extracted.resize((width, height), Image.Resampling.LANCZOS)
        left, top = local_point(pose, [box[0] / sx, box[1] / sy])
        bounds = [left + width / 2, top + height / 2, width, height]
        symbol = pose["symbol"]
        # OverrideSymbol keeps the frame requested by the native animation:
        # front=0, profile=1, back=2 (also for headbase_hat). One image spans
        # that range; a frame-0-only row makes side-facing heads disappear.
        symbols.append({"name": symbol, "hash": hash_name(symbol),
                        "frames": [[first_frame, duration, *bounds, 0, 0]]})
        sprites[(symbol, first_frame)] = sprite
        sprite.save(art / (pose["selection"] + ".png"))
        mouth = local_point(pose, pose["mouth_point"])
        assert left < mouth[0] < left + width and top < mouth[1] < top + height
        manifest["parts"][pose["pose"]] = {"selection": selection, "placement": pose, "source_crop": list(box),
                                            "compiled_bounds": bounds, "local_mouth": mouth,
                                            "native_head_frames": native_frames}
        lines.append("        %s = { symbol = %s, mouth = { %.6f, %.6f } }," %
                     (pose["pose"], json.dumps(symbol), *mouth))
    lines.extend(["    },", "}"])
    (MOD / "scripts/krypton_frostbreath_head_data.lua").write_text("\n".join(lines) + "\n", encoding="utf8")
    archive = MOD / config["archive"]
    atlas = write_build(config["build"], symbols, sprites, archive, config["atlas_size"])
    atlas.save(PREVIEWS / "frostbreath-head-atlas.png")
    with zipfile.ZipFile(archive) as package:
        assert set(package.namelist()) == {"build.bin", "atlas-0.tex"}, "Never package native animation data"
        compiled = read_build(package.read("build.bin"))
        texture = read_tex(package.read("atlas-0.tex"))
    validate_build_symbols(compiled)
    assert compiled["name"] == config["build"]
    assert len(compiled["symbols"]) == 2
    assert texture.size == (config["atlas_size"], config["atlas_size"])
    for symbol in compiled["symbols"]:
        assert len(symbol["frames"]) == 1
        row = symbol["frames"][0]
        assert all(row[0] <= frame < row[0] + row[1] for frame in native_frames), \
            "Every head override must cover native front/profile/back frame requests"
    # Opaque white source eyes must survive edge-connected white-paper removal.
    assert source.getpixel((240, 410))[3] == 255
    assert source.getpixel((1168, 406))[3] == 255
    assert source.getpixel((10, 10))[3] == 0
    assert hashlib.sha256(path.read_bytes()).hexdigest() == source_hash
    manifest["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
    (ROOT / "build/frostbreath-head-extraction-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print("Compiled two supplied breath heads, preserved enclosed eye whites and emitted shared mouth anchors; no native animation distributed.")
    print(archive)


if __name__ == "__main__":
    main()
