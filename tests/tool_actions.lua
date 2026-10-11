local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

EQUIPSLOTS = { HANDS = "hands" }
CONTROL_ACTION = 1
ACTIONS = {}
for index, name in ipairs({ "PICK", "PICKUP", "DIG", "CHOP", "MINE", "HAMMER", "SMOTHER", "HAUNT", "LOOKAT" }) do
    ACTIONS[name] = { id = name, code = index, priority = 0, rmb = name == "HAMMER" }
end
TOOLACTIONS = { CHOP = true, MINE = true, HAMMER = true, DIG = true }
BufferedAction = function(inst, target, action, tool)
    return { doer = inst, target = target, action = action, invobject = tool }
end
CanEntitySeeTarget = function(inst, target) return not target.unseen end

local nearby
TheSim = { FindEntities = function(self, x, y, z, radius, must, excluded, any)
    local result = {}
    for _, target in ipairs(nearby) do
        local include = target.distance <= radius
        for _, tag in ipairs(excluded or {}) do
            if target:HasTag(tag) then include = false end
        end
        if any ~= nil then
            local matches = false
            for _, tag in ipairs(any) do
                if target:HasTag(tag) then matches = true end
            end
            include = include and matches
        end
        if include then result[#result + 1] = target end
    end
    return result
end }

local function entity(prefab, tags, distance)
    local inst = { prefab = prefab, tags = {}, replica = {}, components = {}, distance = distance or 1 }
    for _, tag in ipairs(tags or {}) do inst.tags[tag] = true end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.IsValid = function(self) return not self.removed end
    inst.entity = { IsVisible = function() return not inst.invisible end }
    return inst
end
local function axe(prefab)
    return entity(prefab or "krypton_staff", { "CHOP_tool", "MINE_tool", "HAMMER_tool", "DIG_tool" })
end
local function plant(ready)
    return entity("berrybush", ready and { "plant", "renewable", "DIG_workable", "pickable" }
        or { "plant", "renewable", "DIG_workable" })
end

-- Small behavioral fixture for the installed native controller. It deliberately
-- models the pre-existing work-before-PICK decision, nearby iteration, targeted
-- server regeneration, and eligibility guards rather than the new filter.
local function native_pickup(inst, target, tool)
    if target:HasTag("smolder") then return ACTIONS.SMOTHER end
    for name in pairs(TOOLACTIONS) do
        if target:HasTag(name .. "_workable") and tool ~= nil and tool:HasTag(name .. "_tool") then
            return ACTIONS[name]
        end
    end
    if target:HasTag("_inventoryitem") then return ACTIONS.PICKUP end
    if target:HasTag("pickable") and not target:HasTag("fire") then return ACTIONS.PICK end
end
local function native_action_button(self, target)
    self.native_calls = self.native_calls + 1
    if self.busy or not self.enabled or self.remote_cooldown then return end
    if target ~= nil and (not target.entity:IsVisible() or target:HasTag("INLIMBO") or target:HasTag("NOCLICK")) then return end
    if self.override ~= nil then return self.override end
    if self.inst:HasTag("playerghost") then
        return target ~= nil and BufferedAction(self.inst, target, ACTIONS.HAUNT) or nil
    end
    if self.doing or self.heavy or self.floater then return end
    local tool = self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if target ~= nil then
        if target.distance > (self.directwalking and 3 or 6) then return end
        local action = native_pickup(self.inst, target, tool)
        return action ~= nil and BufferedAction(self.inst, target, action, tool) or nil
    end
    local candidates = TheSim:FindEntities(0, 0, 0, self.directwalking and 3 or 6, nil,
        { "FX", "NOCLICK", "DECOR", "INLIMBO", "stealth", "catchable", "mineactive", "intense", "paired" })
    for _, candidate in ipairs(candidates) do
        candidate = candidate.client_forward_target or candidate
        if candidate ~= self.inst and candidate.entity:IsVisible() and CanEntitySeeTarget(self.inst, candidate) then
            local action = native_pickup(self.inst, candidate, tool)
            if action ~= nil then return BufferedAction(self.inst, candidate, action, tool) end
        end
    end
end
local function player(prefab)
    local inst = entity(prefab or "krypton_survivor")
    inst.tasks, inst.events = {}, {}
    inst.Transform = { GetWorldPosition = function() return 0, 0, 0 end }
    inst.replica.inventory = { GetEquippedItem = function() return inst.tool end }
    inst.components.playercontroller = { inst = inst, native_calls = 0, enabled = true,
        GetActionButtonAction = native_action_button }
    local picker = { inst = inst }
    picker.GetEquippedItemActions = function(self, target, tool, right)
        local action = target:HasTag("DIG_workable") and tool:HasTag("DIG_tool") and ACTIONS.DIG
            or native_pickup(self.inst, target, tool)
        return action ~= nil and { BufferedAction(inst, target, action, tool) } or {}
    end
    picker.GetSceneActions = function(self, target)
        if target:HasTag("pickable") and not target:HasTag("fire") then
            return { BufferedAction(inst, target, ACTIONS.PICK) }
        end
        return {}
    end
    picker.GetLeftClickActions = function(self, target)
        local actions = self:GetEquippedItemActions(target, inst.tool)
        return #actions > 0 and actions or self:GetSceneActions(target)
    end
    picker.GetRightClickActions = function(self, target)
        return self:GetEquippedItemActions(target, inst.tool, true)
    end
    inst.components.playeractionpicker = picker
    inst.DoTaskInTime = function(self, delay, fn) self.tasks[#self.tasks + 1] = fn end
    inst.ListenForEvent = function(self, event, fn) self.events[event] = fn end
    inst.tool = axe()
    return inst
end

local ToolActions = load_source("mod/scripts/krypton_tool_actions.lua")
local inst = player()
local controller, picker = inst.components.playercontroller, inst.components.playeractionpicker
local ready, empty = plant(true), plant(false)
nearby = { ready }
equal(controller:GetActionButtonAction().action, ACTIONS.DIG, "native SPACE used tool work before harvest")
equal(picker:GetLeftClickActions(ready)[1].action, ACTIONS.DIG, "native left-click prioritizes equipped tools")
ToolActions.CommonInit(inst)
equal(controller:GetActionButtonAction().action, ACTIONS.PICK, "SPACE harvests ready bushes")
equal(picker:GetLeftClickActions(ready)[1].action, ACTIONS.PICK, "left-click falls back to native scene harvesting")
equal(picker:GetRightClickActions(ready)[1].action, ACTIONS.DIG, "explicit right-click still uproots")
equal(picker:GetRightClickActions(empty)[1].action, ACTIONS.DIG, "right-click also uproots empty plants")
equal(controller:GetActionButtonAction(ready).action, ACTIONS.PICK, "server targeted regeneration matches client PICK")
equal(controller:GetActionButtonAction(empty), nil, "targeted SPACE never uproots an empty plant")

-- Continuing to hold SPACE after the first harvest must move to the next bush.
ready.tags.pickable = nil
local second, third = plant(true), plant(true)
nearby = { ready, empty, second, third }
equal(controller:GetActionButtonAction().target, second, "empty nearer plants do not starve the search")
second.tags.pickable = nil
equal(controller:GetActionButtonAction().target, third, "repeated SPACE keeps harvesting")
third.tags.pickable = nil
equal(controller:GetActionButtonAction(), nil, "nothing is uprooted after the final harvest")
for _, target in ipairs(nearby) do equal(target:HasTag("DIG_workable"), true, "target tags stay intact") end
equal(inst.tool:HasTag("DIG_tool"), true, "tool tag remains available for right-click")

for _, prefab in ipairs({ "grass", "sapling", "berrybush", "berrybush_juicy" }) do
    local target = plant(true)
    target.prefab = prefab
    nearby = { target }
    equal(controller:GetActionButtonAction().action, ACTIONS.PICK, prefab .. " harvesting")
    target.tags.pickable = nil
    equal(controller:GetActionButtonAction(), nil, prefab .. " remains planted after harvesting")
end

for _, name in ipairs({ "CHOP", "MINE", "HAMMER", "DIG" }) do
    local target = entity(name == "DIG" and "evergreen" or "work_target", { name .. "_workable", "stump" })
    nearby = { empty, target }
    equal(controller:GetActionButtonAction().action, ACTIONS[name], name .. " stays available behind empty plants")
    equal(controller:GetActionButtonAction(target).action, ACTIONS[name], name .. " targeted regeneration")
end
nearby = { empty, entity("berries", { "_inventoryitem" }) }
equal(controller:GetActionButtonAction().action, ACTIONS.PICKUP, "loose items remain collectable")
local smoldering = plant(true)
smoldering.tags.smolder = true
nearby = { smoldering }
equal(controller:GetActionButtonAction().action, ACTIONS.SMOTHER, "fire prevention retains native priority")
local burnt = plant(false)
burnt.tags.burnt = true
equal(controller:GetActionButtonAction(burnt).action, ACTIONS.DIG, "burnt plants can still be cleared")

local hidden, unseen, limbo, noclick, far = plant(true), plant(true), plant(true), plant(true), plant(true)
hidden.invisible, unseen.unseen, limbo.tags.INLIMBO, noclick.tags.NOCLICK, far.distance = true, true, true, true, 8
nearby = { empty, hidden, unseen, limbo, noclick, far }
equal(controller:GetActionButtonAction(), nil, "fallback rejects hidden, unseen, limbo, NOCLICK and out-of-range candidates")
equal(controller:GetActionButtonAction(hidden), nil, "targeted native visibility guards remain")
equal(controller:GetActionButtonAction(limbo), nil, "targeted native limbo guards remain")
equal(controller:GetActionButtonAction(far), nil, "targeted native distance guards remain")
far.distance = 4
controller.directwalking = true
nearby = { empty, far }
equal(controller:GetActionButtonAction(), nil, "direct walking preserves its shorter native radius")
controller.directwalking = false
equal(controller:GetActionButtonAction().target, far, "normal radius can reach the same candidate")

for _, flag in ipairs({ "busy", "doing", "heavy", "floater", "remote_cooldown" }) do
    controller[flag] = true
    equal(controller:GetActionButtonAction(plant(true)), nil, flag .. " guard is respected")
    controller[flag] = false
end
controller.enabled = false
equal(controller:GetActionButtonAction(plant(true)), nil, "disabled controls remain blocked")
controller.enabled = true
inst.tags.playerghost = true
equal(controller:GetActionButtonAction(empty).action, ACTIONS.HAUNT, "ghost behavior is untouched")
inst.tags.playerghost = nil
controller.override = BufferedAction(inst, empty, ACTIONS.LOOKAT)
equal(controller:GetActionButtonAction(empty), controller.override, "existing custom override is preserved")
controller.override = nil

inst.tool = axe("shovel")
equal(controller:GetActionButtonAction(empty).action, ACTIONS.DIG, "other equipped tools retain native behavior")
inst.tool = axe()
inst.prefab = "wilson"
equal(controller:GetActionButtonAction(empty).action, ACTIONS.DIG, "other characters retain native behavior")
inst.prefab = "krypton_survivor"

local wrapped = controller.GetActionButtonAction
ToolActions.CommonInit(inst)
for _, task in ipairs(inst.tasks) do task(inst) end
inst.events.playeractivated(inst)
equal(controller.GetActionButtonAction, wrapped, "initialization and activation are idempotent")
local delayed = player()
local saved_controller, saved_picker = delayed.components.playercontroller, delayed.components.playeractionpicker
delayed.components.playercontroller, delayed.components.playeractionpicker = nil, nil
ToolActions.CommonInit(delayed)
delayed.components.playercontroller, delayed.components.playeractionpicker = saved_controller, saved_picker
delayed.tasks[1](delayed)
equal(saved_controller:GetActionButtonAction(plant(true)).action, ACTIONS.PICK, "late client component initialization works")
equal(ACTIONS.DIG.priority, 0, "global action priority stays unchanged")
equal(ACTIONS.DIG.rmb, false, "global right-click metadata stays unchanged")
print("Tool actions: native work-before-pick regression, harvest continuation, targeted server regeneration, explicit digging and normal work passed.")
