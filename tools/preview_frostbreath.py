"""Inspect compiled mouth anchors using native motion and existing ice pixels.

This is an orthographic pixel/geometry diagram, not an in-game screenshot.
It composites the mod's compiled character and installed-game ice crystals.
The installed frostbreath texture and envelope metadata are read for auditing;
the engine's GPU mist, bloom, depth sorting and camera are not simulated.
Native source/animation/texture archives are read in memory and never copied.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import zipfile

from PIL import Image, ImageDraw, ImageFont

from klei_assets import read_tex
from paths import ROOT, PREVIEWS
from preview_heatvision import (
    BACKGROUND, ORIGIN, character_scene, load_archive, load_motion,
    multiply, point, render_fx,
)


WORLD_SIZE = (1536, 1536)
OUTPUT_SIZE = (768, 768)
LABEL_HEIGHT = 62
POSES = (
    ("front", 8, False, (0, 1), (768, 390)),
    ("side_right", 5, False, (1, 0), (180, 900)),
    ("side_left", 5, True, (-1, 0), (1356, 900)),
    ("back", 2, False, (0, -1), (768, 1470)),
)
NOTICE = "Compiled-pixel diagram; not an in-game screenshot. GPU mist is not simulated."


def local_mouth(spec, pose):
    """Use the same source-to-head mapping as the generated runtime data."""
    layout = spec["frostbreath"]["mouth_points"][pose]
    source = layout.get("inherit", pose)
    source_point = spec["frostbreath"]["mouth_points"][source]["source_point"]
    config = spec["placement"]["head"][source]
    return [config["local_anchor"][axis]
            + (source_point[axis] - config["anchor"][axis]) * config["scale"]
            for axis in (0, 1)]


def read_native_mist(game):
    texture_path = game / "data/fx/frostbreath.tex"
    texture = read_tex(texture_path.read_bytes())
    archive_path = game / "data/databundles/scripts.zip"
    source_name = "scripts/prefabs/frostbreath.lua"
    with zipfile.ZipFile(archive_path) as archive:
        source = archive.read(source_name).decode("utf8")
    colours = [
        [float(time), [int(r), int(g), int(b), int(a)]]
        for time, r, g, b, a in re.findall(
            r"\{\s*([\d.]+)\s*,\s*IntColour\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", source)
    ]
    return {
        "texture_path": str(texture_path),
        "texture_dimensions": list(texture.size),
        "texture_alpha_bounds": list(texture.getchannel("A").getbbox()),
        "native_script_archive": str(archive_path),
        "native_script_member": source_name,
        "colour_envelope_rgba_255": colours,
        "scale_envelope_start": float(re.search(r"local min_scale\s*=\s*([\d.]+)", source)[1]),
        "scale_envelope_end": float(re.search(r"local max_scale\s*=\s*([\d.]+)", source)[1]),
        "native_max_lifetime_seconds": float(re.search(r"local MAX_LIFETIME\s*=\s*([\d.]+)", source)[1]),
        "runtime_particle_lifetime_seconds": 0.65,
        "runtime_emission_limit_per_update": 2,
        "native_pixels_exported_separately": False,
        "gpu_mist_simulated": False,
    }


def font(size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def scene(character, names, animation, native_frame, label, pose, mirrored,
          direction, origin, spec, flakes, flake_animation, elapsed,
          breath_range, half_angle):
    character_pixels, head = character_scene(character, names, animation, native_frame, mirrored)
    offset = (origin[0] - ORIGIN[0], origin[1] - ORIGIN[1])
    head = multiply((1, 0, 0, 1, *offset), head)
    mouth = point(head, local_mouth(spec, pose))
    canvas = Image.new("RGBA", WORLD_SIZE, BACKGROUND)
    character_layer = Image.new("RGBA", WORLD_SIZE)
    character_layer.alpha_composite(character_pixels, offset)
    ice_layer = Image.new("RGBA", WORLD_SIZE)
    dx, dy = direction
    pixels_per_unit = spec["frostbreath"]["pixels_per_unit"]
    records = []
    for index in range(8):
        phase = (elapsed / 0.65 + index / 8) % 1
        lane = (index % 3 - 1) * 0.65
        forward = phase * breath_range * pixels_per_unit
        lateral = math.tan(math.radians(half_angle)) * forward * lane
        x = mouth[0] + dx * forward - dy * lateral
        y = mouth[1] + dy * forward + dx * lateral
        scale = 0.12 + phase * 0.22
        alpha = math.sin(phase * math.pi) * 0.65
        # Native crystals occupy a small patch. Transforming a full 1536px
        # canvas for each sprite would make the diagnostic unnecessarily slow.
        patch = Image.new("RGBA", (512, 512))
        px, py = math.floor(x), math.floor(y)
        render_fx(patch, flakes, flake_animation, native_frame,
                  (scale, 0, 0, scale, 256 + x - px, 256 + y - py),
                  ((0.68, 0.9, 1, alpha), (0, 0, 0, 0)))
        bounds = patch.getchannel("A").getbbox()
        assert bounds is None or (bounds[0] > 0 and bounds[1] > 0 and bounds[2] < 512 and bounds[3] < 512), "Crystal patch clips native pixels"
        ice_layer.alpha_composite(patch, (px - 256, py - 256))
        records.append({"phase": phase, "lane": lane, "position": [x, y], "scale": scale})
    if pose == "back":
        canvas.alpha_composite(ice_layer)
        canvas.alpha_composite(character_layer)
    else:
        canvas.alpha_composite(character_layer)
        canvas.alpha_composite(ice_layer)

    # These are diagram annotations, not new character or weapon artwork.
    annotations = ImageDraw.Draw(canvas)
    x, y = mouth
    annotations.ellipse((x - 6, y - 6, x + 6, y + 6), outline=(0, 120, 160, 255), width=2)
    output = canvas.resize(OUTPUT_SIZE, Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(output)
    draw.rectangle((0, 0, OUTPUT_SIZE[0], LABEL_HEIGHT), fill=BACKGROUND)
    draw.text((12, 8), f"{animation['name']} / {label} / {elapsed:.2f}s", font=font(21), fill=(40, 40, 40))
    draw.text((12, 36), "Native crystal pixels only; cyan circle = mouth anchor", font=font(17), fill=(35, 85, 105))
    # A close-up retains useful face scale while the main diagram shows all
    # eight units. It is a literal crop of the same compiled character pixels.
    closeup = canvas.crop((round(x - 150), round(y - 190), round(x + 150), round(y + 110)))
    closeup = closeup.resize((240, 240), Image.Resampling.LANCZOS)
    if label == "side_right":
        inset = (16, OUTPUT_SIZE[1] - 258)
    elif label == "side_left":
        inset = (OUTPUT_SIZE[0] - 256, OUTPUT_SIZE[1] - 258)
    else:
        inset = (16, LABEL_HEIGHT + 10)
    output.alpha_composite(closeup, inset)
    draw.rectangle((inset[0], inset[1], inset[0] + 240, inset[1] + 240), outline=(100, 115, 115), width=1)
    record = {
        "elapsed_seconds": elapsed,
        "native_motion_frame": native_frame,
        "source_local_mouth": local_mouth(spec, pose),
        "mouth_on_full_canvas": list(mouth),
        "head_matrix": list(head),
        "orthographic_direction": list(direction),
        "full_range_pixels": breath_range * pixels_per_unit,
        "crystals": records,
    }
    return output, record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, default=Path(os.environ.get(
        "DST_GAME_DIR", r"D:\SteamLibrary\steamapps\common\Don't Starve Together")))
    args = parser.parse_args()
    game = args.game_dir
    spec_path = ROOT / "assets/slices.json"
    spec = json.loads(spec_path.read_text(encoding="utf8"))
    main_source = (ROOT / "mod/modmain.lua").read_text(encoding="utf8")
    def tuning(name, default):
        match = re.search(rf"{name}\s*=\s*([\d.]+)", main_source)
        return float(match[1]) if match else default
    breath_range = tuning("frostbreath_range", 8)
    half_angle = tuning("frostbreath_half_angle", 28)
    duration = tuning("frostbreath_duration", 1)
    character_path = ROOT / "mod/anim/krypton_survivor.zip"
    character = load_archive(character_path, animation=False)
    motion_paths = [game / "data/anim" / name for name in ("player_basic.zip", "player_idles.zip")]
    motion = [load_motion(path) for path in motion_paths]
    animations = [animation for data in motion for animation in data["animations"]]
    names = {key: value for data in motion for key, value in data["names"].items()}
    flakes_path = game / "data/anim/deer_ice_flakes.zip"
    flakes = load_archive(flakes_path)
    flake_animation = next(animation for animation in flakes["animations"] if animation["name"] == "loop")
    report = {
        "notice": NOTICE,
        "layout": "Rows: idle_loop, run_loop. Columns: front, side right, side left mirrored, back.",
        "projection": "Orthographic front/down, sides/horizontal, back/up; not the game's camera projection.",
        "limitations": [
            "GPU frostbreath particle mist, its depth sorting, bloom and camera rotation are not simulated.",
            "Blue circles are anchor annotations, not replacement mouth artwork.",
            "Inset panels are enlarged crops of the same compiled pixels.",
            "Back plume roots are occluded by compiled back-of-head pixels.",
            "A body native idle/run pose is shown; no new open-mouth or dedicated breath pose has been drawn.",
        ],
        "sources": {
            "authoritative_placements": str(spec_path),
            "compiled_character": str(character_path),
            "compiled_character_sha256": hashlib.sha256(character_path.read_bytes()).hexdigest(),
            "native_motions": [str(path) for path in motion_paths],
            "native_crystals": str(flakes_path),
        },
        "range_units": breath_range,
        "half_angle_degrees": half_angle,
        "duration_seconds": duration,
        "head_local_mouths": {pose: local_mouth(spec, pose) for pose in ("front", "side", "back")},
        "native_mist_metadata": read_native_mist(game),
        "full_canvas_size": list(WORLD_SIZE),
        "output_cell_size": list(OUTPUT_SIZE),
        "poses": {},
    }
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (OUTPUT_SIZE[0] * 4, OUTPUT_SIZE[1] * 2 + 44), BACKGROUND)
    ImageDraw.Draw(sheet).text((12, 10), NOTICE, font=font(21), fill=(45, 45, 45))
    rendered = 0
    for row, action in enumerate(("idle_loop", "run_loop")):
        for column, (label, facing, mirrored, direction, origin) in enumerate(POSES):
            animation = next(animation for animation in animations if animation["name"] == action and animation["facing"] == facing)
            frames, records = [], []
            frame_count = max(1, math.ceil(animation["rate"] * duration))
            for index in range(frame_count):
                image, record = scene(character, names, animation, index % len(animation["frames"]),
                                      label, label.split("_")[0], mirrored, direction, origin, spec,
                                      flakes, flake_animation, index / animation["rate"], breath_range, half_angle)
                frames.append(image.convert("RGB"))
                records.append(record)
            contact_index = min(len(frames) - 1, round(animation["rate"] * 0.25))
            sheet.alpha_composite(frames[contact_index].convert("RGBA"), (column * OUTPUT_SIZE[0], row * OUTPUT_SIZE[1] + 44))
            frames[0].save(PREVIEWS / f"frostbreath-{action}-{label}.gif", save_all=True,
                           append_images=frames[1:], duration=round(1000 / animation["rate"]), loop=0)
            report["poses"][f"{action}:{label}"] = records
            rendered += len(frames)
    sheet.convert("RGB").save(PREVIEWS / "frostbreath-mouths.png")
    (PREVIEWS / "frostbreath-mouths.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print(NOTICE)
    print(f"Rendered {rendered} compiled motion frames and 8 native-crystal GIFs; all {breath_range:g} range units included.")
    print(PREVIEWS / "frostbreath-mouths.png")


if __name__ == "__main__":
    main()
