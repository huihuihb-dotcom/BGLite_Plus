if BG and BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local RaidMap = ns.RaidMap or {}
ns.RaidMap = RaidMap
_G.RaidMap = RaidMap

--------------------------------------------------------------------------------
-- 1. 标准职业图标映射 (零重复定义，全模块共享)
--------------------------------------------------------------------------------
RaidMap.CLASS_ICONS = {
    WARRIOR     = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN     = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER      = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE       = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST      = "Interface\\Icons\\ClassIcon_Priest",
    DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
    SHAMAN      = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE        = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK     = "Interface\\Icons\\ClassIcon_Warlock",
    DRUID       = "Interface\\Icons\\ClassIcon_Druid",
}

--------------------------------------------------------------------------------
-- 2. 战术数据中心 (Registry - 共享全局表存储)
--------------------------------------------------------------------------------
RaidMap.bosses = RaidMap.bosses or {}
RaidMap.bossList = RaidMap.bossList or {}
RaidMap.fbs = RaidMap.fbs or {}
RaidMap.fbOrder = RaidMap.fbOrder or {}

-- 注册副本分类
function RaidMap.RegisterFB(fbKey, fbName)
    if not fbKey then return end
    RaidMap.fbs = RaidMap.fbs or {}
    RaidMap.fbOrder = RaidMap.fbOrder or {}
    if not RaidMap.fbs[fbKey] then
        RaidMap.fbs[fbKey] = {
            key = fbKey,
            name = fbName or fbKey,
            bosses = {},
        }
        table.insert(RaidMap.fbOrder, fbKey)
    end
    return RaidMap.fbs[fbKey]
end

-- 注册 BOSS 战术预设
function RaidMap.RegisterBoss(bossConfig)
    if not bossConfig or not bossConfig.id then return end
    RaidMap.bosses = RaidMap.bosses or {}
    RaidMap.bossList = RaidMap.bossList or {}
    RaidMap.fbs = RaidMap.fbs or {}
    RaidMap.fbOrder = RaidMap.fbOrder or {}

    local fbKey = bossConfig.fb or "GENERAL"
    RaidMap.RegisterFB(fbKey, bossConfig.fbName or fbKey)

    RaidMap.bosses[bossConfig.id] = bossConfig

    local exists = false
    for i, b in ipairs(RaidMap.bossList) do
        if b.id == bossConfig.id then
            RaidMap.bossList[i] = bossConfig
            exists = true
            break
        end
    end
    if not exists then
        table.insert(RaidMap.bossList, bossConfig)
    end

    if RaidMap.fbs[fbKey] then
        local fbExists = false
        for i, b in ipairs(RaidMap.fbs[fbKey].bosses) do
            if b.id == bossConfig.id then
                RaidMap.fbs[fbKey].bosses[i] = bossConfig
                fbExists = true
                break
            end
        end
        if not fbExists then
            table.insert(RaidMap.fbs[fbKey].bosses, bossConfig)
        end
    end
end

-- 获取指定 BOSS 预设
function RaidMap.GetBoss(bossID)
    if not RaidMap.bosses then return nil end
    return RaidMap.bosses[bossID]
end

-- 获取全部 BOSS 列表 (保持线性有序，兼容旧版 BOSS_LIST)
function RaidMap.GetAllBosses()
    return RaidMap.bossList or {}
end

-- 兼容旧版引用
RaidMap.BOSS_LIST = RaidMap.bossList

-- 获取全部注册的副本
function RaidMap.GetRegisteredFBs()
    local list = {}
    for _, k in ipairs(RaidMap.fbOrder or {}) do
        table.insert(list, RaidMap.fbs[k])
    end
    return list
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 3. 智能动态弹性阵型排布引擎 (Dynamic Elastic Tactical Layout Engine)
--------------------------------------------------------------------------------
-- 支持根据实际团队阵容自适应生成点位，彻底杜绝固定假人溢出或缺位；
-- 战术协同：核心保坦治疗（奶骑/戒律牧）自动贴紧坦克安全内圈，近战扇形与远程大分散容量弹性伸缩。
function RaidMap.GenerateDynamicTacticalSpots(cx, cy, opts, rosterData)
    opts = opts or {}
    local spots = {}

    -- 战术基准坐标体系 (正北为顶端/BOSS与坦克方，正南为底端/入口与远程方)
    -- cy = -height/2 + 10 = -270。在 WoW TOPLEFT 坐标系下，Y 越大(更接近 0)越靠近顶部(北)，Y 越小越靠近底部(南)
    local tankY = opts.tankY or 160           -- 坦克在正北靠墙 (cy + 160 = -110)
    local meleeY = opts.meleeY or 35          -- 近战在 BOSS 正背后脚后跟 (cy + 35 = -235，BOSS 位于 cy + 90 = -180)
    local rangedMode = opts.rangedMode or "arc"

    ----------------------------------------------------------------------------
    -- A. 如果没有传入实际团队阵容 (即未组队或单人演示模式)，提供标准 25 人规范架构
    ----------------------------------------------------------------------------
    if not rosterData then
        -- 1. 坦克组 3 人 (正北迎击 BOSS，背靠北墙，使 BOSS 背对全团)
        table.insert(spots, { x = cx, y = cy + tankY, num = "1", role = "tank", name = "主坦-MT", cls = "WARRIOR" })
        table.insert(spots, { x = cx + (opts.tankSpread or 45), y = cy + tankY - 10, num = "2", role = "tank", name = "副坦-OT", cls = "PALADIN" })
        table.insert(spots, { x = cx - (opts.tankSpread or 45), y = cy + tankY - 10, num = "3", role = "tank", name = "换坦-ST", cls = "DEATHKNIGHT" })

        -- 2. 核心保坦治疗 2 人 (紧贴坦克两翼 20~25 码安全内圈，压制/牺牲/道标无死角覆盖，严禁卡射程)
        local thL = opts.tankHealerLeft or { x = -75, y = 125 }
        local thR = opts.tankHealerRight or { x = 75, y = 125 }
        table.insert(spots, { x = cx + thL.x, y = cy + thL.y, num = "4", role = "healer", name = "保坦奶-奶骑", cls = "PALADIN", isTankHealer = true })
        table.insert(spots, { x = cx + thR.x, y = cy + thR.y, num = "5", role = "healer", name = "保坦奶-戒律", cls = "PRIEST",  isTankHealer = true })

        -- 3. 团补治疗 3 人 (居中场内圈，辐射全场近战与后排)
        local rhList = {
            { name = "团补奶-奶萨", cls = "SHAMAN", x = cx - 60, y = cy - 20, num = "6" },
            { name = "团补奶-神牧", cls = "PRIEST", x = cx,      y = cy - 15, num = "7" },
            { name = "团补奶-奶德", cls = "DRUID",  x = cx + 60, y = cy - 20, num = "8" },
        }
        for _, h in ipairs(rhList) do table.insert(spots, { x = h.x, y = h.y, num = h.num, role = "healer", name = h.name, cls = h.cls }) end

        -- 4. 近战输出 6 人 (BOSS 正背后脚后跟紧凑等分排布，规避招架与顺劈)
        local defaultMelees = {
            { name = "近战-狂暴", cls = "WARRIOR" },
            { name = "近战-潜行A", cls = "ROGUE" },
            { name = "近战-潜行B", cls = "ROGUE" },
            { name = "近战-惩戒", cls = "PALADIN" },
            { name = "近战-猫德", cls = "DRUID" },
            { name = "近战-增强", cls = "SHAMAN" },
        }
        for i, m in ipairs(defaultMelees) do
            local mx = cx - 65 + (i - 1) * 26
            local myOffset = (i % 2 == 0) and -6 or 0
            table.insert(spots, { x = mx, y = cy + meleeY + myOffset, num = tostring(8 + i), role = "melee", name = m.name, cls = m.cls })
        end

        -- 5. 远程输出 11 人 (位于南半场，根据 BOSS 机制形态精准展开)
        local defaultRangeds = {
            { name = "远程-法师A", cls = "MAGE" },
            { name = "远程-法师B", cls = "MAGE" },
            { name = "远程-术士A", cls = "WARLOCK" },
            { name = "远程-术士B", cls = "WARLOCK" },
            { name = "远程-暗牧",   cls = "PRIEST" },
            { name = "远程-鸟德",   cls = "DRUID" },
            { name = "远程-元萨",   cls = "SHAMAN" },
            { name = "远程-猎人A", cls = "HUNTER" },
            { name = "远程-猎人B", cls = "HUNTER" },
            { name = "远程-邪DK",   cls = "DEATHKNIGHT" },
            { name = "远程-术士C", cls = "WARLOCK" },
        }

        if rangedMode == "two_groups" then
            -- 维扎克斯将军：A/B 两组扎堆踩黑水 (西南与东南)
            for i, r in ipairs(defaultRangeds) do
                local isA = (i % 2 == 1)
                local gx = isA and (cx - 130) or (cx + 130)
                local gy = cy - 90
                local offX = (math.floor((i - 1) / 2) % 3 - 1) * 14
                local offY = (math.floor((i - 1) / 6)) * 14
                table.insert(spots, { x = gx + offX, y = gy - offY, num = tostring(14 + i), role = "ranged", name = r.name, cls = r.cls })
            end
        elseif rangedMode == "campfire" then
            -- 霍迪尔：暖炉火堆抱团取暖
            for i, r in ipairs(defaultRangeds) do
                local ang = math.pi * 0.15 + (i - 1) / 10 * (math.pi * 0.7)
                local rx = cx + math.cos(ang) * 125
                local ry = cy - 25 - math.sin(ang) * 75
                table.insert(spots, { x = rx, y = ry, num = tostring(14 + i), role = "ranged", name = r.name, cls = r.cls })
            end
        else
            -- 标准南半场宽幅大分散 (交错内外双圈，确保 10 码安全间距)
            for i, r in ipairs(defaultRangeds) do
                local ang = math.pi * 0.12 + (i - 1) / 10 * (math.pi * 0.76)
                local rx = cx + math.cos(ang) * 230 * (i % 2 == 0 and 1.0 or 0.85)
                local ry = cy - 70 - math.sin(ang) * 115
                table.insert(spots, { x = rx, y = ry, num = tostring(14 + i), role = "ranged", name = r.name, cls = r.cls })
            end
        end

        return spots
    end

    ----------------------------------------------------------------------------
    -- B. 如果传入了实际团队阵容 (真实开荒团队)：动态弹性排布，一人一位不多不少！
    ----------------------------------------------------------------------------
    local tanks = rosterData.tanks or {}
    local tankHealers = rosterData.tankHealers or {}
    local raidHealers = rosterData.raidHealers or {}
    local melees = rosterData.melees or {}
    local rangeds = rosterData.rangeds or {}
    local spotIndex = 1

    -- 1. 坦克组排布 (1 ~ #tanks，正北迎敌背靠北墙)
    local nTanks = #tanks
    if nTanks == 1 then
        local t = tanks[1]
        table.insert(spots, { x = cx, y = cy + tankY, num = tostring(spotIndex), role = "tank", name = t.name, cls = t.class, specIcon = t.specIcon })
        spotIndex = spotIndex + 1
    elseif nTanks >= 2 then
        local spread = opts.tankSpread or 45
        for i, t in ipairs(tanks) do
            local tx
            if i == 1 then
                tx = cx -- 主坦居中
            elseif i == 2 then
                tx = cx + spread -- 副坦右
            else
                tx = cx - spread * (i - 1) -- 备用坦左
            end
            table.insert(spots, { x = tx, y = cy + tankY - (i > 1 and 10 or 0), num = tostring(spotIndex), role = "tank", name = t.name, cls = t.class, specIcon = t.specIcon })
            spotIndex = spotIndex + 1
        end
    end

    -- 2. 核心保坦治疗 (紧贴坦克安全内圈，道标/压制/牺牲最佳施法射程，杜绝卡射程倒坦)
    local nTH = #tankHealers
    if nTH > 0 then
        local thL = opts.tankHealerLeft or { x = -75, y = 125 }
        local thR = opts.tankHealerRight or { x = 75, y = 125 }
        for i, h in ipairs(tankHealers) do
            local hx, hy
            if i == 1 then
                hx, hy = cx + thL.x, cy + thL.y
            elseif i == 2 then
                hx, hy = cx + thR.x, cy + thR.y
            else
                hx = cx + thL.x - (i - 2) * 25
                hy = cy + thL.y - 15
            end
            table.insert(spots, { x = hx, y = hy, num = tostring(spotIndex), role = "healer", name = h.name, cls = h.class, specIcon = h.specIcon, isTankHealer = true })
            spotIndex = spotIndex + 1
        end
    end

    -- 3. 团补治疗 (中内圈居中展开，兼顾近战与后排)
    local nRH = #raidHealers
    if nRH > 0 then
        for i, h in ipairs(raidHealers) do
            local hx, hy
            if nRH == 1 then
                hx, hy = cx, cy - 20
            else
                local frac = (i - 1) / (nRH - 1)
                hx = cx - 65 + frac * 130
                hy = cy - 20 - (i % 2 == 0 and 15 or 0)
            end
            table.insert(spots, { x = hx, y = hy, num = tostring(spotIndex), role = "healer", name = h.name, cls = h.class, specIcon = h.specIcon })
            spotIndex = spotIndex + 1
        end
    end

    -- 4. 近战输出组 (容量自适应！根据实际近战人数 nMelee 等分排列在 BOSS 正脚后跟)
    local nMelee = #melees
    if nMelee > 0 then
        local totalSpan = math.min(180, math.max(60, nMelee * 24))
        local step = (nMelee > 1) and (totalSpan / (nMelee - 1)) or 0
        local startX = cx - totalSpan / 2
        for i, m in ipairs(melees) do
            local mx = (nMelee == 1) and cx or (startX + (i - 1) * step)
            local myOffset = (i % 2 == 0) and -6 or 0
            table.insert(spots, { x = mx, y = cy + meleeY + myOffset, num = tostring(spotIndex), role = "melee", name = m.name, cls = m.class, specIcon = m.specIcon })
            spotIndex = spotIndex + 1
        end
    end

    -- 5. 远程输出组 (容量自适应！根据 BOSS 机制形态与实际远程人数 nRanged 排布在南半场)
    local nRanged = #rangeds
    if nRanged > 0 then
        if rangedMode == "two_groups" then
            -- 维扎克斯将军：A/B 两组紧凑抱团踩黑水 (西南与东南)
            local groupA = opts.groupA or { x = -130, y = -90 }
            local groupB = opts.groupB or { x = 130, y = -90 }
            for i, r in ipairs(rangeds) do
                local isA = (i % 2 == 1)
                local gx = isA and (cx + groupA.x) or (cx + groupB.x)
                local gy = cy + (isA and groupA.y or groupB.y)
                local offX = (math.floor((i - 1) / 2) % 3 - 1) * 14
                local offY = (math.floor((i - 1) / 6)) * 14
                table.insert(spots, { x = gx + offX, y = gy - offY, num = tostring(spotIndex), role = "ranged", name = r.name, cls = r.class, specIcon = r.specIcon })
                spotIndex = spotIndex + 1
            end
        elseif rangedMode == "campfire" then
            -- 霍迪尔：围绕暖炉火堆抱团
            local cp = opts.campfirePos or { x = 0, y = 0 }
            for i, r in ipairs(rangeds) do
                local ang = math.pi * 0.15 + (i - 1) / math.max(1, nRanged - 1) * (math.pi * 0.7)
                local rx = cx + cp.x + math.cos(ang) * 125
                local ry = cy + cp.y - 25 - math.sin(ang) * 75
                table.insert(spots, { x = rx, y = ry, num = tostring(spotIndex), role = "ranged", name = r.name, cls = r.class, specIcon = r.specIcon })
                spotIndex = spotIndex + 1
            end
        else
            -- 标准南半场宽幅大分散 (交错内外两圈，确保间距 10 码以上)
            for i, r in ipairs(rangeds) do
                local ang = math.pi * 0.12 + (i - 1) / math.max(1, nRanged - 1) * (math.pi * 0.76)
                local radiusMul = (i % 2 == 0) and 1.0 or 0.85
                local rx = cx + math.cos(ang) * 230 * radiusMul
                local ry = cy - 70 - math.sin(ang) * 115
                table.insert(spots, { x = rx, y = ry, num = tostring(spotIndex), role = "ranged", name = r.name, cls = r.cls })
                spotIndex = spotIndex + 1
            end
        end
    end

    return spots
end

-- 保持旧版接口平滑兼容
RaidMap.GenerateStandard25Spots = function(cx, cy, opts)
    return RaidMap.GenerateDynamicTacticalSpots(cx, cy, opts, nil)
end
