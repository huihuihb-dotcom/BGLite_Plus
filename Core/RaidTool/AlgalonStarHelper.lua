if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L or {}
local LibBG = ns.LibBG
local RGB = ns.RGB
local BIAOGE_TEXT_FONT = BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT

local STC_b1 = BG.STC_b1 or function(t) return "|cff00BFFF" .. t .. "|r" end
local STC_g1 = BG.STC_g1 or function(t) return "|cff00FF00" .. t .. "|r" end
local STC_r1 = BG.STC_r1 or function(t) return "|cffff0000" .. t .. "|r" end
local STC_o1 = BG.STC_o1 or function(t) return "|cffff9900" .. t .. "|r" end
local STC_y1 = BG.STC_y1 or function(t) return "|cffffff00" .. t .. "|r" end
local STC_dis = BG.STC_dis or function(t) return "|cff888888" .. t .. "|r" end
local STC_w1 = BG.STC_w1 or function(t) return "|cffffffff" .. t .. "|r" end

local AlgalonStar = {}
ns.AlgalonStar = AlgalonStar
_G.AlgalonStar = AlgalonStar

--------------------------------------------------------------------------------
-- 1. 核心常量与配置
--------------------------------------------------------------------------------
local STAR_NPC_ID = 32955        -- 坍缩星 (Collapsing Star)
local ALGALON_NPC_ID = 32871     -- 观察者奥尔加隆 (Algalon the Observer)

-- 大爆炸技能 ID (25人: 64584, 10人: 64443)
local BIG_BANG_SPELLS = {
    [64584] = true,
    [64443] = true,
}

-- 黑洞爆炸技能 ID (坍缩星死亡爆炸: 10人 64122, 25人 65108)
local BLACK_HOLE_EXPLOSION_SPELLS = {
    [64122] = true,
    [65108] = true,
}

local BIGBANG_BASE_COOLDOWN = 90.5     -- 每次施法大爆炸间隔严格为 90.5 秒 (对齐官方 DBM: timerNextBigBang = 90.5s)
local BIGBANG_FIRST_PULL_DELAY = 98.0  -- 战斗开始到首次大爆炸约 98.0 秒 (对齐 DBM: 8s 开怪剧情台词 + 90s)
local PHASE2_HP_THRESHOLD = 0.20       -- 奥尔加隆血量低于 20% 进入 P2 (转阶段)

-- 团队标记固定映射：1号骷髅(8), 2号红叉(7), 3号方块(6), 4号三角(4)
local MARK_LIST = { 8, 7, 6, 4 }
local MARK_NAMES = {
    [1] = "星星",
    [2] = "大饼",
    [3] = "菱形",
    [4] = "三角",
    [5] = "月亮",
    [6] = "方块",
    [7] = "红叉",
    [8] = "骷髅",
}
local MARK_TEXTURE_PREFIX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function GetMarkIcon(mark, size)
    size = size or 16
    if mark and type(mark) == "number" and mark >= 1 and mark <= 8 then
        return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d:%d:0:0|t", mark, size, size)
    end
    return ""
end

-- 核心修星伤害 DoT 白名单定义 (德鲁伊、牧师、术士)
local RAW_DOT_SPELLS = {
    -- 德鲁伊 (Druid)
    { id = 8921, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8924, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8925, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8926, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8927, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8928, name = "月火术", class = "DRUID", duration = 12 },
    { id = 8929, name = "月火术", class = "DRUID", duration = 12 },
    { id = 9833, name = "月火术", class = "DRUID", duration = 12 },
    { id = 9834, name = "月火术", class = "DRUID", duration = 12 },
    { id = 9835, name = "月火术", class = "DRUID", duration = 12 },
    { id = 26988, name = "月火术", class = "DRUID", duration = 12 },
    { id = 48462, name = "月火术", class = "DRUID", duration = 12 },
    { id = 48463, name = "月火术", class = "DRUID", duration = 12 }, -- 满级月火

    { id = 5570, name = "虫群", class = "DRUID", duration = 12 },
    { id = 24974, name = "虫群", class = "DRUID", duration = 12 },
    { id = 24975, name = "虫群", class = "DRUID", duration = 12 },
    { id = 24976, name = "虫群", class = "DRUID", duration = 12 },
    { id = 24977, name = "虫群", class = "DRUID", duration = 12 },
    { id = 27013, name = "虫群", class = "DRUID", duration = 12 },
    { id = 48468, name = "虫群", class = "DRUID", duration = 12 }, -- 满级虫群

    -- 牧师 (Priest)
    { id = 589, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 594, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 970, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 992, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 2767, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 10892, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 10893, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 10894, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 25367, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 25368, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 48124, name = "暗言术：痛", class = "PRIEST", duration = 18 },
    { id = 48125, name = "暗言术：痛", class = "PRIEST", duration = 18 }, -- 满级痛

    { id = 34914, name = "吸血鬼之触", class = "PRIEST", duration = 15 },
    { id = 34916, name = "吸血鬼之触", class = "PRIEST", duration = 15 },
    { id = 34917, name = "吸血鬼之触", class = "PRIEST", duration = 15 },
    { id = 48160, name = "吸血鬼之触", class = "PRIEST", duration = 15 }, -- 满级触

    { id = 2944, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 19276, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 19277, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 19278, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 19279, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 19280, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 25467, name = "噬灵疫病", class = "PRIEST", duration = 24 },
    { id = 48300, name = "噬灵疫病", class = "PRIEST", duration = 24 }, -- 满级疫病

    -- 术士 (Warlock)
    { id = 172, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 6222, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 6223, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 7648, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 11671, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 11672, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 25311, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 27216, name = "腐蚀术", class = "WARLOCK", duration = 18 },
    { id = 47813, name = "腐蚀术", class = "WARLOCK", duration = 18 }, -- 满级腐蚀

    { id = 980, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 1014, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 6079, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 11705, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 11706, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 27218, name = "痛苦诅咒", class = "WARLOCK", duration = 24 },
    { id = 47864, name = "痛苦诅咒", class = "WARLOCK", duration = 24 }, -- 满级痛苦诅咒
}

local DOT_WHITELIST_BY_ID = {}
local DOT_WHITELIST_BY_NAME = {}

for _, item in ipairs(RAW_DOT_SPELLS) do
    DOT_WHITELIST_BY_ID[item.id] = item
    DOT_WHITELIST_BY_NAME[item.name] = item
    if GetSpellInfo then
        local realName, _, realIcon = GetSpellInfo(item.id)
        if realName then
            item.name = realName
            item.icon = realIcon
            DOT_WHITELIST_BY_NAME[realName] = item
        end
    end
end

--------------------------------------------------------------------------------
-- 2. 状态变量与数据结构 (含前向声明，杜绝 nil 调用)
--------------------------------------------------------------------------------
local activeStars = {}            -- [guid] = starData
local starCounter = 0             -- 顺位注册计数器
local bigBangCastEnd = 0          -- 当前大爆炸施法结束时间戳 (8s 施法)
local bigBangNextEstimate = 0     -- 下次大爆炸预计发生的时间戳
local encounterStartTime = 0      -- 开战时间戳
local isPhase2 = false            -- 是否进入 P2 阶段 (<= 20% HP)
local algalonGUID = nil           -- 奥尔加隆 GUID
local isCombatRegistered = false
local isTesting = false
local testTicker = nil
local lastAlertSoundTime = 0

-- 关键前向声明：防止 ShowMainUI 调用 RefreshUI 时报 attempt to call a nil value
local RefreshUI
local CreateMainUI
local ShowMainUI

local eventFrame = CreateFrame("Frame", "BG_AlgalonStarEventFrame", UIParent)
AlgalonStar.eventFrame = eventFrame

--------------------------------------------------------------------------------
-- 3. 辅助解析与权限函数
--------------------------------------------------------------------------------
local function GetNpcIDFromGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" then
        return tonumber(npcID)
    end
    local id = guid:match("Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if id then return tonumber(id) end
    return nil
end

local function CanSetMarks()
    if not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.autoMark) then
        return false
    end
    if not IsInGroup() then return true end
    if IsInRaid() then
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    else
        return UnitIsGroupLeader("player")
    end
end

local function GetCombatLogArgs(...)
    if CombatLogGetCurrentEventInfo then
        return CombatLogGetCurrentEventInfo()
    end
    return ...
end

local function GetHarmfulAura(unit, index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HARMFUL")
        if aura then
            return aura.name, aura.icon, aura.applications or aura.count or 0, aura.duration or 0, aura.expirationTime or 0, aura.sourceUnit, aura.spellId
        end
        return nil
    elseif UnitDebuff then
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitDebuff(unit, index)
        if type(icon) ~= "string" and type(icon) ~= "number" then
            name, _, icon, count, debuffType, duration, expirationTime, source, isStealable, _, spellId = UnitDebuff(unit, index)
        end
        return name, icon, count, duration, expirationTime, source, spellId
    elseif UnitAura then
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, index, "HARMFUL")
        if type(icon) ~= "string" and type(icon) ~= "number" then
            name, _, icon, count, debuffType, duration, expirationTime, source, isStealable, _, spellId = UnitAura(unit, index, "HARMFUL")
        end
        return name, icon, count, duration, expirationTime, source, spellId
    end
    return nil
end

function AlgalonStar.IsInUlduar()
    if isTesting then return true end
    if GetInstanceInfo then
        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        if instanceID == 603 then return true end
    end
    local zone = GetRealZoneText() or GetZoneText() or ""
    local subZone = GetSubZoneText() or ""
    if zone:find("奥杜尔") or zone:find("奧杜爾") or zone:find("Ulduar") or subZone:find("天界") or subZone:find("天穹") or subZone:find("Celestial") then
        return true
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and (mapID == 147 or (mapID >= 147 and mapID <= 152) or (mapID >= 529 and mapID <= 534)) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 4. 注册与数据更新核心算法 (自适应与平滑掉血)
--------------------------------------------------------------------------------
local function GetDefaultStarMaxHP()
    return (IsInRaid() and GetNumGroupMembers() > 10) and 75600 or 37800
end

local function RegisterStar(guid, maxHP)
    local now = GetTime()
    if not activeStars[guid] then
        -- 优先复用已经死亡槽位的顺位标记(1~4)，确保场上4颗活星永远分配骷髅/红叉/方块/三角
        local usedIndices = {}
        for _, s in pairs(activeStars) do
            if not s.isDead and s.currentHP > 0 and s.index then
                usedIndices[s.index] = true
            end
        end
        local assignIndex = nil
        for idx = 1, 4 do
            if not usedIndices[idx] then
                assignIndex = idx
                break
            end
        end
        if not assignIndex then
            starCounter = (starCounter % 4) + 1
            assignIndex = starCounter
        end

        local mark = MARK_LIST[assignIndex] or 8
        local defaultMax = (maxHP and maxHP > 0) and maxHP or GetDefaultStarMaxHP()

        activeStars[guid] = {
            guid = guid,
            index = assignIndex,
            raidMark = mark,
            currentHP = defaultMax,
            maxHP = defaultMax,
            dps = defaultMax * 0.01,  -- 刚出生默认自残速率 1%/s
            dmgHistory = {},
            dots = {},
            spawnTime = now,
            lastTick = now,
            lastRealSync = 0,         -- 上次由姓名板/UNIT_HEALTH/CLEU伤害同步的时间戳
            nameplateUnit = nil,
            lastMarkTime = 0,
            isDead = false,
        }
    else
        if maxHP and maxHP > 0 then
            local star = activeStars[guid]
            if star.lastRealSync == 0 and star.currentHP == star.maxHP then
                star.currentHP = maxHP
            end
            star.maxHP = maxHP
        end
    end
    return activeStars[guid]
end

-- 记录掉血滑动窗口并计算实时掉血速率 (3秒滑动窗口)
local function AddDamageHistory(star, dmg, now)
    table.insert(star.dmgHistory, { t = now, dmg = dmg })
    local cutoff = now - 3.0
    local totalDmg = 0
    local oldestTime = now

    for i = #star.dmgHistory, 1, -1 do
        local entry = star.dmgHistory[i]
        if entry.t < cutoff then
            table.remove(star.dmgHistory, i)
        else
            totalDmg = totalDmg + entry.dmg
            if entry.t < oldestTime then oldestTime = entry.t end
        end
    end

    local timeSpan = now - oldestTime
    local baseDecay = star.maxHP * 0.01
    if timeSpan > 0.4 and totalDmg > 0 then
        star.dps = math.max(baseDecay, totalDmg / timeSpan)
    else
        star.dps = (star.dps and star.dps >= baseDecay) and star.dps or baseDecay
    end
end

-- 从姓名板扫描专属 DoT
local function ScanNameplateDots(star, unit)
    if not unit then return end
    local now = GetTime()
    local seenDots = {}

    for i = 1, 40 do
        local name, icon, count, duration, expirationTime, source, spellId = GetHarmfulAura(unit, i)
        if not name then break end

        local info = (spellId and DOT_WHITELIST_BY_ID[spellId]) or DOT_WHITELIST_BY_NAME[name]
        if info then
            local isMine = (source == "player")
            star.dots[name] = {
                name = name,
                icon = icon or info.icon,
                duration = (duration and duration > 0) and duration or info.duration,
                expTime = (expirationTime and expirationTime > 0) and expirationTime or (now + info.duration),
                count = count or 0,
                isMine = isMine,
                class = info.class,
            }
            seenDots[name] = true
        end
    end

    -- 清理已经自然结束或消失的 DoT
    for dotName, _ in pairs(star.dots) do
        if not seenDots[dotName] then
            star.dots[dotName] = nil
        end
    end
end

-- 预定义扫描单元数组，彻底消除高频 RefreshUI 运行中的表分配与字符串拼接 GC 损耗
local STATIC_UNITS_BASE = { "target", "focus", "mouseover" }
local RAID_TARGET_UNITS = {}
for i = 1, 40 do
    RAID_TARGET_UNITS[i] = "raid" .. i .. "target"
end
local PARTY_TARGET_UNITS = {}
for i = 1, 4 do
    PARTY_TARGET_UNITS[i] = "party" .. i .. "target"
end
local lastGroupScanTime = 0

-- 扫描当前小队/团队目标及焦点，弥补姓名板被关闭或未进入视野时的盲区 (0 垃圾分配，0.35s 轻量节流)
local function ScanGroupTargetsForStars(force)
    if isPhase2 or isTesting then return end
    local now = GetTime()
    if not force and (now - lastGroupScanTime) < 0.35 then return end
    lastGroupScanTime = now

    local function CheckUnit(u)
        if UnitExists(u) and not UnitIsDead(u) then
            local guid = UnitGUID(u)
            if guid and GetNpcIDFromGUID(guid) == STAR_NPC_ID then
                local maxHP = UnitHealthMax(u)
                local curHP = UnitHealth(u)
                local star = RegisterStar(guid, maxHP)
                if curHP and curHP > 0 then
                    star.currentHP = curHP
                    star.lastRealSync = now
                    star.lastTick = now
                end
                if maxHP and maxHP > 0 then
                    star.maxHP = maxHP
                end
                local rt = GetRaidTargetIndex(u)
                if rt and rt >= 1 and rt <= 8 then
                    star.raidMark = rt
                end
                ScanNameplateDots(star, u)
            end
        end
    end

    for _, u in ipairs(STATIC_UNITS_BASE) do
        CheckUnit(u)
    end

    if IsInRaid() then
        local num = GetNumGroupMembers()
        for i = 1, num do
            local u = RAID_TARGET_UNITS[i]
            if u then CheckUnit(u) end
        end
    elseif IsInGroup() then
        local num = GetNumSubgroupMembers()
        for i = 1, num do
            local u = PARTY_TARGET_UNITS[i]
            if u then CheckUnit(u) end
        end
    end
end

--------------------------------------------------------------------------------
-- 5. 核心安全预测模型 (红 / 黄 / 绿 深度判定算法)
--------------------------------------------------------------------------------
local function EvaluateStarSafety(star, now, isBigBangCasting, bigBangLeft, timeToNextBB, collisionInfo)
    local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
    local dps = (star.dps > 0) and star.dps or (star.maxHP * 0.01)
    local eta = star.currentHP / dps

    -- 【最高优先级：双星连炸致命灭团点 (Double Star Collision)】
    if collisionInfo then
        local gap = collisionInfo.gap or 0
        if collisionInfo.nearBigBang then
            if collisionInfo.isEarlier then
                return "RED", string.format("大爆炸双爆! (早%.1fs·先引爆)", gap), 1.0, 0.1, 0.0
            else
                return "RED", string.format("大爆炸双爆! (慢%.1fs·停手错开)", gap), 1.0, 0.1, 0.0
            end
        else
            if collisionInfo.isEarlier then
                return "RED", string.format("双星连炸! (早%.1fs·先引爆)", gap), 1.0, 0.2, 0.0
            else
                return "RED", string.format("双星连炸! (慢%.1fs·停手错开)", gap), 1.0, 0.2, 0.0
            end
        end
    end

    -- A. 大爆炸正在读条中 (8 秒读条期间，全团进入黑洞躲避)
    if isBigBangCasting then
        if eta >= 1.5 and eta <= (bigBangLeft - 1.2) then
            return "GREEN", string.format("进洞免伤 (洞内%.1fs)", eta), 0.1, 0.85, 0.3
        end
        if math.abs(eta - bigBangLeft) <= 1.5 then
            return "RED", string.format("出洞瞬间炸! (危险%.1fs)", eta), 1.0, 0.2, 0.0
        end
        if eta > (bigBangLeft + 1.5) and eta <= (bigBangLeft + 20.0) then
            local delay = eta - bigBangLeft
            return "YELLOW", string.format("出洞炸 (出洞+%.1fs)", delay), 0.95, 0.8, 0.1
        end
        if eta < 1.5 then
            return "RED", string.format("进洞前猝死! (%.1fs)", eta), 0.95, 0.1, 0.1
        end
        return "YELLOW", string.format("延后较慢 (出洞+%.0fs)", eta - bigBangLeft), 0.2, 0.7, 0.9
    end

    -- B. 非大爆炸读条期间 (正常战斗阶段，依据下次大爆炸倒计时预测)
    local diff = (timeToNextBB > 0) and (eta - timeToNextBB) or nil

    if diff and (diff >= -4.0 and diff < 1.5) then
        if eta <= 5.0 or pct <= 15 then
            return "RED", string.format("撞车濒死! (剩%.1fs·差%.1fs)", eta, math.abs(diff)), 1.0, 0.2, 0.0
        else
            return "RED", string.format("大爆炸撞车危险! (差%.1fs)", math.abs(diff)), 1.0, 0.3, 0.0
        end
    end
    if diff and (diff >= 6.5 and diff <= 9.5) then
        return "RED", string.format("出洞瞬间撞车! (危险%.1fs)", math.abs(diff - 8.0)), 1.0, 0.2, 0.0
    end
    if diff and (diff >= 1.5 and diff < 6.5) then
        return "GREEN", string.format("进洞免伤 (洞内%.1fs)", diff - 1.5), 0.1, 0.85, 0.3
    end
    if diff and (diff < -4.0 and eta >= 5.0 and eta <= 40.0) then
        local lead = -diff
        return "YELLOW", string.format("提前留洞 (提前%.0fs爆)", lead), 0.95, 0.8, 0.1
    end
    if eta <= 5.0 or pct <= 15 then
        if diff and diff < -4.0 then
            return "YELLOW", string.format("即将留洞 (剩%.1fs·提前%.0fs)", eta, -diff), 0.95, 0.8, 0.1
        else
            return "RED", string.format("即将自爆! (剩%.1fs)", eta), 0.95, 0.1, 0.1
        end
    end
    if diff and (diff > 9.5 and diff <= 28.0) then
        local delay = diff - 8.0
        return "YELLOW", string.format("出洞炸 (大爆炸后%.0fs)", delay), 0.95, 0.8, 0.1
    end
    if eta > 60.0 or (diff and diff > 28.0) then
        return "YELLOW", string.format("掉血平稳 (%.0fs后)", eta), 0.2, 0.7, 0.9
    end

    return "YELLOW", string.format("自爆: %.1fs", eta), 0.9, 0.75, 0.2
end

--------------------------------------------------------------------------------
-- 6. UI 界面构建 (彻底剥离 Secure 战斗锁定冲突，战斗中 100% 自由显隐不拦截)
--------------------------------------------------------------------------------
local mainFrame = nil
local bars = {}

CreateMainUI = function()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "BG_AlgalonStarMainUI", UIParent, "BackdropTemplate")
    mainFrame:SetSize(246, 168)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    -- 恢复保存的坐标
    local savedPoint = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.point
    if savedPoint and type(savedPoint) == "table" and #savedPoint >= 5 then
        mainFrame:SetPoint(savedPoint[1], savedPoint[2], savedPoint[3], savedPoint[4], savedPoint[5])
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 340, 50)
    end

    local function SaveMainFramePosition()
        local point, _, relPoint, x, y = mainFrame:GetPoint()
        BiaoGe = BiaoGe or {}
        BiaoGe.AlgalonStar = BiaoGe.AlgalonStar or {}
        BiaoGe.AlgalonStar.point = { point, "UIParent", relPoint, math.floor(x or 0), math.floor(y or 0) }
    end

    mainFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isMoving and not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    mainFrame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = nil
            SaveMainFramePosition()
        end
    end)
    mainFrame:SetScript("OnDragStart", function(self)
        if not self.isMoving and not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = nil
            SaveMainFramePosition()
        end
    end)
    mainFrame:SetScript("OnHide", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = nil
        end
    end)

    mainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    mainFrame:SetBackdropColor(0.05, 0.07, 0.1, 0.88)
    mainFrame:SetBackdropBorderColor(0.2, 0.6, 1, 0.7)

    -- 顶部标题与大爆炸/P2警报条
    local titleBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    titleBg:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -4)
    titleBg:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -4)
    titleBg:SetHeight(22)
    titleBg:SetColorTexture(0.1, 0.18, 0.28, 0.8)
    mainFrame.titleBg = titleBg

    local titleText = mainFrame:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    titleText:SetPoint("LEFT", titleBg, "LEFT", 6, 0)
    titleText:SetText(STC_b1("观星者") .. " 坍缩星监控")
    mainFrame.titleText = titleText

    -- 顶部专属拖拽手柄层
    local dragBar = CreateFrame("Frame", nil, mainFrame)
    dragBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -4)
    dragBar:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", -26, -26)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not mainFrame.isMoving and not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
            mainFrame:StartMoving()
            mainFrame.isMoving = true
        end
    end)
    dragBar:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and mainFrame.isMoving then
            mainFrame:StopMovingOrSizing()
            mainFrame.isMoving = nil
            SaveMainFramePosition()
        end
    end)
    dragBar:SetScript("OnDragStart", function()
        if not mainFrame.isMoving and not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
            mainFrame:StartMoving()
            mainFrame.isMoving = true
        end
    end)
    dragBar:SetScript("OnDragStop", function()
        if mainFrame.isMoving then
            mainFrame:StopMovingOrSizing()
            mainFrame.isMoving = nil
            SaveMainFramePosition()
        end
    end)
    dragBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_b1("观星修星助手"), 1, 1, 1)
        GameTooltip:AddLine("按住鼠标左键可自由拖动窗口位置。", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("输入 " .. STC_g1("/star lock") .. " 可锁定/解锁窗口拖动。", 0.7, 0.9, 1)
        GameTooltip:Show()
    end)
    dragBar:SetScript("OnLeave", GameTooltip_Hide)
    mainFrame.dragBar = dragBar

    -- 关闭按钮
    local btnClose = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    btnClose:SetSize(20, 20)
    btnClose:SetPoint("RIGHT", titleBg, "RIGHT", -2, 0)
    btnClose:SetFrameLevel(dragBar:GetFrameLevel() + 5)
    btnClose:SetScript("OnClick", function()
        mainFrame:Hide()
        if BG and BG.PlaySound then BG.PlaySound(1) end
    end)

    -- 专属战术警报栏 (第 2 行：用于双星连炸等重大突发危机)
    local alertBar = CreateFrame("Frame", nil, mainFrame)
    alertBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -28)
    alertBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -28)
    alertBar:SetHeight(22)

    local alertBg = alertBar:CreateTexture(nil, "BACKGROUND")
    alertBg:SetAllPoints()
    alertBg:SetColorTexture(0.18, 0.04, 0.05, 0.92)
    alertBar.bg = alertBg

    local borderTop = alertBar:CreateTexture(nil, "BORDER")
    borderTop:SetPoint("TOPLEFT", alertBar, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", alertBar, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)
    borderTop:SetColorTexture(1.0, 0.5, 0.1, 0.65)
    alertBar.borderTop = borderTop

    local borderBottom = alertBar:CreateTexture(nil, "BORDER")
    borderBottom:SetPoint("BOTTOMLEFT", alertBar, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", alertBar, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)
    borderBottom:SetColorTexture(1.0, 0.5, 0.1, 0.65)
    alertBar.borderBottom = borderBottom

    local alertText = alertBar:CreateFontString(nil, "OVERLAY")
    alertText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    alertText:SetPoint("LEFT", alertBar, "LEFT", 6, 0)
    alertText:SetPoint("RIGHT", alertBar, "RIGHT", -6, 0)
    alertText:SetJustifyH("LEFT")
    alertText:SetWordWrap(false)
    alertBar.text = alertText
    alertBar:Hide()
    mainFrame.alertBar = alertBar

    -- 4 根血条构建：采用非受保护普通 Button，彻底杜绝战斗中 Show/Hide/SetPoint 引发 ADDON_ACTION_BLOCKED 导致血条不显示！
    for i = 1, 4 do
        local bar = CreateFrame("Button", "BG_AlgalonStarBar_" .. i, mainFrame)
        bar:SetSize(230, 26)
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -30 - (i - 1) * 32)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")

        bar:SetScript("OnDragStart", function()
            if not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
                mainFrame:StartMoving()
                mainFrame.isMoving = true
            end
        end)
        bar:SetScript("OnDragStop", function()
            if mainFrame.isMoving then
                mainFrame:StopMovingOrSizing()
                mainFrame.isMoving = nil
                SaveMainFramePosition()
            end
        end)

        -- 状态条底图
        local sb = CreateFrame("StatusBar", nil, bar)
        sb:SetAllPoints()
        sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        sb:GetStatusBarTexture():SetHorizTile(false)
        sb:SetStatusBarColor(0, 0.7, 1)
        bar.sb = sb

        local bg = sb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.12, 0.18, 0.6)
        bar.bg = bg

        -- 标记图标
        local markIcon = sb:CreateTexture(nil, "OVERLAY")
        markIcon:SetSize(20, 20)
        markIcon:SetPoint("LEFT", sb, "LEFT", 3, 0)
        bar.markIcon = markIcon

        -- 血量与名称文本
        local label = sb:CreateFontString(nil, "OVERLAY")
        label:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        label:SetPoint("LEFT", markIcon, "RIGHT", 4, 0)
        bar.label = label

        -- 安全预测与倒计时文本
        local timerText = sb:CreateFontString(nil, "OVERLAY")
        timerText:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.timerText = timerText

        -- 边框高亮材质
        local glow = bar:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("TOPLEFT", -3, 3)
        glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)
        bar.glow = glow

        bar:SetScript("OnEnter", function(self)
            local star = self.starData
            if not star then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local mark = (star.raidMark and star.raidMark > 0) and star.raidMark or MARK_LIST[star.index or i] or 8
            local markName = MARK_NAMES[mark] or "坍缩星"
            GameTooltip:AddLine(GetMarkIcon(mark, 16) .. " 坍缩星 (" .. markName .. ")", 1, 1, 1)
            local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
            GameTooltip:AddLine(string.format("血量: %d / %d (%.1f%%)", star.currentHP or 0, star.maxHP or 75600, pct), 0.85, 0.85, 0.85)
            if star.dps and star.dps > 0 then
                GameTooltip:AddLine(string.format("掉血速率: %.0f/s", star.dps), 0.85, 0.85, 0.85)
            end
            GameTooltip:AddLine("按住左键拖动: 移动窗口位置", 0.7, 0.9, 1)
            GameTooltip:Show()
        end)
        bar:SetScript("OnLeave", GameTooltip_Hide)

        -- 右侧 DoT 图标槽 (3个槽位，尺寸 20x20)
        local dotsContainer = CreateFrame("Frame", nil, bar)
        dotsContainer:SetSize(72, 22)
        dotsContainer:SetPoint("LEFT", bar, "RIGHT", 6, 0)
        bar.dotsContainer = dotsContainer

        bar.dotFrames = {}
        for d = 1, 3 do
            local dotF = CreateFrame("Frame", nil, dotsContainer)
            dotF:SetSize(20, 20)
            dotF:SetPoint("LEFT", dotsContainer, "LEFT", (d - 1) * 23, 0)

            local icon = dotF:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            dotF.icon = icon

            local border = dotF:CreateTexture(nil, "OVERLAY")
            border:SetPoint("TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", 2, -2)
            border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
            border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
            border:Hide()
            dotF.border = border

            local cd = CreateFrame("Cooldown", nil, dotF, "CooldownFrameTemplate")
            cd:SetAllPoints()
            cd:SetDrawEdge(false)
            cd:SetSwipeColor(0, 0, 0, 0.75)
            if cd.SetHideCountdownNumbers then
                cd:SetHideCountdownNumbers(true)
            end
            cd.noCooldownCount = true
            dotF.cd = cd

            local cdText = dotF:CreateFontString(nil, "OVERLAY")
            cdText:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
            cdText:SetPoint("CENTER", dotF, "CENTER", 0, 0)
            dotF.cdText = cdText

            dotF:Hide()
            bar.dotFrames[d] = dotF
        end

        bar:Hide()
        bars[i] = bar
    end

    mainFrame:Hide()
    AlgalonStar.mainFrame = mainFrame
    return mainFrame
end

ShowMainUI = function()
    local enabled = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.enabled
    if not enabled and not isTesting then return end

    if not isTesting and not AlgalonStar.IsInUlduar() then return end

    CreateMainUI()
    if mainFrame and not mainFrame:IsShown() then
        mainFrame:Show()
    end
    if RefreshUI then
        RefreshUI()
    end
end

--------------------------------------------------------------------------------
-- 7. UI 实时刷新与渲染逻辑
--------------------------------------------------------------------------------
RefreshUI = function()
    if not mainFrame or not mainFrame:IsShown() then return end

    local now = GetTime()

    -- 1. P2 阶段优先展示
    if isPhase2 then
        mainFrame.titleBg:SetColorTexture(0.1, 0.5, 0.2, 0.95)
        mainFrame.titleText:SetText(STC_g1("【P2 阶段】") .. " 坍缩星消失，无大爆炸 ─ 全力 RUSH Boss！")
        if mainFrame.alertBar then mainFrame.alertBar:Hide() end
        for i = 1, 4 do
            if bars[i] then bars[i]:Hide() end
        end
        return
    end

    -- 1.5 扫描队友目标/焦点并推演未处于视野内的坍缩星自然自残掉血 (1%/s)
    if not isTesting then
        ScanGroupTargetsForStars()
        for _, star in pairs(activeStars) do
            if not star.isDead and star.currentHP > 0 then
                local dt = now - (star.lastTick or now)
                star.lastTick = now
                -- 若该星当前没有姓名板实时同步，也超过 1.2 秒未收到直接血量校准，则按自残速率平滑演进
                if dt > 0 and dt < 5.0 and not star.nameplateUnit and (now - (star.lastRealSync or 0)) > 1.2 then
                    local decay = (star.maxHP or 75600) * 0.01 * dt
                    star.currentHP = math.max(1, star.currentHP - decay)
                end
            end
        end
    end

    -- 2. 提取活星并按血量排序
    local starList = {}
    for _, star in pairs(activeStars) do
        if not star.isDead and star.currentHP > 0 then
            table.insert(starList, star)
        end
    end

    table.sort(starList, function(a, b)
        if math.abs(a.currentHP - b.currentHP) > 1 then
            return a.currentHP < b.currentHP
        end
        return (a.index or 0) < (b.index or 0)
    end)

    -- 3. 大爆炸读条与预警倒计时
    local bigBangLeft = math.max(0, bigBangCastEnd - now)
    local isBigBangCasting = (bigBangLeft > 0)
    local timeToNextBB = (bigBangNextEstimate > 0) and math.max(0, bigBangNextEstimate - now) or 0

    -- 4. 全局双星连炸 (Double Star Collision) 检测
    local worstCollision = nil
    local minCollisionGap = 999
    local collisionMap = {}

    for i = 1, #starList do
        for j = i + 1, #starList do
            local s1, s2 = starList[i], starList[j]
            local dps1 = (s1.dps > 0) and s1.dps or (s1.maxHP * 0.01)
            local dps2 = (s2.dps > 0) and s2.dps or (s2.maxHP * 0.01)
            local eta1 = s1.currentHP / dps1
            local eta2 = s2.currentHP / dps2
            local gap = math.abs(eta1 - eta2)

            if gap <= 4.2 and eta1 <= 65 and eta2 <= 65 then
                local icon1 = GetMarkIcon(s1.raidMark, 16)
                local icon2 = GetMarkIcon(s2.raidMark, 16)
                if icon1 == "" then icon1 = "星" .. s1.index end
                if icon2 == "" then icon2 = "星" .. s2.index end

                local isNearBB = false
                if isBigBangCasting then
                    isNearBB = true
                elseif timeToNextBB > 0 then
                    local diff1 = eta1 - timeToNextBB
                    local diff2 = eta2 - timeToNextBB
                    if (diff1 >= -14.0 and diff1 <= 16.0) or (diff2 >= -14.0 and diff2 <= 16.0) then
                        isNearBB = true
                    end
                end

                if not collisionMap[s1.guid] or gap < collisionMap[s1.guid].gap then
                    collisionMap[s1.guid] = { otherMark = icon2, gap = gap, isEarlier = (eta1 <= eta2), nearBigBang = isNearBB }
                end
                if not collisionMap[s2.guid] or gap < collisionMap[s2.guid].gap then
                    collisionMap[s2.guid] = { otherMark = icon1, gap = gap, isEarlier = (eta2 < eta1), nearBigBang = isNearBB }
                end

                if gap < minCollisionGap then
                    minCollisionGap = gap
                    worstCollision = {
                        markEarlier = (eta1 <= eta2) and icon1 or icon2,
                        markLater = (eta1 <= eta2) and icon2 or icon1,
                        gap = gap,
                        nearBigBang = isNearBB,
                    }
                end
            end
        end
    end

    -- 5. 顶部主标题栏
    if isBigBangCasting then
        mainFrame.titleBg:SetColorTexture(0.7, 0.1, 0.05, 0.95)
        mainFrame.titleText:SetText(string.format(STC_r1("【大爆炸！进黑洞！】") .. " 剩余: " .. STC_y1("%.1fs"), bigBangLeft))
    elseif timeToNextBB > 0 and timeToNextBB <= 15.0 then
        mainFrame.titleBg:SetColorTexture(0.55, 0.35, 0.05, 0.92)
        mainFrame.titleText:SetText(string.format(STC_y1("【大爆炸临近】") .. " 约 " .. STC_r1("%.0fs") .. " 后施放 (准备进洞)", timeToNextBB))
    elseif timeToNextBB > 0 then
        mainFrame.titleBg:SetColorTexture(0.1, 0.18, 0.28, 0.8)
        mainFrame.titleText:SetText(string.format(STC_b1("观星者") .. " 下次大爆炸约: " .. STC_w1("%.0fs"), timeToNextBB))
    else
        mainFrame.titleBg:SetColorTexture(0.1, 0.18, 0.28, 0.8)
        mainFrame.titleText:SetText(STC_b1("观星者") .. " 坍缩星监控")
    end

    -- 5.5 第 2 行：专属战术警报栏
    local alertMsg = nil
    if worstCollision then
        local prefix = worstCollision.nearBigBang and STC_o1("【大爆炸连爆】") or STC_o1("【双星连爆】")
        alertMsg = prefix .. string.format("%s 与 %s 仅差 %.1fs! ", worstCollision.markEarlier, worstCollision.markLater, worstCollision.gap) .. STC_y1("慢星停手·错开")
    end

    local isAlertShown = (alertMsg ~= nil and mainFrame.alertBar ~= nil)
    if isAlertShown then
        mainFrame.alertBar:Show()
        mainFrame.alertBar.text:SetText(alertMsg)
    elseif mainFrame.alertBar then
        mainFrame.alertBar:Hide()
    end

    -- 动态自适应血条起始 Y 坐标与窗口总高度
    local startY = isAlertShown and -54 or -30
    local targetHeight = isAlertShown and 190 or 166
    if mainFrame:GetHeight() ~= targetHeight then
        mainFrame:SetHeight(targetHeight)
    end
    for i = 1, 4 do
        if bars[i] then
            bars[i]:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, startY - (i - 1) * 32)
        end
    end

    -- 6. 动态感知全场活跃 DoT 数量并自适应主窗口宽度
    local maxActiveDots = 0
    for i = 1, math.min(4, #starList) do
        local star = starList[i]
        local activeDotCount = 0
        if star.dots then
            for _, dot in pairs(star.dots) do
                if dot.expTime and dot.expTime > now then
                    activeDotCount = activeDotCount + 1
                end
            end
        end
        if activeDotCount > maxActiveDots then
            maxActiveDots = activeDotCount
        end
    end
    maxActiveDots = math.min(3, maxActiveDots)

    local targetWidth = 246
    if maxActiveDots == 1 then
        targetWidth = 272
    elseif maxActiveDots == 2 then
        targetWidth = 295
    elseif maxActiveDots >= 3 then
        targetWidth = 318
    end

    if isAlertShown then
        targetWidth = math.max(targetWidth, 318)
    end

    if mainFrame:GetWidth() ~= targetWidth then
        mainFrame:SetWidth(targetWidth)
    end

    -- 7. 逐条渲染
    for i = 1, 4 do
        local bar = bars[i]
        local star = starList[i]

        if star and bar then
            bar.starData = star
            bar:Show()
            bar.sb:SetMinMaxValues(0, star.maxHP or 75600)
            bar.sb:SetValue(star.currentHP)

            local displayMark = (star.raidMark and star.raidMark > 0) and star.raidMark or MARK_LIST[star.index or i] or 8
            bar.markIcon:SetTexture(MARK_TEXTURE_PREFIX .. displayMark)
            bar.markIcon:Show()

            local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
            bar.label:SetText(string.format("%.1f%%", pct))

            local safetyLevel, statusText, r, g, b = EvaluateStarSafety(star, now, isBigBangCasting, bigBangLeft, timeToNextBB, collisionMap[star.guid])

            bar.sb:SetStatusBarColor(r, g, b)
            bar.timerText:SetText(statusText)

            if safetyLevel == "RED" then
                bar.glow:SetVertexColor(1, 0.2, 0)
                bar.glow:SetAlpha(0.9)

                if BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.soundAlert then
                    if (now - lastAlertSoundTime) > 3.5 then
                        lastAlertSoundTime = now
                        if PlaySound then
                            pcall(PlaySound, 8959, "Master")
                        elseif PlaySoundFile then
                            pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.ogg", "Master")
                        end
                    end
                end
            elseif safetyLevel == "YELLOW" then
                bar.glow:SetVertexColor(1, 0.8, 0)
                bar.glow:SetAlpha(0.3)
            else
                bar.glow:SetAlpha(0)
            end

            -- DoT 图标槽渲染
            local dotList = {}
            for _, dot in pairs(star.dots) do
                if dot.expTime and dot.expTime > now then
                    table.insert(dotList, dot)
                end
            end
            table.sort(dotList, function(a, b)
                if a.isMine ~= b.isMine then
                    return a.isMine
                end
                return a.expTime < b.expTime
            end)

            for d = 1, 3 do
                local dotF = bar.dotFrames[d]
                local dotData = dotList[d]
                if dotData and dotF then
                    dotF:Show()
                    dotF.icon:SetTexture(dotData.icon or "Interface\\Icons\\Spell_Nature_StarFall")

                    local remain = dotData.expTime - now
                    -- 避免每 0.15 秒重复调用 SetCooldown 引起转圈闪烁
                    if dotData.duration and dotData.duration > 0 then
                        local startTime = dotData.expTime - dotData.duration
                        if not dotF.lastExpTime or math.abs(dotF.lastExpTime - dotData.expTime) > 0.2 then
                            dotF.lastExpTime = dotData.expTime
                            dotF.cd:SetCooldown(startTime, dotData.duration)
                        end
                    end

                    if remain > 0 then
                        if remain < 3.0 then
                            dotF.cdText:SetText(STC_r1(string.format("%.1f", remain)))
                        else
                            dotF.cdText:SetText(STC_y1(string.format("%d", math.ceil(remain))))
                        end
                    else
                        dotF.cdText:SetText("")
                    end

                    if dotData.isMine then
                        dotF.border:Show()
                        dotF.border:SetVertexColor(1, 0.85, 0.2, 1)
                    else
                        dotF.border:Hide()
                    end
                elseif dotF then
                    dotF.lastExpTime = nil
                    dotF:Hide()
                end
            end
        elseif bar then
            bar.starData = nil
            bar:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- 8. 战斗与事件监听 (全事件捕获 + SPELL_SUMMON 秒出 + P2 判定)
--------------------------------------------------------------------------------
local function CheckP2Status(bossHP, bossMax)
    if isPhase2 then return end
    if bossHP and bossMax and bossMax > 0 and (bossHP / bossMax) <= PHASE2_HP_THRESHOLD then
        isPhase2 = true
        bigBangCastEnd = 0
        bigBangNextEstimate = 0
        wipe(activeStars)
        starCounter = 0
        DEFAULT_CHAT_FRAME:AddMessage(STC_g1("[BGLite 观星助手]") .. " 观星者血量 ≤ 20%，正式进入 P2 阶段！坍缩星消失，无大爆炸，全力击杀！")
        RefreshUI()
    end
end

local function OnCombatLogEvent(...)
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, param12, param13, param14, param15 = GetCombatLogArgs(...)

    local srcNpcID = GetNpcIDFromGUID(sourceGUID)
    local dstNpcID = GetNpcIDFromGUID(destGUID)

    -- 记录奥尔加隆 GUID，开怪自动唤醒面板
    if not algalonGUID then
        if dstNpcID == ALGALON_NPC_ID then
            algalonGUID = destGUID
            if bigBangNextEstimate == 0 then
                bigBangNextEstimate = GetTime() + BIGBANG_FIRST_PULL_DELAY
            end
            ShowMainUI()
        elseif srcNpcID == ALGALON_NPC_ID then
            algalonGUID = sourceGUID
            if bigBangNextEstimate == 0 then
                bigBangNextEstimate = GetTime() + BIGBANG_FIRST_PULL_DELAY
            end
            ShowMainUI()
        end
    end

    -- 1. 监控奥尔加隆大爆炸施法 (SpellID: 64584/64443)
    if subEvent == "SPELL_CAST_START" then
        local spellID = param12
        if spellID and BIG_BANG_SPELLS[spellID] and not isPhase2 then
            local now = GetTime()
            bigBangCastEnd = now + 8.0
            bigBangNextEstimate = now + BIGBANG_BASE_COOLDOWN
            ShowMainUI()
            RefreshUI()
        end
    end

    -- 2. 检查奥尔加隆血量是否触发 P2
    if destGUID and destGUID == algalonGUID and not isPhase2 then
        local hp = UnitHealth("boss1")
        local maxHP = UnitHealthMax("boss1")
        CheckP2Status(hp, maxHP)
    end

    if isPhase2 then return end

    -- 2.5 捕获坍缩星出生召唤 (SPELL_SUMMON) 或坍缩星作为施法者 (srcNpcID == STAR_NPC_ID) 的任何动作，第一时间秒上屏！
    if srcNpcID == STAR_NPC_ID and sourceGUID then
        local star = activeStars[sourceGUID] or RegisterStar(sourceGUID)
        ShowMainUI()
        -- 若坍缩星施放了黑洞爆炸 (64122 / 65108)，立即判定死亡
        if (subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_DAMAGE") and param12 and BLACK_HOLE_EXPLOSION_SPELLS[param12] then
            star.isDead = true
            star.currentHP = 0
            RefreshUI()
            return
        end
    end

    -- 3. 坍缩星精准伤害扣减与掉血跟踪 (作为目标 destGUID)
    if dstNpcID == STAR_NPC_ID and destGUID then
        local star = activeStars[destGUID] or RegisterStar(destGUID)
        ShowMainUI()

        local dmg = 0
        if subEvent == "SWING_DAMAGE" then
            dmg = param12 or 0
        elseif subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "ENVIRONMENTAL_DAMAGE" then
            dmg = param15 or param12 or 0
        end

        if dmg and type(dmg) == "number" and dmg > 0 then
            local now = GetTime()
            star.currentHP = math.max(0, star.currentHP - dmg)
            star.lastRealSync = now
            star.lastTick = now
            AddDamageHistory(star, dmg, now)
        end

        -- 4. 监控 DoT 施加与移除 (视角盲区兜底)
        if subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
            local spellID = param12
            local spellName = param13
            local info = (spellID and DOT_WHITELIST_BY_ID[spellID]) or DOT_WHITELIST_BY_NAME[spellName]
            if info then
                local now = GetTime()
                local isMine = (sourceGUID == UnitGUID("player"))
                star.dots[info.name] = {
                    name = info.name,
                    icon = info.icon,
                    duration = info.duration,
                    expTime = now + info.duration,
                    isMine = isMine,
                    class = info.class,
                }
            end
        elseif subEvent == "SPELL_AURA_REMOVED" then
            local spellName = param13
            if spellName and star.dots[spellName] then
                star.dots[spellName] = nil
            end
        end

        -- 5. 死亡清理
        if subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
            star.isDead = true
            star.currentHP = 0
            RefreshUI()
        end
    end
end

local function TryAutoMark(unit)
    if not unit or not CanSetMarks() then return end
    local guid = UnitGUID(unit)
    if not guid or UnitIsDead(unit) then return end

    local npcID = GetNpcIDFromGUID(guid)
    if npcID ~= STAR_NPC_ID then return end

    local star = activeStars[guid] or RegisterStar(guid, UnitHealthMax(unit))
    if not star or not star.raidMark or star.raidMark <= 0 then return end

    local now = GetTime()
    if (now - (star.lastMarkTime or 0)) < 0.6 then return end
    star.lastMarkTime = now

    local currentMark = GetRaidTargetIndex(unit)
    if currentMark ~= star.raidMark then
        SetRaidTarget(unit, star.raidMark)
    end
end

local function SyncStarFromUnit(unit)
    if not unit or isPhase2 then return end
    local guid = UnitGUID(unit)
    if not guid or GetNpcIDFromGUID(guid) ~= STAR_NPC_ID then return end

    if UnitIsDead(unit) then
        if activeStars[guid] then
            activeStars[guid].isDead = true
            activeStars[guid].currentHP = 0
        end
        return
    end

    local now = GetTime()
    local maxHP = UnitHealthMax(unit)
    local curHP = UnitHealth(unit)
    local star = RegisterStar(guid, maxHP)

    if maxHP and maxHP > 0 then
        star.maxHP = maxHP
    end
    -- 严防姓名板刚载入瞬间 UnitHealth 返回 0 将满血星误判为 0 血隐藏
    if curHP and curHP > 0 then
        local isFirstSync = (star.lastRealSync == 0)
        local prevHP = star.currentHP
        local syncInterval = now - (star.lastRealSync or 0)

        star.currentHP = curHP
        star.lastRealSync = now
        star.lastTick = now

        -- 首次同步（此前仅为预估基准血量）或脱离视线过久（>3s）时不计入瞬时伤害滑动窗口，严防虚假掉血尖峰导致误报警
        if not isFirstSync and prevHP and prevHP > curHP then
            local dmgDiff = prevHP - curHP
            if syncInterval <= 3.0 then
                AddDamageHistory(star, dmgDiff, now)
            else
                star.dps = math.max(star.maxHP * 0.01, dmgDiff / syncInterval)
            end
        end
    end

    local rt = GetRaidTargetIndex(unit)
    if rt and rt >= 1 and rt <= 8 then
        star.raidMark = rt
    end

    ScanNameplateDots(star, unit)
    TryAutoMark(unit)
    ShowMainUI()
end

local function OnEvent(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and GetNpcIDFromGUID(guid) == STAR_NPC_ID and not isPhase2 then
            SyncStarFromUnit(unit)
            if activeStars[guid] then
                activeStars[guid].nameplateUnit = unit
            end
            RefreshUI()
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        SyncStarFromUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        SyncStarFromUnit("target")
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            activeStars[guid].nameplateUnit = nil
        end
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        local unit = ...
        if not unit then return end
        -- 监听 Boss 血量，P2 判定
        if (unit == "boss1" or unit == "target" or unit == "focus") and not isPhase2 then
            local guid = UnitGUID(unit)
            if guid and GetNpcIDFromGUID(guid) == ALGALON_NPC_ID then
                algalonGUID = guid
                CheckP2Status(UnitHealth(unit), UnitHealthMax(unit))
            end
        end

        -- 坍缩星血量实时校准 (严禁 hp == 0 覆盖，死亡由 UnitIsDead / UNIT_DIED 判定)
        local guid = UnitGUID(unit)
        if guid and GetNpcIDFromGUID(guid) == STAR_NPC_ID and not isPhase2 then
            SyncStarFromUnit(unit)
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if not unit then return end
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            ScanNameplateDots(activeStars[guid], unit)
        end
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        local isAlgalon = (encounterID == 757 or encounterID == 1130) or
                          (encounterName and (string.find(encounterName, "奥尔加隆") or string.find(encounterName, "艾爾加隆") or string.find(encounterName, "Algalon")))
        if isAlgalon then
            if isTesting then
                isTesting = false
                if testTicker then testTicker:Cancel(); testTicker = nil end
                wipe(activeStars)
            end
            encounterStartTime = GetTime()
            bigBangNextEstimate = encounterStartTime + BIGBANG_FIRST_PULL_DELAY
            bigBangCastEnd = 0
            isPhase2 = false
            algalonGUID = nil
            wipe(activeStars)
            starCounter = 0
            ShowMainUI()
        elseif not isTesting then
            if mainFrame and mainFrame:IsShown() then
                mainFrame:Hide()
            end
        end
    elseif event == "ENCOUNTER_END" then
        if not isTesting then
            wipe(activeStars)
            starCounter = 0
            bigBangCastEnd = 0
            bigBangNextEstimate = 0
            isPhase2 = false
            algalonGUID = nil
            if mainFrame then mainFrame:Hide() end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        AlgalonStar.UpdateEventRegistration()
    end
end

--------------------------------------------------------------------------------
-- 9. 事件截断与动态开关控制 (核心性能防线)
--------------------------------------------------------------------------------
function AlgalonStar.RegisterCombatEvents()
    if isCombatRegistered then return end
    isCombatRegistered = true
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")

    -- 开启 0.15 秒节流刷新定时器
    local elapsedTotal = 0
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 0.15 then
            elapsedTotal = 0
            RefreshUI()
        end
    end)
end

function AlgalonStar.UnregisterCombatEvents()
    if not isCombatRegistered then return end
    isCombatRegistered = false
    eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_MAXHEALTH")
    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("ENCOUNTER_START")
    eventFrame:UnregisterEvent("ENCOUNTER_END")
    eventFrame:SetScript("OnUpdate", nil)
end

function AlgalonStar.UpdateEventRegistration()
    local enabled = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.enabled
    if enabled == nil then enabled = false end

    if not enabled then
        AlgalonStar.UnregisterCombatEvents()
        if testTicker then testTicker:Cancel(); testTicker = nil end
        isTesting = false
        wipe(activeStars)
        starCounter = 0
        if mainFrame then mainFrame:Hide() end
        return
    end

    if isTesting or AlgalonStar.IsInUlduar() then
        AlgalonStar.RegisterCombatEvents()
    else
        AlgalonStar.UnregisterCombatEvents()
        wipe(activeStars)
        starCounter = 0
        if mainFrame then mainFrame:Hide() end
    end
end

function AlgalonStar.SetEnabled(enabled)
    BiaoGe = BiaoGe or {}
    BiaoGe.AlgalonStar = BiaoGe.AlgalonStar or {}
    BiaoGe.AlgalonStar.enabled = enabled
    AlgalonStar.UpdateEventRegistration()

    if enabled then
        DEFAULT_CHAT_FRAME:AddMessage(STC_g1("[BGLite 观星助手]") .. " 模块已【开启】(进入奥杜尔自动激活，支持 /star test 主城测试)。")
    else
        DEFAULT_CHAT_FRAME:AddMessage(STC_r1("[BGLite 观星助手]") .. " 模块已【关闭】，已完全截断事件监听与后台计算，零性能开销。")
    end
end

--------------------------------------------------------------------------------
-- 10. 主城模拟测试沙盘 (/star test - 完美展示绿/黄/红全状态)
--------------------------------------------------------------------------------
function AlgalonStar.ToggleTestMode(subMode)
    if isTesting and not subMode then
        isTesting = false
        print(STC_r1("[BGLite 观星助手]") .. " 模拟测试沙盘已【关闭】。")
        if testTicker then testTicker:Cancel(); testTicker = nil end
        wipe(activeStars)
        starCounter = 0
        bigBangCastEnd = 0
        bigBangNextEstimate = 0
        isPhase2 = false
        if mainFrame then mainFrame:Hide() end
        return
    end

    isTesting = true
    CreateMainUI()
    if testTicker then testTicker:Cancel(); testTicker = nil end
    wipe(activeStars)
    mainFrame:Show()

    if subMode == "p2" then
        isPhase2 = true
        bigBangCastEnd = 0
        bigBangNextEstimate = 0
        print(STC_g1("[BGLite 观星助手]") .. " 模拟测试：【P2 阶段演示】(Boss ≤ 20%，坍缩星消失，全力 RUSH！)")
        RefreshUI()
        return
    end

    isPhase2 = false
    local now = GetTime()
    bigBangNextEstimate = now + 32.0

    local mockData = {}
    if subMode == "double" or subMode == "wipe" then
        print(STC_r1("[BGLite 观星助手]") .. " 模拟测试：【大爆炸前后双星连炸灭团高危场景】！")
        mockData = {
            { hpPct = 0.50, dps = 1021, mark = 8, dots = { { name = "月火术", dur = 12, remain = 8.5, isMine = true } } },
            { hpPct = 0.28, dps = 1320, mark = 7, dots = { { name = "暗言术：痛", dur = 18, remain = 14.0, isMine = true } } },
            { hpPct = 0.48, dps = 1008, mark = 6, dots = { { name = "吸血鬼之触", dur = 15, remain = 9.4, isMine = true } } },
            { hpPct = 0.85, dps = 600,  mark = 4, dots = { { name = "腐蚀术", dur = 18, remain = 16.0, isMine = false } } },
        }
    else
        print(STC_g1("[BGLite 观星助手]") .. " 模拟测试沙盘已【启动】！输入 /star test double 测双星连炸灭团，/star test p2 测P2。")
        mockData = {
            { hpPct = 0.50, dps = 1080, mark = 8, dots = { { name = "月火术", dur = 12, remain = 8.5, isMine = true } } },
            { hpPct = 0.28, dps = 1320, mark = 7, dots = { { name = "暗言术：痛", dur = 18, remain = 14.0, isMine = true } } },
            { hpPct = 0.45, dps = 756,  mark = 6, dots = {} },
            { hpPct = 0.53, dps = 1300, mark = 4, dots = {} },
        }
    end

    for i, item in ipairs(mockData) do
        local guid = "TEST-COLLAPSING-STAR-" .. i
        local maxHP = 75600
        local star = {
            guid = guid,
            index = i,
            raidMark = item.mark,
            maxHP = maxHP,
            currentHP = maxHP * item.hpPct,
            dps = item.dps,
            dmgHistory = {},
            dots = {},
            lastTick = now,
            lastRealSync = now,
            nameplateUnit = nil,
            isDead = false,
        }

        for _, d in ipairs(item.dots) do
            local info = DOT_WHITELIST_BY_NAME[d.name] or { name = d.name, duration = d.dur, icon = "Interface\\Icons\\Spell_Nature_StarFall" }
            star.dots[d.name] = {
                name = d.name,
                icon = info.icon or "Interface\\Icons\\Spell_Nature_StarFall",
                duration = d.dur,
                expTime = now + d.remain,
                isMine = d.isMine,
            }
        end
        activeStars[guid] = star
    end

    RefreshUI()

    local loopCounter = 0
    testTicker = C_Timer.NewTicker(0.2, function()
        loopCounter = loopCounter + 1
        local tickNow = GetTime()

        if loopCounter % 225 == 160 then
            bigBangCastEnd = tickNow + 8.0
            bigBangNextEstimate = tickNow + 8.0 + 45.0
        end

        for _, star in pairs(activeStars) do
            star.currentHP = math.max(0, star.currentHP - (star.dps * 0.2))
            if star.currentHP <= 0 then
                star.currentHP = star.maxHP
                for _, dot in pairs(star.dots) do
                    dot.expTime = tickNow + dot.duration
                end
            end
        end
        RefreshUI()
    end)
end

--------------------------------------------------------------------------------
-- 11. 挂载到团队工具底部 (站位图开关右侧)
--------------------------------------------------------------------------------
function AlgalonStar.CreateToolControls(entry, anchorFrame)
    if not entry or entry.starControlsCreated then return end
    entry.starControlsCreated = true

    local cbStar = CreateFrame("CheckButton", "BG_AlgalonStarToolCheckButton", entry, "UICheckButtonTemplate")
    cbStar:SetSize(20, 20)
    cbStar:SetPoint("LEFT", anchorFrame.text or anchorFrame, "RIGHT", 18, 0)
    cbStar.text = cbStar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbStar.text:SetPoint("LEFT", cbStar, "RIGHT", 4, 0)
    cbStar.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    cbStar.text:SetText(STC_b1("观星修星助手"))
    cbStar:SetHitRectInsets(-2, -cbStar.text:GetStringWidth() - 4, -2, -2)

    cbStar:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        AlgalonStar.SetEnabled(checked)
        if BG and BG.PlaySound then BG.PlaySound(1) end
    end)
    cbStar:SetScript("OnShow", function(self)
        local enabled = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.enabled
        if enabled == nil then enabled = false end
        self:SetChecked(enabled)
    end)
    cbStar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_b1("观星修星助手 (奥尔加隆)") .. " - 核心开关", 1, 1, 1)
        GameTooltip:AddLine("勾选开启奥杜尔观星者坍缩星专属血量监控与大爆炸冲突预警 (默认关闭，需手动勾选)。", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("核心预测与特性：", 1, 0.82, 0)
        GameTooltip:AddLine("- " .. STC_g1("【绿色·进洞免伤】") .. " 预测大爆炸读条期间全团在洞内0伤害引爆 (极佳)", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- " .. STC_y1("【黄色·注意】") .. " 预测提前留洞引爆，或出洞后引爆 (需关注团血/备用洞)", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- " .. STC_r1("【红色·危险】") .. " 预测在大爆炸前夕撞车、出洞瞬间连爆或双星连炸", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- 鸟德/暗牧核心修星 DoT 倒计时与专属图标", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- 自动识别 P2 阶段 (≤20% HP) 坍缩星消失清空", 0.85, 0.85, 0.85)
        GameTooltip:AddLine(STC_g1("【性能截断】") .. " 关闭时完全注销战斗日志与事件监听，0 CPU 占用！", 0.2, 1, 0.4, true)
        GameTooltip:Show()
    end)
    cbStar:SetScript("OnLeave", GameTooltip_Hide)

    -- 测试沙盘按钮
    local btnTest = BG.CreateButton(entry)
    btnTest:SetSize(84, 24)
    btnTest:SetPoint("LEFT", cbStar.text, "RIGHT", 12, 0)
    btnTest:SetText(STC_g1("测试沙盘"))
    btnTest:SetScript("OnClick", function()
        AlgalonStar.ToggleTestMode()
        if BG and BG.PlaySound then BG.PlaySound(1) end
    end)
    btnTest:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_g1("观星修星模拟沙盘 (/star test)"), 1, 1, 1)
        GameTooltip:AddLine("无需进入奥杜尔副本，在主城即可模拟 4 颗坍缩星平滑掉血、DoT 倒计时、动态排序及红/黄/绿安全预测！", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("方便修星人员与团长调试窗口位置、字体及警报效果。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnTest:SetScript("OnLeave", GameTooltip_Hide)

    -- 呼出/收起窗口按钮
    local btnToggle = BG.CreateButton(entry)
    btnToggle:SetSize(84, 24)
    btnToggle:SetPoint("LEFT", btnTest, "RIGHT", 6, 0)
    btnToggle:SetText(STC_w1("呼出面板"))
    btnToggle:SetScript("OnClick", function()
        CreateMainUI()
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
            RefreshUI()
        end
        if BG and BG.PlaySound then BG.PlaySound(1) end
    end)
    btnToggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_w1("呼出/收起监控面板"), 1, 1, 1)
        GameTooltip:AddLine("手动展开或隐藏观星修星监控主框体，可用于在脱战时预先调整屏幕位置。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnToggle:SetScript("OnLeave", GameTooltip_Hide)

    -- 辅助说明文字
    local tipText = entry:CreateFontString(nil, "OVERLAY")
    tipText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    tipText:SetPoint("LEFT", btnToggle, "RIGHT", 10, 0)
    tipText:SetText(STC_dis("(红/黄/绿安全预测 / 核心DoT倒计时 / P2自动识别)"))
end

--------------------------------------------------------------------------------
-- 12. 初始化与 Slash 指令注册
--------------------------------------------------------------------------------
function ns.InitAlgalonStarDB()
    BiaoGe = BiaoGe or {}
    BiaoGe.AlgalonStar = BiaoGe.AlgalonStar or {}
    local db = BiaoGe.AlgalonStar

    if not db.v261013_init then
        db.v261013_init = true
        db.enabled = false
    end

    if db.enabled == nil then db.enabled = false end
    if db.autoMark == nil then db.autoMark = true end
    if db.soundAlert == nil then db.soundAlert = true end
    if db.locked == nil then db.locked = false end
    if db.point == nil then db.point = { "CENTER", "UIParent", "CENTER", 340, 50 } end
end

function ns.InitAlgalonStarModule()
    ns.InitAlgalonStarDB()
    CreateMainUI()

    eventFrame:SetScript("OnEvent", OnEvent)
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    AlgalonStar.UpdateEventRegistration()
end

SLASH_ALGALONSTAR1 = "/star"
SLASH_ALGALONSTAR2 = "/bgstar"
SLASH_ALGALONSTAR3 = "/algalon"
SlashCmdList["ALGALONSTAR"] = function(msg)
    msg = msg and msg:lower():trim() or ""
    if msg == "test" then
        AlgalonStar.ToggleTestMode()
    elseif msg == "test double" or msg == "test wipe" or msg == "double" then
        AlgalonStar.ToggleTestMode("double")
    elseif msg == "test p2" or msg == "p2" then
        AlgalonStar.ToggleTestMode("p2")
    elseif msg == "lock" then
        BiaoGe = BiaoGe or {}
        BiaoGe.AlgalonStar = BiaoGe.AlgalonStar or {}
        BiaoGe.AlgalonStar.locked = not BiaoGe.AlgalonStar.locked
        DEFAULT_CHAT_FRAME:AddMessage(STC_b1("[BGLite 观星助手]") .. (BiaoGe.AlgalonStar.locked and " 窗口已锁定。" or " 窗口已解锁。"))
    elseif msg == "on" then
        AlgalonStar.SetEnabled(true)
    elseif msg == "off" then
        AlgalonStar.SetEnabled(false)
    else
        CreateMainUI()
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
            RefreshUI()
        end
        DEFAULT_CHAT_FRAME:AddMessage(STC_b1("[BGLite 观星助手]") .. " 常用指令: /star test (测试常规状态), /star test double (测试双星连炸灭团), /star test p2 (测试P2), /star lock (锁定), /star on/off (开关)")
    end
end