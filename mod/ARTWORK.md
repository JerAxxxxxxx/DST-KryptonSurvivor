# Artwork sources / 美术来源

Character, portraits, flight, eating expressions and Rao's Edge textures were extracted from supplied source
images supplied by the project owner, stored in the repository's assets/source/:
superman-motion.jpg, superman-standing.jpg, superman-flight.jpg, superman-eat.jpg and raos-edge.png. These filenames
were changed for organization; the image bytes remain identical to the originals.
The character depicts DC's Superman. Some supplied images were generated with
Gemini; exact model versions are not inferred from the original filenames.

角色、头像和拉奥之锋贴图提取自用户提供的原图；角色身份为 DC 超人。
只对已有像素抠图、切片、旋转、镜像和缩放，没有用程序重画人物或武器。
使用原图保存在项目 assets/source/，字节内容与收到的原图相同。
完整来源与原始文件名记录见项目 assets/README.md。

LICENSE applies to project code and documentation. Supplied artwork and derived
textures retain their source attribution and are not relicensed by that file.
The mod loads game-owned animations and voices from the installed game.

Heat vision loads the installed game's wagdrone_laserwire_fx and bishop_attack
animations at runtime for the beam and a small eye glow. Eye placements are
generated from assets/slices.json; no new character artwork is drawn.
The mod supplies its own temporary FX entity and damage logic, not the game artwork.

Flight uses six whole poses from the owner's supplied Gemini image. The JPG
checkerboard was removed with an alpha mask; the original file is unchanged.
krypton_flight.zip contains an original build and original hover/movement
animation data using only these pixels and whole-pose translation. It contains
no base-game animation files. Normal actions still load the installed game.

Eating expressions use three supplied front-facing heads from eat.jpg. The JPG
checkerboard was removed by an alpha mask; original image bytes are unchanged.
krypton_eating.zip contains only the extracted head textures and their original
build data. Native eating body motions, food sprites and sounds load from the
installed game; no base-game eating animation files are distributed.

The Starcore Amulet uses the orange energy core extracted from the supplied
Rao's Edge source image. Its custom build and inventory texture contain only
those selected pixels. Native amulets animations load from the installed game;
no game-owned animation or artwork is included in the amulet archive.

Frost breath uses front and profile heads extracted from the supplied head.jpg,
stored unchanged as assets/source/superman-frostbreath-head.jpg. Only exterior
white paper is masked; enclosed eye whites and the original face pixels remain.
krypton_frostbreath_head.zip contains only the owned build and texture. Native
body animation, cold mist and ice crystal resources load from the installed game.

Flight, protection and revival HUD icons were created with the OpenAI image
generation tool in this conversation. Original transparent PNGs, full prompts
and source hashes are stored under assets/source/ui/. No exact generation model
version is inferred. The mod's 128-pixel icon atlases use only alpha-bound crops,
uniform scaling and placement; the code license does not relicense these images.
