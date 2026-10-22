-- Use each production handler together: a shared input state must not leave
-- heat vision working while silently swallowing frost breath or form changes.
local function load_source(path)
    return assert(load(read_project_file(path), "@" .. path))()
end

local handlers = {
    heat = load_source("mod/scripts/krypton_heatvision_input.lua"),
    frost = load_source("mod/scripts/krypton_frostbreath_input.lua"),
    form = load_source("mod/scripts/krypton_darkform_input.lua"),
}
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function fixture()
    local state = { valid = true, tags = {}, focus = false, hovered = nil,
        enabled = true, busy = false, working = false, riding = false,
        local_paused = false, server_paused = false, dedicated = false,
        position = { x = 12, z = -9 }, now = 10, modifiers = {}, sends = {}, keys = {} }
    local actor = { prefab = "krypton_survivor", components = {}, replica = {} }
    actor.IsValid = function() return state.valid end
    actor.HasTag = function(_, tag) return state.tags[tag] == true end
    actor.HUD = { HasInputFocus = function() return state.focus end }
    actor.components.health = { IsDead = function() return state.dead == true end }
    actor.components.playercontroller = {
        IsEnabled = function() return state.enabled end,
        IsBusy = function() return state.busy end,
        IsDoingOrWorking = function() return state.working end,
    }
    actor.replica.rider = { IsRiding = function() return state.riding end }
    local G = { ThePlayer = actor, KEY_CTRL = 401, KEY_ALT = 400, KEY_SHIFT = 402,
        TUNING = { KRYPTON_SURVIVOR = {
            heatvision_interval = .35, frostbreath_interval = 1.2, darkform_toggle_interval = .35 } },
        GetTime = function() return state.now end,
        IsPaused = function() return state.local_paused end,
        TheNet = { IsDedicated = function() return state.dedicated end,
            IsServerPaused = function() return state.server_paused end },
        TheInput = {
            AddKeyDownHandler = function(_, key, fn) state.keys[key] = fn end,
            GetHUDEntityUnderMouse = function() return state.hovered end,
            GetWorldPosition = function() return state.position end,
            IsKeyDown = function(_, key) return state.modifiers[key] == true end,
        },
    }
    function state:Register()
        for name, register in pairs(handlers) do
            self.sends[name] = {}
            register(G, name, function(...)
                local args = { ... }
                if name == "form" then
                    equal(select("#", ...), 0, "form RPC supplies no client-authored mode or sanity")
                else
                    equal(select("#", ...), 2, name .. " RPC contains only mouse aim")
                    equal(args[1], 12, name .. " retains aim x")
                    equal(args[2], -9, name .. " retains aim z")
                end
                self.sends[name][#self.sends[name] + 1] = args
            end)
        end
    end
    function state:PressAll()
        for _, name in ipairs({ "heat", "frost", "form" }) do
            assert(self.keys[name], name .. " handler missing")()
        end
    end
    function state:Expect(heat, frost, form, message)
        for name, expected in pairs({ heat = heat, frost = frost, form = form }) do
            equal(#self.sends[name], expected, message .. " / " .. name)
        end
    end
    return state, G, actor
end

for _, modifiers in ipairs({ {}, { 401 }, { 400 }, { 402 }, { 401, 400, 402 } }) do
    local state = fixture()
    for _, key in ipairs(modifiers) do state.modifiers[key] = true end
    state:Register(); state:PressAll()
    state:Expect(1, 1, 1, "idle input parity with native modifier state")
    state:PressAll()
    state:Expect(1, 1, 1, "modifiers do not bypass key repeat limits")
    state.now = 10.35; state:PressAll()
    state:Expect(2, 1, 2, "each skill retains its own simulation cooldown")
    state.now = 11.2; state:PressAll()
    state:Expect(3, 2, 3, "frost interval completes without locking other skills")
end

local blockers = {
    missing_player = function(state, G) G.ThePlayer = nil end,
    invalid = function(state) state.valid = false end,
    wrong_character = function(state, G, actor) actor.prefab = "wilson" end,
    ghost = function(state) state.tags.playerghost = true end,
    busy_tag = function(state) state.tags.busy = true end,
    no_hud = function(state, G, actor) actor.HUD = nil end,
    input_focus = function(state) state.focus = true end,
    local_pause = function(state) state.local_paused = true end,
    server_pause = function(state) state.server_paused = true end,
    hovered_ui = function(state) state.hovered = {} end,
    no_controller = function(state, G, actor) actor.components.playercontroller = nil end,
    disabled_controller = function(state) state.enabled = false end,
    controller_busy = function(state) state.busy = true end,
    doing_or_working = function(state) state.working = true end,
    placement = function(state, G, actor) actor.components.playercontroller.placer = {} end,
}
for name, block in pairs(blockers) do
    local state, G, actor = fixture()
    state.modifiers[401], state.modifiers[400], state.modifiers[402] = true, true, true
    state:Register(); block(state, G, actor); state:PressAll()
    state:Expect(0, 0, 0, "shared safety guard retained: " .. name)
end

local mounted = fixture()
mounted.riding = true; mounted:Register(); mounted:PressAll()
mounted:Expect(1, 0, 1, "only frost retains its actual riding restriction")
local no_aim = fixture()
no_aim.position = nil; no_aim:Register(); no_aim:PressAll()
no_aim:Expect(0, 0, 1, "form switching requires no mouse aim")
for _, dedicated in ipairs({ false, true }) do
    local state, G = fixture()
    state.dedicated = dedicated
    for _, register in pairs(handlers) do register(G, dedicated and "unused" or nil, function() error("no input expected") end) end
    equal(next(state.keys), nil, "disabled shortcuts and dedicated servers register no handlers")
end

print("Ability input parity: production R/X/H handlers agree with modifier states, retain shared safety guards and preserve skill-specific cooldown, aim and riding rules.")
