local FrostBreath = {}

local QUERY_EXCLUDES = { "INLIMBO", "FX" }
local FREEZE_EXCLUDES = {
    "INLIMBO", "player", "playerghost", "companion", "wall", "structure",
    "FX", "notarget", "invisible", "player_aligned", "domesticated",
}

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function FrostBreath.CanCast(player)
    if TheNet:IsServerPaused() or player == nil or not player:IsValid()
        or player.prefab ~= "krypton_survivor" or not player:HasTag("kryptonian")
        or player:HasTag("playerghost") or player:HasTag("busy")
        or player.components.health == nil or player.components.health:IsDead()
        or player.components.combat == nil then
        return false
    end
    local rider = player.components.rider
    if rider ~= nil and rider:IsRiding() then return false end
    local controller = player.components.playercontroller
    return controller ~= nil and controller:IsEnabled() and not controller:IsBusy()
        and not controller:IsDoingOrWorking() and controller.placer == nil
end

local function CanFreeze(player, target)
    for _, tag in ipairs(FREEZE_EXCLUDES) do
        if target:HasTag(tag) then return false end
    end
    return target ~= player and target.components.health ~= nil and not target.components.health:IsDead()
        and target.components.combat ~= nil and target.components.freezable ~= nil
        and not (target.components.follower ~= nil and target.components.follower.leader ~= nil)
        and player.components.combat:CanTarget(target)
end

local function CanExtinguish(target)
    local burnable = target.components.burnable
    -- A campfire's native onextinguish callback empties its fuel. Fuelled
    -- lights, cookers and intentional fire sources must keep operating.
    return burnable ~= nil and (burnable:IsBurning() or burnable:IsSmoldering())
        and not target:HasTag("campfire") and not target:HasTag("cooker")
        and target.components.fueled == nil
end

local function InCone(x, z, dx, dz, target, range, half_angle)
    local tx, _, tz = target.Transform:GetWorldPosition()
    local ox, oz = tx - x, tz - z
    local along = ox * dx + oz * dz
    if along < 0 then return false end
    local radius = math.max(0, math.min(3, target:GetPhysicsRadius(0)))
    local distance = math.sqrt(ox * ox + oz * oz)
    if not IsFinite(distance) or distance > range + radius then return false end
    local across = math.abs(ox * dz - oz * dx)
    -- Distance from each ray bounding the cone; radius includes large bodies
    -- touching the edge without extending the cone behind its source.
    return across * math.cos(half_angle) - along * math.sin(half_angle) <= radius
end

local function Finish(player, channel)
    if channel.finished then return end
    channel.finished = true
    if channel.task ~= nil then channel.task:Cancel(); channel.task = nil end
    if channel.endtask ~= nil then channel.endtask:Cancel(); channel.endtask = nil end
    if channel.fx ~= nil and channel.fx:IsValid() then channel.fx:Remove() end
    if player._krypton_frostbreath_channel == channel then player._krypton_frostbreath_channel = nil end
    player:RemoveEventCallback("onremove", channel.stop)
    player:RemoveEventCallback("death", channel.stop)
end

local function Pulse(player, channel)
    if channel.finished then return end
    if not FrostBreath.CanCast(player) or GetTime() >= channel.ends then
        Finish(player, channel)
        return
    end
    local x, y, z = player.Transform:GetWorldPosition()
    local dx, dz, range = channel.dx, channel.dz, channel.range
    -- Stop a channel when another input turns away. The fixed authoritative
    -- cone must never keep freezing behind a newly turned head.
    if player.Transform.GetRotation ~= nil then
        local angle = player.Transform:GetRotation() * DEGREES
        if math.cos(angle) * dx - math.sin(angle) * dz < 0.7 then
            Finish(player, channel)
            return
        end
    end
    local targets = TheSim:FindEntities(x, y, z, range + 3, nil, QUERY_EXCLUDES)
    for _, target in ipairs(targets) do
        if target:IsValid() and InCone(x, z, dx, dz, target, range, channel.half_angle) then
            -- Extinguishing is also allowed on burning friends and buildings;
            -- protection from freezing must not prevent rescuing them.
            if CanExtinguish(target) then target.components.burnable:Extinguish(true, 0) end
            if target:IsValid() and not channel.hit[target] and CanFreeze(player, target) then
                channel.hit[target] = true
                -- Native coldness preserves resistance, redirects, nofreeze
                -- states and bosses' diminishing returns. Never call Freeze.
                target.components.freezable:AddColdness(channel.coldness, channel.freezetime)
            end
        end
    end
end

function FrostBreath.Cast(player, aim_x, aim_z)
    local tuning = TUNING.KRYPTON_SURVIVOR
    if not TheWorld.ismastersim or tuning.frostbreath_enabled == false
        or not IsFinite(aim_x) or not IsFinite(aim_z) or not FrostBreath.CanCast(player) then
        return false
    end
    local now = GetTime()
    if now < (player._krypton_frostbreath_nextcast or 0) or player._krypton_frostbreath_channel ~= nil then return false end
    local x, y, z = player.Transform:GetWorldPosition()
    local dx, dz = aim_x - x, aim_z - z
    local distance = math.sqrt(dx * dx + dz * dz)
    if not IsFinite(distance) or distance < 0.1 then return false end
    dx, dz = dx / distance, dz / distance

    local duration = tuning.frostbreath_duration or 1
    local channel = {
        dx = dx, dz = dz, range = tuning.frostbreath_range or 8,
        half_angle = (tuning.frostbreath_half_angle or 28) * DEGREES,
        coldness = tuning.frostbreath_coldness or 2, freezetime = tuning.frostbreath_freezetime or 4,
        ends = now + duration, hit = {},
    }
    player._krypton_frostbreath_nextcast = now + math.max(duration, tuning.frostbreath_interval or 1.2)
    player._krypton_frostbreath_channel = channel
    player:ForceFacePoint(x + dx * channel.range, y, z + dz * channel.range)
    if player.SuspendKryptonFlightVisual ~= nil then player:SuspendKryptonFlightVisual(duration + 0.1) end
    channel.fx = SpawnPrefab("krypton_frostbreath_fx")
    if channel.fx ~= nil then channel.fx:SetCaster(player, dx, dz) end
    channel.stop = function() Finish(player, channel) end
    player:ListenForEvent("onremove", channel.stop)
    player:ListenForEvent("death", channel.stop)
    channel.task = player:DoPeriodicTask(0.2, function() Pulse(player, channel) end)
    channel.endtask = player:DoTaskInTime(duration, channel.stop)
    Pulse(player, channel)
    return true
end

return FrostBreath
