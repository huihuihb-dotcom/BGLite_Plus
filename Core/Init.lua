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
    SafeHide(BG.AuctionPresetMainFrame)
    SafeHide(BG.TitanGoblinMainFrame)
    if _G["BG_RaidCompMatrixModalFrame"] then
        SafeHide(_G["BG_RaidCompMatrixModalFrame"])
    end
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

    -- 0.1 保护上游 BGLite 拍卖聊天历史表，避免上游缺失初始化导致 tinsert 报 nil
    if BiaoGe and BiaoGe.auctionMSGhistory == nil then
        BiaoGe.auctionMSGhistory = {}
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
    if ns.TitanGoblin and ns.TitanGoblin.CreateMainFrame then
        ns.TitanGoblin.CreateMainFrame(BG.MainFrame)
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
                pcall(ns.RaidTool.SyncCurrentRaidRoster, false)
            end
            if ns.RaidComp and ns.RaidComp.UpdateUI then
                pcall(ns.RaidComp.UpdateUI)
            end
        end)
    end

    -- 4.6 团队阵容天赋分析与 Buff 缺口初始化
    if ns.InitRaidCompModule then
        securecall(ns.InitRaidCompModule)
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
            BG.ButtonTabTrade = BG.Create_TabButton(BG.TradeHistoryMainFrameTabNum, L["交易记录"], BG.TradeHistoryMainFrame, 90)
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

    -- 5.1 底部 Tab 栏逻辑排序与绝对居中对齐机制
    function ns.UpdateTabButtonsLayout()
        if not (BG and BG.tabButtons and BG.MainFrame) then return end

        -- 逻辑权重排序表：
        -- 1. 表格 -> 2. 对账 -> 3. 交易记录 -> 4. 邮件记录 (账务与流水成组紧随表格)
        -- 5. 预设价格 -> 6. 装备库 -> 7. 心愿清单 -> 8. 团队工具 (金团辅助与扩展工具平滑衔接)
        local TAB_ORDER = {
            [BG.FBMainFrameTabNum or 1] = 1,              -- 表格
            [BG.DuiZhangMainFrameTabNum or 2] = 2,         -- 对账
            [BG.TradeHistoryMainFrameTabNum or 101] = 3,   -- 交易记录
            [BG.MailHistoryMainFrameTabNum or 102] = 4,    -- 邮件记录
            [BG.AuctionPresetMainFrameTabNum or 104] = 5,  -- 预设价格
            [BG.ItemLibMainFrameTabNum or 20] = 6,         -- 装备库
            [BG.HopeMainFrameTabNum or 21] = 7,            -- 心愿清单
            [BG.RaidToolMainFrameTabNum or 22] = 8,        -- 团队工具
            [BG.TitanGoblinMainFrameTabNum or 105] = 9,   -- 碎片统计
        }

        local validItems = {}
        local hiddenItems = {}
        for _, item in ipairs(BG.tabButtons) do
            if item.button and item.button.IsShown and item.button:IsShown() then
                table.insert(validItems, item)
            else
                table.insert(hiddenItems, item)
            end
        end

        if #validItems == 0 then return end

        -- 按逻辑权重稳定排序
        table.sort(validItems, function(a, b)
            local orderA = TAB_ORDER[a.num] or (1000 + (tonumber(a.num) or 0))
            local orderB = TAB_ORDER[b.num] or (1000 + (tonumber(b.num) or 0))
            return orderA < orderB
        end)

        -- 同步回写 BG.tabButtons 列表顺序，保证逻辑遍历与渲染一致
        wipe(BG.tabButtons)
        for _, item in ipairs(validItems) do
            table.insert(BG.tabButtons, item)
        end
        for _, item in ipairs(hiddenItems) do
            table.insert(BG.tabButtons, item)
        end

        -- 规范统一尺寸：全部 90 宽 x 28 高，按钮间距 3 像素
        local btnWidth = 90
        local btnHeight = 28
        local spacing = 3
        local totalWidth = 0

        for _, item in ipairs(validItems) do
            local bt = item.button
            bt:SetSize(btnWidth, btnHeight)
            totalWidth = totalWidth + btnWidth
        end
        totalWidth = totalWidth + (#validItems - 1) * spacing

        -- 绝对居中：以主界面底部中心点 (BOTTOM, X=0) 为基准，向左偏移总宽度的一半
        local startX = -math.floor(totalWidth / 2)

        for i, item in ipairs(validItems) do
            local bt = item.button
            bt:ClearAllPoints()
            if i == 1 then
                bt:SetPoint("TOPLEFT", BG.MainFrame, "BOTTOM", startX, 1)
            else
                local prevBt = validItems[i - 1].button
                bt:SetPoint("LEFT", prevBt, "RIGHT", spacing, 0)
            end
        end
    end

    -- 挂载完成后立即执行一次居中排布
    ns.UpdateTabButtonsLayout()

    -- 安全挂钩：后续若有任何新 Tab 动态创建，自动重新居中排布
    if BG.Create_TabButton and not BG.hasHookedTabButtonLayout then
        BG.hasHookedTabButtonLayout = true
        hooksecurefunc(BG, "Create_TabButton", function()
            if ns.UpdateTabButtonsLayout then
                ns.UpdateTabButtonsLayout()
            end
        end)
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
        BG.MainFrame:HookScript("OnShow", function()
            RestoreLastTab()
            if ns.UpdateTabButtonsLayout then
                ns.UpdateTabButtonsLayout()
            end
        end)
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

    -- 9. 底部 Plus 版本控件
    if ns.CreatePlusVerFrame then
        ns.CreatePlusVerFrame()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    InitPlusUI()
    HookMinimap()
    if ns.CreatePlusVerFrame then
        ns.CreatePlusVerFrame()
    end
end)

--------------------------------------------------------------------------------
-- 9. BGLite_Plus 专属版本通信协议 (Plus Version Check Engine)
--------------------------------------------------------------------------------
ns.ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(AddonName, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(AddonName, "Version"))
    or "1.0.9"

BG.plusVer = ns.ver
BG.raidPlusVersion = BG.raidPlusVersion or {}
BG.guildPlusVersion = BG.guildPlusVersion or {}
ns.raidPlusVersion = BG.raidPlusVersion
ns.guildPlusVersion = BG.guildPlusVersion

local COMM_PREFIX_PLUS = "BGLite_Plus"

pcall(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX_PLUS)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(COMM_PREFIX_PLUS)
    end
end)

function ns.SendPlusVersionCheck(channel)
    local dist = channel
    if not dist then
        if IsInRaid and IsInRaid() then
            dist = "RAID"
        elseif IsInGroup and IsInGroup() then
            dist = "PARTY"
        end
    end
    if not dist then return end

    pcall(function()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage(COMM_PREFIX_PLUS, "PlusVersionCheck", dist)
        elseif SendAddonMessage then
            SendAddonMessage(COMM_PREFIX_PLUS, "PlusVersionCheck", dist)
        end
    end)
end

function ns.SendPlusMyVer(dist)
    if not dist then return end
    pcall(function()
        local msg = "PlusMyVer-" .. tostring(ns.ver)
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage(COMM_PREFIX_PLUS, msg, dist)
        elseif SendAddonMessage then
            SendAddonMessage(COMM_PREFIX_PLUS, msg, dist)
        end
    end)
end

local verFrame = CreateFrame("Frame")
verFrame:RegisterEvent("CHAT_MSG_ADDON")
verFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
verFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

local function SafeTrimStr(s)
    if not s then return "" end
    s = tostring(s)
    if _G.strtrim then return _G.strtrim(s) end
    return s:match("^%s*(.-)%s*$") or s
end

local function CleanVerPlayerName(name)
    if not name then return "" end
    name = tostring(name)
    name = name:gsub("|Hplayer:([^|:]+).-|h.-|h", "%1")
    name = name:gsub("|H.-|h", "")
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = SafeTrimStr(name:gsub("[%[%]]", ""))
    local first = strsplit("-", name)
    return SafeTrimStr(first)
end

verFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, distType, sender = ...
        if prefix ~= COMM_PREFIX_PLUS then return end

        sender = CleanVerPlayerName(sender)
        local myName = CleanVerPlayerName(UnitName("player"))

        if msg == "PlusVersionCheck" then
            -- 收到版本查询，自动向对应频道回送自身 Plus 版本
            if sender ~= myName then
                ns.SendPlusMyVer(distType)
            end
        elseif msg and msg:find("^PlusMyVer%-") then
            local _, ver = strsplit("-", msg)
            if ver and ver ~= "" then
                if distType == "RAID" or distType == "PARTY" then
                    ns.raidPlusVersion[sender] = ver
                    if ns.UpdatePlusVerFrame then
                        ns.UpdatePlusVerFrame()
                    end
                elseif distType == "GUILD" then
                    ns.guildPlusVersion[sender] = ver
                    if ns.UpdatePlusVerFrame then
                        ns.UpdatePlusVerFrame()
                    end
                end
            end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if ns.UpdatePlusVerFrame then
            ns.UpdatePlusVerFrame()
        end
        -- 队伍变动防抖 1.5 秒后主动握手版本
        if self.timer then self.timer:Cancel() end
        self.timer = C_Timer.NewTimer(1.5, function()
            if (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup()) then
                ns.SendPlusVersionCheck()
            end
            if ns.UpdatePlusVerFrame then
                ns.UpdatePlusVerFrame()
            end
        end)
    elseif event == "GUILD_ROSTER_UPDATE" then
        if ns.UpdatePlusVerFrame then
            ns.UpdatePlusVerFrame()
        end
    end
end)

--------------------------------------------------------------------------------
-- 主界面底部【Plus 增强包版本】控件 (位于工会插件 - 团队插件右侧最底部)
--------------------------------------------------------------------------------
local function PlusVer_OnEnter(self)
    if not self then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
    GameTooltip:ClearLines()
    self.isOnEnter = true

    -- 严格对齐魔兽与BGLite原生规则：
    -- 只有真正的团队团本（IsInRaid(1)）才显示团队；5人小队或个人状态下100%跟随公会（IsInGuild）显示！
    local inRaid = IsInRaid and IsInRaid(1)
    local inGuild = IsInGuild and IsInGuild()

    if inRaid then
        GameTooltip:AddLine(ns.L["BGLite_Plus增强包版本"] .. "(" .. (RAID or "团队") .. ")", 0, 1, 0)
        GameTooltip:AddLine(" ")

        local rosterList = (BG.SortRaidRosterInfo and BG.SortRaidRosterInfo()) or (BG.raidRosterInfo) or {}
        local line = 2
        local myName = CleanVerPlayerName(UnitName("player"))

        for i, v in ipairs(rosterList) do
            local name = v.name or ""
            local cleanName = CleanVerPlayerName(name)
            local ver = ns.raidPlusVersion[cleanName]
            if cleanName == myName then
                ver = ns.ver
            end

            local r, g, b = 1, 1, 1
            if not ver then
                if v.online == false then
                    ver = ns.L["未知(离线)"]
                else
                    ver = ns.L["无"]
                end
                r, g, b = 0.5, 0.5, 0.5
            else
                r, g, b = 0, 1, 0
            end

            local role = ""
            if v.rank == 2 then
                role = role .. (ns.AddTexture and ns.AddTexture("interface/groupframe/ui-group-leadericon") or "")
            elseif v.rank == 1 then
                role = role .. (ns.AddTexture and ns.AddTexture("interface/groupframe/ui-group-assistanticon") or "")
            end
            if v.isML then
                role = role .. (ns.AddTexture and ns.AddTexture("interface/groupframe/ui-group-masterlooter") or "")
            end

            local c1, c2, c3 = 1, 1, 1
            if ns.GetClassRGB then
                c1, c2, c3 = ns.GetClassRGB(name)
            end

            GameTooltip:AddDoubleLine(name .. role, ver, c1, c2, c3, r, g, b)

            if ver == ns.L["无"] or ver == ns.L["未知(离线)"] then
                local alpha = 0.4
                local leftLine = _G["GameTooltipTextLeft" .. (i + line)]
                local rightLine = _G["GameTooltipTextRight" .. (i + line)]
                if leftLine then leftLine:SetAlpha(alpha) end
                if rightLine then rightLine:SetAlpha(alpha) end
            end
        end
    elseif inGuild then
        GameTooltip:AddLine(ns.L["BGLite_Plus增强包版本"] .. "(" .. (GUILD or "公会") .. ")", 0, 1, 0)
        GameTooltip:AddLine(" ")

        local ii = 0
        local numTotal = GetNumGuildMembers and GetNumGuildMembers() or 0
        local myName = CleanVerPlayerName(UnitName("player"))

        for i = 1, numTotal do
            local name, rankName, rankIndex, level, classDisplayName, zone,
            publicNote, officerNote, isOnline, status, class = GetGuildRosterInfo(i)
            if isOnline and name then
                name = BG.GSN and BG.GSN(name) or name
                local cleanName = CleanVerPlayerName(name)
                if ii > 40 then
                    GameTooltip:AddLine("......")
                    break
                end
                ii = ii + 1
                local ver = ns.guildPlusVersion[cleanName]
                if cleanName == myName then
                    ver = ns.ver
                end

                local r, g, b = 1, 1, 1
                if not ver then
                    ver = ns.L["无"]
                    r, g, b = 0.5, 0.5, 0.5
                else
                    r, g, b = 0, 1, 0
                end

                local c1, c2, c3 = 1, 1, 1
                if class and GetClassColor then
                    c1, c2, c3 = GetClassColor(class)
                elseif ns.GetClassRGB then
                    c1, c2, c3 = ns.GetClassRGB(name)
                end

                GameTooltip:AddDoubleLine(name, ver, c1, c2, c3, r, g, b)
            end
        end
    else
        GameTooltip:AddLine(ns.L["BGLite_Plus增强包版本"], 0, 1, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(CleanVerPlayerName(UnitName("player")), ns.ver, 0, 1, 0, 0, 1, 0)
    end
    GameTooltip:Show()
end

local function PlusVer_OnLeave(self)
    GameTooltip:Hide()
    self.isOnEnter = false
end

function ns.CreatePlusVerFrame()
    if not (BG and BG.MainFrame) then return end
    if BG.ButtonRaidPlusVer then return end

    local plusBtn = CreateFrame("Frame", "BG_ButtonRaidPlusVer", BG.MainFrame)
    plusBtn:SetSize(80, 20)
    plusBtn:SetFrameLevel((BG.ButtonGuildVer and BG.ButtonGuildVer:GetFrameLevel() or BG.MainFrame:GetFrameLevel()) + 2)
    plusBtn.title2 = "Plus：%s"
    plusBtn.isPlus = true

    plusBtn.text = plusBtn:CreateFontString()
    plusBtn.text:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 13, "OUTLINE")
    plusBtn.text:SetPoint("LEFT")
    plusBtn.text:SetTextColor(0, 0.82, 1)

    plusBtn:SetScript("OnEnter", PlusVer_OnEnter)
    plusBtn:SetScript("OnLeave", PlusVer_OnLeave)

    BG.ButtonRaidPlusVer = plusBtn

    -- 挂钩主面板打开时立即自愈刷新
    if BG.MainFrame.HookScript then
        BG.MainFrame:HookScript("OnShow", function()
            ns.UpdatePlusVerFrame()
        end)
    end

    ns.UpdatePlusVerFrame()
end

function ns.UpdatePlusVerFrame()
    local btn = BG.ButtonRaidPlusVer
    if not btn then
        if BG.MainFrame then
            ns.CreatePlusVerFrame()
            btn = BG.ButtonRaidPlusVer
        end
    end
    if not btn then return end

    -- 严格遵循 BGLite 原生标准：
    -- 只有处于团队状态 IsInRaid(1) 才作为团队处理；
    -- 个人状态或5人小队状态，完全跟随公会（公会插件）！
    local inRaid = IsInRaid and IsInRaid(1)
    local inGuild = IsInGuild and IsInGuild()

    btn:ClearAllPoints()
    if inRaid then
        if BG.ButtonRaidAuction and BG.ButtonRaidAuction:IsShown() and BG.ButtonRaidAuction:GetWidth() > 1 then
            btn:SetPoint("LEFT", BG.ButtonRaidAuction, "RIGHT", 6, 0)
        elseif BG.ButtonRaidVer and BG.ButtonRaidVer:IsShown() and BG.ButtonRaidVer:GetWidth() > 1 then
            btn:SetPoint("LEFT", BG.ButtonRaidVer, "RIGHT", 6, 0)
        else
            btn:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 10, 2)
        end

        local myName = CleanVerPlayerName(UnitName("player"))
        local count = 0
        local total = (GetNumGroupMembers and GetNumGroupMembers()) or 0

        if BG.raidRosterInfo and #BG.raidRosterInfo > 0 then
            for _, v in ipairs(BG.raidRosterInfo) do
                local cleanName = CleanVerPlayerName(v.name)
                if cleanName == myName or ns.raidPlusVersion[cleanName] then
                    count = count + 1
                end
            end
        else
            for name in pairs(ns.raidPlusVersion) do
                count = count + 1
            end
            if not ns.raidPlusVersion[myName] then
                count = count + 1
            end
        end
        if total == 0 then total = count end
        btn.text:SetFormattedText("Plus：%s", count .. "/" .. total)

    elseif inGuild then
        -- 个人或5人小队：紧靠在【公会插件】右侧！
        if BG.ButtonGuildVer and BG.ButtonGuildVer:IsShown() and BG.ButtonGuildVer:GetWidth() > 1 then
            btn:SetPoint("LEFT", BG.ButtonGuildVer, "RIGHT", 6, 0)
        else
            btn:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 10, 2)
        end

        local numTotal, numOnline = GetNumGuildMembers()
        numOnline = numOnline or 1
        local count = 0
        local myName = CleanVerPlayerName(UnitName("player"))
        for name in pairs(ns.guildPlusVersion) do
            count = count + 1
        end
        if not ns.guildPlusVersion[myName] then
            count = count + 1
        end
        btn.text:SetFormattedText("Plus：%s", count .. "/" .. numOnline)
    else
        btn:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 10, 2)
        btn.text:SetText("Plus：1/1")
    end

    btn:SetWidth(btn.text:GetStringWidth() + 10)
    btn:Show()

                if btn.isOnEnter then
        PlusVer_OnEnter(btn)
    end
end

--------------------------------------------------------------------------------

-- 10. BGLite 专属输入框焦点管理与错误状态自愈体系 (SafeInput & FocusGuard)
--------------------------------------------------------------------------------
-- 核心设计与准则：
-- 1. 严格守界 (Boundary Guard)：严禁全局无差别 Hook StaticPopup_Hide 或 WorldFrame:OnMouseDown！
--    杜绝干扰暴雪原生弹窗（如销毁装备 DELETE_GOOD_ITEM、删除角色、解散公会等），彻底解决原生弹窗无法输入的问题。
-- 2. 错误保护 (SafeCommit & pcall)：在用户回车、点击确认或执行业务计算时全程采用保护模式执行。
--    即使业务代码发生任何未预料的 Lua 报错，保证在 finally 阶段无条件执行 ClearFocus() 和重置 IME 高亮，彻底终结“报错即卡键”！
-- 3. 生命周期自愈 (Lifecycle Cleanup)：在父级隐藏、控件禁用 (Disable) 或失去焦点时，自动级联清理选区与残留焦点。

-- ① 归属判定：精准识别是否属于 BGLite / BGLite_Plus 管辖的组件
function ns.IsBGLiteElement(frame)
    if not frame then return false end
    if frame._isBGLiteManaged then return true end

    local current = frame
    local depth = 0
    while current and depth < 10 do
        if current == (BG and BG.MainFrame) or current == (ns.TeamInfo and ns.TeamInfo.sideFrame) then
            return true
        end
        local name = current.GetName and current:GetName()
        if name then
            if name:find("^BGLite") or name:find("^BiaoGe") or name:find("^BG_") then
                return true
            end
        end
        if current == UIParent or current == WorldFrame then
            break
        end
        current = current.GetParent and current:GetParent()
        depth = depth + 1
    end
    return false
end

-- ② 错误保护提交机制：带 pcall 异常捕获与必定脱焦兜底
function ns.SafeCommit(editBox, callback)
    local ok, err
    if callback then
        ok, err = pcall(callback, editBox)
        if not ok then
            local errMsg = format("|cffff2020[BGLite 输入异常]|r %s", tostring(err))
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage(errMsg)
            end
        end
    end
    -- 核心保障 (Finally 机制)：无论业务逻辑是否抛错，100% 强制清空高亮并安全脱焦，收回键盘控制权
    if editBox then
        if editBox.HighlightText then editBox:HighlightText(0, 0) end
        if editBox.ClearFocus then editBox:ClearFocus() end
    end
    return ok, err
end

-- ③ 界面级安全防御：BGLite 主界面隐藏（按 ESC 或点击关闭）时，仅回收属于本插件的残留焦点
if BG and BG.MainFrame then
    BG.MainFrame:HookScript("OnHide", function()
        local currentFocus = GetFocus and GetFocus()
        if currentFocus and currentFocus.IsObjectType and currentFocus:IsObjectType("EditBox") then
            if ns.IsBGLiteElement(currentFocus) then
                if currentFocus.HighlightText then currentFocus:HighlightText(0, 0) end
                if currentFocus.ClearFocus then currentFocus:ClearFocus() end
            end
        end
    end)
end

-- ④ 标准化安全输入框装配器 (支持 pcall 保护、异常自愈、禁用与失焦级联回收)
function ns.SecureEditBox(editBox, options, legacyOnEscape)
    if not editBox then return end
    editBox._isBGLiteManaged = true

    local opts = options
    if type(options) == "function" then
        opts = {
            onEnter = options,
            onEscape = legacyOnEscape,
        }
    elseif type(options) ~= "table" then
        opts = {}
    end

    editBox:SetAutoFocus(false)

    -- OnEscapePressed: 安全脱焦并清空选区，执行可选取消逻辑
    editBox:HookScript("OnEscapePressed", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
        if self.ClearFocus then self:ClearFocus() end
        if opts.onEscape then
            pcall(opts.onEscape, self)
        end
    end)

    -- OnEnterPressed: 无论回调成功或异常抛错，均必定收回焦点
    editBox:HookScript("OnEnterPressed", function(self)
        ns.SafeCommit(self, function(eb)
            -- 若开启数字类型校验，在提交前完成异常数据自愈与容错
            if opts.isNumeric then
                local text = eb:GetText() or ""
                local num = tonumber(text)
                if not num then
                    if opts.defaultValue ~= nil then
                        eb:SetText(tostring(opts.defaultValue))
                    end
                    if opts.errorTip and UIErrorsFrame then
                        UIErrorsFrame:AddMessage(opts.errorTip, 1, 0.2, 0.2)
                    end
                elseif opts.minValue and num < opts.minValue then
                    eb:SetText(tostring(opts.minValue))
                    if UIErrorsFrame then UIErrorsFrame:AddMessage("数值低于下限，已自动重置", 1, 0.8, 0) end
                elseif opts.maxValue and num > opts.maxValue then
                    eb:SetText(tostring(opts.maxValue))
                    if UIErrorsFrame then UIErrorsFrame:AddMessage("数值超出上限，已自动限制", 1, 0.8, 0) end
                end
            end
            if opts.onEnter then
                opts.onEnter(eb)
            end
        end)
    end)

    -- OnEditFocusLost: 释放 IME 高亮选区，防止输入法拦截
    editBox:HookScript("OnEditFocusLost", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
        if opts.onFocusLost then
            pcall(opts.onFocusLost, self)
        end
    end)

    -- OnHide: 框架隐藏时，若持有焦点则平稳脱焦
    editBox:HookScript("OnHide", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
        if self.ClearFocus and (self.HasFocus and self:HasFocus()) then
            self:ClearFocus()
        end
    end)

    -- 禁用状态联动：控件被 Disable 时主动脱焦，杜绝幽灵焦点
    if editBox.Disable then
        hooksecurefunc(editBox, "Disable", function(self)
            if self.ClearFocus and (self.HasFocus and self:HasFocus()) then
                if self.HighlightText then self:HighlightText(0, 0) end
                self:ClearFocus()
            end
        end)
    end
    if editBox.SetEnabled then
        hooksecurefunc(editBox, "SetEnabled", function(self, enabled)
            if not enabled and self.ClearFocus and (self.HasFocus and self:HasFocus()) then
                if self.HighlightText then self:HighlightText(0, 0) end
                self:ClearFocus()
            end
        end)
    end

    -- 绑定确认按钮联动
    if opts.commitButton then
        opts.commitButton:HookScript("OnClick", function()
            ns.SafeCommit(editBox, function(eb)
                if opts.onEnter then opts.onEnter(eb) end
            end)
        end)
    end
end

