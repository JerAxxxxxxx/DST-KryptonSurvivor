name = "Krypton Survivor · 氪星幸存者"
description = "超人测试版 / Superman prototype\n黑暗形态切换（默认 H）、飞行（默认 V）、Ctrl＋地图右键瞬移、热视线（R）、冰冻吐息（X）、能力状态面板、拉奥之锋、星核护符、完整夜视和白天恢复。\nDark form toggle (H), flight (V), Ctrl + map right-click teleport, heat vision (R), frost breath (X), ability HUD, Rao's Edge, Starcore Amulet, night vision and daytime recovery."
author = "Krypton Survivor Project"
version = "0.11.0"
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
        name = "staff_range",
        label = "战斧攻击距离 / Axe attack range",
        hover = "服务器统一近战距离，默认6。 / Server-wide melee reach; default 6.",
        options = {
            { description = "3", data = 3 },
            { description = "6", data = 6 },
            { description = "10", data = 10 },
            { description = "16", data = 16 },
        },
        default = 6,
    },
    {
        name = "staff_aoe_radius",
        label = "战斧范围伤害半径 / Axe splash radius",
        hover = "服务器统一；0关闭范围伤害，保留主目标攻击。默认5。 / Server-wide; 0 disables splash, keeping the primary hit. Default 5.",
        options = {
            { description = "0：关闭 / Off", data = 0 },
            { description = "3", data = 3 },
            { description = "5", data = 5 },
            { description = "8", data = 8 },
            { description = "12", data = 12 },
        },
        default = 5,
    },
    {
        name = "frostbreath_coldness",
        label = "吐息冷量 / Frost breath coldness",
        hover = "服务器统一每次吐息冷量，保留原生怪物抗性。默认2。 / Server-wide coldness per cast; native resistance applies. Default 2.",
        options = {
            { description = "1", data = 1 },
            { description = "2", data = 2 },
            { description = "4", data = 4 },
            { description = "8", data = 8 },
        },
        default = 2,
    },
    {
        name = "daylight_health_regen",
        label = "白天回血 / Daytime health recovery",
        hover = "服务器统一每模拟秒恢复量，仅地表白天；0关闭。默认100。 / Server-wide health per simulation second, surface daytime only; 0 disables. Default 100.",
        options = {
            { description = "0：关闭 / Off", data = 0 },
            { description = "10 / 秒 / sec", data = 10 },
            { description = "50 / 秒 / sec", data = 50 },
            { description = "100 / 秒 / sec", data = 100 },
            { description = "500 / 秒 / sec", data = 500 },
        },
        default = 100,
    },
    {
        name = "daylight_sanity_regen",
        label = "白天回理智 / Daytime sanity recovery",
        hover = "服务器统一每模拟秒恢复量，仅正常形态地表白天；0关闭。黑暗形态仍维持低理智。默认100。 / Server-wide sanity per simulation second, normal form in surface daytime; 0 disables. Dark form stays low. Default 100.",
        options = {
            { description = "0：关闭 / Off", data = 0 },
            { description = "10 / 秒 / sec", data = 10 },
            { description = "50 / 秒 / sec", data = 50 },
            { description = "100 / 秒 / sec", data = 100 },
            { description = "500 / 秒 / sec", data = 500 },
        },
        default = 100,
    },
    {
        name = "darkform_key",
        label = "黑暗形态按键 / Dark form key",
        options = {
            { description = "H", data = "KEY_H" },
            { description = "J", data = "KEY_J" },
            { description = "K", data = "KEY_K" },
            { description = "关闭按键 / Disable key", data = "disabled" },
        },
        default = "KEY_H",
        client = true,
    },
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
        name = "heatvision_ignite",
        label = "热视线点燃目标 / Heat vision ignition",
        options = {
            { description = "开启 / Enabled", data = true },
            { description = "关闭 / Disabled", data = false },
        },
        default = true,
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
