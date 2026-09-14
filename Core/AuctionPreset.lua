local AddonName, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RGB_16 = ns.RGB_16 or (BG and BG.RGB_16)
local GetClassRGB = ns.GetClassRGB or (BG and BG.GetClassRGB)
local GetItemID = ns.GetItemID or (BG and BG.GetItemID)

local AuctionPreset = {}
ns.AuctionPreset = AuctionPreset

BG.AuctionPresetMainFrameTabNum = BG.AuctionPresetMainFrameTabNum or 104

-- 辅助工具：超级健壮提取装备 ID（支持标准链接、纯数字、Token兑换物、带方括号名称及带装等后缀文本）
local function SafeGetItemID(text)
    if not text or text == "" then return nil end
    local str = tostring(text)

    -- 1. 标准 item:XXXX 链接匹配
    local id = str:match("item:(%d+)")
    if id then return tonumber(id) end

    -- 2. 纯数字 ID
    if tonumber(str) then return tonumber(str) end

    -- 3. 上游 BGLite GetItemID fallback
    if BG and BG.GetItemID then
        local bgId = BG.GetItemID(str)
        if bgId then return tonumber(bgId) end
    end

    -- 4. 彻底剥离颜色代码、方括号、前缀属性括号 (如 (板甲-腰部)(213) )、去除首尾空格后的纯名称解析
    local cleanName = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%[", ""):gsub("%]", "")
    cleanName = cleanName:gsub("%b()", ""):gsub("%b（）", "")
    cleanName = cleanName:gsub("^%s+", ""):gsub("%s+$", "")
    local nameWithoutLevel = cleanName:gsub("%s+%d+$", ""):gsub("^%s+", ""):gsub("%s+$", "")

    if cleanName ~= "" and GetItemInfoInstant then
        local id2 = GetItemInfoInstant(cleanName)
        if id2 then return tonumber(id2) end
        if nameWithoutLevel ~= "" and nameWithoutLevel ~= cleanName then
            local id2Sub = GetItemInfoInstant(nameWithoutLevel)
            if id2Sub then return tonumber(id2Sub) end
        end
    end

    if cleanName ~= "" and GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, id3 = GetItemInfo(cleanName)
        if id3 then return tonumber(id3) end
        if nameWithoutLevel ~= "" and nameWithoutLevel ~= cleanName then
            local _, _, _, _, _, _, _, _, _, _, _, _, _, _, id3Sub = GetItemInfo(nameWithoutLevel)
            if id3Sub then return tonumber(id3Sub) end
        end
    end

    return nil
end

-- 辅助工具：确保获得魔兽标准可用的装备超链接 (必须包含 |Hitem:)
local function SafeGetItemLink(rawText, itemID)
    if rawText and type(rawText) == "string" and rawText:find("|Hitem:") then
        return rawText
    end
    if itemID then
        local _, link = GetItemInfo(itemID)
        if link and link:find("|Hitem:") then return link end
    end
    return nil -- 关键：若无法获得标准超链接，必须返回 nil，绝不能返回纯文本字符串，防止接收端 Item:CreateFromItemLink 报废死锁
end

-- 辅助工具：精准识别套装兑换物 (Tier Token / 印记 / 奖章 / 兑换物)
local function IsTierTokenItem(itemID, FB)
    if not itemID then return false end
    local idNum = tonumber(itemID)
    if not idNum then return false end

    -- 1. 最权威数据源：上游 BGLite 原生维护的 ExchangeItems 数据库
    if BG and BG.Loot then
        if FB and BG.Loot[FB] and BG.Loot[FB].ExchangeItems and BG.Loot[FB].ExchangeItems[idNum] then
            return true
        end
        for fbKey, fbData in pairs(BG.Loot) do
            if type(fbData) == "table" and fbData.ExchangeItems and fbData.ExchangeItems[idNum] then
                return true
            end
        end
    end

    -- 2. 名字特征匹配（严格匹配套装代币专属模式，排除普通穿戴装备）
    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(idNum)
    if name then
        if name:find("失落的") or name:find("战败的") or name:find("征服者的")
           or name:find("保卫者的") or name:find("胜利者的")
           or name:find("圣洁勋服") or name:find("圣洁徽记")
           or name:find("北伐奖章") or name:find("十字军奖章")
           or name:find("印记") or name:find("代币") or name:find("兑换物") then
            if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then
                return true
            elseif name:find("失落的") or name:find("战败的") or name:find("征服者的") or name:find("保卫者的") or name:find("胜利者的") or name:find("印记") then
                return true
            end
        end
    end

    return false
end
ns.IsTierTokenItem = IsTierTokenItem

-- 全局读取预设价格与起拍语接口 (支持数字与字符串双类型键名，支持时光服别名互通与全副本兜底)
function BG.GetAuctionPreset(FB, itemID)
    if not itemID then return nil, nil end
    local numID = tonumber(itemID)
    local strID = tostring(itemID)

    if not BiaoGe or not BiaoGe.auctionPreset then return nil, nil end

    local function LookupInFBDb(fbName)
        if not fbName or not BiaoGe.auctionPreset[fbName] or not BiaoGe.auctionPreset[fbName].money then
            return nil, nil
        end
        local mDB = BiaoGe.auctionPreset[fbName].money
        local money = (numID and mDB[numID]) or mDB[strID]
        local tips = (numID and mDB[numID .. "tips"]) or mDB[strID .. "tips"]
        if money or tips then
            return money, tips
        end
        return nil, nil
    end

    -- 1. 优先在传入的当前活动副本中检索
    if FB then
        local m, t = LookupInFBDb(FB)
        if m or t then return m, t end
    end

    -- 2. 检查时光服/正式服对应别名 (如 TOC 与 TOCtitan 双向映射)
    if FB then
        local altFB = FB:find("titan") and (FB:gsub("titan", "")) or (FB .. "titan")
        local m, t = LookupInFBDb(altFB)
        if m or t then return m, t end
    end

    -- 3. 检查预设面板当前选中的副本 currentFB
    local curFB = BiaoGe.auctionPreset.currentFB
    if curFB and curFB ~= FB then
        local m, t = LookupInFBDb(curFB)
        if m or t then return m, t end
    end

    -- 4. 检查全局活跃副本 BG.FB2 与 BG.FB1
    if BG then
        if BG.FB2 and BG.FB2 ~= FB then
            local m, t = LookupInFBDb(BG.FB2)
            if m or t then return m, t end
        end
        if BG.FB1 and BG.FB1 ~= FB then
            local m, t = LookupInFBDb(BG.FB1)
            if m or t then return m, t end
        end
    end

    -- 5. 跨其他已知副本查找 fallback
    for _, fbName in ipairs(BG and BG.FBtable or {}) do
        if fbName ~= FB then
            local m, t = LookupInFBDb(fbName)
            if m or t then return m, t end
        end
    end

    -- 6. 全局字典遍历最终兜底
    for fbName, fbData in pairs(BiaoGe.auctionPreset) do
        if type(fbData) == "table" and fbData.money and fbName ~= FB then
            local m, t = LookupInFBDb(fbName)
            if m or t then return m, t end
        end
    end

    return nil, nil
end

function ns.InitAuctionPresetModule()
    if AuctionPreset.isInitialized then return end
    AuctionPreset.isInitialized = true

    BiaoGe = BiaoGe or {}
    BiaoGe.auctionPreset = BiaoGe.auctionPreset or {}
    BiaoGe.auctionPreset.currentFB = BiaoGe.auctionPreset.currentFB or (BG.FB1 or "MC")
    BiaoGe.auctionPreset.sortType = BiaoGe.auctionPreset.sortType or "level" -- level, quality, price
    BiaoGe.auctionPreset.sortAsc = BiaoGe.auctionPreset.sortAsc or false

    for _, FB in ipairs(BG.FBtable or {}) do
        BiaoGe.auctionPreset[FB] = BiaoGe.auctionPreset[FB] or {}
        BiaoGe.auctionPreset[FB].money = BiaoGe.auctionPreset[FB].money or {}
        BiaoGe.auctionPreset[FB].autoAuction = BiaoGe.auctionPreset[FB].autoAuction or {}
    end

    local currentFB = BiaoGe.auctionPreset.currentFB
    local currentItems = {}
    local filteredItems = {}
    local mainFrame
    local scrollFrame
    local contentFrame
    local rowFrames = {}
    local searchKeyword = ""
    local UpdateBottomTipCount
    local ApplyFilterAndSort
    local RefreshScrollView

    local ROW_HEIGHT = 26
    local MAX_ROWS = 32
    local VISIBLE_ROWS = 23

    local function UpdateVisibleRowCount()
        if contentFrame and contentFrame:GetHeight() and contentFrame:GetHeight() > 100 then
            local count = math.floor(contentFrame:GetHeight() / ROW_HEIGHT)
            if count > #rowFrames and #rowFrames > 0 then count = #rowFrames end
            if count < 10 then count = 10 end
            VISIBLE_ROWS = count
        end
        return VISIBLE_ROWS
    end

    -- 全局装备名称与属性缓存字典 (itemID -> { name, link, quality, level, texture })
    local itemInfoCache = {}

    -- 穿透式物品查询扫描 Tooltip（强力迫使底层游戏客户端向服务器发送物品查询数据包）
    local scanTip = CreateFrame("GameTooltip", "BGLitePresetScanTip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")

    -- 全局监听官方 GET_ITEM_INFO_RECEIVED 事件：只要服务器数据到达，自动回填缓存并防抖重绘
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local refreshTimer = nil
    eventFrame:SetScript("OnEvent", function(self, event, itemID, success)
        if not itemID then return end
        itemID = tonumber(itemID)
        if not itemID then return end

        local n, l, q, lvl, _, _, _, _, _, tex = GetItemInfo(itemID)
        if n and n ~= "" then
            itemInfoCache[itemID] = itemInfoCache[itemID] or {}
            itemInfoCache[itemID].name = n
            itemInfoCache[itemID].link = l
            itemInfoCache[itemID].quality = q or 1
            itemInfoCache[itemID].level = lvl or 0
            itemInfoCache[itemID].texture = tex
        end

        if mainFrame and mainFrame:IsShown() and RefreshScrollView then
            if not refreshTimer then
                refreshTimer = C_Timer.NewTimer(0.08, function()
                    refreshTimer = nil
                    if mainFrame and mainFrame:IsShown() and RefreshScrollView then
                        if searchKeyword and searchKeyword ~= "" and ApplyFilterAndSort then
                            ApplyFilterAndSort()
                        end
                        RefreshScrollView()
                    end
                end)
            end
        end
    end)

    -- 异步预热并缓存装备属性 (离线字典秒级预热 + Tooltip穿透 + 官方API三重并发)
    local function PreloadItemInfo(itemID, onLoaded)
        if not itemID then return end
        itemID = tonumber(itemID)
        if not itemID then return end

        -- 1. 优先从内存缓存中取（必须非虚构名称）
        if itemInfoCache[itemID] and itemInfoCache[itemID].name and (not itemInfoCache[itemID].name:find("^Item:")) then
            if onLoaded then onLoaded(itemInfoCache[itemID]) end
            return itemInfoCache[itemID]
        end

        -- 2. 离线数据库预热名称（彻底根除客户端首次登录或未缓存时无名字的致命缺陷）
        local dbName = ns.ItemNameDB and ns.ItemNameDB[itemID]
        if dbName then
            itemInfoCache[itemID] = itemInfoCache[itemID] or {}
            if not itemInfoCache[itemID].name or itemInfoCache[itemID].name:find("^Item:") then
                itemInfoCache[itemID].name = dbName
            end
        end

        -- 3. 实时查询游戏客户端官方 API
        local name, link, quality, level, _, _, _, _, _, texture = GetItemInfo(itemID)
        if name and name ~= "" then
            itemInfoCache[itemID] = {
                name = name,
                link = link,
                quality = quality or 1,
                level = level or 0,
                texture = texture,
            }
            if onLoaded then onLoaded(itemInfoCache[itemID]) end
            return itemInfoCache[itemID]
        end

        -- 4. 强制穿透式网络拉取：Tooltip + C_Item + OnItemLoad 三重并发保障
        scanTip:SetHyperlink("item:" .. itemID)

        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end

        if BG.OnItemLoad then
            BG.OnItemLoad(itemID):ContinueOnItemLoad(function()
                local n, l, q, lvl, _, _, _, _, _, tex = GetItemInfo(itemID)
                if n and n ~= "" then
                    itemInfoCache[itemID] = {
                        name = n,
                        link = l,
                        quality = q or 1,
                        level = lvl or 0,
                        texture = tex,
                    }
                    if onLoaded then onLoaded(itemInfoCache[itemID]) end
                end
            end)
        end
    end

    -- 1. 采集当前副本真正掉落的装备 (严格仅采集 Boss 原生掉落，坚决排除 NPC 兑换后的进阶成品装备)
    local function CollectFBItems(FB)
        local items = {}
        local seen = {}

        -- 优先扫描当前副本；仅当当前副本完全无数据时才回退至别名
        local fbsToScan = { FB }
        local altFB = FB:find("titan") and (FB:gsub("titan", "")) or (FB .. "titan")
        if not (BG.Loot and BG.Loot[FB]) and (BG.Loot and BG.Loot[altFB]) then
            tinsert(fbsToScan, altFB)
        end

        for _, scanFB in ipairs(fbsToScan) do
            if BG.Loot and BG.Loot[scanFB] and BG.difficultyTable and BG.difficultyTable[scanFB] then
                for _, hard in ipairs(BG.difficultyTable[scanFB]) do
                    local lootTable = BG.Loot[scanFB][hard]
                    if lootTable and type(lootTable) == "table" then
                        -- 严格按连续 boss1, boss2, ... 遍历真正的 Boss 掉落物
                        -- 严格排除 bossXother (NPC兑换成品)、Quest、Trash 等非掉落项
                        local b = 1
                        while lootTable["boss" .. b] do
                            local list = lootTable["boss" .. b]
                            if type(list) == "table" then
                                for _, itemID in ipairs(list) do
                                    itemID = tonumber(itemID)
                                    if itemID and not seen[itemID] then
                                        seen[itemID] = true
                                        tinsert(items, { itemID = itemID, bossNum = b, hard = hard })
                                        PreloadItemInfo(itemID)
                                    end
                                end
                            end
                            b = b + 1
                        end

                        -- 兜底支持非连续但严格合法的 Boss 键名，排除任何带 other 的兑换项
                        for k, list in pairs(lootTable) do
                            local bNum = k:match("^boss(%d+)$")
                            if bNum and type(list) == "table" then
                                bNum = tonumber(bNum)
                                for _, itemID in ipairs(list) do
                                    itemID = tonumber(itemID)
                                    if itemID and not seen[itemID] then
                                        seen[itemID] = true
                                        tinsert(items, { itemID = itemID, bossNum = bNum, hard = hard })
                                        PreloadItemInfo(itemID)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 如果通过 BG.Loot 没找到足够的装备，尝试从金团表格 BG.Frame 里抓取并提取已有名称
        if BG.Frame and BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
            for b = 1, BG.Maxb[FB] do
                if BG.Frame[FB]["boss" .. b] then
                    local maxi = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
                    for i = 1, maxi do
                        local cell = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                        if cell then
                            local text = cell:GetText()
                            local itemID = SafeGetItemID(text)
                            if itemID and not seen[itemID] then
                                seen[itemID] = true
                                local cachedName = text and text:match("%[(.-)%]") or nil
                                if cachedName and cachedName ~= "" then
                                    itemInfoCache[itemID] = itemInfoCache[itemID] or {}
                                    itemInfoCache[itemID].name = cachedName
                                end
                                tinsert(items, { itemID = itemID, bossNum = b, hard = "N", cachedName = cachedName, isDynamic = true })
                                PreloadItemInfo(itemID)
                            end
                        end
                    end
                end
            end
        end

        return items
    end

    -- 2. 排序与过滤 (支持纯数字ID、中文精准包含搜索、中括号/超链接粘贴、多词空格过滤、离线装备库秒搜)
    ApplyFilterAndSort = function()
        filteredItems = {}
        local moneyDB = BiaoGe.auctionPreset[currentFB] and BiaoGe.auctionPreset[currentFB].money or {}
        local autoDB = BiaoGe.auctionPreset[currentFB] and BiaoGe.auctionPreset[currentFB].autoAuction or {}

        -- 清洗关键字：去除首尾空格与中括号超链接符号
        local rawKw = searchKeyword or ""
        local cleanKw = strtrim(rawKw)
        if cleanKw:find("%[") and cleanKw:find("%]") then
            cleanKw = cleanKw:match("%[(.-)%]") or cleanKw
        end
        cleanKw = cleanKw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        cleanKw = strtrim(cleanKw)

        for _, item in ipairs(currentItems) do
            local itemID = item.itemID
            local cached = itemInfoCache[itemID]
            local name = cached and cached.name
            local link = cached and cached.link
            local quality = cached and cached.quality
            local level = cached and cached.level
            local dbName = ns.ItemNameDB and ns.ItemNameDB[itemID]

            if not name or name == "" or name:find("^Item:") then
                local n, l, q, lvl = GetItemInfo(itemID)
                if n and n ~= "" then
                    name = n
                    link = l
                    quality = q or 1
                    level = lvl or 0
                    itemInfoCache[itemID] = { name = n, link = l, quality = quality, level = level }
                elseif dbName then
                    name = dbName
                    itemInfoCache[itemID] = itemInfoCache[itemID] or {}
                    itemInfoCache[itemID].name = dbName
                else
                    name = item.cachedName
                end
            end
            name = name or dbName or ("Item:" .. itemID)
            quality = quality or 1
            level = level or 0

            local match = true
            if cleanKw ~= "" then
                local idStr = tostring(itemID)
                local hit = false

                -- 1. 纯数字 ID 匹配 (如输入 19884)
                if idStr == cleanKw or idStr:find(cleanKw, 1, true) then
                    hit = true
                -- 2. 纯中文/原文包含匹配 (如输入 "金"、"吞"、"烈焰")
                elseif name and name:find(cleanKw, 1, true) then
                    hit = true
                -- 3. 离线字典绝对兜底包含匹配 (确保未缓存装备100%秒级命中)
                elseif dbName and dbName:find(cleanKw, 1, true) then
                    hit = true
                -- 4. 超链接 link 包含匹配 (防止 name 缺失时 link 包含汉字)
                elseif link and link:find(cleanKw, 1, true) then
                    hit = true
                -- 5. 原始缓存名称包含匹配
                elseif item.cachedName and item.cachedName:find(cleanKw, 1, true) then
                    hit = true
                -- 6. 实时直接从 GetItemInfo 获取一次比对
                else
                    local realName, realLink = GetItemInfo(itemID)
                    if realName and realName:find(cleanKw, 1, true) then
                        hit = true
                        name = realName
                        itemInfoCache[itemID] = itemInfoCache[itemID] or {}
                        itemInfoCache[itemID].name = realName
                    elseif realLink and realLink:find(cleanKw, 1, true) then
                        hit = true
                        link = realLink
                    elseif name and name:lower():find(cleanKw:lower(), 1, true) then
                        hit = true
                    elseif dbName and dbName:lower():find(cleanKw:lower(), 1, true) then
                        hit = true
                    end
                end

                if not hit then
                    match = false
                end
            end

            if match then
                local numID = tonumber(itemID)
                local strID = tostring(itemID)
                local pVal = (numID and moneyDB[numID]) or moneyDB[strID] or 0
                local tVal = (numID and moneyDB[numID .. "tips"]) or moneyDB[strID .. "tips"] or ""
                local aVal = (numID and autoDB[numID]) or autoDB[strID]

                tinsert(filteredItems, {
                    itemID = itemID,
                    name = name,
                    link = link,
                    quality = quality,
                    level = level,
                    price = pVal,
                    tips = tVal,
                    autoAuction = aVal, -- nil: 默认跟随, 1: 开启, 0: 关闭(人工处理)
                    bossNum = item.bossNum,
                    isDynamic = item.isDynamic,
                })
            end
        end

        local sortType = BiaoGe.auctionPreset.sortType
        local sortAsc = BiaoGe.auctionPreset.sortAsc
        table.sort(filteredItems, function(a, b)
            if not a or not b then return false end

            if sortType == "price" then
                local ap = a.price or 0
                local bp = b.price or 0
                if ap ~= bp then
                    if sortAsc then
                        return ap < bp
                    else
                        return ap > bp
                    end
                end
            elseif sortType == "quality" then
                local aq = a.quality or 0
                local bq = b.quality or 0
                if aq ~= bq then
                    if sortAsc then
                        return aq < bq
                    else
                        return aq > bq
                    end
                end
            end

            -- 默认或平局按装等
            local al = a.level or 0
            local bl = b.level or 0
            if al ~= bl then
                if sortAsc then
                    return al < bl
                else
                    return al > bl
                end
            end

            local aid = a.itemID or 0
            local bid = b.itemID or 0
            return aid < bid
        end)
    end

    -- 3. 刷新列表显示 (对齐原版 BiaoGe：自主计算滚动偏移与上下边界，自适应填满主窗口垂直空间)
    RefreshScrollView = function()
        if not contentFrame then return end
        UpdateVisibleRowCount()
        local visibleCount = VISIBLE_ROWS
        local total = #filteredItems
        local maxScroll = math.max(0, total - visibleCount)
        local scrollBar = (mainFrame and mainFrame.scrollBar) or _G["BGLite_AuctionPresetScrollBar"]

        if scrollBar then
            scrollBar:SetMinMaxValues(0, maxScroll)
            if total <= visibleCount then
                scrollBar:SetValue(0)
                scrollBar:Hide()
            else
                scrollBar:Show()
            end
        end

        local offset = 0
        if scrollBar and total > visibleCount then
            offset = math.floor(scrollBar:GetValue() or 0)
            if offset > maxScroll then offset = maxScroll end
            if offset < 0 then offset = 0 end
        end

        local emptyTip = (mainFrame and mainFrame.emptyTip) or (contentFrame and contentFrame.emptyTip)
        if emptyTip then
            emptyTip:SetShown(total == 0)
        end

        for ri = 1, #rowFrames do
            local row = rowFrames[ri]
            if ri <= visibleCount then
                local idx = offset + ri
                if idx <= total then
                    local data = filteredItems[idx]
                    row.data = data
                    row.indexText:SetText(tostring(idx))
                    row.levelText:SetText(data.level > 0 and tostring(data.level) or "")

                    -- 价格与起拍语输入框
                    row.priceEdit:SetText(data.price > 0 and tostring(data.price) or "")
                    row.tipsEdit:SetText(data.tips or "")

                    -- 自动拍卖复选框渲染 (橙装、动态新增项、图纸配方、或未设底价的新装备：默认绝对不自动开拍，保留人工处理！)
                    local function UpdateAutoCheckState(currentDisplayName)
                        if row.autoCheck then
                            local isAuto
                            local checkText = currentDisplayName or data.link or data.name or (ns.ItemNameDB and ns.ItemNameDB[data.itemID]) or (itemInfoCache[data.itemID] and itemInfoCache[data.itemID].name) or ""
                            local isRecipe = checkText:find("设计图", 1, true) or checkText:find("图样", 1, true) or checkText:find("配方", 1, true) or checkText:find("结构图", 1, true)
                            local priceNum = tonumber(data.price) or 0
                            if data.quality == 5 or data.isDynamic or isRecipe or (data.autoAuction == nil and priceNum <= 0) then
                                isAuto = (data.autoAuction == 1) -- 必须显式主动勾选(1)才开启，否则默认未勾选(0)！
                            else
                                isAuto = (data.autoAuction == nil) or (data.autoAuction == 1)
                            end
                            row.autoCheck:SetChecked(isAuto)
                        end
                    end

                    -- 异步获取装备完整信息并实时渲染
                    local function RenderRowItem()
                        local name, link, quality, level, _, _, _, _, _, texture = GetItemInfo(data.itemID)
                        if name and name ~= "" then
                            itemInfoCache[data.itemID] = itemInfoCache[data.itemID] or {}
                            itemInfoCache[data.itemID].name = name
                            itemInfoCache[data.itemID].link = link
                            itemInfoCache[data.itemID].quality = quality or 1
                            itemInfoCache[data.itemID].level = level or 0
                            itemInfoCache[data.itemID].texture = texture
                        end

                        local r, g, b = GetItemQualityColor(quality or data.quality or 1)
                        if texture then
                            row.icon:SetTexture(texture)
                        else
                            row.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
                        end
                        row.iconFrame:SetBackdropBorderColor(r, g, b, 1)

                        local displayName = link or name
                        if not displayName or displayName == "" or displayName:find("^Item:") then
                            local dbName = ns.ItemNameDB and ns.ItemNameDB[data.itemID]
                            if dbName then
                                displayName = dbName
                            else
                                displayName = "Item:" .. data.itemID
                            end
                        end
                        row.nameText:SetText(displayName)
                        row.levelText:SetText(level and level > 0 and tostring(level) or (data.level > 0 and tostring(data.level) or ""))
                        row.levelText:SetTextColor(r, g, b)

                        UpdateAutoCheckState(displayName)
                    end

                    RenderRowItem()
                    PreloadItemInfo(data.itemID, function()
                        if row.data == data then
                            RenderRowItem()
                        end
                    end)

                    row:Show()
                else
                    row.data = nil
                    row:Hide()
                end
            else
                row.data = nil
                row:Hide()
            end
        end
    end

    local function ReloadCurrentFB(FB)
        currentFB = FB or currentFB
        BiaoGe.auctionPreset.currentFB = currentFB
        BiaoGe.auctionPreset[currentFB] = BiaoGe.auctionPreset[currentFB] or { money = {}, autoAuction = {} }
        BiaoGe.auctionPreset[currentFB].autoAuction = BiaoGe.auctionPreset[currentFB].autoAuction or {}
        currentItems = CollectFBItems(currentFB)
        ApplyFilterAndSort()
        RefreshScrollView()
        if UpdateBottomTipCount then UpdateBottomTipCount() end
    end

    -- 转换副本显示名称：优先中文全称 + 英文缩写
    local function GetFBDisplayName(fbKey)
        if not fbKey then return "" end
        local localName = (BG.GetFBinfo and BG.GetFBinfo(fbKey, "localName")) or ""
        local shortName = (BG.GetFBinfo and BG.GetFBinfo(fbKey, "shortName")) or fbKey
        if localName ~= "" and localName ~= shortName then
            return string.format("%s (%s)", localName, shortName)
        elseif localName ~= "" then
            return localName
        else
            return shortName
        end
    end

    -- 4. 构建主 Tab 面板 UI
    function AuctionPreset.CreateMainFrame(parentFrame)
        if mainFrame then return mainFrame end
        local parent = parentFrame or BG.MainFrame or UIParent

        local f = CreateFrame("Frame", "BGLite_AuctionPresetMainFrame", parent, "BackdropTemplate")
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -60)
        f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 42)
        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
        local cr, cg, cb = 0.2, 0.8, 1
        if GetClassRGB then cr, cg, cb = GetClassRGB(nil, "player") end
        f:SetBackdropBorderColor(cr, cg, cb, 0.9)
        f:EnableMouse(true)
        f:Hide()

        -- 顶栏工具栏
        local topBar = CreateFrame("Frame", nil, f)
        topBar:SetPoint("TOPLEFT", 10, -8)
        topBar:SetPoint("TOPRIGHT", -10, -8)
        topBar:SetHeight(32)

        -- 副本选择下拉菜单
        local dropDown = LibBG:Create_UIDropDownMenu("BGLite_AuctionPresetFBDropDown", topBar)
        dropDown:SetPoint("LEFT", topBar, "LEFT", -15, 0)
        LibBG:UIDropDownMenu_SetWidth(dropDown, 140)
        LibBG:UIDropDownMenu_SetText(dropDown, GetFBDisplayName(currentFB))
        LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level)
            for _, fbKey in ipairs(BG.FBtable or {}) do
                local info = LibBG:UIDropDownMenu_CreateInfo()
                info.text = GetFBDisplayName(fbKey)
                info.value = fbKey
                info.checked = (fbKey == currentFB)
                info.func = function()
                    LibBG:UIDropDownMenu_SetText(dropDown, GetFBDisplayName(fbKey))
                    ReloadCurrentFB(fbKey)
                end
                LibBG:UIDropDownMenu_AddButton(info)
            end
        end)
        f.fbDropDown = dropDown

        -- 搜索过滤输入框
        local searchEdit = CreateFrame("EditBox", nil, topBar, "InputBoxTemplate")
        searchEdit:SetSize(110, 20)
        searchEdit:SetPoint("LEFT", dropDown, "RIGHT", 15, 2)
        searchEdit:SetAutoFocus(false)
        searchEdit:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")

        -- 搜索命中件数即时提示
        local countText = topBar:CreateFontString(nil, "ARTWORK")
        countText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        countText:SetPoint("LEFT", searchEdit, "RIGHT", 6, 0)
        countText:SetTextColor(0.8, 0.8, 0.8)
        f.countText = countText

        UpdateBottomTipCount = function()
            if not f.countText then return end
            local total = #filteredItems
            if searchKeyword and searchKeyword ~= "" then
                if total == 0 then
                    f.countText:SetText("|cffff5555(0件)|r")
                else
                    f.countText:SetText(string.format("|cff00ff00(%d件)|r", total))
                end
            else
                f.countText:SetText(string.format("|cff888888(%d件)|r", total))
            end
        end

        local function ExecuteSearch()
            local text = searchEdit:GetText() or ""
            text = text:match("^%s*(.-)%s*$") or ""
            searchKeyword = text
            local scrollBar = (mainFrame and mainFrame.scrollBar) or _G["BGLite_AuctionPresetScrollBar"]
            if scrollBar then
                scrollBar:SetValue(0)
            end
            ApplyFilterAndSort()
            RefreshScrollView()
            if UpdateBottomTipCount then UpdateBottomTipCount() end
        end

        searchEdit:SetScript("OnTextChanged", function(self)
            ExecuteSearch()
        end)
        searchEdit:SetScript("OnEnterPressed", function(self)
            ExecuteSearch()
            self:ClearFocus()
        end)
        searchEdit:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            ExecuteSearch()
            self:ClearFocus()
        end)
        searchEdit:SetScript("OnEditFocusLost", function(self)
            ExecuteSearch()
        end)
        searchEdit:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                self:SetText("")
                ExecuteSearch()
            end
        end)

        local searchLabel = searchEdit:CreateFontString(nil, "ARTWORK")
        searchLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        searchLabel:SetPoint("RIGHT", searchEdit, "LEFT", -5, 0)
        searchLabel:SetText(L["搜索:"] or "搜索:")
        searchLabel:SetTextColor(1, 0.82, 0)

        -- 排序按钮组
        local sortButtons = {
            { key = "level", text = L["按装等"] or "按装等" },
            { key = "quality", text = L["按品质"] or "按品质" },
            { key = "price", text = L["按起拍价"] or "按起拍价" },
        }
        local lastSortBtn
        for _, sInfo in ipairs(sortButtons) do
            local btn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
            btn:SetSize(72, 22)
            if not lastSortBtn then
                btn:SetPoint("LEFT", countText, "RIGHT", 10, 0)
            else
                btn:SetPoint("LEFT", lastSortBtn, "RIGHT", 5, 0)
            end
            btn:SetText(sInfo.text)
            btn:SetScript("OnClick", function()
                if BG.PlaySound then BG.PlaySound(1) end
                if BiaoGe.auctionPreset.sortType == sInfo.key then
                    BiaoGe.auctionPreset.sortAsc = not BiaoGe.auctionPreset.sortAsc
                else
                    BiaoGe.auctionPreset.sortType = sInfo.key
                    BiaoGe.auctionPreset.sortAsc = false
                end
                ApplyFilterAndSort()
                RefreshScrollView()
            end)
            lastSortBtn = btn
        end

        -- 批量设置底价按钮
        local batchPriceBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        batchPriceBtn:SetSize(88, 22)
        batchPriceBtn:SetPoint("LEFT", lastSortBtn, "RIGHT", 15, 0)
        batchPriceBtn:SetText(L["批量底价"] or "批量底价")
        batchPriceBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            StaticPopupDialogs["BGLITE_BATCH_PRESET_PRICE"] = {
                text = "为当前副本所有装备设置统一预设起拍价（0 为跳过）：",
                button1 = OKAY or "确定",
                button2 = CANCEL or "取消",
                hasEditBox = 1,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                EditBoxOnEnterPressed = function(self)
                    local parent = self:GetParent()
                    if parent and parent.button1 then
                        StaticPopup_OnClick(parent, 1)
                    end
                end,
                EditBoxOnEscapePressed = function(self)
                    local parent = self:GetParent()
                    if parent and parent.button2 then
                        StaticPopup_OnClick(parent, 2)
                    end
                end,
                OnShow = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if edit then
                        edit:SetAutoFocus(false)
                        edit:SetNumeric(true)
                        edit:SetFocus()
                    end
                end,
                OnHide = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if edit then
                        if edit.HighlightText then edit:HighlightText(0, 0) end
                        if edit.ClearFocus then edit:ClearFocus() end
                    end
                end,
                OnCancel = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if edit then
                        if edit.HighlightText then edit:HighlightText(0, 0) end
                        if edit.ClearFocus then edit:ClearFocus() end
                    end
                end,
                OnAccept = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if not edit and self:GetParent() then
                        local p = self:GetParent()
                        edit = p.editBox or p.EditBox or (p.GetName and _G[p:GetName() .. "EditBox"])
                    end
                    if edit then
                        if edit.HighlightText then edit:HighlightText(0, 0) end
                        if edit.ClearFocus then edit:ClearFocus() end
                    end
                    local text = edit and edit:GetText() or ""
                    local val = tonumber(text)
                    if val and val > 0 then
                        pcall(function()
                            local moneyDB = BiaoGe.auctionPreset[currentFB].money
                            local altFB = currentFB:find("titan") and (currentFB:gsub("titan", "")) or (currentFB .. "titan")
                            local altMoneyDB = BiaoGe.auctionPreset[altFB] and BiaoGe.auctionPreset[altFB].money

                            for _, item in ipairs(currentItems) do
                                local id = item.itemID
                                moneyDB[id] = val
                                moneyDB[tostring(id)] = val
                                if altMoneyDB then
                                    altMoneyDB[id] = val
                                    altMoneyDB[tostring(id)] = val
                                end
                            end
                            ApplyFilterAndSort()
                            RefreshScrollView()
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已将 %s 所有 %d 件装备预设底价更新为：%dG（已自动同步时光服关联副本）", GetFBDisplayName(currentFB), #currentItems, val))
                        end)
                    end
                end,
            }
            StaticPopup_Show("BGLITE_BATCH_PRESET_PRICE")
        end)

        -- 自动拍卖控制组：Label加冒号 + 快捷操作按钮 (全选/全关/恢复默认)
        local autoLabel = topBar:CreateFontString(nil, "ARTWORK")
        autoLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        autoLabel:SetPoint("LEFT", batchPriceBtn, "RIGHT", 12, 0)
        autoLabel:SetText(L["自动拍卖:"] or "自动拍卖:")
        autoLabel:SetTextColor(1, 0.82, 0)

        -- 套装与代币/特殊物品判定函数 (用于恢复默认时智能剔除)
        local function IsTierTokenItem(itemID, fb)
            if ns.IsSetTokenOrRaidItem then
                local name, link = GetItemInfo(itemID)
                if ns.IsSetTokenOrRaidItem(itemID, link, name, fb) then
                    return true
                end
            end
            local idNum = tonumber(itemID)
            if BG and BG.Loot then
                if fb and BG.Loot[fb] and BG.Loot[fb].ExchangeItems and (BG.Loot[fb].ExchangeItems[itemID] or (idNum and BG.Loot[fb].ExchangeItems[idNum])) then
                    return true
                end
                for fbKey, fbData in pairs(BG.Loot) do
                    if type(fbData) == "table" and fbData.ExchangeItems and (fbData.ExchangeItems[itemID] or (idNum and fbData.ExchangeItems[idNum])) then
                        return true
                    end
                end
            end
            local name, link, quality, _, _, _, _, _, equipLoc = GetItemInfo(itemID)
            local checkText = name or link or ""
            if checkText:find("失落的") or checkText:find("战败的") or checkText:find("征服者的")
               or checkText:find("保卫者的") or checkText:find("胜利者的") or checkText:find("印记")
               or checkText:find("徽记") or checkText:find("奖章") or checkText:find("勋服")
               or checkText:find("代币") or checkText:find("兑换物") or checkText:find("头颅")
               or checkText:find("之心") or checkText:find("精华") or checkText:find("碎片") then
                if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then
                    return true
                end
            end
            return false
        end

        local function BatchSetAutoAuction(mode)
            local autoDB = BiaoGe.auctionPreset[currentFB].autoAuction
            local count = 0
            for _, item in ipairs(currentItems) do
                local itemID = item.itemID
                local _, _, quality = GetItemInfo(itemID)
                quality = quality or item.quality or 1
                local isLegendary = (quality == 5)
                local isLowQuality = (quality <= 3)
                local isToken = IsTierTokenItem(itemID, currentFB)

                local val = 1
                if mode == "enable" then
                    -- 全部开启：橙装依然保留人工处理安全保护
                    if isLegendary then
                        val = 0
                    else
                        val = 1
                    end
                elseif mode == "disable" then
                    -- 全部关闭：所有装备人工处理
                    val = 0
                elseif mode == "default" then
                    -- 恢复默认规则：去掉橙装、蓝绿装、套装、图纸配方、动态新增项及无底价项（设为不自动人工处理），普通紫装开启自动
                    local itemName, itemLink = GetItemInfo(itemID)
                    local checkName = itemName or itemLink or item.cachedName or (ns.ItemNameDB and ns.ItemNameDB[itemID]) or ""
                    local isRecipe = checkName:find("设计图", 1, true) or checkName:find("图样", 1, true) or checkName:find("配方", 1, true) or checkName:find("结构图", 1, true)
                    local presetMoney = BG.GetAuctionPreset and BG.GetAuctionPreset(currentFB, itemID)
                    local priceNum = tonumber(presetMoney) or 0
                    local hasPrice = (priceNum > 0)
                    if isLegendary or isLowQuality or isToken or isRecipe or item.isDynamic or not hasPrice then
                        val = 0 -- 不自动 (人工处理)
                    else
                        val = 1 -- 自动
                    end
                end
                autoDB[itemID] = val
                autoDB[tostring(itemID)] = val
                if tonumber(itemID) then autoDB[tonumber(itemID)] = val end
                count = count + 1
            end
            ApplyFilterAndSort()
            RefreshScrollView()

            if mode == "enable" then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件装备设为：|cff00ff00全部开启自动拍卖|r (橙装保留人工保护)", GetFBDisplayName(currentFB), count))
            elseif mode == "disable" then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件装备设为：|cffff8000全部关闭 (保留人工处理)|r", GetFBDisplayName(currentFB), count))
            elseif mode == "default" then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已恢复默认自动规则：|cffffaa00橙装、蓝绿装、套装/兑换物设为不自动(人工处理)|r，|cff00ff00普通紫装已开启自动拍卖|r", GetFBDisplayName(currentFB)))
            end
        end

        local autoAllBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        autoAllBtn:SetSize(45, 22)
        autoAllBtn:SetPoint("LEFT", autoLabel, "RIGHT", 5, 0)
        autoAllBtn:SetText(L["全选"] or "全选")
        autoAllBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            BatchSetAutoAuction("enable")
        end)
        autoAllBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("自动拍卖 - 全选", 1, 0.82, 0)
            GameTooltip:AddLine("将当前副本所有装备全部勾选【开启自动拍卖】。", 1, 1, 1, true)
            GameTooltip:AddLine("（橙装依然受安全保护，保留人工拍卖）", 0.5, 0.8, 1, true)
            GameTooltip:Show()
        end)
        autoAllBtn:SetScript("OnLeave", GameTooltip_Hide)

        local autoNoneBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        autoNoneBtn:SetSize(48, 22)
        autoNoneBtn:SetPoint("LEFT", autoAllBtn, "RIGHT", 4, 0)
        autoNoneBtn:SetText(L["全关"] or "全关")
        autoNoneBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            BatchSetAutoAuction("disable")
        end)
        autoNoneBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("自动拍卖 - 全关", 1, 0.82, 0)
            GameTooltip:AddLine("将当前副本所有装备全部取消勾选【不自动】（全部由团长人工拍卖）。", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        autoNoneBtn:SetScript("OnLeave", GameTooltip_Hide)

        local autoDefaultBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        autoDefaultBtn:SetSize(72, 22)
        autoDefaultBtn:SetPoint("LEFT", autoNoneBtn, "RIGHT", 4, 0)
        autoDefaultBtn:SetText(L["恢复默认"] or "恢复默认")
        autoDefaultBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            BatchSetAutoAuction("default")
        end)
        autoDefaultBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("自动拍卖 - 恢复默认", 1, 0.82, 0)
            GameTooltip:AddLine("• 去掉橙装（人工确认安全保护）", 1, 0.5, 0, true)
            GameTooltip:AddLine("• 去掉蓝绿装、白装与杂物", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("• 去掉套装兑换物/印记/任务道具", 1, 0.82, 0, true)
            GameTooltip:AddLine("• 仅普通紫装开启自动拍卖", 0, 1, 0, true)
            GameTooltip:Show()
        end)
        autoDefaultBtn:SetScript("OnLeave", GameTooltip_Hide)

        -- 清空当前副本按钮
        local clearBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        clearBtn:SetSize(72, 22)
        clearBtn:SetPoint("RIGHT", topBar, "RIGHT", -5, 0)
        clearBtn:SetText(L["全部清空"] or "全部清空")
        clearBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            StaticPopupDialogs["BGLITE_CLEAR_PRESET_CONFIRM"] = {
                text = string.format("确定要清空【%s】的所有预设起拍价、起拍语与自动设置吗？", GetFBDisplayName(currentFB)),
                button1 = OKAY or "确定",
                button2 = CANCEL or "取消",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnAccept = function()
                    BiaoGe.auctionPreset[currentFB].money = {}
                    BiaoGe.auctionPreset[currentFB].autoAuction = {}
                    ApplyFilterAndSort()
                    RefreshScrollView()
                    if UpdateBottomTipCount then UpdateBottomTipCount() end
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已清空 %s 的所有预设价格与自动拍卖设置", GetFBDisplayName(currentFB)))
                end,
            }
            StaticPopup_Show("BGLITE_CLEAR_PRESET_CONFIRM")
        end)

        -- 5. 列表表头
        local headerFrame = CreateFrame("Frame", nil, f)
        headerFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -5)
        headerFrame:SetPoint("TOPRIGHT", topBar, "BOTTOMRIGHT", -20, -5)
        headerFrame:SetHeight(22)

        local columns = {
            { text = L["序号"] or "序号", width = 45, justify = "CENTER" },
            { text = L["等级"] or "等级", width = 50, justify = "CENTER" },
            { text = L["装备"] or "装备", width = 230, justify = "LEFT" },
            { text = L["预设起拍价"] or "预设起拍价", width = 110, justify = "CENTER" },
            { text = L["预设起拍语 (附加喊话)"] or "预设起拍语 (附加喊话)", width = 190, justify = "LEFT" },
            { text = L["自动"] or "自动", width = 45, justify = "CENTER" },
            { text = L["清空"] or "清空", width = 45, justify = "CENTER" },
        }

        local curX = 5
        for _, col in ipairs(columns) do
            local th = headerFrame:CreateFontString(nil, "ARTWORK")
            th:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            th:SetPoint("LEFT", headerFrame, "LEFT", curX, 0)
            th:SetWidth(col.width)
            th:SetJustifyH(col.justify)
            th:SetTextColor(1, 0.82, 0)
            th:SetText(col.text)
            curX = curX + col.width + 10
        end

        -- 6. 列表容器 (直接挂载于主面板 f，尺寸自适应占满主窗口垂直空间)
        contentFrame = CreateFrame("Frame", "BGLite_AuctionPresetContentFrame", f)
        contentFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
        contentFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 32)
        contentFrame:EnableMouseWheel(true)
        contentFrame:SetScript("OnSizeChanged", function(self)
            UpdateVisibleRowCount()
            RefreshScrollView()
        end)

        -- 原生滚动条 (对齐原版 BiaoGe：由当前过滤结果自主精确控制)
        f.OnScrollBarValueChanged = function(self, value)
            RefreshScrollView()
        end

        local scrollBar = CreateFrame("Slider", "BGLite_AuctionPresetScrollBar", f, "UIPanelScrollBarTemplate")
        scrollBar:SetPoint("TOPLEFT", contentFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMRIGHT", 4, 16)
        scrollBar:SetScript("OnValueChanged", function(self, val)
            RefreshScrollView()
        end)
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        scrollBar:SetValueStep(1)
        scrollBar.scrollStep = 1
        f.scrollBar = scrollBar

        contentFrame:SetScript("OnMouseWheel", function(self, delta)
            if not f.scrollBar or not f.scrollBar:IsShown() then return end
            local cur = f.scrollBar:GetValue() or 0
            local minV, maxV = f.scrollBar:GetMinMaxValues()
            local newVal = cur - delta * 3
            if newVal < minV then newVal = minV end
            if newVal > maxV then newVal = maxV end
            f.scrollBar:SetValue(newVal)
        end)

        -- 空结果居中提示 (对齐原版 BiaoGe)
        local emptyTip = contentFrame:CreateFontString(nil, "ARTWORK")
        emptyTip:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        emptyTip:SetPoint("CENTER", contentFrame, "CENTER", 0, 30)
        emptyTip:SetTextColor(0.6, 0.6, 0.6)
        emptyTip:SetText("没有符合当前搜索条件的装备")
        emptyTip:Hide()
        contentFrame.emptyTip = emptyTip
        f.emptyTip = emptyTip

        -- 创建自适应单行控件池 (最多 32 行，自动占满整个主窗口可用高度)
        for ri = 1, MAX_ROWS do
            local row = CreateFrame("Button", nil, contentFrame)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -(ri - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -(ri - 1) * ROW_HEIGHT)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(self, delta)
                if contentFrame and contentFrame:GetScript("OnMouseWheel") then
                    contentFrame:GetScript("OnMouseWheel")(contentFrame, delta)
                end
            end)

            -- 奇偶行背景
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if ri % 2 == 0 then
                bg:SetColorTexture(0.12, 0.12, 0.12, 0.6)
            else
                bg:SetColorTexture(0.08, 0.08, 0.08, 0.4)
            end
            row.bg = bg

            -- 高亮
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.2, 0.4, 0.8, 0.25)

            local rx = 5
            -- 序号
            local idxText = row:CreateFontString(nil, "ARTWORK")
            idxText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            idxText:SetPoint("LEFT", row, "LEFT", rx, 0)
            idxText:SetWidth(columns[1].width)
            idxText:SetJustifyH("CENTER")
            idxText:SetTextColor(0.6, 0.6, 0.6)
            row.indexText = idxText
            rx = rx + columns[1].width + 10

            -- 装等
            local lvlText = row:CreateFontString(nil, "ARTWORK")
            lvlText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            lvlText:SetPoint("LEFT", row, "LEFT", rx, 0)
            lvlText:SetWidth(columns[2].width)
            lvlText:SetJustifyH("CENTER")
            row.levelText = lvlText
            rx = rx + columns[2].width + 10

            -- 装备图标
            local iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
            iconFrame:SetSize(20, 20)
            iconFrame:SetPoint("LEFT", row, "LEFT", rx, 0)
            iconFrame:SetBackdrop({
                edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeSize = 1,
            })
            local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.icon = iconTex
            row.iconFrame = iconFrame

            -- 装备名称
            local nameText = row:CreateFontString(nil, "ARTWORK")
            nameText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            nameText:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
            nameText:SetWidth(columns[3].width - 26)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            row.nameText = nameText

            -- 鼠标悬停原生 Tooltip
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if self.data and self.data.itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                    GameTooltip:ClearLines()
                    if BG.SetSpecIDToLink and self.data.link then
                        GameTooltip:SetHyperlink(BG.SetSpecIDToLink(self.data.link))
                    elseif self.data.link then
                        GameTooltip:SetHyperlink(self.data.link)
                    else
                        GameTooltip:SetItemByID(self.data.itemID)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

            rx = rx + columns[3].width + 10

            -- 起拍价输入框
            local pEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            pEdit:SetSize(columns[4].width - 10, 18)
            pEdit:SetPoint("LEFT", row, "LEFT", rx + 5, 0)
            pEdit:SetAutoFocus(false)
            pEdit:SetNumeric(true)
            pEdit:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            pEdit:SetScript("OnTextChanged", function(self, userInput)
                if not userInput or not row.data then return end
                local num = tonumber(self:GetText()) or 0
                local moneyDB = BiaoGe.auctionPreset[currentFB].money
                if num > 0 then
                    moneyDB[row.data.itemID] = num
                    row.data.price = num
                else
                    moneyDB[row.data.itemID] = nil
                    row.data.price = 0
                end
            end)
            pEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            pEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            pEdit:SetScript("OnEditFocusLost", function(self) self:ClearFocus() end)
            row.priceEdit = pEdit
            rx = rx + columns[4].width + 10

            -- 起拍语输入框
            local tEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            tEdit:SetSize(columns[5].width - 10, 18)
            tEdit:SetPoint("LEFT", row, "LEFT", rx + 5, 0)
            tEdit:SetAutoFocus(false)
            tEdit:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            tEdit:SetScript("OnTextChanged", function(self, userInput)
                if not userInput or not row.data then return end
                local txt = self:GetText():trim()
                local moneyDB = BiaoGe.auctionPreset[currentFB].money
                if txt ~= "" then
                    moneyDB[row.data.itemID .. "tips"] = txt
                    row.data.tips = txt
                else
                    moneyDB[row.data.itemID .. "tips"] = nil
                    row.data.tips = ""
                end
            end)
            tEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            tEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            tEdit:SetScript("OnEditFocusLost", function(self) self:ClearFocus() end)
            row.tipsEdit = tEdit
            rx = rx + columns[5].width + 10

            -- 自动拍卖复选框
            local aCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            aCheck:SetSize(20, 20)
            aCheck:SetPoint("CENTER", row, "LEFT", rx + columns[6].width / 2, 0)
            aCheck:SetScript("OnClick", function(self)
                if BG.PlaySound then BG.PlaySound(1) end
                if not row.data then return end
                local autoDB = BiaoGe.auctionPreset[currentFB].autoAuction
                if self:GetChecked() then
                    autoDB[row.data.itemID] = 1
                    row.data.autoAuction = 1
                else
                    autoDB[row.data.itemID] = 0
                    row.data.autoAuction = 0
                end
            end)
            aCheck:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["掉落自动拍卖"] or "掉落自动拍卖", 1, 0.82, 0)
                local isChecked = self:GetChecked()
                if isChecked then
                    GameTooltip:AddLine("当前状态：|cff00ff00开启自动拍卖|r", 1, 1, 1)
                else
                    GameTooltip:AddLine("当前状态：|cffff8000不自动拍卖 (保留人工处理)|r", 1, 1, 1)
                end
                if row.data and row.data.quality == 5 then
                    GameTooltip:AddLine("【橙装保护】橙装价值极高，默认不自动拍卖，保留由团长单独人工拍卖。", 1, 0.5, 0, true)
                else
                    GameTooltip:AddLine("• 勾选（默认）：拾取/摸尸体时自动发起拍卖。", 0.85, 0.85, 0.85, true)
                    GameTooltip:AddLine("• 取消勾选：拾取/摸尸体时不自动开拍，保留在背包由团长最后单独人工拍卖。", 1, 0.82, 0.4, true)
                end
                GameTooltip:Show()
            end)
            aCheck:SetScript("OnLeave", GameTooltip_Hide)
            row.autoCheck = aCheck
            rx = rx + columns[6].width + 10

            -- 清空按钮
            local clrBt = CreateFrame("Button", nil, row)
            clrBt:SetSize(16, 16)
            clrBt:SetPoint("CENTER", row, "LEFT", rx + columns[7].width / 2, 0)
            clrBt:SetNormalTexture("interface/raidframe/readycheck-notready")
            clrBt:SetHighlightTexture("interface/raidframe/readycheck-notready")
            clrBt:SetScript("OnClick", function()
                if BG.PlaySound then BG.PlaySound(1) end
                if row.data then
                    local moneyDB = BiaoGe.auctionPreset[currentFB].money
                    local autoDB = BiaoGe.auctionPreset[currentFB].autoAuction
                    moneyDB[row.data.itemID] = nil
                    moneyDB[row.data.itemID .. "tips"] = nil
                    if autoDB then autoDB[row.data.itemID] = nil end
                    row.data.price = 0
                    row.data.tips = ""
                    row.data.autoAuction = nil
                    pEdit:SetText("")
                    tEdit:SetText("")
                    local defaultChecked = (row.data.quality ~= 5)
                    aCheck:SetChecked(defaultChecked)
                end
            end)
            row.clearBtn = clrBt

            rowFrames[ri] = row
        end

        -- 拾取后自动全开拍卖控制区 (放置于底栏左侧，采用链式相对锚点，彻底根除遮挡)
        local autoCheck = CreateFrame("CheckButton", "BGLite_AuctionPreset_AutoAuctionCheck", f, "UICheckButtonTemplate")
        autoCheck:SetSize(22, 22)
        autoCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 6)
        local autoText = autoCheck:CreateFontString(nil, "ARTWORK")
        autoText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        autoText:SetPoint("LEFT", autoCheck, "RIGHT", 2, 0)
        autoText:SetText(L["拾取后自动拍卖"] or "拾取后自动拍卖")
        autoText:SetTextColor(1, 0.82, 0)
        autoCheck:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionOnLoot == 1)
        autoCheck:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            BiaoGe.options = BiaoGe.options or {}
            local val = self:GetChecked() and 1 or 0
            BiaoGe.options.autoAuctionOnLoot = val
            -- 双向同步：如果设置面板中的选项存在，实时同步
            if ns.SyncOptionAutoAuctionOnLoot then
                ns.SyncOptionAutoAuctionOnLoot(val)
            end
            if self:GetChecked() then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已开启【拾取后自动拍卖】功能。团长拾取Boss装备进包且自动录入表格后，将发起全团自动拍卖。")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已关闭【拾取后自动拍卖】功能。")
            end
        end)

        -- 自动拍卖开关旁边的说明图标按钮 [?]
        local autoHelpBtn = CreateFrame("Button", nil, f)
        autoHelpBtn:SetSize(18, 18)
        autoHelpBtn:SetPoint("LEFT", autoText, "RIGHT", 2, 0)
        local autoHelpText = autoHelpBtn:CreateFontString(nil, "ARTWORK")
        autoHelpText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        autoHelpText:SetPoint("CENTER", 0, 0)
        autoHelpText:SetText("|cffffd100[?]|r")

        -- 最佳实践悬停说明
        local function ShowAutoAuctionTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["拾取后自动拍卖 - 使用指南"] or "拾取后自动拍卖 - 使用指南", 1, 0.82, 0, true)
            GameTooltip:AddLine("建议配合预设价格使用，避免未预设起拍价导致误拍。", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("安全机制：仅当装备被金团表格正式记录入库后才会展开自动拍卖，白装/小怪杂物绝不误拍。", 0.4, 0.8, 1, true)
            GameTooltip:Show()
        end

        autoCheck:SetScript("OnEnter", ShowAutoAuctionTooltip)
        autoCheck:SetScript("OnLeave", GameTooltip_Hide)
        autoHelpBtn:SetScript("OnEnter", ShowAutoAuctionTooltip)
        autoHelpBtn:SetScript("OnLeave", GameTooltip_Hide)
        f.autoAuctionCheck = autoCheck
        f.autoHelpBtn = autoHelpBtn

        -- 免确认秒拍复选框 (严格相对 autoHelpBtn 右侧 35 像素排布，彻底消除遮挡与重叠)
        local instantCheck = CreateFrame("CheckButton", "BGLite_AuctionPreset_InstantCheck", f, "UICheckButtonTemplate")
        instantCheck:SetSize(22, 22)
        instantCheck:SetPoint("LEFT", autoHelpBtn, "RIGHT", 35, 0)
        local instText = instantCheck:CreateFontString(nil, "ARTWORK")
        instText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        instText:SetPoint("LEFT", instantCheck, "RIGHT", 2, 0)
        instText:SetText(L["免确认秒开"] or "免确认秒开")
        instText:SetTextColor(0.85, 0.85, 0.85)
        instantCheck:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionInstant == 1)
        instantCheck:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            BiaoGe.options = BiaoGe.options or {}
            local val = self:GetChecked() and 1 or 0
            BiaoGe.options.autoAuctionInstant = val
            -- 双向同步：如果设置面板中的选项存在，实时同步
            if ns.SyncOptionAutoAuctionInstant then
                ns.SyncOptionAutoAuctionInstant(val)
            end
        end)
        instantCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["免确认秒开"] or "免确认秒开", 1, 1, 1, true)
            GameTooltip:AddLine("勾选后：拾取完装备脱战后，不显示 5 秒倒计时确认条，直接秒级全开发起拍卖。", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("不勾选（推荐）：拾取完毕显示 5 秒倒计时悬浮条，方便团长临时取消或立即点击全拍。", 0, 1, 0, true)
            GameTooltip:Show()
        end)
        instantCheck:SetScript("OnLeave", GameTooltip_Hide)
        f.instantCheck = instantCheck

        -- 页面显示时同步复选框状态与自适应行数
        f:HookScript("OnShow", function()
            if BiaoGe.options then
                autoCheck:SetChecked(BiaoGe.options.autoAuctionOnLoot == 1)
                instantCheck:SetChecked(BiaoGe.options.autoAuctionInstant == 1)
            end
            UpdateVisibleRowCount()
            RefreshScrollView()
        end)

        mainFrame = f
        BG.AuctionPresetMainFrame = f

        -- 初始化数据
        ReloadCurrentFB(currentFB)

        -- 注册到底部 Tab
        if BG.Create_TabButton then
            local tabBtn = BG.Create_TabButton(BG.AuctionPresetMainFrameTabNum, L["预设价格"] or "预设价格", f, 90)
            AuctionPreset.tabBtn = tabBtn
        end

        return f
    end

    -- 7. 拍卖发起联动逻辑 Hook
    -- ① 单件开拍拦截与自动填充起拍价和起拍语
    local orig_StartAuction = BG.StartAuction
    if orig_StartAuction then
        BG.StartAuction = function(link, bt, isNotAuctioned, notAlt, isRightButton, noSound, callback)
            orig_StartAuction(link, bt, isNotAuctioned, notAlt, isRightButton, noSound, callback)

            -- 当 BG.StartAucitonFrame 弹出且有装备时，读取预设价格并自动填入
            local f = BG.StartAucitonFrame
            if f and f:IsVisible() and f.Edit2 then
                local itemID = SafeGetItemID(link)
                if itemID then
                    local money, tips = BG.GetAuctionPreset(BG.FB1 or currentFB, itemID)
                    if money and money > 0 then
                        f.Edit2:SetText(tostring(money))
                        f.Edit2:SetCursorPosition(0)
                        if f.bt and f.bt.money then
                            f.bt.money = money
                        end
                        if tips and tips ~= "" and f.EditTips then
                            f.EditTips:SetText(tips)
                        end
                    end
                end
            end
        end
    end

    -- ② 悬停装备显示预设起拍价与起拍语
    local function AddAuctionPresetTooltip(tooltip)
        if not IsAltKeyDown() then return end
        local name, link = tooltip:GetItem()
        if not link then return end
        local itemID = SafeGetItemID(link)
        if not itemID then return end
        local money, tips = BG.GetAuctionPreset(BG.FB1 or currentFB, itemID)
        if money or (tips and tips ~= "") then
            if money and money > 0 then
                local numStr = (BG.FormatNumber and BG.FormatNumber(money, 2)) or tostring(money)
                tooltip:AddLine("预设起拍价：|cffffffff" .. numStr .. "|r", 1, 0.82, 0, true)
            end
            if tips and tips ~= "" then
                tooltip:AddLine("预设起拍语：|cffffffff" .. tips .. "|r", 1, 0.82, 0, true)
            end
            tooltip:Show()
        end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(self)
            if self == GameTooltip then AddAuctionPresetTooltip(self) end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetItem", AddAuctionPresetTooltip)
    end

end

-- =========================================================================
-- 注入至 BGLite 设置面板：“锁定拍卖竞价窗口”下方追加自动拍卖与免确认选项
-- =========================================================================
local optAutoCheck = nil
local optInstantCheck = nil

function ns.SyncOptionAutoAuctionOnLoot(val)
    if optAutoCheck then
        optAutoCheck:SetChecked(val == 1)
    end
end

function ns.SyncOptionAutoAuctionInstant(val)
    if optInstantCheck then
        optInstantCheck:SetChecked(val == 1)
    end
end

function ns.InitAuctionPresetOptions()
    if not (BG and BG.options and BG.options["buttonauctionMoveByShift"]) then return end
    local anchorBtn = BG.options["buttonauctionMoveByShift"]
    if anchorBtn.hasInitedPresetOptions then return end
    anchorBtn.hasInitedPresetOptions = true

    local parent = anchorBtn:GetParent()
    if not parent then return end

    -- 1. 开启自动拍卖（拾取后自动拍卖）复选框
    local cbAuto = CreateFrame("CheckButton", "BG_Button_OptAutoAuctionOnLoot", parent, "ChatConfigCheckButtonTemplate")
    cbAuto:SetSize(30, 30)
    cbAuto:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -5)
    local cbAutoText = cbAuto.Text or _G[cbAuto:GetName() .. "Text"] or cbAuto:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbAuto.Text = cbAutoText
    cbAutoText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    cbAutoText:SetText(BG.STC_g1(L["开启自动拍卖"] or "开启自动拍卖"))
    cbAutoText:SetWordWrap(false)
    local w1 = (cbAutoText.GetStringWidth and cbAutoText:GetStringWidth() or 120) + 20
    if cbAutoText.SetWidth then cbAutoText:SetWidth(w1) end
    if cbAuto.SetHitRectInsets then cbAuto:SetHitRectInsets(0, -w1, 0, 0) end
    cbAuto:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionOnLoot == 1)

    cbAuto:SetScript("OnClick", function(self)
        if BG.PlaySound then BG.PlaySound(1) end
        BiaoGe.options = BiaoGe.options or {}
        local val = self:GetChecked() and 1 or 0
        BiaoGe.options.autoAuctionOnLoot = val
        -- 双向绑定：同步预设面板中的复选框
        local main = BG.AuctionPresetMainFrame
        if main and main.autoAuctionCheck then
            main.autoAuctionCheck:SetChecked(val == 1)
        end
    end)
    cbAuto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["开启自动拍卖"] or "开启自动拍卖", 1, 0.82, 0, true)
        GameTooltip:AddLine("团长拾取Boss装备进包且自动录入表格后，将发起自动拍卖。", 1, 1, 1, true)
        GameTooltip:AddLine("与【预设价格】底部的“拾取后自动拍卖”实时双向同步保持一致。", 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    cbAuto:SetScript("OnLeave", GameTooltip_Hide)
    cbAuto:SetScript("OnShow", function(self)
        self:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionOnLoot == 1)
    end)
    optAutoCheck = cbAuto
    BG.options["buttonautoAuctionOnLoot"] = cbAuto

    -- 2. 免确认秒开复选框
    local cbInst = CreateFrame("CheckButton", "BG_Button_OptAutoAuctionInstant", parent, "ChatConfigCheckButtonTemplate")
    cbInst:SetSize(30, 30)
    cbInst:SetPoint("TOPLEFT", cbAuto, "BOTTOMLEFT", 0, -5)
    local cbInstText = cbInst.Text or _G[cbInst:GetName() .. "Text"] or cbInst:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbInst.Text = cbInstText
    cbInstText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    cbInstText:SetText(L["免确认"] or "免确认")
    cbInstText:SetWordWrap(false)
    local w2 = (cbInstText.GetStringWidth and cbInstText:GetStringWidth() or 140) + 20
    if cbInstText.SetWidth then cbInstText:SetWidth(w2) end
    if cbInst.SetHitRectInsets then cbInst:SetHitRectInsets(0, -w2, 0, 0) end
    cbInst:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionInstant == 1)

    cbInst:SetScript("OnClick", function(self)
        if BG.PlaySound then BG.PlaySound(1) end
        BiaoGe.options = BiaoGe.options or {}
        local val = self:GetChecked() and 1 or 0
        BiaoGe.options.autoAuctionInstant = val
        -- 双向绑定：同步预设面板中的复选框
        local main = BG.AuctionPresetMainFrame
        if main and main.instantCheck then
            main.instantCheck:SetChecked(val == 1)
        end
    end)
    cbInst:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["免确认"] or "免确认", 1, 1, 1, true)
        GameTooltip:AddLine("勾选后：拾取完装备脱战后，不显示 5 秒倒计时悬浮条，直接发起自动拍卖。", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("与【预设价格】底部的“免确认秒开”实时双向同步保持一致。", 0.4, 0.8, 1, true)
        GameTooltip:Show()
    end)
    cbInst:SetScript("OnLeave", GameTooltip_Hide)
    cbInst:SetScript("OnShow", function(self)
        self:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionInstant == 1)
    end)
    optInstantCheck = cbInst
    BG.options["buttonautoAuctionInstant"] = cbInst
end

-- 自启动与设置面板挂载
if ns.InitAuctionPresetOptions then
    ns.InitAuctionPresetOptions()
end
if BG and BG.OpenOption and not ns.hasHookedOpenOptionForAuctionPreset then
    ns.hasHookedOpenOptionForAuctionPreset = true
    hooksecurefunc(BG, "OpenOption", function()
        if ns.InitAuctionPresetOptions then
            ns.InitAuctionPresetOptions()
        end
    end)
end

if IsLoggedIn() then
    ns.InitAuctionPresetModule()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        ns.InitAuctionPresetModule()
        self:UnregisterAllEvents()
    end)
end
