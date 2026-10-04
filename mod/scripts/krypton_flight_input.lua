-- One keyboard handler per client. The server owns the actual mode change.
return function(G, key, send)
    if key == nil or G.TheNet:IsDedicated() then return end
    local next_toggle = 0
    G.TheInput:AddKeyDownHandler(key, function()
        local player = G.ThePlayer
        if G.TUNING.KRYPTON_SURVIVOR.flight_enabled == false or player == nil
            or not player:IsValid() or player.prefab ~= "krypton_survivor"
            or player:HasTag("playerghost") or player:HasTag("busy") or player.HUD == nil
            or player.HUD:HasInputFocus() or G.IsPaused() or G.TheNet:IsServerPaused()
            or G.TheInput:GetHUDEntityUnderMouse() ~= nil then
            return
        end
        local controller = player.components.playercontroller
        if controller == nil or not controller:IsEnabled() or controller:IsBusy()
            or controller:IsDoingOrWorking() or controller.placer ~= nil then return end
        local now = G.GetTime()
        if now >= next_toggle then
            next_toggle = now + (G.TUNING.KRYPTON_SURVIVOR.flight_toggle_interval or .35)
            send()
        end
    end)
end
