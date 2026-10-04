local Flight = {}
local Visual = require("krypton_flight_visual")

local function IsEnabled()
    return TUNING.KRYPTON_SURVIVOR.flight_enabled ~= false
end

local function IsRiding(inst)
    local rider = inst.components.rider or (inst.replica ~= nil and inst.replica.rider) or nil
    return rider ~= nil and rider:IsRiding()
end

function Flight.IsFlying(inst)
    local health = inst ~= nil and (inst.components.health or (inst.replica ~= nil and inst.replica.health) or nil)
    return inst ~= nil and inst._krypton_flying ~= nil and inst._krypton_flying:value()
        and IsEnabled() and not inst:HasTag("playerghost") and not IsRiding(inst)
        and (health == nil or not health:IsDead())
end

local function IsInBounds(x, y, z)
    local map = TheWorld.Map
    local width, height = map:GetSize()
    local half_width, half_height = width * TILE_SCALE / 2, height * TILE_SCALE / 2
    -- Reject by world coordinates before the native tile lookup can clamp an
    -- out-of-range position back onto an edge tile.
    if x <= -half_width or x >= half_width or z <= -half_height or z >= half_height then
        return false
    end
    if not map:IsInMapBounds(x, y, z) then return false end
    -- Tile indices are zero based; exclude the extra edge accepted by the
    -- native bounds helper, while still admitting internal cave VOID tiles.
    local tx, tz = map:GetTileCoordsAtPoint(x, y, z)
    return tx >= 0 and tz >= 0 and tx < width and tz < height
end

local function CanLand(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    return IsInBounds(x, y, z) and (inst:GetCurrentPlatform() ~= nil
        or TheWorld.Map:IsVisualGroundAtPoint(x, y, z))
end

local function StopMoving(inst)
    local locomotor = inst.components.locomotor
    if locomotor ~= nil then
        locomotor:Stop()
        locomotor:Clear()
    end
    inst:ClearBufferedAction()
    local controller = inst.components.playercontroller
    if controller ~= nil then
        controller:ClearRemotePredictData()
        if TheWorld.ismastersim and controller.remote_vector ~= nil then
            controller.remote_vector.y = 0
        end
    end
    inst.Physics:Stop()
end

local function ConfigureLocomotor(inst, flying)
    local locomotor = inst.components.locomotor
    if locomotor == nil then return end
    local saved = locomotor._krypton_flight_restore
    if flying then
        if saved == nil then
            saved = {
                directdrive = locomotor.directdrive,
                ground = locomotor.enablegroundspeedmultiplier,
                creep = locomotor.triggerscreep,
                hopping = locomotor.allow_platform_hopping,
            }
            locomotor._krypton_flight_restore = saved
            locomotor:ResetPath()
        end
        -- ConfigurePlayerLocomotor replaces this table after prediction starts
        -- or resurrection. Capture that new normal table before changing it.
        if saved.pathcaps == nil or saved.pathcaps ~= locomotor.pathcaps then
            if saved.pathcaps ~= nil then saved.pathcaps.allowocean = saved.allowocean end
            saved.pathcaps = locomotor.pathcaps or {}
            saved.allowocean = saved.pathcaps.allowocean
            locomotor.pathcaps = saved.pathcaps
        end
        locomotor.pathcaps.allowocean = true
        -- Like the native wagdrone_flying: direct drive bypasses a pathfinder
        -- that understands oceans but has no capability for cave VOID.
        -- Physical walls, trees and creatures still block this movement.
        locomotor.directdrive = true
        if locomotor.enablegroundspeedmultiplier ~= false then
            locomotor:EnableGroundSpeedMultiplier(false)
        end
        if locomotor.triggerscreep ~= false then locomotor:SetTriggersCreep(false) end
        if locomotor.allow_platform_hopping ~= false then locomotor:SetAllowPlatformHopping(false) end
    elseif saved ~= nil then
        saved.pathcaps.allowocean = saved.allowocean
        locomotor.directdrive = saved.directdrive
        locomotor:EnableGroundSpeedMultiplier(saved.ground ~= false)
        -- Ghost setup already changed these fields; preserve its native rules.
        if not inst:HasTag("playerghost") then
            locomotor:SetTriggersCreep(saved.creep ~= false)
            locomotor:SetAllowPlatformHopping(saved.hopping == true)
        end
        locomotor._krypton_flight_restore = nil
        locomotor:ResetPath()
    end
end

local function HasCollision(mask, flag)
    return mask % (flag * 2) >= flag
end

local function ConfigurePhysics(inst, flying)
    if inst:HasTag("playerghost") then
        -- MakeGhostPhysics owns the ghost mask; never restore living limits.
        inst._krypton_flight_physics_restore = nil
        return
    end
    if not inst.Physics:IsActive() or (inst.sg ~= nil and inst.sg.statemem.isphysicstoggle) then
        return
    end
    local mask = inst.Physics:GetCollisionMask()
    local saved = inst._krypton_flight_physics_restore
    if flying then
        if saved == nil then
            saved = {
                land = HasCollision(mask, COLLISION.LAND_OCEAN_LIMITS),
                boat = HasCollision(mask, COLLISION.BOAT_LIMITS),
            }
            inst._krypton_flight_physics_restore = saved
        end
        -- Both surface shores and cave discontinuities use these limits.
        -- Keep GROUND, the character collision group and every obstacle bit.
        if HasCollision(mask, COLLISION.LAND_OCEAN_LIMITS) then
            inst.Physics:ClearCollidesWith(COLLISION.LAND_OCEAN_LIMITS)
        end
        if HasCollision(mask, COLLISION.BOAT_LIMITS) then
            inst.Physics:ClearCollidesWith(COLLISION.BOAT_LIMITS)
        end
    elseif saved ~= nil then
        if saved.land then inst.Physics:CollidesWith(COLLISION.LAND_OCEAN_LIMITS) end
        if saved.boat then inst.Physics:CollidesWith(COLLISION.BOAT_LIMITS) end
        inst._krypton_flight_physics_restore = nil
    end
end

local function CheckBounds(inst)
    if not TheWorld.ismastersim and inst ~= ThePlayer then return end
    local x, y, z = inst.Transform:GetWorldPosition()
    if IsInBounds(x, y, z) then
        inst._krypton_flight_lastposition = { x = x, y = y, z = z }
    elseif Flight.IsFlying(inst) then
        local last = inst._krypton_flight_lastposition
        -- The map is centred on (0, 0); this fallback is only for an already
        -- out-of-bounds save with no valid position recorded on this session.
        inst.Physics:Stop()
        inst.Physics:Teleport(last ~= nil and last.x or 0,
            last ~= nil and last.y or 0, last ~= nil and last.z or 0)
        -- Stop can enter another state and emit newstate. Correct the position
        -- first so that callback cannot recursively handle the same bad point.
        StopMoving(inst)
    end
end

local function ApplyFlight(inst)
    local flying = Flight.IsFlying(inst)
    ConfigureLocomotor(inst, flying)
    ConfigurePhysics(inst, flying)
    if flying then
        if not inst:HasTag("flying") then inst:AddTag("flying") end
    elseif not inst._krypton_flight_originaltag and inst:HasTag("flying") then
        inst:RemoveTag("flying")
    end
    if TheWorld.ismastersim and inst.components.drownable ~= nil then
        if flying then
            if inst._krypton_flight_drowning_restore == nil then
                inst._krypton_flight_drowning_restore = inst.components.drownable.enabled ~= false
            end
            -- Native drownable handles both drowning and falling into VOID.
            inst.components.drownable.enabled = false
        elseif inst._krypton_flight_drowning_restore ~= nil then
            inst.components.drownable.enabled = inst._krypton_flight_drowning_restore
            inst._krypton_flight_drowning_restore = nil
        end
    end
    CheckBounds(inst)
    Visual.Apply(inst)
end

function Flight.CommonInit(inst)
    inst._krypton_flying = net_bool(inst.GUID, "krypton_survivor.flying", "krypton_flyingdirty")
    inst._krypton_flight_originaltag = inst:HasTag("flying")
    Visual.CommonInit(inst, Flight.IsFlying)
    local previous = inst.ExtraConfigurePlayerLocomotor
    inst.ExtraConfigurePlayerLocomotor = function(player)
        if previous ~= nil then previous(player) end
        player.components.locomotor:SetExternalSpeedMultiplier(player,
            "krypton_survivor", TUNING.KRYPTON_SURVIVOR.speed)
        ApplyFlight(player)
    end
    for _, event in ipairs({ "krypton_flyingdirty", "playeractivated", "newstate",
        "isridingdirty", "mounted", "dismounted", "ms_becameghost", "ms_respawnedfromghost" }) do
        inst:ListenForEvent(event, ApplyFlight)
    end
    -- Stategraphs may restore WORLD collision after hops/teleports; also cover
    -- client prediction being enabled later and guard the actual world edge.
    inst:DoPeriodicTask(FRAMES, ApplyFlight)
end

function Flight.MasterInit(inst)
    inst._krypton_flying:set(IsEnabled())
    ApplyFlight(inst)
    local on_save, on_load = inst.OnSave, inst.OnLoad
    inst.OnSave = function(player, data)
        local refs = on_save ~= nil and on_save(player, data) or nil
        data.krypton_flying = player._krypton_flying:value()
        return refs
    end
    inst.OnLoad = function(player, data)
        if on_load ~= nil then on_load(player, data) end
        player._krypton_flying:set(IsEnabled() and (data == nil or data.krypton_flying ~= false))
        -- Runs before player_common's deferred invalid-ground reset and before
        -- drownable enables itself, so a saved flight above VOID stays there.
        ApplyFlight(player)
    end
end

function Flight.Toggle(inst)
    if not TheWorld.ismastersim or not IsEnabled() then return false, "disabled" end
    if inst == nil or not inst:IsValid() or inst.prefab ~= "krypton_survivor"
        or not inst:HasTag("kryptonian") or inst:HasTag("playerghost")
        or inst.components.health == nil or inst.components.health:IsDead() then
        return false, "unavailable"
    end
    if IsRiding(inst) then return false, "riding" end
    local controller = inst.components.playercontroller
    if TheNet:IsServerPaused() or controller == nil or not controller:IsEnabled()
        or controller:IsBusy() or controller:IsDoingOrWorking() or inst:HasTag("busy")
        or (inst.sg ~= nil and inst.sg:HasStateTag("busy")) then
        return false, "busy"
    end
    local now = GetTime()
    if now < (inst._krypton_flight_nexttoggle or 0) then return false, "cooldown" end
    if Flight.IsFlying(inst) and not CanLand(inst) then return false, "cannot_land" end
    inst._krypton_flight_nexttoggle = now + (TUNING.KRYPTON_SURVIVOR.flight_toggle_interval or .35)
    StopMoving(inst)
    inst._krypton_flying:set(not inst._krypton_flying:value())
    ApplyFlight(inst)
    inst.Physics:Teleport(inst.Transform:GetWorldPosition())
    return true
end

return Flight
