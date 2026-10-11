local function load_source(path)
    local chunk, err = load(read_project_file(path), "@" .. path)
    assert(chunk, err)
    return chunk()
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function close(actual, expected, message)
    assert(math.abs(actual - expected) < 0.000001, message or "unexpected number")
end

FRAMES = 1 / 30
TILE_SCALE = 10
COLLISION = { GROUND = 1, LAND_OCEAN_LIMITS = 2, BOAT_LIMITS = 4, OBSTACLES = 8, CHARACTERS = 16 }
MAX_PHYSICS_RADIUS = 3
checkbit = function(mask, flag) return mask % (flag * 2) >= flag end
Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
net_bool = function()
    return { stored = false, value = function(self) return self.stored end,
        set = function(self, value) self.stored = value end }
end
local now, world, occupancy, teleport_permitted, sound_entities
GetTime = function() return now end
CreateEntity = function()
    local sound = { valid = true, tags = {}, entity = {}, plays = 0 }
    sound.AddTag = function(self, tag) self.tags[tag] = true end
    sound.IsValid = function(self) return self.valid end
    sound.Hide = function(self) self.hidden = true end
    sound.Remove = function(self) self.valid = false; self.removed = true end
    sound.entity.SetCanSleep = function(self, value) self.can_sleep = value end
    sound.entity.AddTransform = function() sound.Transform = {} end
    sound.entity.SetParent = function(self, parent) self.parent = parent end
    sound.entity.AddSoundEmitter = function()
        sound.SoundEmitter = {
            PlaySound = function(self, path, handle, volume)
                sound.path, sound.handle, sound.volume = path, handle, volume
                sound.plays = sound.plays + 1
            end,
            KillSound = function(self, handle) sound.killed = handle end,
        }
    end
    -- No AddNetwork method: playback must use a local child, not a second
    -- replicated emitter that would play over the host's native sound event.
    table.insert(sound_entities, sound)
    return sound
end
IsTeleportingPermittedFromPointToPoint = function(sx, sy, sz, x, y, z) return teleport_permitted end
package.preload["componentutil"] = function() return {} end
package.preload["krypton_flight_visual"] = function() return load_source("mod/scripts/krypton_flight_visual.lua") end
package.preload["krypton_flight"] = function() return load_source("mod/scripts/krypton_flight.lua") end
local Flight = require("krypton_flight")

local function reset_world()
    now, occupancy, teleport_permitted, ThePlayer, sound_entities = 10, {}, true, nil, {}
    TUNING = { KRYPTON_SURVIVOR = { speed = 2, flight_enabled = true,
        flight_toggle_interval = .35, map_teleport_enabled = true, map_teleport_interval = .5 } }
    TheNet = { paused = false, dedicated = false,
        IsServerPaused = function(self) return self.paused end,
        IsDedicated = function(self) return self.dedicated end }
    world = { ismastersim = true, ground = true, terrain = "land", blocked = false,
        path_clear = true, destination_platform = nil }
    world.Map = {
        -- Match the native helper's inclusive extra edge; tile bounds below
        -- exclude that edge and represent actual valid map cells.
        IsInMapBounds = function(self, x, y, z)
            assert(math.abs(x) < 1e7 and math.abs(z) < 1e7, "raw world range must protect native coordinate helpers")
            return x >= -100 and x <= 100 and z >= -100 and z <= 100
        end,
        GetTileCoordsAtPoint = function(self, x, y, z)
            assert(math.abs(x) < 1e7 and math.abs(z) < 1e7, "huge RPC values must never reach native tile conversion")
            return math.floor((x + 100) / 10), math.floor((z + 100) / 10)
        end,
        GetSize = function() return 20, 20 end,
        IsVisualGroundAtPoint = function() return world.ground end,
        IsPassableAtPoint = function(self, x, y, z, allow_ocean)
            world.last_allow_ocean = allow_ocean
            local tx, tz = self:GetTileCoordsAtPoint(x, y, z)
            return tx >= 0 and tz >= 0 and tx < 20 and tz < 20
                and (world.terrain == "land" or (world.terrain == "ocean" and allow_ocean))
        end,
        GetPlatformAtPoint = function() return world.destination_platform end,
        IsGroundTargetBlocked = function(self, position, radius) return world.blocked end,
    }
    world.Pathfinder = { IsClear = function(self, sx, sy, sz, x, y, z, caps)
        equal(caps.ignorewalls, false, "landing cannot ignore native walls")
        return world.path_clear
    end }
    TheWorld = world
    TheSim = { FindEntities = function(self, x, y, z, radius, must, excluded)
        equal(y, 0, "landing collision query is at ground height")
        return occupancy
    end }
end

local next_guid = 0
local function player()
    next_guid = next_guid + 1
    local inst = { GUID = next_guid, prefab = "krypton_survivor", valid = true,
        tags = { player = true, kryptonian = true }, components = {}, events = {}, tasks = {},
        x = 5, y = 0, z = 6, radius = .5, log = {}, entity = {}, asleep = false }
    local function record(event) table.insert(inst.log, event) end
    inst.IsValid = function(self) return self.valid end
    inst.IsAsleep = function(self) return self.asleep end
    inst.HasTag = function(self, tag) return self.tags[tag] == true end
    inst.AddTag = function(self, tag) self.tags[tag] = true end
    inst.RemoveTag = function(self, tag) self.tags[tag] = nil end
    inst.ListenForEvent = function(self, event, fn) self.events[event] = fn end
    inst.DoPeriodicTask = function(self, period, fn) table.insert(self.tasks, { period = period, fn = fn }) end
    inst.DoTaskInTime = function(self, delay, fn)
        local task = { delay = delay, fn = fn, cancelled = false,
            Cancel = function(self) self.cancelled = true end }
        table.insert(self.tasks, task)
        return task
    end
    inst.GetPhysicsRadius = function(self, fallback) return self.radius or fallback end
    inst.GetCurrentPlatform = function(self) return self.platform end
    inst.ClearBufferedAction = function(self) self.buffer_cleared = true; record("clear_action") end
    inst.PushEvent = function(self, event) self.pushed_event = event; record("event") end
    inst.SnapCamera = function(self) self.camera_snapped = true; record("camera") end
    inst.Transform = { GetWorldPosition = function() return inst.x, inst.y, inst.z end }
    inst.AnimState = { animation = "attack", plays = 0, length = 1,
        AddOverrideBuild = function(self, build) self.override_build = build end,
        IsCurrentAnimation = function(self, animation) return self.animation == animation end,
        PlayAnimation = function(self, animation, loop) self.animation, self.loop = animation, loop; self.plays = self.plays + 1 end,
        GetCurrentAnimationLength = function(self) return self.length end,
        SetTime = function(self, time) self.phase = time end,
    }
    inst.Physics = {
        active = true, mask = 31, group = COLLISION.CHARACTERS,
        IsActive = function(self) return self.active end,
        GetCollisionMask = function(self) return self.mask end,
        GetCollisionGroup = function(self) return self.group end,
        ClearCollidesWith = function(self, flag)
            assert(flag == 2 or flag == 4, "flight cannot clear ground or obstacle collisions")
            if checkbit(self.mask, flag) then self.mask = self.mask - flag end
        end,
        CollidesWith = function(self, flag)
            if not checkbit(self.mask, flag) then self.mask = self.mask + flag end
        end,
        Stop = function(self) self.stopped = true; record("physics_stop") end,
        Teleport = function(self, x, y, z)
            inst.x, inst.y, inst.z = x, y, z
            self.teleports = (self.teleports or 0) + 1
            record("teleport")
        end,
    }
    inst.components.health = { dead = false, IsDead = function(self) return self.dead end }
    inst.components.drownable = { enabled = true }
    inst.components.locomotor = {
        directdrive = false, enablegroundspeedmultiplier = true, triggerscreep = true,
        allow_platform_hopping = true, pathcaps = { allowocean = false, ignorecreep = false },
        ResetPath = function(self) self.path_resets = (self.path_resets or 0) + 1 end,
        EnableGroundSpeedMultiplier = function(self, value) self.enablegroundspeedmultiplier = value end,
        SetTriggersCreep = function(self, value) self.triggerscreep = value end,
        SetAllowPlatformHopping = function(self, value) self.allow_platform_hopping = value end,
        SetExternalSpeedMultiplier = function(self, owner, source, value) self.speed = value end,
        Stop = function(self) self.stopped = true; record("locomotor_stop") end,
        Clear = function(self) self.cleared = true; record("locomotor_clear") end,
        IsValidDestinationPlatform = function(self, from, destination)
            inst.checked_platform_from, inst.checked_platform_to = from, destination
            return destination.valid_destination ~= false
        end,
    }
    inst.components.playercontroller = {
        enabled = true, busy = false, working = false, remote_vector = { x = 1, y = 9, z = 2 },
        classified = { iscontrollerenabled = { stored = true,
            value = function(self) return self.stored end } },
        IsEnabled = function(self) return self.enabled end,
        IsBusy = function(self) return self.busy end,
        IsDoingOrWorking = function(self) return self.working end,
        ResetRemoteController = function(self) self.reset = true; record("reset_remote") end,
        ClearRemotePredictData = function(self, force) self.predict_cleared = true; self.force = force; record("clear_predict") end,
        RemotePausePrediction = function(self, frames) self.pause_frames = frames; record("pause_prediction") end,
    }
    inst.components.rider = { riding = false, IsRiding = function(self) return self.riding end,
        GetMount = function(self) return self.mount end }
    inst.components.areaaware = { UpdatePosition = function(self, x, y, z)
        self.position = { x, y, z }; record("area")
    end }
    inst.sg = { tags = {}, statemem = {}, currentstate = { name = "idle" },
        HasStateTag = function(self, tag) return self.tags[tag] == true end,
        HasAnyStateTag = function(self, ...)
            for _, tag in ipairs({ ... }) do if self.tags[tag] then return true end end
            return false
        end,
    }
    return inst
end

local function flying_player()
    local inst = player()
    Flight.CommonInit(inst)
    Flight.MasterInit(inst)
    return inst
end
local function apply(inst) inst.events.krypton_flyingdirty(inst) end

reset_world()
local flyer = flying_player()
assert(Flight.IsFlying(flyer), "new character starts in flight")
equal(flyer.Physics.mask, 25, "only shore and boat limits are removed")
assert(flyer.tags.flying and not flyer.components.drownable.enabled, "flight prevents native drowning and VOID falling")
local loco = flyer.components.locomotor
assert(loco.directdrive and loco.pathcaps.allowocean, "direct movement crosses cave VOID and oceans")
equal(loco.pathcaps.ignorecreep, false, "flight preserves other path capabilities")
assert(not loco.enablegroundspeedmultiplier and not loco.triggerscreep and not loco.allow_platform_hopping)
equal(flyer.tasks[1].period, FRAMES, "movement limits maintained each native frame")
flyer.ExtraConfigurePlayerLocomotor(flyer)
equal(loco.speed, 2, "shared setup applies selected movement speed")

equal(Flight.Toggle(flyer), true, "landing on solid ground succeeds")
assert(not Flight.IsFlying(flyer) and not flyer.tags.flying)
equal(flyer.Physics.mask, 31, "landing restores original native collisions")
assert(flyer.components.drownable.enabled and not loco.directdrive and not loco.pathcaps.allowocean)
assert(loco.enablegroundspeedmultiplier and loco.triggerscreep and loco.allow_platform_hopping)
assert(flyer.buffer_cleared and loco.stopped and loco.cleared and flyer.Physics.stopped)
equal(flyer.components.playercontroller.remote_vector.y, 0, "toggle clears old flight prediction height")
local ok, reason = Flight.Toggle(flyer)
equal(ok, false, "toggle cooldown enforced")
equal(reason, "cooldown")
now = 10.35
equal(Flight.Toggle(flyer), true, "takeoff available at cooldown boundary")

reset_world()
world.ground, world.terrain = false, "void"
local cave_flyer = flying_player()
assert(Flight.IsFlying(cave_flyer), "in-bounds cave VOID permits continued flight")
ok, reason = Flight.Toggle(cave_flyer)
equal(ok, false, "cannot drop from flight into cave VOID")
equal(reason, "cannot_land")
equal(cave_flyer.Physics.teleports, nil, "failed landing does not move player")
assert(Flight.IsFlying(cave_flyer) and not cave_flyer.components.drownable.enabled)
cave_flyer.platform = {}
equal(Flight.Toggle(cave_flyer), true, "a real platform permits landing")

-- Prevent leaking out through the map helper's inclusive upper edge.
reset_world()
local edge_flyer = flying_player()
edge_flyer.x, edge_flyer.z = 99.9, 4
apply(edge_flyer)
edge_flyer.x = 100
apply(edge_flyer)
close(edge_flyer.x, 99.9, "tile edge rolls back to last valid position")
close(edge_flyer.z, 4, "edge rollback preserves other coordinate")
assert(edge_flyer.buffer_cleared and edge_flyer.components.playercontroller.predict_cleared)
edge_flyer.x = 1000
apply(edge_flyer)
close(edge_flyer.x, 99.9, "actual world exterior cannot be traversed")
edge_flyer.x = 1e300
apply(edge_flyer)
close(edge_flyer.x, 99.9, "corrupt finite saved coordinates cannot reach native map helpers")

local flight_rejections = {
    { function(p) p.valid = false end, "unavailable" },
    { function(p) p.prefab = "wilson" end, "unavailable" },
    { function(p) p.tags.kryptonian = nil end, "unavailable" },
    { function(p) p.tags.playerghost = true end, "unavailable" },
    { function(p) p.components.health.dead = true end, "unavailable" },
    { function(p) p.components.rider.riding = true end, "riding" },
    { function(p) p.components.playercontroller.enabled = false end, "busy" },
    { function(p) p.components.playercontroller.busy = true end, "busy" },
    { function(p) p.components.playercontroller.working = true end, "busy" },
    { function(p) p.tags.busy = true end, "busy" },
    { function(p) p.sg.tags.busy = true end, "busy" },
    { function() TheNet.paused = true end, "busy" },
}
for _, case in ipairs(flight_rejections) do
    reset_world()
    local inst = flying_player()
    case[1](inst)
    ok, reason = Flight.Toggle(inst)
    equal(ok, false, "ineligible flight toggle refused")
    equal(reason, case[2])
    equal(inst.Physics.teleports, nil, "rejected toggle does not move caster")
end
reset_world()
TUNING.KRYPTON_SURVIVOR.flight_enabled = false
local disabled = flying_player()
assert(not Flight.IsFlying(disabled), "configuration disables default flight")
equal(select(2, Flight.Toggle(disabled)), "disabled")

-- Preserve native ghost masks and riding rules, then resume saved flight when
-- the living character dismounts or resurrects.
reset_world()
local lifecycle = flying_player()
local living_pathcaps = lifecycle.components.locomotor.pathcaps
lifecycle.tags.playerghost = true
lifecycle.Physics.mask = 16
lifecycle.components.locomotor.pathcaps = { allowocean = true, ignorecreep = true }
local ghost_pathcaps = lifecycle.components.locomotor.pathcaps
lifecycle.components.locomotor.triggerscreep = false
lifecycle.components.locomotor.allow_platform_hopping = false
lifecycle.events.ms_becameghost(lifecycle)
assert(not Flight.IsFlying(lifecycle))
equal(lifecycle.Physics.mask, 16, "ghost mask must never regain living shore limits")
equal(living_pathcaps.allowocean, false, "native ghost setup does not leave living pathcap table mutated")
equal(lifecycle.components.locomotor.pathcaps, ghost_pathcaps, "native ghost pathcap table stays selected")
equal(ghost_pathcaps.allowocean, true, "ghost can retain its native ocean capability")
assert(not lifecycle.components.locomotor.triggerscreep and not lifecycle.components.locomotor.allow_platform_hopping,
    "native ghost locomotor rules stay intact")
lifecycle.tags.playerghost = nil
lifecycle.Physics.mask = 31
lifecycle.events.ms_respawnedfromghost(lifecycle)
assert(Flight.IsFlying(lifecycle) and lifecycle.Physics.mask == 25)
lifecycle.components.rider.riding = true
lifecycle.events.mounted(lifecycle)
assert(not Flight.IsFlying(lifecycle) and lifecycle.Physics.mask == 31 and lifecycle.components.drownable.enabled)
lifecycle.components.rider.riding = false
lifecycle.events.dismounted(lifecycle)
assert(Flight.IsFlying(lifecycle) and lifecycle.Physics.mask == 25)
lifecycle.Physics.mask, lifecycle.sg.statemem.isphysicstoggle = 31, true
apply(lifecycle)
equal(lifecycle.Physics.mask, 31, "temporary stategraph physics owned by native transition")
lifecycle.sg.statemem.isphysicstoggle = nil
apply(lifecycle)
equal(lifecycle.Physics.mask, 25, "flight resumes collision filtering after transition")

reset_world()
local saved = player()
local native_save_refs = { 17, 29 }
saved.OnSave = function(self, data) data.original_save = true; return native_save_refs end
saved.OnLoad = function(self, data) self.original_load = true end
Flight.CommonInit(saved)
Flight.MasterInit(saved)
local save_data = {}
equal(saved:OnSave(save_data), native_save_refs, "save chain preserves native referenced-entity list")
assert(save_data.original_save and save_data.krypton_flying, "save chain preserves native data and flight mode")
saved:OnLoad({ krypton_flying = false })
assert(saved.original_load and not Flight.IsFlying(saved) and saved.Physics.mask == 31,
    "grounded saved mode restored synchronously")
world.ground, world.terrain = false, "void"
saved:OnLoad({ krypton_flying = true })
assert(Flight.IsFlying(saved) and not saved.components.drownable.enabled and saved.Physics.mask == 25,
    "saved flight over VOID restores before native ground/drown checks")
saved:OnLoad({})
assert(Flight.IsFlying(saved), "existing saves without mode opt into enabled flight")

-- Prediction gets a new pathcap table when the local player activates. Track
-- that new native table and restore its own values when flight ends.
reset_world()
world.ismastersim = false
local predicted = player()
ThePlayer = predicted
local native_caps
predicted.ExtraConfigurePlayerLocomotor = function(self)
    native_caps = { allowocean = false, ignorecreep = true }
    self.components.locomotor.pathcaps = native_caps
    self.prior_config_called = true
end
Flight.CommonInit(predicted)
predicted._krypton_flying:set(true)
predicted.ExtraConfigurePlayerLocomotor(predicted)
assert(predicted.prior_config_called and native_caps.allowocean and predicted.components.locomotor.directdrive)
equal(predicted.components.locomotor.pathcaps.ignorecreep, true, "prediction preserves current native caps")
local original_prediction_caps = native_caps
predicted.ExtraConfigurePlayerLocomotor(predicted)
local replacement_caps = native_caps
equal(original_prediction_caps.allowocean, false, "replaced prediction table must not leak flight-only capability")
predicted._krypton_flying:set(false)
apply(predicted)
equal(predicted.components.locomotor.pathcaps, replacement_caps, "restore current prediction table rather than stale original")
assert(not replacement_caps.allowocean and not predicted.components.locomotor.directdrive)
equal(predicted.components.drownable.enabled, true, "client cannot author drowning protection")
equal(select(2, Flight.Toggle(predicted)), "disabled", "client cannot author flight state")
predicted.components.health, predicted.components.rider = nil, nil
predicted.replica = {
    health = { dead = false, IsDead = function(self) return self.dead end },
    rider = { riding = false, IsRiding = function(self) return self.riding end },
}
predicted._krypton_flying:set(true)
apply(predicted)
assert(Flight.IsFlying(predicted), "local prediction works with native replicas instead of server components")
predicted.replica.rider.riding = true
apply(predicted)
assert(not Flight.IsFlying(predicted), "client rider replica suppresses flight prediction")
predicted.replica.rider.riding, predicted.replica.health.dead = false, true
apply(predicted)
assert(not Flight.IsFlying(predicted), "client health replica suppresses dead flight prediction")

local FlightVisual = require("krypton_flight_visual")
reset_world()
local visual_actor = player()
visual_actor.AnimState.animation = "idle_loop"
Flight.CommonInit(visual_actor)
Flight.MasterInit(visual_actor)
equal(visual_actor.AnimState.override_build, "krypton_flight_build", "original flight art loaded as its own override build")
equal(visual_actor.AnimState.animation, "krypton_flight_idle", "flying idle selects original airborne pose")
equal(visual_actor.SuspendKryptonFlightVisual, FlightVisual.Suspend, "character exposes temporary visual suspension for heat vision")
local plays = visual_actor.AnimState.plays
now = 10.2
apply(visual_actor)
equal(visual_actor.AnimState.plays, plays, "normal flight frame does not restart its animation")
visual_actor.AnimState.animation = "idle_loop"
now = 10.75
apply(visual_actor)
close(visual_actor.AnimState.phase, .75, "native idle reentry preserves airborne loop phase")
visual_actor.sg.currentstate.name, visual_actor.AnimState.animation = "run", "run_loop"
apply(visual_actor)
equal(visual_actor.AnimState.animation, "krypton_flight_move", "flying run uses airborne motion")
visual_actor.AnimState.animation = "run_loop"
now = 10.95
apply(visual_actor)
close(visual_actor.AnimState.phase, .2, "native run reentry preserves airborne cycle phase")
visual_actor.sg.currentstate.name, visual_actor.AnimState.animation = "walk", "walk_loop"
apply(visual_actor)
equal(visual_actor.AnimState.animation, "krypton_flight_move", "flying walk uses airborne motion")
equal(Flight.Toggle(visual_actor), true, "landing turns off flight visuals through the real toggle")
equal(visual_actor.AnimState.animation, "walk_loop", "landing restores the actual native walk loop")
now = 11.3
equal(Flight.Toggle(visual_actor), true)
equal(visual_actor.AnimState.animation, "krypton_flight_move", "takeoff restores airborne motion")
visual_actor.components.rider.riding = true
visual_actor.events.mounted(visual_actor)
equal(visual_actor.AnimState.animation, "walk_loop", "mounted player restores native locomotion animation")
visual_actor.components.rider.riding = false
visual_actor.events.dismounted(visual_actor)
equal(visual_actor.AnimState.animation, "krypton_flight_move", "dismount resumes saved flight pose")
for _, animation in ipairs({ "attack", "chop_loop", "run_pre", "run_pst", "walk_pst", "idle_inaction" }) do
    visual_actor.AnimState.animation = animation
    apply(visual_actor)
    equal(visual_actor.AnimState.animation, animation, "complex actions and native transitions take precedence")
end
visual_actor.sg.currentstate.name, visual_actor.AnimState.animation = "attack", "attack"
visual_actor.sg.tags.busy = true
apply(visual_actor)
equal(visual_actor.AnimState.animation, "attack", "busy stategraph animation cannot be overwritten")
visual_actor.sg.tags.busy = nil
visual_actor.tags.playerghost = true
visual_actor.AnimState.animation = "ghost_idle_loop"
visual_actor.events.ms_becameghost(visual_actor)
equal(visual_actor.AnimState.animation, "ghost_idle_loop", "native ghost animation takes precedence")

reset_world()
local suspended_actor = player()
suspended_actor.AnimState.animation, suspended_actor.sg.currentstate.name = "run_loop", "run"
Flight.CommonInit(suspended_actor)
Flight.MasterInit(suspended_actor)
suspended_actor:SuspendKryptonFlightVisual(.5)
assert(suspended_actor._krypton_flight_visual_suspended:value(), "server replicates temporary visual suspension")
equal(suspended_actor.AnimState.animation, "run_loop", "suspension immediately restores native head-bearing animation")
assert(Flight.IsFlying(suspended_actor) and suspended_actor.Physics.mask == 25,
    "heat-vision suspension changes pose while retaining actual flight movement")
local first_resume = suspended_actor._krypton_flight_visual_resume_task
close(first_resume.delay, .5, "suspension schedules recovery")
now = 10.2
suspended_actor:SuspendKryptonFlightVisual(.1)
assert(first_resume.cancelled, "repeated suspension cancels obsolete recovery task")
close(suspended_actor._krypton_flight_visual_pauseuntil, 10.5, "short repeated request cannot shorten existing pause")
local final_resume = suspended_actor._krypton_flight_visual_resume_task
close(final_resume.delay, .3, "replacement timer retains remaining pause")
now = 10.49
apply(suspended_actor)
equal(suspended_actor.AnimState.animation, "run_loop", "suspension remains through deadline")
now = 10.5
final_resume.fn(suspended_actor)
equal(suspended_actor._krypton_flight_visual_suspended:value(), false, "server releases replicated visual pause")
equal(suspended_actor.AnimState.animation, "krypton_flight_move", "resume returns to the correct airborne movement loop")

reset_world()
world.ismastersim = false
local observer = player()
observer.sg = nil
observer.AnimState.animation = "idle_loop"
Flight.CommonInit(observer)
observer._krypton_flying:set(true)
apply(observer)
equal(observer.AnimState.animation, "krypton_flight_idle", "remote observers without a stategraph render exact native idle loops")
observer._krypton_flight_visual_suspended:set(true)
observer.events.krypton_flight_visualdirty(observer)
equal(observer.AnimState.animation, "idle_loop", "replicated pause restores native pose on other clients")
observer:SuspendKryptonFlightVisual(.5)
assert(observer._krypton_flight_visual_suspended:value(), "client local suspension cannot author authoritative pause state")
local local_resume = observer._krypton_flight_visual_resume_task
now = 10.5
local_resume.fn(observer)
equal(observer.AnimState.animation, "idle_loop", "client timer cannot override a still-active replicated suspension")
observer._krypton_flight_visual_suspended:set(false)
observer.events.krypton_flight_visualdirty(observer)
equal(observer.AnimState.animation, "krypton_flight_idle", "replicated release resumes airborne visuals")
observer.AnimState.animation = "attack"
apply(observer)
equal(observer.AnimState.animation, "attack", "remote action animations are preserved without a stategraph")

-- The native footstep override is per player. Air movement has one local wind
-- child; normal actions keep their original SoundEmitter and override chain.
reset_world()
local audio_actor = player()
local previous_steps, previous_volume, previous_predicted = 0
local original_emitter = {}
audio_actor.SoundEmitter = original_emitter
audio_actor.footstepoverridefn = function(inst, volume, predicted)
    previous_steps, previous_volume, previous_predicted = previous_steps + 1, volume, predicted
    return false
end
audio_actor.AnimState.animation = "idle_loop"
Flight.CommonInit(audio_actor)
Flight.MasterInit(audio_actor)
equal(audio_actor:footstepoverridefn(.6, true), true, "hovering does not play a ground step")
equal(previous_steps, 0, "airborne step cannot play clothing overrides before suppression")
equal(#sound_entities, 0, "hovering keeps the air loop quiet")
for _, transition in ipairs({ { "run_start", "run_pre" }, { "run_start", "walk_pre" },
    { "run_stop", "run_pst" }, { "run_stop", "walk_pst" } }) do
    audio_actor.sg.currentstate.name, audio_actor.AnimState.animation = transition[1], transition[2]
    equal(audio_actor:footstepoverridefn(1, true), true, "airborne movement transitions cannot leak first-step sounds")
    apply(audio_actor)
    equal(audio_actor.AnimState.animation, transition[2], "audio fix preserves native transition animation")
    equal(#sound_entities, 0, "movement transition does not start a separate air loop")
end
audio_actor.sg.currentstate.name, audio_actor.AnimState.animation = "run", "run_loop"
equal(audio_actor:footstepoverridefn(.6, true), true, "native run reentry cannot leak terrain footsteps")
apply(audio_actor)
local moving_sound = audio_actor._krypton_flight_sound
assert(moving_sound ~= nil and moving_sound.hidden and not moving_sound.persists,
    "moving flight starts a hidden unsaved local sound child")
equal(moving_sound.entity.parent, audio_actor.entity, "air sound follows the player position")
equal(moving_sound.entity.can_sleep, false, "wind child cannot suspend its loop independently")
equal(moving_sound.path, "meta5/woby/sprint_wind_lp", "air sound uses an existing globally loaded event")
equal(moving_sound.handle, "krypton_flight")
close(moving_sound.volume, .15, "wind remains below normal full-volume movement")
audio_actor.AnimState.animation = "run_loop"
apply(audio_actor)
equal(audio_actor._krypton_flight_sound, moving_sound, "native movement reentry reuses the same emitter")
equal(moving_sound.plays, 1, "frame updates cannot stack or restart air loops")
equal(#sound_entities, 1, "one flight emitter exists per rendered player")
equal(audio_actor.SoundEmitter, original_emitter, "combat and eating emitter is never replaced or muted")
equal(Flight.Toggle(audio_actor), true)
assert(moving_sound.removed and moving_sound.killed == "krypton_flight", "landing kills and removes the wind child")
equal(audio_actor._krypton_flight_sound, nil, "landing clears sound ownership")
equal(audio_actor:footstepoverridefn(.4, true), false, "grounded steps fall through to terrain audio")
equal(previous_steps, 1, "landing restores the existing skin/mod footstep override")
close(previous_volume, .4, "previous override receives original volume")
equal(previous_predicted, true, "previous override receives prediction flag")
now = now + .4
equal(Flight.Toggle(audio_actor), true)
moving_sound = audio_actor._krypton_flight_sound
audio_actor.components.rider.riding = true
audio_actor.events.mounted(audio_actor)
assert(moving_sound.removed, "mounting stops airborne audio")
equal(audio_actor:footstepoverridefn(.8, false), false, "mounted native footsteps remain available")
audio_actor.components.rider.riding = false
audio_actor.events.dismounted(audio_actor)
moving_sound = audio_actor._krypton_flight_sound
audio_actor.sg.currentstate.name, audio_actor.AnimState.animation = "attack", "attack"
audio_actor.sg.tags.busy = true
apply(audio_actor)
assert(moving_sound.removed, "an attack immediately stops the movement air loop")
equal(audio_actor:footstepoverridefn(.5, false), false, "busy action footstep events use their original behavior")
audio_actor.sg.tags.busy = nil
audio_actor.sg.currentstate.name, audio_actor.AnimState.animation = "run", "run_loop"
apply(audio_actor)
moving_sound = audio_actor._krypton_flight_sound
audio_actor:SuspendKryptonFlightVisual(.5)
assert(moving_sound.removed, "heat-vision visual suspension also stops flight wind")
equal(audio_actor:footstepoverridefn(.5, true), false, "suspended action sounds are preserved")
now = now + .5
audio_actor._krypton_flight_visual_resume_task.fn(audio_actor)
moving_sound = audio_actor._krypton_flight_sound
audio_actor.asleep = true
audio_actor.events.entitysleep(audio_actor)
assert(moving_sound.removed, "sleeping player removes its local sound child")
apply(audio_actor)
equal(audio_actor._krypton_flight_sound, nil, "periodic updates cannot recreate sound while asleep")
audio_actor.asleep = false
audio_actor.events.entitywake(audio_actor)
moving_sound = audio_actor._krypton_flight_sound
assert(moving_sound ~= nil, "waking restores moving flight audio")
audio_actor.components.health.dead = true
apply(audio_actor)
assert(moving_sound.removed, "death stops the loop without touching native death sounds")
audio_actor.components.health.dead = false
apply(audio_actor)
moving_sound = audio_actor._krypton_flight_sound
audio_actor.events.onremove(audio_actor)
audio_actor.events.onremove(audio_actor)
assert(moving_sound.removed and audio_actor._krypton_flight_sound == nil,
    "removal cleanup is idempotent and cannot leak wind")

reset_world()
TheNet.dedicated = true
local silent_server = player()
silent_server.sg.currentstate.name, silent_server.AnimState.animation = "run", "run_loop"
Flight.CommonInit(silent_server)
Flight.MasterInit(silent_server)
equal(silent_server:footstepoverridefn(1, true), true, "dedicated server suppresses replicated terrain steps")
equal(#sound_entities, 0, "dedicated server creates no presentation sound entities")

reset_world()
world.ismastersim = false
local audio_observer = player()
audio_observer.sg = nil
audio_observer.AnimState.animation = "run_loop"
Flight.CommonInit(audio_observer)
audio_observer._krypton_flying:set(true)
apply(audio_observer)
moving_sound = audio_observer._krypton_flight_sound
assert(moving_sound ~= nil, "other clients render one positional air loop for a moving player")
audio_observer.AnimState.animation = "attack"
apply(audio_observer)
assert(moving_sound.removed, "remote actions stop sound even without a local stategraph")
equal(audio_observer:footstepoverridefn(1, false), false, "remote action animations do not swallow native footstep events")

-- Flight keyboard input follows focus/placement guards and never registers on
-- a dedicated server. Actual state eligibility remains authoritative above.
local register_flight_input = load_source("mod/scripts/krypton_flight_input.lua")
local function input_fixture()
    local G = { ThePlayer = player(), TUNING = TUNING, now = 20, paused = false,
        KEY_CTRL = 17, CONTROL_SECONDARY = 2, CONTROL_PRIMARY = 1,
        TheNet = { dedicated = false, paused = false,
            IsDedicated = function(self) return self.dedicated end,
            IsServerPaused = function(self) return self.paused end },
        TheInput = { ctrl = true, controller = false, registered = 0,
            IsKeyDown = function(self, key) equal(key, 17); return self.ctrl end,
            ControllerAttached = function(self) return self.controller end,
            GetHUDEntityUnderMouse = function(self) return self.hud_entity end,
            AddKeyDownHandler = function(self, key, fn) self.key, self.handler = key, fn; self.registered = self.registered + 1 end },
        sends = {}, order = {},
    }
    G.GetTime = function() return G.now end
    G.IsPaused = function() return G.paused end
    G.ThePlayer.HUD = { focus = false, HasInputFocus = function(self)
        -- Match native PlayerHud: an active overlay owns input focus even when
        -- the HUD itself has no explicit inventory/text/mod focus flag.
        return self.focus or (G.active_screen ~= nil and G.active_screen ~= self)
    end }
    G.send = function(x, z)
        table.insert(G.sends, { x = x, z = z })
        table.insert(G.order, "send")
    end
    return G
end
reset_world()
for _, reason_to_block in ipairs({
    function(G) G.ThePlayer = nil end,
    function(G) G.ThePlayer.prefab = "wilson" end,
    function(G) G.ThePlayer.tags.playerghost = true end,
    function(G) G.ThePlayer.tags.busy = true end,
    function(G) G.ThePlayer.HUD.focus = true end,
    function(G) G.paused = true end,
    function(G) G.TheNet.paused = true end,
    function(G) G.TheInput.hud_entity = {} end,
    function(G) G.ThePlayer.components.playercontroller.placer = {} end,
    function(G) G.ThePlayer.components.playercontroller.enabled = false end,
    function(G) G.ThePlayer.components.playercontroller.busy = true end,
    function(G) G.ThePlayer.components.playercontroller.working = true end,
    function(G) G.TUNING.KRYPTON_SURVIVOR.flight_enabled = false end,
}) do
    reset_world()
    local G = input_fixture()
    register_flight_input(G, 103, G.send)
    reason_to_block(G)
    G.TheInput.handler()
    equal(#G.sends, 0, "guarded flight input sends no RPC")
end
reset_world()
local G = input_fixture()
register_flight_input(G, nil, G.send)
equal(G.TheInput.registered, 0, "disabled key has no handler")
G.TheNet.dedicated = true
register_flight_input(G, 103, G.send)
equal(G.TheInput.registered, 0, "dedicated server has no key handler")
G.TheNet.dedicated = false
register_flight_input(G, 103, G.send)
G.TheInput.handler()
G.TheInput.handler()
equal(#G.sends, 1, "flight key repetitions are debounced")
G.now = 20.35
G.TheInput.handler()
equal(#G.sends, 2, "flight key debounce expires")

print("Mobility flight tests passed: native collisions, cave VOID, bounds, landing, lifecycle, save/load, prediction and input guards.")

local Teleport = load_source("mod/scripts/krypton_map_teleport.lua")
local function rejected_teleport(inst, x, z, expected_reason)
    local original_x, original_y, original_z = inst.x, inst.y, inst.z
    local success, why = Teleport.Cast(inst, x, z)
    equal(success, false, "unsafe teleport rejected")
    equal(why, expected_reason, "teleport refusal reason")
    equal(inst.x, original_x, "refused destination does not move x")
    equal(inst.y, original_y, "refused destination does not move y")
    equal(inst.z, original_z, "refused destination does not move z")
    equal(inst.buffer_cleared, nil, "refusal leaves current action intact")
    equal(inst.camera_snapped, nil, "refusal does not snap camera")
end
reset_world()
equal(select(2, Teleport.Cast(nil, 20, 30)), "unavailable", "missing caster refused")
for _, value in ipairs({ "20", {}, false, math.huge, -math.huge, 0 / 0 }) do
    rejected_teleport(flying_player(), value, 30, "unavailable")
    rejected_teleport(flying_player(), 20, value, "unavailable")
end
rejected_teleport(flying_player(), nil, 30, "unavailable")
rejected_teleport(flying_player(), 20, nil, "unavailable")
rejected_teleport(flying_player(), 1e300, -1e300, "invalid_ground")
rejected_teleport(flying_player(), 100, 30, "invalid_ground")
rejected_teleport(flying_player(), 20, -100, "invalid_ground")

local teleport_rejections = {
    { function(p) p.valid = false end, "unavailable" },
    { function(p) p.prefab = "wilson" end, "unavailable" },
    { function(p) p.tags.kryptonian = nil end, "unavailable" },
    { function(p) p.tags.playerghost = true end, "unavailable" },
    { function(p) p.tags.busy = true end, "busy" },
    { function(p) p.components.health.dead = true end, "unavailable" },
    { function(p) p.components.health = nil end, "unavailable" },
    { function(p) p.components.locomotor = nil end, "unavailable" },
    { function(p) p.Physics = nil end, "unavailable" },
    { function(p) p.components.rider.riding = true end, "riding" },
    { function(p) p.components.playercontroller = nil end, "controls_disabled" },
    { function(p) p.components.playercontroller.classified = nil end, "controls_disabled" },
    { function(p) p.components.playercontroller.classified.iscontrollerenabled = nil end, "controls_disabled" },
    { function(p) p.components.playercontroller.classified.iscontrollerenabled.stored = false end, "controls_disabled" },
    { function(p) p.components.playercontroller.busy = true end, "busy" },
    { function(p) p.components.playercontroller.working = true end, "busy" },
    { function(p) p.sg.tags.busy = true end, "busy" },
    { function(p) p.sg.tags.jumping = true end, "busy" },
    { function(p) p.sg.tags.nointerrupt = true end, "busy" },
    { function() TheWorld.ismastersim = false end, "unavailable" },
    { function() TheNet.paused = true end, "paused" },
    { function() TUNING.KRYPTON_SURVIVOR.map_teleport_enabled = false end, "disabled" },
}
for _, case in ipairs(teleport_rejections) do
    reset_world()
    local inst = flying_player()
    case[1](inst)
    equal(Teleport.CanCast(inst), false, "ineligible map caster cannot cast")
    rejected_teleport(inst, 20, 30, case[2])
end

-- A listen-server player's IsEnabled includes local menu/HUD focus. Native
-- authority lives in the classified control flag, just as on a headless host.
reset_world()
local host_traveller = flying_player()
host_traveller.components.playercontroller.enabled = false
host_traveller.components.playercontroller.IsEnabled = function()
    error("server map teleport must not consult local HUD-dependent IsEnabled")
end
equal(Teleport.CanCast(host_traveller), true, "authoritative enabled controls survive temporary host HUD focus")
equal(Teleport.Cast(host_traveller, 20, 30), true, "listen-server host can teleport like a remote client")

reset_world()
world.ground, world.terrain = false, "void"
rejected_teleport(flying_player(), 20, 30, "invalid_ground")
equal(world.last_allow_ocean, true, "flight can request ocean capability but native cave VOID remains invalid")
reset_world()
world.ground, world.terrain = false, "ocean"
local ocean_flyer = flying_player()
equal(Teleport.Cast(ocean_flyer, 20, 30), true, "flying character can arrive over real ocean")
equal(ocean_flyer.components.drownable.enabled, false, "ocean arrival keeps native drowning disabled")
local grounded = player()
Flight.CommonInit(grounded)
rejected_teleport(grounded, 20, 30, "invalid_ground")
equal(world.last_allow_ocean, false, "grounded character cannot forge ocean flight capability")

reset_world()
world.blocked = true
rejected_teleport(flying_player(), 20, 30, "blocked")
reset_world()
world.path_clear = false
rejected_teleport(flying_player(), 20, 30, "blocked")
reset_world()
teleport_permitted = false
rejected_teleport(flying_player(), 20, 30, "restricted")

-- Respect each actual collider's group/mask/body radius. Ignore an inactive
-- decorative body, but refuse buildings, trees or cave entrances that collide
-- with the character even when native tile/path helpers say the point is clear.
reset_world()
local building = player()
building.x, building.z, building.radius = 20.8, 30, .5
occupancy = { building }
rejected_teleport(flying_player(), 20, 30, "blocked")
building.Physics.active = false
equal(Teleport.Cast(flying_player(), 20, 30), true, "inactive body does not block destination")
building.Physics.active, building.Physics.mask = true, 0
equal(Teleport.Cast(flying_player(), 20, 30), true, "noncolliding body does not block destination")
building.Physics.mask, building.x = COLLISION.CHARACTERS, 21
equal(Teleport.Cast(flying_player(), 20, 30), true, "touching physics circles may land without overlapping")
building.x, building.radius = 22, 2
rejected_teleport(flying_player(), 20, 30, "blocked")

local function platform(x, z, radius)
    return { Transform = { GetWorldPosition = function() return x, 0, z end },
        components = { walkableplatform = { platform_radius = radius } } }
end
reset_world()
local boat = platform(20, 30, 5)
world.destination_platform = boat
local boater = flying_player()
boater.platform = {}
equal(Teleport.Cast(boater, 20, 30), true, "safe interior of an accessible platform permits landing")
equal(boater.checked_platform_from, boater.platform, "native platform transition receives current platform")
equal(boater.checked_platform_to, boat, "native platform transition receives destination")
boat.valid_destination = false
rejected_teleport(flying_player(), 20, 30, "blocked")
boat.valid_destination = true
rejected_teleport(flying_player(), 24.01, 30, "blocked")
world.destination_platform = platform(20, 30, 1)
rejected_teleport(flying_player(), 20, 30, "blocked")

reset_world()
local traveller = flying_player()
occupancy = { traveller }
equal(Teleport.Cast(traveller, -40, 35), true, "safe exact map point is used without a nearby search")
equal(traveller.x, -40, "requested x")
equal(traveller.z, 35, "requested z")
equal(traveller.y, 0, "destination uses ground height")
equal(table.concat(traveller.log, ","), "reset_remote,clear_predict,clear_action,locomotor_stop,pause_prediction,teleport,area,event,camera",
    "old prediction and actions clear before movement, followed by location/camera updates")
equal(traveller.components.playercontroller.force, true, "force clears stale remote prediction")
equal(traveller.components.playercontroller.pause_frames, 3, "native prediction paused for three frames")
equal(traveller.pushed_event, "teleported", "native teleport listeners notified")
equal(traveller.components.areaaware.position[1], -40, "area awareness updates immediately")
ok, reason = Teleport.Cast(traveller, 45, 40)
equal(ok, false, "rapid teleport repetition rejected")
equal(reason, "cooldown")
now = 10.5
equal(Teleport.Cast(traveller, 45, 40), true, "server teleport cooldown expires")

local register_map_input = load_source("mod/scripts/krypton_map_teleport_input.lua")
local function screen_fixture(G)
    local screen = { owner = G.ThePlayer, shown = true, delegated = 0, position = { 25.5, 0, -31.25 } }
    screen.OnControl = function(self, control, down)
        self.delegated = self.delegated + 1
        self.old_control, self.old_down = control, down
        return "native-control-result"
    end
    screen.GetWorldPositionAtCursor = function(self)
        self.cursor_conversions = (self.cursor_conversions or 0) + 1
        table.insert(G.order, "cursor")
        if self.position == nil then return nil end
        return self.position[1], self.position[2], self.position[3]
    end
    G.ThePlayer.components.playercontroller.map_enabled = true
    G.ThePlayer.components.playercontroller.IsMapControlsEnabled = function(self) return self.map_enabled end
    -- Normal map teardown is synchronous, but the network pause result is not:
    -- it may remain paused in the input frame until simulation resumes.
    G.ThePlayer.components.playercontroller.enabled = false
    G.ThePlayer.HUD.focus = true
    G.paused = true
    G.TheNet.paused = true
    G.active_screen = screen
    G.hud_screen = G.ThePlayer.HUD
    G.TheFrontEnd = { PopScreen = function(self)
        table.insert(G.order, "pop")
        screen.destroyed = (screen.destroyed or 0) + 1
        screen.shown = false
        G.paused = false
        G.ThePlayer.HUD.focus = false
        G.ThePlayer.components.playercontroller.enabled = true
        G.active_screen = G.hud_screen
        table.insert(G.order, "request_unpause")
    end,
        GetActiveScreen = function() return G.active_screen end,
    }
    return screen
end

local function next_simulation_tick(G, owner, after_resume)
    G.now = G.now + FRAMES
    G.paused, G.TheNet.paused = false, false
    table.insert(G.order, "simulation_resumed")
    local pending = owner.tasks
    owner.tasks = {}
    if after_resume ~= nil then after_resume(G, owner) end
    for _, task in ipairs(pending) do
        if task.delay ~= nil and not task.cancelled then task.fn(owner) end
    end
end
reset_world()
local map_G = input_fixture()
local map_screen = screen_fixture(map_G)
register_map_input(map_G, "ctrl_right", map_G.send)(map_screen)
equal(map_screen:OnControl(map_G.CONTROL_SECONDARY, true), true, "Ctrl+right consumes map teleport click")
equal(map_screen.delegated, 0, "teleport click does not also run native control")
equal(map_screen.cursor_conversions, 1, "use native zoom/pan-aware map coordinate conversion")
equal(#map_G.sends, 0, "closing map does not send in the stale paused input frame")
equal(map_G.TheNet.paused, true, "network pause can survive synchronous map teardown")
equal(#map_screen.owner.tasks, 1, "teleport request is scheduled once for resumed simulation")
equal(map_screen.owner.tasks[1].delay, 0, "deferred request waits for the next normal simulation tick")
map_screen.position = { 88, 0, 77 }
next_simulation_tick(map_G, map_screen.owner)
equal(map_G.sends[1].x, 25.5, "native map x preserved")
equal(map_G.sends[1].z, -31.25, "native map z preserved")
equal(map_screen.cursor_conversions, 1, "deferred callback uses the captured point instead of a new cursor position")
equal(table.concat(map_G.order, ","), "cursor,pop,request_unpause,simulation_resumed,send",
    "RPC waits for simulation to resume after map teardown")
equal(map_screen.destroyed, 1, "normal teardown occurs exactly once")
equal(map_G.ThePlayer.components.playercontroller._hack_ignore_held_controls, .1, "held world controls suppressed after closing map")
assert(type(map_G.ThePlayer.components.playercontroller._hack_ignore_ups_for) == "table")

-- Revalidate the original living caster after the map closes. A queued request
-- cannot fire for a new character or through a menu opened before the next tick.
local delayed_map_cancellations = {
    function(G, owner) owner.valid = false end,
    function(G, owner) G.ThePlayer = nil end,
    function(G, owner) G.ThePlayer = player() end,
    function(G, owner) owner.tags.playerghost = true end,
    function(G, owner) owner.components.health.dead = true end,
    function(G, owner) owner.tags.busy = true end,
    function(G, owner) owner.HUD = nil end,
    function(G, owner) owner.HUD.focus = true end,
    function(G, owner) G.active_screen = { name = "PauseScreen" } end,
    function(G, owner) owner.components.playercontroller = nil end,
    function(G, owner) owner.components.playercontroller.enabled = false end,
    function(G, owner) owner.components.playercontroller.busy = true end,
    function(G, owner) owner.components.playercontroller.working = true end,
    function(G, owner) owner.components.playercontroller.placer = {} end,
    function(G, owner) G.paused = true end,
    function(G, owner) G.TheNet.paused = true end,
    function(G, owner) G.TUNING.KRYPTON_SURVIVOR.map_teleport_enabled = false end,
}
for _, modify in ipairs(delayed_map_cancellations) do
    reset_world()
    local input = input_fixture()
    local screen = screen_fixture(input)
    local owner = screen.owner
    register_map_input(input, "ctrl_right", input.send)(screen)
    equal(screen:OnControl(input.CONTROL_SECONDARY, true), true, "eligible map click queues a request")
    equal(#input.sends, 0, "queued cancellation case cannot send during old pause")
    next_simulation_tick(input, owner, modify)
    equal(#input.sends, 0, "changed character, state or focus cancels the deferred request")
    equal(screen.destroyed, 1, "cancelled request does not repeat map teardown")
    equal(screen.cursor_conversions, 1, "cancelled request never converts a later cursor location")
end

local map_passthrough = {
    function(G, screen) G.TheInput.ctrl = false end,
    function(G, screen) G.TheInput.controller = true end,
    function(G, screen) screen.shown = false end,
    function(G, screen) screen.quitting = true end,
    function(G, screen) screen._hack_ignore_held_controls = true end,
    function(G, screen) screen.owner = nil end,
    function(G, screen) screen.owner = player() end,
    function(G, screen) screen.owner.valid = false end,
    function(G, screen) screen.owner.prefab = "wilson" end,
    function(G, screen) screen.owner.tags.playerghost = true end,
    function(G, screen) screen.owner.tags.busy = true end,
    function(G, screen) screen.owner.components.playercontroller.map_enabled = false end,
    function(G, screen) screen.owner.components.playercontroller.busy = true end,
    function(G, screen) screen.owner.components.playercontroller.working = true end,
    function(G, screen) screen.owner.components.playercontroller.placer = {} end,
    function(G, screen) G.TUNING.KRYPTON_SURVIVOR.map_teleport_enabled = false end,
}
for _, modify in ipairs(map_passthrough) do
    reset_world()
    local input = input_fixture()
    local screen = screen_fixture(input)
    register_map_input(input, "ctrl_right", input.send)(screen)
    modify(input, screen)
    equal(screen:OnControl(input.CONTROL_SECONDARY, true), "native-control-result", "unhandled map input delegates unchanged")
    equal(screen.delegated, 1, "unhandled control reaches original map once")
    equal(#input.sends, 0, "unhandled input cannot send a teleport")
    equal(screen.cursor_conversions, nil, "unhandled input avoids coordinate conversion")
    equal(screen.destroyed, nil, "unhandled input leaves map open")
end
for _, control in ipairs({ 1, 7 }) do
    reset_world()
    local input = input_fixture()
    local screen = screen_fixture(input)
    register_map_input(input, "ctrl_right", input.send)(screen)
    equal(screen:OnControl(control, true), "native-control-result", "left click and other controls preserved")
    equal(screen.old_control, control, "original control code preserved")
    equal(screen.old_down, true, "original control state preserved")
end
reset_world()
local input = input_fixture()
local screen = screen_fixture(input)
register_map_input(input, "ctrl_right", input.send)(screen)
equal(screen:OnControl(input.CONTROL_SECONDARY, false), "native-control-result", "right-button release delegates")
screen.position = nil
equal(screen:OnControl(input.CONTROL_SECONDARY, true), true, "no native map coordinate consumes click without teleport")
equal(#input.sends, 0, "missing cursor location does not send RPC")
equal(screen.destroyed, nil, "missing cursor location leaves map open")

reset_world()
input = input_fixture()
screen = screen_fixture(input)
local native_control = screen.OnControl
register_map_input(input, "disabled", input.send)(screen)
equal(screen.OnControl, native_control, "disabled map ability installs no interception")
input.TheNet.dedicated = true
register_map_input(input, "ctrl_right", input.send)(screen)
equal(screen.OnControl, native_control, "dedicated server does not install map input")

reset_world()
input = input_fixture()
input.TheInput.ctrl = false
screen = screen_fixture(input)
register_map_input(input, "right", input.send)(screen)
equal(screen:OnControl(input.CONTROL_SECONDARY, true), true, "configured right-click mode needs no Ctrl modifier")
equal(#input.sends, 0, "right-click mode waits for resumed simulation too")
next_simulation_tick(input, screen.owner)
equal(#input.sends, 1, "right-click mode still sends native map position")

-- The debounce spans map instances rather than resetting on reopening.
reset_world()
input = input_fixture()
local map_hook = register_map_input(input, "ctrl_right", input.send)
screen = screen_fixture(input)
map_hook(screen)
screen:OnControl(input.CONTROL_SECONDARY, true)
next_simulation_tick(input, screen.owner)
local reopened = screen_fixture(input)
map_hook(reopened)
equal(reopened:OnControl(input.CONTROL_SECONDARY, true), true, "reopened map respects input cooldown")
equal(reopened.destroyed, nil, "reopening during cooldown keeps map available")
equal(#input.sends, 1, "reopening cannot bypass teleport debounce")
input.now = 20.5
reopened:OnControl(input.CONTROL_SECONDARY, true)
next_simulation_tick(input, reopened.owner)
equal(#input.sends, 2, "map input cooldown expires")

print("Mobility teleport tests passed: safe destinations, authoritative control eligibility, explicit refusal reasons, prediction reset, captured map coordinates, asynchronous pause recovery and deferred focus/lifecycle guards.")
