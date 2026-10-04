# Artwork sources / 美术来源

Character, portraits and Rao's Edge textures were extracted from the six images
supplied by the project owner. The character depicts DC's Superman. The owner
reported using Gemini for some supplied images; exact model versions are not
inferred from filenames.

角色、头像和拉奥之锋贴图提取自用户提供的原图；角色身份为 DC 超人。
只对已有像素抠图、切片、旋转、镜像和缩放，没有用程序重画人物或武器。
完整来源记录见项目 assets/README.md 与 user-pic/。

LICENSE applies to project code and documentation. Supplied artwork and derived
textures retain their source attribution and are not relicensed by that file.
The mod loads game-owned animations and voices from the installed game.

Heat vision loads the installed game's wagdrone_laserwire_fx and bishop_attack
animations at runtime for the beam and a small eye glow. Eye placements are
generated from assets/slices.json; no new character artwork is drawn.
The mod supplies its own temporary FX entity and damage logic, not the game artwork.
