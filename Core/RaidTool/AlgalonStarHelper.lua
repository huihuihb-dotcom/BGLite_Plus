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
local STAR_NPC_ID = 32955        -- 塌缩星 (Collapsing Star)
local ALGALON_NPC_ID = 32871     -- 观察者奥尔加隆 (Algalon the Observer)

-- 大爆炸技能 ID (25人: 64584, 10人: 64443)
local BIG_BANG_SPELLS = {
    [64584] = true,
    [64443] = true,
}

local BIGBANG_BASE_COOLDOWN = 90.5     -- 每次施法大爆炸间隔严格为 90.5 秒 (对齐官方 DBM: timerNextBigBang = 90.5s)
local BIGBANG_FIRST_PULL_DELAY = 98.0  -- 战斗开始到首次大爆炸约 98.0 秒 (对齐 DBM: 8s 开怪剧情台词 + 90s)
local PHASE2_HP_THRESHOLD = 0.20       -- 奥尔加隆血量低于 20% 进入 P2 (转阶段)

-- 团队标记固定映射：1号骷髅(8), 2号红叉(7), 3号方块(6), 4号三角(4)
local MARK_LIST = { 8, 7, 6, 4 }
local MARK_NAMES = {
    [8] = "骷髅",
    [7] = "红叉",
    [6] = "方块",
    [4] = "三角",
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
-- 2. 状态变量与数据结构
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

local eventFrame = CreateFrame("Frame", "BG_AlgalonStarEventFrame", UIParent)
AlgalonStar.eventFrame = eventFrame

--------------------------------------------------------------------------------
-- 3. 辅助解析与权限函数
--------------------------------------------------------------------------------
local function GetNpcIDFromGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
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
    elseif UnitAura then
        local name, _, icon, count, _, duration, expirationTime, source, _, _, spellId = UnitAura(unit, index, "HARMFUL")
        return name, icon, count, duration, expirationTime, source, spellId
    end
    return nil
end

function AlgalonStar.IsInUlduar()
    if isTesting then return true end
    local zone = GetRealZoneText() or GetZoneText() or ""
    local subZone = GetSubZoneText() or ""
    if zone:find("奥杜尔") or zone:find("Ulduar") or subZone:find("天界") or subZone:find("天穹") or subZone:find("Celestial") then
        return true
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and (mapID == 125 or (mapID >= 529 and mapID <= 534)) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 4. 注册与数据更新核心算法 (自适应与平滑掉血)
--------------------------------------------------------------------------------
local function RegisterStar(guid, maxHP)
    if not activeStars[guid] then
        starCounter = (starCounter % 4) + 1
        local assignIndex = starCounter
        local mark = MARK_LIST[assignIndex] or 0

        -- 默认基准血量：时光服 25 人约 7.56w，10 人约 3.78w。一旦姓名板出现立即用真实 maxHP 校准
        local defaultMax = maxHP
        if not defaultMax or defaultMax <= 0 then
            defaultMax = (IsInRaid() and GetNumGroupMembers() > 10) and 75600 or 37800
        end

        activeStars[guid] = {
            guid = guid,
            index = assignIndex,
            raidMark = mark,
            currentHP = defaultMax,
            maxHP = defaultMax,
            dps = defaultMax * 0.01,  -- 刚出生默认自残速率 1%/s
            dmgHistory = {},
            dots = {},
            lastTick = GetTime(),
            nameplateUnit = nil,
            lastMarkTime = 0,
            isDead = false,
        }
    else
        if maxHP and maxHP > 0 then
            activeStars[guid].maxHP = maxHP
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
    if timeSpan > 0.4 and totalDmg > 0 then
        star.dps = totalDmg / timeSpan
    else
        star.dps = (star.dps > 0) and star.dps or (star.maxHP * 0.01) -- 兜底自残1%/s
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

--------------------------------------------------------------------------------
-- 5. 核心安全预测模型 (红 / 黄 / 绿 深度判定算法)
--------------------------------------------------------------------------------
--[[
  【安全模型法则】
  1. 绿色 (完美安全 / 最理想)：
     - 大爆炸之后几秒（炸完出洞后 2s ~ 15s）才自爆的星！全团血线已抬满、减伤已就绪，最稳！
     - 或者在大爆炸读条中（已进洞）在暮光领域免伤期提前炸掉。
  2. 黄色 (需注意 / 提前留洞)：
     - 提前在大爆炸前 5s~30s 引爆（虽能备洞，但团队会吃一次自爆AOE，需治疗覆盖）。
     - 或者掉血极慢（大爆炸后 >15s 才爆），留洞节奏较晚。
  3. 红色 (不安全 / 高度危险 / 撞车)：
     - 大爆炸前夕或刚出洞瞬间爆炸（距大爆炸结束 -4s ~ +1.5s）：致命重叠减员！
     - 濒死猝死自爆（ETA <= 5s 或 HP <= 15% 且非进洞期）：随时乱炸。
     - 场上两颗星 ETA 相差 <= 3.5s：双星撞车连炸团灭！
]]
local function EvaluateStarSafety(star, now, isBigBangCasting, bigBangLeft, timeToNextBB, collisionInfo)
    local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
    local dps = (star.dps > 0) and star.dps or (star.maxHP * 0.01)
    local eta = star.currentHP / dps

    -- 【最高优先级：双星连炸致命灭团点 (Double Star Collision)】
    -- 无论大爆炸处于何种阶段，两颗星相隔 <= 4.2s 连续爆炸，瞬间 40k+ 伤害必灭团！
    -- 若还发生在大爆炸前后（大爆炸前 14s 或大爆炸后出洞 15s 内），更是 100% 团灭大祸！
    -- 强制标红报警，绝不允许被“大爆炸后安全”掩盖，并给出精确的“打爆拉开 / 停手停DoT”指令！
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
        -- A1. 刚进洞免伤期内炸 (自爆时间在出洞前 1.5s 以前)：全团在洞内免疫伤害！【真正绿色·进洞免伤】
        if eta >= 1.5 and eta <= (bigBangLeft - 1.2) then
            return "GREEN", string.format("进洞免伤 (洞内%.1fs)", eta), 0.1, 0.85, 0.3
        end

        -- A2. 出洞瞬间炸 (|eta - bigBangLeft| <= 1.5s)：刚出洞残血吃自爆，大团灭点！
        if math.abs(eta - bigBangLeft) <= 1.5 then
            return "RED", string.format("出洞瞬间炸! (危险%.1fs)", eta), 1.0, 0.2, 0.0
        end

        -- A3. 大爆炸炸完、全团出洞后才炸：【出洞炸，黄色警示】
        if eta > (bigBangLeft + 1.5) and eta <= (bigBangLeft + 20.0) then
            local delay = eta - bigBangLeft
            return "YELLOW", string.format("出洞炸 (出洞+%.1fs)", delay), 0.95, 0.8, 0.1
        end

        -- A4. 进洞前不到 1.5 秒急促爆炸：
        if eta < 1.5 then
            return "RED", string.format("进洞前猝死! (%.1fs)", eta), 0.95, 0.1, 0.1
        end

        -- A5. 炸后延后很久 (>20s) 才炸：掉血慢
        return "YELLOW", string.format("延后较慢 (出洞+%.0fs)", eta - bigBangLeft), 0.2, 0.7, 0.9
    end

    -- B. 非大爆炸读条期间 (正常战斗阶段，依据下次大爆炸倒计时预测)
    local diff = (timeToNextBB > 0) and (eta - timeToNextBB) or nil

    -- B1. 与下次大爆炸前夕撞车 (大爆炸前 4 秒至大爆炸开始后 1.5 秒内)：
    if diff and (diff >= -4.0 and diff < 1.5) then
        if eta <= 5.0 or pct <= 15 then
            return "RED", string.format("撞车濒死! (剩%.1fs·差%.1fs)", eta, math.abs(diff)), 1.0, 0.2, 0.0
        else
            return "RED", string.format("大爆炸撞车危险! (差%.1fs)", math.abs(diff)), 1.0, 0.3, 0.0
        end
    end
    -- 出洞瞬间撞车 (大爆炸读条 8s 结束前后 1.5s)：
    if diff and (diff >= 6.5 and diff <= 9.5) then
        return "RED", string.format("出洞瞬间撞车! (危险%.1fs)", math.abs(diff - 8.0)), 1.0, 0.2, 0.0
    end

    -- B2. 【真正完美免伤：进洞免伤】 (自爆正好落在大爆炸 8 秒读条全团在洞内期间，diff 在 +1.5s ~ +6.5s)
    if diff and (diff >= 1.5 and diff < 6.5) then
        return "GREEN", string.format("进洞免伤 (洞内%.1fs)", diff - 1.5), 0.1, 0.85, 0.3
    end

    -- B3. 提前引爆留洞 (在大爆炸前 5s ~ 40s 爆炸)：
    if diff and (diff < -4.0 and eta >= 5.0 and eta <= 40.0) then
        local lead = -diff
        return "YELLOW", string.format("提前留洞 (提前%.0fs爆)", lead), 0.95, 0.8, 0.1
    end

    -- B4. 濒死自爆预警 (非撞车期，自身血量/时间极度危急)：
    if eta <= 5.0 or pct <= 15 then
        if diff and diff < -4.0 then
            return "YELLOW", string.format("即将留洞 (剩%.1fs·提前%.0fs)", eta, -diff), 0.95, 0.8, 0.1
        else
            return "RED", string.format("即将自爆! (剩%.1fs)", eta), 0.95, 0.1, 0.1
        end
    end

    -- B5. 【出洞炸】 (大爆炸彻底炸完、全团出洞后爆炸，diff 在 +9.5s ~ +28.0s)：黄色警示！
    if diff and (diff > 9.5 and diff <= 28.0) then
        local delay = diff - 8.0
        return "YELLOW", string.format("出洞炸 (大爆炸后%.0fs)", delay), 0.95, 0.8, 0.1
    end

    -- B6. 掉血缓慢 / 延后过久 (不会猝死，但留洞慢)
    if eta > 60.0 or (diff and diff > 28.0) then
        return "YELLOW", string.format("掉血平稳 (%.0fs后)", eta), 0.2, 0.7, 0.9
    end

    return "YELLOW", string.format("自爆: %.1fs", eta), 0.9, 0.75, 0.2
end

--------------------------------------------------------------------------------
-- 6. UI 界面构建 (StatusBar + DoT 图标槽 + 大爆炸预警)
--------------------------------------------------------------------------------
local mainFrame = nil
local bars = {}

local function CreateMainUI()
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

    mainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relTo, relPoint, x, y = self:GetPoint()
        if not BiaoGe.AlgalonStar then BiaoGe.AlgalonStar = {} end
        BiaoGe.AlgalonStar.point = { point, "UIParent", relPoint, math.floor(x), math.floor(y) }
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
    titleText:SetText(STC_b1("观星者") .. " 塌缩星监控")
    mainFrame.titleText = titleText

    -- 关闭按钮
    local btnClose = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    btnClose:SetSize(20, 20)
    btnClose:SetPoint("RIGHT", titleBg, "RIGHT", -2, 0)
    btnClose:SetScript("OnClick", function()
        mainFrame:Hide()
        BG.PlaySound(1)
    end)

    -- 专属战术警报栏 (第 2 行：用于双星连炸等重大突发危机，暗夜黑红底+金橙高光微边，平时自动隐藏零占用)
    local alertBar = CreateFrame("Frame", nil, mainFrame)
    alertBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -28)
    alertBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -4, -28)
    alertBar:SetHeight(22)

    -- 暗夜黑红底色（告别刺目廉价大鲜红，兼顾高级感与危机感）
    local alertBg = alertBar:CreateTexture(nil, "BACKGROUND")
    alertBg:SetAllPoints()
    alertBg:SetColorTexture(0.18, 0.04, 0.05, 0.92)
    alertBar.bg = alertBg

    -- 上下 1px 金橙发光细边，打造精致 HUD 战术条质感
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
    alertText:SetWordWrap(false) -- 彻底杜绝文字折行、下坠穿模
    alertBar.text = alertText
    alertBar:Hide()
    mainFrame.alertBar = alertBar

    -- 4 根血条构建 (加大宽度至 230 以清晰容纳预测状态文字，杜绝文字压盖)
    for i = 1, 4 do
        local bar = CreateFrame("Button", "BG_AlgalonStarBar_" .. i, mainFrame, "SecureActionButtonTemplate")
        bar:SetSize(230, 26)
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -32 - (i - 1) * 32)
        bar:RegisterForClicks("AnyUp")
        bar:SetAttribute("type", "macro")
        bar:SetAttribute("macrotext", "/targetexact 塌缩星")

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

        -- 标记图标 (挂载在 sb 上且设为 OVERLAY，确保永远置顶浮在颜色进度条最上方)
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

        -- 边框高亮材质 (危险撞车时闪烁)
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
            local markName = MARK_NAMES[mark] or "塌缩星"
            GameTooltip:AddLine(GetMarkIcon(mark, 16) .. " 塌缩星 (" .. markName .. ")", 1, 1, 1)
            local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
            GameTooltip:AddLine(string.format("血量: %d / %d (%.1f%%)", star.currentHP or 0, star.maxHP or 75600, pct), 0.85, 0.85, 0.85)
            if star.dps and star.dps > 0 then
                GameTooltip:AddLine(string.format("掉血速率: %.0f/s", star.dps), 0.85, 0.85, 0.85)
            end
            GameTooltip:AddLine("左键点击: 选定目标", 0.2, 1, 0.4)
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

            -- 边框 (玩家自己的 DoT 显示高亮金边)
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
            cd.noCooldownCount = true -- 彻底阻止 OmniCC / tullaCC 等外部插件注入倒计时数字
            dotF.cd = cd

            -- 专属倒计时文本 (居中显示，彻底解决与暴雪原生/OmniCC双层文字重叠问题)
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

local function ShowMainUI()
    CreateMainUI()
    if mainFrame and not mainFrame:IsShown() then
        mainFrame:Show()
        RefreshUI()
    end
end

--------------------------------------------------------------------------------
-- 7. UI 实时刷新与渲染逻辑
--------------------------------------------------------------------------------
local function RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local now = GetTime()

    -- 1. P2 阶段优先展示
    if isPhase2 then
        mainFrame.titleBg:SetColorTexture(0.1, 0.5, 0.2, 0.95)
        mainFrame.titleText:SetText(STC_g1("【P2 阶段】") .. " 塌缩星消失，无大爆炸 ─ 全力 RUSH Boss！")
        for i = 1, 4 do
            if bars[i] then bars[i]:Hide() end
        end
        return
    end

    -- 2. 提取活星并按血量排序
    local starList = {}
    for _, star in pairs(activeStars) do
        if not star.isDead and star.currentHP > 0 then
            table.insert(starList, star)
        end
    end

    table.sort(starList, function(a, b)
        return a.currentHP < b.currentHP
    end)

    -- 3. 大爆炸读条与预警倒计时
    local bigBangLeft = math.max(0, bigBangCastEnd - now)
    local isBigBangCasting = (bigBangLeft > 0)
    local timeToNextBB = (bigBangNextEstimate > 0) and math.max(0, bigBangNextEstimate - now) or 0

    -- 4. 全局双星连炸 (Double Star Collision) 检测
    -- 灭团死穴：大爆炸前夕或大爆炸后刚出洞，两颗星间隔 <= 4.2 秒连炸，瞬间 40,000+ 伤害直接灭团！
    local worstCollision = nil
    local minCollisionGap = 999
    local collisionMap = {} -- [guid] = { otherMark = markName, gap = gap, isEarlier = bool, nearBigBang = bool }

    for i = 1, #starList do
        for j = i + 1, #starList do
            local s1, s2 = starList[i], starList[j]
            local dps1 = (s1.dps > 0) and s1.dps or (s1.maxHP * 0.01)
            local dps2 = (s2.dps > 0) and s2.dps or (s2.maxHP * 0.01)
            local eta1 = s1.currentHP / dps1
            local eta2 = s2.currentHP / dps2
            local gap = math.abs(eta1 - eta2)

            -- 只要两颗星都在 65 秒内爆炸，且时间差 <= 4.2 秒，构成致命双星连炸！
            if gap <= 4.2 and eta1 <= 65 and eta2 <= 65 then
                local icon1 = GetMarkIcon(s1.raidMark, 16)
                local icon2 = GetMarkIcon(s2.raidMark, 16)
                if icon1 == "" then icon1 = "星" .. s1.index end
                if icon2 == "" then icon2 = "星" .. s2.index end

                -- 是否紧贴大爆炸（大爆炸前 14s 内或大爆炸后出洞 15s 内发生双爆，绝对团灭死穴！）
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

    -- 5. 顶部主标题栏：专职展示奥尔加隆大爆炸核心时钟与状态 (绝不被其他警报顶替冲掉)
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
        mainFrame.titleText:SetText(STC_b1("观星者") .. " 塌缩星监控")
    end

    -- 5.5 第 2 行：专属战术警报栏 (双星连炸等重大突发危机，金橙标题+高亮指令，平时自动隐藏零占用)
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

    -- 动态自适应血条起始 Y 坐标与窗口总高度 (有第 2 行警报时向下微展 24px)
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

    -- 6. 动态感知全场活跃 DoT 数量并自适应主窗口宽度 (默认无 DoT 时 246px 极简，根据 DoT 出现平滑扩展)
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

    -- 基础血条宽 230，边距 8，无 DoT 时宽 246 (精致紧凑)
    -- 1 个 DoT 宽 272，2 个 DoT 宽 295，3 个 DoT 宽 318
    local targetWidth = 246
    if maxActiveDots == 1 then
        targetWidth = 272
    elseif maxActiveDots == 2 then
        targetWidth = 295
    elseif maxActiveDots >= 3 then
        targetWidth = 318
    end

    -- 若触发第 2 行双星连炸警报，保持至少 318px 充足宽幅，确保横向单行优雅展开
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

            -- 标记图标 (暴雪原生团队标记材质，若尚未打上标记则保底显示预定顺位标记)
            local displayMark = (star.raidMark and star.raidMark > 0) and star.raidMark or MARK_LIST[star.index or i] or 8
            bar.markIcon:SetTexture(MARK_TEXTURE_PREFIX .. displayMark)
            bar.markIcon:Show()

            -- 血量百分比与数值 (由左侧图标展示标记，不再显示汉字标记，杜绝重叠挤压)
            local pct = (star.maxHP > 0) and ((star.currentHP / star.maxHP) * 100) or 100
            bar.label:SetText(string.format("%.1f%%", pct))

            -- 核心预测算法判定 (红 / 黄 / 绿，传入专有双星连炸状态)
            local safetyLevel, statusText, r, g, b = EvaluateStarSafety(star, now, isBigBangCasting, bigBangLeft, timeToNextBB, collisionMap[star.guid])

            bar.sb:SetStatusBarColor(r, g, b)
            bar.timerText:SetText(statusText)

            -- 红色不安全时触发边框警报与音效
            if safetyLevel == "RED" then
                bar.glow:SetVertexColor(1, 0.2, 0)
                bar.glow:SetAlpha(0.9)

                -- 播放音效节流 (3.5秒一次)
                if BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.soundAlert then
                    if (now - lastAlertSoundTime) > 3.5 then
                        lastAlertSoundTime = now
                        PlaySoundFile("Sound\\Interface\\RaidWarning.ogg", "Master")
                    end
                end
            elseif safetyLevel == "YELLOW" then
                bar.glow:SetVertexColor(1, 0.8, 0)
                bar.glow:SetAlpha(0.3)
            else
                bar.glow:SetAlpha(0)
            end

            -- 点击目标宏设置
            if not InCombatLockdown() then
                if star.nameplateUnit then
                    bar:SetAttribute("type", "target")
                    bar:SetAttribute("unit", star.nameplateUnit)
                else
                    bar:SetAttribute("type", "macro")
                    bar:SetAttribute("macrotext", "/targetexact 塌缩星")
                end
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
                    return a.isMine -- 玩家自己的 DoT 优先展示
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
                    if dotData.duration and dotData.duration > 0 then
                        dotF.cd:SetCooldown(dotData.expTime - dotData.duration, dotData.duration)
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
                    dotF:Hide()
                end
            end
        elseif bar then
            bar:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- 8. 战斗与事件监听 (CLEU 优化 + P2 判定 + 截断防线)
--------------------------------------------------------------------------------
local function CheckP2Status(bossHP, bossMax)
    if isPhase2 then return end
    if bossHP and bossMax and bossMax > 0 and (bossHP / bossMax) <= PHASE2_HP_THRESHOLD then
        isPhase2 = true
        bigBangCastEnd = 0
        bigBangNextEstimate = 0
        wipe(activeStars)
        starCounter = 0
        DEFAULT_CHAT_FRAME:AddMessage(STC_g1("[BGLite 观星助手]") .. " 观星者血量 ≤ 20%，正式进入 P2 阶段！塌缩星消失，无大爆炸，全力击杀！")
        RefreshUI()
    end
end

local function OnCombatLogEvent(...)
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, param12, param13, param14, param15 = GetCombatLogArgs(...)

    -- 记录奥尔加隆 GUID，开怪自动唤醒面板
    if not algalonGUID then
        if destGUID and GetNpcIDFromGUID(destGUID) == ALGALON_NPC_ID then
            algalonGUID = destGUID
            if bigBangNextEstimate == 0 then
                bigBangNextEstimate = GetTime() + BIGBANG_FIRST_PULL_DELAY
            end
            ShowMainUI()
        elseif sourceGUID and GetNpcIDFromGUID(sourceGUID) == ALGALON_NPC_ID then
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
            -- 严格对齐 DBM：计时从施法开始时刻起算 90.5s，彻底根除多算 8 秒读条的时钟漂移
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

    -- P2 阶段塌缩星完全不处理
    if isPhase2 then return end

    -- 3. 塌缩星精准伤害扣减与掉血跟踪
    local npcID = GetNpcIDFromGUID(destGUID)
    if npcID == STAR_NPC_ID then
        local star = activeStars[destGUID] or RegisterStar(destGUID)
        ShowMainUI()

        local dmg = 0
        if subEvent == "SWING_DAMAGE" then
            dmg = param12 or 0
        elseif subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" or subEvent == "RANGE_DAMAGE" then
            dmg = param15 or 0
        end

        if dmg and dmg > 0 then
            star.currentHP = math.max(0, star.currentHP - dmg)
            AddDamageHistory(star, dmg, GetTime())
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
        if subEvent == "UNIT_DIED" then
            star.isDead = true
            star.currentHP = 0
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

local function OnEvent(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and GetNpcIDFromGUID(guid) == STAR_NPC_ID and not isPhase2 then
            local maxHP = UnitHealthMax(unit)
            local curHP = UnitHealth(unit)
            local star = RegisterStar(guid, maxHP)
            star.nameplateUnit = unit
            if curHP and curHP > 0 then star.currentHP = curHP end
            if maxHP and maxHP > 0 then star.maxHP = maxHP end

            -- 扫描 DoT
            ScanNameplateDots(star, unit)

            -- 自动分配团队标记
            TryAutoMark(unit)

            ShowMainUI()
            RefreshUI()
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        TryAutoMark("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        TryAutoMark("target")
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            activeStars[guid].nameplateUnit = nil
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        -- 监听 Boss 血量，P2 判定
        if (unit == "boss1" or unit == "target") and not isPhase2 then
            local guid = UnitGUID(unit)
            if guid and GetNpcIDFromGUID(guid) == ALGALON_NPC_ID then
                algalonGUID = guid
                CheckP2Status(UnitHealth(unit), UnitHealthMax(unit))
            end
        end

        -- 塌缩星血量实时校准
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            local hp = UnitHealth(unit)
            if hp and hp >= 0 then
                activeStars[guid].currentHP = hp
            end
            local maxHP = UnitHealthMax(unit)
            if maxHP and maxHP > 0 then
                activeStars[guid].maxHP = maxHP
            end
        end
    elseif event == "UNIT_AURA" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            ScanNameplateDots(activeStars[guid], unit)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 脱战清理 (若场上无活星或已结束则重置)
        local hasLiveStar = false
        for _, star in pairs(activeStars) do
            if not star.isDead and star.currentHP > 0 then
                hasLiveStar = true
                break
            end
        end
        if not hasLiveStar and not isTesting then
            wipe(activeStars)
            starCounter = 0
            bigBangCastEnd = 0
            bigBangNextEstimate = 0
            isPhase2 = false
            algalonGUID = nil
            if mainFrame then mainFrame:Hide() end
        end
    elseif event == "ENCOUNTER_START" then
        -- 记录战斗开始，初始化首次大爆炸时间轴 (严格对齐 DBM: 8s 开怪剧情台词 + 90s = 98s)
        local encounterID, encounterName = ...
        local isAlgalon = (encounterID == 757 or encounterID == 1130) or
                          (encounterName and (string.find(encounterName, "奥尔加隆") or string.find(encounterName, "Algalon")))
        if (isAlgalon or AlgalonStar.IsInUlduar()) and not isTesting then
            encounterStartTime = GetTime()
            bigBangNextEstimate = encounterStartTime + BIGBANG_FIRST_PULL_DELAY
            bigBangCastEnd = 0
            isPhase2 = false
            algalonGUID = nil
            wipe(activeStars)
            starCounter = 0
            ShowMainUI()
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
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:UnregisterEvent("ENCOUNTER_START")
    eventFrame:UnregisterEvent("ENCOUNTER_END")
    eventFrame:SetScript("OnUpdate", nil)
end

function AlgalonStar.UpdateEventRegistration()
    local enabled = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.enabled
    if enabled == nil then enabled = true end

    -- 若被用户总开关关闭：彻底截断所有事件，清空定时器，隐藏界面，实现 0 CPU 消耗
    if not enabled then
        AlgalonStar.UnregisterCombatEvents()
        if testTicker then testTicker:Cancel(); testTicker = nil end
        isTesting = false
        wipe(activeStars)
        starCounter = 0
        if mainFrame then mainFrame:Hide() end
        return
    end

    -- 若启用：检查是否在奥杜尔副本中或正在测试沙盘
    if isTesting or AlgalonStar.IsInUlduar() then
        AlgalonStar.RegisterCombatEvents()
    else
        -- 离开奥杜尔且非测试：挂起战斗事件，保留区域事件，避免在主城或其它副本浪费性能
        AlgalonStar.UnregisterCombatEvents()
        wipe(activeStars)
        starCounter = 0
        if mainFrame then mainFrame:Hide() end
    end
end

function AlgalonStar.SetEnabled(enabled)
    if not BiaoGe and BiaoGe.AlgalonStar then BiaoGe.AlgalonStar = {} end
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
        print(STC_g1("[BGLite 观星助手]") .. " 模拟测试：【P2 阶段演示】(Boss ≤ 20%，塌缩星消失，全力 RUSH！)")
        RefreshUI()
        return
    end

    isPhase2 = false
    local now = GetTime()
    bigBangNextEstimate = now + 32.0 -- 模拟 32 秒后大爆炸

    local mockData = {}
    if subMode == "double" or subMode == "wipe" then
        print(STC_r1("[BGLite 观星助手]") .. " 模拟测试：【大爆炸前后双星连炸灭团高危场景】！")
        -- 骷髅(ETA 37.0s) 与 方块(ETA 36.0s) 在大爆炸(32s)后仅差 1.0s 连爆！
        -- 触发【大爆炸前后双星连炸! 必灭团!】顶栏警报与精确集火/停手指令！
        mockData = {
            { hpPct = 0.50, dps = 1021, mark = 8, dots = { { name = "月火术", dur = 12, remain = 8.5, isMine = true } } },
            { hpPct = 0.28, dps = 1320, mark = 7, dots = { { name = "暗言术：痛", dur = 18, remain = 14.0, isMine = true } } },
            { hpPct = 0.48, dps = 1008, mark = 6, dots = { { name = "吸血鬼之触", dur = 15, remain = 9.4, isMine = true } } },
            { hpPct = 0.85, dps = 600,  mark = 4, dots = { { name = "腐蚀术", dur = 18, remain = 16.0, isMine = false } } },
        }
    else
        print(STC_g1("[BGLite 观星助手]") .. " 模拟测试沙盘已【启动】！输入 /star test double 测双星连炸灭团，/star test p2 测P2。")
        -- 常规四态演示：
        -- 星 1：绿色【进洞免伤】(自爆在 35 秒，大爆炸 32s 施法 8s，刚好在进洞期间 3s 免伤自爆，0 伤害极佳)
        -- 星 2：黄色【提前留洞】(自爆在 16 秒，大爆炸前提前 16 秒爆，能留洞但需覆盖团血)
        -- 星 3：黄色【出洞炸】(自爆在 45 秒，大爆炸彻底结束后出洞 5 秒炸，需关注团血)
        -- 星 4：红色【大爆炸撞车】(自爆在 31 秒，刚好在大爆炸读条前夕重叠，高危撞车)
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

    local loopCounter = 0
    testTicker = C_Timer.NewTicker(0.2, function()
        loopCounter = loopCounter + 1
        local tickNow = GetTime()

        -- 模拟每 45 秒循环一次大爆炸 (8秒读条)
        if loopCounter % 225 == 160 then
            bigBangCastEnd = tickNow + 8.0
            bigBangNextEstimate = tickNow + 8.0 + 45.0
        end

        for _, star in pairs(activeStars) do
            star.currentHP = math.max(0, star.currentHP - (star.dps * 0.2))
            if star.currentHP <= 0 then
                star.currentHP = star.maxHP -- 循环重置
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

    -- 观星修星助手主开关复选框 (直接挂载在战术站位图右侧，无冗余分隔符)
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
        BG.PlaySound(1)
    end)
    cbStar:SetScript("OnShow", function(self)
        local enabled = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.enabled
        if enabled == nil then enabled = true end
        self:SetChecked(enabled)
    end)
    cbStar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_b1("观星修星助手 (奥尔加隆)") .. " - 核心开关", 1, 1, 1)
        GameTooltip:AddLine("勾选开启奥杜尔观星者塌缩星专属血量监控与大爆炸冲突预警。", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("核心预测与特性：", 1, 0.82, 0)
        GameTooltip:AddLine("- " .. STC_g1("【绿色·进洞免伤】") .. " 预测大爆炸读条期间全团在洞内0伤害引爆 (极佳)", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- " .. STC_y1("【黄色·注意】") .. " 预测提前留洞引爆，或出洞后引爆 (需关注团血/备用洞)", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- " .. STC_r1("【红色·危险】") .. " 预测在大爆炸前夕撞车、出洞瞬间连爆或双星连炸", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- 鸟德/暗牧核心修星 DoT 倒计时与专属图标", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("- 自动识别 P2 阶段 (≤20% HP) 塌缩星消失清空", 0.85, 0.85, 0.85)
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
        BG.PlaySound(1)
    end)
    btnTest:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(STC_g1("观星修星模拟沙盘 (/star test)"), 1, 1, 1)
        GameTooltip:AddLine("无需进入奥杜尔副本，在主城即可模拟 4 颗塌缩星平滑掉血、DoT 倒计时、动态排序及红/黄/绿安全预测！", 0.85, 0.85, 0.85, true)
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
        BG.PlaySound(1)
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
    if db.enabled == nil then db.enabled = true end
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
        if not BiaoGe.AlgalonStar then BiaoGe.AlgalonStar = {} end
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
