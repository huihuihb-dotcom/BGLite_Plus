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

-- 全局读取预设价格与起拍语接口
function BG.GetAuctionPreset(FB, itemID)
    if not itemID then return nil, nil end
    itemID = tonumber(itemID)
    if not itemID then return nil, nil end

    FB = FB or (BG and BG.FB1)
    if BiaoGe and BiaoGe.auctionPreset then
        if FB and BiaoGe.auctionPreset[FB] and BiaoGe.auctionPreset[FB].money then
            local money = BiaoGe.auctionPreset[FB].money[itemID]
            local tips = BiaoGe.auctionPreset[FB].money[itemID .. "tips"]
            if money or tips then
                return money, tips
            end
        end

        -- 若当前副本没找到，跨其他副本查找 fallback
        for _, fbName in ipairs(BG.FBtable or {}) do
            if fbName ~= FB and BiaoGe.auctionPreset[fbName] and BiaoGe.auctionPreset[fbName].money then
                local money = BiaoGe.auctionPreset[fbName].money[itemID]
                local tips = BiaoGe.auctionPreset[fbName].money[itemID .. "tips"]
                if money or tips then
                    return money, tips
                end
            end
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

    local ROW_HEIGHT = 26
    local VISIBLE_ROWS = 18

    -- 1. 采集当前副本所有装备
    local function CollectFBItems(FB)
        local items = {}
        local seen = {}

        if BG.Loot and BG.Loot[FB] and BG.difficultyTable and BG.difficultyTable[FB] then
            for _, hard in ipairs(BG.difficultyTable[FB]) do
                local lootTable = BG.Loot[FB][hard]
                if lootTable then
                    local bi = 1
                    while lootTable["boss" .. bi] do
                        for _, itemID in ipairs(lootTable["boss" .. bi]) do
                            itemID = tonumber(itemID)
                            if itemID and not seen[itemID] then
                                seen[itemID] = true
                                tinsert(items, { itemID = itemID, bossNum = bi, hard = hard })
                            end
                        end
                        bi = bi + 1
                    end
                end
            end
        end

        -- 如果通过 BG.Loot 没找到，尝试从表格 BG.Frame 里抓取
        if #items == 0 and BG.Frame and BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
            for b = 1, BG.Maxb[FB] do
                if BG.Frame[FB]["boss" .. b] then
                    local maxi = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
                    for i = 1, maxi do
                        local cell = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                        if cell then
                            local itemID = SafeGetItemID(cell:GetText())
                            if itemID and not seen[itemID] then
                                seen[itemID] = true
                                tinsert(items, { itemID = itemID, bossNum = b, hard = "N" })
                            end
                        end
                    end
                end
            end
        end

        return items
    end

    -- 2. 排序与过滤
    local function ApplyFilterAndSort()
        filteredItems = {}
        local moneyDB = BiaoGe.auctionPreset[currentFB] and BiaoGe.auctionPreset[currentFB].money or {}
        local autoDB = BiaoGe.auctionPreset[currentFB] and BiaoGe.auctionPreset[currentFB].autoAuction or {}

        for _, item in ipairs(currentItems) do
            local itemID = item.itemID
            local name, link, quality, level = GetItemInfo(itemID)
            name = name or ("Item:" .. itemID)
            quality = quality or 1
            level = level or 0

            local match = true
            if searchKeyword and searchKeyword ~= "" then
                if not name:lower():find(searchKeyword:lower(), 1, true) then
                    match = false
                end
            end

            if match then
                tinsert(filteredItems, {
                    itemID = itemID,
                    name = name,
                    link = link,
                    quality = quality,
                    level = level,
                    price = moneyDB[itemID] or 0,
                    tips = moneyDB[itemID .. "tips"] or "",
                    autoAuction = autoDB[itemID], -- nil: 默认跟随, 1: 开启, 0: 关闭(人工处理)
                    bossNum = item.bossNum,
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

    -- 3. 刷新列表显示
    local function RefreshScrollView()
        if not scrollFrame then return end
        local total = #filteredItems
        FauxScrollFrame_Update(scrollFrame, total, VISIBLE_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)

        for ri = 1, VISIBLE_ROWS do
            local row = rowFrames[ri]
            local idx = offset + ri
            if idx <= total then
                local data = filteredItems[idx]
                row.data = data
                row.indexText:SetText(tostring(idx))
                row.levelText:SetText(data.level > 0 and tostring(data.level) or "")

                -- 异步获取装备完整信息
                local function RenderRowItem()
                    local name, link, quality, level, _, _, _, _, _, texture = GetItemInfo(data.itemID)
                    local r, g, b = GetItemQualityColor(quality or data.quality or 1)
                    if texture then
                        row.icon:SetTexture(texture)
                    else
                        row.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
                    end
                    row.iconFrame:SetBackdropBorderColor(r, g, b, 1)
                    row.nameText:SetText(link or name or ("Item:" .. data.itemID))
                    row.levelText:SetText(level and level > 0 and tostring(level) or (data.level > 0 and tostring(data.level) or ""))
                    row.levelText:SetTextColor(r, g, b)
                end

                RenderRowItem()
                if BG.OnItemLoad then
                    BG.OnItemLoad(data.itemID):ContinueOnItemLoad(RenderRowItem)
                end

                -- 价格与起拍语输入框
                row.priceEdit:SetText(data.price > 0 and tostring(data.price) or "")
                row.tipsEdit:SetText(data.tips or "")

                -- 自动拍卖复选框渲染 (橙装 quality == 5 默认必须人工处理；普通装备默认开启自动)
                if row.autoCheck then
                    local isAuto
                    if data.quality == 5 then
                        isAuto = (data.autoAuction == 1)
                    else
                        isAuto = (data.autoAuction == nil) or (data.autoAuction == 1)
                    end
                    row.autoCheck:SetChecked(isAuto)
                end

                row:Show()
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
        f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 35)
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
        searchEdit:SetSize(130, 20)
        searchEdit:SetPoint("LEFT", dropDown, "RIGHT", 15, 2)
        searchEdit:SetAutoFocus(false)
        searchEdit:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        searchEdit:SetScript("OnTextChanged", function(self)
            searchKeyword = self:GetText():trim()
            ApplyFilterAndSort()
            RefreshScrollView()
        end)
        searchEdit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        searchEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        searchEdit:SetScript("OnEditFocusLost", function(self)
            self:ClearFocus()
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
                btn:SetPoint("LEFT", searchEdit, "RIGHT", 15, 0)
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
                            for _, item in ipairs(currentItems) do
                                moneyDB[item.itemID] = val
                            end
                            ApplyFilterAndSort()
                            RefreshScrollView()
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已将 %s 所有装备预设底价更新为：%dG", GetFBDisplayName(currentFB), val))
                        end)
                    end
                end,
            }
            StaticPopup_Show("BGLITE_BATCH_PRESET_PRICE")
        end)

        -- 自动拍卖批量设置按钮与下拉菜单
        local batchSetBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        batchSetBtn:SetSize(90, 22)
        batchSetBtn:SetPoint("LEFT", batchPriceBtn, "RIGHT", 8, 0)
        batchSetBtn:SetText(L["自动拍卖 ▾"] or "自动拍卖 ▾")

        local batchSetMenu = LibBG:Create_UIDropDownMenu("BGLite_AuctionPresetBatchSetMenu", batchSetBtn)
        LibBG:UIDropDownMenu_Initialize(batchSetMenu, function(self, level)
            local function BatchSetAutoAuction(mode, filterTokenOnly)
                local autoDB = BiaoGe.auctionPreset[currentFB].autoAuction
                local count = 0
                for _, item in ipairs(currentItems) do
                    local isToken = IsTierTokenItem(item.itemID, currentFB)

                    if filterTokenOnly then
                        -- 仅处理套装兑换物：非套装装备一律跳过，绝不修改！
                        if isToken then
                            count = count + 1
                            if mode == "disable" then
                                autoDB[item.itemID] = 0
                            elseif mode == "enable" then
                                autoDB[item.itemID] = 1
                            elseif mode == "reset" then
                                autoDB[item.itemID] = nil
                            end
                        end
                    else
                        -- 处理当前副本全部装备
                        local isLegendary = false
                        local _, _, q = GetItemInfo(item.itemID)
                        if q == 5 then isLegendary = true end

                        if mode == "enable" and isLegendary then
                            -- 橙装保护：即使批量开启，橙装也保持默认人工处理，绝不误开
                        else
                            count = count + 1
                            if mode == "enable" then
                                autoDB[item.itemID] = 1
                            elseif mode == "disable" then
                                autoDB[item.itemID] = 0
                            elseif mode == "reset" then
                                autoDB[item.itemID] = nil
                            end
                        end
                    end
                end
                ApplyFilterAndSort()
                RefreshScrollView()
                if UpdateBottomTipCount then UpdateBottomTipCount() end

                local scopeName = filterTokenOnly and "套装兑换物" or "装备"
                if mode == "enable" then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件%s设为：|cff00ff00开启自动拍卖|r (橙装保持人工保护)", GetFBDisplayName(currentFB), count, scopeName))
                elseif mode == "disable" and filterTokenOnly then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件套装兑换物设为：|cffffaa00不自动拍卖 (保留最后人工处理)|r", GetFBDisplayName(currentFB), count))
                elseif mode == "disable" then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件装备设为：|cffff8000全部不自动 (保留人工处理)|r", GetFBDisplayName(currentFB), count))
                elseif mode == "reset" then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 自动拍卖]|r 已将 %s 共 %d 件装备恢复为：默认跟随", GetFBDisplayName(currentFB), count))
                end
            end

            local info1 = LibBG:UIDropDownMenu_CreateInfo()
            info1.text = "|cff00ff00全部开启自动拍卖|r (橙装保持人工)"
            info1.notCheckable = true
            info1.func = function() BatchSetAutoAuction("enable", false) end
            LibBG:UIDropDownMenu_AddButton(info1)

            local info2 = LibBG:UIDropDownMenu_CreateInfo()
            info2.text = "|cffff8000全部关闭自动拍卖 (全部人工)|r"
            info2.notCheckable = true
            info2.func = function() BatchSetAutoAuction("disable", false) end
            LibBG:UIDropDownMenu_AddButton(info2)

            local info3 = LibBG:UIDropDownMenu_CreateInfo()
            info3.text = "|cffffaa00套装：设为不自动 (保留人工)|r"
            info3.notCheckable = true
            info3.func = function() BatchSetAutoAuction("disable", true) end
            LibBG:UIDropDownMenu_AddButton(info3)

            local info4 = LibBG:UIDropDownMenu_CreateInfo()
            info4.text = "|cffaaaaaa全部恢复默认跟随总开关|r"
            info4.notCheckable = true
            info4.func = function() BatchSetAutoAuction("reset", false) end
            LibBG:UIDropDownMenu_AddButton(info4)
        end, "MENU")

        batchSetBtn:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            LibBG:ToggleDropDownMenu(1, nil, batchSetMenu, self, 0, 0)
        end)

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

        -- 6. 滚动列表容器
        scrollFrame = CreateFrame("ScrollFrame", "BGLite_AuctionPresetScrollFrame", f, "FauxScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 28)
        scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, RefreshScrollView)
        end)

        contentFrame = CreateFrame("Frame", nil, scrollFrame)
        contentFrame:SetAllPoints()

        -- 创建 18 行单行控件
        for ri = 1, VISIBLE_ROWS do
            local row = CreateFrame("Button", nil, contentFrame)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -(ri - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, -(ri - 1) * ROW_HEIGHT)

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
                if UpdateBottomTipCount then UpdateBottomTipCount() end
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
                    if UpdateBottomTipCount then UpdateBottomTipCount() end
                end
            end)
            row.clearBtn = clrBt

            rowFrames[ri] = row
        end

        -- 底部说明栏
        local bottomTip = f:CreateFontString(nil, "ARTWORK")
        bottomTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        bottomTip:SetPoint("BOTTOMLEFT", 15, 8)
        bottomTip:SetTextColor(0.8, 0.8, 0.8)
        bottomTip:SetText("提示：取消勾选装备后的【自动】即可禁止自动开拍，留待最后单独人工处理。")

        UpdateBottomTipCount = function()
            if not bottomTip then return end
            local autoDB = BiaoGe.auctionPreset[currentFB] and BiaoGe.auctionPreset[currentFB].autoAuction or {}
            local manualCount = 0
            for k, v in pairs(autoDB) do
                if v == 0 then
                    manualCount = manualCount + 1
                end
            end
            if manualCount > 0 then
                bottomTip:SetText(string.format("提示：已设置 |cffff8000%d|r 件装备【不自动拍卖】(保留最后人工处理)。取消勾选【自动】即可设置。", manualCount))
            else
                bottomTip:SetText("提示：取消勾选装备后的【自动】即可禁止自动开拍，留待最后单独人工处理。")
            end
        end

        -- 拾取后自动全开拍卖控制区
        local autoCheck = CreateFrame("CheckButton", "BGLite_AuctionPreset_AutoAuctionCheck", f, "UICheckButtonTemplate")
        autoCheck:SetSize(22, 22)
        autoCheck:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -210, 4)
        local autoText = autoCheck:CreateFontString(nil, "ARTWORK")
        autoText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        autoText:SetPoint("LEFT", autoCheck, "RIGHT", 2, 0)
        autoText:SetText(L["拾取后自动拍卖"] or "拾取后自动拍卖")
        autoText:SetTextColor(1, 0.82, 0)
        autoCheck:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionOnLoot == 1)
        autoCheck:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            BiaoGe.options = BiaoGe.options or {}
            BiaoGe.options.autoAuctionOnLoot = self:GetChecked() and 1 or 0
            if self:GetChecked() then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已开启【拾取后自动拍卖】功能。团长拾取到Boss装备后将自动发起全团拍卖。")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已关闭【拾取后自动拍卖】功能。")
            end
        end)
        autoCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["拾取后自动拍卖"] or "拾取后自动拍卖", 1, 0.82, 0, true)
            GameTooltip:AddLine("开启后，当团长拾取 Boss 掉落的装备进包时：", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("• 自动聚合同 Boss 掉落的所有未拍卖装备", 0, 1, 0)
            GameTooltip:AddLine("• 优先按本页面设置的预设底价起拍", 0.4, 0.8, 1)
            GameTooltip:AddLine("• 战斗中自动挂起等待，脱战后安全弹出", 1, 0.8, 0.2)
            GameTooltip:AddLine("• 默认显示 5 秒倒计时浮动条，可点击立即全拍或取消", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        autoCheck:SetScript("OnLeave", GameTooltip_Hide)
        f.autoAuctionCheck = autoCheck

        -- 免确认秒拍复选框
        local instantCheck = CreateFrame("CheckButton", "BGLite_AuctionPreset_InstantCheck", f, "UICheckButtonTemplate")
        instantCheck:SetSize(22, 22)
        instantCheck:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -90, 4)
        local instText = instantCheck:CreateFontString(nil, "ARTWORK")
        instText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        instText:SetPoint("LEFT", instantCheck, "RIGHT", 2, 0)
        instText:SetText(L["免确认秒开"] or "免确认秒开")
        instText:SetTextColor(0.8, 0.8, 0.8)
        instantCheck:SetChecked(BiaoGe.options and BiaoGe.options.autoAuctionInstant == 1)
        instantCheck:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            BiaoGe.options = BiaoGe.options or {}
            BiaoGe.options.autoAuctionInstant = self:GetChecked() and 1 or 0
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

        -- 页面显示时同步复选框状态
        f:HookScript("OnShow", function()
            if BiaoGe.options then
                autoCheck:SetChecked(BiaoGe.options.autoAuctionOnLoot == 1)
                instantCheck:SetChecked(BiaoGe.options.autoAuctionInstant == 1)
            end
            if UpdateBottomTipCount then
                UpdateBottomTipCount()
            end
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

-- 自启动检测
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
