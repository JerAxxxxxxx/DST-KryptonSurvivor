local Flight = require("krypton_flight")
require("componentutil")

local Teleport = {}
local EXCLUDE_TAGS = { "INLIMBO", "FX", "DECOR" }

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function IsRiding(player)
    local rider = player.components.rider
    return rider ~= nil and rider:IsRiding()
end

function Teleport.CanCast(player)
    if not TheWorld.ismastersim
        or player == nil or not player:IsValid() or player.prefab ~= "krypton_survivor"
        or not player:HasTag("kryptonian") or player:HasTag("playerghost")
        or player.components.health == nil or player.components.health:IsDead()
        or player.Physics == nil or player.components.locomotor == nil then
        return false, "unavailable"
    end
    if TUNING.KRYPTON_SURVIVOR.map_teleport_enabled == false then return false, "disabled" end
    if TheNet:IsServerPaused() then return false, "paused" end
    if IsRiding(player) then return false, "riding" end
    local controller = player.components.playercontroller
    -- IsEnabled also reads the host's HUD focus. Authorize against the actual
    -- server control flag so map requests behave the same on hosts and clients.
    local classified = controller ~= nil and controller.classified or nil
    if classified == nil or classified.iscontrollerenabled == nil
        or not classified.iscontrollerenabled:value() then
        return false, "controls_disabled"
    end
    if player:HasTag("busy") or controller:IsBusy() or controller:IsDoingOrWorking()
        or (player.sg ~= nil and player.sg:HasAnyStateTag("busy", "jumping", "nointerrupt")) then
        return false, "busy"
    end
    return true
end

local function IsOccupied(player, x, z, radius)
    local group = player.Physics:GetCollisionGroup()
    local mount = player.components.rider ~= nil and player.components.rider:GetMount() or nil
    for _, entity in ipairs(TheSim:FindEntities(x, 0, z, radius + MAX_PHYSICS_RADIUS, nil, EXCLUDE_TAGS)) do
        if entity ~= player and entity ~= mount and entity:IsValid() and entity.Physics ~= nil
            and entity.Physics:IsActive() and checkbit(entity.Physics:GetCollisionMask(), group) then
            local ex, ey, ez = entity.Transform:GetWorldPosition()
            local combined = radius + entity:GetPhysicsRadius(0)
            if (x - ex) ^ 2 + (z - ez) ^ 2 < combined ^ 2 then return true end
        end
    end
    return false
end

local function CheckDestination(player, x, z)
    local map = TheWorld.Map
    local width, height = map:GetSize()
    if math.abs(x) >= width * TILE_SCALE / 2 or math.abs(z) >= height * TILE_SCALE / 2 then
        return false, "invalid_ground"
    end
    if not map:IsInMapBounds(x, 0, z) then return false, "invalid_ground" end

    -- Flight may land over real ocean, but never teleport into cave VOID.
    local allow_ocean = Flight.IsFlying(player)
    if not map:IsPassableAtPoint(x, 0, z, allow_ocean) then return false, "invalid_ground" end

    local platform = map:GetPlatformAtPoint(x, z)
    local radius = player:GetPhysicsRadius(0.5)
    if platform ~= nil then
        local locomotor = player.components.locomotor
        if not locomotor:IsValidDestinationPlatform(player:GetCurrentPlatform(), platform) then
            return false, "blocked"
        end
        local px, py, pz = platform.Transform:GetWorldPosition()
        local usable = platform.components.walkableplatform.platform_radius - radius - 0.5
        if usable <= 0 or (x - px) ^ 2 + (z - pz) ^ 2 > usable ^ 2 then return false, "blocked" end
    end

    if map:IsGroundTargetBlocked(Vector3(x, 0, z), radius)
        or not TheWorld.Pathfinder:IsClear(x, 0, z, x, 0, z,
            { ignorewalls = false, ignorecreep = true, allowocean = allow_ocean or platform ~= nil })
        or IsOccupied(player, x, z, radius) then
        return false, "blocked"
    end
    local sx, sy, sz = player.Transform:GetWorldPosition()
    if not IsTeleportingPermittedFromPointToPoint(sx, sy, sz, x, 0, z) then
        return false, "restricted"
    end
    return true
end

function Teleport.Cast(player, x, z)
    -- Never accept a position from client prediction as an actual teleport.
    if not IsFinite(x) or not IsFinite(z) then return false, "unavailable" end
    local allowed, reason = Teleport.CanCast(player)
    if not allowed then return false, reason end
    local now = GetTime()
    if now < (player._krypton_teleport_nextcast or 0) then return false, "cooldown" end
    player._krypton_teleport_nextcast = now + TUNING.KRYPTON_SURVIVOR.map_teleport_interval
    local safe, reason = CheckDestination(player, x, z)
    if not safe then return false, reason end

    local controller = player.components.playercontroller
    controller:ResetRemoteController()
    controller:ClearRemotePredictData(true)
    player:ClearBufferedAction()
    player.components.locomotor:Stop()
    controller:RemotePausePrediction(3)
    player.Physics:Teleport(x, 0, z)
    if player.components.areaaware ~= nil then player.components.areaaware:UpdatePosition(x, 0, z) end
    player:PushEvent("teleported")
    player:SnapCamera()
    return true
end

return Teleport
