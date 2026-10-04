local Visual = {}

local BUILD = "krypton_flight_build"
local IDLE = "krypton_flight_idle"
local MOVE = "krypton_flight_move"
local LOOPS = { "idle_loop", "run_loop", "walk_loop" }

local function CurrentFlightAnimation(inst)
    if inst.AnimState:IsCurrentAnimation(IDLE) then return IDLE end
    if inst.AnimState:IsCurrentAnimation(MOVE) then return MOVE end
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

local function IsSuspended(inst)
    return (inst._krypton_flight_visual_suspended ~= nil and inst._krypton_flight_visual_suspended:value())
        or GetTime() < (inst._krypton_flight_visual_pauseuntil or 0)
end

function Visual.Apply(inst)
    if inst._krypton_flight_visual_isflying == nil then return end
    local current = CurrentFlightAnimation(inst)
    if not inst._krypton_flight_visual_isflying(inst) or IsSuspended(inst) or not IsNormalState(inst) then
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
end

function Visual.CommonInit(inst, is_flying)
    inst._krypton_flight_visual_isflying = is_flying
    inst.SuspendKryptonFlightVisual = Visual.Suspend
    inst._krypton_flight_visual_suspended = net_bool(inst.GUID,
        "krypton_survivor.flight_visual_suspended", "krypton_flight_visualdirty")
    -- Adds only this original artwork's unique body symbol. The wilson bank
    -- and the existing character build remain available for native actions.
    inst.AnimState:AddOverrideBuild(BUILD)
    inst:ListenForEvent("krypton_flight_visualdirty", Visual.Apply)
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
