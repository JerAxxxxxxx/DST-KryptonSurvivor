local DIRTY_EVENT = "krypton_darkformdirty"

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function Percent(value, fallback)
    return IsFinite(value) and math.max(0, math.min(1, value)) or fallback
end

local function CancelTask(self, name)
    if self[name] ~= nil then self[name]:Cancel(); self[name] = nil end
end

local KryptonDarkform = Class(function(self, inst)
    self.inst = inst
    self.dark = false
    self._on_sanity = function() self:QueueMaintain() end
    self._on_respawn = function() self:QueueMaintain() end
    self._on_death = function() CancelTask(self, "_pending") end
    self._on_remove = function() self:OnRemoveFromEntity() end
    inst:ListenForEvent("sanitydelta", self._on_sanity)
    inst:ListenForEvent("ms_respawnedfromghost", self._on_respawn)
    inst:ListenForEvent("respawnfromcorpse", self._on_respawn)
    inst:ListenForEvent("death", self._on_death)
    inst:ListenForEvent("ms_becameghost", self._on_death)
    inst:ListenForEvent("onremove", self._on_remove)
end)

function KryptonDarkform:IsDark()
    return not self._removed and self.dark == true
end

function KryptonDarkform:GetNormalSanityPercent()
    return self.normal_percent
end

function KryptonDarkform:CanMaintain()
    local inst = self.inst
    local health = inst.components.health
    return not self._removed and TheWorld.ismastersim and inst:IsValid()
        and not inst:HasTag("playerghost") and not inst:HasTag("corpse")
        and health ~= nil and not health:IsDead() and inst.components.sanity ~= nil
end

function KryptonDarkform:Publish()
    local variable = self.inst._krypton_dark_form
    if variable ~= nil and variable:value() ~= self.dark then variable:set(self.dark) end
    -- A host reads the authoritative value immediately; remote peers receive
    -- the native netvar dirty event. Neither path predicts a form change.
    self.inst:PushEvent(DIRTY_EVENT)
end

function KryptonDarkform:TargetPercent()
    local sanity = self.inst.components.sanity
    local requested = Percent(TUNING.KRYPTON_SURVIVOR.darkform_sanity_percent, .05)
    -- Respect native effective maximum sanity without changing any penalty.
    return math.min(requested, math.max(0, 1 - sanity:GetPenaltyPercent()))
end

function KryptonDarkform:Maintain()
    if not self:IsDark() or not self:CanMaintain() or self._maintaining then return end
    local sanity = self.inst.components.sanity
    local target = self:TargetPercent()
    if math.abs(sanity:GetRealPercent() - target) <= .000001 then return end
    self._maintaining = true
    -- Native SetPercent -> DoDelta preserves replication, transition events,
    -- redirect/ignore behavior and all other mods' induced/lunacy sources.
    sanity:SetPercent(target, true)
    self._maintaining = false
end

function KryptonDarkform:QueueMaintain()
    if not self:IsDark() or self._maintaining or self._pending ~= nil then return end
    self._pending = self.inst:DoTaskInTime(0, function()
        self._pending = nil
        self:Maintain()
    end)
end

function KryptonDarkform:StartMaintaining()
    if self._periodic == nil then
        self._periodic = self.inst:DoPeriodicTask(1, function() self:Maintain() end)
    end
end

function KryptonDarkform:SetDark(value)
    value = value == true
    if self._removed or not TheWorld.ismastersim then return false end
    if self.dark == value then return true end
    if value and not self:CanMaintain() then return false end
    local sanity = self.inst.components.sanity
    if value then
        -- GetPercent can be forced to zero or one by another effect. Save the
        -- real stored sanity instead, so leaving does not copy that illusion.
        self.normal_percent = Percent(sanity:GetRealPercent(), 1)
        self.dark = true
        self:Maintain()
        self:StartMaintaining()
    else
        self.dark = false
        CancelTask(self, "_pending")
        CancelTask(self, "_periodic")
        if self:CanMaintain() then sanity:SetPercent(Percent(self.normal_percent, 1), true) end
        self.normal_percent = nil
    end
    self:Publish()
    return true
end

function KryptonDarkform:OnSave()
    return self.dark and { dark = true, normal_percent = Percent(self.normal_percent, 1) } or nil
end

function KryptonDarkform:OnLoad(data)
    if self._removed or not TheWorld.ismastersim then return end
    CancelTask(self, "_pending")
    CancelTask(self, "_periodic")
    self.dark = data ~= nil and data.dark == true
    self.normal_percent = self.dark and Percent(data.normal_percent, 1) or nil
    self:Publish()
    if self.dark then
        -- All native component loads, including sanity and health, finish
        -- before this task. Never overwrite a later native OnLoad value.
        self:QueueMaintain()
        self:StartMaintaining()
    end
end

function KryptonDarkform:OnRemoveFromEntity()
    if self._removed then return end
    self._removed = true
    self.dark = false
    CancelTask(self, "_pending")
    CancelTask(self, "_periodic")
    local inst = self.inst
    inst:RemoveEventCallback("sanitydelta", self._on_sanity)
    inst:RemoveEventCallback("ms_respawnedfromghost", self._on_respawn)
    inst:RemoveEventCallback("respawnfromcorpse", self._on_respawn)
    inst:RemoveEventCallback("death", self._on_death)
    inst:RemoveEventCallback("ms_becameghost", self._on_death)
    inst:RemoveEventCallback("onremove", self._on_remove)
    -- Explicit component removal may leave the character alive. Do not leave
    -- a stale replicated flag suppressing its normal daylight recovery.
    if inst:IsValid() then self:Publish() end
end

return KryptonDarkform
