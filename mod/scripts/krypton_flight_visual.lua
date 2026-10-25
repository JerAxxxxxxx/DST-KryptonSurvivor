local Visual = {}
local DarkForm = require("krypton_darkform")

local BUILD = "krypton_flight_build"
local DARK_BUILD = "krypton_dark_flight"
local SYMBOL = "krypton_flight_body"
local SYMBOL_HASH = hash(SYMBOL)
local BUILD_HASHES = { [BUILD] = hash(BUILD), [DARK_BUILD] = hash(DARK_BUILD) }
local IDLE = "krypton_flight_idle"
local MOVE = "krypton_flight_move"
local LOOPS = { "idle_loop", "run_loop", "walk_loop" }
-- This native air loop is globally loaded by prefabs/global.lua. Keep the
-- emitter local, like Walter's sprint trail, so host and client playback cannot
-- duplicate each other and no native sound files need to ship with the mod.
local FLIGHT_SOUND = "meta5/woby/sprint_wind_lp"
local FLIGHT_SOUND_VOLUME = .15

local function IsFlightSymbolBound(inst)
    local desired = inst._krypton_flight_visual_build
    if desired == nil then return false end
    local build, symbol = inst.AnimState:GetSymbolOverride(SYMBOL)
    return build == BUILD_HASHES[desired] and symbol == SYMBOL_HASH
end

local function ClearFlightBuild(inst)
    local previous = inst._krypton_flight_visual_build
    if previous ~= nil then
        if IsFlightSymbolBound(inst) then inst.AnimState:ClearOverrideSymbol(SYMBOL) end
        inst.AnimState:ClearOverrideBuild(previous)
        inst._krypton_flight_visual_build = nil
    end
end

local function ApplyFlightBuild(inst)
    local health = inst.components.health or (inst.replica ~= nil and inst.replica.health)
    if inst:IsAsleep() or inst:HasTag("playerghost") or inst:HasTag("corpse")
        or (health ~= nil and health:IsDead()) then
        ClearFlightBuild(inst)
        return false
    end
    local desired = DarkForm.IsDark(inst) and DARK_BUILD or BUILD
    if inst._krypton_flight_visual_build ~= desired then
        -- Both builds supply the same unique flight symbol. Keep exactly one
        -- active so returning to normal cannot leave a later dark override in
        -- front. Switching pixels must not restart the current flight cycle.
        ClearFlightBuild(inst)
        inst.AnimState:AddOverrideBuild(desired)
        inst._krypton_flight_visual_build = desired
    end
    if not IsFlightSymbolBound(inst) then
        -- CommonInit runs before native skin/save initialization finishes, and
        -- a later replicated AnimState can replace an earlier local binding.
        -- A Lua build cache is not proof that our sole flight symbol exists.
        -- Bind it explicitly and compare the native returned hashes on every
        -- refresh; leave clothing, heads and equipment symbols untouched.
        inst.AnimState:OverrideSymbol(SYMBOL, desired, SYMBOL)
    end
    return IsFlightSymbolBound(inst)
end

local function StopFlightSound(inst)
    local sound = inst._krypton_flight_sound
    inst._krypton_flight_sound = nil
    if sound ~= nil and sound:IsValid() then
        sound.SoundEmitter:KillSound("krypton_flight")
        sound:Remove()
    end
end

local function ClearVisual(inst)
    StopFlightSound(inst)
    ClearFlightBuild(inst)
end

local function UpdateFlightSound(inst, moving)
    if not moving or TheNet:IsDedicated() or inst:IsAsleep() then
        StopFlightSound(inst)
        return
    end
    if inst._krypton_flight_sound == nil then
        local sound = CreateEntity()
        sound:AddTag("FX")
        sound:AddTag("NOCLICK")
        sound.entity:SetCanSleep(false)
        sound.persists = false
        sound.entity:AddTransform()
        sound.entity:AddSoundEmitter()
        sound.entity:SetParent(inst.entity)
        sound:Hide()
        sound.SoundEmitter:PlaySound(FLIGHT_SOUND, "krypton_flight", FLIGHT_SOUND_VOLUME)
        inst._krypton_flight_sound = sound
    end
end

local function CurrentFlightAnimation(inst)
    if inst.AnimState:IsCurrentAnimation(IDLE) then return IDLE end
    if inst.AnimState:IsCurrentAnimation(MOVE) then return MOVE end
end

local function IsFlightLoop(inst)
    if CurrentFlightAnimation(inst) ~= nil then return true end
    for _, animation in ipairs(LOOPS) do
        if inst.AnimState:IsCurrentAnimation(animation) then return true end
    end
    return false
end

local function IsNormalState(inst)
    if inst:HasTag("busy") then return false end
    if inst.sg ~= nil then
        local state = inst.sg.currentstate
        return state ~= nil and (state.name == "idle" or state.name == "run" or state.name == "walk")
            and not inst.sg:HasStateTag("busy")
    end
    -- Other clients' players have no local stategraph. The exact loop check
    -- below still prevents replacing their replicated attacks or transitions.
    return true
end

local function IsFlightStep(inst)
    if IsNormalState(inst) then return IsFlightLoop(inst) end
    local state = inst.sg ~= nil and inst.sg.currentstate or nil
    if inst:HasTag("busy") or state == nil or inst.sg:HasStateTag("busy")
        or (state.name ~= "run_start" and state.name ~= "run_stop") then
        return false
    end
    -- Both Wilson SGs emit a terrain step during run_start. We preserve these
    -- native transition animations, but an airborne player still has no floor
    -- contact. Landing and mounted transitions fall through via IsFlying.
    return inst.AnimState:IsCurrentAnimation("run_pre")
        or inst.AnimState:IsCurrentAnimation("run_pst")
        or inst.AnimState:IsCurrentAnimation("walk_pre")
        or inst.AnimState:IsCurrentAnimation("walk_pst")
end

local function IsSuspended(inst)
    return (inst._krypton_flight_visual_suspended ~= nil and inst._krypton_flight_visual_suspended:value())
        or GetTime() < (inst._krypton_flight_visual_pauseuntil or 0)
end

function Visual.Apply(inst)
    if TheNet:IsDedicated() or inst._krypton_flight_visual_isflying == nil then return end
    local build_ready = ApplyFlightBuild(inst)
    if inst:IsAsleep() then
        StopFlightSound(inst)
        return
    end
    local current = CurrentFlightAnimation(inst)
    if not build_ready or not inst._krypton_flight_visual_isflying(inst) or inst:HasTag("corpse")
        or IsSuspended(inst) or not IsNormalState(inst) then
        StopFlightSound(inst)
        if current ~= nil then
            -- Only replace our own animation. A stategraph attack, gathering
            -- action, ghost or mounted animation always takes precedence.
            inst.AnimState:PlayAnimation(inst._krypton_flight_visual_native
                or (current == IDLE and "idle_loop" or "run_loop"), true)
        end
        inst._krypton_flight_visual_animation = nil
        inst._krypton_flight_visual_started = nil
        inst._krypton_flight_visual_native = nil
        return
    end

    local native
    for _, animation in ipairs(LOOPS) do
        if inst.AnimState:IsCurrentAnimation(animation) then
            native = animation
            break
        end
    end
    local desired = native ~= nil and (native == "idle_loop" and IDLE or MOVE) or current
    if desired == nil then
        StopFlightSound(inst)
        -- Preserve run_pre/run_pst, funny idles and all complex actions.
        inst._krypton_flight_visual_animation = nil
        inst._krypton_flight_visual_started = nil
        inst._krypton_flight_visual_native = nil
        return
    end

    local now = GetTime()
    if inst._krypton_flight_visual_animation ~= desired then
        inst._krypton_flight_visual_animation = desired
        inst._krypton_flight_visual_started = now
    end
    if native ~= nil then inst._krypton_flight_visual_native = native end
    if current ~= desired then
        inst.AnimState:PlayAnimation(desired, true)
        -- Native run periodically re-enters itself and plays run_loop when our
        -- unique name does not match. Preserve the flight cycle's phase across
        -- that re-entry without patching the shared SG or AnimState methods.
        local length = inst.AnimState:GetCurrentAnimationLength()
        if length > 0 then
            inst.AnimState:SetTime((now - inst._krypton_flight_visual_started) % length)
        end
    end
    UpdateFlightSound(inst, desired == MOVE)
end

function Visual.CommonInit(inst, is_flying)
    inst._krypton_flight_visual_isflying = is_flying
    inst.SuspendKryptonFlightVisual = Visual.Suspend
    inst._krypton_flight_visual_suspended = net_bool(inst.GUID,
        "krypton_survivor.flight_visual_suspended", "krypton_flight_visualdirty")
    -- Adds only this original artwork's unique body symbol. The wilson bank
    -- and the existing character build remain available for native actions.
    if not TheNet:IsDedicated() then ApplyFlightBuild(inst) end
    inst:ListenForEvent("krypton_flight_visualdirty", Visual.Apply)
    inst:ListenForEvent("krypton_darkformdirty", Visual.Apply)
    inst:ListenForEvent("entitysleep", ClearVisual)
    inst:ListenForEvent("entitywake", Visual.Apply)
    inst:ListenForEvent("death", ClearVisual)
    inst:ListenForEvent("ms_becameghost", ClearVisual)
    inst:ListenForEvent("respawnfromcorpse", Visual.Apply)
    inst:ListenForEvent("onremove", ClearVisual)
    -- Native PlayFootstep supports this per-player hook in both Wilson SGs.
    -- Preserve skin/mod overrides whenever landing, mounted or doing an action;
    -- don't mute the SoundEmitter, which also plays combat and eating sounds.
    local previous_footstep = inst.footstepoverridefn
    inst.footstepoverridefn = function(player, volume, ispredicted)
        if player._krypton_flight_visual_isflying(player)
            and not IsSuspended(player) and IsFlightStep(player) then
            return true
        end
        return previous_footstep ~= nil and previous_footstep(player, volume, ispredicted) or false
    end
end

function Visual.Suspend(inst, duration)
    if inst == nil or not inst:IsValid() or inst._krypton_flight_visual_suspended == nil then return end
    local now = GetTime()
    local until_time = math.max(inst._krypton_flight_visual_pauseuntil or 0, now + (duration or .5))
    inst._krypton_flight_visual_pauseuntil = until_time
    if TheWorld.ismastersim then inst._krypton_flight_visual_suspended:set(true) end
    if inst._krypton_flight_visual_resume_task ~= nil then
        inst._krypton_flight_visual_resume_task:Cancel()
    end
    inst._krypton_flight_visual_resume_task = inst:DoTaskInTime(math.max(0, until_time - now), function(player)
        player._krypton_flight_visual_resume_task = nil
        if TheWorld.ismastersim then player._krypton_flight_visual_suspended:set(false) end
        Visual.Apply(player)
    end)
    Visual.Apply(inst)
end

return Visual
