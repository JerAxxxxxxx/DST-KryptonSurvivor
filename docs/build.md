# 构建与检查

## 环境

验证环境为 Python 3.13.1、Node.js 24.12.0、Pillow 11.0.0、NumPy 2.4.3、OpenCV 4.13.0。Python 包固定在 requirements.txt；Node 包固定在 package-lock.json。

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
npm ci
```

## 修改图片

编辑 assets/slices.json 的多边形和关节位置，再运行：

```powershell
python tools/extract_user_art.py
python tools/build_custom_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/preview_animation.py --game-dir "你的饥荒联机版安装目录"
python tools/check_assets.py
npm run check
```

也可设置 DST_GAME_DIR 环境变量。游戏目录下需要 data/anim/wilson.zip、swap_cane.zip、cane.zip 和 player 动画文件；这些内容只从用户本机读取，不复制到仓库。

build/art 是切片；build/extraction-manifest.json 记录源文件 SHA-256 与原图坐标；build/previews 包含三方向站立、跑动、攻击 GIF 和攻击逐帧拼图。预览从已编译的 BILD 和本机游戏动作计算，不是另画一张效果图。

修改 Lua 后运行 npm run check。检查覆盖语言、选人模型隔离、角色属性、装备、联机分支、采集、所有权、范围伤害、夜视与热视线。它无法代替游戏内测试。

## 热视线眼部定位（0.5.1）

瞳孔来源点和光束边界统一保存在 assets/slices.json 的 heatvision 中。原图仍保持不变；build_custom_assets.py 根据头部锚点与缩放生成 mod/scripts/krypton_heatvision_visual_data.lua，不手改该生成文件。正面两处瞳孔、侧面一处；背面继承正面双束位置，但不生成眼部发光。

运行时各客户端在动画更新后通过 GetSymbolPosition 读取 headbase，必要时读取 headbase_hat，跟随实际头部位置。光束使用原版 wagdrone_laserwire_fx 的 beam_straight，眼部光点使用 bishop_attack 的 shot_fx；均从已安装游戏加载。原版光束边界为 -183 至 176 像素，150 像素对应一个世界单位，按实际左端平移起点，避免向眼睛后方延伸。

```powershell
python tools/preview_heatvision.py --game-dir "你的饥荒联机版安装目录"
```

该工具在内存中读取编译人物与本机游戏特效，输出 build/previews/heatvision-eyes.png、heatvision-eyes.json，以及站立和跑动各方向的连续与逐帧预览。内容是已有像素、动画变换和光束边界的几何检查，不是实际游戏摄像机渲染，不模拟完整光晕或客户端视角；最终仍需按 docs/playtest.md 实测。原版资源不进入发布包。

## 打包与安装

```powershell
.\tools\package.ps1
```

只打包 mod/。版本号来自 mod/modinfo.lua。更新本地安装前退出游戏，备份原安装，再复制 mod/。普通美术更新保持 prefab 名称，避免破坏已有物品引用。

也可运行 tools/install.ps1 -GameDir "游戏安装目录"。脚本会检查游戏进程、备份原安装，并逐文件校验安装结果；写入游戏目录需要相应权限。

## 工坊封面

运行 `python tools/prepare_workshop_preview.py`，从用户提供的持斧正面原图裁切、缩放生成 `build/workshop/preview.jpg` 和 `preview.png`（512×512）。裁切位置记录在 `assets/slices.json`；不重画人物，不修改原图。上传工具的 Update Data 选择 `mod/`，Update Preview Image 优先通过 Browse 选择标准 RGB、非渐进的 JPG。PNG 可作为备用。两张图均经过格式、尺寸与读取完整性检查。

## 历史归档

archive/before-0.4.1.zip 是整理前快照；archive/legacy-tree 保存实际搬移的旧工具、图片、参考素材及安装备份，archive/legacy-files-current.zip 是搬移前的核验副本。全部 332 个候选文件均已逐字节核验。archive/ 不提交。恢复历史文件时单独取回所需内容，避免整体覆盖新版本。
