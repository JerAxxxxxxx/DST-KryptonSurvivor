local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function close(actual, expected, message)
    assert(math.abs(actual - expected) < 0.000001, message or "unexpected numeric value")
end

TUNING = { KRYPTON_SURVIVOR = {
    heatvision_damage = 2000, heatvision_range = 20,
    heatvision_width = 0.8, heatvision_interval = 0.35,
} }
RADIANS = 180 / math.pi
-- The game exposes atan2; Fengari provides the two-argument atan instead.
math.atan2 = function(y, x) return math.atan(y, x) end
TheWorld = { ismastersim = true }
TheNet = { paused = false, dedicated = false,
    IsServerPaused = function(self) return self.paused end,
    IsDedicated = function(self) return self.dedicated end,
}
local now, query_count, spawned, query_targets = 10, 0, {}, {}
GetTime = function() return now end

local function entity(x, z)
    local inst = { tags = {}, components = {}, valid = true, x = x or 0, z = z or 0 }
    inst.IsValid = function(self) return self.valid end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.GetPhysicsRadius = function(self, default) return self.radius or default end
    inst.Transform = { GetWorldPosition = function() return inst.x, 0, inst.z end }
    inst.components.health = { dead = false, IsDead = function(self) return self.dead end }
    inst.components.combat = { GetAttacked = function(self, attacker, damage, weapon, stimulus)
        self.hits = (self.hits or 0) + 1
        self.attacker, self.damage, self.weapon, self.stimulus = attacker, damage, weapon, stimulus
        if inst.dies_on_hit then inst.components.health.dead = true end
        if inst.removed_on_hit then inst.valid = false end
    end }
    inst.components.burnable = { Ignite = function(self, force, attacker, source)
        self.ignitions = (self.ignitions or 0) + 1
        self.force, self.attacker, self.source = force, attacker, source
    end }
    return inst
end

local function player()
    local inst = entity(0, 0)
    inst.prefab, inst.tags.kryptonian, inst.tags.player = "krypton_survivor", true, true
    inst.components.combat.CanTarget = function(self, target) return not target.untargetable end
    inst.components.playercontroller = {
        enabled = true, busy = false, working = false,
        IsEnabled = function(self) return self.enabled end,
        IsBusy = function(self) return self.busy end,
        IsDoingOrWorking = function(self) return self.working end,
    }
    inst.ForceFacePoint = function(self, x, y, z) self.facing = { x, y, z } end
    return inst
end

SpawnPrefab = function(name)
    equal(name, "krypton_heatvision_fx", "beam prefab")
    local fx = { SetCaster = function(self, caster, dx, dz)
        self.caster, self.dx, self.dz = caster, dx, dz
    end }
    table.insert(spawned, fx)
    return fx
end
TheSim = { FindEntities = function(self, x, y, z, radius, must, excluded)
    query_count = query_count + 1
    equal(must[1], "_combat", "only combat entities should be queried")
    local excludes_players = false
    for _, tag in ipairs(excluded) do if tag == "player" then excludes_players = true end end
    assert(excludes_players, "the broad-phase query must exclude players")
    close(radius, 13.8, "beam broad-phase covers large body intersections")
    return query_targets
end }
local HeatVision = load_source("mod/scripts/krypton_heatvision.lua")

-- Reject malformed RPC data before producing effects or acquiring targets.
local function reject(inst, x, z, description)
    local count, fx_count = query_count, #spawned
    equal(HeatVision.Cast(inst, x, z), false, description)
    equal(query_count, count, description .. " must not query targets")
    equal(#spawned, fx_count, description .. " must not emit beams")
    if inst ~= nil then equal(inst._krypton_heatvision_nextcast, nil, description .. " must not spend cooldown") end
end
reject(nil, 10, 0, "missing player")
for _, input in ipairs({ "10", false, {}, math.huge, -math.huge, 0 / 0 }) do
    reject(player(), input, 0, "invalid x coordinate")
    reject(player(), 10, input, "invalid z coordinate")
end
reject(player(), 0, 0, "zero-length beam")
reject(player(), 0.01, 0, "near-zero aim")
reject(player(), 1e308, 1e308, "finite coordinates with overflowing distance")
local invalid_players = {
    function(p) p.valid = false end,
    function(p) p.prefab = "wilson" end,
    function(p) p.tags.kryptonian = nil end,
    function(p) p.tags.playerghost = true end,
    function(p) p.components.health.dead = true end,
    function(p) p.components.health = nil end,
    function(p) p.components.combat = nil end,
    function(p) p.components.playercontroller = nil end,
    function(p) p.components.playercontroller.enabled = false end,
    function(p) p.components.playercontroller.busy = true end,
    function(p) p.components.playercontroller.working = true end,
}
for _, modify in ipairs(invalid_players) do
    local inst = player()
    modify(inst)
    reject(inst, 10, 0, "ineligible caster")
end
TheWorld.ismastersim = false
reject(player(), 10, 0, "client-side cast")
TheWorld.ismastersim = true
TheNet.paused = true
reject(player(), 10, 0, "paused server")
TheNet.paused = false

-- A point near the player sets direction, not beam length. A far point cannot
-- extend the 20-unit beam. Broad-phase results deliberately include allies.
local caster = player()
local center, edge, end_point = entity(5, 0), entity(12, 0.8), entity(20, 0)
local behind, wide, distant = entity(-0.01, 0), entity(5, 0.801), entity(20.81, 0)
behind.radius = 1
local large, end_overlap, beyond_cap = entity(12, 1.8), entity(21.5, 0), entity(21.5, 1.5)
large.radius, end_overlap.radius, beyond_cap.radius = 1, 1, 1
local dead, invalid, untargetable = entity(5, 0), entity(5, 0), entity(5, 0)
dead.components.health.dead, invalid.valid, untargetable.untargetable = true, false, true
local follower, immunity = entity(5, 0), entity(5, 0)
follower.components.follower = { leader = {} }
immunity.tags.fireimmune = true
local killed, removed, nonburnable = entity(5, 0), entity(5, 0), entity(5, 0)
killed.dies_on_hit, removed.removed_on_hit, nonburnable.components.burnable = true, true, nil
local protected = {}
for _, tag in ipairs({ "INLIMBO", "player", "playerghost", "companion", "wall", "structure", "FX", "notarget", "invisible", "player_aligned", "domesticated" }) do
    local victim = entity(5, 0)
    victim.tags[tag] = true
    table.insert(protected, victim)
end
query_targets = { center, edge, end_point, large, end_overlap, beyond_cap, behind, wide, distant, dead, invalid,
    untargetable, follower, immunity, killed, removed, nonburnable, caster }
for _, victim in ipairs(protected) do table.insert(query_targets, victim) end
equal(HeatVision.Cast(caster, 1, 0), true, "cast requires no equipment, hunger or sanity")
for _, victim in ipairs({ center, edge, end_point, large, end_overlap, immunity, killed, removed, nonburnable }) do
    equal(victim.components.combat.hits, 1, "beam target hit exactly once")
    equal(victim.components.combat.damage, 2000, "configured damage")
    equal(victim.components.combat.attacker, caster, "damage credited to caster")
    equal(victim.components.combat.weapon, nil, "innate power requires no weapon")
    equal(victim.components.combat.stimulus, "fire", "fire damage stimulus")
end
for _, victim in ipairs({ behind, wide, distant, beyond_cap, dead, invalid, untargetable, follower, caster }) do
    equal(victim.components.combat.hits, nil, "excluded target remains unharmed")
end
for _, victim in ipairs(protected) do equal(victim.components.combat.hits, nil, "ally or structure remains unharmed") end
for _, victim in ipairs({ center, edge, end_point }) do
    equal(victim.components.burnable.ignitions, 1, "surviving targets ignite")
    equal(victim.components.burnable.attacker, caster, "fire credited to caster")
end
for _, victim in ipairs({ immunity, killed, removed, follower, dead }) do
    equal(victim.components.burnable.ignitions, nil, "immune, dead, removed or protected target must not ignite")
end
equal(#spawned, 1, "one shared network cast for observer-specific eye positions")
equal(spawned[1].caster, caster, "shared cast identifies its animated caster")
close(spawned[1].dx, 1, "shared cast direction x")
close(spawned[1].dz, 0, "shared cast direction z")
close(caster._krypton_heatvision_nextcast, 10.35, "server interval")
local queries_after_cast = query_count
now = 10.349
equal(HeatVision.Cast(caster, 1000, 0), false, "rapid RPC repetition blocked")
equal(query_count, queries_after_cast, "repeated RPC performs no query")
query_targets = { distant }
now = 10.35
equal(HeatVision.Cast(caster, 1000, 0), true, "cast available at cooldown boundary")
equal(distant.components.combat.hits, nil, "far aim point cannot extend range")

-- A non-axis-aligned shot catches targets on its own line, not the world axes.
local diagonal, axis_target = entity(10, 10), entity(10, 0)
query_targets = { diagonal, axis_target }
equal(HeatVision.Cast(player(), 1, 1), true, "diagonal cast")
equal(diagonal.components.combat.hits, 1, "diagonal target hit")
equal(axis_target.components.combat.hits, nil, "off-line target excluded")
TUNING.KRYPTON_SURVIVOR.heatvision_damage = 50000
local new_damage_target = entity(0, -4)
query_targets = { new_damage_target }
equal(HeatVision.Cast(player(), 0, -1), true, "negative direction supported")
equal(new_damage_target.components.combat.damage, 50000, "cast reads current configured damage")

local register_input = load_source("mod/scripts/krypton_heatvision_input.lua")
local function input_fixture()
    local G = { TUNING = TUNING, ThePlayer = player(), time = 20, paused = false,
        TheNet = { dedicated = false, paused = false,
            IsDedicated = function(self) return self.dedicated end,
            IsServerPaused = function(self) return self.paused end,
        },
        TheInput = { registered = 0, hud_entity = nil, position = { x = 7, z = -3 },
            AddKeyDownHandler = function(self, key, fn)
                self.registered, self.key, self.handler = self.registered + 1, key, fn
            end,
            GetHUDEntityUnderMouse = function(self) return self.hud_entity end,
            GetWorldPosition = function(self) return self.position end,
        }, sent = {},
    }
    G.GetTime = function() return G.time end
    G.IsPaused = function() return G.paused end
    G.ThePlayer.HUD = { focused = false, HasInputFocus = function(self) return self.focused end }
    G.send = function(x, z) table.insert(G.sent, { x = x, z = z }) end
    return G
end
local disabled = input_fixture()
register_input(disabled, nil, disabled.send)
equal(disabled.TheInput.registered, 0, "disabled hotkey installs no handler")
local dedicated = input_fixture()
dedicated.TheNet.dedicated = true
register_input(dedicated, 114, dedicated.send)
equal(dedicated.TheInput.registered, 0, "dedicated server installs no keyboard handler")
local input_rejections = {
    function(G) G.ThePlayer = nil end,
    function(G) G.ThePlayer.valid = false end,
    function(G) G.ThePlayer.prefab = "wilson" end,
    function(G) G.ThePlayer.tags.playerghost = true end,
    function(G) G.ThePlayer.tags.busy = true end,
    function(G) G.ThePlayer.HUD = nil end,
    function(G) G.ThePlayer.HUD.focused = true end,
    function(G) G.paused = true end,
    function(G) G.TheNet.paused = true end,
    function(G) G.TheInput.hud_entity = {} end,
    function(G) G.ThePlayer.components.playercontroller = nil end,
    function(G) G.ThePlayer.components.playercontroller.enabled = false end,
    function(G) G.ThePlayer.components.playercontroller.busy = true end,
    function(G) G.ThePlayer.components.playercontroller.working = true end,
    function(G) G.ThePlayer.components.playercontroller.placer = {} end,
    function(G) G.TheInput.position = nil end,
}
for _, modify in ipairs(input_rejections) do
    local G = input_fixture()
    register_input(G, 114, G.send)
    modify(G)
    G.TheInput.handler()
    equal(#G.sent, 0, "blocked input must not send an RPC")
end
local G = input_fixture()
register_input(G, 114, G.send)
equal(G.TheInput.registered, 1, "one handler registered")
equal(G.TheInput.key, 114, "configured key respected")
G.ThePlayer.HUD.focused = true
G.TheInput.handler()
G.ThePlayer.HUD.focused = false
G.TheInput.handler()
equal(#G.sent, 1, "chat focus does not consume cooldown")
equal(G.sent[1].x, 7, "RPC x aim")
equal(G.sent[1].z, -3, "RPC z aim")
G.time = 20.349
G.TheInput.handler()
equal(#G.sent, 1, "client debounce limits repeated key events")
G.time = 20.35
G.TheInput.handler()
equal(#G.sent, 2, "client debounce expires at server interval")

-- One network cast spawns local eye beams that track each observer's animated
-- symbol positions. The fixture records those engine positions independently
-- of the renderer's root offset so its visible endpoints can be checked.
Asset = function(kind, path) return { kind = kind, path = path } end
Prefab = function(name, fn, assets) return { name = name, fn = fn, assets = assets } end
ANIM_ORIENTATION = { OnGround = 1 }
DEGREES = math.pi / 180
FACING_RIGHT, FACING_UP, FACING_LEFT, FACING_DOWN = 0, 1, 2, 3
FACING_UPRIGHT, FACING_DOWNRIGHT, FACING_UPLEFT, FACING_DOWNLEFT = 4, 5, 6, 7
unpack = table.unpack
local entities = {}
CreateEntity = function()
    local inst = { components = {}, tags = {}, tasks = {}, removed = false, GUID = #entities + 1 }
    table.insert(entities, inst)
    inst.entity = {}
    for _, component in ipairs({ "Transform", "AnimState", "SoundEmitter", "Network" }) do
        inst.entity["Add" .. component] = function() inst["has_" .. component] = true end
    end
    inst.entity.SetPristine = function() inst.pristine = true end
    inst.entity.SetParent = function(self, parent) self.parent = parent end
    inst.Transform = {
        SetPosition = function(self, x, y, z) self.position = { x, y, z } end,
        SetRotation = function(self, angle) self.rotation = angle end,
    }
    inst.AddTag = function(self, tag) self.tags[tag] = true end
    inst.entity.SetCanSleep = function(self, value) inst.can_sleep = value end
    inst.AddComponent = function(self, name)
        equal(name, "updatelooper", "FX only requires a local animation update loop")
        self.components[name] = { AddPostUpdateFn = function(component, fn) component.update = fn end }
    end
    inst.AnimState = {}
    for _, method in ipairs({ "SetBank", "SetBuild", "PlayAnimation", "SetOrientation", "SetBloomEffectHandle", "SetLightOverride", "SetMultColour", "SetAddColour", "SetScale", "SetFinalOffset" }) do
        inst.AnimState[method] = function(self, ...) self[method .. "_args"] = { ... } end
    end
    inst.SoundEmitter = { PlaySound = function(self, sound, channel, volume)
        self.sound, self.channel, self.volume = sound, channel, volume
    end }
    inst.DoTaskInTime = function(self, delay, fn) table.insert(self.tasks, { delay = delay, fn = fn }) end
    inst.Remove = function(self)
        self.removed = true
        if self.OnRemoveEntity ~= nil then self.OnRemoveEntity(self) end
    end
    return inst
end
local function net_value(initial)
    return { stored = initial,
        set = function(self, value) self.stored = value end,
        value = function(self) return self.stored end,
    }
end
net_entity = function() return net_value(nil) end
net_float = function() return net_value(0) end
package.preload["krypton_heatvision_visual_data"] = function()
    return load_source("mod/scripts/krypton_heatvision_visual_data.lua")
end
package.preload["krypton_heatvision_visual"] = function()
    return load_source("mod/scripts/krypton_heatvision_visual.lua")
end
local Data = require("krypton_heatvision_visual_data")
local Visual = require("krypton_heatvision_visual")

local function visual_caster()
    local inst = player()
    inst.entity = {}
    inst.facing, inst.pose_y, inst.pose_x, inst.pose_z = FACING_DOWN, 2.2, 3, 4
    inst.animation, inst.animation_frame, inst.facing_queries = "idle", 0, 0
    inst.head_found, inst.hat_found, inst.symbol_calls = true, false, {}
    inst.AnimState = {
        MakeFacingDirty = function() inst.facing_dirty = true end,
        GetCurrentFacing = function()
            assert(inst.facing_dirty, "refresh facing cache before reading current eye pose")
            inst.facing_dirty = false
            inst.facing_queries = inst.facing_queries + 1
            return inst.facing
        end,
        IsCurrentAnimation = function(self, animation) return inst.animation == animation end,
        GetCurrentAnimationFrame = function() return inst.animation_frame end,
        GetSymbolPosition = function(self, symbol, x, y, z)
            table.insert(inst.symbol_calls, { symbol, x, y, z })
            local found = symbol == "headbase" and inst.head_found
                or symbol == "headbase_hat" and inst.hat_found
            -- Simulate engine-applied mirroring and a changing animation frame.
            local mirror = inst.facing == FACING_LEFT and -1 or 1
            return inst.pose_x + mirror * x / 150, inst.pose_y - y / 150, inst.pose_z, found
        end,
    }
    return inst
end

local function verify_ray(eye, origin, angle)
    local theta = angle * DEGREES
    local dx, dz = math.cos(theta), -math.sin(theta)
    for _, ray in ipairs({ eye.halo, eye.core }) do
        local position = ray.Transform.position
        local scale = ray.AnimState.SetScale_args[1]
        -- Independently reconstruct the native art's actual left/right edges.
        -- Both must be exact: no glow extends behind the eye and the far edge
        -- is 20 world units ahead, even though the source art is asymmetric.
        local source_left, source_right, pixels_per_unit = -183, 176, 150
        close(position[1] + dx * source_left * scale / pixels_per_unit, origin[1], "beam starts at actual eye x")
        close(position[2], origin[2], "beam keeps animated eye height")
        close(position[3] + dz * source_left * scale / pixels_per_unit, origin[3], "beam starts at actual eye z")
        close(position[1] + dx * source_right * scale / pixels_per_unit, origin[1] + dx * 20, "beam reaches full range x")
        close(position[3] + dz * source_right * scale / pixels_per_unit, origin[3] + dz * 20, "beam reaches full range z")
        close(ray.Transform.rotation, angle, "local ray preserves cast angle")
        equal(ray.has_Network, nil, "eye artwork is local to each observer")
        equal(ray.can_sleep, false, "local rays must not disappear independently")
        equal(next(ray.components), nil, "local artwork must not acquire damage components")
    end
    if eye.spark ~= nil then
        for axis = 1, 3 do close(eye.spark.Transform.position[axis], origin[axis], "face glow stays at eye") end
        equal(eye.spark.AnimState.SetBank_args[1], "bishop_attack", "stock eye glow source")
    end
end

local fx_prefab = load_source("mod/scripts/prefabs/krypton_heatvision_fx.lua")
equal(fx_prefab.name, "krypton_heatvision_fx", "network beam prefab name")
equal(fx_prefab.assets[1].path, "anim/wagdrone_laserwire_fx.zip", "stock beam loaded from installed game")
TheWorld.ismastersim = false
local client_fx = fx_prefab.fn()
assert(client_fx.has_Network and client_fx.pristine, "client FX must replicate")
assert(client_fx.tags.FX and client_fx.tags.NOCLICK and client_fx.tags.NOBLOCK, "FX must be noninteractive")
assert(client_fx.components.updatelooper ~= nil, "observer updates after animated symbols")
equal(client_fx.components.updatelooper.update, Visual.Update, "post-animation updates are registered")
equal(client_fx.has_AnimState, nil, "shared cast itself has no fixed-height art")
equal(#client_fx.tasks, 0, "client leaves removal to authoritative server")
equal(client_fx.SoundEmitter.sound, nil, "server owns beam sound")
equal(client_fx.persists, false, "temporary beam must not be saved")
equal(client_fx.SetCaster, nil, "clients cannot author server caster state")
local initial_entities = #entities
Visual.Update(client_fx)
equal(#entities, initial_entities, "unresolved replicated caster creates no orphan visuals")

local actor = visual_caster()
client_fx._caster:set(actor)
client_fx._angle:set(37)
client_fx.components.updatelooper.update(client_fx)
equal(client_fx._eye_pose, "front", "front-facing eye layout")
equal(#client_fx._eyes, 2, "front has two separate eye origins")
close(actor.symbol_calls[1][2], -25.95152, "left eye is authored head pixel")
close(actor.symbol_calls[2][2], 20.54304, "right eye is authored head pixel")
close(actor.symbol_calls[1][3], -62.22336, "left eye height is authored head pixel")
close(actor.symbol_calls[2][3], -62.86848, "right eye height is authored head pixel")
local front_eyes = client_fx._eyes
for index, point in ipairs(Data.front.eyes) do
    local origin = { actor.pose_x + point[1] / 150, actor.pose_y - point[2] / 150, actor.pose_z }
    verify_ray(front_eyes[index], origin, 37)
    assert(front_eyes[index].spark ~= nil, "visible eyes get small origin glow")
end

-- Animation/prediction moves the head. Reuse the local entities and update
-- their world positions rather than fixing the cast at its original midpoint.
local entity_count = #entities
actor.pose_x, actor.pose_y, actor.pose_z = 13, 1.8, -8
client_fx._angle:set(-113)
client_fx.components.updatelooper.update(client_fx)
equal(#entities, entity_count, "per-frame tracking reuses local artwork")
equal(client_fx._eyes, front_eyes, "animated frame retains eye entities")
for index, point in ipairs(Data.front.eyes) do
    verify_ray(front_eyes[index], { 13 + point[1] / 150, 1.8 - point[2] / 150, -8 }, -113)
end

-- Side views use one visible eye; left-facing symbol positions are mirrored by
-- the engine. Turning to the back removes face glow and restores two rays.
actor.facing = FACING_LEFT
Visual.Update(client_fx)
equal(#client_fx._eyes, 1, "side has one visible eye")
for _, eye in ipairs(front_eyes) do
    assert(eye.halo.removed and eye.core.removed and eye.spark.removed, "facing switch clears all old front art")
end
local side_eye = client_fx._eyes[1]
verify_ray(side_eye, { 13 - 8.6208 / 150, 1.8 + 68.50432 / 150, -8 }, -113)
assert(side_eye.spark ~= nil, "side-facing eye has visible origin glow")
for _, facing in ipairs({ FACING_UP, FACING_UPRIGHT, FACING_UPLEFT }) do
    actor.facing = facing
    Visual.Update(client_fx)
    equal(client_fx._eye_pose, "back", "all upward facings use back layout")
    equal(#client_fx._eyes, 2, "back keeps paired rays")
    for _, eye in ipairs(client_fx._eyes) do equal(eye.spark, nil, "back view cannot glow through face") end
end
assert(side_eye.halo.removed and side_eye.core.removed and side_eye.spark.removed, "back switch removes side art")
actor.facing = FACING_RIGHT
Visual.Update(client_fx)
equal(#client_fx._eyes, 1, "right side also uses a single eye")
for _, facing in ipairs({ FACING_DOWN, FACING_DOWNRIGHT, FACING_DOWNLEFT }) do
    actor.facing = facing
    Visual.Update(client_fx)
    equal(client_fx._eye_pose, "front", "all downward facings use front layout")
end
assert(actor.facing_queries > 0, "renderer checks refreshed facing each update")

-- Native mounted animations use a front head for horizontal idle/run and a
-- profile head during walk. The two-frame walk-post transition must follow
-- the head actually displayed, with upward facings always using the back.
actor.replica = { rider = { riding = true, IsRiding = function(self) return self.riding end } }
actor.facing, actor.animation = FACING_RIGHT, "idle"
Visual.Update(client_fx)
equal(client_fx._eye_pose, "front", "mounted horizontal idle has front head")
equal(#client_fx._eyes, 2, "mounted idle uses both front eyes")
actor.animation = "run_loop"
Visual.Update(client_fx)
equal(client_fx._eye_pose, "front", "mounted horizontal run has front head")
actor.animation = "walk_loop"
Visual.Update(client_fx)
equal(client_fx._eye_pose, "side", "mounted horizontal walk has profile head")
equal(#client_fx._eyes, 1, "mounted walk uses visible profile eye")
actor.facing, actor.animation, actor.animation_frame = FACING_LEFT, "walk_pst", 1
Visual.Update(client_fx)
equal(client_fx._eye_pose, "side", "early mounted walk-post keeps profile head")
actor.animation_frame = 2
Visual.Update(client_fx)
equal(client_fx._eye_pose, "front", "mounted walk-post switches to front on frame two")
actor.facing = FACING_UPRIGHT
Visual.Update(client_fx)
equal(client_fx._eye_pose, "back", "mounted upward diagonal uses back head")
for _, eye in ipairs(client_fx._eyes) do equal(eye.spark, nil, "mounted back face gets no eye glow") end
actor.replica.rider.riding, actor.facing = false, FACING_LEFT
Visual.Update(client_fx)
equal(client_fx._eye_pose, "side", "unmounted rider replica follows ground-facing profile")
actor.replica, actor.facing, actor.animation = nil, FACING_DOWN, "idle"
Visual.Update(client_fx)

-- A hat switches the head symbol used by native animations. Missing symbols
-- must clear stale beams rather than falling back to a torso-height offset.
actor.head_found, actor.hat_found, actor.symbol_calls = false, true, {}
Visual.Update(client_fx)
equal(actor.symbol_calls[1][1], "headbase", "first try ordinary head")
equal(actor.symbol_calls[2][1], "headbase_hat", "hat symbol fallback")
equal(actor.symbol_calls[1][2], actor.symbol_calls[2][2], "hat keeps authored eye offset")
local hat_eyes = client_fx._eyes
actor.hat_found = false
Visual.Update(client_fx)
equal(client_fx._eyes, nil, "unavailable head symbols clear stale rays")
for _, eye in ipairs(hat_eyes) do assert(eye.halo.removed and eye.core.removed and eye.spark.removed) end
actor.head_found = true
Visual.Update(client_fx)
assert(client_fx._eyes ~= nil, "visuals recover when an animated head is present")

local awake_eyes = client_fx._eyes
client_fx.OnEntitySleep(client_fx)
equal(client_fx._eyes, nil, "sleep clears local artwork")
for _, eye in ipairs(awake_eyes) do assert(eye.halo.removed and eye.core.removed and eye.spark.removed) end
entity_count = #entities
Visual.Update(client_fx)
equal(#entities, entity_count, "updates cannot recreate artwork while sleeping")
client_fx.OnEntityWake(client_fx)
assert(client_fx._eyes ~= nil, "wake resolves current head pose again")
actor.tags.playerghost = true
Visual.Update(client_fx)
equal(client_fx._eyes, nil, "ghost caster does not retain eye rays")
actor.tags.playerghost, actor.valid = nil, false
Visual.Update(client_fx)
equal(client_fx._eyes, nil, "invalid caster does not create visuals")
actor.valid = true
Visual.Update(client_fx)
local last_eyes = client_fx._eyes
client_fx:Remove()
equal(client_fx._eyes, nil, "network removal cleans up all local eyes")
for _, eye in ipairs(last_eyes) do assert(eye.halo.removed and eye.core.removed and eye.spark.removed) end

TheWorld.ismastersim = true
local server_fx = fx_prefab.fn()
server_fx:SetCaster(actor, 0, -1)
equal(server_fx._caster:value(), actor, "replicated caster identity")
close(server_fx._angle:value(), 90, "replicated cast angle")
equal(server_fx.entity.parent, actor.entity, "caster parent keeps network interest with player")
for axis = 1, 3 do equal(server_fx.Transform.position[axis], 0, "network cast remains attached to caster root") end
assert(server_fx._eyes ~= nil, "host renders local eye positions too")
equal(#server_fx.tasks, 1, "server schedules beam cleanup")
equal(server_fx.tasks[1].delay, 0.3, "beam lifetime")
local host_eyes = server_fx._eyes
server_fx.tasks[1].fn(server_fx)
equal(server_fx.removed, true, "beam cleanup removes network entity")
for _, eye in ipairs(host_eyes) do assert(eye.halo.removed and eye.core.removed and eye.spark.removed) end
assert(server_fx.SoundEmitter.sound ~= nil, "server starts beam sound")

TheNet.dedicated = true
entity_count = #entities
local dedicated_fx = fx_prefab.fn()
dedicated_fx:SetCaster(actor, 1, 0)
equal(#entities, entity_count + 1, "dedicated server creates only the shared network cast")
equal(next(dedicated_fx.components), nil, "dedicated server has no render update loop")
equal(dedicated_fx._eyes, nil, "dedicated server does not build local eye artwork")
equal(dedicated_fx.OnEntityWake, nil, "dedicated server has no visual lifecycle hooks")
equal(dedicated_fx.has_AnimState, nil, "dedicated cast has no fixed-height art")
equal(dedicated_fx._caster:value(), actor, "dedicated cast replicates caster for observers")

print("Heat vision tests passed: server validation, line targeting, fire, cooldown, input guards, animated eye origins, forward-only geometry, facing layouts and network/local visual cleanup.")
