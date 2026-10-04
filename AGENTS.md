# Project instructions

- Keep all user-pic files unchanged. They are the authoritative artwork.
- Do not draw or redraw characters, faces, clothing or weapons with code, SVG,
  Canvas or procedural strokes. Pixel extraction, alpha masks, rotation, mirroring,
  scaling and animation packaging are allowed. New artwork requires an image
  generation tool or user-supplied artwork.
- Source polygons and placements belong in assets/slices.json. Generated parts
  and motion previews belong in build/, which is ignored.
- Keep krypton_survivor and krypton_staff prefab identifiers for save compatibility.
- Run npm run check after Lua changes; rebuild, run tools/check_assets.py and
  inspect compiled animation previews after visual changes.
- Never redistribute reference-mod artwork or base-game animation files. Runtime
  dependencies must load from the user's installed game.
- Preserve local history in ignored archive/. Do not publish or choose a license
  without the user's instruction. Leave unresolved decisions in docs/pending-decisions.md.
