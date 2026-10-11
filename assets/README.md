# 素材来源

项目使用以下原图，正式源文件保存在 `assets/source/`：

| 用途 | 正式源文件 | 原始文件名 |
| --- | --- | --- |
| 头部三视图、立绘、头像 | [source/superman-motion.jpg](source/superman-motion.jpg) | Gemini_Generated_Image_4v9kem4v9kem4v9k.jpg |
| 躯干、披风、四肢和握持手 | [source/superman-standing.jpg](source/superman-standing.jpg) | Gemini_Generated_Image_o4a0r3o4a0r3o4a0.jpg |
| 拉奥之锋 | [source/raos-edge.png](source/raos-edge.png) | Code_Generated_Image (2).png |
| 悬浮待机、飞行移动的三方向完整姿态 | [source/superman-flight.jpg](source/superman-flight.jpg) | Gemini_Generated_Image_u7i1k8u7i1k8u7i1.jpg |
| 吃东西时的张嘴、咀嚼及满足表情 | [source/superman-eat.jpg](source/superman-eat.jpg) | eat.jpg |

正式源文件仅调整文件名和存放目录，字节内容与收到的原图完全相同。角色身份为 DC 超人；部分图片由 Gemini 生成，原始文件名不用于推断生成模型的具体版本。

根目录 MIT 许可证用于项目代码和文档。人物图、武器图及其衍生贴图保留此处的来源说明，不因收录到仓库而声明为项目原创或自动改用代码许可证。

slices.json 是可修改的源选区。选区以 1024×341 为坐标参考，实际从高分辨率原图切取。头部五官已包含在原图头部中，额外 face、hair 符号透明，避免重复五官与头发。

允许的处理是抠图、选区、旋转、镜像、缩放和锚点调整。正面左侧披风被手臂遮住的部分，复用原图右侧披风的镜像像素。移动手臂会排除背后红披风的像素。未绘制新的线条、五官、衣服或肌肉。

飞行原图为 JPG，灰白棋盘格是图片中的背景像素，并不是真实透明通道。`tools/build_flight_assets.py` 通过边缘连通背景抠除棋盘格，再从原图提取六个完整姿态：正面、侧面、背面的悬浮待机和飞行移动。选区、缩放与锚点均记录在 `slices.json`；飞行循环只将整张姿态上下平移三个像素，没有重画或补画人物。侧面移动直接使用原图中的横向飞行姿态。

`krypton_flight.zip` 中的 BILD 贴图和 ANIM 动作由上述工具从原图独立生成，包含两个自定义动作名、每个动作的三个方向。沿用 `wilson` 动作库名称便于与人物普通动作切换，未复制游戏的动画帧。陆地模型、头像和武器编译资源保持各自原有来源。

吃东西的三个正面头部来自用户提供的 `eat.jpg`，生成工具与模型版本未另行注明。`tools/build_eating_assets.py` 去除 JPG 棋盘格背景、提取原有像素并统一眼睛锚点，编译为 `krypton_eating.zip`。这个包只包含自有头部贴图与 BILD 数据，不包含原版动画；身体、手、食物及声音继续使用已安装游戏的吃饭动作。原图与既有人物、头像、武器和飞行贴图保持不变。

星核护符复用 `source/raos-edge.png` 中央的橙色发光核，仅在 `slices.json` 的 `starcore` 与 `starcore-core` 中记录选区和缩放位置；没有新增绘制项链或饰品像素。`tools/build_starcore_assets.py` 生成自有 `krypton_starcore_build.zip`、物品图集和忽略的编译预览。原版 `amulets.zip` 动作仅从本机读取或运行时加载，不随仓库分发。

ui/ 中的名称 PNG 是早期已有的 SUPERMAN 文字素材，只用于名称界面，不是人物绘制来源。

热视线的眼部定位记录在 `slices.json` 的 `heatvision` 段，由构建工具转换为头部局部像素坐标。光束与眼部亮光运行时加载已安装游戏的 `wagdrone_laserwire_fx` 和 `bishop_attack`；角色的声音、幽灵与通用动作也使用游戏运行时资源。Mod 只提供自有的编译贴图、特效实体与玩法逻辑，不复制游戏原版动画、贴图或参考 Mod 美术。

`tools/preview_heatvision.py` 在内存中读取本机游戏资源，与编译人物像素合成定位预览。切片、动作预览和几何检查输出保存在忽略的 `build/`，不进入发布包。构建命令见 [构建说明](../docs/build.md)。
