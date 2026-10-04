local Data = require("krypton_heatvision_visual_data")
local Visual = {}

local function CreateVisual(bank, animation)
    local fx = CreateEntity()
    fx.entity:AddTransform()
    fx.entity:AddAnimState()
    fx:AddTag("FX")
    fx:AddTag("NOCLICK")
    fx.persists = false
    fx.entity:SetCanSleep(false)
    fx.AnimState:SetBank(bank)
    fx.AnimState:SetBuild(bank)
    fx.AnimState:PlayAnimation(animation, true)
    fx.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    fx.AnimState:SetLightOverride(1)
    return fx
end

local function CreateEye(glow)
    local eye = {
        halo = CreateVisual("wagdrone_laserwire_fx", "beam_straight"),
        core = CreateVisual("wagdrone_laserwire_fx", "beam_straight"),
    }
    for _, fx in ipairs({ eye.halo, eye.core }) do
        fx.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
    end
    eye.halo.AnimState:SetMultColour(1, 0.04, 0.01, 0.8)
    eye.halo.AnimState:SetAddColour(0.6, 0, 0, 0)
    eye.core.AnimState:SetMultColour(1, 0.7, 0.3, 0.95)
    eye.core.AnimState:SetAddColour(0.3, 0.05, 0, 0)
    eye.core.AnimState:SetFinalOffset(1)
    if glow then
        eye.spark = CreateVisual("bishop_attack", "shot_fx")
        eye.spark.AnimState:SetScale(Data.beam.eye_glow_scale, Data.beam.eye_glow_scale)
        eye.spark.AnimState:SetMultColour(1, 0.15, 0.05, 0.9)
        eye.spark.AnimState:SetAddColour(0.6, 0.04, 0, 0)
        eye.spark.AnimState:SetFinalOffset(2)
    end
    return eye
end

function Visual.Clear(inst)
    if inst._eyes ~= nil then
        for _, eye in ipairs(inst._eyes) do
            eye.halo:Remove()
            eye.core:Remove()
            if eye.spark ~= nil then eye.spark:Remove() end
        end
    end
    inst._eyes = nil
    inst._eye_pose = nil
end

function Visual.Sleep(inst)
    inst._visual_sleeping = true
    Visual.Clear(inst)
end

function Visual.Wake(inst)
    inst._visual_sleeping = false
    Visual.Update(inst)
end

local function GetPose(caster)
    caster.AnimState:MakeFacingDirty()
    local facing = caster.AnimState:GetCurrentFacing()
    local rider = caster.replica ~= nil and caster.replica.rider or nil
    if rider ~= nil and rider:IsRiding() then
        -- Mounted idle/run use the front head even in horizontal facings.
        -- Only the mounted walk loop/post animation uses the profile head.
        if facing == FACING_UP or facing == FACING_UPRIGHT or facing == FACING_UPLEFT then
            return "back"
        elseif (facing == FACING_RIGHT or facing == FACING_LEFT)
            and (caster.AnimState:IsCurrentAnimation("walk_loop")
                or (caster.AnimState:IsCurrentAnimation("walk_pst") and caster.AnimState:GetCurrentAnimationFrame() < 2)) then
            return "side"
        end
        return "front"
    end
    if facing == FACING_RIGHT or facing == FACING_LEFT then
        return "side"
    elseif facing == FACING_UP or facing == FACING_UPRIGHT or facing == FACING_UPLEFT then
        return "back"
    end
    return "front"
end

function Visual.Update(inst)
    if inst._visual_sleeping then return end
    local caster = inst._caster:value()
    if caster == nil or not caster:IsValid() or caster:HasTag("playerghost") then
        Visual.Clear(inst)
        return
    end
    local pose = GetPose(caster)
    local layout = Data[pose]
    local positions = {}
    for _, point in ipairs(layout.eyes) do
        -- Local offsets are authored head pixels. The engine applies the head's
        -- current animation, mirroring, prediction and observer camera.
        local x, y, z, found = caster.AnimState:GetSymbolPosition("headbase", point[1], point[2], 0)
        if not found then
            x, y, z, found = caster.AnimState:GetSymbolPosition("headbase_hat", point[1], point[2], 0)
        end
        if not found then
            Visual.Clear(inst)
            return
        end
        positions[#positions + 1] = { x, y, z }
    end
    if inst._eye_pose ~= pose then
        Visual.Clear(inst)
        inst._eyes = {}
        for _ = 1, #positions do inst._eyes[#inst._eyes + 1] = CreateEye(layout.glow) end
        inst._eye_pose = pose
    end

    local angle = inst._angle:value()
    local theta = angle * DEGREES
    local dx, dz = math.cos(theta), -math.sin(theta)
    local range = TUNING.KRYPTON_SURVIVOR.heatvision_range
    local scale = range * Data.beam.pixels_per_unit / (Data.beam.right - Data.beam.left)
    -- The native beam is centred art with asymmetric glow extents. Offset its
    -- root by its real left edge, so no part of it begins behind the eye.
    local advance = -Data.beam.left * scale / Data.beam.pixels_per_unit
    for index, eye in ipairs(inst._eyes) do
        local position = positions[index]
        local x, y, z = position[1] + dx * advance, position[2], position[3] + dz * advance
        eye.halo.Transform:SetPosition(x, y, z)
        eye.core.Transform:SetPosition(x, y, z)
        eye.halo.Transform:SetRotation(angle)
        eye.core.Transform:SetRotation(angle)
        eye.halo.AnimState:SetScale(scale, Data.beam.glow_width)
        eye.core.AnimState:SetScale(scale, Data.beam.core_width)
        if eye.spark ~= nil then eye.spark.Transform:SetPosition(unpack(position)) end
    end
end

function Visual.Init(inst)
    inst:AddComponent("updatelooper")
    inst.components.updatelooper:AddPostUpdateFn(Visual.Update)
    inst.OnEntitySleep = Visual.Sleep
    inst.OnEntityWake = Visual.Wake
    inst.OnRemoveEntity = Visual.Clear
end

return Visual
