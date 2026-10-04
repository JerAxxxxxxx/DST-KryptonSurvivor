# Krypton Survivor · 氪星幸存者

Steam《饥荒联机版》超人人物 Mod。超高属性、完整夜视、热视线和专属战斧 **拉奥之锋 / Rao's Edge**，适合与朋友轻松探索和战斗。

**当前版本：0.5.1，已发布至 Steam 创意工坊。** 支持中文和英语。

[Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3811663817) · [更新记录](docs/changelog.md) · [开发说明](docs/build.md)

![超人与拉奥之锋的原画三视图](assets/source/superman-standing.jpg)

## 人物能力

- 生命、饥饿、理智上限各 **10000**。
- 关闭自然饥饿和持续理智消耗；食物等即时效果仍可能影响理智。
- 常驻完整夜视，夜晚与洞穴均可看清环境，无鼹鼠视野滤镜。
- 地表白天每秒恢复 **100 生命、100 理智**，恢复至当前上限为止；黄昏、夜晚、洞穴及死亡或幽灵状态不触发。
- 移动速度可设置为普通角色的 **1.5、2 或 3 倍**。

## 热视线

人物自带远程能力，无需独立装备。**鼠标瞄准方向，按 R 发射**，空手或持斧均可使用。

- 射程 **20**，可直线穿透多个敌人，点燃仍存活且可燃、不免疫火焰的目标。
- 伤害与战斧分别配置；无饥饿、理智或耐久消耗，最短发射间隔 **0.35 秒**。
- 光束从眼睛向前发射并跟随头部动作，带有亮芯、光晕和眼部发光。
- 直接命中跳过玩家、随从、伙伴、驯化生物、墙和建筑；点燃后的原版火焰仍可能蔓延。

聊天、界面操作和建筑放置时不会触发；忙碌、工作、死亡、幽灵及服务器暂停期间无法发射。

## 专属战斧：拉奥之锋

- 开局自带并自动装备，仅超人可以使用。
- 高额近战伤害，加长攻击距离，并对目标周围造成范围伤害。
- 范围伤害跳过玩家、墙、建筑及已有领主的随从。
- 集攻击、砍树、挖矿、锤砸于一体，工作效率为普通工具的 **10 倍**。
- 无限耐久；装备后在夜晚和洞穴提供照明，不消耗燃料。

## 安装与使用

1. 在上方 Steam 创意工坊页面订阅。
2. 在世界的**服务器模组**设置中启用本 Mod。
3. 进入选人界面，选择**超人**。

联机玩家需使用相同版本。更新后等待 Steam 下载完成并重启游戏，避免同时启用工坊版与本地同名版本。

本地安装：将仓库的 `mod/` 目录完整复制到游戏的 `mods/KryptonSurvivor/`，再启用服务器模组。

## 配置

| 配置 | 可选值 | 默认值 |
| --- | --- | --- |
| 语言 | 自动、中文、英语 | 自动 |
| 移动速度 | 1.5、2、3 倍 | 1.5 倍 |
| 战斧伤害 | 2000、10000、50000 | 2000 |
| 热视线伤害 | 2000、10000、50000 | 2000 |
| 热视线按键 | R、G、Z、关闭 | R |

热视线按键由每位玩家在自己的 Mod 配置中设置。

## 开发

Lua 检查需要 Node.js 24：

```shell
npm ci
npm run check
```

`mod/` 包含可直接安装的脚本与编译资源，`assets/` 保存实际使用的原图、切片配置和素材来源，`tools/` 提供构建、预览与打包工具。美术重建还需要 Python 3.13 和本机安装的《饥荒联机版》，完整流程见 [开发说明](docs/build.md)。

遇到问题可提交 [Issue](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor/issues)，附上版本、复现步骤和截图或相关日志。

## 许可证与素材

代码和文档采用 [MIT](LICENSE)。人物、武器原图及衍生贴图的来源与许可范围见 [素材说明](assets/README.md)。原版游戏动画和特效仅在运行时加载，不随仓库分发。

## English

A Superman character mod for **Don't Starve Together**, featuring powerful stats, full night vision, surface daytime health and sanity regeneration, innate heat vision, and the exclusive axe **Rao's Edge**. Version **0.5.1** is available on Steam Workshop.

Subscribe and enable it under server mods, then select Superman. Aim with the mouse and press **R** to fire heat vision without equipment or resource cost. The key, damage, movement speed and language are configurable. Direct beam hits exclude allies and structures; ignited targets can spread native fire. Code and documentation use the MIT license; artwork retains the source notes linked above.
