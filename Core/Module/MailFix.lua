if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L

--------------------------------------------------------------------------------
-- 上游邮件记录 (MailHistory) 与交易记录 (TradeHistory) 数据库动态守护自愈补丁
-- 作用：彻底根治上游 MailHistory.lua:299 attempt to index field '?' (a nil value) 报错
-- 卸载方式：若后期官方 BGLite 修复了该问题，可直接在 BGLite_Plus.toc 中移除本文件
--------------------------------------------------------------------------------

local function ProtectHistoryTable(rootTable)
    if not rootTable or type(rootTable) ~= "table" then return end

    local function WrapRealm(r, realmTbl)
        if type(realmTbl) ~= "table" then return realmTbl end
        local rNum = tonumber(r) or r
        local realmMeta = {
            __bg_history_guard = true,
            __index = function(t, p)
                if type(p) == "string" and p ~= "" then
                    local pName = UnitName("player")
                    local pClass = (p == pName) and select(2, UnitClass("player")) or nil
                    local pLevel = (p == pName) and (UnitLevel("player") or 0) or 0
                    local newPlayerTbl = {
                        name = p,
                        realmID = rNum,
                        info = {},
                        class = pClass,
                        level = pLevel,
                    }
                    rawset(t, p, newPlayerTbl)
                    return newPlayerTbl
                end
            end
        }
        return setmetatable(realmTbl, realmMeta)
    end

    -- 包装所有已存在的 realm 表
    for r, realmTbl in pairs(rootTable) do
        if type(realmTbl) == "table" and (type(r) == "number" or tonumber(r)) then
            WrapRealm(r, realmTbl)
            for p, playerTbl in pairs(realmTbl) do
                if type(playerTbl) == "table" and not playerTbl.info then
                    playerTbl.info = {}
                end
            end
        end
    end

    -- 给 rootTable 挂载 __index 保护
    local rootMeta = getmetatable(rootTable)
    if not (rootMeta and rootMeta.__bg_history_guard) then
        setmetatable(rootTable, {
            __bg_history_guard = true,
            __index = function(t, r)
                if type(r) == "number" or (type(r) == "string" and tonumber(r)) then
                    local newRealmTbl = WrapRealm(r, {})
                    rawset(t, r, newRealmTbl)
                    return newRealmTbl
                end
            end
        })
    end

    -- 主动为当前登录角色创建确切节点
    local player = UnitName("player")
    local realmID = GetRealmID()
    if player and realmID then
        rootTable[realmID] = rootTable[realmID] or {}
        WrapRealm(realmID, rootTable[realmID])
        rootTable[realmID][player] = rootTable[realmID][player] or {
            name = player,
            realmID = realmID,
            info = {},
        }
        rootTable[realmID][player].info = rootTable[realmID][player].info or {}
        rootTable[realmID][player].name = rootTable[realmID][player].name or player
        rootTable[realmID][player].realmID = rootTable[realmID][player].realmID or realmID
        if not rootTable[realmID][player].class then
            rootTable[realmID][player].class = select(2, UnitClass("player"))
        end
        if not rootTable[realmID][player].level or rootTable[realmID][player].level == 0 then
            rootTable[realmID][player].level = UnitLevel("player")
        end
    end
end

local function ProtectAllLegacyHistory()
    if not BiaoGe then return end
    if BiaoGe.mailHistory then
        ProtectHistoryTable(BiaoGe.mailHistory)
    end
    if BiaoGe.tradeHistory then
        ProtectHistoryTable(BiaoGe.tradeHistory)
    end
end

local function InitMailFix()
    ProtectAllLegacyHistory()
end

ns.InitMailFix = InitMailFix

-- 邮箱与交易事件即时守护帧：在进世界、打开邮箱、更新收件、开启交易时毫秒级自愈确保
local historyGuardFrame = CreateFrame("Frame")
historyGuardFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
historyGuardFrame:RegisterEvent("MAIL_SHOW")
historyGuardFrame:RegisterEvent("MAIL_INBOX_UPDATE")
historyGuardFrame:RegisterEvent("TRADE_SHOW")
historyGuardFrame:SetScript("OnEvent", function()
    ProtectAllLegacyHistory()
end)

if IsLoggedIn() then
    InitMailFix()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        InitMailFix()
    end)
end
