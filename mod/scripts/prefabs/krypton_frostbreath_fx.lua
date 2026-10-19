local Mouth = require("krypton_frostbreath_visual_data")
local HeadVisual = require("krypton_frostbreath_head_visual")
local assets = { Asset("ANIM", "anim/deer_ice_flakes.zip"), Asset("ANIM", "anim/krypton_frostbreath_head.zip") }
local prefabs = { "frostbreath" }
local PARTICLE_LIFETIME = 0.65

local function Clear(inst, interrupted)
    if inst._head_caster ~= nil then
        HeadVisual.Clear(inst._head_caster, inst, interrupted)
        inst._head_caster = nil
    end
    if inst._mist ~= nil then inst._mist:Remove(); inst._mist = nil end
    if inst._flakes ~= nil then
        for _, flake in ipairs(inst._flakes) do flake.fx:Remove() end
        inst._flakes = nil
    end
    inst._lastemit = nil
end

local function GetMouth(inst, caster)
    caster.AnimState:MakeFacingDirty()
    local facing = caster.AnimState:GetCurrentFacing()
    local pose = (facing == FACING_RIGHT or facing == FACING_LEFT) and "side"
        or ((facing == FACING_UP or facing == FACING_UPRIGHT or facing == FACING_UPLEFT) and "back" or "front")
    local active, mouth = HeadVisual.Apply(caster, inst, pose, inst._started:value())
    if not active then return end
    inst._head_caster = caster
    mouth = mouth or Mouth[pose].mouth
    local x, y, z, found = caster.AnimState:GetSymbolPosition("headbase", mouth[1], mouth[2], 0)
    if not found then x, y, z, found = caster.AnimState:GetSymbolPosition("headbase_hat", mouth[1], mouth[2], 0) end
    if found then return x, y, z end
end

local function CreateFlake()
    local fx = CreateEntity()
    fx.entity:AddTransform()
    fx.entity:AddAnimState()
    fx.entity:SetCanSleep(false)
    fx:AddTag("FX")
    fx:AddTag("NOCLICK")
    fx.persists = false
    fx.AnimState:SetBank("deer_ice_flakes")
    fx.AnimState:SetBuild("deer_ice_flakes")
    fx.AnimState:PlayAnimation("loop", true)
    fx.AnimState:SetLightOverride(1)
    fx.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    fx.AnimState:SetFinalOffset(2)
    return fx
end

local function Update(inst)
    if inst._sleeping then return end
    local caster = inst._caster:value()
    if caster == nil or not caster:IsValid() or caster:HasTag("playerghost") or caster:HasTag("busy") then
        Clear(inst, caster ~= nil)
        return
    end
    if inst._head_caster ~= nil and inst._head_caster ~= caster then
        HeadVisual.Clear(inst._head_caster, inst, true)
        inst._head_caster = nil
    end
    if inst._pose_caster ~= caster then
        inst._pose_caster = caster
        if caster.SuspendKryptonFlightVisual ~= nil then
            caster:SuspendKryptonFlightVisual((TUNING.KRYPTON_SURVIVOR.frostbreath_duration or 1) + 0.1)
        end
    end
    local angle = inst._angle:value() * DEGREES
    local dx, dz = math.cos(angle), -math.sin(angle)
    if caster.Transform.GetRotation ~= nil then
        local facing = caster.Transform:GetRotation() * DEGREES
        if math.cos(facing) * dx - math.sin(facing) * dz < 0.7 then Clear(inst, true); return end
    end
    local x, y, z = GetMouth(inst, caster)
    if x == nil then Clear(inst); return end
    if inst._mist == nil then
        -- The installed game's non-networked frostbreath supplies its particle
        -- texture, shader and envelopes. Only emission vectors are changed.
        inst._mist = SpawnPrefab("frostbreath")
        if inst._mist ~= nil then inst._mist.entity:SetCanSleep(false) end
    end
    if inst._flakes == nil then
        inst._flakes = {}
        for index = 1, 8 do
            inst._flakes[index] = { fx = CreateFlake(), phase = (index - 1) / 8, lane = ((index - 1) % 3 - 1) * 0.65 }
        end
    end
    local now = GetTime()
    local tuning = TUNING.KRYPTON_SURVIVOR
    local range = tuning.frostbreath_range or 8
    local half_angle = (tuning.frostbreath_half_angle or 28) * DEGREES
    if inst._mist ~= nil then
        inst._mist.Transform:SetPosition(x, y, z)
        if inst._mist.VFXEffect ~= nil and (inst._lastemit == nil or now - inst._lastemit >= FRAMES) then
            inst._lastemit = now
            for _ = 1, 2 do
                local ray = angle + (math.random() * 2 - 1) * half_angle
                local speed = range / PARTICLE_LIFETIME * FRAMES
                inst._mist.VFXEffect:AddRotatingParticleUV(0, PARTICLE_LIFETIME,
                    0, 0, 0, math.cos(ray) * speed, -0.003, -math.sin(ray) * speed,
                    math.random() * 360, math.random() * 2 - 1, 0, 0)
            end
        end
    end
    for _, flake in ipairs(inst._flakes or {}) do
        local phase = (now / PARTICLE_LIFETIME + flake.phase) % 1
        local forward = phase * range
        local lateral = math.tan(half_angle) * forward * flake.lane
        flake.fx.Transform:SetPosition(x + dx * forward - dz * lateral, y - 0.3 * phase, z + dz * forward + dx * lateral)
        local scale = 0.12 + phase * 0.22
        flake.fx.AnimState:SetScale(scale, scale)
        flake.fx.AnimState:SetMultColour(0.68, 0.9, 1, math.sin(phase * math.pi) * 0.65)
    end
end

local function SetCaster(inst, caster, dx, dz)
    inst._started:set(GetTime())
    inst._angle:set(math.atan2(-dz, dx) * RADIANS)
    inst._caster:set(caster)
    inst.entity:SetParent(caster.entity)
    inst.Transform:SetPosition(0, 0, 0)
    if not TheNet:IsDedicated() then Update(inst) end
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    inst:AddTag("FX")
    inst:AddTag("NOCLICK")
    inst:AddTag("NOBLOCK")
    inst.persists = false
    inst._caster = net_entity(inst.GUID, "krypton_frostbreath.caster")
    inst._angle = net_float(inst.GUID, "krypton_frostbreath.angle")
    inst._started = net_float(inst.GUID, "krypton_frostbreath.started")
    if not TheNet:IsDedicated() then
        inst:AddComponent("updatelooper")
        inst.components.updatelooper:AddPostUpdateFn(Update)
        inst.OnEntitySleep = function(self) self._sleeping = true; Clear(self) end
        inst.OnEntityWake = function(self) self._sleeping = false; Update(self) end
        inst.OnRemoveEntity = Clear
    end
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst.SetCaster = SetCaster
    inst.SoundEmitter:PlaySound("dontstarve/creatures/together/deer/fx/steam_LP", "frostbreath", 0.25)
    inst:DoTaskInTime(TUNING.KRYPTON_SURVIVOR.frostbreath_duration or 1, inst.Remove)
    return inst
end

return Prefab("krypton_frostbreath_fx", fn, assets, prefabs)
