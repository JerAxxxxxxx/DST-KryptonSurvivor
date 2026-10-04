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
    NAMES = {}, CHARACTER_TITLES = {}, CHARACTER_NAMES = {}, CHARACTER_DESCRIPTIONS = {},
    CHARACTER_QUOTES = {}, CHARACTER_SURVIVABILITY = {}, SKIN_NAMES = {},
    CHARACTERS = { GENERIC = { DESCRIBE = { WILSON = { GENERIC = "Hi %s" } } } },
}
TUNING = {}
LanguageTranslator = { defaultlang = "zh" }
GLOBAL = { STRINGS = STRINGS, TUNING = TUNING, LanguageTranslator = LanguageTranslator, deepcopy = deepcopy,
    KEY_R = 114, KEY_V = 118, TheNet = { IsDedicated = function() return true end } }
package.preload["krypton_heatvision"] = function() return load_source("mod/scripts/krypton_heatvision.lua") end
package.preload["krypton_heatvision_input"] = function() return load_source("mod/scripts/krypton_heatvision_input.lua") end
package.preload["krypton_flight_visual"] = function() return load_source("mod/scripts/krypton_flight_visual.lua") end
package.preload["krypton_flight"] = function() return load_source("mod/scripts/krypton_flight.lua") end
package.preload["krypton_flight_input"] = function() return load_source("mod/scripts/krypton_flight_input.lua") end
package.preload["krypton_map_teleport"] = function() return load_source("mod/scripts/krypton_map_teleport.lua") end
package.preload["krypton_map_teleport_input"] = function() return load_source("mod/scripts/krypton_map_teleport_input.lua") end
package.preload["componentutil"] = function() return {} end
local ability_rpcs = {}
AddModRPCHandler = function(namespace, name, fn)
    assert(namespace == "KryptonSurvivor" and (name == "HeatVision" or name == "ToggleFlight" or name == "MapTeleport"))
    ability_rpcs[name] = fn
end
local config = {}
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
assert(STRINGS.CHARACTER_TITLES.krypton_survivor == "超人 · 氪星幸存者")
assert(STRINGS.CHARACTERS.KRYPTON_SURVIVOR ~= STRINGS.CHARACTERS.GENERIC)
assert(type(ability_rpcs.HeatVision) == "function" and TUNING.KRYPTON_SURVIVOR.heatvision_damage == 2000)
assert(type(ability_rpcs.ToggleFlight) == "function" and type(ability_rpcs.MapTeleport) == "function")
assert(type(map_hook) == "function" and TUNING.KRYPTON_SURVIVOR.flight_enabled == true)
assert(TUNING.KRYPTON_SURVIVOR.map_teleport_enabled == true)
config.language = "en"
config.staff_damage = 10000
config.speed_multiplier = 2
config.heatvision_damage = 50000
load_source("mod/modmain.lua")
assert(STRINGS.NAMES.KRYPTON_SURVIVOR == "Superman")
assert(STRINGS.NAMES.KRYPTON_STAFF == "Rao's Edge")
assert(TUNING.KRYPTON_SURVIVOR.staff_damage == 10000 and TUNING.KRYPTON_SURVIVOR.speed == 2)
assert(TUNING.KRYPTON_SURVIVOR.heatvision_damage == 50000)

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
local player = {
    GUID = 1, tags = { player = true },
    components = {}, replica = {},
    MiniMapEntity = { SetIcon = function(self, value) self.icon = value end },
    AnimState = { SetBuild = function(self, value) self.build = value end,
        AddOverrideBuild = function(self, value) self.override_build = value end,
        IsCurrentAnimation = function() return false end },
    AddTag = function(self, tag) self.tags[tag] = true end,
    RemoveTag = function(self, tag) self.tags[tag] = nil end,
    DoTaskInTime = function(self, delay, fn) self.visiontask = fn end,
    DoPeriodicTask = function(self, period, fn) self.regentask = fn end,
    ListenForEvent = function(self, event, fn) self.activation = fn end,
    HasTag = function(self, tag) return self.tags[tag] == true end,
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
    assert(overtime == true and cause == "krypton_sunlight")
end
player.components.sanity.DoDelta = function(self, delta) self.delta = delta end
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
player.components.inventory = {
    FindItem = function(self, test) return test(starter) and starter or nil end,
    Equip = function(self, item) self.equipped = item end,
}
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
assert(#player.starting_inventory == 1 and player.starting_inventory[1] == "krypton_staff")
player:OnNewSpawn()
assert(player.components.inventory.equipped == starter)
player.components.skinner.skin_data = {}
player.components.skinner:SetSkinMode("ghost_skin")
assert(player.components.skinner.skin_data.ghost_skin == "ghost_wilson_build")
player.components.skinner:SetSkinMode("normal_skin")
assert(player.components.skinner.skin_data.normal_skin == "krypton_survivor")

ACTIONS = { CHOP = { id = "CHOP" }, MINE = { id = "MINE" }, HAMMER = { id = "HAMMER" } }
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
TheWorld.ismastersim = true
local staff = staff_prefab.fn()
assert(staff.components.weapon.damage == 10000)
assert(staff.components.weapon.attackrange == 6 and staff.components.weapon.hitrange == 8)
local function victim()
    return { IsValid = function() return true end,
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
TheSim = { FindEntities = function(self, x, y, z, radius, must, excluded)
    assert(x == 10 and z == 20 and radius == 5 and must[1] == "_combat")
    local protects_players = false
    for _, tag in ipairs(excluded) do if tag == "player" then protects_players = true end end
    assert(protects_players)
    return { primary, nearby, follower, dead, attacker }
end }
staff.components.weapon.onattack(staff, attacker, primary)
assert(nearby.components.combat.hits == 1 and nearby.components.combat.damage == 10000)
assert(primary.components.combat.hits == nil and follower.components.combat.hits == nil)
assert(dead.components.combat.hits == nil and attacker.components.combat.hits == nil)
assert(staff.components.tool.actions.CHOP == 10 and staff.components.tool.actions.MINE == 10)
assert(staff.components.tool.actions.HAMMER == 10 and staff.components.tool.tough)
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
