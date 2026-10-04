# Steam 创意工坊

- 名称：Krypton Survivor · 氪星幸存者。
- 条目 ID：**3811663817**。
- 链接：https://steamcommunity.com/sharedfiles/filedetails/?id=3811663817
- 目标游戏：Don't Starve Together，App ID 322330。
- 首次上传版本：**0.4.2**。
- 已确认上传的版本：**0.4.2**；本地 **0.5.1** 热视线视觉修正尚未上传，也没有 0.5.0 上传成功记录。
- 上传时间：2026-10-02 10:26:56（本机日志时间）。
- 上传状态：用户确认成功；ModUploader.log 的创建和提交结果均为 EResult 1，最终显示 Publish complete。
- 2026-10-03：用户确认已处理页面功能介绍；具体语言覆盖尚未确认。
- 页面可见性尚未单独确认；上传成功不代表已核对公开访问或所有客户端可用。

2026-10-04，用户已完成本地 0.5.1 复测，反馈“暂无问题”，准备发布新版本。当前源码、本地安装与安装包的 33 个文件一致，版本均为 0.5.1；尚未收到此次上传成功确认。用户的总体复测反馈不等于全部专项联机项目已逐一验证。

0.5.1 更新同一条目即可。更新说明与可追加到工坊介绍的技能说明已准备，见 [0.5.1 发布文案](workshop-release-0.5.1.md)。本次相对工坊已确认的 0.4.2 新增人物自带热视线及眼部视觉修正；无需独立装备，按键和伤害可配置，原版火焰可能蔓延。

## 上传文件

- Update Data：`D:\Develop\Code\Vibe\KryptonSurvivor\mod` 文件夹，选择包含 modinfo.lua 与 modmain.lua 的这一层；不要选择项目根目录或 ZIP 安装包。
- Update Preview Image：`build/workshop/preview.jpg`，512×512，标准 RGB、非渐进 JPG，71028 字节。
- 封面生成：`python tools/prepare_workshop_preview.py`。原图保持不变，裁切位置见 `assets/slices.json`。

## 更新现有条目

1. 修改并检查：Lua 修改后运行 `npm run check`；游戏美术修改后重建资源、运行 `tools/check_assets.py` 并查看编译动作预览。
2. 在本地测试通过后更新 `mod/modinfo.lua` 的版本，同步 package.json、package-lock.json 与变更记录。
3. 运行上传工具，目标游戏选择 Don't Starve Together，在列表选中当前条目并点击 Edit。
4. 勾选 Update Data，确认选择 `mod/`。仅在封面或页面资料发生变化时勾选对应更新选项，避免覆盖已在工坊编辑的说明。
5. 提交新版本并确认成功，记录版本和更新内容。后续继续使用 **3811663817**，无需重新 Add。
6. 房主和参与测试的朋友确认下载完成后重启游戏，在测试世界中验证新版本。测试工坊版时只启用该工坊条目，避免同时加载本地同名版本。

上传工具中 Update Data、Update Preview Image 与 Update Details 的作用见 [Klei 官方上传教程](https://kleiforums.com/forums/topic/26494-dont-starve-steam-workshop-uploader/)。本次数据更新选择现有条目的 Edit 和 Update Data；已有封面保持原样，页面介绍可在工坊网页追加热视线说明，避免用 modinfo.lua 的短说明覆盖现有详细介绍。

用户于 2026-10-04 明确授权上传 GitHub，已创建并推送公开仓库 [JerAxxxxxxx/DST-KryptonSurvivor](https://github.com/JerAxxxxxxx/DST-KryptonSurvivor)。GitHub 与 Steam 创意工坊分别更新；此记录不代表工坊 0.5.1 已上传成功。
