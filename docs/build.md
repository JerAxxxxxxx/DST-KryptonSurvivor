# 构建与检查

仓库中的 `mod/` 已包含编译资源，可直接安装。修改 Lua 只需 Node.js；重新处理图片和生成预览还需要 Python 与本机安装的《饥荒联机版》。

## 环境

验证环境为 Python 3.13.1、Node.js 24.12.0、Pillow 11.0.0、NumPy 2.4.3、OpenCV 4.13.0。Python 依赖固定在 `requirements.txt`，Node.js 依赖固定在 `package-lock.json`。

在仓库根目录运行以下 PowerShell 命令：

```powershell
npm ci
npm run check
```

需要重建美术资源时，再安装 Python 依赖：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

## 重建资源

使用原图保存在 `assets/source/`，原始文件名与来源见 [素材说明](../assets/README.md)。选区、关节位置和眼部坐标保存在 `assets/slices.json`。调整选区或位置后，依次运行：

```powershell
python tools/extract_user_art.py
python tools/build_custom_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/build_flight_assets.py
python tools/preview_animation.py --game-dir "你的饥荒联机版安装目录"
python tools/check_assets.py
npm run check
```

也可设置 `DST_GAME_DIR` 环境变量，省略命令中的 `--game-dir`。构建读取游戏目录 `data/anim/` 下的 `wilson.zip` 和 `swap_cane.zip`；动作预览还读取 `cane.zip`、`player_basic.zip`、`player_attacks.zip` 和 `player_idles.zip`。热视线预览读取 `wagdrone_laserwire_fx.zip` 和 `bishop_attack.zip`。这些游戏资源仅从本机安装读取，不复制到仓库或 Mod 发布包。

生成文件如下：

- `build/art/`：从原图提取的透明切片及局部坐标。
- `build/extraction-manifest.json`：源文件 SHA-256、选区和原图坐标。
- `build/previews/`：编译资源的三方向站立、跑步、攻击 GIF 与逐帧拼图。
- `mod/anim/`、`mod/images/`、`mod/bigportraits/`：可安装的编译资源。

`build/` 属于本地生成目录，不提交。预览使用编译后的 BILD 与本机游戏动画矩阵合成已有像素。

## 飞行姿态

飞行动作由用户提供的 `assets/source/superman-flight.jpg` 提取，不重新绘制人物。原图中的棋盘格背景是 JPG 像素，构建时用边缘连通背景生成 alpha；六个完整姿态的选区与位置记录在 `assets/slices.json` 的 `flight` 和 `selections` 中。

```powershell
python tools/build_flight_assets.py
python tools/check_assets.py
```

此构建不依赖游戏安装，生成 `mod/anim/krypton_flight.zip` 中自有的 BILD v6、ANIM v4 与 KTEX 贴图。动作库为 `wilson`，自定义动作为 `krypton_flight_idle` 和 `krypton_flight_move`，均有正面、侧面、背面三个方向，每个方向 12 帧、12 fps。循环仅整体平移原图像素，悬浮幅度为三个像素。

透明原始选区、缩放切片与来源哈希保存在 `build/art/flight/` 和 `build/flight-extraction-manifest.json`。预览从生成的编译包重新解码，输出 `build/previews/flight-poses.png`、`flight-contact-sheet.png`、`flight-loop.gif` 及各方向 GIF。检查六个姿态完整、没有混入相邻姿态或背景残片，并在游戏中确认镜像、动作切换、装备与帽子的表现。

## 热视线眼部定位

瞳孔来源点和光束边界保存在 `assets/slices.json` 的 `heatvision` 中。`tools/build_custom_assets.py` 根据头部锚点与缩放生成 `mod/scripts/krypton_heatvision_visual_data.lua`；修改源坐标后重新构建，不直接编辑生成文件。正面两处瞳孔、侧面一处；背面继承正面双束位置，不生成眼部发光。

运行时各客户端在动画更新后通过 `GetSymbolPosition` 读取 `headbase`，必要时读取 `headbase_hat`，跟随当前头部位置。光束使用原版 `wagdrone_laserwire_fx` 的 `beam_straight`，眼部光点使用 `bishop_attack` 的 `shot_fx`。原版光束边界为 -183 至 176 像素，150 像素对应一个世界单位，按实际左端平移起点，使光束从眼睛向前延伸。

```powershell
python tools/preview_heatvision.py --game-dir "你的饥荒联机版安装目录"
```

该工具在内存中读取编译人物与本机游戏特效，输出 `build/previews/heatvision-eyes.png`、`heatvision-eyes.json`，以及站立和跑步各方向的连续与逐帧预览。预览用于核对已有像素、动画变换和光束边界；实际摄像机投影、客户端视角与完整光晕效果应在游戏中检查。

## 检查

修改 Lua 后运行 `npm run check`。检查覆盖 Lua 5.1 语法、资源引用、语言、选人模型、角色属性、装备、联机分支、采集、所有权、范围伤害、夜视与热视线，以及飞行碰撞、存档、预测、视觉和地图瞬移的落点、权限、暂停恢复与输入焦点。GitHub Actions 在推送和拉取请求时执行同一套检查，无需安装游戏。

重建图片后运行 `python tools/check_assets.py`，核对编译帧、贴图 mip 层、图集引用与可用的原图哈希，并检查生成的动作预览。

游戏内验证可从新建世界和已有存档分别开始：启用服务器 Mod、选择超人，检查开局装备、采集、夜视、白天回血、热视线，以及飞行跨海与洞穴断层、安全着陆、地图瞬移和成功／失败提示；再检查戴帽、骑乘、洞穴切换、摄像机转向、保存读取与远程玩家加入。自动检查和几何预览不能替代这些游戏操作。

## 打包与安装

```powershell
.\tools\package.ps1
```

此命令只打包 `mod/`，版本号取自 `mod/modinfo.lua`，输出 `dist/KryptonSurvivor-版本号.zip`。

手动安装时，退出游戏和服务器，将 `mod/` 内的文件复制到游戏的 `mods/KryptonSurvivor/`，再在世界设置中启用服务器 Mod。更新前备份原安装；联机玩家应使用相同版本。

也可运行：

```powershell
.\tools\install.ps1 -GameDir "你的饥荒联机版安装目录"
```

安装脚本检查游戏进程、备份原安装并逐文件校验复制结果。角色与武器的 prefab 标识保持 `krypton_survivor`、`krypton_staff`，以兼容现有存档。

## 工坊封面

```powershell
python tools/prepare_workshop_preview.py
```

命令从持斧正面原图裁切、缩放生成 `build/workshop/preview.jpg` 和 `preview.png`（512×512）。裁切位置记录在 `assets/slices.json`，原图保持不变。上传 Mod 内容时选择 `mod/`；封面可使用生成的标准 RGB、非渐进 JPG。
