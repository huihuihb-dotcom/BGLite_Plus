if BG.IsBlackListPlayer then return end
local AddonName, ns = ...
local L = ns.L or {}
local LibBG = ns.LibBG
local RGB = ns.RGB or function(hex, a)
    local r = tonumber(strsub(hex, 1, 2), 16) / 255
    local g = tonumber(strsub(hex, 3, 4), 16) / 255
    local b = tonumber(strsub(hex, 5, 6), 16) / 255
    return r, g, b, a or 1
end
local AddTexture = ns.AddTexture or function(tex, sz)
    sz = sz or 16
    return string.format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t ", tostring(tex), sz, sz)
end
local GetItemID = ns.GetItemID or function(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function GetMaxb(FB)
    return (BG.Maxb and BG.Maxb[FB]) or (ns.Maxb and ns.Maxb[FB]) or 0
end

BG.History = BG.History or {}

-- 单副本最大历史记录保留上限（FIFO 先进先出）
local MAX_HISTORY_PER_FB = 10

-------------------------------------------------------------------------------
-- 1. 数据库安全初始化与合规性匿名化数据清洗
-------------------------------------------------------------------------------
local function EnforceHistoryLimit(FB)
    if not (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB]) then return end
    while #BiaoGe.HistoryList[FB] > MAX_HISTORY_PER_FB do
        local removed = table.remove(BiaoGe.HistoryList[FB])
        if removed and removed[1] and BiaoGe.History and BiaoGe.History[FB] then
            BiaoGe.History[FB][removed[1]] = nil
        end
    end
end

local function InitHistoryDB()
    if not BiaoGe then BiaoGe = {} end
    if not BiaoGe.HistoryList then BiaoGe.HistoryList = {} end
    if not BiaoGe.History then BiaoGe.History = {} end

    if BG.FBtable then
        for _, FB in ipairs(BG.FBtable) do
            if not BiaoGe.HistoryList[FB] then BiaoGe.HistoryList[FB] = {} end
            if not BiaoGe.History[FB] then BiaoGe.History[FB] = {} end

            -- 1. 严格锁死每个副本 10 份上限
            EnforceHistoryLimit(FB)

            -- 2. 合规性清洗：自动剥离存量历史记录中可能存在的角色名、名单及聊天日志（保留合法的物品、收支与团队关键信息）
            for dt, record in pairs(BiaoGe.History[FB]) do
                if type(record) == "table" then
                    record.raidRoster = nil
                    record.auctionLog = nil
                    record.leaderInfo = nil
                    record.tradeTbl = nil
                    for b = 1, 35 do
                        local bTbl = record["boss" .. b]
                        if type(bTbl) == "table" then
                            for i = 1, 35 do
                                bTbl["maijia" .. i] = nil
                                bTbl["color" .. i] = nil
                                bTbl["class" .. i] = nil
                                bTbl["level" .. i] = nil
                                bTbl["realm" .. i] = nil
                            end
                        end
                    end
                end
            end

            -- 3. 自动清理无任何有效装备与金额的空历史记录
            local emptyDTs = {}
            for dt, record in pairs(BiaoGe.History[FB]) do
                if type(record) == "table" then
                    local hasItem = false
                    for b = 1, 35 do
                        local bTbl = record["boss" .. b]
                        if type(bTbl) == "table" then
                            for i = 1, 35 do
                                local zb = bTbl["zhuangbei" .. i]
                                if zb and zb ~= "" and not tonumber(zb) then
                                    hasItem = true
                                    break
                                end
                                local je = bTbl["jine" .. i]
                                if je and je ~= "" and tonumber(je) and tonumber(je) > 0 then
                                    hasItem = true
                                    break
                                end
                            end
                        end
                        if hasItem then break end
                    end
                    if not hasItem then
                        emptyDTs[dt] = true
                    end
                end
            end

            for dt in pairs(emptyDTs) do
                BiaoGe.History[FB][dt] = nil
            end

            if BiaoGe.HistoryList[FB] then
                for i = #BiaoGe.HistoryList[FB], 1, -1 do
                    local item = BiaoGe.HistoryList[FB][i]
                    if type(item) == "table" and emptyDTs[item[1]] then
                        table.remove(BiaoGe.HistoryList[FB], i)
                    end
                end
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

-- 更新历史按钮文本（显示当前副本已存数量）
function BG.UpdateHistoryButton()
    InitHistoryDB()
    local FB = BG.FB1 or (BG.FBtable and BG.FBtable[1])
    if not FB then return end
    local count = (BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and #BiaoGe.HistoryList[FB]) or 0
    local text = string.format(L["历史表格（%d个）"] or "历史表格（%d个）", count)

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

-------------------------------------------------------------------------------
-- 检查当前表格是否包含实际有效数据（装备掉落、成交金额或支出金额）
-- 彻底杜绝空表格、全清空状态下误保存空历史记录
-------------------------------------------------------------------------------
local function IsBiaoGeHasContent(FB)
    local FB = FB or BG.FB1
    if not FB or not BiaoGe or not BiaoGe[FB] then return false end
    local maxb = GetMaxb(FB)
    if maxb == 0 then return false end

    -- 1. 检查各 BOSS 格子 (1 到 maxb)：
    for b = 1, maxb do
        local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
        for i = 1, maxRow do
            -- 检查 UI 控件
            if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
                local zb = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                if zb and zb.GetText then
                    local t = zb:GetText()
                    if t and t ~= "" and not tonumber(t) then
                        return true
                    end
                end
                local mj = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                if mj and mj.GetText then
                    local t = mj:GetText()
                    if t and t ~= "" then
                        return true
                    end
                end
                local je = BG.Frame[FB]["boss" .. b]["jine" .. i]
                if je and je.GetText then
                    local t = je:GetText()
                    if t and t ~= "" and tonumber(t) and tonumber(t) > 0 then
                        return true
                    end
                end
            end
            -- 检查底层数据表 BiaoGe[FB]
            if BiaoGe[FB]["boss" .. b] then
                local zb = BiaoGe[FB]["boss" .. b]["zhuangbei" .. i]
                if zb and zb ~= "" and not tonumber(zb) then
                    return true
                end
                local mj = BiaoGe[FB]["boss" .. b]["maijia" .. i]
                if mj and mj ~= "" then
                    return true
                end
                local je = BiaoGe[FB]["boss" .. b]["jine" .. i]
                if je and je ~= "" and tonumber(je) and tonumber(je) > 0 then
                    return true
                end
                local qk = BiaoGe[FB]["boss" .. b]["qiankuan" .. i]
                if qk and qk ~= "" and tonumber(qk) and tonumber(qk) > 0 then
                    return true
                end
            end
        end
    end

    -- 2. 检查支出格子 (b = maxb + 1)：仅当有实际支出金额或买家时才算有内容（忽略清空时保留的纯补贴名称）
    local bZhiChu = maxb + 1
    local maxRowZhiChu = (BG.GetMaxi and BG.GetMaxi(FB, bZhiChu)) or 20
    for i = 1, maxRowZhiChu do
        if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. bZhiChu] then
            local je = BG.Frame[FB]["boss" .. bZhiChu]["jine" .. i]
            if je and je.GetText then
                local t = je:GetText()
                if t and t ~= "" and tonumber(t) and tonumber(t) > 0 then
                    return true
                end
            end
            local mj = BG.Frame[FB]["boss" .. bZhiChu]["maijia" .. i]
            if mj and mj.GetText then
                local t = mj:GetText()
                if t and t ~= "" then
                    return true
                end
            end
        end
        if BiaoGe[FB]["boss" .. bZhiChu] then
            local je = BiaoGe[FB]["boss" .. bZhiChu]["jine" .. i]
            if je and je ~= "" and tonumber(je) and tonumber(je) > 0 then
                return true
            end
            local mj = BiaoGe[FB]["boss" .. bZhiChu]["maijia" .. i]
            if mj and mj ~= "" then
                return true
            end
        end
    end

    -- 3. 检查总览金额 (b = maxb + 2)：总收入是否大于 0
    if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] then
        local jine1 = BG.Frame[FB]["boss" .. maxb + 2]["jine1"] -- 总收入
        if jine1 and jine1.GetText then
            local t = jine1:GetText()
            if t and t ~= "" and tonumber(t) and tonumber(t) > 0 then
                return true
            end
        end
    end

    return false
end
BG.IsBiaoGeHasContent = IsBiaoGeHasContent

-------------------------------------------------------------------------------
-- 战网小号与角色归属智能推导引擎
-- 彻底根治因 BiaoGe 账号共享数据导致的换号后角色名“张冠李戴”问题
-------------------------------------------------------------------------------
local function CleanPlayerName(name)
    if not name or name == "" then return "" end
    return name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", ""):gsub("%-.+$", "")
end

local function GetAccountCharacters()
    local chars = {}
    ns.KnownCharClasses = ns.KnownCharClasses or {}

    -- 1. 从 BiaoGe.playerInfo 获取本战网所有已知角色及其职业
    if BiaoGe and BiaoGe.playerInfo then
        for rID, rTable in pairs(BiaoGe.playerInfo) do
            if type(rTable) == "table" then
                for pName, pInfo in pairs(rTable) do
                    if type(pInfo) == "table" and pName ~= "" then
                        local cName = CleanPlayerName(pName)
                        local cls = pInfo.class or "WARRIOR"
                        chars[cName] = {
                            class = cls,
                            realmID = rID,
                            level = pInfo.level or 80,
                        }
                        ns.KnownCharClasses[cName] = cls
                    end
                end
            end
        end
    end

    -- 2. 从 BiaoGe.MONEY 获取可能存在的小号 (金币记录表包含了名下全角色)
    if BiaoGe and BiaoGe.MONEY then
        for rID, rTable in pairs(BiaoGe.MONEY) do
            if type(rTable) == "table" then
                for pName, pInfo in pairs(rTable) do
                    local cName = CleanPlayerName(pName)
                    if not chars[cName] then
                        chars[cName] = {
                            class = (pInfo and pInfo.class) or (ns.KnownCharClasses and ns.KnownCharClasses[cName]) or "WARRIOR",
                            realmID = rID,
                        }
                    end
                end
            end
        end
    end

    -- 3. 从 BiaoGe.RoleOverviewSort 补充可能存在的小号
    if BiaoGe and BiaoGe.RoleOverviewSort then
        for rID, rList in pairs(BiaoGe.RoleOverviewSort) do
            if type(rList) == "table" then
                for _, item in ipairs(rList) do
                    if type(item) == "table" and item.player and item.player ~= "" then
                        local cName = CleanPlayerName(item.player)
                        if not chars[cName] then
                            local cls = item.class or "WARRIOR"
                            chars[cName] = {
                                class = cls,
                                realmID = rID,
                            }
                            ns.KnownCharClasses[cName] = cls
                        end
                    end
                end
            end
        end
    end

    -- 4. 当前登录角色兜底
    local myName = UnitName("player")
    local myClass = select(2, UnitClass("player")) or "WARRIOR"
    if myName and myName ~= "" then
        local cName = CleanPlayerName(myName)
        chars[cName] = {
            class = myClass,
            realmID = (GetRealmID and GetRealmID()) or 0,
        }
        ns.KnownCharClasses[cName] = myClass
    end
    return chars
end
ns.GetAccountCharacters = GetAccountCharacters

local function DeduceTableOwner(FB, bTblOrFB)
    local accountChars = GetAccountCharacters()
    local tbl = (bTblOrFB and type(bTblOrFB) == "table") and bTblOrFB or (BiaoGe and BiaoGe[FB])
    local myName = UnitName("player") or "未知角色"
    local myClass = select(2, UnitClass("player")) or "WARRIOR"
    if not tbl then return myName, myClass end

    local candidateScores = {}
    local candidateClasses = {}

    local function AddScore(name, pts, cls)
        if not name or name == "" then return end
        local cName = CleanPlayerName(name)
        if accountChars[cName] then
            candidateScores[cName] = (candidateScores[cName] or 0) + pts
            if cls and cls ~= "" then
                candidateClasses[cName] = cls
                if ns.KnownCharClasses then ns.KnownCharClasses[cName] = cls end
            end
        end
    end

    local function ResolveCharClass(name, fallbackClass)
        if not name or name == "" then return fallbackClass or "WARRIOR" end
        local cName = CleanPlayerName(name)
        if cName == CleanPlayerName(myName) then return myClass end
        if candidateClasses[cName] and candidateClasses[cName] ~= "" then return candidateClasses[cName] end
        if ns.KnownCharClasses and ns.KnownCharClasses[cName] and ns.KnownCharClasses[cName] ~= "" then return ns.KnownCharClasses[cName] end
        if accountChars[cName] and accountChars[cName].class and accountChars[cName].class ~= "" then return accountChars[cName].class end
        if BiaoGe and BiaoGe.playerInfo then
            for _, rTable in pairs(BiaoGe.playerInfo) do
                if type(rTable) == "table" and rTable[cName] and rTable[cName].class then
                    return rTable[cName].class
                end
            end
        end
        return fallbackClass or "WARRIOR"
    end

    local raidTs = tonumber(tbl.raidTime) or (GetServerTime and GetServerTime()) or time()

    -- 1. 优先校验权威官方团队成员名单 (raidRoster)
    -- 原版 BiaoGe 在每次 Boss 掉落时由 Loot.lua 自动记录 25/10 人全团成员名单
    -- 若某个战网小号赫然在列，说明该号 100% 亲身出勤了该团本！赋予最高置信度 100 分
    if tbl.raidRoster and type(tbl.raidRoster) == "table" and tbl.raidRoster.roster then
        local rrTime = tonumber(tbl.raidRoster.time)
        if not (rrTime and raidTs and math.abs(rrTime - raidTs) > 86400) then
            for _, rName in ipairs(tbl.raidRoster.roster) do
                local cName = CleanPlayerName(rName)
                if accountChars[cName] then
                    AddScore(cName, 100)
                end
            end
        end
    end

    -- 2. 扫描团队关键信息入队欢迎语 (teamInfo)
    -- 如："欢迎 虚空水晶/暗夜卡莎 加入团队" 赋予 40 分（每号限计一次）
    local seenRecruitPlayer = {}
    if tbl.teamInfo and tbl.teamInfo.recruits and type(tbl.teamInfo.recruits) == "table" then
        for _, rec in ipairs(tbl.teamInfo.recruits) do
            local text = rec.text or ""
            for accName in pairs(accountChars) do
                if not seenRecruitPlayer[accName] and text:find(accName, 1, true) then
                    seenRecruitPlayer[accName] = true
                    AddScore(accName, 40)
                end
            end
        end
    end
    if tbl.teamInfo and tbl.teamInfo.members then
        for mName in pairs(tbl.teamInfo.members) do
            local cM = CleanPlayerName(mName)
            if accountChars[cM] and not seenRecruitPlayer[cM] then
                seenRecruitPlayer[cM] = true
                AddScore(cM, 30)
            end
        end
    end

    local maxb = (BG.GetMaxb and BG.GetMaxb(FB)) or 25

    -- 3. 深度财务与交易加权打分 (Boss买家、补贴名单、交易记录)
    -- 真金白银购买装备、领取补贴或发生金币交易：每个买家格子 +50 分，同时捕获职业
    for b = 1, maxb + 2 do
        local bossTbl = tbl["boss" .. b]
        if type(bossTbl) == "table" then
            for i = 1, 30 do
                local buyer = bossTbl["maijia" .. i]
                local bClass = bossTbl["class" .. i]
                if buyer and buyer ~= "" then
                    local cBuyer = CleanPlayerName(buyer)
                    if accountChars[cBuyer] then
                        AddScore(cBuyer, 50, bClass)
                    end
                end
            end
        end
    end

    -- 4. 扫描副本内部交易记录表 (tradeTbl)
    -- 交易记录中买家/卖家/maijia +50 分，同时精确捕获交易职业（每号限计一次）
    local seenTradePlayer = {}
    if tbl.tradeTbl and type(tbl.tradeTbl) == "table" then
        for _, tr in ipairs(tbl.tradeTbl) do
            local p = tr.maijia or tr.buyer or tr.seller or tr.player
            if p and p ~= "" then
                local cP = CleanPlayerName(p)
                if accountChars[cP] and not seenTradePlayer[cP] then
                    seenTradePlayer[cP] = true
                    AddScore(cP, 50, tr.class)
                end
            end
        end
    end

    -- 5. 如果当前登录角色正好身处该副本内打本，当前角色具有高置信度 (+80分)
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "raid" or instanceType == "party") then
        local curFBID = select(8, GetInstanceInfo())
        if BG and BG.FBIDtable and BG.FBIDtable[curFBID] == FB then
            AddScore(myName, 80, myClass)
        end
    end

    -- 6. 扫描掉落拾取日志 (lootHistory) - 仅限本场24小时窗口内，严格过滤5人本地下城噪音（每号限计一次 +15分）
    local seenLootPlayer = {}
    if tbl.lootHistory and type(tbl.lootHistory) == "table" and #tbl.lootHistory > 0 then
        for _, item in ipairs(tbl.lootHistory) do
            if item.player and item.source then
                local itemTs = tonumber(item.timestamp)
                if not (itemTs and raidTs and math.abs(itemTs - raidTs) > 86400) then
                    local s = tostring(item.source)
                    if not (s:find("熔炉") or s:find("围栏") or s:find("地牢") or s:find("监狱") or s:find("迷宫") or s:find("破碎") or s:find("城墙") or s:find("沼泽") or s:find("幽暗") or s:find("平台")) then
                        local cP = CleanPlayerName(item.player)
                        if accountChars[cP] and not seenLootPlayer[cP] then
                            seenLootPlayer[cP] = true
                            AddScore(cP, 15, item.class or ResolveCharClass(cP))
                        end
                    end
                end
            end
        end
    end

    -- 7. 表格原有 charName / player 作为历史先验弱参考 (+5 分，绝不独裁霸凌强证据)
    if tbl.charName and tbl.charName ~= "" then
        local cName = CleanPlayerName(tbl.charName)
        if accountChars[cName] then
            AddScore(cName, 5, tbl.class)
        end
    end
    if tbl.player and tbl.player ~= "" then
        local cName = CleanPlayerName(tbl.player)
        if accountChars[cName] then
            AddScore(cName, 5, tbl.class)
        end
    end

    -- 8. 选出客观证据总分最高的真实战网角色
    local bestChar, bestScore = nil, 0
    for cName, score in pairs(candidateScores) do
        if score > bestScore then
            bestScore = score
            bestChar = cName
        end
    end

    if bestChar and bestScore > 0 then
        local cClass = ResolveCharClass(bestChar)
        -- 核心自愈：若发现表格此前被旧会话错误固化了其他小号名字，以压倒性证据自动纠偏并固化
        if tbl.charName ~= bestChar then
            tbl.charName = bestChar
            tbl.class = cClass
        end
        return bestChar, cClass
    end

    -- 9. 最终兜底：无任何证据（空表格或无关联）时，若身处副本则采用当前角色；否则仅只读返回当前登录号，绝不反写污染表格
    return myName, myClass
end
ns.DeduceTableOwner = DeduceTableOwner

-------------------------------------------------------------------------------
-- 获取账单真实发生打本时间 (True Raid Time)
-- 优先采纳官方标准打本开始时间 raidTime；若缺失则扫描拍卖日志、Boss 掉落与交易，杜绝被5人本杂项时间篡改
-------------------------------------------------------------------------------
local function GetTrueRaidTime(FB)
    if not (FB and BiaoGe and BiaoGe[FB]) then return nil end
    local now = (GetServerTime and GetServerTime()) or time()
    local curWeekStart = (WR and WR.GetCDWeekStart and WR.GetCDWeekStart(now))
        or (ns.WorkerReport and ns.WorkerReport.GetCDWeekStart and ns.WorkerReport.GetCDWeekStart(now))
        or (now - 7 * 86400)

    local candidates = {}
    local thisWeekCandidates = {}

    -- 1. 深度扫描该副本的拍卖日志 (BiaoGe[FB].auctionLog)
    if BiaoGe[FB].auctionLog and type(BiaoGe[FB].auctionLog) == "table" then
        for _, entry in ipairs(BiaoGe[FB].auctionLog) do
            local ts = tonumber(entry.time) or tonumber(entry.timestamp)
            if ts and ts > 1000000000 and ts <= (now + 300) then
                table.insert(candidates, ts)
                if ts >= curWeekStart then
                    table.insert(thisWeekCandidates, ts)
                end
            end
        end
    end

    -- 2. 深度扫描掉落拾取日志 (BiaoGe[FB].lootHistory)
    if BiaoGe[FB].lootHistory and type(BiaoGe[FB].lootHistory) == "table" then
        for _, entry in ipairs(BiaoGe[FB].lootHistory) do
            local ts = tonumber(entry.timestamp) or tonumber(entry.time)
            if ts and ts > 1000000000 and ts <= (now + 300) then
                table.insert(candidates, ts)
                if ts >= curWeekStart then
                    table.insert(thisWeekCandidates, ts)
                end
            end
        end
    end

    -- 3. 扫描团队信息通告 (BiaoGe[FB].teamInfo.recruits)
    if BiaoGe[FB].teamInfo and BiaoGe[FB].teamInfo.recruits and type(BiaoGe[FB].teamInfo.recruits) == "table" then
        for _, entry in ipairs(BiaoGe[FB].teamInfo.recruits) do
            local ts = tonumber(entry.timestamp) or tonumber(entry.time)
            if ts and ts > 1000000000 and ts <= (now + 300) then
                table.insert(candidates, ts)
                if ts >= curWeekStart then
                    table.insert(thisWeekCandidates, ts)
                end
            end
        end
    end

    -- 4. 扫描 Boss 子表中的任意可能时间戳
    local maxb = (BG.GetMaxb and BG.GetMaxb(FB)) or 25
    for b = 1, maxb do
        local bTbl = BiaoGe[FB]["boss" .. b]
        if type(bTbl) == "table" then
            for k, v in pairs(bTbl) do
                if type(v) == "table" then
                    local ts = tonumber(v.timestamp) or tonumber(v.time)
                    if ts and ts > 1000000000 and ts <= (now + 300) then
                        table.insert(candidates, ts)
                        if ts >= curWeekStart then
                            table.insert(thisWeekCandidates, ts)
                        end
                    end
                end
            end
        end
    end

    -- 5. 内部交易表时间戳
    if BiaoGe[FB].tradeTbl and type(BiaoGe[FB].tradeTbl) == "table" then
        for _, tr in ipairs(BiaoGe[FB].tradeTbl) do
            local ts = tonumber(tr.time) or tonumber(tr.timestamp)
            if ts and ts > 1000000000 and ts <= (now + 300) then
                table.insert(candidates, ts)
                if ts >= curWeekStart then
                    table.insert(thisWeekCandidates, ts)
                end
            end
        end
    end

    -- 6. 核心智能仲裁：
    -- A. 若本周内有确切打本证据（本周的拍卖/掉落/通告）：
    if #thisWeekCandidates > 0 then
        table.sort(thisWeekCandidates)
        local bestTs = thisWeekCandidates[1] -- 取本周最早一次打本操作时间
        -- 核心自愈：若 BiaoGe[FB].raidTime 仍停留在此前旧周，立即纠正固化为本周真实打本时间
        if not BiaoGe[FB].raidTime or BiaoGe[FB].raidTime < curWeekStart then
            BiaoGe[FB].raidTime = bestTs
            BiaoGe[FB].lastRaidTime = bestTs
        end
        return bestTs
    end

    -- B. 核心自愈与防误篡改：若本周无任何客观打本证据，但扫描到了明确的客观历史打本证据
    if #thisWeekCandidates == 0 and #candidates > 0 then
        table.sort(candidates)
        local bestOldTs = candidates[#candidates] -- 取历史打本最后记录的客观时刻
        local rt = tonumber(BiaoGe[FB].raidTime)
        -- 若 raidTime 却异常大于等于当前周开始时间（即被系统误赋予或重载误篡改），坚决纠正还原为历史真实打本时刻！
        if rt and rt >= curWeekStart then
            BiaoGe[FB].raidTime = bestOldTs
            BiaoGe[FB].lastRaidTime = bestOldTs
        end
        return bestOldTs
    end

    -- C. 显式记录的 raidTime（仅当没有本周新证据冲突且无历史证据反证时采纳）
    local rt = tonumber(BiaoGe[FB].raidTime)
    if rt and rt > 1000000000 and rt <= (now + 300) then
        return rt
    end

    -- D. 兜底检查 lastRaidTime 或 raidRoster.time
    if BiaoGe[FB].raidRoster and tonumber(BiaoGe[FB].raidRoster.time) and tonumber(BiaoGe[FB].raidRoster.time) > 1000000000 and tonumber(BiaoGe[FB].raidRoster.time) <= (now + 300) then
        return tonumber(BiaoGe[FB].raidRoster.time)
    end
    local lrt = tonumber(BiaoGe[FB].lastRaidTime)
    if lrt and lrt > 1000000000 and lrt <= (now + 300) then
        return lrt
    end

    -- E. 若所有证据都属于旧历史：取最后候选时间
    if #candidates > 0 then
        table.sort(candidates)
        return candidates[#candidates]
    end

    return nil
end
ns.GetTrueRaidTime = GetTrueRaidTime

-------------------------------------------------------------------------------
-- 2. 核心：保存当前表格为历史表格（彻底去角色名 + 10份FIFO上限）
-------------------------------------------------------------------------------
function BG.SaveBiaoGe(FB, isSilent)
    local FB = FB or BG.FB1
    if not FB or not BiaoGe or not BiaoGe[FB] then return false end
    InitHistoryDB()

    local maxb = GetMaxb(FB)
    if maxb == 0 then return false end

    -- 空表格严格拦截：没有任何有效掉落装备或金额时不予保存
    if not IsBiaoGeHasContent(FB) then
        if not isSilent then
            local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["<%s> 当前表格没有任何装备或金额记录，无法保存。"] or "<%s> 当前表格没有任何装备或金额记录，无法保存。", fbShort))
            if BG.PlaySound then BG.PlaySound(1) end
        end
        return false
    end

    local serverTime = GetServerTime()
    local trueRaidTime = GetTrueRaidTime(FB) or serverTime
    local recordTime = trueRaidTime or serverTime
    local DT = tonumber(date("%y%m%d%H%M%S", recordTime))
    if BiaoGe.History[FB][DT] then
        recordTime = recordTime + 1
        DT = tonumber(date("%y%m%d%H%M%S", recordTime))
    end
    local DTcn = date(L["%m月%d日%H:%M:%S\n"] or "%m月%d日%H:%M:%S\n", recordTime)

    local record = {}

    -- 仅保存装备与金额，彻底去除角色名称与敏感属性
    for b = 1, maxb + 2 do
        record["boss" .. b] = {}
        for i = 1, BG.GetMaxi(FB, b) do
            if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
                local zhuangbei = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                if zhuangbei and zhuangbei:GetText() ~= "" then
                    record["boss" .. b]["zhuangbei" .. i] = zhuangbei:GetText()
                    if BiaoGe[FB]["boss" .. b] then
                        record["boss" .. b]["itemLevel" .. i] = BiaoGe[FB]["boss" .. b]["itemLevel" .. i]
                        record["boss" .. b]["bindOnEquip" .. i] = BiaoGe[FB]["boss" .. b]["bindOnEquip" .. i]
                    end
                end

                -- 买家姓名 (maijia) 及相关属性 (color, class, level, realm) 绝对不存入

                local jine = BG.Frame[FB]["boss" .. b]["jine" .. i]
                if jine and jine:GetText() ~= "" then
                    record["boss" .. b]["jine" .. i] = jine:GetText()
                end

                if BiaoGe[FB]["boss" .. b] then
                    if BiaoGe[FB]["boss" .. b]["guanzhu" .. i] then
                        record["boss" .. b]["guanzhu" .. i] = true
                    end
                    if BiaoGe[FB]["boss" .. b]["qiankuan" .. i] then
                        record["boss" .. b]["qiankuan" .. i] = BiaoGe[FB]["boss" .. b]["qiankuan" .. i]
                    end
                end
            end
        end
    end

    -- 在保存历史前，智能推导出打本角色（即使换号后保存也准确归入原打本角色名下）
    local ownerName, ownerClass = DeduceTableOwner(FB)
    local myName = ownerName or UnitName("player")
    local mySpend = 0
    local mySpends = {}
    local subsidy = 0
    local penalty = 0

    -- 检查本人消费 (1 到 maxb)
    for b = 1, maxb do
        local maxRow = BG.GetMaxi(FB, b)
        for i = 1, maxRow do
            local mj = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["maijia" .. i])
            local je = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["jine" .. i])
            local zb = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i])
            local buyerName = (mj and mj.GetText and mj:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["maijia" .. i])
            local money = tonumber(je and je.GetText and je:GetText()) or tonumber(BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["jine" .. i]) or 0
            local itemText = (zb and zb.GetText and zb:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["zhuangbei" .. i]) or ""

            if buyerName and CleanPlayerName(buyerName) == CleanPlayerName(myName) and money > 0 then
                if itemText == (L["罚款"] or "罚款") or itemText:find(L["罚款"] or "罚款") then
                    penalty = penalty + money
                else
                    mySpend = mySpend + money
                    table.insert(mySpends, { item = itemText, money = money, boss = b })
                end
            end
        end
    end

    -- 检查本人获得的补贴 (支出格 maxb + 1)
    local bZhiChu = maxb + 1
    local maxRowZhiChu = BG.GetMaxi(FB, bZhiChu)
    for i = 1, maxRowZhiChu do
        local mj = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. bZhiChu] and BG.Frame[FB]["boss" .. bZhiChu]["maijia" .. i])
        local je = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. bZhiChu] and BG.Frame[FB]["boss" .. bZhiChu]["jine" .. i])
        local buyerName = (mj and mj.GetText and mj:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. bZhiChu] and BiaoGe[FB]["boss" .. bZhiChu]["maijia" .. i])
        local money = tonumber(je and je.GetText and je:GetText()) or tonumber(BiaoGe[FB] and BiaoGe[FB]["boss" .. bZhiChu] and BiaoGe[FB]["boss" .. bZhiChu]["jine" .. i]) or 0
        if buyerName and CleanPlayerName(buyerName) == CleanPlayerName(myName) and money > 0 then
            subsidy = subsidy + money
        end
    end

    local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
    local totalPeople = tonumber((BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine4"] and BG.Frame[FB]["boss" .. maxb + 2]["jine4"]:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. maxb + 2] and BiaoGe[FB]["boss" .. maxb + 2]["jine4"])) or 0
    local wageNum = tonumber((BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine5"] and BG.Frame[FB]["boss" .. maxb + 2]["jine5"]:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. maxb + 2] and BiaoGe[FB]["boss" .. maxb + 2]["jine5"])) or 0
    local grossMoney = tonumber((BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine1"] and BG.Frame[FB]["boss" .. maxb + 2]["jine1"]:GetText()) or (BiaoGe[FB] and BiaoGe[FB]["boss" .. maxb + 2] and BiaoGe[FB]["boss" .. maxb + 2]["jine1"])) or 0

    -- 存储本场数据并记录打工角色信息、收支明细与真实打本时间
    record.charName = ownerName or UnitName("player")
    record.class = ownerClass or select(2, UnitClass("player")) or "WARRIOR"
    record.realm = GetRealmName()
    record.raidTime = recordTime
    record.totalPeople = totalPeople
    record.wage = wageNum
    record.grossMoney = grossMoney
    record.mySpend = mySpend
    record.mySpends = mySpends
    record.subsidy = subsidy
    record.penalty = penalty
    record.netWage = wageNum + subsidy - penalty - mySpend

    -- 核心：联合存储 TeamInfo（YY号、团长、招募通告等）
    local teamData = nil
    if BiaoGe[FB] and BiaoGe[FB].teamInfo and (
        (BiaoGe[FB].teamInfo.yy and BiaoGe[FB].teamInfo.yy ~= "") or
        (BiaoGe[FB].teamInfo.leader and BiaoGe[FB].teamInfo.leader ~= "") or
        (BiaoGe[FB].teamInfo.recruits and #BiaoGe[FB].teamInfo.recruits > 0)
    ) then
        teamData = BiaoGe[FB].teamInfo
    elseif ns.TeamInfo and ns.TeamInfo.stagingData and (
        (ns.TeamInfo.stagingData.yy and ns.TeamInfo.stagingData.yy ~= "") or
        (ns.TeamInfo.stagingData.leader and ns.TeamInfo.stagingData.leader ~= "") or
        (ns.TeamInfo.stagingData.recruits and #ns.TeamInfo.stagingData.recruits > 0)
    ) then
        teamData = ns.TeamInfo.stagingData
    end

    if teamData then
        record.teamInfo = BG.Copy and BG.Copy(teamData) or {
            yy = teamData.yy or "",
            leader = teamData.leader or "",
            recruits = (BG.Copy and BG.Copy(teamData.recruits)) or {},
            bindTime = teamData.bindTime or serverTime,
        }
    end

    BiaoGe.History[FB][DT] = record

    local titleSummary = string.format("%s %s人 工资:%s", fbShort, totalPeople, wageNum)
    local d = { DT, titleSummary, date("%m/%d", recordTime), date("%H:%M:%S", recordTime) }

    table.insert(BiaoGe.HistoryList[FB], 1, d)

    -- 严格执行单个副本最多 10 份限制，自动物理淘汰最旧的存档
    EnforceHistoryLimit(FB)

    -- 自动通知看板数据变动
    if wageNum > 0 and ns.WorkerReport and ns.WorkerReport.AddRecordFromHistory then
        ns.WorkerReport.AddRecordFromHistory(FB, recordTime, totalPeople, wageNum, grossMoney, mySpend, subsidy)
    end

    BG.UpdateHistoryButton()
    if BG.CreatHistoryListButton then
        BG.CreatHistoryListButton(FB)
    end

    if not isSilent then
        local sTime = serverTime
        local link = "|cff00FF00|Hgarrmission:BiaoGe:" .. (L["撤回清空"] or "撤回清空") .. ":" .. FB .. ":" .. sTime .. "|h[" .. (L["撤回清空"] or "撤回清空") .. "]|h|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已将当前表格保存至 <%s> 历史表格1，并已自动清空当前表格。"] or "已将当前表格保存至 <%s> 历史表格1，并已自动清空当前表格。", fbShort) .. " " .. link)
    end
    return true
end

-------------------------------------------------------------------------------
-- 3. 核心：应用历史表格到当前活跃表格
-------------------------------------------------------------------------------
function BG.SetBiaoGeFormHistory(FB, num)
    local FB = FB or BG.FB1
    num = num or (BG.History and BG.History.chooseNum) or 1
    if not (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and BiaoGe.HistoryList[FB][num]) then return end

    local DT = BiaoGe.HistoryList[FB][num][1]
    local histData = BiaoGe.History and BiaoGe.History[FB] and BiaoGe.History[FB][DT]
    if not histData then return end

    -- 清空当前活跃表格内容（置位保护，避免应用时重复触发自动归档）
    if BG.ClearBiaoGe then
        BG._isApplyingHistory = true
        BG.ClearBiaoGe("biaoge", FB)
        BG._isApplyingHistory = nil
    end

    local maxBoss = GetMaxb(FB)
    if maxBoss == 0 then return end

    for b = 1, maxBoss + 2 do
        if histData["boss" .. b] then
            local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b, true)) or 5
            if b == maxBoss + 2 then maxRow = 5 end

            for i = 1, maxRow do
                local zbVal = histData["boss" .. b]["zhuangbei" .. i]
                local jeVal = histData["boss" .. b]["jine" .. i]

                if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
                    if zbVal then
                        BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]:SetText(zbVal)
                    end
                    -- 买家留空，玩家可按需填入
                    BG.Frame[FB]["boss" .. b]["maijia" .. i]:SetText("")
                    if jeVal then
                        BG.Frame[FB]["boss" .. b]["jine" .. i]:SetText(jeVal)
                    end
                end

                if BiaoGe[FB] and BiaoGe[FB]["boss" .. b] then
                    BiaoGe[FB]["boss" .. b]["zhuangbei" .. i] = zbVal
                    BiaoGe[FB]["boss" .. b]["maijia" .. i] = nil
                    BiaoGe[FB]["boss" .. b]["jine" .. i] = jeVal
                    BiaoGe[FB]["boss" .. b]["itemLevel" .. i] = histData["boss" .. b]["itemLevel" .. i]
                    BiaoGe[FB]["boss" .. b]["bindOnEquip" .. i] = histData["boss" .. b]["bindOnEquip" .. i]

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
                end
            end
        end
    end

    -- 核心：还原 TeamInfo
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
    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已成功将历史表格应用并恢复至 <%s> 表格！"] or "已成功将历史表格应用并恢复至 <%s> 表格！", fbShort))
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

-------------------------------------------------------------------------------
-- 5. 历史表格 UI 界面构建
-------------------------------------------------------------------------------
local function CreateHistoryUI()
    if BG.History.hasCreatedUI then return end
    BG.History.hasCreatedUI = true
    InitHistoryDB()

    -- A. 历史表格查看主窗口
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
            if ns.TeamInfo and ns.TeamInfo.sideFrame then
                ns.TeamInfo.sideFrame:Show()
            end
            if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end
        end)

        BG.HistoryMainFrame:SetScript("OnHide", function(self)
            if BG.History then
                BG.History.chooseNum = nil
            end
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
        end)
    end

    -- B. 顶部操作栏
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
    saveBtn:SetText(L["保存"] or "保存")
    if saveBtn:GetFontString() then
        saveBtn:SetSize(saveBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(saveBtn) end
    BG.History.SaveButton = saveBtn

    saveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["保存表格"] or "保存表格", 1, 1, 1, true)
        GameTooltip:AddLine(L["把当前表格保存至历史表格并清空当前表格（仅保存装备与金额，最多保留10场）。"] or "把当前表格保存至历史表格并清空当前表格（仅保存装备与金额，最多保留10场）。", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    saveBtn:SetScript("OnClick", function(self)
        if BG.FrameHide then BG.FrameHide(2) end
        self:SetEnabled(false)
        C_Timer.After(0.5, function() saveBtn:SetEnabled(true) end)
        local FB = BG.FB1
        local ok = BG.SaveBiaoGe(FB)
        if ok then
            -- 保存成功后调用清空当前表格
            if BG.ClearBiaoGe and FB then
                BG._isSavingHistoryClear = true
                BG.ClearBiaoGe("biaoge", FB)
                BG._isSavingHistoryClear = nil
            end
            -- 同步清空当前活跃视图下的右侧团队信息留存
            if ns.TeamInfo and ns.TeamInfo.ClearOnSaveHistory then
                ns.TeamInfo.ClearOnSaveHistory(FB)
            elseif ns.TeamInfo and ns.TeamInfo.ClearFBBinding then
                ns.TeamInfo.ClearFBBinding(FB)
            end
            if BG.PlaySound then
                BG.PlaySound(2)
            end
        end
    end)

    -- C. 历史表格下拉菜单
    local listFrame = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
    listFrame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listFrame:SetBackdropColor(0, 0, 0, 0.9)
    listFrame:SetSize(280, 380)
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

    -- 标题与说明
    local TitleText = BG.HistoryMainFrame:CreateFontString()
    TitleText:SetPoint("TOP", BG.MainFrame, "TOP", 0, -4)
    TitleText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    TitleText:SetTextColor(RGB("00FF00"))
    BG.History.Title = TitleText

    local tipText = listFrame:CreateFontString()
    tipText:SetPoint("TOP", listFrame, "BOTTOM", 0, 0)
    tipText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tipText:SetText(BG.STC_w1 and BG.STC_w1(string.format(L["（ALT+%s改名，ALT+%s删除表格，单本上限10份）"] or "（ALT+%s改名，ALT+%s删除表格，单本上限10份）", AddTexture("LEFT"), AddTexture("RIGHT"))) or "（ALT+左键改名，ALT+右键删除，单本上限10份）")

    -- 清空历史弹窗辅助函数
    local function PromptClearAllHistory(FB)
        local FB = FB or BG.FB1
        local count = (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and #BiaoGe.HistoryList[FB]) or 0
        local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
        if count == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["<%s> 暂无任何历史表格。"] or "<%s> 暂无任何历史表格。", fbShort))
            if BG.PlaySound then BG.PlaySound(1) end
            return
        end

        StaticPopupDialogs["BGLITE_PLUS_CLEAR_ALL_HISTORY"] = {
            text = string.format(L["确定清空<%s>的所有历史表格？"] or "确定清空<%s>的所有历史表格？", fbShort),
            button1 = L["是"] or "是",
            button2 = L["否"] or "否",
            OnAccept = function()
                if BiaoGe and BiaoGe.History and BiaoGe.History[FB] then wipe(BiaoGe.History[FB]) end
                if BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] then wipe(BiaoGe.HistoryList[FB]) end
                if BG.EscHistoryFrame then BG.EscHistoryFrame() end
                BG.UpdateHistoryButton()
                if BG.CreatHistoryListButton then BG.CreatHistoryListButton(FB) end
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已成功清空<%s>的所有历史表格。"] or "已成功清空<%s>的所有历史表格。", fbShort))
                if BG.PlaySound then BG.PlaySound(1) end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            showAlert = true,
        }
        StaticPopup_Show("BGLITE_PLUS_CLEAR_ALL_HISTORY")
    end

    -- 清空历史按钮
    local clearHistBtn = BG.CreateButton and BG.CreateButton(listFrame) or CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
    clearHistBtn:SetSize(110, 25)
    clearHistBtn:SetPoint("TOP", listFrame, "BOTTOM", 0, -20)
    clearHistBtn:SetText(L["清空历史表格"] or "清空历史表格")
    clearHistBtn:SetScript("OnClick", function()
        PromptClearAllHistory(BG.FB1)
    end)

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
        elseif button == "RightButton" then
            PromptClearAllHistory(BG.FB1)
        end
    end)
    histBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        GameTooltip:AddLine(AddTexture("LEFT") .. (L["打开历史表格"] or "打开历史表格"), 1, 0.82, 0, true)
        GameTooltip:AddLine(AddTexture("RIGHT") .. (L["删除历史表格"] or "删除历史表格"), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    histBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- D. 历史查看模式下的【返回】与【应用】
    local escBtn = CreateFrame("Button", nil, BG.HistoryMainFrame)
    escBtn:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -30, -1)
    escBtn:SetNormalFontObject(BG.FontFen15 or GameFontNormalLarge)
    escBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    escBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    escBtn:SetText(L["返回"] or "返回")
    if escBtn:GetFontString() then
        escBtn:SetSize(escBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(escBtn) end
    BG.History.EscButton = escBtn

    local yongBtn = CreateFrame("Button", nil, BG.HistoryMainFrame)
    yongBtn:SetPoint("TOPRIGHT", escBtn, "TOPLEFT", -10, 0)
    yongBtn:SetNormalFontObject(BG.FontGreen15 or GameFontNormalLarge)
    yongBtn:SetDisabledFontObject(BG.FontDis15 or GameFontDisableLarge)
    yongBtn:SetHighlightFontObject(BG.FontWhite15 or GameFontHighlightLarge)
    yongBtn:SetText(L["应用"] or "应用")
    if yongBtn:GetFontString() then
        yongBtn:SetSize(yongBtn:GetFontString():GetWidth() + 10, 20)
    end
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(yongBtn) end
    BG.History.YongButton = yongBtn

    yongBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["应用表格"] or "应用表格", 1, 1, 1, true)
        GameTooltip:AddLine(L["把该历史表格的掉落与金额覆盖还原到当前表格。"] or "把该历史表格的掉落与金额覆盖还原到当前表格。", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    yongBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yongBtn:SetScript("OnClick", function()
        StaticPopupDialogs["BGLITE_PLUS_APPLY_HISTORY"] = {
            text = (L["确定应用表格？\n你当前的表格数据将被"] or "确定应用表格？\n你当前的表格数据将被") .. (BG.STC_r1 and BG.STC_r1(L[" 替换 "] or " 替换 ") or " 替换 "),
            button1 = L["是"] or "是",
            button2 = L["否"] or "否",
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

    -- [切换历史] 按钮
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
        elseif button == "RightButton" then
            PromptClearAllHistory(BG.FB1)
        end
    end)
    histModeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", self, "BOTTOMLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
        GameTooltip:AddLine(AddTexture("LEFT") .. (L["打开历史表格列表"] or "打开历史表格列表"), 1, 0.82, 0, true)
        GameTooltip:AddLine(AddTexture("RIGHT") .. (L["删除历史表格"] or "删除历史表格"), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    histModeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function BG.EscHistoryFrame()
        if BG.FrameHide then BG.FrameHide(0) end
        if BG.HistoryMainFrame then BG.HistoryMainFrame:Hide() end
        if BG.History then BG.History.chooseNum = nil end
        if BG.FBMainFrame then BG.FBMainFrame:Show() end
        if BG.Title then BG.Title:Show() end
        if BG.VerText then BG.VerText:Show() end
        if BG.UpdateAuctionLogFrame then BG.UpdateAuctionLogFrame() end
        if BG.PlaySound then BG.PlaySound(1) end
        BG.UpdateHistoryButton()
        if ns.TeamInfo and ns.TeamInfo.UpdateUI then
            ns.TeamInfo.UpdateUI()
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
    okBtn:SetText(L["确定"] or "确定")
    okBtn:SetScript("OnClick", function()
        local FB = BG.FB1
        local text = renameEdit:GetText()
        if text ~= "" and BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and BG.History.GaiMingNum then
            BiaoGe.HistoryList[FB][BG.History.GaiMingNum][2] = text
            renameFrame:Hide()
            BG.CreatHistoryListButton(FB)
            if BG.PlaySound then BG.PlaySound(1) end
        end
    end)

    local cancelBtn = BG.CreateButton and BG.CreateButton(renameFrame) or CreateFrame("Button", nil, renameFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetPoint("BOTTOMRIGHT", renameFrame, "BOTTOMRIGHT", -15, 15)
    cancelBtn:SetText(L["取消"] or "取消")
    cancelBtn:SetScript("OnClick", function()
        renameFrame:Hide()
        if BG.PlaySound then BG.PlaySound(1) end
    end)

    BG.UpdateHistoryButton()
end

-------------------------------------------------------------------------------
-- 6. 构建历史查看表格中的 Boss 格子
-------------------------------------------------------------------------------
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
        if b == maxBoss + 2 then maxRow = 5 end

        for i = 1, maxRow do
            if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i] then
                local origZB = BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                local origMJ = BG.Frame[FB]["boss" .. b]["maijia" .. i]
                local origJE = BG.Frame[FB]["boss" .. b]["jine" .. i]

                -- 装备框 (只读)
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
                                local jeBox = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["jine" .. i]
                                local nowMoney = jeBox and jeBox:GetText() or ""
                                BG.SetHistoryMoney(itemID, nowMoney)
                            end
                        end
                    end
                end)
                zb:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                    if BG.HideHistoryMoney then BG.HideHistoryMoney() end
                end)
                BG.HistoryFrame[FB]["boss" .. b]["zhuangbei" .. i] = zb

                -- 买家框 (只读，保持留空以保护隐私合规)
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

                -- 欠款与关注图标
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

                if b == maxBoss + 1 then
                    zb:SetTextColor(RGB("00FF00"))
                    je:SetTextColor(RGB("00FF00"))
                    mj:Hide()
                elseif b == maxBoss + 2 then
                    mj:Hide()
                    if i == 1 then
                        zb:SetText(L["总收入"] or "总收入")
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 2 then
                        zb:SetText(L["总支出"] or "总支出")
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 3 then
                        zb:SetText(L["净收入"] or "净收入")
                        zb:SetTextColor(RGB("EE82EE"))
                        je:SetTextColor(RGB("EE82EE"))
                    elseif i == 4 then
                        zb:SetText(L["分钱人数"] or "分钱人数")
                        zb:SetTextColor(RGB("00BFFF"))
                        je:SetTextColor(RGB("00BFFF"))
                    elseif i == 5 then
                        zb:SetText(L["人均工资"] or "人均工资")
                        zb:SetTextColor(RGB("00BFFF"))
                        je:SetTextColor(RGB("00BFFF"))
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- 7. 渲染下拉菜单中的历史条目
-------------------------------------------------------------------------------
function BG.CreatHistoryListButton(FB)
    FB = FB or BG.FB1
    if not (BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB]) then return end

    local k = 1
    while BG.History["ListButton" .. k] do
        BG.History["ListButton" .. k]:Hide()
        BG.History["ListButton" .. k] = nil
        k = k + 1
    end

    local list = BiaoGe.HistoryList[FB]
    local child = BG.History.child
    if not child then return end

    for i = 1, #list do
        local bt = CreateFrame("Button", nil, child, "BackdropTemplate")
        bt:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground" })
        bt:SetBackdropColor(1, 1, 1, 0.1)
        if i == 1 then
            bt:SetPoint("TOPLEFT", child, "TOPLEFT", 10, -10)
        else
            bt:SetPoint("TOPLEFT", BG.History["ListButton" .. (i - 1)], "BOTTOMLEFT", 0, -5)
        end
        bt:SetSize(250, 42)
        bt:SetNormalFontObject(BG.FontBlue13 or GameFontNormal)
        bt:SetDisabledFontObject(BG.FontWhite13 or GameFontDisable)
        bt:SetHighlightFontObject(BG.FontWhite13 or GameFontHighlight)
        bt:SetText(string.format("%d. %s", i, list[i][2]))

        local t = bt:GetFontString()
        if t then
            t:SetWidth(bt:GetWidth() - 10)
            t:SetPoint("LEFT", 6, 0)
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
                    BG.DeleteHistory(FB, i)
                    if BG.History.GaiMingFrame then BG.History.GaiMingFrame:Hide() end
                    if BG.PlaySound then BG.PlaySound(1) end
                    return
                else
                    BG.History.GaiMingNum = i
                    BG.History.GaiMingFrame:Show()
                    BG.History.GaiMingBiaoTi:SetText(string.format(L["你正在改名第 %s 个表格"] or "你正在改名第 %s 个表格", i))
                    BG.History.GaiMingEdit1:SetText(list[i][2])
                    BG.History.GaiMingEdit1:SetFocus()
                    BG.History.GaiMingEdit1:HighlightText()
                    if BG.PlaySound then BG.PlaySound(1) end
                    return
                end
            end

            -- 查看历史账单
            BG.History.chooseNum = i
            if BG.HistoryMainFrame then BG.HistoryMainFrame:Show() end

            for _, fb in ipairs(BG.FBtable or {}) do
                if BG["HistoryFrame" .. fb] then BG["HistoryFrame" .. fb]:Hide() end
            end
            if BG["HistoryFrame" .. FB] then BG["HistoryFrame" .. FB]:Show() end

            -- 展开右侧团队信息面板并加载该历史快照的团队信息
            if ns.TeamInfo and ns.TeamInfo.sideFrame then
                ns.TeamInfo.sideFrame:Show()
            end
            if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                ns.TeamInfo.UpdateUI()
            end

            if BG.History.Title then
                BG.History.Title:SetText((L["<历史表格>"] or "<历史表格>") .. " " .. list[i][2])
            end

            local DT = list[i][1]
            local histData = BiaoGe.History and BiaoGe.History[FB] and BiaoGe.History[FB][DT]
            if histData and BG.HistoryFrame and BG.HistoryFrame[FB] then
                local maxBoss = GetMaxb(FB)
                for b = 1, maxBoss + 2 do
                    local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b, true)) or 5
                    if b == maxBoss + 2 then maxRow = 5 end

                    for r = 1, maxRow do
                        local zb = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["zhuangbei" .. r]
                        local mj = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["maijia" .. r]
                        local je = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["jine" .. r]
                        local qk = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["qiankuan" .. r]
                        local gz = BG.HistoryFrame[FB]["boss" .. b] and BG.HistoryFrame[FB]["boss" .. b]["guanzhu" .. r]

                        if b == maxBoss + 2 then
                            if je then
                                je:SetText((histData["boss" .. b] and (histData["boss" .. b]["jine" .. r] or histData["boss" .. b]["jine" .. tostring(r)])) or "")
                            end
                        else
                            if zb then zb:SetText((histData["boss" .. b] and histData["boss" .. b]["zhuangbei" .. r]) or "") end
                            -- 买家留空显示
                            if mj then mj:SetText("") end
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

            for k_bt = 1, #list do
                if BG.History["ListButton" .. k_bt] then
                    BG.History["ListButton" .. k_bt]:Enable()
                end
            end
            bt:Disable()
            if BG.History.List then BG.History.List:Hide() end
            if BG.PlaySound then BG.PlaySound(1) end
        end)
    end
end

-------------------------------------------------------------------------------
-- 8. 清空前自动保存与一键撤回清空超链接联动
-------------------------------------------------------------------------------
local function SetupAutoSaveAndUndo()
    local clicked = {}
    hooksecurefunc("SetItemRef", function(link)
        local _, addon, action, FB, timeStr = strsplit(":", link)
        if (addon == "BGLite" or addon == "BiaoGe" or addon == "BGLite_Plus") and action == (L["撤回清空"] or "撤回清空") and FB then
            if not clicked[timeStr] then
                clicked[timeStr] = true
                BG.SetBiaoGeFormHistory(FB, 1)
                BG.DeleteHistory(FB, 1)
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. (L["已撤回清空，成功还原了表格数据，并删除了临时历史表格1。"] or "已撤回清空，成功还原了表格数据，并删除了临时历史表格1。"))
                if BG.PlaySound then
                    BG.PlaySound("cehuiqingkong")
                    BG.PlaySound(1)
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. (BG.STC_r1 and BG.STC_r1(L["只能撤回一次。"] or "只能撤回一次。") or "只能撤回一次。"))
            end
        end
    end)
end

-- 拦截与 Hook 核心清空逻辑：在清空前自动将原账单压入历史表格 1，并附带撤回超链接
local function HookClearBiaoGe()
    if BG.ClearBiaoGe and not BG._hasHistoryClearHook then
        BG._hasHistoryClearHook = true
        local orig_ClearBiaoGe = BG.ClearBiaoGe
        BG.ClearBiaoGe = function(_type, FB)
            if _type == "biaoge" and FB and not BG._isApplyingHistory and not BG._isSavingHistoryClear then
                if BiaoGe and BiaoGe.options and BiaoGe.options.autoQingKongSaveHistory ~= 0 then
                    -- 仅当表格真正有掉落装备或有效金额内容时，才自动归档并提示撤回
                    if IsBiaoGeHasContent(FB) then
                        local saved = BG.SaveBiaoGe(FB, true)
                        if saved then
                            local sTime = GetServerTime()
                            local link = "|cff00FF00|Hgarrmission:BiaoGe:" .. (L["撤回清空"] or "撤回清空") .. ":" .. FB .. ":" .. sTime .. "|h[" .. (L["撤回清空"] or "撤回清空") .. "]|h|r"
                            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已自动将原表格数据保存至 <%s> 历史表格1。"] or "已自动将原表格数据保存至 <%s> 历史表格1。", (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB) .. " " .. link)
                        end
                    end
                end
            end
            local res = orig_ClearBiaoGe(_type, FB)
            -- 核心重置：清空表格时必须同步清除旧打本时间戳与角色绑定，杜绝污染下一个 CD 周期
            if _type == "biaoge" and FB and BiaoGe and BiaoGe[FB] then
                BiaoGe[FB].raidTime = nil
                BiaoGe[FB].lastRaidTime = nil
                BiaoGe[FB].lootHistory = nil
                BiaoGe[FB].charName = nil
                BiaoGe[FB].class = nil
                if not BG._isApplyingHistory then
                    if ns.TeamInfo and ns.TeamInfo.ClearOnSaveHistory then
                        ns.TeamInfo.ClearOnSaveHistory(FB)
                    else
                        BiaoGe[FB].teamInfo = nil
                        if ns.TeamInfo and ns.TeamInfo.UpdateUI then
                            ns.TeamInfo.UpdateUI()
                        end
                    end
                end
            end
            return res
        end
    end
end

-------------------------------------------------------------------------------
-- 9. 表格装备悬停历史价格走势图挂载
-------------------------------------------------------------------------------
local function HookAllItemButtons()
    for _, FB in ipairs(BG.FBtable or {}) do
        local maxb = GetMaxb(FB)
        if maxb > 0 and BG.Frame and BG.Frame[FB] then
            for b = 1, maxb do
                local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                for i = 1, maxRow do
                    local bt = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    if bt and not bt._hasHistoryMoneyHook then
                        bt._hasHistoryMoneyHook = true

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
                                        -- 原生 GameTooltip
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

                                        -- 历史成交价格走势柱状图 (不含角色名)
                                        if BG.SetHistoryMoney then
                                            local jineBox = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["jine" .. i]
                                            local nowMoney = jineBox and jineBox:GetText() or ""
                                            BG.SetHistoryMoney(itemID, nowMoney)
                                        end

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

-------------------------------------------------------------------------------
-- 10. 装备历史价格悬浮走势图实现 (纯粹日期与金额，无角色名)
-------------------------------------------------------------------------------
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

        if db and db.HistoryList and db.HistoryList[FB] and db.History and db.History[FB] then
            for idx, item in ipairs(db.HistoryList[FB]) do
                local DT = item[1]
                if db.History[FB][DT] then
                    local b = 1
                    while db.History[FB][DT]["boss" .. b] do
                        local maxI = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                        for i = 1, maxI do
                            local zb = db.History[FB][DT]["boss" .. b]["zhuangbei" .. i]
                            local _itemID = GetItemID(zb)
                            if zb and _itemID and _itemID == itemID then
                                local jine = db.History[FB][DT]["boss" .. b]["jine" .. i]
                                if tonumber(jine) then
                                    table.insert(tbl, {
                                        DT = tonumber(DT),
                                        item = zb,
                                        money = tonumber(jine) or 0,
                                    })
                                end
                            end
                        end
                        b = b + 1
                    end
                end
            end
        end

        BG.HistoryMoneyCache[itemID] = tbl
        callback(tbl)
    end

    function BG.SetHistoryMoney(itemID, nowMoney)
        if not BG.MainFrame or not BG.MainFrame:IsVisible() then return end
        if not itemID then return end
        local FB = BG.FB1
        if not BG.HistoryMoneyFrame then
            local f = CreateFrame("Frame", nil, BG.MainFrame, "BackdropTemplate")
            f:SetSize(280, 0)
            f:SetPoint("BOTTOMRIGHT", BG.MainFrame, "BOTTOMRIGHT", -3, 40)
            f:SetFrameLevel(118)
            f:Hide()
            f.buttons = {}
            BG.HistoryMoneyFrame = f

            f.bg = f:CreateTexture()
            f.bg:SetSize(f:GetWidth(), 0)
            f.bg:SetPoint("TOP")
            f.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
            f.bg:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.95))

            local t = f:CreateFontString()
            t:SetPoint("TOP", f, "TOP", 3, -10)
            t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            f.title = t
        end

        BG.HistoryMoneyFrame:Hide()
        for k, bt in pairs(BG.HistoryMoneyFrame.buttons) do
            bt:Hide()
            BG.HistoryMoneyFrame.buttons[k] = nil
        end

        local maxCount = nowMoney and 14 or 15

        BG.GetHistoryMoney(itemID, FB, function(tbl)
            if #tbl == 0 and not (nowMoney and tonumber(nowMoney) and tonumber(nowMoney) > 0) then
                return
            end

            table.sort(tbl, function(a, b) return a.DT > b.DT end)

            local _tbl = {}
            for i, v in ipairs(tbl) do
                if i > maxCount then break end
                table.insert(_tbl, v)
            end

            if nowMoney and tonumber(nowMoney) and tonumber(nowMoney) > 0 then
                table.insert(_tbl, 1, {
                    DT = 0,
                    money = tonumber(nowMoney),
                    isCurrent = true,
                })
            end

            local maxJine = 1
            for i = 1, #_tbl do
                if _tbl[i].money > maxJine then
                    maxJine = _tbl[i].money
                end
            end

            local name, link, quality, level, _, _, _, _, _, Texture = GetItemInfo(itemID)
            if not link then return end
            BG.HistoryMoneyFrame.title:SetText(string.format(L["历史价格：%s%s(%s)"] or "历史价格：%s%s(%s)", (AddTexture(Texture) .. link), "|cff9370DB", level or ""))

            local down
            local color = { "00BFFF", "00FFCC", "00FF99", "00FF66", "00FF33", "33FF66", "00CC33", "33CC00", "66FF33", "33FF00", "66FF00", "99FF00", "CCFF00", "CCFF33", "99CC00" }
            for i = 1, #_tbl do
                local v = _tbl[i]
                local f = CreateFrame("Frame", nil, BG.HistoryMoneyFrame, "BackdropTemplate")
                f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
                f:SetBackdropColor(RGB(color[i] or "00FFCC", 1))
                if i == 1 then
                    f:SetPoint("TOPRIGHT", BG.HistoryMoneyFrame, "TOPRIGHT", -75, -40)
                else
                    f:SetPoint("TOPRIGHT", down, "BOTTOMRIGHT", 0, -HEIGHT2)
                end
                local widthPercent = v.money / maxJine
                local width = (widthPercent == 0) and 1 or ((BG.HistoryMoneyFrame:GetWidth() - 170) * widthPercent + 45)
                f:SetSize(width, HEIGHT)
                down = f
                table.insert(BG.HistoryMoneyFrame.buttons, f)

                local tDate = f:CreateFontString()
                tDate:SetPoint("LEFT", f, "RIGHT", 4, 0)
                tDate:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                tDate:SetTextColor(RGB(color[i] or "00FFCC"))
                if v.isCurrent then
                    tDate:SetText(L["当前"] or "当前")
                else
                    local dtStr = tostring(v.DT)
                    local a = strsub(dtStr, 3, 4)
                    if a:sub(1, 1) == "0" then a = a:sub(2, 2) end
                    local b = strsub(dtStr, 5, 6)
                    if b:sub(1, 1) == "0" then b = b:sub(2, 2) end
                    tDate:SetText(a .. (L["月"] or "月") .. b .. (L["日"] or "日"))
                end

                local tMoney = f:CreateFontString()
                tMoney:SetPoint("RIGHT", f, "LEFT", -4, 0)
                tMoney:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                tMoney:SetTextColor(RGB(color[i] or "00FFCC"))
                local numText = (BG.FormatNumber and BG.FormatNumber(v.money, 2)) or tostring(v.money)
                tMoney:SetText(numText)
            end

            local height = #_tbl * (HEIGHT + HEIGHT2) + 65
            BG.HistoryMoneyFrame:SetHeight(height)
            BG.HistoryMoneyFrame.bg:SetHeight(height + 50)
            BG.HistoryMoneyFrame:Show()
        end)
    end

    function BG.HideHistoryMoney()
        if BG.HistoryMoneyFrame then
            BG.HistoryMoneyFrame:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- 11. 生命周期自启动与事件绑定
-------------------------------------------------------------------------------
local function StartHistoryModule()
    InitHistoryDB()
    HookClearBiaoGe()
    SetupAutoSaveAndUndo()

    C_Timer.After(0.5, function()
        if BG.MainFrame then
            CreateHistoryUI()
            HookAllItemButtons()
            HookClearBiaoGe()

            if not BG.History.hasHookedFBButtons then
                BG.History.hasHookedFBButtons = true

                if BG.MainFrame.HookScript then
                    BG.MainFrame:HookScript("OnShow", function()
                        BG.UpdateHistoryButton()
                        HookAllItemButtons()
                        HookClearBiaoGe()
                    end)
                end
                if BG.FBMainFrame and BG.FBMainFrame.HookScript then
                    BG.FBMainFrame:HookScript("OnShow", function()
                        BG.UpdateHistoryButton()
                        HookAllItemButtons()
                        HookClearBiaoGe()
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
end

-- 自愈清洗被污染的在途表格数据（如外部5人本污染导致的时间戳偏离、非本团本拾取等）
local function SanitizeActiveTables()
    if not (BiaoGe and (BG.FBtable or BG.FBIDtable)) then return end
    local fbList = BG.FBtable or {}
    local now = (GetServerTime and GetServerTime()) or time()
    local curWeekStart = (WR and WR.GetCDWeekStart and WR.GetCDWeekStart(now))
        or (ns.WorkerReport and ns.WorkerReport.GetCDWeekStart and ns.WorkerReport.GetCDWeekStart(now))
        or (now - 7 * 86400)

    for _, fb in ipairs(fbList) do
        if BiaoGe[fb] then
            local rt = tonumber(BiaoGe[fb].raidTime)
            local lrt = tonumber(BiaoGe[fb].lastRaidTime)

            -- 跨周与跨车次智能自愈：若 lastRaidTime 属于当前 CD 周 (>= curWeekStart) 且比旧 raidTime 晚很多，说明是新 CD 车次，更新 raidTime
            if lrt and lrt >= curWeekStart and (not rt or rt < curWeekStart or (lrt - rt > 16 * 3600)) then
                BiaoGe[fb].raidTime = lrt
            end

            -- 清洗掉落拾取日志中的外部5人本条目
            if BiaoGe[fb].lootHistory and type(BiaoGe[fb].lootHistory) == "table" then
                local clean = {}
                for _, item in ipairs(BiaoGe[fb].lootHistory) do
                    local s = tostring(item.source or "")
                    if not (s:find("熔炉") or s:find("围栏") or s:find("地牢") or s:find("监狱") or s:find("迷宫") or s:find("破碎") or s:find("城墙") or s:find("沼泽") or s:find("幽暗") or s:find("平台")) then
                        table.insert(clean, item)
                    end
                end
                BiaoGe[fb].lootHistory = clean
            end
            -- 重新推导打本角色：借助多重客观证据仲裁（raidRoster、买家、交易、入队记录）
            -- 仅对包含实际内容的表格进行纠偏与固化，绝不盲目污染空表格
            if IsBiaoGeHasContent and IsBiaoGeHasContent(fb) then
                local owner, oClass = DeduceTableOwner(fb)
                if owner and owner ~= "" and owner ~= "未知角色" then
                    BiaoGe[fb].charName = owner
                    BiaoGe[fb].class = oClass
                end
            end
        end
    end
end
ns.SanitizeActiveTables = SanitizeActiveTables

-- 实时监听团本 BOSS 战斗与击杀，自动标记真实打本时间戳（仅限团队副本内）
local raidEventFrame = CreateFrame("Frame")
raidEventFrame:RegisterEvent("ENCOUNTER_END")
raidEventFrame:RegisterEvent("BOSS_KILL")
raidEventFrame:SetScript("OnEvent", function(self, event, ...)
    local fb = BG.FB2 or BG.FB1
    if fb and BiaoGe and BiaoGe[fb] then
        local now = (GetServerTime and GetServerTime()) or time()
        local curWeekStart = (WR and WR.GetCDWeekStart and WR.GetCDWeekStart(now))
            or (ns.WorkerReport and ns.WorkerReport.GetCDWeekStart and ns.WorkerReport.GetCDWeekStart(now))
            or (now - 7 * 86400)
        local rt = tonumber(BiaoGe[fb].raidTime)
        -- 若没有 raidTime，或者已有 raidTime 属于上一个 CD 周，或者相距超过 16 小时：刷新为当前本次打本时间！
        if not rt or rt < curWeekStart or (now - rt > 16 * 3600) then
            BiaoGe[fb].raidTime = now
        end
        BiaoGe[fb].lastRaidTime = now
        local myName = UnitName("player")
        if myName and myName ~= "" then
            BiaoGe[fb].charName = myName
            BiaoGe[fb].class = select(2, UnitClass("player")) or "WARRIOR"
        end
    end
end)

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function(self, event)
    SanitizeActiveTables()
    StartHistoryModule()
end)

-- 顶层立即预热执行
SanitizeActiveTables()
StartHistoryModule()
