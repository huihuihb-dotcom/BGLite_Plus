if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L

local function InitTradeFix()
    if not (BG and BG.trade and BG.TradeUpdate) then return end
    if ns.hasInitializedTradeFix then return end
    ns.hasInitializedTradeFix = true

    hooksecurefunc("AcceptTrade", function()
        BG.trade.isAccepted = true

        if BG.trade.autoAuction and next(BG.trade.autoAuction) then
            BG.trade.autoAuctionSnapshot = CopyTable(BG.trade.autoAuction)
        end

        BG.trade.snapshot = {
            target = BG.trade.target,
            player = BG.trade.player,
            targetmoney = BG.trade.targetmoney,
            playermoney = BG.trade.playermoney,
            targetitems = BG.trade.targetitems and CopyTable(BG.trade.targetitems) or {},
            playeritems = BG.trade.playeritems and CopyTable(BG.trade.playeritems) or {},
            targetinfo = BG.trade.targetinfo and CopyTable(BG.trade.targetinfo) or {},
            playerinfo = BG.trade.playerinfo and CopyTable(BG.trade.playerinfo) or {},
        }
    end)

    local origTradeUpdate = BG.TradeUpdate
    BG.TradeUpdate = function(...)
        if BG.trade.isAccepted then
            return
        end
        return origTradeUpdate(...)
    end

    BG.RegisterEvent("TRADE_SHOW", function()
        BG.trade.isAccepted = nil
        BG.trade.autoAuctionSnapshot = nil
        BG.trade.snapshot = nil
    end)

    BG.RegisterEvent("TRADE_CLOSED", function()
        C_Timer.After(0, function()
            BG.trade.isAccepted = nil
            BG.trade.autoAuctionSnapshot = nil
            BG.trade.snapshot = nil
        end)
    end)

    local tradeAcceptFrame = CreateFrame("Frame")
    tradeAcceptFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
    tradeAcceptFrame:SetScript("OnEvent", function(self, event, playerAccepted, targetAccepted)
        if BG.trade.isAccepted and playerAccepted == 0 then
            BG.trade.isAccepted = nil
            if TradeFrame and TradeFrame:IsVisible() then
                C_Timer.After(0, function()
                    if not BG.trade.isAccepted then
                        origTradeUpdate()
                    end
                end)
            end
        end
    end)

    local origGetTradeSeeText = BG.GetTradeSeeText
    if origGetTradeSeeText then
        BG.GetTradeSeeText = function(saved, ...)
            if saved and (not BG.trade.autoAuction or not next(BG.trade.autoAuction)) then
                if BG.trade.autoAuctionSnapshot and next(BG.trade.autoAuctionSnapshot) then
                    BG.trade.autoAuction = CopyTable(BG.trade.autoAuctionSnapshot)
                end
                if BG.trade.snapshot then
                    local s = BG.trade.snapshot
                    if s.targetmoney and s.targetmoney > 0 then
                        BG.trade.targetmoney = s.targetmoney
                    end
                    if s.playermoney and s.playermoney > 0 then
                        BG.trade.playermoney = s.playermoney
                    end
                    if s.target and s.target ~= "" then
                        BG.trade.target = s.target
                    end
                    if s.player and s.player ~= "" then
                        BG.trade.player = s.player
                    end
                    if s.targetitems and next(s.targetitems) and not next(BG.trade.targetitems) then
                        BG.trade.targetitems = CopyTable(s.targetitems)
                    end
                    if s.playeritems and next(s.playeritems) and not next(BG.trade.playeritems) then
                        BG.trade.playeritems = CopyTable(s.playeritems)
                    end
                    if s.targetinfo and next(s.targetinfo) and not next(BG.trade.targetinfo) then
                        BG.trade.targetinfo = CopyTable(s.targetinfo)
                    end
                    if s.playerinfo and next(s.playerinfo) and not next(BG.trade.playerinfo) then
                        BG.trade.playerinfo = CopyTable(s.playerinfo)
                    end
                end
            end

            local result = origGetTradeSeeText(saved, ...)

            if saved then
                BG.trade.isAccepted = nil
                BG.trade.autoAuctionSnapshot = nil
                BG.trade.snapshot = nil
            end

            return result
        end
    end

    BG.SendSystemMessage("|cff00FF00[BGLite_Plus]|r 交易防漏单保护已启用")
end

ns.InitTradeFix = InitTradeFix

if IsLoggedIn() then
    InitTradeFix()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        InitTradeFix()
    end)
end
