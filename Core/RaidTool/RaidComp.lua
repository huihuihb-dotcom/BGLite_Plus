if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidComp = {}
ns.RaidComp = RaidComp
_G.RaidComp = RaidComp

local RaidTool = ns.RaidTool or _G.RaidTool

-- 推广信息标准尾缀（已包含作者波比兔与网易DD平台下载指引）
RaidComp.PROMO_TEXT = ">>> 来自 [BGLite PLUS] 团队阵容助手 - 作者: 波比兔 (网易DD平台搜索: BGlite PLUS 下载)"

--------------------------------------------------------------------------------
-- 1. 专精定义与角色定位 (Spec Definitions & Roles)
--------------------------------------------------------------------------------
-- 专精角色定位：tank(坦克), healer(治疗), melee(近战DPS), ranged(远程DPS)
local SPEC_INFO = {
    -- 战士
    ["WARRIOR"] = {
        [1] = { name = "武器", role = "melee" },
        [2] = { name = "狂暴", role = "melee" },
        [3] = { name = "防护", role = "tank" },
    },
    -- 圣骑士
    ["PALADIN"] = {
        [1] = { name = "神圣", role = "healer" },
        [2] = { name = "防护", role = "tank" },
        [3] = { name = "惩戒", role = "melee" },
    },
    -- 猎人
    ["HUNTER"] = {
        [1] = { name = "兽王", role = "ranged" },
        [2] = { name = "射击", role = "ranged" },
        [3] = { name = "生存", role = "ranged" },
    },
    -- 潜行者
    ["ROGUE"] = {
        [1] = { name = "刺杀", role = "melee" },
        [2] = { name = "战斗", role = "melee" },
        [3] = { name = "敏锐", role = "melee" },
    },
    -- 牧师
    ["PRIEST"] = {
        [1] = { name = "戒律", role = "healer" },
        [2] = { name = "神圣", role = "healer" },
        [3] = { name = "暗影", role = "ranged" },
    },
    -- 死亡骑士
    ["DEATHKNIGHT"] = {
        [1] = { name = "鲜血", role = "tank" },     -- WLK/时光服 血DK通常作为主流主坦/副坦
        [2] = { name = "冰霜", role = "melee" },
        [3] = { name = "邪恶", role = "melee" },
    },
    -- 萨满
    ["SHAMAN"] = {
        [1] = { name = "元素", role = "ranged" },
        [2] = { name = "增强", role = "melee" },
        [3] = { name = "恢复", role = "healer" },
    },
    -- 法师
    ["MAGE"] = {
        [1] = { name = "奥术", role = "ranged" },
        [2] = { name = "火焰", role = "ranged" },
        [3] = { name = "冰霜", role = "ranged" },
    },
    -- 术士
    ["WARLOCK"] = {
        [1] = { name = "痛苦", role = "ranged" },
        [2] = { name = "恶魔", role = "ranged" },
        [3] = { name = "毁灭", role = "ranged" },
    },
    -- 德鲁伊
    ["DRUID"] = {
        [1] = { name = "平衡", role = "ranged" },   -- 鸟德
        [2] = { name = "野性", role = "melee" },    -- 熊/猫 (默认近战/副坦)
        [3] = { name = "恢复", role = "healer" },   -- 奶德
    },
}

--------------------------------------------------------------------------------
-- 2. 全团 Buff / Debuff 规则全家福定义 (24 大核心项，完整涵盖原图所有项目)
--------------------------------------------------------------------------------
RaidComp.BUFF_CATEGORIES = {
    { id = "CORE", name = "全团核心增益", desc = "全团通用伤害/急速爆发与核心祝福" },
    { id = "SPELL", name = "法系增益与减益", desc = "法伤、法术暴击、法术命中与法系易伤" },
    { id = "PHYSICAL", name = "物理增益与减益", desc = "攻强、近战急速、物理暴击与大/小破甲" },
    { id = "SURVIVAL", name = "团队生存与削弱", desc = "减伤大招、Boss攻击削弱与战复/激活" },
}

RaidComp.BUFF_DEFINITIONS = {
    ----------------------------------------------------------------------------
    -- A. 全团核心增益 (CORE)
    ----------------------------------------------------------------------------
    {
        id = "DAMAGE_3",
        category = "CORE",
        name = "3% 全伤害加成",
        shortName = "3%伤害",
        desc = "提高全团造成的伤害 3%",
        providers = {
            { class = "PALADIN", spec = "惩戒", skill = "圣洁惩戒", isBest = true },
            { class = "MAGE", spec = "奥术", skill = "奥术增效", isBest = true },
            { class = "HUNTER", spec = "兽王", skill = "凶猛灵感" },
        },
        needSpec = "惩戒骑 / 奥法 / 兽王猎",
    },
    {
        id = "HASTE_3",
        category = "CORE",
        name = "3% 全急速加成",
        shortName = "3%全急速",
        desc = "提高全团施法与攻击速度 3%",
        providers = {
            { class = "PALADIN", spec = "惩戒", skill = "迅捷惩戒", isBest = true },
            { class = "DRUID", spec = "平衡", skill = "强化枭兽光环", isBest = true },
        },
        needSpec = "惩戒骑 / 鸟德",
    },
    {
        id = "BLOODLUST",
        category = "CORE",
        name = "嗜血 / 英勇爆发",
        shortName = "嗜血/英勇",
        desc = "全团爆发急速 30% 持续 40 秒 (萨满唯一)",
        providers = {
            { class = "SHAMAN", skill = "嗜血/英勇", isBest = true },
        },
        needSpec = "任意专精萨满 (增强/元素/奶萨)",
    },
    {
        id = "PALADIN_BLESSINGS",
        category = "CORE",
        name = "圣骑士三大祝福",
        shortName = "骑士三祝福",
        desc = "王者祝福(全属性10%) + 庇护(3%减伤/回蓝) + 力量/智慧",
        customCheck = function(roster)
            local count = 0
            local names = {}
            for _, m in pairs(roster) do
                if m.class == "PALADIN" then
                    count = count + 1
                    tinsert(names, m.name .. "(" .. (m.specName or "骑士") .. ")")
                end
            end
            if count >= 3 then
                return true, names, "齐备(≥3位骑士)"
            elseif count == 2 then
                return true, names, "基本齐备(2位骑士，缺1种祝福)"
            elseif count == 1 then
                return false, names, "缺2种祝福(仅1位骑士)"
            else
                return false, {}, "严重缺失(团队无骑士)"
            end
        end,
        needSpec = "需要至少 2~3 位圣骑士",
    },
    {
        id = "CRIT_DEBUFF_3",
        category = "CORE",
        name = "3% 全受暴击 (Debuff)",
        shortName = "3%暴击Debuff",
        desc = "目标承受物理与法术暴击几率提高 3%",
        providers = {
            { class = "PALADIN", spec = "惩戒", skill = "十字军之心", isBest = true },
            { class = "ROGUE", spec = "刺杀", skill = "奇毒", isBest = true },
            { class = "SHAMAN", spec = "元素", skill = "天怒图腾" },
        },
        needSpec = "惩戒骑 / 刺杀贼 / 元素萨",
    },

    ----------------------------------------------------------------------------
    -- B. 法系增益与减益 (SPELL)
    ----------------------------------------------------------------------------
    {
        id = "SPELL_HASTE_5",
        category = "SPELL",
        name = "5% 法术急速 (空气图腾)",
        shortName = "5%法术急速",
        desc = "提高法系与治疗法术急速 5% (萨满空气之怒图腾唯一)",
        providers = {
            { class = "SHAMAN", skill = "空气之怒图腾", isBest = true },
        },
        needSpec = "任意专精萨满 (增强/元素/恢复)",
    },
    {
        id = "SPELL_POWER_BUFF",
        category = "SPELL",
        name = "法术强度光环 / 恶魔契约",
        shortName = "全团法强",
        desc = "恶魔契约(提供自身法伤10%加成，全团400~600+法伤) 或 天怒图腾(固定280)",
        providers = {
            { class = "WARLOCK", spec = "恶魔", skill = "恶魔契约", isBest = true },
            { class = "SHAMAN", spec = "元素", skill = "天怒图腾" },
        },
        needSpec = "首选恶魔术 (法伤加成最高) / 元素萨",
    },
    {
        id = "SPELL_CRIT_5",
        category = "SPELL",
        name = "5% 法术暴击光环",
        shortName = "5%法术暴击",
        desc = "使全团法术暴击几率提高 5%",
        providers = {
            { class = "DRUID", spec = "平衡", skill = "枭兽光环", isBest = true },
            { class = "SHAMAN", spec = "元素", skill = "元素之誓", isBest = true },
        },
        needSpec = "鸟德 (平衡) / 元素萨",
    },
    {
        id = "SPELL_HIT_3",
        category = "SPELL",
        name = "3% 法术命中加深",
        shortName = "3%法术命中",
        desc = "目标承受法术命中几率提高 3% (法系配装直接减少命中压力)",
        providers = {
            { class = "DRUID", spec = "平衡", skill = "强化精灵火", isBest = true },
            { class = "PRIEST", spec = "暗影", skill = "悲惨", isBest = true },
        },
        needSpec = "鸟德 / 暗牧",
    },
    {
        id = "SPELL_VULN_13",
        category = "SPELL",
        name = "13% 法术伤害易伤",
        shortName = "13%法术易伤",
        desc = "目标受到所有法术伤害提高 13%",
        providers = {
            { class = "DEATHKNIGHT", spec = "邪恶", skill = "黑色瘟疫使者", isBest = true },
            { class = "DRUID", spec = "平衡", skill = "大地与月亮", isBest = true },
            { class = "WARLOCK", skill = "元素诅咒", isBest = true },
        },
        needSpec = "邪DK / 鸟德 / 术士",
    },
    {
        id = "SPELL_CRIT_DEBUFF_5",
        category = "SPELL",
        name = "5% 法术暴击加深 (Debuff)",
        shortName = "5%法爆Debuff",
        desc = "目标承受法术暴击几率额外提高 5%",
        providers = {
            { class = "WARLOCK", spec = "痛苦", skill = "强化暗影箭", isBest = true },
            { class = "WARLOCK", spec = "恶魔", skill = "强化暗影箭", isBest = true },
            { class = "MAGE", spec = "火焰", skill = "强化灼烧", isBest = true },
            { class = "MAGE", spec = "冰霜", skill = "深冬之寒" },
        },
        needSpec = "痛苦术 / 恶魔术 / 火法",
    },

    ----------------------------------------------------------------------------
    -- C. 物理增益与减益 (PHYSICAL)
    ----------------------------------------------------------------------------
    {
        id = "MELEE_HASTE_20",
        category = "PHYSICAL",
        name = "20% 近战急速光环",
        shortName = "20%近战急速",
        desc = "使近战和远程物理攻击速度提高 20%",
        providers = {
            { class = "DEATHKNIGHT", spec = "冰霜", skill = "强化冰冷之爪", isBest = true },
            { class = "SHAMAN", spec = "增强", skill = "强化风怒图腾", isBest = true },
        },
        needSpec = "冰DK / 增强萨",
    },
    {
        id = "PHYSICAL_CRIT_5",
        category = "PHYSICAL",
        name = "5% 物理暴击光环",
        shortName = "5%物理暴击",
        desc = "使附近队友物理暴击几率提高 5%",
        providers = {
            { class = "WARRIOR", spec = "狂暴", skill = "暴怒", isBest = true },
            { class = "DRUID", spec = "野性", skill = "兽群领袖", isBest = true },
        },
        needSpec = "狂暴战 / 熊德 / 猫德",
    },
    {
        id = "ATTACK_POWER_PCT_10",
        category = "PHYSICAL",
        name = "10% 攻击强度加成",
        shortName = "10%攻强",
        desc = "使全团攻击强度提高 10%",
        providers = {
            { class = "DEATHKNIGHT", spec = "鲜血", skill = "憎恶之力", isBest = true },
            { class = "HUNTER", spec = "射击", skill = "强击光环", isBest = true },
            { class = "SHAMAN", spec = "增强", skill = "怒火释放", isBest = true },
        },
        needSpec = "血DK / 射击猎 / 增强萨",
    },
    {
        id = "ATTACK_POWER_FLAT",
        category = "PHYSICAL",
        name = "固定攻强加成 (力量祝福/战吼)",
        shortName = "数值攻强",
        desc = "强化力量祝福 (688点) 或 强化战斗怒吼 (685点)",
        providers = {
            { class = "PALADIN", skill = "强化力量祝福", isBest = true },
            { class = "WARRIOR", skill = "战斗怒吼" },
        },
        needSpec = "圣骑士 (力量祝福) / 战士 (战吼)",
    },
    {
        id = "STR_AGI_BUFF",
        category = "PHYSICAL",
        name = "力量与敏捷加成",
        shortName = "力量敏捷",
        desc = "强化大地力量图腾 (178力敏) 或 寒冬号角 (155力敏)",
        providers = {
            { class = "SHAMAN", spec = "增强", skill = "强化力量图腾", isBest = true },
            { class = "DEATHKNIGHT", skill = "寒冬号角", isBest = true },
        },
        needSpec = "增强萨 (178力敏) / 任意DK (155号角)",
    },
    {
        id = "MAJOR_ARMOR_20",
        category = "PHYSICAL",
        name = "主要破甲 -20% (大破甲)",
        shortName = "20%主要破甲",
        desc = "降低目标护甲值 20% (战士破甲攻击 或 盗贼强破)",
        providers = {
            { class = "WARRIOR", skill = "破甲攻击(五破)", isBest = true },
            { class = "ROGUE", spec = "战斗", skill = "强化暴露护甲" },
        },
        needSpec = "战士 (防战/狂暴/武器) / 战斗贼",
    },
    {
        id = "MINOR_ARMOR_5",
        category = "PHYSICAL",
        name = "次要破甲 -5% (精灵火)",
        shortName = "5%精灵火破甲",
        desc = "降低目标护甲值 5% (与主要破甲乘法叠加，大幅提升物理输出)",
        providers = {
            { class = "DRUID", skill = "精灵之火", isBest = true },
        },
        needSpec = "任意德鲁伊 (鸟德/熊/猫/树德)",
    },
    {
        id = "PHYSICAL_VULN_4",
        category = "PHYSICAL",
        name = "4% 物理伤害易伤",
        shortName = "4%物理易伤",
        desc = "目标受到的物理伤害提高 4%",
        providers = {
            { class = "ROGUE", spec = "战斗", skill = "野蛮战斗", isBest = true },
            { class = "WARRIOR", spec = "武器", skill = "血腥狂乱", isBest = true },
        },
        needSpec = "战斗贼 / 武器战",
    },
    {
        id = "BLEED_VULN_30",
        category = "PHYSICAL",
        name = "30% 流血伤害加深",
        shortName = "30%流血伤害",
        desc = "目标受到的流血伤害提高 30% (猫德与战士重伤极大收益)",
        providers = {
            { class = "DRUID", spec = "野性", skill = "裂伤", isBest = true },
            { class = "WARRIOR", spec = "武器", skill = "创伤", isBest = true },
        },
        needSpec = "猫德 / 熊德 / 武器战",
    },

    ----------------------------------------------------------------------------
    -- D. 团队生存与削弱 (SURVIVAL)
    ----------------------------------------------------------------------------
    {
        id = "RAID_REDUCTION",
        category = "SURVIVAL",
        name = "团队大减伤 (神圣牺牲/守护者)",
        shortName = "全团大减伤",
        desc = "全团 20% 伤害减免神技，团本高压灭团点底牌",
        providers = {
            { class = "PALADIN", spec = "防护", skill = "神圣守护者", isBest = true },
            { class = "PALADIN", spec = "神圣", skill = "神圣牺牲", isBest = true },
        },
        needSpec = "防骑 / 奶骑",
    },
    {
        id = "TANK_BOSS_SLOW_20",
        category = "SURVIVAL",
        name = "Boss 攻击速度降低 20%",
        shortName = "Boss减速20%",
        desc = "使 Boss 物理攻击速度降低 20%，大幅缓解主坦倒坦风险",
        providers = {
            { class = "DEATHKNIGHT", skill = "冰霜疫病", isBest = true },
            { class = "WARRIOR", skill = "雷霆一击", isBest = true },
            { class = "DRUID", spec = "野性", skill = "感染" },
        },
        needSpec = "DK (冰霜疫病) / 战士 (雷霆) / 熊德",
    },
    {
        id = "TANK_BOSS_AP_REDUCE",
        category = "SURVIVAL",
        name = "Boss 攻击强度削弱",
        shortName = "Boss减攻强",
        desc = "降低 Boss 近战攻击强度 575+ 点 (挫志/虚弱诅咒)",
        providers = {
            { class = "WARRIOR", skill = "挫志怒吼", isBest = true },
            { class = "DRUID", skill = "挫志咆哮", isBest = true },
            { class = "WARLOCK", skill = "虚弱诅咒" },
        },
        needSpec = "战士 / 德鲁伊 / 术士",
    },
    {
        id = "COMBAT_RES_INNER",
        category = "SURVIVAL",
        name = "战斗复活 & 激活回蓝",
        shortName = "战复与激活",
        desc = "战斗中复活队员与关键治疗回蓝激活 (容错保障)",
        providers = {
            { class = "DRUID", skill = "复生 / 激活", isBest = true },
        },
        needSpec = "德鲁伊 (建议团队备 2~3 名小德)",
    },
    {
        id = "EXTERNAL_DEF_PAIN",
        category = "SURVIVAL",
        name = "单体保坦大减伤 (压制/树皮/牺牲)",
        shortName = "保坦大减伤",
        desc = "痛苦压制 (戒律牧40%减伤)、树皮术/铁木树皮 (小德)、牺牲之手 (骑士30%转移)、守护圣灵 (神牧免死)",
        providers = {
            { class = "PRIEST", spec = "戒律", skill = "痛苦压制", isBest = true },
            { class = "DRUID", spec = "恢复", skill = "树皮术/铁木树皮", isBest = true },
            { class = "PALADIN", skill = "牺牲之手", isBest = true },
            { class = "PRIEST", spec = "神圣", skill = "守护圣灵" },
        },
        needSpec = "首选戒律牧 (痛苦压制) / 奶德 (树皮) / 圣骑士",
    },
    {
        id = "STAMINA_BUFF",
        category = "SURVIVAL",
        name = "全团耐力加成 (真言术:韧)",
        shortName = "全团耐力",
        desc = "大幅提高全团耐力与最大生命值上限 (开荒硬生存底牌)",
        providers = {
            { class = "PRIEST", skill = "真言术:韧", isBest = true },
        },
        needSpec = "任意专精牧师 (戒律牧 / 神牧 / 暗牧)",
    },
}

--------------------------------------------------------------------------------
-- 3. 多源融合团队专精与天赋识别网络 (Multi-Source Talent & Spec Network)
--------------------------------------------------------------------------------
-- 全局标准专精 ID 映射表 (覆盖全部 10 大职业全部专精)
local SPEC_ID_MAP = {
    -- 战士
    [71] = { name = "武器", role = "melee" },
    [72] = { name = "狂暴", role = "melee" },
    [73] = { name = "防护", role = "tank" },
    -- 圣骑士
    [65] = { name = "神圣", role = "healer" },
    [66] = { name = "防护", role = "tank" },
    [70] = { name = "惩戒", role = "melee" },
    -- 猎人
    [253] = { name = "兽王", role = "ranged" },
    [254] = { name = "射击", role = "ranged" },
    [255] = { name = "生存", role = "ranged" },
    -- 潜行者
    [259] = { name = "刺杀", role = "melee" },
    [260] = { name = "战斗", role = "melee" },
    [261] = { name = "敏锐", role = "melee" },
    -- 牧师
    [256] = { name = "戒律", role = "healer" },
    [257] = { name = "神圣", role = "healer" },
    [258] = { name = "暗影", role = "ranged" },
    -- 死亡骑士
    [250] = { name = "鲜血", role = "tank" },
    [251] = { name = "冰霜", role = "melee" },
    [252] = { name = "邪恶", role = "melee" },
    -- 萨满
    [262] = { name = "元素", role = "ranged" },
    [263] = { name = "增强", role = "melee" },
    [264] = { name = "恢复", role = "healer" },
    -- 法师
    [62] = { name = "奥术", role = "ranged" },
    [63] = { name = "火焰", role = "ranged" },
    [64] = { name = "冰霜", role = "ranged" },
    -- 术士
    [265] = { name = "痛苦", role = "ranged" },
    [266] = { name = "恶魔", role = "ranged" },
    [267] = { name = "毁灭", role = "ranged" },
    -- 德鲁伊
    [102] = { name = "平衡", role = "ranged" },
    [103] = { name = "野性", role = "melee" },
    [104] = { name = "野性", role = "tank" },
    [105] = { name = "恢复", role = "healer" },
}

local rosterData = {}           -- [name] = { name, class, unit, guid, specName, specRole, source, isInspected, ... }
local inspectQueue = {}         -- 待视距内 inspect 的 unit 列表
local currentInspectUnit = nil
local currentInspectTime = 0
local isScanning = false

-- 提取纯角色名 (去除服务器后缀)
local function GetCleanPlayerName(fullName)
    if not fullName then return nil end
    local clean = string.match(tostring(fullName), "^([^-]+)")
    return clean or fullName
end

-- 初始化本地跨会话持久化专精记忆池 (SavedVariables)
local function GetPersistentCache()
    BiaoGe = BiaoGe or {}
    BiaoGe.RaidCompCache = BiaoGe.RaidCompCache or {}
    return BiaoGe.RaidCompCache
end

local function SavePersistentSpec(name, class, specName, role, source)
    if not name or name == "" or not specName or specName == "" or specName == "未知" then return end
    local cache = GetPersistentCache()
    cache[name] = {
        class = class,
        specName = specName,
        specRole = role,
        source = source or "inspect",
        updateTime = time(),
    }
end

-- 获取团队成员总数 (全版本无死角兼容：团队API + 小队API + UnitExists兜底)
local function GetRosterMemberCount()
    if IsInRaid and IsInRaid() then
        if GetNumGroupMembers and GetNumGroupMembers() > 0 then return GetNumGroupMembers() end
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then return GetNumRaidMembers() end
        for i = 40, 1, -1 do
            if (GetRaidRosterInfo and GetRaidRosterInfo(i)) or UnitExists("raid" .. i) then return i end
        end
    end
    if IsInGroup and IsInGroup() then
        if GetNumGroupMembers and GetNumGroupMembers() > 0 then return GetNumGroupMembers() end
        if GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then return GetNumSubgroupMembers() + 1 end
        if GetNumPartyMembers and GetNumPartyMembers() > 0 then return GetNumPartyMembers() + 1 end
        for i = 4, 1, -1 do
            if UnitExists("party" .. i) then return i + 1 end
        end
        return 2
    end
    if UnitExists and UnitExists("party1") then
        for i = 4, 1, -1 do
            if UnitExists("party" .. i) then return i + 1 end
        end
    end
    if UnitExists and UnitExists("raid1") then
        for i = 40, 1, -1 do
            if UnitExists("raid" .. i) then return i end
        end
    end
    return 1
end

-- 怀旧服安全职业查询函数 (防止 UnitClass 传入非合法 UnitId 时报错崩溃)
local function SafeUnitClass(unitOrName)
    if not unitOrName or unitOrName == "" then return nil end
    local ok, name, file = pcall(UnitClass, unitOrName)
    if ok and file then return file end
    return nil
end

-- 根据玩家名字逆向查找合法的 UnitToken (支持小队与团队全映射)
local function FindUnitTokenByName(name)
    if not name or name == "" then return nil end
    local clean = GetCleanPlayerName(name)
    local pName = UnitName("player")
    if pName and GetCleanPlayerName(pName) == clean then return "player" end
    for i = 1, 40 do
        local rUnit = "raid" .. i
        if UnitExists(rUnit) and GetCleanPlayerName(UnitName(rUnit)) == clean then
            return rUnit
        end
    end
    for i = 1, 4 do
        local pUnit = "party" .. i
        if UnitExists(pUnit) and GetCleanPlayerName(UnitName(pUnit)) == clean then
            return pUnit
        end
    end
    return nil
end

-- 全口径团队花名册收集器 (第一优先级：直接继承上面团队阵容已成功读出的真实成员名单)
local function GetAllGroupMembers(externalList, externalClasses)
    local members = {}
    local seen = {}

    -- 优先级 1：直接继承外部传入或上层团队工具（RaidTool.currentRosterList）已成功读出的阵容！
    local sourceList = externalList or (RaidTool and RaidTool.currentRosterList)
    local sourceClasses = externalClasses or (RaidTool and RaidTool.currentRosterClasses)
    if sourceList and next(sourceList) then
        local myName = GetCleanPlayerName(UnitName("player"))
        for idx = 1, 40 do
            local rawName = sourceList[idx]
            if rawName and rawName ~= "" then
                local cleanName = GetCleanPlayerName(rawName)
                if not seen[cleanName] then
                    seen[cleanName] = true
                    local token = FindUnitTokenByName(cleanName)
                    local isSelf = (cleanName == myName) or (rawName == myName)
                    local unit = isSelf and "player" or token
                    local cls = (sourceClasses and sourceClasses[idx]) or (unit and SafeUnitClass(unit)) or SafeUnitClass(cleanName) or "WARRIOR"
                    local guid = (unit and UnitExists(unit) and UnitGUID(unit)) or nil
                    tinsert(members, {
                        unit = unit,
                        name = cleanName,
                        fullName = rawName,
                        class = cls,
                        guid = guid,
                        subgroup = math.floor((idx - 1) / 5) + 1,
                    })
                end
            end
        end
        if #members > 0 then
            return members
        end
    end

    -- 优先级 2：自身玩家绝对保底（无论何时自身必须在队）
    local pName = UnitName("player")
    if pName and pName ~= "" then
        local shortSelf = GetCleanPlayerName(pName)
        seen[shortSelf] = true
        tinsert(members, {
            unit = "player",
            name = shortSelf,
            fullName = pName,
            class = SafeUnitClass("player") or "WARRIOR",
            guid = UnitGUID("player"),
            subgroup = 1,
        })
    end

    local memberCount = GetRosterMemberCount()
    local inRaid = (IsInRaid and IsInRaid()) or (GetRaidRosterInfo and GetRaidRosterInfo(1) ~= nil) or (memberCount > 5)

    -- 团队模式扫描
    if inRaid then
        local raidLimit = math.max(memberCount, 40)
        for i = 1, raidLimit do
            local rName, rank, subgroup, level, className, classFileName = GetRaidRosterInfo(i)
            local unitToken = "raid" .. i
            local name = rName or (UnitExists(unitToken) and UnitName(unitToken))
            if name and name ~= "" then
                local shortName = GetCleanPlayerName(name)
                if not seen[shortName] then
                    seen[shortName] = true
                    local cls = classFileName or (UnitExists(unitToken) and SafeUnitClass(unitToken)) or SafeUnitClass(name) or "WARRIOR"
                    local guid = (UnitExists(unitToken) and UnitGUID(unitToken)) or nil
                    tinsert(members, {
                        unit = unitToken,
                        name = shortName,
                        fullName = name,
                        class = cls,
                        guid = guid,
                        subgroup = subgroup or 1,
                    })
                end
            end
        end
    end

    -- 小队模式扫描
    local partyLimit = 4
    if GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then
        partyLimit = math.max(partyLimit, GetNumSubgroupMembers())
    end
    for i = 1, partyLimit do
        local unitToken = "party" .. i
        if UnitExists(unitToken) then
            local partName = UnitName(unitToken)
            if partName and partName ~= "" then
                local shortName = GetCleanPlayerName(partName)
                if not seen[shortName] then
                    seen[shortName] = true
                    local cls = SafeUnitClass(unitToken) or SafeUnitClass(partName) or "WARRIOR"
                    local guid = UnitGUID(unitToken)
                    tinsert(members, {
                        unit = unitToken,
                        name = shortName,
                        fullName = partName,
                        class = cls,
                        guid = guid,
                        subgroup = 1,
                    })
                end
            end
        end
    end

    return members
end

-- 智能角色职责与职业常识推测 (Smart Fallback - 100% 安全无报错)
local function SmartInferSpecAndRole(unit, class)
    class = class or "WARRIOR"
    local assignedRole = nil

    -- 仅当 unit 真实有效存在时，才尝试调用暴雪职责 API，并以 pcall 安全沙箱完全包裹
    if unit and UnitExists(unit) then
        pcall(function()
            if UnitGroupRolesAssigned then
                assignedRole = UnitGroupRolesAssigned(unit)
            end
            if not assignedRole or assignedRole == "NONE" then
                if GetPartyAssignment then
                    if GetPartyAssignment("MAINTANK", unit) then
                        assignedRole = "TANK"
                    elseif GetPartyAssignment("MAINASSIST", unit) then
                        assignedRole = "HEALER"
                    end
                end
            end
        end)
    end

    if assignedRole == "TANK" then
        if class == "WARRIOR" then return "防护", "tank" end
        if class == "PALADIN" then return "防护", "tank" end
        if class == "DEATHKNIGHT" then return "鲜血", "tank" end
        if class == "DRUID" then return "野性", "tank" end
    elseif assignedRole == "HEALER" then
        if class == "PRIEST" then return "戒律", "healer" end
        if class == "PALADIN" then return "神圣", "healer" end
        if class == "SHAMAN" then return "恢复", "healer" end
        if class == "DRUID" then return "恢复", "healer" end
    end

    -- 纯 DPS 与各职业标准专精推测 (常识判定，保证全员 100% 分配到合适角色)
    if class == "ROGUE" then return "战斗", "melee" end
    if class == "MAGE" then return "火焰", "ranged" end
    if class == "WARLOCK" then return "恶魔", "ranged" end
    if class == "HUNTER" then return "生存", "ranged" end
    if class == "WARRIOR" then return "狂暴", "melee" end
    if class == "DEATHKNIGHT" then return "冰霜", "melee" end
    if class == "PALADIN" then return "惩戒", "melee" end
    if class == "SHAMAN" then return "增强", "melee" end
    if class == "DRUID" then return "平衡", "ranged" end
    if class == "PRIEST" then return "暗影", "ranged" end

    return "待定", "melee"
end

-- 1. NoWCL 数据源检测 (网易国服 WCL 插件运行时与数据库)
local function TryGetSpecFromNoWCL(name, guid, class)
    local clean = GetCleanPlayerName(name)
    local candidates = { name, clean }

    -- 运行时 NoWCL.Readiness
    if _G.NoWCL and _G.NoWCL.Readiness then
        local rd = _G.NoWCL.Readiness
        if type(rd.GetSpecializationEvidence) == "function" then
            for _, cand in ipairs(candidates) do
                local ok, ev = pcall(rd.GetSpecializationEvidence, rd, cand, guid)
                if ok and ev and ev.specId and SPEC_ID_MAP[ev.specId] then
                    local s = SPEC_ID_MAP[ev.specId]
                    return s.name, s.role, "NoWCL", ev.specTalents
                end
            end
        end
        if type(rd.localCache) == "table" then
            for _, cand in ipairs(candidates) do
                local ev = rd.localCache[cand]
                if ev and ev.specId and SPEC_ID_MAP[ev.specId] then
                    local s = SPEC_ID_MAP[ev.specId]
                    return s.name, s.role, "NoWCL", ev.specTalents
                end
            end
        end
    end

    -- 本地持久化 NoWCLDB.readinessCache
    if _G.NoWCLDB and type(_G.NoWCLDB.readinessCache) == "table" then
        local rc = _G.NoWCLDB.readinessCache
        for _, cand in ipairs(candidates) do
            local ev = rc[cand]
            if ev and ev.specId and SPEC_ID_MAP[ev.specId] then
                local s = SPEC_ID_MAP[ev.specId]
                return s.name, s.role, "NoWCL", ev.specTalents
            end
            if ev and ev.specTalents and type(ev.specTalents) == "string" and class and SPEC_INFO[class] then
                local p1, p2, p3 = string.match(ev.specTalents, "(%d+)/(%d+)/(%d+)")
                p1, p2, p3 = tonumber(p1) or 0, tonumber(p2) or 0, tonumber(p3) or 0
                local maxP, bestI = -1, 1
                if p1 > maxP then maxP = p1; bestI = 1 end
                if p2 > maxP then maxP = p2; bestI = 2 end
                if p3 > maxP then maxP = p3; bestI = 3 end
                if maxP > 0 and SPEC_INFO[class][bestI] then
                    local s = SPEC_INFO[class][bestI]
                    return s.name, s.role, "NoWCL", ev.specTalents
                end
            end
        end
    end

    return nil
end

-- 2. TalentEmuX 数据源检测 (网易有爱/爱不易天赋模拟器与网络通信)
local function TryGetSpecFromTalentEmu(name, guid, class)
    local meta = _G and rawget(_G, "__ala_meta__")
    local emu = meta and meta.emu
    if not emu or not emu.VT or not emu.VT.TQueryCache then return nil end

    local clean = GetCleanPlayerName(name)
    local candidates = { name, clean }
    local cache = nil
    for _, cand in ipairs(candidates) do
        if emu.VT.TQueryCache[cand] then
            cache = emu.VT.TQueryCache[cand]
            break
        end
    end

    if cache and cache.TalData and (cache.class or class) then
        local targetClass = cache.class or class
        local talData = cache.TalData
        local active = tonumber(talData.active) or 1
        local data = talData[active] or talData[1]
        local countTreePoints = emu.MT and emu.MT.CountTreePoints
        if data and type(countTreePoints) == "function" then
            local ok, rawPoints = pcall(countTreePoints, data, targetClass)
            if ok and type(rawPoints) == "table" and #rawPoints >= 3 then
                local p1, p2, p3 = tonumber(rawPoints[1]) or 0, tonumber(rawPoints[2]) or 0, tonumber(rawPoints[3]) or 0
                local maxP, bestI = -1, 1
                if p1 > maxP then maxP = p1; bestI = 1 end
                if p2 > maxP then maxP = p2; bestI = 2 end
                if p3 > maxP then maxP = p3; bestI = 3 end
                if maxP > 0 and SPEC_INFO[targetClass] and SPEC_INFO[targetClass][bestI] then
                    local s = SPEC_INFO[targetClass][bestI]
                    return s.name, s.role, "TalentEmu", string.format("%d/%d/%d", p1, p2, p3)
                end
            end
        end
    end

    -- 若未命中，向该队员发起静默远程跨地图天赋查询
    if emu.MT and type(emu.MT.SendQueryRequest) == "function" then
        pcall(emu.MT.SendQueryRequest, clean or name, nil, false, false, true, false, false)
    end

    return nil
end

-- 3. Details! 数据源检测 (战斗统计专精与缓存)
local function TryGetSpecFromDetails(guid, name, class)
    if not _G.Details then return nil end
    if guid and _G.Details.cached_specs and _G.Details.cached_specs[guid] then
        local specId = _G.Details.cached_specs[guid]
        if SPEC_ID_MAP[specId] then
            local s = SPEC_ID_MAP[specId]
            return s.name, s.role, "Details", nil
        end
    end
    if guid and type(_G.Details.GetSpecByGUID) == "function" then
        local ok, specId = pcall(_G.Details.GetSpecByGUID, _G.Details, guid)
        if ok and specId and SPEC_ID_MAP[specId] then
            local s = SPEC_ID_MAP[specId]
            return s.name, s.role, "Details", nil
        end
    end
    return nil
end

-- 4. LibGroupInSpecT 数据源检测 (WeakAuras/Cell/MRT/163UI 共享通信网)
local function TryGetSpecFromLGIST(guid, class)
    local lgist = LibStub and LibStub("LibGroupInSpecT-1.1", true)
    if guid and lgist and lgist.GetCachedInfo then
        local cInfo = lgist:GetCachedInfo(guid)
        if cInfo and cInfo.spec_name and cInfo.spec_name ~= "" then
            local role = (cInfo.spec_role == "TANK") and "tank" or ((cInfo.spec_role == "HEALER") and "healer" or "melee")
            if cInfo.spec_role == "DAMAGER" and (class == "MAGE" or class == "WARLOCK" or class == "HUNTER" or (class == "DRUID" and cInfo.spec_name == "平衡") or (class == "PRIEST" and cInfo.spec_name == "暗影") or (class == "SHAMAN" and cInfo.spec_name == "元素")) then
                role = "ranged"
            end
            return cInfo.spec_name, role, "跨插件通信", nil
        end
    end
    return nil
end

-- 5. tdInspect 数据源检测 (远程观察插件数据库)
local function TryGetSpecFromTDInspect(name, guid, class)
    local td = _G.TDDB_INSPECT2
    if not td then return nil end
    local userCache = td.userCache or (td.global and td.global.userCache)
    if not userCache then return nil end

    local clean = GetCleanPlayerName(name)
    local entry = userCache[name] or (clean and userCache[clean])
    if not entry and clean then
        for k, v in pairs(userCache) do
            if string.find(k, "^" .. clean) then
                entry = v
                break
            end
        end
    end

    if entry and entry.talents and type(entry.talents) == "table" and class then
        local act = entry.activeGroup or 1
        local tStr = entry.talents[act] or entry.talents[1]
        local addon = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("tdInspect", true)
        if addon and addon.ResolveTalent and type(tStr) == "string" then
            local ok, res = pcall(addon.ResolveTalent, addon, class, tStr)
            if ok and type(res) == "string" and res ~= "" then
                return res, "melee", "tdInspect", nil
            end
        end
    end
    return nil
end

-- 6. 持久化历史记忆池检测
local function TryGetSpecFromPersistentCache(name)
    local pCache = GetPersistentCache()
    local clean = GetCleanPlayerName(name)
    local entry = pCache[name] or (clean and pCache[clean])
    if entry and entry.specName and entry.specName ~= "" and entry.specName ~= "未知" then
        return entry.specName, entry.specRole or "melee", "历史记忆", nil
    end
    return nil
end

-- 怀旧服安全天赋投入点数查询函数 (解决各版本返回值偏移与 string 比较崩溃)
local function SafeGetTalentPoints(tabIndex, isInspect)
    if not GetTalentTabInfo then return 0, "" end
    -- WLK Classic (3.4.x / 4.4.x):
    -- id, name, description, iconTexture, pointsSpent, background, previewPointsSpent, isUnlocked = GetTalentTabInfo(...)
    local ok, id, name, desc, icon, points = pcall(GetTalentTabInfo, tabIndex, isInspect)
    if not ok then return 0, "" end
    local pts = tonumber(points)
    if not pts then
        if type(desc) == "number" then
            pts = desc
        else
            pts = 0
        end
    end
    return pts, (type(name) == "string" and name or "")
end

-- 多源专精解析裁决器：支持传入 member 对象或 unitToken，按优先级综合裁决，超视距全员 0 延迟秒级装配
local function ResolveUnitSpecMultiSource(memberOrUnit)
    if not memberOrUnit then return nil end

    local ok, res = pcall(function()
        local name, class, unit, guid
        if type(memberOrUnit) == "table" then
            name = memberOrUnit.name
            class = memberOrUnit.class
            unit = memberOrUnit.unit
            guid = memberOrUnit.guid or (unit and UnitExists(unit) and UnitGUID(unit))
        else
            unit = memberOrUnit
            if not UnitExists(unit) then return nil end
            name = GetCleanPlayerName(UnitName(unit))
            class = SafeUnitClass(unit)
            guid = UnitGUID(unit)
        end

        if not name or name == "" then return nil end

        -- 若职业未确定，尝试通过单位或名字补齐
        if not class or class == "" then
            if unit and UnitExists(unit) then
                class = SafeUnitClass(unit)
            end
            if not class then
                class = SafeUnitClass(name)
            end
        end
        class = class or "WARRIOR"

        -- 1. 玩家自身：直接调用原生 API 100% 准确获取
        local pName = UnitName("player")
        local myName = pName and GetCleanPlayerName(pName)
        if unit == "player" or name == myName or (guid and guid == UnitGUID("player")) then
            local bestTab, maxPoints = 1, -1
            local tabPoints = {}
            for i = 1, 3 do
                local pts, tabName = SafeGetTalentPoints(i, false)
                tabPoints[i] = pts
                if pts > maxPoints then
                    maxPoints = pts
                    bestTab = i
                end
            end
            local sName = (SPEC_INFO[class] and SPEC_INFO[class][bestTab]) and SPEC_INFO[class][bestTab].name or "未知"
            local sRole = (SPEC_INFO[class] and SPEC_INFO[class][bestTab]) and SPEC_INFO[class][bestTab].role or "melee"
            SavePersistentSpec(name, class, sName, sRole, "自己")
            return {
                name = name, class = class, unit = "player", guid = UnitGUID("player"),
                specName = sName, specRole = sRole, source = "自己",
                isInspected = true, isEstimated = false, points = table.concat(tabPoints, "/"),
            }
        end

        -- 2. 依次查询外部插件接口 (NoWCL -> TalentEmu -> Details -> LGIST -> tdInspect -> 本地历史记忆)
        local sName, sRole, sourceTag, pts

        pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromNoWCL(name, guid, class) end)
        if not sName then pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromTalentEmu(name, guid, class) end) end
        if not sName then pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromDetails(guid, name, class) end) end
        if not sName then pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromLGIST(guid, class) end) end
        if not sName then pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromTDInspect(name, guid, class) end) end
        if not sName then pcall(function() sName, sRole, sourceTag, pts = TryGetSpecFromPersistentCache(name) end) end

        if sName then
            SavePersistentSpec(name, class, sName, sRole, sourceTag)
            return {
                name = name, class = class, unit = unit, guid = guid,
                specName = sName, specRole = sRole, source = sourceTag,
                isInspected = true, isEstimated = false, points = pts,
            }
        end

        -- 3. 终极职责与职业常识智能推测 (绝对不留白、不报“未找到”，确保全团 100% 具备专精)
        local inferSpec, inferRole = SmartInferSpecAndRole(unit, class)
        return {
            name = name, class = class, unit = unit, guid = guid,
            specName = inferSpec, specRole = inferRole, source = "职责推导",
            isInspected = true, isEstimated = true, points = nil,
        }
    end)

    if ok and res then
        return res
    else
        local n = (type(memberOrUnit) == "table" and memberOrUnit.name) or "队员"
        local c = (type(memberOrUnit) == "table" and memberOrUnit.class) or "WARRIOR"
        local inferSpec, inferRole = SmartInferSpecAndRole(nil, c)
        return {
            name = n, class = c, unit = nil, guid = nil,
            specName = inferSpec or "待定", specRole = inferRole or "melee", source = "智能兜底",
            isInspected = true, isEstimated = true, points = nil,
        }
    end
end

-- 解析原生 Inspect 回调 (视距内校准)
local function ParseInspectTalents(unit)
    if not unit or not UnitExists(unit) then return nil end
    local name = GetCleanPlayerName(UnitName(unit))
    local class = SafeUnitClass(unit)
    local guid = UnitGUID(unit)
    if not name or not class then return nil end

    local bestTab, maxPoints = 1, -1
    local tabPoints = {}

    for i = 1, 3 do
        local pts, tabName = SafeGetTalentPoints(i, true)
        tabPoints[i] = pts
        if pts > maxPoints then
            maxPoints = pts
            bestTab = i
        end
    end

    local specName = (SPEC_INFO[class] and SPEC_INFO[class][bestTab]) and SPEC_INFO[class][bestTab].name or "未知"
    local role = (SPEC_INFO[class] and SPEC_INFO[class][bestTab]) and SPEC_INFO[class][bestTab].role or "melee"

    if class == "DRUID" and bestTab == 2 then
        specName = "野性"
    end

    SavePersistentSpec(name, class, specName, role, "实时扫描")
    return {
        name = name, class = class, unit = unit, guid = guid,
        specTab = bestTab, specName = specName, specRole = role,
        points = table.concat(tabPoints, "/"), maxPoints = maxPoints,
        isInspected = true, isEstimated = false, source = "实时扫描",
    }
end

-- 原生 Inspect 队列推进器 (仅对视距内且需精确校准的目标发起)
local scannerFrame = CreateFrame("Frame")
scannerFrame:RegisterEvent("INSPECT_READY")
scannerFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
scannerFrame:RegisterEvent("PARTY_LEADER_CHANGED")
scannerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scannerFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(function() scannerFrame:RegisterEvent("RAID_ROSTER_UPDATE") end)
pcall(function() scannerFrame:RegisterEvent("CHAT_MSG_ADDON") end)

local function ProcessNextInspect()
    if #inspectQueue == 0 then
        isScanning = false
        currentInspectUnit = nil
        RaidComp.OnRosterUpdated()
        return
    end

    currentInspectUnit = tremove(inspectQueue, 1)
    if not currentInspectUnit or not UnitExists(currentInspectUnit) then
        ProcessNextInspect()
        return
    end

    -- 严格限制：只有视距内(~28码)才发起 NotifyInspect，绝不对超距队友盲目发起造成卡死
    if CanInspect and CanInspect(currentInspectUnit) and CheckInteractDistance(currentInspectUnit, 1) then
        currentInspectTime = GetTime()
        pcall(NotifyInspect, currentInspectUnit)
    else
        C_Timer.After(0.05, ProcessNextInspect)
    end
end

scannerFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "INSPECT_READY" then
        if currentInspectUnit and UnitExists(currentInspectUnit) then
            local info = ParseInspectTalents(currentInspectUnit)
            if info and info.isInspected then
                rosterData[info.name] = info
            end
            currentInspectUnit = nil
            C_Timer.After(0.15, ProcessNextInspect)
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RaidComp.StartScan(false)
    elseif event == "CHAT_MSG_ADDON" and arg1 == "BGLitePlus_Spec" then
        -- 接收来自其他安装了 BGLite_Plus 队员的专精广播
        if arg2 and arg4 then
            local pName, pClass, pSpec, pRole = strsplit(",", arg2)
            if pName and pSpec and pSpec ~= "" then
                SavePersistentSpec(pName, pClass, pSpec, pRole, "BGLitePlus")
                if rosterData[pName] then
                    rosterData[pName].specName = pSpec
                    rosterData[pName].specRole = pRole or rosterData[pName].specRole
                    rosterData[pName].isInspected = true
                    rosterData[pName].source = "插件互联"
                    RaidComp.OnRosterUpdated()
                end
            end
        end
    end
end)

-- 广播自己专精到队伍
local function BroadcastMySpec()
    if not IsInGroup() and not IsInRaid() then return end
    local myInfo = ResolveUnitSpecMultiSource("player")
    if myInfo and myInfo.specName then
        pcall(function()
            C_ChatInfo.RegisterAddonMessagePrefix("BGLitePlus_Spec")
            local channel = IsInRaid() and "RAID" or "PARTY"
            local payload = format("%s,%s,%s,%s", myInfo.name, myInfo.class, myInfo.specName, myInfo.specRole)
            C_ChatInfo.SendAddOnMessage("BGLitePlus_Spec", payload, channel)
        end)
    end
end

-- 挂载 LibGroupInSpecT-1.1 回调
local function HookLibGroupInSpecT()
    local lgist = LibStub and LibStub("LibGroupInSpecT-1.1", true)
    if lgist and not RaidComp.hasHookedLGIST then
        RaidComp.hasHookedLGIST = true
        lgist.RegisterCallback(RaidComp, "GroupInSpecT_Update", function(event, guid, unit, info)
            if info and info.name and info.spec_name and info.spec_name ~= "" then
                local role = (info.spec_role == "TANK") and "tank" or ((info.spec_role == "HEALER") and "healer" or "melee")
                if info.spec_role == "DAMAGER" and (info.class == "MAGE" or info.class == "WARLOCK" or info.class == "HUNTER") then
                    role = "ranged"
                end
                SavePersistentSpec(info.name, info.class, info.spec_name, role, "LGIST")
                if rosterData[info.name] then
                    rosterData[info.name].specName = info.spec_name
                    rosterData[info.name].specRole = role
                    rosterData[info.name].isInspected = true
                    rosterData[info.name].source = "跨插件通信"
                    RaidComp.OnRosterUpdated()
                end
            end
        end)
    end
end

-- 超时看门狗 (0.8秒未返回即推进，避免任何UI卡顿)
C_Timer.NewTicker(0.4, function()
    if isScanning and currentInspectUnit then
        if GetTime() - currentInspectTime > 0.8 then
            currentInspectUnit = nil
            ProcessNextInspect()
        end
    end
end)

-- 触发全团扫描与多源装配
function RaidComp.StartScan(force, externalList, externalClasses)
    HookLibGroupInSpecT()
    BroadcastMySpec()

    local members = GetAllGroupMembers(externalList, externalClasses)

    -- 建立当前存活名单索引
    local activeNames = {}
    for _, m in ipairs(members) do
        if m.name and m.name ~= "" then
            activeNames[m.name] = true
        end
    end

    -- 清理已离队人员 (防御性保护：当且仅当 members > 0 时清理，防止瞬态事件把全团清空为0人)
    if #members > 0 then
        for name in pairs(rosterData) do
            if not activeNames[name] then
                rosterData[name] = nil
            end
        end
    end

    -- 第一步：多源快速检索装配全员 (NoWCL + TalentEmu + Details + LGIST + tdInspect + 历史记忆 + 智能推导)
    -- 此步 0 延迟瞬间全部装配完成，无论队员是否在附近，100% 具备专精与角色！
    wipe(inspectQueue)
    for _, m in ipairs(members) do
        local n = m.name
        if n and n ~= "" then
            if force or not rosterData[n] or not rosterData[n].isInspected then
                local resolved = ResolveUnitSpecMultiSource(m)
                if resolved then
                    rosterData[n] = resolved
                end
                -- 仅当该成员是推测状态、且当前恰好在视距内时，才排队进行近距离高精校准
                if resolved and resolved.isEstimated and m.unit and UnitExists(m.unit) and CheckInteractDistance and CheckInteractDistance(m.unit, 1) then
                    tinsert(inspectQueue, m.unit)
                end
            end
        end
    end

    -- 第二步：若有符合条件的近距离人员，启动近距离精确校准
    if #inspectQueue > 0 then
        isScanning = true
        ProcessNextInspect()
    else
        isScanning = false
        currentInspectUnit = nil
    end

    RaidComp.OnRosterUpdated()
end



--------------------------------------------------------------------------------
-- 4. 团队阵容统计与 Buff 缺口矩阵计算 (Coverage Calculation)
--------------------------------------------------------------------------------
function RaidComp.GetRosterStats()
    local total = 0
    local tanks = 0
    local healers = 0
    local melees = 0
    local rangeds = 0
    local inspectedCount = 0

    for _, m in pairs(rosterData) do
        total = total + 1
        if m.isInspected then
            inspectedCount = inspectedCount + 1
        end
        if m.specRole == "tank" then
            tanks = tanks + 1
        elseif m.specRole == "healer" then
            healers = healers + 1
        elseif m.specRole == "melee" then
            melees = melees + 1
        elseif m.specRole == "ranged" then
            rangeds = rangeds + 1
        end
    end

    return {
        total = total,
        tanks = tanks,
        healers = healers,
        melees = melees,
        rangeds = rangeds,
        inspectedCount = inspectedCount,
        isScanning = isScanning,
    }
end

-- 检查某个增益在当前阵容中是否覆盖
function RaidComp.EvaluateBuff(buffDef)
    if buffDef.customCheck then
        local isCovered, providers, note = buffDef.customCheck(rosterData)
        return isCovered, providers, note
    end

    local providers = {}
    for _, m in pairs(rosterData) do
        for _, req in ipairs(buffDef.providers or {}) do
            if m.class == req.class then
                if not req.spec or m.specName == req.spec or not m.isInspected then
                    local descText = m.name .. " (" .. (m.specName or "待测") .. ")"
                    tinsert(providers, descText)
                    break
                end
            end
        end
    end

    local isCovered = (#providers > 0)
    return isCovered, providers, isCovered and "已覆盖" or "缺失"
end

-- 获取全量 Buff 计算诊断结果
function RaidComp.GetFullBuffDiagnostics()
    local coveredList = {}
    local missingList = {}
    local categoryResults = {}

    for _, cat in ipairs(RaidComp.BUFF_CATEGORIES) do
        categoryResults[cat.id] = {
            id = cat.id,
            name = cat.name,
            total = 0,
            covered = 0,
            items = {},
        }
    end

    for _, buffDef in ipairs(RaidComp.BUFF_DEFINITIONS) do
        local isCovered, providers, note = RaidComp.EvaluateBuff(buffDef)
        local itemResult = {
            def = buffDef,
            isCovered = isCovered,
            providers = providers,
            note = note,
        }

        if isCovered then
            tinsert(coveredList, itemResult)
        else
            tinsert(missingList, itemResult)
        end

        local cat = categoryResults[buffDef.category]
        if cat then
            cat.total = cat.total + 1
            if isCovered then cat.covered = cat.covered + 1 end
            tinsert(cat.items, itemResult)
        end
    end

    -- 智能计算性价比最高的补充职业建议 (Top Recommendations)
    local specWeights = {}
    for _, mItem in ipairs(missingList) do
        for _, req in ipairs(mItem.def.providers or {}) do
            local key = req.class .. (req.spec and ("-" .. req.spec) or "")
            specWeights[key] = (specWeights[key] or 0) + 1
        end
    end

    local recommendations = {}
    for key, count in pairs(specWeights) do
        tinsert(recommendations, { specKey = key, count = count })
    end
    table.sort(recommendations, function(a, b) return a.count > b.count end)

    return {
        totalBuffs = #RaidComp.BUFF_DEFINITIONS,
        coveredCount = #coveredList,
        missingCount = #missingList,
        coveredList = coveredList,
        missingList = missingList,
        categoryResults = categoryResults,
        recommendations = recommendations,
    }
end

--------------------------------------------------------------------------------
-- 5. 频道通报与推广信息引擎 (Channel Report Engine)
--------------------------------------------------------------------------------
function RaidComp.SendReportToChat(targetChannel)
    targetChannel = targetChannel or "RAID"

    if targetChannel == "RAID" and not IsInRaid() then
        targetChannel = IsInGroup() and "PARTY" or "SAY"
    elseif targetChannel == "PARTY" and not IsInGroup() then
        targetChannel = "SAY"
    end

    local stats = RaidComp.GetRosterStats()
    local diag = RaidComp.GetFullBuffDiagnostics()

    local function SanitizeChatMessage(msg)
        if not msg then return "" end
        msg = tostring(msg)
        -- 去除所有内嵌的颜色代码 |cXXXXXXXX 与 |r
        msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        -- 去除超链接 |H...|h 与 |h
        msg = msg:gsub("|H.-|h", ""):gsub("|h", "")
        -- 去除内嵌材质图标 |T...|t
        msg = msg:gsub("|T.-|t", "")
        -- 核心防御：魔兽聊天引擎中单独的 | 是转义起始符，若未成对或无效会触发 Invalid escape code
        -- 将任何剩余的单个管道符替换为 '/'
        msg = msg:gsub("|", "/")
        return msg
    end

    local lines = {}
    local promo = RaidComp.PROMO_TEXT or ">>> 来自 [BGLite PLUS] 团队阵容助手 - 作者: 波比兔 (网易DD平台搜索: BGlite PLUS 下载)"

    -- 1. 团队人数与阵容概况
    tinsert(lines, format("【BGLite PLUS】团队阵容与增益诊断 (%d人 / 坦:%d 奶:%d 近:%d 远:%d)",
        stats.total, stats.tanks, stats.healers, stats.melees, stats.rangeds))

    -- 2. 核心增益覆盖状态
    if diag.missingCount == 0 then
        tinsert(lines, format("[全团齐备] 全团 %d 项核心 Buff/Debuff 已 100%% 完美覆盖，无任何缺口！", diag.totalBuffs))
    else
        -- 罗列缺失的关键 Buff (最多列 4 项，避免单行超长)
        local missStr = ""
        local showCount = math.min(#diag.missingList, 4)
        for i = 1, showCount do
            local item = diag.missingList[i]
            local sep = (i == showCount) and "" or ", "
            missStr = missStr .. "[" .. item.def.shortName .. ":" .. (item.def.needSpec or "") .. "]" .. sep
        end
        if #diag.missingList > 4 then
            missStr = missStr .. " 等" .. #diag.missingList .. "项"
        end
        tinsert(lines, "[缺失增益] " .. missStr)

        -- 3. 推荐招募职业
        local recStr = ""
        if #diag.recommendations > 0 then
            for i = 1, math.min(#diag.recommendations, 3) do
                local rec = diag.recommendations[i]
                local cls, spc = strsplit("-", rec.specKey)
                local clsName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
                local full = (spc and spc ~= "") and (spc .. clsName) or clsName
                recStr = recStr .. full .. "(补" .. rec.count .. "项) "
            end
        end

        if recStr ~= "" then
            tinsert(lines, "[建议招募] " .. recStr)
        end
    end

    -- 4. 推广信息尾缀 (包含作者波比兔与网易DD平台下载指引)
    tinsert(lines, promo)

    -- 逐行安全延时发送到聊天频道 (间隔设为 0.5 秒，彻底避开暴雪客户端聊天 Anti-Spam 吞消息限制)
    for i, line in ipairs(lines) do
        C_Timer.After((i - 1) * 0.5, function()
            local cleanLine = SanitizeChatMessage(line)
            local ok, err = pcall(SendChatMessage, cleanLine, targetChannel)
            if not ok and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[BGLite PLUS 通报失败]|r " .. tostring(err))
            end
        end)
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite PLUS]|r 已成功将阵容与Buff缺口分析通报至 [" .. targetChannel .. "] 频道！")
    end
    BG.PlaySound(1)
end

-- 暴露只读/引用数据池与专精库供 UI 层渲染与交互
RaidComp.rosterData = rosterData
RaidComp.SPEC_INFO = SPEC_INFO

-- 手动调整队员团队职责与专精 (用户自定义调整)
function RaidComp.ManualSetMemberSpecRole(playerName, newSpecName, newRole)
    if not playerName or not rosterData[playerName] then return end
    local m = rosterData[playerName]
    if newSpecName then m.specName = newSpecName end
    if newRole then m.specRole = newRole end
    m.isEstimated = false
    m.source = "手动指定"
    m.isInspected = true

    -- 同步存入持久化缓存，下次进组自动生效
    SavePersistentSpec(playerName, m.class, m.specName, m.specRole, "Manual")

    RaidComp.OnRosterUpdated()
end

-- 广播更新回调
function RaidComp.OnRosterUpdated()
    if RaidComp.UpdateUI then
        RaidComp.UpdateUI()
    end
end

