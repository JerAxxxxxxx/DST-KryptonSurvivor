local MakePlayerCharacter = require("prefabs/player_common")
local Flight = require("krypton_flight")
local EatingVisual = require("krypton_eating_visual")
local ToolActions = require("krypton_tool_actions")
local StarcoreStarter = require("krypton_starcore_starter")
local AbilityStatus = require("krypton_ability_status")
local DarkForm = require("krypton_darkform")
local assets = {
    Asset("ANIM", "anim/krypton_survivor.zip"),
    Asset("ANIM", "anim/krypton_flight.zip"),
    Asset("ANIM", "anim/krypton_eating.zip"),
    Asset("ANIM", "anim/krypton_frostbreath_head.zip"),
    Asset("ANIM", "anim/ghost_wilson_build.zip"),
}
local prefabs = { "krypton_staff", "krypton_heatvision_fx", "krypton_starcore_amulet", "krypton_frostbreath_fx" }

local function common_postinit(inst)
    inst:AddTag("kryptonian")
    inst.MiniMapEntity:SetIcon("avatar_krypton_survivor.tex")
    inst.AnimState:SetBuild("krypton_survivor")
    Flight.CommonInit(inst)
    AbilityStatus.CommonInit(inst)
    DarkForm.CommonInit(inst)
    EatingVisual.CommonInit(inst)
    ToolActions.CommonInit(inst)
    local function EnableNightVision(player)
        if player.components.playervision ~= nil then
            -- Preserve normal daylight warmth; brighten darkness without the
            -- mole-goggles colour cube (the final argument disables that filter).
            local ambient = {
                PHASE_COLOURS = {
                    default = {
                        day = { colour = Point(1, 230 / 255, 158 / 255), time = 4 },
                        dusk = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 6 },
                        night = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 8 },
                    },
                    spring = {
                        day = { colour = Point(1, 244 / 255, 213 / 255), time = 4 },
                        dusk = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 6 },
                        night = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 8 },
                    },
                },
                FULL_MOON_COLOUR = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 8 },
                CAVE_COLOUR = { colour = Point(200 / 255, 200 / 255, 200 / 255), time = 2 },
            }
            player.components.playervision:PushForcedNightVision("krypton_survivor", 0, nil, false, ambient, true)
        end
    end
    inst:DoTaskInTime(0, EnableNightVision)
    inst:ListenForEvent("playeractivated", EnableNightVision)
end

local function master_postinit(inst)
    local tuning = TUNING.KRYPTON_SURVIVOR
    Flight.MasterInit(inst)
    inst:AddComponent("krypton_starcore")
    AbilityStatus.MasterInit(inst)
    inst.soundsname = "wilson"
    inst.ghostbuild = "ghost_wilson_build"
    inst.starting_inventory = { "krypton_staff", "krypton_starcore_amulet" }

    -- Keep the custom build across loading, resurrection and outfit changes.
    local skinner = inst.components.skinner
    local set_skin_mode = skinner.SetSkinMode
    skinner.SetSkinMode = function(self, skin_type, default_build)
        self.skin_data = self.skin_data or {}
        self.skin_data.normal_skin = "krypton_survivor"
        self.skin_data.ghost_skin = "ghost_wilson_build"
        return set_skin_mode(self, skin_type, default_build)
    end
    skinner:SetSkinMode("normal_skin")

    inst.components.health:SetMaxHealth(tuning.health)
    inst.components.hunger:SetMax(tuning.hunger)
    inst.components.hunger:SetRate(0)
    inst.components.sanity:SetMax(tuning.sanity)
    inst.components.sanity.rate_modifier = 0
    inst:AddComponent("krypton_darkform")
    if tuning.daylight_sanity_regen > 0 or tuning.daylight_health_regen > 0 then
        inst:DoPeriodicTask(1, function(player)
            if TheWorld.state.isday and not TheWorld:HasTag("cave") and not player:HasTag("playerghost")
                and not player:HasTag("corpse") and not player.components.health:IsDead() then
                local sanity = player.components.sanity
                -- DoDelta at the effective maximum still emits sanitydelta.
                -- Keep forced/induced display percentages out of this decision.
                if tuning.daylight_sanity_regen > 0 and not DarkForm.IsDark(player)
                    and sanity:GetRealPercent() < 1 - sanity:GetPenaltyPercent() then
                    sanity:DoDelta(tuning.daylight_sanity_regen)
                end
                if tuning.daylight_health_regen > 0 and player.components.health:IsHurt() then
                    player.components.health:DoDelta(tuning.daylight_health_regen, true, "krypton_sunlight")
                end
            end
        end)
    end

    -- The shared hook also configures remote-client movement prediction.
    inst.ExtraConfigurePlayerLocomotor(inst)

    inst.OnNewSpawn = function(player)
        local inventory = player.components.inventory
        local staff = inventory:FindItem(function(item) return item.prefab == "krypton_staff" end)
        if staff ~= nil then
            inventory:Equip(staff)
        end
        StarcoreStarter.Ensure(player)
    end
    -- Deferred until native inventory/component loading has completed. Old
    -- saves keep their backpack/armor equipped and receive one gift in storage.
    inst:DoTaskInTime(0, StarcoreStarter.Ensure)
    inst:ListenForEvent("ms_respawnedfromghost", function(player)
        player:DoTaskInTime(0, StarcoreStarter.Ensure)
    end)
end

return MakePlayerCharacter("krypton_survivor", prefabs, assets, common_postinit, master_postinit)
