# 构建与检查

仓库中的 `mod/` 已包含编译资源，可直接安装。修改 Lua 只需 Node.js；重新处理图片和生成预览还需要 Python 与本机安装的《饥荒联机版》。

当前代码与 Steam 创意工坊版本均为 **0.11.0**。本次工坊更新累计覆盖0.8.2之后的黑暗形态、技能反馈、友方保护、吐息修复与服务器数值配置，详见[更新记录](changelog.md)。

## 环境

验证环境为 Python 3.13.1、Node.js 24.12.0、Pillow 11.0.0、NumPy 2.4.3、OpenCV 4.13.0。Python 依赖固定在 `requirements.txt`，Node.js 依赖固定在 `package-lock.json`。

在仓库根目录运行以下 PowerShell 命令：

```powershell
npm ci
npm run check
```

发布前资源检查无需游戏安装，只需Python 3.13及Pillow：

```powershell
python -m pip install -r requirements-check.txt
npm run check:assets
```

`requirements-check.txt` 只供检查，完整美术重建依赖仍使用 `requirements.txt`。GitHub Actions在推送和拉取请求时分别运行Lua回归与资源检查；两项通过后再继续发布流程。

需要重建美术资源时，再安装 Python 依赖：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

## 重建资源

使用原图保存在 `assets/source/`，原始文件名与来源见 [素材说明](../assets/README.md)。选区、关节位置以及眼部和嘴部坐标保存在 `assets/slices.json`。调整选区或位置后，依次运行：

```powershell
python tools/extract_user_art.py
python tools/build_custom_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/build_flight_assets.py
python tools/build_eating_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/build_starcore_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/build_frostbreath_head_assets.py
python tools/build_ability_ui_assets.py
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

## 吃东西的表情

`assets/source/superman-eat.jpg` 是用户提供的 `eat.jpg` 原样副本。三个正面头部的选区、缩放、锚点与切换时间线保存在 `assets/slices.json` 的 `eating` 段。

```powershell
python tools/build_eating_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/check_assets.py
npm run check
```

此工具去除原图中的棋盘格背景并提取已有像素，生成只含自有 BILD 与贴图的 `mod/anim/krypton_eating.zip`，以及运行时使用的 `krypton_eating_visual_data.lua`。不打包原版吃饭动画，运行时沿用游戏的身体、手部、食物与声音。

`build/art/eating/` 保存透明切片，`build/eating-extraction-manifest.json` 保存来源与位置。`build/previews/eating-heads.png` 对照常态头与三个表情；`eat-supplied.gif`、`quick_eat-supplied.gif`、`quick_drink-supplied.gif` 及同名 contact PNG 从编译包解码头部，并在内存中合成本机 `player_actions_eat.zip` 的身体动作。预览不代表食物显示、帽子或联机已完成实测。

头部替换只在吃东西期间生效，结束或中断后恢复。脚本检查覆盖帧边界、前摇与客户端等待动画、动作打断、死亡、骑乘、皮肤和其他覆盖的恢复。BILD 符号表必须按无符号 SDBM 哈希升序排列；编译器统一排序，资源检查验证写入后的实际顺序，避免预览正常但游戏找不到头部。帽子、食物显示、连续吃东西与朋友客户端的实际表现仍需游戏验证。

## 星核护符

`tools/build_starcore_assets.py` 按 `assets/slices.json` 中的 `starcore` 与 `starcore-core` 从既有拉奥之锋透明原图提取发光核，生成 `mod/anim/krypton_starcore_build.zip` 和物品图集。该包只有自有 BILD 与贴图，使用 `redamulet` 符号；原版 `amulets.zip` 的动作在运行时加载。

```powershell
python tools/build_starcore_assets.py --game-dir "你的饥荒联机版安装目录"
python tools/check_assets.py
npm run check
```

`build/starcore-extraction-manifest.json` 记录来源、选区和位置。`build/previews/starcore-compiled-contact.png` 对照编译地面切片和物品图标，`starcore-ground-native.gif` 使用本机原版护符动作矩阵合成编译像素；原版动画只用于本地预览，不复制到安装包。

`tests/starcore.lua` 覆盖原生装备事件顺序、干燥来源与冷热伤害过滤的撤销、自动复活成功与外部机制竞争、人物冷却／存档／分片，以及旧存档一次补发和身体栏兼容。实际游戏的装备、死亡与复活过程仍需试玩。

## 热视线眼部定位

瞳孔来源点和光束边界保存在 `assets/slices.json` 的 `heatvision` 中。`tools/build_custom_assets.py` 根据头部锚点与缩放生成 `mod/scripts/krypton_heatvision_visual_data.lua`；修改源坐标后重新构建，不直接编辑生成文件。正面两处瞳孔、侧面一处；背面继承正面双束位置，不生成眼部发光。

运行时各客户端在动画更新后通过 `GetSymbolPosition` 读取 `headbase`，必要时读取 `headbase_hat`，跟随当前头部位置。光束使用原版 `wagdrone_laserwire_fx` 的 `beam_straight`，眼部光点使用 `bishop_attack` 的 `shot_fx`。原版光束边界为 -183 至 176 像素，150 像素对应一个世界单位，按实际左端平移起点，使光束从眼睛向前延伸。

```powershell
python tools/preview_heatvision.py --game-dir "你的饥荒联机版安装目录"
```

该工具在内存中读取编译人物与本机游戏特效，输出 `build/previews/heatvision-eyes.png`、`heatvision-eyes.json`，以及站立和跑步各方向的连续与逐帧预览。预览用于核对已有像素、动画变换和光束边界；实际摄像机投影、客户端视角与完整光晕效果应在游戏中检查。

## 能力状态面板

`krypton_ability_status.lua` 在角色的 CommonInit 中、`SetPristine` 之前声明同一套网络变量；服务器在飞行与星核护符组件建立后启动状态同步。数据由服务器读取真实飞行、骑乘、生存、装备、保护和复活冷却状态，每个模拟秒更新，不修改既有护符保护或存档逻辑。

`krypton_ability_hud.lua` 挂接原生 `widgets/controls`，仅为超人建立 `widgets/krypton_ability_status.lua` 面板。面板位于原生 `topright_root` 下，继承玩家 HUD 缩放，默认让出生命、饥饿、理智与湿度表。三行分别显示飞行、护符保护和复活；倒计时直接显示服务器剩余秒数，客户端不使用现实时间推算。

面板复用原版 `images/global.xml` 背景；三行图标来自 `assets/source/ui/`，选区和位置见 `assets/slices.json` 的 `hud_icons`。运行 `python tools/build_ability_ui_assets.py` 可生成三份 128×128 透明图集和完整 mip 层，以及 `build/previews/ability-icons-compiled.png`、`ability-status-ui-composition.png`。后者用于核对中英文就绪、冷却、未装备的文字与图标布局，不是真实游戏截图。

0.9.0在旧面板顶端与三行位置不变的情况下向下扩展，追加两行纯文字技能状态。真实本机按键由modmain传入，服务器仍使用同一个ushort标志同步技能可用、冷却与施放状态；成功施法及吐息结束触发状态事件，单次模拟时间任务在最近冷却到期时刷新，避免1秒轮询漏掉0.35秒冷却。客户端每0.1秒只评估本机操作限制，不修改网络标志或复活剩余时间。新增缩放预览为 `build/previews/ability-status-ui-scale-preview.png`。

`status_hud_enabled`、`status_hud_scale` 和 `status_hud_position` 为每位玩家独立设置，支持显示／隐藏、0.8／1／1.2 倍，以及 `default`／`left`／`lower` 三个固定位置。悬停说明使用原生 tooltip；没有自由拖动、按钮或额外快捷键。

`tests/status_hud.lua` 验证服务器与远程快照、暂停不倒数、装备与冷却变化、死亡与重进、非超人和专用服务器无 UI，以及本地配置与控制事件。屏幕分辨率、其他 HUD Mod 和实际联机布局仍需游戏试玩。

## 冰冻吐息与嘴部定位

`krypton_frostbreath.lua` 由服务器校验施法资格与鼠标方向，对前方范围 8、半角 28° 的扇形持续约 1 秒检查目标，最短间隔 1.2 秒。同一次吐息对每个目标最多调用一次原生 `freezable:AddColdness(2, 4)`；其中的参数 4 交由原生冻结系统处理，不代表所有目标统一冻结 4 秒。原版抗性、免冻、冷量重定向与 Boss 递减仍生效，不直接调用强制冻结或增加生命伤害。

冻结筛选跳过友方与结构；灭火使用独立筛选，允许救助着火的玩家、随从、建筑和树木，同时排除 `campfire`、`cooker` 与具有 `fueled` 组件的设备。能力和按键分别由服务器 `frostbreath_enabled` 与客户端 `frostbreath_key` 配置，默认 X，可选 C、N 或关闭。无需装备与资源。

常态嘴部源坐标保存在 `assets/slices.json` 的 `frostbreath.mouth_points`，构建生成 `krypton_frostbreath_visual_data.lua`。0.8.1 另从用户 `head.jpg` 的原样副本提取正面与侧面张嘴头部，选区、颈部锚点、等比缩放和嘴部坐标见 `breath_head` 段。运行时先切换表情，再从当前头部读取嘴部位置发射本机原版冷气和冰晶，结束或中断后恢复；背面保留原头。

```powershell
python tools/build_frostbreath_head_assets.py
python tools/preview_frostbreath_heads.py --game-dir "你的饥荒联机版安装目录"
```

新头部编译包只含自有 `build.bin` 与 `atlas-0.tex`；`krypton_frostbreath_head_data.lua` 同步输出嘴部定位。透明切片保存在 `build/art/frostbreath/`，来源记录在 `build/frostbreath-head-extraction-manifest.json`。`build/previews/frostbreath-head-comparison.png` 与四方向站立／跑步切换 GIF 从编译包重新读取像素，在内存中合成本机身体动画，用于检查颈部、镜像与恢复。原图及其他人物／武器资源不重画。

原生 `OverrideSymbol` 保留动作请求的帧号。头部与帽子头部在正面／侧面／背面分别读取 0／1／2，部分炎热和困倦侧面动作也会读取 0。`breath_head.native_head_frames` 声明完整范围；每个吐息符号用起始帧 0、持续 3 帧的同一图片覆盖，不复制或重画像素。资源检查逐帧验证覆盖，预览按原生动画实际帧及持续区间查找，缺失时直接失败；固定读取第 0 帧不能代替此检查。

```powershell
python tools/preview_frostbreath.py --game-dir "你的饥荒联机版安装目录"
```

该工具从编译后的角色包和本机原版站立／跑步动作读取像素与矩阵，在内存中合成原版冰晶，输出 `build/previews/frostbreath-mouths.png`、`frostbreath-mouths.json`，以及 `frostbreath-idle_loop-*.gif`、`frostbreath-run_loop-*.gif`。预览包括正面、左右侧面和背面；嘴部标记与放大框仅用于核对坐标。

**这是编译像素与几何示意，不是真实游戏画面。** 工具读取原版冷气纹理和粒子参数用于核验，但不模拟 GPU 冷雾、泛光、深度排序或游戏摄像机投影。应在游戏中确认实际发射位置、雾效与遮挡。原生源码、动画和贴图仅从用户安装目录读取，不写出或随 Mod 分发。

0.10.2吐息特效读取服务器同步的施放方向，客户端不再把预测的Transform朝向短暂不同作为永久中断。服务器Pulse保留0.2秒方向与资格检查，真实转身时删除代理；本机忙碌、死亡、皮肤及动作中断仍及时清理。

`preview_frostbreath_heads.py`额外输出 `frostbreath-head-direction-coverage.png` 与JSON，枚举8个世界瞄准角×4种原生渲染姿态。它复用编译像素，仅作正交嘴部／冰晶几何诊断，特意把姿态与方向独立；不模拟GPU雾、真实相机投影或深度排序。原四向288帧预览继续保留。

## 黑暗形态

`krypton_darkform.lua`在common阶段声明独立net_bool，组件`krypton_darkform`只在服务器创建并保存dark和normal_percent。H/J/K输入与现有RPC命名空间使用同一已归一化配置；X/H在0.10.1中与R保持相同修饰键策略，不再仅因Ctrl/Alt/Shift状态就拒绝发送或让吐息变灰；界面焦点、鼠标悬UI、暂停、忙碌与服务器资格检查保留。服务器校验实际角色、控制器、状态与0.35秒间隔，客户端不自行改变形态。

组件通过原生GetRealPercent快照、SetPercent校正至5%，遵守有效上限、ignore／redirect与外部强制理智效果。sanitydelta仅排入去重0延时任务，避开DoDelta尾部状态收尾的重入；仅黑暗状态有1秒兜底任务，退出／移除会取消。OnLoad等所有组件加载后校正，复活后同样延后；死亡或幽灵不强制覆盖。原来的白天恢复任务仅在黑暗时跳过sanity分支，健康分支不变。

普通理智模式的5%低于原生疯狂阈值；月岛等启蒙来源与sanitymode不改写，原版影怪刷新与可见／可交互规则保留。面板增加独立形态行，监听同一个net_bool的dirty事件；原三行及R/X位置不变。UI builder重建预览时不重画角色或更改编译美术。

`tests/darkform.lua`运行实际模块及组件，覆盖理智正负变化、原生限制兼容、保存加载顺序、ghost／corpse／复活、切换恢复、权限、暂停与任务清理；`smoke.lua`验证实际prefab白天回血／回理智分支与modmain配置，`status_hud.lua`覆盖新输入与远端显示。

## 服务器数值配置与恢复

`krypton_config.lua`统一校验modmain使用的八项数字：新攻击距离／范围半径／吐息冷量／两种白天恢复，以及原伤害与移速选项。仅接受菜单列出的有限number，缺失或错误类型／NaN／无穷／越界返回既有默认；合法0仅用于关闭对应恢复或范围伤害。`tests/configuration.lua`加载实际modinfo，逐项检查菜单与验证表一致；烟测再执行真实modmain及prefab消费非默认值。

范围伤害0不进行FindEntities，仍保留原主目标攻击；原生weapon:SetRange的attackrange属性钩子通过inventoryitem classified同步客户端，因此无需新增预测netvar。吐息仍使用原生AddColdness并保留目标抗性。

两种恢复独立为0时跳过对应DoDelta，双0不创建恢复任务；正常形态仅在GetRealPercent低于1-GetPenaltyPercent的有效上限时恢复理智，避免每秒对满值发出sanitydelta。黑暗优先级、地表白天、生存及暂停语义保留，生命恢复仍使用原生健康组件。

## 检查

### 资源与发布副本检查

`npm run check:assets`依次运行 `tools/check_assets.py` 与 `tools/test_asset_validation.py`。资源检查扫描全部Mod Lua中的字面ANIM／ATLAS／IMAGE声明，严格校验相对路径和大小写；自有资源必须随包提供，明确列出的原生动画只在运行时加载，并拒绝将其打包分发。新增自有动画时应同时更新自有包清单与具体内容验证。

负例检查只复制自有项目资源到临时发布树，以Python `-S`和独立Pillow证明检查不依赖本机游戏、user-pic、build记录或NumPy／OpenCV。它覆盖旧版侧面缺帧、符号表乱序、纹理截断、缺图集／动画、错误大小写与未审查的动画包，所有损坏只发生在临时副本，不修改源图或工作目录编译资源。

### Lua与游戏行为

修改 Lua 后运行 `npm run check`。检查覆盖 Lua 5.1 语法、资源引用、语言、选人模型、角色属性、装备、联机分支、采集、所有权、范围伤害、夜视与热视线，以及飞行碰撞、存档、预测、视觉和地图瞬移的落点、权限、暂停恢复与输入焦点。工具操作回归覆盖原生工作优先于采集的情形、连续空格采集、已采完植物保护、服务器指定目标验证、右键挖掘及原有工具动作。GitHub Actions 在推送和拉取请求时执行同一套检查，无需安装游戏。

0.9.0新增三种范围效果的共用目标保护交叉回归，验证点燃关闭仍造成原伤害、友方保护不妨碍灭火、技能事件时序与短冷却恢复。公共规则位于 `mod/scripts/krypton_combat_targets.lua`；主目标普攻与原生CanTarget校验保持各自职责。

0.8.0 新增状态面板与冰冻吐息的独立回归，覆盖权威状态／冷却同步、本地 UI 配置，以及吐息扇形边界、目标筛选、单次冷量、灭火、输入拦截、冷却和生命周期清理。自动检查结果不等同于真实游戏效果已确认。

星核护符检查覆盖真实参数顺序、安全体温与原生同步、温度伤害入口、后置回调覆盖、装备立即纠正、卸下恢复与原生复活／冷却。可选本机审计直接读取自己安装的温度、生命、装备和客户端温度同步函数，原生源码仅在内存使用，CI默认无需安装游戏：

```powershell
python tools/audit_starcore_native.py --scripts-zip "D:\SteamLibrary\steamapps\common\Don't Starve Together\data\databundles\scripts.zip"
```

重建图片后运行 `python tools/check_assets.py`，核对编译帧、BILD 符号表的排序与哈希、贴图 mip 层、图集引用与可用的原图哈希，并检查生成的动作预览。

游戏内验证可从新建世界和已有存档分别开始：启用服务器 Mod、选择超人，检查开局装备、采集、夜视、白天回血、热视线，以及飞行跨海与洞穴断层、安全着陆、地图瞬移和成功／失败提示；再检查冰冻吐息的嘴部起点、冻结／免冻、友方灭火、营火保留，状态面板的位置／缩放／装备状态／复活倒计时，以及戴帽、骑乘、洞穴切换、摄像机转向、保存读取、暂停与远程玩家加入。自动检查和几何预览不能替代这些游戏操作。

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
