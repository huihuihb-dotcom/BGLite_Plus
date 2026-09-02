if BG.IsBlackListPlayer then return end

local AddonName, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RGB = ns.RGB
local RGB_16 = ns.RGB_16
local GetClassRGB = ns.GetClassRGB
local SetClassCFF = ns.SetClassCFF

local function GetWhoHistoryList()
    BiaoGe = BiaoGe or {}
    BiaoGe.whoFrame = BiaoGe.whoFrame or {}
    BiaoGe.whoFrame.history = BiaoGe.whoFrame.history or {}
    return BiaoGe.whoFrame.history
end

local function IsSearchListEnabled()
    if BiaoGe and BiaoGe.options and BiaoGe.options["searchList"] ~= nil then
        return BiaoGe.options["searchList"] ~= 0
    end
    return true
end

local function SendWhoSafe(text)
    if not text or text == "" then return end
    if C_FriendList and C_FriendList.SendWho then
        if Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social then
            C_FriendList.SendWho(text, Enum.SocialWhoOrigin.Social)
        else
            C_FriendList.SendWho(text)
        end
    elseif SendWho then
        SendWho(text)
    end
end

local isInitialized = false

local function InitWhoHistory()
    if isInitialized then return end
    if not WhoFrame then return end
    isInitialized = true

    GetWhoHistoryList()

    local f = CreateFrame("Frame", "BG_WhoFrameHistoryList", WhoFrame, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local anchorFrame = WhoFrameEditBoxInset or WhoFrameEditBox
    if anchorFrame then
        f:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", WhoFrameEditBoxInset and 5 or 12, 0)
    else
        f:SetPoint("TOPLEFT", WhoFrame, "TOPRIGHT", 5, -30)
    end

    local frameHeight = (FriendsFrame and FriendsFrame:GetHeight() or 420) - 50
    f:SetSize(110, math.max(300, frameHeight))
    f:Hide()
    BG.WhoFrameList = f

    local t = f:CreateFontString(nil, "OVERLAY")
    t:SetPoint("BOTTOM", f, "TOP", 0, 4)
    t:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    t:SetTextColor(1, 0.82, 0)
    t:SetText(L["查询记录"])

    local tipBtn = CreateFrame("Button", nil, f)
    tipBtn:SetSize(18, 18)
    tipBtn:SetPoint("LEFT", t, "RIGHT", 2, 0)
    local tex = tipBtn:CreateTexture()
    tex:SetAllPoints()
    tex:SetTexture(616343)
    tipBtn:SetHighlightTexture(616343)
    tipBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(BG.STC_g1(L["角色查询记录侧边栏"]))
        GameTooltip:AddLine(L["• 左键点击：直接搜索该记录"], 1, 1, 1)
        GameTooltip:AddLine(L["• 右键点击：删除该条记录"], 1, 0.4, 0.4)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine(BG.STC_dis(L["可在插件设置里随时开启或关闭此功能。"]), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    tipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local buttons = {}
    local maxButtons = math.floor(f:GetHeight() / 22)

    local function RefreshHistoryUI()
        for _, btn in pairs(buttons) do
            btn:Hide()
        end
        wipe(buttons)

        local history = GetWhoHistoryList()

        -- 限制最多保存的条数
        while #history > maxButtons do
            tremove(history)
        end

        for i, textVal in ipairs(history) do
            local bt = CreateFrame("Button", nil, f, "BackdropTemplate")
            bt:SetSize(f:GetWidth() - 10, 20)
            bt:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            if i == 1 then
                bt:SetPoint("BOTTOMLEFT", 5, 6)
            else
                bt:SetPoint("BOTTOMLEFT", buttons[i - 1], "TOPLEFT", 0, 2)
            end

            local fs = bt:CreateFontString(nil, "OVERLAY")
            fs:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            fs:SetPoint("LEFT", 4, 0)
            fs:SetWidth(bt:GetWidth() - 8)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetTextColor(1, 0.9, 0.4)
            fs:SetText(textVal)
            bt.fontString = fs

            bt:SetScript("OnEnter", function(self)
                self.fontString:SetTextColor(1, 1, 1)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(BG.STC_g1(textVal))
                GameTooltip:AddLine(L["• 左键点击：搜索该记录"], 1, 1, 1)
                GameTooltip:AddLine(L["• 右键点击：删除该记录"], 1, 0.4, 0.4)
                GameTooltip:Show()
            end)
            bt:SetScript("OnLeave", function(self)
                self.fontString:SetTextColor(1, 0.9, 0.4)
                GameTooltip:Hide()
            end)

            bt:SetScript("OnClick", function(self, btnClicked)
                if btnClicked == "RightButton" then
                    local curHistory = GetWhoHistoryList()
                    tremove(curHistory, i)
                    RefreshHistoryUI()
                    BG.PlaySound(1)
                else
                    if WhoFrameEditBox then
                        WhoFrameEditBox:SetText(textVal)
                        SendWhoSafe(textVal)
                        BG.PlaySound(1)
                    end
                end
            end)

            tinsert(buttons, bt)
            bt:Show()
        end
    end

    RefreshHistoryUI()

    local function AddSearchHistory()
        if not WhoFrameEditBox then return end
        local text = WhoFrameEditBox:GetText():trim()
        if text ~= "" then
            local history = GetWhoHistoryList()
            for i = #history, 1, -1 do
                if history[i] == text then
                    tremove(history, i)
                end
            end
            tinsert(history, 1, text)
            RefreshHistoryUI()
        end
    end

    if WhoFrameWhoButton then
        WhoFrameWhoButton:HookScript("OnClick", AddSearchHistory)
    end
    if WhoFrameEditBox then
        WhoFrameEditBox:HookScript("OnEnterPressed", AddSearchHistory)
    end

    -- 导出查询名单按钮
    local whoResultText = nil
    local exportBtn = BG.CreateButton(WhoFrame)
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("TOPRIGHT", WhoFrame, "TOPRIGHT", -20, -28)
    exportBtn:SetText(L["导出名单"])
    BG.WhoFrameSendOutButton = exportBtn

    exportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(BG.STC_g1(self:GetText()))
        GameTooltip:AddLine(L["导出本次查询到的所有玩家名单，方便批量复制与管理。"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    exportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    exportBtn:SetScript("OnClick", function(self)
        if not self.exportModal then
            local modal = CreateFrame("Frame", nil, WhoFrame, "BackdropTemplate")
            modal:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            modal:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
            modal:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
            modal:SetPoint("TOPLEFT", WhoFrame, "TOPLEFT", 0, -55)
            modal:SetPoint("BOTTOMRIGHT", WhoFrame, "BOTTOMRIGHT", 0, 68)
            modal:SetFrameLevel(WhoFrame:GetFrameLevel() + 10)
            modal:SetFrameStrata("HIGH")
            modal:EnableMouse(true)
            modal:Hide()
            self.exportModal = modal

            local scroll = CreateFrame("ScrollFrame", nil, modal, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 10, -10)
            scroll:SetPoint("BOTTOMRIGHT", -28, 10)

            local eb = CreateFrame("EditBox", nil, modal)
            eb:SetWidth(modal:GetWidth() - 40)
            eb:SetAutoFocus(false)
            eb:SetMultiLine(true)
            eb:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            eb:SetScript("OnEscapePressed", function(ebSelf)
                modal:Hide()
            end)
            scroll:SetScrollChild(eb)
            modal.editBox = eb

            modal:SetScript("OnShow", function()
                exportBtn:SetText(L["关闭名单"])
                eb:SetText(whoResultText or "")
                eb:HighlightText()
                eb:SetFocus()
            end)
            modal:SetScript("OnHide", function()
                exportBtn:SetText(L["导出名单"])
            end)
        end

        if self.exportModal:IsShown() then
            self.exportModal:Hide()
        else
            self.exportModal:Show()
        end
    end)

    local function CollectWhoResults()
        whoResultText = nil
        local names = {}
        local numWhos = 0
        if C_FriendList and C_FriendList.GetNumWhoResults then
            numWhos = C_FriendList.GetNumWhoResults() or 0
        elseif GetNumWhoResults then
            numWhos = GetNumWhoResults() or 0
        end

        if numWhos > 0 then
            for i = 1, numWhos do
                local info = nil
                if C_FriendList and C_FriendList.GetWhoInfo then
                    info = C_FriendList.GetWhoInfo(i)
                end
                if info and info.fullName then
                    tinsert(names, info.fullName)
                elseif GetWhoInfo then
                    local pName, pGuild, pLevel, pRace, pClass, pZone = GetWhoInfo(i)
                    if pName and pName ~= "" then
                        tinsert(names, pName)
                    end
                end
            end
        end

        if #names > 0 then
            whoResultText = table.concat(names, " ") .. " "
            exportBtn:Enable()
            if exportBtn.exportModal and exportBtn.exportModal:IsShown() then
                exportBtn.exportModal.editBox:SetText(whoResultText)
            end
        else
            exportBtn:Disable()
            if exportBtn.exportModal and exportBtn.exportModal:IsShown() then
                exportBtn.exportModal:Hide()
            end
        end
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("WHO_LIST_UPDATE")
    eventFrame:SetScript("OnEvent", CollectWhoResults)

    WhoFrame:HookScript("OnShow", function()
        if IsSearchListEnabled() then
            f:Show()
            exportBtn:Show()
            exportBtn:SetText(L["导出名单"])
            RefreshHistoryUI()
            CollectWhoResults()
        else
            f:Hide()
            exportBtn:Hide()
        end

        if exportBtn.exportModal then
            exportBtn.exportModal:Hide()
        end
    end)
end

-- 当好友框体加载或显示时初始化
local initHookFrame = CreateFrame("Frame")
initHookFrame:RegisterEvent("PLAYER_LOGIN")
initHookFrame:RegisterEvent("ADDON_LOADED")
initHookFrame:SetScript("OnEvent", function(self, event, addon)
    if WhoFrame then
        InitWhoHistory()
    end
end)

if WhoFrame then
    InitWhoHistory()
end
