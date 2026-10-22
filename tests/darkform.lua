local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < .000001,
        (message or "unexpected percentage") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
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
TUNING = { KRYPTON_SURVIVOR = { darkform_sanity_percent = .05, darkform_toggle_interval = .35 } }
TheWorld = { ismastersim = true }
local now, paused, tasks = 0, false, {}
GetTime = function() return now end
TheNet = { IsServerPaused = function() return paused end }
net_bool = function(_, name, event)
    assert(name == "krypton_survivor.dark_form" and event == "krypton_darkformdirty")
    return { state = false, writes = 0,
        value = function(self) return self.state end,
        set = function(self, value) assert(type(value) == "boolean"); self.state = value; self.writes = self.writes + 1 end }
end
local function schedule(inst, delay, fn, period)
    local task = { at = now + delay, fn = function() fn(inst) end, period = period }
    task.Cancel = function(self) self.cancelled = true end
    tasks[#tasks + 1] = task
    return task
end
local function advance(seconds)
    if paused then return end
    local finish, iterations = now + seconds, 0
    while true do
        local next_task
        for _, task in ipairs(tasks) do
            if not task.cancelled and not task.done and task.at <= finish
                and (next_task == nil or task.at < next_task.at) then next_task = task end
        end
        if next_task == nil then break end
        iterations = iterations + 1
        assert(iterations < 1000, "recursive sanity events must not produce an endless deferred loop")
        now = next_task.at
        next_task.done = true
        next_task.fn()
        if next_task.period ~= nil and not next_task.cancelled then
            next_task.done = false
            next_task.at = now + next_task.period
        end
    end
    now = finish
end
local Form = load_source("mod/scripts/krypton_darkform.lua")
local Core = load_source("mod/scripts/components/krypton_darkform.lua")

local function player(options)
    options = options or {}
    local inst = { GUID = 1, prefab = "krypton_survivor", tags = { kryptonian = true },
        valid = true, components = {}, events = {}, event_count = {}, }
    inst.IsValid = function(self) return self.valid end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.DoTaskInTime = function(self, delay, fn) return schedule(self, delay, fn) end
    inst.DoPeriodicTask = function(self, period, fn) return schedule(self, period, fn, period) end
    inst.ListenForEvent = function(self, event, fn)
        self.events[event] = self.events[event] or {}
        self.events[event][fn] = true
    end
    inst.RemoveEventCallback = function(self, event, fn)
        if self.events[event] ~= nil then self.events[event][fn] = nil end
    end
    inst.PushEvent = function(self, event, data)
        self.event_count[event] = (self.event_count[event] or 0) + 1
        local callbacks = {}
        for fn in pairs(self.events[event] or {}) do callbacks[#callbacks + 1] = fn end
        for _, fn in ipairs(callbacks) do fn(self, data) end
    end
    inst.components.health = { dead = false, IsDead = function(self) return self.dead end }
    inst.components.rider = { riding = false, IsRiding = function(self) return self.riding end }
    inst.components.playercontroller = { enabled = true,
        IsEnabled = function(self) return self.enabled end,
        IsBusy = function(self) return self.busy == true end,
        IsDoingOrWorking = function(self) return self.working == true end }
    inst.sg = { tags = {}, HasAnyStateTag = function(self, ...)
        for _, tag in ipairs({ ... }) do if self.tags[tag] then return true end end
        return false
    end }
    -- Independent native public contracts: SetPercent delegates through
    -- DoDelta, penalties clamp the stored value, induced effects only alter
    -- GetPercent, and lunacy changes the insanity interpretation.
    inst.components.sanity = { max = options.max or 10000,
        current = (options.percent or .83) * (options.max or 10000), penalty = 0, writes = 0,
        GetRealPercent = function(self) return self.current / self.max end,
        GetPercent = function(self)
            if self.inducedinsanity then return 0 end
            if self.inducedlunacy then return 1 - self.penalty end
            return self:GetRealPercent()
        end,
        GetPenaltyPercent = function(self) return self.penalty end,
        IsInsane = function(self) return not self.lunacy and self:GetRealPercent() <= .15 end,
        SetPercent = function(self, percent, overtime) self:DoDelta(percent * self.max - self.current, overtime) end,
        DoDelta = function(self, delta, overtime)
            if self.redirect ~= nil then self.redirect(delta, overtime); return end
            if self.ignore then return end
            self.current = math.min(math.max(self.current + delta, 0), self.max * (1 - self.penalty))
            self.writes = self.writes + 1
            inst:PushEvent("sanitydelta", { newpercent = self:GetPercent(), overtime = overtime })
        end }
    Form.CommonInit(inst)
    inst.components.krypton_darkform = Core(inst)
    return inst, inst.components.krypton_darkform, inst.components.sanity
end

assert(Form.DIRTY_EVENT == "krypton_darkformdirty")
assert(not Form.IsDark(nil) and not Form.IsDark({}))
local p, core, sanity = player()
assert(not core:IsDark() and not Form.IsDark(p) and core:OnSave() == nil)
local success, reason = Form.Toggle(p)
assert(success and reason == "dark_on" and core:IsDark() and Form.IsDark(p))
close(sanity.current, 500, "5% is relative to the character's maximum, not 5 raw points")
assert(sanity:IsInsane(), "Native low sanity, without induced-insanity or mode overrides")
close(core:GetNormalSanityPercent(), .83)
assert(p.event_count[Form.DIRTY_EVENT] == 1, "Hosts receive an immediate authoritative update")
success, reason = Form.Toggle(p)
assert(not success and reason == "cooldown" and core:IsDark())
advance(.35)
success, reason = Form.Toggle(p)
assert(success and reason == "dark_off" and not core:IsDark() and not Form.IsDark(p))
close(sanity:GetRealPercent(), .83, "Leaving restores the real pre-form percentage")
local writes = sanity.writes
advance(3)
assert(sanity.writes == writes, "No maintenance writes in normal form")

advance(.35)
assert(Form.Toggle(p))
sanity:DoDelta(4000)
assert(sanity.current > 500)
advance(0)
close(sanity.current, 500, "Eating and killing shadow creatures cannot leave sanity high")
writes = sanity.writes
advance(0)
assert(sanity.writes == writes, "Native sanitydelta from our correction does not recurse")
sanity:DoDelta(-2000)
advance(0)
close(sanity.current, 500, "Negative food effects also return to the low target")
sanity.max = 2000
advance(1)
close(sanity.current, 100, "Changing maximum sanity preserves the target percentage")
sanity.penalty = .98
sanity:DoDelta(0)
advance(0)
close(sanity.current, 40, "The effective maximum bounds maintenance")
advance(.35)
assert(Form.Toggle(p))
close(sanity.current, 40, "Restoration goes through native penalty limits")
sanity.penalty = 0
sanity:DoDelta(100)
advance(1)
close(sanity.current, 140, "Normal-form food effects are no longer corrected")

-- External induced effects and lunacy remain owned by native code/other mods.
local induced, induced_core, induced_sanity = player({ percent = .64 })
induced_sanity.inducedinsanity = true
assert(Form.Toggle(induced))
close(induced_core:GetNormalSanityPercent(), .64, "Snapshot uses GetRealPercent, not forced GetPercent")
assert(induced_sanity.inducedinsanity == true and induced_sanity:GetPercent() == 0)
advance(.35)
assert(Form.Toggle(induced))
close(induced_sanity:GetRealPercent(), .64)
assert(induced_sanity.inducedinsanity == true, "Never clear another effect's insanity source")
induced_sanity.inducedinsanity, induced_sanity.inducedlunacy = nil, true
advance(.35)
assert(Form.Toggle(induced))
close(induced_core:GetNormalSanityPercent(), .64)
induced_sanity.lunacy = true
advance(1)
assert(not induced_sanity:IsInsane(), "Moon-island lunacy retains the native interpretation")
assert(induced_sanity.inducedlunacy and induced_sanity.lunacy)

local ignored, ignored_core, ignored_sanity = player()
ignored_sanity.ignore = true
assert(Form.Toggle(ignored))
close(ignored_sanity:GetRealPercent(), .83, "Native ignore behavior is respected")
ignored_sanity.ignore = false
advance(1)
close(ignored_sanity:GetRealPercent(), .05)
ignored_sanity.redirect = function(delta) ignored.redirected = delta end
ignored_sanity.current = 5000
advance(1)
assert(ignored.redirected < 0)
close(ignored_sanity.current, 5000, "Native redirect is not bypassed with direct field writes")
ignored_sanity.redirect = nil
advance(1)
close(ignored_sanity.current, 500)

-- Dark state migrates with the character; deferred enforcement follows all
-- native component loads and never treats a load as a fresh entry snapshot.
local saved, saved_core, saved_sanity = player({ percent = .91 })
assert(Form.Toggle(saved))
local data = saved_core:OnSave()
assert(data.dark and data.normal_percent == .91)
local loaded, loaded_core, loaded_sanity = player({ percent = .4 })
loaded_core:OnLoad(data)
loaded_sanity.current = 7200 -- a later native sanity OnLoad
advance(0)
assert(loaded_core:IsDark() and Form.IsDark(loaded))
close(loaded_sanity.current, 500)
close(loaded_core:GetNormalSanityPercent(), .91)
assert(Form.Toggle(loaded))
close(loaded_sanity.current, 9100)
local old, old_core, old_sanity = player({ percent = .46 })
old_core:OnLoad(nil)
advance(0)
assert(not old_core:IsDark() and not Form.IsDark(old))
close(old_sanity:GetRealPercent(), .46, "Old saves remain normal without a sanity reset")
local corrupt, corrupt_core, corrupt_sanity = player()
corrupt_core:OnLoad({ dark = true, normal_percent = 0/0 })
advance(0)
assert(Form.Toggle(corrupt))
close(corrupt_sanity:GetRealPercent(), 1, "Invalid saved values have a finite fallback")

-- Death, ghost/corpse loading, and native revival cannot mutate ghost sanity.
local revived, revived_core, revived_sanity = player()
assert(Form.Toggle(revived))
revived_sanity:DoDelta(1000)
revived.components.health.dead = true
revived:PushEvent("death")
writes = revived_sanity.writes
advance(2)
assert(revived_sanity.writes == writes and revived_core:IsDark())
revived.tags.playerghost = true
revived:PushEvent("ms_becameghost")
revived_sanity.current = 8000
advance(1)
assert(revived_sanity.current == 8000)
revived.components.health.dead = false
revived:PushEvent("ms_respawnedfromghost")
revived.tags.playerghost = nil -- native tag removal can finish after the event
advance(0)
close(revived_sanity.current, 500)
revived.tags.corpse = true
revived_core:OnLoad(data)
advance(0)
revived_sanity.current = 7000
advance(1)
assert(revived_sanity.current == 7000)
revived.tags.corpse = nil
revived:PushEvent("respawnfromcorpse")
advance(0)
close(revived_sanity.current, 500)

-- Server authority and safety checks preserve flight/riding, but refuse any
-- unsafe state or RPC that cannot belong to a living Superman.
local safe = player()
safe.components.rider.riding = true
safe.tags.flying = true
assert(Form.CanToggle(safe), "A mode change needs no dismount or landing")
local function rejected(change, undo, expected)
    change()
    local accepted, why = Form.Toggle(safe)
    assert(not accepted and why == expected, "Expected rejection " .. expected .. ", got " .. tostring(why))
    undo()
end
rejected(function() TheWorld.ismastersim = false end, function() TheWorld.ismastersim = true end, "unavailable")
rejected(function() safe.valid = false end, function() safe.valid = true end, "unavailable")
rejected(function() safe.prefab = "wilson" end, function() safe.prefab = "krypton_survivor" end, "unavailable")
rejected(function() safe.tags.kryptonian = nil end, function() safe.tags.kryptonian = true end, "unavailable")
for _, tag in ipairs({ "playerghost", "corpse" }) do
    rejected(function() safe.tags[tag] = true end, function() safe.tags[tag] = nil end, "unavailable")
end
rejected(function() safe.components.health.dead = true end, function() safe.components.health.dead = false end, "unavailable")
rejected(function() paused = true end, function() paused = false end, "paused")
rejected(function() safe.components.playercontroller.enabled = false end, function() safe.components.playercontroller.enabled = true end, "controls_disabled")
rejected(function() safe.tags.busy = true end, function() safe.tags.busy = nil end, "busy")
rejected(function() safe.components.playercontroller.busy = true end, function() safe.components.playercontroller.busy = nil end, "busy")
rejected(function() safe.components.playercontroller.working = true end, function() safe.components.playercontroller.working = nil end, "busy")
rejected(function() safe.components.playercontroller.placer = {} end, function() safe.components.playercontroller.placer = nil end, "busy")
for _, tag in ipairs({ "busy", "jumping", "nointerrupt" }) do
    rejected(function() safe.sg.tags[tag] = true end, function() safe.sg.tags[tag] = nil end, "busy")
end
local accepted = Form.Toggle(nil)
assert(not accepted)
local real_time = now
paused = true
advance(100)
assert(now == real_time, "Simulation time, including maintenance, stops while paused")
paused = false

-- Switching out cancels an already queued correction; removal never leaves
-- background tasks or event listeners operating on a discarded component.
local removed, removed_core, removed_sanity = player()
assert(Form.Toggle(removed))
removed_sanity:DoDelta(3000)
advance(.35)
removed_sanity:DoDelta(2000)
assert(Form.Toggle(removed))
advance(0)
close(removed_sanity:GetRealPercent(), .83)
advance(.35)
assert(Form.Toggle(removed))
removed_sanity:DoDelta(3000)
removed_core:OnRemoveFromEntity()
writes = removed_sanity.writes
advance(10)
assert(removed_sanity.writes == writes and not removed_core:IsDark() and not Form.IsDark(removed))
removed:PushEvent("sanitydelta")
removed:PushEvent("ms_respawnedfromghost")
advance(0)
assert(removed_sanity.writes == writes and next(removed.events.sanitydelta) == nil)
assert(not removed_core:SetDark(true))
removed_core:OnRemoveFromEntity()

print("Dark form: low sanity, restoration, native effects, save/load, revival, authority and task cleanup passed.")
