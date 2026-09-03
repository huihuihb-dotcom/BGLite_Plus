local AddonName, ns = ...
local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local AddTexture = ns.AddTexture
local RGB_16 = ns.RGB_16
local GetItemID = ns.GetItemID

local function GetMaxb(FB)
    return (BG.Maxb and BG.Maxb[FB]) or (ns.Maxb and ns.Maxb[FB]) or 0
end
local BossNum = ns.BossNum or BG.BossNum

BG.History = BG.History or {}

-- 1. 数据库安全初始化
local function InitHistoryDB()
    if not BiaoGe then BiaoGe = {} end
    if not BiaoGe.HistoryList then
        BiaoGe.HistoryList = {}
    end
    if not BiaoGe.History then
        BiaoGe.History = {}
    end
    if BG.FBtable then
        for _, FB in ipairs(BG.FBtable) do
            if not BiaoGe.HistoryList[FB] then
                BiaoGe.HistoryList[FB] = {}
            end
            if not BiaoGe.History[FB] then
                BiaoGe.History[FB] = {}
            end
        end
    end
    if BiaoGe.options then
        if BiaoGe.options.autoQingKongSaveHistory == nil then
            BiaoGe.options.autoQingKongSaveHistory = 1
        end
    end
end
ns.InitHistoryDB = InitHistoryDB

-- 更新历史按钮上的数量文本
function BG.UpdateHistoryButton()
    InitHistoryDB()
    local FB = BG.FB1 or (BG.FBtable and BG.FBtable[1])
    if not FB then return end
    local count = (BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and #BiaoGe.HistoryList[FB]) or 0
    local text = string.format(L["历史表格（%d个）"], count)

    if BG.History and BG.History.HistoryButton then
        local bt = BG.History.HistoryButton
        bt:SetText(text)
        if bt:GetFontString() then
            bt:SetSize(bt:GetFontString():GetWidth() + 10, 20)
        end
    end

    if BG.History and BG.History.HistoryButtonInHistoryMode then
        local bt2 = BG.History.HistoryButtonInHistoryMode
        bt2:SetText(text)
        if bt2:GetFontString() then
            bt2:SetSize(bt2:GetFontString():GetWidth() + 10, 20)
        end
    end
end

-- 2. 核心：保存当前表格为历史表格 (完全对标原版 BiaoGe + TeamInfo 联合存储)
function BG.SaveBiaoGe(FB)
    local FB = FB or BG.FB1
    if not FB or not BiaoGe or not BiaoGe[FB] then return end
    InitHistoryDB()

    local maxb = (BG.Maxb and BG.Maxb[FB]) or (ns.Maxb and ns.Maxb[FB]) or 0
    if maxb == 0 then return end

    local serverTime = BiaoGe[FB].raidRoster and BiaoGe[FB].raidRoster.time or GetServerTime()
    local DT = tonumber(date("%y%m%d%H%M%S", serverTime))
    if BiaoGe.History[FB][DT] then
        serverTime = GetServerTime()
        DT = tonumber(date("%y%m%d%H%M%S", serverTime))
    end
    local DTcn = date(L["%m月%d日%H:%M:%S\n"], serverTime)

    BiaoGe.History[FB][DT] = {}
    BiaoGe.History[FB][DT].tradeTbl = {}

    for b = 1, maxb + 2 do
        BiaoGe.History[FB][DT]["boss" .. b] = {}
        for i = 1, BG.GetMaxi(FB, b) do
            if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
                local zhuangbei = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                if zhuangbei then
                    if zhuangbei:GetText() ~= "" then
                        BiaoGe.History[FB][DT]["boss" .. b]["zhuangbei" .. i] = zhuangbei:GetText()
                        if BiaoGe[FB]["boss" .. b] then
                            BiaoGe.History[FB][DT]["boss" .. b]["itemLevel" .. i] = BiaoGe[FB]["boss" .. b]["itemLevel" .. i]
                            BiaoGe.History[FB][DT]["boss" .. b]["bindOnEquip" .. i] = BiaoGe[FB]["boss" .. b]["bindOnEquip" .. i]
                        end
                    end

                    local maijia = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                    if maijia and maijia:GetText() ~= "" then
                        BiaoGe.History[FB][DT]["boss" .. b]["maijia" .. i] = maijia:GetText()
                        if BiaoGe[FB]["boss" .. b] then
                            for k, v in pairs(BG.playerClass or {}) do
                                BiaoGe.History[FB][DT]["boss" .. b][k .. i] = BiaoGe[FB]["boss" .. b][k .. i]
                            end
                        end
                    end

                    local jine = BG.Frame[FB]["boss" .. b]["jine" .. i]
                    if jine and jine:GetText() ~= "" then
                        BiaoGe.History[FB][DT]["boss" .. b]["jine" .. i] = jine:GetText()
                    end

                    if BiaoGe[FB]["boss" .. b] then
                        if BiaoGe[FB]["boss" .. b]["guanzhu" .. i] then
                            BiaoGe.History[FB][DT]["boss" .. b]["guanzhu" .. i] = true
                        end
                        if BiaoGe[FB]["boss" .. b]["qiankuan" .. i] then
                            BiaoGe.History[FB][DT]["boss" .. b]["qiankuan" .. i] = BiaoGe[FB]["boss" .. b]["qiankuan" .. i]
                        end
                        if BiaoGe[FB]["boss" .. b]["loot" .. i] then
                            BiaoGe.History[FB][DT]["boss" .. b]["loot" .. i] = BiaoGe[FB]["boss" .. b]["loot" .. i]
                        end
                    end
                end
            end
        end
    end

    if BiaoGe[FB].tradeTbl then
        BiaoGe.History[FB][DT].tradeTbl = BG.Copy and BG.Copy(BiaoGe[FB].tradeTbl) or BiaoGe[FB].tradeTbl
    end
    if BiaoGe[FB].raidRoster then
        BiaoGe.History[FB][DT].raidRoster = BG.Copy and BG.Copy(BiaoGe[FB].raidRoster) or BiaoGe[FB].raidRoster
    end
    if BiaoGe[FB].auctionLog then
        BiaoGe.History[FB][DT].auctionLog = BG.Copy and BG.Copy(BiaoGe[FB].auctionLog) or BiaoGe[FB].auctionLog
    end
    if BiaoGe[FB].leaderInfo then
        BiaoGe.History[FB][DT].leaderInfo = BG.Copy and BG.Copy(BiaoGe[FB].leaderInfo) or BiaoGe[FB].leaderInfo
    end

    -- ★ 核心：联合存储 TeamInfo（YY号、团长、招募通告等）
    if BiaoGe[FB].teamInfo then
        BiaoGe.History[FB][DT].teamInfo = BG.Copy and BG.Copy(BiaoGe[FB].teamInfo) or BiaoGe[FB].teamInfo
    end

    local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
    local totalPeople = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine" .. 4] and BG.Frame[FB]["boss" .. maxb + 2]["jine" .. 4]:GetText()) or "0"
    local wage = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine" .. 5] and BG.Frame[FB]["boss" .. maxb + 2]["jine" .. 5]:GetText()) or "0"

    local d = { DT, string.format(L["%s%s %s人 工资:%s"], DTcn, fbShort, totalPeople, wage), date("%m/%d", serverTime), date("%H:%M:%S", serverTime) }
    table.insert(BiaoGe.HistoryList[FB], 1, d)

    BG.UpdateHistoryButton()
    if BG.CreatHistoryListButton then
        BG.CreatHistoryListButton(FB)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已将当前表格保存至 <%s> 历史表格1。"], fbShort))
end

-- 3. 核心：应用历史表格到当前活跃表格 (含 TeamInfo 还原)
function BG.SetBiaoGeFormHistory(FB, num)
    local FB = FB or BG.FB1
    num = num or (BG.History and BG.History.chooseNum) or 1
    if not (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and BiaoGe.HistoryList[FB][num]) then return end

    local DT = BiaoGe.HistoryList[FB][num][1]
    local histData = BiaoGe.History and BiaoGe.History[FB] and BiaoGe.History[FB][DT]
    if not histData then return end

    -- 清空当前表格
    if BG.ClearBiaoGe then
        BG.ClearBiaoGe("biaoge", FB)
    end

    local maxBoss = GetMaxb(FB)
    if maxBoss == 0 then return end

    for b = 1, maxBoss + 2 do
        if histData["boss" .. b] then
            local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b, true)) or 5
            if b == maxBoss + 2 then maxRow = 5 end

            for i = 1, maxRow do
                local zbVal = histData["boss" .. b]["zhuangbei" .. i]
                local mjVal = histData["boss" .. b]["maijia" .. i]
                local jeVal = histData["boss" .. b]["jine" .. i]

                if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
                    if zbVal then
                        BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]:SetText(zbVal)
                    end
                    if mjVal then
                        BG.Frame[FB]["boss" .. b]["maijia" .. i]:SetText(mjVal)
                        if histData["boss" .. b]["color" .. i] then
                            BG.Frame[FB]["boss" .. b]["maijia" .. i]:SetTextColor(unpack(histData["boss" .. b]["color" .. i]))
                        end
                    end
                    if jeVal then
                        BG.Frame[FB]["boss" .. b]["jine" .. i]:SetText(jeVal)
                    end
                end

                if BiaoGe[FB] and BiaoGe[FB]["boss" .. b] then
                    BiaoGe[FB]["boss" .. b]["zhuangbei" .. i] = zbVal
                    BiaoGe[FB]["boss" .. b]["maijia" .. i] = mjVal
                    BiaoGe[FB]["boss" .. b]["jine" .. i] = jeVal
                    BiaoGe[FB]["boss" .. b]["itemLevel" .. i] = histData["boss" .. b]["itemLevel" .. i]
                    BiaoGe[FB]["boss" .. b]["bindOnEquip" .. i] = histData["boss" .. b]["bindOnEquip" .. i]

                    for k, v in pairs(BG.playerClass or {}) do
                        BiaoGe[FB]["boss" .. b][k .. i] = histData["boss" .. b][k .. i]
                    end

                    if histData["boss" .. b]["guanzhu" .. i] then
                        BiaoGe[FB]["boss" .. b]["guanzhu" .. i] = true
                        if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b]["guanzhu" .. i] then
                            BG.Frame[FB]["boss" .. b]["guanzhu" .. i]:Show()
                        end
                    end

                    if histData["boss" .. b]["qiankuan" .. i] then
                        BiaoGe[FB]["boss" .. b]["qiankuan" .. i] = histData["boss" .. b]["qiankuan" .. i]
                        if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b]["qiankuan" .. i] then
                            BG.Frame[FB]["boss" .. b]["qiankuan" .. i]:Show()
                        end
                    end

                    if histData["boss" .. b]["loot" .. i] then
                        BiaoGe[FB]["boss" .. b]["loot" .. i] = histData["boss" .. b]["loot" .. i]
                    end
                end
            end
        end
    end

    if type(histData.tradeTbl) == "table" then
        BiaoGe[FB].tradeTbl = {}
        for i, v in ipairs(histData.tradeTbl) do
            BiaoGe[FB].tradeTbl[i] = BG.Copy and BG.Copy(v) or v
        end
    end
    if type(histData.raidRoster) == "table" then
        BiaoGe[FB].raidRoster = BG.Copy and BG.Copy(histData.raidRoster) or histData.raidRoster
    end
    if type(histData.auctionLog) == "table" then
        BiaoGe[FB].auctionLog = BG.Copy and BG.Copy(histData.auctionLog) or histData.auctionLog
    end
    if type(histData.leaderInfo) == "table" then
        BiaoGe[FB].leaderInfo = BG.Copy and BG.Copy(histData.leaderInfo) or histData.leaderInfo
    end

    -- ★ 核心：还原 TeamInfo
    if type(histData.teamInfo) == "table" then
        BiaoGe[FB].teamInfo = BG.Copy and BG.Copy(histData.teamInfo) or histData.teamInfo
    else
        BiaoGe[FB].teamInfo = nil
    end

    if ns.TeamInfo and ns.TeamInfo.UpdateUI then
        ns.TeamInfo.UpdateUI()
    end

    if BG.EscHistoryFrame then
        BG.EscHistoryFrame()
    end
    if BG.UpdateAuctionLogFrame then
        BG.UpdateAuctionLogFrame()
    end

    local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已成功将历史表格应用并恢复至 <%s> 表格！"], fbShort))
end

-- 4. 删除指定历史账单
function BG.DeleteHistory(FB, num)
    local FB = FB or BG.FB1
    if not (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and BiaoGe.HistoryList[FB][num]) then return end
    local DT = BiaoGe.HistoryList[FB][num][1]
    if BiaoGe.History and BiaoGe.History[FB] then
        BiaoGe.History[FB][DT] = nil
    end
    table.remove(BiaoGe.HistoryList[FB], num)
    BG.UpdateHistoryButton()
    if BG.CreatHistoryListButton then
        BG.CreatHistoryListButton(FB)
    end
end

-- 5. 历史表格 UI 构建与交互
local function CreateHistoryUI()
    if BG.History.hasCreatedUI then return end
    BG.History.hasCreatedUI = true
    InitHistoryDB()

    -- A. 历史表格主框架
    if not BG.HistoryMainFrame then
        BG.HistoryMainFrame = CreateFrame("Frame", "BG.HistoryMainFrame", BG.MainFrame)
        BG.HistoryMainFrame:Hide()
        BG.HistoryFrame = BG.HistoryFrame or {}

        for _, FB in ipairs(BG.FBtable or {}) do
            if not BG["HistoryFrame" .. FB] then
                BG["HistoryFrame" .. FB] = CreateFrame("Frame", "BG.HistoryFrame" .. FB, BG.HistoryMainFrame)
                BG["HistoryFrame" .. FB]:Hide()
                BG.HistoryFrame[FB] = BG["HistoryFrame" .. FB]
            end
        end

        BG.HistoryMainFrame:SetScript("OnShow", function(self)
            local FB = BG.FB1 or (BG.FBtable and BG.FBtable[1])
            for _, fb in ipairs(BG.FBtable or {}) do
                if BG["HistoryFrame" .. fb] then
                    BG["HistoryFrame" .. fb]:Hide()
                end
            end
            if BG["HistoryFrame" .. FB] then
                BG["HistoryFrame" .. FB]:Show()
            end
            if BG.FBMainFrame then BG.FBMainFrame:Hide() end
            if BG.Title then BG.Title:Hide() end
            if BG.VerText then BG.VerText:Hide() end

            if BG.History.List then
                BG.History.List:SetParent(self)
                BG.History.List:SetFrameLevel(BG.History.List.frameLevel or 130)
            end

            for _, fb in ipairs(BG.FBtable or {}) do
                if BG["Button" .. fb] then
                    BG["Button" .. fb]:SetEnabled(false)
                end
            end

            BG.UpdateHistoryButton()

            -- 点开历史表格详情时，右侧团队信息面板直接显示并加载历史快照数据
            if ns.TeamInfo then
                if ns.TeamInfo.topBtn then
                    ns.TeamInfo.topBtn:Show()
                end
                if ns.TeamInfo.sideFrame then
                    ns.TeamInfo.sideFrame:Show()
                end
                if ns.TeamInfo.UpdateUI then
                    ns.TeamInfo.UpdateUI()
                end
            end
        end)

        BG.HistoryMainFrame:SetScript("OnHide", function(self)
            if BG.History.List then
                BG.History.List:Hide()
            end
            if BG.History.GaiMingFrame then
                BG.History.GaiMingFrame:Hide()
            end
            if BG.History.List and BG.FBMainFrame then
                BG.History.List:SetParent(BG.MainFrame)
                BG.History.List:SetFrameLevel(BG.History.List.frameLevel or 130)
            end
            for _, fb in ipairs(BG.FBtable or {}) do
                if BG["Button" .. fb] then
                    BG["Button" .. fb]:SetEnabled(true)
                end
            end
            if BG.FB1 and BG["Button" .. BG.FB1] then
                BG["Button" .. BG.FB1]:SetEnabled(false)
            end

            BG.UpdateHistoryButton()

            if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end
        end)
    end

    -- B. 顶部操作栏（挂载在 BG.MainFrame / BG.FBMainFrame）
    local parent = BG.FBMainFrame or BG.MainFrame

    -- [历史表格（N个）] 按钮
    local histBtn = CreateFrame("Button", nil, parent)
    histBtn:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -30, -1)
    histBtn:SetNormalFontObject(BG.FontGreen15 or GameFontNormalLarge)
    histBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    histBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    histBtn:RegisterForClicks("AnyUp")
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(histBtn) end
    BG.History.HistoryButton = histBtn

    -- [保存] 按钮
    local saveBtn = CreateFrame("Button", nil, parent)
    saveBtn:SetPoint("TOPRIGHT", histBtn, "TOPLEFT", -10, 0)
    saveBtn:SetNormalFontObject(BG.FontGreen15 or GameFontNormalLarge)
    saveBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    saveBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    saveBtn:SetText(L["保存"])
    if saveBtn:GetFontString() then
        saveBtn:SetSize(saveBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(saveBtn) end
    BG.History.SaveButton = saveBtn

    saveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["保存表格"], 1, 1, 1, true)
        GameTooltip:AddLine(L["把当前表格保存至历史表格，同时同步保存团队关键信息与招募通告。"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    saveBtn:SetScript("OnClick", function(self)
        if BG.FrameHide then BG.FrameHide(2) end
        self:SetEnabled(false)
        C_Timer.After(0.5, function() saveBtn:SetEnabled(true) end)
        BG.SaveBiaoGe()
        if BG.PlaySound then BG.PlaySound(2) end
    end)

    -- C. 历史表格下拉菜单列表
    local listFrame = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
    listFrame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listFrame:SetBackdropColor(0, 0, 0, 0.9)
    listFrame:SetSize(270, 380)
    listFrame:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", 0, -20)
    listFrame.frameLevel = 130
    listFrame:SetFrameLevel(listFrame.frameLevel)
    listFrame:EnableMouse(true)
    listFrame:Hide()
    BG.History.List = listFrame

    local scroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    scroll:SetWidth(listFrame:GetWidth() - 27)
    scroll:SetHeight(listFrame:GetHeight() - 9)
    scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -5)
    scroll.ScrollBar.scrollStep = BG.scrollStep or 80
    if BG.CreateSrollBarBackdrop then BG.CreateSrollBarBackdrop(scroll.ScrollBar) end
    if BG.HookScrollBarShowOrHide then BG.HookScrollBarShowOrHide(scroll) end
    BG.History.scroll = scroll

    local child = CreateFrame("Frame", nil, listFrame)
    child:SetWidth(scroll:GetWidth())
    child:SetHeight(scroll:GetHeight())
    BG.History.child = child
    scroll:SetScrollChild(child)

    -- 标题与提示
    local TitleText = BG.HistoryMainFrame:CreateFontString()
    TitleText:SetPoint("TOP", BG.MainFrame, "TOP", 0, -4)
    TitleText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    TitleText:SetTextColor(RGB("00FF00"))
    BG.History.Title = TitleText

    local tipText = listFrame:CreateFontString()
    tipText:SetPoint("TOP", listFrame, "BOTTOM", 0, 0)
    tipText:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    tipText:SetText(BG.STC_w1 and BG.STC_w1(string.format(L["（ALT+%s改名，ALT+%s删除表格）"], AddTexture("LEFT"), AddTexture("RIGHT"))) or "（ALT+左键改名，ALT+右键删除表格）")

    -- 清空历史按钮
    local clearHistBtn = BG.CreateButton and BG.CreateButton(listFrame) or CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
    clearHistBtn:SetSize(110, 25)
    clearHistBtn:SetPoint("TOP", listFrame, "BOTTOM", 0, -20)
    clearHistBtn:SetText(L["清空历史表格"])
    clearHistBtn:SetScript("OnClick", function()
        local FB = BG.FB1
        StaticPopupDialogs["BGLITE_PLUS_CLEAR_ALL_HISTORY"] = {
            text = string.format(L["确定清空<%s>的所有历史表格？"], (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB),
            button1 = L["是"],
            button2 = L["否"],
            OnAccept = function()
                if BiaoGe and BiaoGe.History and BiaoGe.History[FB] then wipe(BiaoGe.History[FB]) end
                if BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] then wipe(BiaoGe.HistoryList[FB]) end
                if BG.EscHistoryFrame then BG.EscHistoryFrame() end
                BG.UpdateHistoryButton()
                if BG.CreatHistoryListButton then BG.CreatHistoryListButton(FB) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }
        StaticPopup_Show("BGLITE_PLUS_CLEAR_ALL_HISTORY")
    end)

    -- 点击历史按钮展开/收起下拉
    histBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if BG.FrameHide then BG.FrameHide(2) end
            if BG.CreatHistoryListButton then
                BG.CreatHistoryListButton(BG.FB1)
            end
            if listFrame:IsVisible() then
                listFrame:Hide()
            else
                listFrame:Show()
            end
            if BG.PlaySound then BG.PlaySound(1) end
        end
    end)
    histBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        GameTooltip:AddLine(AddTexture("LEFT") .. L["打开历史表格"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    histBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- D. 历史查看模式下的【返回】、【应用】和【切换历史】按钮 (全部挂在 BG.HistoryMainFrame)
    -- [返回] 按钮 (最右上角，点击退出历史查看)
    local escBtn = CreateFrame("Button", nil, BG.HistoryMainFrame)
    escBtn:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -30, -1)
    escBtn:SetNormalFontObject(BG.FontFen15 or GameFontNormalLarge)
    escBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    escBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    escBtn:SetText(L["返回"])
    if escBtn:GetFontString() then
        escBtn:SetSize(escBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(escBtn) end
    BG.History.EscButton = escBtn

    -- [应用] 按钮 (返回按钮左侧，点击确认后恢复到活跃表格)
    local yongBtn = CreateFrame("Button", nil, BG.HistoryMainFrame)
    yongBtn:SetPoint("TOPRIGHT", escBtn, "TOPLEFT", -10, 0)
    yongBtn:SetNormalFontObject(BG.FontGreen15 or GameFontNormalLarge)
    yongBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    yongBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    yongBtn:SetText(L["应用"])
    if yongBtn:GetFontString() then
        yongBtn:SetSize(yongBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(yongBtn) end
    BG.History.YongButton = yongBtn

    yongBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["应用表格"], 1, 1, 1, true)
        GameTooltip:AddLine(L["把该历史表格复制粘贴到当前表格（含团队信息与YY），这样你可以继续编辑或通报。"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    yongBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yongBtn:SetScript("OnClick", function()
        StaticPopupDialogs["BGLITE_PLUS_APPLY_HISTORY"] = {
            text = L["确定应用表格？\n你当前的表格数据与团队信息将被"] .. (BG.STC_r1 and BG.STC_r1(L[" 替换 "]) or " 替换 "),
            button1 = L["是"],
            button2 = L["否"],
            OnAccept = function()
                BG.SetBiaoGeFormHistory()
                if BG.PlaySound then BG.PlaySound(2) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }
        StaticPopup_Show("BGLITE_PLUS_APPLY_HISTORY")
    end)

    -- [切换历史] 按钮 (应用按钮左侧，在历史模式下可随时切换其他账单)
    local histModeBtn = CreateFrame("Button", nil, BG.HistoryMainFrame)
    histModeBtn:SetPoint("TOPRIGHT", yongBtn, "TOPLEFT", -10, 0)
    histModeBtn:SetNormalFontObject(BG.FontGreen15 or GameFontNormalLarge)
    histModeBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    histModeBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    histModeBtn:RegisterForClicks("AnyUp")
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(histModeBtn) end
    BG.History.HistoryButtonInHistoryMode = histModeBtn

    histModeBtn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if BG.FrameHide then BG.FrameHide(2) end
            if BG.CreatHistoryListButton then
                BG.CreatHistoryListButton(BG.FB1)
            end
            if listFrame:IsVisible() then
                listFrame:Hide()
            else
                listFrame:Show()
            end
            if BG.PlaySound then BG.PlaySound(1) end
        end
    end)
    histModeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        GameTooltip:AddLine(AddTexture("LEFT") .. L["打开历史表格列表"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    histModeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- [返回] 函数逻辑
    function BG.EscHistoryFrame()
        if BG.FrameHide then BG.FrameHide(0) end
        if BG.HistoryMainFrame then BG.HistoryMainFrame:Hide() end
        if BG.FBMainFrame then BG.FBMainFrame:Show() end
        if BG.Title then BG.Title:Show() end
        if BG.VerText then BG.VerText:Show() end
        if BG.UpdateAuctionLogFrame then BG.UpdateAuctionLogFrame() end
        if BG.PlaySound then BG.PlaySound(1) end
        BG.UpdateHistoryButton()
        if ns.TeamInfo then
            if BiaoGe and BiaoGe.options and BiaoGe.options.showTeamInfoFrame == 1 then
                if ns.TeamInfo.sideFrame then ns.TeamInfo.sideFrame:Show() end
            end
            if ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end
        end
    end
    escBtn:SetScript("OnClick", BG.EscHistoryFrame)

    -- E. 改名弹窗
    local renameFrame = CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
    renameFrame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    renameFrame:SetBackdropColor(0, 0, 0, 0.9)
    renameFrame:SetSize(250, 150)
    renameFrame:SetPoint("TOPRIGHT", listFrame, "TOPLEFT", -2, 0)
    renameFrame:SetFrameLevel(140)
    renameFrame:Hide()
    BG.History.GaiMingFrame = renameFrame

    local renameTitle = renameFrame:CreateFontString()
    renameTitle:SetPoint("TOP", renameFrame, "TOP", 0, -20)
    renameTitle:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    renameTitle:SetTextColor(RGB("00BFFF"))
    BG.History.GaiMingBiaoTi = renameTitle

    local ebBox = CreateFrame("Frame", nil, renameFrame, "BackdropTemplate")
    ebBox:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    ebBox:SetBackdropColor(0, 0, 0, 0.2)
    ebBox:SetSize(230, 60)
    ebBox:SetPoint("TOPRIGHT", renameFrame, "TOPRIGHT", -10, -45)

    local renameEdit = CreateFrame("EditBox", nil, ebBox)
    renameEdit:SetSize(ebBox:GetWidth() - 10, ebBox:GetHeight())
    renameEdit:SetPoint("TOPLEFT", 5, -5)
    renameEdit:SetAutoFocus(false)
    renameEdit:EnableMouse(true)
    renameEdit:SetMultiLine(true)
    renameEdit:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    BG.History.GaiMingEdit1 = renameEdit

    renameEdit:SetScript("OnEscapePressed", function() renameFrame:Hide() end)
    ebBox:SetScript("OnMouseDown", function()
        renameEdit:SetFocus()
        renameEdit:SetCursorPosition(string.len(renameEdit:GetText()))
    end)

    local okBtn = BG.CreateButton and BG.CreateButton(renameFrame) or CreateFrame("Button", nil, renameFrame, "UIPanelButtonTemplate")
    okBtn:SetSize(100, 25)
    okBtn:SetPoint("BOTTOMLEFT", renameFrame, "BOTTOMLEFT", 15, 15)
    okBtn:SetText(L["确定"])
    okBtn:SetScript("OnClick", function()
        local FB = BG.FB1
        local text = renameEdit:GetText()
        if text ~= "" and BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] then
            BiaoGe.HistoryList[FB][BG.History.GaiMingNum][2] = text
            renameFrame:Hide()
            BG.CreatHistoryListButton(FB)
            if BG.PlaySound then BG.PlaySound(1) end
        end
    end)

    local cancelBtn = BG.CreateButton and BG.CreateButton(renameFrame) or CreateFrame("Button", nil, renameFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetPoint("BOTTOMRIGHT", renameFrame, "BOTTOMRIGHT", -15, 15)
    cancelBtn:SetText(L["取消"])
    cancelBtn:SetScript("OnClick", function()
        renameFrame:Hide()
        if BG.PlaySound then BG.PlaySound(1) end
    end)

    BG.UpdateHistoryButton()
end

-- 6. 构建历史查看表格中各个 BOSS 格子
local function CreateHistoryFBUI(FB)
    if not FB then return end
    if BG["History" .. FB .. "IsRoadUI"] then return end
    BG["History" .. FB .. "IsRoadUI"] = true

    CreateHistoryUI()

    local parentFrame = BG["HistoryFrame" .. FB]
    if not parentFrame then return end

    BG.HistoryFrame = BG.HistoryFrame or {}
    BG.HistoryFrame[FB] = BG.HistoryFrame[FB] or {}

    local maxBoss = GetMaxb(FB)
    if maxBoss == 0 then return end
    for b = 1, maxBoss + 2 do
        BG.HistoryFrame[FB]["boss" .. b] = BG.HistoryFrame[FB]["boss" .. b] or {}
        local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b, true)) or 5
        if b == maxBoss + 2 then
            maxRow = 5 -- 总览与工资栏严格只有 5 行
        end

        for i = 1, maxRow do
            if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i] then
                local origZB = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                local origMJ = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                local origJE = BG.Frame[FB]["boss" .. b]["jine" .. i]

                -- 装备框 (只读，统一挂载在 parentFrame 上)
                local zb = CreateFrame("EditBox", nil, parentFrame, BG.editTemplate or "InputBoxTemplate")
                zb:SetSize(origZB:GetWidth(), origZB:GetHeight())
                zb:SetPoint("TOPLEFT", origZB, "TOPLEFT", 0, 0)
                zb:SetFontObject(origZB:GetFontObject() or GameFontHighlight)
                zb:EnableMouse(true)
                zb:SetAutoFocus(false)
                zb:SetScript("OnEditFocusGained", function(self) self:ClearFocus() end)
                zb:SetScript("OnEnter", function(self)
                    local text = self:GetText()
                    if text and text ~= "" and not tonumber(text) then
                        local itemID = GetItemID(text)
                        if itemID then
                            local name, link = GetItemInfo(text)
                            if link then
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                                GameTooltip:ClearLines()
                                GameTooltip:SetHyperlink(link)
                                GameTooltip:Show()
                            end
                            if BG.SetHistoryMoney then
                                local mjBox = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["maijia" .. i]
                                local jeBox = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["jine" .. i]
                                local nowPlayer = mjBox and mjBox:GetText() or ""
                                local nowMoney = jeBox and jeBox:GetText() or ""
                                local r, g, b_col = 1, 1, 1
                                if mjBox and mjBox.GetTextColor then
                                    r, g, b_col = mjBox:GetTextColor()
                                end
                                BG.SetHistoryMoney(itemID, nowMoney, nowPlayer, r, g, b_col)
                            end
                        end
                    end
                end)
                zb:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                    if BG.HideHistoryMoney then
                        BG.HideHistoryMoney()
                    end
                end)
                BG.HistoryFrame[FB]["boss" .. b]["zhuangbei" .. i] = zb

                -- 买家框 (只读)
                local mj = CreateFrame("EditBox", nil, parentFrame, BG.editTemplate or "InputBoxTemplate")
                mj:SetSize(origMJ:GetWidth(), origMJ:GetHeight())
                mj:SetPoint("TOPLEFT", origMJ, "TOPLEFT", 0, 0)
                mj:SetFontObject(origMJ:GetFontObject() or GameFontHighlight)
                mj:EnableMouse(true)
                mj:SetAutoFocus(false)
                mj:SetScript("OnEditFocusGained", function(self) self:ClearFocus() end)
                BG.HistoryFrame[FB]["boss" .. b]["maijia" .. i] = mj

                -- 金额框 (只读)
                local je = CreateFrame("EditBox", nil, parentFrame, BG.editTemplate or "InputBoxTemplate")
                je:SetSize(origJE:GetWidth(), origJE:GetHeight())
                je:SetPoint("TOPLEFT", origJE, "TOPLEFT", 0, 0)
                je:SetFontObject(origJE:GetFontObject() or GameFontHighlight)
                je:EnableMouse(true)
                je:SetAutoFocus(false)
                je:SetScript("OnEditFocusGained", function(self) self:ClearFocus() end)
                BG.HistoryFrame[FB]["boss" .. b]["jine" .. i] = je

                -- 欠款与关注图标克隆
                local qk = CreateFrame("Frame", nil, parentFrame)
                qk:SetSize(16, 16)
                qk:SetPoint("RIGHT", je, "RIGHT", -2, 0)
                local qkTex = qk:CreateTexture(nil, "OVERLAY")
                qkTex:SetAllPoints()
                qkTex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                qk:Hide()
                BG.HistoryFrame[FB]["boss" .. b]["qiankuan" .. i] = qk

                local gz = CreateFrame("Frame", nil, parentFrame)
                gz:SetSize(16, 16)
                gz:SetPoint("RIGHT", zb, "RIGHT", -2, 0)
                local gzTex = gz:CreateTexture(nil, "OVERLAY")
                gzTex:SetAllPoints()
                gzTex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                gz:Hide()
                BG.HistoryFrame[FB]["boss" .. b]["guanzhu" .. i] = gz

                -- 特殊栏位格式与颜色初始化
                if b == maxBoss + 1 then
                    -- 支出栏：绿色
                    zb:SetTextColor(RGB("00FF00"))
                    je:SetTextColor(RGB("00FF00"))
                    mj:Hide()
                elseif b == maxBoss + 2 then
                    -- 总览与工资栏：固定文字与颜色
                    mj:Hide()
                    if i == 1 then
                        zb:SetText(L["总收入"])
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 2 then
                        zb:SetText(L["总支出"])
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 3 then
                        zb:SetText(L["净收入"])
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 4 then
                        zb:SetText(L["分钱人数"])
                        zb:SetTextColor(RGB("00BFFF"))
                        je:SetTextColor(RGB("00BFFF"))
                    elseif i == 5 then
                        zb:SetText(L["人均工资"])
                        zb:SetTextColor(RGB("00BFFF"))
                        je:SetTextColor(RGB("00BFFF"))
                    end
                else
                    -- 常规 BOSS 装备鼠标悬停 Tooltip
                    zb:SetScript("OnEnter", function(self)
                        local text = self:GetText()
                        if text and text ~= "" and GameTooltip then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink(text)
                            GameTooltip:Show()
                        end
                    end)
                    zb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                end
            end
        end
    end
end

-- 7. 渲染并填充历史账单列表项
function BG.CreatHistoryListButton(FB)
    local FB = FB or BG.FB1
    if not FB then return end
    CreateHistoryUI()

    -- 清除已有按钮
    local idx = 1
    while BG.History["ListButton" .. idx] do
        BG.History["ListButton" .. idx]:Hide()
        BG.History["ListButton" .. idx] = nil
        idx = idx + 1
    end

    local list = (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB]) or {}
    for i = 1, #list do
        local bt = CreateFrame("Button", nil, BG.History.child, "BackdropTemplate")
        bt:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground" })
        bt:SetBackdropColor(1, 1, 1, 0.1)
        if i == 1 then
            bt:SetPoint("TOPLEFT", BG.History.child, "TOPLEFT", 10, -10)
        else
            bt:SetPoint("TOPLEFT", BG.History["ListButton" .. i - 1], "BOTTOMLEFT", 0, -5)
        end
        bt:SetSize(230, 40)
        bt:SetNormalFontObject(BG.FontBlue13 or GameFontNormal)
        bt:SetDisabledFontObject(BG.FontWhite13 or GameFontHighlight)
        bt:SetHighlightFontObject(BG.FontWhite13 or GameFontHighlight)
        bt:SetText(tostring(i) .. ". " .. tostring(list[i][2] or ""))
        
        local t = bt:GetFontString()
        if t then
            t:SetWidth(bt:GetWidth() - 10)
            t:SetPoint("LEFT", 3, 0)
            t:SetJustifyH("LEFT")
        end
        BG.History["ListButton" .. i] = bt

        local tex2 = bt:CreateTexture(nil, "ARTWORK")
        tex2:SetAllPoints()
        tex2:SetColorTexture(RGB(BG.b1 or "00BFFF"))
        bt:SetDisabledTexture(tex2)

        bt:HookScript("OnEnter", function() bt:SetBackdropColor(RGB(BG.b1 or "00BFFF", 0.6)) end)
        bt:HookScript("OnLeave", function() bt:SetBackdropColor(1, 1, 1, 0.1) end)

        bt:SetScript("OnMouseUp", function(self, button)
            CreateHistoryFBUI(FB)
            if BG.FrameHide then BG.FrameHide(2) end

            if IsAltKeyDown() then
                if button == "RightButton" then
                    -- 删除历史
                    BG.DeleteHistory(FB, i)
                    if BG.History.GaiMingFrame then BG.History.GaiMingFrame:Hide() end
                    if BG.PlaySound then BG.PlaySound(1) end
                    return
                else
                    -- 改名
                    BG.History.GaiMingNum = i
                    BG.History.GaiMingFrame:Show()
                    BG.History.GaiMingBiaoTi:SetText(string.format(L["你正在改名第 %s 个表格"], i))
                    BG.History.GaiMingEdit1:SetText(list[i][2])
                    BG.History.GaiMingEdit1:SetFocus()
                    BG.History.GaiMingEdit1:HighlightText()
                    if BG.PlaySound then BG.PlaySound(1) end
                    return
                end
            end

            -- 正常点击：进入查看该历史账单
            BG.History.chooseNum = i
            if BG.HistoryMainFrame then
                BG.HistoryMainFrame:Show()
            end
            for _, fb in ipairs(BG.FBtable or {}) do
                if BG["HistoryFrame" .. fb] then
                    BG["HistoryFrame" .. fb]:Hide()
                end
            end
            if BG["HistoryFrame" .. FB] then
                BG["HistoryFrame" .. FB]:Show()
            end

            if BG.History.Title then
                BG.History.Title:SetText(L["<历史表格>"] .. " " .. list[i][2])
            end

            -- 加载数据到只读框中
            local DT = list[i][1]
            local histData = BiaoGe.History and BiaoGe.History[FB] and BiaoGe.History[FB][DT]
            if histData and BG.HistoryFrame and BG.HistoryFrame[FB] then
                local maxBoss = GetMaxb(FB)
                for b = 1, maxBoss + 2 do
                    local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b, true)) or 5
                    if b == maxBoss + 2 then
                        maxRow = 5
                    end

                    for r = 1, maxRow do
                        local zb = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["zhuangbei" .. r]
                        local mj = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["maijia" .. r]
                        local je = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["jine" .. r]
                        local qk = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["qiankuan" .. r]
                        local gz = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["guanzhu" .. r]

                        if b == maxBoss + 2 then
                            -- 总览工资栏：只载入金额，不覆盖固定的总收入/总支出/净收入/分钱人数/人均工资
                            if je then
                                je:SetText((histData["boss" .. b] and (histData["boss" .. b]["jine" .. r] or histData["boss" .. b]["jine" .. tostring(r)])) or "")
                            end
                        else
                            if zb then zb:SetText((histData["boss" .. b] and histData["boss" .. b]["zhuangbei" .. r]) or "") end
                            if mj then
                                mj:SetText((histData["boss" .. b] and histData["boss" .. b]["maijia" .. r]) or "")
                                if histData["boss" .. b] and histData["boss" .. b]["color" .. r] then
                                    mj:SetTextColor(unpack(histData["boss" .. b]["color" .. r]))
                                else
                                    mj:SetTextColor(1, 1, 1)
                                end
                            end
                            if je then je:SetText((histData["boss" .. b] and histData["boss" .. b]["jine" .. r]) or "") end
                            if qk then
                                if histData["boss" .. b] and histData["boss" .. b]["qiankuan" .. r] then
                                    qk:Show()
                                else
                                    qk:Hide()
                                end
                            end
                            if gz then
                                if histData["boss" .. b] and histData["boss" .. b]["guanzhu" .. r] then
                                    gz:Show()
                                else
                                    gz:Hide()
                                end
                            end
                        end
                    end
                end
            end

            -- 禁用当前按钮选中高亮
            for k = 1, #list do
                if BG.History["ListButton" .. k] then
                    BG.History["ListButton" .. k]:Enable()
                end
            end
            bt:Disable()
            if BG.History.List then BG.History.List:Hide() end
            if BG.PlaySound then BG.PlaySound(1) end
            -- 点开历史表格详情时，右侧团队信息面板直接显示并加载历史快照数据
            if ns.TeamInfo then
                if ns.TeamInfo.topBtn then
                    ns.TeamInfo.topBtn:Show()
                end
                if ns.TeamInfo.sideFrame then
                    ns.TeamInfo.sideFrame:Show()
                end
                if ns.TeamInfo.UpdateUI then
                    ns.TeamInfo.UpdateUI()
                end
            end
        end)
    end
end

-- 8. 进本自动清空与超链接一键撤回联动
local function SetupAutoSaveAndUndo()
    local clicked = {}
    hooksecurefunc("SetItemRef", function(link)
        local _, addon, action, FB, timeStr = strsplit(":", link)
        if (addon == "BGLite" or addon == "BiaoGe" or addon == "BGLite_Plus") and action == L["撤回清空"] and FB then
            if not clicked[timeStr] then
                clicked[timeStr] = true
                BG.SetBiaoGeFormHistory(FB, 1)
                BG.DeleteHistory(FB, 1)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已撤回清空，成功还原了表格数据与团队信息，并删除了历史表格1。"])
                if BG.PlaySound then
                    BG.PlaySound("cehuiqingkong")
                    BG.PlaySound(1)
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. (BG.STC_r1 and BG.STC_r1(L["只能撤回一次。"]) or L["只能撤回一次。"]))
            end
        end
    end)
end

-- 9. 装备框悬停历史价格统一 Hook 注入
local function HookAllItemButtons()
    for _, FB in ipairs(BG.FBtable or {}) do
        local maxb = (BG.Maxb and BG.Maxb[FB]) or (ns.Maxb and ns.Maxb[FB]) or 0
        if maxb > 0 and BG.Frame and BG.Frame[FB] then
            for b = 1, maxb do
                local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                for i = 1, maxRow do
                    local bt = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    if bt and not bt._hasHistoryMoneyHook then
                        bt._hasHistoryMoneyHook = true

                        -- 鼠标进入装备框时触发装备信息展示与历史价格展示
                        if BG.OnEnterDelay then
                            BG.OnEnterDelay(bt, function(self)
                                self.isEnter = true
                                if BG.FrameDs and BG.FrameDs[FB .. 1] and BG.FrameDs[FB .. 1]["boss" .. b] and BG.FrameDs[FB .. 1]["boss" .. b]["ds" .. i] then
                                    BG.FrameDs[FB .. 1]["boss" .. b]["ds" .. i]:Show()
                                end
                                local text = self:GetText()
                                if text and text ~= "" and not tonumber(text) then
                                    local link = text
                                    local itemID = GetItemID(link)
                                    if BG.Show_AllHighlight then
                                        BG.Show_AllHighlight(link, "biaoge")
                                    end
                                    if itemID then
                                        -- 1. 装备原生属性信息悬浮窗 (GameTooltip)
                                        if not (BG.IsHideTooltipKeyDown and BG.IsHideTooltipKeyDown()) then
                                            local point
                                            if BG.ButtonIsInRight and BG.ButtonIsInRight(self) then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
                                                point = "LEFT"
                                            else
                                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                                                point = "RIGHT"
                                            end
                                            GameTooltip:ClearLines()
                                            local showLink = (BG.SetSpecIDToLink and BG.SetSpecIDToLink(link)) or link
                                            GameTooltip:SetHyperlink(showLink)
                                            if L and L['< 按住CTRL+SHIFT隐藏此界面 >'] then
                                                GameTooltip:AddLine(L['< 按住CTRL+SHIFT隐藏此界面 >'], 0, 1, 0, true)
                                            end
                                            GameTooltip:Show()
                                            if BG.SetZUGSetTooltip then
                                                BG.SetZUGSetTooltip(itemID, point)
                                            end
                                        end

                                        -- 2. 装备历史价格走势图
                                        if BG.SetHistoryMoney then
                                            local maijiaBox = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["maijia" .. i]
                                            local jineBox = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["jine" .. i]
                                            local nowPlayer = maijiaBox and maijiaBox:GetText() or ""
                                            local nowMoney = jineBox and jineBox:GetText() or ""
                                            local r, g, b_col = 1, 1, 1
                                            if maijiaBox and maijiaBox.GetTextColor then
                                                r, g, b_col = maijiaBox:GetTextColor()
                                            end
                                            BG.SetHistoryMoney(itemID, nowMoney, nowPlayer, r, g, b_col)
                                        end

                                        -- 3. 辅助高亮与状态
                                        BG.DressUpLastButton = self
                                        BG.canShowTrunToItemLibCursor = true
                                        if BG.IsML then
                                            BG.canShowStartAuctionCursor = true
                                        else
                                            BG.canShowHopeCursor = true
                                        end
                                    end
                                end
                            end, BG.itemOnEnterDelay or 0.1)
                        end

                        -- 鼠标移出时隐藏
                        if BG.OnLeaveDelay then
                            BG.OnLeaveDelay(bt, function(self)
                                self.isEnter = false
                                GameTooltip:Hide()
                                if BG.HideHistoryMoney then
                                    BG.HideHistoryMoney()
                                end
                                if BG.FrameDs and BG.FrameDs[FB .. 1] and BG.FrameDs[FB .. 1]["boss" .. b] and BG.FrameDs[FB .. 1]["boss" .. b]["ds" .. i] then
                                    BG.FrameDs[FB .. 1]["boss" .. b]["ds" .. i]:Hide()
                                end
                                if BG.Hide_AllHighlight then
                                    BG.Hide_AllHighlight()
                                end
                            end)
                        end
                    end
                end
            end
        end
    end
end

-- 10. 初始化与事件挂载
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    InitHistoryDB()
    C_Timer.After(0.5, function()
        if BG.MainFrame then
            CreateHistoryUI()
            HookAllItemButtons()

            -- 挂载主界面与各副本切换按钮的 Hook，确保随时同步历史数量与装备价格 Hook
            if not BG.History.hasHookedFBButtons then
                BG.History.hasHookedFBButtons = true

                if BG.MainFrame.HookScript then
                    BG.MainFrame:HookScript("OnShow", function()
                        BG.UpdateHistoryButton()
                        HookAllItemButtons()
                    end)
                end
                if BG.FBMainFrame and BG.FBMainFrame.HookScript then
                    BG.FBMainFrame:HookScript("OnShow", function()
                        BG.UpdateHistoryButton()
                        HookAllItemButtons()
                    end)
                end

                for _, fb in ipairs(BG.FBtable or {}) do
                    if BG["Button" .. fb] and BG["Button" .. fb].HookScript then
                        BG["Button" .. fb]:HookScript("OnClick", function()
                            C_Timer.After(0.05, function()
                                BG.UpdateHistoryButton()
                                HookAllItemButtons()
                                if BG.History and BG.History.List and BG.History.List:IsVisible() then
                                    if BG.CreatHistoryListButton then
                                        BG.CreatHistoryListButton(BG.FB1)
                                    end
                                end
                            end)
                        end)
                    end
                end
            end

            BG.UpdateHistoryButton()
        end
    end)

    if event == "PLAYER_LOGIN" then
        SetupAutoSaveAndUndo()
    end
end)

-- 10. 装备历史价格悬浮图表模块
do
    local HEIGHT = 14
    local HEIGHT2 = 5
    BG.HistoryMoneyCache = {}
    BG.HistoryMoneyUpdateFrame = CreateFrame("Frame", nil, BG.MainFrame)

    function BG.GetHistoryMoney(itemID, FB, callback)
        local updateFrame = BG.HistoryMoneyUpdateFrame
        updateFrame:SetScript("OnUpdate", nil)
        FB = FB or BG.FB1
        local tbl = {}
        local db = BiaoGe
        local startI = 1
        local _startI = 1
        local oneTime = 5
        local allEnd = false
        local biaogeEnd = false
        local hasAccounts = false
        if BiaoGeAccounts and BiaoGeAccounts.HistoryList and BiaoGeAccounts.HistoryList[FB] then
            hasAccounts = true
        end

        local function AddDB(ii, isAccounts)
            if not (db.HistoryList and db.HistoryList[FB] and db.HistoryList[FB][ii]) then return end
            local DT = db.HistoryList[FB][ii][1]
            if db.History and db.History[FB] and db.History[FB][DT] then
                local b = 1
                while db.History[FB][DT]["boss" .. b] do
                    local maxI = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                    for i = 1, maxI do
                        local zhuangbei = db.History[FB][DT]["boss" .. b]["zhuangbei" .. i]
                        local _itemID = GetItemID(zhuangbei)
                        if zhuangbei and _itemID then
                            local maijia = db.History[FB][DT]["boss" .. b]["maijia" .. i]
                            local color = db.History[FB][DT]["boss" .. b]["color" .. i]
                            local jine = db.History[FB][DT]["boss" .. b]["jine" .. i]
                            if _itemID == itemID and tonumber(jine) then
                                tinsert(tbl, {
                                    DT = tonumber(DT),
                                    item = zhuangbei,
                                    player = maijia or "",
                                    color = color or { 1, 1, 1 },
                                    money = tonumber(jine) or 0,
                                    isAccounts = isAccounts,
                                })
                            end
                        end
                    end
                    b = b + 1
                end
            end
        end

        updateFrame:SetScript("OnUpdate", function(self, elapsed)
            if allEnd then
                self:SetScript("OnUpdate", nil)
                BG.HistoryMoneyCache[itemID] = tbl
                callback(tbl)
                if BG.historyLastCallback and BG.historyLastCallback ~= callback then
                    BG.historyLastCallback(tbl)
                end
                return
            end

            if not biaogeEnd then
                for ii = startI, startI + oneTime - 1 do
                    if not (db.HistoryList and db.HistoryList[FB] and db.HistoryList[FB][ii]) then
                        if hasAccounts then
                            biaogeEnd = true
                            db = BiaoGeAccounts
                        else
                            allEnd = true
                        end
                        break
                    end
                    AddDB(ii)
                end
                startI = startI + oneTime
            else
                for ii = _startI, _startI + oneTime - 1 do
                    if not (db.HistoryList and db.HistoryList[FB] and db.HistoryList[FB][ii]) then
                        allEnd = true
                        break
                    end
                    AddDB(ii, true)
                end
                _startI = _startI + oneTime
            end
        end)
    end

    function BG.SetHistoryMoney(itemID, nowMoney, nowPlayer, nowR, nowG, nowB)
        if not BG.MainFrame or not BG.MainFrame:IsVisible() then return end
        if not itemID then return end
        local FB = BG.FB1
        if not BG.HistoryMoneyFrame then
            local f = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
            f:SetSize(300, 0)
            f:SetPoint("BOTTOMRIGHT", BG.MainFrame, "BOTTOMRIGHT", -3, 40)
            f:SetFrameLevel(118)
            f:Hide()
            f.buttons = {}
            BG.HistoryMoneyFrame = f
            f:SetScript("OnHide", function(self)
                BG.HistoryMoneyUpdateFrame:SetScript("OnUpdate", nil)
            end)

            f.bg = f:CreateTexture()
            f.bg:SetSize(f:GetWidth(), 0)
            f.bg:SetPoint("TOP")
            f.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
            f.bg:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 1))

            local t = BG.HistoryMoneyFrame:CreateFontString()
            t:SetPoint("TOP", BG.HistoryMoneyFrame, "TOP", 3, -10)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            BG.HistoryMoneyFrame.title = t
        end

        BG.HistoryMoneyFrame:Hide()
        for k, bt in pairs(BG.HistoryMoneyFrame.buttons) do
            bt:Hide()
            BG.HistoryMoneyFrame.buttons[k] = nil
        end

        local itemStackCount = select(8, GetItemInfo(itemID))
        if not itemStackCount or itemStackCount > 1 then return end

        local maxCount = nowMoney and 14 or 15

        BG.GetHistoryMoney(itemID, FB, function(tbl)
            if #tbl == 0 then
                return
            end

            sort(tbl, function(a, b)
                return a.DT > b.DT
            end)

            local _tbl = {}
            for i, v in ipairs(tbl) do
                if i > maxCount then break end
                tinsert(_tbl, v)
            end

            if nowMoney then
                if not tonumber(nowMoney) or tonumber(nowMoney) == 0 then
                    nowMoney = 0
                end
                local a = {
                    DT = 0,
                    item = "",
                    player = nowPlayer,
                    color = { nowR, nowG, nowB },
                    money = tonumber(nowMoney)
                }
                table.insert(_tbl, 1, a)
            end

            local maxJine
            for i = 1, #_tbl do
                if maxJine == nil or maxJine < _tbl[i].money then
                    maxJine = _tbl[i].money
                end
            end
            if not maxJine or maxJine == 0 then maxJine = 1 end

            local name, link, quality, level, _, _, _, _, _, Texture = GetItemInfo(itemID)
            if not link then return end
            BG.HistoryMoneyFrame.title:SetText(string.format(L["历史价格：%s%s(%s)"], (AddTexture(Texture) .. link), "|cff" .. "9370DB", level or ""))

            local down
            local color = { (nowMoney and "00BFFF" or "33FFCC"), "00FFCC", "00FF99", "00FF66", "00FF33", "33FF66", "00CC33", "33CC00", "66FF33", "33FF00", "66FF00", "99FF00", "CCFF00", "CCFF33", "99CC00" }
            for i = 1, #_tbl do
                local v = _tbl[i]
                local f = CreateFrame("Frame", nil, BG.HistoryMoneyFrame, "BackdropTemplate")
                f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
                f:SetBackdropColor(RGB(color[i] or "00FFCC", 1))
                if i == 1 then
                    f:SetPoint("TOPRIGHT", BG.HistoryMoneyFrame, "TOPRIGHT", -80, -40)
                else
                    f:SetPoint("TOPRIGHT", down, "BOTTOMRIGHT", 0, -HEIGHT2)
                end
                local widthPercent = v.money / maxJine
                local width = (widthPercent == 0) and 1 or ((BG.HistoryMoneyFrame:GetWidth() - 220) * widthPercent + 60)
                f:SetSize(width, HEIGHT)
                down = f
                tinsert(BG.HistoryMoneyFrame.buttons, f)

                local tDate = f:CreateFontString()
                tDate:SetPoint("LEFT", f, "RIGHT", 3, 0)
                tDate:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                tDate:SetTextColor(RGB(color[i] or "00FFCC"))
                if nowMoney and i == 1 then
                    tDate:SetText(L["当前"])
                else
                    local dtStr = tostring(v.DT)
                    local a = strsub(dtStr, 3, 4)
                    if a:sub(1, 1) == "0" then a = a:sub(2, 2) end
                    local b = strsub(dtStr, 5, 6)
                    if b:sub(1, 1) == "0" then b = b:sub(2, 2) end
                    tDate:SetText(a .. L["月"] .. b .. L["日"])
                end

                local tMoney = f:CreateFontString()
                tMoney:SetPoint("RIGHT", f, "LEFT", -3, 0)
                tMoney:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                tMoney:SetTextColor(RGB(color[i] or "00FFCC"))
                local numText = (BG.FormatNumber and BG.FormatNumber(v.money, 2)) or tostring(v.money)
                tMoney:SetText(numText .. (v.isAccounts and "*" or ""))

                local tPlayer = f:CreateFontString(nil, "OVERLAY")
                tPlayer:SetPoint("RIGHT")
                tPlayer:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                tPlayer:SetTextColor(unpack(v.color or { 1, 1, 1 }))
                tPlayer:SetText(v.player or "")
            end

            local height = #_tbl * (HEIGHT + HEIGHT2) + 65
            BG.HistoryMoneyFrame:SetHeight(height)
            BG.HistoryMoneyFrame.bg:SetHeight(height + 50)
            BG.HistoryMoneyFrame:Show()
        end)
    end

    function BG.HideHistoryMoney()
        BG.HistoryMoneyUpdateFrame:SetScript("OnUpdate", nil)
        if BG.HistoryMoneyFrame then
            BG.HistoryMoneyFrame:Hide()
        end
    end
end
