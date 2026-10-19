name = "Krypton Survivor · 氪星幸存者"
description = "超人测试版 / Superman prototype\n飞行（默认 V）、Ctrl＋地图右键瞬移、热视线（R）、冰冻吐息（X）、能力状态面板、拉奥之锋、星核护符、完整夜视和白天恢复。\nFlight (V), Ctrl + map right-click teleport, heat vision (R), frost breath (X), ability HUD, Rao's Edge, Starcore Amulet, night vision and daytime recovery."
author = "Krypton Survivor Project"
version = "0.8.2"
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
        name = "frostbreath_enabled",
        label = "冰冻吐息能力 / Frost breath",
        options = {
            { description = "开启 / Enabled", data = true },
            { description = "关闭 / Disabled", data = false },
        },
        default = true,
    },
    {
        name = "frostbreath_key",
        label = "冰冻吐息按键 / Frost breath key",
        options = {
            { description = "X", data = "KEY_X" },
            { description = "C", data = "KEY_C" },
            { description = "N", data = "KEY_N" },
            { description = "关闭按键 / Disable key", data = "disabled" },
        },
        default = "KEY_X",
        client = true,
    },
    {
        name = "status_hud_enabled",
        label = "能力状态面板 / Ability status HUD",
        options = {
            { description = "显示 / Show", data = true },
            { description = "隐藏 / Hide", data = false },
        },
        default = true,
        client = true,
    },
    {
        name = "status_hud_scale",
        label = "能力面板大小 / Ability HUD scale",
        options = {
            { description = "80%", data = 0.8 },
            { description = "100%", data = 1 },
            { description = "120%", data = 1.2 },
        },
        default = 1,
        client = true,
    },
    {
        name = "status_hud_position",
        label = "能力面板位置 / Ability HUD position",
        options = {
            { description = "右上方状态栏下 / Below status meters", data = "default" },
            { description = "向左移 / Shift left", data = "left" },
            { description = "向下移 / Shift down", data = "lower" },
        },
        default = "default",
        client = true,
    },
    {
        name = "flight_enabled",
        label = "飞行能力 / Flight",
        options = {
            { description = "开启 / Enabled", data = true },
            { description = "关闭 / Disabled", data = false },
        },
        default = true,
    },
    {
        name = "flight_key",
        label = "飞行切换按键 / Flight toggle key",
        options = {
            { description = "V", data = "KEY_V" },
            { description = "B", data = "KEY_B" },
            { description = "关闭按键 / Disable key", data = "disabled" },
        },
        default = "KEY_V",
        client = true,
    },
    {
        name = "map_teleport_enabled",
        label = "地图瞬移能力 / Map teleport",
        options = {
            { description = "开启 / Enabled", data = true },
            { description = "关闭 / Disabled", data = false },
        },
        default = true,
    },
    {
        name = "map_teleport_input",
        label = "地图瞬移操作 / Map teleport input",
        options = {
            { description = "Ctrl＋右键 / Ctrl + right-click", data = "ctrl_right" },
            { description = "关闭操作 / Disable input", data = "disabled" },
        },
        default = "ctrl_right",
        client = true,
    },
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
