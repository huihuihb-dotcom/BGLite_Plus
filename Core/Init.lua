local AddonName, ns = ...
local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB

local function SafeHide(f)
    if f and type(f) == "table" and type(f.Hide) == "function" then
        pcall(function() f:Hide() end)
    end
end

local function SafeShow(f)
    if f and type(f) == "table" and type(f.Show) == "function" then
        pcall(function() f:Show() end)
    end
end

local function RestoreLastTab()
    if BiaoGe and BiaoGe.lastFrame and BG[BiaoGe.lastFrame .. "MainFrameTabNum"] and BG[BiaoGe.lastFrame .. "MainFrame"] then
        if BG.ClickTabButton then
            BG.ClickTabButton(BG[BiaoGe.lastFrame .. "MainFrameTabNum"])
        end
    elseif BG.ClickTabButton and BG.FBMainFrameTabNum then
        BG.ClickTabButton(BG.FBMainFrameTabNum)
    end
end

local function HookMinimap()
    local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then return end
    local plugin = ldb:GetDataObjectByName("BGLite") or ldb:GetDataObjectByName("BiaoGe")
    if not plugin then return end

    plugin.OnEnter = function(self)
        if (not BG.FBCDall_table or #BG.FBCDall_table == 0) and BG.RoleOverviewUI then
            pcall(BG.RoleOverviewUI)
        end
        if BG.SetFBCD then
            local ok, err = pcall(BG.SetFBCD, self, "minimap")
            if not ok and BG.FBCDFrame and not BG.FBCDFrame.click then
                SafeHide(BG.FBCDFrame)
            end
        end
    end

    plugin.OnLeave = function(self)
        if BG.FBCDFrame and not BG.FBCDFrame.click then
            SafeHide(BG.FBCDFrame)
        end
        GameTooltip:Hide()
    end

    local orig_OnClick = plugin.OnClick
    plugin.OnClick = function(self, button)
        if button == "MiddleButton" or (button == "LeftButton" and IsControlKeyDown()) then
            if BG.SetFBCD then
                BG.SetFBCD(nil, nil, true)
                BG.PlaySound(1)
                return
            end
        end
        if button == "LeftButton" and not IsControlKeyDown() then
            if BG.MainFrame and not BG.MainFrame:IsVisible() then
                RestoreLastTab()
            end
        end
        if orig_OnClick then
            orig_OnClick(self, button)
        end
    end
end

local function HideAllSubFrames()
    if BG.ItemLibMainFrame then
        SafeHide(BG.ItemLibMainFrame)
        SafeHide(BG.ItemLibMainFrame.bg)
        SafeHide(BG.ItemLibMainFrame.Hope)
    end
    SafeHide(BG.HopeMainFrame)
    SafeHide(BG.RaidToolMainFrame)
    SafeHide(BG.FilterClassItemMainFrame)
    SafeHide(BG.TradeHistoryMainFrame)
end

local function InitPlusUI()
    if not (BG and BG.MainFrame) then return end
    if ns.hasInitedPlusUI then return end
    ns.hasInitedPlusUI = true

    -- 0. 合规性：清理历史快照数据库（对齐官方新版零历史持久化要求）
    if BG.Once then
        BG.Once("CleanLegacyHistory_Compliance_260904", 260904, function()
            if BiaoGe then
                BiaoGe.History = nil
                BiaoGe.HistoryList = nil
            end
        end)
    end

    -- 初始化心愿数据库与职业过滤数据库结构
    if ns.InitHopeDB then
        ns.InitHopeDB()
    end
    if ns.InitFilterClassItemDB then
        ns.InitFilterClassItemDB()
    end
    if ns.InitRaidToolDB then
        ns.InitRaidToolDB()
    end
    if ns.InitRoleOverviewOptions then
        ns.InitRoleOverviewOptions()
    end
    if ns.InitRaidToolOthersOptions then
        ns.InitRaidToolOthersOptions()
    end
    if ns.InitTradeHistoryModule then
        securecall(ns.InitTradeHistoryModule)
    end
    if ns.InitReputationModule then
        securecall(ns.InitReputationModule)
    end
    if ns.InitBestPriceModule then
        securecall(ns.InitBestPriceModule)
    end
    if ns.InitAuctionPresetModule then
        securecall(ns.InitAuctionPresetModule)
        if ns.AuctionPreset and ns.AuctionPreset.CreateMainFrame then
            ns.AuctionPreset.CreateMainFrame(BG.MainFrame)
        end
    end
    if BG.OpenOption and not ns.hasHookedOpenOptionForRaidTool then
        ns.hasHookedOpenOptionForRaidTool = true
        hooksecurefunc(BG, "OpenOption", function()
            if ns.InitRaidToolOthersOptions then
                ns.InitRaidToolOthersOptions()
            end
        end)
    end

    -- 1. 职业过滤初始化
    if BG.FilterClassItemUI then
        securecall(BG.FilterClassItemUI)
        SafeHide(BG.FilterClassItemMainFrame)
    end

    -- 2. 装备库主框架与初始化
    -- 注意：BGLite function2.lua 中预创建了 stub: BG.ItemLibMainFrame = CreateFrame("Frame") (无parent)
    -- 必须强制重新创建为 BG.MainFrame 的子框架，否则装备库会浮在 MainFrame 外面
    do
        if not BG.ItemLibMainFrame then
            BG.ItemLibMainFrame = CreateFrame("Frame", nil, BG.MainFrame)
        else
            BG.ItemLibMainFrame:SetParent(BG.MainFrame)
        end
        BG.ItemLibMainFrame.IsVisible = nil
        BG.ItemLibMainFrame.IsShown = nil
        BG.ItemLibMainFrame:Hide()
        if BG.BackBiaoGe then
            BG.BackBiaoGe(BG.ItemLibMainFrame)
        end
    end

    if BG.ItemLibUI then
        securecall(BG.ItemLibUI)
    end

    -- 装备库生命周期绑定 (与原版 BiaoGe BiaoGe.lua:405 对齐)
    if BG.ItemLibMainFrame then
        BG.ItemLibMainFrame.first = true
        BG.ItemLibMainFrame:SetScript("OnShow", function(self)
            local FB = BG.FB1
            BG.FrameHide(0)
            BiaoGe.lastFrame = "ItemLib"

            SafeHide(BG.FBMainFrame)
            SafeHide(BG.HopeMainFrame)
            SafeHide(BG.DuiZhangMainFrame)
            SafeShow(BG.TabButtonsFB)

            for i, fb in ipairs(BG.FBtable or {}) do
                if BG["Button" .. fb] then
                    BG["Button" .. fb]:SetEnabled(true)
                end
            end
            if BG.FB1 and BG["Button" .. BG.FB1] then
                BG["Button" .. BG.FB1]:SetEnabled(false)
            end
            if BG.NanDuDropDown and BG.NanDuDropDown.DropDown then
                SafeHide(BG.NanDuDropDown.DropDown)
            end
            if BG.UpdateBiaoGeAllIsHaved then
                BG.UpdateBiaoGeAllIsHaved()
            end
            if BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2 then
                BG.FilterClassItemMainFrame.Buttons2:SetParent(self)
                SafeHide(BG.FilterClassItemMainFrame)
                BG.FilterClassItemMainFrame.Buttons2:ClearAllPoints()
                if BG.ItemLibMainFrame.filtleText then
                    BG.FilterClassItemMainFrame.Buttons2:SetPoint("LEFT", BG.ItemLibMainFrame.filtleText, "RIGHT", 10, 0)
                end
            end
            if BG.ButtonImportHope then
                BG.ButtonImportHope:SetParent(self)
                BG.ButtonExportHope:SetParent(self)
            end

            -- 关键修复：OnShow 时触发装备库检索与列表更新
            if BG.UpdateItemLib then
                BG.After(self.first and 0.2 or 0, function()
                    BG.UpdateItemLib()
                end)
            end
            if BG.UpdateItemLib_LeftHope_All then BG.UpdateItemLib_LeftHope_All() end
            if BG.UpdateItemLib_LeftLib_IsHaved_All then BG.UpdateItemLib_LeftLib_IsHaved_All() end
            if BG.UpdateItemLib_LeftLib_IsLooted_All then BG.UpdateItemLib_LeftLib_IsLooted_All() end
            if BG.UpdateItemLib_RightHope_All then BG.UpdateItemLib_RightHope_All() end
            self.first = nil
        end)

        BG.ItemLibMainFrame:SetScript("OnHide", function(self)
            SafeHide(BG.FilterClassItemMainFrame)
        end)

        -- 初始状态强制隐藏
        SafeHide(BG.ItemLibMainFrame)
    end

    -- 3. 心愿单主框架与初始化 (与原版 BiaoGe 一致：简单子框架)
    if not BG.HopeMainFrame then
        BG.HopeMainFrame = CreateFrame("Frame", nil, BG.MainFrame)
        SafeHide(BG.HopeMainFrame)
        for i, FB in ipairs(BG.FBtable or {}) do
            BG["HopeFrame" .. FB] = CreateFrame("Frame", "BG.HopeFrame" .. FB, BG.HopeMainFrame)
            SafeHide(BG["HopeFrame" .. FB])
        end
        if BG.BackBiaoGe then
            BG.BackBiaoGe(BG.HopeMainFrame)
        end
    end

    -- 左下角心愿说明
    if BG.HopeMainFrame and not BG.HopeMainFrame.hasTextIntro then
        BG.HopeMainFrame.hasTextIntro = true
        local t = BG.HopeMainFrame:CreateFontString()
        t:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 35, 75)
        t:SetFont(BIAOGE_TEXT_FONT, 20, "OUTLINE")
        t:SetTextColor(RGB(BG.g1))
        t:SetText(L["心愿清单："])
        local tt = t
        local t = BG.HopeMainFrame:CreateFontString()
        t:SetPoint("LEFT", tt, "RIGHT", 0, 0)
        t:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        t:SetTextColor(RGB(BG.g2))
        t:SetText(L["你可以设置一些装备，这些装备只要掉落就会提醒，并且自动关注团长拍卖"])
    end

    for _, FB in ipairs(BG.FBtable or {}) do
        if BG.HopeUI then
            securecall(BG.HopeUI, FB)
        end
    end

    if BG.HopeMainFrame then

        BG.HopeMainFrame:SetScript("OnShow", function(self)
            local FB = BG.FB1 or (BG.FBtable and BG.FBtable[1])
            BG.FrameHide(0)
            SafeHide(BG.FBMainFrame)
            SafeHide(BG.ItemLibMainFrame)
            SafeHide(BG.DuiZhangMainFrame)

            for i, fb in ipairs(BG.FBtable or {}) do
                SafeHide(BG["HopeFrame" .. fb])
            end
            if FB and BG["HopeFrame" .. FB] then
                SafeShow(BG["HopeFrame" .. FB])
            end
            BiaoGe.lastFrame = "Hope"
            SafeShow(BG.TabButtonsFB)
            for i, fb in ipairs(BG.FBtable or {}) do
                if BG["Button" .. fb] then
                    BG["Button" .. fb]:SetEnabled(true)
                end
            end
            if BG.FB1 and BG["Button" .. BG.FB1] then
                BG["Button" .. BG.FB1]:SetEnabled(false)
            end
            if BG.NanDuDropDown and BG.NanDuDropDown.DropDown then
                SafeShow(BG.NanDuDropDown.DropDown)
                if LibBG and LibBG.UIDropDownMenu_EnableDropDown then
                    LibBG:UIDropDownMenu_EnableDropDown(BG.NanDuDropDown.DropDown)
                end
            end
            if BG.UpdateBiaoGeAllIsHaved then
                BG.UpdateBiaoGeAllIsHaved()
            end
            if BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2 then
                BG.FilterClassItemMainFrame.Buttons2:SetParent(self)
                SafeHide(BG.FilterClassItemMainFrame)
                BG.FilterClassItemMainFrame.Buttons2:UpdatePoint()
            end
            if BG.ButtonImportHope then
                BG.ButtonImportHope:SetParent(self)
                BG.ButtonExportHope:SetParent(self)
            end
        end)

        BG.HopeMainFrame:SetScript("OnHide", function(self)
            for i, fb in ipairs(BG.FBtable or {}) do
                SafeHide(BG["HopeFrame" .. fb])
            end
            SafeHide(BG.FilterClassItemMainFrame)
        end)
        SafeHide(BG.HopeMainFrame)
    end

    -- 4. 角色总览初始化
    if BG.RoleOverviewUI then
        securecall(BG.RoleOverviewUI)
    end

    -- 4.5 团队工具初始化
    if ns.RaidTool and ns.RaidTool.CreateUI then
        securecall(ns.RaidTool.CreateUI, BG.MainFrame)
    end

    if BG.RaidToolMainFrame then
        BG.RaidToolMainFrame:SetScript("OnShow", function(self)
            BG.FrameHide(0)
            SafeHide(BG.FBMainFrame)
            SafeHide(BG.ItemLibMainFrame)
            SafeHide(BG.HopeMainFrame)
            SafeHide(BG.DuiZhangMainFrame)
            SafeHide(BG.TabButtonsFB)
            BiaoGe.lastFrame = "RaidTool"
            if ns.RaidTool and ns.RaidTool.SyncCurrentRaidRoster then
                ns.RaidTool.SyncCurrentRaidRoster(false)
            end
        end)
    end

    -- 5. 挂载底部 TabButtons
    BG.ItemLibMainFrameTabNum = BG.ItemLibMainFrameTabNum or 20
    BG.HopeMainFrameTabNum = BG.HopeMainFrameTabNum or 21
    BG.RaidToolMainFrameTabNum = BG.RaidToolMainFrameTabNum or 22

    if BG.Create_TabButton then
        if not BG.ButtonTabItemLib then
            BG.ButtonTabItemLib = BG.Create_TabButton(BG.ItemLibMainFrameTabNum, L["装备库"], BG.ItemLibMainFrame)
        end
        if not BG.ButtonTabHope then
            BG.ButtonTabHope = BG.Create_TabButton(BG.HopeMainFrameTabNum, L["心愿清单"], BG.HopeMainFrame)
        end
        if not BG.ButtonTabRaidTool and BG.RaidToolMainFrame then
            BG.ButtonTabRaidTool = BG.Create_TabButton(BG.RaidToolMainFrameTabNum, L["团队工具"], BG.RaidToolMainFrame)
        end
        BG.TradeHistoryMainFrameTabNum = BG.TradeHistoryMainFrameTabNum or 101
        if not BG.ButtonTabTrade and not BG.TradeHistoryTabButton and BG.TradeHistoryMainFrame then
            BG.ButtonTabTrade = BG.Create_TabButton(BG.TradeHistoryMainFrameTabNum, L["交易记录"], BG.TradeHistoryMainFrame)
            BG.TradeHistoryTabButton = BG.ButtonTabTrade
            if BG.OnEnterDelay then
                BG.OnEnterDelay(BG.ButtonTabTrade, function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(L["< 交易记录 >"], 1, 1, 1, true)
                    GameTooltip:AddLine(L["查看和搜索与玩家的交易历史记录。"], 1, 0.82, 0, true)
                    GameTooltip:Show()
                end, 0.5, true)
            end
        end
    end

    -- 隐藏交易面板底部的「交易选项设置」按钮
    local function HideTradeOptionButton()
        if not BG.TradeHistoryMainFrame then return end
        local textToFind = (L and L["交易选项设置"]) or "交易选项设置"
        local children = { BG.TradeHistoryMainFrame:GetChildren() }
        for _, child in ipairs(children) do
            if child.GetText and child:GetText() == textToFind then
                child:Hide()
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -9999, -9999)
                child:HookScript("OnShow", function(self) self:Hide() end)
            end
        end
    end
    HideTradeOptionButton()
    if BG.TradeHistoryMainFrame and not BG.TradeHistoryMainFrame.hasHookedHideOptionBtn then
        BG.TradeHistoryMainFrame.hasHookedHideOptionBtn = true
        BG.TradeHistoryMainFrame:HookScript("OnShow", HideTradeOptionButton)
    end

    -- 5.5 表格主框架 (FBMainFrame) 生命周期补齐与装备过滤挂载 & 团队信息侧边栏
    if BG.FBMainFrame and not BG.FBMainFrame.hasHookedPlusOnShow then
        BG.FBMainFrame.hasHookedPlusOnShow = true

        -- 创建团队信息组件 (顶部入口按钮与右侧抽屉面板)
        if ns.TeamInfo and ns.TeamInfo.CreateUI then
            ns.TeamInfo.CreateUI()
        end

        BG.FBMainFrame:HookScript("OnShow", function(self)
            if BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2 then
                BG.FilterClassItemMainFrame.Buttons2:SetParent(self)
                SafeShow(BG.FilterClassItemMainFrame.Buttons2)
                if BG.FilterClassItemMainFrame.Buttons2.UpdatePoint then
                    BG.FilterClassItemMainFrame.Buttons2:UpdatePoint()
                end
                SafeHide(BG.FilterClassItemMainFrame)

                -- 挂载心理价格入口按钮
                if ns.BestPrice and ns.BestPrice.CreateEntryButton then
                    local entryBtn = ns.BestPrice.CreateEntryButton(BG.FilterClassItemMainFrame.Buttons2)
                    if entryBtn then SafeShow(entryBtn) end
                end
            end
            if ns.BestPrice and ns.BestPrice.HookAllTableButtons then
                ns.BestPrice.HookAllTableButtons()
            end
            if BG.UpdateAllFilter then
                BG.UpdateAllFilter()
            end
            if ns.TeamInfo and ns.TeamInfo.topBtn then
                SafeShow(ns.TeamInfo.topBtn)
            end
            if BiaoGe and BiaoGe.options and BiaoGe.options.showTeamInfoFrame == 1 then
                if ns.TeamInfo and ns.TeamInfo.sideFrame then
                    SafeShow(ns.TeamInfo.sideFrame)
                end
            end
            if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end
        end)

        BG.FBMainFrame:HookScript("OnHide", function(self)
            if ns.TeamInfo and ns.TeamInfo.sideFrame then
                SafeHide(ns.TeamInfo.sideFrame)
            end
        end)
    end

    -- 6. Hook 主框架、Tab 切换与 副本切换逻辑
    if BG.MainFrame and not BG.MainFrame.hasHookedPlus then
        BG.MainFrame.hasHookedPlus = true
        BG.MainFrame:HookScript("OnHide", function()
            HideAllSubFrames()
            if ns.TeamInfo and ns.TeamInfo.sideFrame then
                SafeHide(ns.TeamInfo.sideFrame)
            end
        end)

        if BG.ClickTabButton then
            local orig_ClickTab = BG.ClickTabButton
            BG.ClickTabButton = function(num)
                if num ~= BG.ItemLibMainFrameTabNum and BG.ItemLibMainFrame then
                    SafeHide(BG.ItemLibMainFrame)
                end
                if num ~= BG.HopeMainFrameTabNum and BG.HopeMainFrame then
                    SafeHide(BG.HopeMainFrame)
                end
                if num ~= BG.RaidToolMainFrameTabNum and BG.RaidToolMainFrame then
                    SafeHide(BG.RaidToolMainFrame)
                end
                if num ~= BG.TradeHistoryMainFrameTabNum and BG.TradeHistoryMainFrame then
                    SafeHide(BG.TradeHistoryMainFrame)
                end
                if num ~= (BG.FBMainFrameTabNum or 1) then
                    if ns.TeamInfo and ns.TeamInfo.topBtn then SafeHide(ns.TeamInfo.topBtn) end
                    if ns.TeamInfo and ns.TeamInfo.sideFrame then SafeHide(ns.TeamInfo.sideFrame) end
                elseif num == (BG.FBMainFrameTabNum or 1) then
                    if ns.TeamInfo and ns.TeamInfo.topBtn then SafeShow(ns.TeamInfo.topBtn) end
                    if BiaoGe and BiaoGe.options and BiaoGe.options.showTeamInfoFrame == 1 then
                        if ns.TeamInfo and ns.TeamInfo.sideFrame then SafeShow(ns.TeamInfo.sideFrame) end
                    end
                    if ns.TeamInfo and ns.TeamInfo.UpdateUI then ns.TeamInfo.UpdateUI() end
                end

                orig_ClickTab(num)

                -- 装备过滤方案按钮栏按 Tab 智能归属与显隐
                if BG.FilterClassItemMainFrame and BG.FilterClassItemMainFrame.Buttons2 then
                    local b2 = BG.FilterClassItemMainFrame.Buttons2
                    if num == (BG.FBMainFrameTabNum or 1) and BG.FBMainFrame then
                        b2:SetParent(BG.FBMainFrame)
                        SafeShow(b2)
                        if b2.UpdatePoint then b2:UpdatePoint() end
                        if BG.UpdateAllFilter then BG.UpdateAllFilter() end
                        if ns.BestPrice and ns.BestPrice.entryButton then SafeShow(ns.BestPrice.entryButton) end
                    elseif num == BG.HopeMainFrameTabNum and BG.HopeMainFrame then
                        b2:SetParent(BG.HopeMainFrame)
                        SafeShow(b2)
                        if b2.UpdatePoint then b2:UpdatePoint() end
                        if BG.UpdateAllFilter then BG.UpdateAllFilter() end
                        if ns.BestPrice and ns.BestPrice.entryButton then SafeShow(ns.BestPrice.entryButton) end
                    elseif num == BG.ItemLibMainFrameTabNum and BG.ItemLibMainFrame then
                        b2:SetParent(BG.ItemLibMainFrame)
                        SafeShow(b2)
                        b2:ClearAllPoints()
                        if BG.ItemLibMainFrame.filtleText then
                            b2:SetPoint("LEFT", BG.ItemLibMainFrame.filtleText, "RIGHT", 10, 0)
                        end
                        if ns.BestPrice and ns.BestPrice.entryButton then SafeHide(ns.BestPrice.entryButton) end
                    else
                        -- 其他 Tab (对账/历史/团队工具等) 隐藏装备过滤按钮栏与心理价格按钮
                        SafeHide(b2)
                        SafeHide(BG.FilterClassItemMainFrame)
                        if ns.BestPrice and ns.BestPrice.entryButton then SafeHide(ns.BestPrice.entryButton) end
                    end
                end
            end
        end
    end

    if BG.ClickFBbutton and not BG.hasHookedFBButtonPlus then
        BG.hasHookedFBButtonPlus = true
        local orig_ClickFBbutton = BG.ClickFBbutton
        BG.ClickFBbutton = function(FB)
            if BiaoGe and FB then
                BiaoGe[FB] = BiaoGe[FB] or {}
                BiaoGe[FB].tradeTbl = BiaoGe[FB].tradeTbl or {}
            end
            orig_ClickFBbutton(FB)
            if BG.HopeMainFrame and BG.HopeMainFrame:IsVisible() then
                for i, fb in ipairs(BG.FBtable or {}) do
                    SafeHide(BG["HopeFrame" .. fb])
                end
                if BG["HopeFrame" .. FB] then
                    SafeShow(BG["HopeFrame" .. FB])
                end
            elseif BG.ItemLibMainFrame and BG.ItemLibMainFrame:IsVisible() and BG.UpdateItemLib then
                BG.UpdateItemLib()
            end

            -- 切换副本后自动刷新装备过滤变灰状态与团队信息
            if BG.UpdateAllFilter then
                BG.UpdateAllFilter()
            end
            if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end
        end
    end

    -- 初始化加载时恢复上次退出的 Tab 面板（默认表格）
    RestoreLastTab()

    -- 7. 物品信息加载回调防抖刷新
    if not ns.hasHookedItemInfoEvent then
        ns.hasHookedItemInfoEvent = true
        local itemEventFrame = CreateFrame("Frame")
        itemEventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        local isPendingUpdate = false
        itemEventFrame:SetScript("OnEvent", function()
            if BG.MainFrame and BG.MainFrame:IsVisible() and not isPendingUpdate then
                isPendingUpdate = true
                C_Timer.After(0.2, function()
                    isPendingUpdate = false
                    if BG.MainFrame and BG.MainFrame:IsVisible() and BG.UpdateAllFilter then
                        BG.UpdateAllFilter()
                    end
                end)
            end
        end)
    end

    -- 8. 小地图钩子
    HookMinimap()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    InitPlusUI()
    HookMinimap()
end)
