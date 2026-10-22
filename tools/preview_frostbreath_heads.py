"""Inspect supplied breath heads over compiled bodies and native idle/run motion.

Only existing character/axe pixels and installed ice-crystal pixels are composited.
The contact sheet is an orthographic geometry diagnostic, not a game screenshot;
GPU mist, bloom and the real client camera are not simulated. Native files are
read in memory, never copied into the distributable mod or exported as assets.
"""
import hashlib
import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from klei_assets import hash_name
from paths import MOD, PREVIEWS, ROOT, game_anim_dir
from preview_heatvision import BACKGROUND, ORIGIN, SIZE, load_archive, load_motion, multiply, point, render_fx, sprite_for, warp


POSES = (("front", 8, False, (0, 1)), ("side_right", 5, False, (1, 0)),
         ("side_left", 5, True, (-1, 0)), ("back", 2, False, (0, -1)))


def font(size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def old_mouth(spec, pose):
    layout = spec["frostbreath"]["mouth_points"][pose]
    source = layout.get("inherit", pose)
    head = spec["placement"]["head"][source]
    mouth = spec["frostbreath"]["mouth_points"][source]["source_point"]
    return [head["local_anchor"][axis] + (mouth[axis] - head["anchor"][axis]) * head["scale"] for axis in (0, 1)]


def required_head_sprite(data, symbol, native_frame, context):
    """Resolve the actual ANIM frame through BILD ranges, as the engine does.

    A symbol override changes the build/symbol, not the native frame request.
    In particular, a profile requests frame 1 even when its replacement has
    only one source image. Never substitute frame 0 for an uncovered request.
    """
    hashed = hash_name(symbol)
    definition = next((row for row in data["build"]["symbols"] if row["hash"] == hashed), None)
    if definition is None:
        raise AssertionError(f"{context}: missing head symbol {symbol}")
    source = next((row for row in definition["frames"]
                   if row[0] <= native_frame < row[0] + row[1]), None)
    if source is None:
        ranges = [(row[0], row[0] + row[1] - 1) for row in definition["frames"]]
        raise AssertionError(f"{context}: {symbol} cannot resolve native head frame {native_frame}; "
                             f"compiled source ranges are {ranges}")
    sprite = sprite_for(data, hashed, native_frame)
    if sprite is None or sprite[0].getchannel("A").getbbox() is None:
        raise AssertionError(f"{context}: {symbol} frame {native_frame} has no visible pixels")
    return sprite, {"native_head_frame": native_frame, "resolved_source_symbol": symbol,
                    "resolved_source_frame": source[0], "resolved_source_duration": source[1]}


def validate_native_head_coverage(game, config, heads):
    """Audit every locally installed allowed clip, including hat-head requests.

    Animation data stays in memory. The report contains only names, frame ids,
    range resolutions and counts, never native animation files or artwork.
    """
    runtime = (MOD / "scripts/krypton_frostbreath_head_visual.lua").read_text(encoding="utf8")
    whitelist = re.search(r"local LOOPS\s*=\s*\{(.*?)\}", runtime, re.S)
    assert whitelist is not None, "Runtime breath animation whitelist was not found"
    allowed = set(re.findall(r'"([a-z0-9_]+)"', whitelist.group(1)))
    declared = set(config["native_head_frames"])
    found, records, paths = set(), [], []
    for path in sorted(game.glob("player*.zip")):
        try:
            motion = load_motion(path)
        except KeyError:
            # Some player-prefixed archives contain only a build.
            continue
        matched = [clip for clip in motion["animations"] if clip["name"] in allowed]
        if not matched:
            continue
        paths.append(str(path))
        for clip in matched:
            found.add(clip["name"])
            requests = {}
            for frame in clip["frames"]:
                for element in frame["elements"]:
                    target = motion["names"].get(element[0])
                    if target in ("headbase", "headbase_hat"):
                        requests[(target, element[1])] = requests.get((target, element[1]), 0) + 1
            for (target, requested), count in sorted(requests.items()):
                context = f"{path.name}:{clip['name']}:facing={clip['facing']}:{target}"
                assert requested in declared, f"{context}: undeclared native head frame {requested}"
                resolutions = []
                # Both runtime overrides must cover every supported native
                # request, including camera/facing changes between updates.
                for pose in config["poses"]:
                    _, record = required_head_sprite(heads, pose["symbol"], requested, context)
                    resolutions.append(record)
                records.append({"archive": path.name, "animation": clip["name"],
                                "facing": clip["facing"], "target_symbol": target,
                                "native_head_frame": requested, "element_count": count,
                                "override_resolutions": resolutions})
    assert found == allowed, f"Allowed breath animations missing from installed game: {sorted(allowed - found)}"
    assert {row["native_head_frame"] for row in records} == declared, \
        "Declared head frame requests do not match installed allowed clips"
    assert {row["target_symbol"] for row in records} == {"headbase", "headbase_hat"}
    return {"allowed_animation_names": sorted(allowed), "native_head_frames": sorted(declared),
            "validated_head_elements": sum(row["element_count"] for row in records),
            "native_inputs_read_only": paths, "records": records}


def main():
    game = game_anim_dir()
    spec = json.loads((ROOT / "assets/slices.json").read_text(encoding="utf8"))
    config = spec["breath_head"]
    source = ROOT / spec["sources"]["breath_head"]["path"]
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    config_poses = {pose["pose"]: pose for pose in config["poses"]}
    character = load_archive(MOD / "anim/krypton_survivor.zip", animation=False)
    heads = load_archive(MOD / config["archive"], animation=False)
    axe = load_archive(MOD / "anim/krypton_staff_build.zip", animation=False)
    axe_sprite = axe["sprites"][(hash_name("swap_cane"), 0)]
    native = [load_motion(game / name) for name in ("player_basic.zip", "player_idles.zip")]
    animations = [animation for data in native for animation in data["animations"]]
    names = {key: name for data in native for key, name in data["names"].items()}
    flakes = load_archive(game / "deer_ice_flakes.zip")
    flake_animation = next(animation for animation in flakes["animations"] if animation["name"] == "loop")
    report = {"notice": "Compiled-pixel geometry diagnostic, not an in-game screenshot. GPU mist is not simulated.",
              "layout": "Rows: idle normal / idle breath / run normal / run breath. Columns: front / side right / side left / back.",
              "source_sha256": source_hash, "compiled_head_archive": str(MOD / config["archive"]),
              "native_inputs_read_only": [str(game / path) for path in ("player_basic.zip", "player_idles.zip", "deer_ice_flakes.zip")],
              "native_files_distributed": False, "poses": {}}
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    cell = (448, 336)
    sheet = Image.new("RGB", (cell[0] * 4, cell[1] * 4 + 40), BACKGROUND[:3])
    ImageDraw.Draw(sheet).text((10, 10), report["notice"], font=font(17), fill=(35, 50, 55))

    def render(animation, index, label, mirrored, direction, breathing,
               aim_degrees=None, overlay_crystals=False):
        pose = label.split("_")[0]
        canvas = Image.new("RGBA", SIZE, BACKGROUND)
        character_layer = Image.new("RGBA", SIZE)
        scene = (-1 if mirrored else 1, 0, 0, 1, *ORIGIN)
        head_matrix, mouth, chosen = None, None, None
        head_records = []
        for element in sorted(animation["frames"][index % len(animation["frames"])]
                              ["elements"], key=lambda element: element[9], reverse=True):
            name, layer = names.get(element[0]), names.get(element[2])
            sprite = sprite_for(character, element[0], element[1]) if element[0] in character["build"]["names"] else None
            if name == "swap_object":
                sprite = axe_sprite
            if name in ("headbase", "headbase_hat"):
                if breathing and pose != "back":
                    chosen = config_poses[pose]
                    sprite, record = required_head_sprite(heads, chosen["symbol"], element[1],
                                                          f"{animation['name']}:{label}:{name}")
                else:
                    sprite, record = required_head_sprite(character, name, element[1],
                                                          f"{animation['name']}:{label}:{name}")
                record["target_symbol"] = name
                head_records.append(record)
            # Both native head variants above must resolve even though only
            # headbase is composited for this normal, non-hat diagnostic.
            if layer == "ARM_normal" or name in ("headbase_hat", "hair_hat"):
                continue
            if name == "headbase":
                head_matrix = multiply(scene, element[3:9])
                if breathing and pose != "back":
                    local_mouth = [chosen["local_anchor"][axis] +
                                   (chosen["mouth_point"][axis] - chosen["anchor"][axis]) * chosen["scale"]
                                   for axis in (0, 1)]
                else:
                    local_mouth = old_mouth(spec, pose)
                mouth = point(head_matrix, local_mouth)
            if sprite is not None:
                warp(character_layer, *sprite, multiply(scene, element[3:9]))
        assert head_matrix is not None and mouth is not None, "Native headbase must remain visible"
        crystals = Image.new("RGBA", SIZE)
        crystal_records = []
        if breathing:
            dx, dy = direction
            for lane in range(3):
                phase = (index / 18 + lane / 3) % 1
                distance = 12 + phase * 150
                spread = (lane - 1) * (6 + phase * 22)
                x = mouth[0] + dx * distance - dy * spread
                y = mouth[1] + dy * distance + dx * spread
                scale = .11 + phase * .12
                render_fx(crystals, flakes, flake_animation, index,
                          (scale, 0, 0, scale, x, y), ((.68, .9, 1, .6), (0, 0, 0, 0)))
                crystal_records.append({"position_canvas": [x, y], "forward_pixels": distance,
                                        "lateral_pixels": spread, "source": "native ice pixels"})
        if pose == "back" and not overlay_crystals:
            canvas.alpha_composite(crystals)
            canvas.alpha_composite(character_layer)
        else:
            canvas.alpha_composite(character_layer)
            canvas.alpha_composite(crystals)
        draw = ImageDraw.Draw(canvas)
        if breathing and pose != "back":
            x, y = mouth
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), outline=(0, 120, 170), width=1)
        title = f"{animation['name']} / {label} / {'breath' if breathing else 'normal'}"
        if aim_degrees is not None:
            title = f"Server aim {aim_degrees:03d} deg / rendered {label}"
        draw.text((12, 12), title,
                  font=font(20), fill=(35, 50, 55))
        draw.text((12, 40), "Cyan circle = calibrated mouth; held axe uses existing compiled pixels",
                  font=font(15), fill=(35, 65, 80))
        record = {"native_frame": index % len(animation["frames"]), "breathing": breathing,
                  "head_override": chosen["symbol"] if chosen else None,
                  "mouth_canvas": list(mouth), "head_matrix": list(head_matrix),
                  "head_symbol_frames": head_records,
                  "emission_direction_projected": list(direction),
                  "crystals": crystal_records}
        record.update(next(item for item in head_records if item["target_symbol"] == "headbase"))
        return canvas.convert("RGB").resize(cell, Image.Resampling.LANCZOS), record

    rendered = 0
    for action_index, action in enumerate(("idle_loop", "run_loop")):
        for column, (label, facing, mirrored, direction) in enumerate(POSES):
            animation = next(animation for animation in animations if animation["name"] == action and animation["facing"] == facing)
            frames, records = [], []
            for index in range(36):
                breathing = 3 <= index < 33
                image, record = render(animation, index, label, mirrored, direction, breathing)
                frames.append(image)
                records.append(record)
            for state, index in enumerate((0, 10)):
                image, _ = render(animation, 0, label, mirrored, direction, bool(state))
                sheet.paste(image, (column * cell[0], (action_index * 2 + state) * cell[1] + 40))
            frames[0].save(PREVIEWS / f"frostbreath-head-{action}-{label}.gif", save_all=True,
                           append_images=frames[1:], duration=round(1000 / animation["rate"]), loop=0)
            report["poses"][f"{action}:{label}"] = records
            rendered += len(frames)
    report["native_head_coverage"] = validate_native_head_coverage(game, config, heads)
    sheet.save(PREVIEWS / "frostbreath-head-comparison.png")
    (PREVIEWS / "frostbreath-head-comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")

    # Keep aim independent from the rendered body. Native clients can briefly
    # display a previous pose while the cast direction has already replicated.
    # This grid is deliberately not an engine-camera conversion or a claim
    # about real GPU visibility/depth: it checks compiled mouths and vectors.
    angles = tuple(range(0, 360, 45))
    directions = {"notice": "Orthographic compiled-pixel direction diagnostic, not a game screenshot. "
                            "GPU mist, the engine camera and real depth sorting are not simulated.",
                  "layout": "Rows: rendered front / right / left / back. Columns: server aim 0..315 in 45-degree steps.",
                  "projection": "Diagram x = world x; diagram y = world z. Pose is independent of aim. "
                                "Rows are native four-way body poses, not inferred camera headings.",
                  "ice_overlay": "Native ice pixels are overlaid above the body for diagnostic visibility only.",
                  "source_sha256": source_hash, "native_files_distributed": False,
                  "gpu_mist_simulated": False, "camera_simulated": False, "depth_simulated": False,
                  "records": []}
    direction_sheet = Image.new("RGB", (cell[0] * len(angles), cell[1] * len(POSES) + 76), BACKGROUND[:3])
    heading = ImageDraw.Draw(direction_sheet)
    heading.text((10, 8), directions["notice"], font=font(17), fill=(35, 50, 55))
    heading.text((10, 34), "Aim and rendered pose vary independently; cyan circle = mouth. "
                 "Native ice pixels overlay the body only in this geometry grid.",
                 font=font(17), fill=(35, 50, 55))
    for row, (label, facing, mirrored, _) in enumerate(POSES):
        animation = next(item for item in animations
                         if item["name"] == "idle_loop" and item["facing"] == facing)
        baseline_mouth = None
        for column, degrees in enumerate(angles):
            theta = math.radians(degrees)
            projected = (math.cos(theta), -math.sin(theta))
            image, record = render(animation, 10, label, mirrored, projected, True,
                                   aim_degrees=degrees, overlay_crystals=True)
            assert len(record["crystals"]) == 3, "Each direction must emit the existing ice pixels"
            if baseline_mouth is None:
                baseline_mouth = record["mouth_canvas"]
            assert record["mouth_canvas"] == baseline_mouth, "Aim must not move the rendered pose's mouth anchor"
            assert (record["head_override"] is None) == (label == "back"), "Only supplied front/profile heads may override"
            for crystal in record["crystals"]:
                ox = crystal["position_canvas"][0] - record["mouth_canvas"][0]
                oy = crystal["position_canvas"][1] - record["mouth_canvas"][1]
                forward = ox * projected[0] + oy * projected[1]
                lateral = -ox * projected[1] + oy * projected[0]
                assert abs(forward - crystal["forward_pixels"]) < .000001
                assert abs(lateral - crystal["lateral_pixels"]) < .000001
                assert forward > 0, "Crystals must extend from the mouth in the server's forward direction"
            record.update({"server_angle_degrees": degrees, "world_direction": list(projected),
                           "rendered_pose": label, "native_facing_mask": facing, "mirrored": mirrored,
                           "crystals_overlaid_for_visibility": True})
            directions["records"].append(record)
            direction_sheet.paste(image, (column * cell[0], row * cell[1] + 76))
    assert len(directions["records"]) == 32
    direction_sheet.save(PREVIEWS / "frostbreath-head-direction-coverage.png")
    (PREVIEWS / "frostbreath-head-direction-coverage.json").write_text(
        json.dumps(directions, indent=2) + "\n", encoding="utf8")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    print(f"Rendered {rendered} decoded native-motion frames: four-direction normal/breath comparisons and 8 transition GIFs.")
    print("Validated 32 independent server-aim/rendered-pose combinations, including every 45-degree diagonal.")
    print(PREVIEWS / "frostbreath-head-comparison.png")
    print(PREVIEWS / "frostbreath-head-direction-coverage.png")


if __name__ == "__main__":
    main()
