if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L or {}
local LibBG = ns.LibBG
local RGB = ns.RGB
local BIAOGE_TEXT_FONT = BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT

local STC_b1 = BG.STC_b1 or function(t) return "|cff00BFFF" .. t .. "|r" end
local STC_g1 = BG.STC_g1 or function(t) return "|cff00FF00" .. t .. "|r" end
local STC_r1 = BG.STC_r1 or function(t) return "|cffff0000" .. t .. "|r" end
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

-- 团队标记固定映射：1号骷髅(8), 2号红叉(7), 3号方块(6), 4号三角(4)
local MARK_LIST = { 8, 7, 6, 4 }
local MARK_NAMES = {
    [8] = "骷髅",
    [7] = "红叉",
    [6] = "方块",
    [4] = "三角",
}
local MARK_TEXTURE_PREFIX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

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
local activeStars = {}       -- [guid] = starData
local starCounter = 0        -- 顺位注册计数器
local bigBangCastEnd = 0     -- 当前大爆炸施法结束时间戳
local isCombatRegistered = false
local isTesting = false
local testTicker = nil
local lastAlertSoundTime = 0

local eventFrame = CreateFrame("Frame", "BG_AlgalonStarEventFrame", UIParent)
AlgalonStar.eventFrame = eventFrame

--------------------------------------------------------------------------------
-- 3. 辅助解析函数
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
-- 4. 注册与数据更新核心算法
--------------------------------------------------------------------------------
local function RegisterStar(guid, maxHP)
    if not activeStars[guid] then
        starCounter = (starCounter % 4) + 1
        local assignIndex = starCounter
        local mark = MARK_LIST[assignIndex] or 0

        activeStars[guid] = {
            guid = guid,
            index = assignIndex,
            raidMark = mark,
            currentHP = maxHP or 75600,
            maxHP = maxHP or 75600,
            dps = 0,
            dmgHistory = {},
            dots = {},
            lastTick = GetTime(),
            nameplateUnit = nil,
            lastMarkTime = 0,
        }
    else
        if maxHP and maxHP > 0 and (not activeStars[guid].maxHP or activeStars[guid].maxHP <= 0) then
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
    if timeSpan > 0.5 and totalDmg > 0 then
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

    -- 清理已经不存在的 DoT
    for dotName, _ in pairs(star.dots) do
        if not seenDots[dotName] then
            star.dots[dotName] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- 5. UI 界面构建 (StatusBar + DoT 图标槽 + 大爆炸预警)
--------------------------------------------------------------------------------
local mainFrame = nil
local bars = {}

local function CreateMainUI()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "BG_AlgalonStarMainUI", UIParent, "BackdropTemplate")
    mainFrame:SetSize(280, 168)
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
        if not (BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked) then
            self:StartMoving()
        end
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

    -- 顶部标题与大爆炸警报条
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

    -- 锁定按钮
    local btnLock = CreateFrame("Button", nil, mainFrame)
    btnLock:SetSize(16, 16)
    btnLock:SetPoint("RIGHT", titleBg, "RIGHT", -22, 0)
    btnLock.icon = btnLock:CreateTexture(nil, "ARTWORK")
    btnLock.icon:SetAllPoints()
    btnLock.icon:SetTexture("Interface\\GuildFrame\\GuildFrame")
    btnLock.icon:SetTexCoord(0.25, 0.35, 0.85, 0.95)

    local function UpdateLockIcon()
        local locked = BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.locked
        if locked then
            btnLock.icon:SetDesaturated(false)
            btnLock.icon:SetVertexColor(1, 0.8, 0.2)
        else
            btnLock.icon:SetDesaturated(true)
            btnLock.icon:SetVertexColor(0.8, 0.8, 0.8)
        end
    end
    UpdateLockIcon()

    btnLock:SetScript("OnClick", function()
        if not BiaoGe.AlgalonStar then BiaoGe.AlgalonStar = {} end
        BiaoGe.AlgalonStar.locked = not BiaoGe.AlgalonStar.locked
        UpdateLockIcon()
        if BiaoGe.AlgalonStar.locked then
            DEFAULT_CHAT_FRAME:AddMessage(STC_b1("[BGLite 观星助手]") .. " 窗口已锁定。")
        else
            DEFAULT_CHAT_FRAME:AddMessage(STC_b1("[BGLite 观星助手]") .. " 窗口已解锁，可按住拖动。")
        end
        BG.PlaySound(1)
    end)
    btnLock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("锁定/解锁位置", 1, 1, 1)
        GameTooltip:AddLine("解锁后可按住窗口任意空白处拖拽调整位置。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnLock:SetScript("OnLeave", GameTooltip_Hide)

    -- 关闭按钮
    local btnClose = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    btnClose:SetSize(22, 22)
    btnClose:SetPoint("RIGHT", titleBg, "RIGHT", 2, 0)
    btnClose:SetScript("OnClick", function()
        mainFrame:Hide()
        BG.PlaySound(1)
    end)

    -- 4 根血条构建
    for i = 1, 4 do
        local bar = CreateFrame("Button", "BG_AlgalonStarBar_" .. i, mainFrame, "SecureActionButtonTemplate")
        bar:SetSize(185, 26)
        bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -32 - (i - 1) * 32)
        bar:RegisterForClicks("AnyUp")

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
        local markIcon = bar:CreateTexture(nil, "OVERLAY")
        markIcon:SetSize(20, 20)
        markIcon:SetPoint("LEFT", bar, "LEFT", 2, 0)
        bar.markIcon = markIcon

        -- 血量与名称文本
        local label = sb:CreateFontString(nil, "OVERLAY")
        label:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        label:SetPoint("LEFT", markIcon, "RIGHT", 4, 0)
        bar.label = label

        -- 自爆倒计时文本
        local timerText = sb:CreateFontString(nil, "OVERLAY")
        timerText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.timerText = timerText

        -- 边框高亮材质 (大爆炸冲突时闪烁)
        local glow = bar:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("TOPLEFT", -3, 3)
        glow:SetPoint("BOTTOMRIGHT", 3, -3)
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)
        bar.glow = glow

        -- 右侧 DoT 图标槽 (3个槽位，尺寸18x18)
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
            dotF.cd = cd

            local cdText = dotF:CreateFontString(nil, "OVERLAY")
            cdText:SetFont(BIAOGE_TEXT_FONT, 9, "OUTLINE")
            cdText:SetPoint("BOTTOM", dotF, "BOTTOM", 0, -1)
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

--------------------------------------------------------------------------------
-- 6. UI 实时刷新与渲染逻辑
--------------------------------------------------------------------------------
local function RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local now = GetTime()
    local bigBangLeft = math.max(0, bigBangCastEnd - now)
    local isBigBangCasting = (bigBangLeft > 0)

    -- 顶部标题条状态更新
    if isBigBangCasting then
        mainFrame.titleBg:SetColorTexture(0.6, 0.15, 0.05, 0.95)
        mainFrame.titleText:SetText(string.format(STC_r1("【大爆炸读条中】") .. " 剩余: " .. STC_y1("%.1fs") .. " (注意减伤/进洞)", bigBangLeft))
    else
        mainFrame.titleBg:SetColorTexture(0.1, 0.18, 0.28, 0.8)
        mainFrame.titleText:SetText(STC_b1("观星者") .. " 塌缩星监控 (自适应)")
    end

    -- 提取星体并排序
    local starList = {}
    for _, star in pairs(activeStars) do
        if not star.isDead and star.currentHP > 0 then
            table.insert(starList, star)
        end
    end

    -- 默认按剩余血量升序排列 (血最少、最危险的排在最前)
    table.sort(starList, function(a, b)
        return a.currentHP < b.currentHP
    end)

    for i = 1, 4 do
        local bar = bars[i]
        local star = starList[i]

        if star and bar then
            bar:Show()
            bar.sb:SetMinMaxValues(0, star.maxHP or 75600)
            bar.sb:SetValue(star.currentHP)

            -- 标记图标
            if star.raidMark and star.raidMark > 0 then
                bar.markIcon:SetTexture(MARK_TEXTURE_PREFIX .. star.raidMark)
                bar.markIcon:Show()
            else
                bar.markIcon:Hide()
            end

            -- 血量百分比与数值
            local pct = (star.currentHP / (star.maxHP > 0 and star.maxHP or 75600)) * 100
            local markName = MARK_NAMES[star.raidMark] or ("星" .. star.index)
            bar.label:SetText(string.format("%s %.1f%% (%.1fk)", markName, pct, star.currentHP / 1000))

            -- 掉血倒计时 ETA 与冲突判定
            local dps = (star.dps > 0) and star.dps or (star.maxHP * 0.01)
            local eta = star.currentHP / dps

            local isCollision = isBigBangCasting and (math.abs(eta - bigBangLeft) <= 2.5)

            if isCollision then
                bar.sb:SetStatusBarColor(1, 0.45, 0) -- 亮橙色警报
                bar.timerText:SetText(STC_r1(string.format("自爆: %.1fs (撞车危险!)", eta)))
                bar.glow:SetVertexColor(1, 0.3, 0)
                bar.glow:SetAlpha(0.9)

                -- 播放警报音效 (防刷屏节流 4 秒一次)
                if BiaoGe and BiaoGe.AlgalonStar and BiaoGe.AlgalonStar.soundAlert then
                    if (now - lastAlertSoundTime) > 4.0 then
                        lastAlertSoundTime = now
                        PlaySoundFile("Sound\\Interface\\RaidWarning.ogg", "Master")
                    end
                end
            elseif pct <= 20 or eta <= 5.0 then
                bar.sb:SetStatusBarColor(0.9, 0.15, 0.15) -- 濒死自爆深红
                bar.timerText:SetText(STC_r1(string.format("即将自爆: %.1fs", eta)))
                bar.glow:SetVertexColor(1, 0, 0)
                bar.glow:SetAlpha(0.5)
            elseif isBigBangCasting and (eta < bigBangLeft - 2.5) then
                bar.sb:SetStatusBarColor(0.2, 0.85, 0.3) -- 绿色安全早引爆
                bar.timerText:SetText(STC_g1(string.format("自爆: %.1fs (安全提早)", eta)))
                bar.glow:SetAlpha(0)
            else
                bar.sb:SetStatusBarColor(0, 0.7, 1) -- 正常青蓝
                if eta < 60 then
                    bar.timerText:SetText(string.format("自爆: %.1fs", eta))
                else
                    bar.timerText:SetText("血量平稳")
                end
                bar.glow:SetAlpha(0)
            end

            -- 点击目标宏设置 (非战斗状态或具有有效目标时绑定)
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
-- 7. 战斗与事件监听 (支持开关硬截断)
--------------------------------------------------------------------------------
local function OnCombatLogEvent(...)
    local timestamp, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, param12, param13, param14, param15 = GetCombatLogArgs(...)

    -- 1. 监控奥尔加隆大爆炸施法
    if subEvent == "SPELL_CAST_START" then
        local spellID = param12
        if spellID and BIG_BANG_SPELLS[spellID] then
            bigBangCastEnd = GetTime() + 8.0
            if mainFrame and not mainFrame:IsShown() then
                mainFrame:Show()
            end
            RefreshUI()
        end
    end

    -- 2. 塌缩星伤害扣减与掉血跟踪
    local npcID = GetNpcIDFromGUID(destGUID)
    if npcID == STAR_NPC_ID then
        local star = activeStars[destGUID] or RegisterStar(destGUID)
        if mainFrame and not mainFrame:IsShown() then
            mainFrame:Show()
        end

        local dmg = 0
        if subEvent == "SWING_DAMAGE" then
            dmg = param12 or 0
        elseif subEvent:find("_DAMAGE") then
            dmg = param15 or param12 or 0
        end

        if dmg and dmg > 0 then
            star.currentHP = math.max(0, star.currentHP - dmg)
            AddDamageHistory(star, dmg, GetTime())
        end

        -- 3. 监控 DoT 施加与移除 (视角盲区兜底)
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

        -- 4. 死亡清理
        if subEvent == "UNIT_DIED" then
            star.isDead = true
            star.currentHP = 0
        end
    end
end

local function OnEvent(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and GetNpcIDFromGUID(guid) == STAR_NPC_ID then
            local maxHP = UnitHealthMax(unit)
            local curHP = UnitHealth(unit)
            local star = RegisterStar(guid, maxHP)
            star.nameplateUnit = unit
            if curHP and curHP > 0 then star.currentHP = curHP end
            if maxHP and maxHP > 0 then star.maxHP = maxHP end

            -- 扫描 DoT
            ScanNameplateDots(star, unit)

            -- 自动分配团队标记 (限团长/助理，防抖)
            local now = GetTime()
            if CanSetMarks() and star.raidMark and star.raidMark > 0 then
                if (now - (star.lastMarkTime or 0)) > 1.5 then
                    star.lastMarkTime = now
                    local currentMark = GetRaidTargetIndex(unit)
                    if currentMark ~= star.raidMark then
                        SetRaidTarget(unit, star.raidMark)
                    end
                end
            end

            if mainFrame and not mainFrame:IsShown() then
                mainFrame:Show()
            end
            RefreshUI()
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local guid = UnitGUID(unit)
        if guid and activeStars[guid] then
            activeStars[guid].nameplateUnit = nil
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
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
        -- 脱战清理 (若场上无活星则重置)
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
            if mainFrame then mainFrame:Hide() end
        end
    elseif event == "ENCOUNTER_END" then
        if not isTesting then
            wipe(activeStars)
            starCounter = 0
            bigBangCastEnd = 0
            if mainFrame then mainFrame:Hide() end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        AlgalonStar.UpdateEventRegistration()
    end
end

--------------------------------------------------------------------------------
-- 8. 事件截断与动态开关控制 (核心性能防线)
--------------------------------------------------------------------------------
function AlgalonStar.RegisterCombatEvents()
    if isCombatRegistered then return end
    isCombatRegistered = true
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
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
    if not BiaoGe.AlgalonStar then BiaoGe.AlgalonStar = {} end
    BiaoGe.AlgalonStar.enabled = enabled
    AlgalonStar.UpdateEventRegistration()

    if enabled then
        DEFAULT_CHAT_FRAME:AddMessage(STC_g1("[BGLite 观星助手]") .. " 模块已【开启】(进入奥杜尔自动激活，支持 /star test 主城测试)。")
    else
        DEFAULT_CHAT_FRAME:AddMessage(STC_r1("[BGLite 观星助手]") .. " 模块已【关闭】，已完全截断事件监听与后台计算，零性能开销。")
    end
end

--------------------------------------------------------------------------------
-- 9. 主城模拟测试沙盘 (/star test)
--------------------------------------------------------------------------------
function AlgalonStar.ToggleTestMode()
    isTesting = not isTesting
    CreateMainUI()

    if isTesting then
        print(STC_g1("[BGLite 观星助手]") .. " 模拟测试沙盘已【启动】！按住标题栏可拖拽调整位置，再次点击或输入 /star test 结束。")
        wipe(activeStars)
        mainFrame:Show()

        local now = GetTime()
        local mockData = {
            { hpPct = 0.38, dps = 1450, mark = 8, dots = { { name = "月火术", dur = 12, remain = 6.8, isMine = true }, { name = "虫群", dur = 12, remain = 4.2, isMine = true } } },
            { hpPct = 0.58, dps = 950,  mark = 7, dots = { { name = "暗言术：痛", dur = 18, remain = 12.0, isMine = true }, { name = "噬灵疫病", dur = 24, remain = 16.5, isMine = false } } },
            { hpPct = 0.82, dps = 760,  mark = 6, dots = { { name = "吸血鬼之触", dur = 15, remain = 9.4, isMine = true } } },
            { hpPct = 0.95, dps = 756,  mark = 4, dots = { { name = "腐蚀术", dur = 18, remain = 14.0, isMine = false } } },
        }

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

            -- 模拟每 28 秒施放一次大爆炸 (8秒读条)
            if loopCounter % 140 == 30 then
                bigBangCastEnd = tickNow + 8.0
            end

            for _, star in pairs(activeStars) do
                star.currentHP = math.max(0, star.currentHP - (star.dps * 0.2))
                if star.currentHP <= 0 then
                    star.currentHP = star.maxHP -- 循环重置
                    -- 刷新 DoT 倒计时
                    for _, dot in pairs(star.dots) do
                        dot.expTime = tickNow + dot.duration
                    end
                end
            end
            RefreshUI()
        end)
    else
        print(STC_r1("[BGLite 观星助手]") .. " 模拟测试沙盘已【关闭】。")
        if testTicker then testTicker:Cancel(); testTicker = nil end
        wipe(activeStars)
        starCounter = 0
        bigBangCastEnd = 0
        if mainFrame then mainFrame:Hide() end
    end
end

--------------------------------------------------------------------------------
-- 10. 挂载到团队工具底部 (站位图开关右侧)
--------------------------------------------------------------------------------
function AlgalonStar.CreateToolControls(entry, anchorFrame)
    if not entry or entry.starControlsCreated then return end
    entry.starControlsCreated = true

    -- 分隔符
    local sep = entry:CreateFontString(nil, "OVERLAY")
    sep:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    sep:SetPoint("LEFT", anchorFrame.text or anchorFrame, "RIGHT", 14, 0)
    sep:SetText(STC_dis("|"))

    -- 观星修星助手主开关复选框
    local cbStar = CreateFrame("CheckButton", "BG_AlgalonStarToolCheckButton", entry, "UICheckButtonTemplate")
    cbStar:SetSize(20, 20)
    cbStar:SetPoint("LEFT", sep, "RIGHT", 12, 0)
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
        GameTooltip:AddLine("勾选开启奥杜尔观星者塌缩星专属血量自适应监控与大爆炸冲突预警。", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("功能特性：", 1, 0.82, 0)
        GameTooltip:AddLine("• 4星独立血条与实时掉血速率推算", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("• 鸟德/暗牧核心修星 DoT 倒计时与专属图标", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("• 大爆炸与自爆重叠撞车全屏警报与音效提示", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("• 唯一 GUID 绑定防串星，自动打骷髅等团队标记", 0.85, 0.85, 0.85)
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
        GameTooltip:AddLine("无需进入奥杜尔副本，在主城即可模拟 4 颗塌缩星平滑掉血、DoT 倒计时、动态排序及大爆炸冲突报警！", 0.85, 0.85, 0.85, true)
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
    tipText:SetText(STC_dis("(血量自适应 / 核心DoT倒计时 / 大爆炸撞车预警)"))
end

--------------------------------------------------------------------------------
-- 11. 初始化与 Slash 指令注册
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
        DEFAULT_CHAT_FRAME:AddMessage(STC_b1("[BGLite 观星助手]") .. " 常用指令: /star test (测试沙盘), /star lock (锁定/解锁), /star on/off (开关)")
    end
end
