-- Lua ownership/authority contracts only. The optional installed-game audit
-- runs actual native clothing code; no C++ renderer is reproduced here.
local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err); return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function forbidden(name) return function() error("Clothing must preserve " .. name) end end
FRAMES = 1 / 30
local now, dedicated, next_guid = 10, false, 0
GetTime = function() return now end
TheWorld = { ismastersim = true }
TheNet = { IsDedicated = function() return dedicated end, IsServerPaused = function() return false end }
TUNING = { KRYPTON_SURVIVOR = { darkform_sanity_percent = .05, darkform_toggle_interval = .35 } }
local names, hashes, next_hash = {}, {}, 13000
hash = function(value)
    if type(value) == "number" or value == nil then return value end
    if hashes[value] == nil then
        next_hash = next_hash + 1; hashes[value], names[next_hash] = next_hash, value
    end
    return hashes[value]
end
local function name(value) return names[value] or value end
Class = function(constructor)
    local class = {}; class.__index = class
    return setmetatable(class, { __call = function(_, ...)
        local value = setmetatable({}, class); constructor(value, ...); return value
    end })
end
net_bool = function()
    local master = TheWorld.ismastersim
    return { state = false, writes = 0, value = function(self) return self.state end,
        set = function(self, value)
            assert(master and TheWorld.ismastersim, "Observers cannot author form state")
            self.state, self.writes = value, self.writes + 1
        end }
end
package.preload.krypton_darkform = function() return load_source("mod/scripts/krypton_darkform.lua") end
package.preload.krypton_eating_visual_data = function() return load_source("mod/scripts/krypton_eating_visual_data.lua") end
local Form = require("krypton_darkform")
local Core = load_source("mod/scripts/components/krypton_darkform.lua")
local Suit = load_source("mod/scripts/krypton_darkform_visual.lua")
local Flight = load_source("mod/scripts/krypton_flight_visual.lua")
local Eating = load_source("mod/scripts/krypton_eating_visual.lua")
local BODY, FLIGHT, DARK_FLIGHT = "krypton_dark_suit", "krypton_flight_build", "krypton_dark_flight"
local CLOTHES = { "torso", "torso_pelvis", "arm_upper", "arm_lower", "leg", "foot" }
local CLOTHING = { torso = true, torso_pelvis = true, arm_upper = true, arm_lower = true, leg = true,
    foot = true, skirt = true, arm_lower_cuff = true, arm_upper_skin = true, hand = true }
local function emit(inst, event, data)
    local callbacks = {}
    for fn in pairs(inst.events[event] or {}) do callbacks[#callbacks + 1] = fn end
    for _, fn in ipairs(callbacks) do fn(inst, data) end
end
local function pump(inst, duration)
    local finish, count = now + duration, 0
    while true do
        local next_task
        for _, task in ipairs(inst.tasks) do
            if not task.cancelled and not task.done and task.at <= finish
                and (next_task == nil or task.at < next_task.at) then next_task = task end
        end
        if not next_task then break end
        count = count + 1; assert(count < 1000, "No recursive zero-delay visual refresh")
        now, next_task.done = next_task.at, true; next_task.fn(inst)
        if next_task.period and not next_task.cancelled then
            next_task.done, next_task.at = false, now + next_task.period
        end
    end
    now = finish
end
local function player(master)
    TheWorld.ismastersim = master; next_guid = next_guid + 1
    local inst = { GUID = next_guid, prefab = "krypton_survivor", valid = true, events = {}, tasks = {},
        components = {}, replica = {}, tags = { kryptonian = true }, calls = {},
        requests = {}, skin_requests = {}, builds = {}, build_log = {}, symbol_log = {},
        animation = "idle_loop", frame = 0, plays = 0, flying = false, build = "krypton_survivor", skinbuild = "krypton_survivor" }
    inst.IsValid = function(self) return self.valid end
    inst.IsAsleep = function(self) return self.asleep == true end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.ListenForEvent = function(self, event, fn)
        self.events[event] = self.events[event] or {}; self.events[event][fn] = true
    end
    inst.RemoveEventCallback = function(self, event, fn)
        if self.events[event] then self.events[event][fn] = nil end
    end
    inst.PushEvent = emit
    local function schedule(delay, fn, period)
        local task = { at = now + delay, fn = fn, period = period,
            Cancel = function(self) self.cancelled = true end }
        inst.tasks[#inst.tasks + 1] = task; return task
    end
    inst.DoTaskInTime = function(self, delay, fn) return schedule(delay, fn) end
    inst.DoPeriodicTask = function(self, period, fn, initial) return schedule(initial or period, fn, period) end
    local health = { dead = false, IsDead = function(self) return self.dead end }
    local rider = { riding = false, IsRiding = function(self) return self.riding end }
    if master then
        inst.components.health, inst.components.rider = health, rider
        inst.components.sanity = { percent = .81, GetRealPercent = function(self) return self.percent end,
            GetPenaltyPercent = function() return 0 end,
            SetPercent = function(self, value) self.percent = value; emit(inst, "sanitydelta") end }
        inst.components.playercontroller = { IsEnabled = function() return true end,
            IsBusy = function() return false end, IsDoingOrWorking = function() return false end }
        inst.sg = { currentstate = { name = "idle" }, HasStateTag = function() return false end,
            HasAnyStateTag = function() return false end }
        inst.components.skinner = {
            clothing = { body = "real_coat", hand = "real_gloves", legs = "real_trousers", feet = "real_shoes" },
            skin_data = { normal_skin = "krypton_survivor", ghost_skin = "ghost_wilson_build" },
            mode = "normal_skin", monkey_curse = nil,
            GetSkinMode = function(self) return self.mode end,
            GetMonkeyCurse = function(self) return self.monkey_curse end,
        }
    else inst.replica.health, inst.replica.rider = health, rider end
    local function request(kind, target, build, symbol)
        inst.symbol_log[#inst.symbol_log + 1] = { kind, target, name(build), name(symbol) }
        local map = kind == "skin" and inst.skin_requests or inst.requests
        map[target] = { name(build), name(symbol) }
    end
    inst.AnimState = {
        _owner = inst,
        OverrideSymbol = function(_, target, build, symbol) request("symbol", target, build, symbol) end,
        OverrideSkinSymbol = function(_, target, build, symbol) request("skin", target, build, symbol) end,
        ClearOverrideSymbol = function(_, target)
            inst.requests[target], inst.skin_requests[target] = nil, nil
            inst.symbol_log[#inst.symbol_log + 1] = { "clear", target }
        end,
        -- Stand-in only for flight/eating ownership, not a visible renderer.
        GetSymbolOverride = function(_, target)
            local value = inst.requests[target] or inst.skin_requests[target]
            if value then return hash(value[1]), hash(value[2]) end
        end,
        IsSkinBuild = function(_, build) return name(build) ~= BODY end,
        AddOverrideBuild = function(_, build)
            inst.builds[build] = true; inst.build_log[#inst.build_log + 1] = { "add", build }
        end,
        ClearOverrideBuild = function(_, build)
            inst.builds[build] = nil; inst.build_log[#inst.build_log + 1] = { "clear", build }
        end,
        GetBuild = function() return inst.build end, GetSkinBuild = function() return inst.skinbuild end,
        IsCurrentAnimation = function(_, animation) return inst.animation == animation end,
        GetCurrentAnimationTime = function() return inst.frame / 30 end,
        GetCurrentAnimationLength = function() return 1 end,
        PlayAnimation = function(_, animation, loop) inst.animation, inst.loop, inst.plays = animation, loop, inst.plays + 1 end,
        SetTime = function(_, value) inst.phase = value end,
        SetSkin = forbidden("base skin / face"), SetBuild = forbidden("base build"),
        SetBank = forbidden("animation bank"), SetMultColour = forbidden("colour"),
        Hide = forbidden("equipment visibility"), Show = forbidden("equipment visibility"),
    }
    Form.CommonInit(inst)
    if master then inst.components.krypton_darkform = Core(inst) end
    return inst, health, rider
end
-- Helper argument spy only. Real helper execution belongs to the separate
-- installed-game audit, which includes skirts, cuffs, hide state and exchanges.
SetSkinsOnAnim = function(anim, prefab, base, clothing, curse, mode, default_build)
    local inst = anim._owner
    assert(TheWorld.ismastersim, "Only authority may change replicated clothing")
    equal(prefab, "krypton_survivor")
    equal(mode, "NO_BASE", "Clothes-only helper preserves live faces and action heads")
    inst.calls[#inst.calls + 1] = { base = base, clothing = clothing, curse = curse, mode = mode, default_build = default_build }
    for symbol in pairs(CLOTHING) do anim:ClearOverrideSymbol(symbol) end
end
local function common(inst) Suit.CommonInit(inst, Form.IsDark); pump(inst, 0) end
local function dark_requests(inst)
    for _, symbol in ipairs(CLOTHES) do
        local request = inst.requests[symbol]
        assert(request and request[1] == BODY and request[2] == symbol, "Authority requests authored dark joint: " .. symbol)
    end
end
local function receive(inst, value) inst._krypton_dark_form.state = value; emit(inst, Form.DIRTY_EVENT) end
local host = player(true)
common(host)
local initial_calls = #host.calls
for _ = 1, 12 do Suit.Apply(host) end
equal(#host.calls, initial_calls, "Stable normal state does not rebuild clothing")
assert(Form.Toggle(host))
equal(#host.calls, initial_calls + 1, "One native clothes reset on dark entry")
equal(next(host.calls[#host.calls].clothing), nil, "Dark removes every native clothing part through the helper")
dark_requests(host)
local calls, writes = #host.calls, #host.symbol_log
for _ = 1, 12 do Suit.Apply(host) end
equal(#host.calls, calls, "Stable dark mode does not keep resetting clothes")
equal(#host.symbol_log, writes, "Stable dark mode does not rebind symbols")
local saved = host.components.krypton_darkform:OnSave()
equal(saved.dark, true); equal(saved.normal_percent, .81)
pump(host, .35); assert(Form.Toggle(host))
equal(#host.calls, calls + 1)
equal(host.calls[#host.calls].clothing, host.components.skinner.clothing, "Normal exit rebuilds real native skinner clothing")
for _, symbol in ipairs(CLOTHES) do equal(host.requests[symbol], nil, "No dark ordinary override survives reset") end
for _, is_dedicated in ipairs({ false, true }) do
    dedicated = is_dedicated
    local server = player(true)
    local existing_tasks = #server.tasks
    common(server)
    for index = existing_tasks + 1, #server.tasks do
        assert(not server.tasks[index].period, "No periodic wardrobe writer")
    end
    assert(Form.Toggle(server)); dark_requests(server)
    local server_calls = #server.calls
    pump(server, .35); assert(Form.Toggle(server))
    equal(#server.calls, server_calls + 1, "Dedicated authority must restore native clothing too")
end
dedicated = false
local remote = player(false)
local tasks, symbol_writes, build_writes = #remote.tasks, #remote.symbol_log, #remote.build_log
common(remote)
for _, dark in ipairs({ true, false, true, false }) do
    receive(remote, dark); Suit.Apply(remote); Suit.Clear(remote); Suit.OnSkinModeChanged(remote)
end
equal(#remote.tasks, tasks, "Observers install no wardrobe task")
equal(#remote.symbol_log, symbol_writes, "Observers leave authoritative clothing symbols alone")
equal(#remote.build_log, build_writes, "Observers do not author body clothing builds")
equal(#remote.calls, 0, "Observers never rebuild clothing")
equal(remote._krypton_dark_form.writes, 0)

TheWorld.ismastersim = true
local changed = player(true)
common(changed); receive(changed, true); dark_requests(changed)
local revised = { body = "new_coat", hand = "new_gloves", legs = "new_pants", feet = "new_shoes" }
changed.components.skinner.clothing = revised
SetSkinsOnAnim(changed.AnimState, changed.prefab, "krypton_survivor", revised, nil, "NO_BASE")
calls = #changed.calls; Suit.OnSkinModeChanged(changed)
equal(#changed.calls, calls + 1, "A native outfit update is followed by one dark reapply")
dark_requests(changed); receive(changed, false)
equal(changed.calls[#changed.calls].clothing, revised, "Normal uses current clothing, not saved six-part snapshots")
calls = #changed.calls; Suit.OnSkinModeChanged(changed)
equal(#changed.calls, calls, "Normal native skin mode completion is already the authoritative outfit")
changed.components.skinner.monkey_curse = "MONKEY_CURSE_2"
receive(changed, true); receive(changed, false)
equal(changed.calls[#changed.calls].curse, "MONKEY_CURSE_2", "Normal passes through native monkey curse")
receive(changed, true)
changed.components.skinner.mode = "ghost_skin"
SetSkinsOnAnim(changed.AnimState, changed.prefab, "ghost_wilson_build", {}, nil, "NO_BASE")
calls = #changed.calls; Suit.OnSkinModeChanged(changed)
equal(#changed.calls, calls, "Native ghost mode cannot acquire living dark clothes")
for _, symbol in ipairs(CLOTHES) do equal(changed.requests[symbol], nil, "Ghost skin stays free of dark clothes") end
changed.components.skinner.mode = "normal_skin"
Suit.OnSkinModeChanged(changed); dark_requests(changed)
local protected = player(true)
protected.requests.headbase = { "custom_face", "face_source" }
protected.requests.headbase_hat = { "custom_hat_face", "hat_face_source" }
protected.requests.swap_hat = { "equipped_hat", "swap_hat" }
protected.requests.swap_object = { "krypton_staff", "swap_krypton_staff" }
protected.builds.other_mod_effect = true
common(protected)
for _, dark in ipairs({ true, false, true, false }) do receive(protected, dark) end
equal(protected.requests.headbase[1], "custom_face")
equal(protected.requests.headbase_hat[1], "custom_hat_face")
equal(protected.requests.swap_hat[1], "equipped_hat")
equal(protected.requests.swap_object[1], "krypton_staff")
equal(protected.builds.other_mod_effect, true)
equal(protected.plays, 0, "Clothing changes cannot restart animation")
local loaded, health = player(true)
common(loaded); loaded.components.krypton_darkform:OnLoad(saved); pump(loaded, 0)
dark_requests(loaded); equal(loaded.components.sanity.percent, .05)
loaded.asleep = true; emit(loaded, "entitysleep")
equal(loaded.calls[#loaded.calls].clothing, loaded.components.skinner.clothing)
loaded.asleep = false; emit(loaded, "entitywake"); dark_requests(loaded)
health.dead, loaded.tags.playerghost = true, true
emit(loaded, "death"); emit(loaded, "ms_becameghost"); calls = #loaded.calls
for _ = 1, 3 do Suit.Apply(loaded) end
equal(#loaded.calls, calls, "Ghost cannot repeatedly install living clothes")
health.dead, loaded.tags.playerghost = false, nil
emit(loaded, "ms_respawnedfromghost"); dark_requests(loaded)
loaded.tags.corpse = true; emit(loaded, "newstate")
loaded.tags.corpse = nil; emit(loaded, "respawnfromcorpse"); dark_requests(loaded)
loaded.valid = false; emit(loaded, "onremove")
calls = #loaded.calls; pump(loaded, 1)
equal(#loaded.calls, calls, "Removal cancels delayed clothing mutation")
local unready = player(true); unready.components.skinner = nil
common(unready); receive(unready, true)
equal(#unready.calls, 0, "Common initialization can precede skinner creation")
local removed = player(true)
Suit.CommonInit(removed, Form.IsDark)
removed._krypton_dark_form.state, removed.valid = true, false
emit(removed, "onremove"); pump(removed, 0)
equal(#removed.calls, 0, "Removal before initial refresh cancels it")

TheWorld.ismastersim = true
local flyer = player(true)
common(flyer); Flight.CommonInit(flyer, function(inst) return inst.flying end)
flyer.flying = true; Flight.Apply(flyer)
equal(flyer.requests.krypton_flight_body[1], FLIGHT)
local plays = flyer.plays
receive(flyer, true); dark_requests(flyer)
equal(flyer.requests.krypton_flight_body[1], DARK_FLIGHT)
equal(flyer.plays, plays, "Airborne form change preserves animation phase")
receive(flyer, false); equal(flyer.requests.krypton_flight_body[1], FLIGHT)
local observer = player(false)
common(observer); Flight.CommonInit(observer, function(inst) return inst.flying end)
observer.flying = true; Flight.Apply(observer); receive(observer, true)
equal(observer.requests.krypton_flight_body[1], DARK_FLIGHT)
equal(#observer.calls, 0, "Client flight does not imply client wardrobe writes")
for _, dark in ipairs({ false, true }) do
    local cold = player(false); cold._krypton_dark_form.state, cold.flying = dark, true
    common(cold); Flight.CommonInit(cold, function(inst) return inst.flying end)
    equal(cold.requests.krypton_flight_body[1], dark and DARK_FLIGHT or FLIGHT)
    cold.requests.krypton_flight_body = nil; Flight.Apply(cold)
    equal(cold.requests.krypton_flight_body[1], dark and DARK_FLIGHT or FLIGHT, "Flight repairs its own missing binding")
end
for _, eating_first in ipairs({ true, false }) do
    local diner = player(true)
    diner.requests.headbase = { "genuine_face", "original_face" }
    diner.requests.headbase_hat = { "genuine_face", "original_hat_face" }
    if eating_first then Eating.CommonInit(diner); common(diner) else common(diner); Eating.CommonInit(diner) end
    diner.animation, diner.frame = "eat", 24; Eating.Apply(diner)
    equal(diner.requests.headbase[1], "krypton_eating_build")
    for _, dark in ipairs({ true, false, true }) do
        receive(diner, dark); Eating.Apply(diner)
        equal(diner.requests.headbase[1], "krypton_eating_build", "Clothes helper preserves active eating head")
    end
    diner.animation = "idle_loop"; Eating.Apply(diner)
    equal(diner.skin_requests.headbase[1], "genuine_face", "Eating requests its original skin source again")
    equal(diner.skin_requests.headbase[2], "original_face")
    equal(diner._krypton_eating_overrides, nil, "Eating releases temporary ownership")
end
print("Dark suit Lua contracts passed: authoritative clothes writer including dedicated hosts, no observer wardrobe polling, clothes-only native helper selection, current outfit/curse restoration, lifecycle and preserved flight/eating ownership. Native helper and GPU rendering are separate checks.")
