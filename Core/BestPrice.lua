local AddonName, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RGB_16 = ns.RGB_16 or (BG and BG.RGB_16)
local GetClassRGB = ns.GetClassRGB or (BG and BG.GetClassRGB)

local BestPrice = {}
ns.BestPrice = BestPrice

-- 强化版 SafeGetItemID：支持完整超链接、纯数字、纯item字符串以及装备名称
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

local function GetRealmAndPlayer()
    local realmID = GetRealmID()
    local player = UnitName("player")
    return realmID, player
end

-- 全局重写快捷键判定：支持 Alt + 右键 快速设置心理价格
function BG.IsSetBestPriceKeyDown(isRightClick)
    if BG.SetBestPrice then
        if BG.IsML then
            return IsAltKeyDown() and IsControlKeyDown()
        else
            return isRightClick and IsAltKeyDown()
        end
    end
    return false
end

function ns.InitBestPriceModule()
    if BestPrice.isInitialized then return end
    BestPrice.isInitialized = true

    local realmID, player = GetRealmAndPlayer()
    BiaoGe = BiaoGe or {}
    BiaoGe.bestPrice = BiaoGe.bestPrice or {}
    BiaoGe.bestPrice[realmID] = BiaoGe.bestPrice[realmID] or {}
    BiaoGe.bestPrice[realmID][player] = BiaoGe.bestPrice[realmID][player] or {}

    local bestPriceDB = BiaoGe.bestPrice[realmID][player]
    bestPriceDB.money = bestPriceDB.money or ""

    local mainFrame
    local rows = {}
    local entryButton
    local setPriceFrame
    local SetBestPrice
    local CreateSetPriceFrame
    local CreateXinLiJiaGeFrame

    local function NormalizeRow(ri)
        bestPriceDB[ri] = bestPriceDB[ri] or {}
        local data = bestPriceDB[ri]
        data.enabled = data.enabled ~= false
        data.equipment = data.equipment or ""
        data.price = tonumber(data.price) or 0
        return data
    end

    local function BestPriceIsFull(itemID)
        local hasEmptyRow = false
        for ri = 1, 10 do
            local data = NormalizeRow(ri)
            local equipment = data.equipment or ""
            if itemID and SafeGetItemID(equipment) == itemID then
                return false
            end
            if equipment == "" then
                hasEmptyRow = true
            end
        end
        return not hasEmptyRow
    end

    local function GetBestPriceCount()
        local count = 0
        for ri = 1, 10 do
            local data = NormalizeRow(ri)
            if data.enabled and data.price > 0 and SafeGetItemID(data.equipment) then
                count = count + 1
            end
        end
        return count
    end

    local function UpdateEntryButtonText()
        if entryButton then
            local count = GetBestPriceCount()
            local r, g, b = 0.5, 0.5, 0.5
            if count == 10 then
                r, g, b = 1, 0, 0
            elseif count > 0 then
                r, g, b = 0, 1, 0
            end
            local countStr = RGB_16 and RGB_16(count, r, g, b) or tostring(count)
            entryButton:SetText(L["心理价格"] .. "(" .. countStr .. ")")
        end
    end

    local function RefreshRow(row, data)
        row.cb:SetChecked(data.enabled)
        row.editEquip:SetText(data.equipment or "")
        row.editPrice:SetText(data.price ~= 0 and data.price or "")
        row.UpdateEquipInfo()
        row.UpdateRowAlpha()
    end

    local function RefreshAllRows()
        for ri = 1, 10 do
            if rows[ri] then
                RefreshRow(rows[ri], NormalizeRow(ri))
            end
        end
        UpdateEntryButtonText()
    end

    local function SetAllRowsEnabled(enabled)
        for ri = 1, 10 do
            NormalizeRow(ri).enabled = enabled and true or false
        end
        RefreshAllRows()
    end

    local function ClearAllRows()
        for ri = 1, 10 do
            local data = NormalizeRow(ri)
            data.enabled = true
            data.equipment = ""
            data.price = 0
        end
        RefreshAllRows()
    end

    SetBestPrice = function(link, price)
        local itemID = SafeGetItemID(link)
        local rowIndex

        for ri = 1, 10 do
            local data = NormalizeRow(ri)
            if itemID and SafeGetItemID(data.equipment) == itemID then
                rowIndex = ri
                break
            end
            if not rowIndex and data.equipment == "" then
                rowIndex = ri
            end
        end

        rowIndex = rowIndex or 10

        local data = NormalizeRow(rowIndex)
        data.enabled = true
        data.equipment = link or ""
        data.price = tonumber(price) or 0

        if rows[rowIndex] then
            RefreshRow(rows[rowIndex], data)
        end
        UpdateEntryButtonText()
    end

    local function SaveBestPrice(link, money)
        money = tonumber(money) or 0
        if money <= 0 then return end
        local itemID = SafeGetItemID(link)
        if BestPriceIsFull(itemID) then
            UIErrorsFrame:AddMessage(L["心理价格已满，请先删除一条心理价格。"], 1, 0, 0)
            return
        end
        SetBestPrice(link, money)
        local numText = (BG.FormatNumber and BG.FormatNumber(money, 2)) or tostring(money)
        local msg = string.format(L["%s的心理价格已设为：%s"], link, numText)
        if BG.SendSystemMessage then
            BG.SendSystemMessage(msg)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. msg)
        end
        return true
    end

    -- 供外部调用的核心 API
    function BG.GetBestPrice(itemID)
        itemID = tonumber(itemID)
        if itemID then
            for ri = 1, 10 do
                local data = NormalizeRow(ri)
                if data.enabled and data.price > 0 and SafeGetItemID(data.equipment) == itemID then
                    return data.price
                end
            end
        end
        return nil
    end

    function BG.DisableBestPrice(itemID)
        itemID = tonumber(itemID)
        if not itemID then return end

        for ri = 1, 10 do
            local data = NormalizeRow(ri)
            if SafeGetItemID(data.equipment) == itemID then
                data.enabled = false
                if rows[ri] then
                    RefreshRow(rows[ri], data)
                end
                UpdateEntryButtonText()
                return true
            end
        end
    end

    function BG.SetBestPrice(link, anchor)
        if not link or link == "" then return end
        local itemID = SafeGetItemID(link)
        if not itemID then return end

        if BestPriceIsFull(itemID) then
            UIErrorsFrame:AddMessage(L["心理价格已满，请先删除一条心理价格。"], 1, 0, 0)
            GameTooltip:Hide()
            return
        end

        local f = CreateSetPriceFrame()
        f.link = link
        f.iconFrame.link = link
        f.iconFrame.itemID = itemID

        local function FillItemData()
            local name, itemLink, quality, level, _, itemType, itemSubType, _, itemEquipLoc, Texture,
            _, classID, subclassID, bindType = GetItemInfo(link)

            local r, g, b = GetItemQualityColor(quality or 1)
            f.iconFrame:SetBackdropBorderColor(r, g, b, 1)
            if Texture then f.iconFrame.tex:SetTexture(Texture) end
            f.iconFrame.level:SetText(level or "")
            f.iconFrame.level:SetTextColor(r, g, b)
            f.iconFrame.bind:SetShown(bindType == 2)
            f.itemText:SetText((link or name or ""):gsub("%[", ""):gsub("%]", ""))

            local classText = (BG.GetTooltipClassText and BG.GetTooltipClassText(itemID)) or ""
            if itemEquipLoc and _G[itemEquipLoc] then
                if classID == 2 then
                    f.itemTypeText:SetText((itemSubType or "") .. "  " .. classText)
                else
                    f.itemTypeText:SetText(_G[itemEquipLoc] .. " " .. (itemSubType or "") .. "  " .. classText)
                end
            else
                f.itemTypeText:SetText(classText)
            end
        end

        FillItemData()
        if BG.OnItemLoad then
            BG.OnItemLoad(link):ContinueOnItemLoad(FillItemData)
        end

        f:ClearAllPoints()
        if anchor and anchor:IsVisible() then
            f:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
        elseif entryButton and entryButton:IsVisible() then
            f:SetPoint("BOTTOM", entryButton, "TOP", 0, 5)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        f:Show()
        f.edit:SetText(bestPriceDB.money or "")
        f.edit:SetFocus()
        f.edit:SetCursorPosition(#f.edit:GetText())
        GameTooltip:Hide()
    end

    -- 快捷小弹窗（设置单个装备心理价格）
    CreateSetPriceFrame = function()
        if BG.StartAucitonFrame then BG.StartAucitonFrame:Hide() end
        if setPriceFrame then return setPriceFrame end

        local f = CreateFrame("Frame", "BGLite_SetPricePopupFrame", BG.MainFrame or UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 2,
        })
        f:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        f:SetFrameLevel(210)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:SetSize(250, 120)
        f:SetScript("OnMouseDown", function(self)
            self:StartMoving()
            if self.edit then self.edit:ClearFocus() end
        end)
        f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
        f:Hide()

        if BG.CreateCloseButton then
            BG.CreateCloseButton(f, 0, 0)
            f.CloseButton:SetSize(30, 30)
            f.CloseButton:SetFrameLevel(f.CloseButton:GetParent():GetFrameLevel() + 50)
        else
            local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", 2, 2)
            f.CloseButton = close
        end

        -- 装备展示区域
        f.itemFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
        f.itemFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
        f.itemFrame:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -2, -35)
        f.itemFrame:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
        })
        f.itemFrame:SetBackdropColor(0, 0, 0, 0.8)
        f.itemFrame:EnableMouse(true)
        f.itemFrame:SetScript("OnMouseDown", function(self)
            self:GetParent():GetScript("OnMouseDown")(self:GetParent())
        end)
        f.itemFrame:SetScript("OnMouseUp", function(self)
            self:GetParent():GetScript("OnMouseUp")(self:GetParent())
        end)

        f.iconFrame = CreateFrame("Frame", nil, f.itemFrame, "BackdropTemplate")
        f.iconFrame:SetBackdrop({
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 1.5,
        })
        f.iconFrame:SetPoint("TOPLEFT", 0, 0)
        f.iconFrame:SetSize(31, 31)
        f.iconFrame:EnableMouse(true)
        f.iconFrame:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                GameTooltip:ClearLines()
                if BG.SetSpecIDToLink then
                    GameTooltip:SetHyperlink(BG.SetSpecIDToLink(self.link))
                else
                    GameTooltip:SetHyperlink(self.link)
                end
                GameTooltip:Show()
            end
        end)
        f.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.iconFrame.tex = f.iconFrame:CreateTexture(nil, "BACKGROUND")
        f.iconFrame.tex:SetAllPoints()
        f.iconFrame.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)

        f.iconFrame.level = f.iconFrame:CreateFontString(nil, "OVERLAY")
        f.iconFrame.level:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        f.iconFrame.level:SetPoint("BOTTOM", f.iconFrame, "BOTTOM", 0, 1)

        f.iconFrame.bind = f.iconFrame:CreateFontString(nil, "OVERLAY")
        f.iconFrame.bind:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        f.iconFrame.bind:SetPoint("TOP", f.iconFrame, 0, -2)
        f.iconFrame.bind:SetText(L["装绑"])
        f.iconFrame.bind:SetTextColor(0, 1, 0)

        f.itemText = f.itemFrame:CreateFontString(nil, "OVERLAY")
        f.itemText:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        f.itemText:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", 4, -2)
        f.itemText:SetPoint("RIGHT", f.itemFrame, "RIGHT", -22, 0)
        f.itemText:SetJustifyH("LEFT")
        f.itemText:SetWordWrap(false)

        f.itemTypeText = f.itemFrame:CreateFontString(nil, "OVERLAY")
        f.itemTypeText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        f.itemTypeText:SetPoint("BOTTOMLEFT", f.iconFrame, "BOTTOMRIGHT", 4, 1)
        f.itemTypeText:SetPoint("RIGHT", f.itemText, "RIGHT", 0, 0)
        f.itemTypeText:SetHeight(12)
        f.itemTypeText:SetJustifyH("LEFT")
        f.itemTypeText:SetWordWrap(false)

        -- 心理价格输入框
        local label = f:CreateFontString(nil, "ARTWORK")
        label:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        label:SetPoint("TOPLEFT", f.itemFrame, "BOTTOMLEFT", 5, -10)
        label:SetSize(90, 20)
        label:SetTextColor(1, 0.82, 0)
        label:SetJustifyH("RIGHT")
        label:SetText(L["心理价格："])

        local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        editBox:SetSize(95, 20)
        editBox:SetPoint("LEFT", label, "RIGHT", 5, 0)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(8)
        editBox:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            self:GetParent():Hide()
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            self:GetParent().ok:Click()
        end)
        editBox:SetScript("OnHide", function(self)
            self:ClearFocus()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            if BG.UpdateTwo0 then BG.UpdateTwo0(self) end
            bestPriceDB.money = self:GetText()
        end)
        f.edit = editBox

        -- 确定与取消按钮
        local okBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        okBtn:SetSize(85, 22)
        okBtn:SetPoint("BOTTOM", -50, 10)
        okBtn:SetText(OKAY or "确定")
        okBtn:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            local p = self:GetParent()
            if SaveBestPrice(p.link, p.edit:GetText()) then
                p:Hide()
            end
        end)
        f.ok = okBtn

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(85, 22)
        cancelBtn:SetPoint("BOTTOM", 50, 10)
        cancelBtn:SetText(CANCEL or "取消")
        cancelBtn:SetScript("OnClick", function(self)
            self:GetParent():Hide()
        end)
        f.cancel = cancelBtn

        setPriceFrame = f
        return f
    end

    -- 10 格完整管理清单 UI
    local headerW = { 40, 190, 100, 40 }
    local function CreateRow(parent, ri, y)
        local data = NormalizeRow(ri)
        local x = 20

        local widgets = {}
        local editEquip
        local function UpdateRowAlpha()
            local a = data.enabled and 1 or 0.5
            for _, w in ipairs(widgets) do
                w:SetAlpha(a)
            end
        end

        local function ClearEquipInfo()
            if editEquip.icon then editEquip.icon:SetTexture(nil) end
            if BG.BindOnEquip then BG.BindOnEquip(editEquip) end
            if BG.LevelText then BG.LevelText(editEquip) end
        end

        local function UpdateEquipInfo()
            local itemText = editEquip:GetText()
            local itemID = SafeGetItemID(itemText)
            if not itemID then
                ClearEquipInfo()
                return
            end

            local function SetInfo()
                if editEquip:GetText() ~= itemText then return end
                local name, link, quality, level, _, _, _, _, _, Texture,
                _, typeID, _, bindType = GetItemInfo(itemText)
                if editEquip.icon then editEquip.icon:SetTexture(Texture) end
                if BG.BindOnEquip then BG.BindOnEquip(editEquip, bindType) end
                if BG.LevelText then BG.LevelText(editEquip, level, typeID) end
            end

            if BG.OnItemLoad then
                BG.OnItemLoad(itemText):ContinueOnItemLoad(SetInfo)
            else
                SetInfo()
            end
        end

        -- 第 1 列：启用 CheckButton
        local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x + 5, y)
        cb:SetChecked(data.enabled)
        cb:SetHitRectInsets(0, 0, 0, 0)
        cb:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            data.enabled = self:GetChecked() and true or false
            UpdateRowAlpha()
            UpdateEntryButtonText()
        end)
        tinsert(widgets, cb)

        x = x + headerW[1] + 5

        -- 第 2 列：装备输入框
        editEquip = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editEquip:SetSize(headerW[2], 20)
        editEquip:SetPoint("TOPLEFT", x, y)
        editEquip:SetTextInsets(18, 28, 0, 0)
        editEquip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        editEquip.icon = editEquip:CreateTexture(nil, "ARTWORK")
        editEquip.icon:SetPoint("LEFT", 0, 0)
        editEquip.icon:SetSize(16, 16)
        editEquip.icon:SetTexCoord(unpack(BG.iconTexCoord or { 0.08, 0.92, 0.08, 0.92 }))
        editEquip:SetText(data.equipment or "")
        editEquip:SetAutoFocus(false)
        editEquip:SetScript("OnTextChanged", function(self)
            data.equipment = self:GetText()
            UpdateEquipInfo()
            UpdateEntryButtonText()
        end)
        if BG.SetEditBaseClass then BG.SetEditBaseClass(editEquip) end

        if BG.OnEnterDelay then
            BG.OnEnterDelay(editEquip, function(self)
                local link = self:GetText()
                if BG.Show_AllHighlight then BG.Show_AllHighlight(link) end
                local itemID = SafeGetItemID(link)
                if itemID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                    GameTooltip:ClearLines()
                    if BG.SetSpecIDToLink then
                        GameTooltip:SetHyperlink(BG.SetSpecIDToLink(link))
                    else
                        GameTooltip:SetHyperlink(link)
                    end
                    GameTooltip:Show()
                end
            end, BG.itemOnEnterDelay or 0.2)
        end

        if BG.OnLeaveDelay then
            BG.OnLeaveDelay(editEquip, function(self)
                self.isEnter = false
                GameTooltip:Hide()
                if BG.Hide_AllHighlight then BG.Hide_AllHighlight() end
            end)
        end
        tinsert(widgets, editEquip)

        x = x + headerW[2] + 5

        -- 第 3 列：心理价格输入框
        local editPrice = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editPrice:SetSize(headerW[3], 20)
        editPrice:SetPoint("TOPLEFT", x, y)
        editPrice:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        editPrice:SetText(data.price ~= 0 and data.price or "")
        editPrice:SetAutoFocus(false)
        editPrice:SetNumeric(true)
        editPrice:SetScript("OnTextChanged", function(self)
            local num = tonumber(self:GetText())
            data.price = num or 0
            UpdateEntryButtonText()
        end)
        if BG.SetEditBaseClass then BG.SetEditBaseClass(editPrice) end
        tinsert(widgets, editPrice)

        x = x + headerW[3] + 5

        -- 第 4 列：清空该行按钮
        local clearBt = CreateFrame("Button", nil, parent)
        clearBt:SetSize(16, 16)
        clearBt:SetPoint("TOPLEFT", x + 0, y - 2)
        clearBt:SetNormalTexture("interface/raidframe/readycheck-notready")
        clearBt:SetHighlightTexture("interface/raidframe/readycheck-notready")
        clearBt:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            editEquip:SetText("")
            editPrice:SetText("")
            cb:SetChecked(true)
            data.enabled = true
            data.equipment = ""
            data.price = 0
            UpdateRowAlpha()
            UpdateEquipInfo()
            UpdateEntryButtonText()
        end)
        tinsert(widgets, clearBt)

        UpdateEquipInfo()
        UpdateRowAlpha()

        return { cb = cb, editEquip = editEquip, editPrice = editPrice, clearBt = clearBt, UpdateRowAlpha = UpdateRowAlpha, UpdateEquipInfo = UpdateEquipInfo }
    end

    local function UpdateTip(tip)
        tip:SetTextColor(0.8, 0.8, 0.8)
        tip:SetText(L["提示：ALT+右键点击表格装备，可添加心理价格。"])
    end

    CreateXinLiJiaGeFrame = function(parent)
        if mainFrame then
            mainFrame:SetShown(not mainFrame:IsShown())
            mainFrame:ClearAllPoints()
            if parent then
                mainFrame:SetPoint("BOTTOM", parent, "TOP", 0, 5)
            else
                mainFrame:SetPoint("CENTER", BG.MainFrame or UIParent, "CENTER")
            end
            UpdateTip(mainFrame.tip)
            return
        end

        local f = CreateFrame("Frame", "BGLite_BestPriceMainFrame", parent or BG.MainFrame or UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 16,
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        local r, g, b = 0.2, 0.8, 1.0
        if GetClassRGB then
            r, g, b = GetClassRGB(nil, "player")
        end
        f:SetBackdropBorderColor(r, g, b, 1)
        f:SetFrameLevel(205)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:SetToplevel(true)
        f:SetSize(410, 338)
        if parent then
            f:SetPoint("BOTTOM", parent, "TOP", 0, 5)
        else
            f:SetPoint("CENTER", BG.MainFrame or UIParent, "CENTER")
        end
        f:SetClampedToScreen(true)
        f:SetScript("OnMouseDown", function(self)
            if BG.ClearFocus then BG.ClearFocus() end
            self:StartMoving()
        end)
        f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

        f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.CloseButton:SetPoint("TOPRIGHT", -2, -2)

        local title = f:CreateFontString(nil, "ARTWORK")
        title:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        title:SetPoint("TOP", 0, -7)
        title:SetText(L["预设心理价格"])
        title:SetTextColor(0, 0.9, 1)

        -- 表头
        local headerX = 20
        local headerY = -30
        local headers = { L["启用"], L["装备"], L["心理价格"], "" }
        for i = 1, 4 do
            local ht = f:CreateFontString(nil, "ARTWORK")
            ht:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
            ht:SetPoint("TOPLEFT", headerX, headerY)
            ht:SetText(headers[i])
            ht:SetTextColor(1, 0.82, 0)
            ht:SetWidth(headerW[i])
            ht:SetJustifyH(i == 4 and "CENTER" or "LEFT")
            headerX = headerX + headerW[i] + 5
        end

        -- 10 行装备配置
        local rowStartY = headerY - 18
        local rowHeight = 22
        for ri = 1, 10 do
            rows[ri] = CreateRow(f, ri, rowStartY - (ri - 1) * rowHeight)
        end

        local tip = f:CreateFontString(nil, "ARTWORK")
        tip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        tip:SetPoint("BOTTOM", f, "BOTTOM", 0, 46)
        f.tip = tip
        UpdateTip(tip)

        local buttonInfo = {
            { text = L["全部启用"], onClick = function() SetAllRowsEnabled(true) end },
            { text = L["全部禁用"], onClick = function() SetAllRowsEnabled(false) end },
            { text = L["全部清空"], onClick = ClearAllRows },
            { text = L["关闭"], onClick = function() f:Hide() end },
        }
        local buttonW = 82
        local buttonGap = 8
        local totalW = #buttonInfo * buttonW + (#buttonInfo - 1) * buttonGap
        local startX = -totalW / 2 + buttonW / 2
        for i, info in ipairs(buttonInfo) do
            local bt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            bt:SetSize(buttonW, 22)
            bt:SetPoint("BOTTOM", f, "BOTTOM", startX + (i - 1) * (buttonW + buttonGap), 12)
            bt:SetText(info.text)
            bt:SetScript("OnClick", function(self)
                if i ~= #buttonInfo and BG.PlaySound then
                    BG.PlaySound(1)
                end
                info.onClick()
            end)
        end

        mainFrame = f
    end

    -- 创建主界面挂载按钮【心理价格(x)】
    function BestPrice.CreateEntryButton(parentFrame)
        if entryButton then return entryButton end
        local parent = parentFrame or (BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2) or BG.MainFrame
        if not parent then return nil end

        local bt = CreateFrame("Button", "BGLite_ButtonBestPrice", parent, "UIPanelButtonTemplate")
        bt:SetSize(110, 22)
        if parent == (BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2) then
            bt:SetPoint("LEFT", parent, "RIGHT", 35, 0)
        else
            bt:SetPoint("TOPLEFT", BG.MainFrame, "TOPLEFT", 280, -32)
        end
        entryButton = bt
        BestPrice.entryButton = bt
        UpdateEntryButtonText()

        bt:SetScript("OnClick", function(self)
            if BG.PlaySound then BG.PlaySound(1) end
            CreateXinLiJiaGeFrame(self)
        end)

        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["预设心理价格"], 1, 1, 1)
            GameTooltip:AddLine(L["点击展开心理价格管理面板。"], 1, 0.82, 0, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["开拍自动出价接管："], 0, 0.9, 1)
            GameTooltip:AddLine(L["当拍卖清单中的装备时，插件会自动填入该心理价并开启自动出价，能捡漏则捡漏、逐级加一手跟进直至封顶。"], 0.85, 0.85, 0.85, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["快捷设定：按住 ALT 并右键点击任何装备格子即可快速添加！"], 0.2, 1, 0.6, true)
            GameTooltip:Show()
        end)
        bt:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return bt
    end

    -- 7. 开拍自动出价逻辑（与 AuctionWA 联动）
    local function SetBestPriceAuto(f, itemID)
        if not BG.GetBestPrice then return end
        if not (f and f.autoFrame and f.autoMoneyEdit and f.autoButton) then return end
        if f.isAuto then return end
        local price = tonumber(BG.GetBestPrice(itemID))
        if not price or price <= 0 then return end
        local money = tonumber(f.money) or 0
        if f.start then
            if price < money then return end
        elseif price <= money then
            return
        end

        C_Timer.After((math.random(400, 600)) / 1000, function()
            if not f.autoFrame or not f.autoMoneyEdit or not f.autoButton then return end
            f.autoFrame:Show()
            f.autoMoneyEdit:SetText(price)
            f.autoMoneyEdit:SetCursorPosition(0)
            C_Timer.After(0, function()
                if f.autoButton and f.autoButton:IsEnabled() then
                    f.autoButton:Click()
                    if f.isAuto and BG.DisableBestPrice then
                        BG.DisableBestPrice(itemID)
                    end
                    local linkText = f.link or ("item:" .. itemID)
                    local numText = (BG.FormatNumber and BG.FormatNumber(price, 2)) or tostring(price)
                    local msg = string.format(L["已开始自动出价：%s %s。"], linkText, numText)
                    if BG.SendSystemMessage then
                        BG.SendSystemMessage(msg)
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. msg)
                    end
                end
            end)
        end)
        return true
    end

    -- 8. 折叠拍卖窗出价高亮与布局优化增强注入 (BGLite_Plus 独立 Hook)
    local function GetColoredPlayerName(name)
        if not name or name == "" then return "" end
        local shortName = name:match("^([^-]+)") or name
        if BGA and BGA.aura_env and BGA.aura_env.SetClassCFF then
            local cName = BGA.aura_env.SetClassCFF(shortName)
            if cName and cName ~= "" then
                return cName
            end
        end
        local _, classFile = UnitClass(shortName)
        if classFile then
            local colorHex = select(4, GetClassColor(classFile))
            if colorHex then
                return "|c" .. colorHex .. shortName .. "|r"
            end
        end
        return shortName
    end

    local function UpdateSmallWindowMoney(f, money, player)
        if not (f and f.IsSmallWindow) then return end
        if not (f.currentMoneyFrame and f.currentMoneyText) then return end

        local currentMoney = money or f.money or 0
        local currentPlayer = player or f.player
        local myName = (BGA and BGA.aura_env and BGA.aura_env.GN and BGA.aura_env.GN()) or UnitName("player")
        local isMe = (currentPlayer and currentPlayer ~= "" and currentPlayer == myName)
        local moneyColor = isMe and "|cff00FF00" or "|cffFFD100"
        local formatNum = (BGA and BGA.aura_env and BGA.aura_env.FormatNumber and BGA.aura_env.FormatNumber(currentMoney)) or tostring(currentMoney)

        local displayText = ""
        if currentPlayer and currentPlayer ~= "" and not f.start then
            local nameText = isMe and ("|cff00FF00" .. (L["你"] or "你") .. "|r") or GetColoredPlayerName(currentPlayer)
            displayText = nameText .. " " .. moneyColor .. formatNum .. "|r"
        else
            displayText = moneyColor .. formatNum .. "|r"
        end

        f.currentMoneyText:SetText(displayText)
        f.currentMoneyText:SetJustifyH("RIGHT")

        local textWidth = (f.currentMoneyText.GetStringWidth and f.currentMoneyText:GetStringWidth()) or 80
        local frameWidth = math.max(60, math.min(145, textWidth + 8))

        f.currentMoneyFrame:ClearAllPoints()
        f.currentMoneyFrame:SetSize(frameWidth, 20)
        if f.itemFrame then
            f.currentMoneyFrame:SetFrameLevel(f.itemFrame:GetFrameLevel() + 5)
        end
        f.currentMoneyFrame:SetPoint("RIGHT", f.hide, "LEFT", -5, 0)

        if f.itemFrame and f.itemFrame.itemNameText and f.itemFrame.iconFrame then
            f.itemFrame.itemNameText:ClearAllPoints()
            f.itemFrame.itemNameText:SetPoint("LEFT", f.itemFrame.iconFrame, "RIGHT", 2, 0)
            f.itemFrame.itemNameText:SetPoint("RIGHT", f.currentMoneyFrame, "LEFT", -4, 0)
            f.itemFrame.itemNameText:SetWordWrap(false)
        end
    end

    local function HookAuctionFrameSmallWindow(f)
        if not f or f.hasHookedSmallWindow then return end
        f.hasHookedSmallWindow = true

        if f.hide then
            f.hide:HookScript("OnClick", function(self)
                if f.IsSmallWindow then
                    UpdateSmallWindowMoney(f)
                else
                    if f.currentMoneyFrame then
                        f.currentMoneyFrame:SetSize(190, 20)
                        f.currentMoneyFrame:SetFrameLevel(f:GetFrameLevel() + 11)
                    end
                    if f.itemFrame and f.itemFrame.itemNameText and f.itemFrame.iconFrame then
                        f.itemFrame.itemNameText:ClearAllPoints()
                        f.itemFrame.itemNameText:SetPoint("TOPLEFT", f.itemFrame.iconFrame, "TOPRIGHT", 2, -2)
                        f.itemFrame.itemNameText:SetWidth(f.itemFrame:GetWidth() - f.itemFrame:GetHeight() - 50)
                    end
                end
            end)
        end

        if f.IsSmallWindow then
            UpdateSmallWindowMoney(f)
        end
        C_Timer.After(0.05, function()
            if f and f.IsSmallWindow then
                UpdateSmallWindowMoney(f)
            end
        end)
    end

    -- Hook 底层 BGA.aura_env.SetMoney
    local function HookBgaSetMoney()
        if BGA and BGA.aura_env and BGA.aura_env.SetMoney and not BGA.aura_env._orig_SetMoney_Plus then
            BGA.aura_env._orig_SetMoney_Plus = BGA.aura_env.SetMoney
            BGA.aura_env.SetMoney = function(bidFrame, money, player)
                BGA.aura_env._orig_SetMoney_Plus(bidFrame, money, player)
                if bidFrame and bidFrame.IsSmallWindow then
                    if bidFrame.updateFrame then
                        bidFrame.updateFrame:Show()
                    end
                    UpdateSmallWindowMoney(bidFrame, money, player)
                end
            end
        end
    end

    -- 安全包装 HookCreateAuction
    local orig_HookCreateAuction = BG.HookCreateAuction
    BG.HookCreateAuction = function(f)
        if orig_HookCreateAuction then
            orig_HookCreateAuction(f)
        end

        HookBgaSetMoney()
        if f then
            HookAuctionFrameSmallWindow(f)
        end

        if f and f.itemID then
            local leiting
            if BG.GetAllFB and BG.GetLeiTingItem then
                for _, FB in ipairs(BG.GetAllFB()) do
                    if BG.GetLeiTingItem(f.itemID, FB) ~= f.itemID then
                        leiting = BG.GetLeiTingItem(f.itemID, FB)
                        break
                    end
                end
            end
            local itemID = leiting or f.itemID
            SetBestPriceAuto(f, itemID)
        end
    end

    -- 9. 核心拦截机制：全局装备格子 Alt + 右键 快捷设定注入
    function BestPrice.HookZhuangBeiButton(bt)
        if not bt or bt.hasHookedBestPrice then return end
        bt.hasHookedBestPrice = true

        local orig_OnMouseDown = bt:GetScript("OnMouseDown")
        bt:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" and IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() then
                local text = self:GetText()
                if text and text ~= "" and not text:find("^%s*$") then
                    self:ClearFocus()
                    if BG.lastfocus then BG.lastfocus:ClearFocus() end
                    BG.SetBestPrice(text, self)
                    return
                end
            end
            if orig_OnMouseDown then
                orig_OnMouseDown(self, button)
            end
        end)
    end

    function BestPrice.HookAllTableButtons()
        if not (BG and BG.Frame and BG.FBtable) then return end
        for _, FB in ipairs(BG.FBtable) do
            if BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
                for b = 1, (BG.Maxb[FB] + 2) do
                    if BG.Frame[FB]["boss" .. b] then
                        local maxi = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
                        for i = 1, maxi do
                            local bt = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                            if bt then
                                BestPrice.HookZhuangBeiButton(bt)
                            end
                        end
                    end
                end
            end
        end
    end

    function BestPrice.HookAllHopeButtons()
        if not (BG and BG.HopeFrame and BG.FBtable) then return end
        for _, FB in ipairs(BG.FBtable) do
            if BG.HopeFrame[FB] and BG.HopeMaxn and BG.HopeMaxb and BG.HopeMaxn[FB] and BG.HopeMaxb[FB] then
                for n = 1, BG.HopeMaxn[FB] do
                    if BG.HopeFrame[FB]["nandu" .. n] then
                        for b = 1, BG.HopeMaxb[FB] do
                            if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b] then
                                for i = 1, (BG.HopeMaxi or 4) do
                                    local bt = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                                    if bt then
                                        BestPrice.HookZhuangBeiButton(bt)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 执行初次扫描拦截
    HookBgaSetMoney()
    BestPrice.HookAllTableButtons()
    BestPrice.HookAllHopeButtons()

    -- 延迟补救：应对某些尚未完成布局的副本格子
    C_Timer.After(0.5, function()
        BestPrice.HookAllTableButtons()
        BestPrice.HookAllHopeButtons()
    end)
    C_Timer.After(2, function()
        BestPrice.HookAllTableButtons()
        BestPrice.HookAllHopeButtons()
    end)
end

-- 自启动检测
if IsLoggedIn() then
    ns.InitBestPriceModule()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        ns.InitBestPriceModule()
        self:UnregisterAllEvents()
    end)
end
