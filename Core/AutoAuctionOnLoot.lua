local AddonName, ns = ...

local L = ns.L or {}
local AutoAuctionOnLoot = {}
ns.AutoAuctionOnLoot = AutoAuctionOnLoot

-- 1. 配置项缺省自愈与默认开启
local function EnsureOptions()
    BiaoGe = BiaoGe or {}
    BiaoGe.options = BiaoGe.options or {}
    -- 默认开箱即用：默认开启 1（带 5 秒倒计时浮动条确认）
    if BiaoGe.options.autoAuctionOnLoot == nil then
        BiaoGe.options.autoAuctionOnLoot = 1
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

-- 2. 权限与环境校验 (严格限定大型团队副本 Raid，严禁 5 人小队或野外触发)
local function CanInitiateAuction(isManualTest)
    -- 2.1 若为手动测试指令 (/bgloot test)，直接允许通过
    if isManualTest then return true end

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

    -- 2.4 身份检测：必须是团队领袖 (团长) 或 物品分配者 (Master Looter)
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return true
    end

    if IsMasterLooter and IsMasterLooter() then
        return true
    end

    local lootmethod, partyMaster, raidMaster = GetLootMethod()
    if lootmethod == "master" and raidMaster then
        if UnitIsUnit("raid" .. raidMaster, "player") then
            return true
        end
    end

    if BG and (BG.IsML or BG.IsLeader) then
        return true
    end

    return false
end

-- 3. 待拍防抖批处理缓冲池与 45 秒防重击穿池
local pendingLootQueue = {}
local recentQueuedItems = {} -- [itemID .. "_" .. link] = timestamp
local debounceTimer = nil
local countDownFrame = nil

local function IsRecentlyQueued(itemID, link)
    local key = tostring(itemID) .. "_" .. tostring(link or "")
    local now = GetTime()
    if recentQueuedItems[key] and (now - recentQueuedItems[key] < 45) then
        return true
    end
    return false
end

local function MarkItemQueued(itemID, link)
    local key = tostring(itemID) .. "_" .. tostring(link or "")
    recentQueuedItems[key] = GetTime()
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

    -- 仅向团队频道发送一条汇总开拍提示（严禁向 5 人小队 PARTY 频道发送）
    local inRaid = IsInRaid and (IsInRaid(1) or IsInRaid())
    if inRaid then
        local msg = format("[BGLite] 团长已发起【%s】自动拍卖（共 %d 件装备），请在拍卖窗口出价！", bossName or "Boss", #itemsToAuction)
        SendChatMessage(msg, "RAID")
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite]|r 正在为【%s】发起全部 %d 件装备拍卖（平滑发送中，间隔1.2秒）...", bossName or "Boss", #itemsToAuction))
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(format("已发起【%s】共 %d 件装备自动拍卖", bossName or "Boss", #itemsToAuction), 0, 1, 0)
    end

    local delay = 0
    for _, it in ipairs(itemsToAuction) do
        local finalMoney = it.presetMoney or fallbackPrice or 100
        local itemID = it.id
        local link = it.link
        C_Timer.After(delay, function()
            if BG and BG.SendStartAuctionMsg then
                BG.SendStartAuctionMsg(isGen2, itemID, finalMoney, duration, mod, link, resetThreshold)
            end
        end)
        delay = delay + 1.2
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

        local unpresetCount = 0
        for _, it in ipairs(itemsToAuction) do
            if not it.presetMoney then unpresetCount = unpresetCount + 1 end
        end

        self.subText:SetText(format("【%s】共 %d 件", self.bossName, #itemsToAuction))
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

-- 判断是否为套装代币 (Token) 或团本核心掉落拍卖品
local function IsSetTokenOrRaidItem(itemID, link, name, FB)
    if not itemID then return false end

    -- 1. BGLite 官方套装兑换物数据库匹配 (ExchangeItems)
    if BG and BG.Loot then
        -- 优先匹配当前活跃副本的兑换物
        if FB and BG.Loot[FB] and BG.Loot[FB].ExchangeItems and BG.Loot[FB].ExchangeItems[itemID] then
            return true
        end
        -- 全局遍历所有副本的兑换物表兜底
        for fbKey, fbData in pairs(BG.Loot) do
            if type(fbData) == "table" and fbData.ExchangeItems and fbData.ExchangeItems[itemID] then
                return true
            end
        end
    end

    -- 2. 当前副本 Boss 掉落列表或金团表格中存在该物品
    if FB and BG and BG.Frame and BG.Frame[FB] and BG.Maxb and BG.Maxb[FB] then
        for b = 1, BG.Maxb[FB] - 1 do
            local maxI = (BG.GetMaxi and BG.GetMaxi(FB, b)) or 30
            for i = 1, maxI do
                local cell = BG.Frame[FB]["boss" .. b] and BG.Frame[FB]["boss" .. b]["zhuangbei" .. i]
                if cell then
                    local txt = cell:GetText()
                    if txt and (txt:find("item:" .. itemID) or (link and txt == link)) then
                        return true
                    end
                end
            end
        end
    end
    if FB and BG and BG.Loot and BG.Loot.itemToBoss and BG.Loot.itemToBoss[FB] and BG.Loot.itemToBoss[FB][itemID] then
        return true
    end

    -- 3. 白名单物品
    if BG and BG.Loot and BG.Loot.whitelist and BG.Loot.whitelist[itemID] then
        return true
    end

    -- 4. 套装代币名称特征模式匹配（涵盖全版本套装印记、兑换物、奖章）
    local checkText = name or link or ""
    if checkText:find("失落") or checkText:find("战败") or checkText:find("征服者") or checkText:find("保卫者")
       or checkText:find("胜利者") or checkText:find("勇猛") or checkText:find("英雄") or checkText:find("圣洁")
       or checkText:find("北伐") or checkText:find("十字军") or checkText:find("代币") or checkText:find("印记")
       or checkText:find("徽记") or checkText:find("奖章") or checkText:find("之核") or checkText:find("雕像")
       or checkText:find("硬币") or checkText:find("头盔") or checkText:find("胸甲") or checkText:find("护腿")
       or checkText:find("肩铠") or checkText:find("护手") or checkText:find("护腕") or checkText:find("腰带")
       or checkText:find("长靴") then
        return true
    end

    return false
end

-- 6. 统一的装备加入待拍队列入口
function AutoAuctionOnLoot.QueueItemForAuction(link, explicitBossName, isManualTest)
    EnsureOptions()
    if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
    if not CanInitiateAuction(isManualTest) then return end
    if not link or link == "" then return end

    local itemID = GetItemInfoInstant(link)
    if not itemID then return end

    -- 防重复防击穿判断 (45 秒内同一件装备不重复入队)
    if IsRecentlyQueued(itemID, link) then
        return
    end

    -- 解析副本与物品信息
    local FB = (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"
    local name, _, quality, level, _, _, _, _, _, Texture, _, classID, subclassID, bindType = GetItemInfo(link)
    if not quality then
        -- 本地缓存未就绪时的色值兜底
        if link:find("|cffa335ee") then quality = 4
        elseif link:find("|cffff8000") then quality = 5
        elseif link:find("|cffe6cc80") then quality = 6
        elseif link:find("|cff0070dd") then quality = 3
        else quality = 1 end
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
        -- 普通装备必须史诗(紫色 quality >= 4)及以上
        if quality < 4 then return end
    else
        -- 是套装兑换物/团本掉落：绝对放行，仅过滤明确的黑名单
        if BG and BG.Loot and BG.Loot.blacklist and BG.Loot.blacklist[itemID] then return end
    end

    -- 解析对应副本及 Boss
    local bossName = explicitBossName

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

    -- 队列查重
    for _, queued in ipairs(pendingLootQueue) do
        if queued.id == itemID and queued.link == link then
            return
        end
    end

    MarkItemQueued(itemID, link)

    tinsert(pendingLootQueue, {
        id = itemID,
        link = link,
        presetMoney = (presetMoney and tonumber(presetMoney) and tonumber(presetMoney) > 0) and tonumber(presetMoney) or nil,
        presetTips = presetTips,
        bossName = bossName,
    })

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite 自动拍卖]|r 捕获掉落装备：%s（归属【%s】），已加入待拍批次...", link, bossName))
    end

    -- 1.5 秒防抖窗口合并同 Boss 掉落
    if debounceTimer then
        debounceTimer:Cancel()
    end
    debounceTimer = C_Timer.NewTimer(1.5, ProcessPendingAuctions)
end

-- 7. 触发源 A：LOOT_OPENED (摸尸体/打开掉落列表时立即捕获)
local lootOpenedFrame = CreateFrame("Frame")
lootOpenedFrame:RegisterEvent("LOOT_OPENED")
lootOpenedFrame:SetScript("OnEvent", function(self, event, ...)
    EnsureOptions()
    if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
    if not CanInitiateAuction() then return end

    local numItems = GetNumLootItems and GetNumLootItems()
    if not numItems or numItems <= 0 then return end

    local targetName = UnitName("target")
    if not targetName or targetName == "" then
        targetName = "Boss掉落"
    end

    for slot = 1, numItems do
        local link = GetLootSlotLink(slot)
        if link then
            AutoAuctionOnLoot.QueueItemForAuction(link, targetName)
        end
    end
end)

-- 8. 触发源 B：CHAT_MSG_LOOT (装备进包/分配时捕获，采用绝对可靠的通用超链接正则)
local lootMsgFrame = CreateFrame("Frame")
lootMsgFrame:RegisterEvent("CHAT_MSG_LOOT")
lootMsgFrame:SetScript("OnEvent", function(self, event, msg, ...)
    if not msg then return end
    EnsureOptions()
    if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
    if not CanInitiateAuction() then return end

    -- 使用通用超链接正则提取装备链接，完全避开易损坏的本地化全局字符串
    local link = msg:match("(|c%x+|Hitem:%d+.-|h%[.-%]|h|r)")
    if not link then return end

    -- 校验归属：在团队/小队中，仅当该物品属于当前玩家（自己/分配者获得）时触发
    local isMine = false
    if msg:find("你获得了") or msg:find("你收到了") or msg:find("You receive loot") or msg:find("You create") then
        isMine = true
    end
    if not isMine then
        local myName = UnitName("player")
        if myName and msg:find(myName) then
            isMine = true
        end
    end

    -- 若在组队状态且非当前玩家获得，则不在此处重复触发
    if (IsInRaid() or IsInGroup()) and not isMine then
        return
    end

    AutoAuctionOnLoot.QueueItemForAuction(link, nil)
end)

-- 9. 触发源 C：BG.AddLootItem 外部调用的额外兜底
if BG and BG.AddLootItem then
    hooksecurefunc(BG, "AddLootItem", function(FB, numb, link, Texture, level, Hope, count, typeID, lootplayer)
        if not link then return end
        local bName = nil
        if numb and BG and BG.Boss and FB and BG.Boss[FB] and BG.Boss[FB]["boss" .. numb] then
            bName = BG.Boss[FB]["boss" .. numb].name2 or BG.Boss[FB]["boss" .. numb].name
        end
        AutoAuctionOnLoot.QueueItemForAuction(link, bName)
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
    elseif arg == "test" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 正在模拟拾取 2 件装备测试自动拍卖...")
        local testItems = {
            { id = 40395, link = "|cffa335ee|Hitem:40395::::::::80:::::::::|h[火炬]|h|r", bossName = "测试 Boss", presetMoney = 1000 },
            { id = 40384, link = "|cffa335ee|Hitem:40384::::::::80:::::::::|h[背叛者的下场]|h|r", bossName = "测试 Boss", presetMoney = nil },
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
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 掉落自动拍卖状态]|r")
        DEFAULT_CHAT_FRAME:AddMessage("  - 当前功能开关: " .. statusStr)
        DEFAULT_CHAT_FRAME:AddMessage("  - 开拍触发模式: " .. instantStr)
        DEFAULT_CHAT_FRAME:AddMessage("  - 当前团长/分配权限: " .. canAuction)
        DEFAULT_CHAT_FRAME:AddMessage("  - 待拍池当前积压件数: " .. #pendingLootQueue)
        DEFAULT_CHAT_FRAME:AddMessage("可用指令：")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot on       - 启用掉落自动拍卖")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot off      - 关闭掉落自动拍卖")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot test     - 模拟 2 件装备弹出倒计时测试")
        DEFAULT_CHAT_FRAME:AddMessage("  /bgloot [装备]   - 手动输入装备链接测试加入队列")
    end
end
