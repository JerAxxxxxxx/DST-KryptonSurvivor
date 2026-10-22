local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < .000001, message or "values differ")
end
local real_require = require
local Flight = { IsFlying = function(inst) return inst.actual_flying end }
-- Status consumes each ability's canonical eligibility; these opaque test
-- answers let this suite prove that it never invents its own server policy.
local HeatVision = { CanCast = function(inst) return inst.heat_can_cast ~= false and not inst.dead end }
local FrostBreath = { CanCast = function(inst) return inst.frost_can_cast ~= false and not inst.dead end }
require = function(name)
    if name == "krypton_flight" then return Flight end
    if name == "krypton_heatvision" then return HeatVision end
    if name == "krypton_frostbreath" then return FrostBreath end
    return real_require(name)
end

local net_count, pristine = 0, false
local function netvar(guid, name, event)
    assert(not pristine, "status netvars must be created before SetPristine")
    net_count = net_count + 1
    return { data = 0, sets = 0, event = event,
        value = function(self) return self.data end,
        set = function(self, value) self.data = value; self.sets = self.sets + 1 end }
end
net_byte, net_ushortint = netvar, netvar
TUNING = { KRYPTON_SURVIVOR = { flight_enabled = true } }
TheWorld = { ismastersim = true }
local Status = load_source("mod/scripts/krypton_ability_status.lua")
local now = 0
GetTime = function() return now end
local function player()
    local inst = { GUID = 101, prefab = "krypton_survivor", tags = {}, listeners = {}, periodic = {}, deferred = {},
        components = {}, actual_flying = true, dead = false, riding = false,
        equipped = true, protected = true, reviving = false, cooldown_end = 0 }
    inst._krypton_dark_form = { data = false, value = function(self) return self.data end }
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:ListenForEvent(event, fn) self.listeners[event] = fn end
    function inst:DoPeriodicTask(interval, fn) self.periodic[#self.periodic + 1] = { interval = interval, fn = fn }; return {} end
    function inst:DoTaskInTime(delay, fn)
        local task = { delay = delay, due = now + delay, fn = fn,
            Cancel = function(self) self.cancelled = true end }
        self.deferred[#self.deferred + 1] = task
        return task
    end
    inst.components.health = { IsDead = function() return inst.dead end }
    inst.components.rider = { IsRiding = function() return inst.riding end }
    inst.components.krypton_starcore = {
        GetEquippedAmulet = function() return inst.equipped and {} or nil end,
        IsProtected = function() return inst.protected end,
        IsAutoReviving = function() return inst.reviving end,
        GetCooldownRemaining = function() return math.max(0, inst.cooldown_end - now) end,
    }
    return inst
end
local host = player()
Status.CommonInit(host)
equal(net_count, 2, "identical small netvar schema")
equal(Status.GetSnapshot(host).initialized, false, "no ready state before server's first snapshot")
pristine = true
Status.MasterInit(host)
equal(host.periodic[1].interval, 1, "simulation cadence")
Status.MasterInit(host)
equal(#host.periodic, 1, "no duplicate server periodic task")
local first = Status.GetSnapshot(host)
assert(first.initialized and first.alive and first.flying and first.protected and first.equipped)
local rows = Status.GetRows(first, "zh")
equal(rows[1].text, "飞行：已开启")
equal(rows[2].text, "护符：保护生效")
equal(rows[3].text, "复活：已就绪")
assert(rows[1].colour[3] > rows[1].colour[1], "flight blue")
assert(rows[2].colour[2] > rows[2].colour[1], "protection green")

-- Remote HUD consumes only replicated state; it needs no server components.
pristine = false
local client = { GUID = 102, _krypton_dark_form = { data = false, value = function(self) return self.data end } }
Status.CommonInit(client)
pristine = true
local function replicate()
    client._krypton_status_flags.data = host._krypton_status_flags:value()
    client._krypton_status_cooldown.data = host._krypton_status_cooldown:value()
    client._krypton_dark_form.data = host._krypton_dark_form:value()
end
host.cooldown_end = 275
host.periodic[1].fn()
replicate()
TheWorld.ismastersim = false
rows = Status.GetRows(Status.GetSnapshot(client), "zh")
equal(rows[3].text, "复活：冷却 04:35")
assert(rows[2].text == "护符：保护生效", "protection must remain active during cooldown")
now = 200
equal(Status.GetRows(Status.GetSnapshot(client), "zh")[3].text, "复活：冷却 04:35",
    "client and paused HUD do not count wall-clock or predict a cooldown")
local previous_sets = client._krypton_status_flags.sets
Status.Sync(client)
equal(client._krypton_status_flags.sets, previous_sets, "client never writes status netvars")
TheWorld.ismastersim = true
host.periodic[1].fn()
replicate()
equal(Status.GetRows(Status.GetSnapshot(client), "en")[3].text, "Revive: Cooldown 01:15")

-- Unequipping does not hide ongoing cooldown or falsely advertise readiness.
host.equipped, host.protected = false, false
host.listeners.unequip()
replicate()
rows = Status.GetRows(Status.GetSnapshot(client), "zh")
equal(rows[2].text, "护符：未装备")
equal(rows[3].text, "复活：冷却 01:15")
assert(rows[3].tooltip:find("当前未装备护符", 1, true))
now = 276
host.periodic[1].fn()
replicate()
equal(Status.GetRows(Status.GetSnapshot(client), "zh")[3].text, "复活：未装备")
host.equipped, host.protected = true, true
host.listeners.equip()
equal(Status.GetRows(Status.GetSnapshot(host), "zh")[3].text, "复活：已就绪")

-- A worn amulet still protects in Wilderness, but cannot advertise a
-- revival that its native no-ghost/no-corpse rules cannot perform.
host.ghostenabled = false
Status.Sync(host)
replicate()
rows = Status.GetRows(Status.GetSnapshot(client), "zh")
equal(rows[2].text, "护符：保护生效", "Wilderness environmental protection remains")
equal(rows[3].text, "复活：模式不可用", "no false ready state in no-revival mode")
host.components.revivablecorpse = {}
Status.Sync(host)
equal(Status.GetRows(Status.GetSnapshot(host), "zh")[3].text, "复活：已就绪", "native revivable-corpse mode remains supported")
host.ghostenabled, host.components.revivablecorpse = nil, nil

host.actual_flying, host.riding = false, true
host.listeners.mounted()
equal(Status.GetRows(Status.GetSnapshot(host), "zh")[1].text, "飞行：骑乘中暂停")
host.riding, host.dead, host.protected, host.reviving = false, true, false, true
host.tags.playerghost = true
host.listeners.ms_becameghost()
rows = Status.GetRows(Status.GetSnapshot(host), "zh")
equal(rows[1].text, "飞行：不可用")
equal(rows[2].text, "护符：暂未生效")
equal(rows[3].text, "复活：复活中")
host.reviving, host.tags.playerghost, host.dead, host.protected = false, nil, false, true
host.cooldown_end = now + .25
host.listeners.ms_respawnedfromghost()
equal(Status.GetSnapshot(host).cooldown, 1, "round fractional remaining time upward, not premature ready")
now = now + .25
host.periodic[1].fn()
equal(Status.GetRows(Status.GetSnapshot(host), "zh")[3].text, "复活：已就绪")
TUNING.KRYPTON_SURVIVOR.flight_enabled = false
host.periodic[1].fn()
equal(Status.GetRows(Status.GetSnapshot(host), "zh")[1].text, "飞行：服务器关闭")

-- Deferred initialization observes cooldown restored by native loading.
local loaded = player()
pristine = false
Status.CommonInit(loaded)
pristine = true
Status.MasterInit(loaded)
loaded.cooldown_end = now + 480
loaded.deferred[1].fn(loaded)
equal(Status.GetSnapshot(loaded).cooldown, 480)

-- Successful casts notify the server immediately, and one-shot simulation
-- tasks resolve sub-second cooldowns between the normal 1-second snapshots.
now = 500
local caster = player()
pristine = false; Status.CommonInit(caster); pristine = true; Status.MasterInit(caster)
local function skills(actor, language, keys, context)
    return Status.GetSkillRows(Status.GetSnapshot(actor), language or "zh", keys, context)
end
local function run_due(actor)
    local again = true
    while again do
        again = false
        for _, task in ipairs(actor.deferred) do
            if not task.cancelled and not task.fired and task.due <= now then
                task.fired = true; task.fn(actor); again = true
            end
        end
    end
end
equal(skills(caster)[1].text, "热视线 [R]：就绪", "default heat key and authoritative ready")
equal(skills(caster)[2].text, "吐息 [X]：就绪", "default frost key")
local unchanged_sets = caster._krypton_status_flags.sets
Status.Sync(caster)
equal(caster._krypton_status_flags.sets, unchanged_sets, "unchanged server snapshots generate no status write")
caster._krypton_heatvision_nextcast = now + .35
caster.listeners.krypton_skillstatechanged()
equal(skills(caster)[1].state, "cooldown", "cast event dims heat immediately")
assert(skills(caster)[1].colour[4] < 1, "short cooldown dims instead of displaying decimals")
close(caster._krypton_status_skill_task.delay, .35, "one-shot catches heat cooldown before periodic poll")
local pending = caster._krypton_status_skill_task
Status.Sync(caster)
equal(caster._krypton_status_skill_task, pending, "same deadline is not rescheduled on unrelated status updates")
now = 500.34; run_due(caster)
equal(skills(caster)[1].state, "cooldown", "heat cannot become ready early")
now = 500.35; run_due(caster)
equal(skills(caster)[1].state, "ready", "heat ready returns at actual .35-second deadline")

caster._krypton_frostbreath_channel = { ends = now + 1 }
caster._krypton_frostbreath_nextcast = now + 1.2
caster.listeners.krypton_skillstatechanged()
equal(skills(caster)[2].state, "casting", "breath channel has a distinct casting state")
caster._krypton_heatvision_nextcast = now + .35
caster.listeners.krypton_skillstatechanged()
close(caster._krypton_status_skill_task.delay, .35, "concurrent skills wake at earliest deadline")
now = now + .35; run_due(caster)
equal(skills(caster)[1].state, "ready", "heat can finish during a breath channel")
equal(skills(caster)[2].state, "casting", "breath remains active until its own channel ends")
now = 501.35; run_due(caster)
equal(skills(caster)[2].state, "cooldown", "expired channel cannot remain casting before Finish callback")
caster._krypton_frostbreath_channel = nil
caster.listeners.krypton_skillstatechanged()
now = 501.55; run_due(caster)
equal(skills(caster)[2].state, "ready", "breath ready returns at 1.2-second deadline")
equal(#caster.periodic, 1, "skill feedback does not add a high-frequency server poll")

-- A remote viewer reads server bits; changing its local time cannot advance
-- cooldown or modify replicated values, and local settings only narrow input.
client._krypton_status_flags.data = caster._krypton_status_flags:value()
client._krypton_status_cooldown.data = caster._krypton_status_cooldown:value()
local configured = skills(client, "en", { heatvision_key = "KEY_Z", frostbreath_key = "KEY_N" })
equal(configured[1].text, "Heat [Z]: Ready")
equal(configured[2].text, "Frost [N]: Ready")
local local_flags = client._krypton_status_flags:value()
equal(skills(client, "zh", { heatvision_key = "disabled" })[1].state, "key_off")
equal(skills(client, "zh", nil, { blocked = true })[1].state, "unavailable")
equal(skills(client, "zh", nil, { frost_blocked = true })[1].state, "ready", "frost riding guard does not invent a heat restriction")
equal(skills(client, "zh", nil, { frost_blocked = true })[2].state, "unavailable")
equal(client._krypton_status_flags:value(), local_flags, "client guards never write server flags")
caster.heat_can_cast = false; caster.frost_can_cast = false
caster.listeners.newstate()
equal(skills(caster)[1].state, "unavailable", "canonical heat denial cannot show ready")
equal(skills(caster)[2].state, "unavailable", "canonical frost denial cannot show ready")
caster.heat_can_cast = true; caster.frost_can_cast = true
caster.listeners.newstate()
equal(skills(caster)[1].state, "ready", "newstate immediately restores actual eligibility")
TUNING.KRYPTON_SURVIVOR.frostbreath_enabled = false
Status.Sync(caster)
equal(skills(caster)[2].state, "server_off", "server setting wins over a locally enabled key")
TUNING.KRYPTON_SURVIVOR.frostbreath_enabled = true
caster._krypton_heatvision_nextcast = now + .35
caster.listeners.krypton_skillstatechanged()
local remove_task = caster._krypton_status_skill_task
caster.listeners.onremove(caster)
assert(remove_task.cancelled and caster._krypton_status_skill_task == nil, "removal cancels pending skill wake")

-- Form state comes only from the saved form's own replicated boolean. The
-- current form remains visible when switching input is temporarily blocked.
host._krypton_dark_form.data = true
host.dead, host.tags.playerghost = false, nil
Status.Sync(host); replicate()
local form = Status.GetFormRow(Status.GetSnapshot(client), "zh", "KEY_H")
equal(form.text, "形态 [H]：黑暗", "remote form reads the replicated mode")
equal(form.state, "dark")
assert(form.colour[3] > form.colour[2], "dark form has a purple status colour")
assert(form.tooltip:find("5%", 1, true) and form.tooltip:find("白天回血", 1, true))
form = Status.GetFormRow(Status.GetSnapshot(client), "en", "KEY_J", { blocked = true })
equal(form.text, "Form [J]: Dark", "blocked switching never hides the current mode")
assert(not form.available and form.colour[4] < 1)
form = Status.GetFormRow(Status.GetSnapshot(client), "en", "disabled")
equal(form.text, "Form [-]: Dark", "disabled local key does not reset server form")
assert(not form.available and form.tooltip:find("disabled", 1, true))
host._krypton_dark_form.data = false
replicate()
equal(Status.GetFormRow(Status.GetSnapshot(client), "en", "KEY_K").text, "Form [K]: Normal")
equal(Status.GetFormRow(Status.GetSnapshot(client), "en", "KEY_H", { form_blocked = true }).available, false)
equal(Status.GetFormRow({ initialized = false }, "zh").state, "syncing")
equal(Status.GetFormRow({ initialized = true, alive = false, dark_form = true }, "en").text, "Form [H]: Dark")

Class = function(base, constructor)
    local class = {}; class.__index = class
    class._ctor = constructor
    return setmetatable(class, { __index = base, __call = function(_, ...)
        local self = setmetatable({}, class); constructor(self, ...); return self
    end })
end
local Widget = {}
function Widget._ctor(self, name)
    self.name, self.children, self.events = name, {}, {}
    self.inst = { ListenForEvent = function(_, event, fn, source)
        self.events[event] = { fn = fn, source = source }
    end }
end
function Widget:AddChild(child) self.children[#self.children + 1] = child; return child end
function Widget:SetPosition(x, y, z) self.position = { x, y, z } end
function Widget:SetScale(value) self.scale = value end
function Widget:SetSize(w, h) self.size = { w, h } end
function Widget:SetRegionSize(w, h) self.region = { w, h } end
function Widget:SetTint(...) self.tint = { ... } end
function Widget:SetColour(value, ...) self.colour = type(value) == "table" and value or { value, ... } end
function Widget:SetTooltip(value) self.tooltip = value end
function Widget:SetString(value) self.text = value end
function Widget:SetHAlign(value) self.align = value end
function Widget:SetClickable(value) self.clickable = value end
function Widget:StartUpdating() self.updating = true end
local Text = Class(Widget, function(self, font, size, text)
    Widget._ctor(self, "Text"); self.font, self.font_size, self.text = font, size, text
end)
local Image = Class(Widget, function(self, atlas, texture)
    Widget._ctor(self, "Image"); self.atlas, self.texture = atlas, texture
end)
UIFONT, ANCHOR_LEFT = "font", "left"
local AbilityStatus
require = function(name)
    if name == "widgets/widget" then return Widget end
    if name == "widgets/text" then return Text end
    if name == "widgets/image" then return Image end
    if name == "krypton_ability_status" then return Status end
    if name == "widgets/krypton_ability_status" then return AbilityStatus end
    return real_require(name)
end
AbilityStatus = load_source("mod/scripts/widgets/krypton_ability_status.lua")
local widget = AbilityStatus(client, { language = "zh" })
equal(widget.background.clickable, false, "background does not create a click target")
equal(widget.background.size[1], 250, "preserve panel width")
equal(widget.background.size[2], 217, "expanded panel fits skill feedback and mode")
equal(widget.background.position[2] + widget.background.size[2] / 2, 66, "old panel top edge remains fixed")
local icon_names = { "flight", "protection", "revival" }
for i, name in ipairs(icon_names) do
    equal(widget.row_icons[i].atlas, "images/abilityicons/krypton_" .. name .. ".xml", "own row atlas")
    equal(widget.row_icons[i].texture, "krypton_" .. name .. ".tex", "distinct generated row icon")
    equal(widget.row_icons[i].size[1], 28, "small icon width")
    equal(widget.rows[i].region[1], 196, "reserve text width beside icon")
    equal(widget.rows[i].font_size, 22, "Chinese font remains readable")
    equal(widget.row_icons[i].tooltip, widget.rows[i].tooltip, "matching hover help")
    assert(widget.row_icons[i].position[1] + widget.row_icons[i].size[1] / 2
        < widget.rows[i].position[1] - widget.rows[i].region[1] / 2, "icons never overlap the text")
    assert(widget.rows[i].position[1] + widget.rows[i].region[1] / 2 <= 125, "text stays within panel")
    equal(widget.row_icons[i].tint[1], 1, "preserve generated icon colour")
end
equal(widget.events[Status.DIRTY_EVENT].source, client, "widget tracks its owning player")
equal(widget.events[Status.FORM_DIRTY_EVENT].source, client, "form updates independently of skill flags")
equal(widget.rows[3].text, Status.GetRows(Status.GetSnapshot(client), "zh")[3].text)
equal(widget:OnControl("map", true), false, "HUD claims no gameplay control")
assert(widget.updating and #widget.skill_rows == 2, "only visible HUD starts local availability updates")
equal(widget.skill_rows[1].region[1], 230, "skill row has no redundant picture or cramped icon column")
equal(widget.skill_rows[2].position[2], -104, "skill rows fit below original rows")
equal(widget.form_row.position[2], -131, "form extends downward without moving old skill rows")
equal(widget.form_row.region[1], 230)
equal(widget.form_row.text, "形态 [H]：正常")
client._krypton_dark_form.data = true
widget.events[Status.FORM_DIRTY_EVENT].fn()
equal(widget.form_row.text, "形态 [H]：黑暗", "form dirty event refreshes immediately")
client._krypton_dark_form.data = false
widget.events[Status.FORM_DIRTY_EVENT].fn()
host.actual_flying, TUNING.KRYPTON_SURVIVOR.flight_enabled = true, true
host.periodic[1].fn()
replicate()
widget.events[Status.DIRTY_EVENT].fn()
equal(widget.rows[1].text, "飞行：已开启")
assert(widget.rows[1].tooltip ~= nil and widget.rows[3].tooltip ~= nil)

-- Ready/cooldown icons retain authored colour; disabled and unequipped icons
-- dim independently. A cooldown remains fully readable, even in English.
host.cooldown_end = now + 480
Status.Sync(host)
replicate()
widget:Refresh()
equal(widget.rows[3].text, "复活：冷却 08:00", "complete Chinese timer")
equal(widget.row_icons[1].tint[4], 1, "flight active icon")
equal(widget.row_icons[2].tint[4], 1, "protection stays active during cooldown")
equal(widget.row_icons[3].tint[4], 1, "cooldown icon remains visible")
local english_widget = AbilityStatus(client, { language = "en" })
equal(english_widget.rows[3].text, "Revive: Cooldown 08:00", "complete English timer")
equal(english_widget.rows[3].font_size, 18, "English cooldown fits beside its icon")
host.actual_flying, host.equipped, host.protected, host.cooldown_end = false, false, false, now
Status.Sync(host)
replicate()
widget:Refresh()
english_widget:Refresh()
equal(english_widget.rows[2].text, "Amulet: Not equipped", "complete unequipped text")
for i = 1, 3 do
    equal(widget.row_icons[i].tint[4], .35, "unavailable icon is dimmed")
    equal(widget.row_icons[i].tooltip, widget.rows[i].tooltip, "hover updates with status")
end
equal(english_widget:OnControl("attack", true), false, "icons consume no attack control")

local Hud = load_source("mod/scripts/krypton_ability_hud.lua")
local hooks = {}
local dedicated = false
local locally_paused, local_focus, local_busy, local_riding, modifier = false, false, false, false, false
local G = { TheNet = { IsDedicated = function() return dedicated end, IsServerPaused = function() return locally_paused end },
    IsPaused = function() return locally_paused end,
    KEY_CTRL = "ctrl", KEY_ALT = "alt", KEY_SHIFT = "shift",
    TheInput = { GetHUDEntityUnderMouse = function() return nil end, IsKeyDown = function() return modifier end } }
local function add_hook(path, fn) hooks[#hooks + 1] = { path = path, fn = fn } end
Hud.Install(G, { enabled = false, add_class_post_construct = add_hook })
equal(#hooks, 0, "local hidden config installs no panel")
dedicated = true
Hud.Install(G, { add_class_post_construct = add_hook })
equal(#hooks, 0, "dedicated server loads no HUD")
dedicated = false
Hud.Install(G, { scale = 1.2, position = "lower", language = "en", heatvision_key = "KEY_G", frostbreath_key = "KEY_C", darkform_key = "KEY_K", add_class_post_construct = add_hook })
equal(hooks[1].path, "widgets/controls")
local other = { owner = { prefab = "wilson" }, topright_root = setmetatable({ children = {} }, { __index = Widget }) }
hooks[1].fn(other)
equal(#other.topright_root.children, 0, "other characters do not receive Superman's HUD")
local controls = { owner = client, topright_root = setmetatable({ children = {} }, { __index = Widget }) }
client.prefab = "krypton_survivor"
client.HUD = { HasInputFocus = function() return local_focus end }
client.components = { playercontroller = { IsEnabled = function() return true end,
    IsBusy = function() return local_busy end, IsDoingOrWorking = function() return false end } }
client.replica = { rider = { IsRiding = function() return local_riding end } }
hooks[1].fn(controls)
assert(controls.krypton_ability_status ~= nil)
equal(controls.krypton_ability_status.position[2], -525)
equal(controls.krypton_ability_status.scale, 1.2)
equal(controls.krypton_ability_status.title.text, "Abilities")
local panel = controls.krypton_ability_status
equal(panel.skill_rows[1].text, "Heat [G]: Ready", "installed HUD displays configured heat key")
equal(panel.skill_rows[2].text, "Frost [C]: Ready", "installed HUD displays configured frost key")
equal(panel.form_row.text, "Form [K]: Normal", "installed HUD receives actual form key")
local original_timer = panel.rows[3].text
for _, set_blocked in ipairs({
    function(value) local_focus = value end,
    function(value) local_busy = value end,
    function(value) locally_paused = value end,
}) do
    set_blocked(true); panel:OnUpdate(.1)
    equal(panel.skill_rows[1].text, "Heat [G]: Unavailable", "local input state narrows availability promptly")
    equal(panel.rows[3].text, original_timer, "local HUD tick never advances revival clock")
    assert(not panel._form_model.available, "local input guards also dim form switching")
    set_blocked(false); panel:OnUpdate(.1)
    equal(panel.skill_rows[1].text, "Heat [G]: Ready", "local input restoration does not wait for server polling")
end
local_riding = true; panel:OnUpdate(.1)
equal(panel.skill_rows[2].text, "Frost [C]: Unavailable", "replica riding immediately dims breath")
assert(panel._form_model.available, "riding alone does not invent a form switching restriction")
local_riding = false; modifier = true; panel:OnUpdate(.1)
equal(panel.skill_rows[1].text, "Heat [G]: Ready", "modifier state keeps heat input available")
equal(panel.skill_rows[2].text, "Frost [C]: Ready", "modifier state alone does not falsely disable frost")
assert(panel._form_model.available, "form switching follows the same modifier policy as heat vision")
modifier = false; panel:OnUpdate(.1)
equal(panel.skill_rows[2].text, "Frost [C]: Ready")
client._krypton_status_flags.data = caster._krypton_status_flags:value()
panel:Refresh()
equal(panel.skill_rows[1].text, "Heat [G]: Cooldown")
local paused_bits = client._krypton_status_flags:value()
locally_paused = true; panel:OnUpdate(100)
equal(panel.skill_rows[1].text, "Heat [G]: Unavailable", "pause blocks local input without inventing completion")
equal(client._krypton_status_flags:value(), paused_bits, "real-time UI updates do not advance server cooldown flags")
locally_paused = false; panel:OnUpdate(.1)
equal(panel.skill_rows[1].text, "Heat [G]: Cooldown", "resume retains actual unfinished simulation cooldown")
caster._krypton_heatvision_nextcast = now
Status.Sync(caster)
client._krypton_status_flags.data = caster._krypton_status_flags:value()
panel.events[Status.DIRTY_EVENT].fn()
equal(panel.skill_rows[1].text, "Heat [G]: Ready", "only server completion restores ready")
hooks[1].fn(controls)
equal(#controls.topright_root.children, 1, "no duplicate panel")

-- A mode key sends no arguments or local prediction, respects input focus,
-- and rate limits duplicate requests in simulation time.
local input_handler = load_source("mod/scripts/krypton_darkform_input.lua")
local handler, sends, input_now = nil, 0, 10
local input = { tags = {}, prefab = "krypton_survivor", components = {}, replica = {},
    valid = true, dead = false, focused = false, hovered = nil, enabled = true,
    busy = false, working = false, modifier = false }
function input:IsValid() return self.valid end
function input:HasTag(tag) return self.tags[tag] == true end
input.HUD = { HasInputFocus = function() return input.focused end }
input.components.health = { IsDead = function() return input.dead end }
input.components.playercontroller = {
    IsEnabled = function() return input.enabled end,
    IsBusy = function() return input.busy end,
    IsDoingOrWorking = function() return input.working end,
}
local input_paused, input_dedicated = false, false
local input_g = { ThePlayer = input, KEY_CTRL = "ctrl", KEY_ALT = "alt", KEY_SHIFT = "shift",
    IsPaused = function() return input_paused end,
    GetTime = function() return input_now end,
    TUNING = { KRYPTON_SURVIVOR = { darkform_toggle_interval = .35 } },
    TheNet = { IsDedicated = function() return input_dedicated end, IsServerPaused = function() return input_paused end },
    TheInput = {
        AddKeyDownHandler = function(_, key, fn) equal(key, "H"); handler = fn end,
        GetHUDEntityUnderMouse = function() return input.hovered end,
        IsKeyDown = function() return input.modifier end,
    },
}
local function send(...) equal(select("#", ...), 0, "server decides mode; no client-supplied sanity"); sends = sends + 1 end
input_handler(input_g, nil, send)
equal(handler, nil, "disabled form input registers no handler")
input_dedicated = true; input_handler(input_g, "H", send)
equal(handler, nil, "dedicated server registers no input")
input_dedicated = false; input_handler(input_g, "H", send)
handler(); handler()
equal(sends, 1, "duplicate key presses inside .35 simulation seconds are limited")
input_now = input_now + .35; handler()
equal(sends, 2, "ready at actual simulation interval")
for _, block in ipairs({
    function(v) input.tags.playerghost = v end,
    function(v) input.tags.corpse = v end,
    function(v) input.tags.busy = v end,
    function(v) input.dead = v end,
    function(v) input.focused = v end,
    function(v) input.hovered = v and {} or nil end,
    function(v) input.enabled = not v end,
    function(v) input.busy = v end,
    function(v) input.working = v end,
    function(v) input_paused = v end,
    function(v) input.valid = not v end,
    function(v) input.components.playercontroller.placer = v and {} or nil end,
    function(v) input.prefab = v and "wilson" or "krypton_survivor" end,
}) do
    input_now = input_now + 1
    local before = sends
    block(true); handler(); equal(sends, before, "blocked input sends no mode request")
    block(false); handler(); equal(sends, before + 1, "cleared guard restores switching")
end
input_now = input_now + 1
input.modifier = true
local modifier_before = sends
handler()
equal(sends, modifier_before + 1, "modifier state alone must not silently swallow form switching")
input.modifier = false
input_now = input_now + 1
input_g.ThePlayer = nil
local before = sends; handler(); equal(sends, before, "no local player during loading is safe")

print("Ability HUD: server-owned state, remote snapshots, pause, equipment, cooldown, lifecycle and UI contracts passed.")
