"""Pixel/geometry preview of eye anchors; this is not an in-game camera capture.

Only compiled user artwork and native installed-game FX pixels are composited.
Native archives are read in memory and never copied into the distributable mod.
The contact sheet crops the beams near their origins; JSON records full extents.
"""
from pathlib import Path
import argparse
import json
import math
import os
import re
import zipfile

from PIL import Image

from klei_assets import crop_symbol, read_anim, read_build, read_tex
from paths import ROOT, PREVIEWS


SIZE = (640, 480)
ORIGIN = (320, 400)
BACKGROUND = (224, 218, 199, 255)
IDENTITY = (1, 0, 0, 1, 0, 0)
HALO = ((1, .04, .01, .8), (.6, 0, 0, 0))
CORE = ((1, .7, .3, .95), (.3, .05, 0, 0))
SPARK = ((1, .15, .05, .9), (.6, .04, 0, 0))


def load_archive(path, animation=True):
    with zipfile.ZipFile(path) as archive:
        build = read_build(archive.read("build.bin"))
        atlases = [read_tex(archive.read(name)) for name in build["textures"]]
        animations, names = read_anim(archive.read("anim.bin")) if animation else ([], {})
    sprites = {}
    for symbol in build["symbols"]:
        for row in symbol["frames"]:
            sprites[(symbol["hash"], row[0])] = (
                crop_symbol(build, atlases, symbol, row[0]), row
            )
    return {"build": build, "sprites": sprites, "animations": animations, "names": names}


def load_motion(path):
    with zipfile.ZipFile(path) as archive:
        animations, names = read_anim(archive.read("anim.bin"))
    return {"animations": animations, "names": names}


def sprite_for(data, hashed, frame):
    found = data["sprites"].get((hashed, frame))
    if found is not None:
        return found
    symbol = next(symbol for symbol in data["build"]["symbols"] if symbol["hash"] == hashed)
    row = next((row for row in symbol["frames"] if row[0] <= frame < row[0] + row[1]), None)
    if row is None:
        return None  # Native builds can contain intentionally empty symbol frames.
    return data["sprites"][(hashed, row[0])]


def multiply(outer, inner):
    a, b, c, d, tx, ty = outer
    e, f, g, h, ux, uy = inner
    return (a*e+c*f, b*e+d*f, a*g+c*h, b*g+d*h, a*ux+c*uy+tx, b*ux+d*uy+ty)


def point(matrix, xy):
    a, b, c, d, tx, ty = matrix
    x, y = xy
    return (a*x+c*y+tx, b*x+d*y+ty)


def shade(image, colors):
    """Apply the runtime RGB multiply/add and alpha multiply to existing pixels."""
    mult, add = colors
    return Image.merge("RGBA", tuple(
        channel.point(lambda value, m=mult[index], a=add[index]:
                      round(min(255, max(0, value*m + (255*a if index < 3 else 0)))))
        for index, channel in enumerate(image.split())
    ))


def warp(canvas, image, row, matrix):
    a, b, c, d, tx, ty = matrix
    det = a*d-b*c
    if abs(det) < .00001:
        return
    left, top = row[2]-row[4]/2, row[3]-row[5]/2
    inverse = (d/det, -c/det, (-d*tx+c*ty)/det-left,
               -b/det, a/det, (b*tx-a*ty)/det-top)
    canvas.alpha_composite(image.transform(canvas.size, Image.Transform.AFFINE,
                                           inverse, Image.Resampling.BICUBIC))


def render_fx(canvas, data, animation, frame, outer=IDENTITY, colors=None):
    for element in sorted(animation["frames"][frame % len(animation["frames"])]
                          ["elements"], key=lambda element: element[9], reverse=True):
        sprite = sprite_for(data, element[0], element[1])
        if sprite is None:
            continue
        image, row = sprite
        if colors is not None:
            image = shade(image, colors)
        warp(canvas, image, row, multiply(outer, element[3:9]))


def eye_offsets(spec, pose):
    layout = spec["heatvision"]["eyes"][pose]
    source = layout.get("inherit", pose)
    config = spec["placement"]["head"][source]
    return [(config["local_anchor"][0] + (x-config["anchor"][0])*config["scale"],
             config["local_anchor"][1] + (y-config["anchor"][1])*config["scale"])
            for x, y in spec["heatvision"]["eyes"][source]["source_points"]]


def character_scene(character, native_names, animation, frame, mirrored=False):
    canvas = Image.new("RGBA", SIZE)
    scene = (-1 if mirrored else 1, 0, 0, 1, *ORIGIN)
    head = None
    for element in sorted(animation["frames"][frame]["elements"],
                          key=lambda element: element[9], reverse=True):
        name = native_names.get(element[0])
        layer = native_names.get(element[2])
        if layer == "ARM_carry" or name in ("headbase_hat", "hair_hat"):
            continue
        sprite = character["sprites"].get((element[0], element[1]))
        if sprite is None:
            continue
        matrix = multiply(scene, element[3:9])
        warp(canvas, *sprite, matrix)
        if name == "headbase":
            head = matrix
    assert head is not None, "Native animation has no visible headbase symbol"
    return canvas, head


def measure_beam(beam, animation):
    bounds = []
    for frame in range(len(animation["frames"])):
        canvas = Image.new("RGBA", (512, 256))
        render_fx(canvas, beam, animation, frame, (1, 0, 0, 1, 256, 128))
        bbox = canvas.getchannel("A").getbbox()
        assert bbox is not None
        bounds.append([bbox[0]-256, bbox[1]-128, bbox[2]-256, bbox[3]-128])
    return bounds


def scene(character, names, animation, frame, pose, spec, beam, beam_animation,
          spark, spark_animation, beam_range, mirrored=False):
    character_pixels, head = character_scene(character, names, animation, frame, mirrored)
    canvas = Image.new("RGBA", SIZE, BACKGROUND)
    # This orthographic diagram chooses a screen direction per pose. It is not
    # an approximation of the game's observer camera or OnGround projection.
    direction = {"front": (0, 1), "side": (-1 if mirrored else 1, 0), "back": (0, -1)}[pose]
    dx, dy = direction
    config = spec["heatvision"]["beam"]
    scale = beam_range*config["pixels_per_unit"]/(config["right"]-config["left"])
    advance = -config["left"]*scale
    eyes = [point(head, offset) for offset in eye_offsets(spec, pose)]
    beams = Image.new("RGBA", SIZE)
    glows = Image.new("RGBA", SIZE)
    for x, y in eyes:
        root_x, root_y = x+dx*advance, y+dy*advance
        for width, colors in [(config["glow_width"], HALO), (config["core_width"], CORE)]:
            matrix = (dx*scale, dy*scale, -dy*width, dx*width, root_x, root_y)
            render_fx(beams, beam, beam_animation, frame, matrix, colors)
        if spec["heatvision"]["eyes"][pose]["glow"]:
            glow_scale = config["eye_glow_scale"]
            render_fx(glows, spark, spark_animation, frame,
                      (glow_scale, 0, 0, glow_scale, x, y), SPARK)
    if pose == "back":
        # The eyes are occluded by the back-of-head artwork. No eye glow is
        # drawn; the beams remain visible after they clear the character.
        canvas.alpha_composite(beams)
        canvas.alpha_composite(character_pixels)
    else:
        canvas.alpha_composite(character_pixels)
        canvas.alpha_composite(beams)
    canvas.alpha_composite(glows)
    return canvas, {"eyes": eyes, "direction": direction, "head_matrix": head,
                    "visible_eye_glows": len(eyes) if pose != "back" else 0,
                    "full_beam_length_pixels": beam_range*config["pixels_per_unit"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, default=Path(os.environ.get(
        "DST_GAME_DIR", r"D:\SteamLibrary\steamapps\common\Don't Starve Together")))
    args = parser.parse_args()
    game = args.game_dir/"data/anim"
    spec = json.loads((ROOT/"assets/slices.json").read_text(encoding="utf8"))
    tuning = (ROOT/"mod/modmain.lua").read_text(encoding="utf8")
    beam_range = float(re.search(r"heatvision_range\s*=\s*([\d.]+)", tuning).group(1))
    character = load_archive(ROOT/"mod/anim/krypton_survivor.zip", animation=False)
    native = [load_motion(game/name) for name in ("player_basic.zip", "player_idles.zip")]
    animations = [animation for data in native for animation in data["animations"]]
    names = {key: name for data in native for key, name in data["names"].items()}
    beam = load_archive(game/"wagdrone_laserwire_fx.zip")
    spark = load_archive(game/"bishop_attack.zip")
    beam_animation = next(animation for animation in beam["animations"] if animation["name"] == "beam_straight")
    spark_animation = next(animation for animation in spark["animations"] if animation["name"] == "shot_fx")
    native_bounds = measure_beam(beam, beam_animation)
    config = spec["heatvision"]["beam"]
    assert min(bounds[0] for bounds in native_bounds) >= config["left"]
    assert max(bounds[2] for bounds in native_bounds) <= config["right"]
    scale = beam_range*config["pixels_per_unit"]/(config["right"]-config["left"])
    starts = [(bounds[0]-config["left"])*scale for bounds in native_bounds]
    ends = [(bounds[2]-config["left"])*scale for bounds in native_bounds]
    assert min(starts) >= 0, "Native beam extends behind the eye"
    assert max(ends) <= beam_range*config["pixels_per_unit"]
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    poses = [("front", 8, False), ("side_right", 5, False),
             ("side_left", 5, True), ("back", 2, False)]
    contact = Image.new("RGBA", (SIZE[0]*4, SIZE[1]*2), BACKGROUND)
    report = {"notice": "Pixel/geometry preview; not an actual in-game client camera capture.",
              "layout": "Rows: idle_loop, run_loop. Columns: front, side RIGHT, side LEFT, back.",
              "beam_visibility": "Contact sheet crops the beam near the eye; full range is validated numerically.",
              "diagram_projection": "Orthographic front/down, side/horizontal, back/up. Back roots are occluded by character pixels. Actual camera projection and bloom are not simulated.",
              "range_units": beam_range, "native_beam_frames": native_bounds,
              "beam_start_pixels_ahead_of_eye": [min(starts), max(starts)],
              "beam_end_pixels_ahead_of_eye": [min(ends), max(ends)],
              "head_local_eyes": {pose: eye_offsets(spec, pose) for pose in ("front", "side", "back")},
              "poses": {}}
    all_frames = []
    for row, action in enumerate(("idle_loop", "run_loop")):
        for column, (label, facing, mirrored) in enumerate(poses):
            animation = next(animation for animation in animations if animation["name"] == action and animation["facing"] == facing)
            pose = label.split("_")[0]
            records = []
            frames = []
            for frame in range(len(animation["frames"])):
                image, record = scene(character, names, animation, frame, pose, spec,
                                      beam, beam_animation, spark, spark_animation, beam_range, mirrored)
                frames.append(image)
                records.append(record)
            contact.alpha_composite(frames[0], (column*SIZE[0], row*SIZE[1]))
            report["poses"][f"{action}:{label}"] = records
            frames[0].convert("RGB").save(PREVIEWS/f"heatvision-{action}-{label}.gif", save_all=True,
                append_images=[image.convert("RGB") for image in frames[1:]],
                duration=round(1000/animation["rate"]), loop=0)
            all_frames.append((action, label, frames))
    contact.convert("RGB").save(PREVIEWS/"heatvision-eyes.png")
    # Every native pose frame is also exposed in compact contact sheets.
    for action, label, frames in all_frames:
        sheet = Image.new("RGBA", (SIZE[0]*4, SIZE[1]*math.ceil(len(frames)/4)), BACKGROUND)
        for index, image in enumerate(frames):
            sheet.alpha_composite(image, ((index % 4)*SIZE[0], (index//4)*SIZE[1]))
        sheet.convert("RGB").save(PREVIEWS/f"heatvision-{action}-{label}-all.png")
    (PREVIEWS/"heatvision-eyes.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print("Pixel/geometry preview only; this is not an actual in-game client camera capture.")
    print(f"Eye layout: front 2, side 1, back 0 eye glows. All {sum(len(frames) for _, _, frames in all_frames)} native pose frames rendered.")
    print(f"Native beam starts {min(starts):.3f}-{max(starts):.3f}px ahead of eye; ends {min(ends):.3f}-{max(ends):.3f}px ahead. No beam pixels extend behind eye.")
    print(PREVIEWS/"heatvision-eyes.png")


if __name__ == "__main__":
    main()
