-- Mode changes are requested by the owning client and decided by the server.
return function(G, key, send)
    if key == nil or G.TheNet:IsDedicated() then return end
    local next_toggle = 0
    G.TheInput:AddKeyDownHandler(key, function()
        local player = G.ThePlayer
        if player == nil or not player:IsValid() or player.prefab ~= "krypton_survivor"
            or player:HasTag("playerghost") or player:HasTag("corpse") or player:HasTag("busy")
            or player.HUD == nil or player.HUD:HasInputFocus()
            or G.IsPaused() or G.TheNet:IsServerPaused()
            or G.TheInput:GetHUDEntityUnderMouse() ~= nil then return end
        local health = player.components.health or (player.replica ~= nil and player.replica.health)
        if health ~= nil and health:IsDead() then return end
        -- Use the same shortcut policy as heat vision and frost breath; a
        -- modifier flag alone does not mean an interface owns the input.
        local controller = player.components.playercontroller
        if controller == nil or not controller:IsEnabled() or controller:IsBusy()
            or controller:IsDoingOrWorking() or controller.placer ~= nil then return end
        local now = G.GetTime()
        if now >= next_toggle then
            next_toggle = now + (G.TUNING.KRYPTON_SURVIVOR.darkform_toggle_interval or .35)
            send()
        end
    end)
end
