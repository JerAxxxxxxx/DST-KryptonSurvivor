# 素材来源

发布版使用用户在 user-pic 中提供的素材：

| 用途 | 原文件 |
| --- | --- |
| 头部三视图、立绘、头像 | Gemini_Generated_Image_4v9kem4v9kem4v9k.jpg |
| 躯干、披风、四肢和握持手 | Gemini_Generated_Image_o4a0r3o4a0r3o4a0.jpg |
| 拉奥之锋 | Code_Generated_Image (2).png |
| 其他原图备选 | Code_Generated_Image.png、Code_Generated_Image (1).png、Gemini_Generated_Image_4r62ou4r62ou4r62.jpg |

这些文件按用户原样保留。文件名不用于推断生成模型的具体版本。角色身份为 DC 超人，用户说明部分图片由 Gemini 生成。2026-10-02，用户已同意六张原图收入未来 GitHub 仓库，并成功上传创意工坊 0.4.2；后续更新记录见 docs/workshop.md。

根目录 MIT 许可证用于项目代码和文档。人物图、武器图及其衍生贴图保留此处的来源说明，不因收录到仓库而声明为项目原创或自动改用代码许可证。

slices.json 是可修改的源选区。选区以 1024×341 为坐标参考，实际从高分辨率原图切取。头部五官已包含在原图头部中，额外 face、hair 符号透明，避免重复五官与头发。

允许的处理是抠图、选区、旋转、镜像、缩放和锚点调整。正面左侧披风被手臂遮住的部分，复用原图右侧披风的镜像像素。移动手臂会排除背后红披风的像素。未绘制新的线条、五官、衣服或肌肉。

ui/ 中的名称 PNG 是早期已有的 SUPERMAN 文字素材，只用于名称界面，不是人物绘制来源。

0.5.0 热视线通过游戏本机的 anim/wagdrone_laserwire_fx.zip 加载原版光束动画，Mod 只提供短暂特效实体及独立伤害逻辑。游戏原版动画与贴图没有复制到发布包。

0.5.1 的眼部定位记录在 slices.json 的 heatvision 段，由构建工具转换为头部局部像素坐标。激光与眼部亮光运行时使用游戏的 wagdrone_laserwire_fx 和 bishop_attack，均未复制入 mod/。tools/preview_heatvision.py 只将本机资源与编译人物合成定位预览，输出属于忽略的 build/。

旧 SVG 人物、电影参考图、其他 Mod 导出的研究素材及历史抠图已移入本机 archive/legacy-tree，并有整理前的快照 archive/before-0.4.1.zip。332 个归档文件均已逐字节核验，发布包不使用它们。
