local AddonName, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RGB_16 = ns.RGB_16 or (BG and BG.RGB_16)
local GetClassRGB = ns.GetClassRGB or (BG and BG.GetClassRGB)
local GetItemID = ns.GetItemID or (BG and BG.GetItemID)

local AuctionPreset = {}
ns.AuctionPreset = AuctionPreset

BG.AuctionPresetMainFrameTabNum = BG.AuctionPresetMainFrameTabNum or 104

-- 辅助工具：提取装备 ID
local function SafeGetItemID(text)
    if not text or text == "" then return nil end
    local id = tostring(text):match("item:(%d+)")
    if id then return tonumber(id) end
    if tonumber(text) then return tonumber(text) end
    if GetItemInfoInstant then
        local id2 = GetItemInfoInstant(text)
        if id2 then return tonumber(id2) end
    end
    return nil
end

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
    end

    local currentFB = BiaoGe.auctionPreset.currentFB
    local currentItems = {}
    local filteredItems = {}
    local mainFrame
    local scrollFrame
    local contentFrame
    local rowFrames = {}
    local searchKeyword = ""

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
        BiaoGe.auctionPreset[currentFB] = BiaoGe.auctionPreset[currentFB] or { money = {} }
        currentItems = CollectFBItems(currentFB)
        ApplyFilterAndSort()
        RefreshScrollView()
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
                OnShow = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if edit then
                        edit:SetNumeric(true)
                        edit:SetFocus()
                    end
                end,
                OnAccept = function(self)
                    local edit = self.editBox or self.EditBox or (self.GetName and _G[self:GetName() .. "EditBox"])
                    if not edit and self:GetParent() then
                        local p = self:GetParent()
                        edit = p.editBox or p.EditBox or (p.GetName and _G[p:GetName() .. "EditBox"])
                    end
                    local text = edit and edit:GetText() or ""
                    local val = tonumber(text)
                    if val and val > 0 then
                        local moneyDB = BiaoGe.auctionPreset[currentFB].money
                        for _, item in ipairs(currentItems) do
                            moneyDB[item.itemID] = val
                        end
                        ApplyFilterAndSort()
                        RefreshScrollView()
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已将 %s 所有装备预设底价更新为：%dG", GetFBDisplayName(currentFB), val))
                    end
                end,
                EditBoxOnEnterPressed = function(self)
                    local parent = self:GetParent()
                    local text = self:GetText()
                    local val = tonumber(text)
                    if val and val > 0 then
                        local moneyDB = BiaoGe.auctionPreset[currentFB].money
                        for _, item in ipairs(currentItems) do
                            moneyDB[item.itemID] = val
                        end
                        ApplyFilterAndSort()
                        RefreshScrollView()
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已将 %s 所有装备预设底价更新为：%dG", GetFBDisplayName(currentFB), val))
                    end
                    parent:Hide()
                end,
            }
            StaticPopup_Show("BGLITE_BATCH_PRESET_PRICE")
        end)

        -- 清空当前副本按钮
        local clearBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
        clearBtn:SetSize(72, 22)
        clearBtn:SetPoint("RIGHT", topBar, "RIGHT", -5, 0)
        clearBtn:SetText(L["全部清空"] or "全部清空")
        clearBtn:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            StaticPopupDialogs["BGLITE_CLEAR_PRESET_CONFIRM"] = {
                text = string.format("确定要清空【%s】的所有预设起拍价和起拍语吗？", GetFBDisplayName(currentFB)),
                button1 = OKAY or "确定",
                button2 = CANCEL or "取消",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                OnAccept = function()
                    BiaoGe.auctionPreset[currentFB].money = {}
                    ApplyFilterAndSort()
                    RefreshScrollView()
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format("已清空 %s 的所有预设价格", GetFBDisplayName(currentFB)))
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
            { text = L["预设起拍语 (附加喊话)"] or "预设起拍语 (附加喊话)", width = 200, justify = "LEFT" },
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
            row.tipsEdit = tEdit
            rx = rx + columns[5].width + 10

            -- 清空按钮
            local clrBt = CreateFrame("Button", nil, row)
            clrBt:SetSize(16, 16)
            clrBt:SetPoint("CENTER", row, "LEFT", rx + columns[6].width / 2, 0)
            clrBt:SetNormalTexture("interface/raidframe/readycheck-notready")
            clrBt:SetHighlightTexture("interface/raidframe/readycheck-notready")
            clrBt:SetScript("OnClick", function()
                if BG.PlaySound then BG.PlaySound(1) end
                if row.data then
                    local moneyDB = BiaoGe.auctionPreset[currentFB].money
                    moneyDB[row.data.itemID] = nil
                    moneyDB[row.data.itemID .. "tips"] = nil
                    row.data.price = 0
                    row.data.tips = ""
                    pEdit:SetText("")
                    tEdit:SetText("")
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
        bottomTip:SetText("提示：团长右键装备开拍时自动填入起拍价；按住 ALT 点击主表格 Boss 名字，可一键将该 Boss 所有预设装备全部开拍！")

        mainFrame = f
        BG.AuctionPresetMainFrame = f

        -- 初始化数据
        ReloadCurrentFB(currentFB)

        -- 注册到底部 Tab
        if BG.Create_TabButton then
            local tabBtn = BG.Create_TabButton(BG.AuctionPresetMainFrameTabNum, L["预设价格"] or "预设价格", f, 100)
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

    -- ② Alt + 点击 Boss 名字：一键全开拍
    function AuctionPreset.HookBossTitleClicks()
        if not (BG and BG.Frame and BG.FBtable) then return end
        for _, FB in ipairs(BG.FBtable) do
            if BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
                for b = 1, BG.Maxb[FB] do
                    local bossFrame = BG.Frame[FB]["boss" .. b]
                    local bossNameBtn = bossFrame and bossFrame.bossName
                    if bossNameBtn and not bossNameBtn.hasHookedAuctionPreset then
                        bossNameBtn.hasHookedAuctionPreset = true
                        bossNameBtn:HookScript("OnMouseUp", function(self, button)
                            if not (BG.IsML and IsAltKeyDown()) then return end
                            local preset = BiaoGe.auctionPreset and BiaoGe.auctionPreset[FB]
                            local moneyDB = preset and preset.money
                            if not moneyDB then return end

                            local itemsToAuction = {}
                            local maxi = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
                            for i = 1, maxi do
                                local cell = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                                if cell then
                                    local link = cell:GetText()
                                    local itemID = SafeGetItemID(link)
                                    if itemID and moneyDB[itemID] then
                                        tinsert(itemsToAuction, { link = link, anchor = cell })
                                    end
                                end
                            end

                            if #itemsToAuction > 0 then
                                if BG.PlaySound then BG.PlaySound(1) end
                                for idx, it in ipairs(itemsToAuction) do
                                    C_Timer.After((idx - 1) * 1.0, function()
                                        if BG.StartAuction then
                                            BG.StartAuction(it.link, it.anchor, nil, nil, true, true)
                                        end
                                    end)
                                end
                            end
                        end)
                    end
                end
            end
        end
    end

    -- ③ 悬停装备显示预设起拍价与起拍语
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

    -- 首次及延迟执行 Boss 标题 Hook
    AuctionPreset.HookBossTitleClicks()
    C_Timer.After(1, AuctionPreset.HookBossTitleClicks)
    C_Timer.After(3, AuctionPreset.HookBossTitleClicks)
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
