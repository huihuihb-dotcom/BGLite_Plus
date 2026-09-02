local AddonName, ns = ...
local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF

local TeamInfo = {}
ns.TeamInfo = TeamInfo

-- 1. 时光服特征关键字库
local TITAN_KEYWORDS = {
    -- 橙武/极品/包团
    "风剑", "橙锤", "橙弓", "橙匕", "片", "碎片", "裁决", "匕首", "包", "可包", "全拍不包", "不包",
    -- 模式/计费
    "百元", "百元团", "百元全通", "均分", "均分团", "全拍均分", "摸奖", "全拍", "单本", "速推", "全通",
    "无双", "无双无R", "起拍", "升级", "k起", "K起", "w起", "W起", "2w", "2W", "1w", "1W",
    -- 补助/奖励/考核
    "补", "硬补", "T硬补", "补贴", "TN", "TN1", "RTN1", "过2R", "过万R", "过2W", "DD321", "432",
    "工具", "恶鱼", "恶鱼工具", "统计", "考核", "锅", "DPS", "考核DPS", "听指挥",
    -- 团本简称
    "TOC", "toc", "NAXX", "naxx", "SW", "sw", "ZAM", "zam", "ZG", "zg", "SSC", "ssc", "TK", "tk",
    "宝库", "土王", "双龙", "黑曜石", "奥杜尔", "ULD", "uld",
    -- 职业
    "FQ", "NQ", "CJQ", "BDK", "KBZ", "WQZ", "AM", "JLM", "SS", "DZ", "LR", "SM", "猫德", "鸟德", "奶德",
    -- 语音/YY
    "YY", "yy", "歪歪", "语音", "上YY", "挂YY",
}

-- 2. YY 正则匹配模式
local YY_PATTERNS = {
    "[yY]*[yY][：:_/%-%s]*([%d%s][%d%s][%d%s][%d%s]*%d+)",
    "(%d+[%d%s][%d%s][%d%s][%d%s]*)[：:_/%-%s]*[yY][yY]*",
    "[歪]*歪[：:_/%-%s]*([%d%s][%d%s][%d%s][%d%s]*%d+)",
}

-- 名字标准化（同时支持带服名与纯名字比对）
local function CleanName(name)
    if not name or type(name) ~= "string" then return "" end
    name = Ambiguate(name, "none")
    return (strsplit("-", name))
end

local function IsSamePlayer(name1, name2)
    if not name1 or not name2 then return false end
    if name1 == name2 then return true end
    local c1 = CleanName(name1)
    local c2 = CleanName(name2)
    return (c1 ~= "" and c1 == c2)
end

-- 提取纯数字 YY 号
local function ExtractYYFromText(text)
    if not text or type(text) ~= "string" then return nil end
    for _, pattern in ipairs(YY_PATTERNS) do
        local yy = text:match(pattern)
        if yy then
            yy = yy:gsub("%s", "")
            if #yy >= 4 and #yy <= 12 and tonumber(yy) then
                return yy
            end
        end
    end
    return nil
end

local function ContainsTitanKeyword(text)
    if not text or type(text) ~= "string" then return false end
    for _, kw in ipairs(TITAN_KEYWORDS) do
        if text:find(kw, 1, true) then
            return true
        end
    end
    return false
end

-- 3. 插件自动欢迎/通知黑名单 (杜绝网易有爱、大脚等入队代发干扰)
local NOISE_KEYWORDS = {
    "有爱提示", "大脚提示", "大脚团队", "爱不易", "网易有爱",
    "欢迎新队友", "欢迎加入", "愿我们同心协力", "拥有一次完美的旅程",
    "祝大家游戏愉快", "开始通报", "准备确认", "插件提示",
}

local function IsAddonNoise(text)
    if not text or type(text) ~= "string" then return false end
    for _, kw in ipairs(NOISE_KEYWORDS) do
        if text:find(kw, 1, true) then
            return true
        end
    end
    return false
end

-- 解析集结号原生 MHH 广播数据包 (如: MHH@波比兔.百元均分团。测试信息 不开； 无)
local function ParseMHHMessage(msg, sender)
    if not msg or not msg:find("^MHH") then return nil end
    local leader, rest = msg:match("^MHH%d?@([^%.]+)%.(.*)")
    if leader and rest then
        local title, comment
        if rest:find("。") then
            title, comment = rest:match("^([^。]+)。(.*)")
        elseif rest:find("%.") then
            title, comment = rest:match("^([^%.]+)%.(.*)")
        else
            title = rest
            comment = ""
        end
        local formatted = ""
        if title and title ~= "" then
            formatted = "《" .. title .. "》 "
        end
        if comment and comment ~= "" then
            formatted = formatted .. comment
        end
        return CleanName(leader), formatted, leader
    end
    return nil
end

-- 4. 公共频道招募缓存池
local WorldRecruitCache = {}
local CACHE_EXPIRATION = 15 * 60 -- 15 分钟

local function AddToWorldCache(sender, msg)
    if not sender or not msg or #msg < 8 then return end
    if IsAddonNoise(msg) then return end
    local now = GetServerTime()

    -- 检查是否为集结号底层 MHH 广播
    local mhhLeader, mhhText, mhhFullLeader = ParseMHHMessage(msg, sender)
    if mhhLeader and mhhText and mhhText ~= "" then
        WorldRecruitCache[mhhLeader] = {
            msg = mhhText,
            time = now,
            fullName = mhhFullLeader or sender,
            isMHH = true,
        }
        return
    end

    local pureName = CleanName(sender)
    for k, v in pairs(WorldRecruitCache) do
        if now - v.time > CACHE_EXPIRATION then
            WorldRecruitCache[k] = nil
        end
    end

    WorldRecruitCache[pureName] = {
        msg = msg,
        time = now,
        fullName = sender,
    }
end

-- 4. 获取当前团队领袖与助理名单
local function GetRaidLeaders()
    local leaders = {}
    local num = GetNumGroupMembers()
    if num == 0 then return leaders end

    if not IsInRaid() then
        -- 5人队伍
        for i = 1, num do
            local unit = (i == 1) and "player" or ("party" .. (i - 1))
            if UnitIsGroupLeader(unit) then
                local name = GetUnitName(unit, true)
                if name then
                    leaders[name] = "leader"
                    leaders[CleanName(name)] = "leader"
                end
            end
        end
        return leaders
    end

    -- 团队模式
    for i = 1, num do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
        if name then
            local pureName = CleanName(name)
            if rank == 2 then
                leaders[name] = "leader"
                leaders[pureName] = "leader"
            elseif isML then
                leaders[name] = leaders[name] or "ml"
                leaders[pureName] = leaders[pureName] or "ml"
            elseif rank == 1 then
                leaders[name] = leaders[name] or "assistant"
                leaders[pureName] = leaders[pureName] or "assistant"
            end
        end
    end
    return leaders
end

-- 玩家最后在集结号点击/申请的活动暂存
local LastAppliedMeetingHornActivity = nil

-- 5. 从集结号（MeetingHorn）全方位遍历与查找活动
local function FetchFromMeetingHorn(leaderName)
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MeetingHorn")) or (IsAddOnLoaded and IsAddOnLoaded("MeetingHorn"))
    if not isLoaded then return nil end

    local pureTarget = CleanName(leaderName)

    local ok, title, comment = pcall(function()
        local LibStub = _G.LibStub
        if not LibStub then return nil end
        local MeetingHorn = LibStub:GetLibrary("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("MeetingHorn", true)
        if not MeetingHorn then return nil end

        -- 辅助比较单个活动对象
        local function CheckActivity(act)
            if not act then return nil end
            local lName = act.GetLeader and act:GetLeader() or act.leader or act.creator or (act.data and (act.data.leader or act.data.creator))
            if lName and (IsSamePlayer(lName, pureTarget) or pureTarget == "") then
                local t = act.GetTitle and act:GetTitle() or act.GetActivityName and act:GetActivityName() or act.title or (act.data and (act.data.title or act.data.activityName)) or ""
                local c = act.GetComment and act:GetComment() or act.comment or (act.data and act.data.comment) or ""
                if c ~= "" or t ~= "" then
                    return t, c
                end
            end
            return nil
        end

        -- 1. 优先检查玩家申请的最后一条活动
        if LastAppliedMeetingHornActivity then
            local t, c = CheckActivity(LastAppliedMeetingHornActivity)
            if t or c then return t, c end
        end

        -- 2. 检查 DataBroker
        if MeetingHorn.DataBroker then
            if MeetingHorn.DataBroker.GetPlayerActivity then
                local t, c = CheckActivity(MeetingHorn.DataBroker:GetPlayerActivity())
                if t or c then return t, c end
            end
            if MeetingHorn.DataBroker.activityList and type(MeetingHorn.DataBroker.activityList) == "table" then
                for _, act in pairs(MeetingHorn.DataBroker.activityList) do
                    local t, c = CheckActivity(act)
                    if t or c then return t, c end
                end
            end
        end

        -- 3. 检查 LFG 模块
        local LFG = MeetingHorn.GetModule and MeetingHorn:GetModule('LFG', true)
        if LFG then
            if LFG.GetActivityList then
                local list = LFG:GetActivityList()
                if list and type(list) == "table" then
                    for _, act in ipairs(list) do
                        local t, c = CheckActivity(act)
                        if t or c then return t, c end
                    end
                end
            end
            if LFG.activities and type(LFG.activities) == "table" then
                for _, act in pairs(LFG.activities) do
                    local t, c = CheckActivity(act)
                    if t or c then return t, c end
                end
            end
            if LFG.activityList and type(LFG.activityList) == "table" then
                for _, act in pairs(LFG.activityList) do
                    local t, c = CheckActivity(act)
                    if t or c then return t, c end
                end
            end
        end

        -- 4. 检查 MainPanel.Browser 的活动列表
        if MeetingHorn.MainPanel and MeetingHorn.MainPanel.Browser and MeetingHorn.MainPanel.Browser.ActivityList then
            local list = MeetingHorn.MainPanel.Browser.ActivityList
            if type(list) == "table" then
                for _, act in pairs(list) do
                    local t, c = CheckActivity(act)
                    if t or c then return t, c end
                end
            end
        end

        -- 5. 检查全局 activityList / activities
        if MeetingHorn.activityList and type(MeetingHorn.activityList) == "table" then
            for _, act in pairs(MeetingHorn.activityList) do
                local t, c = CheckActivity(act)
                if t or c then return t, c end
            end
        end
        if MeetingHorn.activities and type(MeetingHorn.activities) == "table" then
            for _, act in pairs(MeetingHorn.activities) do
                local t, c = CheckActivity(act)
                if t or c then return t, c end
            end
        end

        return nil
    end)

    if ok and (title or comment) then
        return title, comment
    end
    return nil
end

-- Hook 集结号的点击与申请动作，捕获玩家正在交互的活动
local function HookMeetingHornInteractions()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("MeetingHorn")) or (IsAddOnLoaded and IsAddOnLoaded("MeetingHorn"))
    if not isLoaded then return end

    pcall(function()
        local LibStub = _G.LibStub
        if not LibStub then return end
        local MeetingHorn = LibStub:GetLibrary("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("MeetingHorn", true)
        if not MeetingHorn then return end

        local LFG = MeetingHorn.GetModule and MeetingHorn:GetModule('LFG', true)
        if LFG and LFG.SignupActivity and not LFG.hasHookedSignupBGLite then
            LFG.hasHookedSignupBGLite = true
            hooksecurefunc(LFG, "SignupActivity", function(self, activity)
                if activity then
                    LastAppliedMeetingHornActivity = activity
                end
            end)
        end
    end)
end

-- 6. 全局当前队伍独立暂存池 (未进本/组队中时的数据容器)
TeamInfo.currentGroupData = {
    yy = "",
    leader = "",
    recruits = {},
    isBound = false,
    boundFB = nil,
}

-- 获取当前查看的副本简写
local function GetCurrentFB()
    return BG.FB1 or (BG.FBtable and BG.FBtable[1]) or "TOC"
end

-- 获取当前卡片所处的展示状态
-- 1: STATE_UNBOUND (进本前/组队未绑定态)
-- 2: STATE_BOUND   (已进本/表格已绑定态)
-- 3: STATE_ARCHIVE (单人查账/历史存档态)
function TeamInfo.GetCardState()
    local inGroup = IsInGroup() or IsInRaid()
    local currentFB = GetCurrentFB()
    if not inGroup then
        local data = BiaoGe and BiaoGe[currentFB] and BiaoGe[currentFB].teamInfo
        return 3, data or { yy = "", leader = "", recruits = {} }, currentFB
    end

    if TeamInfo.currentGroupData.isBound and TeamInfo.currentGroupData.boundFB == currentFB then
        local data = BiaoGe and BiaoGe[currentFB] and BiaoGe[currentFB].teamInfo
        return 2, data or TeamInfo.currentGroupData, currentFB
    end

    return 1, TeamInfo.currentGroupData, currentFB
end

-- 获取适合写入的数据源
function TeamInfo.GetActiveDataForWrite()
    local inGroup = IsInGroup() or IsInRaid()
    if inGroup then
        return TeamInfo.currentGroupData
    else
        local fb = GetCurrentFB()
        if BiaoGe and BiaoGe[fb] then
            BiaoGe[fb].teamInfo = BiaoGe[fb].teamInfo or { yy = "", leader = "", recruits = {} }
            return BiaoGe[fb].teamInfo
        end
    end
    return TeamInfo.currentGroupData
end

-- 将当前暂存的组队信息「固化绑定」到指定副本表格中
function TeamInfo.BindCurrentGroupToFB(targetFB)
    targetFB = targetFB or GetCurrentFB()
    if not BiaoGe or not BiaoGe[targetFB] then return end

    BiaoGe[targetFB].teamInfo = {
        yy = TeamInfo.currentGroupData.yy or "",
        leader = TeamInfo.currentGroupData.leader or "",
        recruits = BG.Copy and BG.Copy(TeamInfo.currentGroupData.recruits) or {},
        bindTime = GetServerTime(),
    }
    TeamInfo.currentGroupData.isBound = true
    TeamInfo.currentGroupData.boundFB = targetFB

    local fbShort = BG.GetFBinfo and BG.GetFBinfo(targetFB, "shortName") or targetFB
    DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. string.format(L["已将当前团队招募语与 YY 成功绑定至 <%s> 表格！"], fbShort))
    if BG.PlaySound then BG.PlaySound(1) end
    TeamInfo.UpdateUI()
end

-- 记录一条通告（自动去重、容量管理，并同步到绑定副本）
function TeamInfo.AddRecruitEntry(channel, text, customTime, FB)
    if not text or text == "" then return false end
    local data = TeamInfo.GetActiveDataForWrite()
    if not data then return false end

    data.recruits = data.recruits or {}
    local timeStr = customTime or date("%H:%M:%S")

    -- 排重：如果已存在相同正文，则跳过
    for _, item in ipairs(data.recruits) do
        if item.text == text then
            return false
        end
    end

    -- 最多保留 15 条
    if #data.recruits >= 15 then
        tremove(data.recruits, 1)
    end

    tinsert(data.recruits, {
        time = timeStr,
        channel = channel or L["团队通告"],
        text = text,
    })

    -- 从通告自动提取 YY
    local yy = ExtractYYFromText(text)
    if yy and (not data.yy or data.yy == "") then
        data.yy = yy
    end

    -- 如果已绑定副本，同步更新副本存档
    if TeamInfo.currentGroupData.isBound and TeamInfo.currentGroupData.boundFB then
        local bfb = TeamInfo.currentGroupData.boundFB
        if BiaoGe and BiaoGe[bfb] and BiaoGe[bfb].teamInfo then
            BiaoGe[bfb].teamInfo.yy = data.yy
            BiaoGe[bfb].teamInfo.recruits = BG.Copy and BG.Copy(data.recruits) or data.recruits
        end
    end

    TeamInfo.UpdateUI()
    return true
end

function TeamInfo.SetYY(yy)
    if not yy then return end
    local cleanYY = tostring(yy):gsub("%s", "")
    local data = TeamInfo.GetActiveDataForWrite()
    if data then
        data.yy = cleanYY
    end
    if TeamInfo.currentGroupData.isBound and TeamInfo.currentGroupData.boundFB then
        local bfb = TeamInfo.currentGroupData.boundFB
        if BiaoGe and BiaoGe[bfb] and BiaoGe[bfb].teamInfo then
            BiaoGe[bfb].teamInfo.yy = cleanYY
        end
    end
    TeamInfo.UpdateUI()
end

-- 7. 进团/组队主触发逻辑 (含团长变更追踪)
local groupJoinTime = 0
function TeamInfo.OnGroupUpdate(forceScan)
    local inGroup = IsInGroup() or IsInRaid()
    if not inGroup then
        TeamInfo.currentGroupData = { yy = "", leader = "", recruits = {}, isBound = false, boundFB = nil }
        TeamInfo.UpdateUI()
        return
    end

    local leaders = GetRaidLeaders()
    local leaderName = nil
    for name, role in pairs(leaders) do
        if role == "leader" then
            leaderName = name
            break
        end
    end
    if not leaderName then
        for name in pairs(leaders) do
            leaderName = name
            break
        end
    end

    local cleanLeader = CleanName(leaderName)
    local data = TeamInfo.currentGroupData

    -- 团长换人追踪 (Leader Change Tracking)
    if cleanLeader ~= "" and data.leader and data.leader ~= "" and data.leader ~= cleanLeader then
        local oldLeader = data.leader
        data.leader = cleanLeader
        local changeMsg = string.format(L["团长变更为: %s (原团长: %s)"], cleanLeader, oldLeader)
        TeamInfo.AddRecruitEntry(L["团队变动"], changeMsg)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r |cffFF9900" .. changeMsg .. "|r")
    elseif cleanLeader ~= "" and (not data.leader or data.leader == "") then
        data.leader = cleanLeader
    end

    -- 自动进本检测：若进入了团队副本且尚未绑定，则自动绑定到对应副本
    local isInstance, instanceType = IsInInstance()
    if isInstance and (instanceType == "raid" or instanceType == "party") then
        local FBID = select(8, GetInstanceInfo())
        if FBID and BG.FBIDtable and BG.FBIDtable[FBID] then
            local fbKey = BG.FBIDtable[FBID]
            if not data.isBound or data.boundFB ~= fbKey then
                TeamInfo.BindCurrentGroupToFB(fbKey)
            end
        end
    end

    -- 1. 扫描集结号
    local title, comment = FetchFromMeetingHorn(leaderName or "")
    if title or comment then
        local fullText = ""
        if title and title ~= "" then
            fullText = "《" .. title .. "》 "
        end
        if comment and comment ~= "" then
            fullText = fullText .. comment
        end
        if fullText ~= "" then
            local added = TeamInfo.AddRecruitEntry(L["集结号"], fullText)
            if added then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动从集结号捕获团队招募: "] .. "|cff00FF00" .. fullText .. "|r")
            end
        end
    end

    -- 2. 扫描世界频道/集结号MHH近期缓存
    if cleanLeader ~= "" and WorldRecruitCache[cleanLeader] then
        local item = WorldRecruitCache[cleanLeader]
        local timeStr = date("%H:%M:%S", item.time)
        local channelName = item.isMHH and L["集结号"] or L["世界频道"]
        local added = TeamInfo.AddRecruitEntry(channelName, item.msg, timeStr)
        if added then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动捕获团长招募: "] .. "|cff00FF00" .. item.msg .. "|r")
        end
    end

    TeamInfo.UpdateUI()
end

-- 多波次延迟扫描，应对暴雪进组网络延迟
local function TriggerMultiWaveScan()
    groupJoinTime = GetServerTime()
    HookMeetingHornInteractions()
    C_Timer.After(0.2, function() TeamInfo.OnGroupUpdate() end)
    C_Timer.After(1.0, function() TeamInfo.OnGroupUpdate() end)
    C_Timer.After(2.5, function() TeamInfo.OnGroupUpdate() end)
    C_Timer.After(5.0, function() TeamInfo.OnGroupUpdate() end)
end

-- 判断一条消息是否为合法的开团招募/团队规则通告 (经过严密语义特征引擎筛选)
local function IsValidRecruitOrRuleMessage(msg)
    if not msg or type(msg) ~= "string" or #msg < 4 then return false end
    if IsAddonNoise(msg) then return false end

    -- 必须命中以下实质性开团规则之一：
    if ExtractYYFromText(msg) then return true end
    if ContainsTitanKeyword(msg) then return true end

    -- 补充开团规则关键词
    local RULE_EXTRA_KEYWORDS = {
        "规则", "起拍", "罚款", "补贴", "补助", "打手", "考核", "合剂", "分金", "听指挥",
        "不分金", "灭团", "清buff", "消灭", "装备起", "包团", "流拍", "降价", "退组",
    }
    for _, kw in ipairs(RULE_EXTRA_KEYWORDS) do
        if msg:find(kw, 1, true) then
            return true
        end
    end

    return false
end

-- 8. 聊天与组队事件监听
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_YELL")
eventFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:RegisterEvent("GROUP_LEFT")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, msg, sender, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        HookMeetingHornInteractions()
        TeamInfo.OnGroupUpdate()
        return
    elseif event == "GROUP_JOINED" then
        TriggerMultiWaveScan()
        return
    elseif event == "GROUP_LEFT" then
        TeamInfo.currentGroupData = { yy = "", leader = "", recruits = {}, isBound = false, boundFB = nil }
        TeamInfo.UpdateUI()
        return
    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        if IsInGroup() or IsInRaid() then
            C_Timer.After(0.3, function() TeamInfo.OnGroupUpdate() end)
        else
            TeamInfo.currentGroupData = { yy = "", leader = "", recruits = {}, isBound = false, boundFB = nil }
            TeamInfo.UpdateUI()
        end
        return
    end

    if not msg or not sender then return end
    local pureSender = CleanName(sender)

    -- 场景 A：公共频道/大喊/集结号MHH广播（入缓存）
    if event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_YELL" then
        if msg:find("^MHH") or IsValidRecruitOrRuleMessage(msg) then
            AddToWorldCache(sender, msg)
        end
        return
    end

    -- 场景 B：团队内部消息 (必须是团长且必须经过规则引擎过滤)
    local leaders = GetRaidLeaders()
    if leaders[sender] or leaders[pureSender] then
        -- 纯数字 YY 容错 (进团 10 分钟内)
        local numOnly = msg:gsub("%s", ""):match("^(%d+)$")
        if numOnly and #numOnly >= 4 and #numOnly <= 12 and (GetServerTime() - groupJoinTime < 600) then
            TeamInfo.SetYY(numOnly)
            TeamInfo.AddRecruitEntry(L["团队频道"], L["团长发布YY号: "] .. numOnly)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动记录团长YY: "] .. "|cff00FF00" .. numOnly .. "|r")
            return
        end

        -- 严格经过开团规则与时光服引擎过滤，杜绝一切闲聊与客套话
        if IsValidRecruitOrRuleMessage(msg) then
            local channelTag = L["团队频道"]
            if event == "CHAT_MSG_RAID_WARNING" then
                channelTag = L["团队警告"]
            elseif event == "CHAT_MSG_WHISPER" then
                channelTag = L["密语"]
            end
            TeamInfo.AddRecruitEntry(channelTag, msg)
        end
    end
end)

-- 9. UI 组件构建 (方案 A：三态指示卡片)
function TeamInfo.CreateUI()
    local parent = BG and BG.MainFrame
    if not parent or TeamInfo.cardFrame then return end

    local f = CreateFrame("Frame", "BGLite_TeamInfoCard", parent, "BackdropTemplate")
    f:SetSize(525, 48)
    f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 295, 30)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel((parent:GetFrameLevel() or 100) + 30)
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0, 0, 0, 0.88)
    TeamInfo.cardFrame = f

    -- 状态标签与标题
    local statusTag = f:CreateFontString(nil, "ARTWORK")
    statusTag:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    statusTag:SetPoint("TOPLEFT", 8, -6)
    f.statusTag = statusTag

    -- 团长信息
    local leaderText = f:CreateFontString(nil, "ARTWORK")
    leaderText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    leaderText:SetPoint("LEFT", statusTag, "RIGHT", 4, 0)
    leaderText:SetTextColor(1, 0.82, 0)
    f.leaderText = leaderText

    -- YY 频道区域
    local yyLabel = f:CreateFontString(nil, "ARTWORK")
    yyLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    yyLabel:SetPoint("LEFT", leaderText, "RIGHT", 6, 0)
    yyLabel:SetTextColor(1, 1, 1)
    yyLabel:SetText(L["YY:"])
    f.yyLabel = yyLabel

    local yyEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    yyEdit:SetSize(68, 18)
    yyEdit:SetPoint("LEFT", yyLabel, "RIGHT", 2, 0)
    yyEdit:SetAutoFocus(false)
    yyEdit:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    yyEdit:SetTextColor(0, 1, 0)
    f.yyEdit = yyEdit

    yyEdit:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput then
            local text = self:GetText():gsub("%s", "")
            TeamInfo.SetYY(text)
        end
    end)

    -- 复制 YY 按钮
    local btnCopyYY = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCopyYY:SetSize(38, 20)
    btnCopyYY:SetPoint("LEFT", yyEdit, "RIGHT", 3, 0)
    btnCopyYY:SetText(L["复制"])
    btnCopyYY:SetScript("OnClick", function()
        local _, data = TeamInfo.GetCardState()
        local yy = (data and data.yy and data.yy ~= "") and data.yy or yyEdit:GetText()
        if yy and yy ~= "" then
            local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or DEFAULT_CHAT_FRAME.editBox
            ChatEdit_ActivateChat(editBox)
            editBox:SetText(yy)
            editBox:HighlightText()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已将 YY 频道号放入输入框: "] .. "|cff00FF00" .. yy .. "|r")
            if BG.PlaySound then BG.PlaySound(1) end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["当前没有记录到有效的 YY 号"])
        end
    end)
    f.btnCopyYY = btnCopyYY

    -- 导出全部通告按钮 (靠右)
    local btnCopyAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCopyAll:SetSize(58, 20)
    btnCopyAll:SetPoint("TOPRIGHT", -6, -5)
    btnCopyAll:SetText(L["导出"])
    btnCopyAll:SetScript("OnClick", function()
        local _, data = TeamInfo.GetCardState()
        if not data or not data.recruits or #data.recruits == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["当前暂无招募通告记录"])
            return
        end
        local lines = {}
        for _, item in ipairs(data.recruits) do
            tinsert(lines, string.format("[%s] [%s] %s", item.time or "", item.channel or "", item.text or ""))
        end
        local fullOutput = table.concat(lines, "\n")
        local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or DEFAULT_CHAT_FRAME.editBox
        ChatEdit_ActivateChat(editBox)
        editBox:SetText(fullOutput)
        editBox:HighlightText()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已将全部招募通告（带时间戳）放入输入框！"])
        if BG.PlaySound then BG.PlaySound(1) end
    end)
    f.btnCopyAll = btnCopyAll

    -- 手动刷新按钮
    local btnScan = CreateFrame("Button", nil, f)
    btnScan:SetSize(35, 20)
    btnScan:SetPoint("RIGHT", btnCopyAll, "LEFT", -3, 0)
    local btnScanText = btnScan:CreateFontString(nil, "ARTWORK")
    btnScanText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    btnScanText:SetPoint("CENTER")
    btnScanText:SetText("|cff00FF00[抓取]|r")
    btnScan:SetScript("OnClick", function()
        TeamInfo.OnGroupUpdate(true)
        if BG.PlaySound then BG.PlaySound(1) end
    end)
    btnScan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(L["点击立即重新从集结号与世界频道抓取团长招募语与YY"])
        GameTooltip:Show()
    end)
    btnScan:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.btnScan = btnScan

    -- 一键绑定开团按钮 (仅在未绑定态出现)
    local btnBind = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnBind:SetSize(58, 20)
    btnBind:SetPoint("RIGHT", btnScan, "LEFT", -3, 0)
    btnBind:SetText("|cffFF9900" .. L["绑定开团"] .. "|r")
    btnBind:SetScript("OnClick", function()
        TeamInfo.BindCurrentGroupToFB()
    end)
    btnBind:SetScript("OnEnter", function(self)
        local curFB = GetCurrentFB()
        local fbShort = BG.GetFBinfo and BG.GetFBinfo(curFB, "shortName") or curFB
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(string.format(L["点击将当前队伍信息与招募通告正式绑定至 <%s> 表格"], fbShort))
        GameTooltip:Show()
    end)
    btnBind:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.btnBind = btnBind

    -- 第二行：通告条目展示框 (鼠标悬停展开完整历史)
    local recruitBox = CreateFrame("Button", nil, f, "BackdropTemplate")
    recruitBox:SetSize(509, 18)
    recruitBox:SetPoint("BOTTOMLEFT", 8, 4)
    recruitBox:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 6,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    recruitBox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    recruitBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    f.recruitBox = recruitBox

    local recruitText = recruitBox:CreateFontString(nil, "ARTWORK")
    recruitText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    recruitText:SetPoint("TOPLEFT", 4, -2)
    recruitText:SetPoint("BOTTOMRIGHT", -4, 2)
    recruitText:SetJustifyH("LEFT")
    recruitText:SetJustifyV("MIDDLE")
    recruitText:SetWordWrap(false)
    recruitText:SetTextColor(0.9, 0.9, 0.9)
    f.recruitText = recruitText

    -- 鼠标悬停显示全部多条通告 Tooltip
    recruitBox:SetScript("OnEnter", function(self)
        local _, data = TeamInfo.GetCardState()
        if not data or not data.recruits or #data.recruits == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["【团队招募与开团通告完整时序记录】"], 0, 0.9, 1)
        GameTooltip:AddLine(" ")
        for i, item in ipairs(data.recruits) do
            local header = string.format("|cff00FF00[%s]|r |cffFFFF00[%s]|r", item.time or "", item.channel or "")
            GameTooltip:AddLine(header, 1, 1, 1)
            GameTooltip:AddLine("  " .. (item.text or ""), 0.9, 0.9, 0.9, true)
            if i < #data.recruits then
                GameTooltip:AddLine(" ")
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["提示: 点击右上角 [导出] 按钮可一键导出带时间戳正文"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    recruitBox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

end

-- 10. 刷新卡片 UI 与状态机渲染
function TeamInfo.UpdateUI()
    local f = TeamInfo.cardFrame
    if not f or not f:IsVisible() then return end

    local state, data, currentFB = TeamInfo.GetCardState()
    local fbShort = BG.GetFBinfo and BG.GetFBinfo(currentFB, "shortName") or currentFB

    if state == 1 then
        -- 状态 1：进本前 / 组队未绑定态 (翠绿边框)
        f:SetBackdropBorderColor(0.0, 1.0, 0.4, 0.95)
        f.statusTag:SetText("|cff00FF66[当前队伍(未绑定)]|r")
        if f.btnBind then f.btnBind:Show() end
        if f.btnScan then f.btnScan:Show() end
    elseif state == 2 then
        -- 状态 2：已进本 / 表格已绑定态 (亮蓝边框)
        f:SetBackdropBorderColor(0.2, 0.8, 1.0, 0.95)
        f.statusTag:SetText(string.format("|cff00BFFF[%s已绑定]|r", fbShort))
        if f.btnBind then f.btnBind:Hide() end
        if f.btnScan then f.btnScan:Show() end
    else
        -- 状态 3：单人 / 历史存档态 (暗灰边框)
        f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.7)
        f.statusTag:SetText(string.format("|cff888888[%s存档]|r", fbShort))
        if f.btnBind then f.btnBind:Hide() end
        if f.btnScan then f.btnScan:Hide() end
    end

    if data and data.leader and data.leader ~= "" then
        f.leaderText:SetText(string.format("(%s: %s)", L["团长"], SetClassCFF and SetClassCFF(data.leader) or data.leader))
    else
        f.leaderText:SetText("")
    end

    if not f.yyEdit:HasFocus() then
        f.yyEdit:SetText((data and data.yy) or "")
    end

    if data and data.recruits and #data.recruits > 0 then
        local lines = {}
        for i = math.max(1, #data.recruits - 1), #data.recruits do
            local item = data.recruits[i]
            tinsert(lines, string.format("|cff00FF00[%s]|r |cffFFFF00[%s]|r %s", item.time or "", item.channel or "", item.text or ""))
        end
        f.recruitText:SetText(table.concat(lines, "\n"))
    else
        if state == 1 then
            f.recruitText:SetText("|cff777777" .. L["已开启当前队伍监听，自动捕获集结号、YY与团长规则..."] .. "|r")
        else
            f.recruitText:SetText("|cff777777" .. L["暂无该场次的招募通告与开团规则记录"] .. "|r")
        end
    end
end

-- 自愈挂载：无论何时打开表格，确保卡片已创建并处于显示状态
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        if BG and BG.MainFrame and not TeamInfo.cardFrame then
            TeamInfo.CreateUI()
        end
        if TeamInfo.cardFrame then
            TeamInfo.UpdateUI()
        end
    end)
end)
