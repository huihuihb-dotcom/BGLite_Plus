if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidTool = {}
ns.RaidTool = RaidTool

local MAX_RAID_MEMBERS = 40
local NUM_GROUPS = 8
local MEMBERS_PER_GROUP = 5

--------------------------------------------------------------------------------
-- 1. 数据库与默认配置初始化
--------------------------------------------------------------------------------
function ns.InitRaidToolDB()
    BiaoGe = BiaoGe or {}
    BiaoGe.RaidTool = BiaoGe.RaidTool or {}
    local db = BiaoGe.RaidTool

    if db.debugLog == nil then db.debugLog = false end
    if db.autoInvite == nil then db.autoInvite = false end
    if db.anyMessage == nil then db.anyMessage = false end
    if db.onlyGuild == nil then db.onlyGuild = false end
    if db.autoConvertToRaid == nil then db.autoConvertToRaid = true end
    if db.enableYYLink == nil then db.enableYYLink = true end
    if db.keywords == nil then
        db.keywords = { "123", "111", "1", "+" }
    end

    -- 新成员进组通知配置
    if db.autoWhisperNewMember == nil then db.autoWhisperNewMember = false end
    if db.notifyOnlyLeader == nil then db.notifyOnlyLeader = true end
    if db.whisperNewMemberText == nil then db.whisperNewMemberText = "欢迎进组！请上YY：123456，进组打1" end
    if db.whisperHistory == nil then
        db.whisperHistory = {
            "欢迎进组！请上YY：123456，进组打1",
            "欢迎 {name}！请看心愿单并做好开打准备。",
            "欢迎进组，请先就位确认并准备合剂药水。",
        }
    end

    if db.autoRaidAnnounceNew == nil then db.autoRaidAnnounceNew = false end
    if db.raidAnnounceText == nil then db.raidAnnounceText = "欢迎 {name} 加入团队！yy 123456" end
    if db.raidAnnounceHistory == nil then
        db.raidAnnounceHistory = {
            "欢迎 {name} 加入团队！yy 123456",
            "欢迎 {name} 入团，YY频道：123456，请未上语音的尽快上语音。",
            "欢迎 {name} 进本，本周活动全通团，请检查装备与心愿单。",
        }
    end

    BiaoGe.RaidGroups = BiaoGe.RaidGroups or {}
    local rdb = BiaoGe.RaidGroups
    if rdb.keepPosInGroup == nil then rdb.keepPosInGroup = true end
    if rdb.profiles == nil then
        rdb.profiles = {}
    else
        -- 清理旧版本遗留下来的数字索引与非法数据
        for k, v in pairs(rdb.profiles) do
            if type(k) == "number" or type(v) ~= "table" then
                rdb.profiles[k] = nil
            end
        end
    end
    -- 一次性彻底重置清洗开发测试阶段遗留的脏预设数据
    if BG.Once then
        BG.Once("RaidGroups_ResetLegacyDirtyProfiles_260902", 26090201, function()
            rdb.profiles = {}
            rdb.selectedProfile = nil
        end)
    end
end

-- 统一调试状态获取与设置（全局共享同一个配置）
function RaidTool.IsDebugEnabled()
    if BiaoGe and BiaoGe.RaidTool and BiaoGe.RaidTool.debugLog ~= nil then
        return BiaoGe.RaidTool.debugLog == true or BiaoGe.RaidTool.debugLog == 1
    end
    if BiaoGe and BiaoGe.options and BiaoGe.options.raidToolDebugLog ~= nil then
        return BiaoGe.options.raidToolDebugLog == 1 or BiaoGe.options.raidToolDebugLog == true
    end
    return false
end

function RaidTool.SetDebugEnabled(val)
    local enabled = val and true or false
    if BiaoGe then
        BiaoGe.RaidTool = BiaoGe.RaidTool or {}
        BiaoGe.RaidTool.debugLog = enabled
        BiaoGe.options = BiaoGe.options or {}
        BiaoGe.options.raidToolDebugLog = enabled and 1 or 0
    end
    if BG_RaidTool_LeftPanel_DebugLog then
        BG_RaidTool_LeftPanel_DebugLog:SetChecked(enabled)
    end
    if BG_Button_RaidToolDebugLog then
        BG_Button_RaidToolDebugLog:SetChecked(enabled)
    end
end

-- 统一调试日志打印函数 (受全局 debugLog 配置控制)
function RaidTool.Log(msg, colorHex)
    if RaidTool.IsDebugEnabled() then
        local c = colorHex or "00ff00"
        DEFAULT_CHAT_FRAME:AddMessage("|cff" .. c .. "[BGLite 团队工具] " .. msg .. "|r")
    end
end

--------------------------------------------------------------------------------
-- 2. 组队助手底层引擎 (Invite Engine & New Member Notifier)
--------------------------------------------------------------------------------
local function CleanPlayerName(name)
    if not name or name == "" then return "" end
    name = tostring(name)
    -- 剥离聊天超链接与系统链接代码 |Hplayer:name|h...|h
    name = name:gsub("|Hplayer:([^|:]+).-|h.-|h", "%1")
    name = name:gsub("|H.-|h", "")
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("[%[%]]", ""):trim()
    -- 剥离服务器名后缀 (如 名字-服务器 -> 名字)
    local short = (strsplit("-", name)):trim()
    return short
end

local function GetRosterMemberCount()
    if GetNumGroupMembers and GetNumGroupMembers() > 0 then
        return GetNumGroupMembers()
    elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return GetNumRaidMembers()
    elseif GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then
        return GetNumSubgroupMembers() + 1
    end
    return 0
end

local function IsPlayerInGroup(name)
    if not name or name == "" then return false end
    local short = CleanPlayerName(name)
    local myName = CleanPlayerName(UnitName("player") or "")
    if short == myName then return true end

    if IsInRaid() or (GetNumRaidMembers and GetNumRaidMembers() > 0) then
        local count = (GetNumGroupMembers and GetNumGroupMembers() > 0) and GetNumGroupMembers() or (GetNumRaidMembers and GetNumRaidMembers() or 0)
        for i = 1, count do
            local rName = GetRaidRosterInfo(i) or UnitName("raid" .. i)
            if rName and CleanPlayerName(rName) == short then
                return true
            end
        end
    else
        for i = 1, 4 do
            local pName = UnitName("party" .. i)
            if pName and CleanPlayerName(pName) == short then
                return true
            end
        end
    end
    return false
end

local function CanIInvite()
    if not IsInGroup() then return true end
    if UnitIsGroupLeader("player") then return true end
    if IsInRaid() and UnitIsGroupAssistant("player") then return true end
    return false
end

local function IsLeaderOrAssistant()
    if not IsInGroup() then return false end
    if UnitIsGroupLeader("player") then return true end
    if IsInRaid() and UnitIsGroupAssistant("player") then return true end
    return false
end

local recentlyInvited = {}

local function DoInvite(sender)
    if not sender or sender == "" then return end
    if InCombatLockdown() then return end

    local db = BiaoGe and BiaoGe.RaidTool
    if not db or not db.autoInvite then return end

    if not CanIInvite() then
        return
    end

    local shortName = CleanPlayerName(sender)
    local myName = CleanPlayerName(UnitName("player") or "")
    if shortName == myName then return end

    if IsPlayerInGroup(shortName) then return end

    local now = GetTime()
    if recentlyInvited[shortName] and (now - recentlyInvited[shortName] < 3) then
        return
    end
    recentlyInvited[shortName] = now

    if db.onlyGuild and not UnitIsInMyGuild(shortName) then
        return
    end

    if db.autoConvertToRaid and not IsInRaid() and GetRosterMemberCount() >= 4 then
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then
            C_PartyInfo.ConvertToRaid()
        elseif ConvertToRaid then
            ConvertToRaid()
        end
    end

    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(shortName)
    elseif InviteUnit then
        InviteUnit(shortName)
    end
    RaidTool.Log("收到来自 [" .. shortName .. "] 的密语邀请请求，已发出邀请！")
end

local function HandleIncomingChatMessage(msg, sender)
    local db = BiaoGe and BiaoGe.RaidTool
    if not db or not db.autoInvite then return end
    if not sender or sender == "" then return end

    local myName = CleanPlayerName(UnitName("player") or "")
    if CleanPlayerName(sender) == myName then return end

    msg = (msg or ""):lower():trim()

    if db.anyMessage then
        DoInvite(sender)
        return
    end

    for _, kw in ipairs(db.keywords or {}) do
        local target = (kw or ""):lower():trim()
        if target ~= "" then
            -- 使用 plain = true 纯文本匹配，彻底避免 '+' 等特殊字符导致 Lua 正则崩溃
            if msg == target or msg:find(target, 1, true) then
                DoInvite(sender)
                return
            end
        end
    end
end

-- 严格仅监听密语消息 (CHAT_MSG_WHISPER & CHAT_MSG_BN_WHISPER)，绝不监听公屏与白字
local inviteEventFrame = CreateFrame("Frame")
inviteEventFrame:RegisterEvent("CHAT_MSG_WHISPER")
inviteEventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
inviteEventFrame:SetScript("OnEvent", function(self, event, msg, sender, ...)
    if event == "CHAT_MSG_BN_WHISPER" then
        local bnetIDAccount = select(11, ...)
        if bnetIDAccount and C_BattleNet and C_BattleNet.GetAccountInfoByID then
            local accountInfo = C_BattleNet.GetAccountInfoByID(bnetIDAccount)
            if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.characterName then
                sender = accountInfo.gameAccountInfo.characterName
            end
        end
    end
    HandleIncomingChatMessage(msg, sender)
end)

-- 新进队成员自动通知监听引擎 (严密防抖 + 状态安全校验)
local recentlyNotified = {}
local knownRosterMembers = {}
local isFirstRosterScan = true

local function SendNewMemberNotification(targetName)
    if not targetName or targetName == "" then return end
    local cleanName = CleanPlayerName(targetName)
    local myName = CleanPlayerName(UnitName("player") or "")
    if cleanName == "" or cleanName == myName then return end

    local db = BiaoGe and BiaoGe.RaidTool
    if not db then return end

    -- 若开启了仅限团长/助理，且当前不是团长或助理，则直接拦截
    if db.notifyOnlyLeader and not IsLeaderOrAssistant() then
        return
    end

    local now = GetTime()
    if recentlyNotified[cleanName] and (now - recentlyNotified[cleanName] < 8) then
        return
    end
    recentlyNotified[cleanName] = now

    -- 延时 1.0 秒，确保客户端与服务器小队/团队成员路由完全就绪
    C_Timer.After(1.0, function()
        -- 再次校验：确保该玩家当前仍在队伍中，且自身仍为团长/助理
        if not IsPlayerInGroup(cleanName) then return end
        if db.notifyOnlyLeader and not IsLeaderOrAssistant() then return end

        -- 1. 自动密语
        if db.autoWhisperNewMember and db.whisperNewMemberText and db.whisperNewMemberText ~= "" then
            local wMsg = db.whisperNewMemberText:gsub("{name}", cleanName)
            SendChatMessage(wMsg, "WHISPER", nil, cleanName)
            RaidTool.Log("已向新成员 [" .. cleanName .. "] 发送进组密语。")
        end

        -- 2. 自动团队/小队发言
        if db.autoRaidAnnounceNew and db.raidAnnounceText and db.raidAnnounceText ~= "" then
            local rMsg = db.raidAnnounceText:gsub("{name}", cleanName)
            local channel = nil
            if IsInRaid and IsInRaid() then
                channel = "RAID"
            elseif (GetNumRaidMembers and GetNumRaidMembers() > 0) then
                channel = "RAID"
            elseif IsInGroup and IsInGroup() then
                channel = "PARTY"
            elseif (GetNumSubgroupMembers and GetNumSubgroupMembers() > 0) then
                channel = "PARTY"
            elseif (GetNumGroupMembers and GetNumGroupMembers() > 0) then
                channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
            end

            if channel then
                SendChatMessage(rMsg, channel)
                RaidTool.Log("已在 " .. (channel == "RAID" and "团队" or "小队") .. " 频道发送进组欢迎公告。")
            end
        end
    end)
end

local notifyFrame = CreateFrame("Frame")
notifyFrame:RegisterEvent("CHAT_MSG_SYSTEM")
notifyFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
notifyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
notifyFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        isFirstRosterScan = true
        wipe(knownRosterMembers)
        return
    end

    local db = BiaoGe and BiaoGe.RaidTool
    if not db or (not db.autoWhisperNewMember and not db.autoRaidAnnounceNew) then
        return
    end
    if db.notifyOnlyLeader and not IsLeaderOrAssistant() then
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        local msg = select(1, ...)
        if msg then
            local p = msg:match("^(.-)加入了队伍") or msg:match("^(.-)加入了團隊") or msg:match("^(.-)加入了团队") or msg:match("^(.-)加入了隊伍")
            if not p and ERR_JOINED_GROUP_S then
                p = msg:match(ERR_JOINED_GROUP_S:gsub("%%s", "(.+)"))
            end
            if not p and ERR_RAID_MEMBER_ADDED_S then
                p = msg:match(ERR_RAID_MEMBER_ADDED_S:gsub("%%s", "(.+)"))
            end
            if p then
                SendNewMemberNotification(p)
            end
        end
        return
    end

    -- GROUP_ROSTER_UPDATE 差异比对兜底
    local memberCount = GetRosterMemberCount()
    if memberCount == 0 then
        wipe(knownRosterMembers)
        isFirstRosterScan = true
        return
    end

    local currentMembers = {}
    local newMembers = {}
    local myName = CleanPlayerName(UnitName("player") or "")

    if IsInRaid() or (GetRaidRosterInfo and GetRaidRosterInfo(1)) then
        for i = 1, memberCount do
            local name = GetRaidRosterInfo(i) or UnitName("raid" .. i)
            if name and name ~= "" then
                local shortName = CleanPlayerName(name)
                if shortName ~= "" then
                    currentMembers[shortName] = name
                    if not isFirstRosterScan and not knownRosterMembers[shortName] and shortName ~= myName then
                        tinsert(newMembers, shortName)
                    end
                end
            end
        end
    else
        if myName ~= "" then
            currentMembers[myName] = myName
        end
        for i = 1, 4 do
            local partName = UnitName("party" .. i)
            if partName and partName ~= "" then
                local shortName = CleanPlayerName(partName)
                if shortName ~= "" then
                    currentMembers[shortName] = partName
                    if not isFirstRosterScan and not knownRosterMembers[shortName] and shortName ~= myName then
                        tinsert(newMembers, shortName)
                    end
                end
            end
        end
    end

    if isFirstRosterScan then
        isFirstRosterScan = false
        knownRosterMembers = currentMembers
        return
    end

    for _, nName in ipairs(newMembers) do
        SendNewMemberNotification(nName)
    end

    knownRosterMembers = currentMembers
end)

--------------------------------------------------------------------------------
-- 3. 阵容助手核心调队状态机 (Roster Optimizer Engine)
--------------------------------------------------------------------------------
local RosterState = {
    isProcessing = false,
    targetGroup = {},
    targetPosInGroup = {},
    lockedUnit = {},
    groupsReady = false,
}

local rosterEventFrame = CreateFrame("Frame")

function RaidTool.StopProcessRoster(msg)
    RosterState.isProcessing = false
    RosterState.targetGroup = {}
    RosterState.targetPosInGroup = {}
    RosterState.lockedUnit = {}
    RosterState.groupsReady = false
    rosterEventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    if msg then
        RaidTool.Log(msg, "00BFFF")
    end
    if RaidTool.SyncCurrentRaidRoster then
        RaidTool.SyncCurrentRaidRoster(true)
    end
end

function RaidTool.ProcessRosterStep()
    if not RosterState.isProcessing then return end
    if InCombatLockdown() then
        RaidTool.StopProcessRoster("|cffff2020战斗已发生，阵容调整自动中止。|r")
        return
    end

    local numMembers = GetRosterMemberCount()
    if numMembers == 0 then
        RaidTool.StopProcessRoster()
        return
    end

    local needGroup = RosterState.targetGroup
    local needPosInGroup = RosterState.targetPosInGroup
    local lockedUnit = RosterState.lockedUnit

    local currentGroup = {}
    local currentPos = {}
    local nameToRaidIndex = {}
    local groupSize = {}
    for i = 1, NUM_GROUPS do groupSize[i] = 0 end

    for i = 1, numMembers do
        local name, rank, subgroup = GetRaidRosterInfo(i)
        name = name or UnitName("raid" .. i)
        if name then
            local shortName = CleanPlayerName(name)
            local key = needGroup[name] and name or shortName
            subgroup = subgroup or 1
            currentGroup[key] = subgroup
            nameToRaidIndex[key] = i
            groupSize[subgroup] = (groupSize[subgroup] or 0) + 1
            currentPos[key] = groupSize[subgroup]
        end
    end

    -- 阶段 1：移动到未满 5 人的小队
    if not RosterState.groupsReady then
        local moved = false
        for unit, targetGrp in pairs(needGroup) do
            local curGrp = currentGroup[unit]
            if curGrp and curGrp ~= targetGrp and (groupSize[targetGrp] or 0) < MEMBERS_PER_GROUP then
                local raidIdx = nameToRaidIndex[unit]
                if raidIdx then
                    SetRaidSubgroup(raidIdx, targetGrp)
                    groupSize[curGrp] = groupSize[curGrp] - 1
                    groupSize[targetGrp] = groupSize[targetGrp] + 1
                    moved = true
                    break
                end
            end
        end
        if moved then return end

        -- 阶段 2：满编跨队对调
        local swapped = false
        for unit, targetGrp in pairs(needGroup) do
            local curGrp = currentGroup[unit]
            if curGrp and curGrp ~= targetGrp then
                local unitToSwap = nil
                for otherUnit, otherGrp in pairs(currentGroup) do
                    if otherGrp == targetGrp and needGroup[otherUnit] ~= targetGrp then
                        unitToSwap = otherUnit
                        break
                    end
                end
                if unitToSwap and nameToRaidIndex[unit] and nameToRaidIndex[unitToSwap] then
                    SwapRaidSubgroup(nameToRaidIndex[unit], nameToRaidIndex[unitToSwap])
                    swapped = true
                    break
                end
            end
        end
        if swapped then return end

        RosterState.groupsReady = true
    end

    -- 阶段 3：保持队伍内精确位置 (skill参考MRT 3-Way Bridge Swap 桥接排序 感谢mrt)
    if next(needPosInGroup) then
        local bridgeSwapped = false
        for unit, targetPos in pairs(needPosInGroup) do
            local curGrp = currentGroup[unit]
            local curPos = currentPos[unit]
            if curGrp and curPos and curPos ~= targetPos and not lockedUnit[unit] then
                local bridgeUnit = nil
                for otherUnit, otherGrp in pairs(currentGroup) do
                    if otherGrp ~= curGrp and not lockedUnit[otherUnit] then
                        bridgeUnit = otherUnit
                        break
                    end
                end

                local sameGroupTargetUnit = nil
                for otherUnit, otherPos in pairs(currentPos) do
                    if currentGroup[otherUnit] == curGrp and otherPos == targetPos and not lockedUnit[otherUnit] then
                        sameGroupTargetUnit = otherUnit
                        break
                    end
                end

                if bridgeUnit and sameGroupTargetUnit and nameToRaidIndex[unit] and nameToRaidIndex[bridgeUnit] and nameToRaidIndex[sameGroupTargetUnit] then
                    lockedUnit[unit] = true
                    SwapRaidSubgroup(nameToRaidIndex[unit], nameToRaidIndex[bridgeUnit])
                    SwapRaidSubgroup(nameToRaidIndex[bridgeUnit], nameToRaidIndex[sameGroupTargetUnit])
                    SwapRaidSubgroup(nameToRaidIndex[unit], nameToRaidIndex[bridgeUnit])
                    bridgeSwapped = true
                    break
                end
            end
        end
        if bridgeSwapped then return end
    end

    RaidTool.StopProcessRoster("|cff00ff00团队阵容已成功应用并调整完毕！|r")
end

rosterEventFrame:SetScript("OnEvent", function(self, event)
    if RosterState.isProcessing then
        C_Timer.After(0.05, function()
            RaidTool.ProcessRosterStep()
        end)
    elseif BG.RaidToolMainFrame and BG.RaidToolMainFrame:IsVisible() then
        if RaidTool.SyncCurrentRaidRoster then
            RaidTool.SyncCurrentRaidRoster(false)
        end
    end
end)

function RaidTool.ApplyRosterProfile(profileList)
    if not profileList or type(profileList) ~= "table" then return end
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[BGLite 团队工具] 战斗中无法调整团队阵容！|r")
        return
    end
    if GetRosterMemberCount() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[BGLite 团队工具] 你当前不在队伍或团队中！|r")
        return
    end

    local needGroup = {}
    local needPosInGroup = {}

    for grp = 1, NUM_GROUPS do
        for pos = 1, MEMBERS_PER_GROUP do
            local idx = (grp - 1) * MEMBERS_PER_GROUP + pos
            local name = profileList[idx]
            if name and name ~= "" and UnitName(name) then
                needGroup[name] = grp
                needPosInGroup[name] = pos
            end
        end
    end

    RosterState.targetGroup = needGroup
    RosterState.targetPosInGroup = needPosInGroup
    RosterState.lockedUnit = {}
    RosterState.groupsReady = false
    RosterState.isProcessing = true

    rosterEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    RaidTool.ProcessRosterStep()
end

--------------------------------------------------------------------------------
-- 4. 团队工具 UI 主界面构建 (UI Construction)
--------------------------------------------------------------------------------
function RaidTool.CreateUI(parent)
    if BG.RaidToolMainFrame then return end
    local mainFrame = CreateFrame("Frame", "BG.RaidToolMainFrame", parent)
    mainFrame:SetAllPoints()
    mainFrame:Hide()
    BG.RaidToolMainFrame = mainFrame

    ns.InitRaidToolDB()

    -- 拖拽光标跟随浮动框
    local dragCursor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dragCursor:SetSize(120, 24)
    dragCursor:SetFrameStrata("TOOLTIP")
    dragCursor:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    dragCursor:SetBackdropColor(0.1, 0.3, 0.6, 0.95)
    dragCursor:SetBackdropBorderColor(0.3, 0.8, 1, 1)
    dragCursor.text = dragCursor:CreateFontString(nil, "OVERLAY")
    dragCursor.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    dragCursor.text:SetPoint("CENTER")
    dragCursor:Hide()

    local dragSourceIndex = nil

    ----------------------------------------------------------------------------
    -- 左侧：组队助手 & 自动发言通知 (Auto Invite & Announce Panel)
    ----------------------------------------------------------------------------
    local leftPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    leftPanel:SetSize(330, 450)
    leftPanel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -60)
    leftPanel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    leftPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    leftPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY")
    leftTitle:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    leftTitle:SetPoint("TOPLEFT", 14, -10)
    leftTitle:SetText(BG.STC_g1(L["组队工具 (自动邀请)"]))

    local cbDebugLog = CreateFrame("CheckButton", "BG_RaidTool_LeftPanel_DebugLog", leftPanel, "UICheckButtonTemplate")
    cbDebugLog:SetSize(16, 16)
    cbDebugLog:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -80, -10)
    cbDebugLog.text = cbDebugLog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbDebugLog.text:SetPoint("LEFT", cbDebugLog, "RIGHT", 2, 0)
    cbDebugLog.text:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    cbDebugLog.text:SetText(L["调试日志"])
    cbDebugLog:SetChecked(RaidTool.IsDebugEnabled())
    cbDebugLog:SetHitRectInsets(-2, -cbDebugLog.text:GetStringWidth() - 4, -2, -2)
    cbDebugLog:SetScript("OnClick", function(self)
        RaidTool.SetDebugEnabled(self:GetChecked())
        BG.PlaySound(1)
    end)
    cbDebugLog:SetScript("OnShow", function(self)
        self:SetChecked(RaidTool.IsDebugEnabled())
    end)

    local leftY = -32

    -- 紧凑型两列 4 开关
    local cbAutoInv = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbAutoInv:SetSize(18, 18)
    cbAutoInv:SetPoint("TOPLEFT", 14, leftY)
    cbAutoInv.text = cbAutoInv:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbAutoInv.text:SetPoint("LEFT", cbAutoInv, "RIGHT", 3, 0)
    cbAutoInv.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbAutoInv.text:SetText(L["开启自动邀请"])
    cbAutoInv:SetChecked(BiaoGe.RaidTool.autoInvite)
    cbAutoInv:SetHitRectInsets(-2, -cbAutoInv.text:GetStringWidth() - 4, -2, -2)
    cbAutoInv:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.autoInvite = self:GetChecked()
        BG.PlaySound(1)
    end)

    local cbAnyMsg = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbAnyMsg:SetSize(18, 18)
    cbAnyMsg:SetPoint("TOPLEFT", 170, leftY)
    cbAnyMsg.text = cbAnyMsg:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbAnyMsg.text:SetPoint("LEFT", cbAnyMsg, "RIGHT", 3, 0)
    cbAnyMsg.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbAnyMsg.text:SetText(L["任意密语进组"])
    cbAnyMsg:SetChecked(BiaoGe.RaidTool.anyMessage)
    cbAnyMsg:SetHitRectInsets(-2, -cbAnyMsg.text:GetStringWidth() - 4, -2, -2)
    cbAnyMsg:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.anyMessage = self:GetChecked()
        BG.PlaySound(1)
    end)

    leftY = leftY - 22

    local cbOnlyGuild = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbOnlyGuild:SetSize(18, 18)
    cbOnlyGuild:SetPoint("TOPLEFT", 14, leftY)
    cbOnlyGuild.text = cbOnlyGuild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbOnlyGuild.text:SetPoint("LEFT", cbOnlyGuild, "RIGHT", 3, 0)
    cbOnlyGuild.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbOnlyGuild.text:SetText(L["仅限公会成员"])
    cbOnlyGuild:SetChecked(BiaoGe.RaidTool.onlyGuild)
    cbOnlyGuild:SetHitRectInsets(-2, -cbOnlyGuild.text:GetStringWidth() - 4, -2, -2)
    cbOnlyGuild:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.onlyGuild = self:GetChecked()
        BG.PlaySound(1)
    end)

    local cbAutoRaid = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbAutoRaid:SetSize(18, 18)
    cbAutoRaid:SetPoint("TOPLEFT", 170, leftY)
    cbAutoRaid.text = cbAutoRaid:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbAutoRaid.text:SetPoint("LEFT", cbAutoRaid, "RIGHT", 3, 0)
    cbAutoRaid.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbAutoRaid.text:SetText(L["满5人转团队"])
    cbAutoRaid:SetChecked(BiaoGe.RaidTool.autoConvertToRaid)
    cbAutoRaid:SetHitRectInsets(-2, -cbAutoRaid.text:GetStringWidth() - 4, -2, -2)
    cbAutoRaid:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.autoConvertToRaid = self:GetChecked()
        BG.PlaySound(1)
    end)

    leftY = leftY - 26

    -- 密语关键字标签区
    local tagContainer = CreateFrame("Frame", nil, leftPanel)
    tagContainer:SetSize(305, 48)
    tagContainer:SetPoint("TOPLEFT", 14, leftY)

    local activeTags = {}

    local function RenderKeywordTags()
        for _, tag in ipairs(activeTags) do tag:Hide() end
        wipe(activeTags)

        local x, y = 0, 0
        local maxWidth = 305
        local rowHeight = 22

        for idx, kw in ipairs(BiaoGe.RaidTool.keywords or {}) do
            local tag = CreateFrame("Button", nil, tagContainer, "BackdropTemplate")
            tag:SetHeight(18)
            tag:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            tag:SetBackdropColor(0.12, 0.28, 0.45, 0.9)
            tag:SetBackdropBorderColor(0.2, 0.7, 1, 0.85)

            local txt = tag:CreateFontString(nil, "OVERLAY")
            txt:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
            txt:SetPoint("LEFT", 5, 0)
            txt:SetText(kw .. "  |cffff5555×|r")

            local tagW = txt:GetStringWidth() + 10
            tag:SetWidth(tagW)

            if x + tagW > maxWidth then
                x = 0
                y = y - rowHeight
            end

            tag:SetPoint("TOPLEFT", tagContainer, "TOPLEFT", x, y)
            x = x + tagW + 4

            tag:SetScript("OnClick", function()
                table.remove(BiaoGe.RaidTool.keywords, idx)
                RenderKeywordTags()
                BG.PlaySound(1)
            end)

            tinsert(activeTags, tag)
        end
    end

    RenderKeywordTags()

    leftY = leftY - 50

    local addEditBox = CreateFrame("EditBox", nil, leftPanel, BG.editTemplate)
    addEditBox:SetSize(175, 20)
    addEditBox:SetPoint("TOPLEFT", 14, leftY)
    addEditBox:SetAutoFocus(false)
    addEditBox:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")

    local tipText = addEditBox:CreateFontString(nil, "OVERLAY")
    tipText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    tipText:SetPoint("LEFT", 5, 0)
    tipText:SetTextColor(0.5, 0.5, 0.5)
    tipText:SetText(L["输入新关键字并回车..."])

    addEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then tipText:Hide() else tipText:Show() end
    end)

    local function CommitNewKeyword()
        local text = addEditBox:GetText():trim()
        if text and text ~= "" then
            local exists = false
            for _, kw in ipairs(BiaoGe.RaidTool.keywords) do
                if kw == text then exists = true; break end
            end
            if not exists then
                tinsert(BiaoGe.RaidTool.keywords, text)
                RenderKeywordTags()
                BG.PlaySound(1)
            end
            addEditBox:SetText("")
            addEditBox:ClearFocus()
        end
    end

    addEditBox:SetScript("OnEnterPressed", CommitNewKeyword)
    addEditBox:SetScript("OnSpacePressed", CommitNewKeyword)

    local btnAddTag = BG.CreateButton(leftPanel)
    btnAddTag:SetSize(65, 20)
    btnAddTag:SetPoint("LEFT", addEditBox, "RIGHT", 5, 0)
    btnAddTag:SetText(L["添加标签"])
    btnAddTag:SetScript("OnClick", CommitNewKeyword)

    leftY = leftY - 24

    local quickPresets = { "123", "111", "1", "+", "组" }
    local qX = 14
    for _, presetWord in ipairs(quickPresets) do
        local qBtn = BG.CreateButton(leftPanel)
        qBtn:SetSize(40, 18)
        qBtn:SetPoint("TOPLEFT", qX, leftY)
        qBtn:SetText(presetWord)
        qBtn:SetScript("OnClick", function()
            local exists = false
            for _, kw in ipairs(BiaoGe.RaidTool.keywords) do
                if kw == presetWord then exists = true; break end
            end
            if not exists then
                tinsert(BiaoGe.RaidTool.keywords, presetWord)
                RenderKeywordTags()
                BG.PlaySound(1)
            end
        end)
        qX = qX + 44
    end

    leftY = leftY - 26

    ----------------------------------------------------------------------------
    -- 下半部分：新成员进组自动发言与密语通知
    ----------------------------------------------------------------------------
    local splitLine = leftPanel:CreateLine()
    splitLine:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    splitLine:SetStartPoint("TOPLEFT", 10, leftY)
    splitLine:SetEndPoint("TOPLEFT", 320, leftY)
    splitLine:SetThickness(1)

    leftY = leftY - 12

    local notifTitle = leftPanel:CreateFontString(nil, "OVERLAY")
    notifTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    notifTitle:SetPoint("TOPLEFT", 14, leftY)
    notifTitle:SetText(BG.STC_g1(L["新进成员自动通知 (进组触发)"]))

    local cbNotifyOnlyLeader = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbNotifyOnlyLeader:SetSize(18, 18)
    cbNotifyOnlyLeader:SetPoint("TOPLEFT", 215, leftY + 1)
    cbNotifyOnlyLeader.text = cbNotifyOnlyLeader:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbNotifyOnlyLeader.text:SetPoint("LEFT", cbNotifyOnlyLeader, "RIGHT", 3, 0)
    cbNotifyOnlyLeader.text:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    cbNotifyOnlyLeader.text:SetText(L["仅团长/助理"])
    cbNotifyOnlyLeader:SetChecked(BiaoGe.RaidTool.notifyOnlyLeader)
    cbNotifyOnlyLeader:SetHitRectInsets(-2, -cbNotifyOnlyLeader.text:GetStringWidth() - 4, -2, -2)
    cbNotifyOnlyLeader:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.notifyOnlyLeader = self:GetChecked()
        BG.PlaySound(1)
    end)
    cbNotifyOnlyLeader:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["仅团长/助理生效"], 1, 1, 1, true)
        GameTooltip:AddLine(L["勾选后，只有当自己是团长或团队助理(A)时，才会自动发送进组密语或团队通知，避免进入他人团队时产生误发。"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    cbNotifyOnlyLeader:SetScript("OnLeave", GameTooltip_Hide)

    leftY = leftY - 20

    -- 统一预设管理弹窗构造器 (支持选取、实时删除)
    local activeManagerModal = nil
    local function OpenPresetManagerModal(titleText, historyKey, targetEditBox, defaultKey)
        if activeManagerModal then activeManagerModal:Hide() end

        local modal = CreateFrame("Frame", "BG_PresetManagerModal", UIParent, "BackdropTemplate")
        modal:SetSize(360, 260)
        modal:SetPoint("CENTER", UIParent, "CENTER", -100, 50)
        modal:SetFrameStrata("FULLSCREEN_DIALOG")
        modal:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        modal:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
        modal:SetBackdropBorderColor(0.3, 0.8, 1, 0.9)
        modal:EnableMouse(true)
        activeManagerModal = modal

        local mTitle = modal:CreateFontString(nil, "OVERLAY")
        mTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        mTitle:SetPoint("TOPLEFT", 14, -12)
        mTitle:SetText(BG.STC_g1(titleText))

        local mCloseBtn = CreateFrame("Button", nil, modal, "UIPanelCloseButton")
        mCloseBtn:SetPoint("TOPRIGHT", -4, -4)
        mCloseBtn:SetScript("OnClick", function() modal:Hide() end)

        local subTip = modal:CreateFontString(nil, "OVERLAY")
        subTip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        subTip:SetPoint("TOPLEFT", 14, -32)
        subTip:SetText(BG.STC_dis(L["点击左侧文字选取应用，点击右侧 [×] 删除预设:"]))

        local scrollParent = CreateFrame("Frame", nil, modal)
        scrollParent:SetSize(330, 180)
        scrollParent:SetPoint("TOPLEFT", 14, -50)

        local rowFrames = {}

        local function RefreshModalList()
            for _, f in ipairs(rowFrames) do f:Hide() end
            wipe(rowFrames)

            local list = BiaoGe.RaidTool[historyKey] or {}
            for i, textItem in ipairs(list) do
                local row = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
                row:SetSize(330, 22)
                row:SetPoint("TOPLEFT", 0, - (i - 1) * 24)
                row:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/Buttons/WHITE8X8",
                    edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 },
                })
                row:SetBackdropColor(0.12, 0.12, 0.12, 0.6)
                row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

                local selectBtn = CreateFrame("Button", nil, row)
                selectBtn:SetSize(295, 22)
                selectBtn:SetPoint("LEFT", 0, 0)
                local txt = selectBtn:CreateFontString(nil, "OVERLAY")
                txt:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                txt:SetPoint("LEFT", 6, 0)
                txt:SetPoint("RIGHT", -5, 0)
                txt:SetJustifyH("LEFT")
                txt:SetWordWrap(false)
                txt:SetText(textItem)

                selectBtn:SetScript("OnEnter", function()
                    row:SetBackdropColor(0.15, 0.3, 0.5, 0.9)
                    txt:SetTextColor(1, 0.82, 0)
                end)
                selectBtn:SetScript("OnLeave", function()
                    row:SetBackdropColor(0.12, 0.12, 0.12, 0.6)
                    txt:SetTextColor(1, 1, 1)
                end)
                selectBtn:SetScript("OnClick", function()
                    targetEditBox:SetText(textItem)
                    BiaoGe.RaidTool[defaultKey] = textItem
                    modal:Hide()
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 团队工具] 已成功选取预设：|r " .. textItem)
                    BG.PlaySound(1)
                end)

                local delBtn = BG.CreateButton(row)
                delBtn:SetSize(26, 18)
                delBtn:SetPoint("RIGHT", -2, 0)
                delBtn:SetText("|cffff4444×|r")
                delBtn:SetScript("OnClick", function()
                    table.remove(BiaoGe.RaidTool[historyKey], i)
                    RefreshModalList()
                    BG.PlaySound(1)
                end)

                tinsert(rowFrames, row)
            end
        end

        RefreshModalList()
        modal:Show()
    end

    -- 1. 自动加队密语
    local cbWhisper = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbWhisper:SetSize(18, 18)
    cbWhisper:SetPoint("TOPLEFT", 14, leftY)
    cbWhisper.text = cbWhisper:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbWhisper.text:SetPoint("LEFT", cbWhisper, "RIGHT", 4, 0)
    cbWhisper.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbWhisper.text:SetText(L["自动密语新进队成员"])
    cbWhisper:SetChecked(BiaoGe.RaidTool.autoWhisperNewMember)
    cbWhisper:SetHitRectInsets(-2, -cbWhisper.text:GetStringWidth() - 4, -2, -2)
    cbWhisper:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.autoWhisperNewMember = self:GetChecked()
        BG.PlaySound(1)
    end)
    cbWhisper:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["自动密语新进队成员"], 1, 1, 1, true)
        GameTooltip:AddLine(L["当有新玩家加入队伍或团队时，自动向其发送设定的密语（支持 {name} 自动替换）。"], 1, 0.82, 0, true)
        if BiaoGe.RaidTool.notifyOnlyLeader then
            GameTooltip:AddLine(L["* 当前已启用[仅限团长/助理]，仅在拥有管理权限时发送。"], 0.3, 1, 0.3, true)
        end
        GameTooltip:Show()
    end)
    cbWhisper:SetScript("OnLeave", GameTooltip_Hide)

    leftY = leftY - 20

    local whisperEditBox = CreateFrame("EditBox", nil, leftPanel, BG.editTemplate)
    whisperEditBox:SetSize(302, 20)
    whisperEditBox:SetPoint("TOPLEFT", 14, leftY)
    whisperEditBox:SetAutoFocus(false)
    whisperEditBox:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    whisperEditBox:SetText(BiaoGe.RaidTool.whisperNewMemberText or "")

    local function SaveWhisperText()
        local text = whisperEditBox:GetText():trim()
        if text ~= "" then
            BiaoGe.RaidTool.whisperNewMemberText = text
        end
    end
    whisperEditBox:SetScript("OnEnterPressed", function(self)
        SaveWhisperText()
        self:ClearFocus()
        BG.PlaySound(1)
    end)
    whisperEditBox:SetScript("OnEditFocusLost", SaveWhisperText)

    leftY = leftY - 24

    local btnSaveWhisper = BG.CreateButton(leftPanel)
    btnSaveWhisper:SetSize(72, 18)
    btnSaveWhisper:SetPoint("TOPLEFT", 14, leftY)
    btnSaveWhisper:SetText(L["存为预设"])
    btnSaveWhisper:SetScript("OnClick", function()
        local text = whisperEditBox:GetText():trim()
        if text ~= "" then
            BiaoGe.RaidTool.whisperNewMemberText = text
            local exists = false
            for _, item in ipairs(BiaoGe.RaidTool.whisperHistory or {}) do
                if item == text then exists = true; break end
            end
            if not exists then
                tinsert(BiaoGe.RaidTool.whisperHistory, 1, text)
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 团队工具] 自动密语已成功保存为预设！|r")
            BG.PlaySound(1)
        end
    end)

    local btnManageWhisper = BG.CreateButton(leftPanel)
    btnManageWhisper:SetSize(85, 18)
    btnManageWhisper:SetPoint("LEFT", btnSaveWhisper, "RIGHT", 6, 0)
    btnManageWhisper:SetText(L["预设管理/选取"])
    btnManageWhisper:SetScript("OnClick", function()
        OpenPresetManagerModal(L["自动密语预设管理与选取"], "whisperHistory", whisperEditBox, "whisperNewMemberText")
    end)

    leftY = leftY - 26

    -- 2. 自动团队/小队发言
    local cbRaidAnn = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbRaidAnn:SetSize(18, 18)
    cbRaidAnn:SetPoint("TOPLEFT", 14, leftY)
    cbRaidAnn.text = cbRaidAnn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbRaidAnn.text:SetPoint("LEFT", cbRaidAnn, "RIGHT", 4, 0)
    cbRaidAnn.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbRaidAnn.text:SetText(L["自动在团队/小队频道发言"])
    cbRaidAnn:SetChecked(BiaoGe.RaidTool.autoRaidAnnounceNew)
    cbRaidAnn:SetHitRectInsets(-2, -cbRaidAnn.text:GetStringWidth() - 4, -2, -2)
    cbRaidAnn:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.autoRaidAnnounceNew = self:GetChecked()
        BG.PlaySound(1)
    end)
    cbRaidAnn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["自动在团队/小队频道发言"], 1, 1, 1, true)
        GameTooltip:AddLine(L["当有新玩家加入队伍或团队时，自动在团队/小队频道发送进组欢迎公告。"], 1, 0.82, 0, true)
        if BiaoGe.RaidTool.notifyOnlyLeader then
            GameTooltip:AddLine(L["* 当前已启用[仅限团长/助理]，仅在拥有管理权限时发送。"], 0.3, 1, 0.3, true)
        end
        GameTooltip:Show()
    end)
    cbRaidAnn:SetScript("OnLeave", GameTooltip_Hide)

    leftY = leftY - 20

    local raidAnnEditBox = CreateFrame("EditBox", nil, leftPanel, BG.editTemplate)
    raidAnnEditBox:SetSize(302, 20)
    raidAnnEditBox:SetPoint("TOPLEFT", 14, leftY)
    raidAnnEditBox:SetAutoFocus(false)
    raidAnnEditBox:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    raidAnnEditBox:SetText(BiaoGe.RaidTool.raidAnnounceText or "")

    local function SaveRaidAnnText()
        local text = raidAnnEditBox:GetText():trim()
        if text ~= "" then
            BiaoGe.RaidTool.raidAnnounceText = text
        end
    end
    raidAnnEditBox:SetScript("OnEnterPressed", function(self)
        SaveRaidAnnText()
        self:ClearFocus()
        BG.PlaySound(1)
    end)
    raidAnnEditBox:SetScript("OnEditFocusLost", SaveRaidAnnText)

    leftY = leftY - 24

    local btnSaveRaidAnn = BG.CreateButton(leftPanel)
    btnSaveRaidAnn:SetSize(72, 18)
    btnSaveRaidAnn:SetPoint("TOPLEFT", 14, leftY)
    btnSaveRaidAnn:SetText(L["存为预设"])
    btnSaveRaidAnn:SetScript("OnClick", function()
        local text = raidAnnEditBox:GetText():trim()
        if text ~= "" then
            BiaoGe.RaidTool.raidAnnounceText = text
            local exists = false
            for _, item in ipairs(BiaoGe.RaidTool.raidAnnounceHistory or {}) do
                if item == text then exists = true; break end
            end
            if not exists then
                tinsert(BiaoGe.RaidTool.raidAnnounceHistory, 1, text)
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 团队工具] 团队发言已成功保存为预设！|r")
            BG.PlaySound(1)
        end
    end)

    local btnManageRaidAnn = BG.CreateButton(leftPanel)
    btnManageRaidAnn:SetSize(85, 18)
    btnManageRaidAnn:SetPoint("LEFT", btnSaveRaidAnn, "RIGHT", 6, 0)
    btnManageRaidAnn:SetText(L["预设管理/选取"])
    btnManageRaidAnn:SetScript("OnClick", function()
        OpenPresetManagerModal(L["团队发言预设管理与选取"], "raidAnnounceHistory", raidAnnEditBox, "raidAnnounceText")
    end)

    leftY = leftY - 22

    -- 3. 聊天框 YY 语音转超链接开关
    local cbYYLink = CreateFrame("CheckButton", nil, leftPanel, "UICheckButtonTemplate")
    cbYYLink:SetSize(18, 18)
    cbYYLink:SetPoint("TOPLEFT", 14, leftY)
    cbYYLink.text = cbYYLink:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbYYLink.text:SetPoint("LEFT", cbYYLink, "RIGHT", 4, 0)
    cbYYLink.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbYYLink.text:SetText(L["聊天框语音/YY号转超链接 (点击秒复制)"])
    cbYYLink:SetChecked(BiaoGe.RaidTool.enableYYLink)
    cbYYLink:SetHitRectInsets(-2, -cbYYLink.text:GetStringWidth() - 4, -2, -2)
    cbYYLink:SetScript("OnClick", function(self)
        BiaoGe.RaidTool.enableYYLink = self:GetChecked()
        BG.PlaySound(1)
    end)

    leftY = leftY - 18

    local varTip = leftPanel:CreateFontString(nil, "OVERLAY")
    varTip:SetFont(BIAOGE_TEXT_FONT, 10, "OUTLINE")
    varTip:SetPoint("TOPLEFT", 14, leftY)
    varTip:SetText(BG.STC_dis(L["* 支持 {name} 自动替换姓名 | 点击YY超链接直接全选复制"]))

    ----------------------------------------------------------------------------
    -- 右侧：阵容助手 (Raid Groups Optimizer) - 宽度 620, 高度 450
    ----------------------------------------------------------------------------
    local rightPanel = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    rightPanel:SetSize(620, 450)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    rightPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    rightPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY")
    rightTitle:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    rightTitle:SetPoint("TOPLEFT", 16, -14)
    rightTitle:SetText(BG.STC_g1(L["团队阵容管理"]))

    local topTip = rightPanel:CreateFontString(nil, "OVERLAY")
    topTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    topTip:SetPoint("LEFT", rightTitle, "RIGHT", 14, 0)
    topTip:SetText(BG.STC_dis(L["(支持拖拽队员调换队伍，成员变动实时自动同步)"]))

    -- 顶部按钮
    local btnSyncRoster = BG.CreateButton(rightPanel)
    btnSyncRoster:SetSize(100, 24)
    btnSyncRoster:SetPoint("TOPLEFT", 16, -38)
    btnSyncRoster:SetText(L["同步当前团队"])

    local btnSaveProfile = BG.CreateButton(rightPanel)
    btnSaveProfile:SetSize(100, 24)
    btnSaveProfile:SetPoint("LEFT", btnSyncRoster, "RIGHT", 8, 0)
    btnSaveProfile:SetText(L["保存为预设"])

    local btnApplyRoster = BG.CreateButton(rightPanel)
    btnApplyRoster:SetSize(100, 24)
    btnApplyRoster:SetPoint("LEFT", btnSaveProfile, "RIGHT", 8, 0)
    btnApplyRoster:SetText(BG.STC_g1(L["应用此阵容"]))

    -- 8 个小队网格 (单格 140x120)
    local slotButtons = {}
    local currentRosterList = {}
    local currentRosterClasses = {}

    local gridY = -70
    local groupWidth = 142
    local groupHeight = 120

    local function UpdateSlotVisual(slotIndex)
        local btn = slotButtons[slotIndex]
        if not btn then return end
        local name = currentRosterList[slotIndex]
        if name and name ~= "" then
            btn.text:SetText(name)
            local class = currentRosterClasses[slotIndex]
            if not class and UnitName(name) then
                class = select(2, UnitClass(name))
            end
            local r, g, b = 1, 1, 1
            if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
                r = RAID_CLASS_COLORS[class].r
                g = RAID_CLASS_COLORS[class].g
                b = RAID_CLASS_COLORS[class].b
            elseif UnitName(name) then
                r, g, b = GetClassRGB(name)
            end
            btn.text:SetTextColor(r, g, b)
            btn:SetBackdropColor(r * 0.25, g * 0.25, b * 0.25, 0.85)
            btn:SetBackdropBorderColor(r * 0.75, g * 0.75, b * 0.75, 0.9)
        else
            btn.text:SetText(BG.STC_dis(format(L["空位 %d"], ((slotIndex - 1) % MEMBERS_PER_GROUP) + 1)))
            btn:SetBackdropColor(0.08, 0.08, 0.08, 0.4)
            btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        end
    end

    local groupFrames = {}

    local function UpdateGroupBoxesVisibility()
        local isRaid = IsInRaid and IsInRaid()
        local hasOtherGroupMembers = false
        for i = MEMBERS_PER_GROUP + 1, MAX_RAID_MEMBERS do
            if currentRosterList[i] and currentRosterList[i] ~= "" then
                hasOtherGroupMembers = true
                break
            end
        end

        for grp = 1, NUM_GROUPS do
            local gBox = groupFrames[grp]
            if gBox then
                if isRaid or hasOtherGroupMembers or grp == 1 then
                    gBox:SetAlpha(1.0)
                else
                    gBox:SetAlpha(0.28)
                end
            end
        end
    end

    local function SwapSlotValues(idx1, idx2)
        if not idx1 or not idx2 or idx1 == idx2 then return end

        if not (IsInRaid and IsInRaid()) and (idx1 > MEMBERS_PER_GROUP or idx2 > MEMBERS_PER_GROUP) then
            if C_PartyInfo and C_PartyInfo.ConvertToRaid then
                C_PartyInfo.ConvertToRaid()
            elseif ConvertToRaid then
                ConvertToRaid()
            end
            RaidTool.Log("检测到跨队调整，已自动将小队转换为团队！")
        end

        local val1 = currentRosterList[idx1]
        local val2 = currentRosterList[idx2]
        local cls1 = currentRosterClasses[idx1]
        local cls2 = currentRosterClasses[idx2]
        currentRosterList[idx1] = val2
        currentRosterList[idx2] = val1
        currentRosterClasses[idx1] = cls2
        currentRosterClasses[idx2] = cls1
        UpdateSlotVisual(idx1)
        UpdateSlotVisual(idx2)
        UpdateGroupBoxesVisibility()
        BG.PlaySound(1)
    end

    for grp = 1, NUM_GROUPS do
        local col = (grp - 1) % 4
        local row = math.floor((grp - 1) / 4)
        local gX = 16 + col * (groupWidth + 8)
        local gY = gridY - row * (groupHeight + 8)

        local gBox = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
        gBox:SetSize(groupWidth, groupHeight)
        gBox:SetPoint("TOPLEFT", gX, gY)
        gBox:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        gBox:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
        gBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
        groupFrames[grp] = gBox

        local gTitle = gBox:CreateFontString(nil, "OVERLAY")
        gTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        gTitle:SetPoint("TOPLEFT", 6, -3)
        gTitle:SetText(BG.STC_y1(format(L["第 %d 小队"], grp)))

        for pos = 1, MEMBERS_PER_GROUP do
            local idx = (grp - 1) * MEMBERS_PER_GROUP + pos
            local slotBtn = CreateFrame("Button", nil, gBox, "BackdropTemplate")
            slotBtn:SetSize(groupWidth - 10, 19)
            slotBtn:SetPoint("TOPLEFT", 5, -17 - (pos - 1) * 20)
            slotBtn:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            slotBtn.index = idx

            slotBtn.text = slotBtn:CreateFontString(nil, "OVERLAY")
            slotBtn.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            slotBtn.text:SetPoint("LEFT", 6, 0)
            slotBtn.text:SetWordWrap(false)

            slotBtn:RegisterForDrag("LeftButton")
            slotBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            slotBtn:SetScript("OnDragStart", function(self)
                local name = currentRosterList[self.index]
                if name and name ~= "" then
                    dragSourceIndex = self.index
                    dragCursor.text:SetText(name)
                    dragCursor:Show()
                    dragCursor:SetPoint("CENTER", GetCursorPosition())
                    dragCursor:SetScript("OnUpdate", function(f)
                        local cx, cy = GetCursorPosition()
                        local scale = UIParent:GetEffectiveScale()
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
                    end)
                end
            end)

            slotBtn:SetScript("OnDragStop", function(self)
                if dragSourceIndex then
                    dragCursor:Hide()
                    dragCursor:SetScript("OnUpdate", nil)

                    local targetSlotIdx = nil
                    for sIdx, otherBtn in pairs(slotButtons) do
                        if otherBtn:IsMouseOver() then
                            targetSlotIdx = sIdx
                            break
                        end
                    end

                    if targetSlotIdx and targetSlotIdx ~= dragSourceIndex then
                        SwapSlotValues(dragSourceIndex, targetSlotIdx)
                    end
                    dragSourceIndex = nil
                end
            end)

            slotBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    currentRosterList[self.index] = nil
                    UpdateSlotVisual(self.index)
                    BG.PlaySound(1)
                end
            end)

            slotBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.8, 0, 1)
            end)
            slotBtn:SetScript("OnLeave", function(self)
                UpdateSlotVisual(self.index)
            end)

            slotButtons[idx] = slotBtn
            UpdateSlotVisual(idx)
        end
    end

    -- 全自适应同步当前团队/小队
    function RaidTool.SyncCurrentRaidRoster(isManual)
        local memberCount = GetRosterMemberCount()
        if memberCount == 0 then
            wipe(currentRosterList)
            wipe(currentRosterClasses)
            local pName = UnitName("player")
            if pName then
                currentRosterList[1] = CleanPlayerName(pName)
                currentRosterClasses[1] = select(2, UnitClass("player"))
            end
            for i = 1, 40 do
                UpdateSlotVisual(i)
            end
            UpdateGroupBoxesVisibility()
            if isManual then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[BGLite 团队工具] 你当前不在任何队伍或团队中！|r")
            end
            return
        end

        wipe(currentRosterList)
        wipe(currentRosterClasses)
        local groupCounts = {}
        for i = 1, NUM_GROUPS do groupCounts[i] = 0 end

        local loadedCount = 0

        local isRaidMode = false
        if IsInRaid and IsInRaid() then
            isRaidMode = true
        elseif GetRaidRosterInfo and GetRaidRosterInfo(1) then
            isRaidMode = true
        elseif memberCount > 5 then
            isRaidMode = true
        end

        if isRaidMode then
            for i = 1, memberCount do
                local name, rank, subgroup, level, className, classFileName = GetRaidRosterInfo(i)
                name = name or UnitName("raid" .. i)
                if name and name ~= "" then
                    subgroup = (subgroup and subgroup >= 1 and subgroup <= NUM_GROUPS) and subgroup or 1
                    groupCounts[subgroup] = groupCounts[subgroup] + 1
                    local pos = groupCounts[subgroup]
                    if pos <= MEMBERS_PER_GROUP then
                        local slotIdx = (subgroup - 1) * MEMBERS_PER_GROUP + pos
                        local shortName = CleanPlayerName(name)
                        currentRosterList[slotIdx] = shortName
                        currentRosterClasses[slotIdx] = classFileName or (select(2, UnitClass("raid" .. i))) or (select(2, UnitClass(name)))
                        loadedCount = loadedCount + 1
                    end
                end
            end
        else
            local pName = UnitName("player")
            if pName then
                currentRosterList[1] = CleanPlayerName(pName)
                currentRosterClasses[1] = select(2, UnitClass("player"))
                loadedCount = 1
            end
            for i = 1, 4 do
                local partName = UnitName("party" .. i)
                if partName then
                    currentRosterList[1 + i] = CleanPlayerName(partName)
                    currentRosterClasses[1 + i] = select(2, UnitClass("party" .. i)) or select(2, UnitClass(partName))
                    loadedCount = loadedCount + 1
                end
            end
        end

        for i = 1, 40 do
            UpdateSlotVisual(i)
        end
        UpdateGroupBoxesVisibility()

        if isManual then
            RaidTool.Log(format("已成功同步当前阵容（共 %d 名成员）！", loadedCount))
            BG.PlaySound(1)
        end
    end

    btnSyncRoster:SetScript("OnClick", function()
        if BiaoGe.RaidGroups then
            BiaoGe.RaidGroups.selectedProfile = nil
        end
        if RefreshProfileTabs then
            RefreshProfileTabs()
        end
        RaidTool.SyncCurrentRaidRoster(true)
    end)

    -- 预设管理面板 (宽度 590, 高度 110，专注平铺展示方块 Tab)
    local profilePanel = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    profilePanel:SetSize(590, 110)
    profilePanel:SetPoint("TOPLEFT", 16, gridY - 2 * (groupHeight + 8) - 4)
    profilePanel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    profilePanel:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    profilePanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local pTitle = profilePanel:CreateFontString(nil, "OVERLAY")
    pTitle:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    pTitle:SetPoint("TOPLEFT", 14, -8)
    pTitle:SetText(BG.STC_g1(L["预设阵容快捷标签"]))

    local pSubTip = profilePanel:CreateFontString(nil, "OVERLAY")
    pSubTip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    pSubTip:SetPoint("LEFT", pTitle, "RIGHT", 12, 0)
    pSubTip:SetText(BG.STC_dis(L["(点击载入预设 | Alt+点击覆盖保存 | 右键删除)"]))

    -- Tab 按钮平铺容器
    local tabContainer = CreateFrame("Frame", nil, profilePanel)
    tabContainer:SetPoint("TOPLEFT", 14, -28)
    tabContainer:SetPoint("BOTTOMRIGHT", -14, 10)

    local tabButtons = {}
    local RefreshProfileTabs = nil

    local function LoadProfile(pName)
        if not pName then return end
        local pData = BiaoGe.RaidGroups and BiaoGe.RaidGroups.profiles and BiaoGe.RaidGroups.profiles[pName]
        if not pData or type(pData) ~= "table" then return end
        BiaoGe.RaidGroups.selectedProfile = pName
        wipe(currentRosterList)
        wipe(currentRosterClasses)
        for i = 1, 40 do
            local slotData = pData[i]
            if type(slotData) == "table" then
                currentRosterList[i] = slotData.name
                currentRosterClasses[i] = slotData.class
            elseif type(slotData) == "string" and slotData ~= "" then
                currentRosterList[i] = slotData
                if UnitName(slotData) then
                    currentRosterClasses[i] = select(2, UnitClass(slotData))
                end
            end
            UpdateSlotVisual(i)
        end
        UpdateGroupBoxesVisibility()
        if RefreshProfileTabs then RefreshProfileTabs() end
    end

    local function SaveProfile(name)
        if not name or name == "" then return end
        BiaoGe.RaidGroups = BiaoGe.RaidGroups or {}
        BiaoGe.RaidGroups.profiles = BiaoGe.RaidGroups.profiles or {}
        BiaoGe.RaidGroups.profiles[name] = {}
        for i = 1, 40 do
            if currentRosterList[i] and currentRosterList[i] ~= "" then
                BiaoGe.RaidGroups.profiles[name][i] = {
                    name = currentRosterList[i],
                    class = currentRosterClasses[i],
                }
            end
        end
        BiaoGe.RaidGroups.selectedProfile = name
        if RefreshProfileTabs then RefreshProfileTabs() end
        RaidTool.Log(format("已成功保存预设方案 [%s]！", name))
        BG.PlaySound(1)
    end

    local function HandleTabClick(self, button)
        if button == "RightButton" then
            -- 删除预设
            BiaoGe.RaidGroups.profiles[self.profileName] = nil
            if BiaoGe.RaidGroups.selectedProfile == self.profileName then
                BiaoGe.RaidGroups.selectedProfile = nil
            end
            RaidTool.Log(format("已删除预设方案 [%s]。", self.profileName))
            if RefreshProfileTabs then RefreshProfileTabs() end
            BG.PlaySound(1)
        elseif IsAltKeyDown() then
            -- 覆盖保存
            SaveProfile(self.profileName)
        else
            -- 加载预设
            LoadProfile(self.profileName)
            RaidTool.Log(format("已载入预设方案 [%s]。", self.profileName))
            BG.PlaySound(1)
        end
    end

    RefreshProfileTabs = function()
        for _, btn in ipairs(tabButtons) do
            btn:Hide()
        end

        local profiles = BiaoGe.RaidGroups and BiaoGe.RaidGroups.profiles or {}
        local names = {}
        for pName, pData in pairs(profiles) do
            if type(pName) == "string" and pName ~= "" and type(pData) == "table" then
                tinsert(names, pName)
            end
        end
        table.sort(names)

        if #names == 0 then
            if not profilePanel.emptyTip then
                local tip = profilePanel:CreateFontString(nil, "OVERLAY")
                tip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                tip:SetPoint("LEFT", tabContainer, "LEFT", 2, 0)
                tip:SetText(BG.STC_dis(L["暂无保存的预设，点击上方【保存为预设】可将当前团队阵容保存为快捷Tab。"]))
                profilePanel.emptyTip = tip
            end
            profilePanel.emptyTip:Show()
        else
            if profilePanel.emptyTip then
                profilePanel.emptyTip:Hide()
            end

            local xOffset = 0
            local yOffset = 0
            local maxRowWidth = 560

            for idx, pName in ipairs(names) do
                local btn = tabButtons[idx]
                if not btn then
                    btn = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
                    btn:SetHeight(24)
                    btn:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/Buttons/WHITE8X8",
                        edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    btn.text = btn:CreateFontString(nil, "OVERLAY")
                    btn.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                    btn.text:SetPoint("CENTER", 0, 0)

                    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    btn:SetScript("OnClick", HandleTabClick)

                    tabButtons[idx] = btn
                end

                btn.profileName = pName
                btn.text:SetText(pName)
                local textWidth = btn.text:GetStringWidth() + 18
                local btnWidth = math.max(68, textWidth)
                btn:SetWidth(btnWidth)

                if xOffset + btnWidth > maxRowWidth and xOffset > 0 then
                    xOffset = 0
                    yOffset = yOffset - 28
                end

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", xOffset, yOffset)
                xOffset = xOffset + btnWidth + 6

                local isSelected = (BiaoGe.RaidGroups.selectedProfile == pName)
                if isSelected then
                    btn:SetBackdropColor(0.12, 0.42, 0.72, 0.95)
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                    btn.text:SetTextColor(1, 0.95, 0.3)
                else
                    btn:SetBackdropColor(0.14, 0.14, 0.14, 0.85)
                    btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
                    btn.text:SetTextColor(0.9, 0.9, 0.9)
                end

                btn:SetScript("OnEnter", function(self)
                    if BiaoGe.RaidGroups.selectedProfile ~= self.profileName then
                        self:SetBackdropColor(0.22, 0.22, 0.22, 0.95)
                        self:SetBackdropBorderColor(0.2, 0.8, 1, 1)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(BG.STC_g1("预设阵容: ") .. self.profileName)
                    GameTooltip:AddLine(BG.STC_w1("• 左键点击：") .. "载入该阵容到网格", 0.9, 0.9, 0.9)
                    GameTooltip:AddLine(BG.STC_w1("• Alt+左键：") .. "覆盖保存当前网格到该预设", 0.9, 0.9, 0.9)
                    GameTooltip:AddLine(BG.STC_r1("• 右键点击：") .. "删除该预设方案", 0.9, 0.9, 0.9)
                    GameTooltip:Show()
                end)

                btn:SetScript("OnLeave", function(self)
                    local sel = (BiaoGe.RaidGroups.selectedProfile == self.profileName)
                    if sel then
                        self:SetBackdropColor(0.12, 0.42, 0.72, 0.95)
                        self:SetBackdropBorderColor(1, 0.82, 0, 1)
                    else
                        self:SetBackdropColor(0.14, 0.14, 0.14, 0.85)
                        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
                    end
                    GameTooltip:Hide()
                end)

                btn:Show()
            end
        end
    end

    -- 注册原生弹窗：输入方案名称保存预设
    StaticPopupDialogs["BG_SAVE_ROSTER_PROFILE"] = {
        text = L["请输入团队阵容预设方案名称："],
        button1 = L["保存"],
        button2 = L["取消"],
        hasEditBox = true,
        maxLetters = 30,
        OnShow = function(self)
            local editBox = _G[self:GetName() .. "EditBox"]
            if editBox then
                local defName = BiaoGe.RaidGroups and BiaoGe.RaidGroups.selectedProfile or ""
                editBox:SetText(defName)
                editBox:HighlightText()
                editBox:SetFocus()
            end
        end,
        OnAccept = function(self)
            local editBox = _G[self:GetName() .. "EditBox"]
            local name = editBox and editBox:GetText():trim()
            if name and name ~= "" then
                SaveProfile(name)
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            StaticPopup_OnClick(parent, 1)
        end,
        EditBoxOnEscapePressed = function(self)
            local parent = self:GetParent()
            StaticPopup_OnClick(parent, 2)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- 顶部按钮事件绑定
    btnSaveProfile:SetScript("OnClick", function()
        StaticPopup_Show("BG_SAVE_ROSTER_PROFILE")
    end)

    btnApplyRoster:SetScript("OnClick", function()
        RaidTool.ApplyRosterProfile(currentRosterList)
        BG.PlaySound(1)
    end)

    -- 底部待开发提示文本
    local footerTip = mainFrame:CreateFontString(nil, "OVERLAY")
    footerTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    footerTip:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 18)
    footerTip:SetText(BG.STC_dis(L["空白位置待开发中；有需求欢迎dd留言。"]))

    -- 全自动监听团队/小队变动（来人、退人、换队实时自动同步）
    local rosterAutoUpdateFrame = CreateFrame("Frame", nil, mainFrame)
    rosterAutoUpdateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    pcall(function() rosterAutoUpdateFrame:RegisterEvent("RAID_ROSTER_UPDATE") end)
    rosterAutoUpdateFrame:SetScript("OnEvent", function(self, event)
        if mainFrame:IsShown() and not RosterState.isProcessing then
            RaidTool.SyncCurrentRaidRoster(false)
            if BiaoGe.RaidGroups then
                BiaoGe.RaidGroups.selectedProfile = nil
            end
            if RefreshProfileTabs then
                RefreshProfileTabs()
            end
        end
    end)

    mainFrame:HookScript("OnShow", function()
        RefreshProfileTabs()
        if (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0) then
            -- 组队/团队状态下，打开面板自动同步当前真实阵容
            RaidTool.SyncCurrentRaidRoster(false)
            if BiaoGe.RaidGroups then
                BiaoGe.RaidGroups.selectedProfile = nil
            end
            if RefreshProfileTabs then
                RefreshProfileTabs()
            end
        else
            -- 单人未组队状态下，如果有保存的预设方案，优先读出预设展示
            local profiles = BiaoGe.RaidGroups and BiaoGe.RaidGroups.profiles or {}
            local sel = BiaoGe.RaidGroups and BiaoGe.RaidGroups.selectedProfile
            if sel and profiles[sel] then
                LoadProfile(sel)
            else
                local firstProfile = next(profiles)
                if firstProfile then
                    LoadProfile(firstProfile)
                else
                    RaidTool.SyncCurrentRaidRoster(false)
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- 5. 语音/YY号全频道自动识别与超链接生成 (YY Copy Link Engine)
--------------------------------------------------------------------------------
local function CleanYYNumber(raw)
    if not raw then return nil end
    local num = raw:match("(%d%d%d%d+)")
    if num and #num >= 4 and #num <= 10 then
        return num
    end
    return nil
end

local function FormatYYHyperlink(yyNum, tag)
    tag = (tag and tag ~= "") and tag or "YY"
    -- 核心防破坏屏障：在 tag 与数字之间插入 |r|cff00BFFF 管道颜色切换符
    -- 视觉上完全连贯无缝显示为 [DD 123456]，但可物理阻断任何第三方插件基于关键字+空格+数字的粗暴正则识别
    return "|cff00BFFF|Hgarrmission:BGVoice_" .. tag .. "_" .. yyNum .. "|h[" .. tag .. "|r|cff00BFFF " .. yyNum .. "]|h|r"
end

local function YYMessageFilter(self, event, msg, sender, ...)
    local db = BiaoGe and BiaoGe.RaidTool
    if not db or db.enableYYLink == false then
        return false, msg, sender, ...
    end
    if not msg or type(msg) ~= "string" then
        return false, msg, sender, ...
    end

    -- 如果消息中已经包含我们的语音链接或者已经带有超链接，避免重复或二次破坏
    if msg:find("garrmission:BGVoice_") or msg:find("garrmission:BGLite") or msg:find("garrmission:BiaoGeYY:") then
        return false, msg, sender, ...
    end

    local modified = false

    local patternConfigs = {
        { pat = "[yY][yY]%s*[:：=＝%-%s]*([0-9]+)", tag = "YY" },
        { pat = "歪歪%s*[:：=＝%-%s]*([0-9]+)", tag = "YY" },
        { pat = "[dD][dD]%s*[:：=＝%-%s]*([0-9]+)", tag = "DD" },
        { pat = "[kK][oO][oO][kK]%s*[:：=＝%-%s]*([0-9]+)", tag = "KOOK" },
        { pat = "[vV][xX]%s*[:：=＝%-%s]*([0-9]+)", tag = "VX" },
        { pat = "频道%s*[:：=＝%-%s]*([0-9]+)", tag = "频道" },
        { pat = "语音%s*[:：=＝%-%s]*([0-9]+)", tag = "语音" },
    }

    for _, cfg in ipairs(patternConfigs) do
        local startIdx = 1
        while true do
            local s, e, cap = msg:find(cfg.pat, startIdx)
            if not s then break end
            local cleanNum = CleanYYNumber(cap)
            if cleanNum then
                -- 检查并吸收外部可能自带的中括号或中文括号，避免出现 [[DD ...]] 嵌套
                if s > 1 and msg:sub(s - 1, s - 1) == "[" and msg:sub(e + 1, e + 1) == "]" then
                    s = s - 1
                    e = e + 1
                elseif s >= 4 and msg:sub(s - 3, s - 1) == "【" and msg:sub(e + 1, e + 3) == "】" then
                    s = s - 3
                    e = e + 3
                elseif s > 1 and msg:sub(s - 1, s - 1) == "(" and msg:sub(e + 1, e + 1) == ")" then
                    s = s - 1
                    e = e + 1
                elseif s >= 4 and msg:sub(s - 3, s - 1) == "（" and msg:sub(e + 1, e + 3) == "）" then
                    s = s - 3
                    e = e + 3
                end

                local link = FormatYYHyperlink(cleanNum, cfg.tag)
                msg = msg:sub(1, s - 1) .. link .. msg:sub(e + 1)
                startIdx = s + #link
                modified = true
            else
                startIdx = e + 1
            end
        end
    end

    if modified then
        return false, msg, sender, ...
    end
    return false, msg, sender, ...
end

local yyChatEvents = {
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_YELL",
    "CHAT_MSG_SAY",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

for _, evt in ipairs(yyChatEvents) do
    ChatFrame_AddMessageEventFilter(evt, YYMessageFilter)
end

-- 全局一键复制弹窗 (YY / DD / Voice Copy Modal)
local copyModal = nil
local function ShowYYCopyModal(yyNumber, tag)
    tag = (tag and tag ~= "") and tag or "YY"
    if not copyModal then
        copyModal = CreateFrame("Frame", "BG_YYCopyModalFrame", UIParent, "BackdropTemplate")
        copyModal:SetSize(280, 100)
        copyModal:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        copyModal:SetFrameStrata("FULLSCREEN_DIALOG")
        copyModal:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        copyModal:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
        copyModal:SetBackdropBorderColor(0.2, 0.7, 1, 1)
        copyModal:EnableMouse(true)

        local title = copyModal:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        title:SetPoint("TOP", 0, -12)
        title:SetText(BG.STC_g1(tag .. " / 语音频道号 (已全选)"))
        copyModal.title = title

        local tip = copyModal:CreateFontString(nil, "OVERLAY")
        tip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        tip:SetPoint("TOP", 0, -32)
        tip:SetText(BG.STC_y1(L["请直接按 Ctrl+C 复制到剪贴板"]))

        local eb = CreateFrame("EditBox", nil, copyModal, BG.editTemplate)
        eb:SetSize(220, 24)
        eb:SetPoint("TOP", 0, -52)
        eb:SetAutoFocus(true)
        eb:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
        eb:SetJustifyH("CENTER")
        copyModal.editBox = eb

        eb:SetScript("OnEscapePressed", function()
            copyModal:Hide()
        end)
        eb:SetScript("OnEnterPressed", function()
            copyModal:Hide()
            BG.PlaySound(1)
        end)
        eb:SetScript("OnKeyUp", function(self, key)
            if IsControlKeyDown() and key == "C" then
                RaidTool.Log("频道号 [" .. self:GetText() .. "] 已复制！")
                BG.PlaySound(1)
                C_Timer.After(0.25, function() copyModal:Hide() end)
            end
        end)

        local closeBtn = CreateFrame("Button", nil, copyModal, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() copyModal:Hide() end)
    end

    if copyModal.title then
        copyModal.title:SetText(BG.STC_g1(tag .. " / 语音频道号 (已全选)"))
    end
    copyModal.editBox:SetText(yyNumber)
    copyModal:Show()
    copyModal.editBox:SetFocus()
    copyModal.editBox:HighlightText()
    BG.PlaySound(1)
end

-- Hook SetItemRef 处理超链接点击
hooksecurefunc("SetItemRef", function(link, text, button)
    if not link then return end
    local channelTag, yyNum = link:match("^garrmission:BGVoice_(%a+)_(%d+)")
    if not yyNum then
        yyNum, channelTag = link:match("^garrmission:BGLiteChannelLink:(%d+):?(.*)")
    end
    if not yyNum then
        yyNum = link:match("^garrmission:BGLiteCopyYY:(%d+)") or link:match("^BGLiteCopyYY:(%d+)")
    end
    if yyNum then
        local tag = (channelTag and channelTag ~= "") and channelTag or "YY"
        if IsShiftKeyDown() then
            -- SHIFT 点击：填入聊天输入框
            if ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(yyNum)
            else
                local eb = ChatFrame1EditBox
                if eb then
                    ChatFrame_OpenChat(yyNum)
                end
            end
        elseif IsAltKeyDown() then
            -- ALT 点击：在团队/小队广播
            local channel = (IsInRaid and IsInRaid()) and "RAID" or (IsInGroup and IsInGroup() and "PARTY" or "SAY")
            SendChatMessage(format("请进%s语音频道：%s", tag, yyNum), channel)
            RaidTool.Log(format("已在频道广播 %s: %s", tag, yyNum))
        else
            -- 普通左键点击：呼出全选复制浮窗
            ShowYYCopyModal(yyNum, tag)
        end
    end
end)

--------------------------------------------------------------------------------
-- 5. 在插件设置【其他功能】页面注入调试日志复选框
--------------------------------------------------------------------------------
function ns.InitRaidToolOthersOptions()
    if not (BG and BG.FrameOptions_others) then return end
    if BG.FrameOptions_others.hasInitedRaidToolDebug then return end
    BG.FrameOptions_others.hasInitedRaidToolDebug = true

    local parentFrame = BG.FrameOptions_others
    local content = nil
    for _, child in ipairs({ parentFrame:GetChildren() }) do
        if child.scroll and child.scroll.GetScrollChild then
            content = child.scroll:GetScrollChild()
            break
        end
    end
    content = content or parentFrame

    -- 计算已存在控件的最底部 Y 坐标，确保紧凑自然追加在末尾
    local minY = -350
    for _, child in ipairs({ content:GetChildren() }) do
        local p, rel, relP, x, y = child:GetPoint()
        if y and type(y) == "number" and y < minY then
            minY = y
        end
    end

    local startY = minY - 45

    -- 团队与组队工具分区标题
    local sectionTitle = content:CreateFontString(nil, "OVERLAY")
    sectionTitle:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    sectionTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 15, startY)
    sectionTitle:SetText(BG.STC_g1(L["团队与组队工具"]))

    local splitLine = content:CreateLine()
    splitLine:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    splitLine:SetStartPoint("TOPLEFT", 5, startY - 20)
    splitLine:SetEndPoint("TOPLEFT", 480, startY - 20)
    splitLine:SetThickness(1.5)

    -- 调试日志复选框
    local cbDebug = CreateFrame("CheckButton", "BG_Button_RaidToolDebugLog", content, "ChatConfigCheckButtonTemplate")
    cbDebug:SetSize(30, 30)
    cbDebug:SetPoint("TOPLEFT", content, "TOPLEFT", 15, startY - 28)
    cbDebug.Text:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    cbDebug.Text:SetText(L["开启团队工具调试日志"])
    cbDebug.Text:SetWordWrap(false)
    cbDebug.Text:SetWidth(cbDebug.Text:GetStringWidth() + 20)
    cbDebug:SetHitRectInsets(0, -cbDebug.Text:GetWidth(), 0, 0)

    cbDebug:SetChecked(RaidTool.IsDebugEnabled())

    cbDebug:SetScript("OnClick", function(self)
        RaidTool.SetDebugEnabled(self:GetChecked())
        BG.PlaySound(1)
    end)
    cbDebug:SetScript("OnShow", function(self)
        self:SetChecked(RaidTool.IsDebugEnabled())
    end)

    cbDebug:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(BG.STC_g1(L["开启团队工具调试日志"]))
        GameTooltip:AddLine(L["开启后，在聊天框打印新成员进组密语发送、进组欢迎广播、自动邀请响应及调队状态等绿色提示信息；关闭后静默执行，不打扰聊天框。"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cbDebug:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
