if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RR = ns.RR
local NN = ns.NN
local RN = ns.RN
local Size = ns.Size
local RGB = ns.RGB
local RGB_16 = ns.RGB_16
local GetClassRGB = ns.GetClassRGB
local SetClassCFF = ns.SetClassCFF
local GetText_T = ns.GetText_T
local AddTexture = ns.AddTexture
local GetItemID = ns.GetItemID

local pt = print

-- 模块自启动挂载
local ItemOutTime = {}
ns.ItemOutTime = ItemOutTime

-- 私有专用的背景扫描 Tooltip，绝不污染系统与全局 Tooltip
local scanTooltip = CreateFrame("GameTooltip", "BGLite_ItemOutTimeScanTooltip", UIParent, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function GetMaxButton()
    local parent = BG and BG.MainFrame
    local h = (BG and BG.FBHeight and BG.FB1 and BG.FBHeight[BG.FB1]) or (parent and parent:GetHeight()) or 560
    return math.floor((h - 35) / 20 - 1)
end

function ItemOutTime.CreateUI()
    if BG.itemGuoQiFrame then return end
    local parent = BG and BG.MainFrame
    if not parent then return end

    BiaoGe.options = BiaoGe.options or {}
    BiaoGe.options.showGuoQiFrame = BiaoGe.options.showGuoQiFrame or 0
    BiaoGe.options.guoqiRemind = (BiaoGe.options.guoqiRemind ~= nil) and BiaoGe.options.guoqiRemind or 1
    BiaoGe.options.guoqiRemindMinTime = BiaoGe.options.guoqiRemindMinTime or 30
    BiaoGe.lastGuoQiTime = BiaoGe.lastGuoQiTime or 0

    local maxButton = GetMaxButton()
    local notItem = nil

    -- 1. 顶部栏入口切换按钮
    local bt = CreateFrame("Button", "BGLite_ButtonGuoQi", parent)
    bt:SetNormalFontObject(BG.FontGreen15 or "GameFontNormal")
    bt:SetDisabledFontObject(BG.FontDis15 or "GameFontDisable")
    bt:SetHighlightFontObject(BG.FontWhite15 or "GameFontHighlight")
    bt:SetText(L["装备过期"])
    bt:SetSize(bt:GetFontString():GetWidth() + 6, 20)
    bt:SetFrameStrata(parent:GetFrameStrata())
    bt:SetFrameLevel((parent:GetFrameLevel() or 100) + 35)
    if BG.SetTextHighlightTexture then
        BG.SetTextHighlightTexture(bt)
    end
    BG.ButtonGuoQi = bt

    local function RepositionButton()
        if not bt then return end
        bt:ClearAllPoints()
        if BG.ButtonTeamInfo and BG.ButtonTeamInfo:IsShown() then
            bt:SetPoint("LEFT", BG.ButtonTeamInfo, "RIGHT", BG.TopLeftButtonJianGe or 10, 0)
        elseif BG.ButtonAuctionLog and BG.ButtonAuctionLog:IsShown() then
            bt:SetPoint("LEFT", BG.ButtonAuctionLog, "RIGHT", BG.TopLeftButtonJianGe or 10, 0)
        elseif BG.ButtonMove and BG.ButtonMove:IsShown() then
            bt:SetPoint("LEFT", BG.ButtonMove, "RIGHT", BG.TopLeftButtonJianGe or 10, 0)
        else
            bt:SetPoint("TOPLEFT", parent, "TOPLEFT", 280, -5)
        end
    end
    ItemOutTime.RepositionButton = RepositionButton
    BG.RepositionButtonGuoQi = RepositionButton
    RepositionButton()

    bt:SetScript("OnClick", function(self)
        if BG.itemGuoQiFrame:IsVisible() then
            BiaoGe.options.showGuoQiFrame = 0
            BG.itemGuoQiFrame:Hide()
        else
            -- 核心互斥：打开装备过期抽屉时，自动隐藏右侧团队信息抽屉
            if ns.TeamInfo and ns.TeamInfo.sideFrame and ns.TeamInfo.sideFrame:IsVisible() then
                BiaoGe.options.showTeamInfoFrame = 0
                ns.TeamInfo.sideFrame:Hide()
            end
            BiaoGe.options.showGuoQiFrame = 1
            BG.itemGuoQiFrame:Show()
        end
        if BG.PlaySound then BG.PlaySound(1) end
    end)

    bt:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        GameTooltip:AddLine(L["显示背包里的团本装备还有多久不能交易（过期）。"], 1, 0.82, 0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BG.STC_b1("点击：展开/收起右侧装备过期倒计时抽屉"), 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    bt:SetScript("OnLeave", GameTooltip_Hide)

    -- 2. 右侧抽屉框架 (挂载在 BG.MainFrame 右侧边缘，高度与主界面一致)
    local fHeight = (BG and BG.FBHeight and BG.FB1 and BG.FBHeight[BG.FB1]) or (parent:GetHeight()) or 560
    local f = CreateFrame("Frame", "BGLite_ItemGuoQiFrame", parent, "BackdropTemplate")
    f:SetSize(210, fHeight)
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 1, 0)
    f:SetFrameStrata(parent:GetFrameStrata())
    f:SetFrameLevel((parent:GetFrameLevel() or 100) + 30)
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    local r, g, b = 0.2, 0.8, 1.0
    if GetClassRGB then r, g, b = GetClassRGB(nil, "player") end
    f:SetBackdropBorderColor(r, g, b, 0.95)
    f:EnableMouse(true)
    BG.itemGuoQiFrame = f
    BG.itemGuoQiFrame.maxButton = maxButton

    f:SetScript("OnMouseUp", function(self)
        if BG.MainFrame and BG.MainFrame:GetScript("OnMouseUp") then
            BG.MainFrame:GetScript("OnMouseUp")(BG.MainFrame)
        end
    end)
    f:SetScript("OnMouseDown", function(self)
        if BG.MainFrame and BG.MainFrame:GetScript("OnMouseDown") then
            BG.MainFrame:GetScript("OnMouseDown")(BG.MainFrame)
        end
    end)

    f:SetScript("OnShow", function(self)
        -- 核心互斥：自身展示时，自动隐藏右侧团队信息抽屉
        if ns.TeamInfo and ns.TeamInfo.sideFrame and ns.TeamInfo.sideFrame:IsVisible() then
            BiaoGe.options.showTeamInfoFrame = 0
            ns.TeamInfo.sideFrame:Hide()
        end
        BG.UpdateItemGuoQiFrame()
        self:RegisterEvent("BAG_UPDATE_DELAYED")
    end)

    f:SetScript("OnHide", function(self)
        self:UnregisterEvent("BAG_UPDATE_DELAYED")
    end)

    f:SetScript("OnEvent", function(self)
        if BG.After then
            BG.After(0.2, BG.UpdateItemGuoQiFrame)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.2, BG.UpdateItemGuoQiFrame)
        end
    end)

    -- 右上角关闭按钮
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function()
        BiaoGe.options.showGuoQiFrame = 0
        f:Hide()
        if BG.PlaySound then BG.PlaySound(1) end
    end)
    f.CloseButton = closeBtn

    -- 顶部标题
    local titleText = f:CreateFontString(nil, "ARTWORK")
    titleText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    titleText:SetPoint("TOP", f, "TOP", 0, -8)
    titleText:SetTextColor(0, 0.9, 1)
    titleText:SetText(L["装备过期剩余时间"])

    -- 分割线
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetSize(f:GetWidth() - 16, 1)
    sep:SetPoint("TOP", 0, -28)
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    f.tbl = {}
    f.buttons = {}

    local function UpdateFrameSize()
        local h = (BG and BG.FBHeight and BG.FB1 and BG.FBHeight[BG.FB1]) or (parent and parent:GetHeight()) or 560
        f:SetHeight(h)
        maxButton = GetMaxButton()
        f.maxButton = maxButton
    end

    local function UpdateTime()
        wipe(f.tbl)
        local numBags = NUM_BAG_SLOTS or 4
        for b = 0, numBags do
            local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(b))
                or (GetContainerNumSlots and GetContainerNumSlots(b)) or 0
            for i = 1, numSlots do
                local link = (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(b, i))
                    or (GetContainerItemLink and GetContainerItemLink(b, i))
                if link then
                    local itemID = GetItemInfoInstant(link)
                    scanTooltip:ClearLines()
                    if scanTooltip.SetBagItem then
                        scanTooltip:SetBagItem(b, i)
                    end

                    local lineIdx = 1
                    local prefixName = scanTooltip:GetName()
                    while _G[prefixName .. "TextLeft" .. lineIdx] do
                        local tx = _G[prefixName .. "TextLeft" .. lineIdx]:GetText()
                        if tx and tx ~= "" then
                            local timeStr = nil
                            if BIND_TRADE_TIME_REMAINING then
                                local pat = BIND_TRADE_TIME_REMAINING:gsub("%%s", "(.+)")
                                timeStr = tx:match(pat)
                            end
                            if not timeStr then
                                -- 兼容各种可能的多语言时限关键词
                                if tx:find("交易") or tx:find("trade") or tx:find("Trade") or tx:find("可与") or tx:find("可在") then
                                    timeStr = tx
                                end
                            end

                            if timeStr then
                                local h = tonumber(timeStr:match("(%d+)%s*小时") or timeStr:match("(%d+)%s*小時") or timeStr:match("(%d+)%s*hour") or timeStr:match("(%d+)%s*hr") or timeStr:match("(%d+)%s*h"))
                                local m = tonumber(timeStr:match("(%d+)%s*分钟") or timeStr:match("(%d+)%s*分鐘") or timeStr:match("(%d+)%s*min") or timeStr:match("(%d+)%s*m"))
                                local totalMin = (h or 0) * 60 + (m or 0)
                                if (h or m) and totalMin > 0 then
                                    tinsert(f.tbl, { time = totalMin, link = link, itemID = itemID, b = b, i = i })
                                    break
                                end
                            end
                        end
                        lineIdx = lineIdx + 1
                    end
                end
            end
        end

        table.sort(f.tbl, function(a, b)
            return a.time < b.time
        end)
    end

    local function CreateButton(ii, vv)
        local link, itemID, time, bag, slot = vv.link, vv.itemID, vv.time, vv.b, vv.i

        local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
        row:SetSize(f:GetWidth() - 8, 20)
        if ii == 1 then
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -32)
        else
            row:SetPoint("TOPLEFT", f.buttons[ii - 1], "BOTTOMLEFT", 0, -2)
        end
        row:EnableMouse(true)
        row:Show()
        row.link = link
        row.itemID = itemID
        row.time = time
        row.b = bag
        row.i = slot
        tinsert(f.buttons, row)

        if BG.UpdateFilter then
            pcall(BG.UpdateFilter, row, link)
        end

        local tex = row:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        if ii % 2 == 0 then
            tex:SetColorTexture(0.5, 0.5, 0.5, 0.12)
        else
            tex:SetColorTexture(0, 0, 0, 0.28)
        end

        local ds = row:CreateTexture()
        ds:SetAllPoints()
        ds:SetColorTexture(1, 1, 1, 0.15)
        ds:Hide()

        row:SetScript("OnMouseDown", function(self, button)
            if IsShiftKeyDown() then
                if BG.PlaySound then BG.PlaySound(1) end
                if BG.InsertLink then
                    BG.InsertLink(link)
                elseif ChatEdit_InsertLink then
                    ChatEdit_InsertLink(link)
                end
            elseif IsAltKeyDown() and BG.IsML and BG.StartAuction then
                BG.StartAuction(link, row, true, nil, button == "RightButton")
            end
        end)

        row:SetScript("OnEnter", function(self)
            ds:Show()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
            GameTooltip:ClearLines()
            if GameTooltip.SetBagItem then
                GameTooltip:SetBagItem(bag, slot)
            else
                GameTooltip:SetHyperlink(link)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(BG.STC_b1("Shift+点击：发送装备链接"), 0.4, 0.8, 1)
            if BG.IsML then
                GameTooltip:AddLine(BG.STC_g1("Alt+点击：发起此装备拍卖"), 0.2, 1, 0.2)
            end
            GameTooltip:Show()

            if BG.Show_AllHighlight then
                pcall(BG.Show_AllHighlight, link, "outtime")
            end
            if BG.SetHistoryMoney then
                pcall(BG.SetHistoryMoney, itemID)
            end
            if IsAltKeyDown() and BG.IsML and BiaoGe.options and BiaoGe.options["autoAuctionStart"] == 1 then
                SetCursor("interface/cursor/repair")
            end
            if BG.IsML then
                BG.canShowStartAuctionCursor = true
            end
            BG.DressUpLastButton = self
        end)

        row:SetScript("OnLeave", function()
            ds:Hide()
            GameTooltip:Hide()
            if BG.Hide_AllHighlight then pcall(BG.Hide_AllHighlight) end
            if BG.HideHistoryMoney then pcall(BG.HideHistoryMoney) end
            SetCursor(nil)
            BG.canShowStartAuctionCursor = false
            BG.DressUpLastButton = nil
        end)

        -- 装备图标
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 2, 0)
        icon:SetSize(16, 16)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local itemTex = select(5, GetItemInfoInstant(link))
        if itemTex then
            icon:SetTexture(itemTex)
        end

        -- 装备名称
        local tName = row:CreateFontString(nil, "ARTWORK")
        tName:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        tName:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        tName:SetJustifyH("LEFT")
        local cleanName = link:gsub("%[", ""):gsub("%]", "")
        tName:SetText(cleanName)
        tName:SetWidth(100)
        tName:SetWordWrap(false)

        -- 倒计时进度条
        local sb = CreateFrame("StatusBar", nil, row)
        sb:SetPoint("LEFT", tName, "RIGHT", 3, 0)
        sb:SetPoint("RIGHT", row, "RIGHT", -3, 0)
        sb:SetHeight(14)
        sb:SetMinMaxValues(0, 120)
        sb:SetValue(math.min(120, time))
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        if time >= 30 then
            sb:SetStatusBarColor(0, 0.85, 0.3, 0.85)
        else
            sb:SetStatusBarColor(1, 0.25, 0.2, 0.85)
        end

        local bgSb = sb:CreateTexture(nil, "BACKGROUND")
        bgSb:SetAllPoints()
        bgSb:SetColorTexture(0.1, 0.1, 0.1, 0.6)

        -- 倒计时文字
        local tCD = sb:CreateFontString(nil, "OVERLAY")
        tCD:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
        tCD:SetPoint("CENTER", sb, "CENTER", 0, 0)
        if time >= 60 then
            local hh = math.floor(time / 60)
            local mm = time % 60
            tCD:SetText(format("%dh%dm", hh, mm))
        else
            tCD:SetText(time .. "m")
        end
        tCD:SetTextColor(1, 1, 1)
    end

    function BG.UpdateItemGuoQiFrame()
        UpdateTime()
        if not f:IsVisible() then return end
        UpdateFrameSize()

        for _, v in ipairs(f.buttons) do
            v:Hide()
        end
        wipe(f.buttons)
        if notItem then
            notItem:Hide()
        end

        for ii, vv in ipairs(f.tbl) do
            if ii > maxButton then
                local lastbt = f.buttons[ii - 1]
                if lastbt then
                    local t = lastbt:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    t:SetPoint("TOPLEFT", lastbt, "BOTTOMLEFT", 0, -2)
                    t:SetJustifyH("LEFT")
                    t:SetTextColor(1, 0.82, 0)
                    t:SetText("......")
                end
                return
            end
            CreateButton(ii, vv)
        end

        if #f.tbl == 0 then
            if not notItem then
                notItem = f:CreateFontString(nil, "ARTWORK")
                notItem:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                notItem:SetPoint("TOP", f, "TOP", 0, -50)
                notItem:SetWidth(f:GetWidth() - 20)
                notItem:SetText(L["背包里没有可交易的装备。"])
                notItem:SetTextColor(0.8, 0.8, 0.8)
            end
            notItem:Show()
        end
    end

    -- 依据持久化状态初次还原展示
    if BiaoGe.options.showGuoQiFrame == 1 then
        -- 若同时存在团队信息处于显示态，优先保留团队信息并关闭过期抽屉
        if ns.TeamInfo and ns.TeamInfo.sideFrame and ns.TeamInfo.sideFrame:IsVisible() then
            BiaoGe.options.showGuoQiFrame = 0
            f:Hide()
        else
            f:Show()
        end
    else
        f:Hide()
    end
end

-- 全局自动对账轮询 (30秒轻量心跳)
C_Timer.NewTicker(30, function()
    if BG.itemGuoQiFrame and BG.itemGuoQiFrame:IsVisible() then
        BG.UpdateItemGuoQiFrame()
    end

    -- 团长过期倒计时语音/通报提醒
    if BiaoGe and BiaoGe.options and BiaoGe.options.guoqiRemind == 1 and BG.IsML and BG.itemGuoQiFrame then
        local now = GetServerTime()
        if now - (BiaoGe.lastGuoQiTime or 0) >= 60 * 5 then
            for _, v in ipairs(BG.itemGuoQiFrame.tbl or {}) do
                if v.time < (BiaoGe.options.guoqiRemindMinTime or 30) then
                    BiaoGe.lastGuoQiTime = now
                    local msg = BG.STC_r1(format(L["你有装备快过期了。%s"], v.link))
                    if BG.FrameLootMsg and BG.FrameLootMsg.AddMessage then
                        BG.FrameLootMsg:AddMessage(msg)
                    elseif DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage(msg)
                    end
                    if BG.PlaySound then
                        pcall(BG.PlaySound, "guoqi")
                    end
                    break
                end
            end
        end
    end
end)

-- 生命周期自愈挂载
if BG.Init then
    BG.Init(ItemOutTime.CreateUI)
end

local loaderFrame = CreateFrame("Frame")
loaderFrame:RegisterEvent("PLAYER_LOGIN")
loaderFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loaderFrame:SetScript("OnEvent", function()
    C_Timer.After(0.6, function()
        if BG and BG.MainFrame and not BG.itemGuoQiFrame then
            ItemOutTime.CreateUI()
        end
        if ItemOutTime.RepositionButton then
            ItemOutTime.RepositionButton()
        end
    end)
end)
