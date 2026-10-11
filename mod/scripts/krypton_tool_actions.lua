local ToolActions = {}

-- SPACE uses PlayerController's private pickup selection, which checks tools
-- before harvesting. Keep the native eligibility checks and RPC regeneration;
-- only reinterpret this character's axe when it would uproot a living plant.
local PICKUP_EXCLUDE_TAGS = {
    "catchable", "mineactive", "intense", "paired",
    "FX", "NOCLICK", "DECOR", "INLIMBO", "stealth",
}
local PICKUP_TAGS = {
    "_inventoryitem", "pickable", "donecooking", "readyforharvest",
    "notreadyforharvest", "harvestable", "trapsprung", "minesprung",
    "dried", "inactive", "smolder", "saddled", "brushable",
    "tapped_harvestable", "tendable_farmplant", "inventoryitemholder_take",
    "client_forward_action_target",
}

local function GetAxe(inst)
    local inventory = inst.replica ~= nil and inst.replica.inventory or nil
    local tool = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or nil
    return inst.prefab == "krypton_survivor" and tool ~= nil
        and tool.prefab == "krypton_staff" and tool:HasTag("DIG_tool") and tool or nil
end

local function IsLivingPlant(target)
    -- The ready-to-pick tag disappears after harvesting; "plant" persists on
    -- berry bushes, grass and saplings on both clients and the server.
    return target ~= nil and target:HasTag("plant")
        and not target:HasTag("stump") and not target:HasTag("burnt")
end

local function HarvestInstead(inst, action, tool)
    if action ~= nil and action.action == ACTIONS.DIG and IsLivingPlant(action.target) then
        local target = action.target
        if target:HasTag("pickable") and not target:HasTag("fire") then
            return BufferedAction(inst, target, ACTIONS.PICK, tool), true
        end
        return nil, true
    end
    return action, false
end

local function FindNextAction(controller, original, tool)
    local tags = {}
    for _, tag in ipairs(PICKUP_TAGS) do
        tags[#tags + 1] = tag
    end
    if tool:HasTag("MINE_tool") then
        tags[#tags + 1] = "LunarBuildup"
    end
    for name in pairs(TOOLACTIONS) do
        if tool:HasTag(name .. "_tool") then
            tags[#tags + 1] = name .. "_workable"
        end
    end
    if controller.inst.components.revivablecorpse ~= nil then
        tags[#tags + 1] = "corpse"
    end

    local x, y, z = controller.inst.Transform:GetWorldPosition()
    local nearby = TheSim:FindEntities(x, y, z, controller.directwalking and 3 or 6,
        nil, PICKUP_EXCLUDE_TAGS, tags)
    for _, candidate in ipairs(nearby) do
        candidate = candidate.client_forward_target or candidate
        if candidate ~= controller.inst and candidate.entity:IsVisible()
            and CanEntitySeeTarget(controller.inst, candidate) then
            -- Do not manufacture actions for raw nearby entities: the native
            -- method rechecks distance, visibility, busy state and inventory.
            local action = HarvestInstead(controller.inst, original(controller, candidate), tool)
            if action ~= nil then
                return action
            end
        end
    end
end

local function Attach(inst)
    local controller = inst.components.playercontroller
    if controller ~= nil and not controller._krypton_tool_actions then
        controller._krypton_tool_actions = true
        local original = controller.GetActionButtonAction
        controller.GetActionButtonAction = function(self, force_target, ...)
            local action = original(self, force_target, ...)
            local tool = GetAxe(self.inst)
            if tool == nil then
                return action
            end
            local replacement, protected = HarvestInstead(self.inst, action, tool)
            if not protected or replacement ~= nil or force_target ~= nil then
                return replacement
            end
            -- Holding SPACE after picking must skip the now-empty plant and
            -- continue to the next native candidate instead of digging it up.
            return FindNextAction(self, original, tool)
        end
    end

    local picker = inst.components.playeractionpicker
    if picker ~= nil and not picker._krypton_tool_actions then
        picker._krypton_tool_actions = true
        local original = picker.GetEquippedItemActions
        picker.GetEquippedItemActions = function(self, target, useitem, right, ...)
            local actions = original(self, target, useitem, right, ...)
            if not right and useitem == GetAxe(self.inst) and IsLivingPlant(target) then
                -- Native left-click then falls back to scene PICK actions.
                -- Explicit right-click (and controller alternate action) keeps DIG.
                for i = #actions, 1, -1 do
                    if actions[i].action == ACTIONS.DIG then
                        table.remove(actions, i)
                    end
                end
            end
            return actions
        end
    end
end

function ToolActions.CommonInit(inst)
    if inst._krypton_tool_actions_registered then
        return
    end
    inst._krypton_tool_actions_registered = true
    Attach(inst)
    -- Player components can be attached after common_postinit on a client.
    inst:DoTaskInTime(0, Attach)
    inst:ListenForEvent("playeractivated", Attach)
end

return ToolActions
