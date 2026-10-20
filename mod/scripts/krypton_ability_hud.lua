local Hud = {}

local POSITIONS = {
    default = { -165, -415 },
    lower = { -165, -525 },
    left = { -375, -415 },
}

local function LocalSkillContext(G, owner)
    local context = {}
    local controller = owner.components ~= nil and owner.components.playercontroller or nil
    context.blocked = (G.IsPaused ~= nil and G.IsPaused())
        or G.TheNet:IsServerPaused()
        or (owner.IsValid ~= nil and not owner:IsValid())
        or (owner.HasTag ~= nil and (owner:HasTag("playerghost") or owner:HasTag("corpse") or owner:HasTag("busy")))
        or owner.HUD == nil or owner.HUD:HasInputFocus()
        or controller == nil or not controller:IsEnabled()
        or controller:IsBusy() or controller:IsDoingOrWorking() or controller.placer ~= nil
        or (G.TheInput ~= nil and G.TheInput:GetHUDEntityUnderMouse() ~= nil)
    local rider = owner.replica ~= nil and owner.replica.rider or nil
    local health = owner.components ~= nil and owner.components.health
        or (owner.replica ~= nil and owner.replica.health) or nil
    if health ~= nil and health:IsDead() then context.blocked = true end
    context.frost_blocked = rider ~= nil and rider:IsRiding()
    if G.TheInput ~= nil and G.TheInput.IsKeyDown ~= nil then
        for _, name in ipairs({ "KEY_CTRL", "KEY_ALT", "KEY_SHIFT" }) do
            local key = G[name]
            if key ~= nil and G.TheInput:IsKeyDown(key) then context.frost_blocked = true end
        end
    end
    return context
end

function Hud.Install(G, options)
    options = options or {}
    if options.enabled == false or G.TheNet:IsDedicated() then return end
    local add_hook = options.add_class_post_construct
    if add_hook == nil then return end
    local AbilityStatus = require("widgets/krypton_ability_status")
    local scale = tonumber(options.scale) or 1
    if scale ~= scale or scale == math.huge or scale == -math.huge then scale = 1 end
    scale = math.max(.65, math.min(1.3, scale))
    local position = POSITIONS[options.position] or POSITIONS.default
    add_hook("widgets/controls", function(controls)
        local owner = controls.owner
        if owner == nil or owner.prefab ~= "krypton_survivor"
            or controls.topright_root == nil or controls.krypton_ability_status ~= nil then return end
        -- The native top-right scale root follows the player's HUD scaling and
        -- screen anchor. Keep this out of StatusDisplays' internal layout.
        local panel_options = {
            language = options.language,
            heatvision_key = options.heatvision_key,
            frostbreath_key = options.frostbreath_key,
            get_skill_context = function() return LocalSkillContext(G, owner) end,
        }
        local panel = controls.topright_root:AddChild(AbilityStatus(owner, panel_options))
        panel:SetPosition(position[1], position[2], 0)
        panel:SetScale(scale)
        controls.krypton_ability_status = panel
    end)
end

return Hud
