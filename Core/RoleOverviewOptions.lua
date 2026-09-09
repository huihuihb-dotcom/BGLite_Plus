if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB

local function RefreshRoleOverview()
    if BG.FBCDFrame and BG.FBCDFrame:IsVisible() and BG.SetFBCD then
        if BG.FBCDFrame.click then
            BG.SetFBCD(nil, nil, true, true)
        else
            BG.SetFBCD(BG.FBCDFrame.lastSelf, BG.FBCDFrame.lastPosition)
        end
    end
end

local defaultOptionsMap = {
    roleOverviewShowAllServer = 1,
    roleOverviewOnlyFullLevel = 0,
    roleOverviewShowFaction = 1,
    roleOverviewResOnlyFullLevel = 0,
    roleOverviewShowTalent = 1,
    roleOverviewShowBuffCD = 1,
    searchList = 1,
    roleOverviewShortName = 0, -- 默认关闭/否
    roleOverviewShowNote = 0,  -- 默认关闭/否
    roleOverviewShowNote_width = 100,
    roleOverviewShowNote_useClassColor = 1,
}

local function CreateCheckButton(name, text, parent, x, y, ontext, callback, defaultVal)
    local bt = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    bt:SetSize(22, 22)
    bt:SetPoint("TOPLEFT", parent, x, y)
    
    local textLabel = bt.text or _G[bt:GetName() .. "Text"]
    if not textLabel then
        textLabel = bt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        textLabel:SetPoint("LEFT", bt, "RIGHT", 4, 0)
        bt.text = textLabel
    end
    textLabel:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    textLabel:SetText(text)
    textLabel:SetWordWrap(false)
    bt.name = name
    bt.ontext = ontext
    bt.callback = callback

    -- 设定精准命中区域：方框本身及右侧文字均可点击
    local textW = textLabel:GetStringWidth()
    bt:SetHitRectInsets(-2, -textW - 8, -2, -2)

    local isChecked = false
    if defaultVal ~= nil then
        isChecked = (defaultVal == 1 or defaultVal == true)
    elseif defaultOptionsMap[name] ~= nil then
        isChecked = (defaultOptionsMap[name] == 1)
    end
    if BiaoGe and BiaoGe.options and BiaoGe.options[name] ~= nil then
        isChecked = (BiaoGe.options[name] == 1)
    end
    bt:SetChecked(isChecked)

    bt:SetScript("OnClick", function(self)
        local val = self:GetChecked() and 1 or 0
        BiaoGe.options[self.name] = val
        if self.callback then
            self.callback(val)
        end
        RefreshRoleOverview()
        BG.PlaySound(1)
    end)

    bt:SetScript("OnEnter", function(self)
        if self.ontext then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            if type(self.ontext) == "table" then
                for i, t in ipairs(self.ontext) do
                    GameTooltip:AddLine(t, 1, (i == 1 and 1 or 0.82), (i == 1 and 1 or 0), true)
                end
            else
                GameTooltip:SetText(self.ontext)
            end
            GameTooltip:Show()
        end
    end)

    bt:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    bt:SetScript("OnShow", function(self)
        if BiaoGe and BiaoGe.options and BiaoGe.options[self.name] ~= nil then
            self:SetChecked(BiaoGe.options[self.name] == 1)
        end
    end)

    return bt
end

local function CreateSlider(name, text, parent, minValue, maxValue, step, x, y, ontext, width)
    local savedValue = (BiaoGe and BiaoGe.options and tonumber(BiaoGe.options[name])) or 1
    local value = min(maxValue, max(minValue, savedValue))
    BiaoGe.options[name] = value

    local template = BG.IsWLK_80 and "TextToSpeechSliderTemplate" or "OptionsSliderTemplate"
    local slider = CreateFrame("Slider", nil, parent, template)
    slider:SetPoint("TOPLEFT", parent, x, y)
    slider:SetWidth(width or 180)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value)
    slider.name = name
    slider.ontext = ontext

    slider.Low:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    slider.Low:SetText(minValue)
    slider.High:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    slider.High:SetText(maxValue)
    slider.Text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    slider.Text:ClearAllPoints()
    slider.Text:SetPoint("CENTER", 0, 22)
    slider.Text:SetText(text)
    slider.Text:SetTextColor(1, 0.82, 0)

    slider.edit = CreateFrame("EditBox", nil, slider, BG.editTemplate)
    slider.edit:SetSize(50, 18)
    slider.edit:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    slider.edit:SetJustifyH("CENTER")
    slider.edit:SetAutoFocus(false)
    slider.edit:SetText(value)
    slider.edit:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = min(maxValue, max(minValue, val))
            slider:SetValue(val)
            BiaoGe.options[slider.name] = val
            self:SetText(val)
        end
        self:ClearFocus()
        if BG.UpdateFBCDFrameScale then
            BG.UpdateFBCDFrameScale()
        end
    end)

    slider:SetScript("OnValueChanged", function(self, val)
        val = tonumber(string.format("%.2f", val))
        BiaoGe.options[self.name] = val
        self.edit:SetText(val)
        if BG.UpdateFBCDFrameScale then
            BG.UpdateFBCDFrameScale()
        end
    end)

    return slider
end

function BG.GetAllRoleOverviewCharacters()
    local chars = {}
    local seen = {}
    local curRealmID = GetRealmID()
    local curPlayer = UnitName("player")

    local function AddCharacter(db, rID, pName, isAccounts)
        if not rID or not pName or pName == "" then return end
        local key = tostring(rID) .. "_" .. tostring(pName)
        if seen[key] then return end
        seen[key] = true

        local pInfo = db.playerInfo and db.playerInfo[rID] and db.playerInfo[rID][pName]
        local level = pInfo and pInfo.level or 0
        local class = pInfo and pInfo.class
        local iLevel = (pInfo and pInfo.iLevel)
            or (db.PlayerItemsLevel and db.PlayerItemsLevel[rID] and db.PlayerItemsLevel[rID][pName])
            or 0
        local talent = pInfo and pInfo.talent
        local faction = pInfo and pInfo.faction
        local rName = (db.realmName and db.realmName[rID])
            or (BiaoGe and BiaoGe.realmName and BiaoGe.realmName[rID])
            or tostring(rID)

        if not class and BiaoGe and BiaoGe.playerInfo and BiaoGe.playerInfo[rID] and BiaoGe.playerInfo[rID][pName] then
            local fallback = BiaoGe.playerInfo[rID][pName]
            class = class or fallback.class
            level = (level == 0 and fallback.level) or level
            iLevel = (iLevel == 0 and fallback.iLevel) or iLevel
            talent = talent or fallback.talent
            faction = faction or fallback.faction
        end

        tinsert(chars, {
            realmID = rID,
            realmName = rName,
            player = pName,
            class = class,
            level = tonumber(level) or 0,
            iLevel = tonumber(iLevel) or 0,
            talent = talent,
            faction = faction,
            isAccounts = isAccounts,
        })
    end

    if BiaoGe then
        for _, sub in ipairs({ "playerInfo", "RaidCD", "MONEY" }) do
            if BiaoGe[sub] then
                for rID, rData in pairs(BiaoGe[sub]) do
                    if type(rID) == "number" and type(rData) == "table" then
                        for pName in pairs(rData) do
                            AddCharacter(BiaoGe, rID, pName, false)
                        end
                    end
                end
            end
        end
    end

    if BiaoGeAccounts then
        for _, sub in ipairs({ "playerInfo", "RaidCD", "MONEY" }) do
            if BiaoGeAccounts[sub] then
                for rID, rData in pairs(BiaoGeAccounts[sub]) do
                    if type(rID) == "number" and type(rData) == "table" then
                        for pName in pairs(rData) do
                            AddCharacter(BiaoGeAccounts, rID, pName, true)
                        end
                    end
                end
            end
        end
    end

    sort(chars, function(a, b)
        if a.realmID ~= b.realmID then
            if a.realmID == curRealmID then return true end
            if b.realmID == curRealmID then return false end
            return a.realmID > b.realmID
        end
        local isACur = (a.player == curPlayer and a.realmID == curRealmID)
        local isBCur = (b.player == curPlayer and b.realmID == curRealmID)
        if isACur ~= isBCur then
            return isACur
        end
        if (a.iLevel or 0) ~= (b.iLevel or 0) then
            return (a.iLevel or 0) > (b.iLevel or 0)
        end
        if (a.level or 0) ~= (b.level or 0) then
            return (a.level or 0) > (b.level or 0)
        end
        return tostring(a.player) < tostring(b.player)
    end)

    return chars
end

function BG.CreateRoleOverviewFilterFrame(parentBtn)
    if BG.RoleOverviewFilterFrame then
        BG.RoleOverviewFilterFrame:Show()
        if BG.RoleOverviewFilterFrame.RefreshList then
            BG.RoleOverviewFilterFrame.RefreshList()
        end
        return
    end

    local f = CreateFrame("Frame", "BGRoleOverviewFilterFrame", UIParent, "BackdropTemplate")
    f:SetSize(460, 480)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0.75, 1, 1)

    tinsert(UISpecialFrames, "BGRoleOverviewFilterFrame")
    BG.RoleOverviewFilterFrame = f

    -- 标题
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(BG.STC_g1(L["角色显示管理"]))

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        BG.PlaySound(1)
        f:Hide()
    end)

    -- 说明文字
    local subTitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    subTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    subTitle:SetText(BG.STC_dis(L["（勾选的角色将在角色总览中展示，未勾选的将被隐藏）"]))

    -- 搜索框
    local searchBox = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    searchBox:SetSize(140, 22)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText(L["搜索..."])

    -- 快捷操作按钮
    local btnAll = BG.CreateButton(f)
    btnAll:SetSize(72, 22)
    btnAll:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    btnAll:SetText(L["全部显示"])

    local btnCurrentOnly = BG.CreateButton(f)
    btnCurrentOnly:SetSize(78, 22)
    btnCurrentOnly:SetPoint("LEFT", btnAll, "RIGHT", 6, 0)
    btnCurrentOnly:SetText(L["仅当前角色"])

    local btnInvert = BG.CreateButton(f)
    btnInvert:SetSize(60, 22)
    btnInvert:SetPoint("LEFT", btnCurrentOnly, "RIGHT", 6, 0)
    btnInvert:SetText(L["反选"])

    -- 滚动区域
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -92)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(410, 100)
    scrollFrame:SetScrollChild(scrollContent)

    -- 底部状态与关闭
    local statusText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    statusText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)

    local btnBottomClose = BG.CreateButton(f)
    btnBottomClose:SetSize(75, 24)
    btnBottomClose:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    btnBottomClose:SetText(L["确定"])
    btnBottomClose:SetScript("OnClick", function()
        BG.PlaySound(1)
        f:Hide()
    end)

    local itemFrames = {}

    local function RefreshFilterList()
        local allChars = BG.GetAllRoleOverviewCharacters()
        local curRealmID = GetRealmID()
        local curPlayer = UnitName("player")
        local filterText = strlower(strtrim(searchBox:GetText() or ""))

        BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}

        local displayChars = {}
        for _, c in ipairs(allChars) do
            local match = true
            if filterText ~= "" then
                local pLower = strlower(c.player or "")
                local rLower = strlower(tostring(c.realmName or ""))
                if not pLower:find(filterText, 1, true) and not rLower:find(filterText, 1, true) then
                    match = false
                end
            end
            if match then
                tinsert(displayChars, c)
            end
        end

        local totalCount = #allChars
        local hiddenCount = 0
        for _, c in ipairs(allChars) do
            if BiaoGe.roleOverviewHideRoles[c.realmID] and BiaoGe.roleOverviewHideRoles[c.realmID][c.player] then
                hiddenCount = hiddenCount + 1
            end
        end
        local showCount = totalCount - hiddenCount

        if hiddenCount > 0 then
            statusText:SetText(format(L["共 %d 个角色，已显示 |cff00ff00%d|r 个，隐藏 |cffff4444%d|r 个"], totalCount, showCount, hiddenCount))
        else
            statusText:SetText(format(L["共 %d 个角色，已全部显示"], totalCount))
        end

        for _, row in ipairs(itemFrames) do
            row:Hide()
        end

        local cardW = 198
        local cardH = 30
        local cols = 2
        local startX = 2
        local startY = -2
        local gapX = 8
        local gapY = 4

        for i, c in ipairs(displayChars) do
            local row = itemFrames[i]
            if not row then
                row = CreateFrame("Button", nil, scrollContent, "BackdropTemplate")
                row:SetSize(cardW, cardH)
                row:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                })
                row:SetBackdropColor(0.12, 0.12, 0.12, 0.7)
                row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

                local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.cb = cb

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(16, 16)
                icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                row.icon = icon

                local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                nameText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                nameText:SetJustifyH("LEFT")
                row.nameText = nameText

                local infoText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                infoText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                infoText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                infoText:SetJustifyH("RIGHT")
                row.infoText = infoText

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
                    if self.tooltipInfo then
                        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine(self.tooltipInfo.name, 1, 1, 1, true)
                        GameTooltip:AddLine(self.tooltipInfo.sub, 0.8, 0.8, 0.8, true)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.12, 0.12, 0.12, 0.7)
                    GameTooltip:Hide()
                end)

                row:SetScript("OnClick", function(self)
                    self.cb:Click()
                end)

                cb:SetScript("OnClick", function(self)
                    local parentRow = self:GetParent()
                    local charData = parentRow.charData
                    if not charData then return end
                    local checked = self:GetChecked()
                    BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}
                    BiaoGe.roleOverviewHideRoles[charData.realmID] = BiaoGe.roleOverviewHideRoles[charData.realmID] or {}
                    if checked then
                        BiaoGe.roleOverviewHideRoles[charData.realmID][charData.player] = nil
                    else
                        BiaoGe.roleOverviewHideRoles[charData.realmID][charData.player] = true
                    end
                    BG.PlaySound(1)
                    RefreshRoleOverview()
                    RefreshFilterList()
                    if BG.RefreshRoleOverviewOptions then
                        BG.RefreshRoleOverviewOptions()
                    end
                end)

                tinsert(itemFrames, row)
            end

            row.charData = c
            local col = (i - 1) % cols
            local rIndex = math.floor((i - 1) / cols)
            row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", startX + col * (cardW + gapX), startY - rIndex * (cardH + gapY))
            row:Show()

            local isHidden = BiaoGe.roleOverviewHideRoles[c.realmID] and BiaoGe.roleOverviewHideRoles[c.realmID][c.player]
            row.cb:SetChecked(not isHidden)

            local r, g, b, hex = GetClassColor(c.class)
            local pName = c.player or ""
            if c.realmID ~= curRealmID then
                pName = pName .. " |cff888888(" .. tostring(c.realmName) .. ")|r"
            end
            if c.isAccounts then
                pName = pName .. "*"
            end
            row.nameText:SetText("|c" .. hex .. pName .. "|r")

            local talentTex
            if c.class and c.talent and BG.GetTalentTex then
                talentTex = BG.GetTalentTex(c.class, c.talent)
            end
            if talentTex then
                row.icon:SetTexture(talentTex)
                row.icon:Show()
                row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            else
                row.icon:Hide()
                row.nameText:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
            end

            local lvlStr = ""
            if c.iLevel and c.iLevel > 0 then
                lvlStr = tostring(math.floor(c.iLevel)) .. "/" .. tostring(c.level or 0)
            elseif c.level and c.level > 0 then
                lvlStr = tostring(c.level) .. "级"
            end
            row.infoText:SetText("|cffaaaaaa" .. lvlStr .. "|r")

            row.tooltipInfo = {
                name = "|c" .. hex .. c.player .. "|r",
                sub = format(L["服务器：%s  装等：%d  等级：%d"], tostring(c.realmName), c.iLevel or 0, c.level or 0),
            }
        end

        local totalRows = math.ceil(#displayChars / cols)
        local totalH = totalRows * (cardH + gapY) + 10
        scrollContent:SetSize(410, math.max(totalH, 300))
    end

    f.RefreshList = RefreshFilterList

    searchBox:SetScript("OnTextChanged", function(self)
        RefreshFilterList()
    end)

    btnAll:SetScript("OnClick", function()
        BG.PlaySound(1)
        if BiaoGe and BiaoGe.roleOverviewHideRoles then
            wipe(BiaoGe.roleOverviewHideRoles)
        end
        RefreshRoleOverview()
        RefreshFilterList()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
    end)

    btnCurrentOnly:SetScript("OnClick", function()
        BG.PlaySound(1)
        local allChars = BG.GetAllRoleOverviewCharacters()
        local curRealmID = GetRealmID()
        local curPlayer = UnitName("player")
        BiaoGe.roleOverviewHideRoles = {}
        for _, c in ipairs(allChars) do
            if not (c.realmID == curRealmID and c.player == curPlayer) then
                BiaoGe.roleOverviewHideRoles[c.realmID] = BiaoGe.roleOverviewHideRoles[c.realmID] or {}
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = true
            end
        end
        RefreshRoleOverview()
        RefreshFilterList()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
    end)

    btnInvert:SetScript("OnClick", function()
        BG.PlaySound(1)
        local allChars = BG.GetAllRoleOverviewCharacters()
        BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}
        for _, c in ipairs(allChars) do
            BiaoGe.roleOverviewHideRoles[c.realmID] = BiaoGe.roleOverviewHideRoles[c.realmID] or {}
            if BiaoGe.roleOverviewHideRoles[c.realmID][c.player] then
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = nil
            else
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = true
            end
        end
        RefreshRoleOverview()
        RefreshFilterList()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
    end)

    f:SetScript("OnShow", function()
        RefreshFilterList()
    end)

    RefreshFilterList()
end

function ns.InitRoleOverviewOptions()
    if not (BG and BG.OptionsCreateTab) then return end
    if BG.FrameOptions_roleOverview then return end

    -- 确保 RoleOverviewUI 已初始化以生成完整的 BG.FBCDall_table
    if (not BG.FBCDall_table or #BG.FBCDall_table == 0) and BG.RoleOverviewUI then
        BG.RoleOverviewUI()
    end

    -- 纯注入模式在原版设置中追加「角色总览」Tab
    local content = BG.OptionsCreateTab("Options_roleOverview", L["角色总览"])
    if not content then return end

    local yOffset = -15

    -- 1. 标题
    local title = content:CreateFontString()
    title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    title:SetText(BG.STC_g1(L["角色总览与多服设置"]))
    title:SetPoint("TOPLEFT", content, 15, yOffset)

    yOffset = yOffset - 35

    -- 2. 基础开关 - 行 1
    local btAllServer = CreateCheckButton("roleOverviewShowAllServer", L["默认汇聚所有区服角色"], content, 15, yOffset, {
        L["默认汇聚所有区服角色"],
        L["开启时：默认展示所有服务器的角色与CD，按住 Shift 键临时切换为仅当前服。"],
        L["关闭时：默认仅展示当前服务器角色，按住 Shift 键临时切换为全部服务器。"],
    })

    local btFullLevel = CreateCheckButton("roleOverviewOnlyFullLevel", L["CD展示仅显示满级角色"], content, 260, yOffset, {
        L["CD展示仅显示满级角色"],
        L["开启时：团本 CD 列表仅展示满级角色（WLK/泰坦80级/TBC70级/60级时代60级）。"],
        L["关闭时：低等级小号也会显示在团本 CD 列表中。"],
    })

    yOffset = yOffset - 35

    -- 基础开关 - 行 2
    local btFaction = CreateCheckButton("roleOverviewShowFaction", L["显示角色阵营颜色"], content, 15, yOffset, {
        L["显示角色阵营颜色"],
        L["联盟显示浅蓝，部落显示浅红。"],
    })

    local btResFullLevel = CreateCheckButton("roleOverviewResOnlyFullLevel", L["资源面板仅显示满级角色"], content, 260, yOffset, {
        L["资源面板仅显示满级角色"],
        L["开启时：货币、专业技能等资源列表仅展示满级角色。"],
        L["关闭时：低等级小号也会显示在资源列表中。"],
    })

    yOffset = yOffset - 35

    -- 基础开关 - 行 3
    local btTalent = CreateCheckButton("roleOverviewShowTalent", L["显示角色天赋图标"], content, 15, yOffset, {
        L["显示角色天赋图标"],
        L["在角色名字左侧显示其主要天赋树图标。"],
    })

    local btBuffCD = CreateCheckButton("roleOverviewShowBuffCD", L["显示Buff与CD状态"], content, 260, yOffset, {
        L["显示Buff与CD状态"],
        L["在列表中显示各角色的世界Buff及专业技能冷却状态。"],
    })

    yOffset = yOffset - 35

    -- 基础开关 - 行 4 (左侧：O键查询记录侧边栏，右侧：显示副本简称)
    local btSearchList = CreateCheckButton("searchList", L["O键角色查询记录侧边栏"], content, 15, yOffset, {
        L["O键角色查询记录侧边栏"],
        L["开启时：在官方好友/查询（O键）面板右侧显示历史查询记录侧边栏与名单导出功能。"],
        L["关闭时：隐藏侧边栏与导出名单按钮。"],
    }, function(val)
        if BG.WhoFrameList then
            if val == 1 and WhoFrame and WhoFrame:IsVisible() then
                BG.WhoFrameList:Show()
                if BG.WhoFrameSendOutButton then BG.WhoFrameSendOutButton:Show() end
            else
                BG.WhoFrameList:Hide()
                if BG.WhoFrameSendOutButton then BG.WhoFrameSendOutButton:Hide() end
            end
        end
    end)

    local btShortName = CreateCheckButton("roleOverviewShortName", L["显示副本简称"], content, 260, yOffset, {
        L["显示副本简称"],
        L["开启时：角色总览列标题使用紧凑副本简称（如 SW、TOC、NAXX）。"],
        L["关闭时：使用完整副本名称。"],
    }, function(val)
        RefreshRoleOverview()
    end)

    yOffset = yOffset - 35

    -- 基础开关 - 行 5 (左侧：显示角色备注 + 宽度设置，右侧：快捷键绑定)
    local btNote = CreateCheckButton("roleOverviewShowNote", L["显示角色备注"], content, 15, yOffset, {
        L["显示角色备注"],
        L["在角色名字后面，增加显示一段自定义文本。"],
        " ",
        L["使用方法：/BGR，把角色总览面板固定，然后鼠标点击角色对应的备注栏即可修改备注。"]
    }, function(val)
        RefreshRoleOverview()
    end, 0)

    local tWidth = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    tWidth:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tWidth:SetPoint("LEFT", btNote.text, "RIGHT", 8, 0)
    tWidth:SetText(L["宽度:"])

    local editWidth = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    editWidth:SetSize(36, 20)
    editWidth:SetPoint("LEFT", tWidth, "RIGHT", 4, 0)
    editWidth:SetAutoFocus(false)
    editWidth:SetNumeric(true)
    editWidth:SetMaxLetters(3)
    local curW = (BiaoGe and BiaoGe.options and tonumber(BiaoGe.options.roleOverviewShowNote_width)) or 100
    BiaoGe.options.roleOverviewShowNote_width = curW
    editWidth:SetText(tostring(curW))
    editWidth:SetScript("OnTextChanged", function(self)
        local w = tonumber(self:GetText()) or 100
        w = math.max(40, math.min(300, w))
        BiaoGe.options.roleOverviewShowNote_width = w
        RefreshRoleOverview()
    end)
    editWidth:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editWidth:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    editWidth:SetScript("OnEditFocusLost", function(self)
        local w = tonumber(self:GetText()) or 100
        w = math.max(40, math.min(300, w))
        self:SetText(tostring(w))
    end)

    local tBind = content:CreateFontString()
    tBind:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tBind:SetPoint("TOPLEFT", content, 260, yOffset)
    tBind:SetText(L["快捷键："])

    local btnBind = BG.CreateButton(content)
    btnBind:SetSize(130, 22)
    btnBind:SetPoint("LEFT", tBind, "RIGHT", 5, 0)
    btnBind:SetScript("OnClick", function(self)
        if SettingsPanel and SettingsPanel.GetAllCategories then
            local category
            for i, v in pairs(SettingsPanel:GetAllCategories()) do
                if v.name == (SETTINGS_KEYBINDINGS_LABEL or "按键设置") then
                    category = v
                    break
                end
            end
            if category then
                SettingsPanel:SelectCategory(category)
            end
        elseif KeyBindingFrame then
            KeyBindingFrame:Show()
        end
    end)
    local function UpdateBindKeyText()
        local key1, key2 = GetBindingKey("ROLEOVERVIEW")
        if key1 or key2 then
            btnBind:SetText(key1 or key2)
        else
            btnBind:SetText(L["去系统设置绑定"])
        end
    end
    btnBind:SetScript("OnShow", UpdateBindKeyText)
    UpdateBindKeyText()

    yOffset = yOffset - 42

    -- 基础开关 - 行 6 (左侧：角色总览排序方式 + 修改排序，右侧：角色总览缩放比例)
    local tSort = content:CreateFontString()
    tSort:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tSort:SetPoint("TOPLEFT", content, 15, yOffset + 2)
    tSort:SetText(L["排序方式："])

    local sortTbl = {
        { key = "iLevel-class-player", text = L["装等-职业-名字"] },
        { key = "class-iLevel-player", text = L["职业-装等-名字"] },
        { key = "iLevel-player", text = L["装等-名字"] },
        { key = "class-player", text = L["职业-名字"] },
        { key = "player", text = L["名字"] },
        { key = "custom", text = L["自定义排序"] },
    }

    local function GetSortText(key)
        for _, v in ipairs(sortTbl) do
            if v.key == key then
                return v.text
            end
        end
        return L["装等-职业-名字"]
    end

    local sortDropDown = LibBG and LibBG:Create_UIDropDownMenu(nil, content)
    if sortDropDown then
        sortDropDown:SetPoint("LEFT", tSort, "RIGHT", -15, -2)
        LibBG:UIDropDownMenu_SetWidth(sortDropDown, 105)
        LibBG:UIDropDownMenu_SetAnchor(sortDropDown, 0, 0, "TOP", sortDropDown, "BOTTOM")
        LibBG:UIDropDownMenu_SetText(sortDropDown, GetSortText(BiaoGe.options.roleOverviewSort1 or "iLevel-class-player"))
        if BG.dropDownToggle then BG.dropDownToggle(sortDropDown) end

        local btnEditSort = BG.CreateButton(content)
        btnEditSort:SetSize(68, 22)
        btnEditSort:SetPoint("LEFT", sortDropDown, "RIGHT", -5, 2)
        btnEditSort:SetText(L["修改排序"])
        btnEditSort:SetShown(BiaoGe.options.roleOverviewSort1 == "custom")
        btnEditSort:SetScript("OnClick", function(self)
            BG.PlaySound(1)
            if BG.RoleOverviewSortFrame and BG.RoleOverviewSortFrame:IsVisible() then
                BG.RoleOverviewSortFrame:Hide()
            else
                if BG.CreateRoleOverviewSortFrame then
                    BG.CreateRoleOverviewSortFrame(self)
                end
            end
        end)

        LibBG:UIDropDownMenu_Initialize(sortDropDown, function(self, level)
            for _, v in ipairs(sortTbl) do
                local info = LibBG:UIDropDownMenu_CreateInfo()
                info.text = v.text
                info.func = function()
                    if v.key == "custom" and BG.InitializeRoleOverviewCustomSort then
                        BG.InitializeRoleOverviewCustomSort()
                    end
                    BiaoGe.options.roleOverviewSort1 = v.key
                    LibBG:UIDropDownMenu_SetText(sortDropDown, v.text)
                    if v.key ~= "custom" and BG.RoleOverviewSortFrame and BG.RoleOverviewSortFrame:IsVisible() then
                        BG.RoleOverviewSortFrame:Hide()
                    end
                    btnEditSort:SetShown(v.key == "custom")
                    RefreshRoleOverview()
                    BG.PlaySound(1)
                end
                if (BiaoGe.options.roleOverviewSort1 or "iLevel-class-player") == v.key then
                    info.checked = true
                end
                LibBG:UIDropDownMenu_AddButton(info)
            end
        end)
    end

    local sliderScale = CreateSlider("roleOverviewScale", L["角色总览缩放比例"], content, 0.5, 1.5, 0.05, 335, yOffset - 5, L["调整悬浮窗与独立面板的显示缩放比例。"], 170)

    yOffset = yOffset - 45

    -- 基础开关 - 行 7 (左侧：角色显示设置，右侧：状态文本与管理弹窗)
    local tRoleFilter = content:CreateFontString()
    tRoleFilter:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tRoleFilter:SetPoint("TOPLEFT", content, 15, yOffset + 2)
    tRoleFilter:SetText(L["显示/隐藏角色："])

    local btnManageRoles = BG.CreateButton(content)
    btnManageRoles:SetSize(110, 22)
    btnManageRoles:SetPoint("LEFT", tRoleFilter, "RIGHT", 5, 0)
    btnManageRoles:SetText(L["管理角色显示"])

    local txtRoleFilterStatus = content:CreateFontString()
    txtRoleFilterStatus:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    txtRoleFilterStatus:SetPoint("LEFT", btnManageRoles, "RIGHT", 10, 0)

    local function UpdateRoleFilterStatus()
        local count = 0
        if BiaoGe and BiaoGe.roleOverviewHideRoles then
            for rID, pMap in pairs(BiaoGe.roleOverviewHideRoles) do
                if type(pMap) == "table" then
                    for pName, isHidden in pairs(pMap) do
                        if isHidden then
                            count = count + 1
                        end
                    end
                end
            end
        end
        if count > 0 then
            txtRoleFilterStatus:SetText(format("|cffff4444" .. L["已隐藏 %d 个角色"] .. "|r", count))
        else
            txtRoleFilterStatus:SetText(format("|cff00ff00" .. L["全部显示（未隐藏任何角色）"] .. "|r"))
        end
    end
    btnManageRoles:SetScript("OnClick", function(self)
        BG.PlaySound(1)
        if BG.RoleOverviewFilterFrame and BG.RoleOverviewFilterFrame:IsVisible() then
            BG.RoleOverviewFilterFrame:Hide()
        else
            BG.CreateRoleOverviewFilterFrame(self)
        end
    end)
    btnManageRoles:SetScript("OnShow", UpdateRoleFilterStatus)
    UpdateRoleFilterStatus()

    yOffset = yOffset - 40

    -- 3. 分割线
    local line = content:CreateLine()
    line:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line:SetStartPoint("TOPLEFT", 10, yOffset)
    line:SetEndPoint("TOPLEFT", 600, yOffset)
    line:SetThickness(1.5)

    yOffset = yOffset - 18

    -- 4. 团本 CD 显示选择队列标题与操作按钮
    local fbTitle = content:CreateFontString()
    fbTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    fbTitle:SetText(BG.STC_g1(L["团本 CD 与任务显示自定义队列"]))
    fbTitle:SetPoint("TOPLEFT", content, 15, yOffset)

    local fbSubTitle = content:CreateFontString()
    fbSubTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    fbSubTitle:SetText(BG.STC_dis(L["（勾选的项将在角色总览中展示，未勾选的将被隐藏）"]))
    fbSubTitle:SetPoint("LEFT", fbTitle, "RIGHT", 10, 0)

    local fbCheckButtons = {}

    -- 全选按钮
    local btnSelectAll = BG.CreateButton(content)
    btnSelectAll:SetSize(75, 22)
    btnSelectAll:SetPoint("TOPLEFT", content, 440, yOffset + 4)
    btnSelectAll:SetText(L["全部勾选"])
    btnSelectAll:SetScript("OnClick", function()
        BiaoGe.FBCDchoice = BiaoGe.FBCDchoice or {}
        for _, bt in ipairs(fbCheckButtons) do
            bt:SetChecked(true)
            BiaoGe.FBCDchoice[bt.fbName] = 1
        end
        RefreshRoleOverview()
        BG.PlaySound(1)
    end)

    -- 恢复默认按钮
    local btnReset = BG.CreateButton(content)
    btnReset:SetSize(75, 22)
    btnReset:SetPoint("LEFT", btnSelectAll, "RIGHT", 8, 0)
    btnReset:SetText(L["恢复默认"])
    btnReset:SetScript("OnClick", function()
        BiaoGe.FBCDchoice = nil
        if BG.RoleOverviewUI then
            BG.RoleOverviewUI()
        end
        for _, bt in ipairs(fbCheckButtons) do
            local isChecked = (BiaoGe.FBCDchoice and BiaoGe.FBCDchoice[bt.fbName] == 1)
            bt:SetChecked(isChecked)
        end
        RefreshRoleOverview()
        BG.PlaySound(1)
    end)

    yOffset = yOffset - 35

    -- 5. 动态构建所有可用团本/日常/Boss 复选框网格
    local allFBTable = BG.FBCDall_table or {}
    local cols = 4
    local colWidth = 140
    local rowHeight = 30
    local startX = 15

    local currentX = startX
    local currentY = yOffset
    local colIndex = 0

    BiaoGe.FBCDchoice = BiaoGe.FBCDchoice or {}

    for i, v in ipairs(allFBTable) do
        if v.name and v.name2 and not v.name:find('^ignore') then
            local fbName = v.name
            local displayName = v.name2
            if v.color then
                displayName = "|cff" .. v.color .. displayName .. "|r"
            end

            local bt = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            bt:SetSize(22, 22)
            bt:SetPoint("TOPLEFT", content, currentX, currentY)
            
            local textLabel = bt.text or _G[bt:GetName() .. "Text"]
            if not textLabel then
                textLabel = bt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                textLabel:SetPoint("LEFT", bt, "RIGHT", 3, 0)
                bt.text = textLabel
            end
            textLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            textLabel:SetText(displayName)
            textLabel:SetWordWrap(false)
            bt.fbName = fbName

            -- 设定精准命中区域：方框本身及右侧文字均可点击
            local textW = textLabel:GetStringWidth()
            bt:SetHitRectInsets(-2, -textW - 6, -2, -2)

            local isChecked = (BiaoGe.FBCDchoice[fbName] == 1)
            bt:SetChecked(isChecked)

            bt:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                BiaoGe.FBCDchoice[self.fbName] = (checked and 1 or 0)
                RefreshRoleOverview()
                BG.PlaySound(1)
            end)

            bt:SetScript("OnShow", function(self)
                self:SetChecked(BiaoGe.FBCDchoice and BiaoGe.FBCDchoice[self.fbName] == 1)
            end)

            tinsert(fbCheckButtons, bt)

            colIndex = colIndex + 1
            if colIndex >= cols then
                colIndex = 0
                currentX = startX
                currentY = currentY - rowHeight
            else
                currentX = currentX + colWidth
            end
        end
    end

    -- 动态计算滚动区域高度（团本部分完成后下移 yOffset）
    yOffset = currentY - rowHeight - 15

    -- 6. 专业与生活技能显示自定义队列
    local allSkillTable = BG.SKILLall_table or {}
    if #allSkillTable > 0 then
        local lineSkill = content:CreateLine()
        lineSkill:SetColorTexture(0.5, 0.5, 0.5, 0.5)
        lineSkill:SetStartPoint("TOPLEFT", 10, yOffset)
        lineSkill:SetEndPoint("TOPLEFT", 600, yOffset)
        lineSkill:SetThickness(1.5)

        yOffset = yOffset - 18

        local skillTitle = content:CreateFontString()
        skillTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
        skillTitle:SetText(BG.STC_g1(L["专业与生活技能显示自定义队列"]))
        skillTitle:SetPoint("TOPLEFT", content, 15, yOffset)

        local skillSubTitle = content:CreateFontString()
        skillSubTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        skillSubTitle:SetText(BG.STC_dis(L["（勾选的项将在角色总览中展示，未勾选的将被隐藏）"]))
        skillSubTitle:SetPoint("LEFT", skillTitle, "RIGHT", 10, 0)

        local skillCheckButtons = {}

        -- 专业全部勾选按钮
        local btnSkillSelectAll = BG.CreateButton(content)
        btnSkillSelectAll:SetSize(75, 22)
        btnSkillSelectAll:SetPoint("TOPLEFT", content, 440, yOffset + 4)
        btnSkillSelectAll:SetText(L["全部勾选"])
        btnSkillSelectAll:SetScript("OnClick", function()
            BiaoGe.SKILLchoice = BiaoGe.SKILLchoice or {}
            for _, bt in ipairs(skillCheckButtons) do
                bt:SetChecked(true)
                BiaoGe.SKILLchoice[bt.skillId] = 1
            end
            RefreshRoleOverview()
            BG.PlaySound(1)
        end)

        -- 专业恢复默认按钮
        local btnSkillReset = BG.CreateButton(content)
        btnSkillReset:SetSize(75, 22)
        btnSkillReset:SetPoint("LEFT", btnSkillSelectAll, "RIGHT", 8, 0)
        btnSkillReset:SetText(L["恢复默认"])
        btnSkillReset:SetScript("OnClick", function()
            BiaoGe.SKILLchoice = { [0] = true }
            for _, bt in ipairs(skillCheckButtons) do
                local isChecked = (BiaoGe.SKILLchoice and (BiaoGe.SKILLchoice[bt.skillId] == 1 or BiaoGe.SKILLchoice[bt.skillId] == true))
                bt:SetChecked(isChecked)
            end
            RefreshRoleOverview()
            BG.PlaySound(1)
        end)

        yOffset = yOffset - 35

        local sCols = 4
        local sColWidth = 140
        local sRowHeight = 30
        local sStartX = 15

        local sCurrentX = sStartX
        local sCurrentY = yOffset
        local sColIndex = 0

        BiaoGe.SKILLchoice = BiaoGe.SKILLchoice or {}

        for i, v in ipairs(allSkillTable) do
            local skillId = v.id
            local displayName = v.name2 or v.name
            local tex = v.tex

            if v.color then
                displayName = "|cff" .. v.color .. displayName .. "|r"
            end

            local iconText = ""
            if tex and tex ~= "" then
                iconText = (ns.AddTexture and ns.AddTexture(tex, 0, 16)) or ("|T" .. tex .. ":16:16:0:0|t ")
            end

            local bt = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            bt:SetSize(22, 22)
            bt:SetPoint("TOPLEFT", content, sCurrentX, sCurrentY)

            local textLabel = bt.text or _G[bt:GetName() .. "Text"]
            if not textLabel then
                textLabel = bt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                textLabel:SetPoint("LEFT", bt, "RIGHT", 3, 0)
                bt.text = textLabel
            end
            textLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            textLabel:SetText(iconText .. displayName)
            textLabel:SetWordWrap(false)
            bt.skillId = skillId

            local textW = textLabel:GetStringWidth()
            bt:SetHitRectInsets(-2, -textW - 6, -2, -2)

            local isChecked = (BiaoGe.SKILLchoice[skillId] == 1 or BiaoGe.SKILLchoice[skillId] == true)
            bt:SetChecked(isChecked)

            bt:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                if checked then
                    BiaoGe.SKILLchoice[self.skillId] = 1
                else
                    BiaoGe.SKILLchoice[self.skillId] = nil
                end
                RefreshRoleOverview()
                BG.PlaySound(1)
            end)

            bt:SetScript("OnShow", function(self)
                self:SetChecked(BiaoGe.SKILLchoice and (BiaoGe.SKILLchoice[self.skillId] == 1 or BiaoGe.SKILLchoice[self.skillId] == true))
            end)

            tinsert(skillCheckButtons, bt)

            sColIndex = sColIndex + 1
            if sColIndex >= sCols then
                sColIndex = 0
                sCurrentX = sStartX
                sCurrentY = sCurrentY - sRowHeight
            else
                sCurrentX = sCurrentX + sColWidth
            end
        end

        yOffset = sCurrentY - sRowHeight - 15
    end

    -- 7. 分割线
    local line2 = content:CreateLine()
    line2:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line2:SetStartPoint("TOPLEFT", 10, yOffset)
    line2:SetEndPoint("TOPLEFT", 600, yOffset)
    line2:SetThickness(1.5)

    yOffset = yOffset - 18

    -- 8. 货币与装备物品显示自定义队列标题与操作按钮
    local moneyTitle = content:CreateFontString()
    moneyTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    moneyTitle:SetText(BG.STC_g1(L["货币与装备物品显示自定义队列"]))
    moneyTitle:SetPoint("TOPLEFT", content, 15, yOffset)

    local moneySubTitle = content:CreateFontString()
    moneySubTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    moneySubTitle:SetText(BG.STC_dis(L["（勾选的项将在角色总览中展示，未勾选的将被隐藏）"]))
    moneySubTitle:SetPoint("LEFT", moneyTitle, "RIGHT", 10, 0)

    local moneyCheckButtons = {}

    -- 货币全部勾选按钮
    local btnMoneySelectAll = BG.CreateButton(content)
    btnMoneySelectAll:SetSize(75, 22)
    btnMoneySelectAll:SetPoint("TOPLEFT", content, 440, yOffset + 4)
    btnMoneySelectAll:SetText(L["全部勾选"])
    btnMoneySelectAll:SetScript("OnClick", function()
        BiaoGe.MONEYchoice = BiaoGe.MONEYchoice or {}
        for _, bt in ipairs(moneyCheckButtons) do
            bt:SetChecked(true)
            BiaoGe.MONEYchoice[bt.moneyId] = 1
        end
        RefreshRoleOverview()
        BG.PlaySound(1)
    end)

    -- 货币恢复默认按钮
    local btnMoneyReset = BG.CreateButton(content)
    btnMoneyReset:SetSize(75, 22)
    btnMoneyReset:SetPoint("LEFT", btnMoneySelectAll, "RIGHT", 8, 0)
    btnMoneyReset:SetText(L["恢复默认"])
    btnMoneyReset:SetScript("OnClick", function()
        BiaoGe.MONEYchoice = nil
        if BG.RoleOverviewUI then
            BG.RoleOverviewUI()
        end
        for _, bt in ipairs(moneyCheckButtons) do
            local isChecked = (BiaoGe.MONEYchoice and BiaoGe.MONEYchoice[bt.moneyId] == 1)
            bt:SetChecked(isChecked)
        end
        RefreshRoleOverview()
        BG.PlaySound(1)
    end)

    yOffset = yOffset - 35

    -- 8. 动态构建所有可用货币复选框网格
    local allMoneyTable = BG.MONEYall_table or {}
    local mCols = 3
    local mColWidth = 190
    local mRowHeight = 30
    local mStartX = 15

    local mCurrentX = mStartX
    local mCurrentY = yOffset
    local mColIndex = 0

    BiaoGe.MONEYchoice = BiaoGe.MONEYchoice or {}

    for i, v in ipairs(allMoneyTable) do
        local moneyId = v.id
        local displayName = v.name
        local tex = v.tex

        if not displayName or not tex then
            if not v.type or v.type == "currency" then
                if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                    local info = C_CurrencyInfo.GetCurrencyInfo(moneyId)
                    if info then
                        displayName = displayName or info.name
                        tex = tex or info.iconFileID
                    end
                end
            elseif v.type == "item" then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(moneyId)
                if not itemName and GetItemInfoInstant then
                    itemName, _, _, _, itemTexture = GetItemInfoInstant(moneyId)
                end
                displayName = displayName or itemName
                tex = tex or itemTexture
            end
        end

        displayName = displayName or (L["货币"] .. " " .. tostring(moneyId))
        if v.color then
            displayName = "|cff" .. v.color .. displayName .. "|r"
        end

        local iconText = ""
        if tex then
            iconText = (ns.AddTexture and ns.AddTexture(tex, 0, 16)) or ("|T" .. tex .. ":16:16:0:0|t ")
        end

        local bt = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        bt:SetSize(22, 22)
        bt:SetPoint("TOPLEFT", content, mCurrentX, mCurrentY)

        local textLabel = bt.text or _G[bt:GetName() .. "Text"]
        if not textLabel then
            textLabel = bt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            textLabel:SetPoint("LEFT", bt, "RIGHT", 3, 0)
            bt.text = textLabel
        end
        textLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        textLabel:SetText(iconText .. displayName)
        textLabel:SetWordWrap(false)
        bt.moneyId = moneyId
        bt.rawName = v.name or displayName
        bt.moneyType = v.type
        bt.moneyColor = v.color or "FFFFFF"

        -- 设定精准命中区域
        local textW = textLabel:GetStringWidth()
        bt:SetHitRectInsets(-2, -textW - 6, -2, -2)

        local isChecked = (BiaoGe.MONEYchoice[moneyId] == 1)
        bt:SetChecked(isChecked)

        bt:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            if checked then
                BiaoGe.MONEYchoice[self.moneyId] = 1
            else
                BiaoGe.MONEYchoice[self.moneyId] = nil
            end
            RefreshRoleOverview()
            BG.PlaySound(1)
        end)

        bt:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            local tipPrefix = (self.moneyType and self.moneyType:find("item")) and L["物品："] or (self.moneyType == "equip" and L["装备："] or "")
            GameTooltip:SetText("|cff" .. self.moneyColor .. tipPrefix .. (self.rawName or "") .. "|r")
            GameTooltip:Show()
        end)

        bt:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        bt:SetScript("OnShow", function(self)
            self:SetChecked(BiaoGe.MONEYchoice and BiaoGe.MONEYchoice[self.moneyId] == 1)
        end)

        tinsert(moneyCheckButtons, bt)

        mColIndex = mColIndex + 1
        if mColIndex >= mCols then
            mColIndex = 0
            mCurrentX = mStartX
            mCurrentY = mCurrentY - mRowHeight
        else
            mCurrentX = mCurrentX + mColWidth
        end
    end

    yOffset = mCurrentY - mRowHeight - 15

    -- 9. 分割线
    local line3 = content:CreateLine()
    line3:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line3:SetStartPoint("TOPLEFT", 10, yOffset)
    line3:SetEndPoint("TOPLEFT", 600, yOffset)
    line3:SetThickness(1.5)

    yOffset = yOffset - 18

    -- 10. 角色显示自定义队列标题与操作按钮
    local roleTitle = content:CreateFontString()
    roleTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    roleTitle:SetText(BG.STC_g1(L["角色显示自定义队列"]))
    roleTitle:SetPoint("TOPLEFT", content, 15, yOffset)

    local roleSubTitle = content:CreateFontString()
    roleSubTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    roleSubTitle:SetText(BG.STC_dis(L["（勾选的角色将在角色总览中展示，未勾选的将被隐藏）"]))
    roleSubTitle:SetPoint("LEFT", roleTitle, "RIGHT", 10, 0)

    local roleCheckButtons = {}

    local function RefreshRoleCheckButtons()
        UpdateRoleFilterStatus()
        for _, bt in ipairs(roleCheckButtons) do
            if bt.charData then
                local isHidden = BiaoGe.roleOverviewHideRoles
                    and BiaoGe.roleOverviewHideRoles[bt.charData.realmID]
                    and BiaoGe.roleOverviewHideRoles[bt.charData.realmID][bt.charData.player]
                bt:SetChecked(not isHidden)
            end
        end
    end

    BG.RefreshRoleOverviewOptions = function()
        UpdateRoleFilterStatus()
        RefreshRoleCheckButtons()
        if BG.RoleOverviewFilterFrame and BG.RoleOverviewFilterFrame:IsVisible() and BG.RoleOverviewFilterFrame.RefreshList then
            BG.RoleOverviewFilterFrame.RefreshList()
        end
    end

    -- 角色全部勾选按钮
    local btnRoleSelectAll = BG.CreateButton(content)
    btnRoleSelectAll:SetSize(75, 22)
    btnRoleSelectAll:SetPoint("TOPLEFT", content, 360, yOffset + 4)
    btnRoleSelectAll:SetText(L["全部显示"])
    btnRoleSelectAll:SetScript("OnClick", function()
        if BiaoGe and BiaoGe.roleOverviewHideRoles then
            wipe(BiaoGe.roleOverviewHideRoles)
        end
        RefreshRoleOverview()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
        BG.PlaySound(1)
    end)

    -- 仅当前角色
    local btnRoleCurrentOnly = BG.CreateButton(content)
    btnRoleCurrentOnly:SetSize(78, 22)
    btnRoleCurrentOnly:SetPoint("LEFT", btnRoleSelectAll, "RIGHT", 6, 0)
    btnRoleCurrentOnly:SetText(L["仅当前角色"])
    btnRoleCurrentOnly:SetScript("OnClick", function()
        local allChars = BG.GetAllRoleOverviewCharacters()
        local curRealmID = GetRealmID()
        local curPlayer = UnitName("player")
        BiaoGe.roleOverviewHideRoles = {}
        for _, c in ipairs(allChars) do
            if not (c.realmID == curRealmID and c.player == curPlayer) then
                BiaoGe.roleOverviewHideRoles[c.realmID] = BiaoGe.roleOverviewHideRoles[c.realmID] or {}
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = true
            end
        end
        RefreshRoleOverview()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
        BG.PlaySound(1)
    end)

    -- 角色反选按钮
    local btnRoleInvert = BG.CreateButton(content)
    btnRoleInvert:SetSize(60, 22)
    btnRoleInvert:SetPoint("LEFT", btnRoleCurrentOnly, "RIGHT", 6, 0)
    btnRoleInvert:SetText(L["反选"])
    btnRoleInvert:SetScript("OnClick", function()
        local allChars = BG.GetAllRoleOverviewCharacters()
        BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}
        for _, c in ipairs(allChars) do
            BiaoGe.roleOverviewHideRoles[c.realmID] = BiaoGe.roleOverviewHideRoles[c.realmID] or {}
            if BiaoGe.roleOverviewHideRoles[c.realmID][c.player] then
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = nil
            else
                BiaoGe.roleOverviewHideRoles[c.realmID][c.player] = true
            end
        end
        RefreshRoleOverview()
        if BG.RefreshRoleOverviewOptions then
            BG.RefreshRoleOverviewOptions()
        end
        BG.PlaySound(1)
    end)

    yOffset = yOffset - 35

    -- 动态构建角色复选框网格
    local allRoleList = BG.GetAllRoleOverviewCharacters()
    local rCols = 3
    local rColWidth = 190
    local rRowHeight = 30
    local rStartX = 15

    local rCurrentX = rStartX
    local rCurrentY = yOffset
    local rColIndex = 0
    local curRealmID = GetRealmID()

    BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}

    for i, c in ipairs(allRoleList) do
        local r, g, b, hex = GetClassColor(c.class)
        local pName = c.player or ""
        if c.realmID ~= curRealmID then
            pName = pName .. " |cff888888(" .. tostring(c.realmName) .. ")|r"
        end
        if c.isAccounts then
            pName = pName .. "*"
        end

        local iconText = ""
        local talentTex
        if c.class and c.talent and BG.GetTalentTex then
            talentTex = BG.GetTalentTex(c.class, c.talent)
        end
        if talentTex then
            iconText = (ns.AddTexture and ns.AddTexture(talentTex, 0, 16)) or ("|T" .. talentTex .. ":16:16:0:0|t ")
        end

        local lvlStr = ""
        if c.iLevel and c.iLevel > 0 then
            lvlStr = "|cff808080(" .. tostring(math.floor(c.iLevel)) .. ")|r"
        end

        local displayName = iconText .. "|c" .. hex .. pName .. "|r " .. lvlStr

        local bt = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        bt:SetSize(22, 22)
        bt:SetPoint("TOPLEFT", content, rCurrentX, rCurrentY)

        local textLabel = bt.text or _G[bt:GetName() .. "Text"]
        if not textLabel then
            textLabel = bt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            textLabel:SetPoint("LEFT", bt, "RIGHT", 3, 0)
            bt.text = textLabel
        end
        textLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        textLabel:SetText(displayName)
        textLabel:SetWordWrap(false)
        bt.charData = c

        local textW = textLabel:GetStringWidth()
        bt:SetHitRectInsets(-2, -textW - 6, -2, -2)

        local isHidden = BiaoGe.roleOverviewHideRoles[c.realmID] and BiaoGe.roleOverviewHideRoles[c.realmID][c.player]
        bt:SetChecked(not isHidden)

        bt:SetScript("OnClick", function(self)
            local charData = self.charData
            if not charData then return end
            local checked = self:GetChecked()
            BiaoGe.roleOverviewHideRoles = BiaoGe.roleOverviewHideRoles or {}
            BiaoGe.roleOverviewHideRoles[charData.realmID] = BiaoGe.roleOverviewHideRoles[charData.realmID] or {}
            if checked then
                BiaoGe.roleOverviewHideRoles[charData.realmID][charData.player] = nil
            else
                BiaoGe.roleOverviewHideRoles[charData.realmID][charData.player] = true
            end
            RefreshRoleOverview()
            if BG.RefreshRoleOverviewOptions then
                BG.RefreshRoleOverviewOptions()
            end
            BG.PlaySound(1)
        end)

        bt:SetScript("OnEnter", function(self)
            local charData = self.charData
            if not charData then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(charData.player, 1, 1, 1, true)
            GameTooltip:AddLine(format(L["服务器：%s  装等：%d  等级：%d"], tostring(charData.realmName), charData.iLevel or 0, charData.level or 0), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)

        bt:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        bt:SetScript("OnShow", function(self)
            local charData = self.charData
            if charData then
                local hidden = BiaoGe.roleOverviewHideRoles and BiaoGe.roleOverviewHideRoles[charData.realmID] and BiaoGe.roleOverviewHideRoles[charData.realmID][charData.player]
                self:SetChecked(not hidden)
            end
        end)

        tinsert(roleCheckButtons, bt)

        rColIndex = rColIndex + 1
        if rColIndex >= rCols then
            rColIndex = 0
            rCurrentX = rStartX
            rCurrentY = rCurrentY - rRowHeight
        else
            rCurrentX = rCurrentX + rColWidth
        end
    end

    -- 动态计算整体滚动区域高度
    local totalContentHeight = math.abs(rCurrentY) + 60
    content:SetSize(600, math.max(totalContentHeight, 600))
end

