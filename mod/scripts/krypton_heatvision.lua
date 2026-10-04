local HeatVision = {}

local EXCLUDE_TAGS = {
    "INLIMBO", "player", "playerghost", "companion", "wall", "structure",
    "FX", "notarget", "invisible", "player_aligned", "domesticated",
}

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function HeatVision.CanCast(player)
    if TheNet:IsServerPaused() or player == nil or not player:IsValid() or player.prefab ~= "krypton_survivor"
        or not player:HasTag("kryptonian") or player:HasTag("playerghost")
        or player.components.health == nil or player.components.health:IsDead()
        or player.components.combat == nil then
        return false
    end
    local controller = player.components.playercontroller
    return controller ~= nil and controller:IsEnabled() and not controller:IsBusy()
        and not controller:IsDoingOrWorking()
end

local function IsProtected(target)
    for _, tag in ipairs(EXCLUDE_TAGS) do
        if target:HasTag(tag) then return true end
    end
    return target.components.follower ~= nil and target.components.follower.leader ~= nil
end

function HeatVision.Cast(player, aim_x, aim_z)
    -- Clients send only an aim point. The server owns range, damage and targets.
    if not TheWorld.ismastersim or not IsFinite(aim_x) or not IsFinite(aim_z)
        or not HeatVision.CanCast(player) then
        return false
    end
    local now = GetTime()
    if now < (player._krypton_heatvision_nextcast or 0) then return false end

    local x, y, z = player.Transform:GetWorldPosition()
    local dx, dz = aim_x - x, aim_z - z
    local distance = math.sqrt(dx * dx + dz * dz)
    -- Very large coordinates can overflow even when each input is finite.
    if not IsFinite(distance) or distance < 0.1 then return false end
    dx, dz = dx / distance, dz / distance

    local tuning = TUNING.KRYPTON_SURVIVOR
    player._krypton_heatvision_nextcast = now + tuning.heatvision_interval
    local range, width = tuning.heatvision_range, tuning.heatvision_width
    local mid_x, mid_z = x + dx * range / 2, z + dz * range / 2
    player:ForceFacePoint(x + dx * range, y, z + dz * range)

    -- Clients resolve their own animated eye positions from this shared cast.
    local fx = SpawnPrefab("krypton_heatvision_fx")
    if fx ~= nil then fx:SetCaster(player, dx, dz) end

    -- Padding includes large creatures whose body intersects the beam.
    local targets = TheSim:FindEntities(mid_x, y, mid_z, range / 2 + width + 3, { "_combat" }, EXCLUDE_TAGS)
    for _, target in ipairs(targets) do
        if target ~= player and target:IsValid() and not IsProtected(target)
            and target.components.health ~= nil and not target.components.health:IsDead()
            and target.components.combat ~= nil and player.components.combat:CanTarget(target) then
            local tx, ty, tz = target.Transform:GetWorldPosition()
            local offset_x, offset_z = tx - x, tz - z
            local along = offset_x * dx + offset_z * dz
            local across = offset_x * dz - offset_z * dx
            local radius = width + target:GetPhysicsRadius(0)
            local past_end = math.max(0, along - range)
            if along >= 0 and past_end * past_end + across * across <= radius * radius then
                target.components.combat:GetAttacked(player, tuning.heatvision_damage, nil, "fire")
                -- Do not ignite corpses or fire-immune targets; native fire may spread.
                if target:IsValid() and target.components.health ~= nil and not target.components.health:IsDead()
                    and target.components.burnable ~= nil and not target:HasTag("fireimmune") then
                    target.components.burnable:Ignite(true, player, player)
                end
            end
        end
    end
    return true
end

return HeatVision
