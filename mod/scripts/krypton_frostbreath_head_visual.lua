local Visual = {}
local DATA = require("krypton_frostbreath_head_data")
local BUILD = hash(DATA.build)
local HEADS = { "headbase", "headbase_hat" }
local LOOPS = { "idle_loop", "run_loop", "walk_loop", "run_pre", "run_pst", "walk_pre", "walk_pst",
    "idle_inaction", "idle_inaction_sanity", "idle_inaction_lunacy", "hungry",
    "idle_shiver_pre", "idle_shiver_loop", "idle_shiver_pst", "idle_hot_pre", "idle_hot_loop", "idle_hot_pst",
    "idle_groggy_pre", "idle_groggy", "idle_groggy01_pre", "idle_groggy01_loop", "idle_groggy01_pst" }
local INTERRUPTS = { "death", "ms_becameghost", "mounted", "isridingdirty",
    "ms_playerreroll", "equipskinneditem", "unequipskinneditem", "onremove" }

local function SkinChanged(inst, state)
    return inst.AnimState:GetBuild() ~= state.build
        or inst.AnimState:GetSkinBuild() ~= state.skinbuild or inst.skinname ~= state.skinname
end

local function IsOurHead(inst, target)
    return inst.AnimState:GetSymbolOverride(target) == BUILD
end

local function ReleaseHeads(inst, state)
    local changed = SkinChanged(inst, state)
    for _, target in ipairs(HEADS) do
        local previous = state.overrides ~= nil and state.overrides[target] or nil
        previous = previous or {}
        -- Eating's newstate listener can run first and capture our temporary
        -- head. Hand its saved baseline back before it finishes the meal; never
        -- overwrite the active eating pose or an unrelated mod's override.
        local meal = inst._krypton_eating_overrides
        local saved = meal ~= nil and meal[target] or nil
        if saved ~= nil and saved.build == BUILD then
            saved.build = not changed and previous.build or nil
            saved.symbol = not changed and previous.symbol or nil
            saved.skin = not changed and previous.skin or nil
        end
        if IsOurHead(inst, target) then
            if not changed and previous.build ~= nil and previous.symbol ~= nil then
                if previous.skin then
                    inst.AnimState:OverrideSkinSymbol(target, previous.build, previous.symbol)
                else
                    inst.AnimState:OverrideSymbol(target, previous.build, previous.symbol)
                end
            else
                inst.AnimState:ClearOverrideSymbol(target)
            end
        end
    end
    state.overrides, state.pose = nil, nil
end

function Visual.Clear(inst, token, interrupted)
    if interrupted then token._krypton_breath_stopped = true end
    local state = inst ~= nil and inst._krypton_breath_head or nil
    if state == nil or state.token ~= token then return end
    ReleaseHeads(inst, state)
    for _, event in ipairs(INTERRUPTS) do inst:RemoveEventCallback(event, state.interrupt) end
    inst:RemoveEventCallback("newstate", state.newstate)
    inst:RemoveEventCallback("entitysleep", state.sleep)
    inst._krypton_breath_head = nil
end

local function Available(inst)
    if not inst:IsValid() or inst:IsAsleep() or inst:HasTag("playerghost")
        or inst:HasTag("corpse") or inst:HasTag("busy") then return false end
    local health = inst.components.health or (inst.replica ~= nil and inst.replica.health) or nil
    if health ~= nil and health:IsDead() then return false end
    local rider = inst.components.rider or (inst.replica ~= nil and inst.replica.rider) or nil
    if rider ~= nil and rider:IsRiding() then return false end
    local controller = inst.components.playercontroller
    if controller ~= nil and (controller:IsBusy() or controller:IsDoingOrWorking()) then return false end
    -- Observers do not have a stategraph: native rendered clips also prevent a
    -- head from lingering over eating, work, hits or other replicated actions.
    for _, animation in ipairs(LOOPS) do
        if inst.AnimState:IsCurrentAnimation(animation) then return true end
    end
    return false
end

function Visual.Apply(inst, token, pose, started)
    if TheNet:IsDedicated() then return false end
    if token._krypton_breath_stopped then return false end
    if not Available(inst) then
        Visual.Clear(inst, token, not inst:IsAsleep())
        return false
    end
    -- Replication may deliver an older cast after a newer proxy. The server's
    -- cast time prevents that old proxy from retaking or clearing a new head.
    if started < (inst._krypton_breath_latestcast or -math.huge) then
        Visual.Clear(inst, token, true)
        return false
    end
    local state = inst._krypton_breath_head
    if state ~= nil and state.token ~= token then
        Visual.Clear(inst, state.token, true)
        state = nil
    end
    if state ~= nil then
        if SkinChanged(inst, state) then
            Visual.Clear(inst, token, true)
            return false
        end
        for target in pairs(state.overrides or {}) do
            if not IsOurHead(inst, target) then
                Visual.Clear(inst, token, true)
                return false
            end
        end
    else
        state = { token = token, build = inst.AnimState:GetBuild(),
            skinbuild = inst.AnimState:GetSkinBuild(), skinname = inst.skinname }
        inst._krypton_breath_head, inst._krypton_breath_latestcast = state, started
        state.interrupt = function() Visual.Clear(inst, token, true) end
        state.sleep = function() Visual.Clear(inst, token) end
        state.newstate = function()
            if not Available(inst) then state.interrupt() end
        end
        for _, event in ipairs(INTERRUPTS) do inst:ListenForEvent(event, state.interrupt) end
        inst:ListenForEvent("newstate", state.newstate)
        inst:ListenForEvent("entitysleep", state.sleep)
    end
    local data = DATA.poses[pose]
    if data == nil then
        -- The supplied back view remains unchanged. It has no visible mouth.
        ReleaseHeads(inst, state)
        return true
    end
    if state.overrides == nil then
        state.overrides = {}
        for _, target in ipairs(HEADS) do
            local build, symbol = inst.AnimState:GetSymbolOverride(target)
            -- An observer may first see a host's already replicated breath
            -- head. It must not become the saved normal/restored head.
            if build == BUILD then build, symbol = nil, nil end
            state.overrides[target] = { build = build, symbol = symbol,
                skin = build ~= nil and inst.AnimState:IsSkinBuild(build) }
        end
    end
    local update = state.pose ~= pose
    local desired_symbol = hash(data.symbol)
    for _, target in ipairs(HEADS) do
        local _, symbol = inst.AnimState:GetSymbolOverride(target)
        if symbol ~= desired_symbol then update = true end
    end
    if update then
        for _, target in ipairs(HEADS) do inst.AnimState:OverrideSymbol(target, DATA.build, data.symbol) end
        state.pose = pose
    end
    return true, data.mouth
end

return Visual
