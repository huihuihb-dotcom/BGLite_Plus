if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidCD = {}
ns.RaidCD = RaidCD
_G.RaidCD = RaidCD

--------------------------------------------------------------------------------
-- 1. 监控技能核心数据库定义
--------------------------------------------------------------------------------
-- 默认监控规则：
-- 1) 圣骑士：默认仅勾选【神圣牺牲】，其余技能（牺牲之手、保护之手、拯救之手、圣盾术、圣佑术、圣疗术）默认关闭，供用户按需开启。
-- 2) 坦克/治疗核心减伤：默认开启。
-- 3) 团队战略/大抬血技能：按需可选。
RaidCD.SPELLS = {
    -- 圣骑士 (PALADIN)
    { id = 64205, name = "神圣牺牲", class = "PALADIN", cd = 120, category = "raid",     default = true,  icon = 236254, desc = "全团20%伤害转移，团本大减伤" },
    { id = 6940,  name = "牺牲之手", class = "PALADIN", cd = 120, category = "external", default = false, icon = 135966, desc = "单体转移30%伤害，交接保T" },
    { id = 10278, name = "保护之手", class = "PALADIN", cd = 300, category = "external", default = false, icon = 135964, desc = "物理免疫10秒，救法系/消物理Debuff" },
    { id = 1038,  name = "拯救之手", class = "PALADIN", cd = 120, category = "external", default = false, icon = 135967, desc = "降仇恨防OT，插雕文自身20%减伤" },
    { id = 642,   name = "圣盾术",   class = "PALADIN", cd = 300, category = "tank",     default = false, icon = 135896, desc = "完全无敌，消层/防猝死" },
    { id = 498,   name = "圣佑术",   class = "PALADIN", cd = 180, category = "tank",     default = false, icon = 135897, desc = "防骑50%大盾墙，硬抗BOSS大招" },
    { id = 48788, name = "圣疗术",   class = "PALADIN", cd = 1200,category = "external", default = false, icon = 135928, desc = "瞬间回满生命+护甲加成，救命大招" },

    -- 牧师 (PRIEST)
    { id = 33206, name = "痛苦压制", class = "PRIEST", cd = 180, category = "external", default = true,  icon = 135936, desc = "戒律牧40%单体高额减伤" },
    { id = 47788, name = "守护之魂", class = "PRIEST", cd = 180, category = "external", default = true,  icon = 237542, desc = "神牧翅膀，免死并回血50%" },
    { id = 64843, name = "神圣赞美诗", class = "PRIEST", cd = 480, category = "raid",   default = false, icon = 237540, desc = "全团持续高额抬血" },
    { id = 64901, name = "希望圣歌", class = "PRIEST", cd = 360, category = "raid",     default = false, icon = 237541, desc = "全团回蓝与提升法力上限" },

    -- 德鲁伊 (DRUID)
    { id = 22812, name = "树皮术",   class = "DRUID",  cd = 60,  category = "tank",     default = true,  icon = 136034, desc = "奶德/熊德自身20%减伤防打断" },
    { id = 61336, name = "生存本能", class = "DRUID",  cd = 180, category = "tank",     default = false, icon = 236169, desc = "熊坦自身保命，提升30%生命上限" },
    { id = 48477, name = "复生",     class = "DRUID",  cd = 600, category = "raid",     default = true,  icon = 136080, desc = "德鲁伊战斗中复活队友 (战复)" },
    { id = 48447, name = "宁静",     class = "DRUID",  cd = 600, category = "raid",     default = true,  icon = 136077, desc = "全团高频回血救急" },

    -- 战士 (WARRIOR)
    { id = 871,   name = "盾墙",     class = "WARRIOR", cd = 300, category = "tank",     default = true,  icon = 132362, desc = "防战核心大减伤 (60%减伤)" },
    { id = 12975, name = "破釜沉舟", class = "WARRIOR", cd = 180, category = "tank",     default = true,  icon = 132294, desc = "生命上限提升30%自救" },
    { id = 1282056, name = "集结呐喊", class = "WARRIOR", cd = 180, category = "raid",     default = false, icon = 538565, desc = "全团临时提升生命上限" },

    -- 死亡骑士 (DEATHKNIGHT)
    { id = 48792, name = "冰封之韧", class = "DEATHKNIGHT", cd = 120, category = "tank", default = true,  icon = 237527, desc = "DK大盾墙，50%减伤且免疫昏迷" },
    { id = 55233, name = "吸血鬼之血", class = "DEATHKNIGHT", cd = 60, category = "tank", default = true, icon = 136168, desc = "生命上限与受治疗效果提升" },
    { id = 48707, name = "反魔法护罩", class = "DEATHKNIGHT", cd = 45, category = "tank", default = true, icon = 136120, desc = "DK绿坝，大额吸收魔法伤害" },
    { id = 51052, name = "反魔法领域", class = "DEATHKNIGHT", cd = 120, category = "raid", default = true, icon = 237510, desc = "大罩子，全团范围魔法减伤" },
    { id = 48982, name = "符文分流", class = "DEATHKNIGHT", cd = 60, category = "tank", default = false, icon = 237530, desc = "鲜血分流自回血" },
    { id = 42650, name = "亡者大军", class = "DEATHKNIGHT", cd = 600, category = "raid", default = false, icon = 237511, desc = "大军嘲讽控场与引导免伤" },

    -- 萨满祭司 (SHAMAN)
    { id = 2825,  name = "嗜血",     class = "SHAMAN", cd = 300, category = "raid",     default = true,  icon = 136012, desc = "部落核心爆发急速提升" },
    { id = 32182, name = "英勇",     class = "SHAMAN", cd = 300, category = "raid",     default = true,  icon = 135963, desc = "联盟核心爆发急速提升" },
    { id = 16190, name = "法力之潮图腾", class = "SHAMAN", cd = 300, category = "raid", default = true,  icon = 135861, desc = "全团法力值大回蓝图腾" },
}

-- 建立索引加速查询
RaidCD.spellByName = {}
RaidCD.spellById = {}
for _, def in ipairs(RaidCD.SPELLS) do
    local sName, _, sIcon = GetSpellInfo(def.id)
    if sName and sName ~= "" then
        def.name = sName
    end
    if sIcon then
        def.icon = sIcon
    end
    RaidCD.spellById[def.id] = def
    RaidCD.spellByName[def.name] = def
end

-- 默认自动勾选人员的职业白名单 (萨满不默认监控，由用户按需在网格中手动勾选)
local DEFAULT_MONITORED_CLASSES = {
    PALADIN = true,
    PRIEST = true,
    DRUID = true,
    WARRIOR = true,
    DEATHKNIGHT = true,
}

local function CleanPlayerName(name)
    if not name then return "" end
    return (name:gsub("%-.+", ""))
end
RaidCD.CleanPlayerName = CleanPlayerName

local function IsSpellFactionMatch(spellId)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if spellId == 2825 then
        -- 嗜血 (Bloodlust) -> 仅部落萨满有效
        return faction ~= "Alliance"
    elseif spellId == 32182 then
        -- 英勇 (Heroism) -> 仅联盟萨满有效
        return faction == "Alliance"
    end
    return true
end
RaidCD.IsSpellFactionMatch = IsSpellFactionMatch

local function GetSpellHyperlink(spellId, fallbackName)
    local link = GetSpellLink(spellId)
    if link and link ~= "" then return link end
    local name = fallbackName
    if not name or name == "" then
        name = GetSpellInfo(spellId) or ("Spell:" .. spellId)
    end
    return format("|cff71d5ff|Hspell:%d|h[%s]|h|r", spellId, name)
end
RaidCD.GetSpellHyperlink = GetSpellHyperlink

--------------------------------------------------------------------------------
-- 2. 数据库与配置项初始化
--------------------------------------------------------------------------------
function ns.InitRaidCDDB()
    BiaoGe = BiaoGe or {}
    BiaoGe.RaidCD = BiaoGe.RaidCD or {}
    local db = BiaoGe.RaidCD

    if db.enabledSpells == nil then db.enabledSpells = {} end
    for _, def in ipairs(RaidCD.SPELLS) do
        if db.enabledSpells[def.id] == nil then
            db.enabledSpells[def.id] = def.default
        end
    end

    -- 确保萨满核心技能默认可用
    if db.shamanInited == nil then
        db.shamanInited = true
        db.enabledSpells[2825] = true
        db.enabledSpells[32182] = true
        db.enabledSpells[16190] = true
    end

    if db.monitoredPlayers == nil then db.monitoredPlayers = {} end
    if db.showHUD == nil then db.showHUD = true end
    if db.hudLocked == nil then db.hudLocked = false end
    if db.onlyInCombat == nil then db.onlyInCombat = false end
    if db.onlyInGroup == nil then db.onlyInGroup = false end
    if db.hudScale == nil then db.hudScale = 1.0 end
    if db.hudLayout == nil then db.hudLayout = 1 end
    if db.frameStrata == nil then db.frameStrata = "MEDIUM" end
    if db.hudPoint == nil then
        db.hudPoint = { "CENTER", "UIParent", "CENTER", 260, 60 }
    end
    if db.sortMode == nil then db.sortMode = "subgroup" end
    if db.customPlayerOrder == nil then db.customPlayerOrder = {} end

    -- 一次性安全自愈迁移：让更新插件的老用户默认开启技能监控且默认单列布局
    if BG and BG.Once then
        BG.Once("RaidCD_DefaultEnableHUD_SingleCol", 26092902, function()
            db.showHUD = true
            db.onlyInGroup = false
            db.hudLayout = 1
        end)
    end
end

function RaidCD.IsSpellEnabled(spellId)
    local db = BiaoGe and BiaoGe.RaidCD
    if db and db.enabledSpells and db.enabledSpells[spellId] ~= nil then
        return db.enabledSpells[spellId]
    end
    local def = RaidCD.spellById[spellId]
    return def and def.default or false
end

function RaidCD.SetSpellEnabled(spellId, enabled)
    local db = BiaoGe and BiaoGe.RaidCD
    if db then
        db.enabledSpells = db.enabledSpells or {}
        db.enabledSpells[spellId] = enabled and true or false
    end
    RaidCD.UpdateHUD()
    RaidCD.UpdatePanelUI()
end

function RaidCD.IsPlayerMonitored(name, class)
    if not name or name == "" then return false end
    local clean = CleanPlayerName(name)
    local db = BiaoGe and BiaoGe.RaidCD
    if db and db.monitoredPlayers and db.monitoredPlayers[clean] ~= nil then
        return db.monitoredPlayers[clean]
    end
    if not class and UnitName(clean) then
        class = select(2, UnitClass(clean))
    end
    if class and DEFAULT_MONITORED_CLASSES[class] then
        return true
    end
    return false
end

function RaidCD.SetPlayerMonitored(name, enabled)
    if not name or name == "" then return end
    local clean = CleanPlayerName(name)
    local db = BiaoGe and BiaoGe.RaidCD
    if db then
        db.monitoredPlayers = db.monitoredPlayers or {}
        db.monitoredPlayers[clean] = enabled and true or false
    end
    RaidCD.UpdateHUD()
    RaidCD.UpdatePanelUI()
end

function RaidCD.ResetAllPlayersToDefault()
    local db = BiaoGe and BiaoGe.RaidCD
    if db then
        wipe(db.monitoredPlayers)
    end
    RaidCD.UpdateHUD()
    RaidCD.UpdatePanelUI()
    if ns.RaidTool and ns.RaidTool.UpdateAllSlotVisuals then
        ns.RaidTool.UpdateAllSlotVisuals()
    end
end

--------------------------------------------------------------------------------
-- 3. 实时冷却跟踪核心引擎 (Combat Log Engine)
--------------------------------------------------------------------------------
-- activeCDs: [cleanName][spellId] = { startTime, duration, endTime }
RaidCD.activeCDs = {}

function RaidCD.StartCooldown(cleanName, spellId, duration)
    if not cleanName or not spellId or not duration then return end
    RaidCD.activeCDs[cleanName] = RaidCD.activeCDs[cleanName] or {}
    local now = GetTime()
    RaidCD.activeCDs[cleanName][spellId] = {
        startTime = now,
        duration = duration,
        endTime = now + duration,
    }
    RaidCD.UpdateHUD()
    RaidCD.UpdatePanelUI()
end

function RaidCD.GetCooldownRemaining(cleanName, spellId)
    local pCDs = RaidCD.activeCDs[cleanName]
    if not pCDs then return 0 end
    local info = pCDs[spellId]
    if not info then return 0 end
    local remaining = info.endTime - GetTime()
    if remaining <= 0 then
        pCDs[spellId] = nil
        return 0
    end
    return remaining
end

-- 获取角色职业
function RaidCD.GetPlayerClass(name)
    if not name or name == "" then return nil end
    local clean = CleanPlayerName(name)
    if UnitName(clean) then
        return select(2, UnitClass(clean))
    end
    if ns.RaidTool and ns.RaidTool.currentRosterList and ns.RaidTool.currentRosterClasses then
        for i, rName in pairs(ns.RaidTool.currentRosterList) do
            if rName and CleanPlayerName(rName) == clean then
                return ns.RaidTool.currentRosterClasses[i]
            end
        end
    end
    return nil
end

-- 判断角色是否真实处于当前小队/团队中 (权威退队识别)
local function IsPlayerInCurrentGroup(name)
    if not name or name == "" then return false end
    local clean = CleanPlayerName(name)
    local pName = CleanPlayerName(UnitName("player") or "")
    if clean == pName then return true end

    if IsInRaid and IsInRaid() then
        local count = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers())
            or 40
        for i = 1, count do
            local rName = GetRaidRosterInfo(i) or UnitName("raid" .. i)
            if rName and CleanPlayerName(rName) == clean then
                return true
            end
        end
        return false
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local partName = UnitName("party" .. i)
            if partName and CleanPlayerName(partName) == clean then
                return true
            end
        end
        return false
    end
    return clean == pName
end
RaidCD.IsPlayerInCurrentGroup = IsPlayerInCurrentGroup

-- 获取队员在团队/队伍中的天然小队排序权重 (小队 1~8 队，坦克自然在第一队)
local function GetPlayerRosterSortOrder(name, unit, rosterSlot)
    if not name or name == "" then return 999 end

    -- 1. 团队环境 (IsInRaid): 通过 GetRaidRosterInfo 精准获取小队编号 (subgroup 1~8)
    if IsInRaid and IsInRaid() then
        local numMembers = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers())
            or 40
        for i = 1, numMembers do
            local rName, _, subgroup = GetRaidRosterInfo(i)
            if rName and CleanPlayerName(rName) == name then
                subgroup = subgroup or 1
                return subgroup * 100 + i
            end
        end
    end

    -- 2. 团队工具 40 人网格槽位 (rosterSlot: 1~40)
    -- 槽位 1~5 为第 1 队(坦克组)，6~10 为第 2 队，11~15 为第 3 队...
    if rosterSlot and type(rosterSlot) == "number" and rosterSlot > 0 then
        local sub = math.floor((rosterSlot - 1) / 5) + 1
        return sub * 100 + rosterSlot
    end

    -- 检查是否能从团队工具当前阵容列表找到槽位
    local rosterList = (ns.RaidTool and ns.RaidTool.currentRosterList) or (RaidTool and RaidTool.currentRosterList)
    if rosterList then
        for slot = 1, 40 do
            local rName = rosterList[slot]
            if rName and CleanPlayerName(rName) == name then
                local sub = math.floor((slot - 1) / 5) + 1
                return sub * 100 + slot
            end
        end
    end

    -- 3. 5 人小队环境 (Party): player 与 party1~party4
    if unit then
        if unit == "player" then
            return 101
        elseif unit:find("party(%d+)") then
            local pIndex = tonumber(unit:match("party(%d+)")) or 1
            return 101 + pIndex
        elseif unit:find("raid(%d+)") then
            local rIndex = tonumber(unit:match("raid(%d+)")) or 1
            return 200 + rIndex
        end
    end

    return 999
end
RaidCD.GetPlayerRosterSortOrder = GetPlayerRosterSortOrder

-- 获取当前队伍/团队所有队员列表 (供人员选择面板与排序使用)
function RaidCD.GetAllRosterPlayers()
    local players = {}
    local seen = {}

    -- 1. 扫描在线真实单位 (小队/团队)
    local checkUnits = {}
    local isRaid = IsInRaid and IsInRaid()
    if isRaid then
        local maxRaid = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers())
            or 40
        for i = 1, maxRaid do
            tinsert(checkUnits, "raid" .. i)
        end
    else
        tinsert(checkUnits, "player")
        for i = 1, 4 do
            tinsert(checkUnits, "party" .. i)
        end
    end

    for _, u in ipairs(checkUnits) do
        if UnitExists(u) then
            local uName = UnitName(u)
            if uName and uName ~= "" then
                local clean = CleanPlayerName(uName)
                if not seen[clean] then
                    seen[clean] = true
                    local class = select(2, UnitClass(u))
                    local sortOrder = RaidCD.GetPlayerRosterSortOrder(clean, u, nil)
                    local sub = math.floor((sortOrder or 100) / 100)
                    if sub < 1 or sub > 8 then sub = 1 end
                    tinsert(players, {
                        name = clean,
                        class = class,
                        unit = u,
                        subgroup = sub,
                        sortOrder = sortOrder,
                        isMonitored = RaidCD.IsPlayerMonitored(clean, class),
                    })
                end
            end
        end
    end

    -- 2. 扫描团队工具 40 人网格槽位
    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
    local rosterList = (ns.RaidTool and ns.RaidTool.currentRosterList) or (RaidTool and RaidTool.currentRosterList) or {}
    local rosterClasses = (ns.RaidTool and ns.RaidTool.currentRosterClasses) or (RaidTool and RaidTool.currentRosterClasses) or {}
    for slot = 1, 40 do
        local rawName = rosterList[slot]
        if rawName and rawName ~= "" then
            local clean = CleanPlayerName(rawName)
            if not seen[clean] and (not inGroup or IsPlayerInCurrentGroup(clean)) then
                seen[clean] = true
                local class = rosterClasses[slot] or RaidCD.GetPlayerClass(clean)
                local sortOrder = RaidCD.GetPlayerRosterSortOrder(clean, nil, slot)
                local sub = math.floor((slot - 1) / 5) + 1
                tinsert(players, {
                    name = clean,
                    class = class,
                    rosterSlot = slot,
                    subgroup = sub,
                    sortOrder = sortOrder,
                    isMonitored = RaidCD.IsPlayerMonitored(clean, class),
                })
            end
        end
    end

    table.sort(players, function(a, b)
        return (a.sortOrder or 999) < (b.sortOrder or 999)
    end)

    return players
end

-- 手动调整队员自定义排序 (置顶 / 上移 / 下移)
function RaidCD.MovePlayerCustomOrder(name, direction)
    if not name or name == "" then return end
    local clean = CleanPlayerName(name)
    local db = BiaoGe and BiaoGe.RaidCD
    if not db then return end

    db.sortMode = "custom"
    db.customPlayerOrder = db.customPlayerOrder or {}

    local currentList = RaidCD.GetMonitoredRosterCooldowns()
    local names = {}
    local targetIndex = nil
    for i, p in ipairs(currentList) do
        table.insert(names, p.name)
        if p.name == clean then
            targetIndex = i
        end
    end

    if not targetIndex then return end

    if direction == "top" then
        if targetIndex > 1 then
            table.remove(names, targetIndex)
            table.insert(names, 1, clean)
        end
    elseif direction == "up" then
        if targetIndex > 1 then
            local temp = names[targetIndex - 1]
            names[targetIndex - 1] = names[targetIndex]
            names[targetIndex] = temp
        end
    elseif direction == "down" then
        if targetIndex < #names then
            local temp = names[targetIndex + 1]
            names[targetIndex + 1] = names[targetIndex]
            names[targetIndex] = temp
        end
    end

    wipe(db.customPlayerOrder)
    for i, n in ipairs(names) do
        db.customPlayerOrder[n] = i
    end

    RaidCD.UpdateHUD()
    if RaidCD.playerModal and RaidCD.playerModal:IsShown() then
        RaidCD.RefreshPlayerModalUI()
    end
end

-- 获取当前团队/队伍中所有合法的受监控成员及可用技能列表 (严格按照小队顺序排列，第1队坦克自然在最前面)
function RaidCD.GetMonitoredRosterCooldowns()
    local result = {}
    local seen = {}
    local myFaction = (UnitFactionGroup and UnitFactionGroup("player")) or "Horde"

    -- 1. 优先扫描真实在线的队伍/团队成员 (无论5人小队还是40人团队直接读游戏内Unit，最实时可靠)
    local checkUnits = {}
    local isRaid = IsInRaid and IsInRaid()
    if isRaid then
        local maxRaid = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers())
            or 40
        for i = 1, maxRaid do
            tinsert(checkUnits, "raid" .. i)
        end
    else
        tinsert(checkUnits, "player")
        for i = 1, 4 do
            tinsert(checkUnits, "party" .. i)
        end
    end

    for _, u in ipairs(checkUnits) do
        if UnitExists(u) then
            local uName = UnitName(u)
            if uName and uName ~= "" then
                local clean = CleanPlayerName(uName)
                if not seen[clean] then
                    seen[clean] = true
                    local class = select(2, UnitClass(u))
                    if RaidCD.IsPlayerMonitored(clean, class) then
                        local spells = {}
                        for _, def in ipairs(RaidCD.SPELLS) do
                            if IsSpellFactionMatch(def.id) and (not class or def.class == class) and RaidCD.IsSpellEnabled(def.id) then
                                local rem = RaidCD.GetCooldownRemaining(clean, def.id)
                                tinsert(spells, {
                                    def = def,
                                    remaining = rem,
                                    isReady = (rem <= 0),
                                })
                            end
                        end
                        if #spells > 0 then
                            local sortOrder = GetPlayerRosterSortOrder(clean, u, nil)
                            tinsert(result, {
                                name = clean,
                                class = class,
                                spells = spells,
                                sortOrder = sortOrder,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 2. 若玩家当前不在队伍中或团队工具中有预设阵容，补充扫描 40 人网格中尚未收录的成员
    local rosterList = (ns.RaidTool and ns.RaidTool.currentRosterList) or (RaidTool and RaidTool.currentRosterList) or {}
    for idx = 1, 40 do
        local rawName = rosterList[idx]
        if rawName and rawName ~= "" then
            local clean = CleanPlayerName(rawName)
            if not seen[clean] then
                seen[clean] = true
                local class = (ns.RaidTool and ns.RaidTool.currentRosterClasses and ns.RaidTool.currentRosterClasses[idx])
                    or (RaidTool and RaidTool.currentRosterClasses and RaidTool.currentRosterClasses[idx])
                    or RaidCD.GetPlayerClass(clean)
                if RaidCD.IsPlayerMonitored(clean, class) then
                    local spells = {}
                    for _, def in ipairs(RaidCD.SPELLS) do
                        if IsSpellFactionMatch(def.id) and (not class or def.class == class) and RaidCD.IsSpellEnabled(def.id) then
                            local rem = RaidCD.GetCooldownRemaining(clean, def.id)
                            tinsert(spells, {
                                def = def,
                                remaining = rem,
                                isReady = (rem <= 0),
                            })
                        end
                    end
                    if #spells > 0 then
                        local sortOrder = GetPlayerRosterSortOrder(clean, nil, idx)
                        tinsert(result, {
                            name = clean,
                            class = class,
                            spells = spells,
                            sortOrder = sortOrder,
                        })
                    end
                end
            end
        end
    end

    -- 3. 核心排序规则：严格按照小队与队伍槽位顺序从小到大排列 (1队坦克组必然排在最前面，后续小队依次展开)
    table.sort(result, function(a, b)
        local sortMode = (BiaoGe and BiaoGe.RaidCD and BiaoGe.RaidCD.sortMode) or "subgroup"
        local customOrder = (BiaoGe and BiaoGe.RaidCD and BiaoGe.RaidCD.customPlayerOrder) or {}
        local CLASS_PRIO = {
            WARRIOR = 1,
            PALADIN = 2,
            DEATHKNIGHT = 3,
            DRUID = 4,
            PRIEST = 5,
            SHAMAN = 6,
            HUNTER = 7,
            ROGUE = 8,
            MAGE = 9,
            WARLOCK = 10,
        }

        if sortMode == "custom" then
            local pA = customOrder[a.name] or (1000 + (a.sortOrder or 999))
            local pB = customOrder[b.name] or (1000 + (b.sortOrder or 999))
            if pA ~= pB then return pA < pB end
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        elseif sortMode == "class" then
            local cA = CLASS_PRIO[a.class] or 99
            local cB = CLASS_PRIO[b.class] or 99
            if cA ~= cB then return cA < cB end
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        elseif sortMode == "ready" then
            local rA = 0
            for _, s in ipairs(a.spells or {}) do if s.isReady then rA = rA + 1 end end
            local rB = 0
            for _, s in ipairs(b.spells or {}) do if s.isReady then rB = rB + 1 end end
            if rA ~= rB then return rA > rB end
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        elseif sortMode == "name" then
            if a.name ~= b.name then return (a.name or "") < (b.name or "") end
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        else
            -- 默认 subgroup 小队顺序 (1队到8队，1队坦克自然在最前面)
            return (a.sortOrder or 999) < (b.sortOrder or 999)
        end
    end)

    return result
end

--------------------------------------------------------------------------------
-- 4. 事件监听框架 (Combat Log & Roster Listener)
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "BG_RaidCDEventFrame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
if pcall then
    pcall(function() eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE") end)
    pcall(function() eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED") end)
    pcall(function() eventFrame:RegisterEvent("RAID_ROSTER_UPDATE") end)
    pcall(function() eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") end)
    pcall(function() eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end)
    pcall(function() eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD") end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()

        if subEvent == "SPELL_CAST_SUCCESS" and sourceName then
            local def = RaidCD.spellById[spellId] or RaidCD.spellByName[spellName]
            if def and RaidCD.IsSpellEnabled(def.id) then
                local cleanCaster = CleanPlayerName(sourceName)
                local class = RaidCD.GetPlayerClass(cleanCaster)
                if RaidCD.IsPlayerMonitored(cleanCaster, class) then
                    RaidCD.StartCooldown(cleanCaster, def.id, def.cd)
                end
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if RaidTool and RaidTool.SyncCurrentRaidRoster then
            pcall(function() RaidTool.SyncCurrentRaidRoster(false) end)
        end
        RaidCD.UpdateHUD()
        RaidCD.UpdatePanelUI()
        if RaidCD.RefreshPlayerModalUI then
            RaidCD.RefreshPlayerModalUI()
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        RaidCD.CheckCombatVisibility()
    end
end)

--------------------------------------------------------------------------------
-- 5. 屏幕独立悬浮条 (Floating HUD Bar)
--------------------------------------------------------------------------------
-- 格式化 CD 倒计时秒数
local function FormatRemainingTime(seconds)
    if not seconds or seconds <= 0 then return "就绪" end
    if seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return format("%d:%02d", m, s)
    else
        return format("%ds", math.ceil(seconds))
    end
end
RaidCD.FormatRemainingTime = FormatRemainingTime

local function CreateDropDownSeparator()
    return {
        text = " ",
        hasArrow = false,
        dist = 0,
        isTitle = true,
        isUninteractable = true,
        notCheckable = true,
        iconOnly = true,
        icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
        tCoordLeft = 0,
        tCoordRight = 1,
        tCoordTop = 0,
        tCoordBottom = 1,
        tSizeX = 0,
        tSizeY = 8,
        tFitDropDownSizeX = true,
        iconInfo = {
            tCoordLeft = 0,
            tCoordRight = 1,
            tCoordTop = 0,
            tCoordBottom = 1,
            tSizeX = 0,
            tSizeY = 8,
            tFitDropDownSizeX = true,
        },
    }
end

local function CloseDropDownMenusSafe()
    if LibBG and LibBG.CloseDropDownMenus then
        LibBG:CloseDropDownMenus()
    elseif CloseDropDownMenus then
        CloseDropDownMenus()
    end
end

-- 直达团队工具大面板并切换至技能监控子页签
function RaidCD.OpenRaidTool()
    if BG and BG.MainFrame then
        BG.MainFrame:Show()
    end
    local tabNum = (BG and BG.RaidToolMainFrameTabNum) or 22
    if BG and BG.ClickTabButton then
        BG.ClickTabButton(tabNum)
    end
    if ns.RaidTool and ns.RaidTool.SwitchToRaidCDTab then
        ns.RaidTool.SwitchToRaidCDTab()
    end
    BG.PlaySound(1)
end

-- 弹出右键配置菜单 (参考团队监控原生交互)
function RaidCD.OpenHUDMenu(anchorFrame)
    local db = BiaoGe and BiaoGe.RaidCD
    if not db then return end

    local frameStrataOptions = {
        { value = "BACKGROUND", text = "BACKGROUND" },
        { value = "LOW", text = "LOW" },
        { value = "MEDIUM", text = "MEDIUM" },
        { value = "HIGH", text = "HIGH" },
        { value = "DIALOG", text = "DIALOG" },
    }
    local frameStrataMenu = {}
    for _, opt in ipairs(frameStrataOptions) do
        table.insert(frameStrataMenu, {
            text = opt.text,
            checked = function()
                return db.frameStrata == opt.value
            end,
            func = function()
                db.frameStrata = opt.value
                if RaidCD.hudFrame then
                    RaidCD.hudFrame:SetFrameStrata(opt.value)
                end
                CloseDropDownMenusSafe()
            end,
        })
    end

    local frameScaleOptions = { 80, 85, 90, 95, 100, 105, 110, 115, 120 }
    local frameScaleMenu = {}
    for _, percent in ipairs(frameScaleOptions) do
        local scale = percent / 100
        table.insert(frameScaleMenu, {
            text = format("%d%%", percent),
            checked = function()
                return math.abs((db.hudScale or 1.0) - scale) < 0.01
            end,
            func = function()
                db.hudScale = scale
                if RaidCD.hudFrame then
                    RaidCD.hudFrame:SetScale(scale)
                end
                CloseDropDownMenusSafe()
            end,
        })
    end

    local sortModeOptions = {
        { value = "subgroup", text = "小队顺序 (1队到8队，默认)" },
        { value = "class",    text = "职业分类 (战/骑/DK/德/牧/萨)" },
        { value = "ready",    text = "就绪优先 (可用大招置顶)" },
        { value = "name",     text = "名称排序 (字母A-Z)" },
        { value = "custom",   text = "自定义排序 (手动设定)" },
    }
    local sortOrderMenu = {}
    for _, opt in ipairs(sortModeOptions) do
        table.insert(sortOrderMenu, {
            text = opt.text,
            checked = function()
                local cur = db.sortMode or "subgroup"
                return cur == opt.value
            end,
            func = function()
                db.sortMode = opt.value
                RaidCD.UpdateHUD()
                CloseDropDownMenusSafe()
            end,
        })
    end
    table.insert(sortOrderMenu, CreateDropDownSeparator())
    table.insert(sortOrderMenu, {
        text = "自定义调整排序顺序...",
        notCheckable = true,
        func = function()
            RaidCD.TogglePlayerSelectModal("sort")
            CloseDropDownMenusSafe()
        end,
    })

    local menu = {}

    -- 如果右键点击的是具体的队员条目，置入快捷人员排序与操作项
    if anchorFrame and anchorFrame.pName then
        local pName = anchorFrame.pName
        local pClass = anchorFrame.pClass
        local cCode = "|cffffffff"
        if pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass] then
            cCode = RAID_CLASS_COLORS[pClass].colorStr and ("|c" .. RAID_CLASS_COLORS[pClass].colorStr) or cCode
        end
        table.insert(menu, {
            text = format("%s%s|r 快捷操作", cCode, pName),
            isTitle = true,
            notCheckable = true,
        })
        table.insert(menu, {
            text = "置顶该队员",
            notCheckable = true,
            func = function()
                RaidCD.MovePlayerCustomOrder(pName, "top")
                CloseDropDownMenusSafe()
            end,
        })
        table.insert(menu, {
            text = "上移一位",
            notCheckable = true,
            func = function()
                RaidCD.MovePlayerCustomOrder(pName, "up")
                CloseDropDownMenusSafe()
            end,
        })
        table.insert(menu, {
            text = "下移一位",
            notCheckable = true,
            func = function()
                RaidCD.MovePlayerCustomOrder(pName, "down")
                CloseDropDownMenusSafe()
            end,
        })
        table.insert(menu, {
            text = "取消监控该队员",
            notCheckable = true,
            func = function()
                RaidCD.SetPlayerMonitored(pName, false)
                CloseDropDownMenusSafe()
            end,
        })
        table.insert(menu, CreateDropDownSeparator())
    end

    table.insert(menu, {
        text = BG.STC_g1("团队减伤常驻监控") or "|cffffd100团队减伤常驻监控|r",
        isTitle = true,
        notCheckable = true,
    })
    table.insert(menu, {
        text = db.hudLocked and "解锁界面" or "锁定界面",
        notCheckable = true,
        func = function()
            db.hudLocked = not db.hudLocked
            RaidCD.UpdateHUD()
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "隐藏界面",
        notCheckable = true,
        func = function()
            db.showHUD = false
            if RaidCD.hudFrame then RaidCD.hudFrame:Hide() end
            if RaidCD.cbShowHUD then RaidCD.cbShowHUD:SetChecked(false) end
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 技能监控]|r 悬浮条已隐藏。如需再次开启，可在【团队工具】顶部勾选「开启 技能监控」。")
            end
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, CreateDropDownSeparator())

    -- 用户指定新增选项：选择人员，调整排序
    table.insert(menu, {
        text = "选择人员",
        notCheckable = true,
        func = function()
            RaidCD.TogglePlayerSelectModal("select")
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "调整排序",
        hasArrow = true,
        notCheckable = true,
        menuList = sortOrderMenu,
    })
    table.insert(menu, {
        text = "技能过滤",
        notCheckable = true,
        func = function()
            RaidCD.ToggleConfigModal()
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "重置技能冷却记录",
        notCheckable = true,
        func = function()
            RaidCD.cooldowns = {}
            RaidCD.UpdateHUD()
            RaidCD.UpdatePanelUI()
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("|cff00ff00[BGLite] 团队技能监控：已重置所有技能冷却记录|r", 0, 1, 0)
            end
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "框架层级",
        hasArrow = true,
        notCheckable = true,
        menuList = frameStrataMenu,
    })
    table.insert(menu, {
        text = "界面缩放",
        hasArrow = true,
        notCheckable = true,
        menuList = frameScaleMenu,
    })
    table.insert(menu, CreateDropDownSeparator())
    table.insert(menu, {
        text = BG.STC_g1("布局") or "|cffffd100布局|r",
        isTitle = true,
        notCheckable = true,
    })
    table.insert(menu, {
        text = "单列布局",
        checked = function() return db.hudLayout == 1 end,
        func = function()
            db.hudLayout = 1
            RaidCD.UpdateHUD()
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "双列布局",
        checked = function() return db.hudLayout == 2 end,
        func = function()
            db.hudLayout = 2
            RaidCD.UpdateHUD()
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, {
        text = "单行布局",
        checked = function() return db.hudLayout == 3 end,
        func = function()
            db.hudLayout = 3
            RaidCD.UpdateHUD()
            CloseDropDownMenusSafe()
        end,
    })
    table.insert(menu, CreateDropDownSeparator())
    table.insert(menu, {
        text = CANCEL or "取消",
        notCheckable = true,
        func = function()
            CloseDropDownMenusSafe()
        end,
    })

    local dropDown = RaidCD.dropDownFrame
    if not dropDown then
        dropDown = CreateFrame("Frame", "BG_RaidCD_HUDDropDown", UIParent, "UIDropDownMenuTemplate")
        RaidCD.dropDownFrame = dropDown
    end

    if LibBG and LibBG.EasyMenu then
        LibBG:EasyMenu(menu, dropDown, "cursor", 0, 0, "MENU", 2)
    elseif EasyMenu then
        EasyMenu(menu, dropDown, "cursor", 0, 0, "MENU", 2)
    end
end
--------------------------------------------------------------------------------
-- 5.5 悬浮条单元格与按键池 (HUD Cells & Button Pools)
--------------------------------------------------------------------------------
-- 技能小图标按钮 (Spell Button)
local function GetOrCreateSpellButton(row, sIdx)
    local btn = row.spellButtons[sIdx]
    if btn then return btn end

    btn = CreateFrame("Button", nil, row)
    btn:SetSize(18, 18)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local border = btn:CreateLine()
    border:SetThickness(1)
    btn.border = border

    local textCD = btn:CreateFontString(nil, "OVERLAY")
    textCD:SetFont(BIAOGE_TEXT_FONT, 9, "OUTLINE")
    textCD:SetPoint("CENTER", 0, 0)
    btn.textCD = textCD

    btn:SetScript("OnClick", function(self)
        if not self.sDef or not self.pName then return end
        if IsModifiedClick("CHATLINK") then
            local link = RaidCD.GetSpellHyperlink(self.sDef.id, self.sDef.name)
            if link and ChatEdit_InsertLink then
                ChatEdit_InsertLink(link)
            end
        else
            local rem = RaidCD.GetCooldownRemaining(self.pName, self.sDef.id)
            local statusStr = (rem > 0) and ("冷却剩余: " .. RaidCD.FormatRemainingTime(rem)) or "已就绪"
            local msg = format("[BGLite 技能监控] %s 的 %s %s", self.pName, self.sDef.name, statusStr)
            local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "EMOTE")
            if channel == "EMOTE" then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. msg .. "|r")
            else
                SendChatMessage(msg, channel)
            end
            BG.PlaySound(1)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if row.highlight then row.highlight:Show() end
        if not self.sDef or not self.pName then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.sDef.id)
        else
            local link = GetSpellLink(self.sDef.id)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetHyperlink("spell:" .. self.sDef.id)
            end
        end
        local rem = RaidCD.GetCooldownRemaining(self.pName, self.sDef.id)
        GameTooltip:AddLine(" ")
        if self.sDef.desc then
            GameTooltip:AddLine(BG.STC_dis("定位说明: " .. self.sDef.desc))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BG.STC_b1("点击通报状态 | Shift+点击发超链接"), 0.4, 0.8, 1)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        if row.highlight then row.highlight:Hide() end
        GameTooltip_Hide()
    end)

    row.spellButtons[sIdx] = btn
    return btn
end

-- 队员条目 (Player Row)
local function GetOrCreateRow(hud, index)
    local row = hud.rowFrames[index]
    if row then return row end

    row = CreateFrame("Frame", nil, hud)
    row:SetHeight(22)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
    row.bg = bg

    local highlight = row:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.12)
    highlight:Hide()
    row.highlight = highlight

    -- 姓名
    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
    nameText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    row.spellButtons = {}

    row:SetScript("OnMouseDown", function(self, button)
        local locked = BiaoGe and BiaoGe.RaidCD and BiaoGe.RaidCD.hudLocked
        if button == "LeftButton" and (not locked or IsShiftKeyDown()) then
            self.isDraggingHUD = true
            CloseDropDownMenusSafe()
            hud.isMoving = true
            hud:StartMoving()
        end
    end)

    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if self.isDraggingHUD then
                self.isDraggingHUD = nil
                hud.isMoving = nil
                hud:StopMovingOrSizing()
                local point, _, relativePoint, x, y = hud:GetPoint(1)
                if BiaoGe and BiaoGe.RaidCD then
                    BiaoGe.RaidCD.hudPoint = { point, "UIParent", relativePoint, math.floor(x), math.floor(y) }
                end
            end
        elseif button == "RightButton" then
            RaidCD.OpenHUDMenu(self)
        end
    end)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)

    hud.rowFrames[index] = row
    return row
end

--------------------------------------------------------------------------------
-- 5.3 一键通报技能状态 (Broadcast Cooldown Status)
--------------------------------------------------------------------------------
function RaidCD.BroadcastCooldownStatus()
    local rosterData = RaidCD.GetMonitoredRosterCooldowns()
    if not rosterData or #rosterData == 0 then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 技能监控]|r 当前暂无受监控的团队队员（可右键悬浮条选择人员）。")
        end
        return
    end

    local cdList = {}     -- 处于冷却中的技能列表
    local readyCount = 0  -- 已就绪的技能数
    local totalSpells = 0 -- 监控技能总数

    for _, pData in ipairs(rosterData) do
        for _, sInfo in ipairs(pData.spells) do
            totalSpells = totalSpells + 1
            local rem = sInfo.remaining or RaidCD.GetCooldownRemaining(pData.name, sInfo.def.id)
            if rem and rem > 0 then
                tinsert(cdList, {
                    name = pData.name,
                    class = pData.class,
                    spellName = sInfo.def.name,
                    remaining = rem,
                    remStr = FormatRemainingTime(rem),
                })
            else
                readyCount = readyCount + 1
            end
        end
    end

    if totalSpells == 0 then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 技能监控]|r 当前没有勾选任何需要监控的技能（可点击上方【技能配置】进行选择）。")
        end
        return
    end

    local channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    local lines = {}

    -- 模式1：存在冷却中的技能 -> 播报倒计时列表
    if #cdList > 0 then
        tinsert(lines, format("【BGLite 团队技能监控】当前有 %d 项技能冷却中 (已就绪: %d 项):", #cdList, readyCount))

        local currentLine = ""
        local itemCount = 0
        for _, it in ipairs(cdList) do
            local itemStr = format("%s-%s(%s)", it.name, it.spellName, it.remStr)
            if currentLine == "" then
                currentLine = "> " .. itemStr
            else
                currentLine = currentLine .. " | " .. itemStr
            end
            itemCount = itemCount + 1

            -- 每 3 个条目或字符长度超限时换行，保证公屏展示美观且不超长
            if itemCount >= 3 or strlen(currentLine) > 130 then
                tinsert(lines, currentLine)
                currentLine = ""
                itemCount = 0
            end
        end
        if currentLine ~= "" then
            tinsert(lines, currentLine)
        end
    else
        -- 模式2：反之全部就绪 -> 播报全部就绪！
        tinsert(lines, format("【BGLite 团队技能监控】全团 %d 项受监控关键大招全部准备就绪！", totalSpells))
    end

    -- 消息分发与安全延时发送
    if channel then
        for i, line in ipairs(lines) do
            C_Timer.After((i - 1) * 0.35, function()
                SendChatMessage(line, channel)
            end)
        end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite PLUS]|r 已成功将技能状态通报至 [" .. (channel == "RAID" and "团队" or "小队") .. "] 频道！")
        end
    else
        -- 单人未组队状态下本地预览输出
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite PLUS 技能状态本地通报]|r (当前不在队伍中，仅本地预览):")
            for _, line in ipairs(lines) do
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00" .. line .. "|r")
            end
        end
    end
    BG.PlaySound(1)
end

function RaidCD.CreateHUD()
    if RaidCD.hudFrame then return RaidCD.hudFrame end

    local db = BiaoGe and BiaoGe.RaidCD

    local hud = CreateFrame("Frame", "BG_RaidCDHUDFrame", UIParent, "BackdropTemplate")
    hud:SetSize(240, 60)
    hud:SetScale(db and db.hudScale or 1.0)
    hud:SetFrameStrata(db and db.frameStrata or "MEDIUM")
    hud:SetClampedToScreen(true)
    hud:EnableMouse(true)
    hud:SetMovable(true)

    hud:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    hud:SetBackdropColor(0.02, 0.02, 0.02, 0.85)
    hud:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

    -- 恢复保存坐标
    if db and db.hudPoint then
        hud:ClearAllPoints()
        pcall(function()
            hud:SetPoint(db.hudPoint[1], UIParent, db.hudPoint[3], db.hudPoint[4], db.hudPoint[5])
        end)
    else
        hud:SetPoint("CENTER", UIParent, "CENTER", 260, 60)
    end

    local function StartHUDMoving()
        CloseDropDownMenusSafe()
        hud.isMoving = true
        hud:StartMoving()
    end

    local function StopHUDMoving()
        if not hud.isMoving then return end
        hud.isMoving = nil
        hud:StopMovingOrSizing()
        local point, _, relativePoint, x, y = hud:GetPoint(1)
        if BiaoGe and BiaoGe.RaidCD then
            BiaoGe.RaidCD.hudPoint = { point, "UIParent", relativePoint, math.floor(x), math.floor(y) }
        end
    end

    hud:SetScript("OnMouseDown", function(self, button)
        local locked = BiaoGe and BiaoGe.RaidCD and BiaoGe.RaidCD.hudLocked
        if button == "LeftButton" and (not locked or IsShiftKeyDown()) then
            StartHUDMoving()
        end
    end)

    hud:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.isMoving then
            StopHUDMoving()
        elseif button == "RightButton" then
            RaidCD.OpenHUDMenu(self)
        end
    end)

    -- 顶部标题
    local title = hud:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    title:SetText("团队技能监控")
    title:SetTextColor(1, 0.82, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    hud.title = title

    -- 批量通报喇叭按钮
    local broadcastButton = CreateFrame("Button", nil, hud)
    broadcastButton:SetSize(20, 20)
    broadcastButton:SetNormalTexture("Interface\\Common\\VoiceChat-Speaker")
    broadcastButton:SetPushedTexture("Interface\\Common\\VoiceChat-Speaker")
    broadcastButton:SetHighlightTexture("Interface\\Common\\VoiceChat-Speaker")
    broadcastButton:SetScript("OnClick", function()
        RaidCD.BroadcastCooldownStatus()
    end)
    broadcastButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("一键通报技能状态", 1, 1, 1)
        GameTooltip:AddLine("向团队或队伍通报当前所有受监控技能的冷却与就绪状态。", 1, 0.82, 0, true)
        local rosterData = RaidCD.GetMonitoredRosterCooldowns()
        local count = 0
        for _, pData in ipairs(rosterData) do
            for _, sInfo in ipairs(pData.spells) do
                if sInfo.remaining > 0 then
                    if count == 0 then GameTooltip:AddLine(" ") end
                    local icon = format("|T%s:14:14:0:0|t ", sInfo.def.icon)
                    GameTooltip:AddLine(format("%s%s (%s): |cffff5555冷却剩余 %s|r", icon, sInfo.def.name, SetClassCFF(pData.name, pData.class), FormatRemainingTime(sInfo.remaining)))
                    count = count + 1
                end
            end
        end
        if count == 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("当前所有监控技能全部就绪！", 0.2, 1, 0.2)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BG.STC_b1("点击：向频道通报当前全团技能状态"), 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    broadcastButton:SetScript("OnLeave", GameTooltip_Hide)
    hud.broadcastButton = broadcastButton

    -- 团队工具设置按钮 (魔兽原生内置齿轮)
    local settingsButton = CreateFrame("Button", nil, hud)
    settingsButton:SetSize(20, 20)
    settingsButton:SetNormalTexture([[Interface\Buttons\UI-OptionsButton]])
    settingsButton:SetPushedTexture([[Interface\Buttons\UI-OptionsButton]])
    settingsButton:SetHighlightTexture([[Interface\Buttons\UI-OptionsButton]])
    settingsButton:SetScript("OnClick", function()
        RaidCD.OpenRaidTool()
    end)
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("团队工具设置", 1, 1, 1)
        GameTooltip:AddLine("点击打开【团队工具】主面板，配置技能监控与团队阵容。", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", GameTooltip_Hide)
    hud.settingsButton = settingsButton

    -- 空状态提示
    local emptyTip = hud:CreateFontString(nil, "OVERLAY")
    emptyTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    emptyTip:SetPoint("CENTER", 0, -8)
    emptyTip:SetText(BG.STC_dis("暂无监控技能 (右键设置)"))
    emptyTip:Hide()
    hud.emptyTip = emptyTip

    hud.rowFrames = {}

    -- 驱动计时器刷新 (每 0.25 秒刷新一次 CD 倒计时显示)
    local elapsed = 0
    hud:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.25 then
            elapsed = 0
            RaidCD.RefreshHUDTimers()
        end
    end)

    RaidCD.hudFrame = hud
    return hud
end

-- 刷新 HUD 各条目倒计时
function RaidCD.RefreshHUDTimers()
    local hud = RaidCD.hudFrame
    if not hud or not hud:IsShown() then return end

    for _, row in ipairs(hud.rowFrames or {}) do
        if row:IsShown() and row.spellButtons then
            for _, btn in ipairs(row.spellButtons) do
                if btn:IsShown() and btn.sDef and btn.pName then
                    local rem = RaidCD.GetCooldownRemaining(btn.pName, btn.sDef.id)
                    if rem > 0 then
                        btn.icon:SetDesaturated(true)
                        btn.textCD:SetText(FormatRemainingTime(rem))
                        btn.textCD:SetTextColor(1, 0.85, 0.2)
                        btn.textCD:Show()
                        btn.border:SetColorTexture(0.5, 0.5, 0.5, 0.8)
                    else
                        btn.icon:SetDesaturated(false)
                        btn.textCD:SetText("")
                        btn.textCD:Hide()
                        btn.border:SetColorTexture(0.1, 0.9, 0.2, 0.9)
                    end
                end
            end
        end
    end
end

-- 全量刷新 HUD 布局与人员条目
function RaidCD.UpdateHUD()
    local hud = RaidCD.hudFrame or RaidCD.CreateHUD()
    local db = BiaoGe and BiaoGe.RaidCD

    if not db or not db.showHUD then
        hud:Hide()
        return
    end

    if db.onlyInGroup then
        local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
        if not inGroup then
            hud:Hide()
            return
        end
    end

    if db.onlyInCombat and not InCombatLockdown() then
        hud:Hide()
        return
    end

    hud:Show()
    hud:SetScale(db.hudScale or 1.0)
    hud:SetFrameStrata(db.frameStrata or "MEDIUM")

    local locked = db and db.hudLocked
    if locked then
        hud:SetBackdropColor(0, 0, 0, 0)
        hud:SetBackdropBorderColor(0, 0, 0, 0)
    else
        hud:SetBackdropColor(0.02, 0.02, 0.02, 0.85)
        local r, g, b = 0.25, 0.7, 1.0
        if ns.GetClassRGB then
            r, g, b = ns.GetClassRGB(nil, "player")
        end
        hud:SetBackdropBorderColor(r, g, b, 0.9)
    end

    -- 隐藏现有所有 rows
    for _, row in ipairs(hud.rowFrames or {}) do
        row:Hide()
        if row.spellButtons then
            for _, btn in ipairs(row.spellButtons) do
                btn:Hide()
            end
        end
    end

    local rosterData = RaidCD.GetMonitoredRosterCooldowns()
    if #rosterData == 0 then
        hud.title:ClearAllPoints()
        hud.title:SetPoint("TOPLEFT", hud, "TOPLEFT", 7, -5)
        if hud.settingsButton then
            hud.settingsButton:ClearAllPoints()
            hud.settingsButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -3, -2)
        end
        hud.broadcastButton:ClearAllPoints()
        if hud.settingsButton then
            hud.broadcastButton:SetPoint("RIGHT", hud.settingsButton, "LEFT", -2, 0)
        else
            hud.broadcastButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -3, -2)
        end
        hud.emptyTip:Show()
        hud:SetSize(185, 52)
        return
    else
        hud.emptyTip:Hide()
    end

    local layout = db.hudLayout or 1
    local visibleRows = {}
    local rowHeight = 22
    local gap = 2

    -- 动态测算：获取当前可见队员中最长名字的像素宽度与最多的技能数量
    local maxNameWidth = 54  -- 保底最小 54px (常规4字中文约 48~52px)
    local maxSpellsCount = 1 -- 保底至少 1 个图标位置

    for pIdx, pData in ipairs(rosterData) do
        local row = GetOrCreateRow(hud, pIdx)
        row.pName = pData.name
        row.pClass = pData.class

        -- 玩家职业着色
        local r, g, b = 1, 1, 1
        if pData.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pData.class] then
            r = RAID_CLASS_COLORS[pData.class].r
            g = RAID_CLASS_COLORS[pData.class].g
            b = RAID_CLASS_COLORS[pData.class].b
        end
        row.nameText:SetText(pData.name)
        row.nameText:SetTextColor(r, g, b)

        -- 动态精准获取真实名字渲染像素宽度
        local strW = row.nameText:GetStringWidth() or 0
        if strW > maxNameWidth then
            maxNameWidth = strW
        end

        local spellsCount = pData.spells and #pData.spells or 0
        if spellsCount > maxSpellsCount then
            maxSpellsCount = spellsCount
        end
    end

    -- 规范化最大名字宽度 (增加 4px 呼吸间距，保证汉字不贴边)
    maxNameWidth = math.ceil(maxNameWidth) + 4
    -- 统一技能图标起始坐标（图标垂直对齐线：名字左边距4 + 名字宽度 + 间隔4）
    local btnStartX = 4 + maxNameWidth + 4
    -- 动态计算单条目(Row)总宽度：起始X + 技能数量 * 20 + 尾部留白4
    local itemWidth = btnStartX + maxSpellsCount * 20 + 4
    itemWidth = math.max(136, itemWidth) -- 保底宽度

    for pIdx, pData in ipairs(rosterData) do
        local row = hud.rowFrames[pIdx]
        -- 名字框统一宽度，确保文字整齐左对齐且不超出技能对齐线
        row.nameText:SetWidth(maxNameWidth)

        local btnX = btnStartX
        for sIdx, sInfo in ipairs(pData.spells) do
            local btn = GetOrCreateSpellButton(row, sIdx)
            btn.pName = pData.name
            btn.pClass = pData.class
            btn.sDef = sInfo.def

            btn:ClearAllPoints()
            btn:SetPoint("LEFT", row, "LEFT", btnX, 0)
            btn.icon:SetTexture(sInfo.def.icon)

            if sInfo.remaining > 0 then
                btn.icon:SetDesaturated(true)
                btn.textCD:SetText(FormatRemainingTime(sInfo.remaining))
                btn.textCD:SetTextColor(1, 0.85, 0.2)
                btn.textCD:Show()
                btn.border:SetColorTexture(0.5, 0.5, 0.5, 0.8)
            else
                btn.icon:SetDesaturated(false)
                btn.textCD:SetText("")
                btn.textCD:Hide()
                btn.border:SetColorTexture(0.1, 0.9, 0.2, 0.9)
            end

            btn:Show()
            btnX = btnX + 20
        end

        row:Show()
        table.insert(visibleRows, row)
    end

    hud.title:ClearAllPoints()
    hud.broadcastButton:ClearAllPoints()
    if hud.settingsButton then hud.settingsButton:ClearAllPoints() end

    if layout == 3 then
        -- 单行布局 (Horizontal)
        hud.title:SetPoint("LEFT", hud, "LEFT", 7, 0)
        hud.broadcastButton:SetPoint("LEFT", hud.title, "RIGHT", 3, 0)
        local anchorRight = hud.broadcastButton
        if hud.settingsButton then
            hud.settingsButton:SetPoint("LEFT", hud.broadcastButton, "RIGHT", 2, 0)
            anchorRight = hud.settingsButton
        end

        local prevRow = nil
        for _, row in ipairs(visibleRows) do
            row:ClearAllPoints()
            if prevRow then
                row:SetPoint("LEFT", prevRow, "RIGHT", gap, 0)
            else
                row:SetPoint("LEFT", anchorRight, "RIGHT", 4, 0)
            end
            row:SetSize(itemWidth, rowHeight)
            prevRow = row
        end

        local titleWidth = math.max(55, hud.title:GetStringWidth() or 55)
        local btnExtraWidth = hud.settingsButton and (2 + 20) or 0
        local frameWidth = 7 + titleWidth + 3 + 20 + btnExtraWidth + 4 + #visibleRows * itemWidth + math.max(0, #visibleRows - 1) * gap + 6
        hud:SetSize(frameWidth, 26)
    else
        -- 纵向布局：单列 (layout == 1, 默认) 或 双列 (layout == 2)
        hud.title:SetPoint("TOPLEFT", hud, "TOPLEFT", 7, -5)
        if hud.settingsButton then
            hud.settingsButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -3, -2)
            hud.broadcastButton:SetPoint("RIGHT", hud.settingsButton, "LEFT", -2, 0)
        else
            hud.broadcastButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -3, -2)
        end

        local columns = (layout == 1) and 1 or 2
        local frameWidth = (columns == 2) and (5 + itemWidth * 2 + gap + 5) or (5 + itemWidth + 5)

        for index, row in ipairs(visibleRows) do
            local col = (index - 1) % columns
            local line = math.floor((index - 1) / columns)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", hud, "TOPLEFT", 5 + col * (itemWidth + gap), -25 - line * (rowHeight + gap))
            row:SetSize(itemWidth, rowHeight)
        end

        local lineCount = math.floor((#visibleRows + columns - 1) / columns)
        local frameHeight = 30 + lineCount * (rowHeight + gap) - gap
        hud:SetSize(frameWidth, math.max(30, frameHeight))
    end
end


function RaidCD.CheckCombatVisibility()
    local db = BiaoGe and BiaoGe.RaidCD
    if not db or not db.showHUD then return end
    if db.onlyInCombat then
        if InCombatLockdown() then
            RaidCD.UpdateHUD()
        else
            if RaidCD.hudFrame then RaidCD.hudFrame:Hide() end
        end
    else
        RaidCD.UpdateHUD()
    end
end

--------------------------------------------------------------------------------
-- 6. 技能可选过滤配置弹窗 (Config Modal)
--------------------------------------------------------------------------------
local configModal = nil
function RaidCD.ToggleConfigModal()
    if configModal and configModal:IsShown() then
        configModal:Hide()
        return
    end

    if not configModal then
        local f = CreateFrame("Frame", "BG_RaidCDConfigModal", UIParent, "BackdropTemplate")
        f:SetSize(760, 480)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
        f:SetBackdropBorderColor(0.2, 0.7, 1, 0.9)

        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("|TInterface\\AddOns\\BGLite_Plus\\Media\\shield:16:16:0:0|t " .. BG.STC_g1("团队关键减伤监控 - 技能过滤配置"))

        local subTip = f:CreateFontString(nil, "OVERLAY")
        subTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        subTip:SetPoint("TOPLEFT", 16, -32)
        subTip:SetText(BG.STC_dis("左栏：圣骑士 / 牧师 / 德鲁伊    |    右栏：战士 / 死亡骑士 / 萨满祭司    (鼠标悬停查看技能官方详情)"))

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        f.spellCheckButtons = {}
        f.spellRows = {}

        local columns = {
            { x = 18,  classes = { "PALADIN", "PRIEST", "DRUID" } },
            { x = 390, classes = { "WARRIOR", "DEATHKNIGHT", "SHAMAN" } },
        }

        local isAlliance = (UnitFactionGroup and UnitFactionGroup("player") == "Alliance")
        local classTitles = {
            PALADIN = "圣骑士 (Paladin) - 核心减伤与手推",
            PRIEST = "牧师 (Priest) - 单体减伤与赞美诗",
            DRUID = "德鲁伊 (Druid) - 树皮/本能与战复",
            WARRIOR = "战士 (Warrior) - 盾墙与破釜沉舟",
            DEATHKNIGHT = "死亡骑士 (Death Knight) - 冰韧/绿坝与大罩",
            SHAMAN = isAlliance and "萨满祭司 (Shaman) - 英勇与法力潮" or "萨满祭司 (Shaman) - 嗜血与法力潮",
        }

        for _, colInfo in ipairs(columns) do
            local yOffset = -54
            for _, cls in ipairs(colInfo.classes) do
                local secTitle = f:CreateFontString(nil, "OVERLAY")
                secTitle:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                secTitle:SetPoint("TOPLEFT", f, "TOPLEFT", colInfo.x, yOffset)
                local r, g, b = 1, 1, 1
                if RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
                    r = RAID_CLASS_COLORS[cls].r
                    g = RAID_CLASS_COLORS[cls].g
                    b = RAID_CLASS_COLORS[cls].b
                end
                secTitle:SetText(classTitles[cls] or cls)
                secTitle:SetTextColor(r, g, b)
                yOffset = yOffset - 20

                for _, def in ipairs(RaidCD.SPELLS) do
                    if def.class == cls and IsSpellFactionMatch(def.id) then
                        local rowBtn = CreateFrame("Button", nil, f)
                        rowBtn:SetSize(355, 20)
                        rowBtn:SetPoint("TOPLEFT", f, "TOPLEFT", colInfo.x + 4, yOffset)

                        local hl = rowBtn:CreateTexture(nil, "HIGHLIGHT")
                        hl:SetAllPoints()
                        hl:SetTexture("Interface/Buttons/UI-Listbox-Highlight")
                        hl:SetAlpha(0.2)

                        local cb = CreateFrame("CheckButton", nil, rowBtn, "UICheckButtonTemplate")
                        cb:SetSize(18, 18)
                        cb:SetPoint("LEFT", 0, 0)
                        cb.spellId = def.id

                        local icon = rowBtn:CreateTexture(nil, "ARTWORK")
                        icon:SetSize(16, 16)
                        icon:SetPoint("LEFT", cb, "RIGHT", 3, 0)
                        icon:SetTexture(def.icon)
                        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                        local txt = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                        txt:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                        txt:SetPoint("LEFT", icon, "RIGHT", 5, 0)
                        txt:SetWidth(310)
                        txt:SetJustifyH("LEFT")
                        txt:SetWordWrap(false)
                        cb.label = txt

                        cb:SetScript("OnClick", function(self)
                            if IsModifiedClick("CHATLINK") then
                                self:SetChecked(not self:GetChecked())
                                local link = GetSpellHyperlink(self.spellId, def.name)
                                if link and ChatEdit_InsertLink then
                                    ChatEdit_InsertLink(link)
                                end
                            else
                                RaidCD.SetSpellEnabled(self.spellId, self:GetChecked())
                                BG.PlaySound(1)
                            end
                        end)

                        local function ShowSpellTooltip(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:ClearLines()
                            if GameTooltip.SetSpellByID then
                                GameTooltip:SetSpellByID(def.id)
                            else
                                local link = GetSpellLink(def.id)
                                if link then
                                    GameTooltip:SetHyperlink(link)
                                else
                                    GameTooltip:SetHyperlink("spell:" .. def.id)
                                end
                            end
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddDoubleLine(BG.STC_g1("官方基础冷却: "), BG.STC_w1(FormatRemainingTime(def.cd)))
                            if def.desc then
                                GameTooltip:AddLine(BG.STC_dis("定位说明: " .. def.desc), 0.8, 0.8, 0.8)
                            end
                            GameTooltip:AddLine(BG.STC_b1("Shift+左键：将技能超链接发送至聊天框"), 0.4, 0.8, 1)
                            GameTooltip:Show()
                        end

                        rowBtn:SetScript("OnEnter", ShowSpellTooltip)
                        rowBtn:SetScript("OnLeave", GameTooltip_Hide)
                        cb:SetScript("OnEnter", ShowSpellTooltip)
                        cb:SetScript("OnLeave", GameTooltip_Hide)

                        rowBtn:SetScript("OnClick", function(self, button)
                            if IsModifiedClick("CHATLINK") then
                                local link = GetSpellHyperlink(def.id, def.name)
                                if link and ChatEdit_InsertLink then
                                    ChatEdit_InsertLink(link)
                                end
                            else
                                cb:SetChecked(not cb:GetChecked())
                                RaidCD.SetSpellEnabled(cb.spellId, cb:GetChecked())
                                BG.PlaySound(1)
                            end
                        end)

                        f.spellCheckButtons[def.id] = cb
                        f.spellRows[def.id] = { btn = rowBtn, cb = cb, txt = txt, def = def }
                        yOffset = yOffset - 21
                    end
                end
                yOffset = yOffset - 8
            end
        end

        -- 底部一键操作栏
        local btnAllDefault = BG.CreateButton(f)
        btnAllDefault:SetSize(110, 24)
        btnAllDefault:SetPoint("BOTTOMLEFT", 16, 12)
        btnAllDefault:SetText("恢复默认勾选")
        btnAllDefault:SetScript("OnClick", function()
            local db = BiaoGe and BiaoGe.RaidCD
            if db then
                for _, def in ipairs(RaidCD.SPELLS) do
                    db.enabledSpells[def.id] = def.default
                end
            end
            RaidCD.RefreshConfigModalUI()
            RaidCD.UpdateHUD()
            RaidCD.UpdatePanelUI()
            BG.PlaySound(1)
        end)

        local btnResetPeople = BG.CreateButton(f)
        btnResetPeople:SetSize(130, 24)
        btnResetPeople:SetPoint("LEFT", btnAllDefault, "RIGHT", 8, 0)
        btnResetPeople:SetText("恢复默认监控职业")
        btnResetPeople:SetScript("OnClick", function()
            RaidCD.ResetAllPlayersToDefault()
            BG.PlaySound(1)
        end)

        local btnSelectAll = BG.CreateButton(f)
        btnSelectAll:SetSize(76, 24)
        btnSelectAll:SetPoint("LEFT", btnResetPeople, "RIGHT", 8, 0)
        btnSelectAll:SetText("全部开启")
        btnSelectAll:SetScript("OnClick", function()
            local db = BiaoGe and BiaoGe.RaidCD
            if db then
                for _, def in ipairs(RaidCD.SPELLS) do
                    db.enabledSpells[def.id] = true
                end
            end
            RaidCD.RefreshConfigModalUI()
            RaidCD.UpdateHUD()
            RaidCD.UpdatePanelUI()
            BG.PlaySound(1)
        end)

        local btnDeselectAll = BG.CreateButton(f)
        btnDeselectAll:SetSize(76, 24)
        btnDeselectAll:SetPoint("LEFT", btnSelectAll, "RIGHT", 8, 0)
        btnDeselectAll:SetText("全部关闭")
        btnDeselectAll:SetScript("OnClick", function()
            local db = BiaoGe and BiaoGe.RaidCD
            if db then
                for _, def in ipairs(RaidCD.SPELLS) do
                    db.enabledSpells[def.id] = false
                end
            end
            RaidCD.RefreshConfigModalUI()
            RaidCD.UpdateHUD()
            RaidCD.UpdatePanelUI()
            BG.PlaySound(1)
        end)

        local btnClose = BG.CreateButton(f)
        btnClose:SetSize(70, 24)
        btnClose:SetPoint("BOTTOMRIGHT", -16, 12)
        btnClose:SetText("关闭")
        btnClose:SetScript("OnClick", function() f:Hide() end)

        configModal = f
    end

    RaidCD.RefreshConfigModalUI()
    configModal:Show()
end

function RaidCD.RefreshConfigModalUI()
    if not configModal or not configModal.spellRows then return end

    for sId, row in pairs(configModal.spellRows) do
        row.cb:SetChecked(RaidCD.IsSpellEnabled(sId))
        local cdStr = format("(%s)", RaidCD.FormatRemainingTime(row.def.cd))
        local descStr = row.def.desc and (" " .. BG.STC_dis(row.def.desc)) or ""
        row.txt:SetText(row.def.name .. " " .. BG.STC_dis(cdStr) .. descStr)
    end
end

--------------------------------------------------------------------------------
-- 7. 团队工具面板内置展示与联动 (Panel Integration)
--------------------------------------------------------------------------------
function RaidCD.CreatePanelSection(parent)
    if RaidCD.panelSection then return RaidCD.panelSection end

    local panel = CreateFrame("Frame", "BG_RaidCDPanelSection", parent)
    panel:SetAllPoints()

    -- 人员与排序配置按钮
    local btnPlayerCfg = BG.CreateButton(panel)
    btnPlayerCfg:SetSize(90, 20)
    btnPlayerCfg:SetPoint("TOPRIGHT", -4, 22)
    btnPlayerCfg:SetText("人员与排序")
    btnPlayerCfg:SetScript("OnClick", function()
        RaidCD.TogglePlayerSelectModal()
        BG.PlaySound(1)
    end)
    btnPlayerCfg:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("团队技能监控人员与排序配置", 1, 1, 1)
        GameTooltip:AddLine("配置需要监控的队员名单，或自由调整人员在悬浮条与面板中的排布顺序。", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnPlayerCfg:SetScript("OnLeave", GameTooltip_Hide)

    -- 预览展示滚动列表
    local scrollParent = CreateFrame("ScrollFrame", "BG_RaidCDPanelScroll", panel, "UIPanelScrollFrameTemplate")
    scrollParent:SetPoint("TOPLEFT", 0, 0)
    scrollParent:SetPoint("BOTTOMRIGHT", -20, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollParent)
    scrollChild:SetSize(540, 50)
    scrollParent:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild
    panel.entryItems = {}

    RaidCD.panelSection = panel
    return panel
end

function RaidCD.UpdatePanelUI()
    local panel = RaidCD.panelSection
    if not panel or not panel:IsShown() then return end

    local content = panel.scrollChild
    local rosterData = RaidCD.GetMonitoredRosterCooldowns()

    for _, it in ipairs(panel.entryItems) do it:Hide() end

    if #rosterData == 0 then
        if not panel.emptyTip then
            local t = panel:CreateFontString(nil, "OVERLAY")
            t:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
            t:SetPoint("LEFT", panel, "LEFT", 20, -10)
            t:SetText(BG.STC_dis("当前无监控中队员或技能。请在上方40人阵列网格中勾选队员，或点击右上角【技能过滤配置】。"))
            panel.emptyTip = t
        end
        panel.emptyTip:Show()
        return
    else
        if panel.emptyTip then panel.emptyTip:Hide() end
    end

    local xOffset = 0
    for idx, pData in ipairs(rosterData) do
        local item = panel.entryItems[idx]
        if not item then
            item = CreateFrame("Frame", nil, content, "BackdropTemplate")
            item:SetSize(130, 44)
            item:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            item:SetBackdropColor(0.12, 0.12, 0.12, 0.8)
            item:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)

            local pText = item:CreateFontString(nil, "OVERLAY")
            pText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            pText:SetPoint("TOPLEFT", 4, -3)
            item.pText = pText

            item.icons = {}
            panel.entryItems[idx] = item
        end

        local r, g, b = 1, 1, 1
        if pData.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pData.class] then
            r = RAID_CLASS_COLORS[pData.class].r
            g = RAID_CLASS_COLORS[pData.class].g
            b = RAID_CLASS_COLORS[pData.class].b
        end
        item.pText:SetText(pData.name)
        item.pText:SetTextColor(r, g, b)

        local iX = 4
        for sIdx, sInfo in ipairs(pData.spells) do
            if sIdx <= 4 then
                local sBtn = item.icons[sIdx]
                if not sBtn then
                    sBtn = CreateFrame("Button", nil, item)
                    sBtn:SetSize(18, 18)
                    sBtn.tex = sBtn:CreateTexture(nil, "ARTWORK")
                    sBtn.tex:SetAllPoints()
                    sBtn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    sBtn.txt = sBtn:CreateFontString(nil, "OVERLAY")
                    sBtn.txt:SetFont(BIAOGE_TEXT_FONT, 9, "OUTLINE")
                    sBtn.txt:SetPoint("BOTTOM", 0, -1)

                    sBtn:SetScript("OnEnter", function(self)
                        if not self.sInfo then return end
                        GameTooltip:SetOwner(self, "ANCHOR_TOP")
                        GameTooltip:ClearLines()
                        local sDef = self.sInfo.def
                        if GameTooltip.SetSpellByID then
                            GameTooltip:SetSpellByID(sDef.id)
                        else
                            local link = GetSpellLink(sDef.id)
                            if link then
                                GameTooltip:SetHyperlink(link)
                            else
                                GameTooltip:SetHyperlink("spell:" .. sDef.id)
                            end
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine(BG.STC_w1("使用者: " .. (self.pName or "")), (self.sInfo.remaining > 0) and ("|cffff5555冷却剩余: " .. FormatRemainingTime(self.sInfo.remaining) .. "|r") or "|cff00ff00准备就绪|r")
                        GameTooltip:AddDoubleLine(BG.STC_g1("官方基础冷却: "), BG.STC_w1(FormatRemainingTime(sDef.cd)))
                        if sDef.desc then
                            GameTooltip:AddLine(BG.STC_dis("定位说明: " .. sDef.desc))
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(BG.STC_b1("左键点击：通报状态 | Shift+点击：发送技能超链接"), 0.4, 0.8, 1)
                        GameTooltip:Show()
                    end)
                    sBtn:SetScript("OnLeave", GameTooltip_Hide)

                    sBtn:SetScript("OnClick", function(self)
                        if not self.sInfo or not self.pName then return end
                        local sDef = self.sInfo.def
                        if IsModifiedClick("CHATLINK") then
                            local link = GetSpellHyperlink(sDef.id, sDef.name)
                            if link and ChatEdit_InsertLink then
                                ChatEdit_InsertLink(link)
                            end
                        else
                            local rem = RaidCD.GetCooldownRemaining(self.pName, sDef.id)
                            local statusStr = (rem > 0) and ("冷却剩余: " .. FormatRemainingTime(rem)) or "【已就绪】"
                            local msg = format("[BGLite 技能监控] %s 的 %s %s", self.pName, sDef.name, statusStr)
                            local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "EMOTE")
                            if channel == "EMOTE" then
                                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF" .. msg .. "|r")
                            else
                                SendChatMessage(msg, channel)
                            end
                            BG.PlaySound(1)
                        end
                    end)

                    item.icons[sIdx] = sBtn
                end
                sBtn.sInfo = sInfo
                sBtn.pName = pData.name
                sBtn:SetPoint("TOPLEFT", iX, -20)
                sBtn.tex:SetTexture(sInfo.def.icon)
                if sInfo.remaining > 0 then
                    sBtn.tex:SetDesaturated(true)
                    sBtn.txt:SetText(FormatRemainingTime(sInfo.remaining))
                    sBtn.txt:SetTextColor(1, 0.8, 0.2)
                else
                    sBtn.tex:SetDesaturated(false)
                    sBtn.txt:SetText(BG.STC_g1("就绪"))
                end
                sBtn:Show()
                iX = iX + 22
            end
        end

        item:SetPoint("TOPLEFT", xOffset, 0)
        item:Show()
        xOffset = xOffset + 136
    end
    content:SetWidth(math.max(540, xOffset))
end

--------------------------------------------------------------------------------
-- 8. 模块初始化入口
--------------------------------------------------------------------------------
function ns.InitRaidCDModule()
    ns.InitRaidCDDB()
    if BiaoGe and BiaoGe.RaidCD and BiaoGe.RaidCD.showHUD then
        RaidCD.CreateHUD()
        RaidCD.UpdateHUD()
    end
end
