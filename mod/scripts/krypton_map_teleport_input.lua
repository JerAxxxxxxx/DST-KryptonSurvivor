-- Hook only the map screen; leave normal world mouse controls untouched.
return function(G, mode, send)
    if mode == "disabled" or G.TheNet:IsDedicated() then return function() end end
    local next_cast = 0
    return function(screen)
        local old_control = screen.OnControl
        screen.OnControl = function(self, control, down)
            local player = self.owner
            if not down or control ~= G.CONTROL_SECONDARY or not self.shown or self.quitting
                or self._hack_ignore_held_controls or G.TheInput:ControllerAttached()
                or (mode ~= "right" and not G.TheInput:IsKeyDown(G.KEY_CTRL))
                or player == nil or player ~= G.ThePlayer or not player:IsValid()
                or player.prefab ~= "krypton_survivor" or player:HasTag("playerghost")
                or player:HasTag("busy") then
                return old_control(self, control, down)
            end
            local controller = player.components.playercontroller
            if controller == nil or not controller:IsMapControlsEnabled() or controller:IsBusy()
                or controller:IsDoingOrWorking() or controller.placer ~= nil
                or G.TUNING.KRYPTON_SURVIVOR.map_teleport_enabled == false then
                return old_control(self, control, down)
            end
            local now = G.GetTime()
            if now < next_cast then return true end
            local x, y, z = self:GetWorldPositionAtCursor()
            if x == nil or z == nil then return true end
            next_cast = now + G.TUNING.KRYPTON_SURVIVOR.map_teleport_interval
            -- Normal OnDestroy releases map autopause exactly once. The native
            -- network pause can settle after this frame, so send next sim tick.
            G.TheFrontEnd:PopScreen()
            controller._hack_ignore_held_controls = 0.1
            controller._hack_ignore_ups_for = {}
            player:DoTaskInTime(0, function()
                if player ~= G.ThePlayer or not player:IsValid()
                    or player.prefab ~= "krypton_survivor" or player:HasTag("playerghost")
                    or player:HasTag("dead") or player:HasTag("busy") or player.HUD == nil
                    or player.HUD:HasInputFocus() or G.IsPaused() or G.TheNet:IsServerPaused()
                    or G.TUNING.KRYPTON_SURVIVOR.map_teleport_enabled == false then return end
                local health = player.components.health or (player.replica ~= nil and player.replica.health)
                if health ~= nil and health:IsDead() then return end
                local current_controller = player.components.playercontroller
                if current_controller == nil or not current_controller:IsEnabled() or current_controller:IsBusy()
                    or current_controller:IsDoingOrWorking() or current_controller.placer ~= nil then return end
                -- Keep the selected world point even if the mouse moves after closing.
                send(x, z)
            end)
            return true
        end
    end
end
