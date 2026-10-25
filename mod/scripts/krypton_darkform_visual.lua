local Visual = {}

local BUILD = "krypton_dark_suit"
local CLOTHES = { "torso", "torso_pelvis", "arm_upper", "arm_lower", "leg", "foot" }

local function GetState(inst)
    if inst._krypton_dark_visual_clothes == nil then
        inst._krypton_dark_visual_clothes = { applied = false }
    end
    return inst._krypton_dark_visual_clothes
end

local function GetSkinner(inst)
    return TheWorld.ismastersim and inst.components.skinner or nil
end

local function IsAvailable(inst, skinner)
    if skinner:GetSkinMode() ~= "normal_skin" or inst:IsAsleep()
        or inst:HasTag("playerghost") or inst:HasTag("corpse") then return false end
    local health = inst.components.health
    return health == nil or not health:IsDead()
end

local function QueueRefresh(inst)
    if inst._krypton_dark_visual_refresh ~= nil then return end
    inst._krypton_dark_visual_refresh = inst:DoTaskInTime(0, function(player)
        player._krypton_dark_visual_refresh = nil
        Visual.Apply(player)
    end)
end

local function Source(anim, symbol)
    local build, source = anim:GetSymbolOverride(symbol)
    return tostring(build) .. "/" .. tostring(source)
end

local function Render(inst, skinner, dark)
    local state = GetState(inst)
    if state.rendering then
        state.invalidated = true
        QueueRefresh(inst)
        return
    end
    state.rendering = true
    local mode = skinner:GetSkinMode()
    local base = skinner.skin_data ~= nil and skinner.skin_data[mode] or nil
    base = base or inst.prefab
    -- A coat also owns skirts, cuffs, hidden symbols and torso/pelvis render
    -- exchanges. Only the native complete clothing pass can release all of
    -- those rules and reconstruct the current outfit correctly afterwards.
    -- NO_BASE keeps the character skin and independent head/equipment symbols;
    -- it is a native clothing mode, so the real clothing table works here.
    -- Never put normal clothes onto a ghost while releasing a previous suit.
    local clothes = not dark and mode == "normal_skin" and skinner.clothing or {}
    SetSkinsOnAnim(inst.AnimState, inst.prefab, base, clothes,
        not dark and mode == "normal_skin" and skinner:GetMonkeyCurse() or nil, "NO_BASE")
    if dark then
        for _, symbol in ipairs(CLOTHES) do
            inst.AnimState:OverrideSymbol(symbol, BUILD, symbol)
        end
    end
    state.applied, state.rendering = dark, false
    -- Log only real outfit transitions. These native renderer results make a
    -- reported coat conflict traceable without collecting any player identity.
    print(string.format("[Krypton Survivor] clothes=%s mode=%s body=%s torso=%s pelvis=%s skirt=%s",
        dark and "dark" or "normal", tostring(mode), tostring(skinner.clothing.body or ""),
        Source(inst.AnimState, "torso"), Source(inst.AnimState, "torso_pelvis"), Source(inst.AnimState, "skirt")))
    if state.invalidated then
        -- An external outfit callback changed state during the native pass.
        -- Reconcile once after the callback unwinds, never inside that pass.
        state.invalidated, state.applied = nil, nil
        QueueRefresh(inst)
    end
end

function Visual.Apply(inst)
    local skinner = GetSkinner(inst)
    if skinner == nil or inst._krypton_dark_visual_isdark == nil then return end
    local dark = IsAvailable(inst, skinner) and inst._krypton_dark_visual_isdark(inst)
    if GetState(inst).applied ~= dark then Render(inst, skinner, dark) end
end

function Visual.Clear(inst)
    local skinner = GetSkinner(inst)
    if skinner ~= nil and GetState(inst).applied ~= false then Render(inst, skinner, false) end
end

function Visual.OnSkinModeChanged(inst)
    local skinner = GetSkinner(inst)
    if skinner == nil or inst._krypton_dark_visual_isdark == nil then return end
    local state = GetState(inst)
    if state.rendering then
        state.invalidated = true
        QueueRefresh(inst)
        return
    end
    -- SetSkinMode has just completed a full native clothing reset. Its current
    -- skinner data is authoritative, including any newly selected coat. Keep
    -- that result in normal/ghost form; hide it again if dark form is active.
    state.applied = false
    Visual.Apply(inst)
end

function Visual.CommonInit(inst, is_dark)
    -- Clothing is authored by the master, including dedicated servers, and
    -- copied by the native AnimState network. Local observers must not race
    -- those updates or mistake replicated dark pixels for their normal coat.
    if not TheWorld.ismastersim then return end
    inst._krypton_dark_visual_isdark = is_dark
    inst.AnimState:ClearOverrideBuild(BUILD)
    for _, event in ipairs({ "krypton_darkformdirty", "playeractivated", "newstate",
        "entitywake", "ms_respawnedfromghost", "respawnfromcorpse" }) do
        inst:ListenForEvent(event, Visual.Apply)
    end
    for _, event in ipairs({ "death", "ms_becameghost", "entitysleep" }) do
        inst:ListenForEvent(event, Visual.Clear)
    end
    inst:ListenForEvent("onremove", function(player)
        if player._krypton_dark_visual_refresh ~= nil then
            player._krypton_dark_visual_refresh:Cancel()
            player._krypton_dark_visual_refresh = nil
        end
    end)
    -- Common initialization precedes creation/loading of the native skinner.
    -- Its SetSkinMode hook handles later outfit changes without a polling loop.
    QueueRefresh(inst)
end

return Visual
