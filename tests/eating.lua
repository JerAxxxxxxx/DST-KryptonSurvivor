local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Native Wilson/Wilson-client SG audit: eat_pre queues eat on the server and
-- eat_lag during client prediction; quickeat similarly queues quick_eat[_lag]
-- or quick_drink[_lag]. Client prediction may flatten into idle/noanim before
-- replicated eating ends, and server busy is removed before the animation ends.
-- Consequently the actual animation, not SG busy/state/time, is authoritative.
FRAMES = 1 / 30
local dedicated = false
TheNet = { IsDedicated = function() return dedicated end }
TheWorld = { ismastersim = true }
package.preload["krypton_eating_visual_data"] = function()
    return load_source("mod/scripts/krypton_eating_visual_data.lua")
end
local Visual = load_source("mod/scripts/krypton_eating_visual.lua")
local build = "krypton_eating_build"
local symbols = { open = "krypton_eat_open", chew = "krypton_eat_chew", satisfied = "krypton_eat_satisfied" }
local function forbidden(name)
    return function() error("Eating expressions must preserve native " .. name) end
end

local function player()
    local inst = { GUID = 1, valid = true, tags = {}, events = {}, tasks = {},
        components = {}, replica = {}, frame = 0, animation = "idle_loop", overrides = {}, writes = 0 }
    inst.IsValid = function(self) return self.valid end
    inst.IsAsleep = function(self) return self.asleep == true end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.ListenForEvent = function(self, event, fn)
        self.events[event] = self.events[event] or {}
        table.insert(self.events[event], fn)
    end
    inst.DoPeriodicTask = function(self, period, fn)
        local task = { period = period, fn = fn, Cancel = function(t) t.cancelled = true end }
        table.insert(self.tasks, task)
        return task
    end
    inst.DoTaskInTime = function(self, delay, fn)
        local task = { delay = delay, fn = fn, Cancel = function(t) t.cancelled = true end }
        table.insert(self.tasks, task)
        return task
    end
    inst.components.health = { IsDead = function() return inst.dead == true end }
    inst.components.rider = { IsRiding = function() return inst.riding == true end }
    inst.replica.health = inst.components.health
    inst.replica.rider = inst.components.rider
    inst.AnimState = {
        IsCurrentAnimation = function(self, animation) return inst.animation == animation end,
        GetCurrentAnimationFrame = function() return math.floor(inst.frame) end,
        GetCurrentAnimationTime = function() return inst.frame / 30 end,
        GetCurrentAnimationLength = function() return 98 / 30 end,
        GetBuild = function() return inst.build or "krypton_survivor" end,
        GetSkinBuild = function() return inst.skinbuild or "" end,
        IsSkinBuild = function(self, source) return source == "genuine_skin" end,
        GetSymbolOverride = function(self, symbol)
            local value = inst.overrides[symbol]
            if value ~= nil then return value[1], value[2] end
        end,
        OverrideSymbol = function(self, symbol, source, source_symbol)
            assert(symbol == "headbase" or symbol == "headbase_hat", "Only the head may be replaced")
            inst.overrides[symbol] = { source, source_symbol }
            inst.writes = inst.writes + 1
        end,
        OverrideSkinSymbol = function(self, symbol, source, source_symbol)
            assert(symbol == "headbase" or symbol == "headbase_hat", "Only the previous head skin may be restored")
            inst.overrides[symbol] = { source, source_symbol }
            inst.skin_restores = (inst.skin_restores or 0) + 1
            inst.writes = inst.writes + 1
        end,
        ClearOverrideSymbol = function(self, symbol)
            assert(symbol == "headbase" or symbol == "headbase_hat", "Only owned head overrides may be cleared")
            inst.overrides[symbol] = nil
            inst.writes = inst.writes + 1
        end,
        SetBank = forbidden("animation bank"), SetBuild = forbidden("character build"),
        AddOverrideBuild = forbidden("shared build selection"),
        PlayAnimation = forbidden("body animation"), PushAnimation = forbidden("animation queue"),
        SetTime = forbidden("animation timing"), SetFrame = forbidden("animation frame"),
        Show = forbidden("symbol visibility"), Hide = forbidden("symbol visibility"),
    }
    inst.SoundEmitter = { PlaySound = forbidden("eating audio"), KillSound = forbidden("eating audio") }
    inst.PerformBufferedAction = forbidden("food consumption")
    inst.PerformPreviewBufferedAction = forbidden("predicted food consumption")
    inst.ClearBufferedAction = forbidden("buffered action")
    return inst
end
local function event(inst, name)
    for _, fn in ipairs(inst.events[name] or {}) do fn(inst) end
end
local function pose(inst, expected, message)
    for _, target in ipairs({ "headbase", "headbase_hat" }) do
        local value = inst.overrides[target]
        if expected == nil then
            equal(value, nil, message or (target .. " should use the normal character head"))
        else
            assert(value ~= nil, message or (target .. " missing eating expression"))
            equal(value[1], build, message)
            equal(value[2], symbols[expected], message)
        end
    end
end
local function step(inst, animation, frame, expected)
    inst.animation, inst.frame = animation, frame
    Visual.Apply(inst)
    pose(inst, expected, animation .. " at frame " .. tostring(frame))
end

local inst = player()
Visual.CommonInit(inst)
pose(inst, nil)
step(inst, "eat_pre", 0, "open")
step(inst, "eat", 0, "open")
step(inst, "eat", 11, "open")
step(inst, "eat", 11.9999, "open")
step(inst, "eat", 12, "chew")
step(inst, "eat", 12.0001, "chew")
step(inst, "eat", 17, "chew")
step(inst, "eat", 18, "open")
step(inst, "eat", 24, "chew")
step(inst, "eat", 30, "open")
step(inst, "eat", 60, "chew")
step(inst, "eat", 65, "chew")
step(inst, "eat", 66, "satisfied")
step(inst, "eat", 76, "satisfied")
step(inst, "eat", 77, "open")
step(inst, "eat", 83, "chew")
step(inst, "eat", 87, "satisfied")
step(inst, "eat", 97, "satisfied")
step(inst, "idle_loop", 0, nil)
step(inst, "quick_eat_pre", 5, nil)
step(inst, "quick_eat_pre", 6, "open")
step(inst, "quick_eat", 0, "open")
step(inst, "quick_eat", 3, "open")
step(inst, "quick_eat", 4, "chew")
step(inst, "quick_eat", 8, "chew")
step(inst, "quick_eat", 9, "satisfied")
step(inst, "quick_eat", 11, "satisfied")
step(inst, "idle_loop", 0, nil)
step(inst, "quick_drink_pre", 2, nil)
step(inst, "quick_drink_pre", 3, "open")
step(inst, "quick_drink", 12, "open")
step(inst, "quick_drink", 13, "satisfied")

-- Prediction lag is an open mouth, never a fake swallow before the server
-- confirms consumption. Remote observers have no SG/components at all.
TheWorld.ismastersim = false
local observer = player()
observer.components, observer.sg = {}, nil
Visual.CommonInit(observer)
step(observer, "eat_lag", 0, "open")
step(observer, "eat_lag", 90, "open")
step(observer, "quick_eat_lag", 90, "open")
step(observer, "quick_drink_lag", 90, "open")
observer.sg = { currentstate = { name = "idle" }, HasStateTag = function() return false end }
step(observer, "eat", 24, "chew")
step(observer, "quick_eat", 9, "satisfied")
-- Server symbol replication and local animation polling can arrive separately.
-- A newly replicated expression from our own build is still ours to animate.
step(observer, "eat", 0, "open")
observer.overrides.headbase = { build, symbols.chew }
observer.overrides.headbase_hat = { build, symbols.chew }
step(observer, "eat", 24, "chew")
step(observer, "eat", 66, "satisfied")
observer.sg.currentstate.name = "quickeat"
step(observer, "idle_loop", 0, nil)

-- Every interrupt/ordinary action relinquishes the expression on its first
-- visible frame, irrespective of the native animation queue or SG state tags.
for _, animation in ipairs({ "idle_loop", "run_pre", "run_loop", "attack", "hit", "chop_pre",
    "mine", "dig", "heavy_eat", "heavy_quick_eat", "refuseeat", "death", "ghost_idle",
    "krypton_flight_idle", "krypton_flight_move" }) do
    step(inst, "eat", 24, "chew")
    step(inst, animation, 0, nil)
end

-- Capture actual previous overrides, not an assumed default head, and do not
-- restore the temporary chew expression after cycling through several poses.
local layered = player()
layered.overrides.headbase = { "other_skin", "other_head" }
layered.overrides.headbase_hat = { "other_hat_skin", "other_hat_head" }
Visual.CommonInit(layered)
step(layered, "eat", 0, "open")
step(layered, "eat", 24, "chew")
step(layered, "eat", 66, "satisfied")
layered.animation = "idle_loop"
Visual.Apply(layered)
equal(layered.overrides.headbase[1], "other_skin", "Restore pre-meal skin build")
equal(layered.overrides.headbase[2], "other_head", "Restore pre-meal head symbol")
equal(layered.overrides.headbase_hat[1], "other_hat_skin", "Restore pre-meal hat head independently")
step(layered, "eat", 24, "chew")
layered.overrides.headbase = { "new_external_skin", "new_external_head" }
Visual.Clear(layered)
equal(layered.overrides.headbase[1], "new_external_skin", "Cleanup must not overwrite an external mid-meal skin change")
equal(layered.overrides.headbase_hat[1], "other_hat_skin", "Still restore the head that remains owned")

local external = player()
Visual.CommonInit(external)
step(external, "eat", 0, "open")
external.overrides.headbase = { "external_midmeal", "external_face" }
external.frame = 24
Visual.Apply(external)
equal(external.overrides.headbase[1], "external_midmeal", "Polling must honor another mod's new head")
equal(external.overrides.headbase_hat, nil, "Release the remaining owned head after an external replacement")
external.frame = 66
Visual.Apply(external)
equal(external.overrides.headbase[1], "external_midmeal", "Do not retake the head later in the same meal")
external.animation = "idle_loop"
Visual.Apply(external)
step(external, "quick_eat", 4, "chew")
external.animation = "idle_loop"
Visual.Apply(external)
equal(external.overrides.headbase[1], "external_midmeal", "A new meal restores the newly chosen head")

local changed = player()
changed.overrides.headbase = { "old_outfit", "old_face" }
Visual.CommonInit(changed)
step(changed, "eat", 24, "chew")
changed.build, changed.skinbuild, changed.skinname = "new_character_build", "new_skin_build", "new_skin"
Visual.Apply(changed)
pose(changed, nil, "Changing the base skin must discard the old outfit's captured head")
Visual.Apply(changed)
pose(changed, nil, "Skin changes block the remaining meal instead of reapplying the old head")

local skinned = player()
skinned.overrides.headbase = { "genuine_skin", "skin_head" }
Visual.CommonInit(skinned)
step(skinned, "eat", 24, "chew")
skinned.animation = "idle_loop"
Visual.Apply(skinned)
equal(skinned.skin_restores, 1, "A prior skin override must restore through the native skin API")
equal(skinned.overrides.headbase[1], "genuine_skin")

-- A client can first observe a player after the host already applied a meal
-- symbol; that temporary symbol must never become the restored idle head.
local late = player()
late.overrides.headbase = { build, symbols.chew }
late.overrides.headbase_hat = { build, symbols.chew }
Visual.CommonInit(late)
step(late, "eat", 24, "chew")
step(late, "idle_loop", 0, nil)

-- A dead/ghost/mounted player can retain a replicated eating frame briefly;
-- lifecycle flags must still clear it, including replicas without a server SG.
for _, condition in ipairs({ "dead", "riding", "playerghost" }) do
    local actor = player()
    Visual.CommonInit(actor)
    step(actor, "eat", 24, "chew")
    if condition == "playerghost" then actor.tags.playerghost = true else actor[condition] = true end
    Visual.Apply(actor)
    pose(actor, nil, condition .. " must clear eating expression")
end
for _, name in ipairs({ "death", "ms_becameghost", "onremove" }) do
    local actor = player()
    Visual.CommonInit(actor)
    step(actor, "eat", 24, "chew")
    event(actor, name)
    pose(actor, nil, name .. " must immediately release the expression")
    if name == "onremove" then
        equal(actor.tasks[1].cancelled, true, "Removed players must cancel their per-frame visual task")
    end
end

local loading = player()
local loaded_data, loaded_argument
loading.OnLoad = function(self, data, argument)
    loaded_data, loaded_argument = data, argument
    return "native_load_result", argument
end
Visual.CommonInit(loading)
step(loading, "eat", 24, "chew")
local save = { preserved = true }
local result, result_argument = loading:OnLoad(save, "extra")
equal(loaded_data, save, "Preserve the existing character load hook")
equal(loaded_argument, "extra", "Forward additional load arguments")
equal(result, "native_load_result", "Preserve native load return values")
equal(result_argument, "extra")
pose(loading, nil, "Loading must release old temporary head overrides")
Visual.Apply(loading)
pose(loading, nil, "Loading cannot resurrect an interrupted meal expression")
step(loading, "idle_loop", 0, nil)
step(loading, "quick_eat", 4, "chew")

local sleeping = player()
Visual.CommonInit(sleeping)
step(sleeping, "eat", 24, "chew")
sleeping.asleep = true
event(sleeping, "entitysleep")
pose(sleeping, nil, "Sleeping entities must release temporary overrides")
Visual.Apply(sleeping)
pose(sleeping, nil)
sleeping.asleep, sleeping.frame = false, 66
event(sleeping, "entitywake")
pose(sleeping, "satisfied", "A waking observer uses the replicated current animation phase")

-- An idle entity never needs a renderer mutation, and dedicated servers must
-- not start a graphical per-frame updater (all clients read native animation).
local idle = player()
Visual.CommonInit(idle)
Visual.Apply(idle)
local writes = idle.writes
for _ = 1, 20 do Visual.Apply(idle) end
equal(idle.writes, writes, "Idle polling should not modify symbols")
dedicated = true
local server = player()
Visual.CommonInit(server)
equal(#server.tasks, 0, "Dedicated server must not run a visual update task")
equal(server.writes, 0, "Dedicated initialization must not touch symbols")
print("Eating tests passed: native food/body preservation, normal/quick/drink timing, prediction and remote observers, interrupts, lifecycle cleanup and previous/external skin overrides.")
