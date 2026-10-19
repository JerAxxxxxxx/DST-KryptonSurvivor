local Hud = {}

local POSITIONS = {
    default = { -165, -415 },
    lower = { -165, -525 },
    left = { -375, -415 },
}

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
        local panel = controls.topright_root:AddChild(AbilityStatus(owner, options))
        panel:SetPosition(position[1], position[2], 0)
        panel:SetScale(scale)
        controls.krypton_ability_status = panel
    end)
end

return Hud
