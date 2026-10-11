"""Run Starcore regressions against methods from a locally installed DST game.

Native source stays in memory and is never written into the repository or mod.
This optional audit supplements the portable, non-native `npm run check` suite.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile


def native_method(source: str, signature: str) -> str:
    start = source.index(signature)
    # Native component methods are top-level declarations; their inner blocks
    # are indented. Stop before the next top-level declaration/module return.
    tail = source[start:]
    boundary = re.search(r"\n(?:function |local function |fns\.|return )", tail)
    return tail[:boundary.start()] if boundary else tail


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scripts-zip", type=Path, required=True,
                        help="Installed game's data/databundles/scripts.zip")
    args = parser.parse_args()
    classes = {
        "Temperature": ("temperature", ("OnUpdate(dt, applyhealthdelta)", "SetTemperature(value)",
                                         "DoDelta(delta, skipinsulation)", "OnLoad(data)")),
        "Health": ("health", ("DoDelta(amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)",)),
        "Equippable": ("equippable", ("Equip(owner, from_ground)", "Unequip(owner)", "IsEquipped()")),
    }
    source_hashes = {}
    declarations = []
    methods = []
    with zipfile.ZipFile(args.scripts_zip) as archive:
        for class_name, (component, signatures) in classes.items():
            name = f"scripts/components/{component}.lua"
            source_bytes = archive.read(name)
            source = source_bytes.decode("utf-8").replace("\r\n", "\n")
            source_hashes[name] = hashlib.sha256(source_bytes).hexdigest()
            declarations.append(f"local {class_name} = {{}}")
            if component == "temperature":
                declarations.extend(re.findall(
                    r"^local (?:ZERO_DISTANCE|ZERO_DISTSQ|UPDATE_\w+_TAGS) = [^\n]+",
                    source, re.MULTILINE))
            for signature in signatures:
                methods.append(native_method(source, f"function {class_name}:{signature}"))
        classified_name = "scripts/prefabs/player_classified.lua"
        classified_bytes = archive.read(classified_name)
        classified = classified_bytes.decode("utf-8").replace("\r\n", "\n")
        source_hashes[classified_name] = hashlib.sha256(classified_bytes).hexdigest()
        declarations.extend(re.findall(
            r"^local (?:max_precision_temp|min_precision_temp|precision_factor|coarse_factor|pivot) = [^\n]+",
            classified, re.MULTILINE))
        for signature in ("SetTemperature(inst, temperature)", "DeserializeTemperature(inst)",
                          "OnTemperatureDirty(inst)"):
            methods.append(native_method(classified, f"local function {signature}"))
    fixture = "\n".join(declarations + methods + [
        "return {Temperature = Temperature, Health = Health, Equippable = Equippable, "
        "PlayerClassified = {SetTemperature = SetTemperature, OnTemperatureDirty = OnTemperatureDirty}}"])
    payload = json.dumps({"fixture": fixture, "sources": source_hashes})
    root = Path(__file__).resolve().parent.parent
    subprocess.run(["node", str(root / "tools/audit_starcore_native.cjs")],
                   cwd=root, input=payload, text=True, check=True)


if __name__ == "__main__":
    main()
