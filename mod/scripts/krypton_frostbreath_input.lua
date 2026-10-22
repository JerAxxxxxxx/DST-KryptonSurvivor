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
        -- Match heat vision: modifier state alone must not silently swallow
        -- this shortcut. Chat, UI focus and unsafe actions are guarded above.
        local rider = player.replica ~= nil and player.replica.rider or nil
        if rider ~= nil and rider:IsRiding() then return end
        local controller = player.components.playercontroller
        if controller == nil or not controller:IsEnabled() or controller:IsBusy()
            or controller:IsDoingOrWorking() or controller.placer ~= nil then return end
        local position = G.TheInput:GetWorldPosition()
        local now = G.GetTime()
        if position ~= nil and now >= next_cast then
            next_cast = now + (G.TUNING.KRYPTON_SURVIVOR.frostbreath_interval or 1.2)
            send(position.x, position.z)
        end
    end)
end
