local Visual = {}
local DATA = require("krypton_eating_visual_data")
local HEADS = { "headbase", "headbase_hat" }

local function CurrentAnimation(inst)
    for animation in pairs(DATA.timelines) do
        if inst.AnimState:IsCurrentAnimation(animation) then return animation end
    end
end

local function CurrentPose(inst, animation)
    -- GetCurrentAnimationTime is the rendered native animation's time, including
    -- replicated players with no local SG and client prediction's *_lag clips.
    local frame = math.floor(inst.AnimState:GetCurrentAnimationTime()
        * DATA.frames_per_second + .00001)
    local pose
    for _, stage in ipairs(DATA.timelines[animation]) do
        if frame < stage.frame then break end
        pose = stage.pose
    end
    return pose ~= nil and DATA.symbols[pose] or nil
end

local function IsOurOverride(inst, target, previous)
    local build = inst.AnimState:GetSymbolOverride(target)
    -- A host's next pose may replicate before this client's next visual tick.
    -- This private build contains only our three eating heads, so all of its
    -- poses are owned here; a different build (or cleared override) is external.
    return build == previous.own_build
end

function Visual.Clear(inst)
    local overrides = inst._krypton_eating_overrides
    if overrides == nil then return end
    -- A new base/skin build must not inherit saved overrides from its old skin.
    local changed = inst.AnimState:GetBuild() ~= inst._krypton_eating_build
        or inst.AnimState:GetSkinBuild() ~= inst._krypton_eating_skinbuild
        or inst.skinname ~= inst._krypton_eating_skinname
    for target, previous in pairs(overrides) do
        if IsOurOverride(inst, target, previous) then
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
    inst._krypton_eating_overrides = nil
    inst._krypton_eating_pose = nil
    inst._krypton_eating_build = nil
    inst._krypton_eating_skinbuild = nil
    inst._krypton_eating_skinname = nil
end

local function Interrupt(inst)
    Visual.Clear(inst)
    inst._krypton_eating_interrupted = true
end

local function IsUnavailable(inst)
    if inst:HasTag("playerghost") or inst:HasTag("corpse") then return true end
    local health = inst.components.health or (inst.replica ~= nil and inst.replica.health)
    if health ~= nil and health:IsDead() then return true end
    local rider = inst.components.rider or (inst.replica ~= nil and inst.replica.rider)
    return rider ~= nil and rider:IsRiding()
end

function Visual.Apply(inst)
    if TheNet:IsDedicated() then return end
    local animation = CurrentAnimation(inst)
    if animation == nil then
        Visual.Clear(inst)
        inst._krypton_eating_interrupted = nil
        return
    end
    if inst:IsAsleep() then
        Visual.Clear(inst)
        return
    end
    if IsUnavailable(inst) then Interrupt(inst) end
    if inst._krypton_eating_interrupted then return end

    local overrides = inst._krypton_eating_overrides
    if overrides ~= nil then
        if inst.AnimState:GetBuild() ~= inst._krypton_eating_build
            or inst.AnimState:GetSkinBuild() ~= inst._krypton_eating_skinbuild
            or inst.skinname ~= inst._krypton_eating_skinname then
            Interrupt(inst)
            return
        end
        for target, previous in pairs(overrides) do
            if not IsOurOverride(inst, target, previous) then
                -- Hats, skins or another mod changed the head during the meal.
                -- Leave their new value alone and stop owning this meal's head.
                Interrupt(inst)
                return
            end
        end
    end

    local pose = CurrentPose(inst, animation)
    if pose == nil then
        Visual.Clear(inst)
        return
    end
    if pose == inst._krypton_eating_pose then return end
    if overrides == nil then
        overrides = {}
        inst._krypton_eating_overrides = overrides
        inst._krypton_eating_build = inst.AnimState:GetBuild()
        inst._krypton_eating_skinbuild = inst.AnimState:GetSkinBuild()
        inst._krypton_eating_skinname = inst.skinname
        for _, target in ipairs(HEADS) do
            local build, symbol = inst.AnimState:GetSymbolOverride(target)
            overrides[target] = {
                build = build,
                symbol = symbol,
                skin = build ~= nil and inst.AnimState:IsSkinBuild(build),
            }
        end
    end
    for target, previous in pairs(overrides) do
        inst.AnimState:OverrideSymbol(target, DATA.build, pose)
        previous.own_build, previous.own_symbol = inst.AnimState:GetSymbolOverride(target)
        -- A host's current eating override can already be replicated when an
        -- observer starts watching. Never save our own head as the idle head.
        if previous.build == previous.own_build then
            previous.build, previous.symbol, previous.skin = nil, nil, nil
        end
    end
    inst._krypton_eating_pose = pose
end

function Visual.CommonInit(inst)
    if TheNet:IsDedicated() then return end
    -- Native body, arms, food, nutrition and sound remain entirely unchanged.
    -- Only the two native head symbols are temporarily sourced from supplied art.
    for _, event in ipairs({ "newstate", "animover", "animqueueover", "entitywake" }) do
        inst:ListenForEvent(event, Visual.Apply)
    end
    for _, event in ipairs({ "death", "ms_becameghost", "mounted", "isridingdirty",
        "ms_playerreroll", "equipskinneditem", "unequipskinneditem" }) do
        inst:ListenForEvent(event, Interrupt)
    end
    inst:ListenForEvent("entitysleep", Visual.Clear)
    inst:ListenForEvent("onremove", function(player)
        Visual.Clear(player)
        if player._krypton_eating_task ~= nil then
            player._krypton_eating_task:Cancel()
            player._krypton_eating_task = nil
        end
    end)
    local on_load = inst.OnLoad
    inst.OnLoad = function(player, data, ...)
        Interrupt(player)
        if on_load ~= nil then return on_load(player, data, ...) end
    end
    inst._krypton_eating_task = inst:DoPeriodicTask(FRAMES, Visual.Apply, 0)
end

return Visual
