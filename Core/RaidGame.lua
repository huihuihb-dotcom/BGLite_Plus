if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidGame = {}
ns.RaidGame = RaidGame

--------------------------------------------------------------------------------
-- 1. 常量与规则配置
--------------------------------------------------------------------------------
RaidGame.COMM_PREFIX = "BGL_GAME"

RaidGame.MODES = {
    { id = "TOP1", name = "选最大 (1人)", desc = "取点数最高第 1 名获胜" },
    { id = "TOP2", name = "2个最大 (前2名)", desc = "取点数最高前 2 名获胜" },
    { id = "TOP1_BOTTOM1", name = "1大1小 (双向)", desc = "取点数最高第 1 名与最低第 1 名同时获胜" },
    { id = "TOP3", name = "3个最大 (前3名)", desc = "取点数最高前 3 名获胜" },
    { id = "BOTTOM3", name = "3个最小 (前3名)", desc = "取点数最低前 3 名获胜" },
    { id = "BOTTOM1", name = "选最小 (1人)", desc = "取点数最低第 1 名获胜" },
}

local function GetModeName(modeId)
    for _, m in ipairs(RaidGame.MODES) do
        if m.id == modeId then return m.name end
    end
    return "选最大 (1人)"
end

--------------------------------------------------------------------------------
-- 2. 数据库与默认配置初始化
--------------------------------------------------------------------------------
function ns.InitRaidGameDB()
    BiaoGe = BiaoGe or {}
    BiaoGe.RaidGame = BiaoGe.RaidGame or {}
    local db = BiaoGe.RaidGame

    if db.mode == nil then db.mode = "TOP1" end
    if db.countdown == nil then db.countdown = 30 end
    if db.disallowMultiple == nil then db.disallowMultiple = false end
    if db.autoAnnounce == nil then db.autoAnnounce = true end
    if db.sound == nil then db.sound = true end
    if db.startMessage == nil or db.startMessage == "" then
        db.startMessage = "【团队小游戏】骰子大比拼开始啦！规则：[{rule}]，限时 {time} 秒！请点击骰子按钮或输入 /roll 100 参与！{rule_tip}"
    end

    -- 一次性自愈清洗历史可能残留的 Unicode Emoji 乱码方块与默认选项迁移
    if BG.Once then
        BG.Once("RaidGameCleanEmoji_v110", 2026090401, function()
            db.startMessage = "【团队小游戏】骰子大比拼开始啦！规则：[{rule}]，限时 {time} 秒！请点击骰子按钮或输入 /roll 100 参与！{rule_tip}"
            db.disallowMultiple = false
        end)
    end
end

--------------------------------------------------------------------------------
-- 3. 运行时状态机 (Runtime Game State)
--------------------------------------------------------------------------------
local currentGame = {
    active = false,
    gameId = 0,
    mode = "TOP1",
    totalDuration = 30,
    startTime = 0,
    endTime = 0,
    disallowMultiple = true,
    rolls = {},             -- [playerName] = { name, class, roll, time, count, isDisqualified }
    rollList = {},          -- 顺序列表用于快速遍历与渲染
    winners = {},           -- 计算出的获胜者列表
    disqualifiedList = {},  -- 被取消资格的违规玩家名单
    timerObj = nil,
    tickerObj = nil,
}
RaidGame.currentGame = currentGame

local function CleanPlayerName(name)
    if not name or name == "" then return "" end
    name = tostring(name)
    name = name:gsub("|Hplayer:([^|:]+).-|h.-|h", "%1")
    name = name:gsub("|H.-|h", "")
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("[%[%]]", ""):trim()
    local short = (strsplit("-", name)):trim()
    return short
end

local function GetPlayerClass(name)
    if not name or name == "" then return "PRIEST" end
    local num = GetNumGroupMembers and GetNumGroupMembers() or 0
    if num > 0 then
        for i = 1, num do
            local unit = (IsInRaid and IsInRaid()) and ("raid" .. i) or ("party" .. i)
            if i == num and not IsInRaid() then unit = "player" end
            local uName = UnitName(unit)
            if uName and CleanPlayerName(uName) == name then
                local _, class = UnitClass(unit)
                return class or "PRIEST"
            end
        end
    end
    if name == CleanPlayerName(UnitName("player")) then
        local _, class = UnitClass("player")
        return class or "PRIEST"
    end
    return "PRIEST"
end

local function IsLeaderOrAssistant()
    if not (IsInRaid and IsInRaid()) and not (IsInGroup and IsInGroup()) then
        return true -- 单人模式下允许自由调试测试
    end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- 4. 胜出者算法与排行榜结算 (带多次参与违规剔除与顺延)
--------------------------------------------------------------------------------
function RaidGame.CalculateResults()
    local validList = {}
    local disqList = {}

    for _, entry in pairs(currentGame.rolls) do
        if entry.isDisqualified then
            tinsert(disqList, entry)
        else
            tinsert(validList, entry)
        end
    end

    -- 排序：先按点数，点数相同按完成时间先到先得
    table.sort(validList, function(a, b)
        if a.roll ~= b.roll then
            return a.roll > b.roll
        end
        return a.time < b.time
    end)

    table.sort(disqList, function(a, b)
        return a.time < b.time
    end)

    local winners = {}
    local mode = currentGame.mode
    local count = #validList

    if count > 0 then
        if mode == "TOP1" then
            tinsert(winners, { title = "[最佳手气王]", entry = validList[1] })
        elseif mode == "TOP2" then
            tinsert(winners, { title = "[冠军手气]", entry = validList[1] })
            if validList[2] then
                tinsert(winners, { title = "[亚军手气]", entry = validList[2] })
            end
        elseif mode == "TOP1_BOTTOM1" then
            tinsert(winners, { title = "[最佳手气王]", entry = validList[1] })
            if count > 1 then
                tinsert(winners, { title = "[倒霉小幸运]", entry = validList[count] })
            end
        elseif mode == "TOP3" then
            tinsert(winners, { title = "[冠军手气]", entry = validList[1] })
            if validList[2] then tinsert(winners, { title = "[亚军手气]", entry = validList[2] }) end
            if validList[3] then tinsert(winners, { title = "[季军手气]", entry = validList[3] }) end
        elseif mode == "BOTTOM3" then
            -- 3个最小
            tinsert(winners, { title = "[倒霉蛋一号]", entry = validList[count] })
            if count >= 2 then tinsert(winners, { title = "[倒霉蛋二号]", entry = validList[count - 1] }) end
            if count >= 3 then tinsert(winners, { title = "[倒霉蛋三号]", entry = validList[count - 2] }) end
        elseif mode == "BOTTOM1" then
            tinsert(winners, { title = "[终极倒霉蛋]", entry = validList[count] })
        end
    end

    currentGame.winners = winners
    currentGame.disqualifiedList = disqList
    return winners, disqList, validList
end

--------------------------------------------------------------------------------
-- 5. 团队发言通报模块 (Announce Engine)
--------------------------------------------------------------------------------
function RaidGame.AnnounceResults()
    local winners, disqList, validList = RaidGame.CalculateResults()
    local channel = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or "SAY")
    local totalParticipants = #validList + #disqList

    if totalParticipants == 0 then
        SendChatMessage("【团队小游戏】骰子小游戏已结束，本次无人参与投掷。", channel)
        return
    end

    local ruleName = GetModeName(currentGame.mode)
    SendChatMessage(string.format("【团队小游戏】骰子大比拼结算！规则：[%s]，共 %d 人参与：", ruleName, totalParticipants), channel)

    if #winners > 0 then
        for _, w in ipairs(winners) do
            SendChatMessage(string.format("[获胜] %s：%s 掷出 %d 点！恭喜！", w.title, w.entry.name, w.entry.roll), channel)
        end
    else
        SendChatMessage("[提示] 本轮所有参与者均因违规或无人合格，无有效胜出者。", channel)
    end

    -- 若有违规被剔除资格的玩家，公开通报以示公正
    if #disqList > 0 then
        local names = {}
        for _, d in ipairs(disqList) do
            tinsert(names, d.name .. "(" .. d.roll .. "点/投" .. d.count .. "次)")
        end
        SendChatMessage("[提示] 违规取消资格名单：" .. table.concat(names, "、") .. " (因多次R点已被剔除资格，名额顺延)", channel)
    end
end

--------------------------------------------------------------------------------
-- 6. 插件信道协议支持 (Addon Message Protocol: BGL_GAME)
--------------------------------------------------------------------------------
local commFrame = CreateFrame("Frame")
pcall(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(RaidGame.COMM_PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(RaidGame.COMM_PREFIX)
    end
end)

local function SendGameComm(msg)
    local channel = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or nil)
    if not channel then return end
    pcall(function()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage(RaidGame.COMM_PREFIX, msg, channel)
        elseif SendAddonMessage then
            SendAddonMessage(RaidGame.COMM_PREFIX, msg, channel)
        end
    end)
end

--------------------------------------------------------------------------------
-- 7. 倒计时与游戏启停核心
--------------------------------------------------------------------------------
function RaidGame.StartGame()
    if not IsLeaderOrAssistant() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[BGLite 团队小游戏] 仅团长或助理有权限发起团队小游戏。|r")
        return
    end

    ns.InitRaidGameDB()
    local db = BiaoGe.RaidGame

    -- 重置当前运行数据
    currentGame.active = true
    currentGame.gameId = GetTime()
    currentGame.mode = db.mode or "TOP1"
    currentGame.totalDuration = tonumber(db.countdown) or 30
    currentGame.startTime = GetTime()
    currentGame.endTime = currentGame.startTime + currentGame.totalDuration
    currentGame.disallowMultiple = (db.disallowMultiple ~= false)
    currentGame.rolls = {}
    currentGame.rollList = {}
    currentGame.winners = {}
    currentGame.disqualifiedList = {}

    -- 主动发起 Plus 插件版本查询握手
    if ns.SendPlusVersionCheck then
        ns.SendPlusVersionCheck()
    end

    -- 1. 团队聊天发言开场白
    local ruleName = GetModeName(currentGame.mode)
    local msg = db.startMessage or "【团队小游戏】骰子大比拼开始啦！规则：[{rule}]，限时 {time} 秒！请点击骰子按钮或输入 /roll 100 参与！{rule_tip}"
    local ruleTip = currentGame.disallowMultiple and "(严禁多次R点，多次参与直接取消资格)" or "(仅首次R点成绩有效)"
    if msg:find("{rule_tip}") then
        msg = msg:gsub("{rule_tip}", ruleTip)
    else
        msg = msg:gsub("%(严禁多次R点%)", ruleTip):gsub("%(仅首次R点成绩有效%)", ruleTip)
    end
    msg = msg:gsub("{rule}", ruleName):gsub("{time}", tostring(currentGame.totalDuration))
    local channel = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or "SAY")
    SendChatMessage(msg, channel)

    -- 2. 插件信道广播开始信号 START:gameId:mode:duration:ruleName:disallowMultiple
    local commMsg = string.format("START:%d:%s:%d:%s:%s",
        math.floor(currentGame.gameId),
        currentGame.mode,
        currentGame.totalDuration,
        ruleName,
        currentGame.disallowMultiple and "1" or "0"
    )
    SendGameComm(commMsg)

    -- 3. 本地打开掷骰弹窗
    RaidGame.ShowDicePopup(true)

    -- 4. 启动倒计时定时器与心跳
    if currentGame.timerObj then currentGame.timerObj:Cancel() end
    if currentGame.tickerObj then currentGame.tickerObj:Cancel() end

    currentGame.tickerObj = C_Timer.NewTicker(0.2, function()
        if not currentGame.active then return end
        RaidGame.UpdateUIStatus()
        RaidGame.UpdatePopupTimer()
    end)

    currentGame.timerObj = C_Timer.NewTimer(currentGame.totalDuration, function()
        RaidGame.EndGame(true)
    end)

    -- 播放开始音效
    if db.sound then
        PlaySound(SOUNDKIT.READY_CHECK or 8960)
    end

    RaidGame.UpdateUIStatus()
end

function RaidGame.EndGame(isAutoTimeout)
    if not currentGame.active then return end
    currentGame.active = false

    if currentGame.timerObj then currentGame.timerObj:Cancel(); currentGame.timerObj = nil end
    if currentGame.tickerObj then currentGame.tickerObj:Cancel(); currentGame.tickerObj = nil end

    -- 信道广播结束
    SendGameComm("END:" .. math.floor(currentGame.gameId))

    -- 计算结果
    RaidGame.CalculateResults()

    -- 自动团队通报
    local db = BiaoGe.RaidGame or {}
    if isAutoTimeout and (db.autoAnnounce ~= false) and IsLeaderOrAssistant() then
        RaidGame.AnnounceResults()
    end

    -- 播放结算音效
    if db.sound then
        PlaySound(SOUNDKIT.AUCTION_WINDOW_CLOSE or 895)
    end

    RaidGame.UpdateUIStatus()
    RaidGame.UpdatePopupTimer()
end

function RaidGame.CancelGame()
    if not currentGame.active then return end
    currentGame.active = false

    if currentGame.timerObj then currentGame.timerObj:Cancel(); currentGame.timerObj = nil end
    if currentGame.tickerObj then currentGame.tickerObj:Cancel(); currentGame.tickerObj = nil end

    SendGameComm("CANCEL:" .. math.floor(currentGame.gameId))

    local channel = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or "SAY")
    SendChatMessage("【团队小游戏】团长已中止本次骰子小游戏。", channel)

    RaidGame.UpdateUIStatus()
    RaidGame.UpdatePopupTimer()
    if RaidGame.dicePopup then
        RaidGame.dicePopup:Hide()
    end
end

--------------------------------------------------------------------------------
-- 8. 暴雪系统 Roll 点事件拦截与信道监听
--------------------------------------------------------------------------------
commFrame:RegisterEvent("CHAT_MSG_SYSTEM")
commFrame:RegisterEvent("CHAT_MSG_ADDON")

commFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        if not currentGame.active then return end
        local text = ...
        if not text then return end

        -- 提取掷骰信息，支持各语言与标准格式
        local name, rollVal, minVal, maxVal = nil, nil, nil, nil

        -- 1. 标准中文/繁体/英文模式匹配
        name, rollVal, minVal, maxVal = text:match("^(.+) 掷出 (%d+) %((%d+)%-(%d+)%)")
        if not name then
            name, rollVal, minVal, maxVal = text:match("^(.+) 擲出 (%d+) %((%d+)%-(%d+)%)")
        end
        if not name then
            name, rollVal, minVal, maxVal = text:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)")
        end

        -- 2. 官方 RANDOM_ROLL_RESULT fallback
        if not name and RANDOM_ROLL_RESULT then
            local p = RANDOM_ROLL_RESULT:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"):gsub("%-", "%%-")
            name, rollVal, minVal, maxVal = text:match(p)
        end

        if name and rollVal and minVal and maxVal then
            minVal = tonumber(minVal)
            maxVal = tonumber(maxVal)
            rollVal = tonumber(rollVal)

            -- 必须是标准的 1-100 点掷骰，防止恶意作弊范围
            if minVal == 1 and maxVal == 100 then
                local cleanName = CleanPlayerName(name)
                local now = GetTime()

                if not currentGame.rolls[cleanName] then
                    -- 首次合法投掷
                    local entry = {
                        name = cleanName,
                        class = GetPlayerClass(cleanName),
                        roll = rollVal,
                        time = now,
                        count = 1,
                        isDisqualified = false,
                    }
                    currentGame.rolls[cleanName] = entry
                    tinsert(currentGame.rollList, entry)

                    -- 若是本人，同步刷新本人弹窗状态
                    if cleanName == CleanPlayerName(UnitName("player")) and RaidGame.dicePopup then
                        RaidGame.OnPlayerRolled(rollVal)
                    end
                else
                    -- 重复投掷！
                    local entry = currentGame.rolls[cleanName]
                    entry.count = entry.count + 1

                    if currentGame.disallowMultiple then
                        entry.isDisqualified = true
                        if cleanName == CleanPlayerName(UnitName("player")) then
                            DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[BGLite 团队小游戏] 警告：你进行了多次R点，已直接取消本次获胜资格！|r")
                            if RaidGame.dicePopup then
                                RaidGame.dicePopup.statusText:SetText(BG.STC_r1("已取消资格 (多次R点)"))
                            end
                        end
                    end
                end

                RaidGame.UpdateUIStatus()
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix ~= RaidGame.COMM_PREFIX then return end
        if CleanPlayerName(sender) == CleanPlayerName(UnitName("player")) then return end -- 忽略自己

        local cmd, rest = message:match("^(%w+):?(.*)")
        if cmd == "START" then
            local gId, mode, dur, ruleName, disMul = strsplit(":", rest)
            dur = tonumber(dur) or 30

            currentGame.active = true
            currentGame.gameId = tonumber(gId) or GetTime()
            currentGame.mode = mode or "TOP1"
            currentGame.totalDuration = dur
            currentGame.startTime = GetTime()
            currentGame.endTime = currentGame.startTime + dur
            currentGame.disallowMultiple = (disMul == "1")
            currentGame.rolls = {}
            currentGame.rollList = {}

            -- 自动弹出掷骰面板
            RaidGame.ShowDicePopup(false)

            if currentGame.tickerObj then currentGame.tickerObj:Cancel() end
            currentGame.tickerObj = C_Timer.NewTicker(0.2, function()
                if not currentGame.active then return end
                RaidGame.UpdatePopupTimer()
            end)

            if BiaoGe and BiaoGe.RaidGame and (BiaoGe.RaidGame.sound ~= false) then
                PlaySound(SOUNDKIT.READY_CHECK or 8960)
            end

        elseif cmd == "END" then
            currentGame.active = false
            RaidGame.UpdatePopupTimer()
            if RaidGame.dicePopup and RaidGame.dicePopup:IsShown() then
                RaidGame.dicePopup.rollBtn:Disable()
                RaidGame.dicePopup.rollBtn:SetText(L["已截止"])
            end
        elseif cmd == "CANCEL" then
            currentGame.active = false
            if RaidGame.dicePopup then RaidGame.dicePopup:Hide() end
        end
    end
end)

--------------------------------------------------------------------------------
-- 9. 团队工具底部专区 UI (In-Tool Panel: 965 x 82)
--------------------------------------------------------------------------------
function RaidGame.InitUI(parent)
    if not parent or RaidGame.bottomBar then return end

    local bar = CreateFrame("Frame", "BG_RaidGame_BottomBar", parent, "BackdropTemplate")
    bar:SetSize(965, 82)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -512)
    bar:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bar:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    bar:SetBackdropBorderColor(0.2, 0.7, 1, 0.8)
    RaidGame.bottomBar = bar

    ns.InitRaidGameDB()
    local db = BiaoGe.RaidGame

    ----------------------------------------------------------------------------
    -- 左侧：标题与规则模式选择
    ----------------------------------------------------------------------------
    local iconTitle = bar:CreateFontString(nil, "OVERLAY")
    iconTitle:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    iconTitle:SetPoint("TOPLEFT", 14, -10)
    iconTitle:SetText(BG.STC_g1("团队小游戏 (掷骰大比拼)"))

    -- 模式下拉菜单
    local modeLabel = bar:CreateFontString(nil, "OVERLAY")
    modeLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    modeLabel:SetPoint("TOPLEFT", 14, -36)
    modeLabel:SetText(BG.STC_w1("胜出规则:"))

    local btnMode = BG.CreateButton(bar)
    btnMode:SetSize(130, 22)
    btnMode:SetPoint("LEFT", modeLabel, "RIGHT", 6, 0)
    btnMode:SetText(GetModeName(db.mode))
    bar.btnMode = btnMode

    btnMode:SetScript("OnClick", function(self)
        local menu = {}
        for _, m in ipairs(RaidGame.MODES) do
            tinsert(menu, {
                text = m.name,
                notCheckable = false,
                checked = (BiaoGe.RaidGame.mode == m.id),
                func = function()
                    BiaoGe.RaidGame.mode = m.id
                    btnMode:SetText(m.name)
                    BG.PlaySound(1)
                end,
            })
        end
        local dropDown = BG.dropDown or (LibBG and LibBG.Create_UIDropDownMenu and LibBG:Create_UIDropDownMenu("BG_RaidGame_DropDown", bar))
        if LibBG and LibBG.EasyMenu then
            LibBG:EasyMenu(menu, dropDown, self, 0, 0, "MENU", 2)
        elseif EasyMenu then
            EasyMenu(menu, dropDown, self, 0, 0, "MENU", 2)
        end
    end)

    -- 倒计时时长配置
    local timeLabel = bar:CreateFontString(nil, "OVERLAY")
    timeLabel:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    timeLabel:SetPoint("LEFT", btnMode, "RIGHT", 14, 0)
    timeLabel:SetText(BG.STC_w1("限时:"))

    local btnTime = BG.CreateButton(bar)
    btnTime:SetSize(56, 22)
    btnTime:SetPoint("LEFT", timeLabel, "RIGHT", 5, 0)
    btnTime:SetText(tostring(db.countdown or 30) .. "秒")
    bar.btnTime = btnTime

    btnTime:SetScript("OnClick", function(self)
        local menu = {}
        local durations = { 15, 20, 30, 45, 60 }
        for _, dur in ipairs(durations) do
            tinsert(menu, {
                text = tostring(dur) .. " 秒",
                notCheckable = false,
                checked = (BiaoGe.RaidGame.countdown == dur),
                func = function()
                    BiaoGe.RaidGame.countdown = dur
                    btnTime:SetText(tostring(dur) .. "秒")
                    BG.PlaySound(1)
                end,
            })
        end
        local dropDown = BG.dropDown or (LibBG and LibBG.Create_UIDropDownMenu and LibBG:Create_UIDropDownMenu("BG_RaidGame_DropDown", bar))
        if LibBG and LibBG.EasyMenu then
            LibBG:EasyMenu(menu, dropDown, self, 0, 0, "MENU", 2)
        elseif EasyMenu then
            EasyMenu(menu, dropDown, self, 0, 0, "MENU", 2)
        end
    end)

    -- 禁止多次投掷复选框 (默认不勾选)
    local cbDisallow = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    cbDisallow:SetSize(18, 18)
    cbDisallow:SetPoint("TOPLEFT", 14, -58)
    cbDisallow.text = cbDisallow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbDisallow.text:SetPoint("LEFT", cbDisallow, "RIGHT", 3, 0)
    cbDisallow.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbDisallow.text:SetText(L["禁止多次R点 (多次剔除资格)"])
    cbDisallow:SetChecked(db.disallowMultiple == true)
    cbDisallow:SetHitRectInsets(-2, -cbDisallow.text:GetStringWidth() - 4, -2, -2)
    cbDisallow:SetScript("OnClick", function(self)
        BiaoGe.RaidGame.disallowMultiple = self:GetChecked()
        BG.PlaySound(1)
    end)
    cbDisallow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["禁止多次参与 (公平防作弊)"], 1, 1, 1, true)
        GameTooltip:AddLine(L["勾选后，若有玩家在一次游戏中投掷了2次或以上，直接取消其获胜资格，胜出名额严格按规则顺延给下一位合法玩家，并在通报中公示违规名单。"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    cbDisallow:SetScript("OnLeave", GameTooltip_Hide)

    -- 编辑开场客套话按钮
    local btnEditMsg = BG.CreateButton(bar)
    btnEditMsg:SetSize(86, 20)
    btnEditMsg:SetPoint("LEFT", cbDisallow.text, "RIGHT", 14, 0)
    btnEditMsg:SetText(L["编辑开场语"])
    btnEditMsg:SetScript("OnClick", function()
        RaidGame.OpenStartMessageEditor()
    end)

    ----------------------------------------------------------------------------
    -- 中间：倒计时进度条与统计显示
    ----------------------------------------------------------------------------
    local centerSep = bar:CreateLine()
    centerSep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    centerSep:SetStartPoint("TOPLEFT", 380, -8)
    centerSep:SetEndPoint("BOTTOMLEFT", 380, 8)
    centerSep:SetThickness(1)

    local statusTitle = bar:CreateFontString(nil, "OVERLAY")
    statusTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    statusTitle:SetPoint("TOPLEFT", 395, -12)
    statusTitle:SetText(BG.STC_w1("游戏状态: ") .. BG.STC_dis("未开始"))
    bar.statusTitle = statusTitle

    local statInfo = bar:CreateFontString(nil, "OVERLAY")
    statInfo:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    statInfo:SetPoint("TOPLEFT", 395, -34)
    statInfo:SetText(BG.STC_dis("已投掷: 0 人  (最高: --, 最低: --)"))
    bar.statInfo = statInfo

    -- 倒计时进度条
    local pBar = CreateFrame("StatusBar", nil, bar)
    pBar:SetSize(240, 16)
    pBar:SetPoint("TOPLEFT", 395, -54)
    pBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    pBar:SetStatusBarColor(0.2, 0.8, 1, 0.9)
    pBar:SetMinMaxValues(0, 30)
    pBar:SetValue(0)
    bar.pBar = pBar

    local pBarBg = pBar:CreateTexture(nil, "BACKGROUND")
    pBarBg:SetAllPoints()
    pBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local pBarText = pBar:CreateFontString(nil, "OVERLAY")
    pBarText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    pBarText:SetPoint("CENTER")
    pBarText:SetText("等待发起")
    bar.pBarText = pBarText

    ----------------------------------------------------------------------------
    -- 右侧：团长控制按钮与结算通报
    ----------------------------------------------------------------------------
    local rightSep = bar:CreateLine()
    rightSep:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    rightSep:SetStartPoint("TOPLEFT", 665, -8)
    rightSep:SetEndPoint("BOTTOMLEFT", 665, 8)
    rightSep:SetThickness(1)

    -- 发起/中止按钮
    local btnAction = BG.CreateButton(bar)
    btnAction:SetSize(90, 26)
    btnAction:SetPoint("TOPLEFT", 685, -14)
    btnAction:SetText(BG.STC_g1("发起游戏"))
    bar.btnAction = btnAction

    btnAction:SetScript("OnClick", function()
        if currentGame.active then
            RaidGame.CancelGame()
        else
            RaidGame.StartGame()
        end
        BG.PlaySound(1)
    end)

    -- 手动呼出自己弹窗按钮
    local btnMyDice = BG.CreateButton(bar)
    btnMyDice:SetSize(90, 26)
    btnMyDice:SetPoint("TOPLEFT", 685, -46)
    btnMyDice:SetText("掷骰弹窗")
    btnMyDice:SetScript("OnClick", function()
        RaidGame.ShowDicePopup(false)
        BG.PlaySound(1)
    end)

    -- 团队通报按钮
    local btnAnnounce = BG.CreateButton(bar)
    btnAnnounce:SetSize(85, 26)
    btnAnnounce:SetPoint("TOPLEFT", 785, -14)
    btnAnnounce:SetText(BG.STC_y1("团队通报"))
    bar.btnAnnounce = btnAnnounce
    btnAnnounce:SetScript("OnClick", function()
        RaidGame.AnnounceResults()
        BG.PlaySound(1)
    end)

    -- 完整排行榜按钮
    local btnRank = BG.CreateButton(bar)
    btnRank:SetSize(85, 26)
    btnRank:SetPoint("TOPLEFT", 785, -46)
    btnRank:SetText("完整榜单")
    btnRank:SetScript("OnClick", function()
        RaidGame.ToggleLeaderboard()
        BG.PlaySound(1)
    end)

    -- 帮助说明问号
    local helpBtn = CreateFrame("Button", nil, bar)
    helpBtn:SetSize(20, 20)
    helpBtn:SetPoint("TOPRIGHT", -8, -8)
    local hText = helpBtn:CreateFontString(nil, "OVERLAY")
    hText:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    hText:SetPoint("CENTER")
    hText:SetText(BG.STC_w1("?"))
    helpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(BG.STC_g1("团队小游戏 (R点/骰子) 说明"), 1, 1, 1, true)
        GameTooltip:AddLine("1. 团长或助理配置好胜出规则和限时后，点击【发起游戏】即可启动全团小游戏。", 1, 0.82, 0, true)
        GameTooltip:AddLine("2. 全团装有插件的成员将自动弹出【幸运掷骰】面板，点击按钮即可一键投掷。", 1, 0.82, 0, true)
        GameTooltip:AddLine("3. 若玩家关闭了弹窗，可输入命令 /bgroll 或 /bggame 重新呼出。", 1, 0.82, 0, true)
        GameTooltip:AddLine("4. 未安装插件的队员直接在聊天框输入 /roll 100 同样会自动纳入统计与排名。", 1, 0.82, 0, true)
        GameTooltip:AddLine("5. 倒计时结束后自动截止，并自动在团队频道通报获奖名单。", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    helpBtn:SetScript("OnLeave", GameTooltip_Hide)

    RaidGame.UpdateUIStatus()
end

--------------------------------------------------------------------------------
-- 10. UI 状态刷新
--------------------------------------------------------------------------------
function RaidGame.UpdateUIStatus()
    local bar = RaidGame.bottomBar
    if not bar or not bar:IsVisible() then return end

    if currentGame.active then
        bar.btnAction:SetText(BG.STC_r1("中止游戏"))
        bar.statusTitle:SetText(BG.STC_w1("游戏状态: ") .. BG.STC_g1("正在进行中..."))

        local remain = math.max(0, math.ceil(currentGame.endTime - GetTime()))
        bar.pBar:SetMinMaxValues(0, currentGame.totalDuration)
        bar.pBar:SetValue(remain)
        bar.pBarText:SetText(string.format("剩余 %d 秒", remain))

        if remain <= 5 then
            bar.pBar:SetStatusBarColor(1, 0.2, 0.2, 0.9)
        else
            bar.pBar:SetStatusBarColor(0.2, 0.8, 1, 0.9)
        end
    else
        bar.btnAction:SetText(BG.STC_g1("发起游戏"))
        bar.statusTitle:SetText(BG.STC_w1("游戏状态: ") .. BG.STC_dis("等待发起"))
        bar.pBar:SetValue(0)
        bar.pBarText:SetText("未在进行中")
        bar.pBar:SetStatusBarColor(0.3, 0.3, 0.3, 0.5)
    end

    -- 统计参与人数与极值
    local count = 0
    local maxR = -1
    local minR = 101
    for _, entry in pairs(currentGame.rolls) do
        count = count + 1
        if not entry.isDisqualified then
            if entry.roll > maxR then maxR = entry.roll end
            if entry.roll < minR then minR = entry.roll end
        end
    end

    local maxStr = (maxR >= 0) and tostring(maxR) or "--"
    local minStr = (minR <= 100) and tostring(minR) or "--"
    bar.statInfo:SetText(string.format("已投掷: %s 人 (最高:%s 最低:%s)",
        BG.STC_g1(tostring(count)),
        BG.STC_y1(maxStr),
        BG.STC_w1(minStr)
    ))
end

--------------------------------------------------------------------------------
-- 11. 全员【幸运掷骰】独立浮动面板 (Dice Popup Frame)
--------------------------------------------------------------------------------
function RaidGame.CreateDicePopup()
    if RaidGame.dicePopup then return end

    local f = CreateFrame("Frame", "BG_DiceGamePopupFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 190)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    f:SetBackdropBorderColor(0.2, 0.7, 1, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    RaidGame.dicePopup = f

    -- 标题
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText(BG.STC_g1("团队骰子小游戏"))

    -- 关闭按钮
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- 规则说明与防刷警示
    local ruleText = f:CreateFontString(nil, "OVERLAY")
    ruleText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    ruleText:SetPoint("TOP", 0, -32)
    ruleText:SetText(BG.STC_w1("规则: ") .. BG.STC_y1("选最大 (1人)"))
    f.ruleText = ruleText

    local warnText = f:CreateFontString(nil, "OVERLAY")
    warnText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    warnText:SetPoint("TOP", 0, -50)
    warnText:SetText(BG.STC_y1("* 仅首次R点成绩有效，重复投掷不计入成绩。"))
    f.warnText = warnText

    -- 倒计时条
    local timerBar = CreateFrame("StatusBar", nil, f)
    timerBar:SetSize(280, 14)
    timerBar:SetPoint("TOP", 0, -68)
    timerBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    timerBar:SetStatusBarColor(0.2, 0.8, 1, 0.9)
    timerBar:SetMinMaxValues(0, 30)
    timerBar:SetValue(30)
    f.timerBar = timerBar

    local timerBarBg = timerBar:CreateTexture(nil, "BACKGROUND")
    timerBarBg:SetAllPoints()
    timerBarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local timerBarText = timerBar:CreateFontString(nil, "OVERLAY")
    timerBarText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    timerBarText:SetPoint("CENTER")
    timerBarText:SetText("剩余 30 秒")
    f.timerBarText = timerBarText

    -- 中央状态与点数展示
    local statusText = f:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(BIAOGE_TEXT_FONT, 26, "OUTLINE")
    statusText:SetPoint("CENTER", 0, -8)
    statusText:SetText(BG.STC_w1("[  ?  ]"))
    f.statusText = statusText

    -- 投掷按钮 (调用暴雪原生 API: RandomRoll(1, 100)，与聊天窗口骰子按钮行为 100% 一致)
    local rollBtn = BG.CreateButton(f)
    rollBtn:SetSize(140, 32)
    rollBtn:SetPoint("BOTTOM", 0, 15)
    rollBtn:SetText(BG.STC_g1("立即投掷"))
    f.rollBtn = rollBtn

    rollBtn:SetScript("OnClick", function(self)
        if not currentGame.active then return end
        PlaySound(SOUNDKIT.DICE_ROLL or 895)
        f.statusText:SetText(BG.STC_y1("正在掷骰..."))

        if RandomRoll then
            RandomRoll(1, 100)
        else
            local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() or ChatFrame1EditBox
            if eb then
                local old = eb:GetText()
                eb:SetText("/roll 100")
                ChatEdit_SendText(eb, 0)
                eb:SetText(old or "")
            end
        end
    end)
end

function RaidGame.ShowDicePopup(isStart)
    RaidGame.CreateDicePopup()
    local f = RaidGame.dicePopup

    local ruleName = GetModeName(currentGame.mode)
    f.ruleText:SetText(BG.STC_w1("规则: ") .. BG.STC_y1(ruleName))

    if currentGame.disallowMultiple then
        f.warnText:SetText(BG.STC_r1("* 严禁多次R点，多次投掷将直接取消获胜资格！"))
    else
        f.warnText:SetText(BG.STC_y1("* 仅首次R点成绩有效，重复投掷不计入成绩。"))
    end

    local myName = CleanPlayerName(UnitName("player"))
    local myEntry = currentGame.rolls[myName]

    if myEntry then
        if myEntry.isDisqualified then
            f.statusText:SetText(BG.STC_r1("已取消资格 (多次R点)"))
        else
            f.statusText:SetText(BG.STC_y1("已投出: ") .. BG.STC_g1(tostring(myEntry.roll) .. " 点"))
        end
        f.rollBtn:Disable()
        f.rollBtn:SetText(L["已完成投掷"])
    else
        if currentGame.active then
            f.statusText:SetText(BG.STC_w1("[  ?  ]"))
            f.rollBtn:Enable()
            f.rollBtn:SetText(BG.STC_g1("立即投掷"))
        else
            f.statusText:SetText(BG.STC_dis("未在进行中"))
            f.rollBtn:Disable()
            f.rollBtn:SetText(L["未开始"])
        end
    end

    f:Show()
    RaidGame.UpdatePopupTimer()
end

function RaidGame.OnPlayerRolled(rollValue)
    if not RaidGame.dicePopup then return end
    local f = RaidGame.dicePopup
    f.statusText:SetText(BG.STC_y1("已投出: ") .. BG.STC_g1(tostring(rollValue) .. " 点"))
    f.rollBtn:Disable()
    f.rollBtn:SetText(L["已完成投掷"])
end

function RaidGame.UpdatePopupTimer()
    if not RaidGame.dicePopup or not RaidGame.dicePopup:IsShown() then return end
    local f = RaidGame.dicePopup

    if currentGame.active then
        local remain = math.max(0, math.ceil(currentGame.endTime - GetTime()))
        f.timerBar:SetMinMaxValues(0, currentGame.totalDuration)
        f.timerBar:SetValue(remain)
        f.timerBarText:SetText(string.format("限时倒计时: %d 秒", remain))

        if remain <= 5 then
            f.timerBar:SetStatusBarColor(1, 0.2, 0.2, 0.9)
        else
            f.timerBar:SetStatusBarColor(0.2, 0.8, 1, 0.9)
        end

        if remain == 0 then
            f.rollBtn:Disable()
            f.rollBtn:SetText(L["已截止"])
        end
    else
        f.timerBar:SetValue(0)
        f.timerBarText:SetText("游戏已截止")
        f.timerBar:SetStatusBarColor(0.4, 0.4, 0.4, 0.5)
        f.rollBtn:Disable()
        f.rollBtn:SetText(L["已截止"])
    end
end

--------------------------------------------------------------------------------
-- 12. 详细排行榜抽屉/弹窗 (Leaderboard Modal)
--------------------------------------------------------------------------------
function RaidGame.ToggleLeaderboard()
    if RaidGame.rankModal and RaidGame.rankModal:IsShown() then
        RaidGame.rankModal:Hide()
        return
    end

    if not RaidGame.rankModal then
        local m = CreateFrame("Frame", "BG_DiceGameRankModal", UIParent, "BackdropTemplate")
        m:SetSize(360, 340)
        m:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        m:SetFrameStrata("DIALOG")
        m:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        m:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
        m:SetBackdropBorderColor(0.3, 0.8, 1, 1)
        m:EnableMouse(true)
        m:SetMovable(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", m.StartMoving)
        m:SetScript("OnDragStop", m.StopMovingOrSizing)
        RaidGame.rankModal = m

        local title = m:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
        title:SetPoint("TOP", 0, -12)
        title:SetText(BG.STC_g1("骰子小游戏 - 完整排名榜"))

        local closeBtn = CreateFrame("Button", nil, m, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() m:Hide() end)

        local sf = CreateFrame("ScrollFrame", "BG_DiceGameRankScroll", m, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -38)
        sf:SetPoint("BOTTOMRIGHT", -30, 42)
        m.sf = sf

        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(315, 1)
        sf:SetScrollChild(content)
        m.content = content

        -- 底部通报按钮
        local btnAnn = BG.CreateButton(m)
        btnAnn:SetSize(110, 24)
        btnAnn:SetPoint("BOTTOM", 0, 10)
        btnAnn:SetText(BG.STC_y1("团队通报"))
        btnAnn:SetScript("OnClick", function()
            RaidGame.AnnounceResults()
            BG.PlaySound(1)
        end)
    end

    RaidGame.RenderLeaderboard()
    RaidGame.rankModal:Show()
    BG.PlaySound(1)
end

function RaidGame.RenderLeaderboard()
    local m = RaidGame.rankModal
    if not m or not m.content then return end
    local content = m.content

    -- 清空旧子项
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local winners, disqList, validList = RaidGame.CalculateResults()
    local y = -2

    -- 渲染有效成绩
    for i, entry in ipairs(validList) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(315, 20)
        row:SetPoint("TOPLEFT", 0, y)

        local rankText = row:CreateFontString(nil, "OVERLAY")
        rankText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        rankText:SetPoint("LEFT", 4, 0)
        if i == 1 then
            rankText:SetText(BG.STC_g1("No.1"))
        elseif i == 2 then
            rankText:SetText(BG.STC_y1("No.2"))
        elseif i == 3 then
            rankText:SetText(BG.STC_w1("No.3"))
        else
            rankText:SetText(BG.STC_dis(string.format("%2d.", i)))
        end

        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        nameText:SetPoint("LEFT", 52, 0)
        nameText:SetText(SetClassCFF(entry.name, entry.class))

        local scoreText = row:CreateFontString(nil, "OVERLAY")
        scoreText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        scoreText:SetPoint("RIGHT", -6, 0)
        if entry.count and entry.count > 1 then
            scoreText:SetText(BG.STC_g1(tostring(entry.roll) .. " 点") .. BG.STC_dis(" (首投有效/共" .. entry.count .. "次)"))
        else
            scoreText:SetText(BG.STC_g1(tostring(entry.roll) .. " 点"))
        end

        y = y - 22
    end

    -- 渲染被取消资格名单
    if #disqList > 0 then
        local sep = content:CreateLine()
        sep:SetColorTexture(0.5, 0.2, 0.2, 0.8)
        sep:SetStartPoint("TOPLEFT", 0, y - 4)
        sep:SetEndPoint("TOPLEFT", 310, y - 4)
        sep:SetThickness(1)
        y = y - 10

        local disTitle = content:CreateFontString(nil, "OVERLAY")
        disTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        disTitle:SetPoint("TOPLEFT", 4, y)
        disTitle:SetText(BG.STC_r1("以下玩家因多次R点已被剔除获胜资格 (名额已顺延):"))
        y = y - 18

        for _, d in ipairs(disqList) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(315, 20)
            row:SetPoint("TOPLEFT", 0, y)

            local tag = row:CreateFontString(nil, "OVERLAY")
            tag:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            tag:SetPoint("LEFT", 4, 0)
            tag:SetText(BG.STC_r1("[违规取消]"))

            local nameText = row:CreateFontString(nil, "OVERLAY")
            nameText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            nameText:SetPoint("LEFT", 72, 0)
            nameText:SetText(SetClassCFF(d.name, d.class))

            local rollText = row:CreateFontString(nil, "OVERLAY")
            rollText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
            rollText:SetPoint("RIGHT", -6, 0)
            rollText:SetText(BG.STC_r1(string.format("首投%d点 (违规投%d次)", d.roll, d.count)))

            y = y - 20
        end
    end

    if #validList == 0 and #disqList == 0 then
        local empty = content:CreateFontString(nil, "OVERLAY")
        empty:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        empty:SetPoint("CENTER", content, "CENTER", 0, -40)
        empty:SetText(BG.STC_dis("暂无投掷数据"))
    end

    content:SetHeight(math.max(150, -y + 10))
end

--------------------------------------------------------------------------------
-- 13. 开场客套话自定义弹窗
--------------------------------------------------------------------------------
function RaidGame.OpenStartMessageEditor()
    local m = CreateFrame("Frame", "BG_DiceGameMsgEditorModal", UIParent, "BackdropTemplate")
    m:SetSize(380, 190)
    m:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    m:SetFrameStrata("DIALOG")
    m:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
    m:SetBackdropBorderColor(0.3, 0.8, 1, 1)
    m:EnableMouse(true)

    local title = m:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText(BG.STC_g1("自定义开场客套话"))

    local tip = m:CreateFontString(nil, "OVERLAY")
    tip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    tip:SetPoint("TOP", 0, -32)
    tip:SetText(BG.STC_dis("支持动态变量: {rule} 胜出规则, {time} 倒计时秒数"))

    local eb = CreateFrame("EditBox", nil, m, BG.editTemplate)
    eb:SetSize(340, 48)
    eb:SetPoint("TOP", 0, -56)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    eb:SetText(BiaoGe.RaidGame.startMessage or "")

    local btnSave = BG.CreateButton(m)
    btnSave:SetSize(80, 24)
    btnSave:SetPoint("BOTTOMLEFT", 60, 16)
    btnSave:SetText(L["保存"])
    btnSave:SetScript("OnClick", function()
        local text = eb:GetText():trim()
        if text ~= "" then
            BiaoGe.RaidGame.startMessage = text
        end
        m:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 团队小游戏] 开场发言已保存！|r")
        BG.PlaySound(1)
    end)

    local btnReset = BG.CreateButton(m)
    btnReset:SetSize(80, 24)
    btnReset:SetPoint("BOTTOMRIGHT", -60, 16)
    btnReset:SetText(L["恢复默认"])
    btnReset:SetScript("OnClick", function()
        BiaoGe.RaidGame.startMessage = "【团队小游戏】骰子大比拼开始啦！规则：[{rule}]，限时 {time} 秒！请点击骰子按钮或输入 /roll 100 参与！(严禁多次R点)"
        eb:SetText(BiaoGe.RaidGame.startMessage)
        BG.PlaySound(1)
    end)

    local closeBtn = CreateFrame("Button", nil, m, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() m:Hide() end)
end

--------------------------------------------------------------------------------
-- 14. 快捷斜杠命令支持 (Slash Commands)
--------------------------------------------------------------------------------
SLASH_BGROLL1 = "/bgroll"
SLASH_BGROLL2 = "/bggame"
SLASH_BGROLL3 = "/bgrgame"
SlashCmdList["BGROLL"] = function(msg)
    RaidGame.ShowDicePopup(false)
end
