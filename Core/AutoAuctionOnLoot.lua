local AddonName, ns = ...

local L = ns.L or {}
local AutoAuctionOnLoot = {}
ns.AutoAuctionOnLoot = AutoAuctionOnLoot

-- 安全提取装备 ID 工具函数（杜绝全局 GetItemID 不存在导致的运行时报错崩溃）
local function SafeGetItemID(text)
    if not text then return nil end
    if type(text) == "number" then return text end
    local id = text:match("item:(%d+)") or text:match("Hitem:(%d+)")
    return id and tonumber(id) or nil
end
local GetItemID = ns.GetItemID or SafeGetItemID

-- 1. 配置项缺省自愈与默认开启
local function EnsureOptions()
    BiaoGe = BiaoGe or {}
    BiaoGe.options = BiaoGe.options or {}
    -- 一次性安全自愈迁移：重置历史开启状态为默认关闭 0，建议团长按最佳实践配置预设后再主动开启
    -- 注意：BG.Once 必须传入 3 个参数：(name, dt, func)
    if BG and BG.Once then
        BG.Once("autoAuctionDefaultOff", 260911, function()
            BiaoGe.options.autoAuctionOnLoot = 0
        end)
    end
    -- 默认出厂为关闭 0（建议配合预设价格配置后主动开启）
    if BiaoGe.options.autoAuctionOnLoot == nil then
        BiaoGe.options.autoAuctionOnLoot = 0
    end
    if BiaoGe.options.autoAuctionConfirmTime == nil then
        BiaoGe.options.autoAuctionConfirmTime = 5 -- 默认 5 秒倒计时浮动条确认
    end
    if BiaoGe.options.autoAuctionInstant == nil then
        BiaoGe.options.autoAuctionInstant = 0 -- 0: 5秒倒计时确认; 1: 秒级极速全自动开拍
    end
    if BiaoGe.options.autoAuctionFallbackPrice == nil then
        BiaoGe.options.autoAuctionFallbackPrice = 100 -- 未预设装备保底起拍底价 100G
    end
end

-- 2. 权限与环境校验 (严格限定大型团队副本 Raid，严禁 5 人小队或野外普通怪物触发)
local function CanInitiateAuction(isManualTest)
    -- 2.1 若为手动测试指令 (/bgloot test) 或开发者调试模式，直接放行
    if isManualTest or (BG and (BG.DeBug or BG.DEBUG)) then return true end

    -- 2.2 核心限制：必须处于团队 (Raid) 中！5 人小队 (Party)、单人、野外一律严格拦截
    local inRaid = IsInRaid and (IsInRaid(1) or IsInRaid())
    if not inRaid then
        return false
    end

    -- 2.3 核心限制：地下城类型检测，严禁 5 人地下城、战场、竞技场
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and instanceType ~= "raid" then
            return false
        end
    end

    -- 2.4 身份检测：优先直接使用 BGLite 权威计算的团长/分配者状态
    if BG and (BG.IsML or BG.IsLeader or (BG.ImMLorLeader and BG.ImMLorLeader())) then
        return true
    end

    -- 团队领袖 (团长) 兜底检测
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return true
    end

    -- 物品分配者 (Master Looter) 兜底检测 (兼容 C_PartyInfo 新 API，杜绝 GetLootMethod 为空报错)
    local GetLootMethodFunc = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
    if GetLootMethodFunc then
        local lootmethod, partyMaster, raidMaster = GetLootMethodFunc()
        if lootmethod == "master" or lootmethod == 2 then
            if raidMaster == 0 or partyMaster == 0 then
                return true
            elseif raidMaster and UnitIsUnit("raid" .. raidMaster, "player") then
                return true
            end
        end
    end

    if type(IsMasterLooter) == "function" and IsMasterLooter() then
        return true
    end

    return false
end

-- 3. 表格槽位级“只拍一次”终生锁定池 (支持跨 /reload 持久化与生命周期自愈)
local function GetAuctionedSlotsDB()
    BiaoGe = BiaoGe or {}
    BiaoGe.autoAuctionedSlots = BiaoGe.autoAuctionedSlots or {}
    return BiaoGe.autoAuctionedSlots
end
AutoAuctionOnLoot.GetAuctionedSlotsDB = GetAuctionedSlotsDB

local function IsSlotAuctioned(slotKey)
    if not slotKey or slotKey == "" then return false end
    local db = GetAuctionedSlotsDB()
    return db[slotKey] == true
end

local function MarkSlotAuctioned(slotKey)
    if not slotKey or slotKey == "" then return end
    local db = GetAuctionedSlotsDB()
    db[slotKey] = true
end

local function ClearSlotAuctioned(slotKey)
    if not slotKey or slotKey == "" then return end
    local db = GetAuctionedSlotsDB()
    db[slotKey] = nil
end

local function ResetAllAuctionedSlots()
    local db = GetAuctionedSlotsDB()
    wipe(db)
end
AutoAuctionOnLoot.ResetAllAuctionedSlots = ResetAllAuctionedSlots

-- 3.1 非 Boss 掉落交互状态追踪（杜绝队友交易归还、邮寄、商店回购等引发误拍）
local isTradeOpen = false
local lastTradeTime = 0
local lastTradeCompleteTime = 0
local isMailOpen = false
local lastMailTime = 0
local isMerchantOpen = false
local lastMerchantTime = 0

local interactionWatcher = CreateFrame("Frame")
interactionWatcher:RegisterEvent("TRADE_SHOW")
interactionWatcher:RegisterEvent("TRADE_CLOSED")
interactionWatcher:RegisterEvent("TRADE_ACCEPT_UPDATE")
interactionWatcher:RegisterEvent("UI_INFO_MESSAGE")
interactionWatcher:RegisterEvent("MAIL_SHOW")
interactionWatcher:RegisterEvent("MAIL_CLOSED")
interactionWatcher:RegisterEvent("MERCHANT_SHOW")
interactionWatcher:RegisterEvent("MERCHANT_CLOSED")

interactionWatcher:SetScript("OnEvent", function(self, event, ...)
    local now = GetTime()
    if event == "TRADE_SHOW" then
        isTradeOpen = true
    elseif event == "TRADE_CLOSED" then
        isTradeOpen = false
        lastTradeTime = now
    elseif event == "TRADE_ACCEPT_UPDATE" then
        -- 交易状态保持活跃
    elseif event == "UI_INFO_MESSAGE" then
        local _, text = ...
        if (ERR_TRADE_COMPLETE and text == ERR_TRADE_COMPLETE) or (text and text:find("交易完成")) then
            lastTradeCompleteTime = now
            lastTradeTime = now
        end
    elseif event == "MAIL_SHOW" then
        isMailOpen = true
    elseif event == "MAIL_CLOSED" then
        isMailOpen = false
        lastMailTime = now
    elseif event == "MERCHANT_SHOW" then
        isMerchantOpen = true
    elseif event == "MERCHANT_CLOSED" then
        isMerchantOpen = false
        lastMerchantTime = now
    end
end)

local function IsNonLootInteractionActive()
    local now = GetTime()
    if isTradeOpen or (now - lastTradeTime < 3.5) or (now - lastTradeCompleteTime < 3.5) then
        return true, "交易状态"
    end
    if isMailOpen or (now - lastMailTime < 3.0) then
        return true, "邮件状态"
    end
    if isMerchantOpen or (now - lastMerchantTime < 3.0) then
        return true, "商人/回购状态"
    end
    return false
end
AutoAuctionOnLoot.IsNonLootInteractionActive = IsNonLootInteractionActive

-- 3.2 待拍防抖批处理缓冲池与防重复防击穿池
local pendingLootQueue = {}
local recentQueuedItems = {} -- [key] = timestamp
local debounceTimer = nil
local countDownFrame = nil

-- 检查某个槽位是否当前正处于未开拍的待拍缓冲队列中（防止并发查找命中同一槽位）
local function IsSlotInPendingQueue(slotKey)
    if not slotKey or slotKey == "" then return false end
    for _, item in ipairs(pendingLootQueue) do
        if item.slotKey == slotKey then
            return true
        end
    end
    return false
end
AutoAuctionOnLoot.IsSlotInPendingQueue = IsSlotInPendingQueue

local function IsRecentlyQueued(itemID, link, slotKey)
    local now = GetTime()
    -- 1. 槽位级终生锁定与短期防抖校验（优先依据独立槽位判定，彻底杜绝误伤同名装备）
    if slotKey and slotKey ~= "" then
        if IsSlotAuctioned(slotKey) then
            return true
        end
        local slotTimeKey = "slot_" .. slotKey
        if recentQueuedItems[slotTimeKey] and (now - recentQueuedItems[slotTimeKey] < 45) then
            return true
        end
        if IsSlotInPendingQueue(slotKey) then
            return true
        end
        -- 有明确且未锁定的独立槽位，直接放行，绝不能被全局 itemID 拦截！
        return false
    end

    -- 2. 仅当没有 slotKey 时（如手动调试指令），才使用全局 itemID + link 短期防抖兜底
    local key = tostring(itemID) .. "_" .. tostring(link or "")
    if recentQueuedItems[key] and (now - recentQueuedItems[key] < 45) then
        return true
    end
    return false
end

local function MarkItemQueued(itemID, link, slotKey)
    local now = GetTime()
    if slotKey and slotKey ~= "" then
        recentQueuedItems["slot_" .. slotKey] = now
        MarkSlotAuctioned(slotKey)
    else
        local key = tostring(itemID) .. "_" .. tostring(link or "")
        recentQueuedItems[key] = now
    end
end

-- 执行拍卖广播 (仅限团队 RAID 频道广播)
local function ExecuteAutoAuction(itemsToAuction, fallbackPrice, bossName)
    if not itemsToAuction or #itemsToAuction == 0 then return end

    local duration = tonumber(BiaoGe.Auction and BiaoGe.Auction.duration)
    if not duration or duration <= 0 then duration = 40 end
    local mod = (BiaoGe.Auction and BiaoGe.Auction.mod) or "normal"
    if mod == "roll" or mod == "anonymous" then mod = "normal" end
    local isGen2 = (BiaoGe.Auction and BiaoGe.Auction.gen == 2)
    local resetThreshold = max(tonumber(BiaoGe.Auction and BiaoGe.Auction.resetThreshold) or 0, 10)

    if BG and BG.PlaySound then BG.PlaySound(1) end

    -- 统计待拍实际总件数（考虑单格子带 xN 数量的情况）
    local totalItemCount = 0
    for _, it in ipairs(itemsToAuction) do
        totalItemCount = totalItemCount + (it.count or 1)
    end

    -- 仅向团队频道发送一条汇总开拍提示（严禁向 5 人小队 PARTY 频道发送）
    local inRaid = IsInRaid and (IsInRaid(1) or IsInRaid())
    if inRaid then
        local msg = format("[BGLite] 团长已发起【%s】自动拍卖（共 %d 件装备），请在拍卖窗口出价！", bossName or "Boss", totalItemCount)
        SendChatMessage(msg, "RAID")
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite]|r 正在为【%s】发起全部 %d 件装备拍卖（平滑发送中，间隔1.2秒）...", bossName or "Boss", totalItemCount))
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(format("已发起【%s】共 %d 件装备自动拍卖", bossName or "Boss", totalItemCount), 0, 1, 0)
    end

    local delay = 0
    for _, it in ipairs(itemsToAuction) do
        local finalMoney = it.presetMoney or fallbackPrice or 100
        local itemID = it.id
        local link = it.link
        local itCount = it.count or 1
        -- 支持同一装备/代币循环发起相应次数的拍卖，分别生成独立拍卖框
        for c = 1, itCount do
            C_Timer.After(delay, function()
                if BG and BG.SendStartAuctionMsg then
                    BG.SendStartAuctionMsg(isGen2, itemID, finalMoney, duration, mod, link, resetThreshold)
                end
            end)
            delay = delay + 1.2
        end
    end
end

-- 4. 倒计时悬浮条 UI
local function GetOrCreateCountDownFrame()
    if countDownFrame then return countDownFrame end

    local f = CreateFrame("Frame", "BGLite_Plus_AutoAuctionCountDownFrame", UIParent, "BackdropTemplate")
    f:SetSize(350, 90)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(250)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)

    -- 标题
    local title = f:CreateFontString(nil, "ARTWORK")
    title:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 13, "OUTLINE")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetTextColor(1, 0.82, 0)
    title:SetText(L["[BGLite] 掉落装备自动拍卖"] or "[BGLite] 掉落装备自动拍卖")
    f.title = title

    -- 副标题（状态与件数）
    local subText = f:CreateFontString(nil, "ARTWORK")
    subText:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 12, "OUTLINE")
    subText:SetPoint("TOPRIGHT", -12, -8)
    subText:SetTextColor(0.4, 0.8, 1)
    subText:SetText("")
    f.subText = subText

    -- 倒计时进度条
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(326, 16)
    bar:SetPoint("TOP", 0, -30)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.2, 0.9)
    bar:SetMinMaxValues(0, 5)
    bar:SetValue(5)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    local barText = bar:CreateFontString(nil, "OVERLAY")
    barText:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 11, "OUTLINE")
    barText:SetPoint("CENTER", 0, 0)
    barText:SetTextColor(1, 1, 1)
    bar.text = barText
    f.bar = bar

    -- 立即全拍按钮
    local btnStart = CreateFrame("Button", nil, f, "BackdropTemplate")
    btnStart:SetSize(80, 22)
    btnStart:SetPoint("BOTTOMLEFT", 12, 10)
    btnStart:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeSize = 1,
    })
    btnStart:SetBackdropColor(0.1, 0.5, 0.15, 0.9)
    btnStart:SetBackdropBorderColor(0.3, 0.9, 0.3, 1)
    local tStart = btnStart:CreateFontString(nil, "ARTWORK")
    tStart:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 11, "OUTLINE")
    tStart:SetPoint("CENTER", 0, 0)
    tStart:SetText(L["立即全拍"] or "立即全拍")
    tStart:SetTextColor(1, 1, 1)
    btnStart:SetScript("OnClick", function()
        if BG and BG.PlaySound then BG.PlaySound(1) end
        f:StopAndExecute()
    end)
    btnStart:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.65, 0.2, 1)
    end)
    btnStart:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.5, 0.15, 0.9)
    end)
    f.btnStart = btnStart

    -- 取消按钮
    local btnCancel = CreateFrame("Button", nil, f, "BackdropTemplate")
    btnCancel:SetSize(60, 22)
    btnCancel:SetPoint("BOTTOMRIGHT", -12, 10)
    btnCancel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeSize = 1,
    })
    btnCancel:SetBackdropColor(0.4, 0.12, 0.12, 0.9)
    btnCancel:SetBackdropBorderColor(0.9, 0.3, 0.3, 1)
    local tCancel = btnCancel:CreateFontString(nil, "ARTWORK")
    tCancel:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 11, "OUTLINE")
    tCancel:SetPoint("CENTER", 0, 0)
    tCancel:SetText(L["取消"] or "取消")
    tCancel:SetTextColor(1, 0.8, 0.8)
    btnCancel:SetScript("OnClick", function()
        if BG and BG.PlaySound then BG.PlaySound(2) end
        f:CancelAuction()
    end)
    btnCancel:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.15, 0.15, 1)
    end)
    btnCancel:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.12, 0.12, 0.9)
    end)
    f.btnCancel = btnCancel

    -- 中间提示文字
    local infoText = f:CreateFontString(nil, "ARTWORK")
    infoText:SetFont(BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT, 11, "OUTLINE")
    infoText:SetPoint("LEFT", btnStart, "RIGHT", 10, 0)
    infoText:SetPoint("RIGHT", btnCancel, "LEFT", -10, 0)
    infoText:SetJustifyH("CENTER")
    infoText:SetTextColor(0.85, 0.85, 0.85)
    f.infoText = infoText

    f.timeRemaining = 0
    f.totalTime = 5
    f.items = {}
    f.bossName = ""

    function f:StartCountdown(itemsToAuction, bossName)
        self.items = itemsToAuction
        self.bossName = bossName or "Boss"
        self.totalTime = tonumber(BiaoGe.options.autoAuctionConfirmTime) or 5
        if self.totalTime < 2 then self.totalTime = 2 end
        self.timeRemaining = self.totalTime

        self.bar:SetMinMaxValues(0, self.totalTime)
        self.bar:SetValue(self.totalTime)
        self.bar:SetStatusBarColor(0.2, 0.8, 0.2, 0.9)

        local totalItemCount = 0
        local unpresetCount = 0
        for _, it in ipairs(itemsToAuction) do
            local c = it.count or 1
            totalItemCount = totalItemCount + c
            if not it.presetMoney then unpresetCount = unpresetCount + c end
        end

        self.subText:SetText(format("【%s】共 %d 件", self.bossName, totalItemCount))
        if unpresetCount > 0 then
            local fallback = tonumber(BiaoGe.options.autoAuctionFallbackPrice) or 100
            self.infoText:SetText(format("%d件未设底价(按%dG)", unpresetCount, fallback))
        else
            self.infoText:SetText("|cff00ff00全部已匹配预设底价|r")
        end

        self:Show()

        self:SetScript("OnUpdate", function(self, elapsed)
            self.timeRemaining = self.timeRemaining - elapsed
            if self.timeRemaining <= 0 then
                self:SetScript("OnUpdate", nil)
                self:StopAndExecute()
            else
                self.bar:SetValue(self.timeRemaining)
                local pct = self.timeRemaining / self.totalTime
                if pct > 0.5 then
                    self.bar:SetStatusBarColor(0.2, 0.8, 0.2, 0.9)
                elseif pct > 0.25 then
                    self.bar:SetStatusBarColor(0.9, 0.7, 0.1, 0.9)
                else
                    self.bar:SetStatusBarColor(0.9, 0.2, 0.2, 0.9)
                end
                self.bar.text:SetText(format("%.1f 秒后自动全开拍卖", self.timeRemaining))
            end
        end)
    end

    function f:StopAndExecute()
        self:SetScript("OnUpdate", nil)
        self:Hide()
        if not self.items or #self.items == 0 then return end

        local fallbackPrice = tonumber(BiaoGe.options.autoAuctionFallbackPrice) or 100
        local toRun = self.items
        local bName = self.bossName
        self.items = {}
        ExecuteAutoAuction(toRun, fallbackPrice, bName)
    end

    function f:CancelAuction()
        self:SetScript("OnUpdate", nil)
        self:Hide()
        self.items = {}
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff8000[BGLite]|r 已取消本次掉落自动拍卖。", 1, 0.8, 0)
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 团长已取消本次掉落装备自动拍卖。")
        end
    end

    countDownFrame = f
    return countDownFrame
end

-- 5. 处理防抖收集完成的待拍装备
local function ProcessPendingAuctions()
    debounceTimer = nil
    if #pendingLootQueue == 0 then return end

    -- 战斗状态感知：若在战斗中，不丢弃队列，提示并等待脱战执行
    if InCombatLockdown() or UnitAffectingCombat("player") then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 自动拍卖]|r 当前正处于战斗中，拍卖将在脱战后自动发起...")
        end
        return
    end

    local itemsToAuction = {}
    for _, item in ipairs(pendingLootQueue) do
        tinsert(itemsToAuction, item)
    end
    wipe(pendingLootQueue)

    local bossName = itemsToAuction[1] and itemsToAuction[1].bossName or "Boss"

    EnsureOptions()
    if BiaoGe.options.autoAuctionInstant == 1 then
        local fallbackPrice = tonumber(BiaoGe.options.autoAuctionFallbackPrice) or 100
        ExecuteAutoAuction(itemsToAuction, fallbackPrice, bossName)
    else
        local frame = GetOrCreateCountDownFrame()
        frame:StartCountdown(itemsToAuction, bossName)
    end
end

-- 脱战监听：战斗结束后 1 秒唤醒执行挂起的拍卖
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    if #pendingLootQueue > 0 and not debounceTimer then
        C_Timer.After(1, function()
            if not InCombatLockdown() and #pendingLootQueue > 0 then
                ProcessPendingAuctions()
            end
        end)
    end
end)

-- 检查物品是否已被正式【记录进拍卖表格】(BiaoGe[FB])
-- checkAvailableOnly: 是否严格只匹配【尚未开拍且尚未记账结账】的有效待拍槽位
local function FindItemInBiaoGeTable(itemID, link, FB, checkAvailableOnly)
    if not BiaoGe then return false end
    local targetID = itemID and tonumber(itemID)
    if not targetID and link then
        targetID = SafeGetItemID(link)
    end
    if not targetID then return false end

    -- 确定待检查副本列表：优先传入FB -> BG.FB2 -> BG.FB1 -> 预设当前FB -> 全量BiaoGe
    local fbsToCheck = {}
    local addedFB = {}
    local function AddFB(fbName)
        if fbName and type(fbName) == "string" and fbName ~= "" and BiaoGe[fbName] and not addedFB[fbName] then
            tinsert(fbsToCheck, fbName)
            addedFB[fbName] = true
        end
    end

    AddFB(FB)
    AddFB(BG and BG.FB2)
    AddFB(BG and BG.FB1)
    AddFB(BiaoGe.auctionPreset and BiaoGe.auctionPreset.currentFB)

    for fbName, fbData in pairs(BiaoGe) do
        if type(fbData) == "table" and fbData.boss1 ~= nil then
            AddFB(fbName)
        end
    end

    for _, fbName in ipairs(fbsToCheck) do
        local maxb = (BG and BG.Maxb and BG.Maxb[fbName]) or 30
        for b = 1, maxb do
            if BiaoGe[fbName]["boss" .. b] then
                local maxi = (BG and BG.GetMaxi and BG.GetMaxi(fbName, b)) or 30
                for i = 1, maxi do
                    local txt = BiaoGe[fbName]["boss" .. b]["zhuangbei" .. i]
                    local slotKey = tostring(fbName) .. "_" .. tostring(b) .. "_" .. tostring(i)

                    if txt and txt ~= "" then
                        local id = SafeGetItemID(txt)
                        if (id and id == targetID) or (link and (txt == link or txt:find(link, 1, true))) then
                            local jine = BiaoGe[fbName]["boss" .. b]["jine" .. i]
                            local maijia = BiaoGe[fbName]["boss" .. b]["maijia" .. i]
                            local hasMoney = (jine and tonumber(jine) and tonumber(jine) > 0)
                            local hasBuyer = (maijia and maijia ~= "")
                            local isAuctioned = IsSlotAuctioned(slotKey)
                            local isPending = IsSlotInPendingQueue(slotKey)

                            -- 解析槽位文本中可能包含的数量后缀（例如 [北伐奖章]x2）
                            local slotCount = 1
                            local countMatch = txt:match("x(%d+)$") or txt:match("x(%d+)%s*$")
                            if countMatch then
                                slotCount = tonumber(countMatch) or 1
                            end

                            local bName = nil
                            if BG and BG.Boss and BG.Boss[fbName] and BG.Boss[fbName]["boss" .. b] then
                                bName = BG.Boss[fbName]["boss" .. b].name2 or BG.Boss[fbName]["boss" .. b].name
                            end

                            if checkAvailableOnly then
                                -- 严格过滤：若该槽位已记账有金额、已有买家、此前已自动开拍过、或当前正处于待拍批次中，一律视为已占用槽位跳过
                                if not hasMoney and not hasBuyer and not isAuctioned and not isPending then
                                    return true, b, i, bName, fbName, slotKey, slotCount
                                end
                            else
                                return true, b, i, bName, fbName, slotKey, slotCount
                            end
                        end
                    else
                        -- 槽位已被团长在表格中删空，自愈释放该槽位锁定
                        if IsSlotAuctioned(slotKey) then
                            ClearSlotAuctioned(slotKey)
                        end
                    end
                end
            end
        end
    end
    return false
end
AutoAuctionOnLoot.FindItemInBiaoGeTable = FindItemInBiaoGeTable

-- 判断是否为套装代币 (Token) 或团本指定兑换物
local function IsSetTokenOrRaidItem(itemID, link, name, FB)
    if not itemID then return false end
    local idNum = tonumber(itemID)

    -- 1. BGLite 官方套装兑换物数据库匹配 (ExchangeItems)
    if BG and BG.Loot then
        if FB and BG.Loot[FB] and BG.Loot[FB].ExchangeItems and (BG.Loot[FB].ExchangeItems[itemID] or (idNum and BG.Loot[FB].ExchangeItems[idNum])) then
            return true
        end
        for fbKey, fbData in pairs(BG.Loot) do
            if type(fbData) == "table" and fbData.ExchangeItems and (fbData.ExchangeItems[itemID] or (idNum and fbData.ExchangeItems[idNum])) then
                return true
            end
        end
    end

    -- 2. 官方白名单物品 (如废墟技能书、萨弗拉斯之眼、源质矿石等)
    if BG and BG.Loot and BG.Loot.whitelist and (BG.Loot.whitelist[itemID] or (idNum and BG.Loot.whitelist[idNum])) then
        return true
    end

    -- 3. 套装代币专有名称特征模式匹配（严格限定专属前缀，绝不包含头盔/胸甲等泛用防具槽位词）
    local checkText = name or link or ""
    local isTokenName = checkText:find("失落的") or checkText:find("战败的") or checkText:find("征服者的")
       or checkText:find("保卫者的") or checkText:find("胜利者的") or checkText:find("勇猛") or checkText:find("英雄")
       or checkText:find("圣洁勋服") or checkText:find("圣洁徽记") or checkText:find("北伐奖章") or checkText:find("十字军奖章")
       or checkText:find("代币") or checkText:find("印记") or checkText:find("徽记") or checkText:find("奖章")
       or checkText:find("兑换物")

    if isTokenName then
        local equipLoc = select(9, GetItemInfo(itemID))
        -- 套装兑换物必须为非直接穿戴槽位
        if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP" then
            return true
        elseif checkText:find("失落的") or checkText:find("战败的") or checkText:find("征服者的") or checkText:find("保卫者的") or checkText:find("胜利者的") or checkText:find("印记") then
            return true
        end
    end

    return false
end
ns.IsSetTokenOrRaidItem = IsSetTokenOrRaidItem

-- 检查某件装备是否允许自动拍卖（支持单件装备预设不自动 / 保留人工处理）
function AutoAuctionOnLoot.IsItemAutoEnabled(itemID, FB)
    if not itemID then return false end
    FB = FB or (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"
    local idNum = tonumber(itemID)
    local idStr = tostring(itemID)

    -- 1. 检查总开关
    if BiaoGe and BiaoGe.options and BiaoGe.options.autoAuctionOnLoot == 0 then
        return false
    end

    -- 2. 检查当前副本 FB 的单件装备覆盖配置 (兼容数字与字符串双类型检索)
    if BiaoGe and BiaoGe.auctionPreset and FB and BiaoGe.auctionPreset[FB] and BiaoGe.auctionPreset[FB].autoAuction then
        local autoDB = BiaoGe.auctionPreset[FB].autoAuction
        local setting = (idNum and autoDB[idNum]) or autoDB[idStr]
        if setting == 0 or setting == false then
            return false -- 明确配置为不自动（保留人工处理）
        elseif setting == 1 or setting == true then
            return true  -- 明确配置为自动拍卖
        end
    end

    -- 3. 检查当前选中的副本 currentFB（防止玩家在预设界面设置的副本与实际活动副本存在别名映射差异）
    local curFB = BiaoGe and BiaoGe.auctionPreset and BiaoGe.auctionPreset.currentFB
    if curFB and curFB ~= FB and BiaoGe.auctionPreset[curFB] and BiaoGe.auctionPreset[curFB].autoAuction then
        local autoDB = BiaoGe.auctionPreset[curFB].autoAuction
        local setting = (idNum and autoDB[idNum]) or autoDB[idStr]
        if setting == 0 or setting == false then
            return false
        elseif setting == 1 or setting == true then
            return true
        end
    end

    -- 4. 跨副本检查 fallback（若其他副本配置了不自动，则同样尊重其人工处理设置）
    if BiaoGe and BiaoGe.auctionPreset then
        for fbKey, fbData in pairs(BiaoGe.auctionPreset) do
            if type(fbData) == "table" and fbData.autoAuction then
                local setting = (idNum and fbData.autoAuction[idNum]) or fbData.autoAuction[idStr]
                if setting == 0 or setting == false then
                    return false
                end
            end
        end
    end

    -- 5. 橙装 (Legendary, quality == 5) 出厂保护：默认必须人工处理，除非团长显式配置为开启 (1)
    local _, _, quality = GetItemInfo(itemID)
    if quality == 5 then
        return false -- 橙装默认不自动，保留人工处理
    end

    -- 6. 普通装备默认跟随全局开启
    return true
end

-- 6. 统一的装备加入待拍队列入口
function AutoAuctionOnLoot.QueueItemForAuction(link, explicitBossName, isManualTest, slotKey, requireInTable, count)
    EnsureOptions()
    if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
    if not CanInitiateAuction(isManualTest) then return end
    if not link or link == "" then return end

    local itemID = GetItemInfoInstant(link)
    if not itemID then return end

    -- 绝对物理防御：链接中直接包含白色 |cffffffff 或灰色 |cff9d9d9d 的物品，100% 绝对拦截！
    if not isManualTest and (link:find("|cffffffff") or link:find("|cff9d9d9d")) then
        return
    end

    -- 解析物品详细信息
    local name, _, quality, level, _, _, _, _, _, Texture, _, classID, subclassID, bindType = GetItemInfo(link)
    if not quality then
        -- 本地缓存未就绪时的色值兜底
        if link:find("|cffa335ee") then quality = 4
        elseif link:find("|cffff8000") then quality = 5
        elseif link:find("|cffe6cc80") then quality = 6
        elseif link:find("|cff0070dd") then quality = 3
        else quality = 1 end
    end

    -- 绝对物理防御：灰色(0)和白色(1)物品绝对不进入拍卖流程！
    if not isManualTest and quality and quality <= 1 then
        return
    end

    -- 绿色(2)物品必须是官方白名单物品，否则一律拦截
    if not isManualTest and quality == 2 and not (BG and BG.Loot and BG.Loot.whitelist and (BG.Loot.whitelist[itemID] or (tonumber(itemID) and BG.Loot.whitelist[tonumber(itemID)]))) then
        return
    end

    -- 解析副本
    local FB = (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"

    -- 核心关键机制：必须已被正式【记录进拍卖表格】且未开拍未结账，才展开自动拍卖！
    local inTable, tableBossNum, tableSlot, tableBossName, foundFB, resolvedSlotKey, resolvedCount = FindItemInBiaoGeTable(itemID, link, FB, not isManualTest)
    if not isManualTest and requireInTable and not inTable then
        -- 未入库进金团拍卖表格，或该装备已售出/已开拍过，绝对不展开自动拍卖
        return
    end
    if foundFB then FB = foundFB end
    slotKey = slotKey or resolvedSlotKey
    local finalCount = count or resolvedCount or 1

    -- 绝对防线：若该表格槽位已完成自动拍卖过，终生绝不开拍第二次！
    if not isManualTest and slotKey and IsSlotAuctioned(slotKey) then
        return
    end

    -- 核心：校验单件装备是否配置为【不自动拍卖】（保留最后人工处理）
    if not AutoAuctionOnLoot.IsItemAutoEnabled(itemID, FB) then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite 自动拍卖]|r 装备：%s 已配置为【不自动拍卖】（保留人工处理），已跳过。", link))
        end
        return
    end

    -- 防重复防击穿判断 (基于 slotKey 终生锁池与全局 45 秒防抖池双重防护)
    if IsRecentlyQueued(itemID, link, slotKey) then
        return
    end

    -- 判断是否为套装代币或团本指定拍卖品
    local isSetOrRaid = IsSetTokenOrRaidItem(itemID, link, name, FB)

    if not isSetOrRaid then
        -- 常规非套装物品的过滤检查：
        -- 排除货币/牌子 (classID == 10)
        if classID == 10 then return end
        -- 排除附魔拆解材料 (classID == 7 且 subclassID 为 12 或 0)
        if classID == 7 and (subclassID == 12 or subclassID == 0) then return end
        -- 排除普通消耗品与普通任务物品
        if classID == 0 or classID == 12 or bindType == 4 then return end
        -- 排除黑名单
        if BG and BG.Loot and BG.Loot.blacklist and BG.Loot.blacklist[itemID] then return end
        -- 普通装备必须史诗(紫色 quality >= 4)及以上，小团本允许蓝装(quality >= BG.lootQuality[FB])
        local minQuality = (BG and BG.lootQuality and FB and BG.lootQuality[FB]) or 4
        if quality < minQuality then return end
    else
        -- 是套装兑换物/团本掉落：绝对放行，仅过滤明确的黑名单
        if BG and BG.Loot and BG.Loot.blacklist and BG.Loot.blacklist[itemID] then return end
    end

    -- 解析对应副本及 Boss (优先采用表格中记录的准确 Boss 名称)
    local bossName = tableBossName or explicitBossName

    if not bossName or bossName == "" or bossName == "Boss掉落" then
        if tableBossNum and BG and BG.Boss and FB and BG.Boss[FB] and BG.Boss[FB]["boss" .. tableBossNum] then
            bossName = BG.Boss[FB]["boss" .. tableBossNum].name2 or BG.Boss[FB]["boss" .. tableBossNum].name
        end
    end

    if not bossName or bossName == "" or bossName == "Boss掉落" then
        if BG and BG.Frame and BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
            for b = 1, BG.Maxb[FB] - 1 do
                local maxI = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
                for i = 1, maxI do
                    local cell = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                    if cell then
                        local txt = cell:GetText()
                        if txt and (txt:find("item:" .. itemID) or txt == link) then
                            if BG.Boss and BG.Boss[FB] and BG.Boss[FB]["boss" .. b] then
                                bossName = BG.Boss[FB]["boss" .. b].name2 or BG.Boss[FB]["boss" .. b].name
                            else
                                bossName = "Boss " .. b
                            end
                            break
                        end
                    end
                end
                if bossName and bossName ~= "Boss掉落" then break end
            end
        end

        if (not bossName or bossName == "Boss掉落") and BG and BG.Loot and BG.Loot.itemToBoss and BG.Loot.itemToBoss[FB] then
            local b = BG.Loot.itemToBoss[FB][itemID]
            if b and BG.Boss and BG.Boss[FB] and BG.Boss[FB]["boss" .. b] then
                bossName = BG.Boss[FB]["boss" .. b].name2 or BG.Boss[FB]["boss" .. b].name
            end
        end

        if not bossName or bossName == "" then
            bossName = "Boss掉落"
        end
    end
    bossName = bossName:gsub("\n", "")

    -- 读取预设起拍底价
    local presetMoney, presetTips = nil, nil
    if BG and BG.GetAuctionPreset then
        presetMoney, presetTips = BG.GetAuctionPreset(FB, itemID)
    end

    -- 待拍队列查重：按表格槽位 slotKey 查重，防止同一个格子重复入队；无槽位时按 itemID 和 link 查重
    if slotKey and slotKey ~= "" then
        for _, queued in ipairs(pendingLootQueue) do
            if queued.slotKey == slotKey then
                return
            end
        end
    else
        for _, queued in ipairs(pendingLootQueue) do
            if queued.id == itemID and queued.link == link and (not queued.slotKey or queued.slotKey == "") then
                return
            end
        end
    end

    MarkItemQueued(itemID, link, slotKey)

    tinsert(pendingLootQueue, {
        id = itemID,
        link = link,
        count = finalCount,
        presetMoney = (presetMoney and tonumber(presetMoney) and tonumber(presetMoney) > 0) and tonumber(presetMoney) or nil,
        presetTips = presetTips,
        bossName = bossName,
        slotKey = slotKey,
    })

    if DEFAULT_CHAT_FRAME then
        local countStr = (finalCount and finalCount > 1) and format(" x%d", finalCount) or ""
        DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite 自动拍卖]|r 捕获掉落装备：%s%s（归属【%s】），已加入待拍批次...", link, countStr, bossName))
    end

    -- 1.5 秒防抖窗口合并同 Boss 掉落
    if debounceTimer then
        debounceTimer:Cancel()
    end
    debounceTimer = C_Timer.NewTimer(1.5, ProcessPendingAuctions)
end

-- 7. 触发源 A：CHAT_MSG_LOOT (仅当装备被 BGLite 确认【记录进拍卖表格】后延时捕获)
local lootMsgFrame = CreateFrame("Frame")
lootMsgFrame:RegisterEvent("CHAT_MSG_LOOT")
lootMsgFrame:SetScript("OnEvent", function(self, event, msg, ...)
    if not msg then return end
    EnsureOptions()
    if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
    if not CanInitiateAuction() then return end

    -- 第一道绝对防线：非掉落交互状态拦截（交易中、交易关闭3.5秒内、邮件、商店）直接物理丢弃！
    local isNonLoot, reason = IsNonLootInteractionActive()
    if isNonLoot then
        return
    end

    -- 使用通用超链接正则提取装备链接与可能存在的数量后缀 (如 x2)
    local link, countText = msg:match("(|c%x+|Hitem:%d+.-|h%[.-%]|h|r)%s*x?(%d*)")
    if not link then return end
    local msgCount = tonumber(countText) or 1

    -- 绝对防御：灰白色链接立即丢弃
    if link:find("|cffffffff") or link:find("|cff9d9d9d") then return end

    local itemID = SafeGetItemID(link) or (GetItemInfoInstant and GetItemInfoInstant(link))
    if not itemID then return end

    -- 延时多段对账：等待 BGLite 的 Loot.lua 完成对金团表格 (BiaoGe[FB]) 的自动录入
    -- 阶段1：0.15秒（BGLite 延迟0.10秒写入）
    -- 阶段2：0.40秒（兜底网络延迟或掉帧）
    -- 阶段3：0.80秒（最终超时对账）
    local function TryQueueAfterTableCheck(attempt)
        attempt = attempt or 1
        -- 异步回调中再次检测交易状态（防止在延时窗口内突然打开交易或产生交易事件）
        if IsNonLootInteractionActive() then return end

        local FB = (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"
        -- 严格模式查找：只匹配尚未开拍且未记账结账的有效槽位（排查已被待拍队列占用的槽位）
        local inTable, b, i, bossName, foundFB, slotKey, slotCount = FindItemInBiaoGeTable(itemID, link, FB, true)
        if inTable and slotKey then
            local finalCount = (slotCount and slotCount > 1) and slotCount or msgCount
            AutoAuctionOnLoot.QueueItemForAuction(link, bossName, false, slotKey, true, finalCount)
        elseif attempt < 3 then
            C_Timer.After(attempt == 1 and 0.25 or 0.40, function()
                TryQueueAfterTableCheck(attempt + 1)
            end)
        end
    end

    C_Timer.After(0.15, function()
        TryQueueAfterTableCheck(1)
    end)
end)

-- 8. 触发源 B：BG.AddLootItem 外部调用的额外兜底
if BG and BG.AddLootItem then
    hooksecurefunc(BG, "AddLootItem", function(FB, numb, link, Texture, level, Hope, count, typeID, lootplayer)
        if not link then return end
        EnsureOptions()
        if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
        if not CanInitiateAuction() then return end
        if IsNonLootInteractionActive() then return end

        local bName = nil
        if numb and BG and BG.Boss and FB and BG.Boss[FB] and BG.Boss[FB]["boss" .. numb] then
            bName = BG.Boss[FB]["boss" .. numb].name2 or BG.Boss[FB]["boss" .. numb].name
        end
        -- 外部或手动调用 AddLootItem 录入表格时，延时 0.2 秒待表格写入完成后触发
        C_Timer.After(0.2, function()
            if IsNonLootInteractionActive() then return end
            AutoAuctionOnLoot.QueueItemForAuction(link, bName, false, nil, true, count)
        end)
    end)
end

-- 9. 联动清空表格：当团长清空表格或某 Boss 掉落时，同步释放对应的已拍槽位记忆
if BG and BG.ClearBiaoGeByIndex then
    hooksecurefunc(BG, "ClearBiaoGeByIndex", function(FB, b)
        if not FB or not b then return end
        local db = GetAuctionedSlotsDB()
        local prefix = tostring(FB) .. "_" .. tostring(b) .. "_"
        for k in pairs(db) do
            if k:find("^" .. prefix) then
                db[k] = nil
            end
        end
    end)
end

if BG and BG.ClearBiaoGe then
    hooksecurefunc(BG, "ClearBiaoGe", function(_type, FB)
        local db = GetAuctionedSlotsDB()
        if FB then
            local prefix = tostring(FB) .. "_"
            for k in pairs(db) do
                if k:find("^" .. prefix) then
                    db[k] = nil
                end
            end
        else
            wipe(db)
        end
    end)
end

-- 10. 控制与调试命令 (/bgloot)
SLASH_BGLOOTCMD1 = "/bgloot"
SlashCmdList["BGLOOTCMD"] = function(msg)
    EnsureOptions()
    local arg = msg and msg:trim()
    if arg == "on" then
        BiaoGe.options.autoAuctionOnLoot = 1
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 掉落自动拍卖功能已：|cff00ff00开启|r（默认 5 秒倒计时浮动条）")
    elseif arg == "off" then
        BiaoGe.options.autoAuctionOnLoot = 0
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 掉落自动拍卖功能已：|cffff0000关闭|r")
    elseif arg == "reset" then
        ResetAllAuctionedSlots()
        wipe(recentQueuedItems)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r |cff00ff00已清空全部已自动拍卖槽位记忆，新掉落或重新录入可再次触发自动拍卖。|r")
    elseif arg == "test" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 正在模拟拾取 2 件装备测试自动拍卖...")
        local testItems = {
            { id = 40395, link = "|cffa335ee|Hitem:40395::::::::80:::::::::|h[火炬]|h|r", bossName = "测试 Boss", presetMoney = 1000, slotKey = "test_1", count = 1 },
            { id = 40384, link = "|cffa335ee|Hitem:40384::::::::80:::::::::|h[背叛者的下场]|h|r", bossName = "测试 Boss", presetMoney = nil, slotKey = "test_2", count = 1 },
        }
        local frame = GetOrCreateCountDownFrame()
        frame:StartCountdown(testItems, "测试 Boss")
    elseif arg == "testsame" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 正在模拟拾取 2 件相同装备测试自动拍卖...")
        local testItems = {
            { id = 40395, link = "|cffa335ee|Hitem:40395::::::::80:::::::::|h[火炬]|h|r", bossName = "测试 Boss", presetMoney = 1000, slotKey = "test_same_1", count = 1 },
            { id = 40395, link = "|cffa335ee|Hitem:40395::::::::80:::::::::|h[火炬]|h|r", bossName = "测试 Boss", presetMoney = 1000, slotKey = "test_same_2", count = 1 },
        }
        local frame = GetOrCreateCountDownFrame()
        frame:StartCountdown(testItems, "测试 Boss")
    elseif arg and arg:find("|Hitem:") then
        -- 直接支持命令后跟装备超链接测试
        local link = arg:match("(|c%x+|Hitem:%d+.-|h%[.-%]|h|r)")
        if link then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 手动注入装备测试：" .. link)
            AutoAuctionOnLoot.QueueItemForAuction(link, "手动测试", true)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[BGLite]|r 未识别出有效的装备链接。")
        end
    else
        local statusStr = (BiaoGe.options.autoAuctionOnLoot == 1) and "|cff00ff00开启|r" or "|cffff0000关闭|r"
        local instantStr = (BiaoGe.options.autoAuctionInstant == 1) and "|cffff8000极速秒拍|r" or "|cff00ff005秒倒计时确认|r"
        local canAuction = CanInitiateAuction() and "|cff00ff00拥有发起权限|r" or "|cffff0000无权限(非团长/非分配者)|r"
        local db = GetAuctionedSlotsDB()
        local slotCount = 0
        for _ in pairs(db) do slotCount = slotCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 掉落自动拍卖状态]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  - 当前功能开关: " .. statusStr)
        DEFAULT_CHAT_FRAME:AddMessage("  - 开拍触发模式: " .. instantStr)
        DEFAULT_CHAT_FRAME:AddMessage("  - 当前团长/分配权限: " .. canAuction)
        DEFAULT_CHAT_FRAME:AddMessage("  - 待拍池当前积压件数: " .. #pendingLootQueue)
        DEFAULT_CHAT_FRAME:AddMessage("  - 已锁定的已拍槽位记忆: " .. slotCount .. " 个")
        DEFAULT_CHAT_FRAME:AddMessage("可用指令：")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot on       - 启用掉落自动拍卖")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot off      - 关闭掉落自动拍卖")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot reset    - 重置已拍槽位记忆(允许重新自动开拍)")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot test     - 模拟 2 件装备弹出倒计时测试")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot [装备]   - 手动输入装备链接测试加入队列")
    end
end
