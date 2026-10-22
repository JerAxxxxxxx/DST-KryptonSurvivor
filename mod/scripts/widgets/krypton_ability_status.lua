local Widget = require("widgets/widget")
local Text = require("widgets/text")
local Image = require("widgets/image")
local Status = require("krypton_ability_status")
local ICONS = { "flight", "protection", "revival" }

local AbilityStatus = Class(Widget, function(self, owner, options)
    Widget._ctor(self, "KryptonAbilityStatus")
    self.owner = owner
    self.language = options.language
    self.skill_keys = { heatvision_key = options.heatvision_key, frostbreath_key = options.frostbreath_key }
    self.darkform_key = options.darkform_key
    self.get_skill_context = options.get_skill_context

    -- Only the neutral panel square comes from the installed game. Each row
    -- uses its own generated raster icon, packaged in this mod's UI atlas.
    self.background = self:AddChild(Image("images/global.xml", "square.tex"))
    -- Expand downwards: the existing top edge, title and three icon rows stay
    -- where players placed them, while skills and the form row fit below.
    self.background:SetSize(250, 217)
    self.background:SetPosition(0, -42.5)
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
    self.skill_rows, self._skill_models = {}, {}
    for i = 1, 2 do
        local row = self:AddChild(Text(UIFONT, 18, ""))
        row:SetRegionSize(230, 26)
        row:SetHAlign(ANCHOR_LEFT)
        row:SetPosition(0, -77 - (i - 1) * 27)
        self.skill_rows[i] = row
    end
    self.form_row = self:AddChild(Text(UIFONT, 18, ""))
    self.form_row:SetRegionSize(230, 26)
    self.form_row:SetHAlign(ANCHOR_LEFT)
    self.form_row:SetPosition(0, -131)
    self._on_status_dirty = function() self:Refresh() end
    self.inst:ListenForEvent(Status.DIRTY_EVENT, self._on_status_dirty, owner)
    self.inst:ListenForEvent(Status.FORM_DIRTY_EVENT, self._on_status_dirty, owner)
    self:Refresh()
    self:StartUpdating()
end)

function AbilityStatus:RefreshSkills(snapshot)
    snapshot = snapshot or Status.GetSnapshot(self.owner)
    local context = self.get_skill_context ~= nil and self.get_skill_context() or nil
    local rows = Status.GetSkillRows(snapshot, self.language, self.skill_keys, context)
    for i, model in ipairs(rows) do
        local previous = self._skill_models[i]
        if previous == nil or previous.text ~= model.text or previous.state ~= model.state
            or previous.tooltip ~= model.tooltip then
            self.skill_rows[i]:SetString(model.text)
            self.skill_rows[i]:SetColour(model.colour)
            self.skill_rows[i]:SetTooltip(model.tooltip)
            self._skill_models[i] = model
        end
    end
    local form = Status.GetFormRow(snapshot, self.language, self.darkform_key, context)
    local previous = self._form_model
    if previous == nil or previous.text ~= form.text or previous.state ~= form.state
        or previous.tooltip ~= form.tooltip or previous.available ~= form.available then
        self.form_row:SetString(form.text)
        self.form_row:SetColour(form.colour)
        self.form_row:SetTooltip(form.tooltip)
        self._form_model = form
    end
end

function AbilityStatus:OnUpdate(dt)
    self._skill_update_time = (self._skill_update_time or 0) + dt
    if self._skill_update_time >= .1 then
        self._skill_update_time = 0
        -- Only re-evaluate local input availability. Cooldowns and revival
        -- remaining time still come exclusively from server netvars.
        self:RefreshSkills()
    end
end

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
    self:RefreshSkills(snapshot)
end

-- Text and icon supply native hover tooltips but never claim a control event.
-- No key handlers, action buttons or drag callbacks compete with gameplay.
function AbilityStatus:OnControl(control, down)
    return false
end

return AbilityStatus
