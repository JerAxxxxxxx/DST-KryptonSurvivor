local G = GLOBAL
local language = GetModConfigData("language") or "auto"
if language == "auto" then
    local locale = G.LanguageTranslator and G.LanguageTranslator.defaultlang or "en"
    language = (locale == "zh" or locale == "zhr" or locale == "zht" or locale == "chs" or locale == "cht") and "zh" or "en"
end

G.TUNING.KRYPTON_SURVIVOR = {
    health = 10000,
    hunger = 10000,
    sanity = 10000,
    speed = GetModConfigData("speed_multiplier") or 1.5,
    staff_damage = GetModConfigData("staff_damage") or 2000,
    work_efficiency = 10,
    staff_range = 6,
    staff_aoe_radius = 5,
    daylight_sanity_regen = 100,
    daylight_health_regen = 100,
    heatvision_damage = GetModConfigData("heatvision_damage") or 2000,
    heatvision_range = 20,
    heatvision_width = 0.8,
    heatvision_interval = 0.35,
    flight_enabled = GetModConfigData("flight_enabled") ~= false,
    flight_toggle_interval = 0.35,
    map_teleport_enabled = GetModConfigData("map_teleport_enabled") ~= false,
    map_teleport_interval = 0.35,
    starcore_revive_cooldown = G.TUNING.TOTAL_DAY_TIME,
}

PrefabFiles = { "krypton_survivor", "krypton_staff", "krypton_heatvision_fx", "krypton_starcore_amulet" }
Assets = {
    Asset("ANIM", "anim/krypton_survivor.zip"),
    Asset("ANIM", "anim/ghost_wilson_build.zip"),
    Asset("ATLAS", "bigportraits/krypton_survivor.xml"),
    Asset("IMAGE", "bigportraits/krypton_survivor.tex"),
    Asset("ATLAS", "images/avatars/avatar_krypton_survivor.xml"),
    Asset("IMAGE", "images/avatars/avatar_krypton_survivor.tex"),
    Asset("ATLAS", "images/avatars/avatar_ghost_krypton_survivor.xml"),
    Asset("IMAGE", "images/avatars/avatar_ghost_krypton_survivor.tex"),
    Asset("ATLAS", "images/avatars/self_inspect_krypton_survivor.xml"),
    Asset("IMAGE", "images/avatars/self_inspect_krypton_survivor.tex"),
    Asset("ATLAS", "images/saveslot_portraits/krypton_survivor.xml"),
    Asset("IMAGE", "images/saveslot_portraits/krypton_survivor.tex"),
    Asset("ATLAS", "images/selectscreen_portraits/krypton_survivor.xml"),
    Asset("IMAGE", "images/selectscreen_portraits/krypton_survivor.tex"),
    Asset("ATLAS", "images/selectscreen_portraits/krypton_survivor_silho.xml"),
    Asset("IMAGE", "images/selectscreen_portraits/krypton_survivor_silho.tex"),
    Asset("ATLAS", "images/names_krypton_survivor.xml"),
    Asset("IMAGE", "images/names_krypton_survivor.tex"),
    Asset("ATLAS", "images/names_gold_krypton_survivor.xml"),
    Asset("IMAGE", "images/names_gold_krypton_survivor.tex"),
    Asset("ATLAS", "images/inventoryimages/krypton_starcore_amulet.xml"),
    Asset("IMAGE", "images/inventoryimages/krypton_starcore_amulet.tex"),
}

local S = G.STRINGS
local zh = language == "zh"
S.NAMES.KRYPTON_SURVIVOR = zh and "超人" or "Superman"
S.NAMES.KRYPTON_STAFF = zh and "拉奥之锋" or "Rao's Edge"
S.NAMES.KRYPTON_STARCORE_AMULET = zh and "星核护符" or "Starcore Amulet"
S.RECIPE_DESC.KRYPTON_STARCORE_AMULET = zh
    and "保持干燥与安全体温，为生命保留一道星光。"
    or "Stay dry and comfortable, and return from death."
S.KRYPTON_STARCORE = zh and {
    REVIVED = "星核护符已将我复活，1个游戏日后再次就绪。",
    READY = "星核护符已就绪。",
    COOLDOWN = "星核护符正在恢复，暂时无法再次复活。",
} or {
    REVIVED = "The Starcore revived me. It will be ready in one game day.",
    READY = "The Starcore Amulet is ready.",
    COOLDOWN = "The Starcore is recovering and cannot revive me yet.",
}
S.CHARACTER_TITLES.krypton_survivor = zh and "超人 · 氪星幸存者" or "Superman · Krypton Survivor"
S.CHARACTER_NAMES.krypton_survivor = S.NAMES.KRYPTON_SURVIVOR
S.CHARACTER_DESCRIPTIONS.krypton_survivor = zh
    and "*超高属性、完整夜视、白天恢复\n*热视线 R，飞行切换 V（按键可配置）\n*Ctrl＋地图右键瞬移\n*拉奥之锋：范围攻击与采集"
    or "*Superpowered stats, night vision and daytime recovery\n*Heat vision R; flight toggle V (keys configurable)\n*Ctrl + right-click the map to teleport\n*Rao's Edge: area attacks and harvesting"
S.CHARACTER_QUOTES.krypton_survivor = zh and '"希望，也能照亮这片荒野。"' or '"Hope can light this wilderness."'
S.CHARACTER_SURVIVABILITY.krypton_survivor = zh and "超能力体验" or "Superpowered"
S.SKIN_NAMES.krypton_survivor_none = S.NAMES.KRYPTON_SURVIVOR

-- Reuse the base game's speech tables until custom dialogue is written.
S.CHARACTERS.KRYPTON_SURVIVOR = G.deepcopy(S.CHARACTERS.GENERIC)
for _, speech in pairs(S.CHARACTERS) do
    if speech.DESCRIBE then
        speech.DESCRIBE.KRYPTON_STAFF = zh and "氪星的力量，尽在掌握。" or "The power of Krypton, in one hand."
        speech.DESCRIBE.KRYPTON_STARCORE_AMULET = {
            GENERIC = zh and "保持干燥与安全体温，星核还会在死亡后唤回我。"
                or "It keeps me dry and comfortable, and can bring me back from death.",
            COOLDOWN = S.KRYPTON_STARCORE.COOLDOWN,
        }
        speech.DESCRIBE.KRYPTON_SURVIVOR = G.deepcopy(speech.DESCRIBE.WILSON or speech.DESCRIBE.PLAYER)
    end
end

AddRecipe2("krypton_starcore_amulet", {
    G.Ingredient("goldnugget", 3), G.Ingredient("nightmarefuel", 2), G.Ingredient("redgem", 1),
}, G.TECH.NONE, {
    builder_tag = "kryptonian",
    atlas = "images/inventoryimages/krypton_starcore_amulet.xml",
    image = "krypton_starcore_amulet.tex",
}, { "CHARACTER" })

AddMinimapAtlas("images/avatars/avatar_krypton_survivor.xml")
-- The frontend preview does not use the player's server-side skinner component.
AddClassPostConstruct("widgets/skinspuppet", function(puppet)
    local set_skins = puppet.SetSkins
    puppet.SetSkins = function(self, prefab, base, clothing, skip_emote, mode, curse)
        if prefab == "krypton_survivor" then
            return set_skins(self, prefab, nil, clothing, skip_emote, mode, curse)
        end
        return set_skins(self, prefab, base, clothing, skip_emote, mode, curse)
    end
end)
AddModCharacter("krypton_survivor", "MALE")

local HeatVision = require("krypton_heatvision")
local Flight = require("krypton_flight")
local MapTeleport = require("krypton_map_teleport")
-- A stable namespace works for both local and Workshop folder names.
local rpc_namespace = "KryptonSurvivor"
AddModRPCHandler(rpc_namespace, "HeatVision", HeatVision.Cast)
local ability_messages = zh and {
    flight_on = "飞行已开启。",
    flight_off = "已经着陆。",
    cannot_land = "这里无法着陆，先飞回陆地或船上。",
    riding = "先下坐骑，再使用这项能力。",
    invalid_ground = "这里没有安全的瞬移落点。",
    teleported = "瞬移成功，已抵达目标位置。",
    blocked = "落点被挡住了，换个位置。",
    restricted = "无法穿过这里的特殊屏障。",
    paused = "游戏仍在暂停，请恢复游戏后再瞬移。",
    busy = "请先结束当前动作，再使用瞬移。",
    controls_disabled = "人物暂时无法操作，请恢复控制后再瞬移。",
    unavailable = "当前人物状态无法使用这项能力。",
    disabled = "服务器已关闭这项能力。",
} or {
    flight_on = "Flight enabled.",
    flight_off = "Landed.",
    cannot_land = "Fly back to land or a boat before landing.",
    riding = "Dismount before using this ability.",
    invalid_ground = "There is no safe teleport destination here.",
    teleported = "Teleported to the selected location.",
    blocked = "That spot is blocked. Try another location.",
    restricted = "This special barrier blocks teleportation.",
    paused = "The game is paused. Resume before teleporting.",
    busy = "Finish your current action before teleporting.",
    controls_disabled = "Regain character control before teleporting.",
    unavailable = "This ability is unavailable in your current state.",
    disabled = "The server has disabled this ability.",
}
local function SayAbilityResult(player, reason)
    if player ~= nil and player:IsValid() and player.prefab == "krypton_survivor"
        and not player:HasTag("playerghost") and player.components.talker ~= nil
        and ability_messages[reason] ~= nil then
        player.components.talker:Say(ability_messages[reason])
    end
end
AddModRPCHandler(rpc_namespace, "ToggleFlight", function(player)
    local success, reason = Flight.Toggle(player)
    SayAbilityResult(player, success and (Flight.IsFlying(player) and "flight_on" or "flight_off") or reason)
end)
AddModRPCHandler(rpc_namespace, "MapTeleport", function(player, x, z)
    local success, reason = MapTeleport.Cast(player, x, z)
    if success then
        SayAbilityResult(player, "teleported")
    else
        SayAbilityResult(player, reason)
        -- Log only the rejection category, without player IDs or coordinates.
        if reason ~= "cooldown" then print("[Krypton Survivor] MapTeleport rejected: " .. tostring(reason)) end
    end
end)
local key_name = GetModConfigData("heatvision_key", true) or "KEY_R"
local heatvision_keys = { KEY_R = G.KEY_R, KEY_G = G.KEY_G, KEY_Z = G.KEY_Z }
local heatvision_key = key_name ~= "disabled" and (heatvision_keys[key_name] or G.KEY_R) or nil
require("krypton_heatvision_input")(G, heatvision_key, function(x, z)
    SendModRPCToServer(GetModRPC(rpc_namespace, "HeatVision"), x, z)
end)
local flight_key_name = GetModConfigData("flight_key", true) or "KEY_V"
local flight_keys = { KEY_V = G.KEY_V, KEY_B = G.KEY_B }
local flight_key = flight_key_name ~= "disabled" and (flight_keys[flight_key_name] or G.KEY_V) or nil
require("krypton_flight_input")(G, flight_key, function()
    SendModRPCToServer(GetModRPC(rpc_namespace, "ToggleFlight"))
end)
local map_mode = GetModConfigData("map_teleport_input", true) or "ctrl_right"
AddClassPostConstruct("screens/mapscreen", require("krypton_map_teleport_input")(G, map_mode, function(x, z)
    SendModRPCToServer(GetModRPC(rpc_namespace, "MapTeleport"), x, z)
end))
print("[Krypton Survivor] Registered krypton_survivor; version 0.7.2")
