local Status = {}
local Flight = require("krypton_flight")
local HeatVision = require("krypton_heatvision")
local FrostBreath = require("krypton_frostbreath")

local DIRTY_EVENT = "krypton_ability_statusdirty"
local FLAGS = { ALIVE = 1, FLYING = 2, FLIGHT_ENABLED = 4, AMULET = 8,
    PROTECTED = 16, RIDING = 32, REVIVING = 64, INITIALIZED = 128, REVIVE_SUPPORTED = 256,
    HEAT_AVAILABLE = 512, HEAT_COOLDOWN = 1024, FROST_AVAILABLE = 2048,
    FROST_COOLDOWN = 4096, FROST_CASTING = 8192, FROST_ENABLED = 16384 }

local function HasFlag(flags, flag)
    return math.floor(flags / flag) % 2 == 1
end

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function RemainingSeconds(value)
    -- This value is generated only by the simulation server. Clients display
    -- it directly instead of advancing a wall-clock or predicted countdown.
    return IsFinite(value) and math.min(65535, math.max(0, math.ceil(value))) or 0
end

function Status.CommonInit(inst)
    -- Declare the same netvars on every peer, before SetPristine is called.
    inst._krypton_status_flags = net_ushortint(inst.GUID, "krypton_survivor.status_flags", DIRTY_EVENT)
    inst._krypton_status_cooldown = net_ushortint(inst.GUID, "krypton_survivor.status_cooldown", DIRTY_EVENT)
end

local function NextSkillRefresh(inst, now)
    local due
    for _, value in ipairs({ inst._krypton_heatvision_nextcast or 0,
        inst._krypton_frostbreath_nextcast or 0,
        inst._krypton_frostbreath_channel ~= nil and inst._krypton_frostbreath_channel.ends or 0 }) do
        if IsFinite(value) and value > now and (due == nil or value < due) then due = value end
    end
    if inst._krypton_status_skill_due == due then return end
    if inst._krypton_status_skill_task ~= nil then inst._krypton_status_skill_task:Cancel() end
    inst._krypton_status_skill_task, inst._krypton_status_skill_due = nil, due
    if due ~= nil then
        -- A one-shot simulation task catches 0.35/1.2-second cooldowns without
        -- increasing periodic network polling or running a client wall clock.
        inst._krypton_status_skill_task = inst:DoTaskInTime(due - now, function(player)
            player._krypton_status_skill_task, player._krypton_status_skill_due = nil, nil
            Status.Sync(player)
        end)
    end
end

function Status.Sync(inst)
    if not TheWorld.ismastersim or inst._krypton_status_flags == nil then return end
    local health = inst.components.health
    local alive = health ~= nil and not health:IsDead()
        and not inst:HasTag("playerghost") and not inst:HasTag("corpse")
    local rider = inst.components.rider
    local riding = rider ~= nil and rider:IsRiding()
    local core = inst.components.krypton_starcore
    local flags = FLAGS.INITIALIZED
    if inst.ghostenabled ~= false or inst.components.revivablecorpse ~= nil then
        flags = flags + FLAGS.REVIVE_SUPPORTED
    end
    if alive then flags = flags + FLAGS.ALIVE end
    if Flight.IsFlying(inst) then flags = flags + FLAGS.FLYING end
    if TUNING.KRYPTON_SURVIVOR.flight_enabled ~= false then flags = flags + FLAGS.FLIGHT_ENABLED end
    if riding then flags = flags + FLAGS.RIDING end
    if core ~= nil then
        if core:GetEquippedAmulet() ~= nil then flags = flags + FLAGS.AMULET end
        if core:IsProtected() then flags = flags + FLAGS.PROTECTED end
        if core:IsAutoReviving() then flags = flags + FLAGS.REVIVING end
    end
    local now = GetTime()
    if HeatVision.CanCast(inst) then flags = flags + FLAGS.HEAT_AVAILABLE end
    if now < (inst._krypton_heatvision_nextcast or 0) then flags = flags + FLAGS.HEAT_COOLDOWN end
    if TUNING.KRYPTON_SURVIVOR.frostbreath_enabled ~= false then flags = flags + FLAGS.FROST_ENABLED end
    if FrostBreath.CanCast(inst) then flags = flags + FLAGS.FROST_AVAILABLE end
    if now < (inst._krypton_frostbreath_nextcast or 0) then flags = flags + FLAGS.FROST_COOLDOWN end
    local channel = inst._krypton_frostbreath_channel
    if channel ~= nil and not channel.finished and (channel.ends == nil or now < channel.ends) then
        flags = flags + FLAGS.FROST_CASTING
    end
    local cooldown = RemainingSeconds(core ~= nil and core:GetCooldownRemaining() or 0)
    if inst._krypton_status_cooldown:value() ~= cooldown then inst._krypton_status_cooldown:set(cooldown) end
    if inst._krypton_status_flags:value() ~= flags then inst._krypton_status_flags:set(flags) end
    NextSkillRefresh(inst, now)
end

function Status.MasterInit(inst)
    if not TheWorld.ismastersim or inst._krypton_status_task ~= nil then return end
    local sync = function() Status.Sync(inst) end
    -- Inventory's equip events run after its slot assignment; the existing
    -- Starcore component owns all protection, revival and save/load behavior.
    for _, event in ipairs({ "equip", "unequip", "krypton_flyingdirty", "death",
        "ms_becameghost", "ms_respawnedfromghost", "mounted", "dismounted", "newstate",
        "krypton_skillstatechanged" }) do
        inst:ListenForEvent(event, sync)
    end
    Status.Sync(inst)
    inst:DoTaskInTime(0, sync)
    -- Native entity periodic tasks use simulation time and stop with pause.
    inst._krypton_status_task = inst:DoPeriodicTask(1, sync)
    inst:ListenForEvent("onremove", function(player)
        if player._krypton_status_skill_task ~= nil then player._krypton_status_skill_task:Cancel() end
        player._krypton_status_skill_task, player._krypton_status_skill_due = nil, nil
    end)
end

function Status.GetSnapshot(inst)
    if inst == nil or inst._krypton_status_flags == nil or inst._krypton_status_cooldown == nil then
        return { initialized = false, cooldown = 0 }
    end
    local flags = inst._krypton_status_flags:value()
    return {
        initialized = HasFlag(flags, FLAGS.INITIALIZED),
        alive = HasFlag(flags, FLAGS.ALIVE),
        flying = HasFlag(flags, FLAGS.FLYING),
        flight_enabled = HasFlag(flags, FLAGS.FLIGHT_ENABLED),
        equipped = HasFlag(flags, FLAGS.AMULET),
        protected = HasFlag(flags, FLAGS.PROTECTED),
        riding = HasFlag(flags, FLAGS.RIDING),
        reviving = HasFlag(flags, FLAGS.REVIVING),
        revive_supported = HasFlag(flags, FLAGS.REVIVE_SUPPORTED),
        heat_available = HasFlag(flags, FLAGS.HEAT_AVAILABLE),
        heat_cooldown = HasFlag(flags, FLAGS.HEAT_COOLDOWN),
        frost_available = HasFlag(flags, FLAGS.FROST_AVAILABLE),
        frost_cooldown = HasFlag(flags, FLAGS.FROST_COOLDOWN),
        frost_casting = HasFlag(flags, FLAGS.FROST_CASTING),
        frost_enabled = HasFlag(flags, FLAGS.FROST_ENABLED),
        cooldown = inst._krypton_status_cooldown:value(),
    }
end

local COLOURS = {
    blue = { .40, .76, 1, 1 }, green = { .46, .91, .59, 1 },
    grey = { .65, .67, .70, 1 }, amber = { 1, .79, .39, 1 },
}

local function KeyLabel(value, fallback)
    if value == "disabled" then return "-", false end
    return type(value) == "string" and value:match("^KEY_([A-Z])$") or fallback, true
end

function Status.GetSkillRows(snapshot, language, keys, context)
    local zh, rows = language == "zh", {}
    keys, context = keys or {}, context or {}
    for _, skill in ipairs({
        { id = "heat", key = keys.heatvision_key, fallback = "R", title = zh and "热视线" or "Heat" },
        { id = "frost", key = keys.frostbreath_key, fallback = "X", title = zh and "吐息" or "Frost" },
    }) do
        local key, key_enabled = KeyLabel(skill.key, skill.fallback)
        local state
        if not snapshot.initialized then state = "syncing"
        elseif skill.id == "frost" and not snapshot.frost_enabled then state = "server_off"
        elseif not key_enabled then state = "key_off"
        elseif not snapshot.alive or context.blocked or (skill.id == "frost" and context.frost_blocked) then state = "unavailable"
        elseif not snapshot[skill.id .. "_available"] then state = "unavailable"
        elseif skill.id == "frost" and snapshot.frost_casting then state = "casting"
        elseif snapshot[skill.id .. "_cooldown"] then state = "cooldown"
        else state = "ready" end
        local labels = zh and {
            syncing = "同步中…", server_off = "服务器关闭", key_off = "按键关闭",
            unavailable = "不可用", casting = "施放中", cooldown = "冷却中", ready = "就绪",
        } or {
            syncing = "Syncing...", server_off = "Server off", key_off = "Key off",
            unavailable = "Unavailable", casting = "Casting", cooldown = "Cooldown", ready = "Ready",
        }
        local ready, casting = state == "ready", state == "casting"
        local base = COLOURS[ready and "green" or (casting and "blue" or "grey")]
        local colour = { base[1], base[2], base[3], (ready or casting) and 1 or .75 }
        local tooltip = zh
            and ("鼠标瞄准后按 " .. key .. "。技能状态由服务器确认；短冷却用变暗表示。\n聊天、界面、暂停或忙碌时暂不可用；按键可在本机模组配置中修改。")
            or ("Aim with the mouse and press " .. key .. ". Skill state is confirmed by the server; short cooldowns dim this row.\nChat, interfaces, pause or busy actions temporarily block input. Change the key in local mod settings.")
        if not key_enabled then
            tooltip = zh and "此技能的本机快捷键已关闭，可在模组配置中重新选择按键。"
                or "This skill's local shortcut is disabled. Choose a key in mod settings to enable input."
        end
        if skill.id == "frost" then
            tooltip = tooltip .. (zh and "\n吐息持续约1秒，间隔1.2秒；骑乘时不可用，服务器可关闭能力。"
                or "\nBreath lasts about 1 second with a 1.2-second interval; riding blocks it and the server can disable it.")
        end
        rows[#rows + 1] = { key = skill.id, state = state,
            text = skill.title .. " [" .. key .. "]" .. (zh and "：" or ": ") .. labels[state],
            colour = colour, tooltip = tooltip }
    end
    return rows
end

local function Clock(seconds)
    seconds = RemainingSeconds(seconds)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Status.GetRows(snapshot, language)
    local zh = language == "zh"
    local rows = {}
    local function Row(key, value, colour, tooltip)
        rows[#rows + 1] = { key = key, text = value, colour = COLOURS[colour], tooltip = tooltip }
    end
    if not snapshot.initialized then
        local waiting = zh and "同步中…" or "Syncing..."
        Row("flight", (zh and "飞行：" or "Flight: ") .. waiting, "grey", waiting)
        Row("amulet", (zh and "护符：" or "Amulet: ") .. waiting, "grey", waiting)
        Row("revive", (zh and "复活：" or "Revive: ") .. waiting, "grey", waiting)
        return rows
    end
    local flight, flight_colour
    if not snapshot.flight_enabled then flight, flight_colour = zh and "服务器关闭" or "Disabled", "grey"
    elseif not snapshot.alive then flight, flight_colour = zh and "不可用" or "Unavailable", "grey"
    elseif snapshot.riding then flight, flight_colour = zh and "骑乘中暂停" or "Riding", "grey"
    elseif snapshot.flying then flight, flight_colour = zh and "已开启" or "Enabled", "blue"
    else flight, flight_colour = zh and "已关闭" or "Disabled", "grey" end
    Row("flight", (zh and "飞行：" or "Flight: ") .. flight, flight_colour, zh
        and "人物自带飞行。开启时可以跨海与跨越洞穴内部裂隙；骑乘和死亡时暂停生效。\n只能在陆地或船上关闭飞行。切换按键可在模组配置中修改。"
        or "Innate flight crosses seas and gaps inside caves; it is suspended while riding or dead.\nLand on ground or a boat before disabling flight. The key is configurable.")

    local amulet = snapshot.protected and (zh and "保护生效" or "Protected")
        or (snapshot.equipped and (zh and "暂未生效" or "Inactive") or (zh and "未装备" or "Not equipped"))
    Row("amulet", (zh and "护符：" or "Amulet: ") .. amulet, snapshot.protected and "green" or "grey", zh
        and "装备星核护符并存活时保持干燥与安全体温。\n复活冷却期间，这两项保护仍生效；护符不免疫攻击、火焰或食物的其他影响。"
        or "While alive and wearing the Starcore Amulet, stay dry and at a safe temperature.\nThese protections remain during revival cooldown. Attacks, fire and other food effects still apply.")

    local revive, revive_colour
    if snapshot.reviving then revive, revive_colour = zh and "复活中" or "Reviving", "amber"
    elseif snapshot.revive_supported == false then
        revive, revive_colour = zh and "模式不可用" or "Unavailable", "grey"
    elseif snapshot.cooldown > 0 then
        revive, revive_colour = (zh and "冷却 " or "Cooldown ") .. Clock(snapshot.cooldown), "amber"
    elseif not snapshot.equipped then revive, revive_colour = zh and "未装备" or "Not equipped", "grey"
    elseif snapshot.protected then revive, revive_colour = zh and "已就绪" or "Ready", "green"
    else revive, revive_colour = zh and "不可用" or "Unavailable", "grey" end
    local revive_tip = zh
        and "佩戴且就绪时，死亡后自动在原地复活；成功后冷却一个游戏日。\n冷却属于人物，卸下或更换护符不会重置。倒计时来自服务器，暂停游戏时停止。\n荒野模式等不保留幽灵或可复活尸体的模式不触发自动复活。"
        or "Wear the ready amulet to revive automatically at your death location; a successful revival starts one game day of cooldown.\nUnequipping or replacing it does not reset the player's cooldown. The server timer stops with the simulation.\nModes without a ghost or revivable corpse, such as Wilderness, do not trigger automatic revival."
    if not snapshot.equipped and snapshot.cooldown > 0 then
        revive_tip = (zh and "当前未装备护符，冷却仍在继续。\n" or "Amulet not equipped; cooldown continues.\n") .. revive_tip
    end
    Row("revive", (zh and "复活：" or "Revive: ") .. revive, revive_colour, revive_tip)
    return rows
end

Status.DIRTY_EVENT = DIRTY_EVENT
return Status
