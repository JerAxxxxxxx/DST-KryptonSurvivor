-- Register one keyboard handler per client, never on a dedicated server.
return function(G, key, send)
    if key == nil or G.TheNet:IsDedicated() then return end
    local next_cast = 0
    G.TheInput:AddKeyDownHandler(key, function()
        local player = G.ThePlayer
        if player == nil or not player:IsValid() or player.prefab ~= "krypton_survivor"
            or player:HasTag("playerghost") or player:HasTag("busy") or player.HUD == nil
            or player.HUD:HasInputFocus() or G.IsPaused() or G.TheNet:IsServerPaused()
            or G.TheInput:GetHUDEntityUnderMouse() ~= nil then
            return
        end
        local controller = player.components.playercontroller
        if controller == nil or not controller:IsEnabled() or controller:IsBusy()
            or controller:IsDoingOrWorking() or controller.placer ~= nil then return end
        local position = G.TheInput:GetWorldPosition()
        local now = G.GetTime()
        if position ~= nil and now >= next_cast then
            next_cast = now + G.TUNING.KRYPTON_SURVIVOR.heatvision_interval
            send(position.x, position.z)
        end
    end)
end
