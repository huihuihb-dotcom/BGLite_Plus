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

-- 3. 插件自动欢迎/通知/金团拍卖等黑名单 (杜绝网易有爱、大脚入队代发及金团拍卖喊话干扰)
local NOISE_KEYWORDS = {
    "有爱提示", "大脚提示", "大脚团队", "爱不易", "网易有爱",
    "欢迎新队友", "欢迎加入", "愿我们同心协力", "拥有一次完美的旅程",
    "祝大家游戏愉快", "开始通报", "准备确认", "插件提示",
    -- 金团拍卖及装备升级过滤
    "拍卖开始", "流拍", "建议升级",
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

-- 清理集结号内部协议元数据（如缺职业、版本掩码、MHH尾缀），截断 WARRIOR / 职业列表之前的内容
local function CleanMeetingHornRawText(text)
    if not text or text == "" then return "" end

    -- 1. 截断职业列表或内部职业标识之前的协议串 (WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, DEATHKNIGHT, SHAMAN, MAGE, WARLOCK, DRUID)
    local CLASS_TOKENS = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    }
    for _, classToken in ipairs(CLASS_TOKENS) do
        -- 匹配 ..WARRIOR 或 .WARRIOR 或 空格WARRIOR 或 _WARRIOR
        local s, e = text:find("[%s%.~_]+" .. classToken)
        if s and s > 1 then
            text = text:sub(1, s - 1)
        end
    end

    -- 2. 截断集结号协议尾缀 (如 ~0,0,3 或 .MHH@@ 或 MHH@)
    local s1 = text:find("[~_]%d+") or text:find("[%s%.~_]*MHH@*")
    if s1 and s1 > 1 then
        text = text:sub(1, s1 - 1)
    end

    -- 3. 截断版本/状态编码数字串 (如 3.80.3456.1..)
    text = text:gsub("[%s%.~_]*%d+%.%d+%.%d+%.%d+.*$", "")
    text = text:gsub("[%s%.~_]*%d+%.%d+%.%d+.*$", "")

    -- 4. 去除多余末尾的点号、波浪号和空白
    text = text:gsub("[%s%.~_]+$", "")
    return text:trim()
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
        formatted = CleanMeetingHornRawText(formatted)
        return CleanName(leader), formatted, leader
    end
    return nil
end

-- 4. 公共频道招募缓存池
local WorldRecruitCache = {}
local CACHE_EXPIRATION = 15 * 60 -- 15 分钟

local function AddToWorldCache(sender, msg)
    if not sender or not msg or #msg < 4 then return end
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

    local cleanMsg = CleanMeetingHornRawText(msg)
    if cleanMsg == "" then return end

    local pureName = CleanName(sender)
    for k, v in pairs(WorldRecruitCache) do
        if now - v.time > CACHE_EXPIRATION then
            WorldRecruitCache[k] = nil
        end
    end

    WorldRecruitCache[pureName] = {
        msg = cleanMsg,
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

-- 6. 数据存储与持久化 (支持 Reload 全状态自愈与防丢)
local function GetCurrentFB()
    return BG.FB1 or (BG.FBtable and BG.FBtable[1]) or "TOC"
end

local function InitDataPersistence()
    if not BiaoGe then return end
    BiaoGe.currentGroupData = BiaoGe.currentGroupData or {
        yy = "",
        leader = "",
        recruits = {},
        isBound = false,
        boundFB = nil,
    }
    TeamInfo.currentGroupData = BiaoGe.currentGroupData
end

-- 获取当前面板所处的展示状态
-- 1: STATE_UNBOUND (进本前/组队未绑定态)
-- 2: STATE_BOUND   (已进本/表格已绑定态)
-- 3: STATE_ARCHIVE (单人查账/历史存档态)
function TeamInfo.GetCardState()
    InitDataPersistence()
    local currentFB = GetCurrentFB()

    -- 历史表格查看态检测：如果正在查看历史账单，优先只读展示该历史快照中的 teamInfo
    if BG and BG.HistoryMainFrame and BG.HistoryMainFrame:IsShown() and BG.History and BG.History.chooseNum then
        local num = BG.History.chooseNum
        local histList = BiaoGe and BiaoGe.HistoryList and BiaoGe.HistoryList[currentFB]
        if histList and histList[num] then
            local DT = histList[num][1]
            local histData = BiaoGe.History and BiaoGe.History[currentFB] and BiaoGe.History[currentFB][DT]
            local histTeam = histData and histData.teamInfo
            return 3, histTeam or { yy = "", leader = "", recruits = {} }, currentFB
        end
    end

    local inGroup = IsInGroup() or IsInRaid()
    local fbData = BiaoGe and BiaoGe[currentFB] and BiaoGe[currentFB].teamInfo

    if not inGroup then
        return 3, fbData or { yy = "", leader = "", recruits = {} }, currentFB
    end

    -- 组队状态下：如果已绑定当前副本，或者当前副本有持久化记录
    if (TeamInfo.currentGroupData.isBound and TeamInfo.currentGroupData.boundFB == currentFB)
       or (fbData and fbData.leader and fbData.leader ~= "") then
        return 2, fbData or TeamInfo.currentGroupData, currentFB
    end

    return 1, TeamInfo.currentGroupData, currentFB
end

-- 获取适合写入的数据源
function TeamInfo.GetActiveDataForWrite()
    InitDataPersistence()
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
    InitDataPersistence()
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
    if IsAddonNoise(text) then return false end
    text = CleanMeetingHornRawText(text)
    if not text or text == "" then return false end
    if IsAddonNoise(text) then return false end

    InitDataPersistence()
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

    -- 最多保留 100 条历史
    if #data.recruits >= 100 then
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
    InitDataPersistence()
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

-- 统一团队信息调试日志打印 (受团队工具中的“开启调试日志”复选框控制)
function TeamInfo.Log(msg, colorHex)
    local isDebug = false
    if ns.RaidTool and ns.RaidTool.IsDebugEnabled then
        isDebug = ns.RaidTool.IsDebugEnabled()
    elseif BiaoGe and BiaoGe.RaidTool and BiaoGe.RaidTool.debugLog ~= nil then
        isDebug = (BiaoGe.RaidTool.debugLog == true or BiaoGe.RaidTool.debugLog == 1)
    elseif BiaoGe and BiaoGe.options and BiaoGe.options.raidToolDebugLog ~= nil then
        isDebug = (BiaoGe.options.raidToolDebugLog == 1 or BiaoGe.options.raidToolDebugLog == true)
    end

    if isDebug then
        local c = colorHex or "00FFCC"
        DEFAULT_CHAT_FRAME:AddMessage("|cff" .. c .. "[BGLite 团队信息] " .. msg .. "|r")
    end
end

-- 7. 进团/组队主触发逻辑 (含团长变更追踪与进本自动绑定)
local groupJoinTime = 0
function TeamInfo.OnGroupUpdate(forceScan)
    InitDataPersistence()
    local inGroup = IsInGroup() or IsInRaid()
    if not inGroup then
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

    if forceScan then
        TeamInfo.Log(string.format(L["开始手动抓取队伍信息... 当前团长: |cffFFFF00%s|r"], (cleanLeader ~= "" and cleanLeader or L["未知"])), "00FF88")
    end

    -- 团长换人追踪 (Leader Change Tracking)
    if cleanLeader ~= "" and data.leader and data.leader ~= "" and data.leader ~= cleanLeader then
        local oldLeader = data.leader
        data.leader = cleanLeader
        local changeMsg = string.format(L["团长变更为: %s (原团长: %s)"], cleanLeader, oldLeader)
        TeamInfo.AddRecruitEntry(L["团队变动"], changeMsg)
        TeamInfo.Log(changeMsg, "FF9900")
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r |cffFF9900" .. changeMsg .. "|r")
    elseif cleanLeader ~= "" and (not data.leader or data.leader == "") then
        data.leader = cleanLeader
    end

    -- 自动进本检测：若进入了团队副本且尚未绑定，则自动绑定到对应副本
    local currentFBKey = nil
    if BG and BG.FB2 then
        currentFBKey = BG.FB2
    else
        local isInstance, instanceType = IsInInstance()
        if isInstance and (instanceType == "raid" or instanceType == "party") then
            local FBID = select(8, GetInstanceInfo())
            if FBID and BG and BG.FBIDtable and BG.FBIDtable[FBID] then
                currentFBKey = BG.FBIDtable[FBID]
            end
        end
    end

    if currentFBKey and currentFBKey ~= "" then
        if not data.isBound or data.boundFB ~= currentFBKey then
            TeamInfo.Log(string.format(L["检测到已进入副本 <%s>，正在执行自动绑定..."], currentFBKey), "00BFFF")
            TeamInfo.BindCurrentGroupToFB(currentFBKey)
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
            TeamInfo.Log(string.format(L["【集结号】成功抓取活动: %s"], fullText), "00FF00")
            -- if added then
            --     DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动从集结号捕获团队招募: "] .. "|cff00FF00" .. fullText .. "|r")
            -- end
        end
    else
        if forceScan then
            TeamInfo.Log(L["【集结号】未检索到当前团长发布的有效活动"], "AAAAAA")
        end
    end

    -- 2. 扫描世界频道/集结号MHH近期缓存
    if cleanLeader ~= "" and WorldRecruitCache[cleanLeader] then
        local item = WorldRecruitCache[cleanLeader]
        local timeStr = date("%H:%M:%S", item.time)
        local channelName = item.isMHH and L["集结号"] or L["世界频道"]
        local added = TeamInfo.AddRecruitEntry(channelName, item.msg, timeStr)
        TeamInfo.Log(string.format(L["【世界频道缓存】匹配到团长喊话: %s"], item.msg), "00FF00")
        -- if added then
        --     DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动捕获团长招募: "] .. "|cff00FF00" .. item.msg .. "|r")
        -- end
    else
        if forceScan then
            TeamInfo.Log(L["【世界频道缓存】近 15 分钟内未发现该团长的开团喊话"], "AAAAAA")
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
        "不分金", "灭团", "清buff", "消灭", "装备起", "包团", "降价", "退组",
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
        C_Timer.After(1.0, function() TeamInfo.OnGroupUpdate() end)
        C_Timer.After(3.0, function() TeamInfo.OnGroupUpdate() end)
        return
    elseif event == "GROUP_JOINED" then
        TriggerMultiWaveScan()
        return
    elseif event == "GROUP_LEFT" then
        if BiaoGe and BiaoGe.currentGroupData then
            BiaoGe.currentGroupData = { yy = "", leader = "", recruits = {}, isBound = false, boundFB = nil }
            TeamInfo.currentGroupData = BiaoGe.currentGroupData
        end
        TeamInfo.UpdateUI()
        return
    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        if IsInGroup() or IsInRaid() then
            C_Timer.After(0.3, function() TeamInfo.OnGroupUpdate() end)
        else
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
            -- DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已自动记录团长YY: "] .. "|cff00FF00" .. numOnly .. "|r")
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

-- 9. UI 组件构建 (右侧抽屉侧边栏 + 顶部控制按钮)
function TeamInfo.CreateUI()
    local parent = BG and BG.MainFrame
    if not parent or TeamInfo.sideFrame then return end

    -- 9.1 顶部栏入口切换按钮 (挂载在拍卖记录按钮旁边)
    local topBtn = CreateFrame("Button", "BGLite_ButtonTeamInfo", parent)
    topBtn:SetSize(65, 20)
    if BG.ButtonAuctionLog then
        topBtn:SetPoint("LEFT", BG.ButtonAuctionLog, "RIGHT", BG.TopLeftButtonJianGe or 10, 0)
    elseif BG.ButtonMove then
        topBtn:SetPoint("LEFT", BG.ButtonMove, "RIGHT", BG.TopLeftButtonJianGe or 10, 0)
    else
        topBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 220, -5)
    end
    topBtn:SetNormalFontObject(BG.FontGreen15 or "GameFontNormal")
    topBtn:SetHighlightFontObject(BG.FontWhite15 or "GameFontHighlight")
    topBtn:SetText(L["团队信息"])
    topBtn:SetSize(topBtn:GetFontString():GetWidth() + 6, 20)
    if BG.SetTextHighlightTexture then BG.SetTextHighlightTexture(topBtn) end
    TeamInfo.topBtn = topBtn

    topBtn:SetScript("OnClick", function(self)
        BiaoGe.options = BiaoGe.options or {}
        if TeamInfo.sideFrame:IsVisible() then
            BiaoGe.options.showTeamInfoFrame = 0
            TeamInfo.sideFrame:Hide()
        else
            BiaoGe.options.showTeamInfoFrame = 1
            TeamInfo.sideFrame:Show()
            TeamInfo.UpdateUI()
        end
        if BG.PlaySound then BG.PlaySound(1) end
    end)
    topBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["团队信息与开团通告"], 1, 1, 1)
        GameTooltip:AddLine(L["点击展开/收起右侧团队信息面板。"], 1, 0.82, 0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["功能特性："], 0, 0.9, 1)
        GameTooltip:AddLine(L["自动捕获集结号、世界喊话与开团规则，支持YY号一键复制及副本账单自动绑定。"], 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["【开发调试中】如遇任何异常或有优化建议，欢迎前往 DD频道: 434056 交流反馈！"], 0.2, 1, 0.6, true)
        GameTooltip:Show()
    end)
    topBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 9.2 右侧抽屉侧边栏 (挂载在 BG.MainFrame 右侧边缘，高度与主界面及拍卖记录一致)
    local fHeight = (BG.FBHeight and BG.FB1 and BG.FBHeight[BG.FB1]) or (parent:GetHeight()) or 560
    local f = CreateFrame("Frame", "BGLite_TeamInfoSideFrame", parent, "BackdropTemplate")
    f:SetSize(340, fHeight)
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 3, 0)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel((parent:GetFrameLevel() or 100) + 30)
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    f:SetBackdropBorderColor(0.2, 0.8, 1.0, 0.95)
    f:EnableMouse(true)
    f:Hide()
    TeamInfo.sideFrame = f

    -- 顶部标题与状态标签
    local titleText = f:CreateFontString(nil, "ARTWORK")
    titleText:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetTextColor(0, 0.9, 1)
    titleText:SetText(L["团队信息与招募通告"])
    f.titleText = titleText

    -- 右上角关闭按钮
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        BiaoGe.options = BiaoGe.options or {}
        BiaoGe.options.showTeamInfoFrame = 0
        f:Hide()
        if BG.PlaySound then BG.PlaySound(1) end
    end)

    -- 状态标签
    local statusTag = f:CreateFontString(nil, "ARTWORK")
    statusTag:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    statusTag:SetPoint("TOPLEFT", 12, -32)
    f.statusTag = statusTag

    -- 团长信息
    local leaderText = f:CreateFontString(nil, "ARTWORK")
    leaderText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    leaderText:SetPoint("LEFT", statusTag, "RIGHT", 6, 0)
    leaderText:SetTextColor(1, 0.82, 0)
    f.leaderText = leaderText

    -- 第一操作行：YY 频道与复制
    local yyLabel = f:CreateFontString(nil, "ARTWORK")
    yyLabel:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    yyLabel:SetPoint("TOPLEFT", 12, -54)
    yyLabel:SetTextColor(1, 1, 1)
    yyLabel:SetText(L["YY 频道:"])
    f.yyLabel = yyLabel

    local yyEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    yyEdit:SetSize(110, 20)
    yyEdit:SetPoint("LEFT", yyLabel, "RIGHT", 6, 0)
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

    local btnCopyYY = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCopyYY:SetSize(52, 22)
    btnCopyYY:SetPoint("LEFT", yyEdit, "RIGHT", 5, 0)
    btnCopyYY:SetText(L["复制"])
    btnCopyYY:SetScript("OnClick", function()
        local _, data = TeamInfo.GetCardState()
        local yy = (data and data.yy and data.yy ~= "") and data.yy or yyEdit:GetText()
        if yy and yy ~= "" then
            local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or DEFAULT_CHAT_FRAME.editBox
            ChatEdit_ActivateChat(editBox)
            editBox:SetText(yy)
            editBox:HighlightText()
            -- DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已将 YY 频道号放入输入框: "] .. "|cff00FF00" .. yy .. "|r")
            if BG.PlaySound then BG.PlaySound(1) end
        else
            -- DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["当前没有记录到有效的 YY 号"])
        end
    end)
    f.btnCopyYY = btnCopyYY

    -- 第二操作行：功能按钮组 (已移除导出通告)
    local btnBind = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnBind:SetSize(90, 22)
    btnBind:SetPoint("TOPLEFT", 12, -80)
    btnBind:SetText("|cffFF9900" .. L["绑定开团"] .. "|r")
    btnBind:SetScript("OnClick", function()
        TeamInfo.BindCurrentGroupToFB()
    end)
    f.btnBind = btnBind

    local btnScan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnScan:SetSize(75, 22)
    btnScan:SetPoint("LEFT", btnBind, "RIGHT", 8, 0)
    btnScan:SetText("|cff00FF00" .. L["抓取"] .. "|r")
    btnScan:SetScript("OnClick", function()
        TeamInfo.OnGroupUpdate(true)
        if BG.PlaySound then BG.PlaySound(1) end
    end)
    f.btnScan = btnScan

    -- 分割线
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetSize(316, 1)
    line:SetPoint("TOPLEFT", 12, -108)
    line:SetColorTexture(0.3, 0.3, 0.3, 0.8)

    -- 通告列表标题
    local listTitle = f:CreateFontString(nil, "ARTWORK")
    listTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    listTitle:SetPoint("TOPLEFT", 12, -114)
    listTitle:SetTextColor(0.8, 0.8, 0.8)
    listTitle:SetText(L["招募喊话与团队规则时序列表:"])

    -- 9.3 滚动列表容器 (填满等高下方区域)
    local scroll = CreateFrame("ScrollFrame", "BGLite_TeamInfoScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -132)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    if BG.CreateSrollBarBackdrop then BG.CreateSrollBarBackdrop(scroll.ScrollBar) end
    if BG.HookScrollBarShowOrHide then BG.HookScrollBarShowOrHide(scroll) end
    f.scroll = scroll

    local content = CreateFrame("Frame", "BGLite_TeamInfoScrollContent", scroll)
    content:SetSize(296, 300)
    scroll:SetScrollChild(content)
    f.content = content
    f.entries = {}

    -- 空数据提示
    local emptyHint = f.content:CreateFontString(nil, "ARTWORK")
    emptyHint:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    emptyHint:SetPoint("TOPLEFT", 6, -10)
    emptyHint:SetPoint("TOPRIGHT", -6, -10)
    emptyHint:SetJustifyH("LEFT")
    emptyHint:SetTextColor(0.6, 0.6, 0.6)
    f.emptyHint = emptyHint

    -- 依据持久化选项恢复显示/隐藏
    BiaoGe.options = BiaoGe.options or {}
    if BiaoGe.options.showTeamInfoFrame == 1 then
        f:Show()
    else
        f:Hide()
    end

    TeamInfo.UpdateUI()
end

-- 10. 刷新侧边栏 UI 与状态机渲染 (高度动态自适应 + 滚动条目渲染)
function TeamInfo.UpdateUI()
    InitDataPersistence()
    local f = TeamInfo.sideFrame
    if not f or not f:IsVisible() then return end

    local state, data, currentFB = TeamInfo.GetCardState()
    local fbShort = BG.GetFBinfo and BG.GetFBinfo(currentFB, "shortName") or currentFB

    -- 动态与主界面及拍卖记录保持一致高度
    local parent = BG and BG.MainFrame
    local h = (BG.FBHeight and currentFB and BG.FBHeight[currentFB]) or (parent and parent:GetHeight()) or 560
    f:SetHeight(h)

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

    -- 渲染时序通告列表项
    for _, btn in ipairs(f.entries) do
        btn:Hide()
    end

    local recruits = (data and data.recruits) or {}
    local startY = 0
    local itemHeight = 42
    local totalHeight = 0

    if #recruits == 0 then
        if f.emptyHint then
            if state == 1 then
                f.emptyHint:SetText(L["已开启队伍监听，自动捕获集结号、YY与开团规则..."])
            else
                f.emptyHint:SetText(L["暂无该副本场次的招募通告与开团规则记录"])
            end
            f.emptyHint:Show()
        end
    else
        if f.emptyHint then f.emptyHint:Hide() end

        for i, item in ipairs(recruits) do
            local btn = f.entries[i]
            if not btn then
                btn = CreateFrame("Button", nil, f.content, "BackdropTemplate")
                btn:SetSize(292, itemHeight)
                btn:SetFrameStrata(f:GetFrameStrata())
                btn:SetFrameLevel(f.content:GetFrameLevel() + 2)
                btn:SetBackdrop({
                    bgFile = "Interface/Buttons/WHITE8X8",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    edgeSize = 6,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 }
                })
                btn:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
                btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

                local timeText = btn:CreateFontString(nil, "OVERLAY")
                timeText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                timeText:SetPoint("TOPLEFT", 5, -3)
                timeText:SetPoint("TOPRIGHT", -5, -3)
                timeText:SetJustifyH("LEFT")
                btn.timeText = timeText

                local bodyText = btn:CreateFontString(nil, "OVERLAY")
                bodyText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                bodyText:SetPoint("TOPLEFT", 5, -17)
                bodyText:SetPoint("BOTTOMRIGHT", -5, 3)
                bodyText:SetJustifyH("LEFT")
                bodyText:SetJustifyV("TOP")
                bodyText:SetWordWrap(true)
                bodyText:SetTextColor(0.9, 0.9, 0.9)
                btn.bodyText = bodyText

                btn:SetScript("OnClick", function(self, button)
                    if self.rawText and self.rawText ~= "" then
                        local editBox = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend() or DEFAULT_CHAT_FRAME.editBox
                        ChatEdit_ActivateChat(editBox)
                        editBox:SetText(self.rawText)
                        editBox:HighlightText()
                        -- DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r " .. L["已将此条通告放入输入框"])
                        if BG.PlaySound then BG.PlaySound(1) end
                    end
                end)

                btn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.2, 0.35, 0.5, 0.95)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.headerText or "", 1, 1, 1)
                    GameTooltip:AddLine(self.rawText or "", 0.9, 0.9, 0.9, true)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["点击此条可将正文放入聊天输入框"], 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
                    GameTooltip:Hide()
                end)

                f.entries[i] = btn
            end

            btn:SetPoint("TOPLEFT", f.content, "TOPLEFT", 2, -startY)
            local header = string.format("|cff00FF00[%s]|r |cffFFFF00[%s]|r", item.time or "", item.channel or "")
            btn.timeText:SetText(header)
            btn.bodyText:SetText(item.text or "")
            btn.headerText = header
            btn.rawText = item.text or ""
            btn:Show()

            startY = startY + itemHeight + 3
            totalHeight = startY
        end
    end

    f.content:SetSize(296, math.max(20, totalHeight))
    if f.scroll and f.scroll.UpdateScrollChildRect then
        f.scroll:UpdateScrollChildRect()
    end
end

-- 11. Hook 清空表格逻辑，当清空某个副本表格时，同步清空该副本绑定的团队信息
if BG and BG.ClearBiaoGe then
    hooksecurefunc(BG, "ClearBiaoGe", function(clearType, FB)
        if clearType == "biaoge" and FB and BiaoGe and BiaoGe[FB] then
            BiaoGe[FB].teamInfo = nil
            TeamInfo.UpdateUI()
        end
    end)
end

-- 自愈与定时扫描挂载：定时检测进本状态与自动同步
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, function()
        if BG and BG.MainFrame and not TeamInfo.sideFrame then
            TeamInfo.CreateUI()
        end
        if TeamInfo.sideFrame and TeamInfo.sideFrame:IsVisible() then
            TeamInfo.UpdateUI()
        end
    end)
end)

-- 每 3 秒定期检测是否进入了新副本，实现 100% 自动绑定
C_Timer.NewTicker(3, function()
    if IsInGroup() or IsInRaid() then
        TeamInfo.OnGroupUpdate()
    end
end)
