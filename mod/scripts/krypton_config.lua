-- Server values are selected from the same finite choices exposed in modinfo.
-- Old saves may omit new fields; edited configs must never inject strings,
-- infinities or unbounded radii into combat and simulation callbacks.
local Config = {}
local NUMBERS = {
    speed_multiplier = { default = 1.5, values = { 1.5, 2, 3 } },
    staff_damage = { default = 2000, values = { 2000, 10000, 50000 } },
    heatvision_damage = { default = 2000, values = { 2000, 10000, 50000 } },
    staff_range = { default = 6, values = { 3, 6, 10, 16 } },
    staff_aoe_radius = { default = 5, values = { 0, 3, 5, 8, 12 } },
    frostbreath_coldness = { default = 2, values = { 1, 2, 4, 8 } },
    daylight_health_regen = { default = 100, values = { 0, 10, 50, 100, 500 } },
    daylight_sanity_regen = { default = 100, values = { 0, 10, 50, 100, 500 } },
}

function Config.Number(name, reader)
    local definition = assert(NUMBERS[name], "Unknown Krypton numeric configuration: " .. tostring(name))
    local value = reader(name)
    if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
        for _, allowed in ipairs(definition.values) do
            if value == allowed then return value end
        end
    end
    return definition.default
end

return Config
