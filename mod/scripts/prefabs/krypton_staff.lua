local Targets = require("krypton_combat_targets")
local assets = {
    Asset("ANIM", "anim/cane.zip"),
    Asset("ANIM", "anim/krypton_staff_build.zip"),
    Asset("ATLAS", "images/inventoryimages/krypton_staff.xml"),
    Asset("IMAGE", "images/inventoryimages/krypton_staff.tex"),
}

local function OnAttack(inst, attacker, target)
    local radius = TUNING.KRYPTON_SURVIVOR.staff_aoe_radius
    -- Zero disables only splash damage; native primary melee still applies.
    if radius <= 0 or target == nil or not target:IsValid() then return end
    local x, y, z = target.Transform:GetWorldPosition()
    local victims = TheSim:FindEntities(x, y, z, radius,
        { "_combat" }, Targets.EXCLUDE_TAGS)
    for _, victim in ipairs(victims) do
        if victim ~= target and victim ~= attacker and victim:IsValid() and not Targets.IsProtected(victim)
            and victim.components.combat ~= nil and victim.components.health ~= nil
            and not victim.components.health:IsDead()
            and attacker.components.combat:CanTarget(victim) then
            victim.components.combat:GetAttacked(attacker, TUNING.KRYPTON_SURVIVOR.staff_damage, inst)
        end
    end
end

local function UpdateLight(inst)
    local owner = inst.components.inventoryitem.owner
    local equipped = inst.components.equippable:IsEquipped()
    inst.Light:Enable(equipped and owner ~= nil and not owner:HasTag("playerghost")
        and (TheWorld.state.isnight or TheWorld:HasTag("cave")))
end

local function OnEquip(inst, owner)
    owner.AnimState:OverrideSymbol("swap_object", "krypton_staff_build", "swap_cane")
    owner.AnimState:Show("ARM_carry")
    owner.AnimState:Hide("ARM_normal")
    UpdateLight(inst)
end

local function OnUnequip(inst, owner)
    owner.AnimState:Hide("ARM_carry")
    owner.AnimState:Show("ARM_normal")
    inst.Light:Enable(false)
end

local function OnPutInInventory(inst, owner)
    if owner:HasTag("player") and not owner:HasTag("kryptonian") then
        -- Defer until GiveItem has finished inserting the item into its slot.
        inst:DoTaskInTime(0, function(item)
            if item.components.inventoryitem.owner == owner and owner:IsValid()
                and owner.components.inventory ~= nil then
                owner.components.inventory:DropItem(item, true, true)
            end
        end)
    end
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddLight()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("cane")
    inst.AnimState:SetBuild("krypton_staff_build")
    inst.AnimState:PlayAnimation("idle")
    inst:AddTag("weapon")
    inst:AddTag("tool")
    inst:AddTag("sharp")
    -- Client action picking needs these tags before SetPristine.
    inst:AddTag("CHOP_tool")
    inst:AddTag("MINE_tool")
    inst:AddTag("HAMMER_tool")
    inst:AddTag("DIG_tool")

    inst.Light:SetRadius(4)
    inst.Light:SetFalloff(0.7)
    inst.Light:SetIntensity(0.8)
    inst.Light:SetColour(1, 0.85, 0.45)
    inst.Light:Enable(false)
    MakeInventoryFloatable(inst, "med", 0.05, { 0.85, 0.45, 0.85 }, true, 1, { sym_build = "krypton_staff_build" })
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/krypton_staff.xml"
    inst.components.inventoryitem:ChangeImageName("krypton_staff")
    inst.components.inventoryitem:SetOnPutInInventoryFn(OnPutInInventory)

    inst:AddComponent("equippable")
    inst.components.equippable.restrictedtag = "kryptonian"
    inst.components.equippable:SetOnEquip(OnEquip)
    inst.components.equippable:SetOnUnequip(OnUnequip)

    inst:AddComponent("weapon")
    inst.components.weapon:SetDamage(TUNING.KRYPTON_SURVIVOR.staff_damage)
    inst.components.weapon:SetRange(TUNING.KRYPTON_SURVIVOR.staff_range, TUNING.KRYPTON_SURVIVOR.staff_range + 2)
    inst.components.weapon:SetOnAttack(OnAttack)
    inst:AddComponent("tool")
    inst.components.tool:SetAction(ACTIONS.CHOP, TUNING.KRYPTON_SURVIVOR.work_efficiency)
    inst.components.tool:SetAction(ACTIONS.MINE, TUNING.KRYPTON_SURVIVOR.work_efficiency)
    inst.components.tool:SetAction(ACTIONS.HAMMER, TUNING.KRYPTON_SURVIVOR.work_efficiency)
    inst.components.tool:SetAction(ACTIONS.DIG, TUNING.KRYPTON_SURVIVOR.work_efficiency)
    inst.components.tool:EnableToughWork(true)
    -- No finiteuses or fueled component: combat, work and light consume nothing.
    inst:WatchWorldState("isnight", UpdateLight)
    inst:ListenForEvent("ondropped", function() inst.Light:Enable(false) end)
    MakeHauntableLaunch(inst)
    return inst
end

return Prefab("krypton_staff", fn, assets)
