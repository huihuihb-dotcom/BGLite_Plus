--[[
    BGLite_Plus: Core/TitanGoblin.lua
    功能：【碎片统计】时光服泰坦代币（碎片/余烬）兑换物资与 EasyAuction 价格收益分析系统
    特性：
      - 深度联动 EasyAuction 扫描价格（支持【最低挂牌价】与抗钓鱼压价【中位数参考价】双轨分析）
      - 实时计算“每碎片金币收益 (G/片)”与“每余烬金币收益 (G/余烬)”
      - 全服全专业大横向比拼（全服最优推荐冠军卡片 + 全局总排行）
      - 各专业内部自动高亮最优推荐物资（最低价推荐 ★ / 中位价推荐 ★）
      - 顶部中位数显隐开关与偏好持久化记忆
      - 趣味地精身价估算：预估碎片+余烬全换变现金币，叠加自身金币统计总身价
      - 纯正魔兽原生内置材质内嵌（金皇冠、团队星标、暴雪官方专业图标），杜绝乱码方块，质感爆棚！
]]

local ADDON_NAME, ns = ...
local BG = BG or {}
local L = BG.L or {}

ns.TitanGoblin = {}
local TG = ns.TitanGoblin

-- 常量配置
BG.TitanGoblinMainFrameTabNum = 105
local CURRENCY_SHARD = 3406
local CURRENCY_EMBER = 3403
local EMBER_TO_SHARD_RATIO = 100 -- 1 余烬 = 100 碎片

local selectedCategoryKey = "ALL"
local sortColumn = "yieldMinCopper" -- "yieldMinCopper", "yieldMedianCopper", "minCopper", "cost"
local sortAsc = false -- 默认降序（最赚钱排最前面）

-- 暴雪官方原生内置材质内嵌定义（纯正 WoW 材质，杜绝任何中文字体乱码方块）
local ICON_CROWN    = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:16:16:0:0|t"
local ICON_TROPHY   = "|TInterface\\Icons\\INV_Jewelry_Trophy_01:14:14:0:0|t"
local ICON_STAR     = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14:0:0|t"
local ICON_COIN     = "|TInterface\\Icons\\INV_Misc_Coin_01:16:16:0:0|t"
local ICON_GOLD     = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local ICON_EMBER    = "|TInterface\\Icons\\INV_Misc_Gem_Bloodstone_02:14:14:0:0|t"
local ICON_SHARD    = "|TInterface\\Icons\\Spell_Nature_Astral_Burst:14:14:0:0|t"

-- 分类列表 (带暴雪官方专业图标)
local CATEGORIES = {
    { key = "ALL", text = "|TInterface\\Icons\\INV_Jewelry_Trophy_01:14:14:0:0|t 全局排行" },
    { key = "炼金", text = "|TInterface\\Icons\\Trade_Alchemy:14:14:0:0|t 炼金" },
    { key = "矿石", text = "|TInterface\\Icons\\Trade_Mining:14:14:0:0|t 矿石" },
    { key = "附魔", text = "|TInterface\\Icons\\Trade_Engraving:14:14:0:0|t 附魔" },
    { key = "裁缝", text = "|TInterface\\Icons\\Trade_Tailoring:14:14:0:0|t 裁缝" },
    { key = "制皮", text = "|TInterface\\Icons\\Trade_Leatherworking:14:14:0:0|t 制皮" },
    { key = "元素材料", text = "|TInterface\\Icons\\Spell_Nature_Earthquake:14:14:0:0|t 元素材料" },
    { key = "杂项物资", text = "|TInterface\\Icons\\INV_Misc_Bag_08:14:14:0:0|t 杂项物资" },
}

-- ----------------------------------------------------------------------------
-- 1. EasyAuction 价格与中位数读取引擎
-- ----------------------------------------------------------------------------

local function GetEasyAuctionDB()
    if type(EasyAuctionDB2) == "table" then
        local key = nil
        if type(GetRealmFactionKey) == "function" then
            key = GetRealmFactionKey()
        elseif type(ns.EA_GetRealmFactionKey) == "function" then
            key = ns.EA_GetRealmFactionKey()
        else
            local realm = GetRealmName()
            local faction = UnitFactionGroup("player")
            if realm and faction then
                key = realm .. "-" .. faction
            end
        end
        if key and EasyAuctionDB2[key] then
            return EasyAuctionDB2[key]
        end
        for k, v in pairs(EasyAuctionDB2) do
            if type(v) == "table" and v.PriceHistory and next(v.PriceHistory) then
                return v
            end
        end
    end
    if type(EasyAuctionDB) == "table" and EasyAuctionDB.PriceHistory then
        return EasyAuctionDB
    end
    if _G.EasyAuctionDB and type(_G.EasyAuctionDB) == "table" and _G.EasyAuctionDB.PriceHistory then
        return _G.EasyAuctionDB
    end
    return nil
end

local function GetLatestScanTimeFromDB(db)
    if not db then return nil end
    local latestT = 0
    if db.PriceHistory then
        local checked = 0
        for _, raw in pairs(db.PriceHistory) do
            if type(raw) == "string" then
                local tText = raw:match("^PH2|[^|]*|([^|]+)|")
                local t = tonumber(tText)
                if t and t > latestT then latestT = t end
            elseif type(raw) == "table" then
                if raw.lastScanT then
                    local t = tonumber(raw.lastScanT)
                    if t and t > latestT then latestT = t end
                end
                for _, rec in ipairs(raw) do
                    if type(rec) == "table" then
                        local t = tonumber(rec.t or rec.time or rec[3])
                        if t and t > latestT then latestT = t end
                    end
                end
            end
            checked = checked + 1
            if checked > 500 then break end
        end
    end
    if latestT == 0 and db.HourlyMinPrice then
        for _, raw in pairs(db.HourlyMinPrice) do
            if type(raw) == "string" then
                for tText in raw:gmatch(";[^,;]+,[^,;]+,[^,;]+,[^,;]+,([^,;]+)") do
                    local t = tonumber(tText)
                    if t and t > latestT then latestT = t end
                end
            elseif type(raw) == "table" then
                for _, rec in ipairs(raw) do
                    if type(rec) == "table" then
                        local t = tonumber(rec[5] or rec.t)
                        if t and t > latestT then latestT = t end
                    end
                end
            end
        end
    end
    return latestT > 0 and latestT or nil
end

function TG.GetEasyAuctionScanTime()
    if TG.latestScanTime and TG.latestScanTime > 0 then
        return TG.latestScanTime
    end
    local db = GetEasyAuctionDB()
    if db then
        local t = GetLatestScanTimeFromDB(db)
        if t and t > 0 then
            TG.latestScanTime = t
            return t
        end
    end
    return nil
end

function TG.CheckEasyAuctionStatus()
    local isAddonLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EasyAuction"))
        or (IsAddOnLoaded and IsAddOnLoaded("EasyAuction"))
        or (type(EasyAuctionDB2) == "table")
        or (type(EasyAuctionDB) == "table")

    local db = GetEasyAuctionDB()
    if not db then
        if isAddonLoaded then
            return "NO_DATA", nil
        else
            return "NOT_INSTALLED", nil
        end
    end

    local hasPrices = (db.PriceHistory and next(db.PriceHistory))
        or (db.DailyMinPrice and next(db.DailyMinPrice))
        or (db.HourlyMinPrice and next(db.HourlyMinPrice))

    if not hasPrices then
        return "NO_DATA", db
    end

    return "OK", db
end

local function FormatScanTime(ts)
    if not ts or ts <= 0 then
        return "|cffFFA500未知|r"
    end
    local diff = time() - ts
    local dateStr = date("%m-%d %H:%M", ts)
    if diff < 0 or diff < 60 then
        return string.format("|cff00FF00%s (刚刚)|r", dateStr)
    elseif diff < 3600 then
        local mins = math.max(1, math.floor(diff / 60))
        return string.format("|cff00FF00%s (%d分钟前)|r", dateStr, mins)
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return string.format("|cff7CFC00%s (%d小时前)|r", dateStr, hours)
    elseif diff < 86400 * 3 then
        local days = math.floor(diff / 86400)
        return string.format("|cffFFD700%s (%d天前)|r", dateStr, days)
    else
        local days = math.floor(diff / 86400)
        return string.format("|cffFF8000%s (%d天前 过旧)|r", dateStr, days)
    end
end

local function GetItemPrices(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil, nil, nil end

    local db = GetEasyAuctionDB()
    if not db then return nil, nil, nil end

    local minPriceCopper = nil
    local medianCopper = nil
    local itemScanTime = nil

    if type(EasyAuction_GetLatestUnitPriceByItemID) == "function" then
        local p = EasyAuction_GetLatestUnitPriceByItemID(itemID, db)
        if p and p > 0 then
            minPriceCopper = p
        end
    end

    local suffix = ":" .. tostring(itemID)
    local allUnits = {}

    local function CollectFromRaw(raw)
        if type(raw) == "string" then
            local minText, lastText, body = raw:match("^PH2|([^|]*)|([^|]*)|(.*)$")
            local hMin = tonumber(minText)
            if hMin and hMin > 0 and (not minPriceCopper or hMin < minPriceCopper) then
                minPriceCopper = hMin
            end
            local hLast = tonumber(lastText)
            if hLast and hLast > (itemScanTime or 0) then
                itemScanTime = hLast
            end
            for unitText, countText in tostring(body or ""):gmatch("([^,;]+),([^,;]+),[^;]+") do
                local u = tonumber(unitText)
                local c = tonumber(countText) or 1
                if u and u > 0 then
                    for _ = 1, math.min(10, math.max(1, c)) do
                        table.insert(allUnits, u)
                    end
                end
            end
        elseif type(raw) == "table" then
            if raw.lastScanT then
                local t = tonumber(raw.lastScanT)
                if t and t > (itemScanTime or 0) then itemScanTime = t end
            end
            for _, rec in ipairs(raw) do
                local u = tonumber(rec.unit or rec[1])
                local c = tonumber(rec.count or rec[2]) or 1
                local t = tonumber(rec.t or rec.time or rec[3])
                if t and t > (itemScanTime or 0) then itemScanTime = t end
                if u and u > 0 then
                    for _ = 1, math.min(10, math.max(1, c)) do
                        table.insert(allUnits, u)
                    end
                end
            end
        end
    end

    if db.PriceHistory then
        for key, raw in pairs(db.PriceHistory) do
            if type(key) == "string" and key:sub(-#suffix) == suffix then
                CollectFromRaw(raw)
            end
        end
    end

    if #allUnits == 0 and db.DailyMinPrice then
        for key, raw in pairs(db.DailyMinPrice) do
            if type(key) == "string" and key:sub(-#suffix) == suffix then
                if type(raw) == "table" then
                    for _, rec in ipairs(raw) do
                        local u = tonumber(rec[2])
                        if u and u > 0 then table.insert(allUnits, u) end
                    end
                end
            end
        end
    end

    if #allUnits > 0 then
        table.sort(allUnits)
        minPriceCopper = minPriceCopper or allUnits[1]
        local n = #allUnits
        local trim = math.floor(n * 0.10 + 0.5)
        local from = trim + 1
        local to = n - trim
        if from > to then from, to = 1, n end
        local trimmed = {}
        for i = from, to do
            table.insert(trimmed, allUnits[i])
        end
        local tn = #trimmed
        if tn > 0 then
            if tn % 2 == 1 then
                medianCopper = trimmed[math.ceil(tn / 2)]
            else
                local m1 = trimmed[tn / 2]
                local m2 = trimmed[tn / 2 + 1]
                medianCopper = math.floor((m1 + m2) / 2 + 0.5)
            end
        else
            medianCopper = allUnits[math.ceil(n / 2)]
        end
    end

    medianCopper = medianCopper or minPriceCopper
    return minPriceCopper, medianCopper, itemScanTime
end

local function FormatCopperToText(copper)
    if not copper or copper <= 0 then
        return "|cff808080无行情|r"
    end
    copper = math.floor(copper + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100

    local str = ""
    if g > 0 then
        str = str .. string.format("|cffFFD700%d|r金", g)
    end
    if s > 0 or (g > 0 and c > 0) then
        str = str .. string.format("|cffC0C0C0%d|r银", s)
    end
    if c > 0 or (g == 0 and s == 0) then
        str = str .. string.format("|cffCD7F32%d|r铜", c)
    end
    return str
end

-- ----------------------------------------------------------------------------
-- 2. 数据处理与双榜最优分析
-- ----------------------------------------------------------------------------

local processedList = {}
local categoryBestMap = {}
local globalBestMin = nil
local globalBestMedian = nil

function TG.CalculateAllData()
    processedList = {}
    categoryBestMap = {}
    globalBestMin = nil
    globalBestMedian = nil
    local latestScanTime = 0

    local rawDB = BG.TitanExchangeDB or {}

    for catName, items in pairs(rawDB) do
        categoryBestMap[catName] = { bestMin = nil, bestMedian = nil }
        for _, item in ipairs(items) do
            local minCopper, medianCopper, itemScanTime = GetItemPrices(item.id)
            if itemScanTime and itemScanTime > latestScanTime then
                latestScanTime = itemScanTime
            end
            local minGold = minCopper and (minCopper / 10000) or nil
            local medianGold = medianCopper and (medianCopper / 10000) or nil

            local buyCount = item.count or 1
            local cost = item.cost or 20
            local costType = item.costType or CURRENCY_SHARD

            local effectiveShards = (costType == CURRENCY_EMBER) and (cost * EMBER_TO_SHARD_RATIO) or cost
            if effectiveShards <= 0 then effectiveShards = 1 end

            local yieldMinCopper = minCopper and ((minCopper * buyCount) / effectiveShards) or nil
            local yieldMedianCopper = medianCopper and ((medianCopper * buyCount) / effectiveShards) or nil
            local yieldMin = minGold and ((minGold * buyCount) / effectiveShards) or nil
            local yieldMedian = medianGold and ((medianGold * buyCount) / effectiveShards) or nil

            local entry = {
                id = item.id,
                name = item.name,
                category = catName,
                cost = cost,
                count = buyCount,
                costType = costType,
                effectiveShards = effectiveShards,
                minCopper = minCopper,
                medianCopper = medianCopper,
                minGold = minGold,
                medianGold = medianGold,
                yieldMin = yieldMin,
                yieldMedian = yieldMedian,
                yieldMinCopper = yieldMinCopper,
                yieldMedianCopper = yieldMedianCopper,
            }

            table.insert(processedList, entry)

            local catBest = categoryBestMap[catName]
            if yieldMinCopper and (not catBest.bestMin or yieldMinCopper > catBest.bestMin.yieldMinCopper) then
                catBest.bestMin = entry
            end
            if yieldMedianCopper and (not catBest.bestMedian or yieldMedianCopper > catBest.bestMedian.yieldMedianCopper) then
                catBest.bestMedian = entry
            end

            if yieldMinCopper and (not globalBestMin or yieldMinCopper > globalBestMin.yieldMinCopper) then
                globalBestMin = entry
            end
            if yieldMedianCopper and (not globalBestMedian or yieldMedianCopper > globalBestMedian.yieldMedianCopper) then
                globalBestMedian = entry
            end
        end
    end

    if latestScanTime == 0 then
        local db = GetEasyAuctionDB()
        local fallbackT = GetLatestScanTimeFromDB(db)
        if fallbackT and fallbackT > 0 then
            latestScanTime = fallbackT
        end
    end
    TG.latestScanTime = (latestScanTime > 0) and latestScanTime or nil
end

local function GetFilteredAndSortedList()
    local filtered = {}
    for _, it in ipairs(processedList) do
        if selectedCategoryKey == "ALL" or it.category == selectedCategoryKey then
            table.insert(filtered, it)
        end
    end

    table.sort(filtered, function(a, b)
        local valA = a[sortColumn]
        local valB = b[sortColumn]

        if valA == nil and valB ~= nil then return false end
        if valA ~= nil and valB == nil then return true end
        if valA == nil and valB == nil then return a.id < b.id end

        if valA ~= valB then
            if sortAsc then
                return valA < valB
            else
                return valA > valB
            end
        end
        return a.id < b.id
    end)

    return filtered
end

-- ----------------------------------------------------------------------------
-- 3. UI 主界面创建与精确坐标渲染
-- ----------------------------------------------------------------------------

local mainFrame = nil
local rowPool = {}

-- 列相对坐标布局
local COL_LAYOUT = {
    showMedian = {
        name = { x = 6, w = 170 },
        cost = { x = 180, w = 80 },
        minPrice = { x = 265, w = 90 },
        medianPrice = { x = 360, w = 90 },
        yieldMin = { x = 455, w = 95 },
        yieldMedian = { x = 555, w = 95 },
        badge = { x = 655, w = 125 },
    },
    hideMedian = {
        name = { x = 6, w = 210 },
        cost = { x = 225, w = 95 },
        minPrice = { x = 330, w = 110 },
        yieldMin = { x = 450, w = 140 },
        badge = { x = 600, w = 180 },
    }
}

local function CreateBackdrop(f)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.88)
    f:SetBackdropBorderColor(0.2, 0.6, 0.9, 0.8)
end

function TG.CreateMainFrame(parent)
    if mainFrame then return mainFrame end
    parent = parent or BG.MainFrame

    local f = CreateFrame("Frame", "BGTitanGoblinMainFrame", parent, "BackdropTemplate")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -30)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 35)
    CreateBackdrop(f)
    f:Hide()
    BG.TitanGoblinMainFrame = f

    -- 1. 顶部状态与估值卡片区 (高 92px，间距彻底拉开，网格规整对称)
    local topBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    topBar:SetPoint("TOPLEFT", 8, -8)
    topBar:SetPoint("TOPRIGHT", -8, -8)
    topBar:SetHeight(92)
    topBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    topBar:SetBackdropColor(0.06, 0.07, 0.10, 0.85)
    topBar:SetBackdropBorderColor(0.25, 0.35, 0.45, 0.6)
    f.topBar = topBar

    -- 第一行 (Y = -10)：左侧标题 -> 【点击扫描】黄颜色按钮 -> 扫描时间戳展示，右侧刷新与控制开关
    local titleText = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetText("|cff00FFFF【碎片统计】|r |cffFFD100泰坦代币物资兑换与收益排行|r")

    -- 黄颜色【点击扫描】实体按钮（紧贴标题右侧，圆润精致魔兽金黄风格）
    local scanAHBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    scanAHBtn:SetSize(84, 22)
    scanAHBtn:SetPoint("LEFT", titleText, "RIGHT", 14, 0)
    scanAHBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    scanAHBtn:SetBackdropColor(0.32, 0.24, 0.05, 0.95)
    scanAHBtn:SetBackdropBorderColor(1, 0.82, 0, 1)

    local scanAHText = scanAHBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanAHText:SetPoint("CENTER", 0, 0)
    scanAHText:SetText("|cffFFD100点击扫描|r")
    scanAHBtn.text = scanAHText

    local scanAHHl = scanAHBtn:CreateTexture(nil, "HIGHLIGHT")
    scanAHHl:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    scanAHHl:SetTexCoord(0, 0.625, 0, 0.6875)
    scanAHHl:SetAllPoints()
    scanAHHl:SetBlendMode("ADD")

    scanAHBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.52, 0.40, 0.08, 0.98)
        self:SetBackdropBorderColor(1, 0.96, 0.4, 1)
        scanAHText:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("EasyAuction 快速扫描", 1, 0.82, 0)
        GameTooltip:AddLine("点击调用 EasyAuction 插件启动全量行情扫描。", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("【使用条件】", 0, 1, 1)
        GameTooltip:AddLine("请先前往各大主城拍卖行，与【拍卖师】对话打开拍卖界面后，点击此按钮即可一键开始全量扫描！\n扫描完成后返回本界面即可更新呈现最新收益与排行。", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scanAHBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.32, 0.24, 0.05, 0.95)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        scanAHText:SetTextColor(1, 0.82, 0)
        GameTooltip:Hide()
    end)

    scanAHBtn:SetScript("OnClick", function(self)
        if BG.PlaySound then
            BG.PlaySound(1)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end

        local status = TG.CheckEasyAuctionStatus and TG.CheckEasyAuctionStatus()
        if status == "NOT_INSTALLED" then
            local msg = "|cffFF4500[碎片统计]|r 未检测到 EasyAuction 插件，请先启用 EasyAuction！"
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(msg, 1.0, 0.2, 0.2, 1.0, 3)
            end
            return
        end

        local isAuctionOpen = (_G.AuctionFrame and _G.AuctionFrame:IsShown()) or (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown())
        if not isAuctionOpen then
            local msg = "|cffFFD100[碎片统计]|r 请先前往主城拍卖行与【拍卖师】对话打开拍卖界面，然后再点击扫描！"
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("请先与拍卖师对话打开拍卖界面！", 1.0, 0.82, 0.0, 1.0, 3)
            end
            return
        end

        if type(_G.EasyAuction_ScanAllAuctionItems) == "function" then
            _G.EasyAuction_ScanAllAuctionItems()
            local msg = "|cff00FF00[碎片统计]|r 已启动 EasyAuction 全量扫描，请等待扫描进度完成..."
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(msg, 0.0, 1.0, 0.0, 1.0, 3)
            end
        elseif type(_G.EasyAuction_Scan) == "function" then
            _G.EasyAuction_Scan()
            local msg = "|cff00FF00[碎片统计]|r 已启动 EasyAuction 扫描..."
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        else
            local msg = "|cffFFD100[碎片统计]|r 请在拍卖行界面右上角点击 EasyAuction 的【扫描】按钮开始采集！"
            DEFAULT_CHAT_FRAME:AddMessage(msg)
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0, 3)
            end
        end
    end)
    f.scanAHBtn = scanAHBtn

    -- Easy 扫描时间戳展示按钮（紧随【点击扫描】按钮右侧，自由向右延伸，永不重叠）
    local scanTimeBtn = CreateFrame("Button", nil, topBar)
    scanTimeBtn:SetPoint("LEFT", scanAHBtn, "RIGHT", 10, 0)
    scanTimeBtn:SetHeight(22)
    local scanTimeText = scanTimeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanTimeText:SetPoint("LEFT", 0, 0)
    scanTimeText:SetWordWrap(false)
    f.scanTimeText = scanTimeText
    f.scanTimeBtn = scanTimeBtn

    local function RefreshScanTimeDisplay()
        local scanT = TG.GetEasyAuctionScanTime and TG.GetEasyAuctionScanTime()
        if scanT and scanT > 0 then
            scanTimeText:SetText(string.format("|cff808080Easy扫描时间:|r %s", FormatScanTime(scanT)))
        else
            local status = TG.CheckEasyAuctionStatus and TG.CheckEasyAuctionStatus()
            if status == "NOT_INSTALLED" then
                scanTimeText:SetText("|cffFF4500未检测到 EasyAuction 插件|r")
            elseif status == "NO_DATA" then
                scanTimeText:SetText("|cffFFA500Easy 暂无扫描数据(需去AH扫描)|r")
            else
                scanTimeText:SetText("|cff808080Easy扫描时间:|r |cffFFA500未知|r")
            end
        end
        local textW = scanTimeText:GetStringWidth()
        scanTimeBtn:SetWidth(math.max(140, (textW or 0) + 6))
    end
    TG.RefreshScanTimeDisplay = RefreshScanTimeDisplay
    RefreshScanTimeDisplay()

    scanTimeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("EasyAuction 拍卖行行情数据", 0, 1, 1)
        local scanT = TG.GetEasyAuctionScanTime and TG.GetEasyAuctionScanTime()
        if scanT and scanT > 0 then
            GameTooltip:AddLine(string.format("Easy 扫描时间: |cffffffff%s|r", date("%Y-%m-%d %H:%M:%S", scanT)), 1, 0.82, 0)
        else
            local status = TG.CheckEasyAuctionStatus and TG.CheckEasyAuctionStatus()
            if status == "NOT_INSTALLED" then
                GameTooltip:AddLine("|cffFF4500未检测到 EasyAuction 插件！|r", 1, 0.3, 0.3)
            elseif status == "NO_DATA" then
                GameTooltip:AddLine("|cffFFA500EasyAuction 暂无行情，需先前往拍卖行扫描|r", 1, 0.8, 0)
            else
                GameTooltip:AddLine("Easy 扫描时间: |cffaaaaaa暂无记录|r", 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("【说明】", 1, 0.82, 0)
        GameTooltip:AddLine("本时间为 EasyAuction 插件在拍卖行执行全量扫描的真实时刻。\n如需更新价格，请前往各大主城拍卖行，与拍卖师对话后点击左侧黄色【点击扫描】按钮，采集最新数据后返回本界面即可！", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scanTimeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local showMedianCheck = CreateFrame("CheckButton", "BGTitanGoblinShowMedianCheck", topBar, "UICheckButtonTemplate")
    showMedianCheck:SetSize(20, 20)
    showMedianCheck:SetPoint("TOPRIGHT", -116, -9)
    local checkLabel = showMedianCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkLabel:SetPoint("LEFT", showMedianCheck, "RIGHT", 2, 0)
    checkLabel:SetText("显示中位数分析")
    
    BiaoGe = BiaoGe or {}
    BiaoGe.options = BiaoGe.options or {}
    if BiaoGe.options.titanGoblinShowMedian == nil then
        BiaoGe.options.titanGoblinShowMedian = 1
    end
    showMedianCheck:SetChecked(BiaoGe.options.titanGoblinShowMedian == 1)
    showMedianCheck:SetScript("OnClick", function(self)
        BiaoGe.options.titanGoblinShowMedian = self:GetChecked() and 1 or 0
        TG.UpdateTableLayout()
        if TG.hasCalculated then
            TG.RefreshList()
        end
    end)
    f.showMedianCheck = showMedianCheck

    -- 第二行 (Y = -38)：左侧全服最低价冠军，右侧代币持有
    local bestMinCard = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bestMinCard:SetPoint("TOPLEFT", 12, -38)
    bestMinCard:SetWidth(390)
    bestMinCard:SetJustifyH("LEFT")
    bestMinCard:SetWordWrap(false)
    bestMinCard:SetText(string.format("%s |cff00FF00[全服最低价冠军]|r: |cff808080点击开始计算行情|r", ICON_CROWN))
    f.bestMinCard = bestMinCard

    local tokenText = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tokenText:SetPoint("TOPLEFT", 410, -38)
    tokenText:SetJustifyH("LEFT")
    tokenText:SetWordWrap(false)
    f.tokenText = tokenText

    -- 代币持有说明问号按钮
    local tokenHelpBtn = CreateFrame("Button", nil, topBar)
    tokenHelpBtn:SetSize(16, 16)
    tokenHelpBtn:SetPoint("LEFT", tokenText, "RIGHT", 4, 0)
    local helpTex = tokenHelpBtn:CreateTexture(nil, "ARTWORK")
    helpTex:SetAllPoints()
    helpTex:SetTexture(616343)
    tokenHelpBtn:SetHighlightTexture(616343)

    tokenHelpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine("泰坦代币变现与行情风险提示", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("【有价无市风险】", 1, 0.4, 0.4)
        GameTooltip:AddLine("部分兑换物品（特别是等级较低或冷门的材料、配方）虽然拍卖行挂牌出价较高，但可能无人接盘购买，存在【有价无市】的风险。", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("【拍卖行数据局限】", 0.4, 0.8, 1)
        GameTooltip:AddLine("受暴雪官方接口机制限制，客户端仅能扫描到货架当前的挂牌价与一口价，无法获取拍卖行历史实际销售流水与周转流速数据。", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("【地精兑换建议】", 0, 1, 0)
        GameTooltip:AddLine("建议优先兑换当前版本热门主流消耗品（如高频流通的合剂药水原材料、常用顶级附魔等刚需物资），变现速度最快、收益最稳健！", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tokenHelpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.tokenHelpBtn = tokenHelpBtn

    -- 第三行 (Y = -64)：左侧全服中位价冠军，右侧地精身价资产分析
    local bestMedCard = topBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bestMedCard:SetPoint("TOPLEFT", 12, -64)
    bestMedCard:SetWidth(390)
    bestMedCard:SetJustifyH("LEFT")
    bestMedCard:SetWordWrap(false)
    bestMedCard:SetText(string.format("%s |cff00BFFF[全服中位价冠军]|r: |cff808080点击开始计算行情|r", ICON_TROPHY))
    f.bestMedCard = bestMedCard

    local wealthText = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wealthText:SetPoint("TOPLEFT", 410, -64)
    wealthText:SetPoint("RIGHT", topBar, "RIGHT", -12, 0)
    wealthText:SetJustifyH("LEFT")
    wealthText:SetWordWrap(false)
    f.wealthText = wealthText

    -- 2. 左侧分类导航栏 (高质感专业图标)
    local leftNav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftNav:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -6)
    leftNav:SetPoint("BOTTOMLEFT", 8, 8)
    leftNav:SetWidth(135)
    leftNav:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    leftNav:SetBackdropColor(0.04, 0.05, 0.07, 0.7)
    leftNav:SetBackdropBorderColor(0.2, 0.3, 0.4, 0.5)
    f.leftNav = leftNav

    local catButtons = {}
    for idx, item in ipairs(CATEGORIES) do
        local btn = CreateFrame("Button", nil, leftNav, "UIPanelButtonTemplate")
        btn:SetSize(123, 30)
        btn:SetPoint("TOPLEFT", 6, -8 - (idx - 1) * 34)
        btn:SetText(item.text)
        btn:SetScript("OnClick", function()
            selectedCategoryKey = item.key
            for _, b in ipairs(catButtons) do b:UnlockHighlight() end
            btn:LockHighlight()
            if f.scroll then
                f.scroll:SetVerticalScroll(0)
            end
            if TG.hasCalculated then
                TG.RefreshList()
            end
        end)
        catButtons[idx] = btn
    end
    catButtons[1]:LockHighlight()
    f.catButtons = catButtons

    -- 3. 右侧表头栏 (Header)
    local headerBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", leftNav, "TOPRIGHT", 8, 0)
    headerBar:SetPoint("TOPRIGHT", -8, -100)
    headerBar:SetHeight(28)
    headerBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    headerBar:SetBackdropColor(0.08, 0.10, 0.14, 0.9)
    headerBar:SetBackdropBorderColor(0.3, 0.4, 0.5, 0.8)
    f.headerBar = headerBar

    local headerList = {}
    local function CreateHeaderCol(rawTitle, sortKey, justifyH)
        local btn = CreateFrame("Button", nil, headerBar)
        btn:SetHeight(26)
        btn.rawTitle = rawTitle
        btn.sortKey = sortKey
        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint(justifyH or "CENTER", 0, 0)
        t:SetText(rawTitle)
        btn.text = t
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        if sortKey then
            btn:SetScript("OnClick", function()
                if sortColumn == sortKey then
                    sortAsc = not sortAsc
                else
                    sortColumn = sortKey
                    sortAsc = false
                end
                TG.UpdateHeaderSortIndicators()
                if TG.hasCalculated then
                    TG.RefreshList()
                end
            end)
        end
        table.insert(headerList, btn)
        return btn
    end

    function TG.UpdateHeaderSortIndicators()
        for _, btn in ipairs(headerList) do
            if btn.sortKey then
                if sortColumn == btn.sortKey then
                    local arrow = sortAsc and " ^" or " v"
                    btn.text:SetText(string.format("|cffFFD100%s%s|r", btn.rawTitle, arrow))
                else
                    btn.text:SetText(btn.rawTitle)
                end
            else
                btn.text:SetText(btn.rawTitle)
            end
        end
    end

    f.headers = {
        name = CreateHeaderCol("物资名称 (Item)", nil, "LEFT"),
        cost = CreateHeaderCol("兑换消耗", "cost"),
        minPrice = CreateHeaderCol("AH最低价", "minCopper"),
        medianPrice = CreateHeaderCol("AH中位数", "medianCopper"),
        yieldMin = CreateHeaderCol("最低单片收益", "yieldMinCopper"),
        yieldMedian = CreateHeaderCol("中位单片收益", "yieldMedianCopper"),
        badge = CreateHeaderCol("行情推荐", nil),
    }

    -- 4. 滚动列表视口 (ScrollFrame)
    local scroll = CreateFrame("ScrollFrame", "BGTitanGoblinScrollFrame", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(scroll:GetWidth(), 10)
    scroll:SetScrollChild(content)
    f.content = content
    f.scroll = scroll

    function TG.UpdateTableLayout()
        local showMedian = (BiaoGe.options.titanGoblinShowMedian == 1)
        local layout = showMedian and COL_LAYOUT.showMedian or COL_LAYOUT.hideMedian
        local headers = f.headers

        headers.name:ClearAllPoints()
        headers.name:SetPoint("LEFT", headerBar, "LEFT", layout.name.x, 0)
        headers.name:SetWidth(layout.name.w)

        headers.cost:ClearAllPoints()
        headers.cost:SetPoint("LEFT", headerBar, "LEFT", layout.cost.x, 0)
        headers.cost:SetWidth(layout.cost.w)

        headers.minPrice:ClearAllPoints()
        headers.minPrice:SetPoint("LEFT", headerBar, "LEFT", layout.minPrice.x, 0)
        headers.minPrice:SetWidth(layout.minPrice.w)

        headers.medianPrice:SetShown(showMedian)
        if showMedian then
            headers.medianPrice:ClearAllPoints()
            headers.medianPrice:SetPoint("LEFT", headerBar, "LEFT", layout.medianPrice.x, 0)
            headers.medianPrice:SetWidth(layout.medianPrice.w)
        end

        headers.yieldMin:ClearAllPoints()
        headers.yieldMin:SetPoint("LEFT", headerBar, "LEFT", layout.yieldMin.x, 0)
        headers.yieldMin:SetWidth(layout.yieldMin.w)

        headers.yieldMedian:SetShown(showMedian)
        if showMedian then
            headers.yieldMedian:ClearAllPoints()
            headers.yieldMedian:SetPoint("LEFT", headerBar, "LEFT", layout.yieldMedian.x, 0)
            headers.yieldMedian:SetWidth(layout.yieldMedian.w)
        end

        headers.badge:ClearAllPoints()
        headers.badge:SetPoint("LEFT", headerBar, "LEFT", layout.badge.x, 0)
        headers.badge:SetWidth(layout.badge.w)
    end

    -- 5. 按需渲染启动引导区 (未点击前不计算 175 件物资，彻底解决打开 Tab 卡顿)
    local startOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
    startOverlay:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
    startOverlay:SetPoint("BOTTOMRIGHT", -28, 10)
    startOverlay:SetFrameLevel(scroll:GetFrameLevel() + 5)
    startOverlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    startOverlay:SetBackdropColor(0.04, 0.05, 0.07, 0.94)
    startOverlay:SetBackdropBorderColor(0.2, 0.4, 0.6, 0.8)
    f.startOverlay = startOverlay

    local overlayIcon = startOverlay:CreateTexture(nil, "ARTWORK")
    overlayIcon:SetSize(44, 44)
    overlayIcon:SetPoint("CENTER", startOverlay, "CENTER", 0, 52)
    overlayIcon:SetTexture("Interface\\Icons\\INV_Jewelry_Trophy_01")
    startOverlay.icon = overlayIcon

    local overlayTitle = startOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overlayTitle:SetPoint("TOP", overlayIcon, "BOTTOM", 0, -8)
    overlayTitle:SetText("|cff00FFFF【碎片统计】泰坦代币收益分析引擎|r")
    startOverlay.title = overlayTitle

    local bigStartBtn = CreateFrame("Button", nil, startOverlay, "UIPanelButtonTemplate")
    bigStartBtn:SetSize(220, 36)
    bigStartBtn:SetPoint("TOP", overlayTitle, "BOTTOM", 0, -14)
    bigStartBtn:SetText("|cff00FF00开始计算收益排行|r")
    startOverlay.bigStartBtn = bigStartBtn

    local overlayTip = startOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    overlayTip:SetPoint("TOP", bigStartBtn, "BOTTOM", 0, -10)
    overlayTip:SetText("|cff808080点击开始按需分析 175+ 件物资并读取 EasyAuction 拍卖数据\n（按需手动启动，彻底消除切 Tab 时造成的界面卡顿）|r")
    overlayTip:SetJustifyH("CENTER")
    overlayTip:SetSpacing(4)
    startOverlay.tip = overlayTip

    function TG.UpdateStartOverlay()
        if not f.startOverlay then return end
        local status, db = TG.CheckEasyAuctionStatus()

        if status == "NOT_INSTALLED" then
            startOverlay.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
            startOverlay.title:SetText("|cffFF4500未检测到 EasyAuction 拍卖行插件|r")
            startOverlay.tip:SetText("|cffFFD100【碎片统计】仅支持深度联动 EasyAuction 拍卖行数据|r\n\n|cffFFFFFF检测到您当前尚未安装或未启用 EasyAuction 插件。\n请在大脚/网易有爱等插件管理器中启用【EasyAuction】并重载游戏，\n随后前往拍卖行进行一次行情扫描即可使用本功能！|r")
            startOverlay.bigStartBtn:SetText("|cff888888未检测到 EasyAuction 插件|r")
            if f.scanTimeText then
                f.scanTimeText:SetText("|cffFF4500[未检测到 EasyAuction 插件]|r")
            end
        elseif status == "NO_DATA" then
            startOverlay.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
            startOverlay.title:SetText("|cffFFA500EasyAuction 暂无拍卖行情数据|r")
            startOverlay.tip:SetText("|cffFFFFFF已检测到 EasyAuction 插件，但当前服务器/阵营尚未采集过行情数据。\n\n请前往各大主城拍卖行，与拍卖师对话打开拍卖界面，\n点击右上角的【扫描全部】按钮采集最新行情。\n扫描完成后返回此处点击开始即可！|r")
            startOverlay.bigStartBtn:SetText("|cffFFA500尝试加载 EasyAuction 行情|r")
            if f.scanTimeText then
                f.scanTimeText:SetText("|cffFFA500[EasyAuction 暂无行情，需先去拍卖行扫描]|r")
            end
        else
            startOverlay.icon:SetTexture("Interface\\Icons\\INV_Jewelry_Trophy_01")
            startOverlay.title:SetText("|cff00FFFF【碎片统计】泰坦代币收益分析引擎|r")
            local scanT = TG.GetEasyAuctionScanTime and TG.GetEasyAuctionScanTime()
            local scanStr = scanT and FormatScanTime(scanT) or "|cffFFA500未知|r"
            startOverlay.tip:SetText(string.format("|cff808080已就绪！EasyAuction 扫描行情时间: %s\n点击开始按需分析 175+ 件物资泰坦代币收益（0ms 顺滑秒开无顿卡）|r", scanStr))
            startOverlay.bigStartBtn:SetText("|cff00FF00开始计算收益排行|r")
            if f.scanTimeText and scanT then
                f.scanTimeText:SetText(string.format("|cff808080Easy扫描时间:|r %s", FormatScanTime(scanT)))
            end
        end
    end

    function TG.StartCalculation()
        local status, db = TG.CheckEasyAuctionStatus()
        if status == "NOT_INSTALLED" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffFF4500[碎片统计 警告]|r 未检测到 EasyAuction 拍卖行插件！本功能仅支持联动 EasyAuction 数据，请先在插件列表中启用 EasyAuction 并重载游戏。")
            TG.UpdateStartOverlay()
            return
        elseif status == "NO_DATA" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFA500[碎片统计 提示]|r EasyAuction 暂无行情数据，请先前往主城拍卖行点击【扫描全部】采集数据后再试。")
            TG.UpdateStartOverlay()
            return
        end

        TG.hasCalculated = true
        if f.startOverlay then f.startOverlay:Hide() end
        TG.CalculateAllData()
        TG.UpdateHeaderSortIndicators()
        TG.RefreshList()
        TG.UpdateTokensDisplay()

        local scanT = TG.GetEasyAuctionScanTime and TG.GetEasyAuctionScanTime()
        if f.scanTimeText and scanT then
            f.scanTimeText:SetText(string.format("|cff808080Easy扫描时间:|r %s", FormatScanTime(scanT)))
        end

        local scanInfo = scanT and FormatScanTime(scanT) or "最新"
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00FFFF[碎片统计]|r 计算完成！已呈现 175+ 件时光服物资收益排行 (Easy 扫描时间: %s)。", scanInfo))
    end

    bigStartBtn:SetScript("OnClick", function()
        TG.StartCalculation()
    end)

    TG.UpdateTableLayout()
    TG.UpdateHeaderSortIndicators()

    -- 物品信息异步加载监听：首次 GetItemInfo 可能未缓存，图标/名称为空
    -- 监听 GET_ITEM_INFO_RECEIVED 事件，物品数据到达后防抖自动刷新列表
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self, event, itemID, success)
        if event == "GET_ITEM_INFO_RECEIVED" and TG.hasCalculated and self:IsShown() then
            if TG._refreshTimer then
                TG._refreshTimer:Cancel()
            end
            TG._refreshTimer = C_Timer.NewTimer(0.2, function()
                TG._refreshTimer = nil
                if TG.hasCalculated and mainFrame and mainFrame:IsShown() then
                    TG.RefreshList()
                end
            end)
        end
    end)

    -- 切换 Tab 生命周期 (仅更新极轻量代币与状态，杜绝重复计算卡顿)
    f:SetScript("OnShow", function(self)
        if BG.FrameHide then BG.FrameHide(0) end
        if BG.FBMainFrame then BG.FBMainFrame:Hide() end
        if BG.ItemLibMainFrame then BG.ItemLibMainFrame:Hide() end
        if BG.HopeMainFrame then BG.HopeMainFrame:Hide() end
        if BG.DuiZhangMainFrame then BG.DuiZhangMainFrame:Hide() end
        if BG.TradeHistoryMainFrame then BG.TradeHistoryMainFrame:Hide() end
        if BG.AuctionPresetMainFrame then BG.AuctionPresetMainFrame:Hide() end
        if BG.TabButtonsFB then BG.TabButtonsFB:Hide() end

        TG.UpdateTokensDisplay()
        if TG.RefreshScanTimeDisplay then
            TG.RefreshScanTimeDisplay()
        end
        if TG.hasCalculated then
            -- 已经计算过：只做轻量状态维护，绝对不重跑全量计算或重绘，实现 0ms 顺滑切 Tab
            TG.UpdateHeaderSortIndicators()
            if self.startOverlay then self.startOverlay:Hide() end
        else
            -- 首次打开：展示居中开始引导遮罩，等待玩家点击开始按钮
            if self.startOverlay then
                self.startOverlay:Show()
                TG.UpdateStartOverlay()
            end
        end
        if BiaoGe then BiaoGe.lastFrame = "TitanGoblin" end
    end)

    -- 注册底部 Tab 栏
    if BG.Create_TabButton and not BG.ButtonTabTitanGoblin then
        local tabBtn = BG.Create_TabButton(BG.TitanGoblinMainFrameTabNum, L["碎片统计"] or "碎片统计", f, 90)
        BG.ButtonTabTitanGoblin = tabBtn
        TG.tabBtn = tabBtn
        if BG.OnEnterDelay then
            BG.OnEnterDelay(tabBtn, function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["< 碎片统计 >"] or "< 碎片统计 >", 1, 1, 1, true)
                GameTooltip:AddLine(L["泰坦碎片与余烬物资兑换行情与各专业收益排行。"] or "泰坦碎片与余烬物资兑换行情与各专业收益排行。", 1, 0.82, 0, true)
                GameTooltip:Show()
            end, 0.5, true)
        end
    end

    mainFrame = f
    return mainFrame
end

-- 更新代币持有量与身价估值
function TG.UpdateTokensDisplay()
    if not mainFrame then return end

    local shardCount = 0
    local emberCount = 0

    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local sInfo = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_SHARD)
        if sInfo and sInfo.quantity then shardCount = sInfo.quantity end
        local eInfo = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_EMBER)
        if eInfo and eInfo.quantity then emberCount = eInfo.quantity end
    elseif GetCurrencyInfo then
        local _, sQty = GetCurrencyInfo(CURRENCY_SHARD)
        local _, eQty = GetCurrencyInfo(CURRENCY_EMBER)
        shardCount = tonumber(sQty) or 0
        emberCount = tonumber(eQty) or 0
    end

    local totalEquivalentShards = shardCount + (emberCount * EMBER_TO_SHARD_RATIO)
    local playerCopper = GetMoney()

    mainFrame.tokenText:SetText(string.format("代币持有：%s |cff00BFFF碎片: %d|r  |  %s |cffFF8000余烬: %d|r (合计: |cff00FF00%d|r 碎片)",
        ICON_SHARD, shardCount, ICON_EMBER, emberCount, totalEquivalentShards))

    if mainFrame.tokenHelpBtn and mainFrame.tokenText then
        mainFrame.tokenHelpBtn:ClearAllPoints()
        local textW = mainFrame.tokenText:GetStringWidth()
        if textW and textW > 0 then
            mainFrame.tokenHelpBtn:SetPoint("LEFT", mainFrame.tokenText, "LEFT", textW + 6, 0)
        else
            mainFrame.tokenHelpBtn:SetPoint("LEFT", mainFrame.tokenText, "RIGHT", 6, 0)
        end
    end

    local bestYieldCopper = (globalBestMin and globalBestMin.yieldMinCopper) or (globalBestMedian and globalBestMedian.yieldMedianCopper) or 0
    if bestYieldCopper > 0 and totalEquivalentShards > 0 then
        local estimatedTokenCopper = math.floor(totalEquivalentShards * bestYieldCopper)
        local totalNetWorthCopper = playerCopper + estimatedTokenCopper
        mainFrame.wealthText:SetText(string.format("%s |cffFFD700地精身价|r: 现金 %s + 碎片变现约 %s = 预估身价 %s！",
            ICON_COIN, FormatCopperToText(playerCopper), FormatCopperToText(estimatedTokenCopper), FormatCopperToText(totalNetWorthCopper)))
    else
        local hint = TG.hasCalculated and "扫描拍卖行后自动计算代币可变现金币" or "点击【开始计算行情】后评估"
        mainFrame.wealthText:SetText(string.format("%s |cffFFD700地精身价|r: 现金 %s (%s)",
            ICON_COIN, FormatCopperToText(playerCopper), hint))
    end
end

-- 刷新列表行渲染
function TG.RefreshList()
    if not mainFrame or not mainFrame:IsShown() then return end
    if not TG.hasCalculated then return end

    TG.UpdateTokensDisplay()
    local showMedian = (BiaoGe.options.titanGoblinShowMedian == 1)
    local layout = showMedian and COL_LAYOUT.showMedian or COL_LAYOUT.hideMedian
    local items = GetFilteredAndSortedList()

    -- 刷新顶部推荐卡片 (纯每个泰坦碎片收益，不使用余烬计算)
    if globalBestMin and globalBestMin.yieldMinCopper then
        mainFrame.bestMinCard:SetText(string.format("%s |cff00FF00[全服最低价冠军]|r: |cffFFD100%s|r  |cff808080(收益:|r %s|cff808080/片)|r",
            ICON_CROWN, globalBestMin.name, FormatCopperToText(globalBestMin.yieldMinCopper)))
    else
        mainFrame.bestMinCard:SetText(string.format("%s |cff00FF00[全服最低价冠军]|r: |cff808080暂无行情|r", ICON_CROWN))
    end

    if globalBestMedian and globalBestMedian.yieldMedianCopper then
        mainFrame.bestMedCard:SetText(string.format("%s |cff00BFFF[全服中位价冠军]|r: |cffFFD100%s|r  |cff808080(收益:|r %s|cff808080/片)|r",
            ICON_TROPHY, globalBestMedian.name, FormatCopperToText(globalBestMedian.yieldMedianCopper)))
    else
        mainFrame.bestMedCard:SetText(string.format("%s |cff00BFFF[全服中位价冠军]|r: |cff808080暂无行情|r", ICON_TROPHY))
    end

    if mainFrame.scanTimeText and TG.latestScanTime then
        mainFrame.scanTimeText:SetText(string.format("|cff808080Easy扫描时间:|r %s", FormatScanTime(TG.latestScanTime)))
    end

    -- 隐藏旧行
    for _, row in ipairs(rowPool) do row:Hide() end

    local rowHeight = 30
    local contentWidth = mainFrame.content:GetWidth()

    for i, it in ipairs(items) do
        local row = rowPool[i]
        if not row then
            row = CreateFrame("Frame", nil, mainFrame.content, "BackdropTemplate")
            row:SetHeight(rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
            })

            -- 图标
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetPoint("LEFT", 4, 0)
            row.icon = icon

            -- 物品名称
            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            row.nameText = nameText

            -- 鼠标悬停原生 Tooltip
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if self.itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    if self.yieldMinCopper then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("【碎片统计 收益核算】", 0, 1, 1)
                        GameTooltip:AddLine(string.format("  最低单片收益: %s / 碎片", FormatCopperToText(self.yieldMinCopper)), 1, 0.82, 0)
                        if self.yieldMedianCopper then
                            GameTooltip:AddLine(string.format("  中位单片收益: %s / 碎片", FormatCopperToText(self.yieldMedianCopper)), 0.4, 0.8, 1)
                        end
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- 兑换消耗
            local costText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            costText:SetJustifyH("CENTER")
            costText:SetWordWrap(false)
            row.costText = costText

            -- AH 最低价
            local minPriceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            minPriceText:SetJustifyH("CENTER")
            minPriceText:SetWordWrap(false)
            row.minPriceText = minPriceText

            -- AH 中位数
            local medianText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            medianText:SetJustifyH("CENTER")
            medianText:SetWordWrap(false)
            row.medianText = medianText

            -- 最低单片收益
            local yieldMinText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            yieldMinText:SetJustifyH("CENTER")
            yieldMinText:SetWordWrap(false)
            row.yieldMinText = yieldMinText

            -- 中位单片收益
            local yieldMedText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            yieldMedText:SetJustifyH("CENTER")
            yieldMedText:SetWordWrap(false)
            row.yieldMedText = yieldMedText

            -- 推荐评级徽章
            local badgeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            badgeText:SetJustifyH("CENTER")
            badgeText:SetWordWrap(false)
            row.badgeText = badgeText

            rowPool[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -(i - 1) * (rowHeight + 2))
        row:SetWidth(contentWidth)
        row.itemID = it.id
        row.yieldMinCopper = it.yieldMinCopper
        row.yieldMedianCopper = it.yieldMedianCopper

        if i % 2 == 0 then
            row:SetBackdropColor(0.06, 0.07, 0.10, 0.6)
        else
            row:SetBackdropColor(0.03, 0.04, 0.06, 0.35)
        end

        local _, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(it.id)
        row.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local _, _, _, hex = GetItemQualityColor(itemQuality or 1)
        row.nameText:SetText(string.format("|c%s%s|r", hex or "ffffffff", it.name or ("物品 " .. it.id)))

        local tokenIcon = (it.costType == CURRENCY_EMBER) and ICON_EMBER or ICON_SHARD
        local tokenName = (it.costType == CURRENCY_EMBER) and "|cffFF8000余烬|r" or "|cff00BFFF碎片|r"
        row.costText:SetText(string.format("%s %d %s", tokenIcon, it.cost, tokenName))

        row.minPriceText:SetText(FormatCopperToText(it.minCopper))
        row.medianText:SetText(FormatCopperToText(it.medianCopper))

        if it.yieldMinCopper then
            row.yieldMinText:SetText(string.format("%s|cff808080/片|r", FormatCopperToText(it.yieldMinCopper)))
        else
            row.yieldMinText:SetText("|cff666666-|r")
        end

        if it.yieldMedianCopper then
            row.yieldMedText:SetText(string.format("%s|cff808080/片|r", FormatCopperToText(it.yieldMedianCopper)))
        else
            row.yieldMedText:SetText("|cff666666-|r")
        end

        -- 勋章评级 (带暴雪原生高光金星/皇冠/金奖杯)
        local isGlobalMinBest = (globalBestMin and globalBestMin.id == it.id)
        local isGlobalMedBest = (globalBestMedian and globalBestMedian.id == it.id)
        local catBest = categoryBestMap[it.category]
        local isCatMinBest = (catBest and catBest.bestMin and catBest.bestMin.id == it.id)
        local isCatMedBest = (catBest and catBest.bestMedian and catBest.bestMedian.id == it.id)

        if isGlobalMinBest and isGlobalMedBest then
            row.badgeText:SetText(ICON_CROWN .. " |cffFFD700双冠冠军|r")
        elseif isGlobalMinBest then
            row.badgeText:SetText(ICON_CROWN .. " |cff00FF00最低价冠军|r")
        elseif isGlobalMedBest then
            row.badgeText:SetText(ICON_TROPHY .. " |cff00BFFF中位价冠军|r")
        elseif isCatMinBest and isCatMedBest then
            row.badgeText:SetText(ICON_STAR .. " |cffFFFF00组内双优|r")
        elseif isCatMinBest then
            row.badgeText:SetText(ICON_STAR .. " |cff7CFC00最低价推荐|r")
        elseif isCatMedBest then
            row.badgeText:SetText(ICON_STAR .. " |cff87CEFA中位价推荐|r")
        else
            row.badgeText:SetText("|cff808080普通|r")
        end

        -- 行内绝对 X 偏移对齐
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row, "LEFT", layout.name.x + 24, 0)
        row.nameText:SetWidth(layout.name.w - 24)

        row.costText:ClearAllPoints()
        row.costText:SetPoint("LEFT", row, "LEFT", layout.cost.x, 0)
        row.costText:SetWidth(layout.cost.w)

        row.minPriceText:ClearAllPoints()
        row.minPriceText:SetPoint("LEFT", row, "LEFT", layout.minPrice.x, 0)
        row.minPriceText:SetWidth(layout.minPrice.w)

        row.medianText:SetShown(showMedian)
        if showMedian then
            row.medianText:ClearAllPoints()
            row.medianText:SetPoint("LEFT", row, "LEFT", layout.medianPrice.x, 0)
            row.medianText:SetWidth(layout.medianPrice.w)
        end

        row.yieldMinText:ClearAllPoints()
        row.yieldMinText:SetPoint("LEFT", row, "LEFT", layout.yieldMin.x, 0)
        row.yieldMinText:SetWidth(layout.yieldMin.w)

        row.yieldMedText:SetShown(showMedian)
        if showMedian then
            row.yieldMedText:ClearAllPoints()
            row.yieldMedText:SetPoint("LEFT", row, "LEFT", layout.yieldMedian.x, 0)
            row.yieldMedText:SetWidth(layout.yieldMedian.w)
        end

        row.badgeText:ClearAllPoints()
        row.badgeText:SetPoint("LEFT", row, "LEFT", layout.badge.x, 0)
        row.badgeText:SetWidth(layout.badge.w)

        row:Show()
    end

    mainFrame.content:SetHeight(#items * (rowHeight + 2) + 20)
end

-- 快捷命令呼出
SLASH_TITANGOBLIN1 = "/tg"
SLASH_TITANGOBLIN2 = "/titangoblin"
SlashCmdList["TITANGOBLIN"] = function()
    if BG.MainFrame then
        if not BG.MainFrame:IsShown() then
            BG.MainFrame:Show()
        end
        if BG.ClickTabButton and BG.ButtonTabTitanGoblin then
            BG.ClickTabButton(BG.TitanGoblinMainFrameTabNum)
        end
    end
end