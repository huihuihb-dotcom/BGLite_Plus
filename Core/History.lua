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

            -- 2. 合规性清洗：自动剥离存量历史记录中可能存在的角色名、名单及聊天日志
            for dt, record in pairs(BiaoGe.History[FB]) do
                if type(record) == "table" then
                    record.raidRoster = nil
                    record.auctionLog = nil
                    record.leaderInfo = nil
                    record.teamInfo = nil
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
    local DT = tonumber(date("%y%m%d%H%M%S", serverTime))
    if BiaoGe.History[FB][DT] then
        serverTime = serverTime + 1
        DT = tonumber(date("%y%m%d%H%M%S", serverTime))
    end
    local DTcn = date(L["%m月%d日%H:%M:%S\n"] or "%m月%d日%H:%M:%S\n", serverTime)

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

    -- 存储本场数据
    BiaoGe.History[FB][DT] = record

    local fbShort = (BG.GetFBinfo and BG.GetFBinfo(FB, "shortName")) or FB
    local totalPeople = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine4"] and BG.Frame[FB]["boss" .. maxb + 2]["jine4"]:GetText()) or "0"
    local wage = (BG.Frame and BG.Frame[FB] and BG.Frame[FB]["boss" .. maxb + 2] and BG.Frame[FB]["boss" .. maxb + 2]["jine5"] and BG.Frame[FB]["boss" .. maxb + 2]["jine5"]:GetText()) or "0"

    local titleSummary = string.format("%s %s人 工资:%s", fbShort, totalPeople, wage)
    local d = { DT, titleSummary, date("%m/%d", serverTime), date("%H:%M:%S", serverTime) }

    table.insert(BiaoGe.HistoryList[FB], 1, d)

    -- 严格执行单个副本最多 10 份限制，自动物理淘汰最旧的存档
    EnforceHistoryLimit(FB)

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
        if BG.FBMainFrame then BG.FBMainFrame:Show() end
        if BG.Title then BG.Title:Show() end
        if BG.VerText then BG.VerText:Show() end
        if BG.UpdateAuctionLogFrame then BG.UpdateAuctionLogFrame() end
        if BG.PlaySound then BG.PlaySound(1) end
        BG.UpdateHistoryButton()
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
            return orig_ClearBiaoGe(_type, FB)
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

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:SetScript("OnEvent", function(self, event)
    StartHistoryModule()
end)

-- 顶层立即预热执行
StartHistoryModule()
