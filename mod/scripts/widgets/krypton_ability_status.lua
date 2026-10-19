local Widget = require("widgets/widget")
local Text = require("widgets/text")
local Image = require("widgets/image")
local Status = require("krypton_ability_status")
local ICONS = { "flight", "protection", "revival" }

local AbilityStatus = Class(Widget, function(self, owner, options)
    Widget._ctor(self, "KryptonAbilityStatus")
    self.owner = owner
    self.language = options.language

    -- Only the neutral panel square comes from the installed game. Each row
    -- uses its own generated raster icon, packaged in this mod's UI atlas.
    self.background = self:AddChild(Image("images/global.xml", "square.tex"))
    self.background:SetSize(250, 132)
    self.background:SetTint(.055, .065, .08, .75)
    self.background:SetClickable(false)

    self.title = self:AddChild(Text(UIFONT, 23, self.language == "zh" and "超能力" or "Abilities"))
    self.title:SetRegionSize(230, 28)
    self.title:SetHAlign(ANCHOR_LEFT)
    self.title:SetPosition(0, 44)
    self.title:SetColour(.91, .88, .78, 1)
    self.title:SetClickable(false)

    self.rows = {}
    self.row_icons = {}
    for i = 1, 3 do
        local name = "krypton_" .. ICONS[i]
        local icon = self:AddChild(Image("images/abilityicons/" .. name .. ".xml", name .. ".tex"))
        icon:SetSize(28, 28)
        icon:SetPosition(-101, 15 - (i - 1) * 27)
        self.row_icons[i] = icon
        -- Leave the whole English cooldown (including MM:SS) inside the panel.
        local row = self:AddChild(Text(UIFONT, self.language == "zh" and 22 or 18, ""))
        row:SetRegionSize(196, 26)
        row:SetHAlign(ANCHOR_LEFT)
        row:SetPosition(17, 15 - (i - 1) * 27)
        self.rows[i] = row
    end
    self._on_status_dirty = function() self:Refresh() end
    self.inst:ListenForEvent(Status.DIRTY_EVENT, self._on_status_dirty, owner)
    self:Refresh()
end)

function AbilityStatus:Refresh()
    local snapshot = Status.GetSnapshot(self.owner)
    local rows = Status.GetRows(snapshot, self.language)
    local active_icons = {
        snapshot.initialized and snapshot.alive and snapshot.flight_enabled
            and snapshot.flying and not snapshot.riding,
        snapshot.initialized and snapshot.protected,
        snapshot.initialized and snapshot.revive_supported ~= false
            and (snapshot.reviving or (snapshot.equipped and snapshot.alive)),
    }
    for i, model in ipairs(rows) do
        self.rows[i]:SetString(model.text)
        self.rows[i]:SetColour(model.colour)
        self.rows[i]:SetTooltip(model.tooltip)
        self.row_icons[i]:SetTooltip(model.tooltip)
        -- Keep the authored icon colours. Grey rows represent an unavailable
        -- ability; dim those icons instead of applying a blue/green overlay.
        self.row_icons[i]:SetTint(1, 1, 1, active_icons[i] and 1 or .35)
    end
end

-- Text and icon supply native hover tooltips but never claim a control event.
-- No key handlers, action buttons or drag callbacks compete with gameplay.
function AbilityStatus:OnControl(control, down)
    return false
end

return AbilityStatus
