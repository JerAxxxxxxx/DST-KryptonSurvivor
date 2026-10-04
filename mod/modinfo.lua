name = "Krypton Survivor · 氪星幸存者"
description = "超人测试版 / Superman prototype\n热视线（默认 R）、拉奥之锋、完整夜视、白天回血与回理智。\nHeat vision (R), Rao's Edge, full night vision and daytime health/sanity recovery."
author = "Krypton Survivor Project"
version = "0.5.1"
api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false
client_only_mod = false
all_clients_require_mod = true
server_filter_tags = { "character", "Krypton Survivor" }

configuration_options = {
    {
        name = "heatvision_key",
        label = "热视线按键 / Heat vision key",
        options = {
            { description = "R", data = "KEY_R" },
            { description = "G", data = "KEY_G" },
            { description = "Z", data = "KEY_Z" },
            { description = "关闭 / Disabled", data = "disabled" },
        },
        default = "KEY_R",
        client = true,
    },
    {
        name = "heatvision_damage",
        label = "热视线伤害 / Heat vision damage",
        options = {
            { description = "2000", data = 2000 },
            { description = "10000", data = 10000 },
            { description = "50000", data = 50000 },
        },
        default = 2000,
    },
    {
        name = "language",
        label = "语言 / Language",
        options = {
            { description = "自动 / Auto", data = "auto" },
            { description = "中文", data = "zh" },
            { description = "English", data = "en" },
        },
        default = "auto",
    },
    {
        name = "staff_damage",
        label = "拉奥之锋伤害 / Axe damage",
        options = {
            { description = "2000", data = 2000 },
            { description = "10000", data = 10000 },
            { description = "50000", data = 50000 },
        },
        default = 2000,
    },
    {
        name = "speed_multiplier",
        label = "移速倍率 / Movement speed",
        options = {
            { description = "1.5x", data = 1.5 },
            { description = "2x", data = 2 },
            { description = "3x", data = 3 },
        },
        default = 1.5,
    },
}
