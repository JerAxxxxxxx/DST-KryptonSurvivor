-- Executed only by tools/check_native_clothing.cjs. All native implementations
-- and clothing definitions arrive in memory from the user's installed game.
local function source(code, label) local chunk, err = load(code, label); assert(chunk, err); return chunk() end
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
table.contains = function(values, sought)
    for _, value in pairs(values) do if value == sought then return true end end
    return false
end
source(native_clothing, "@installed/clothing.lua")
source(native_constants, "@installed/constants.lua")
source(native_base_tables, "@installed/prefabskin.lua")
GetSkinData = function(name) return assert(CLOTHING[name], "Native clothing item missing: " .. tostring(name)) end
source(native_build_selector, "@installed/skinsutils.lua")
source(native_skin_helper, "@installed/components/skinner.lua")
ModManager = { IsModCharacterClothingSymbolExcluded = function() return false end }
TheWorld = { ismastersim = true }
local dedicated = false
TheNet = { IsDedicated = function() return dedicated end }
hash = function(value) return value end -- This audit does not test engine hashes.
local Visual = source(read_project_file("mod/scripts/krypton_darkform_visual.lua"), "@mod/scripts/krypton_darkform_visual.lua")
local selected = {
    body = "body_trenchcoat_yellow_straw",
    legs = "legs_tweed_knickerbocker_green_hunters",
    feet = "feet_formal_highheel_white_pure",
    hand = "hand_walter_ice",
}
local function actor()
    local inst = { prefab = "krypton_survivor", valid = true, components = {}, replica = {}, events = {}, tasks = {},
        dark = false, tags = {}, ordinary = {
            headbase = { "krypton_eating_build", "temporary_meal_head" },
            headbase_hat = { "krypton_frostbreath_head", "temporary_breath_head" },
            swap_hat = { "external_hat", "swap_hat" }, swap_object = { "krypton_staff", "swap_krypton_staff" },
        }, skin = {}, hidden = {}, exchanges = {}, multi = {}, calls = 0, writes = 0 }
    local skinner = { clothing = selected, skin_data = { normal_skin = "krypton_survivor" }, mode = "normal_skin",
        GetSkinMode = function(self) return self.mode end, GetMonkeyCurse = function() return nil end }
    inst.components.skinner = skinner
    inst.components.health = { IsDead = function() return false end }
    inst.IsValid = function(self) return self.valid end
    inst.IsAsleep = function(self) return self.asleep == true end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.ListenForEvent = function(self, event, fn)
        self.events[event] = self.events[event] or {}; self.events[event][fn] = true
    end
    inst.DoTaskInTime = function(self, _, fn)
        local task = { fn = fn, Cancel = function(self) self.cancelled = true end }
        self.tasks[#self.tasks + 1] = task; return task
    end
    inst.DoPeriodicTask = function(self, _, fn)
        local task = { fn = fn, period = true, Cancel = function(self) self.cancelled = true end }
        self.tasks[#self.tasks + 1] = task; return task
    end
    local function write() inst.writes = inst.writes + 1 end
    inst.AnimState = {
        SetSkin = function() error("Form clothing rebuild must not replace the live base skin or face") end,
        SetBuild = function() error("Form clothing rebuild must not replace the base build") end,
        GetBuild = function() return "krypton_survivor" end,
        GetSkinBuild = function() return "krypton_survivor" end,
        BuildHasSymbol = function() return true end,
        ClearOverrideSymbol = function(_, symbol) write(); inst.ordinary[symbol], inst.skin[symbol] = nil, nil end,
        OverrideSymbol = function(_, symbol, build, source_symbol) write(); inst.ordinary[symbol] = { build, source_symbol } end,
        OverrideSkinSymbol = function(_, symbol, build, source_symbol) write(); inst.skin[symbol] = { build, source_symbol } end,
        HideSymbol = function(_, symbol) write(); inst.hidden[symbol] = true end,
        ShowSymbol = function(_, symbol) write(); inst.hidden[symbol] = nil end,
        ClearSymbolExchanges = function() write(); inst.exchanges, inst.multi = {}, {} end,
        SetSymbolExchange = function(_, a, b) write(); inst.exchanges[a] = b end,
        SetMultiSymbolExchange = function(_, a, b) write(); inst.multi[a] = b end,
        GetSymbolOverride = function(_, symbol)
            local value = inst.ordinary[symbol] or inst.skin[symbol]
            if value then return value[1], value[2] end
        end,
        IsSkinBuild = function(_, build) return CLOTHING[build] ~= nil end,
        ClearOverrideBuild = function() write() end,
    }
    return inst
end
local function emit(inst, event)
    for fn in pairs(inst.events[event] or {}) do fn(inst) end
end
local function initial(inst)
    Visual.CommonInit(inst, function(value) return value.dark end)
    local pending = inst.tasks; inst.tasks = {}
    for _, task in ipairs(pending) do if not task.cancelled then task.fn(inst) end end
end
local function mode(inst, dark) inst.dark = dark; emit(inst, "krypton_darkformdirty") end
local function native_outfit(inst, clothing)
    SetSkinsOnAnim(inst.AnimState, inst.prefab, "krypton_survivor", clothing, nil, "NO_BASE")
end
local function snapshot(inst)
    local function serial(values)
        local parts = {}
        for key, value in pairs(values) do
            parts[#parts + 1] = key .. "=" .. (type(value) == "table" and table.concat(value, ":") or tostring(value))
        end
        table.sort(parts); return table.concat(parts, "|")
    end
    return { ordinary = serial(inst.ordinary), skin = serial(inst.skin), hidden = serial(inst.hidden),
        exchanges = serial(inst.exchanges), multi = serial(inst.multi) }
end
local function same(inst, expected, label)
    for key, value in pairs(snapshot(inst)) do equal(value, expected[key], label .. " / " .. key) end
end
local clothes = { "torso", "torso_pelvis", "arm_upper", "arm_lower", "leg", "foot" }
local function dark(inst, label)
    equal(inst.ordinary.headbase[1], "krypton_eating_build", label .. " / preserve live eating head")
    equal(inst.ordinary.headbase_hat[1], "krypton_frostbreath_head", label .. " / preserve live breath head")
    equal(inst.ordinary.swap_hat[1], "external_hat", label .. " / preserve equipped hat")
    equal(inst.ordinary.swap_object[1], "krypton_staff", label .. " / preserve held weapon")
    for _, symbol in ipairs(clothes) do
        local request = inst.ordinary[symbol]
        assert(request and request[1] == "krypton_dark_suit" and request[2] == symbol, label .. " / authored dark " .. symbol)
    end
    for symbol in pairs(CLOTHING_SYMBOLS) do
        equal(inst.skin[symbol], nil, label .. " / no Steam clothing request remains: " .. symbol)
    end
    equal(next(inst.exchanges), nil, label .. " / no native torso/skirt exchange leaks")
    equal(next(inst.multi), nil, label .. " / no native leg/foot exchange leaks")
    for symbol in pairs(HIDE_SYMBOLS) do equal(inst.hidden[symbol], nil, label .. " / native reset visibility: " .. symbol) end
end
for _, is_dedicated in ipairs({ false, true }) do
    dedicated = is_dedicated
    local inst = actor()
    native_outfit(inst, selected)
    assert(inst.skin.skirt and inst.skin.skirt[1] == selected.body, "Actual trenchcoat uses a skirt request outside the former six-symbol model")
    assert(inst.hidden.arm_upper_skin, "Actual trenchcoat hides upper-arm skin")
    local cuff_exchange = (CLOTHING[selected.legs].legs_cuff_size or 1) > (CLOTHING[selected.feet].feet_cuff_size or 1)
    equal(inst.multi.leg == "foot", cuff_exchange, "Native pants/shoes exchange follows their actual cuff metadata")
    local normal = snapshot(inst)
    initial(inst)
    same(inst, normal, "Initial clothing remains native")
    for iteration = 1, 3 do
        mode(inst, true); dark(inst, "Dark entry " .. iteration)
        local writes = inst.writes; Visual.Apply(inst)
        equal(inst.writes, writes, "No repeated clothes writes in stable dark mode")
        mode(inst, false); same(inst, normal, "Full native outfit restoration " .. iteration)
    end
    native_audit_pass((is_dedicated and "dedicated" or "listen-host") .. ": trenchcoat skirt, hidden arms, pants/shoes exchanges and exact native command-state restoration across three toggles")
    mode(inst, true)
    inst.components.skinner.clothing = { body = "body_buttons_black_jet", legs = selected.legs, feet = selected.feet, hand = selected.hand }
    native_outfit(inst, inst.components.skinner.clothing)
    Visual.OnSkinModeChanged(inst)
    dark(inst, "Native outfit change while dark")
    local expected = actor(); native_outfit(expected, inst.components.skinner.clothing)
    mode(inst, false); same(inst, snapshot(expected), "New native wardrobe restored")
    assert(inst.exchanges.skirt == "torso", "Actual untucked native shirt restores its torso/skirt exchange")
    native_audit_pass((is_dedicated and "dedicated" or "listen-host") .. ": current changed clothing restored including native untucked shirt exchanges")
end
dedicated = false
TheWorld.ismastersim = false
local observer = actor(); observer.components.skinner = nil
initial(observer)
mode(observer, true); Visual.Apply(observer); Visual.Clear(observer); Visual.OnSkinModeChanged(observer)
equal(observer.writes, 0, "Observers must not write competing replicated clothing commands")
equal(#observer.tasks, 0, "Observers have no periodic wardrobe tasks")
native_audit_pass("observer: zero wardrobe mutations or tasks")
print("Actual installed SetSkinsOnAnim/clothing-table audit complete; command-state contracts only, no GPU or Steam ownership simulation.")
