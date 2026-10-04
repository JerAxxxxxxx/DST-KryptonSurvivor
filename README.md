# Krypton Survivor · 氪星幸存者

Steam《饥荒联机版》超人人物 Mod。超高属性、完整夜视、热视线和专属战斧 **拉奥之锋 / Rao's Edge**，适合与朋友轻松探索和战斗。

**仓库版本：0.6.2。Steam 创意工坊版本：0.5.1，待更新。** 支持中文和英语。0.6.2 新增飞行与地图瞬移，跨海飞行与瞬移已进行游戏测试；洞穴与联机同步仍需进一步验证。工坊 0.5.1 暂不包含这两项能力。

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

## 飞行与地图瞬移（0.6.2）

两项能力均由人物自带，无需装备，不消耗饥饿、理智、材料或耐久。

- **飞行出生默认开启，按 V 切换**；每位玩家可改为 B 或关闭按键，服务器可关闭能力。可跨越海面与洞穴内部断层，墙、树等普通障碍仍保留碰撞。
- 需要回到安全陆地或船上才能关闭飞行；海面或洞穴空洞上会拒绝着陆。骑乘时暂停飞行，切换飞行或地图瞬移前需下坐骑。
- **打开地图，按住 Ctrl 并右键点选位置即可瞬移**；地图自动关闭，恢复游戏后执行，无距离或材料限制。目标限于当前世界分片；地表与洞穴之间仍通过入口切换。
- 瞬移拒绝地图外、洞穴空洞、建筑或洞口占据的落点及原生特殊屏障。飞行开启时可选海面，关闭时只允许安全陆地或船上；普通地图拖动、缩放、右键与关闭操作保留。
- 成功后提示“瞬移成功，已抵达目标位置。”；落点被挡住或人物忙碌、骑乘、暂停等情况会给出对应提示。

悬浮待机与飞行移动使用用户提供的三方向原图。飞行循环采用空手姿态，暂不显示手持武器及帽子；攻击、采集和热视线恢复现有人物动作与装备显示，装备属性仍然生效。

## 专属战斧：拉奥之锋

- 开局自带并自动装备，仅超人可以使用。
- 高额近战伤害，加长攻击距离，并对目标周围造成范围伤害。
- 范围伤害跳过玩家、墙、建筑及已有领主的随从。
- 集攻击、砍树、挖矿、锤砸于一体，工作效率为普通工具的 **10 倍**。
- 无限耐久；装备后在夜晚和洞穴提供照明，不消耗燃料。

## 安装与使用

1. 在上方 Steam 创意工坊页面订阅稳定版 0.5.1。
2. 在世界的**服务器模组**设置中启用本 Mod。
3. 进入选人界面，选择**超人**。

联机玩家需使用相同版本。更新后等待 Steam 下载完成并重启游戏，避免同时启用工坊版与本地同名版本。

本地安装：将仓库的 `mod/` 目录完整复制到游戏的 `mods/KryptonSurvivor/`，再启用服务器模组。

## 配置

以下为仓库 0.6.2 的配置；工坊 0.5.1 不含飞行与地图瞬移设置。

| 配置 | 可选值 | 默认值 |
| --- | --- | --- |
| 语言 | 自动、中文、英语 | 自动 |
| 移动速度 | 1.5、2、3 倍 | 1.5 倍 |
| 战斧伤害 | 2000、10000、50000 | 2000 |
| 热视线伤害 | 2000、10000、50000 | 2000 |
| 热视线按键 | R、G、Z、关闭 | R |
| 飞行能力（服务器） | 开启、关闭 | 开启 |
| 飞行切换按键 | V、B、关闭按键 | V |
| 地图瞬移能力（服务器） | 开启、关闭 | 开启 |
| 地图瞬移操作 | Ctrl＋右键、关闭操作 | Ctrl＋右键 |

热视线按键、飞行切换按键和地图瞬移操作由每位玩家在自己的 Mod 配置中设置。目前地图瞬移快捷操作面向键鼠，原手柄地图操作保留。

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

Repository version **0.6.2** adds innate flight and map teleportation; the Steam Workshop update is pending. Ocean flight and map teleportation have been tested in-game, while caves and multiplayer still need further verification. Flight starts enabled, toggles with **V** (or B), and supports oceans and internal cave gaps while keeping ordinary obstacle collisions. Land on safe ground or a boat before disabling it. **Ctrl + right-click the map** closes the map and teleports after gameplay resumes, within the current world shard and without distance or material costs. Success shows “Teleported to the selected location.” Unsafe, occupied and restricted destinations are rejected with a reason. Dismount before toggling flight or teleporting. Hover and movement animations use the supplied artwork. Flight loops show an empty-handed pose without held items or hats; attacks, harvesting and heat vision restore the normal character animations. Equipped items retain their effects.
