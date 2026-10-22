local function load_source(path)
    return assert(load(read_project_file(path), "@" .. path))()
end
local Config = load_source("mod/scripts/krypton_config.lua")
load_source("mod/modinfo.lua")

local expected = {
    speed_multiplier = { default = 1.5, values = { 1.5, 2, 3 } },
    staff_damage = { default = 2000, values = { 2000, 10000, 50000 } },
    heatvision_damage = { default = 2000, values = { 2000, 10000, 50000 } },
    staff_range = { default = 6, values = { 3, 6, 10, 16 } },
    staff_aoe_radius = { default = 5, values = { 0, 3, 5, 8, 12 } },
    frostbreath_coldness = { default = 2, values = { 1, 2, 4, 8 } },
    daylight_health_regen = { default = 100, values = { 0, 10, 50, 100, 500 } },
    daylight_sanity_regen = { default = 100, values = { 0, 10, 50, 100, 500 } },
}
local entries, names = {}, {}
assert(#configuration_options == 21, "all 16 existing and 5 new options must remain available")
for _, entry in ipairs(configuration_options) do
    assert(not names[entry.name], "duplicate mod configuration name")
    names[entry.name] = true
    entries[entry.name] = entry
end
local reads = 0
local function read(value, wanted)
    return function(name, client)
        assert(name == wanted and client == nil, "numeric tuning must read server config, not local overrides")
        reads = reads + 1
        return value
    end
end
for name, definition in pairs(expected) do
    local entry = assert(entries[name], "missing config " .. name)
    assert(entry.client ~= true, "gameplay numeric values must be server-wide")
    assert(entry.default == definition.default, "existing gameplay default changed: " .. name)
    assert(#entry.options == #definition.values, "numeric menu and runtime schema disagree: " .. name)
    for index, value in ipairs(definition.values) do
        assert(entry.options[index].data == value, "menu order/value changed: " .. name)
        local before = reads
        assert(Config.Number(name, read(value, name)) == value, "legal numeric choice was discarded: " .. name)
        assert(reads == before + 1, "config reader must run once per field")
    end
    assert(Config.Number(name, read(nil, name)) == entry.default, "old saves need default for " .. name)
    for _, bad in ipairs({ false, true, "0", tostring(entry.default), {}, function() end,
        -1, -math.huge, math.huge, 0 / 0, 42, .125 }) do
        assert(Config.Number(name, read(bad, name)) == entry.default,
            "bad config must safely return the default: " .. name)
    end
end
for _, name in ipairs({ "staff_aoe_radius", "daylight_health_regen", "daylight_sanity_regen" }) do
    local entry = entries[name]
    assert(entry.options[1].data == 0, "off must be the explicit zero choice")
    assert(entry.options[1].description:find("Off", 1, true), "zero option should explain off")
    assert(entry.hover and entry.hover:find("Server", 1, true), "server scope needs bilingual help")
    assert(entry.hover:find("0", 1, true), "zero behavior must be explained")
    assert(Config.Number(name, read(0, name)) == 0, "zero must not be replaced by the fallback")
end
for _, name in ipairs({ "staff_range", "frostbreath_coldness" }) do
    assert(entries[name].hover and entries[name].hover:find("Server", 1, true), "new numeric settings need server help")
    assert(Config.Number(name, read(0, name)) == expected[name].default,
        "zero is accepted only where the menu actually supports disabling")
end
local ok = pcall(function() Config.Number("unknown", function() return 1 end) end)
assert(not ok, "a developer's unknown key must not silently invent a tuning value")

print("Configuration: actual modinfo menus, server scope, old defaults, every numeric choice, zero/off values and malformed config fallback passed.")
