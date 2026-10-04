# Krypton Survivor · 氪星幸存者

开源仓库：[JerAxxxxxxx/DST-KryptonSurvivor](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor)。

Steam《饥荒联机版》人物 Mod：超人和专属战斧 **拉奥之锋 / Rao's Edge**。当前本地版本 **0.5.1**，修正热视线从头后方发出的视觉问题；用户于 2026-10-04 复测后反馈暂无问题，准备发布。工坊已确认上传的版本仍为 **0.4.2**，尚未收到 0.5.1 上传成功确认。

## 已实现

- 生命、饥饿、理智上限各 10000；关闭自然饥饿及持续理智消耗。
- 白天地表每秒恢复 100 生命、100 理智；生命恢复到有效上限后停止回血。黄昏、夜晚、洞穴以及死亡或幽灵状态不触发恢复；食物仍可能即时扣除理智。
- 常驻完整夜视，禁用鼹鼠视野滤镜；移速可配置 1.5、2、3 倍。
- 开局装备拉奥之锋：伤害 2000、10000、50000 可选，攻击距离 6，命中距离 8，范围伤害半径 5。
- 范围伤害排除玩家、幽灵、墙、建筑及已有领主的随从。
- 砍树、挖矿、锤击效率 10 倍，无耐久；只有本角色可以装备。
- 人物自带热视线，无需独立装备；鼠标指向世界中的方向，按 R 发射直线穿透攻击，空手或持斧均可使用。按键可在本机配置中改为 G、Z 或关闭。
- 热视线伤害单独配置为 2000、10000、50000，默认 2000；射程 20，光束半宽 0.8，并计入目标体型。无饥饿、理智或耐久消耗，两次发射至少间隔 0.35 秒。
- 热视线直接命中排除玩家、随从、伙伴、驯化生物、墙与建筑；命中后可点燃仍存活且可燃、不免疫火焰的生物。原版火焰仍可能蔓延到周围物体。
- 中文和英语。内部标识保持 krypton_survivor / krypton_staff，兼容已有存档。

热视线在忙碌、工作、死亡、幽灵或服务器暂停时不能发射；聊天、界面操作和建筑放置期间不触发。0.5.1 按原图瞳孔位置跟随头部动作设置光束起点，正面双束、侧面单束，背面不显示眼部光点；加强光束亮芯与光晕。特效使用游戏运行时资源，人物与武器美术保持原样。用户已完成总体复测，帽子、骑乘、洞穴、摄像机转向及远程客户端等专项测试仍待逐项确认。

人物、头像、立绘和战斧从 user-pic 中的原图提取，未用程序重新画五官或服装。披风属于人物贴图，未做成独立装备。当前表情固定；幽灵模型和声音引用游戏内的威尔逊资源。飞行、自动复活和其余专属装备尚未实现。

## 安装

工坊版：[Steam 创意工坊条目](https://steamcommunity.com/sharedfiles/filedetails/?id=3811663817)。订阅后在世界的服务器 Mod 设置中启用；页面可见性待确认。测试工坊版时避免同时启用本地同名版本。

把 mod 文件夹内的文件复制到游戏的 mods/KryptonSurvivor 中，启用服务器 Mod。朋友需安装相同版本。更新前退出游戏，再重启加载；旧存档不需要删除。安装包在 dist 中生成。

## 项目目录

| 目录 | 用途 |
| --- | --- |
| mod/ | 可安装的 Lua 脚本、编译后的角色与武器资源 |
| user-pic/ | 用户提供的六张原图，保留原文件名和内容 |
| assets/ | 切片选区、来源说明和名称 UI 素材 |
| tools/ | 原图像素提取、编译、动作预览、检查和打包 |
| tests/ | Lua 功能模拟检查 |
| docs/ | 构建说明、变更记录、实测与待确认事项 |
| build/ | 自动生成的切片、预览和来源哈希，忽略提交 |
| archive/ | 本机历史快照，忽略提交 |
| dist/ | 生成的安装包，忽略提交 |

## 开发

需要 Python 3.13、Node.js 24，以及本机安装的《饥荒联机版》。依赖与命令见 [构建说明](docs/build.md)。

运行 npm ci 后使用 npm run check 验证 Lua。资源重建依次运行：

```powershell
python tools/extract_user_art.py
python tools/build_custom_assets.py --game-dir "D:\SteamLibrary\steamapps\common\Don't Starve Together"
python tools/preview_animation.py --game-dir "D:\SteamLibrary\steamapps\common\Don't Starve Together"
python tools/check_assets.py
.\tools\package.ps1
```

资源编译读取游戏的符号接口与锚点，并从 assets/slices.json 的眼部坐标生成热视线定位数据。动作预览读取本机动画；发布包不复制原版人物贴图、动作或激光资源。武器地面动作通过游戏自带 cane 资源加载。

## 发布状态

本地代码和资源检查通过不等于游戏测试通过。请按 [实测清单](docs/playtest.md) 验证现有存档、联机和穿模情况。

项目已公开至 [**JerAxxxxxxx/DST-KryptonSurvivor**](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor)，默认分支为 main。项目代码和文档采用 [MIT](LICENSE)，六张原图已获用户同意收入仓库，来源与图片许可范围见 [素材来源](assets/README.md)。本地历史、构建预览、安装包与依赖缓存不收入仓库。

Steam 创意工坊 0.4.2 已由用户首次上传成功，条目 ID **3811663817**；0.5.1 总体复测暂无问题，待用户上传。后续更新同一条目，流程见 [工坊记录](docs/workshop.md)，中英文发布文案见 [0.5.1 更新说明](docs/workshop-release-0.5.1.md)。页面可见性、联机专项验证及新增美术见 [TODO](docs/TODO.md)。账号与仓库安排见 [仓库说明](docs/repository.md)。

English: A Don't Starve Together character mod featuring Superman and Rao's Edge, with full night vision, daytime health/sanity regeneration, and intrinsic heat vision. Aim with the mouse and press R (locally configurable) to fire without equipment or resource cost. Direct hits exclude allies and structures; ignited creatures can spread native fire. Local version 0.5.1 adjusts eye anchoring and beam brightness; the user reports no issues after retesting and plans to publish it. Detailed multiplayer and equipment checks remain pending. Workshop item 3811663817 has only a confirmed 0.4.2 upload. Source is publicly available at [JerAxxxxxxx/DST-KryptonSurvivor](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor). Code and documentation use the MIT license; supplied artwork retains its source notes.
