if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local LibBG = ns.LibBG or LibStub:GetLibrary("BiaoGe-LibUIDropDownMenu-4.0", true)
local L = ns.L or {}
local RGB = ns.RGB or function(hex, a)
    local r = tonumber(strsub(hex, 1, 2), 16) / 255
    local g = tonumber(strsub(hex, 3, 4), 16) / 255
    local b = tonumber(strsub(hex, 5, 6), 16) / 255
    return r, g, b, a or 1
end

local function GetClassRGB(class)
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

local function SetClassCFF(name, class)
    if not name or name == "" then return "" end
    local r, g, b = GetClassRGB(class)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
end

-- 副本标准化展示名称映射（贴合账单顶部 Tab 名称与大众习惯）
local FB_NAME_MAP = {
    ["SWtitan"] = "P5双本",
    ["TOCtitan"] = "P4双本",
    ["NAXXtitan"] = "NAXX",
    ["SSCtitan"] = "毒蛇风暴",
    ["MCtitan"] = "熔火之心",
    ["ULDtitan"] = "奥杜尔",
    ["Worldtitan"] = "世界Boss",
    ["OStitan"] = "黑曜石",
    ["EOEtitan"] = "永恒之眼",
    ["SW"] = "太阳之井",
    ["BT"] = "黑暗神殿",
    ["HS"] = "海加尔山",
    ["SSC"] = "毒蛇风暴",
    ["TK"] = "风暴要塞",
    ["NAXX"] = "纳克萨玛斯",
    ["ULD"] = "奥杜尔",
    ["TOC"] = "十字军试炼",
    ["ICC"] = "冰冠堡垒",
    ["MC"] = "熔火之心",
    ["BWL"] = "黑翼之巢",
    ["TAQ"] = "安其拉神殿",
    ["ZUG"] = "祖尔格拉布",
    ["RA"] = "安其拉废墟",
}

local function GetFBDisplayName(FB)
    if not FB then return "" end
    if BG and BG.GetFBinfo then
        local name = BG.GetFBinfo(FB, "shortName") or BG.GetFBinfo(FB, "localName")
        if name and name ~= "" and name ~= FB then
            return name
        end
    end
    return FB_NAME_MAP[FB] or FB
end

local function FormatMoney(amount)
    amount = tonumber(amount) or 0
    if amount >= 10000 then
        local w = amount / 10000
        if amount % 10000 == 0 then
            return string.format("%d万G", w)
        else
            return string.format("%.1f万G", w)
        end
    else
        return string.format("%dG", amount)
    end
end

-------------------------------------------------------------------------------
-- 模块命名空间
-------------------------------------------------------------------------------
local WR = {}
ns.WorkerReport = WR
BG.WorkerReport = WR

WR.MainFrame = nil
WR.rows = {}
WR.curWeekFilter = "current" -- "current", "last", "month", "all"
WR.curCharFilter = "all"

local MAX_RECORDS = 500

-------------------------------------------------------------------------------
-- 1. 数据库初始化
-------------------------------------------------------------------------------
function WR.InitDB()
    if not BiaoGe then BiaoGe = {} end
    if not BiaoGe.WorkerReport then
        BiaoGe.WorkerReport = {
            version = 2,
            manualRecords = {},
            options = {
                showWeeklyPopup = true,
                lastPopupWeek = 0,
            }
        }
    end
    BiaoGe.WorkerReport.manualRecords = BiaoGe.WorkerReport.manualRecords or {}
    if not BiaoGe.WorkerReport.options then
        BiaoGe.WorkerReport.options = {
            showWeeklyPopup = true,
            lastPopupWeek = 0,
        }
    end

    -- 深度清理与平滑迁移：若存在旧版静态写入的 records，提取手工记账项，彻底删除静态缓存！
    if BiaoGe.WorkerReport.records and type(BiaoGe.WorkerReport.records) == "table" and #BiaoGe.WorkerReport.records > 0 then
        for _, r in ipairs(BiaoGe.WorkerReport.records) do
            if r.source == "manual" then
                table.insert(BiaoGe.WorkerReport.manualRecords, r)
            end
        end
        BiaoGe.WorkerReport.records = nil
    end
end

-------------------------------------------------------------------------------
-- 2. 魔兽国服周四 07:00 CD 周期引擎
-------------------------------------------------------------------------------
-- 计算任意时间戳所属的魔兽 CD 周起始时间戳 (周四 07:00:00)
function WR.GetCDWeekStart(ts)
    ts = ts or time()
    local t = date("*t", ts)
    -- wday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    local daysSinceThu = (t.wday - 5) % 7
    local isBefore7AM = (daysSinceThu == 0 and t.hour < 7)
    if isBefore7AM then
        daysSinceThu = 7
    end
    -- 当周周四 07:00 的时间戳
    local midnightToday = ts - (t.hour * 3600 + t.min * 60 + t.sec)
    local thuStart = midnightToday - (daysSinceThu * 86400) + (7 * 3600)
    return thuStart
end

-- 获取周ID（格式为YYYYMMDD，例如 20260918）
function WR.GetCDWeekId(ts)
    local startTs = WR.GetCDWeekStart(ts)
    return tonumber(date("%Y%m%d", startTs))
end

-- 获取当前 CD 周和上周 CD 的范围起止描述
function WR.GetCDWeekDesc(offsetWeeks)
    offsetWeeks = offsetWeeks or 0
    local curStart = WR.GetCDWeekStart(time()) + (offsetWeeks * 7 * 86400)
    local curEnd = curStart + (7 * 86400) - 1
    return string.format("%s ~ %s", date("%m/%d", curStart), date("%m/%d", curEnd)), curStart, curEnd
end

-------------------------------------------------------------------------------
-- 2.5 历史时间戳解析辅助
-------------------------------------------------------------------------------
-- 将 DT (如 260920213015) 转换为 UNIX 时间戳
local function DTToTimestamp(DT)
    if not DT then return nil end
    local str = tostring(DT)
    if #str < 12 then
        str = string.rep("0", 12 - #str) .. str
    end
    local y = 2000 + (tonumber(str:sub(1, 2)) or 0)
    local m = tonumber(str:sub(3, 4)) or 1
    local d = tonumber(str:sub(5, 6)) or 1
    local h = tonumber(str:sub(7, 8)) or 0
    local mi = tonumber(str:sub(9, 10)) or 0
    local s = tonumber(str:sub(11, 12)) or 0
    local ok, ts = pcall(time, { year = y, month = m, day = d, hour = h, min = mi, sec = s })
    return ok and ts or nil
end

-- 兼容空函数（彻底摒弃往全局持久化同步的做法）
function WR.SyncFromHistory() return 0 end
function WR.ScanActiveBiaoGe() return 0 end
function WR.AddRecordFromHistory(...) return end

-------------------------------------------------------------------------------
-- 3. 手工补录流水与删除
-------------------------------------------------------------------------------
function WR.AddRecord(info)
    WR.InitDB()
    if not info or not info.wage or tonumber(info.wage) <= 0 then return false end

    local charName = info.charName or UnitName("player") or "未知角色"
    local realm = info.realm or GetRealmName() or ""
    local class = info.class or select(2, UnitClass("player")) or "WARRIOR"
    local ts = info.timestamp or time()
    local wage = tonumber(info.wage) or 0
    local subsidy = tonumber(info.subsidy) or 0
    local mySpend = tonumber(info.mySpend) or 0
    local netWage = wage + subsidy - mySpend
    local fb = info.fb or "UNKNOWN"
    local fbName = info.fbName or fb
    local totalPeople = tonumber(info.totalPeople) or 0
    local grossMoney = tonumber(info.grossMoney) or 0
    local note = info.note or ""

    local records = BiaoGe.WorkerReport.manualRecords
    local record = {
        id = string.format("manual_%d_%s_%s", ts, charName, fb),
        timestamp = ts,
        charName = charName,
        realm = realm,
        class = class,
        fb = fb,
        fbName = fbName,
        totalPeople = totalPeople,
        grossMoney = grossMoney,
        wage = wage,
        subsidy = subsidy,
        mySpend = mySpend,
        netWage = netWage,
        source = "manual",
        note = (note ~= "") and note or "手工补录",
    }

    table.insert(records, 1, record)
    while #records > MAX_RECORDS do
        table.remove(records)
    end

    if WR.MainFrame and WR.MainFrame:IsShown() then
        WR.UpdateUI()
    end
    return true
end

-- 删除某条记录 (严格仅允许删除手工补录条目，绝对不触碰底层历史账单资产)
function WR.DeleteRecord(record)
    WR.InitDB()
    if not record then return end

    if record.source == "manual" then
        for i, r in ipairs(BiaoGe.WorkerReport.manualRecords or {}) do
            if r.id == record.id or (r.timestamp == record.timestamp and r.charName == record.charName and r.wage == record.wage) then
                table.remove(BiaoGe.WorkerReport.manualRecords, i)
                break
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus]|r " .. (L["已删除手工补录记录。"] or "已删除手工补录记录。"))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus]|r " .. (L["历史表格属于团本核心资产，受安全保护无法从看板删除。若需管理历史，请在右上角【历史表格】下拉框中操作。"] or "历史表格属于团本核心资产，受安全保护无法从看板删除。若需管理历史，请在右上角【历史表格】下拉框中操作。"))
        return
    end

    if WR.MainFrame and WR.MainFrame:IsShown() then
        WR.UpdateUI()
    end
end

-- 校准某条记录的打本真实时间 (解决老历史记录或隔天保存导致时间不对的问题)
function WR.SetRecordTime(record, newTimestamp)
    if not (record and newTimestamp and newTimestamp > 0) then return end
    if record.source == "history" and record.fb and record.DT then
        if BiaoGe and BiaoGe.History and BiaoGe.History[record.fb] and BiaoGe.History[record.fb][record.DT] then
            BiaoGe.History[record.fb][record.DT].raidTime = newTimestamp
        end
        -- 同步更新 HistoryList 里的日期文本
        if BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[record.fb] then
            for _, item in ipairs(BiaoGe.HistoryList[record.fb]) do
                if item[1] == record.DT then
                    item[3] = date("%m/%d", newTimestamp)
                    item[4] = date("%H:%M:%S", newTimestamp)
                    break
                end
            end
        end
        if BG.UpdateHistoryButton then BG.UpdateHistoryButton() end
    elseif record.source == "manual" then
        for _, r in ipairs(BiaoGe.WorkerReport.manualRecords or {}) do
            if r.id == record.id then
                r.timestamp = newTimestamp
                break
            end
        end
    elseif record.source == "active" and record.fb then
        if BiaoGe and BiaoGe[record.fb] then
            BiaoGe[record.fb].raidTime = newTimestamp
            BiaoGe[record.fb].lastRaidTime = newTimestamp
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. string.format(L["已成功将 <%s> 的打本时间校准为: %s"] or "已成功将 <%s> 的打本时间校准为: %s", record.fbName or record.fb, date("%Y-%m-%d %H:%M", newTimestamp)))

    if WR.MainFrame and WR.MainFrame:IsShown() then
        WR.UpdateUI()
    end
end

-- 编辑保存某条记录的全部财务明细 (分得工资、补贴、装备消费、罚款、打本时间)
function WR.SaveRecordAdjustment(record, newWage, newSubsidy, newMySpend, newPenalty, newGross, newTimestamp)
    if not record then return end
    WR.InitDB()

    newWage = tonumber(newWage) or (record.wage or 0)
    newSubsidy = tonumber(newSubsidy) or 0
    newMySpend = tonumber(newMySpend) or 0
    newPenalty = tonumber(newPenalty) or 0
    newGross = tonumber(newGross) or (record.grossMoney or 0)
    newTimestamp = tonumber(newTimestamp) or (record.timestamp or time())
    local netWage = newWage + newSubsidy - newPenalty - newMySpend

    if record.source == "manual" then
        for _, r in ipairs(BiaoGe.WorkerReport.manualRecords or {}) do
            if r.id == record.id or (r.timestamp == record.timestamp and r.charName == record.charName) then
                r.wage = newWage
                r.subsidy = newSubsidy
                r.mySpend = newMySpend
                r.penalty = newPenalty
                r.grossMoney = newGross
                r.netWage = netWage
                r.timestamp = newTimestamp
                break
            end
        end
    elseif record.source == "history" and record.fb and record.DT then
        if BiaoGe and BiaoGe.History and BiaoGe.History[record.fb] and BiaoGe.History[record.fb][record.DT] then
            local hist = BiaoGe.History[record.fb][record.DT]
            hist.wage = newWage
            hist.subsidy = newSubsidy
            hist.mySpend = newMySpend
            hist.penalty = newPenalty
            hist.grossMoney = newGross
            hist.netWage = netWage
            hist.raidTime = newTimestamp

            local maxb = GetFBMaxb and GetFBMaxb(record.fb) or 15
            if hist["boss" .. (maxb + 2)] then
                hist["boss" .. (maxb + 2)]["jine5"] = tostring(newWage)
                if newGross > 0 then
                    hist["boss" .. (maxb + 2)]["jine1"] = tostring(newGross)
                end
            end
        end
        if BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[record.fb] then
            for _, item in ipairs(BiaoGe.HistoryList[record.fb]) do
                if item[1] == record.DT then
                    item[2] = string.format("%s %d人 工资:%d", record.fbName or record.fb, record.totalPeople or 0, newWage)
                    item[3] = date("%m/%d", newTimestamp)
                    item[4] = date("%H:%M:%S", newTimestamp)
                    break
                end
            end
        end
        if BG.UpdateHistoryButton then BG.UpdateHistoryButton() end
    elseif record.source == "active" and record.fb then
        if not BiaoGe.WorkerReport.customAdjustments then
            BiaoGe.WorkerReport.customAdjustments = {}
        end
        local sig = string.format("active_%s", tostring(record.fb))
        BiaoGe.WorkerReport.customAdjustments[sig] = {
            wage = newWage,
            subsidy = newSubsidy,
            mySpend = newMySpend,
            penalty = newPenalty,
            grossMoney = newGross,
            timestamp = newTimestamp,
            netWage = netWage,
        }
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. string.format(L["已成功更新 <%s> 的收支明细 (净到手: %d G)。"] or "已成功更新 <%s> 的收支明细 (净到手: %d G)。", record.fbName or record.fb, netWage))

    if WR.MainFrame and WR.MainFrame:IsShown() then
        WR.UpdateUI()
    end
end

local function GetFBMaxb(FB)
    if not FB then return 15 end
    if BG and BG.Maxb and BG.Maxb[FB] and BG.Maxb[FB] > 0 then
        return BG.Maxb[FB]
    end
    if ns.Maxb and type(ns.Maxb[FB]) == "number" and ns.Maxb[FB] > 0 then
        return ns.Maxb[FB]
    end
    return 15
end

-- 智能提取当前活跃表格总览数据（人均工资、分钱人数、账面总流水）
local function GetActiveOverviewData(FB)
    local wage, totalPeople, grossMoney = 0, 0, 0
    local maxb = GetFBMaxb(FB)
    local candidates = { maxb + 2, maxb + 1, maxb, 19, 18, 17, 14, 12 }

    -- 1. 优先从运行期 UI 框架 (BG.Frame) 获取
    for _, b in ipairs(candidates) do
        if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
            local gzEB = BG.Frame[FB]["boss" .. b]["jine5"]
            local renEB = BG.Frame[FB]["boss" .. b]["jine4"]
            local grossEB = BG.Frame[FB]["boss" .. b]["jine1"]
            local zb1 = BG.Frame[FB]["boss" .. b]["zhuangbei1"]
            local zb4 = BG.Frame[FB]["boss" .. b]["zhuangbei4"]
            local zb5 = BG.Frame[FB]["boss" .. b]["zhuangbei5"]

            local isOverview = false
            if zb1 and zb1.GetText and zb1:GetText():find("总收入") then isOverview = true end
            if zb4 and zb4.GetText and zb4:GetText():find("分钱") then isOverview = true end
            if zb5 and zb5.GetText and zb5:GetText():find("工资") then isOverview = true end
            if gzEB and renEB and grossEB then isOverview = true end

            if isOverview then
                if gzEB and gzEB.GetText then wage = tonumber(gzEB:GetText()) or 0 end
                if renEB and renEB.GetText then totalPeople = tonumber(renEB:GetText()) or 0 end
                if grossEB and grossEB.GetText then grossMoney = tonumber(grossEB:GetText()) or 0 end
                if grossMoney > 0 or wage > 0 then
                    break
                end
            end
        end
    end

    -- 2. 若 UI 中未填或未渲染，从 SavedVariables BiaoGe[FB] 获取
    if grossMoney == 0 and wage == 0 and BiaoGe and BiaoGe[FB] then
        for _, b in ipairs(candidates) do
            local bTbl = BiaoGe[FB]["boss" .. b]
            if type(bTbl) == "table" then
                local isOverview = false
                if bTbl["zhuangbei1"] and tostring(bTbl["zhuangbei1"]):find("总收入") then isOverview = true end
                if bTbl["zhuangbei4"] and tostring(bTbl["zhuangbei4"]):find("分钱") then isOverview = true end
                if bTbl["zhuangbei5"] and tostring(bTbl["zhuangbei5"]):find("工资") then isOverview = true end
                if bTbl["jine5"] or bTbl["jine4"] or bTbl["jine1"] then isOverview = true end

                if isOverview then
                    wage = tonumber(bTbl["jine5"]) or 0
                    totalPeople = tonumber(bTbl["jine4"]) or 0
                    grossMoney = tonumber(bTbl["jine1"]) or 0
                    if grossMoney > 0 or wage > 0 then
                        break
                    end
                end
            end
        end
    end

    -- 3. 如果在活跃表格中总流水仍为 0，遍历 Boss 1..maxb 累加有效金额（防止用户手动录入了装备但未触发总收入汇总）
    if grossMoney == 0 and BiaoGe and BiaoGe[FB] then
        local sumMoney = 0
        for b = 1, maxb do
            local bTbl = BiaoGe[FB]["boss" .. b]
            if type(bTbl) == "table" then
                for i = 1, 25 do
                    local je = tonumber(bTbl["jine" .. i]) or 0
                    sumMoney = sumMoney + je
                end
            end
        end
        if sumMoney > 0 then
            grossMoney = sumMoney
        end
    end

    -- 4. 如果总流水 > 0 但人数未填，自动取该团本标准人数（如 25 人）兜底
    if totalPeople == 0 and grossMoney > 0 then
        totalPeople = tonumber((BG.GetFBinfo and BG.GetFBinfo(FB, "maxplayers"))) or 25
    end

    -- 5. 如果尚未计算人均工资，自动推导工资
    if wage == 0 and grossMoney > 0 and totalPeople > 0 then
        wage = math.floor(grossMoney / totalPeople)
    end

    return wage, totalPeople, grossMoney
end

-- 智能定位支出格子编号
local function GetActiveZhiChuBoss(FB)
    local maxb = GetFBMaxb(FB)
    local candidates = { maxb + 1, maxb, 18, 13, 11 }
    for _, b in ipairs(candidates) do
        if BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] then
            local zb1 = BG.Frame[FB]["boss" .. b]["zhuangbei1"]
            if zb1 and zb1.GetText and (zb1:GetText():find("补") or zb1:GetText():find("支")) then
                return b
            end
        elseif BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. b] then
            local zb1 = BiaoGe[FB]["boss" .. b]["zhuangbei1"]
            if zb1 and (tostring(zb1):find("补") or tostring(zb1):find("支")) then
                return b
            end
        end
    end
    return maxb + 1
end

-------------------------------------------------------------------------------
-- 4. 核心：动态聚合引擎 (Dynamic Aggregation Engine)
-- 彻底杜绝持久化旧快照导致的“日期僵死在历史保存时间”问题
-------------------------------------------------------------------------------
function WR.GetAllRecords()
    WR.InitDB()
    local allRecords = {}
    local registeredSignatures = {}

    local curChar = UnitName("player") or "未知角色"
    local curClass = select(2, UnitClass("player")) or "WARRIOR"
    local curRealm = GetRealmName() or ""

    -- 1. 汇聚用户手工补录记录 (Manual Records)
    for _, r in ipairs(BiaoGe.WorkerReport.manualRecords or {}) do
        table.insert(allRecords, r)
    end

    -- 2. 全量收集所有可能存在的团本键（无死角覆盖毒蛇、风暴、SW、TOC、奥杜尔等）
    local fbMap = {}
    if BG and BG.FBtable then
        for _, fb in ipairs(BG.FBtable) do fbMap[fb] = true end
    end
    if BG and BG.FBtable2 then
        for _, v in ipairs(BG.FBtable2) do if v.FB then fbMap[v.FB] = true end end
    end
    if BiaoGe and BiaoGe.History then
        for fb in pairs(BiaoGe.History) do fbMap[fb] = true end
    end
    local ignoredKeys = {
        options = true, History = true, HistoryList = true, WorkerReport = true,
        tradeHistory = true, mailHistory = true, whoFrame = true, meetingHorn = true,
        Hope = true, equip = true, buffCD = true, point = true, YYdb = true,
        auctionMSGhistory = true, MeetingHorn = true, MeetingHornWhisper = true,
        FilterClassItemDB = true, clearBiaoGeMoney = true,
    }
    if BiaoGe then
        for k, v in pairs(BiaoGe) do
            if type(v) == "table" and not ignoredKeys[k] and (k:find("titan") or k:find("sod") or #k <= 6) then
                fbMap[k] = true
            end
        end
    end
    local fbList = {}
    for fb in pairs(fbMap) do table.insert(fbList, fb) end

    -- 3. 动态扫描历史表格数据库 (BiaoGe.History)
    for _, FB in ipairs(fbList) do
        local maxb = GetFBMaxb(FB)
        local fbDisplayName = GetFBDisplayName(FB)

        -- 建立 HistoryList 辅助速查表 (提取可能存在的精准摘要)
        local listLookup = {}
        if BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[FB] and type(BiaoGe.HistoryList[FB]) == "table" then
            for _, item in ipairs(BiaoGe.HistoryList[FB]) do
                if type(item) == "table" and item[1] then
                    listLookup[item[1]] = item
                end
            end
        end

        if BiaoGe and BiaoGe.History and BiaoGe.History[FB] and type(BiaoGe.History[FB]) == "table" then
            for DT, record in pairs(BiaoGe.History[FB]) do
                if type(record) == "table" then
                    local bOverview = maxb + 2
                    local wage = tonumber(record.wage) or 0
                    local totalPeople = tonumber(record.totalPeople) or 0
                    local grossMoney = tonumber(record.grossMoney) or 0
                    local mySpend = tonumber(record.mySpend) or 0
                    local subsidy = tonumber(record.subsidy) or 0
                    local penalty = tonumber(record.penalty) or 0
                    local mySpends = record.mySpends or {}

                    if record["boss" .. bOverview] then
                        if wage == 0 then wage = tonumber(record["boss" .. bOverview]["jine5"]) or 0 end
                        if totalPeople == 0 then totalPeople = tonumber(record["boss" .. bOverview]["jine4"]) or 0 end
                        if grossMoney == 0 then grossMoney = tonumber(record["boss" .. bOverview]["jine1"]) or 0 end
                    end

                    local histItem = listLookup[DT]
                    if wage == 0 and histItem and histItem[2] then
                        local wMatch = histItem[2]:match("工资:(%d+)")
                        if wMatch then wage = tonumber(wMatch) or 0 end
                    end
                    if totalPeople == 0 and histItem and histItem[2] then
                        local pMatch = histItem[2]:match("(%d+)人")
                        if pMatch then totalPeople = tonumber(pMatch) or 0 end
                    end

                    if wage > 0 then
                        -- 计算打本真实时间戳：优先采用打本真实时间 raidTime
                        local ts = (tonumber(record.raidTime) and tonumber(record.raidTime) > 0 and tonumber(record.raidTime)) or DTToTimestamp(DT) or time()
                        local cName = record.charName or curChar
                        local cClass = record.class or curClass
                        local cRealm = record.realm or curRealm

                        -- 如果历史记录中没有固化消费/补贴，尝试回退检查 (针对未清除名字的记录)
                        if mySpend == 0 and subsidy == 0 and penalty == 0 then
                            for b = 1, maxb do
                                local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                                if record["boss" .. b] then
                                    for i = 1, maxRow do
                                        if record["boss" .. b]["maijia" .. i] == cName then
                                            local je = tonumber(record["boss" .. b]["jine" .. i]) or 0
                                            local zb = record["boss" .. b]["zhuangbei" .. i] or ""
                                            if zb:find(L["罚款"] or "罚款") then
                                                penalty = penalty + je
                                            else
                                                mySpend = mySpend + je
                                                table.insert(mySpends, { item = zb, money = je, boss = b })
                                            end
                                        end
                                    end
                                end
                            end
                            local bZhiChu = maxb + 1
                            if record["boss" .. bZhiChu] then
                                local maxRowZhiChu = (BG.GetMaxi and BG.GetMaxi(FB, bZhiChu)) or 20
                                for i = 1, maxRowZhiChu do
                                    if record["boss" .. bZhiChu]["maijia" .. i] == cName then
                                        subsidy = subsidy + (tonumber(record["boss" .. bZhiChu]["jine" .. i]) or 0)
                                    end
                                end
                            end
                        end

                        local netWage = wage + subsidy - penalty - mySpend

                        local noteText = "历史表格归档"
                        if subsidy > 0 and mySpend > 0 then
                            noteText = string.format("补贴+%dG 消费-%dG", subsidy, mySpend)
                        elseif subsidy > 0 then
                            noteText = string.format("含补贴 +%dG", subsidy)
                        elseif mySpend > 0 then
                            noteText = string.format("购买装备 -%dG", mySpend)
                        end

                        local entry = {
                            id = string.format("hist_%s_%s", tostring(FB), tostring(DT)),
                            historyId = string.format("%s_%s", tostring(FB), tostring(DT)),
                            DT = DT,
                            timestamp = ts,
                            charName = cName,
                            realm = cRealm,
                            class = cClass,
                            fb = FB,
                            fbName = fbDisplayName,
                            totalPeople = totalPeople,
                            grossMoney = grossMoney,
                            wage = wage,
                            subsidy = subsidy,
                            mySpend = mySpend,
                            penalty = penalty,
                            mySpends = mySpends,
                            netWage = netWage,
                            source = "history",
                            note = noteText,
                        }
                        table.insert(allRecords, entry)

                        local sig = string.format("%s_%d_%d", tostring(FB), wage, totalPeople)
                        registeredSignatures[sig] = true
                    end
                end
            end
        end
    end

    -- 4. 动态扫描当前在途活跃表格 (BiaoGe[FB])
    for _, FB in ipairs(fbList) do
        local maxb = GetFBMaxb(FB)
        local wage, totalPeople, grossMoney = GetActiveOverviewData(FB)

        if wage > 0 then
            local sig = string.format("%s_%d_%d", tostring(FB), wage, totalPeople)
            -- 仅当历史存档中没有完全相同的记录时，才作为实时在途账单展示
            if not registeredSignatures[sig] then
                local trueRaidTime = (ns.GetTrueRaidTime and ns.GetTrueRaidTime(FB)) or (BiaoGe and BiaoGe[FB] and BiaoGe[FB].raidTime) or time()
                local fbDisplayName = GetFBDisplayName(FB)

                -- 统计当前表格中本人的消费与补贴
                local curSpend = 0
                local curSubsidy = 0
                local curPenalty = 0
                local mySpends = {}

                for b = 1, maxb do
                    local maxRow = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 22
                    for i = 1, maxRow do
                        local mj = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["maijia" .. i])
                        local je = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["jine" .. i])
                        local zb = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i])
                        local buyer = (mj and mj.GetText and mj:GetText()) or (BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["maijia" .. i])
                        local money = tonumber(je and je.GetText and je:GetText()) or tonumber(BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["jine" .. i]) or 0
                        local itemText = (zb and zb.GetText and zb:GetText()) or (BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. b] and BiaoGe[FB]["boss" .. b]["zhuangbei" .. i]) or ""

                        if buyer == curChar and money > 0 then
                            if itemText:find(L["罚款"] or "罚款") then
                                curPenalty = curPenalty + money
                            else
                                curSpend = curSpend + money
                                table.insert(mySpends, { item = itemText, money = money, boss = b })
                            end
                        end
                    end
                end
                local bZhiChu = GetActiveZhiChuBoss(FB)
                local maxRowZhiChu = (BG.GetMaxi and BG.GetMaxi(FB, bZhiChu)) or 20
                for i = 1, maxRowZhiChu do
                    local mj = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. bZhiChu] and BG.Frame[FB]["boss" .. bZhiChu]["maijia" .. i])
                    local je = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. bZhiChu] and BG.Frame[FB]["boss" .. bZhiChu]["jine" .. i])
                    local buyer = (mj and mj.GetText and mj:GetText()) or (BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. bZhiChu] and BiaoGe[FB]["boss" .. bZhiChu]["maijia" .. i])
                    local money = tonumber(je and je.GetText and je:GetText()) or tonumber(BiaoGe and BiaoGe[FB] and BiaoGe[FB]["boss" .. bZhiChu] and BiaoGe[FB]["boss" .. bZhiChu]["jine" .. i]) or 0
                    if buyer == curChar and money > 0 then
                        curSubsidy = curSubsidy + money
                    end
                end

                -- 检查是否有外部针对此活跃表格的手动调整
                local adjKey = string.format("active_%s", tostring(FB))
                if BiaoGe.WorkerReport.customAdjustments and BiaoGe.WorkerReport.customAdjustments[adjKey] then
                    local adj = BiaoGe.WorkerReport.customAdjustments[adjKey]
                    wage = adj.wage or wage
                    curSubsidy = adj.subsidy or curSubsidy
                    curSpend = adj.mySpend or curSpend
                    curPenalty = adj.penalty or curPenalty
                    grossMoney = adj.grossMoney or grossMoney
                    trueRaidTime = adj.timestamp or trueRaidTime
                end

                local netWage = wage + curSubsidy - curPenalty - curSpend

                local noteText = "当前活跃账单(未归档)"
                if curSubsidy > 0 and curSpend > 0 then
                    noteText = string.format("活跃账单: 补贴+%dG 消费-%dG", curSubsidy, curSpend)
                elseif curSubsidy > 0 then
                    noteText = string.format("活跃账单: 补贴+%dG", curSubsidy)
                elseif curSpend > 0 then
                    noteText = string.format("活跃账单: 消费-%dG", curSpend)
                end

                local entry = {
                    id = string.format("active_%s_%d", tostring(FB), trueRaidTime),
                    timestamp = trueRaidTime,
                    charName = curChar,
                    realm = curRealm,
                    class = curClass,
                    fb = FB,
                    fbName = fbDisplayName,
                    totalPeople = totalPeople,
                    grossMoney = grossMoney,
                    wage = wage,
                    subsidy = curSubsidy,
                    mySpend = curSpend,
                    penalty = curPenalty,
                    mySpends = mySpends,
                    netWage = netWage,
                    source = "active",
                    note = noteText,
                }
                table.insert(allRecords, entry)
            end
        end
    end

    -- 按时间戳降序排序 (最近的排最前)
    table.sort(allRecords, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    return allRecords
end

function WR.GetFilteredRecords()
    local allRecords = WR.GetAllRecords()
    local filtered = {}
    local curWeekStart = WR.GetCDWeekStart(time())
    local curWeekEnd = curWeekStart + 7 * 86400 - 1
    local lastWeekStart = curWeekStart - 7 * 86400
    local lastWeekEnd = curWeekStart - 1
    local monthStart = time() - 30 * 86400

    for i, r in ipairs(allRecords) do
        local matchTime = true
        if WR.curWeekFilter == "current" then
            matchTime = (r.timestamp >= curWeekStart and r.timestamp <= curWeekEnd)
        elseif WR.curWeekFilter == "last" then
            matchTime = (r.timestamp >= lastWeekStart and r.timestamp <= lastWeekEnd)
        elseif WR.curWeekFilter == "month" then
            matchTime = (r.timestamp >= monthStart)
        end

        local matchChar = true
        if WR.curCharFilter ~= "all" and r.charName ~= WR.curCharFilter then
            matchChar = false
        end

        if matchTime and matchChar then
            r._rawIndex = i
            table.insert(filtered, r)
        end
    end

    return filtered
end

function WR.GetSummaryStats(records)
    local totalWage = 0
    local totalNet = 0
    local totalSubsidy = 0
    local totalSpend = 0
    local totalEquipSpend = 0
    local totalPenalty = 0
    local charStats = {}
    local runCount = #records

    for _, r in ipairs(records) do
        local w = r.wage or 0
        local net = r.netWage or 0
        local sub = r.subsidy or 0
        local eqSp = r.mySpend or 0
        local pen = r.penalty or 0
        local sp = eqSp + pen

        totalWage = totalWage + w
        totalNet = totalNet + net
        totalSubsidy = totalSubsidy + sub
        totalSpend = totalSpend + sp
        totalEquipSpend = totalEquipSpend + eqSp
        totalPenalty = totalPenalty + pen

        local charKey = r.charName or "未知"
        if not charStats[charKey] then
            charStats[charKey] = {
                charName = r.charName,
                class = r.class or "WARRIOR",
                wage = 0,
                runs = 0,
                spend = 0,
                equipSpend = 0,
                penalty = 0,
            }
        end
        charStats[charKey].wage = charStats[charKey].wage + w
        charStats[charKey].runs = charStats[charKey].runs + 1
        charStats[charKey].spend = charStats[charKey].spend + sp
        charStats[charKey].equipSpend = charStats[charKey].equipSpend + eqSp
        charStats[charKey].penalty = charStats[charKey].penalty + pen
    end

    local sortedChars = {}
    local sortedSpenderChars = {}
    for _, info in pairs(charStats) do
        table.insert(sortedChars, info)
        if info.spend > 0 then
            table.insert(sortedSpenderChars, info)
        end
    end
    table.sort(sortedChars, function(a, b) return a.wage > b.wage end)
    table.sort(sortedSpenderChars, function(a, b) return a.spend > b.spend end)

    local avgWage = (runCount > 0) and math.floor(totalWage / runCount) or 0
    local topChar = sortedChars[1]
    local topSpender = sortedSpenderChars[1]

    return {
        totalWage = totalWage,
        totalNet = totalNet,
        totalSubsidy = totalSubsidy,
        totalSpend = totalSpend,
        totalEquipSpend = totalEquipSpend,
        totalPenalty = totalPenalty,
        runCount = runCount,
        avgWage = avgWage,
        topChar = topChar,
        sortedChars = sortedChars,
        topSpender = topSpender,
        sortedSpenderChars = sortedSpenderChars,
    }
end

-------------------------------------------------------------------------------
-- 5. 主面板 UI 构建
-------------------------------------------------------------------------------
function WR.CreateUI(parent)
    if WR.MainFrame then return end
    WR.InitDB()

    local f = CreateFrame("Frame", "BG_WorkerReportMainFrame", parent or BG.MainFrame)
    f:SetAllPoints()
    f:Hide()
    WR.MainFrame = f

    -- 标题与提示标记
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 18, "OUTLINE")
    title:SetTextColor(RGB("00BFFF"))
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -35)
    title:SetText(L["团本报表"] or "团本报表")

    local tipsBtn = CreateFrame("Button", nil, f)
    tipsBtn:SetSize(18, 18)
    tipsBtn:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local tipsTex = tipsBtn:CreateTexture(nil, "ARTWORK")
    tipsTex:SetAllPoints()
    tipsTex:SetTexture(616343)
    tipsBtn:SetHighlightTexture(616343)

    local ICON_MOON  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:14:14:0:0|t"
    local ICON_TRI   = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:14:14:0:0|t"
    local ICON_GOLD  = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"
    local ICON_CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14:0:0|t"
    local ICON_CHECK = "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:14:14:0:0|t"

    tipsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["团本报表使用说明"] or "团本报表使用说明", 0, 0.75, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ICON_MOON .. " " .. (L["周期重置：每周四 07:00 自动结算重置 CD 周期。"] or "周期重置：每周四 07:00 自动结算重置 CD 周期。"), 1, 1, 1, true)
        GameTooltip:AddLine(ICON_TRI .. " " .. (L["实时感知：支持当前打本在途账单实时统计与历史账单动态聚合。"] or "实时感知：支持当前打本在途账单实时统计与历史账单动态聚合。"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(ICON_GOLD .. " " .. (L["资金总览：自动汇总名下所有角色的打工工资、补贴、自购装备与罚款支出。"] or "资金总览：自动汇总名下所有角色的打工工资、补贴、自购装备与罚款支出。"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(ICON_CROWN .. " " .. (L["波比兔出品：打造更清晰、更实用的团本打工收益与收支分析看板。"] or "波比兔出品：打造更清晰、更实用的团本打工收益与收支分析看板。"), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ICON_CHECK .. " " .. (L["如遇任何异常或有优化建议，欢迎前往  网易DD频道: 434056 交流反馈！"] or "如遇任何异常或有优化建议，欢迎前往  网易DD频道: 434056 交流反馈！"), 0.2, 1, 0.6, true)
        GameTooltip:Show()
    end)
    tipsBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    WR.tipsBtn = tipsBtn

    ---------------------------------------------------------------------------
    -- 顶部控制栏（周期切换、角色筛选、记一笔/补贴）
    ---------------------------------------------------------------------------
    -- 1. 周期切换下拉按钮
    local cycleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cycleBtn:SetSize(140, 24)
    cycleBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    cycleBtn:SetText(L["本周 CD"] or "本周 CD")
    WR.cycleBtn = cycleBtn

    local cycleDropDown = CreateFrame("Frame", "BG_WR_CycleDropDown", f, "UIDropDownMenuTemplate")
    local cycleList = {
        { text = L["本周 CD (当前)"] or "本周 CD (当前)", key = "current" },
        { text = L["上周 CD"] or "上周 CD", key = "last" },
        { text = L["近 30 天"] or "近 30 天", key = "month" },
        { text = L["全部历史"] or "全部历史", key = "all" },
    }
    cycleBtn:SetScript("OnClick", function()
        local menu = {}
        for _, item in ipairs(cycleList) do
            table.insert(menu, {
                text = item.text,
                checked = (WR.curWeekFilter == item.key),
                func = function()
                    WR.curWeekFilter = item.key
                    cycleBtn:SetText(item.text)
                    WR.UpdateUI()
                end,
            })
        end
        if LibBG and LibBG.EasyMenu then
            LibBG:EasyMenu(menu, cycleDropDown, "cursor", 0, 0, "MENU")
        else
            EasyMenu(menu, cycleDropDown, "cursor", 0, 0, "MENU")
        end
    end)

    -- 2. 角色筛选下拉按钮
    local charBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    charBtn:SetSize(120, 24)
    charBtn:SetPoint("LEFT", cycleBtn, "RIGHT", 10, 0)
    charBtn:SetText(L["全部角色"] or "全部角色")
    WR.charBtn = charBtn

    local charDropDown = CreateFrame("Frame", "BG_WR_CharDropDown", f, "UIDropDownMenuTemplate")
    charBtn:SetScript("OnClick", function()
        local menu = {
            {
                text = L["全部角色"] or "全部角色",
                checked = (WR.curCharFilter == "all"),
                func = function()
                    WR.curCharFilter = "all"
                    charBtn:SetText(L["全部角色"] or "全部角色")
                    WR.UpdateUI()
                end,
            }
        }
        -- 动态搜集所有打工角色
        local charSet = {}
        for _, r in ipairs(WR.GetAllRecords()) do
            if r.charName and not charSet[r.charName] then
                charSet[r.charName] = r.class or "WARRIOR"
            end
        end
        for cName, cClass in pairs(charSet) do
            table.insert(menu, {
                text = SetClassCFF(cName, cClass),
                checked = (WR.curCharFilter == cName),
                func = function()
                    WR.curCharFilter = cName
                    charBtn:SetText(cName)
                    WR.UpdateUI()
                end,
            })
        end
        if LibBG and LibBG.EasyMenu then
            LibBG:EasyMenu(menu, charDropDown, "cursor", 0, 0, "MENU")
        else
            EasyMenu(menu, charDropDown, "cursor", 0, 0, "MENU")
        end
    end)

    -- 3. 【+ 记一笔 / 补录补贴】按钮
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(130, 24)
    addBtn:SetPoint("LEFT", charBtn, "RIGHT", 15, 0)
    addBtn:SetText(L["+ 记一笔 / 补贴"] or "+ 记一笔 / 补贴")
    addBtn:SetScript("OnClick", function()
        WR.ShowManualAddModal()
    end)

    -- 4. 【战报分享】按钮 (放上面最后面，无前置文字)
    local shareBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    shareBtn:SetSize(100, 24)
    shareBtn:SetPoint("LEFT", addBtn, "RIGHT", 15, 0)
    shareBtn:SetText(L["战报分享"] or "战报分享")
    shareBtn:SetScript("OnClick", function()
        if WR.ShowShareModal then
            WR.ShowShareModal()
        end
    end)
    shareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["战报分享"] or "战报分享", 1, 0.84, 0)
        GameTooltip:AddLine(L["生成战报卡片，支持拍照/截图与多频道通报。"] or "生成战报卡片，支持拍照/截图与多频道通报。", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    WR.shareBtn = shareBtn

    ---------------------------------------------------------------------------
    -- 核心数据卡片区 (4 张看板大卡片)
    ---------------------------------------------------------------------------
    local cardWidth = 210
    local cardHeight = 70
    local cardSpacing = 12
    local totalCardWidth = (cardWidth * 4) + (cardSpacing * 3) -- 876px

    local function CreateMetricCard(name, pointX)
        local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
        card:SetSize(cardWidth, cardHeight)
        card:SetPoint("TOPLEFT", f, "TOPLEFT", pointX, -105)
        card:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        card:SetBackdropColor(0.08, 0.08, 0.12, 0.75)
        card:SetBackdropBorderColor(0.25, 0.45, 0.7, 0.6)

        local titleStr = card:CreateFontString(nil, "OVERLAY")
        titleStr:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        titleStr:SetTextColor(RGB("AAAAAA"))
        titleStr:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)

        local valStr = card:CreateFontString(nil, "OVERLAY")
        valStr:SetFont(BIAOGE_TEXT_FONT, 19, "OUTLINE")
        valStr:SetTextColor(RGB("FFD700"))
        valStr:SetPoint("TOPLEFT", titleStr, "BOTTOMLEFT", 0, -4)
        valStr:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        valStr:SetJustifyH("LEFT")
        valStr:SetWordWrap(false)

        local subStr = card:CreateFontString(nil, "OVERLAY")
        subStr:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        subStr:SetTextColor(RGB("88CC88"))
        subStr:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
        subStr:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        subStr:SetJustifyH("LEFT")
        subStr:SetWordWrap(false)

        return { frame = card, title = titleStr, val = valStr, sub = subStr }
    end

    WR.card1 = CreateMetricCard("card1", 30)
    WR.card1.title:SetText(L["累计工资收入"] or "累计工资收入")

    WR.card2 = CreateMetricCard("card2", 30 + cardWidth + cardSpacing)
    WR.card2.title:SetText(L["打工吸金榜首 (劳模)"] or "打工吸金榜首 (劳模)")

    WR.card3 = CreateMetricCard("card3", 30 + (cardWidth + cardSpacing) * 2)
    WR.card3.title:SetText(L["累计总支出"] or "累计总支出")

    WR.card4 = CreateMetricCard("card4", 30 + (cardWidth + cardSpacing) * 3)
    WR.card4.title:SetText(L["单车效率 / 实际净到手"] or "单车效率 / 实际净到手")

    ---------------------------------------------------------------------------
    -- 多角色贡献度可视化条 (彩色横向进度条)
    ---------------------------------------------------------------------------
    local barContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    barContainer:SetSize(totalCardWidth, 28)
    barContainer:SetPoint("TOPLEFT", WR.card1.frame, "BOTTOMLEFT", 0, -12)
    barContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    barContainer:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
    barContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    WR.barContainer = barContainer

    WR.charBars = {}
    for i = 1, 15 do
        local bar = barContainer:CreateTexture(nil, "ARTWORK")
        bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:Hide()
        WR.charBars[i] = bar
    end

    local barLegend = f:CreateFontString(nil, "OVERLAY")
    barLegend:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    barLegend:SetTextColor(RGB("CCCCCC"))
    barLegend:SetPoint("TOPLEFT", barContainer, "BOTTOMLEFT", 0, -4)
    barLegend:SetJustifyH("LEFT")
    barLegend:SetWidth(totalCardWidth)
    WR.barLegend = barLegend

    ---------------------------------------------------------------------------
    -- 明细流水滚动列表
    ---------------------------------------------------------------------------
    local listTitle = f:CreateFontString(nil, "OVERLAY")
    listTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    listTitle:SetTextColor(RGB("00BFFF"))
    listTitle:SetPoint("TOPLEFT", barLegend, "BOTTOMLEFT", 0, -8)
    listTitle:SetText(L["打工与收支明细"] or "打工与收支明细")

    local scrollFrame = CreateFrame("ScrollFrame", "BG_WR_ScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -22)
    scrollFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 30, 20)
    scrollFrame:SetWidth(totalCardWidth - 20)
    scrollFrame.ScrollBar.scrollStep = BG.scrollStep or 25
    if BG.CreateSrollBarBackdrop then
        BG.CreateSrollBarBackdrop(scrollFrame.ScrollBar)
    end

    -- 表头
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("BOTTOMLEFT", scrollFrame, "TOPLEFT", 0, 2)
    header:SetSize(totalCardWidth - 20, 20)

    local cols = {
        { title = L["时间"] or "时间", width = 75, x = 5 },
        { title = L["角色"] or "角色", width = 95, x = 85 },
        { title = L["副本"] or "副本", width = 110, x = 185 },
        { title = L["规模/流水"] or "规模/流水", width = 125, x = 300 },
        { title = L["分得工资"] or "分得工资", width = 90, x = 430 },
        { title = L["补贴"] or "补贴", width = 65, x = 525 },
        { title = L["支出"] or "支出", width = 75, x = 595 },
        { title = L["净落袋"] or "净落袋", width = 85, x = 675 },
        { title = L["操作"] or "操作", width = 60, x = 765 },
    }

    for _, c in ipairs(cols) do
        local ht = header:CreateFontString(nil, "OVERLAY")
        ht:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        ht:SetTextColor(RGB("AAAAAA"))
        ht:SetPoint("LEFT", header, "LEFT", c.x, 0)
        ht:SetText(c.title)
    end

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(totalCardWidth - 20, 1)
    scrollFrame:SetScrollChild(content)
    WR.content = content

    -- 动态创建行支持长列表与外框高度自适应
    WR.rowFrames = {}
    local function GetOrCreateRow(i)
        if WR.rowFrames[i] then
            return WR.rowFrames[i]
        end

        local r = CreateFrame("Frame", nil, content, "BackdropTemplate")
        r:SetSize(totalCardWidth - 20, 24)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * 25)
        r:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = true, tileSize = 16,
        })
        if i % 2 == 0 then
            r:SetBackdropColor(0.1, 0.1, 0.14, 0.4)
        else
            r:SetBackdropColor(0.06, 0.06, 0.09, 0.3)
        end

        -- 时间可点击校准按钮
        local timeBtn = CreateFrame("Button", nil, r)
        timeBtn:SetSize(75, 20)
        timeBtn:SetPoint("LEFT", r, "LEFT", 5, 0)
        local timeText = timeBtn:CreateFontString(nil, "OVERLAY")
        timeText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        timeText:SetTextColor(RGB("888888"))
        timeText:SetPoint("LEFT", timeBtn, "LEFT", 0, 0)
        timeBtn:SetScript("OnClick", function()
            if r.recordData and WR.ShowEditRecordModal then
                WR.ShowEditRecordModal(r.recordData)
            end
        end)
        timeBtn:SetScript("OnEnter", function(self)
            timeText:SetTextColor(RGB("00BFFF"))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["编辑账单与打本时间"] or "编辑账单与打本时间", 0, 0.75, 1)
            GameTooltip:AddLine(L["点击可编辑分得工资、补贴、装备消费、罚款及真实打本时间。"] or "点击可编辑分得工资、补贴、装备消费、罚款及真实打本时间。", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        timeBtn:SetScript("OnLeave", function()
            timeText:SetTextColor(RGB("888888"))
            GameTooltip:Hide()
        end)
        r.timeBtn = timeBtn
        r.timeText = timeText

        r.charText = r:CreateFontString(nil, "OVERLAY")
        r.charText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.charText:SetPoint("LEFT", r, "LEFT", 85, 0)

        r.fbText = r:CreateFontString(nil, "OVERLAY")
        r.fbText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.fbText:SetTextColor(RGB("FFFFFF"))
        r.fbText:SetPoint("LEFT", r, "LEFT", 185, 0)

        r.grossText = r:CreateFontString(nil, "OVERLAY")
        r.grossText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.grossText:SetTextColor(RGB("AAAAAA"))
        r.grossText:SetPoint("LEFT", r, "LEFT", 300, 0)

        r.wageText = r:CreateFontString(nil, "OVERLAY")
        r.wageText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        r.wageText:SetTextColor(RGB("00FF00"))
        r.wageText:SetPoint("LEFT", r, "LEFT", 430, 0)

        r.subsidyText = r:CreateFontString(nil, "OVERLAY")
        r.subsidyText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.subsidyText:SetTextColor(RGB("FFCC00"))
        r.subsidyText:SetPoint("LEFT", r, "LEFT", 525, 0)

        r.spendText = r:CreateFontString(nil, "OVERLAY")
        r.spendText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.spendText:SetTextColor(RGB("FF6B6B"))
        r.spendText:SetPoint("LEFT", r, "LEFT", 595, 0)

        r.netText = r:CreateFontString(nil, "OVERLAY")
        r.netText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        r.netText:SetTextColor(RGB("00FF7F"))
        r.netText:SetPoint("LEFT", r, "LEFT", 675, 0)

        -- 编辑账单/校准时间按钮
        local editBtn = CreateFrame("Button", nil, r)
        editBtn:SetSize(16, 16)
        editBtn:SetPoint("LEFT", r, "LEFT", 765, 0)
        editBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildScheduler-Edit-Up")
        editBtn:SetHighlightTexture("Interface\\Buttons\\UI-GuildScheduler-Edit-Highlight")
        editBtn:SetScript("OnClick", function()
            if r.recordData and WR.ShowEditRecordModal then
                WR.ShowEditRecordModal(r.recordData)
            end
        end)
        editBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["编辑账单明细"] or "编辑账单明细", 0, 0.75, 1)
            GameTooltip:AddLine(L["点击可修改该笔记录的工资、补贴、装备消费、罚款与打本时间。"] or "点击可修改该笔记录的工资、补贴、装备消费、罚款与打本时间。", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        editBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.editBtn = editBtn

        -- 删除手工补录按钮 (仅对手工录入显示)
        local delBtn = CreateFrame("Button", nil, r)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("LEFT", r, "LEFT", 790, 0)
        delBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        delBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        delBtn:SetScript("OnClick", function()
            if r.recordData then
                WR.DeleteRecord(r.recordData)
            end
        end)
        delBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["删除手工补录"] or "删除手工补录", 1, 0.2, 0.2)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.delBtn = delBtn

        WR.rowFrames[i] = r
        return r
    end
    WR.GetOrCreateRow = GetOrCreateRow

    -- 默认预创 50 行以减少首屏加载微卡顿
    for i = 1, 50 do
        GetOrCreateRow(i)
    end

    f:SetScript("OnShow", function()
        WR.UpdateUI()
    end)
end

-------------------------------------------------------------------------------
-- 6. UI 数据刷新
-------------------------------------------------------------------------------
function WR.UpdateUI()
    if not (WR.MainFrame and WR.MainFrame:IsShown()) then return end

    local records = WR.GetFilteredRecords()
    local stats = WR.GetSummaryStats(records)

    -- 更新四大卡片
    -- 卡片1：总收入
    WR.card1.val:SetText(FormatMoney(stats.totalWage))
    local weekRangeStr = (WR.curWeekFilter == "current") and WR.GetCDWeekDesc(0) or ((WR.curWeekFilter == "last") and WR.GetCDWeekDesc(-1) or "")
    WR.card1.sub:SetText(string.format(L["共出勤 %d 车 %s"] or "共出勤 %d 车 %s", stats.runCount, weekRangeStr ~= "" and ("(" .. weekRangeStr .. ")") or ""))

    -- 卡片2：劳模
    if stats.topChar then
        local pct = (stats.totalWage > 0) and math.floor(stats.topChar.wage / stats.totalWage * 100) or 0
        WR.card2.val:SetText(SetClassCFF(stats.topChar.charName, stats.topChar.class))
        WR.card2.sub:SetText(string.format(L["贡献 %s (占比 %d%%, %d车)"] or "贡献 %s (占比 %d%%, %d车)", FormatMoney(stats.topChar.wage), pct, stats.topChar.runs))
    else
        WR.card2.val:SetText(L["暂无数据"] or "暂无数据")
        WR.card2.sub:SetText(L["打本保存表格后自动入账"] or "打本保存表格后自动入账")
    end

    -- 卡片3：累计总支出与消费榜首
    if (stats.totalSpend or 0) > 0 then
        WR.card3.val:SetTextColor(RGB("FF6B6B"))
        WR.card3.val:SetText(string.format("-%s", FormatMoney(stats.totalSpend)))
        if stats.topSpender and stats.topSpender.spend > 0 then
            local spPct = math.floor(stats.topSpender.spend / stats.totalSpend * 100)
            WR.card3.sub:SetTextColor(RGB("FFB088"))
            WR.card3.sub:SetText(string.format(L["消费最多: %s (%s, %d%%)"] or "消费最多: %s (%s, %d%%)", SetClassCFF(stats.topSpender.charName, stats.topSpender.class), FormatMoney(stats.topSpender.spend), spPct))
        else
            WR.card3.sub:SetTextColor(RGB("888888"))
            WR.card3.sub:SetText(L["暂无大额消费记录"] or "暂无大额消费记录")
        end
    else
        WR.card3.val:SetTextColor(RGB("888888"))
        WR.card3.val:SetText("0 G")
        WR.card3.sub:SetTextColor(RGB("888888"))
        WR.card3.sub:SetText(L["暂无装备自购与罚款支出"] or "暂无装备自购与罚款支出")
    end

    WR.card3.frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["累计总支出明细"] or "累计总支出明细", 1, 0.4, 0.4)
        GameTooltip:AddLine(string.format(L["总计支出: -%s"] or "总计支出: -%s", FormatMoney(stats.totalSpend or 0)), 1, 0.8, 0.8)
        GameTooltip:AddLine(string.format(L["装备自购: -%s"] or "装备自购: -%s", FormatMoney(stats.totalEquipSpend or 0)), 0.9, 0.9, 0.9)
        GameTooltip:AddLine(string.format(L["罚款支出: -%s"] or "罚款支出: -%s", FormatMoney(stats.totalPenalty or 0)), 0.9, 0.9, 0.9)
        if stats.sortedSpenderChars and #stats.sortedSpenderChars > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["各角色消费排行:"] or "各角色消费排行:", 1, 0.8, 0)
            for rank, sp in ipairs(stats.sortedSpenderChars) do
                if rank <= 5 then
                    local pct = (stats.totalSpend > 0) and math.floor(sp.spend / stats.totalSpend * 100) or 0
                    GameTooltip:AddDoubleLine(
                        string.format("%d. %s", rank, SetClassCFF(sp.charName, sp.class)),
                        string.format("-%s (%d%%)", FormatMoney(sp.spend), pct),
                        1, 1, 1, 1, 0.5, 0.5
                    )
                end
            end
        end
        GameTooltip:Show()
    end)
    WR.card3.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 卡片4：效率与净到手
    WR.card4.val:SetText(string.format("%s/车", FormatMoney(stats.avgWage)))
    WR.card4.sub:SetText(string.format(L["净落袋: %s (补贴: %s)"] or "净落袋: %s (补贴: %s)", FormatMoney(stats.totalNet), FormatMoney(stats.totalSubsidy)))

    -- 更新多角色占比彩条
    local totalBarWidth = WR.barContainer:GetWidth() - 4
    local currentX = 2
    local legendParts = {}

    for i = 1, #WR.charBars do
        WR.charBars[i]:Hide()
    end

    if stats.totalWage > 0 and #stats.sortedChars > 0 then
        for i, c in ipairs(stats.sortedChars) do
            if i <= #WR.charBars then
                local bar = WR.charBars[i]
                local ratio = c.wage / stats.totalWage
                local w = math.max(2, math.floor(totalBarWidth * ratio))
                local r, g, b = GetClassRGB(c.class)
                bar:SetVertexColor(r, g, b, 0.9)
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", WR.barContainer, "TOPLEFT", currentX, -2)
                bar:SetSize(w, WR.barContainer:GetHeight() - 4)
                bar:Show()
                currentX = currentX + w

                local pct = math.floor(ratio * 100)
                table.insert(legendParts, string.format("%s %d%%", SetClassCFF(c.charName, c.class), pct))
            end
        end
        WR.barLegend:SetText(table.concat(legendParts, "  |  "))
    else
        WR.barLegend:SetText(L["当前周期内暂无打工收益记录"] or "当前周期内暂无打工收益记录")
    end

    -- 更新滚动流水
    local rowHeight = 25
    local totalRows = #records
    WR.content:SetHeight(math.max(1, totalRows * rowHeight))

    for i = 1, #records do
        local r = (WR.GetOrCreateRow and WR.GetOrCreateRow(i)) or WR.rowFrames[i]
        local data = records[i]
        if r and data then
            r.recordData = data
            r.recordIndex = data._rawIndex
            r.timeText:SetText(date("%m/%d %H:%M", data.timestamp))
            r.charText:SetText(SetClassCFF(data.charName, data.class))
            r.fbText:SetText(data.fbName or data.fb or "")
            if data.grossMoney and data.grossMoney > 0 then
                r.grossText:SetText(string.format("%d人 | %s", data.totalPeople or 0, FormatMoney(data.grossMoney)))
            elseif data.totalPeople and data.totalPeople > 0 then
                r.grossText:SetText(string.format("%d人", data.totalPeople))
            else
                r.grossText:SetText("-")
            end
            r.wageText:SetText(string.format("+%d G", data.wage or 0))

            if data.subsidy and data.subsidy > 0 then
                r.subsidyText:SetText(string.format("+%d", data.subsidy))
            else
                r.subsidyText:SetText("-")
            end

            local spend = (data.mySpend or 0) + (data.penalty or 0)
            if spend > 0 then
                r.spendText:SetTextColor(RGB("FF6B6B"))
                r.spendText:SetText(string.format("-%d", spend))
            else
                r.spendText:SetTextColor(RGB("666666"))
                r.spendText:SetText("-")
            end

            if data.netWage then
                if data.netWage >= 0 then
                    r.netText:SetTextColor(RGB("00FF7F"))
                    r.netText:SetText(string.format("+%d", data.netWage))
                else
                    r.netText:SetTextColor(RGB("FF4500"))
                    r.netText:SetText(string.format("%d", data.netWage))
                end
            else
                r.netText:SetText("-")
            end

            -- 操作列：手工录入显示删除按钮与修改按钮；历史账单受保护仅显示校准时间按钮
            if data.source == "manual" then
                r.delBtn:Show()
                r.editBtn:ClearAllPoints()
                r.editBtn:SetPoint("LEFT", r, "LEFT", 765, 0)
            else
                r.delBtn:Hide()
                r.editBtn:ClearAllPoints()
                r.editBtn:SetPoint("LEFT", r, "LEFT", 775, 0)
            end
            r.editBtn:Show()

            r:SetScript("OnEnter", function(self)
                if not self.recordData then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local d = self.recordData
                GameTooltip:AddLine(string.format("%s (%s)", d.fbName or d.fb, date("%Y-%m-%d %H:%M:%S", d.timestamp)), 0, 0.75, 1)
                GameTooltip:AddLine(string.format(L["打工角色: %s"] or "打工角色: %s", SetClassCFF(d.charName, d.class)), 1, 1, 1)
                GameTooltip:AddLine(string.format(L["工资收入: +%d G"] or "工资收入: +%d G", d.wage or 0), 0, 1, 0)
                if d.subsidy and d.subsidy > 0 then
                    GameTooltip:AddLine(string.format(L["获得补贴: +%d G"] or "获得补贴: +%d G", d.subsidy), 1, 0.8, 0)
                end
                local rSpend = (d.mySpend or 0) + (d.penalty or 0)
                if rSpend > 0 then
                    if (d.mySpend or 0) > 0 and (d.penalty or 0) > 0 then
                        GameTooltip:AddLine(string.format(L["本场支出: -%d G (装备%d, 罚款%d)"] or "本场支出: -%d G (装备%d, 罚款%d)", rSpend, d.mySpend, d.penalty), 1, 0.4, 0.4)
                    elseif (d.mySpend or 0) > 0 then
                        GameTooltip:AddLine(string.format(L["装备消费: -%d G"] or "装备消费: -%d G", d.mySpend), 1, 0.3, 0.3)
                    elseif (d.penalty or 0) > 0 then
                        GameTooltip:AddLine(string.format(L["罚款扣减: -%d G"] or "罚款扣减: -%d G", d.penalty), 1, 0.5, 0.2)
                    end
                end
                GameTooltip:AddLine(string.format(L["净落袋: %d G"] or "净落袋: %d G", d.netWage or d.wage or 0), 0, 1, 0.5)
                if d.grossMoney and d.grossMoney > 0 then
                    GameTooltip:AddLine(string.format(L["全团流水: %s (%d人)"] or "全团流水: %s (%d人)", FormatMoney(d.grossMoney), d.totalPeople or 0), 0.8, 0.8, 0.8)
                end
                if d.note and d.note ~= "" then
                    GameTooltip:AddLine(string.format(L["来源/备注: %s"] or "来源/备注: %s", d.note), 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine(L["提示: 点击时间或右侧按钮可修改收支、补贴与打本时间"] or "提示: 点击时间或右侧按钮可修改收支、补贴与打本时间", 0, 0.75, 1)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)

            r:Show()
        end
    end

    for i = #records + 1, #WR.rowFrames do
        local r = WR.rowFrames[i]
        if r then
            r.recordData = nil
            r:SetScript("OnEnter", nil)
            r:SetScript("OnLeave", nil)
            r:Hide()
        end
    end
end

-------------------------------------------------------------------------------
-- 7. 详细账单与收支编辑弹窗 (分得工资、补贴、装备消费、罚款、时间)
-------------------------------------------------------------------------------
function WR.ShowEditRecordModal(record)
    if not record then return end
    if not WR.EditRecordModal then
        local f = CreateFrame("Frame", "BG_WR_EditRecordModal", UIParent, "BackdropTemplate")
        f:SetSize(380, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        f:SetBackdropBorderColor(0, 0.75, 1, 0.8)

        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        title:SetTextColor(RGB("00BFFF"))
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
        title:SetText(L["编辑收支与账单明细"] or "编辑收支与账单明细")
        f.title = title

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

        local desc = f:CreateFontString(nil, "OVERLAY")
        desc:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        desc:SetTextColor(RGB("CCCCCC"))
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        f.desc = desc

        -- 快捷预设按钮组：今天、昨天、前天、上周四
        local quickTitle = f:CreateFontString(nil, "OVERLAY")
        quickTitle:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        quickTitle:SetTextColor(RGB("888888"))
        quickTitle:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
        quickTitle:SetText(L["快捷日期:"] or "快捷日期:")

        local btnToday = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnToday:SetSize(48, 20)
        btnToday:SetPoint("LEFT", quickTitle, "RIGHT", 6, 0)
        btnToday:SetText(L["今天"] or "今天")

        local btnYesterday = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnYesterday:SetSize(48, 20)
        btnYesterday:SetPoint("LEFT", btnToday, "RIGHT", 4, 0)
        btnYesterday:SetText(L["昨天"] or "昨天")

        local btnBeforeYesterday = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnBeforeYesterday:SetSize(48, 20)
        btnBeforeYesterday:SetPoint("LEFT", btnYesterday, "RIGHT", 4, 0)
        btnBeforeYesterday:SetText(L["前天"] or "前天")

        local btnLastThu = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnLastThu:SetSize(56, 20)
        btnLastThu:SetPoint("LEFT", btnBeforeYesterday, "RIGHT", 4, 0)
        btnLastThu:SetText(L["上周四"] or "上周四")

        -- 输入项工厂函数
        local function CreateRowInput(labelText, yOffset)
            local lbl = f:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
            lbl:SetTextColor(RGB("AAAAAA"))
            lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 20, yOffset)
            lbl:SetText(labelText)

            local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
            eb:SetSize(180, 20)
            eb:SetPoint("LEFT", lbl, "LEFT", 110, 0)
            eb:SetAutoFocus(false)
            return eb
        end

        local timeEB = CreateRowInput(L["打本时间:"] or "打本时间:", -88)
        local wageEB = CreateRowInput(L["分得工资 (G):"] or "分得工资 (G):", -118)
        local subEB = CreateRowInput(L["额外补贴 (G):"] or "额外补贴 (G):", -148)
        local spendEB = CreateRowInput(L["装备消费 (G):"] or "装备消费 (G):", -178)
        local penaltyEB = CreateRowInput(L["罚款支出 (G):"] or "罚款支出 (G):", -208)
        local grossEB = CreateRowInput(L["全团总流水 (G):"] or "全团总流水 (G):", -238)

        f.timeEB = timeEB
        f.wageEB = wageEB
        f.subEB = subEB
        f.spendEB = spendEB
        f.penaltyEB = penaltyEB
        f.grossEB = grossEB

        -- 净到手计算预览
        local netPreview = f:CreateFontString(nil, "OVERLAY")
        netPreview:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        netPreview:SetTextColor(RGB("00FF7F"))
        netPreview:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -270)
        f.netPreview = netPreview

        local function UpdateNetPreview()
            local w = tonumber(wageEB:GetText()) or 0
            local sub = tonumber(subEB:GetText()) or 0
            local sp = tonumber(spendEB:GetText()) or 0
            local pen = tonumber(penaltyEB:GetText()) or 0
            local net = w + sub - pen - sp
            netPreview:SetText(string.format(L["净到手计算: %d G (工资%d + 补贴%d - 消费%d - 罚款%d)"] or "净到手计算: %d G (工资%d + 补贴%d - 消费%d - 罚款%d)", net, w, sub, sp, pen))
        end

        wageEB:SetScript("OnTextChanged", UpdateNetPreview)
        subEB:SetScript("OnTextChanged", UpdateNetPreview)
        spendEB:SetScript("OnTextChanged", UpdateNetPreview)
        penaltyEB:SetScript("OnTextChanged", UpdateNetPreview)

        -- 快捷预设事件
        btnToday:SetScript("OnClick", function() timeEB:SetText(date("%Y-%m-%d %H:%M", time())) end)
        btnYesterday:SetScript("OnClick", function() timeEB:SetText(date("%Y-%m-%d %H:%M", time() - 86400)) end)
        btnBeforeYesterday:SetScript("OnClick", function() timeEB:SetText(date("%Y-%m-%d %H:%M", time() - 86400 * 2)) end)
        btnLastThu:SetScript("OnClick", function()
            local curWeekStart = WR.GetCDWeekStart(time())
            local lastThu20 = curWeekStart - 7 * 86400 + (13 * 3600)
            timeEB:SetText(date("%Y-%m-%d %H:%M", lastThu20))
        end)

        -- 解析输入时间
        local function ParseInputToTs(str)
            if not str then return nil end
            local y, m, d, h, mi = str:match("(%d+)[%-%/](%d+)[%-%/](%d+)%s+(%d+):(%d+)")
            if y and m and d and h and mi then
                local ok, ts = pcall(time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
                return ok and ts or nil
            end
            return nil
        end

        -- 保存按钮
        local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        saveBtn:SetSize(100, 26)
        saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 60, 16)
        saveBtn:SetText(L["保存更改"] or "保存更改")

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 26)
        cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -60, 16)
        cancelBtn:SetText(L["取消"] or "取消")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        saveBtn:SetScript("OnClick", function()
            if not f.targetRecord then return end
            local ts = ParseInputToTs(timeEB:GetText())
            if not ts then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. (L["日期时间格式错误，请输入如: 2026-09-20 20:30"] or "日期时间格式错误，请输入如: 2026-09-20 20:30"))
                return
            end
            local w = tonumber(wageEB:GetText()) or 0
            local sub = tonumber(subEB:GetText()) or 0
            local sp = tonumber(spendEB:GetText()) or 0
            local pen = tonumber(penaltyEB:GetText()) or 0
            local gross = tonumber(grossEB:GetText()) or 0

            WR.SaveRecordAdjustment(f.targetRecord, w, sub, sp, pen, gross, ts)
            f:Hide()
        end)

        WR.EditRecordModal = f
    end

    local f = WR.EditRecordModal
    f.targetRecord = record
    f.title:SetText(string.format(L["编辑收支明细 - %s"] or "编辑收支明细 - %s", record.fbName or record.fb or "团本"))
    f.desc:SetText(string.format(L["角色: %s | 来源: %s"] or "角色: %s | 来源: %s", SetClassCFF(record.charName, record.class), (record.source == "manual" and "手工记录") or ((record.source == "history" and "历史存档") or "当前账单")))
    f.timeEB:SetText(date("%Y-%m-%d %H:%M", record.timestamp or time()))
    f.wageEB:SetText(tostring(record.wage or 0))
    f.subEB:SetText(tostring(record.subsidy or 0))
    f.spendEB:SetText(tostring(record.mySpend or 0))
    f.penaltyEB:SetText(tostring(record.penalty or 0))
    f.grossEB:SetText(tostring(record.grossMoney or 0))

    local net = (record.wage or 0) + (record.subsidy or 0) - (record.penalty or 0) - (record.mySpend or 0)
    f.netPreview:SetText(string.format(L["净到手计算: %d G"] or "净到手计算: %d G", net))
    f:Show()
end
WR.ShowEditTimeModal = WR.ShowEditRecordModal

-------------------------------------------------------------------------------
-- 8. 手工记一笔 / 补录补贴与收支弹窗
-------------------------------------------------------------------------------
function WR.ShowManualAddModal()
    if WR.ModalFrame then
        WR.ModalFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "BG_WR_ManualModal", UIParent, "BackdropTemplate")
    f:SetSize(360, 330)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.1, 0.1, 0.15, 0.95)
    f:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
    WR.ModalFrame = f

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    title:SetTextColor(RGB("00BFFF"))
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText(L["补录打工收益 / 资金流水"] or "补录打工收益 / 资金流水")

    local function CreateInput(labelText, yOffset, defaultVal)
        local lbl = f:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        lbl:SetTextColor(RGB("CCCCCC"))
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 25, yOffset)
        lbl:SetText(labelText)

        local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        eb:SetSize(160, 20)
        eb:SetPoint("LEFT", lbl, "LEFT", 120, 0)
        eb:SetAutoFocus(false)
        eb:SetText(defaultVal or "")
        return eb
    end

    local curDefaultFB = (BG.FB1 and GetFBDisplayName(BG.FB1)) or "奥杜尔"
    local charEB = CreateInput(L["角色名称:"] or "角色名称:", -45, UnitName("player"))
    local fbEB = CreateInput(L["副本名称:"] or "副本名称:", -75, curDefaultFB)
    local wageEB = CreateInput(L["分得工资 (G):"] or "分得工资 (G):", -105, "0")
    local subEB = CreateInput(L["额外补贴 (G):"] or "额外补贴 (G):", -135, "0")
    local spendEB = CreateInput(L["装备消费 (G):"] or "装备消费 (G):", -165, "0")
    local penaltyEB = CreateInput(L["罚款支出 (G):"] or "罚款支出 (G):", -195, "0")
    local grossEB = CreateInput(L["全团流水 (G):"] or "全团流水 (G):", -225, "0")
    local noteEB = CreateInput(L["打工备注:"] or "打工备注:", -255, L["TN补贴/野团全通"] or "TN补贴/野团全通")

    -- 确定与取消按钮
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 24)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 55, 14)
    saveBtn:SetText(L["保存入账"] or "保存入账")
    saveBtn:SetScript("OnClick", function()
        local cName = charEB:GetText()
        local fbName = fbEB:GetText()
        local wage = tonumber(wageEB:GetText()) or 0
        local subsidy = tonumber(subEB:GetText()) or 0
        local mySpend = tonumber(spendEB:GetText()) or 0
        local penalty = tonumber(penaltyEB:GetText()) or 0
        local gross = tonumber(grossEB:GetText()) or 0
        local note = noteEB:GetText()

        if wage <= 0 and subsidy <= 0 and mySpend <= 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. (L["工资、补贴和消费不能全部为0！"] or "工资、补贴和消费不能全部为0！"))
            return
        end

        WR.AddRecord({
            timestamp = time(),
            charName = (cName ~= "") and cName or UnitName("player"),
            class = select(2, UnitClass("player")) or "WARRIOR",
            realm = GetRealmName(),
            fb = fbName,
            fbName = fbName,
            totalPeople = 25,
            grossMoney = gross,
            wage = wage,
            subsidy = subsidy,
            mySpend = mySpend,
            penalty = penalty,
            note = note,
            source = "manual",
        })

        local net = wage + subsidy - penalty - mySpend
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. string.format(L["已成功补录流水: %s (净到手: %d G)"] or "已成功补录流水: %s (净到手: %d G)", fbName, net))
        f:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -55, 14)
    cancelBtn:SetText(L["取消"] or "取消")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f:Show()
end

-------------------------------------------------------------------------------
-- 9. 战报分享卡片面板 (Share Card Modal) + 多频道通报引擎
-------------------------------------------------------------------------------
local CHANNELS = {
    { text = L["团队频道 (RAID)"] or "团队频道 (RAID)", channel = "RAID" },
    { text = L["小队频道 (PARTY)"] or "小队频道 (PARTY)", channel = "PARTY" },
    { text = L["公会频道 (GUILD)"] or "公会频道 (GUILD)", channel = "GUILD" },
    { text = L["大喊频道 (YELL)"] or "大喊频道 (YELL)", channel = "YELL" },
    { text = L["说话频道 (SAY)"] or "说话频道 (SAY)", channel = "SAY" },
    { text = L["自我打印 (仅自己可见)"] or "自我打印 (仅自己可见)", channel = "SELF" },
}

function WR.SendBroadcastToChannel(channel)
    local records = WR.GetFilteredRecords()
    local stats = WR.GetSummaryStats(records)

    if stats.runCount == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. (L["当前筛选周期内暂无战报数据可供分享。"] or "当前筛选周期内暂无战报数据可供分享。"))
        return
    end

    local periodName = (WR.curWeekFilter == "current") and (L["本周CD"] or "本周CD") or ((WR.curWeekFilter == "last") and (L["上周CD"] or "上周CD") or (L["阶段"] or "阶段"))
    local weekRange = (WR.curWeekFilter == "current") and WR.GetCDWeekDesc(0) or ((WR.curWeekFilter == "last") and WR.GetCDWeekDesc(-1) or "")
    if weekRange ~= "" then periodName = string.format("%s (%s)", periodName, weekRange) end

    local lines = {}
    -- 1. 抬头
    table.insert(lines, string.format("【BGLite_Plus 波比兔】团本报表 - %s", periodName))

    -- 2. 出勤统计
    table.insert(lines, string.format("出勤统计: %d 车 (均薪: %s/车)", stats.runCount, FormatMoney(stats.avgWage)))

    -- 3. 总计工资
    local subDesc = ""
    if (stats.totalSubsidy or 0) > 0 then
        subDesc = string.format(" (含补贴 +%s)", FormatMoney(stats.totalSubsidy))
    end
    table.insert(lines, string.format("总计工资: %s%s", FormatMoney(stats.totalWage), subDesc))

    -- 4. 累计支出
    if (stats.totalSpend or 0) > 0 then
        local spenderDesc = ""
        if stats.topSpender and stats.topSpender.spend > 0 then
            spenderDesc = string.format(" (消费最多: %s)", stats.topSpender.charName)
        end
        table.insert(lines, string.format("累计支出: -%s%s", FormatMoney(stats.totalSpend), spenderDesc))
    else
        table.insert(lines, "累计支出: 0G (无额外消费)")
    end

    -- 5. 实际到手
    table.insert(lines, string.format("实际到手: %s", FormatMoney(stats.totalNet)))

    -- 6. 吸金榜首
    if stats.topChar then
        local pct = (stats.totalWage > 0) and math.floor(stats.topChar.wage / stats.totalWage * 100) or 0
        table.insert(lines, string.format("吸金榜首: %s (%s, 占比 %d%%, %d车)", stats.topChar.charName, FormatMoney(stats.topChar.wage), pct, stats.topChar.runs))
    end

    -- 7. 励志寄语与品牌后缀
    table.insert(lines, "每一份付出都有回响，愿艾泽拉斯的金币与荣耀与你常伴！[BGLite Plus(波比兔)-团本报表]")

    local function SanitizeChatLine(text)
        if not text then return "" end
        -- 消除独立的单竖线字符，防止魔兽官方聊天转义器抛出 "Invalid escape code in chat message"
        text = text:gsub("||", "\001")
        text = text:gsub("|", "/")
        text = text:gsub("\001", "/")
        text = text:gsub("[\r\n]+", " ")
        return text
    end

    if channel == "SELF" then
        for _, line in ipairs(lines) do
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. line .. "|r")
        end
    else
        if channel == "RAID" and not IsInRaid() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r |cffff5555" .. (L["您当前不在团队中，无法发送团队战报，已为您在本地聊天框展示："] or "您当前不在团队中，无法发送团队战报，已为您在本地聊天框展示：") .. "|r")
            for _, line in ipairs(lines) do
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. line .. "|r")
            end
            return
        elseif channel == "PARTY" and not IsInGroup() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r |cffff5555" .. (L["您当前不在队伍中，无法发送小队战报，已为您在本地聊天框展示："] or "您当前不在队伍中，无法发送小队战报，已为您在本地聊天框展示：") .. "|r")
            for _, line in ipairs(lines) do
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. line .. "|r")
            end
            return
        elseif channel == "GUILD" and not IsInGuild() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r |cffff5555" .. (L["您当前没有公会，无法发送公会战报，已为您在本地聊天框展示："] or "您当前没有公会，无法发送公会战报，已为您在本地聊天框展示：") .. "|r")
            for _, line in ipairs(lines) do
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. line .. "|r")
            end
            return
        end

        -- 有序队列发送机制：每行之间留 0.25 秒安全间隔，确保第 1 句抬头、第 2 句数据、第 3 句寄语绝对按顺序送达，且不触发限流
        local function SendNext(idx)
            if idx > #lines then
                local chName = _G[channel] or (channel == "YELL" and "大喊") or (channel == "SAY" and "说") or channel
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. string.format(L["战报已发送至频道: %s"] or "战报已发送至频道: %s", chName))
                return
            end

            local safeLine = SanitizeChatLine(lines[idx])
            local ok, err = pcall(SendChatMessage, safeLine, channel)
            if not ok then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[BGLite_Plus 波比兔]|r " .. (L["发送战报遇到限制，建议使用【全选文本】复制或切换至团队/公会频道。"] or "发送战报遇到限制，建议使用【全选文本】复制或切换至团队/公会频道。"))
                return
            end

            if idx < #lines then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.25, function() SendNext(idx + 1) end)
                elseif BG and BG.After then
                    BG.After(0.25, function() SendNext(idx + 1) end)
                else
                    SendNext(idx + 1)
                end
            else
                SendNext(idx + 1)
            end
        end

        SendNext(1)
    end
end

-- 兼容旧版调用
function WR.SendBroadcast()
    local ch = (IsInRaid() and "RAID") or ((IsInGroup() and "PARTY") or ((IsInGuild() and "GUILD") or "SELF"))
    WR.SendBroadcastToChannel(ch)
end

function WR.ShowShareModal()
    local records = WR.GetFilteredRecords()
    local stats = WR.GetSummaryStats(records)

    if not WR.ShareModal then
        local f = CreateFrame("Frame", "BG_WR_ShareModal", UIParent, "BackdropTemplate")
        f:SetSize(480, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        table.insert(UISpecialFrames, "BG_WR_ShareModal")

        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0.06, 0.06, 0.10, 0.96)
        f:SetBackdropBorderColor(1, 0.8, 0, 0.9) -- 荣耀暗金色边框

        -- 1. 顶部品牌 Header
        local brand = f:CreateFontString(nil, "OVERLAY")
        brand:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        brand:SetTextColor(RGB("00BFFF"))
        brand:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
        brand:SetText("|cff00BFFF[BGLite_Plus 波比兔]|r")

        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
        title:SetTextColor(RGB("FFD700"))
        title:SetPoint("LEFT", brand, "RIGHT", 8, 0)
        title:SetText(L["团本报表 · 打工进度战报"] or "团本报表 · 打工进度战报")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

        local subPeriod = f:CreateFontString(nil, "OVERLAY")
        subPeriod:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        subPeriod:SetTextColor(RGB("AAAAAA"))
        subPeriod:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -5)
        f.subPeriod = subPeriod

        -- 分割线
        local line1 = f:CreateTexture(nil, "ARTWORK")
        line1:SetSize(444, 1)
        line1:SetColorTexture(0.3, 0.3, 0.35, 0.7)
        line1:SetPoint("TOPLEFT", subPeriod, "BOTTOMLEFT", 0, -8)

        -- 2. 四大核心财务卡片网格
        local function CreateStatBox(label, x, y, valColor)
            local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
            box:SetSize(104, 52)
            box:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
            box:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            box:SetBackdropColor(0.12, 0.12, 0.18, 0.8)
            box:SetBackdropBorderColor(0.4, 0.4, 0.5, 0.5)

            local lbl = box:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
            lbl:SetTextColor(RGB("888888"))
            lbl:SetPoint("TOP", box, "TOP", 0, -5)
            lbl:SetText(label)

            local val = box:CreateFontString(nil, "OVERLAY")
            val:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
            val:SetTextColor(RGB(valColor or "FFD700"))
            val:SetPoint("BOTTOM", box, "BOTTOM", 0, 7)

            return val
        end

        f.statRun = CreateStatBox(L["出勤车数"] or "出勤车数", 18, -62, "00BFFF")
        f.statWage = CreateStatBox(L["累计总工资"] or "累计总工资", 130, -62, "FFD700")
        f.statSub = CreateStatBox(L["额外补贴"] or "额外补贴", 242, -62, "00FF00")
        f.statNet = CreateStatBox(L["实际净落袋"] or "实际净落袋", 354, -62, "00FF7F")

        -- 3. 吸金劳模与出勤阵容展示
        local mvpBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
        mvpBox:SetSize(444, 48)
        mvpBox:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -122)
        mvpBox:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        mvpBox:SetBackdropColor(0.1, 0.12, 0.16, 0.8)
        mvpBox:SetBackdropBorderColor(0.2, 0.6, 1, 0.5)

        local mvpTitle = mvpBox:CreateFontString(nil, "OVERLAY")
        mvpTitle:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        mvpTitle:SetTextColor(RGB("FFD700"))
        mvpTitle:SetPoint("TOPLEFT", mvpBox, "TOPLEFT", 10, -6)
        mvpTitle:SetText(L["🏆 吸金榜首 (打工劳模)"] or "🏆 吸金榜首 (打工劳模)")

        local mvpContent = mvpBox:CreateFontString(nil, "OVERLAY")
        mvpContent:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        mvpContent:SetTextColor(RGB("FFFFFF"))
        mvpContent:SetPoint("BOTTOMLEFT", mvpBox, "BOTTOMLEFT", 10, 8)
        f.mvpContent = mvpContent

        -- 4. 战报预览文本框 (用于拍照、截图或纯文本复制)
        local previewBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
        previewBox:SetSize(444, 215)
        previewBox:SetPoint("TOPLEFT", mvpBox, "BOTTOMLEFT", 0, -10)
        previewBox:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        previewBox:SetBackdropColor(0.04, 0.04, 0.06, 0.9)
        previewBox:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.6)

        local previewTitle = previewBox:CreateFontString(nil, "OVERLAY")
        previewTitle:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        previewTitle:SetTextColor(RGB("00BFFF"))
        previewTitle:SetPoint("TOPLEFT", previewBox, "TOPLEFT", 10, -8)
        previewTitle:SetText(L["战报摘要预览 :"] or "战报摘要预览 :")

        local pScroll = CreateFrame("ScrollFrame", "BG_WR_SharePreviewScroll", previewBox, "UIPanelScrollFrameTemplate")
        pScroll:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -6)
        pScroll:SetSize(415, 175)

        local pText = CreateFrame("EditBox", nil, pScroll)
        pText:SetMultiLine(true)
        pText:SetMaxLetters(9999)
        pText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        pText:SetWidth(410)
        pText:SetAutoFocus(false)
        pText:EnableMouse(true)
        pScroll:SetScrollChild(pText)
        f.previewText = pText

        -- 5. 底部频道选择与操作按钮栏
        local chLbl = f:CreateFontString(nil, "OVERLAY")
        chLbl:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        chLbl:SetTextColor(RGB("CCCCCC"))
        chLbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 22)
        chLbl:SetText(L["通报频道:"] or "通报频道:")

        f.selectedChannel = "RAID"

        -- 正式下拉菜单组件 (LibBG:Create_UIDropDownMenu)
        local chDropDown = LibBG and LibBG:Create_UIDropDownMenu("BG_WR_ShareChannelDropDown", f)
        if not chDropDown then
            chDropDown = CreateFrame("Frame", "BG_WR_ShareChannelDropDown", f, "UIDropDownMenuTemplate")
        end
        f.chDropDown = chDropDown
        if BG.dropDownToggle then
            BG.dropDownToggle(chDropDown)
        end
        chDropDown:SetPoint("LEFT", chLbl, "RIGHT", -15, -2)

        if LibBG and LibBG.UIDropDownMenu_SetWidth then
            LibBG:UIDropDownMenu_SetWidth(chDropDown, 75)
            LibBG:UIDropDownMenu_SetAnchor(chDropDown, 0, 0, "BOTTOM", chDropDown, "TOP")
            LibBG:UIDropDownMenu_SetText(chDropDown, _G["RAID"] or "团队")
            LibBG:UIDropDownMenu_Initialize(chDropDown, function(self, level)
                local title = LibBG:UIDropDownMenu_CreateInfo()
                title.text = L["通报频道"] or "通报频道"
                title.isTitle = true
                title.notCheckable = true
                LibBG:UIDropDownMenu_AddButton(title)

                local function AddChan(channel, name)
                    local info = LibBG:UIDropDownMenu_CreateInfo()
                    info.text = name
                    info.func = function()
                        f.selectedChannel = channel
                        LibBG:UIDropDownMenu_SetText(chDropDown, name)
                    end
                    if f.selectedChannel == channel then
                        info.checked = true
                    end
                    LibBG:UIDropDownMenu_AddButton(info)
                end

                AddChan("RAID", _G["RAID"] or "团队")
                AddChan("PARTY", _G["PARTY"] or "小队")
                AddChan("GUILD", _G["GUILD"] or "公会")
                AddChan("YELL", _G["YELL"] or "大喊")
                AddChan("SAY", _G["SAY"] or "说")
                AddChan("SELF", L["仅自己可见"] or "仅自己可见")
            end)
        end

        local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        sendBtn:SetSize(85, 24)
        sendBtn:SetPoint("LEFT", chDropDown, "RIGHT", -5, 2)
        sendBtn:SetText(L["发送战报"] or "发送战报")
        sendBtn:SetScript("OnClick", function()
            WR.SendBroadcastToChannel(f.selectedChannel or "RAID")
        end)

        local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyBtn:SetSize(75, 24)
        copyBtn:SetPoint("LEFT", sendBtn, "RIGHT", 5, 0)
        copyBtn:SetText(L["全选文本"] or "全选文本")
        copyBtn:SetScript("OnClick", function()
            f.previewText:HighlightText()
            f.previewText:SetFocus()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r " .. (L["已全选战报文本，按 Ctrl+C 即可复制到剪贴板！"] or "已全选战报文本，按 Ctrl+C 即可复制到剪贴板！"))
        end)

        local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        doneBtn:SetSize(55, 24)
        doneBtn:SetPoint("LEFT", copyBtn, "RIGHT", 5, 0)
        doneBtn:SetText(L["关闭"] or "关闭")
        doneBtn:SetScript("OnClick", function() f:Hide() end)

        WR.ShareModal = f
    end

    local f = WR.ShareModal
    if LibBG and f.chDropDown and LibBG.UIDropDownMenu_SetText then
        local chanText = _G[f.selectedChannel] or (f.selectedChannel == "SELF" and (L["仅自己可见"] or "仅自己可见")) or "团队"
        LibBG:UIDropDownMenu_SetText(f.chDropDown, chanText)
    end
    local weekRange = (WR.curWeekFilter == "current") and WR.GetCDWeekDesc(0) or ((WR.curWeekFilter == "last") and WR.GetCDWeekDesc(-1) or "")
    local pDesc = (WR.curWeekFilter == "current" and "本周 CD") or ((WR.curWeekFilter == "last" and "上周 CD") or ((WR.curWeekFilter == "month" and "近 30 天") or "全部历史"))
    if weekRange ~= "" then pDesc = string.format("%s (%s)", pDesc, weekRange) end
    f.subPeriod:SetText(string.format(L["统计周期: %s | 角色筛选: %s"] or "统计周期: %s | 角色筛选: %s", pDesc, (WR.curCharFilter == "all" and "全部角色") or WR.curCharFilter))

    f.statRun:SetText(string.format("%d 车", stats.runCount))
    f.statWage:SetText(FormatMoney(stats.totalWage))
    f.statSub:SetText(string.format("+%s", FormatMoney(stats.totalSubsidy)))
    f.statNet:SetText(FormatMoney(stats.totalNet))

    if stats.topChar then
        local pct = (stats.totalWage > 0) and math.floor(stats.topChar.wage / stats.totalWage * 100) or 0
        f.mvpContent:SetText(string.format("%s  |  贡献: %s (占比 %d%%)  |  出勤 %d 车", SetClassCFF(stats.topChar.charName, stats.topChar.class), FormatMoney(stats.topChar.wage), pct, stats.topChar.runs))
    else
        f.mvpContent:SetText(L["暂无劳模数据"] or "暂无劳模数据")
    end

    -- 生成详细纯文本战报
    local subDesc = ((stats.totalSubsidy or 0) > 0) and string.format(" (含补贴 +%s)", FormatMoney(stats.totalSubsidy)) or ""
    local spDesc = (stats.topSpender and stats.topSpender.spend > 0) and string.format(" (消费最多: %s)", stats.topSpender.charName) or ""
    local spendStr = ((stats.totalSpend or 0) > 0) and string.format("-%s%s", FormatMoney(stats.totalSpend), spDesc) or "0G (无额外消费)"
    local reportLines = {
        "=====================================",
        "【BGLite_Plus 波比兔】团本报表",
        string.format("统计周期: %s", pDesc),
        string.format("出勤统计: %d 车 (均薪: %s/车)", stats.runCount, FormatMoney(stats.avgWage)),
        string.format("总计工资: %s%s", FormatMoney(stats.totalWage), subDesc),
        string.format("累计支出: %s", spendStr),
        string.format("实际到手: %s", FormatMoney(stats.totalNet)),
    }
    if stats.topChar then
        local pct = (stats.totalWage > 0) and math.floor(stats.topChar.wage / stats.totalWage * 100) or 0
        table.insert(reportLines, string.format("吸金榜首: %s (%s, 占比 %d%%, %d车)", stats.topChar.charName, FormatMoney(stats.topChar.wage), pct, stats.topChar.runs))
    end
    if stats.topSpender and stats.topSpender.spend > 0 then
        local spPct = (stats.totalSpend > 0) and math.floor(stats.topSpender.spend / stats.totalSpend * 100) or 0
        table.insert(reportLines, string.format("消费榜首: %s (-%s, 占比 %d%%)", stats.topSpender.charName, FormatMoney(stats.topSpender.spend), spPct))
    end
    table.insert(reportLines, "-------------------------------------")
    table.insert(reportLines, "流水明细:")
    for idx, r in ipairs(records) do
        if idx <= 15 then
            local tStr = date("%m/%d %H:%M", r.timestamp)
            local net = r.netWage or r.wage or 0
            local sp = (r.mySpend or 0) + (r.penalty or 0)
            local spStr = (sp > 0) and string.format(" 支出:-%dG", sp) or ""
            table.insert(reportLines, string.format("[%s] %s %s (%s人) 工资:%dG%s 净落袋:%dG", tStr, r.charName or "", r.fbName or r.fb or "", r.totalPeople or 0, r.wage or 0, spStr, net))
        end
    end
    if #records > 15 then
        table.insert(reportLines, string.format("... 其余 %d 笔明细略", #records - 15))
    end
    table.insert(reportLines, "=====================================")
    table.insert(reportLines, "每一份付出都有回响，愿艾泽拉斯的金币与荣耀与你常伴！(波比兔)")

    f.previewText:SetText(table.concat(reportLines, "\n"))
    f:Show()
end

-------------------------------------------------------------------------------
-- 9. 周四清空 CD 上线智能周报提示 (零扰民机制)
-------------------------------------------------------------------------------
function WR.CheckThursdayWeeklyReportNotice(force)
    WR.InitDB()
    local opts = BiaoGe.WorkerReport.options
    if not force then
        if not opts or not opts.showWeeklyPopup then return end
        local curWeekId = WR.GetCDWeekId(time())
        if opts.lastPopupWeek == curWeekId then
            return -- 本周已经提醒过了，坚决不重复打扰
        end
    end

    -- 检查上周 CD 是否有数据
    local curWeekStart = WR.GetCDWeekStart(time())
    local lastWeekStart = curWeekStart - 7 * 86400
    local lastWeekEnd = curWeekStart - 1

    local lastWeekRecords = {}
    for _, r in ipairs(WR.GetAllRecords()) do
        if r.timestamp >= lastWeekStart and r.timestamp <= lastWeekEnd then
            table.insert(lastWeekRecords, r)
        end
    end

    local stats
    if #lastWeekRecords > 0 then
        stats = WR.GetSummaryStats(lastWeekRecords)
    end

    -- 如果强制测试且上周无数据，优先尝试当周数据；若当周也无数据，使用逼真演示数据
    if force and (not stats or stats.runCount == 0 or stats.totalWage <= 0) then
        local curRecords = WR.GetFilteredRecords()
        if curRecords and #curRecords > 0 then
            stats = WR.GetSummaryStats(curRecords)
        end
        if not stats or stats.runCount == 0 or stats.totalWage <= 0 then
            stats = {
                runCount = 3,
                totalWage = 36800,
                totalSpend = 2000,
                totalNet = 34800,
                avgWage = 12267,
            }
        end
    elseif not force then
        if #lastWeekRecords == 0 or not stats or stats.totalWage <= 0 then
            opts.lastPopupWeek = WR.GetCDWeekId(time())
            return
        end
        opts.lastPopupWeek = WR.GetCDWeekId(time())
    end

    local delay = force and 0.2 or 3
    C_Timer.After(delay, function()
        -- 1. 聊天框优雅超链接
        local link = "|cff00FF00|Hgarrmission:BGLite_WorkerReport:open|h[查看团本报表]|h|r"
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite_Plus 波比兔]|r |cffffd100周四 CD 已重置！|r上周你共出勤 |cff00FF00%d|r 车，分得工资 |cffffd700%s|r！ %s", stats.runCount, FormatMoney(stats.totalWage), link))

        -- 2. 屏幕顶部弹出轻量卡片提示
        local notice = BG_WR_WeeklyNoticeFrame or CreateFrame("Frame", "BG_WR_WeeklyNoticeFrame", UIParent, "BackdropTemplate")
        notice:SetSize(330, 96)
        notice:ClearAllPoints()
        notice:SetPoint("TOP", UIParent, "TOP", 0, -75)
        notice:SetFrameStrata("TOOLTIP")
        notice:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        notice:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        notice:SetBackdropBorderColor(0.2, 0.7, 1, 0.9)

        if not notice.t1 then
            local icon = notice:CreateTexture(nil, "OVERLAY")
            icon:SetSize(20, 20)
            icon:SetPoint("TOPLEFT", notice, "TOPLEFT", 12, -10)
            icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_5")
            notice.icon = icon

            local t1 = notice:CreateFontString(nil, "OVERLAY")
            t1:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            t1:SetTextColor(RGB("00BFFF"))
            t1:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            notice.t1 = t1

            local t2 = notice:CreateFontString(nil, "OVERLAY")
            t2:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
            t2:SetTextColor(RGB("FFFFFF"))
            t2:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
            notice.t2 = t2

            -- 查看报表按钮
            local btnView = CreateFrame("Button", nil, notice, "UIPanelButtonTemplate")
            btnView:SetSize(90, 24)
            btnView:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 12, 10)
            btnView:SetText(L["查看报表"] or "查看报表")
            btnView:SetScript("OnClick", function()
                notice:Hide()
                if BG.MainFrame then
                    BG.MainFrame:Show()
                    if BG.ClickTabButton and BG.WorkerReportMainFrameTabNum then
                        BG.ClickTabButton(BG.WorkerReportMainFrameTabNum)
                    end
                end
                if WR.tipsBtn and WR.tipsBtn:GetScript("OnEnter") then
                    WR.tipsBtn:GetScript("OnEnter")(WR.tipsBtn)
                    C_Timer.After(4, function()
                        if GameTooltip:IsOwned(WR.tipsBtn) then
                            GameTooltip:Hide()
                        end
                    end)
                end
            end)
            notice.btnView = btnView

            -- 知道了/关闭按钮
            local btnClose = CreateFrame("Button", nil, notice, "UIPanelButtonTemplate")
            btnClose:SetSize(80, 24)
            btnClose:SetPoint("LEFT", btnView, "RIGHT", 10, 0)
            btnClose:SetText(L["我知道了"] or "我知道了")
            btnClose:SetScript("OnClick", function() notice:Hide() end)
            notice.btnClose = btnClose
        end

        notice.t1:SetText(L["[BGLite_Plus 波比兔] 周四 CD 重置周报"] or "[BGLite_Plus 波比兔] 周四 CD 重置周报")
        notice.t2:SetText(string.format(L["上周共出勤 %d 车，分得工资 %s !"] or "上周共出勤 %d 车，分得工资 %s !", stats.runCount, FormatMoney(stats.totalWage)))
        notice:Show()

        -- 15 秒后自动淡出消失，绝不滞留
        if notice.timer then notice.timer:Cancel() end
        notice.timer = C_Timer.NewTimer(15, function()
            if notice and notice:IsShown() then
                notice:Hide()
            end
        end)
    end)
end

-------------------------------------------------------------------------------
-- 10. Hook SetItemRef 处理 [查看团本报表] 超链接点击
-------------------------------------------------------------------------------
hooksecurefunc("SetItemRef", function(link)
    local _, tag, action = strsplit(":", link)
    if tag == "BGLite_WorkerReport" and action == "open" then
        if BG.MainFrame then
            BG.MainFrame:Show()
            if BG.ClickTabButton and BG.WorkerReportMainFrameTabNum then
                BG.ClickTabButton(BG.WorkerReportMainFrameTabNum)
            end
        end
        if WR.tipsBtn and WR.tipsBtn:GetScript("OnEnter") then
            WR.tipsBtn:GetScript("OnEnter")(WR.tipsBtn)
            C_Timer.After(4, function()
                if GameTooltip:IsOwned(WR.tipsBtn) then
                    GameTooltip:Hide()
                end
            end)
        end
    end
end)

-------------------------------------------------------------------------------
-- 11. 隐藏测试指令：/bgthu 或 /bgreport 或 /bgbb
-------------------------------------------------------------------------------
SLASH_BGLITE_THURSDAY1 = "/bgthu"
SLASH_BGLITE_THURSDAY2 = "/bgreport"
SLASH_BGLITE_THURSDAY3 = "/bgbb"
SlashCmdList["BGLITE_THURSDAY"] = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "clear" or msg == "reset" then
        if BiaoGe and BiaoGe.WorkerReport and BiaoGe.WorkerReport.options then
            BiaoGe.WorkerReport.options.lastPopupWeek = nil
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r |cff00FF00周四周报提醒标记已清除！下次重载界面 (/reload) 将作为周四首次登录触发。|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite_Plus 波比兔]|r |cffffd100正在为您模拟【周四 CD 首次上线】引导提醒效果...|r")
        WR.CheckThursdayWeeklyReportNotice(true)
    end
end

