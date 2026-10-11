local AMULET_PREFAB = "krypton_starcore_amulet"
local AUTO_REVIVE_DELAY = 0.25
local REVIVE_TIMEOUT = 10

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function CancelTask(self, name)
    local task = self[name]
    if task ~= nil then
        task:Cancel()
        self[name] = nil
    end
end

local function Say(inst, key)
    local strings = STRINGS.KRYPTON_STARCORE
    if strings ~= nil and strings[key] ~= nil and inst.components.talker ~= nil then
        inst.components.talker:Say(strings[key])
    end
end

local function ShardId()
    return TheShard ~= nil and TheShard:GetShardId() or nil
end

local function SafeTemperatureRange(temperature)
    local overheat = IsFinite(temperature.overheattemp) and temperature.overheattemp
        or (IsFinite(TUNING.OVERHEAT_TEMP) and TUNING.OVERHEAT_TEMP or 70)
    -- Clients also compare the replicated temperature with the global limit.
    if IsFinite(TUNING.OVERHEAT_TEMP) then overheat = math.min(overheat, TUNING.OVERHEAT_TEMP) end
    local margin = overheat > 0 and math.min(10, overheat * .5) or 0
    local native_min = IsFinite(temperature.mintemp) and temperature.mintemp or -math.huge
    local native_max = IsFinite(temperature.maxtemp) and temperature.maxtemp or math.huge
    local minimum = math.max(0, native_min)
    local maximum = math.min(native_max, overheat - margin)
    -- An incompatible range imposed by another mod has no safe intersection.
    -- Respect its native bounds instead of inventing an out-of-range value.
    if minimum > maximum then return nil, nil end
    minimum = math.min(maximum, math.max(10, minimum))
    maximum = math.max(minimum, math.min(50, maximum))
    return minimum, maximum
end

local function SafeTemperatureValue(temperature, value)
    if not IsFinite(value) then return value end
    local minimum, maximum = SafeTemperatureRange(temperature)
    return minimum ~= nil and math.max(minimum, math.min(maximum, value)) or value
end

local KryptonStarcore = Class(function(self, inst)
    self.inst = inst
    self.starter_granted = false
    self._on_death = function(_, data) self:OnDeath(data) end
    self._on_ghost = function() self:OnBecameGhost() end
    self._on_request = function() self:OnReviveRequested() end
    self._on_respawn = function() self:OnRespawned() end
    self._on_equipment = function(_, data)
        if data == nil or data.eslot == EQUIPSLOTS.BODY then
            self:SetEquipped(self:GetEquippedAmulet())
        end
    end
    inst:ListenForEvent("death", self._on_death)
    inst:ListenForEvent("ms_becameghost", self._on_ghost)
    inst:ListenForEvent("respawnfromghost", self._on_request)
    inst:ListenForEvent("respawnfromcorpse", self._on_request)
    inst:ListenForEvent("ms_respawnedfromghost", self._on_respawn)
    -- Native item OnEquip runs before Inventory assigns its final body slot.
    -- These owner events run after that assignment/removal, in the same frame.
    inst:ListenForEvent("equip", self._on_equipment)
    inst:ListenForEvent("unequip", self._on_equipment)
end)

function KryptonStarcore:GetEquippedAmulet()
    local inst = self.inst
    local inventory = inst.components.inventory
    local item = inventory ~= nil and inventory:GetEquippedItem(EQUIPSLOTS.BODY) or nil
    local equippable = item ~= nil and item.components.equippable or nil
    return not self._removed and inst:HasTag("kryptonian") and item ~= nil
        and item:IsValid() and item.prefab == AMULET_PREFAB
        and equippable ~= nil and equippable:IsEquipped() and item or nil
end

function KryptonStarcore:IsProtected()
    local inst = self.inst
    local health = inst.components.health
    return self:GetEquippedAmulet() ~= nil and not inst:HasTag("playerghost")
        and not inst:HasTag("corpse") and health ~= nil and not health:IsDead()
end

function KryptonStarcore:GetCooldownRemaining()
    return self._cooldown_end ~= nil and math.max(0, self._cooldown_end - GetTime()) or 0
end

function KryptonStarcore:IsReady()
    return self:GetCooldownRemaining() <= 0
end

function KryptonStarcore:IsAutoReviving()
    return self._inflight == true
end

function KryptonStarcore:MaintainSafeTemperature(temperature)
    if not self:IsProtected() then return end
    local value = SafeTemperatureValue(temperature, temperature.current)
    if value ~= temperature.current then temperature:SetTemperature(value) end
    -- Older game versions expose separate thermal net flags. Current versions
    -- derive them from replicated temperature; never replace that interface.
    local minimum, maximum = SafeTemperatureRange(temperature)
    local classified = self.inst.player_classified
    if classified ~= nil and minimum ~= nil and IsFinite(temperature.current)
        and temperature.current >= minimum and temperature.current <= maximum then
        if classified.isfreezing ~= nil then classified.isfreezing:set(false) end
        if classified.isoverheating ~= nil then classified.isoverheating:set(false) end
    end
end

function KryptonStarcore:InstallTemperatureProtection()
    local temperature = self.inst.components.temperature
    if temperature ~= nil and self._temperature_set_wrapper == nil then
        local previous = temperature.SetTemperature
        local wrapper = function(component, value, ...)
            -- Clamp before the native setter emits transition events. A cold
            -- tick must not briefly announce startfreezing and then undo it.
            if self:IsProtected() then value = SafeTemperatureValue(component, value) end
            return previous(component, value, ...)
        end
        self._temperature_set_component = temperature
        self._temperature_set_previous = previous
        self._temperature_set_wrapper = wrapper
        temperature.SetTemperature = wrapper
    end
    if temperature ~= nil and self._temperature_wrapper == nil then
        local previous = temperature.OnUpdate
        local wrapper = function(component, dt, applyhealthdelta, ...)
            -- Use the native temperature component's existing damage gate.
            -- Its temperature calculation, events and network updates still
            -- run; protection no longer relies on a single health callback
            -- that another mod can replace after this item is equipped.
            if self:IsProtected() then
                self:MaintainSafeTemperature(component)
                applyhealthdelta = false
            end
            return previous(component, dt, applyhealthdelta, ...)
        end
        self._temperature_component = temperature
        self._temperature_previous = previous
        self._temperature_wrapper = wrapper
        temperature.OnUpdate = wrapper
    end
    -- Cover equipment restoration and resurrection immediately, before the
    -- next simulation tick; SetTemp locks belonging to other mods stay intact.
    if temperature ~= nil then self:MaintainSafeTemperature(temperature) end

    local health = self.inst.components.health
    if health == nil or self._delta_wrapper ~= nil then return end
    local previous = health.deltamodifierfn
    local wrapper = function(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        if previous ~= nil then
            amount = previous(inst, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        end
        -- The native temperature component identifies only these two damage
        -- causes. Fire, hunger, attacks and freezing-control effects still work.
        if amount < 0 and (cause == "cold" or cause == "hot") and self:IsProtected() then
            return 0
        end
        return amount
    end
    self._delta_health = health
    self._delta_previous = previous
    self._delta_wrapper = wrapper
    health.deltamodifierfn = wrapper
end

function KryptonStarcore:RemoveTemperatureProtection()
    if self._temperature_set_component ~= nil and self._temperature_set_component.SetTemperature == self._temperature_set_wrapper then
        self._temperature_set_component.SetTemperature = self._temperature_set_previous
    end
    self._temperature_set_component = nil
    self._temperature_set_previous = nil
    self._temperature_set_wrapper = nil
    if self._temperature_component ~= nil and self._temperature_component.OnUpdate == self._temperature_wrapper then
        self._temperature_component.OnUpdate = self._temperature_previous
    end
    self._temperature_component = nil
    self._temperature_previous = nil
    self._temperature_wrapper = nil
    if self._delta_health ~= nil and self._delta_health.deltamodifierfn == self._delta_wrapper then
        self._delta_health.deltamodifierfn = self._delta_previous
    end
    self._delta_health = nil
    self._delta_previous = nil
    self._delta_wrapper = nil
end

function KryptonStarcore:RefreshProtection()
    local item = self:IsProtected() and self:GetEquippedAmulet() or nil
    local moisture = self.inst.components.moisture
    if self._dry_source ~= item then
        if self._dry_source ~= nil and moisture ~= nil then
            moisture:ForceDry(false, self._dry_source)
        end
        self._dry_source = item
        if item ~= nil and moisture ~= nil then moisture:ForceDry(true, item) end
    end
    if item ~= nil then
        self:InstallTemperatureProtection()
    else
        self:RemoveTemperatureProtection()
    end
end

function KryptonStarcore:SetEquipped(item)
    self.amulet = item
    -- Inventory's OnLoad can equip the saved item after this component loads.
    -- Bind that restored entity after all native component loads have finished.
    if self._pending ~= nil and not self._restoring and item ~= self._pending_amulet then
        self:CancelRevive()
    end
    self:RefreshProtection()
end

function KryptonStarcore:CancelRevive()
    CancelTask(self, "_revive_task")
    CancelTask(self, "_timeout_task")
    self._pending = nil
    self._pending_amulet = nil
    self._inflight = nil
end

function KryptonStarcore:OnDeath()
    self:CancelRevive()
    local inst = self.inst
    local item = self:GetEquippedAmulet()
    -- Wilderness deliberately ends this character instead of producing a
    -- ghost/corpse. Keep that game-mode rule rather than replacing its SG.
    if item ~= nil and (inst.ghostenabled ~= false or inst.components.revivablecorpse ~= nil) then
        if self:IsReady() then
            local x, y, z = inst.Transform:GetWorldPosition()
            self._pending = { x = x, y = y, z = z, shard = ShardId() }
            self._pending_amulet = item
        else
            Say(inst, "COOLDOWN")
        end
    end
    self:RefreshProtection()
end

function KryptonStarcore:OnBecameGhost()
    self:RefreshProtection()
    if self._pending == nil or self._inflight then return end
    CancelTask(self, "_revive_task")
    self._revive_task = self.inst:DoTaskInTime(AUTO_REVIVE_DELAY, function()
        self._revive_task = nil
        self:TryRevive()
    end)
end

function KryptonStarcore:TryRevive()
    local inst = self.inst
    local pending = self._pending
    local item = self:GetEquippedAmulet()
    if self._removed or not inst:IsValid() or pending == nil or self._inflight
        or item == nil or item ~= self._pending_amulet or not self:IsReady()
        or inst:HasTag("reviving") or (pending.shard ~= nil and pending.shard ~= ShardId())
        or (not inst:HasTag("playerghost") and not inst:HasTag("corpse")) then
        self:CancelRevive()
        return false
    end

    -- The native custom-source fallback uses reviver_rebirth without consuming
    -- or moving this persistent item. Move only this player to the recorded
    -- death position, then let native resurrection restore all player systems.
    inst.Physics:Teleport(pending.x, pending.y, pending.z)
    self._inflight = true
    self._timeout_task = inst:DoTaskInTime(REVIVE_TIMEOUT, function()
        self._timeout_task = nil
        self:CancelRevive()
    end)
    self._dispatching = true
    inst:PushEvent(inst:HasTag("corpse") and "respawnfromcorpse" or "respawnfromghost", { source = item })
    self._dispatching = nil
    return true
end

function KryptonStarcore:OnReviveRequested()
    -- A heart, touch stone or another mod may beat the scheduled auto revive.
    -- Its success must not spend the starcore's personal cooldown.
    if not self._dispatching then self:CancelRevive() end
end

function KryptonStarcore:SetCooldownRemaining(seconds)
    CancelTask(self, "_cooldown_task")
    seconds = IsFinite(seconds) and math.max(0, seconds) or 0
    self._cooldown_end = seconds > 0 and GetTime() + seconds or nil
    if seconds > 0 then
        self._cooldown_task = self.inst:DoTaskInTime(seconds, function()
            self._cooldown_task = nil
            self._cooldown_end = nil
            if self:IsProtected() then Say(self.inst, "READY") end
        end)
    end
end

function KryptonStarcore:OnRespawned()
    local ours = self._inflight == true
    self:CancelRevive()
    self:RefreshProtection()
    local health = self.inst.components.health
    if ours and not self.inst:HasTag("playerghost") and not self.inst:HasTag("corpse")
        and health ~= nil and not health:IsDead() then
        -- Use the native penalty-aware maximum; do not change max-health
        -- penalties or overwrite the native hunger/sanity revival behavior.
        if health.SetPercent ~= nil then health:SetPercent(1) end
        local tuning = TUNING.KRYPTON_SURVIVOR
        self:SetCooldownRemaining(tuning ~= nil and tuning.starcore_revive_cooldown or TUNING.TOTAL_DAY_TIME)
        self.inst:DoTaskInTime(3.5, function()
            if self.inst:IsValid() and self:IsProtected() then Say(self.inst, "REVIVED") end
        end)
    end
end

function KryptonStarcore:OnSave()
    return {
        starter_granted = self.starter_granted or nil,
        cooldown_remaining = self:GetCooldownRemaining(),
        pending = self._pending,
    }
end

function KryptonStarcore:OnLoad(data)
    if data == nil then return end
    self:CancelRevive()
    CancelTask(self, "_load_task")
    self.starter_granted = data.starter_granted == true
    self:SetCooldownRemaining(data.cooldown_remaining)
    local pending = data.pending
    if type(pending) == "table" and IsFinite(pending.x) and IsFinite(pending.y) and IsFinite(pending.z)
        and (pending.shard == nil or type(pending.shard) == "string") then
        self._pending = { x = pending.x, y = pending.y, z = pending.z, shard = pending.shard }
    end
    self._restoring = true
    -- Inventory and native ghost state can load in either component order.
    self._load_task = self.inst:DoTaskInTime(0, function()
        self._load_task = nil
        self._restoring = nil
        self.amulet = self:GetEquippedAmulet()
        self:RefreshProtection()
        if self._pending ~= nil then
            self._pending_amulet = self.amulet
            if self.inst:HasTag("playerghost") or self.inst:HasTag("corpse") then
                self:OnBecameGhost()
            end
        end
    end)
end

function KryptonStarcore:LongUpdate(dt)
    local remaining = self:GetCooldownRemaining()
    if remaining > 0 and IsFinite(dt) and dt > 0 then
        self:SetCooldownRemaining(math.max(0, remaining - dt))
    end
end

function KryptonStarcore:TransferComponent(newinst)
    local component = newinst.components.krypton_starcore
    if component ~= nil then component:OnLoad(self:OnSave()) end
end

function KryptonStarcore:OnRemoveFromEntity()
    self._removed = true
    self._restoring = nil
    self:CancelRevive()
    CancelTask(self, "_load_task")
    CancelTask(self, "_cooldown_task")
    self:RefreshProtection()
    self.inst:RemoveEventCallback("death", self._on_death)
    self.inst:RemoveEventCallback("ms_becameghost", self._on_ghost)
    self.inst:RemoveEventCallback("respawnfromghost", self._on_request)
    self.inst:RemoveEventCallback("respawnfromcorpse", self._on_request)
    self.inst:RemoveEventCallback("ms_respawnedfromghost", self._on_respawn)
    self.inst:RemoveEventCallback("equip", self._on_equipment)
    self.inst:RemoveEventCallback("unequip", self._on_equipment)
end

return KryptonStarcore
