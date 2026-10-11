local Starter = {}

-- Give each existing survivor one migration item. The saved component flag
-- prevents intentionally dropped/lost amulets from being recreated on reload.
function Starter.Ensure(inst)
    local core = inst.components.krypton_starcore
    local inventory = inst.components.inventory
    if core == nil or inventory == nil or core.starter_granted
        or inst:HasTag("playerghost") or inst:HasTag("corpse") or inst.components.health:IsDead() then
        return
    end
    local body = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    local amulet = body ~= nil and body.prefab == "krypton_starcore_amulet" and body
        or inventory:FindItem(function(item) return item.prefab == "krypton_starcore_amulet" end)
    if amulet == nil then
        amulet = SpawnPrefab("krypton_starcore_amulet")
        if amulet == nil then return end
        -- The native inventory drops the gift nearby if there is no room.
        inventory:GiveItem(amulet, nil, inst:GetPosition())
    end
    core.starter_granted = true
    if body == nil and amulet.components.inventoryitem.owner == inst then
        inventory:Equip(amulet)
    end
end

return Starter
