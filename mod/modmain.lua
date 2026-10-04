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
}

PrefabFiles = { "krypton_survivor", "krypton_staff", "krypton_heatvision_fx" }
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
}

local S = G.STRINGS
local zh = language == "zh"
S.NAMES.KRYPTON_SURVIVOR = zh and "超人" or "Superman"
S.NAMES.KRYPTON_STAFF = zh and "拉奥之锋" or "Rao's Edge"
S.CHARACTER_TITLES.krypton_survivor = zh and "超人 · 氪星幸存者" or "Superman · Krypton Survivor"
S.CHARACTER_NAMES.krypton_survivor = S.NAMES.KRYPTON_SURVIVOR
S.CHARACTER_DESCRIPTIONS.krypton_survivor = zh
    and "*生命、饥饿、理智上限各 10000\n*完整夜视，白天回血、恢复理智\n*热视线：按 R 远程攻击（按键可配置）\n*拉奥之锋：远距离范围攻击与采集"
    or "*10,000 health, hunger and sanity\n*Full night vision and daytime health/sanity recovery\n*Heat vision: press R to fire (key configurable)\n*Rao's Edge: area attacks and harvesting"
S.CHARACTER_QUOTES.krypton_survivor = zh and '"希望，也能照亮这片荒野。"' or '"Hope can light this wilderness."'
S.CHARACTER_SURVIVABILITY.krypton_survivor = zh and "超能力体验" or "Superpowered"
S.SKIN_NAMES.krypton_survivor_none = S.NAMES.KRYPTON_SURVIVOR

-- Reuse the base game's speech tables until custom dialogue is written.
S.CHARACTERS.KRYPTON_SURVIVOR = G.deepcopy(S.CHARACTERS.GENERIC)
for _, speech in pairs(S.CHARACTERS) do
    if speech.DESCRIBE then
        speech.DESCRIBE.KRYPTON_STAFF = zh and "氪星的力量，尽在掌握。" or "The power of Krypton, in one hand."
        speech.DESCRIBE.KRYPTON_SURVIVOR = G.deepcopy(speech.DESCRIBE.WILSON or speech.DESCRIBE.PLAYER)
    end
end

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
-- A stable namespace works for both local and Workshop folder names.
local rpc_namespace = "KryptonSurvivor"
AddModRPCHandler(rpc_namespace, "HeatVision", HeatVision.Cast)
local key_name = GetModConfigData("heatvision_key", true) or "KEY_R"
local heatvision_keys = { KEY_R = G.KEY_R, KEY_G = G.KEY_G, KEY_Z = G.KEY_Z }
local heatvision_key = key_name ~= "disabled" and (heatvision_keys[key_name] or G.KEY_R) or nil
require("krypton_heatvision_input")(G, heatvision_key, function(x, z)
    SendModRPCToServer(GetModRPC(rpc_namespace, "HeatVision"), x, z)
end)
print("[Krypton Survivor] Registered krypton_survivor; version 0.5.1")
