local assets = {
    Asset("ANIM", "anim/amulets.zip"),
    Asset("ANIM", "anim/krypton_starcore_build.zip"),
    Asset("ATLAS", "images/inventoryimages/krypton_starcore_amulet.xml"),
    Asset("IMAGE", "images/inventoryimages/krypton_starcore_amulet.tex"),
}

local function OnEquip(inst, owner)
    if owner.components.krypton_starcore ~= nil then
        owner.components.krypton_starcore:SetEquipped(inst)
    end
end

local function OnUnequip(inst, owner)
    local component = owner.components.krypton_starcore
    if component ~= nil and component.amulet == inst then component:SetEquipped(nil) end
end

local function GetStatus(inst)
    local owner = inst.components.inventoryitem.owner
    local component = owner ~= nil and owner.components.krypton_starcore or nil
    return component ~= nil and not component:IsReady() and "COOLDOWN" or nil
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)

    -- Native animation is loaded from the user's game; our build contains only
    -- the supplied artwork's extracted starcore, never the native art/anim data.
    inst.AnimState:SetBank("amulets")
    inst.AnimState:SetBuild("krypton_starcore_build")
    inst.AnimState:PlayAnimation("redamulet")
    inst.foleysound = "dontstarve/movement/foley/jewlery"
    MakeInventoryFloatable(inst, "med", nil, 0.6)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst:AddComponent("inspectable")
    inst.components.inspectable.getstatus = GetStatus
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages/krypton_starcore_amulet.xml"
    inst.components.inventoryitem:ChangeImageName("krypton_starcore_amulet")
    -- SG death drops equipment before our player's death listener executes.
    -- This also keeps the same amulet available for automatic native revival.
    inst.components.inventoryitem.keepondeath = true

    inst:AddComponent("equippable")
    inst.components.equippable.equipslot = EQUIPSLOTS.BODY
    inst.components.equippable.restrictedtag = "kryptonian"
    inst.components.equippable:SetOnEquip(OnEquip)
    inst.components.equippable:SetOnUnequip(OnUnequip)
    -- Do not override swap_body: the survivor keeps their authoritative outfit.
    -- No fueled, finiteuses or haunt resurrection: cooldown belongs to player.
    MakeHauntableLaunch(inst)
    return inst
end

return Prefab("krypton_starcore_amulet", fn, assets)
