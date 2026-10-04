"""Crop and scale user artwork for Workshop; never redraw or alter the source."""

import hashlib
import json
from pathlib import Path

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[1]
    slices = json.loads((root / "assets" / "slices.json").read_text(encoding="utf-8"))
    preview = slices["workshop_preview"]
    source = root / slices["sources"][preview["source"]]["path"]
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    box = tuple(preview["crop_pixels"])
    size = tuple(preview["output_size"])
    output_dir = root / "build" / "workshop"
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [(output_dir / "preview.png", "PNG"), (output_dir / "preview.jpg", "JPEG")]

    with Image.open(source) as original:
        left, top, right, bottom = box
        if not (0 <= left < right <= original.width and 0 <= top < bottom <= original.height):
            raise ValueError("Preview crop must stay within the original image.")
        cropped = original.crop(box).convert("RGB").resize(size, Image.Resampling.LANCZOS)
        cropped.save(outputs[0][0], format="PNG")
        # Baseline RGB JPEG provides a fallback for older uploader image readers.
        cropped.save(outputs[1][0], format="JPEG", quality=90, subsampling=0, progressive=False)

    if hashlib.sha256(source.read_bytes()).hexdigest() != original_hash:
        raise RuntimeError("Authoritative artwork changed.")
    for output, expected_format in outputs:
        with Image.open(output) as generated:
            if generated.size != size or generated.format != expected_format or generated.mode != "RGB":
                raise RuntimeError("Invalid preview output.")
            generated.verify()
        print(f"Workshop preview: {output} ({output.stat().st_size} bytes)")
    print(f"Size: {size[0]}x{size[1]}; original artwork unchanged.")


if __name__ == "__main__":
    main()
