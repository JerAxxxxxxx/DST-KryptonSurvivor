local assets = {
    Asset("ANIM", "anim/wagdrone_laserwire_fx.zip"),
    Asset("ANIM", "anim/bishop_attack.zip"),
}
local Visual = require("krypton_heatvision_visual")

local function SetCaster(inst, caster, dx, dz)
    inst._angle:set(math.atan2(-dz, dx) * RADIANS)
    inst._caster:set(caster)
    inst.entity:SetParent(caster.entity)
    inst.Transform:SetPosition(0, 0, 0)
    if not TheNet:IsDedicated() then Visual.Update(inst) end
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

    inst._caster = net_entity(inst.GUID, "krypton_heatvision.caster")
    inst._angle = net_float(inst.GUID, "krypton_heatvision.angle")
    if not TheNet:IsDedicated() then Visual.Init(inst) end

    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst.SetCaster = SetCaster
    inst.SoundEmitter:PlaySound("rifts5/wagdrone_rolling/beamlp_a", "beam", 0.3)
    inst:DoTaskInTime(0.3, inst.Remove)
    return inst
end

return Prefab("krypton_heatvision_fx", fn, assets)
