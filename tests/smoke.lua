local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end

local function deepcopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepcopy(v) end
    return out
end

Asset = function(kind, path) return { kind = kind, path = path } end
STRINGS = {
    NAMES = {}, RECIPE_DESC = {}, CHARACTER_TITLES = {}, CHARACTER_NAMES = {}, CHARACTER_DESCRIPTIONS = {},
    CHARACTER_QUOTES = {}, CHARACTER_SURVIVABILITY = {}, SKIN_NAMES = {},
    CHARACTERS = { GENERIC = { DESCRIBE = { WILSON = { GENERIC = "Hi %s" } } } },
}
TUNING = { TOTAL_DAY_TIME = 480 }
EQUIPSLOTS = { HANDS = "hands", BODY = "body" }
LanguageTranslator = { defaultlang = "zh" }
GLOBAL = { STRINGS = STRINGS, TUNING = TUNING, LanguageTranslator = LanguageTranslator, deepcopy = deepcopy,
    KEY_R = 114, KEY_G = 103, KEY_Z = 122, KEY_V = 118, KEY_X = 120, KEY_C = 99, KEY_N = 110,
    KEY_H = 104, KEY_J = 106, KEY_K = 107,
    TheNet = { IsDedicated = function() return true end, IsServerPaused = function() return false end },
    TECH = { NONE = {} }, Ingredient = function(name, amount) return { type = name, amount = amount } end }
TheNet = GLOBAL.TheNet
package.preload["krypton_config"] = function() return load_source("mod/scripts/krypton_config.lua") end
package.preload["krypton_heatvision"] = function() return load_source("mod/scripts/krypton_heatvision.lua") end
package.preload["krypton_combat_targets"] = function() return load_source("mod/scripts/krypton_combat_targets.lua") end
package.preload["krypton_heatvision_input"] = function() return load_source("mod/scripts/krypton_heatvision_input.lua") end
package.preload["krypton_flight_visual"] = function() return load_source("mod/scripts/krypton_flight_visual.lua") end
package.preload["krypton_eating_visual"] = function() return load_source("mod/scripts/krypton_eating_visual.lua") end
package.preload["krypton_tool_actions"] = function() return load_source("mod/scripts/krypton_tool_actions.lua") end
package.preload["krypton_starcore_starter"] = function() return load_source("mod/scripts/krypton_starcore_starter.lua") end
package.preload["krypton_eating_visual_data"] = function() return load_source("mod/scripts/krypton_eating_visual_data.lua") end
package.preload["krypton_flight"] = function() return load_source("mod/scripts/krypton_flight.lua") end
package.preload["krypton_darkform"] = function() return load_source("mod/scripts/krypton_darkform.lua") end
package.preload["krypton_darkform_input"] = function() return load_source("mod/scripts/krypton_darkform_input.lua") end
package.preload["krypton_flight_input"] = function() return load_source("mod/scripts/krypton_flight_input.lua") end
package.preload["krypton_map_teleport"] = function() return load_source("mod/scripts/krypton_map_teleport.lua") end
package.preload["krypton_map_teleport_input"] = function() return load_source("mod/scripts/krypton_map_teleport_input.lua") end
package.preload["krypton_frostbreath"] = function() return load_source("mod/scripts/krypton_frostbreath.lua") end
package.preload["krypton_frostbreath_input"] = function() return load_source("mod/scripts/krypton_frostbreath_input.lua") end
package.preload["krypton_ability_status"] = function() return load_source("mod/scripts/krypton_ability_status.lua") end
local installed_hud_options
package.preload["krypton_ability_hud"] = function()
    local hud = load_source("mod/scripts/krypton_ability_hud.lua")
    local install = hud.Install
    hud.Install = function(g, options)
        installed_hud_options = options
        return install(g, options)
    end
    return hud
end
package.preload["componentutil"] = function() return {} end
local ability_rpcs = {}
AddModRPCHandler = function(namespace, name, fn)
    assert(namespace == "KryptonSurvivor" and (name == "HeatVision" or name == "FrostBreath" or name == "ToggleFlight" or name == "MapTeleport" or name == "ToggleDarkForm"))
    ability_rpcs[name] = fn
end
local config = {}
local recipes = {}
AddRecipe2 = function(name, ingredients, tech, settings, filters)
    recipes[name] = { ingredients = ingredients, tech = tech, settings = settings, filters = filters }
end
GetModConfigData = function(name) return config[name] end
local added_character, puppet_hook, map_hook
AddModCharacter = function(name, gender, modes)
    assert(gender == "MALE" and modes == nil)
    added_character = name
end
AddMinimapAtlas = function() end
AddClassPostConstruct = function(path, callback)
    if path == "widgets/skinspuppet" then puppet_hook = callback
    elseif path == "screens/mapscreen" then map_hook = callback
    else error("unexpected UI hook: " .. path) end
end
load_source("mod/modmain.lua")
assert(added_character == "krypton_survivor")
assert(STRINGS.NAMES.KRYPTON_SURVIVOR == "超人")
assert(STRINGS.NAMES.KRYPTON_STAFF == "拉奥之锋")
assert(STRINGS.NAMES.KRYPTON_STARCORE_AMULET == "星核护符")
assert(TUNING.KRYPTON_SURVIVOR.starcore_revive_cooldown == 480)
local recipe = recipes.krypton_starcore_amulet
assert(recipe.settings.builder_tag == "kryptonian" and recipe.tech == GLOBAL.TECH.NONE)
assert(recipe.ingredients[1].type == "goldnugget" and recipe.ingredients[1].amount == 3)
assert(recipe.ingredients[2].type == "nightmarefuel" and recipe.ingredients[2].amount == 2)
assert(recipe.ingredients[3].type == "redgem" and recipe.ingredients[3].amount == 1)
assert(STRINGS.CHARACTER_TITLES.krypton_survivor == "超人 · 氪星幸存者")
assert(STRINGS.CHARACTERS.KRYPTON_SURVIVOR ~= STRINGS.CHARACTERS.GENERIC)
assert(type(ability_rpcs.HeatVision) == "function" and TUNING.KRYPTON_SURVIVOR.heatvision_damage == 2000)
assert(TUNING.KRYPTON_SURVIVOR.heatvision_ignite == true, "Ignition keeps its existing default")
assert(installed_hud_options.heatvision_key == "KEY_R" and installed_hud_options.frostbreath_key == "KEY_X")
assert(type(ability_rpcs.FrostBreath) == "function" and TUNING.KRYPTON_SURVIVOR.frostbreath_enabled == true)
assert(TUNING.KRYPTON_SURVIVOR.frostbreath_range == 8 and TUNING.KRYPTON_SURVIVOR.frostbreath_duration == 1)
assert(type(ability_rpcs.ToggleFlight) == "function" and type(ability_rpcs.MapTeleport) == "function")
assert(type(ability_rpcs.ToggleDarkForm) == "function" and TUNING.KRYPTON_SURVIVOR.darkform_sanity_percent == .05)
assert(installed_hud_options.darkform_key == "KEY_H")
assert(type(map_hook) == "function" and TUNING.KRYPTON_SURVIVOR.flight_enabled == true)
assert(TUNING.KRYPTON_SURVIVOR.map_teleport_enabled == true)
assert(TUNING.KRYPTON_SURVIVOR.staff_range == 6 and TUNING.KRYPTON_SURVIVOR.staff_aoe_radius == 5)
assert(TUNING.KRYPTON_SURVIVOR.frostbreath_coldness == 2)
assert(TUNING.KRYPTON_SURVIVOR.daylight_health_regen == 100 and TUNING.KRYPTON_SURVIVOR.daylight_sanity_regen == 100)
config.language = "en"
config.staff_damage = 10000
config.speed_multiplier = 2
config.heatvision_damage = 50000
config.heatvision_ignite = false
config.heatvision_key, config.frostbreath_key = "KEY_G", "KEY_N"
config.darkform_key = "KEY_J"
load_source("mod/modmain.lua")
assert(STRINGS.NAMES.KRYPTON_SURVIVOR == "Superman")
assert(STRINGS.NAMES.KRYPTON_STAFF == "Rao's Edge")
assert(STRINGS.NAMES.KRYPTON_STARCORE_AMULET == "Starcore Amulet")
assert(TUNING.KRYPTON_SURVIVOR.staff_damage == 10000 and TUNING.KRYPTON_SURVIVOR.speed == 2)
assert(TUNING.KRYPTON_SURVIVOR.heatvision_damage == 50000)
assert(TUNING.KRYPTON_SURVIVOR.heatvision_ignite == false, "Server config can disable ignition")
assert(installed_hud_options.darkform_key == "KEY_J")
assert(installed_hud_options.heatvision_key == "KEY_G" and installed_hud_options.frostbreath_key == "KEY_N",
    "HUD receives the same configured keys as actual input handlers")
config.heatvision_key, config.frostbreath_key = "disabled", "disabled"
config.darkform_key = "disabled"
load_source("mod/modmain.lua")
assert(installed_hud_options.darkform_key == "disabled")
assert(installed_hud_options.heatvision_key == "disabled" and installed_hud_options.frostbreath_key == "disabled")
config.heatvision_key, config.frostbreath_key = "unknown_key", "unknown_key"
config.darkform_key = "unknown_key"
load_source("mod/modmain.lua")
assert(installed_hud_options.darkform_key == "KEY_H")
assert(installed_hud_options.heatvision_key == "KEY_R" and installed_hud_options.frostbreath_key == "KEY_X",
    "Unknown saved keys show the same fallback as actual input handlers")

local preview = { SetSkins = function(self, prefab, base) self.prefab, self.base = prefab, base end }
puppet_hook(preview)
preview:SetSkins("krypton_survivor", nil)
assert(preview.prefab == "krypton_survivor" and preview.base == nil)
preview:SetSkins("wendy", "wendy_none")
assert(preview.prefab == "wendy" and preview.base == "wendy_none")

FRAMES, TILE_SCALE = 1 / 30, 4
GetTime = function() return 10 end
COLLISION = { LAND_OCEAN_LIMITS = 2, BOAT_LIMITS = 4 }
net_bool = function()
    return { state = false, value = function(self) return self.state end,
        set = function(self, value) self.state = value end }
end
local function net_uint()
    return { state = 0, value = function(self) return self.state end,
        set = function(self, value) assert(type(value) == "number"); self.state = value end }
end
net_byte, net_ushortint = net_uint, net_uint
TheWorld = { ismastersim = true, state = { isday = true }, cave = false,
    Map = { IsInMapBounds = function() return true end,
        GetSize = function() return 100, 100 end,
        GetTileCoordsAtPoint = function() return 50, 50 end },
    HasTag = function(self, tag) return tag == "cave" and self.cave end }
local common, master
package.preload["prefabs/player_common"] = function()
    return function(name, prefabs, assets, c, m)
        assert(name == "krypton_survivor")
        common, master = c, m
        return { name = name }
    end
end
load_source("mod/scripts/prefabs/krypton_survivor.lua")
local function make_player()
local player = {
    GUID = 1, prefab = "krypton_survivor", tags = { player = true },
    components = {}, replica = {}, periodic_tasks = {},
    MiniMapEntity = { SetIcon = function(self, value) self.icon = value end },
    AnimState = { SetBuild = function(self, value) self.build = value end,
        AddOverrideBuild = function(self, value) self.override_build = value end,
        IsCurrentAnimation = function() return false end },
    AddTag = function(self, tag) self.tags[tag] = true end,
    AddComponent = function(self, name)
        if name == "krypton_darkform" then
            self.components[name] = { IsDark = function() return self._krypton_dark_form:value() end }
            return
        end
        assert(name == "krypton_starcore")
        self.components[name] = { starter_granted = false,
            GetEquippedAmulet = function() return nil end,
            IsProtected = function() return false end,
            IsAutoReviving = function() return false end,
            GetCooldownRemaining = function() return 0 end }
    end,
    RemoveTag = function(self, tag) self.tags[tag] = nil end,
    DoTaskInTime = function(self, delay, fn) self.visiontask = fn end,
    DoPeriodicTask = function(self, period, fn)
        local task = { period = period, fn = fn, Cancel = function() end }
        self.periodic_tasks[#self.periodic_tasks + 1] = task
        self.regentask = fn
        return task
    end,
    ListenForEvent = function(self, event, fn) self.activation = fn end,
    HasTag = function(self, tag) return self.tags[tag] == true end,
    IsValid = function() return true end,
    Transform = { GetWorldPosition = function() return 0, 0, 0 end },
    GetCurrentPlatform = function() return nil end,
    Physics = { mask = 31,
        IsActive = function() return true end,
        GetCollisionMask = function(self) return self.mask end,
        ClearCollidesWith = function(self, flag) self.mask = self.mask - flag end,
        CollidesWith = function(self, flag) self.mask = self.mask + flag end },
}
for _, name in ipairs({ "health", "hunger", "sanity" }) do
    player.components[name] = {
        SetMaxHealth = function(self, value) self.max = value end,
        SetMax = function(self, value) self.max = value end,
        SetRate = function(self, value) self.rate = value end,
    }
end
Point = function(x, y, z) return { x = x, y = y, z = z } end
player.components.playervision = { PushForcedNightVision = function(self, source, priority, cc, blend, ambient, nofilter)
    self.forced = source == "krypton_survivor"
    assert(cc == nil and blend == false and nofilter == true, "Mole vision filter must stay disabled")
    assert(ambient.PHASE_COLOURS.default.day.colour.y == 230 / 255)
    assert(ambient.PHASE_COLOURS.spring.day.colour.y == 244 / 255)
    assert(ambient.CAVE_COLOUR.colour.x > 0.7)
end }
player.components.health.IsDead = function(self) return self.dead == true end
player.components.health.IsHurt = function(self) return self.hurt == true end
player.components.health.DoDelta = function(self, delta, overtime, cause)
    self.delta = delta
    self.calls = (self.calls or 0) + 1
    assert(overtime == true and cause == "krypton_sunlight")
end
player.components.sanity.percent, player.components.sanity.penalty = .4, 0
player.components.sanity.GetRealPercent = function(self) return self.percent end
player.components.sanity.GetPenaltyPercent = function(self) return self.penalty end
player.components.sanity.GetPercent = function(self) return self.forced_percent or self.percent end
player.components.sanity.DoDelta = function(self, delta)
    self.delta = delta
    self.calls = (self.calls or 0) + 1
    self.percent = math.max(0, math.min(1 - self.penalty, self.percent + delta / self.max))
end
player.components.skinner = { SetSkinMode = function(self, mode) self.mode = mode end }
player.components.locomotor = {
    pathcaps = { allowocean = false }, directdrive = false,
    enablegroundspeedmultiplier = true, triggerscreep = true, allow_platform_hopping = true,
    ResetPath = function() end,
    EnableGroundSpeedMultiplier = function(self, value) self.enablegroundspeedmultiplier = value end,
    SetTriggersCreep = function(self, value) self.triggerscreep = value end,
    SetAllowPlatformHopping = function(self, value) self.allow_platform_hopping = value end,
    SetExternalSpeedMultiplier = function(self, owner, key, value) self.mult = value end,
}
player.components.drownable = { enabled = true }
local starter = { prefab = "krypton_staff" }
local starter_amulet = { prefab = "krypton_starcore_amulet", components = { inventoryitem = { owner = player } } }
player.components.inventory = {
    FindItem = function(self, test) return test(starter) and starter or (test(starter_amulet) and starter_amulet or nil) end,
    GetEquippedItem = function(self, slot)
        if slot == EQUIPSLOTS.BODY then return self.body end
        return self.equipped
    end,
    Equip = function(self, item)
        if item == starter_amulet then self.body = item else self.equipped = item end
    end,
}
return player, starter, starter_amulet
end
local player, starter, starter_amulet = make_player()
common(player)
assert(player.tags.kryptonian and player.AnimState.build == "krypton_survivor")
player.visiontask(player)
assert(player.components.playervision.forced)
master(player)
assert(player._krypton_flying:value() and player.tags.flying and player.Physics.mask == 25)
assert(player.components.locomotor.directdrive and player.components.locomotor.pathcaps.allowocean)
assert(player.components.drownable.enabled == false)
player.components.health.hurt = true
player.regentask(player)
assert(player.components.sanity.delta == 100)
assert(player.components.health.delta == 100)
player._krypton_dark_form:set(true)
player.components.sanity.delta, player.components.health.delta = nil, nil
player.regentask(player)
assert(player.components.sanity.delta == nil, "Dark form must skip daylight sanity regeneration")
assert(player.components.health.delta == 100, "Dark form preserves daylight healing")
player._krypton_dark_form:set(false)
player.regentask(player)
assert(player.components.sanity.delta == 100, "Normal form resumes existing daylight recovery")
player.components.sanity.delta = nil
player.components.health.delta = nil
TheWorld.state.isday = false
player.regentask(player)
assert(player.components.sanity.delta == nil and player.components.health.delta == nil)
TheWorld.state.isday = true
player.tags.playerghost = true
player.regentask(player)
assert(player.components.sanity.delta == nil and player.components.health.delta == nil)
player.tags.playerghost = nil
player.components.health.dead = true
player.regentask(player)
assert(player.components.sanity.delta == nil and player.components.health.delta == nil)
player.components.health.dead = false
TheWorld.cave = true
player.regentask(player)
assert(player.components.sanity.delta == nil and player.components.health.delta == nil)
TheWorld.cave = false
player.components.health.hurt = false
player.regentask(player)
assert(player.components.health.delta == nil and player.components.sanity.delta == 100)
assert(player.components.health.max == 10000 and player.components.hunger.max == 10000)
assert(player.components.sanity.max == 10000 and player.components.sanity.rate_modifier == 0)
assert(player.components.hunger.rate == 0 and player.components.locomotor.mult == 2)
assert(#player.starting_inventory == 2 and player.starting_inventory[1] == "krypton_staff"
    and player.starting_inventory[2] == "krypton_starcore_amulet")
player:OnNewSpawn()
assert(player.components.inventory.equipped == starter)
assert(player.components.inventory.body == starter_amulet and player.components.krypton_starcore.starter_granted)
player.components.skinner.skin_data = {}
player.components.skinner:SetSkinMode("ghost_skin")
assert(player.components.skinner.skin_data.ghost_skin == "ghost_wilson_build")
player.components.skinner:SetSkinMode("normal_skin")
assert(player.components.skinner.skin_data.normal_skin == "krypton_survivor")

-- Drive the actual modmain configuration reader and the actual prefab master
-- hook together. Server values must reach recovery callbacks, including zero.
local numeric_fields = { "staff_range", "staff_aoe_radius", "frostbreath_coldness",
    "daylight_health_regen", "daylight_sanity_regen" }
local function configure(values)
    for _, name in ipairs(numeric_fields) do config[name] = values[name] end
    load_source("mod/modmain.lua")
    local result = make_player()
    common(result); master(result)
    result.components.health.hurt = true
    return result
end
local custom = configure({ staff_range = 10, staff_aoe_radius = 8, frostbreath_coldness = 4,
    daylight_health_regen = 50, daylight_sanity_regen = 500 })
assert(TUNING.KRYPTON_SURVIVOR.staff_range == 10 and TUNING.KRYPTON_SURVIVOR.staff_aoe_radius == 8)
assert(TUNING.KRYPTON_SURVIVOR.frostbreath_coldness == 4)
custom.regentask(custom)
assert(custom.components.health.delta == 50 and custom.components.sanity.delta == 500,
    "configured independent recovery values reach native component methods")
custom.components.sanity.delta, custom.components.health.delta = nil, nil
custom._krypton_dark_form:set(true)
custom.regentask(custom)
assert(custom.components.sanity.delta == nil and custom.components.health.delta == 50,
    "dark form retains priority over configured sanity recovery without disabling healing")
custom._krypton_dark_form:set(false)
local sanity = custom.components.sanity
sanity.percent = 1
sanity.delta = nil
local sanity_calls = sanity.calls
custom.regentask(custom)
assert(sanity.delta == nil and sanity.calls == sanity_calls,
    "full sanity must not emit redundant sanitydelta every simulated second")
sanity.percent, sanity.penalty, sanity.forced_percent = .75, .25, 0
custom.regentask(custom)
assert(sanity.calls == sanity_calls, "effective maximum uses real sanity, not a forced zero display")
sanity.percent = .74
custom.regentask(custom)
assert(sanity.delta == 500 and sanity.percent == .75,
    "the native sanity method clamps recovery at its penalty-adjusted maximum")
sanity_calls = sanity.calls
custom.regentask(custom)
assert(sanity.calls == sanity_calls, "reaching the effective cap stops subsequent delta events")

local health_only = configure({ daylight_health_regen = 10, daylight_sanity_regen = 0 })
health_only.regentask(health_only)
assert(health_only.components.health.delta == 10 and health_only.components.sanity.delta == nil,
    "zero sanity recovery does not turn off independent healing")
local sanity_only = configure({ daylight_health_regen = 0, daylight_sanity_regen = 50 })
sanity_only.regentask(sanity_only)
assert(sanity_only.components.health.delta == nil and sanity_only.components.sanity.delta == 50,
    "zero health recovery does not turn off independent sanity recovery")
sanity_only.components.sanity.delta = nil
sanity_only.tags.corpse = true
sanity_only.regentask(sanity_only)
assert(sanity_only.components.sanity.delta == nil, "a revivable corpse receives no daylight recovery")
local disabled = configure({ staff_aoe_radius = 0, daylight_health_regen = 0, daylight_sanity_regen = 0 })
assert(TUNING.KRYPTON_SURVIVOR.staff_aoe_radius == 0, "configured zero is preserved")
assert(#disabled.periodic_tasks == 2 and disabled.regentask == disabled._krypton_status_task.fn,
    "disabling both recovery values avoids creating an extra recovery timer")
for _, invalid in ipairs({ "500", false, -1, math.huge, -math.huge, 0 / 0, {} }) do
    local invalid_config = {}
    for _, name in ipairs(numeric_fields) do invalid_config[name] = invalid end
    local fallback = configure(invalid_config)
    assert(TUNING.KRYPTON_SURVIVOR.staff_range == 6 and TUNING.KRYPTON_SURVIVOR.staff_aoe_radius == 5)
    assert(TUNING.KRYPTON_SURVIVOR.frostbreath_coldness == 2)
    fallback.regentask(fallback)
    assert(fallback.components.health.delta == 100 and fallback.components.sanity.delta == 100,
        "invalid persisted server values safely recover the prior defaults")
end
configure({}) -- Preserve the established defaults for the existing staff tests.

ACTIONS = { CHOP = { id = "CHOP" }, MINE = { id = "MINE" }, HAMMER = { id = "HAMMER" }, DIG = { id = "DIG" } }
TheWorld = { ismastersim = true, state = { isnight = false }, cave = false,
    HasTag = function(self, tag) return tag == "cave" and self.cave end }
MakeInventoryPhysics = function() end
MakeInventoryFloatable = function() end
MakeHauntableLaunch = function() end
Prefab = function(name, fn) return { name = name, fn = fn } end
local function noop() end
function CreateEntity()
    local inst = { components = {}, tags = {}, tasks = {}, events = {}, watches = {} }
    inst.AnimState = { SetBank = noop, SetBuild = noop, PlayAnimation = noop }
    inst.Light = { Enable = function(self, value) self.enabled = value end,
        SetRadius = noop, SetFalloff = noop, SetIntensity = noop, SetColour = noop }
    inst.entity = { AddTransform = noop, AddAnimState = noop, AddSoundEmitter = noop,
        AddLight = noop, AddNetwork = noop, SetPristine = function() inst.pristine = true end }
    function inst:AddTag(tag) self.tags[tag] = true end
    function inst:DoTaskInTime(delay, fn) table.insert(self.tasks, fn) end
    function inst:WatchWorldState(key, fn) self.watches[key] = fn end
    function inst:ListenForEvent(key, fn) self.events[key] = fn end
    function inst:AddComponent(name)
        assert(self.pristine and TheWorld.ismastersim, "Server components leaked to client")
        local c = {}
        if name == "inventoryitem" then
            c.ChangeImageName = function(self, value) self.image = value end
            c.SetOnPutInInventoryFn = function(self, fn) self.onput = fn end
        elseif name == "equippable" then
            c.SetOnEquip = function(self, fn) self.onequip = fn end
            c.SetOnUnequip = function(self, fn) self.onunequip = fn end
            c.IsEquipped = function(self) return self.equipped == true end
        elseif name == "weapon" then
            c.SetDamage = function(self, value) self.damage = value end
            c.SetRange = function(self, attack, hit) self.attackrange, self.hitrange = attack, hit end
            c.SetOnAttack = function(self, fn) self.onattack = fn end
        elseif name == "tool" then
            c.actions = {}
            c.SetAction = function(self, action, value) self.actions[action.id] = value end
            c.EnableToughWork = function(self, value) self.tough = value end
        end
        self.components[name] = c
    end
    return inst
end
local staff_prefab = load_source("mod/scripts/prefabs/krypton_staff.lua")
TheWorld.ismastersim = false
local client = staff_prefab.fn()
assert(next(client.components) == nil and client.pristine)
assert(client.tags.CHOP_tool and client.tags.MINE_tool and client.tags.HAMMER_tool)
assert(client.tags.DIG_tool, "Remote clients need the dig action before server components exist")
TheWorld.ismastersim = true
local staff = staff_prefab.fn()
assert(staff.components.weapon.damage == 10000)
assert(staff.components.weapon.attackrange == 6 and staff.components.weapon.hitrange == 8)
for _, range in ipairs({ 3, 10, 16 }) do
    TUNING.KRYPTON_SURVIVOR.staff_range = range
    local configured_staff = staff_prefab.fn()
    assert(configured_staff.components.weapon.attackrange == range
        and configured_staff.components.weapon.hitrange == range + 2,
        "configured melee reach keeps the native two-unit hit tolerance")
end
TUNING.KRYPTON_SURVIVOR.staff_range = 6
local function victim()
    return { IsValid = function() return true end, HasTag = function() return false end,
        Transform = { GetWorldPosition = function() return 10, 0, 20 end },
        components = { health = { IsDead = function() return false end },
            combat = { GetAttacked = function(self, attacker, damage, weapon)
                self.hits = (self.hits or 0) + 1; self.damage = damage
                assert(weapon == staff)
            end } } }
end
local primary, nearby, follower, dead = victim(), victim(), victim(), victim()
follower.components.follower = { leader = {} }
dead.components.health.IsDead = function() return true end
local attacker = victim()
attacker.components.combat.CanTarget = function() return true end
local splash_queries, expected_radius = 0, 5
TheSim = { FindEntities = function(self, x, y, z, radius, must, excluded)
    splash_queries = splash_queries + 1
    assert(x == 10 and z == 20 and radius == expected_radius and must[1] == "_combat")
    local protects_players = false
    for _, tag in ipairs(excluded) do if tag == "player" then protects_players = true end end
    assert(protects_players)
    return { primary, nearby, follower, dead, attacker }
end }
staff.components.weapon.onattack(staff, attacker, primary)
assert(nearby.components.combat.hits == 1 and nearby.components.combat.damage == 10000)
assert(primary.components.combat.hits == nil and follower.components.combat.hits == nil)
assert(dead.components.combat.hits == nil and attacker.components.combat.hits == nil)
for _, radius in ipairs({ 3, 8, 12 }) do
    expected_radius, TUNING.KRYPTON_SURVIVOR.staff_aoe_radius = radius, radius
    local before = splash_queries
    staff.components.weapon.onattack(staff, attacker, primary)
    assert(splash_queries == before + 1, "non-default splash radius reaches the server query")
end
local queries_before, hits_before = splash_queries, nearby.components.combat.hits
TUNING.KRYPTON_SURVIVOR.staff_aoe_radius = 0
staff.components.weapon.onattack(staff, attacker, primary)
assert(splash_queries == queries_before and nearby.components.combat.hits == hits_before,
    "zero splash skips both the entity query and collateral damage")
assert(staff.components.weapon.damage == 10000 and primary.components.combat.hits == nil,
    "disabling splash leaves the native primary hit and weapon damage unchanged")
TUNING.KRYPTON_SURVIVOR.staff_aoe_radius = 5
assert(staff.components.tool.actions.CHOP == 10 and staff.components.tool.actions.MINE == 10)
assert(staff.components.tool.actions.HAMMER == 10 and staff.components.tool.tough)
assert(staff.components.tool.actions.DIG == 10, "Digging must work on the server as well as appear on the client")
assert(staff.components.finiteuses == nil and staff.components.fueled == nil)
assert(staff.components.equippable.restrictedtag == "kryptonian")
local owner = { tags = { player = true, kryptonian = true }, components = {},
    IsValid = function() return true end,
    HasTag = function(self, tag) return self.tags[tag] == true end,
    AnimState = { OverrideSymbol = noop, Show = noop, Hide = noop } }
staff.components.inventoryitem.owner = owner
staff.components.equippable.equipped = true
staff.components.equippable.onequip(staff, owner)
assert(staff.Light.enabled == false)
TheWorld.state.isnight = true
staff.watches.isnight(staff)
assert(staff.Light.enabled == true)
TheWorld.state.isnight = false
TheWorld.cave = true
staff.watches.isnight(staff)
assert(staff.Light.enabled == true)
staff.components.equippable.onunequip(staff, owner)
assert(staff.Light.enabled == false)
staff.components.inventoryitem.onput(staff, owner)
assert(#staff.tasks == 0)
owner.tags.kryptonian = nil
local dropped = false
owner.components.inventory = { DropItem = function(self, item) assert(item == staff); dropped = true end }
staff.components.inventoryitem.onput(staff, owner)
assert(#staff.tasks == 1 and not dropped)
staff.tasks[1](staff)
assert(dropped)
-- A deferred callback must not drop an item already transferred to another owner.
dropped = false
staff.components.inventoryitem.owner = {}
staff.tasks[1](staff)
assert(not dropped)
local overrides = load_source("tests/fixtures/test-world-modoverrides.lua")
assert(overrides.KryptonSurvivor.enabled == true)
assert(overrides.KryptonSurvivor.configuration_options.staff_damage == 2000)
print("Smoke tests passed: languages, preview isolation, starting equipment, stats, sunlight health/sanity recovery, skin modes, server/client split, tools, light and ownership.")
