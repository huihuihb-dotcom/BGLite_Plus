--------------------------------------------------------------------------------
-- BGLite_Plus 战术站位图专属 25 人拟真测试模块 (RaidMock.lua)
-- 作用：在单人/无团队环境下提供即插即拔的 25 人经典奥杜尔开荒拟真队伍数据，
-- 服务于站位图一键入席排布、自身高亮穿透、近战集合组展开与多阶段演变测试。
-- 开关命令: /bgmock (切换开关), /bgmock on (开启), /bgmock off (关闭)
--------------------------------------------------------------------------------
if BG and BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local RaidMock = {}
ns.RaidMock = RaidMock
_G.BGLite_RaidMock = RaidMock

-- 核心热插拔开关 (默认开启，方便您当前随时测试；输入 /bgmock off 即可随时关闭)
RaidMock.enabled = false
RaidMock.forceMock = false -- 无需退队，即便处于任意小队中也会优先采用本套 25 人测试模型

function RaidMock.GetMockRosterData()
    local myName = UnitName("player") or "冰霜波比"
    local _, myClass = UnitClass("player")
    myClass = myClass or "MAGE"

    -- 1. 坦克组 (3人: 覆盖常规 2 坦及议会 3 坦)
    local tanks = {
        { name = "暗夜之拥", class = "DEATHKNIGHT", specName = "血DK", specIcon = "Interface\\Icons\\spell_deathknight_bloodpresence", role = "tank" },
        { name = "圣光庇护", class = "PALADIN",     specName = "防骑", specIcon = "Interface\\Icons\\spell_holy_devotionaura",         role = "tank" },
        
    }

    -- 2. 核心保坦治疗 (2人: 贴紧主副坦安全两翼)
    local tankHealers = {
        { name = "纯白信仰", class = "PALADIN", specName = "奶骑",   specIcon = "Interface\\Icons\\spell_holy_holybolt",         role = "healer", isTankHealer = true },
        { name = "戒律晨曦", class = "PRIEST",  specName = "戒律牧", specIcon = "Interface\\Icons\\spell_holy_powerwordshield",   role = "healer", isTankHealer = true },
    }

    -- 3. 核心团补治疗 (3人: 中场辐射全团)
    local raidHealers = {
        { name = "潮汐图腾", class = "SHAMAN", specName = "奶萨", specIcon = "Interface\\Icons\\spell_nature_magicimmunity", role = "healer" },
        { name = "神圣祈福", class = "PRIEST", specName = "神牧", specIcon = "Interface\\Icons\\spell_holy_guardianspirit", role = "healer" },
        { name = "自然之力", class = "DRUID",  specName = "奶德", specIcon = "Interface\\Icons\\spell_nature_healingtouch",  role = "healer" },
    }

    -- 4. 近战输出组 (6人: 聚合于 [98] 近战组，Boss 正背后脚后跟)
    local melees = {
                { name = "坚如磐石", class = "WARRIOR",     specName = "防战", specIcon = "Interface\\Icons\\ability_warrior_defensivestance", role = "melee" },

        { name = "旋风斩狂", class = "WARRIOR", specName = "狂暴战", specIcon = "Interface\\Icons\\ability_warrior_innerrage", role = "melee" },
        { name = "影步伺机", class = "ROGUE",   specName = "战斗贼", specIcon = "Interface\\Icons\\ability_rogue_eviscerate", role = "melee" },
        { name = "匕首暗杀", class = "ROGUE",   specName = "刺杀贼", specIcon = "Interface\\Icons\\ability_rogue_eviscerate", role = "melee" },
        { name = "十字军裁", class = "PALADIN", specName = "惩戒骑", specIcon = "Interface\\Icons\\spell_holy_auraoflight",   role = "melee" },
        { name = "野性撕咬", class = "DRUID",   specName = "猫德",   specIcon = "Interface\\Icons\\ability_druid_catform",    role = "melee" },
        { name = "风暴打击", class = "SHAMAN",  specName = "增强萨", specIcon = "Interface\\Icons\\spell_shaman_stormstrike", role = "melee" },
    }

    -- 5. 远程输出组 (11人: 南半场大分散，其中包含玩家本人“冰霜波比”)
    local rangeds = {
        -- 玩家本人 (优先采用玩家当前真实名字与法师专精图标，触发战术站位金色高亮光晕！)
        { name = myName,     class = myClass,       specName = "冰法",   specIcon = "Interface\\Icons\\spell_frost_frostbolt02",   role = "ranged" },
        { name = "奥术彗星", class = "MAGE",        specName = "奥法",   specIcon = "Interface\\Icons\\spell_nature_starfall",     role = "ranged" },
        { name = "末日降临", class = "WARLOCK",     specName = "痛苦术", specIcon = "Interface\\Icons\\spell_shadow_haunting",     role = "ranged" },
        { name = "恶魔契约", class = "WARLOCK",     specName = "恶魔术", specIcon = "Interface\\Icons\\spell_shadow_demonicempathy", role = "ranged" },
        { name = "暗影灼烧", class = "WARLOCK",     specName = "毁灭术", specIcon = "Interface\\Icons\\spell_shadow_scourgebuild",   role = "ranged" },
        { name = "虚空之触", class = "PRIEST",      specName = "暗牧",   specIcon = "Interface\\Icons\\spell_shadow_shadowwordpain", role = "ranged" },
        { name = "星落如雨", class = "DRUID",       specName = "鸟德",   specIcon = "Interface\\Icons\\spell_nature_starfall",     role = "ranged" },
        { name = "熔岩爆裂", class = "SHAMAN",      specName = "元萨",   specIcon = "Interface\\Icons\\spell_shaman_lavasurge",     role = "ranged" },
        { name = "鹰眼锁喉", class = "HUNTER",      specName = "生存猎", specIcon = "Interface\\Icons\\ability_hunter_snipershot", role = "ranged" },
        { name = "野兽之心", class = "HUNTER",      specName = "射击猎", specIcon = "Interface\\Icons\\ability_marksmanship",     role = "ranged" },
        { name = "死蛆瘟疫", class = "DEATHKNIGHT", specName = "邪DK",   specIcon = "Interface\\Icons\\spell_deathknight_unholypresence", role = "ranged" },
    }

    return {
        tanks = tanks,
        tankHealers = tankHealers,
        raidHealers = raidHealers,
        melees = melees,
        rangeds = rangeds,
    }
end

-- 优雅外挂代理 (Proxy Hook): 仅在开启仿真且有测试需求时接管，零核心代码侵入
local function HookRaidMapRoster()
    local rMap = ns.RaidMap or _G.RaidMap or (BG and BG.RaidMap)
    if not rMap or not rMap.GetAutoRosterData then return end

    if rMap._orig_GetAutoRosterData then return end
    rMap._orig_GetAutoRosterData = rMap.GetAutoRosterData

    rMap.GetAutoRosterData = function()
        if RaidMock.enabled then
            local num = GetNumGroupMembers()
            if num == 0 or RaidMock.forceMock then
                return RaidMock.GetMockRosterData()
            end
        end
        return rMap._orig_GetAutoRosterData()
    end
end

-- 延迟挂载确保安全
local fHook = CreateFrame("Frame")
fHook:RegisterEvent("PLAYER_LOGIN")
fHook:SetScript("OnEvent", function()
    HookRaidMapRoster()
end)
HookRaidMapRoster()

--------------------------------------------------------------------------------
-- 命令行热插拔支持: /bgmock, /bgmock on, /bgmock off
--------------------------------------------------------------------------------
SLASH_BGLITEMOCK1 = "/bgmock"
SlashCmdList["BGLITEMOCK"] = function(msg)
    msg = msg and string.lower(string.match(msg, "^%s*(.-)%s*$")) or ""
    if msg == "on" or msg == "1" or msg == "true" then
        RaidMock.enabled = true
        RaidMock.forceMock = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 仿真调试]|r 25人黄金开荒团队仿真已【开启】！打开战术站位图点击【同步团队阵容】即可体验全员入席与高亮。")
    elseif msg == "off" or msg == "0" or msg == "false" then
        RaidMock.enabled = false
        RaidMock.forceMock = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[BGLite 仿真调试]|r 团队仿真已【关闭】（已拔出），恢复为仅使用暴雪原生真实团队数据。")
    else
        RaidMock.enabled = not RaidMock.enabled
        RaidMock.forceMock = RaidMock.enabled
        local status = RaidMock.enabled and "|cff00ff00已开启 (仿真团队)|r" or "|cffff4444已关闭 (真实团队)|r"
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 仿真调试]|r 当前状态: %s (输入 /bgmock on 或 /bgmock off 切换)", status))
    end
end
