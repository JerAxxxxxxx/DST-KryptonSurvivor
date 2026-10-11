local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < .000001, message or "unexpected number")
end
Class = function(constructor)
    local class = {}
    class.__index = class
    return setmetatable(class, { __call = function(_, ...)
        local instance = setmetatable({}, class)
        constructor(instance, ...)
        return instance
    end })
end
EQUIPSLOTS = { BODY = "body", HANDS = "hands", HEAD = "head" }
TUNING = { TOTAL_DAY_TIME = 480, KRYPTON_SURVIVOR = { starcore_revive_cooldown = 480 },
    STARTING_TEMP = 35, OVERHEAT_TEMP = 70, SEG_TIME = 30,
    WARM_DEGREES_PER_SEC = 5, THAW_DEGREES_PER_SEC = 2, WET_HEAT_FACTOR_PENALTY = .5 }
STRINGS = { KRYPTON_STARCORE = { COOLDOWN = "cooldown", READY = "ready", REVIVED = "revived" } }
local now, tasks, shard = 0, {}, "1"
GetTime = function() return now end
TheShard = { GetShardId = function() return shard end }
TheWorld = { ismastersim = true, state = { temperature = -20 } }
GetTemperatureAtXZ = function() return TheWorld.state.temperature end
TheSim = { FindEntities = function() return {} end }
math.clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
-- The optional local audit injects methods directly from installed scripts.zip.
-- CI uses small independent contracts; no game's copyrighted source is stored.
local Native
if type(read_native_starcore_methods) == "function" then
    local chunk, err = load(read_native_starcore_methods(), "@installed-starcore-methods")
    assert(chunk, err)
    Native = chunk()
end
local Core = load_source("mod/scripts/components/krypton_starcore.lua")
local Starter = load_source("mod/scripts/krypton_starcore_starter.lua")

local function advance(seconds)
    local finish = now + seconds
    while true do
        local next_task
        for _, task in ipairs(tasks) do
            if not task.cancelled and not task.done and task.at <= finish
                and (next_task == nil or task.at < next_task.at) then next_task = task end
        end
        if next_task == nil then break end
        now = next_task.at
        next_task.done = true
        next_task.fn()
    end
    now = finish
end
local function new_item(prefab, slot)
    local item = { prefab = prefab or "krypton_starcore_amulet", valid = true, components = {} }
    item.IsValid = function(self) return self.valid end
    item.components.inventoryitem = { keepondeath = item.prefab == "krypton_starcore_amulet" }
    item.PushEvent = function() end
    local equippable = { inst = item, equipslot = slot or EQUIPSLOTS.BODY, isequipped = false,
        IsEquipped = Native and Native.Equippable.IsEquipped or function(self) return self.isequipped end }
    equippable.onequipfn = function(_, owner)
        if item.prefab == "krypton_starcore_amulet" then owner.components.krypton_starcore:SetEquipped(item) end
    end
    equippable.onunequipfn = function(_, owner)
        if item.prefab == "krypton_starcore_amulet" then owner.components.krypton_starcore:SetEquipped(nil) end
    end
    equippable.Equip = Native and Native.Equippable.Equip or function(self, owner)
        self.isequipped = true
        self.onequipfn(item, owner)
    end
    equippable.Unequip = Native and Native.Equippable.Unequip or function(self, owner)
        self.isequipped = false
        self.onunequipfn(item, owner)
    end
    item.components.equippable = equippable
    return item
end

-- Model native event ordering, not the component's implementation. In native
-- Inventory:Equip, the item's OnEquip precedes assigning equipslots[BODY];
-- Unequip likewise calls OnUnequip before clearing that slot. Player death's
-- already-registered native SG drops equipment before our death listener.
local function player(options)
    options = options or {}
    local inst = { prefab = options.prefab or "krypton_survivor", valid = true, isplayer = true,
        tags = { kryptonian = options.kryptonian ~= false }, components = {}, events = {},
        ghostenabled = options.ghostenabled ~= false, pos = { x = 17, y = 0, z = -9 },
        sayings = {}, teleports = 0, revive_requests = 0, percent_writes = 0 }
    inst.IsValid = function(self) return self.valid end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.GetPosition = function(self) return self.pos end
    inst.Transform = { GetWorldPosition = function() return inst.pos.x, inst.pos.y, inst.pos.z end }
    inst.Physics = { Teleport = function(_, x, y, z)
        inst.pos = { x = x, y = y, z = z }; inst.teleports = inst.teleports + 1
    end }
    inst.ListenForEvent = function(self, event, fn)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], fn)
    end
    inst.RemoveEventCallback = function(self, event, fn)
        for i, callback in ipairs(self.events[event] or {}) do
            if callback == fn then table.remove(self.events[event], i); break end
        end
    end
    inst.PushEvent = function(self, event, data)
        local callbacks = {}
        for _, fn in ipairs(self.events[event] or {}) do table.insert(callbacks, fn) end
        for _, fn in ipairs(callbacks) do fn(self, data) end
    end
    inst.DoTaskInTime = function(self, delay, fn)
        local task = { at = now + delay, fn = function() fn(self) end,
            Cancel = function(t) t.cancelled = true end }
        table.insert(tasks, task)
        return task
    end
    local health = { inst = inst, currenthealth = 8000, maxhealth = 10000, penalty = .2,
        canheal = true, invincible = false, deltamodifierfn = options.modifier,
        nonlethal_pct = 0, absorb = 0, playerabsorb = 0,
        externalabsorbmodifiers = { Get = function() return 0 end },
        externalreductionmodifiers = { Get = function() return 0 end } }
    health.IsDead = function(self) return self.currenthealth <= 0 end
    health.IsInvincible = function(self) return self.invincible end
    health.GetPercent = function(self) return self.currenthealth / self.maxhealth end
    health.SetVal = function(self, amount) self.currenthealth = math.clamp(amount, 0, self:GetMaxWithPenalty()) end
    health.SetPercent = function(self, percent)
        inst.percent_writes = inst.percent_writes + 1
        self.currenthealth = self.maxhealth * (1 - self.penalty) * percent
    end
    health.GetMaxWithPenalty = function(self) return self.maxhealth * (1 - self.penalty) end
    health.DoDelta = Native and Native.Health.DoDelta or function(self, amount, overtime, cause,
            ignore_invincible, afflicter, ignore_absorb)
        if self.deltamodifierfn ~= nil then
            amount = self.deltamodifierfn(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        end
        self:SetVal(self.currenthealth + amount)
        return amount
    end
    inst.components.health = health
    inst.client_temperature_events, inst.client_cold_events, inst.client_hot_events = 0, 0, 0
    local client_parent = { PushEvent = function(_, event)
        if event == "startfreezing" then inst.client_cold = true; inst.client_cold_events = inst.client_cold_events + 1
        elseif event == "stopfreezing" then inst.client_cold = false
        elseif event == "startoverheating" then inst.client_hot = true; inst.client_hot_events = inst.client_hot_events + 1
        elseif event == "stopoverheating" then inst.client_hot = false
        elseif event == "temperaturedelta" then inst.client_temperature_events = inst.client_temperature_events + 1 end
    end }
    local classified = { _parent = client_parent, _oldtemperature = 10, currenttemperature = 10,
        currenttemperaturedata = { set = function(self, value) self.data = value end,
                                   value = function(self) return self.data end } }
    classified.SetTemperature = Native and Native.PlayerClassified.SetTemperature or function(self, value)
        self.currenttemperaturedata:set(value)
    end
    inst.FlushClassified = function()
        if Native then Native.PlayerClassified.OnTemperatureDirty(classified); return end
        local value = classified.currenttemperaturedata:value() or classified.currenttemperature
        local old = classified.currenttemperature
        classified.currenttemperature = value
        if (value < 0) ~= (old < 0) then client_parent:PushEvent(value < 0 and "startfreezing" or "stopfreezing") end
        if (value > TUNING.OVERHEAT_TEMP) ~= (old > TUNING.OVERHEAT_TEMP) then
            client_parent:PushEvent(value > TUNING.OVERHEAT_TEMP and "startoverheating" or "stopoverheating")
        end
        if value ~= old then client_parent:PushEvent("temperaturedelta") end
    end
    inst.player_classified = classified
    local temperature = { inst = inst, _current = 10, mintemp = -100, maxtemp = 150,
        overheattemp = 70, hurtrate = 2, totalmodifiers = 0, sheltered_level = 1 }
    -- Native Class's oncurrent property serializes temperature to classified.
    -- Deliver replication dirty events explicitly after each completed tick;
    -- native net variables coalesce multiple writes within a frame.
    setmetatable(temperature, {
        __index = function(self, key) if key == "current" then return rawget(self, "_current") end end,
        __newindex = function(self, key, value)
            if key ~= "current" then rawset(self, key, value); return end
            rawset(self, "_current", value)
            classified:SetTemperature(value)
        end,
    })
    temperature.GetMoisturePenalty = function() return 0 end
    temperature.GetInsulation = function() return 0, 0 end
    temperature.SetTemperature = Native and Native.Temperature.SetTemperature or function(self, value)
        local last = self.current
        self.current = math.clamp(value, self.mintemp, self.maxtemp)
        if (self.current < 0) ~= (last < 0) then
            inst:PushEvent(self.current < 0 and "startfreezing" or "stopfreezing")
        end
        if (self.current > self.overheattemp) ~= (last > self.overheattemp) then
            inst:PushEvent(self.current > self.overheattemp and "startoverheating" or "stopoverheating")
        end
        inst:PushEvent("temperaturedelta", { last = last, new = self.current })
    end
    temperature.OnUpdate = Native and Native.Temperature.OnUpdate or function(self, dt, applyhealthdelta)
        -- Native API contract: nil/true enables thermal health deltas; false
        -- suppresses only those deltas and still runs temperature events.
        if self.settemp ~= nil then return end
        self:SetTemperature(self.current + math.clamp(TheWorld.state.temperature - self.current, -1, 1) * dt)
        if applyhealthdelta ~= false then
            if self.current < 0 then health:DoDelta(-self.hurtrate * dt, true, "cold")
            elseif self.current > self.overheattemp then health:DoDelta(-self.hurtrate * dt, true, "hot") end
        end
    end
    temperature.DoDelta = Native and Native.Temperature.DoDelta or function(self, delta)
        self:SetTemperature(self.current + delta)
    end
    temperature.OnLoad = Native and Native.Temperature.OnLoad or function(self, data)
        if data.current ~= nil then self:SetTemperature(data.current) end
    end
    inst.components.temperature = temperature
    inst.components.freezable = { Freeze = function(self) self.frozen = true end }
    inst.components.talker = { Say = function(_, message) table.insert(inst.sayings, message) end }
    inst.hunger, inst.sanity = 9000, 9000
    local moisture = { moisture = 80, sources = {} }
    moisture.ForceDry = function(self, force, source)
        if force then self.sources[source] = true; self.moisture = 0
        else self.sources[source] = nil end
    end
    moisture.DoDelta = function(self, amount)
        if next(self.sources) == nil then self.moisture = self.moisture + amount end
    end
    inst.components.moisture = moisture
    local inv = { equipslots = {}, itemslots = {}, items = {}, full = options.full, dropped = 0 }
    inv.GetOverflowContainer = function() return nil end
    inv.GetActiveItem = function() return nil end
    inv.GetEquippedItem = function(self, slot) return self.equipslots[slot] end
    inv.FindItem = function(self, predicate)
        for _, item in ipairs(self.items) do if predicate(item) then return item end end
    end
    inv.GiveItem = function(self, item)
        if self.full then item.components.inventoryitem.owner = nil; self.dropped = self.dropped + 1
        else item.components.inventoryitem.owner = inst; table.insert(self.items, item) end
    end
    inv.Unequip = function(self, slot)
        local old = self.equipslots[slot]
        if old == nil then return end
        old.components.equippable:Unequip(inst)
        self.equipslots[slot] = nil
        inst:PushEvent("unequip", { item = old, eslot = slot })
        return old
    end
    inv.Equip = function(self, item)
        local slot = item.components.equippable.equipslot
        if item.prefab == "krypton_starcore_amulet" and not inst:HasTag("kryptonian") then return false end
        self:Unequip(slot)
        item.components.inventoryitem.owner = inst
        item.components.equippable:Equip(inst)
        self.equipslots[slot] = item
        inst:PushEvent("equip", { item = item, eslot = slot })
        return true
    end
    inv.DropForDeath = function(self)
        for slot, item in pairs(self.equipslots) do
            if not item.components.inventoryitem.keepondeath then self:Unequip(slot); self.dropped = self.dropped + 1 end
        end
    end
    inst.components.inventory = inv
    if options.corpse then inst.components.revivablecorpse = {} end
    inst:ListenForEvent("death", function() inv:DropForDeath() end)
    local function native_request(_, data)
        local corpse = inst:HasTag("corpse")
        if not corpse and not inst:HasTag("playerghost") then return end
        inst.revive_requests = inst.revive_requests + 1
        inst.tags.reviving = true
        if options.fail_native then return end
        inst:DoTaskInTime(0, function()
            inst.tags.playerghost, inst.tags.corpse, inst.tags.reviving = nil, nil, nil
            health.currenthealth, health.canheal = 50, true
            moisture:ForceDry(false, inst)
            inst:PushEvent("ms_respawnedfromghost", corpse and { corpse = true, reviver = data.source } or nil)
        end)
    end
    inst:ListenForEvent("respawnfromghost", native_request)
    inst:ListenForEvent("respawnfromcorpse", native_request)
    local core = Core(inst)
    inst.components.krypton_starcore = core
    return inst, core
end
local function equip(inst, slot)
    local item = new_item(nil, slot)
    inst.components.inventory:Equip(item)
    return item
end
local function die(inst)
    inst.components.health.currenthealth = 0
    inst:PushEvent("death")
end
local function ghost(inst, corpse)
    inst.tags[corpse and "corpse" or "playerghost"] = true
    inst.components.health.currenthealth = 50
    inst.components.health.canheal = false
    inst.hunger, inst.sanity = 20000 / 3, 5000 -- native CommonPlayerDeath values
    inst.components.moisture:ForceDry(true, inst)
    inst:PushEvent("ms_becameghost", corpse and { corpse = true } or nil)
end

-- Equipment must be effective only in BODY and only for the tagged character.
local a, acore = player()
local necklace = equip(a)
assert(acore:GetEquippedAmulet() == necklace and acore:IsProtected())
equal(a.components.moisture.moisture, 0, "equip should immediately dry the survivor")
a.components.moisture:DoDelta(25) -- rain/splash both use the native moisture path
close(a.components.moisture.moisture, 0, "rain/splash must not wet a protected player")
local external_dry = {}
a.components.moisture:ForceDry(true, external_dry)
a.components.inventory:Unequip(EQUIPSLOTS.BODY)
assert(not acore:IsProtected() and a.components.moisture.sources[necklace] == nil,
    "native unequip must remove amulet protection after clearing BODY")
assert(a.components.moisture.sources[external_dry], "another dry source must survive unequipping")
a.components.moisture:ForceDry(false, external_dry)
a.components.moisture:DoDelta(25)
equal(a.components.moisture.moisture, 25, "rain should work after removing the last protection")
local wrong_slot, wrong_core = player()
equip(wrong_slot, EQUIPSLOTS.HANDS)
assert(wrong_core:GetEquippedAmulet() == nil and not wrong_core:IsProtected())
local other, other_core = player({ prefab = "wilson", kryptonian = false })
assert(other.components.inventory:Equip(new_item()) == false)
assert(not other_core:IsProtected())

-- Chain an existing mod's modifier; block just the two native thermal causes.
local calls = 0
local previous = function(_, amount) calls = calls + 1; return amount * .5 end
local b, bcore = player({ modifier = previous })
equip(b)
close(b.components.health:DoDelta(-100, true, "cold"), 0)
close(b.components.health:DoDelta(-100, true, "hot"), 0)
close(b.components.health:DoDelta(-100, true, "fire"), -50)
close(b.components.health:DoDelta(-100, true, "hound"), -50)
close(b.components.health:DoDelta(100, true, "cold"), 50, "positive thermal healing must remain possible")
equal(calls, 5, "previous mod's modifier should keep receiving calls")
b.components.inventory:Unequip(EQUIPSLOTS.BODY)
assert(b.components.health.deltamodifierfn == previous, "unequip must restore the previous modifier")
close(b.components.health:DoDelta(-100, true, "cold"), -50)
equip(b)
local amulet_wrapper = b.components.health.deltamodifierfn
local external_modifier = function(...) return amulet_wrapper(...) end
b.components.health.deltamodifierfn = external_modifier
b.components.inventory:Unequip(EQUIPSLOTS.BODY)
assert(b.components.health.deltamodifierfn == external_modifier, "never replace a later mod's modifier")
close(b.components.health:DoDelta(-100, true, "hot"), -50, "retained wrapper must become inert after unequip")

-- Exercise native temperature updates and classified replication, not just a
-- direct health modifier call. Later mods may replace deltamodifierfn while
-- safe temperature and native applyhealthdelta=false remain effective.
local function assert_safe(inst, message)
    local temp = inst.components.temperature.current
    assert(temp >= 10 and temp <= 50, (message or "protected temperature") .. ": " .. tostring(temp))
    inst:FlushClassified()
    assert(not inst.client_cold and not inst.client_hot, "replicated temperature must suppress cold/hot client cues")
end
local thermal, thermal_core = player()
local thermometer, thermal_health = thermal.components.temperature, thermal.components.health
local native_update, native_set = thermometer.OnUpdate, thermometer.SetTemperature
local temperature_events, cold_events, hot_events = 0, 0, 0
thermal:ListenForEvent("temperaturedelta", function() temperature_events = temperature_events + 1 end)
thermal:ListenForEvent("startfreezing", function() cold_events = cold_events + 1 end)
thermal:ListenForEvent("startoverheating", function() hot_events = hot_events + 1 end)
TheWorld.state.temperature = -20
thermometer.current = 1
thermometer:OnUpdate(2)
thermal:FlushClassified()
assert(thermometer.current < 0 and thermal_health.currenthealth < 8000 and thermal.client_cold,
    "native cold exposure must damage and show cold cues in an unprotected baseline")
equal(cold_events, 1)
thermal_health.currenthealth = 8000
equip(thermal)
assert_safe(thermal, "equipping into an already-cold state must immediately correct temperature")
local protected_cold_events, protected_hot_events = cold_events, hot_events
local client_cold_events, client_hot_events = thermal.client_cold_events, thermal.client_hot_events
thermal_health.deltamodifierfn = function(_, amount) return amount end
TheWorld.state.temperature = -150
for _ = 1, 40 do thermometer:OnUpdate(10); assert_safe(thermal) end
close(thermal_health.currenthealth, 8000, "extreme cold ticks must remain safe after another mod replaces the health modifier")
TheWorld.state.temperature = 150
for _ = 1, 40 do thermometer:OnUpdate(10, true); assert_safe(thermal) end
close(thermal_health.currenthealth, 8000, "extreme heat ticks must remain safe")
equal(cold_events, protected_cold_events, "safe temperature must not start new freezing effects")
equal(hot_events, protected_hot_events, "safe temperature must not start new overheating effects")
equal(thermal.client_cold_events, client_cold_events, "client must not start new cold cues")
equal(thermal.client_hot_events, client_hot_events, "client must not start new hot cues")

thermometer:SetTemperature(32)
close(thermometer.current, 32, "normal temperatures should remain freely adjustable")
TheWorld.state.temperature = 20
thermometer:OnUpdate(1)
assert(thermometer.current < 32 and thermometer.current >= 10,
    "body temperature must still vary normally within its safe interval")
thermometer:SetTemperature(-500)
close(thermometer.current, 10, "direct cold setters must respect the safe lower bound")
thermometer:SetTemperature(500)
close(thermometer.current, 50, "direct hot setters must respect the safe upper bound")
thermometer:DoDelta(-1000)
close(thermometer.current, 10, "native food/belly/direct temperature deltas must stay safe")
thermometer:DoDelta(1000, true)
close(thermometer.current, 50)
assert_safe(thermal)
assert(thermometer.settemp == nil, "protection must not lock the native settemp field")
thermal_health:DoDelta(-100, false, "hound")
close(thermal_health.currenthealth, 7900, "combat damage must remain active")
thermal_health:DoDelta(-50, false, "fire")
close(thermal_health.currenthealth, 7850, "burning damage must remain active")
thermal_health:DoDelta(50, false, "food")
close(thermal_health.currenthealth, 7900, "food healing must remain active")
thermal.components.freezable:Freeze()
assert(thermal.components.freezable.frozen, "attack-driven freezing control must remain native")
assert(temperature_events > 80, "safe updates must still produce native temperature events")

-- Removal restores both native methods without reinstating an old unsafe
-- temperature. Natural changes resume immediately, and actual damage resumes
-- only once the body temperature crosses the normal game's thresholds.
local before_unequip = thermometer.current
thermal.components.inventory:Unequip(EQUIPSLOTS.BODY)
assert(thermometer.OnUpdate == native_update and thermometer.SetTemperature == native_set,
    "unequip must restore the original temperature API")
close(thermometer.current, before_unequip, "removal must never reinstate pre-equip extreme temperature")
TheWorld.state.temperature = -150
thermometer:OnUpdate(1)
assert(thermometer.current < before_unequip, "temperature must start changing naturally after removal")
close(thermal_health.currenthealth, 7900, "safe body temperature should not immediately damage on removal")
thermometer:SetTemperature(-5)
local before_cold = thermal_health.currenthealth
thermometer:OnUpdate(1)
thermal:FlushClassified()
assert(thermal_health.currenthealth < before_cold and thermal.client_cold,
    "native cold damage and client cues must return after removal")
TheWorld.state.temperature = 150
thermometer:SetTemperature(90)
local before_hot = thermal_health.currenthealth
thermometer:OnUpdate(1)
thermal:FlushClassified()
assert(thermal_health.currenthealth < before_hot and thermal.client_hot,
    "native heat damage and client cues must return after removal")
local after_hot = thermal_health.currenthealth
thermometer:OnUpdate(1, false)
close(thermal_health.currenthealth, after_hot, "the explicit native damage-off gate must be preserved")

-- Already hot states, native early-return locks, and older classified bools
-- must be corrected on equip/tick without resetting another system's lock.
local already_hot = player()
already_hot.components.temperature:SetTemperature(90)
already_hot:FlushClassified()
assert(already_hot.client_hot)
equip(already_hot)
assert_safe(already_hot, "hot equip correction")
local locked, locked_core = player()
locked.components.temperature.settemp = -30
locked.components.temperature.current = -30
equip(locked)
assert_safe(locked)
locked.components.temperature.current = -25 -- external system bypasses the setter
locked.components.temperature:OnUpdate(1)
assert_safe(locked, "wrapper must correct before native settemp early return")
close(locked.components.temperature.settemp, -30, "an unrelated native lock must not be overwritten")
locked.components.health.invincible = true
locked.components.temperature.current = 90
locked.components.temperature:OnUpdate(1)
assert_safe(locked, "native invincibility early return must not leave unsafe temperature")
local legacy = player()
local function net_bool(initial)
    return { data = initial, set = function(self, value) self.data = value end,
             value = function(self) return self.data end }
end
legacy.player_classified.isfreezing = net_bool(true)
legacy.player_classified.isoverheating = net_bool(true)
equip(legacy)
assert(not legacy.player_classified.isfreezing:value() and not legacy.player_classified.isoverheating:value(),
    "older native classified cue fields must be cleared when present")

-- Preserve a mod's later wrappers while making retained Starcore closures
-- harmless after removal. Direct setter and OnUpdate both need this behavior.
local nested, nested_core = player()
equip(nested)
local protected_update, protected_set = nested.components.temperature.OnUpdate, nested.components.temperature.SetTemperature
local later_calls, later_sets = 0, 0
local later_update = function(component, ...)
    later_calls = later_calls + 1
    return protected_update(component, ...)
end
local later_set = function(component, ...)
    later_sets = later_sets + 1
    return protected_set(component, ...)
end
nested.components.temperature.OnUpdate, nested.components.temperature.SetTemperature = later_update, later_set
nested.components.inventory:Unequip(EQUIPSLOTS.BODY)
assert(nested.components.temperature.OnUpdate == later_update and nested.components.temperature.SetTemperature == later_set,
    "unequip must not remove another mod's later temperature wrappers")
TheWorld.state.temperature = -150
nested.components.temperature:SetTemperature(-5)
local nested_before = nested.components.health.currenthealth
nested.components.temperature:OnUpdate(1)
assert(later_calls == 1 and later_sets == 2 and nested.components.health.currenthealth < nested_before,
    "retained Starcore closures must allow native temperature and damage after removal")
local removed_thermal, removed_thermal_core = player()
local removed_native_update, removed_native_set = removed_thermal.components.temperature.OnUpdate, removed_thermal.components.temperature.SetTemperature
equip(removed_thermal)
removed_thermal_core:OnRemoveFromEntity()
assert(removed_thermal.components.temperature.OnUpdate == removed_native_update
    and removed_thermal.components.temperature.SetTemperature == removed_native_set,
    "component removal must restore both original native temperature APIs")

-- Native bounds and modded overheat thresholds take precedence over default
-- limits when there is a valid safe intersection.
local narrow = player()
narrow.components.temperature.mintemp, narrow.components.temperature.maxtemp = 20, 40
equip(narrow)
close(narrow.components.temperature.current, 20)
narrow.components.temperature:SetTemperature(100)
close(narrow.components.temperature.current, 40)
local low_overheat = player()
low_overheat.components.temperature.overheattemp = 8
equip(low_overheat)
assert(low_overheat.components.temperature.current >= 0 and low_overheat.components.temperature.current <= 4,
    "a modded lower overheat threshold must be respected")
local impossible = player()
impossible.components.temperature.mintemp, impossible.components.temperature.maxtemp = -40, -10
impossible.components.temperature.current = -20
equip(impossible)
impossible.components.temperature:OnUpdate(1)
assert(impossible.components.temperature.current <= -10, "do not invent values outside impossible native bounds")
close(impossible.components.health.currenthealth, 8000, "thermal damage fallback must remain effective for incompatible native ranges")

-- Auto revive is queued only for the equipped item, after native ghost setup;
-- native resurrection succeeds before the personal cooldown is consumed.
local c, ccore = player()
local c_native_update, c_native_set = c.components.temperature.OnUpdate, c.components.temperature.SetTemperature
local held = equip(c)
die(c)
assert(c.components.temperature.OnUpdate == c_native_update and c.components.temperature.SetTemperature == c_native_set,
    "death must suspend temperature protection while leaving resurrection equipment available")
assert(ccore._pending ~= nil and ccore:IsReady())
assert(c.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY) == held, "keepondeath keeps the amulet available")
ghost(c)
c.components.temperature.current = -30
c.pos = { x = 77, y = 0, z = 77 }
advance(.249)
equal(c.revive_requests, 0)
assert(ccore:IsReady(), "queued attempts do not spend cooldown")
advance(.001)
equal(c.revive_requests, 1)
equal(c.teleports, 1)
equal(c.pos.x, 17); equal(c.pos.z, -9)
assert(not c:HasTag("playerghost") and not ccore:IsReady())
assert_safe(c, "resurrection must immediately restore safe temperature")
close(ccore:GetCooldownRemaining(), 480)
close(c.components.health.currenthealth, 8000, "revive restores the current maximum after pre-existing penalty")
close(c.components.health.penalty, .2, "revive must not add or remove max-health penalty")
close(c.hunger, 20000 / 3, "starcore must not refill hunger beyond native resurrection")
close(c.sanity, 5000, "starcore must not refill sanity beyond native resurrection")
local csave = ccore:OnSave()
assert(csave.pending == nil)
c:PushEvent("ms_respawnedfromghost")
advance(.1)
equal(c.revive_requests, 1, "duplicate successful events cannot repeat revival")
close(ccore:GetCooldownRemaining(), 479.9, "duplicate events must not restart cooldown")
c.components.inventory:Unequip(EQUIPSLOTS.BODY)
equip(c)
close(ccore:GetCooldownRemaining(), 479.9, "another amulet cannot clear personal cooldown")
die(c); ghost(c)
advance(.3)
equal(c.revive_requests, 1, "death during cooldown must follow native ghost rules")
advance(479.6)
assert(ccore:IsReady(), "cooldown ends after one in-game day")
equal(c.revive_requests, 1, "cooldown expiring must not resurrect an earlier cooldown death")

local unworn, unworn_core = player()
unworn.components.inventory:GiveItem(new_item())
die(unworn); ghost(unworn); advance(.3)
equal(unworn.revive_requests, 0, "an amulet in inventory cannot revive")
assert(unworn_core:IsReady())
local failed, failed_core = player({ fail_native = true })
equip(failed); die(failed); ghost(failed); advance(.25)
assert(failed_core:IsReady(), "failed native resurrection must not consume cooldown")
advance(10)
assert(not failed_core:IsAutoReviving() and failed_core:IsReady(), "timeout must release a stalled attempt")
local raced, raced_core = player()
equip(raced); die(raced); ghost(raced)
raced:PushEvent("respawnfromghost", { source = { prefab = "reviver" } })
advance(.3)
equal(raced.revive_requests, 1, "an external resurrection must cancel the queued auto request")
assert(raced_core:IsReady(), "a heart or other source must not spend personal cooldown")
local changed, changed_core = player()
equip(changed); die(changed); ghost(changed)
changed.components.inventory:Unequip(EQUIPSLOTS.BODY)
equip(changed)
advance(.3)
equal(changed.revive_requests, 0, "swapping the amulet after death invalidates the old attempt")
assert(changed_core:IsReady())
local wilderness, wilderness_core = player({ ghostenabled = false })
equip(wilderness); die(wilderness); advance(1)
equal(wilderness.revive_requests, 0, "Wilderness reroll rules must be preserved")
assert(wilderness_core._pending == nil)
local corpse, corpse_core = player({ ghostenabled = false, corpse = true })
equip(corpse); die(corpse); ghost(corpse, true); advance(.25)
equal(corpse.revive_requests, 1)
assert(not corpse:HasTag("corpse") and not corpse_core:IsReady(), "native revivable corpses use their own event")

-- Save/load and component transfer preserve cooldown and starter-grant flag;
-- invalid untrusted saved coordinates/cooldowns never reach native physics.
local saved, saved_core = player()
equip(saved)
saved_core.starter_granted = true
saved_core:SetCooldownRemaining(300)
advance(50)
local data = saved_core:OnSave()
close(data.cooldown_remaining, 250)
local load_inventory_first, load_inventory_core = player()
equip(load_inventory_first)
load_inventory_first.components.temperature:OnLoad({ current = -40 })
load_inventory_core:OnLoad(data)
advance(0)
assert_safe(load_inventory_first, "inventory-first save restoration must correct saved cold temperature")
local load_component_first, load_component_core = player()
load_component_core:OnLoad(data)
TheWorld.state.temperature = 150
load_component_first.components.temperature:OnLoad({ current = 100 })
equip(load_component_first)
advance(0)
assert_safe(load_component_first, "component-first save restoration must correct saved hot temperature")
TheWorld.state.temperature = -20
local loaded, loaded_core = player()
equip(loaded); loaded_core:OnLoad(data); advance(0)
assert(loaded_core.starter_granted)
close(loaded_core:GetCooldownRemaining(), 250)
loaded_core:LongUpdate(40)
close(loaded_core:GetCooldownRemaining(), 210)
local migrated, migrated_core = player()
equip(migrated)
loaded_core:TransferComponent(migrated)
advance(0)
assert(migrated_core.starter_granted)
close(migrated_core:GetCooldownRemaining(), 210)
local pending, pending_core = player()
equip(pending); die(pending)
local pending_save = pending_core:OnSave()
local resumed, resumed_core = player()
equip(resumed); resumed_core:OnLoad(pending_save)
ghost(resumed); advance(.25)
equal(resumed.revive_requests, 1, "a pending equipped resurrection resumes across save/load")
local reversed_load, reversed_core = player()
reversed_core:OnLoad(pending_save)
equip(reversed_load) -- inventory component loads after the starcore component
ghost(reversed_load); advance(.25)
equal(reversed_load.revive_requests, 1, "later inventory loading must retain saved pending revival")
local dying_load, dying_core = player()
dying_core:OnLoad(pending_save)
equip(dying_load)
dying_load.components.health.currenthealth = 0
advance(.5) -- the native death animation has not yet entered the ghost state
equal(dying_load.revive_requests, 0)
ghost(dying_load); advance(.25)
equal(dying_load.revive_requests, 1, "saved dying players must wait for actual native ghost setup")
local shard_lost, shard_core = player()
equip(shard_lost); die(shard_lost); ghost(shard_lost)
shard = "2"; advance(.25)
equal(shard_lost.revive_requests, 0, "never teleport a saved death location from a different shard")
shard = "1"
local invalid, invalid_core = player()
equip(invalid)
invalid_core:OnLoad({ cooldown_remaining = 0 / 0,
    pending = { x = math.huge, y = 0, z = 0 } })
ghost(invalid); advance(.3)
assert(invalid_core:IsReady()); equal(invalid.teleports, 0)

-- Removing the component cancels owned tasks and protection, retaining any
-- unrelated player's active modifiers and force-dry source.
local removed, removed_core = player({ modifier = previous })
local removed_item = equip(removed)
removed.components.moisture:ForceDry(true, external_dry)
removed_core:SetCooldownRemaining(20)
removed_core:OnRemoveFromEntity()
assert(removed.components.health.deltamodifierfn == previous)
assert(removed.components.moisture.sources[removed_item] == nil)
assert(removed.components.moisture.sources[external_dry])
advance(21)
assert(#removed.sayings == 0)

-- Existing saves receive exactly one gift without replacing a backpack.
local spawn_count = 0
SpawnPrefab = function(name)
    equal(name, "krypton_starcore_amulet")
    spawn_count = spawn_count + 1
    return new_item(name)
end
local fresh, fresh_core = player()
Starter.Ensure(fresh)
equal(spawn_count, 1)
assert(fresh_core.starter_granted and fresh_core:IsProtected())
Starter.Ensure(fresh); equal(spawn_count, 1)
local backpacked, backpacked_core = player()
local backpack = new_item("backpack")
backpacked.components.inventory:Equip(backpack)
Starter.Ensure(backpacked)
equal(spawn_count, 2)
assert(backpacked.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY) == backpack,
    "migration gift must not displace an existing backpack or armor")
assert(backpacked_core.starter_granted and not backpacked_core:IsProtected())
local existing, existing_core = player()
local existing_item = new_item()
existing.components.inventory:GiveItem(existing_item)
Starter.Ensure(existing)
equal(spawn_count, 2, "existing inventory amulet should prevent a duplicate")
assert(existing_core.starter_granted and existing_core:GetEquippedAmulet() == existing_item)
local full, full_core = player({ full = true })
Starter.Ensure(full)
equal(spawn_count, 3); equal(full.components.inventory.dropped, 1)
assert(full_core.starter_granted and not full_core:IsProtected())
Starter.Ensure(full); equal(spawn_count, 3, "a dropped full-inventory gift must still be granted only once")
local dead_old, dead_old_core = player()
ghost(dead_old)
Starter.Ensure(dead_old)
equal(spawn_count, 3)
assert(not dead_old_core.starter_granted, "do not give a migration item to a ghost")
dead_old.tags.playerghost = nil
Starter.Ensure(dead_old)
equal(spawn_count, 4)
assert(dead_old_core.starter_granted)

-- The prefab's client construction stops after replication setup, so the
-- client cannot create protection, resurrection listeners or server items.
Asset = function(kind, path) return { kind = kind, path = path } end
Prefab = function(name, fn) return { name = name, fn = fn } end
MakeInventoryPhysics = function(inst) inst.inventory_physics = true end
MakeInventoryFloatable = function(inst) inst.floatable = true end
MakeHauntableLaunch = function(inst) inst.haunt_launch = true end
CreateEntity = function()
    local item = new_item()
    item.components = {}
    item.entity = {
        AddTransform = function() end, AddAnimState = function() end,
        AddSoundEmitter = function() end, AddNetwork = function() item.network = true end,
        SetPristine = function() item.pristine = true end,
    }
    item.AnimState = {
        SetBank = function(_, bank) item.bank = bank end,
        SetBuild = function(_, build) item.build = build end,
        PlayAnimation = function(_, animation) item.animation = animation end,
    }
    item.AddComponent = function(self, name)
        if name == "inventoryitem" then
            self.components[name] = { ChangeImageName = function(component, image) component.image = image end }
        elseif name == "equippable" then
            self.components[name] = {
                SetOnEquip = function(component, fn) component.onequipfn = fn end,
                SetOnUnequip = function(component, fn) component.onunequipfn = fn end,
            }
        elseif name == "inspectable" then self.components[name] = {}
        else error("unexpected amulet component: " .. name) end
    end
    return item
end
local amulet_prefab = load_source("mod/scripts/prefabs/krypton_starcore_amulet.lua")
equal(amulet_prefab.name, "krypton_starcore_amulet")
TheWorld.ismastersim = false
local client_item = amulet_prefab.fn()
assert(client_item.network and client_item.pristine)
assert(next(client_item.components) == nil and client_item.haunt_launch == nil,
    "client construction must not create server protection or haunt behaviors")
TheWorld.ismastersim = true
local server_item = amulet_prefab.fn()
assert(server_item.components.inventoryitem.keepondeath)
equal(server_item.components.equippable.equipslot, EQUIPSLOTS.BODY)
equal(server_item.components.equippable.restrictedtag, "kryptonian")
assert(server_item.haunt_launch and server_item.components.hauntable == nil,
    "haunting the amulet must not become an alternative revive or cooldown bypass")
assert(server_item.components.finiteuses == nil and server_item.components.fueled == nil)
print("Starcore: native equipment timing, dry/thermal protection, queued revival, cooldown, saves and migration gifts passed.")
