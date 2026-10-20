local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local Targets = load_source("mod/scripts/krypton_combat_targets.lua")
package.preload["krypton_combat_targets"] = function() return Targets end
local HeatVision = load_source("mod/scripts/krypton_heatvision.lua")
local FrostBreath = load_source("mod/scripts/krypton_frostbreath.lua")
DEGREES, RADIANS = math.pi / 180, 180 / math.pi
TheWorld = { ismastersim = true }
TheNet = { IsServerPaused = function() return false end }
GetTime = function() return 30 end
TUNING = { KRYPTON_SURVIVOR = { heatvision_damage = 2000, heatvision_range = 20,
    heatvision_width = .8, heatvision_interval = .35, frostbreath_enabled = true,
    frostbreath_range = 8, frostbreath_half_angle = 28, frostbreath_duration = 1,
    frostbreath_interval = 1.2, frostbreath_coldness = 2, frostbreath_freezetime = 4,
    staff_damage = 2000, staff_aoe_radius = 5, staff_range = 6, work_efficiency = 10 } }
local function noop() end
local function entity()
    local inst = { tags = {}, components = {}, valid = true, listeners = {} }
    function inst:IsValid() return self.valid end
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:GetPhysicsRadius(default) return default end
    function inst:PushEvent() end
    function inst:ListenForEvent(name, fn) self.listeners[name] = fn end
    function inst:RemoveEventCallback(name, fn) if self.listeners[name] == fn then self.listeners[name] = nil end end
    function inst:DoTaskInTime() return { Cancel = noop } end
    inst.DoPeriodicTask = inst.DoTaskInTime
    inst.Transform = { GetWorldPosition = function() return 3, 0, 0 end }
    inst.ForceFacePoint = noop
    inst.components.health = { IsDead = function() return inst.dead == true end }
    inst.components.combat = {
        CanTarget = function(_, target) return not target.untargetable end,
        GetAttacked = function(self, _, damage) self.hits = (self.hits or 0) + 1; self.damage = damage end,
    }
    inst.components.freezable = { AddColdness = function(self, amount) self.calls = (self.calls or 0) + 1; self.amount = amount end }
    inst.components.burnable = {
        IsBurning = function(self) return self.burning == true end, IsSmoldering = function() return false end,
        Extinguish = function(self) self.extinguished = (self.extinguished or 0) + 1; self.burning = false end,
        Ignite = function(self) self.ignitions = (self.ignitions or 0) + 1 end,
    }
    return inst
end
local function caster()
    local inst = entity()
    inst.prefab, inst.tags.player, inst.tags.kryptonian = "krypton_survivor", true, true
    inst.Transform.GetWorldPosition = function() return 0, 0, 0 end
    inst.components.playercontroller = { IsEnabled = function() return true end,
        IsBusy = function() return false end, IsDoingOrWorking = function() return false end }
    return inst
end
SpawnPrefab = function() return { IsValid = function() return true end, Remove = noop, SetCaster = noop } end
local query_targets = {}
TheSim = { FindEntities = function() return query_targets end }

-- Each attack receives deliberately unfiltered broad-phase results so that
-- the server's final protection check, not only the query tags, is exercised.
local policy_tags = { "INLIMBO", "player", "playerghost", "companion", "wall", "structure",
    "FX", "notarget", "invisible", "player_aligned", "domesticated" }
local function matrix()
    local protected, ordinary = {}, { entity(), entity() }
    ordinary[2].components.follower = {} -- A wild creature without a leader remains targetable.
    for _, tag in ipairs(policy_tags) do
        local target = entity(); target.tags[tag] = true; protected[#protected + 1] = target
        assert(Targets.IsProtected(target), "shared policy must protect " .. tag)
    end
    local following = entity(); following.components.follower = { leader = {} }; protected[#protected + 1] = following
    local dead, invalid, untargetable = entity(), entity(), entity()
    dead.dead, invalid.valid, untargetable.untargetable = true, false, true
    local skipped = { dead, invalid, untargetable }
    query_targets = {}
    for _, group in ipairs({ ordinary, protected, skipped }) do
        for _, target in ipairs(group) do query_targets[#query_targets + 1] = target end
    end
    return protected, ordinary, skipped
end
assert(Targets.IsProtected(nil), "missing targets are never eligible for splash or skills")
assert(not Targets.IsProtected(entity()), "ordinary wildlife remains targetable")

Asset = function() return {} end
Prefab = function(_, fn) return { fn = fn } end
MakeInventoryPhysics, MakeInventoryFloatable, MakeHauntableLaunch = noop, noop, noop
ACTIONS = { CHOP = {}, MINE = {}, HAMMER = {}, DIG = {} }
CreateEntity = function()
    local inst = entity(); inst.components = {}
    inst.entity = { AddTransform = noop, AddAnimState = noop, AddSoundEmitter = noop, AddLight = noop,
        AddNetwork = noop, SetPristine = noop }
    inst.AnimState = { SetBank = noop, SetBuild = noop, PlayAnimation = noop }
    inst.Light = { SetRadius = noop, SetFalloff = noop, SetIntensity = noop, SetColour = noop, Enable = noop }
    function inst:AddTag(tag) self.tags[tag] = true end
    inst.WatchWorldState = noop
    function inst:AddComponent(name)
        local component = {}
        for _, method in ipairs({ "SetOnPutInInventoryFn", "ChangeImageName", "SetOnEquip", "SetOnUnequip",
            "SetRange", "SetAction", "EnableToughWork" }) do component[method] = noop end
        function component:SetDamage(value) self.damage = value end
        function component:SetOnAttack(fn) self.onattack = fn end
        self.components[name] = component
    end
    return inst
end
local weapon = load_source("mod/scripts/prefabs/krypton_staff.lua").fn()
equal(weapon.components.weapon.damage, 2000, "shared protection does not lower weapon damage")
local primary = entity()

for _, attack in ipairs({ "heat", "frost", "splash" }) do
    local protected, ordinary, skipped = matrix()
    local actor = caster()
    if attack == "heat" then
        assert(HeatVision.Cast(actor, 1, 0), "heat vision cast remains available")
    elseif attack == "frost" then
        for _, target in ipairs(protected) do
            if target:HasTag("player") or target:HasTag("structure") or target:HasTag("domesticated")
                or target.components.follower ~= nil then target.components.burnable.burning = true end
        end
        assert(FrostBreath.Cast(actor, 1, 0), "frost breath cast remains available")
        actor._krypton_frostbreath_channel.stop()
    else
        query_targets[#query_targets + 1] = actor
        query_targets[#query_targets + 1] = primary
        weapon.components.weapon.onattack(weapon, actor, primary)
        equal(primary.components.combat.hits, nil, "splash does not duplicate the primary melee hit")
        equal(actor.components.combat.hits, nil, "splash does not hit its attacker")
    end
    for _, target in ipairs(ordinary) do
        if attack == "frost" then
            equal(target.components.freezable.calls, 1, "ordinary and unled creatures still receive coldness")
            equal(target.components.freezable.amount, 2, "configured coldness remains unchanged")
        else equal(target.components.combat.hits, 1, "ordinary and unled creatures still take damage") end
    end
    for _, group in ipairs({ protected, skipped }) do
        for _, target in ipairs(group) do
            equal(target.components.combat.hits, nil, attack .. " must not damage protected/invalid targets")
            equal(target.components.freezable.calls, nil, attack .. " must not freeze protected/invalid targets")
            equal(target.components.burnable.ignitions, nil, attack .. " must not ignite protected/invalid targets")
            if attack == "frost" and (target:HasTag("player") or target:HasTag("structure")
                or target:HasTag("domesticated") or target.components.follower ~= nil) then
                equal(target.components.burnable.extinguished, 1, "protected friends/buildings can still be rescued from fire")
            end
        end
    end
end
print("Combat protection: shared friendly-target matrix, native targeting, unchanged damage and independent friendly extinguishing passed.")
