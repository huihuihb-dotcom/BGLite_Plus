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

local function CreateCheckButton(name, text, parent, x, y, ontext, callback)
    local bt = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    bt:SetSize(24, 24)
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

    local defaultChecked = true
    if BiaoGe and BiaoGe.options and BiaoGe.options[name] ~= nil then
        defaultChecked = (BiaoGe.options[name] == 1)
    end
    bt:SetChecked(defaultChecked)

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

    local btFullLevel = CreateCheckButton("roleOverviewOnlyFullLevel", L["默认仅显示满级角色"], content, 260, yOffset, {
        L["默认仅显示满级角色"],
        L["开启时：团本 CD 列表仅展示满级角色（WLK/泰坦80级/TBC70级/60级时代60级）。"],
        L["关闭时：低等级小号也会显示在团本 CD 列表中。"],
    })

    yOffset = yOffset - 35

    -- 基础开关 - 行 2
    local btTalent = CreateCheckButton("roleOverviewShowTalent", L["显示角色天赋图标"], content, 15, yOffset, {
        L["显示角色天赋图标"],
        L["在角色名字左侧显示其主要天赋树图标。"],
    })

    local btFaction = CreateCheckButton("roleOverviewShowFaction", L["显示角色阵营颜色"], content, 260, yOffset, {
        L["显示角色阵营颜色"],
        L["联盟显示浅蓝，部落显示浅红。"],
    })

    yOffset = yOffset - 35

    -- 基础开关 - 行 3
    local btBuffCD = CreateCheckButton("roleOverviewShowBuffCD", L["显示Buff与CD状态"], content, 15, yOffset, {
        L["显示Buff与CD状态"],
        L["在列表中显示各角色的世界Buff及专业技能冷却状态。"],
    })

    -- 角色总览快捷键直达绑定
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

    -- 基础开关 - 行 4 (左侧：O键查询记录侧边栏，右侧：角色总览缩放比例)
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

    local sliderScale = CreateSlider("roleOverviewScale", L["角色总览缩放比例"], content, 0.5, 1.5, 0.05, 260, yOffset - 5, L["调整悬浮窗与独立面板的显示缩放比例。"], 180)

    yOffset = yOffset - 55

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

    -- 6. 分割线
    local line2 = content:CreateLine()
    line2:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    line2:SetStartPoint("TOPLEFT", 10, yOffset)
    line2:SetEndPoint("TOPLEFT", 600, yOffset)
    line2:SetThickness(1.5)

    yOffset = yOffset - 18

    -- 7. 货币显示自定义队列标题与操作按钮
    local moneyTitle = content:CreateFontString()
    moneyTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    moneyTitle:SetText(BG.STC_g1(L["货币与物品显示自定义队列"]))
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
            local tipPrefix = (self.moneyType and self.moneyType:find("item")) and L["物品："] or ""
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

    -- 动态计算整体滚动区域高度
    local totalContentHeight = math.abs(mCurrentY) + 60
    content:SetSize(600, math.max(totalContentHeight, 600))
end

