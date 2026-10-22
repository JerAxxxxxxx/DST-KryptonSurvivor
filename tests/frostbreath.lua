local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
package.preload["krypton_combat_targets"] = function()
    return load_source("mod/scripts/krypton_combat_targets.lua")
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < 0.000001, message or "unexpected numeric value")
end

DEGREES, RADIANS, FRAMES = math.pi / 180, 180 / math.pi, 1 / 30
math.atan2 = function(y, x) return math.atan(y, x) end
TUNING = { KRYPTON_SURVIVOR = {
    frostbreath_enabled = true, frostbreath_range = 8, frostbreath_half_angle = 28,
    frostbreath_interval = 1.2, frostbreath_duration = 1, frostbreath_coldness = 2, frostbreath_freezetime = 4,
} }
TheWorld = { ismastersim = true }
TheNet = { paused = false, dedicated = false,
    IsServerPaused = function(self) return self.paused end,
    IsDedicated = function(self) return self.dedicated end,
}
local now, query_count, targets, spawned = 20, 0, {}, {}
GetTime = function() return now end
local function entity(x, z)
    local inst = { x = x or 0, z = z or 0, valid = true, tags = {}, components = {}, tasks = {}, listeners = {}, events = {} }
    inst.IsValid = function(self) return self.valid end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.GetPhysicsRadius = function(self, default) return self.radius or default end
    inst.Transform = {
        GetWorldPosition = function() return inst.x, 0, inst.z end,
        GetRotation = function() return inst.rotation or 0 end,
    }
    inst.components.health = { dead = false, IsDead = function(self) return self.dead end }
    inst.components.combat = { CanTarget = function(self, target) return not target.untargetable end }
    inst.components.freezable = { AddColdness = function(self, amount, duration, nofreeze)
        self.calls = (self.calls or 0) + 1
        self.amount, self.duration, self.nofreeze = amount, duration, nofreeze
    end }
    inst.components.burnable = {
        burning = false, smoldering = false,
        IsBurning = function(self) return self.burning end,
        IsSmoldering = function(self) return self.smoldering end,
        Extinguish = function(self, reset, heat, smotherer)
            self.extinguished = (self.extinguished or 0) + 1
            self.reset, self.heat, self.smotherer = reset, heat, smotherer
            self.burning, self.smoldering = false, false
        end,
    }
    inst.ListenForEvent = function(self, name, fn) self.listeners[name] = fn end
    inst.RemoveEventCallback = function(self, name, fn)
        if self.listeners[name] == fn then self.listeners[name] = nil end
    end
    inst.PushEvent = function(self, name)
        local channel = self._krypton_frostbreath_channel
        table.insert(self.events, { name = name, nextcast = self._krypton_frostbreath_nextcast,
            channel = channel, ready = channel ~= nil and type(channel.stop) == "function"
                and self.listeners.death == channel.stop and channel.task ~= nil and channel.endtask ~= nil })
    end
    local function schedule(delay, fn, periodic)
        local task = { delay = delay, fn = fn, periodic = periodic }
        task.Cancel = function(self) self.cancelled = true end
        table.insert(inst.tasks, task)
        return task
    end
    inst.DoPeriodicTask = function(self, delay, fn) return schedule(delay, fn, true) end
    inst.DoTaskInTime = function(self, delay, fn) return schedule(delay, fn, false) end
    return inst
end
local function player()
    local inst = entity()
    inst.prefab, inst.tags.player, inst.tags.kryptonian = "krypton_survivor", true, true
    inst.components.playercontroller = {
        enabled = true, busy = false, working = false,
        IsEnabled = function(self) return self.enabled end,
        IsBusy = function(self) return self.busy end,
        IsDoingOrWorking = function(self) return self.working end,
    }
    inst.ForceFacePoint = function(self, x, y, z)
        self.rotation = math.atan2(-(z - self.z), x - self.x) * RADIANS
    end
    inst.SuspendKryptonFlightVisual = function(self, duration) self.suspended = duration end
    return inst
end
local function cast_fx()
    local fx = { valid = true }
    fx.IsValid = function(self) return self.valid end
    fx.Remove = function(self) self.valid = false end
    fx.SetCaster = function(self, caster, dx, dz) self.caster, self.dx, self.dz = caster, dx, dz end
    table.insert(spawned, fx)
    return fx
end
SpawnPrefab = function(name)
    equal(name, "krypton_frostbreath_fx", "only one replicated frost cast is created on server")
    return cast_fx()
end
TheSim = { FindEntities = function(self, x, y, z, radius, required, excludes)
    query_count = query_count + 1
    close(radius, 11, "broad phase includes large bodies")
    equal(required, nil, "burning buildings must be queried without combat components")
    return targets
end }
local FrostBreath = load_source("mod/scripts/krypton_frostbreath.lua")
local function reject(p, x, z, message)
    local queries, effects = query_count, #spawned
    equal(FrostBreath.Cast(p, x, z), false, message)
    equal(query_count, queries, message .. " must not acquire targets")
    equal(#spawned, effects, message .. " must not emit FX")
    if p ~= nil then
        equal(p._krypton_frostbreath_nextcast, nil, message .. " must not consume cooldown")
        equal(#p.events, 0, message .. " must not announce a successful cast")
    end
end
reject(nil, 1, 0, "missing player")
for _, value in ipairs({ "1", false, {}, math.huge, -math.huge, 0 / 0 }) do
    reject(player(), value, 0, "invalid x RPC coordinate")
    reject(player(), 1, value, "invalid z RPC coordinate")
end
reject(player(), 0, 0, "same-position aim")
reject(player(), 0.01, 0, "nearly-zero aim")
reject(player(), 1e308, 1e308, "overflowing distance")
for _, modify in ipairs({
    function(p) p.valid = false end,
    function(p) p.prefab = "wilson" end,
    function(p) p.tags.kryptonian = nil end,
    function(p) p.tags.playerghost = true end,
    function(p) p.tags.busy = true end,
    function(p) p.components.health = nil end,
    function(p) p.components.health.dead = true end,
    function(p) p.components.combat = nil end,
    function(p) p.components.playercontroller = nil end,
    function(p) p.components.playercontroller.enabled = false end,
    function(p) p.components.playercontroller.busy = true end,
    function(p) p.components.playercontroller.working = true end,
    function(p) p.components.playercontroller.placer = {} end,
    function(p) p.components.rider = { IsRiding = function() return true end } end,
}) do
    local p = player(); modify(p); reject(p, 1, 0, "ineligible caster")
end
TheWorld.ismastersim = false; reject(player(), 1, 0, "client cannot cast"); TheWorld.ismastersim = true
TheNet.paused = true; reject(player(), 1, 0, "paused server"); TheNet.paused = false
TUNING.KRYPTON_SURVIVOR.frostbreath_enabled = false
reject(player(), 1, 0, "server-disabled ability")
TUNING.KRYPTON_SURVIVOR.frostbreath_enabled = true

local caster = player()
local center, edge, outside, back, distant = entity(4, 0), entity(4, 4 * math.tan(28 * DEGREES)),
    entity(4, 4 * math.tan(28 * DEGREES) + 0.01), entity(-0.01, 0), entity(8.01, 0)
back.radius = 2
local overlap = entity(4, 4 * math.tan(28 * DEGREES) + 0.2); overlap.radius = 0.2
local dead, invalid, untargetable, follower, nofreezable = entity(4), entity(4), entity(4), entity(4), entity(4)
dead.components.health.dead, invalid.valid, untargetable.untargetable = true, false, true
follower.components.follower = { leader = {} }
nofreezable.components.freezable = nil
local protected = {}
for _, tag in ipairs({ "INLIMBO", "player", "playerghost", "companion", "wall", "structure", "FX", "notarget", "invisible", "player_aligned", "domesticated" }) do
    local target = entity(3); target.tags[tag] = true; table.insert(protected, target)
end
local burning_tree, burning_building, burning_friend, smolder, campfire, cooker, furnace =
    entity(4), entity(4), entity(4), entity(4), entity(4), entity(4), entity(4)
for _, target in ipairs({ burning_tree, burning_building, burning_friend, campfire, cooker, furnace }) do
    target.components.burnable.burning = true
end
burning_tree.components.combat, burning_tree.components.health = nil, nil
burning_building.tags.structure, burning_friend.tags.player = true, true
smolder.components.burnable.smoldering = true
campfire.tags.campfire, cooker.tags.cooker, furnace.components.fueled = true, true, {}
targets = { center, edge, outside, back, distant, overlap, dead, invalid, untargetable, follower, nofreezable,
    burning_tree, burning_building, burning_friend, smolder, campfire, cooker, furnace, caster }
for _, target in ipairs(protected) do table.insert(targets, target) end
equal(FrostBreath.Cast(caster, 1, 0), true, "innate cone does not need equipment or resources")
for _, target in ipairs({ center, edge, overlap }) do
    equal(target.components.freezable.calls, 1, "cone target gets one native coldness application")
    equal(target.components.freezable.amount, 2, "coldness does not bypass native boss resistance")
    equal(target.components.freezable.duration, 4, "native requested freeze wearoff")
    equal(target.components.freezable.nofreeze, nil, "native nofreeze state remains authoritative")
end
for _, target in ipairs({ outside, back, distant, dead, invalid, untargetable, follower, caster }) do
    equal(target.components.freezable.calls, nil, "invalid or outside cone remains unfrozen")
end
for _, target in ipairs(protected) do equal(target.components.freezable.calls, nil, "ally or structure remains unfrozen") end
for _, target in ipairs({ burning_tree, burning_building, burning_friend, smolder }) do
    equal(target.components.burnable.extinguished, 1, "accidental fire or smolder extinguished")
    equal(target.components.burnable.reset, true, "propagation heat reset")
    equal(target.components.burnable.heat, 0, "extinguished fire retains no heat")
    equal(target.components.burnable.smotherer, nil, "no inventory item consumed")
end
for _, target in ipairs({ campfire, cooker, furnace }) do
    equal(target.components.burnable.extinguished, nil, "intentional fire source preserved")
end
equal(caster.suspended, 1.1, "flight art exposes animated head while breathing")
close(caster._krypton_frostbreath_nextcast, 21.2, "authoritative cooldown")
local channel = caster._krypton_frostbreath_channel
equal(#caster.events, 1, "one status event after successful frost breath")
equal(caster.events[1].name, "krypton_skillstatechanged", "shared skill feedback event")
equal(caster.events[1].channel, channel, "status sees active channel before notification")
assert(caster.events[1].ready, "status notification follows complete channel/task/listener setup")
close(caster.events[1].nextcast, 21.2, "status sees server cooldown")
equal(#spawned, 1, "one network proxy serves all observers")
equal(spawned[1].caster, caster, "proxy replicates caster")
now = 20.2
local entered = entity(7)
targets = { center, entered }
channel.task.fn(caster)
equal(center.components.freezable.calls, 1, "lingering targets are not repeatedly frozen within one cast")
equal(entered.components.freezable.calls, 1, "entering the cone during the channel is affected")
local queries_before_replay = query_count
equal(FrostBreath.Cast(caster, 100000, 0), false, "rapid RPC replay blocked")
equal(query_count, queries_before_replay, "replay does not acquire entities")
equal(#caster.events, 1, "refused repeat sends no skill status event")
now = 21
channel.endtask.fn(caster)
equal(channel.finished, true, "channel ends on time")
equal(channel.task, nil, "periodic query is cancelled")
equal(caster._krypton_frostbreath_channel, nil, "active channel cleared")
equal(spawned[1].valid, false, "channel clears shared FX")
equal(caster.listeners.death, nil, "death listener removed")
equal(caster.listeners.onremove, nil, "remove listener removed")
equal(#caster.events, 2, "channel completion announces the changed skill state")
equal(caster.events[2].channel, nil, "completion clears channel before notifying HUD")
channel.stop()
equal(#caster.events, 2, "repeated old cleanup cannot notify newer state")
equal(FrostBreath.Cast(caster, 1, 0), false, "cooldown remains after channel completion")
now = 21.2
targets = {}
equal(FrostBreath.Cast(caster, 1, 0), true, "cast allowed at exact cooldown boundary")
caster._krypton_frostbreath_channel.stop()

local superseded = player()
equal(FrostBreath.Cast(superseded, 1, 0), true, "superseded channel fixture")
local old_channel = superseded._krypton_frostbreath_channel
local new_channel = {}
superseded._krypton_frostbreath_channel = new_channel
old_channel.stop()
equal(superseded._krypton_frostbreath_channel, new_channel, "old cleanup preserves a newer channel")
equal(#superseded.events, 1, "only current channel cleanup may announce state changes")

-- Every interruption terminates both effects and periodic target acquisition.
for _, modify in ipairs({
    function(p) p.components.playercontroller.busy = true end,
    function(p) p.components.health.dead = true end,
    function(p) p.tags.playerghost = true end,
    function(p) p.rotation = 180 end,
    function(p) p.valid = false end,
    function(p) TheNet.paused = true end,
}) do
    local p = player()
    equal(FrostBreath.Cast(p, 1, 0), true, "interruption fixture starts cast")
    local active = p._krypton_frostbreath_channel
    modify(p)
    local queries = query_count
    active.task.fn(p)
    equal(query_count, queries, "interrupted channel cannot hit targets")
    assert(active.finished and not active.fx.valid, "interruption removes FX and channel")
    equal(p._krypton_frostbreath_channel, nil, "interruption releases active cast")
    TheNet.paused = false
end
local remove_player = player()
equal(FrostBreath.Cast(remove_player, 1, 0), true)
local removal_channel = remove_player._krypton_frostbreath_channel
remove_player.listeners.onremove()
assert(removal_channel.finished and not removal_channel.fx.valid, "caster removal releases everything")

local diagonal, axis = entity(-3, -3), entity(-3, 0)
targets = { diagonal, axis }
equal(FrostBreath.Cast(player(), -1, -1), true, "non-axis-aligned cone")
equal(diagonal.components.freezable.calls, 1, "diagonal cone hits correct direction")
equal(axis.components.freezable.calls, nil, "diagonal cone rejects outside angle")

-- Model the native component's public contract rather than replacing bosses'
-- resistance, redirect handling, nofreeze states or diminishing returns.
local boss = entity(4)
boss.tags.epic = true
boss.components.freezable = {
    coldness = 0, resistance = 8, calls = 0,
    AddColdness = function(self, amount, freezetime)
        self.calls = self.calls + 1
        if self.redirected then return end
        self.coldness = self.coldness + amount
        if not self.nofreeze and self.coldness >= self.resistance then self.frozen = true end
    end,
}
targets = { boss }
equal(FrostBreath.Cast(player(), 1, 0), true)
equal(boss.components.freezable.coldness, 2, "boss receives ordinary coldness")
equal(boss.components.freezable.frozen, nil, "resistant boss is not force frozen")
boss.components.freezable.nofreeze = true
for _ = 1, 4 do equal(FrostBreath.Cast(player(), 1, 0), true) end
equal(boss.components.freezable.frozen, nil, "native nofreeze decision remains effective")
local old_coldness = boss.components.freezable.coldness
boss.components.freezable.redirected = true
equal(FrostBreath.Cast(player(), 1, 0), true)
equal(boss.components.freezable.coldness, old_coldness, "native redirect remains effective")

for _, coldness in ipairs({ 1, 4, 8 }) do
    TUNING.KRYPTON_SURVIVOR.frostbreath_coldness = coldness
    local target, actor = entity(4), player()
    targets = { target }
    equal(FrostBreath.Cast(actor, 1, 0), true, "configured coldness permits the ordinary cast")
    equal(target.components.freezable.amount, coldness, "selected coldness reaches native AddColdness")
    equal(target.components.freezable.duration, 4, "coldness settings leave native freeze duration unchanged")
    actor._krypton_frostbreath_channel.stop()
end
TUNING.KRYPTON_SURVIVOR.frostbreath_coldness = 2

local register_input = load_source("mod/scripts/krypton_frostbreath_input.lua")
local function input_fixture()
    local G = { TUNING = TUNING, ThePlayer = player(), time = 40, paused = false, sent = {},
        KEY_CTRL = 401, KEY_ALT = 400, KEY_SHIFT = 402,
        TheNet = { dedicated = false, paused = false,
            IsDedicated = function(self) return self.dedicated end,
            IsServerPaused = function(self) return self.paused end },
        TheInput = { registered = 0, position = { x = 7, z = -3 },
            AddKeyDownHandler = function(self, key, fn) self.registered, self.handler = self.registered + 1, fn end,
            IsKeyDown = function(self, key) return self.modifier == key end,
            GetHUDEntityUnderMouse = function(self) return self.hud end,
            GetWorldPosition = function(self) return self.position end },
    }
    G.GetTime = function() return G.time end
    G.IsPaused = function() return G.paused end
    G.ThePlayer.HUD = { HasInputFocus = function(self) return self.focus end }
    G.send = function(x, z) table.insert(G.sent, { x = x, z = z }) end
    return G
end
local disabled = input_fixture(); register_input(disabled, nil, disabled.send)
equal(disabled.TheInput.registered, 0, "disabled key has no handler")
local dedicated = input_fixture(); dedicated.TheNet.dedicated = true; register_input(dedicated, 120, dedicated.send)
equal(dedicated.TheInput.registered, 0, "dedicated server has no input handler")
for _, modify in ipairs({
    function(G) G.ThePlayer = nil end,
    function(G) G.ThePlayer.valid = false end,
    function(G) G.ThePlayer.prefab = "wilson" end,
    function(G) G.ThePlayer.tags.playerghost = true end,
    function(G) G.ThePlayer.tags.busy = true end,
    function(G) G.ThePlayer.HUD = nil end,
    function(G) G.ThePlayer.HUD.focus = true end,
    function(G) G.paused = true end,
    function(G) G.TheNet.paused = true end,
    function(G) G.TheInput.hud = {} end,
    function(G) G.TheInput.position = nil end,
    function(G) G.ThePlayer.components.playercontroller = nil end,
    function(G) G.ThePlayer.components.playercontroller.enabled = false end,
    function(G) G.ThePlayer.components.playercontroller.busy = true end,
    function(G) G.ThePlayer.components.playercontroller.working = true end,
    function(G) G.ThePlayer.components.playercontroller.placer = {} end,
    function(G) G.ThePlayer.replica = { rider = { IsRiding = function() return true end } } end,
}) do
    local G = input_fixture(); register_input(G, 120, G.send); modify(G); G.TheInput.handler()
    equal(#G.sent, 0, "UI/chat/busy/mount guard suppresses ability RPC")
end
for _, key in ipairs({ 401, 400, 402 }) do
    local modified = input_fixture()
    register_input(modified, 120, modified.send)
    modified.TheInput.modifier = key
    modified.TheInput.handler()
    equal(#modified.sent, 1, "modifier state alone must not silently lock frost while heat vision works")
    equal(modified.sent[1].x, 7); equal(modified.sent[1].z, -3)
end
local G = input_fixture(); register_input(G, 120, G.send); G.TheInput.handler()
equal(#G.sent, 1, "valid hotkey sends mouse position")
equal(G.sent[1].x, 7); equal(G.sent[1].z, -3)
G.TheInput.handler(); equal(#G.sent, 1, "client key-repeat limit")
G.time = 41.2; G.TheInput.handler(); equal(#G.sent, 2, "input available at interval boundary")

-- Observers build native mouth-anchored mist locally; only the cast identity
-- and direction are replicated. No native animation files are copied.
-- Match the installed game constants, including camera-relative diagonals.
FACING_RIGHT, FACING_UP, FACING_LEFT, FACING_DOWN = 0, 1, 2, 3
FACING_UPRIGHT, FACING_UPLEFT, FACING_DOWNRIGHT, FACING_DOWNLEFT = 4, 5, 6, 7
-- Native GetSymbolOverride returns numeric build/symbol hashes, as used by
-- balloon_held_child's net_hash fields. Restoration accepts either hash/name.
local hash_values, hash_names, next_hash = {}, {}, 100
hash = function(value)
    if type(value) ~= "string" then return value end
    if hash_values[value] == nil then
        next_hash = next_hash + 1
        hash_values[value], hash_names[next_hash] = next_hash, value
    end
    return hash_values[value]
end
Asset = function(kind, path) return { kind = kind, path = path } end
Prefab = function(name, fn, assets, prefabs) return { name = name, fn = fn, assets = assets, prefabs = prefabs } end
local created = {}
CreateEntity = function()
    local inst = { GUID = #created + 1, tags = {}, tasks = {}, components = {}, valid = true, particles = {} }
    table.insert(created, inst)
    inst.entity = {}
    for _, component in ipairs({ "Transform", "AnimState", "SoundEmitter", "Network" }) do
        inst.entity["Add" .. component] = function() inst["has_" .. component] = true end
    end
    inst.entity.SetCanSleep = function(self, value) inst.can_sleep = value end
    inst.entity.SetPristine = function() inst.pristine = true end
    inst.entity.SetParent = function(self, parent) inst.parent = parent end
    inst.Transform = { SetPosition = function(self, ...) self.position = { ... } end }
    inst.AnimState = {}
    for _, method in ipairs({ "SetBank", "SetBuild", "PlayAnimation", "SetScale", "SetMultColour", "SetLightOverride", "SetBloomEffectHandle", "SetFinalOffset" }) do
        inst.AnimState[method] = function(self, ...) self[method .. "_args"] = { ... } end
    end
    inst.SoundEmitter = { PlaySound = function(self, sound, channel, volume) self.sound, self.channel, self.volume = sound, channel, volume end }
    inst.AddTag = function(self, tag) self.tags[tag] = true end
    inst.AddComponent = function(self, name)
        self.components[name] = { AddPostUpdateFn = function(component, fn) component.update = fn end }
    end
    inst.DoTaskInTime = function(self, delay, fn) table.insert(self.tasks, { delay = delay, fn = fn }) end
    inst.IsValid = function(self) return self.valid end
    inst.Remove = function(self)
        self.valid = false
        if self.OnRemoveEntity ~= nil then self.OnRemoveEntity(self) end
    end
    return inst
end
local native_mist = {}
SpawnPrefab = function(name)
    equal(name, "frostbreath", "local puff reuses the installed native frostbreath prefab")
    local inst = CreateEntity()
    inst.VFXEffect = { AddRotatingParticleUV = function(self, ...) table.insert(inst.particles, { ... }) end }
    table.insert(native_mist, inst)
    return inst
end
local function net_value(initial)
    return { stored = initial, set = function(self, value) self.stored = value end, value = function(self) return self.stored end }
end
net_entity = function() return net_value(nil) end
net_float = function() return net_value(0) end
package.preload["krypton_frostbreath_visual_data"] = function()
    return load_source("mod/scripts/krypton_frostbreath_visual_data.lua")
end
package.preload["krypton_frostbreath_head_data"] = function()
    return load_source("mod/scripts/krypton_frostbreath_head_data.lua")
end
package.preload["krypton_frostbreath_head_visual"] = function()
    return load_source("mod/scripts/krypton_frostbreath_head_visual.lua")
end
package.preload["krypton_eating_visual_data"] = function()
    return load_source("mod/scripts/krypton_eating_visual_data.lua")
end
local Mouth = require("krypton_frostbreath_visual_data")
local HeadData = require("krypton_frostbreath_head_data")
local HeadVisual = require("krypton_frostbreath_head_visual")
local EatingVisual = load_source("mod/scripts/krypton_eating_visual.lua")
local fx_prefab = load_source("mod/scripts/prefabs/krypton_frostbreath_fx.lua")
equal(fx_prefab.name, "krypton_frostbreath_fx")
equal(fx_prefab.assets[1].path, "anim/deer_ice_flakes.zip", "native ice animation dependency")
equal(fx_prefab.assets[2].path, "anim/krypton_frostbreath_head.zip", "only original supplied heads are shipped")
equal(fx_prefab.prefabs[1], "frostbreath", "native frost texture and shader dependency")
local function visual_actor()
    local actor = player()
    actor.entity, actor.overrides, actor.events, actor.replica, actor.writes = {}, {}, {}, {}, 0
    actor.animation, actor.frame = "idle_loop", 0
    actor.facing, actor.head_found, actor.hat_found, actor.symbol_calls = FACING_DOWN, true, false, {}
    actor.pose_x, actor.pose_y, actor.pose_z = 3, 2, 4
    actor.IsAsleep = function(self) return self.asleep == true end
    actor.ListenForEvent = function(self, name, fn)
        self.events[name] = self.events[name] or {}
        table.insert(self.events[name], fn)
    end
    actor.RemoveEventCallback = function(self, name, fn)
        for index, callback in ipairs(self.events[name] or {}) do
            if callback == fn then table.remove(self.events[name], index); break end
        end
    end
    actor.AnimState = {
    IsCurrentAnimation = function(self, animation) return actor.animation == animation end,
    GetCurrentAnimationTime = function() return actor.frame / 30 end,
    GetBuild = function() return actor.build or "krypton_survivor" end,
    GetSkinBuild = function() return actor.skinbuild or "" end,
    GetSymbolOverride = function(self, symbol)
        local value = actor.overrides[symbol]
        if value ~= nil then return hash(value[1]), hash(value[2]) end
    end,
    IsSkinBuild = function(self, build) return hash(build) == hash("genuine_skin") end,
    OverrideSymbol = function(self, target, build, symbol)
        assert(target == "headbase" or target == "headbase_hat", "only the head is overridden")
        actor.overrides[target] = { hash_names[build] or build, hash_names[symbol] or symbol }
        actor.writes = actor.writes + 1
    end,
    OverrideSkinSymbol = function(self, target, build, symbol)
        actor.AnimState:OverrideSymbol(target, build, symbol)
        actor.skin_restores = (actor.skin_restores or 0) + 1
    end,
    ClearOverrideSymbol = function(self, target)
        actor.overrides[target] = nil; actor.writes = actor.writes + 1
    end,
    MakeFacingDirty = function() actor.facing_dirty = true end,
    GetCurrentFacing = function() assert(actor.facing_dirty); actor.facing_dirty = false; return actor.facing end,
    GetSymbolPosition = function(self, symbol, x, y, z)
        table.insert(actor.symbol_calls, { symbol, x, y, z })
        local found = symbol == "headbase" and actor.head_found or symbol == "headbase_hat" and actor.hat_found
        local mirror = actor.facing == FACING_LEFT and -1 or 1
        return actor.pose_x + mirror * x / 150, actor.pose_y - y / 150, actor.pose_z, found
    end,
    }
    return actor
end
local function emit(actor, event)
    local callbacks = {}
    for _, fn in ipairs(actor.events[event] or {}) do table.insert(callbacks, fn) end
    for _, fn in ipairs(callbacks) do fn(actor) end
end
local function head_pose(actor, expected)
    for _, target in ipairs({ "headbase", "headbase_hat" }) do
        local value = actor.overrides[target]
        if expected == nil then
            equal(value, nil, "ordinary/back head must remain native")
        else
            assert(value ~= nil, "mouth-open head missing")
            equal(value[1], HeadData.build, "head comes from supplied head.jpg pixels")
            equal(value[2], HeadData.poses[expected].symbol, "direction chooses matching supplied head")
        end
    end
end
local actor = visual_actor()
TheWorld.ismastersim = false
local local_fx = fx_prefab.fn()
assert(local_fx.has_Network and local_fx.pristine and not local_fx.has_AnimState, "only the identity proxy is networked")
equal(local_fx.SetCaster, nil, "client cannot author proxy source")
equal(local_fx.persists, false, "cast is never saved")
local updater = local_fx.components.updatelooper.update
local count = #created
updater(local_fx)
equal(#created, count, "unresolved caster does not leak artwork")
local_fx._caster:set(actor); local_fx._angle:set(0); local_fx._started:set(100)
now = 100
updater(local_fx)
equal(actor.suspended, 1.1, "observer restores native mouth-bearing head during flight")
equal(#local_fx._flakes, 8, "bounded native ice crystal entities")
local mist = local_fx._mist
head_pose(actor, "front")
close(mist.Transform.position[1], actor.pose_x + HeadData.poses.front.mouth[1] / 150, "front mist begins at new open mouth x")
close(mist.Transform.position[2], actor.pose_y - HeadData.poses.front.mouth[2] / 150, "front mist begins at new open mouth height")
equal(#mist.particles, 2, "bounded emission per animation update")
for _, particle in ipairs(mist.particles) do
    equal(particle[1], 0, "native emitter zero")
    close(particle[2], 0.65, "short forward mist lifetime")
    equal(particle[3], 0, "mist begins exactly at mouth")
    equal(particle[4], 0, "no torso-height fixed emission")
    equal(particle[5], 0, "no root or rear-origin offset")
    assert(particle[6] > 0, "eastward mist velocity points forward")
    assert(math.abs(particle[8] / particle[6]) <= math.tan(28 * DEGREES) + 0.000001, "mist rays stay inside cone")
end
local mist_count, crystal_list = #native_mist, local_fx._flakes
now = now + FRAMES + 0.001
actor.pose_x, actor.pose_y, actor.pose_z = 13, 2.4, -8
updater(local_fx)
equal(#native_mist, mist_count, "animated source reuses native emitter")
equal(local_fx._flakes, crystal_list, "animated source reuses bounded crystal list")
close(mist.Transform.position[1], 13 + HeadData.poses.front.mouth[1] / 150, "mist tracks moving new animated head")
actor.facing = FACING_LEFT
updater(local_fx)
head_pose(actor, "side")
close(mist.Transform.position[1], 13 - HeadData.poses.side.mouth[1] / 150, "profile mouth follows native mirror")
close(mist.Transform.position[2], 2.4 - HeadData.poses.side.mouth[2] / 150, "profile uses new authored open mouth")
actor.overrides.headbase = { HeadData.build, HeadData.poses.front.symbol }
actor.overrides.headbase_hat = { HeadData.build, HeadData.poses.front.symbol }
updater(local_fx)
head_pose(actor, "side")
actor.facing = FACING_RIGHT
updater(local_fx)
head_pose(actor, "side")
close(mist.Transform.position[1], 13 + HeadData.poses.side.mouth[1] / 150, "right side uses same authored symbol without mirroring pixels")
actor.facing = FACING_UP
updater(local_fx)
head_pose(actor, nil)
close(mist.Transform.position[1], 13 + Mouth.back.mouth[1] / 150, "back view uses head-based forward origin")
actor.overrides.headbase = { HeadData.build, HeadData.poses.front.symbol }
actor.overrides.headbase_hat = { HeadData.build, HeadData.poses.front.symbol }
updater(local_fx)
head_pose(actor, nil)
actor.head_found, actor.hat_found, actor.symbol_calls = false, true, {}
updater(local_fx)
equal(actor.symbol_calls[1][1], "headbase", "try ordinary head symbol first")
equal(actor.symbol_calls[2][1], "headbase_hat", "hat uses native head fallback")
actor.hat_found = false
updater(local_fx)
equal(local_fx._mist, nil, "missing head clears obsolete mouth mist")
assert(not mist.valid, "missing head removes native emitter")
for _, crystal in ipairs(crystal_list) do assert(not crystal.fx.valid, "missing head removes native flakes") end
actor.head_found = true
actor.facing = FACING_DOWN
updater(local_fx)
head_pose(actor, "front")
local sleeping_mist, sleeping_flakes = local_fx._mist, local_fx._flakes
local_fx.OnEntitySleep(local_fx)
head_pose(actor, nil)
assert(not sleeping_mist.valid and local_fx._mist == nil, "sleep removes local particle emitter")
for _, crystal in ipairs(sleeping_flakes) do assert(not crystal.fx.valid, "sleep removes local flakes") end
count = #created; updater(local_fx); equal(#created, count, "sleeping proxy cannot recreate particle effects")
local_fx.OnEntityWake(local_fx)
assert(local_fx._mist ~= nil, "wake resolves mouth position again")
head_pose(actor, "front")
local last_mist = local_fx._mist
local_fx:Remove()
assert(not last_mist.valid and local_fx._mist == nil, "network removal clears all local effects")
head_pose(actor, nil)
actor.tags.playerghost = true
local ghost_proxy = fx_prefab.fn(); ghost_proxy._caster:set(actor); updater(ghost_proxy)
equal(ghost_proxy._mist, nil, "ghost source never emits cold mist")
actor.tags.playerghost = nil

TheWorld.ismastersim = true
local host_fx = fx_prefab.fn()
host_fx:SetCaster(actor, 1, 0)
equal(host_fx._caster:value(), actor, "server replicates caster")
equal(host_fx.parent, actor.entity, "proxy follows network interest of source")
equal(host_fx.tasks[1].delay, 1, "server owns fixed channel FX lifetime")
assert(host_fx._mist ~= nil, "host renders local native effects")
host_fx.tasks[1].fn(host_fx)
equal(host_fx._mist, nil, "server TTL clears host visuals")
head_pose(actor, nil)
assert(host_fx.SoundEmitter.sound ~= nil, "native frost sound plays once per cast")
TheNet.dedicated = true
count = #created
local dedicated_fx = fx_prefab.fn(); dedicated_fx:SetCaster(actor, 1, 0)
equal(#created, count + 1, "dedicated server creates only network cast")
equal(dedicated_fx._mist, nil, "dedicated server does not emit local particles")
equal(next(dedicated_fx.components), nil, "dedicated server has no render update component")
equal(HeadVisual.Apply(actor, dedicated_fx, "front", now), false, "dedicated server never changes head symbols")
head_pose(actor, nil)
TheNet.dedicated = false
TheWorld.ismastersim = false

local function observer_cast(source, started, angle)
    local fx = fx_prefab.fn()
    fx._caster:set(source); fx._angle:set(angle or 0); fx._started:set(started or now)
    updater(fx)
    return fx
end

-- The server owns the cast angle. An observer's camera-facing selection and
-- predicted/world rotation can arrive in a different frame from the cast
-- identity. These rendering inputs must never silently cancel a valid cast.
local function expected_head(facing)
    if facing == FACING_RIGHT or facing == FACING_LEFT then return "side" end
    if facing == FACING_UP or facing == FACING_UPRIGHT or facing == FACING_UPLEFT then return nil end
    return "front"
end
local function forward_particles(mist, from, angle)
    local dx, dz = math.cos(angle * DEGREES), -math.sin(angle * DEGREES)
    for index = from, #mist.particles do
        local particle = mist.particles[index]
        local vx, vz = particle[6], particle[8]
        local forward, lateral = vx * dx + vz * dz, vx * -dz + vz * dx
        assert(forward > 0, "mist follows the authoritative cast direction, not a stale body rotation")
        assert(math.abs(lateral) <= forward * math.tan(28 * DEGREES) + .000001,
            "all new particles remain inside the authoritative cone")
    end
end
for _, angle in ipairs({ 0, 45, 90, 135, 180, 225, 270, 315 }) do
    for _, facing in ipairs({ FACING_DOWN, FACING_RIGHT, FACING_UP, FACING_LEFT }) do
        local p = visual_actor()
        p.facing = facing
        p.rotation = (angle + 90) % 360 -- predicted rotation is one update behind
        local fx = observer_cast(p, now, angle)
        assert(fx._mist ~= nil, "eight-direction cast must render before observer rotation catches up")
        head_pose(p, expected_head(facing))
        equal(#fx._flakes, 8, "every cardinal/diagonal cast retains all ice crystals")
        equal(#fx._mist.particles, 2, "diagonal emission retains the same per-update budget")
        forward_particles(fx._mist, 1, angle)
        local first_mist, first_flakes = fx._mist, fx._flakes
        local previous_count = #first_mist.particles
        -- A transient client-side turn, followed by synchronization, must not
        -- poison the expression token or recreate the whole effect.
        now = now + FRAMES + .001
        p.rotation = (angle + 180) % 360
        updater(fx)
        assert(not fx._krypton_breath_stopped, "predicted rotation must not permanently stop a valid expression")
        equal(fx._mist, first_mist, "predicted rotation does not remove the native mist emitter")
        equal(fx._flakes, first_flakes, "predicted rotation keeps the bounded crystal list")
        head_pose(p, expected_head(facing))
        forward_particles(first_mist, previous_count + 1, angle)
        now = now + FRAMES + .001
        p.rotation = angle
        updater(fx)
        equal(fx._mist, first_mist, "effects remain active when rotation synchronization completes")
        head_pose(p, expected_head(facing))
        fx:Remove()
        head_pose(p, nil)
        assert(not first_mist.valid, "authoritative proxy removal clears diagonal mist")
        for _, crystal in ipairs(first_flakes) do
            assert(not crystal.fx.valid, "authoritative proxy removal clears diagonal ice crystals")
        end
    end
end

-- The caster can be resolved before its angle packet. A later diagonal cast
-- angle plus one stale predicted turn must not permanently disable its head.
local async_actor = visual_actor()
local async_fx = observer_cast(async_actor)
local async_mist, async_flakes = async_fx._mist, async_fx._flakes
head_pose(async_actor, "front")
now = now + FRAMES + .001
async_fx._angle:set(45)
async_actor.rotation = 180
local async_count = #async_mist.particles
updater(async_fx)
equal(async_fx._mist, async_mist, "late angle replication keeps an already established cast visible")
equal(async_fx._flakes, async_flakes, "late angle replication reuses crystals")
assert(not async_fx._krypton_breath_stopped, "a transient rotation disagreement cannot poison the expression token")
head_pose(async_actor, "front")
forward_particles(async_mist, async_count + 1, 45)
now = now + FRAMES + .001
async_actor.rotation, async_actor.facing = 45, FACING_RIGHT
updater(async_fx)
head_pose(async_actor, "side")
equal(async_fx._mist, async_mist, "camera-facing changes only reselect the mouth/head pose")
async_fx:Remove(); head_pose(async_actor, nil)
assert(not async_mist.valid, "server removal still ends asynchronously replicated effects")

-- Every replicated native action and lifecycle interrupt releases our own
-- expression. No body clips, foods, held items or skin builds are replaced.
for _, modify in ipairs({
    function(p) p.tags.busy = true end,
    function(p) p.tags.playerghost = true end,
    function(p) p.tags.corpse = true end,
    function(p) p.components.health.dead = true end,
    function(p) p.components.playercontroller.busy = true end,
    function(p) p.components.playercontroller.working = true end,
    function(p) p.components.rider = { IsRiding = function() return true end } end,
    function(p) p.animation = "hit" end,
    function(p) p.animation = "attack" end,
    function(p) p.animation = "chop_pre" end,
    function(p) p.animation = "mine" end,
    function(p) p.animation = "dig" end,
    function(p) p.valid = false end,
}) do
    local p = visual_actor()
    local fx = observer_cast(p)
    head_pose(p, "front")
    modify(p)
    updater(fx)
    head_pose(p, nil)
    equal(fx._mist, nil, "interrupted cast clears mist with head")
    fx:Remove()
end
for _, event in ipairs({ "death", "ms_becameghost", "mounted", "isridingdirty",
    "ms_playerreroll", "equipskinneditem", "unequipskinneditem", "onremove" }) do
    local p = visual_actor()
    local fx = observer_cast(p)
    emit(p, event)
    head_pose(p, nil)
    updater(fx)
    head_pose(p, nil)
    equal(fx._mist, nil, "lifecycle event cannot reapply expression on delayed FX update")
    fx:Remove()
end
local sleeping = visual_actor()
local sleeping_fx = observer_cast(sleeping)
sleeping.asleep = true; emit(sleeping, "entitysleep")
head_pose(sleeping, nil)
updater(sleeping_fx); head_pose(sleeping, nil)
sleeping.asleep = false
updater(sleeping_fx); head_pose(sleeping, "front")
sleeping_fx:Remove(); head_pose(sleeping, nil)

local layered = visual_actor()
layered.overrides.headbase = { "genuine_skin", "old_skin_head" }
layered.overrides.headbase_hat = { "hat_build", "old_hat_head" }
local layered_fx = observer_cast(layered)
layered.facing = FACING_RIGHT; updater(layered_fx)
layered_fx:Remove()
equal(layered.overrides.headbase[1], "genuine_skin", "restore skin through native skin API")
equal(layered.overrides.headbase[2], "old_skin_head", "restore exact pre-cast head")
equal(layered.overrides.headbase_hat[1], "hat_build", "restore head/hat overrides independently")
equal(layered.skin_restores, 1, "only genuine skin override uses skin API")
local funny = visual_actor()
funny.animation = "idle_inaction"
local funny_fx = observer_cast(funny)
head_pose(funny, "front")
funny_fx:Remove(); head_pose(funny, nil)

local external = visual_actor()
local external_fx = observer_cast(external)
external.overrides.headbase = { "external_face", "chosen_face" }
updater(external_fx)
equal(external.overrides.headbase[1], "external_face", "keep newly chosen external face")
equal(external.overrides.headbase_hat, nil, "release only head still owned by this cast")
updater(external_fx)
equal(external.overrides.headbase[1], "external_face", "do not reclaim externally changed head")
external_fx:Remove()
local changed = visual_actor()
changed.overrides.headbase = { "old_outfit", "old_head" }
local changed_fx = observer_cast(changed)
changed.build, changed.skinbuild, changed.skinname = "new_character", "new_outfit", "new_skin"
updater(changed_fx)
head_pose(changed, nil)
updater(changed_fx); head_pose(changed, nil)
changed_fx:Remove()

local late = visual_actor()
late.overrides.headbase = { HeadData.build, HeadData.poses.front.symbol }
late.overrides.headbase_hat = { HeadData.build, HeadData.poses.front.symbol }
local late_fx = observer_cast(late)
late_fx:Remove(); head_pose(late, nil)

local concurrent = visual_actor()
local old_fx = observer_cast(concurrent, now)
local new_fx = observer_cast(concurrent, now + 2)
head_pose(concurrent, "front")
updater(old_fx); old_fx:Remove()
head_pose(concurrent, "front")
equal(concurrent._krypton_breath_head.token, new_fx, "old cleanup cannot clear a newer cast")
new_fx:Remove(); head_pose(concurrent, nil)
local delayed_fx = observer_cast(concurrent, now + 1)
head_pose(concurrent, nil)
equal(delayed_fx._mist, nil, "late-arriving older cast cannot resurrect old expression")
delayed_fx:Remove()

-- Exercise both real module orderings instead of duplicating eating's logic.
for _, eating_first in ipairs({ true, false }) do
    local p = visual_actor()
    p.overrides.headbase = { "genuine_skin", "pre_breath_head" }
    EatingVisual.CommonInit(p)
    local fx = observer_cast(p)
    p.animation = "eat_pre"
    if eating_first then
        -- Native newstate listeners register eating before this cast.
        emit(p, "newstate")
    else
        updater(fx)
        EatingVisual.Apply(p)
    end
    equal(p.overrides.headbase[1], "krypton_eating_build", "meal owns active expression after interruption")
    updater(fx)
    equal(p.overrides.headbase[1], "krypton_eating_build", "old FX cannot overwrite eating")
    p.animation = "idle_loop"; EatingVisual.Apply(p)
    equal(p.overrides.headbase[1], "genuine_skin", "meal restores original skin instead of breath head")
    equal(p.overrides.headbase[2], "pre_breath_head", "meal baseline handoff keeps exact prior symbol")
    equal(p.overrides.headbase_hat, nil, "meal cannot resurrect a temporary breath hat head")
    fx:Remove()
end

print("Frost breath tests passed: authority, cone edges, protected targets, native freezing and fire safety, RPC guards, authored open-mouth origins, eight-direction/camera/prediction parity, mirrored/front/back poses, lifecycle/skin cleanup, concurrent casts, real eating handoff and dedicated-server isolation.")
