if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L

--[[
    BGLite_Plus 交易记录轻量激活模块
    设计说明：
    上游 BGLite 原版已完整内置了 TradeHistory 核心逻辑与全套 UI (BG.TradeHistoryMainFrame)，
    仅在 BiaoGe.lua 中策划临时隐藏了底部 Tab 入口 (bt:Hide())。
    本模块遵循零冗余原则，不再重复创建第二套相同的 UI，而是直接复用上游原生框架，
    仅负责恢复底部 Tab 按钮并在必要时做显示刷新守护，彻底杜绝双层 UI 叠加透光的缺陷。
--]]

local function InitTradeHistoryModule()
    if not (BG and BG.TradeHistoryMainFrame and BG.TradeHistoryMainFrameTabNum) then return end
    if ns.hasInitializedTradeTab then return end
    ns.hasInitializedTradeTab = true

    -- 1. 恢复底部 Tab 按钮
    if BG.Create_TabButton and not BG.TradeHistoryTabButton then
        local btTrade = BG.Create_TabButton(BG.TradeHistoryMainFrameTabNum, L["交易记录"], BG.TradeHistoryMainFrame, 100)
        BG.TradeHistoryTabButton = btTrade
        if BG.OnEnterDelay then
            BG.OnEnterDelay(btTrade, function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["< 交易记录 >"], 1, 1, 1, true)
                GameTooltip:AddLine(L["查看和搜索与玩家的交易历史记录。"], 1, 0.82, 0, true)
                GameTooltip:Show()
            end, 0.5, true)
        end
    end

    -- 2. 上游 UI 刷新与提示文字（notText）防御守护
    local mf = BG.TradeHistoryMainFrame
    if mf and not mf.hasHookedTradeHistoryPlus then
        mf.hasHookedTradeHistoryPlus = true
        mf:HookScript("OnShow", function(self)
            if BG.UpdateTradeHistoryScrollFrame then
                BG.UpdateTradeHistoryScrollFrame()
            end
            -- 双重安全防御：如果已渲染出数据，确保 notText 不会因边界条件透出
            if self.notText and self.frame and self.frame.scroll then
                -- 依据当前滚动列表状态动态纠正显隐
                if BG.UpdateTradeHistoryScrollFrame then
                    BG.UpdateTradeHistoryScrollFrame()
                end
            end
        end)
    end
end

ns.InitTradeHistoryModule = InitTradeHistoryModule

-- 自启动检测
if IsLoggedIn() then
    InitTradeHistoryModule()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        InitTradeHistoryModule()
    end)
end
