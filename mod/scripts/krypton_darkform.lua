local DarkForm = {}

DarkForm.DIRTY_EVENT = "krypton_darkformdirty"

function DarkForm.CommonInit(inst)
    -- Every peer declares this before the character is made pristine.
    inst._krypton_dark_form = net_bool(inst.GUID, "krypton_survivor.dark_form", DarkForm.DIRTY_EVENT)
end

function DarkForm.IsDark(inst)
    return inst ~= nil and inst._krypton_dark_form ~= nil and inst._krypton_dark_form:value() == true
end

function DarkForm.CanToggle(player)
    if not TheWorld.ismastersim or player == nil or not player:IsValid()
        or player.prefab ~= "krypton_survivor" or not player:HasTag("kryptonian")
        or player:HasTag("playerghost") or player:HasTag("corpse")
        or player.components.health == nil or player.components.health:IsDead()
        or player.components.sanity == nil or player.components.krypton_darkform == nil then
        return false, "unavailable"
    end
    if TheNet:IsServerPaused() then return false, "paused" end
    local controller = player.components.playercontroller
    if controller == nil or not controller:IsEnabled() then return false, "controls_disabled" end
    if player:HasTag("busy") or controller:IsBusy() or controller:IsDoingOrWorking()
        or controller.placer ~= nil
        or (player.sg ~= nil and player.sg:HasAnyStateTag("busy", "jumping", "nointerrupt")) then
        return false, "busy"
    end
    -- This changes no physical state, so safe riding and flight are supported.
    return true
end

function DarkForm.Toggle(player)
    local allowed, reason = DarkForm.CanToggle(player)
    if not allowed then return false, reason end
    local now = GetTime()
    if now < (player._krypton_darkform_nexttoggle or 0) then return false, "cooldown" end
    local component = player.components.krypton_darkform
    if not component:SetDark(not component:IsDark()) then return false, "unavailable" end
    local interval = TUNING.KRYPTON_SURVIVOR.darkform_toggle_interval or .35
    player._krypton_darkform_nexttoggle = now + math.max(.1, interval)
    return true, component:IsDark() and "dark_on" or "dark_off"
end

return DarkForm
