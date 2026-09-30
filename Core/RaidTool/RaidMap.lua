local AddonName, ns = ...
if BG and BG.IsBlackListPlayer then return end

local L = ns.L or {}
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidMap = ns.RaidMap or _G.RaidMap or {}
ns.RaidMap = RaidMap
_G.RaidMap = RaidMap
if BG then BG.RaidMap = RaidMap end

local channelPrefix = "BiaoGeAIMap"
local channelCount = 10
local MAP_PREFIXES = {}

local function RegisterPrefixSafe(prefix)
    if not prefix then return end
    MAP_PREFIXES[prefix] = true
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(prefix)
    end
end

RegisterPrefixSafe(channelPrefix)
for i = 1, channelCount do
    RegisterPrefixSafe(channelPrefix .. i)
end

local function SendAddonMessageSafe(prefix, msg, channel)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, msg, channel)
    elseif SendAddonMessage then
        SendAddonMessage(prefix, msg, channel)
    end
end

--------------------------------------------------------------------------------
-- 1. 自包含轻量高效 Base64 编解码引擎 (零外部依赖，100% 独立健壮)
--------------------------------------------------------------------------------
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64bytes = {}
for i = 1, #b64chars do
    b64bytes[string.byte(b64chars, i)] = i - 1
end

local function Base64Encode(data)
    if not data or data == "" then return "" end
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b0 = string.byte(data, i)
        local b1 = string.byte(data, i + 1) or 0
        local b2 = string.byte(data, i + 2) or 0

        local n = (b0 * 65536) + (b1 * 256) + b2
        out[#out + 1] = string.sub(b64chars, math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        out[#out + 1] = string.sub(b64chars, (math.floor(n / 4096) % 64) + 1, (math.floor(n / 4096) % 64) + 1)
        if (i + 1) <= len then
            out[#out + 1] = string.sub(b64chars, (math.floor(n / 64) % 64) + 1, (math.floor(n / 64) % 64) + 1)
        else
            out[#out + 1] = "="
        end
        if (i + 2) <= len then
            out[#out + 1] = string.sub(b64chars, (n % 64) + 1, (n % 64) + 1)
        else
            out[#out + 1] = "="
        end
    end
    return table.concat(out)
end

local function Base64Decode(data)
    if not data or data == "" then return "" end
    data = string.gsub(data, '[^' .. b64chars .. '=]', '')
    local out = {}
    local len = #data
    for i = 1, len, 4 do
        local c1 = b64bytes[string.byte(data, i)] or 0
        local c2 = b64bytes[string.byte(data, i + 1)] or 0
        local c3 = b64bytes[string.byte(data, i + 2)] or 0
        local c4 = b64bytes[string.byte(data, i + 3)] or 0

        local n = (c1 * 262144) + (c2 * 4096) + (c3 * 64) + c4
        out[#out + 1] = string.char(math.floor(n / 65536))
        if string.sub(data, i + 2, i + 2) ~= '=' then
            out[#out + 1] = string.char(math.floor(n / 256) % 256)
        end
        if string.sub(data, i + 3, i + 3) ~= '=' then
            out[#out + 1] = string.char(n % 256)
        end
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- 2. 压缩/解压与字符串协议解析器
--------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

local function SafeCompress(text)
    if LibDeflate and LibDeflate.CompressDeflate and LibDeflate.EncodeForPrint then
        local comp = LibDeflate:CompressDeflate(text)
        if comp then
            return LibDeflate:EncodeForPrint(comp)
        end
    end
    return text
end

local function SafeDecompress(text)
    if LibDeflate and LibDeflate.DecodeForPrint and LibDeflate.DecompressDeflate then
        local raw = LibDeflate:DecodeForPrint(text)
        if raw then
            local decomp = LibDeflate:DecompressDeflate(raw)
            if decomp then return decomp end
        end
    end
    return text
end

local function SafeSplit(sep, text)
    if not text then return nil end
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(text, pattern, function(c) fields[#fields + 1] = c end)
    return unpack(fields)
end

--------------------------------------------------------------------------------
-- 3. 战术数据中心 (Tactical Registry & Roster Engine)
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

local registeredBosses = {}
local registeredFBOrder = {}
local registeredFBs = {}
local linearBossList = {}

function RaidMap.RegisterFB(fbKey, fbName)
    if not fbKey then return end
    if not registeredFBs[fbKey] then
        registeredFBs[fbKey] = {
            key = fbKey,
            name = fbName or fbKey,
            bosses = {},
        }
        table.insert(registeredFBOrder, fbKey)
    end
    return registeredFBs[fbKey]
end

function RaidMap.RegisterBoss(bossConfig)
    if not bossConfig or not bossConfig.id then return end
    local fbKey = bossConfig.fb or "GENERAL"
    RaidMap.RegisterFB(fbKey, bossConfig.fbName or fbKey)

    registeredBosses[bossConfig.id] = bossConfig
    table.insert(registeredFBs[fbKey].bosses, bossConfig)
    table.insert(linearBossList, bossConfig)
end

function RaidMap.GetBoss(bossID)
    return registeredBosses[bossID]
end

function RaidMap.GetAllBosses()
    return linearBossList
end

RaidMap.BOSS_LIST = linearBossList

function RaidMap.GetRegisteredFBs()
    local list = {}
    for _, fbKey in ipairs(registeredFBOrder) do
        table.insert(list, registeredFBs[fbKey])
    end
    return list
end

--------------------------------------------------------------------------------
-- 4. 战术阵型与队形几何计算引擎 (Tactical Formation Engine)
--------------------------------------------------------------------------------
local currentMeleeMode = "group"
local currentRangedMode = "arc"

function RaidMap.GetCurrentMeleeMode()
    return currentMeleeMode or "group"
end

function RaidMap.GetCurrentRangedMode()
    return currentRangedMode or "arc"
end

RaidMap.MELEE_MODE_NAMES = {
    ["group"] = "聚合群组 (9人合一)",
    ["arc"] = "背后弧形展开 (个人散点)",
    ["double_row"] = "背后双排错位 (紧凑层次)",
    ["two_groups"] = "左右分翼站位 (分边转火)",
    ["compact"] = "背后集中单点 (极度抱团)",
}

RaidMap.RANGED_MODE_NAMES = {
    ["arc"] = "南侧大扇形",
    ["two_groups"] = "左右双堆站位",
    ["campfire"] = "中场环形抱团",
    ["matrix"] = "后方整齐方阵",
}

-- 核心算法：近战组几何坐标计算 (彻底消除人员重叠)
function RaidMap.CalculateMeleePositions(bossX, bossY, cx, cy, nMelee, mode)
    mode = mode or "arc"
    local spots = {}
    if nMelee <= 0 then return spots end
    local bX = bossX or cx
    local bY = bossY or (cy + 90)

    if mode == "double_row" then
        local front = {}
        local back = {}
        for i = 1, nMelee do
            if i % 2 == 1 then table.insert(front, i) else table.insert(back, i) end
        end
        local n1 = #front
        local n2 = #back
        local span1 = math.min(240, math.max(60, n1 * 40))
        local step1 = (n1 > 1) and (span1 / (n1 - 1)) or 0
        local startX1 = bX - span1 / 2
        for idx, origI in ipairs(front) do
            local x = (n1 == 1) and bX or (startX1 + (idx - 1) * step1)
            local y = bY - 48
            spots[origI] = { x = x, y = y }
        end
        local span2 = math.min(240, math.max(60, n2 * 40))
        local step2 = (n2 > 1) and (span2 / (n2 - 1)) or 0
        local startX2 = bX - span2 / 2
        for idx, origI in ipairs(back) do
            local x = (n2 == 1) and bX or (startX2 + (idx - 1) * step2)
            local y = bY - 76
            spots[origI] = { x = x, y = y }
        end

    elseif mode == "two_groups" then
        local leftIdxs = {}
        local rightIdxs = {}
        for i = 1, nMelee do
            if i <= math.ceil(nMelee / 2) then
                table.insert(leftIdxs, i)
            else
                table.insert(rightIdxs, i)
            end
        end
        local nL = #leftIdxs
        local nR = #rightIdxs
        local spanL = math.min(100, math.max(40, nL * 30))
        local stepL = (nL > 1) and (spanL / (nL - 1)) or 0
        local startXL = (bX - 75) - spanL / 2
        for idx, origI in ipairs(leftIdxs) do
            local x = (nL == 1) and (bX - 75) or (startXL + (idx - 1) * stepL)
            local y = bY - 55 - (idx % 2 == 0 and 12 or 0)
            spots[origI] = { x = x, y = y }
        end
        local spanR = math.min(100, math.max(40, nR * 30))
        local stepR = (nR > 1) and (spanR / (nR - 1)) or 0
        local startXR = (bX + 75) - spanR / 2
        for idx, origI in ipairs(rightIdxs) do
            local x = (nR == 1) and (bX + 75) or (startXR + (idx - 1) * stepR)
            local y = bY - 55 - (idx % 2 == 0 and 12 or 0)
            spots[origI] = { x = x, y = y }
        end

    elseif mode == "compact" then
        for i = 1, nMelee do
            local offX = (i - (nMelee + 1) / 2) * 12
            local offY = (i % 2 == 0 and -6 or 0)
            spots[i] = { x = bX + offX, y = bY - 55 + offY }
        end

    else -- "arc" (默认背后弧形展开，彻底消除遮挡)
        if nMelee == 1 then
            spots[1] = { x = bX, y = bY - 60 }
        else
            local totalAngle = math.min(140, math.max(55, nMelee * 15))
            local halfAng = totalAngle / 2
            local stepAng = totalAngle / (nMelee - 1)
            for i = 1, nMelee do
                local curAngDeg = -halfAng + (i - 1) * stepAng
                local curAngRad = math.rad(curAngDeg)
                local radius = (i % 2 == 0) and 74 or 58
                local x = bX + math.sin(curAngRad) * radius
                local y = bY - math.cos(curAngRad) * radius
                spots[i] = { x = x, y = y }
            end
        end
    end
    return spots
end

-- 核心算法：远程组几何坐标计算 (大扇形防炸弹互炸/双堆/方阵/抱团)
function RaidMap.CalculateRangedPositions(cx, cy, nRanged, mode, opts)
    mode = mode or "arc"
    opts = opts or {}
    local spots = {}
    if nRanged <= 0 then return spots end

    if mode == "two_groups" then
        local groupA = opts.groupA or { x = -145, y = -90 }
        local groupB = opts.groupB or { x = 145, y = -90 }
        local leftGroup = {}
        local rightGroup = {}
        for i = 1, nRanged do
            if i % 2 == 1 then table.insert(leftGroup, i) else table.insert(rightGroup, i) end
        end
        for idx, origI in ipairs(leftGroup) do
            local col = (idx - 1) % 3
            local row = math.floor((idx - 1) / 3)
            local gx = cx + groupA.x + (col - 1) * 36
            local gy = cy + groupA.y - row * 34
            spots[origI] = { x = gx, y = gy }
        end
        for idx, origI in ipairs(rightGroup) do
            local col = (idx - 1) % 3
            local row = math.floor((idx - 1) / 3)
            local gx = cx + groupB.x + (col - 1) * 36
            local gy = cy + groupB.y - row * 34
            spots[origI] = { x = gx, y = gy }
        end

    elseif mode == "campfire" then
        local cp = opts.campfirePos or { x = 0, y = 0 }
        for i = 1, nRanged do
            local ang = math.pi * 0.15 + (i - 1) / math.max(1, nRanged - 1) * (math.pi * 0.7)
            local radius = 85 + (i % 2 == 0 and 22 or 0)
            local rx = cx + cp.x + math.cos(ang) * radius
            local ry = cy - 35 - math.sin(ang) * (radius * 0.6)
            spots[i] = { x = rx, y = ry }
        end

    elseif mode == "matrix" then
        local perRow = 5
        local nRows = math.ceil(nRanged / perRow)
        for i = 1, nRanged do
            local row = math.floor((i - 1) / perRow)
            local col = (i - 1) % perRow
            local rowCount = (row == nRows - 1) and (nRanged - row * perRow) or perRow
            local rowSpan = (rowCount - 1) * 48
            local rx = cx - rowSpan / 2 + col * 48
            local ry = cy - 65 - row * 38
            spots[i] = { x = rx, y = ry }
        end

    else -- "arc" (默认南侧大扇形大分散)
        for i = 1, nRanged do
            local ang = (nRanged == 1) and (math.pi * 0.5) or (math.pi * 0.10 + (i - 1) / (nRanged - 1) * (math.pi * 0.80))
            local radius = (i % 2 == 0) and 230 or 195
            local rx = cx + math.cos(ang) * radius
            local ry = cy - 70 - math.sin(ang) * (radius * 0.55)
            spots[i] = { x = rx, y = ry }
        end
    end
    return spots
end

function RaidMap.GenerateDynamicTacticalSpots(cx, cy, opts, rosterData)
    opts = opts or {}
    local spots = {}

    local tankY = opts.tankY or 160
    local meleeY = opts.meleeY or 35
    local bossOffsetY = opts.bossOffsetY or 90
    local userMeleeMode = (RaidMap.GetCurrentMeleeMode and RaidMap.GetCurrentMeleeMode()) or currentMeleeMode or "group"
    local userRangedMode = (RaidMap.GetCurrentRangedMode and RaidMap.GetCurrentRangedMode()) or currentRangedMode or "arc"
    local meleeMode = userMeleeMode or opts.meleeMode or "group"
    local rangedMode = opts.rangedMode or userRangedMode or "arc"

    local bossX = cx
    local bossY = cy + bossOffsetY

    ----------------------------------------------------------------------------
    -- A. 未组队或未提供实际阵容：提供标准的 25 人示范规范架构
    ----------------------------------------------------------------------------
    if not rosterData then
        -- 1. 坦克组 3 人
        table.insert(spots, { x = cx, y = cy + tankY, num = "1", role = "tank", name = "主坦-MT", cls = "WARRIOR" })
        table.insert(spots, { x = cx + (opts.tankSpread or 45), y = cy + tankY - 10, num = "2", role = "tank", name = "副坦-OT", cls = "PALADIN" })
        table.insert(spots, { x = cx - (opts.tankSpread or 45), y = cy + tankY - 10, num = "3", role = "tank", name = "换坦-ST", cls = "DEATHKNIGHT" })

        -- 2. 核心保坦治疗 2 人 (紧贴坦克两翼 20~25 码安全内圈)
        local thL = opts.tankHealerLeft or { x = -75, y = 125 }
        local thR = opts.tankHealerRight or { x = 75, y = 125 }
        table.insert(spots, { x = cx + thL.x, y = cy + thL.y, num = "4", role = "healer", name = "保坦奶-奶骑", cls = "PALADIN", isTankHealer = true })
        table.insert(spots, { x = cx + thR.x, y = cy + thR.y, num = "5", role = "healer", name = "保坦奶-戒律", cls = "PRIEST",  isTankHealer = true })

        -- 3. 团补治疗 3 人 (居中场内圈)
        local rhList = {
            { name = "团补奶-奶萨", cls = "SHAMAN", x = cx - 60, y = cy - 20, num = "6" },
            { name = "团补奶-神牧", cls = "PRIEST", x = cx,      y = cy - 15, num = "7" },
            { name = "团补奶-奶德", cls = "DRUID",  x = cx + 60, y = cy - 20, num = "8" },
        }
        for _, h in ipairs(rhList) do table.insert(spots, { x = h.x, y = h.y, num = h.num, role = "healer", name = h.name, cls = h.cls }) end

        -- 4. 近战输出 6 人 (算法自适应)
        local defaultMelees = {
            { name = "近战-狂暴", cls = "WARRIOR" },
            { name = "近战-潜行A", cls = "ROGUE" },
            { name = "近战-潜行B", cls = "ROGUE" },
            { name = "近战-惩戒", cls = "PALADIN" },
            { name = "近战-猫德", cls = "DRUID" },
            { name = "近战-增强", cls = "SHAMAN" },
        }
        if meleeMode == "group" then
            table.insert(spots, {
                x = bossX,
                y = bossY - 55,
                num = "⚔️",
                role = "melee_group",
                name = string.format("近战组 (%d人)", #defaultMelees),
                cls = "WARRIOR",
                specIcon = "Interface\\Icons\\ability_warrior_bladestorm",
                members = defaultMelees,
            })
        else
            local mSpots = RaidMap.CalculateMeleePositions(bossX, bossY, cx, cy, #defaultMelees, meleeMode)
            for i, m in ipairs(defaultMelees) do
                local sp = mSpots[i] or { x = cx, y = cy + meleeY }
                table.insert(spots, { x = sp.x, y = sp.y, num = tostring(8 + i), role = "melee", name = m.name, cls = m.cls })
            end
        end

        -- 5. 远程输出 11 人 (算法自适应)
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
        local rSpots = RaidMap.CalculateRangedPositions(cx, cy, #defaultRangeds, rangedMode, opts)
        for i, r in ipairs(defaultRangeds) do
            local sp = rSpots[i] or { x = cx, y = cy - 70 }
            table.insert(spots, { x = sp.x, y = sp.y, num = tostring(14 + i), role = "ranged", name = r.name, cls = r.cls })
        end

        return spots
    end

    ----------------------------------------------------------------------------
    -- B. 传入了实际团队阵容：动态弹性排布
    ----------------------------------------------------------------------------
    local tanks = rosterData.tanks or {}
    local tankHealers = rosterData.tankHealers or {}
    local raidHealers = rosterData.raidHealers or {}
    local melees = rosterData.melees or {}
    local rangeds = rosterData.rangeds or {}
    local spotIndex = 1

    local nTanks = #tanks
    if nTanks > 0 then
        local spread = opts.tankSpread or 45
        for i, t in ipairs(tanks) do
            local tx
            if i == 1 then
                tx = cx
            elseif i == 2 then
                tx = cx + spread
            else
                tx = cx - spread * (i - 1)
            end
            table.insert(spots, { x = tx, y = cy + tankY - (i > 1 and 10 or 0), num = tostring(spotIndex), role = "tank", name = t.name, cls = t.class, specIcon = t.specIcon })
            spotIndex = spotIndex + 1
        end
    end

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

    local nMelee = #melees
    if nMelee > 0 then
        if meleeMode == "group" then
            table.insert(spots, {
                x = bossX,
                y = bossY - 55,
                num = "⚔️",
                role = "melee_group",
                name = string.format("近战组 (%d人)", nMelee),
                cls = "WARRIOR",
                specIcon = "Interface\\Icons\\ability_warrior_bladestorm",
                members = melees,
            })
            spotIndex = spotIndex + 1
        else
            local mSpots = RaidMap.CalculateMeleePositions(bossX, bossY, cx, cy, nMelee, meleeMode)
            for i, m in ipairs(melees) do
                local sp = mSpots[i] or { x = cx, y = cy + meleeY }
                table.insert(spots, { x = sp.x, y = sp.y, num = tostring(spotIndex), role = "melee", name = m.name, cls = m.class, specIcon = m.specIcon })
                spotIndex = spotIndex + 1
            end
        end
    end

    local nRanged = #rangeds
    if nRanged > 0 then
        local rSpots = RaidMap.CalculateRangedPositions(cx, cy, nRanged, rangedMode, opts)
        for i, r in ipairs(rangeds) do
            local sp = rSpots[i] or { x = cx, y = cy - 70 }
            table.insert(spots, { x = sp.x, y = sp.y, num = tostring(spotIndex), role = "ranged", name = r.name, cls = r.class, specIcon = r.specIcon })
            spotIndex = spotIndex + 1
        end
    end

    return spots
end

RaidMap.GenerateStandard25Spots = function(cx, cy, opts)
    return RaidMap.GenerateDynamicTacticalSpots(cx, cy, opts, nil)
end

--------------------------------------------------------------------------------
-- 5. 奥杜尔 9 大核心 BOSS 官方实战站位预设 (全部配置规范 1024x1024 高清实景场地背景)
--------------------------------------------------------------------------------
local FB_KEY = "ULDtitan"
local FB_NAME = "奥杜尔"

-- 1. 拆解者 XT-002 (Boss ID = 4)
RaidMap.RegisterBoss({
    id = 4,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "拆解者 XT-002",
    sub = "主坦背墙拉北面 | 近战正背后 | 远程南半场大分散 | 白光跑右 黑光跑左",
    tacticTip = "【拆解者站位要点】\n1. 主坦在 12 点正北背靠北墙拉怪，使 BOSS 背对全团，避免正面震耳发聩AOE；\n2. 保坦奶（奶骑/戒律）靠近坦克两翼 20 码，道标与牺牲无死角覆盖；\n3. 近战集中在 BOSS 正背后 6 点脚后跟输出；\n4. 远程与团补在南半场大扇形分散保持 10 码；\n5. 点名发光炸弹(白光)迅速向右侧(东)跑出人群，重力炸弹(黑光)迅速向左侧(西)跑出人群！",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m4.png",
    targets = {
        { type = "boss", name = "XT-002 拆解者", iconTex = "Interface\\Icons\\achievement_boss_xt002deconstructor_01", relX = 0, relY = 90, size = 52, color = { 1, 0.25, 0.25 } },
        { type = "npc",  name = "左废料出怪点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", relX = -240, relY = 110, size = 36, color = { 0.2, 1, 0.3 } },
        { type = "npc",  name = "右废料出怪点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = 240, relY = 110, size = 36, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "重力炸弹(黑光跑左)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", relX = -200, relY = -110, size = 34, color = { 0.8, 0.3, 1 } },
        { type = "npc",  name = "发光炸弹(白光跑右)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = 200, relY = -110, size = 34, color = { 1, 1, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 165,
            meleeY = 40,
            tankSpread = 40,
            tankHealerLeft = { x = -70, y = 130 },
            tankHealerRight = { x = 70, y = 130 },
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 2. 钢铁议会 (Boss ID = 5)
RaidMap.RegisterBoss({
    id = 5,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "钢铁议会",
    sub = "破钢拉北面 | 唤雷拉东侧防超载 | 蓝圈踩增伤 绿圈后撤",
    tacticTip = "【钢铁议会站位要点】\n1. 主坦将破钢者定在北侧靠墙；\n2. 保坦奶在主坦侧后方 20 码，融化之拳第一时间给压制与大光；\n3. 副坦A拉住唤雷者在东侧远离人群（读条超载时全团20码规避）；\n4. 副坦B拉符文大师在中偏西，近战先集中集火，出蓝色增伤符文全团踩入增加50%伤害；\n5. 出绿色死亡符文全团迅速向后撤退风筝。",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m5.png",
    targets = {
        { type = "boss", name = "破钢者 (大)", iconTex = "Interface\\Icons\\achievement_boss_ironcouncil_01", relX = 0, relY = 90, size = 50, color = { 1, 0.2, 0.2 } },
        { type = "boss", name = "唤雷者 (中)", iconTex = "Interface\\Icons\\spell_nature_lightning", relX = 180, relY = 40, size = 42, color = { 1, 0.6, 0.2 } },
        { type = "boss", name = "符文大师 (小)", iconTex = "Interface\\Icons\\spell_arcane_rune", relX = -130, relY = 50, size = 42, color = { 0.3, 0.8, 1 } },
        { type = "npc",  name = "增伤蓝圈踩圈位", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = -50, relY = 0, size = 32, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "超载规避警戒线", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = 120, relY = -10, size = 30, color = { 1, 0.3, 0.3 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 140,
            tankHealerLeft = { x = -75, y = 125 },
            tankHealerRight = { x = 75, y = 125 },
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 3. 霍迪尔 (Boss ID = 8)
RaidMap.RegisterBoss({
    id = 8,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "霍迪尔",
    sub = "以暖炉火堆为轴心抱团 | 坦拉北侧怪背对 | 踩雪避落冰 雷云进堆传电",
    tacticTip = "【霍迪尔站位要点】\n1. 场地中央暖炉火堆是全团生存与增伤核心，全团严密围拢在火堆 10 码内消除极度寒冷层数；\n2. 坦把霍迪尔定在火堆北面 10 码处，近战脚跟输出并蹭火堆 Buff；\n3. 获【风暴之力(雷云)】点名的玩家第一时间跳入火堆人群，为所有法系传导 100% 暴伤；\n4. 闪霜大落冰前迅速站上积雪，切勿贪打！",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m8.png",
    targets = {
        { type = "boss", name = "霍迪尔 (冰霜之王)", iconTex = "Interface\\Icons\\achievement_boss_hodir_01", relX = 0, relY = 90, size = 52, color = { 0.4, 0.8, 1 } },
        { type = "npc",  name = "暖炉火堆(全团抱团核心)", iconTex = "Interface\\Icons\\spell_fire_lavaspawn", relX = 0, relY = 0, size = 44, color = { 1, 0.5, 0.1 } },
        { type = "npc",  name = "西侧解冻萨满法师", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = -200, relY = 50, size = 32, color = { 0.3, 1, 0.4 } },
        { type = "npc",  name = "东侧解冻德鲁伊牧师", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", relX = 200, relY = 50, size = 32, color = { 0.3, 1, 0.4 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 150,
            meleeY = 45,
            tankHealerLeft = { x = -50, y = 110 },
            tankHealerRight = { x = 50, y = 110 },
            rangedMode = "campfire",
            campfirePos = { x = 0, y = 0 },
        }, rosterData)
    end,
})

-- 4. 托利姆 (Boss ID = 9)
RaidMap.RegisterBoss({
    id = 9,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "托利姆",
    sub = "内外场分兵 | 外场中圈规避暴风雪 | 内场破门冲锋 | P2闪电充能避让",
    tacticTip = "【托利姆站位要点】\n1. 团队分为外场防守组与内场冲锋组；外场主坦中场拉怪，远程外圈分散避暴风雪；\n2. 内场副坦带领小队迅速沿通道破门斩杀符文巨灵；\n3. P2 托利姆跳入竞技场，全团分散站位，严禁站在闪电充能正对扇形区域。",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m9.png",
    targets = {
        { type = "boss", name = "托利姆", iconTex = "Interface\\Icons\\achievement_boss_thorim", relX = 0, relY = 100, size = 50, color = { 0.5, 0.8, 1 } },
        { type = "npc",  name = "外场竞技场中圈", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", relX = 0, relY = 0, size = 36, color = { 0.3, 1, 0.4 } },
        { type = "npc",  name = "内场走廊入口", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", relX = -220, relY = 40, size = 34, color = { 1, 0.8, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 150,
            meleeY = 35,
            tankSpread = 60,
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 5. 弗蕾雅 (Boss ID = 10)
RaidMap.RegisterBoss({
    id = 10,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "弗蕾雅",
    sub = "大范围全团分散 | 坦拉北水池边 | 第一时间转火礼物树 | 元素小怪控血同杀",
    tacticTip = "【弗蕾雅站位要点】\n1. 主坦把弗蕾雅拉在生命温室正北水池边，背对人群；\n2. 全体远程与治疗在南半场大范围分散开，每人间距保持 10 码以上，严禁扎堆；\n3. 刷新【艾欧娜尔的礼物】所有 DPS 第一时间秒掉，否则 BOSS 持续巨幅回血；\n4. 三元素小怪组（水灵、树人、风暴）必须控血同时 10 秒内击杀，否则互相复活。",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m10.png",
    targets = {
        { type = "boss", name = "弗蕾雅", iconTex = "Interface\\Icons\\achievement_boss_freya", relX = 0, relY = 95, size = 52, color = { 0.3, 1, 0.4 } },
        { type = "npc",  name = "艾欧娜尔的礼物(首要秒杀)", iconTex = "Interface\\Icons\\spell_nature_healingtouch", relX = 90, relY = 30, size = 38, color = { 1, 0.9, 0.2 } },
        { type = "npc",  name = "健康蘑菇(沉默避难区)", iconTex = "Interface\\Icons\\inv_mushroom_11", relX = -100, relY = -30, size = 34, color = { 0.4, 0.8, 1 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 40,
            tankSpread = 50,
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 6. 米米尔隆 (Boss ID = 11)
RaidMap.RegisterBoss({
    id = 11,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "米米尔隆",
    sub = "P1避地雷等离子 | P2顺时针转圈躲激光 | P3突击机器人远程转火 | P4修血同时杀",
    tacticTip = "【米米尔隆站位要点】\n1. P1 战车主坦背拉，近战注意地雷，副坦随时准备凝固汽油抗伤；\n2. P2 VX-001 旋转扫射激光弹幕，全员看清面向顺时针全速跑动；\n3. P3 空中指挥单元，猎人术士远程主力击落，副坦拉好突击机器人；\n4. P4 合体形态，全团均分输出修血，底座、身躯、头部必须在 15 秒内同时打爆！",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m11.png",
    targets = {
        { type = "boss", name = "米米尔隆座驾", iconTex = "Interface\\Icons\\achievement_boss_mimiron_01", relX = 0, relY = 85, size = 52, color = { 1, 0.5, 0.1 } },
        { type = "npc",  name = "激光弹幕规避安全区", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = -120, relY = -20, size = 34, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "近战地雷危险红区", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = 40, relY = 40, size = 30, color = { 1, 0.2, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 150,
            meleeY = 35,
            tankSpread = 50,
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 7. 维扎克斯将军 (Boss ID = 12)
RaidMap.RegisterBoss({
    id = 12,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "维扎克斯将军",
    sub = "无自然回蓝 | A/B组踩黑水增伤 | 暗影印记立刻跑出人群 | 萨隆邪铁畸体转火",
    tacticTip = "【将军站位要点】\n1. 本场战斗存在绝望光环，全员无法通过常规手段自然回蓝；\n2. 远程分为左右两组（A组在西南，B组在东南），轮流踩入蒸汽黑水获得急速与伤害加成；\n3. 点名【无面者的印记】的玩家必须在 1 秒内朝后方反向全速跑出大团，严禁传染抽血；\n4. 暗影冲击落点全员瞬间横向侧移规避；困难模式下击杀 6 块矿石合成的畸体。",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m12.png",
    targets = {
        { type = "boss", name = "维扎克斯将军", iconTex = "Interface\\Icons\\achievement_boss_generalvezax_01", relX = 0, relY = 90, size = 52, color = { 0.8, 0.2, 1 } },
        { type = "npc",  name = "左黑水集合点 (A组)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = -130, relY = -75, size = 38, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "右黑水集合点 (B组)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", relX = 130, relY = -75, size = 38, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "印记向后逃逸路线", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = 0, relY = -140, size = 32, color = { 1, 0.2, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 45,
            tankHealerLeft = { x = -60, y = 120 },
            tankHealerRight = { x = 60, y = 120 },
            rangedMode = "two_groups",
            groupA = { x = -130, y = -75 },
            groupB = { x = 130, y = -75 },
        }, rosterData)
    end,
})

-- 8. 尤格萨隆 (Boss ID = 13)
RaidMap.RegisterBoss({
    id = 13,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "尤格萨隆",
    sub = "P1踩绿云出怪控血 | P2进门组打大脑 外场救缠绕 | P3背对疯狂诱视 斩杀信标",
    tacticTip = "【尤格萨隆站位要点】\n1. P1 围绕萨拉中场站位，严禁踩踏扩散绿云，小怪拉在萨拉脚下拉爆炸伤萨拉；\n2. P2 刷新触须海，近战与进门组第一时间通过传送门进入脑房消灭诱视幻象，外场优先解救缠绕大触须；\n3. P3 尤格萨隆破壳，近战与远程严格背对 BOSS 读条【疯狂诱视】，信标怪由副坦拉开优先集火秒杀！",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m13.png",
    targets = {
        { type = "boss", name = "尤格萨隆 (千喉之魔)", iconTex = "Interface\\Icons\\achievement_boss_yoggsaron_01", relX = 0, relY = 90, size = 54, color = { 0.9, 0.1, 0.9 } },
        { type = "npc",  name = "传送门进脑房集合位", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", relX = -120, relY = 20, size = 36, color = { 0.2, 1, 0.4 } },
        { type = "npc",  name = "信标小怪拉开击杀点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = 140, relY = -30, size = 36, color = { 1, 0.8, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 155,
            meleeY = 35,
            tankSpread = 60,
            rangedMode = "arc",
        }, rosterData)
    end,
})

-- 9. 观察者阿加隆 (Boss ID = 14)
RaidMap.RegisterBoss({
    id = 14,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "观察者阿加隆",
    sub = "双坦及时换嘲量子重击 | 副坦外围风筝活化星宿 | 大爆炸全团进黑洞躲避",
    tacticTip = "【阿加隆站位要点】\n1. 主坦在场地正北拉住阿加隆背靠星空，两层相位冲孔后副坦立刻嘲讽换坦，量子重击覆盖大减伤；\n2. 副坦在外围顺时针大圈风筝活化星宿，严禁近战贪打近身引发自爆；\n3. 坍缩星按指挥标记单点轮流击杀，全团大减伤覆盖爆炸；\n4. 读条【大爆炸】时，全团（除留守防骑/惩戒骑开无敌外）全速走进黑洞逃生！",
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m14.png",
    targets = {
        { type = "boss", name = "观察者阿加隆", iconTex = "Interface\\Icons\\achievement_boss_algalon_01", relX = 0, relY = 90, size = 52, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "黑洞避难所(大爆炸进入)", iconTex = "Interface\\Icons\\spell_shadow_twilight", relX = 140, relY = 10, size = 42, color = { 0.7, 0.3, 1 } },
        { type = "npc",  name = "副坦风筝星宿外环", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", relX = -180, relY = -30, size = 34, color = { 1, 0.8, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 45,
            tankHealerLeft = { x = -65, y = 125 },
            tankHealerRight = { x = 65, y = 125 },
            rangedMode = "arc",
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 6. 战术看板 UI 构建与布局
--------------------------------------------------------------------------------
local currentBossID = 5
local mapFrame = nil
local currentMapIndex = 1

function RaidMap.InitDB()
    if not BiaoGe then BiaoGe = {} end
    if not BiaoGe.point then BiaoGe.point = {} end
    if not BiaoGe.maps then BiaoGe.maps = {} end
    if not BiaoGe.RaidMap then
        BiaoGe.RaidMap = {
            enableAutoPopup = true,
            mapScale = 0.85,
            meleeMode = "group",
            rangedMode = "arc",
        }
    else
        if not BiaoGe.RaidMap.meleeMode then BiaoGe.RaidMap.meleeMode = "group" end
        if not BiaoGe.RaidMap.rangedMode then BiaoGe.RaidMap.rangedMode = "arc" end
    end
    currentMeleeMode = BiaoGe.RaidMap.meleeMode
    currentRangedMode = BiaoGe.RaidMap.rangedMode
end

-- 优雅纯净的降级战术刻度网格 (仅当无真实地图时作为安全兜底，绝无任何怪异小地图边框与多余矩形)
local function DrawProceduralTacticalGrid(parent, width, height, bossID)
    if parent.tacticalGrid then
        parent.tacticalGrid:Show()
        return
    end

    local g = CreateFrame("Frame", nil, parent)
    g:SetAllPoints()
    g:SetFrameLevel(parent:GetFrameLevel() + 1)
    parent.tacticalGrid = g

    local bgTex = g:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.04, 0.05, 0.08, 0.96)

    -- 十字与 8 向极简战术刻度标线
    local hLine = g:CreateLine(nil, "BORDER")
    hLine:SetColorTexture(0.25, 0.55, 0.85, 0.3)
    hLine:SetStartPoint("LEFT", g, 30, -10)
    hLine:SetEndPoint("RIGHT", g, -30, -10)
    hLine:SetThickness(1)

    local vLine = g:CreateLine(nil, "BORDER")
    vLine:SetColorTexture(0.25, 0.55, 0.85, 0.3)
    vLine:SetStartPoint("TOP", g, 0, -45)
    vLine:SetEndPoint("BOTTOM", g, 0, 30)
    vLine:SetThickness(1)

    local dLine1 = g:CreateLine(nil, "BORDER")
    dLine1:SetColorTexture(0.2, 0.4, 0.6, 0.18)
    dLine1:SetStartPoint("TOPLEFT", g, 60, -70)
    dLine1:SetEndPoint("BOTTOMRIGHT", g, -60, 50)
    dLine1:SetThickness(1)

    local dLine2 = g:CreateLine(nil, "BORDER")
    dLine2:SetColorTexture(0.2, 0.4, 0.6, 0.18)
    dLine2:SetStartPoint("TOPRIGHT", g, -60, -70)
    dLine2:SetEndPoint("BOTTOMLEFT", g, 60, 50)
    dLine2:SetThickness(1)

    local northText = g:CreateFontString(nil, "ARTWORK")
    northText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    northText:SetPoint("TOP", g, "TOP", 0, -50)
    northText:SetTextColor(0.3, 0.8, 1, 0.75)
    northText:SetText("N (正北/BOSS方)")

    local southText = g:CreateFontString(nil, "ARTWORK")
    southText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    southText:SetPoint("BOTTOM", g, "BOTTOM", 0, 32)
    southText:SetTextColor(0.5, 0.6, 0.7, 0.6)
    southText:SetText("S (入口方)")

    g:Show()
end

function RaidMap.CreateUI()
    if mapFrame then
        return mapFrame
    end
    RaidMap.InitDB()

    local frameName = "BG.RaidMapFrame"
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    f:SetSize(780, 560)
    f.originalWidth = 780
    f.originalHeight = 560
    f.minW = 180
    f.minH = 36
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    f.defaultPoint = { "CENTER", UIParent, "CENTER", 0, 40 }
    local saved = BiaoGe.point[frameName]
    if saved and type(saved) == "table" and #saved >= 1 then
        local p1 = saved[1] or "CENTER"
        local p2 = UIParent
        local p3 = saved[3] or "CENTER"
        local p4 = saved[4] or 0
        local p5 = saved[5] or 40
        f:SetPoint(p1, p2, p3, p4, p5)
    else
        f:SetPoint(unpack(f.defaultPoint))
    end

    local savedScale = BiaoGe.RaidMap and BiaoGe.RaidMap.mapScale or 0.85
    f:SetScale(savedScale)

    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.2, 0.6, 0.9, 0.8)

    f.icons = {}
    f.isViewMode = false
    f.isLocked = false
    f.isMinimized = false

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not self.isLocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self, button)
        self:StopMovingOrSizing()
        if button == "RightButton" and IsControlKeyDown() then
            self:ClearAllPoints()
            self:SetPoint(unpack(self.defaultPoint))
        end
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint(1)
        BiaoGe.point[frameName] = { point, nil, relativePoint, xOfs, yOfs }
    end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetScale()
        local nextScale = math.max(0.5, math.min(1.5, cur + delta * 0.05))
        self:SetScale(nextScale)
        if BiaoGe and BiaoGe.RaidMap then
            BiaoGe.RaidMap.mapScale = nextScale
        end
    end)

    -- 场地贴图层 (全填充，支持 1024x1024 POT 标准贴图)
    local mapTex = f:CreateTexture(nil, "BACKGROUND")
    mapTex:SetAllPoints()
    f.mapTex = mapTex

    -- 顶部标题
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 17, "OUTLINE")
    title:SetPoint("TOPLEFT", 16, -10)
    title:SetTextColor(1, 0.85, 0.1)
    title:SetText("【奥杜尔】 战术站位图")
    f.title = title

    local selfNotice = f:CreateFontString(nil, "OVERLAY")
    selfNotice:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    selfNotice:SetPoint("LEFT", title, "RIGHT", 14, 0)
    selfNotice:SetTextColor(0.2, 1, 0.4)
    selfNotice:SetText("")
    f.selfNotice = selfNotice

    -- 最小化胶囊标题
    local minTitle = f:CreateFontString(nil, "OVERLAY")
    minTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    minTitle:SetPoint("LEFT", 12, 0)
    minTitle:SetTextColor(0.2, 0.8, 1)
    minTitle:SetText("战术站位图 ▾")
    minTitle:Hide()
    f.minTitle = minTitle

    -- 右上角操作区：关闭与最小化
    local btnClose = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    btnClose:SetSize(28, 28)
    btnClose:SetPoint("TOPRIGHT", -4, -4)
    btnClose:SetScript("OnClick", function()
        f:Hide()
        BG.PlaySound(1)
    end)

    local btnMin = CreateFrame("Button", nil, f)
    btnMin:SetSize(20, 20)
    btnMin:SetPoint("RIGHT", btnClose, "LEFT", -2, 0)
    btnMin:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
    btnMin:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
    btnMin:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    f.btnMin = btnMin

    btnMin:SetScript("OnClick", function()
        f.isMinimized = not f.isMinimized
        if f.isMinimized then
            f.savedPoint = { f:GetPoint(1) }
            f:SetSize(f.minW, f.minH)
            f.mapTex:Hide()
            if f.tacticalGrid then f.tacticalGrid:Hide() end
            f.title:Hide()
            f.selfNotice:Hide()
            f.topControls:Hide()
            for _, icon in ipairs(f.icons) do icon:Hide() end
            f.minTitle:Show()
            btnMin:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
        else
            f:SetSize(f.originalWidth, f.originalHeight)
            f.minTitle:Hide()
            f.title:Show()
            f.selfNotice:Show()
            f.topControls:Show()
            if not f.isUsingGrid then
                f.mapTex:Show()
            elseif f.tacticalGrid then
                f.tacticalGrid:Show()
            end
            for _, icon in ipairs(f.icons) do icon:Show() end
            btnMin:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
        end
        BG.PlaySound(1)
    end)

    -- 顶部控制栏 (Top Controls)
    local topControls = CreateFrame("Frame", nil, f)
    topControls:SetPoint("TOPLEFT", 14, -34)
    topControls:SetPoint("TOPRIGHT", -14, -34)
    topControls:SetHeight(28)
    f.topControls = topControls

    -- 1. BOSS 模板切换下拉菜单
    local dropBoss = LibBG and LibBG:Create_UIDropDownMenu("BG_RaidMapBossDropdown", topControls) or CreateFrame("Frame", "BG_RaidMapBossDropdown", topControls, "UIDropDownMenuTemplate")
    dropBoss:SetPoint("LEFT", -14, 0)
    f.dropBoss = dropBoss

    local function InitBossMenu(self, level)
        local bosses = RaidMap.GetAllBosses()
        for _, b in ipairs(bosses) do
            local info = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            info.text = b.name
            info.checked = (currentBossID == b.id)
            info.func = function()
                currentBossID = b.id
                if LibBG then LibBG:UIDropDownMenu_SetText(dropBoss, b.name) else UIDropDownMenu_SetText(dropBoss, b.name) end
                RaidMap.LoadBossTacticalPreset(b.id)
            end
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
        end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(dropBoss, InitBossMenu)
        LibBG:UIDropDownMenu_SetWidth(dropBoss, 135)
        LibBG:UIDropDownMenu_SetText(dropBoss, "钢铁议会")
    else
        UIDropDownMenu_Initialize(dropBoss, InitBossMenu)
        UIDropDownMenu_SetWidth(dropBoss, 135)
        UIDropDownMenu_SetText(dropBoss, "钢铁议会")
    end

    local dropBossClick = CreateFrame("Button", nil, dropBoss)
    dropBossClick:SetAllPoints()
    dropBossClick:SetFrameLevel(dropBoss:GetFrameLevel() + 2)
    dropBossClick:SetScript("OnClick", function()
        if LibBG and LibBG.ToggleDropDownMenu then
            LibBG:ToggleDropDownMenu(1, nil, dropBoss)
        else
            ToggleDropDownMenu(1, nil, dropBoss)
        end
        BG.PlaySound(1)
    end)

    -- 2. 查阅模式防误触状态条 (只读模式下显示，编辑模式下隐藏)
    local viewBadge = CreateFrame("Frame", nil, topControls)
    viewBadge:SetPoint("LEFT", dropBoss, "RIGHT", 8, 0)
    viewBadge:SetSize(360, 26)
    viewBadge:Hide()
    f.viewBadge = viewBadge

    local viewBadgeText = viewBadge:CreateFontString(nil, "OVERLAY")
    viewBadgeText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    viewBadgeText:SetPoint("LEFT", 0, 0)
    viewBadgeText:SetTextColor(1, 0.85, 0.1)
    viewBadgeText:SetText("|TInterface\\AddOns\\BGLite_Plus\\Media\\lock.png:14:14:0:0|t 团队查阅模式 (点位已锁定)")

    local btnUnlock = BG.CreateButton(viewBadge)
    btnUnlock:SetSize(88, 22)
    btnUnlock:SetPoint("LEFT", viewBadgeText, "RIGHT", 10, 0)
    btnUnlock:SetText(BG.STC_w1("|TInterface\\AddOns\\BGLite_Plus\\Media\\unlock.png:13:13:0:0|t 解锁编辑"))
    btnUnlock:SetScript("OnClick", function()
        RaidMap.SetViewMode(false)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图]|r 已解除锁定，您现在可以自由拖拽图标调整站位！")
    end)
    btnUnlock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("临时解锁编辑权限", 1, 1, 1)
        GameTooltip:AddLine("解除点位锁定状态，允许您在本地自由拖拽图标调整站位，或重新同步/广播。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnUnlock:SetScript("OnLeave", GameTooltip_Hide)

    -- 3. 编辑工具栏 (编辑模式下显示)
    local editControls = CreateFrame("Frame", nil, topControls)
    editControls:SetPoint("LEFT", dropBoss, "RIGHT", 8, 0)
    editControls:SetPoint("RIGHT", 0, 0)
    editControls:SetHeight(28)
    f.editControls = editControls

    -- 3.1 同步团队按钮
    local btnAuto = BG.CreateButton(editControls)
    btnAuto:SetSize(86, 24)
    btnAuto:SetPoint("LEFT", 0, 0)
    btnAuto:SetText(BG.STC_b1("同步团队..."))
    btnAuto:SetScript("OnClick", function()
        RaidMap.AutoAssignRosterToMap()
        BG.PlaySound(1)
    end)
    btnAuto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("一键同步团队人员并自动布阵", 1, 1, 1)
        GameTooltip:AddLine("抓取当前团队实际成员，按照职责自动填入指定点位：\n• 坦克自动填入主副坦位；\n• 治疗自动填入核心保坦位与团补位；\n• 近战自动排布在 BOSS 正脚后跟；\n• 远程自动在南半场大扇形分散保持距离。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnAuto:SetScript("OnLeave", GameTooltip_Hide)
    f.btnAuto = btnAuto

    -- 3.2 恢复默认站位按钮
    local btnReset = BG.CreateButton(editControls)
    btnReset:SetSize(86, 24)
    btnReset:SetPoint("LEFT", btnAuto, "RIGHT", 4, 0)
    btnReset:SetText(BG.STC_w1("恢复默认"))
    btnReset:SetScript("OnClick", function()
        currentMeleeMode = "group"
        currentRangedMode = "arc"
        RaidMap.LoadBossTacticalPreset(currentBossID, nil)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图]|r 已恢复当前 BOSS 的官方推荐标准 25 人示范战术阵型 (近战聚合+远程扇形)！")
    end)
    btnReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("恢复默认站位阵型", 1, 1, 1)
        GameTooltip:AddLine("一键重置当前 BOSS 的所有站位点，恢复官方推荐的标准战术点位阵型（消除所有手动拖动位移）。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnReset:SetScript("OnLeave", GameTooltip_Hide)
    -- 3.3 阵型布局与快速组织下拉菜单
    local dropFormation = LibBG and LibBG:Create_UIDropDownMenu("BG_RaidMapFormationDropdown", editControls) or CreateFrame("Frame", "BG_RaidMapFormationDropdown", editControls, "UIDropDownMenuTemplate")
    f.dropFormation = dropFormation

    local function InitFormationMenu(self, level)
        local infoM = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
        infoM.text = "|cffffd100── 近战组队形编排 ──|r"
        infoM.isTitle = true
        infoM.notCheckable = true
        if LibBG then LibBG:UIDropDownMenu_AddButton(infoM, level) else UIDropDownMenu_AddButton(infoM, level) end

        local meleeList = {
            { id = "group", name = "★ 聚合群组模式 (近战组 9人合一)" },
            { id = "arc", name = "背后弧形展开 (个人独立散点)" },
            { id = "double_row", name = "背后双排错位 (紧凑双层)" },
            { id = "two_groups", name = "左右分翼站位 (左侧/右侧)" },
            { id = "compact", name = "背后集中单点 (极度抱团)" },
        }
        for _, m in ipairs(meleeList) do
            local mi = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            mi.text = m.name
            mi.checked = (currentMeleeMode == m.id)
            mi.func = function()
                RaidMap.ApplyFormation(m.id, nil)
            end
            if LibBG then LibBG:UIDropDownMenu_AddButton(mi, level) else UIDropDownMenu_AddButton(mi, level) end
        end

        local infoR = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
        infoR.text = "|cffffd100── 远程组队形编排 ──|r"
        infoR.isTitle = true
        infoR.notCheckable = true
        if LibBG then LibBG:UIDropDownMenu_AddButton(infoR, level) else UIDropDownMenu_AddButton(infoR, level) end

        local rangedList = {
            { id = "arc", name = "南侧大扇形 (防点名大分散)" },
            { id = "two_groups", name = "左右双堆站位 (左翼/右翼分群)" },
            { id = "campfire", name = "中场环形抱团 (吃增益/集合)" },
            { id = "matrix", name = "后方整齐方阵 (三行矩阵)" },
        }
        for _, r in ipairs(rangedList) do
            local ri = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            ri.text = r.name
            ri.checked = (currentRangedMode == r.id)
            ri.func = function()
                RaidMap.ApplyFormation(nil, r.id)
            end
            if LibBG then LibBG:UIDropDownMenu_AddButton(ri, level) else UIDropDownMenu_AddButton(ri, level) end
        end

        local infoOpt = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
        infoOpt.text = "|cff00ff00★ 一键智能排布 (近战聚合+远程扇形)|r"
        infoOpt.notCheckable = true
        infoOpt.func = function()
            RaidMap.ApplyFormation("group", "arc")
        end
        if LibBG then LibBG:UIDropDownMenu_AddButton(infoOpt, level) else UIDropDownMenu_AddButton(infoOpt, level) end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(dropFormation, InitFormationMenu)
    else
        UIDropDownMenu_Initialize(dropFormation, InitFormationMenu)
    end

    local btnFormation = BG.CreateButton(editControls)
    btnFormation:SetSize(90, 24)
    btnFormation:SetPoint("LEFT", btnReset, "RIGHT", 4, 0)
    btnFormation:SetText(BG.STC_b1("阵型布局 ▾"))
    btnFormation:SetScript("OnClick", function(self)
        if LibBG and LibBG.ToggleDropDownMenu then
            LibBG:ToggleDropDownMenu(1, nil, dropFormation, self, 0, 0)
        else
            ToggleDropDownMenu(1, nil, dropFormation, self, 0, 0)
        end
        BG.PlaySound(1)
    end)
    btnFormation:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("近战与远程组队形快速组织", 1, 1, 1)
        GameTooltip:AddLine("一键快速重组当前地图上的近战组与远程组队形：\n• 近战组：背后弧形展开 (推荐/防重叠)、双排错位、左右分翼、集中单点；\n• 远程组：南侧大扇形 (防点名大分散)、左右双堆、环形抱团、三行矩阵。\n排列规则将写入广播协议，全团同步实时生效！", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnFormation:SetScript("OnLeave", GameTooltip_Hide)
    f.btnFormation = btnFormation

    -- 3.4 一键全团广播 (SendMap)
    local btnSend = BG.CreateButton(editControls)
    btnSend:SetSize(86, 24)
    btnSend:SetPoint("LEFT", btnFormation, "RIGHT", 4, 0)
    btnSend:SetText(BG.STC_g1("广播全团"))
    btnSend:SetScript("OnClick", function()
        RaidMap.BroadcastCurrentMap()
        BG.PlaySound(1)
    end)
    btnSend:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("一键全团广播当前战术站位图", 1, 1, 1)
        GameTooltip:AddLine("通过团队协议向全团广播推送当前站位图。\n所有安装了 BGLite_Plus、BiaoGe 或 TuanJian 的队员屏幕上将瞬间自动弹出站位图看板，并高亮各自点位！\n|cffff8800(仅团长与团队助理具有广播权限)|r", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnSend:SetScript("OnLeave", GameTooltip_Hide)
    f.btnSend = btnSend

    -- 3.4 快捷主动锁定按钮
    local btnLock = BG.CreateButton(editControls)
    btnLock:SetSize(62, 24)
    btnLock:SetPoint("LEFT", btnSend, "RIGHT", 4, 0)
    btnLock:SetText(BG.STC_y1("|TInterface\\AddOns\\BGLite_Plus\\Media\\lock.png:13:13:0:0|t 锁定"))
    btnLock:SetScript("OnClick", function()
        RaidMap.SetViewMode(true)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图]|r 已锁定站位点，防止意外拖动误触。")
    end)
    btnLock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("一键锁定站位", 1, 1, 1)
        GameTooltip:AddLine("编排完成后切换至查阅锁定状态，杜绝任何拖拽误触。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnLock:SetScript("OnLeave", GameTooltip_Hide)
    f.btnLock = btnLock

    -- 4. 历史战术预设下拉菜单
    local dropHistory = LibBG and LibBG:Create_UIDropDownMenu("BG_RaidMapHistoryDropdown", topControls) or CreateFrame("Frame", "BG_RaidMapHistoryDropdown", topControls, "UIDropDownMenuTemplate")
    dropHistory:SetPoint("RIGHT", 14, 0)
    f.dropHistory = dropHistory

    local function InitHistoryMenu(self, level)
        if not BiaoGe.maps or #BiaoGe.maps == 0 then
            local info = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            info.text = "暂无历史站位图"
            info.disabled = true
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
            return
        end

        for i, item in ipairs(BiaoGe.maps) do
            local info = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            local timeStr = date("%m/%d %H:%M", item.time or time())
            info.text = string.format("%s - %s (%s)", item.bossName or "未知", item.sender or "团长", timeStr)
            info.func = function()
                currentMapIndex = i
                RaidMap.RenderByCode(item.code, true)
            end
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
        end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(dropHistory, InitHistoryMenu)
        LibBG:UIDropDownMenu_SetWidth(dropHistory, 115)
        LibBG:UIDropDownMenu_SetText(dropHistory, "历史站位图")
    else
        UIDropDownMenu_Initialize(dropHistory, InitHistoryMenu)
        UIDropDownMenu_SetWidth(dropHistory, 115)
        UIDropDownMenu_SetText(dropHistory, "历史站位图")
    end

    local dropHistoryClick = CreateFrame("Button", nil, dropHistory)
    dropHistoryClick:SetAllPoints()
    dropHistoryClick:SetFrameLevel(dropHistory:GetFrameLevel() + 2)
    dropHistoryClick:SetScript("OnClick", function()
        if LibBG and LibBG.ToggleDropDownMenu then
            LibBG:ToggleDropDownMenu(1, nil, dropHistory)
        else
            ToggleDropDownMenu(1, nil, dropHistory)
        end
        BG.PlaySound(1)
    end)

    -- 底部操作与交互提示
    local bottomTip = f:CreateFontString(nil, "OVERLAY")
    bottomTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    bottomTip:SetPoint("BOTTOMLEFT", 16, 8)
    bottomTip:SetTextColor(0.55, 0.65, 0.75, 0.85)
    bottomTip:SetText("交互提示: 鼠标拖拽头像可调换站位 | 滚轮微调缩放 | 空白处拖拽移动窗口 | Ctrl+右键重置窗口位置")
    f.bottomTip = bottomTip

    -- 模式切换器
    function RaidMap.SetViewMode(isView)
        f.isViewMode = isView
        if isView then
            f.editControls:Hide()
            f.viewBadge:Show()
            f.bottomTip:SetText("当前为【团队查阅模式】: 点位已锁定以防误触 | 滚轮可微调缩放 | 点击上方 [解锁编辑] 可自由调位")
        else
            f.viewBadge:Hide()
            f.editControls:Show()
            f.bottomTip:SetText("交互提示: 鼠标拖拽头像可调换站位 | 滚轮微调缩放 | 空白处拖拽移动窗口 | Ctrl+右键重置窗口位置")
        end
    end

    mapFrame = f
    BG.RaidMapFrame = f
    _G["BG.RaidMapFrame"] = f
    return f
end

--------------------------------------------------------------------------------
-- 7. 纯净战术站位图标渲染器 (彻底移除突兀小圆圈，精致黑边裁剪，光晕高亮专属站位)
--------------------------------------------------------------------------------
local function CreateDraggablePointIcon(parent, level, x, y, width, height, iconType, iconTex, coord,
                                       broderShow, broderColor,
                                       numText, numColor,
                                       playerText, playerColor, role, members)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    f:SetPoint("CENTER", parent, "TOPLEFT", x, y)
    f:SetFrameLevel(parent:GetFrameLevel() + level)
    f.x = x
    f.y = y
    f.role = role
    f.playerText = playerText
    f.members = members

    local isBoss = (role == "boss")
    local isNpc = (role == "npc")
    local isMeleeGroup = (role == "melee_group")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    f.icon = icon

    if iconType == "boss" then
        icon:SetTexture(iconTex or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    else
        icon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if coord and #coord == 4 then
        icon:SetTexCoord(unpack(coord))
    else
        -- 裁剪暴雪原生图标自带的黑色硬边框，视觉更精致圆润
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- 序号与名字
    local numFS = f:CreateFontString(nil, "OVERLAY")
    numFS:SetFont(BIAOGE_TEXT_FONT, isMeleeGroup and 14 or 13, "OUTLINE")
    numFS:SetPoint("CENTER", 0, 0)
    numFS:SetText(numText or "")
    if numColor and #numColor >= 3 then
        numFS:SetTextColor(unpack(numColor))
    end
    f.numFS = numFS

    local nameFS = f:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(BIAOGE_TEXT_FONT, (isBoss or isMeleeGroup) and 13 or 12, "OUTLINE")
    nameFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
    nameFS:SetText(playerText or "")
    if isBoss then
        nameFS:SetTextColor(1, 0.35, 0.35)
    elseif isMeleeGroup then
        nameFS:SetTextColor(1, 0.85, 0.1)
    elseif playerColor and #playerColor >= 3 then
        nameFS:SetTextColor(unpack(playerColor))
    end
    f.nameFS = nameFS

    -- 自己的专属站位高亮外框：纯净金色光晕
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("CENTER")
    glow:SetSize(width + 20, height + 20)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.9, 0.2, 0.95)
    glow:Hide()
    f.glow = glow

    -- 鼠标交互与自由拖拽调位 (查阅锁定模式下彻底阻断，防止误触)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self, button)
    end)
    f:SetScript("OnDragStart", function(self)
        if parent.isViewMode then return end
        self.isDragging = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isDragging then
            self.isDragging = false
            self:StopMovingOrSizing()
            local s = parent:GetEffectiveScale() or 1
            local curX, curY = GetCursorPosition()
            curX = curX / s
            curY = curY / s
            local pLeft = parent:GetLeft()
            local pTop = parent:GetTop()
            if pLeft and pTop then
                local relX = curX - pLeft
                local relY = curY - pTop
                self.x = relX
                self.y = relY
                self:ClearAllPoints()
                self:SetPoint("CENTER", parent, "TOPLEFT", relX, relY)
            end
        end
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if isBoss then
            GameTooltip:AddLine("【首领 BOSS】 " .. (playerText ~= "" and playerText or "首领"), 1, 0.25, 0.25)
            local bossData = RaidMap.GetBoss(currentBossID)
            if bossData and bossData.sub and bossData.sub ~= "" then
                GameTooltip:AddLine(bossData.sub, 0.8, 0.8, 0.8, true)
            end
            if bossData and bossData.tacticTip and bossData.tacticTip ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(bossData.tacticTip, 1, 0.85, 0.1, true)
            end
        elseif isMeleeGroup then
            GameTooltip:AddLine("【⚔️ 战术群组】 " .. (playerText ~= "" and playerText or "近战组"), 1, 0.85, 0.1)
            GameTooltip:AddLine("战术职责: BOSS 正背后脚后跟集中输出 (全员集合点)", 0.6, 0.85, 1)
            if self.members and #self.members > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("包含近战成员 (%d人):", #self.members), 1, 1, 1)
                for _, m in ipairs(self.members) do
                    local mName = m.name or "队员"
                    local mCls = m.class
                    local cCode = "|cffffffff"
                    if mCls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[mCls] then
                        cCode = RAID_CLASS_COLORS[mCls].colorStr and ("|c" .. RAID_CLASS_COLORS[mCls].colorStr) or cCode
                    end
                    local specText = m.specName and (" (" .. m.specName .. ")") or ""
                    GameTooltip:AddLine("  • " .. cCode .. mName .. "|r" .. "|cffaaaaaa" .. specText .. "|r")
                end
            end
            if not parent.isViewMode then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("提示: 拖动此标记可整体调整近战集合点；点击顶部【阵型布局】可随时展开为个人散点", 0.3, 1, 0.5, true)
            end
            GameTooltip:Show()
            return
        elseif isNpc then
            GameTooltip:AddLine("【战术标记】 " .. (playerText ~= "" and playerText or "核心地标"), 0.3, 0.9, 1)
        else
            if playerText and playerText ~= "" then
                GameTooltip:AddLine(playerText, playerColor[1] or 1, playerColor[2] or 1, playerColor[3] or 1)
            end
            if numText and numText ~= "" then
                GameTooltip:AddLine("分配站位序号: " .. numText .. " 号位", 1, 0.82, 0)
            end
            if role and role ~= "" then
                local roleDesc
                if role == "tank" then
                    roleDesc = "坦克位 (背对团队/定怪面向正北)"
                elseif role == "healer" then
                    if self.isTankHealer then
                        roleDesc = "核心保坦治疗 (紧贴坦克安全内圈，压制/牺牲/道标无死角覆盖)"
                    else
                        roleDesc = "团补大团治疗 (全团中内圈居中辐射，全方位覆盖近战与远程)"
                    end
                elseif role == "melee" then
                    roleDesc = "近战输出位 (BOSS背后脚后跟集中输出)"
                elseif role == "ranged" then
                    roleDesc = "远程输出位 (外圈分散/保持10码防连线)"
                else
                    roleDesc = role
                end
                GameTooltip:AddLine("战术职责: " .. roleDesc, 0.6, 0.85, 1)
            end
        end

        if parent.isViewMode then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|TInterface\\AddOns\\BGLite_Plus\\Media\\lock.png:13:13:0:0|t 当前为【团队查阅模式】(点位已锁定防误触，点击顶部可临时解锁)", 1, 0.8, 0)
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("提示: 鼠标按住左键可自由拖动调整站位", 0.3, 1, 0.5)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    f:Show()
    tinsert(parent.icons, f)
    return f
end

-- 8. 阵型实时重组与排布执行器 (ApplyFormation)
function RaidMap.ApplyFormation(newMeleeMode, newRangedMode)
    if newMeleeMode then currentMeleeMode = newMeleeMode end
    if newRangedMode then currentRangedMode = newRangedMode end
    if BiaoGe and BiaoGe.RaidMap then
        BiaoGe.RaidMap.meleeMode = currentMeleeMode
        BiaoGe.RaidMap.rangedMode = currentRangedMode
    end

    local f = mapFrame
    if not f or not f:IsShown() then return end

    -- 重新加载当前 BOSS 站位，根据新的队形模式重新生成点位（支持群组与散点无缝切换）
    RaidMap.LoadBossTacticalPreset(currentBossID, RaidMap.lastRosterData)

    local mName = RaidMap.MELEE_MODE_NAMES and RaidMap.MELEE_MODE_NAMES[currentMeleeMode] or currentMeleeMode
    local rName = RaidMap.RANGED_MODE_NAMES and RaidMap.RANGED_MODE_NAMES[currentRangedMode] or currentRangedMode
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[战术站位图]|r 已应用队形布局：近战【%s】、远程【%s】。点击【广播全团】即可推送到全团！", mName, rName))
end

function RaidMap.RefreshSelfHighlight(f)
    if not f or not f.icons then return end
    local myName = UnitName("player")
    local mySpot = nil
    local isMeleeGroupMember = false

    for _, icon in ipairs(f.icons) do
        local isMine = false
        local pText = icon.playerText or (icon.nameFS and icon.nameFS:GetText())
        if pText and pText ~= "" and myName and (pText == myName) then
            isMine = true
        elseif icon.role == "melee_group" and icon.members and myName then
            for _, m in ipairs(icon.members) do
                if m.name == myName then
                    isMine = true
                    isMeleeGroupMember = true
                    break
                end
            end
        end

        if isMine and not mySpot then
            mySpot = icon
            if icon.glow then icon.glow:Show() end
        else
            if icon.glow then icon.glow:Hide() end
        end
    end

    if mySpot then
        if f.selfNotice then
            if isMeleeGroupMember then
                f.selfNotice:SetText("【您的专属站位: ⚔️ 近战集合组 (BOSS正背后输出)】")
            else
                local numStr = (mySpot.numFS and mySpot.numFS:GetText() ~= "") and (mySpot.numFS:GetText() .. "号位") or "指定点"
                f.selfNotice:SetText(string.format("【您的专属站位: %s (%s)】", mySpot.playerText or "", numStr))
            end
        end
    else
        local bossData = RaidMap.GetBoss(currentBossID)
        local subDesc = bossData and bossData.sub or ""
        if f.selfNotice then
            f.selfNotice:SetText(subDesc ~= "" and ("(" .. subDesc .. ")") or "")
        end
    end
end

--------------------------------------------------------------------------------
-- 8. 核心 BOSS 专属预设构建与贴图加载器
--------------------------------------------------------------------------------
function RaidMap.LoadBossTacticalPreset(bossID, rosterData)
    local f = RaidMap.CreateUI()
    if not f then return end
    bossID = bossID or 5
    currentBossID = bossID

    local width, height = 780, 560
    f.originalWidth = width
    f.originalHeight = height
    f:SetSize(width, height)

    -- 若未指定阵容但当前处于队伍或团队中，自动提取真实成员
    if not rosterData and RaidMap.GetAutoRosterData and GetNumGroupMembers() > 0 then
        rosterData = RaidMap.GetAutoRosterData()
    end
    RaidMap.lastRosterData = rosterData

    -- 从数据中心按需提取当前 BOSS 战术数据
    local bossData = RaidMap.GetBoss(bossID)
    if not bossData then
        local all = RaidMap.GetAllBosses()
        for _, b in ipairs(all) do
            if b.id == bossID then bossData = b; break end
        end
    end

    local fbName = bossData and (bossData.fbName or "团本") or "奥杜尔"
    local bossName = bossData and bossData.name or "钢铁议会"
    local subDesc = bossData and bossData.sub or ""

    f.title:SetText(string.format("【%s】 %s", fbName, bossName))
    f.selfNotice:SetText(subDesc ~= "" and ("(" .. subDesc .. ")") or "")

    -- 同步更新下拉菜单文本
    if f.dropBoss then
        if LibBG and LibBG.UIDropDownMenu_SetText then
            LibBG:UIDropDownMenu_SetText(f.dropBoss, bossName)
        else
            UIDropDownMenu_SetText(f.dropBoss, bossName)
        end
    end

    -- 背景底图渲染机制：优先加载 1024x1024 高清实景场地鸟瞰背景
    local hasRealMap = bossData and bossData.hasRealMap and bossData.mapTex
    if hasRealMap then
        f.isUsingGrid = false
        f.mapTex:SetTexture(bossData.mapTex)
        f.mapTex:Show()
        if f.tacticalGrid then f.tacticalGrid:Hide() end
    else
        f.isUsingGrid = true
        f.mapTex:Hide()
        DrawProceduralTacticalGrid(f, width, height, bossID)
    end

    for _, icon in ipairs(f.icons) do icon:Hide() end
    wipe(f.icons)

    local cx, cy = width / 2, -height / 2 + 10

    -- 1. 数据驱动：动态渲染 BOSS 首领与战术特定目标标记
    if bossData and bossData.targets and #bossData.targets > 0 then
        for _, t in ipairs(bossData.targets) do
            local tx = cx + (t.relX or 0)
            local ty = cy + (t.relY or 0)
            local sz = t.size or ((t.type == "boss") and 50 or 36)
            local c = t.color or { 1, 1, 1 }
            local iconTex = t.iconTex or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
            CreateDraggablePointIcon(f, 2, tx, ty, sz, sz, (t.type == "boss" and "boss" or "tex"), iconTex, nil,
                                    1, c, "", { 1, 1, 1 }, t.name or "", c, t.type or "npc")
        end
    else
        CreateDraggablePointIcon(f, 2, cx, cy + 90, 50, 50, "boss", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", nil,
                                1, { 1, 0.2, 0.2 }, "", { 1, 1, 1 }, bossName, { 1, 0.3, 0.3 }, "boss")
    end

    -- 2. 数据驱动：构建推荐阵型点位 (支持根据实际阵容 rosterData 动态弹性生成)
    local spots = nil
    if bossData and bossData.buildSpots then
        spots = bossData.buildSpots(cx, cy, width, height, rosterData)
    else
        spots = RaidMap.GenerateDynamicTacticalSpots(cx, cy, nil, rosterData)
    end

    if spots then
        for _, s in ipairs(spots) do
            local cr, cg, cb = 1, 1, 1
            if RAID_CLASS_COLORS and s.cls and RAID_CLASS_COLORS[s.cls] then
                local c = RAID_CLASS_COLORS[s.cls]; cr, cg, cb = c.r, c.g, c.b
            end
            local classIcons = RaidMap.CLASS_ICONS or {}
            local iconTex = s.specIcon or (s.cls and classIcons[s.cls]) or "Interface\\Icons\\INV_Misc_QuestionMark"
            local isMeleeGroup = (s.role == "melee_group")
            local iconSz = (s.role == "tank") and 30 or (isMeleeGroup and 36 or 28)
            local pointIcon = CreateDraggablePointIcon(f, 3, s.x, s.y, iconSz, iconSz, "tex", iconTex, nil,
                                                      1, { cr, cg, cb }, s.num or "", { 1, 1, 1 }, s.name or "", { cr, cg, cb }, s.role or "player", s.members)
            pointIcon.members = s.members
            pointIcon.isTankHealer = s.isTankHealer
        end
    end

    RaidMap.RefreshSelfHighlight(f)
    RaidMap.SetViewMode(false)
    f:Show()
    f:Raise()
end

RaidMap.ShowDemoTacticalBoard = function(bossID)
    RaidMap.LoadBossTacticalPreset(bossID or 5)
end

--------------------------------------------------------------------------------
-- 9. 智能同步团队职责与动态阵型重塑算法 (Dynamic Roster Reconstruction)
--------------------------------------------------------------------------------
function RaidMap.GetAutoRosterData()
    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then return nil end

    local talentsHub = ns.RaidTalents or _G.BGLite_RaidTalents
    local tanks = {}
    local tankHealers = {}
    local raidHealers = {}
    local melees = {}
    local rangeds = {}
    local seenNames = {}

    for i = 1, numMembers do
        local unit, name, class, role
        if IsInRaid and IsInRaid() then
            unit = "raid" .. i
            local rName, _, _, _, _, rClass, _, _, _, rRole = GetRaidRosterInfo(i)
            name = rName
            class = rClass
            role = rRole
        else
            if i == numMembers then
                unit = "player"
            else
                unit = "party" .. i
            end
            name = UnitName(unit)
            local _, rClass = UnitClass(unit)
            class = rClass
            if UnitGroupRolesAssigned then
                role = UnitGroupRolesAssigned(unit)
            end
        end

        name = name and string.match(name, "^([^-]+)")
        if name and not seenNames[name] then
            seenNames[name] = true
            local mInfo = talentsHub and (talentsHub.GetMember(name) or talentsHub.GetMember(unit))
            local specRole = mInfo and mInfo.specRole
            local specName = mInfo and mInfo.specName
            local specIcon = mInfo and mInfo.specIcon

            local isTank = (role == "MAINTANK" or role == "MAINASSIST" or role == "TANK" or specRole == "tank")
            if not isTank and specName then
                if string.find(specName, "防护") or string.find(specName, "鲜血") then
                    isTank = true
                end
            end

            if isTank then
                tinsert(tanks, { name = name, class = class, specName = specName, specIcon = specIcon, role = "tank" })
            elseif specRole == "healer" or role == "HEALER" or (specName and (string.find(specName, "神圣") or string.find(specName, "戒律") or string.find(specName, "恢复"))) then
                local isTankHealer = false
                if class == "PALADIN" then
                    isTankHealer = true
                elseif class == "PRIEST" then
                    if specName and string.find(specName, "戒律") then
                        isTankHealer = true
                    elseif not specName or specName == "未知" then
                        isTankHealer = true
                    end
                end

                if isTankHealer and #tankHealers < 2 then
                    tinsert(tankHealers, { name = name, class = class, specName = specName, specIcon = specIcon, role = "healer", isTankHealer = true })
                else
                    tinsert(raidHealers, { name = name, class = class, specName = specName, specIcon = specIcon, role = "healer" })
                end
            elseif specRole == "melee"
                   or (class == "ROGUE" or class == "WARRIOR" or class == "DEATHKNIGHT")
                   or (specName and (string.find(specName, "惩戒") or string.find(specName, "增强") or string.find(specName, "狂暴") or string.find(specName, "武器") or string.find(specName, "战斗") or string.find(specName, "刺杀") or string.find(specName, "敏锐") or (string.find(specName, "野性") and not isTank))) then
                tinsert(melees, { name = name, class = class, specName = specName, specIcon = specIcon, role = "melee" })
            else
                tinsert(rangeds, { name = name, class = class, specName = specName, specIcon = specIcon, role = "ranged" })
            end
        end
    end

    if #tankHealers == 0 and #raidHealers > 0 then
        local primaryHealer = tremove(raidHealers, 1)
        primaryHealer.isTankHealer = true
        tinsert(tankHealers, primaryHealer)
    end

    return {
        tanks = tanks,
        tankHealers = tankHealers,
        raidHealers = raidHealers,
        melees = melees,
        rangeds = rangeds,
    }
end

function RaidMap.AutoAssignRosterToMap()
    local f = mapFrame
    if not f or not f:IsShown() then return end

    local rosterData = RaidMap.GetAutoRosterData()
    if not rosterData then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 战术站位图]|r 当前未处于队伍或团队中，已恢复标准示范站位。")
        RaidMap.LoadBossTacticalPreset(currentBossID, nil)
        return
    end

    RaidMap.LoadBossTacticalPreset(currentBossID, rosterData)

    local totalMembers = #rosterData.tanks + #rosterData.tankHealers + #rosterData.raidHealers + #rosterData.melees + #rosterData.rangeds
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[BGLite 战术站位图]|r 已根据当前团队阵容智能重塑阵型：共 %d 名成员 (坦克 %d, 核心保坦奶 %d, 团补奶 %d, 近战 %d, 远程 %d)！",
        totalMembers, #rosterData.tanks, #rosterData.tankHealers, #rosterData.raidHealers, #rosterData.melees, #rosterData.rangeds))
end

--------------------------------------------------------------------------------
-- 10. 一键全团广播 (SendMap - 完全兼容 BiaoGeAIMap 协议)
--------------------------------------------------------------------------------
function RaidMap.BroadcastCurrentMap()
    local f = mapFrame
    if not f or not f:IsShown() then return end

    local inRaid = IsInRaid and IsInRaid()
    local inGroup = IsInGroup and IsInGroup()
    if not inRaid and not inGroup then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[BGLite 战术站位图]|r 您当前不在队伍或团队中，无法广播站位图。")
        return
    end

    if inRaid then
        local isLeader = UnitIsGroupLeader("player")
        local isAssist = UnitIsGroupAssistant("player")
        if not isLeader and not isAssist then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[BGLite 战术站位图]|r 权限拦截：只有团队领袖（团长）或团队助理可以向全团广播站位图，以防误触打乱全团战术！")
            return
        end
    end

    local mapWidth, mapHeight = f:GetSize()
    mapWidth = math.floor(mapWidth)
    mapHeight = math.floor(mapHeight)

    local bossData = RaidMap.GetBoss(currentBossID)
    local bossName = bossData and bossData.name or "奥杜尔战术"
    local FB = bossData and bossData.fb or "ULDtitan"

    local fmtTag = string.format("FMT:m=%s,r=%s", currentMeleeMode or "arc", currentRangedMode or "arc")
    local str = format("%s&&%d&&%d&&%d&&%s&&%s^^", FB, currentBossID, mapWidth, mapHeight, fmtTag, bossName)

    local iconStr = ""
    for _, icon in ipairs(f.icons) do
        local level = icon:GetFrameLevel() or 3
        local x = math.floor(icon.x or 0)
        local y = math.floor(icon.y or 0)
        local w = math.floor(icon:GetWidth())
        local iconType = (icon.role == "boss") and "boss" or "tex"
        local iconTex = icon.icon:GetTexture() or ""
        local numText = icon.numFS and icon.numFS:GetText() or ""
        local playerText = icon.nameFS and icon.nameFS:GetText() or ""

        iconStr = iconStr .. format("%d¦%d¦%d¦%d¦%d¦%s¦%s¦%s¦%s¦%s¦%s¦%d¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f&&",
            level, x, y, w, w, iconType, iconTex,
            "", "", "", "",
            1, 1.0, 1.0, 1.0,
            numText, 1.0, 1.0, 1.0,
            playerText, 0.2, 0.8, 1.0
        )
    end

    str = str .. iconStr
    local compressed = SafeCompress(str)
    local code = Base64Encode(compressed)

    local END_MARK = "!END!"
    local MAX_LEN = 250
    code = "!AIMAP!" .. code .. END_MARK

    local totalLen = string.len(code)
    local curPos = 1
    local msgs = {}
    while curPos <= totalLen do
        local targetEnd = math.min(curPos + MAX_LEN - 1, totalLen)
        local chunk = string.sub(code, curPos, targetEnd)
        tinsert(msgs, chunk)
        curPos = targetEnd + 1
    end

    local channel = inRaid and "RAID" or "PARTY"
    local chIndex = 0
    local function GetNextChannel()
        chIndex = chIndex % channelCount + 1
        return channelPrefix .. chIndex
    end

    for i, m in ipairs(msgs) do
        local targetCh = GetNextChannel()
        C_Timer.After((i - 1) * 0.05, function()
            SendAddonMessageSafe(targetCh, m, channel)
            if i == 1 or i == #msgs then
                SendAddonMessageSafe(channelPrefix, m, channel)
            end
        end)
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 战术站位图]|r 已成功将【%s】站位图广播至 %s 频道 (共 %d 个切片数据包)！全团队员将自动弹出。", bossName, channel, #msgs))
end

--------------------------------------------------------------------------------
-- 11. 接收与解码渲染引擎 (RenderByCode)
--------------------------------------------------------------------------------
function RaidMap.RenderByCode(code, notSave, sender)
    if not code or code == "" then return false end
    local f = RaidMap.CreateUI()

    local decoded = Base64Decode(code)
    local str = SafeDecompress(decoded)
    if not str or str == "" then
        str = decoded
    end
    if not str or str == "" then return false end

    local info, icons = SafeSplit("^^", str)
    if not info then return false end

    local FB, bossIndex, mapWidth, mapHeight, childIndex, bossName = SafeSplit("&&", info)
    bossIndex = tonumber(bossIndex) or 5
    mapWidth = tonumber(mapWidth) or 780
    mapHeight = tonumber(mapHeight) or 560

    if not notSave then
        table.insert(BiaoGe.maps, 1, {
            time = time(),
            sender = sender or "团长",
            code = code,
            FB = FB,
            bossIndex = bossIndex,
            bossName = bossName,
            formation = childIndex,
        })
        while #BiaoGe.maps > 10 do table.remove(BiaoGe.maps, #BiaoGe.maps) end
    end

    f.originalWidth = mapWidth
    f.originalHeight = mapHeight
    f:SetSize(mapWidth, mapHeight)
    currentBossID = bossIndex
    if f.dropBoss then
        if LibBG and LibBG.UIDropDownMenu_SetText then
            LibBG:UIDropDownMenu_SetText(f.dropBoss, bossName or "战术站位")
        else
            UIDropDownMenu_SetText(f.dropBoss, bossName or "战术站位")
        end
    end

    local fmtNotice = ""
    if childIndex and type(childIndex) == "string" and string.find(childIndex, "^FMT:") then
        local mMode = string.match(childIndex, "m=([%a_]+)")
        local rMode = string.match(childIndex, "r=([%a_]+)")
        if mMode then currentMeleeMode = mMode end
        if rMode then currentRangedMode = rMode end
        local mName = RaidMap.MELEE_MODE_NAMES and RaidMap.MELEE_MODE_NAMES[currentMeleeMode]
        local rName = RaidMap.RANGED_MODE_NAMES and RaidMap.RANGED_MODE_NAMES[currentRangedMode]
        if mName or rName then
            fmtNotice = string.format(" [%s | %s]", mName or "近战", rName or "远程")
        end
    end

    f.title:SetText(string.format("【%s】 %s%s", FB or "团本", bossName or "战术站位", fmtNotice))
    f.selfNotice:SetText(string.format("(推送者: %s)", sender or "团长"))

    -- 接收端背景贴图渲染
    local bossData = RaidMap.GetBoss(bossIndex)
    local hasRealMap = bossData and bossData.hasRealMap and bossData.mapTex
    if hasRealMap then
        f.isUsingGrid = false
        f.mapTex:SetTexture(bossData.mapTex)
        f.mapTex:Show()
        if f.tacticalGrid then f.tacticalGrid:Hide() end
    else
        f.isUsingGrid = true
        f.mapTex:Hide()
        DrawProceduralTacticalGrid(f, mapWidth, mapHeight, bossIndex)
    end

    for _, icon in ipairs(f.icons) do icon:Hide() end
    wipe(f.icons)

    if icons and icons ~= "" then
        local iconList = { SafeSplit("&&", icons) }
        for _, iconStr in ipairs(iconList) do
            if iconStr and iconStr ~= "" then
                local level, x, y, width, height, iconType, iconTex,
                      left, right, top, bottom,
                      broderShow, broder_r, broder_g, broder_b,
                      numText, num_r, num_g, num_b,
                      playerText, player_r, player_g, player_b = SafeSplit("¦", iconStr)

                level = tonumber(level) or 3
                x = tonumber(x) or 0
                y = tonumber(y) or 0
                width = tonumber(width) or 28
                height = tonumber(height) or width

                local isMeleeGroup = (numText == "⚔️" or (playerText and string.find(playerText, "近战组")))
                if isMeleeGroup then
                    width = 36
                    height = 36
                end

                local coord = nil
                if left and right and top and bottom and left ~= "" then
                    coord = { tonumber(left) or 0, tonumber(right) or 1, tonumber(top) or 0, tonumber(bottom) or 1 }
                end

                local broderColor = { tonumber(broder_r) or 1, tonumber(broder_g) or 1, tonumber(broder_b) or 1 }
                local numColor = { tonumber(num_r) or 1, tonumber(num_g) or 1, tonumber(num_b) or 1 }
                local playerColor = { tonumber(player_r) or 1, tonumber(player_g) or 1, tonumber(player_b) or 1 }

                local members = nil
                if isMeleeGroup and RaidMap.GetAutoRosterData then
                    local rData = RaidMap.GetAutoRosterData()
                    if rData and rData.melees then
                        members = rData.melees
                    end
                end

                local role = (iconType == "boss" and "boss") or (isMeleeGroup and "melee_group") or "player"

                local pointIcon = CreateDraggablePointIcon(f, level, x, y, width, height, iconType, iconTex, coord,
                                         tonumber(broderShow) or 1, broderColor,
                                         numText, numColor, playerText, playerColor, role, members)
                pointIcon.members = members
            end
        end
    end

    RaidMap.RefreshSelfHighlight(f)
    RaidMap.SetViewMode(true)
    f:Show()
    return true
end

--------------------------------------------------------------------------------
-- 12. 网络消息监听与组装 (CHAT_MSG_ADDON)
--------------------------------------------------------------------------------
local receiveBuffers = {}
local isReceiving = {}

local function IsAuthorizedSender(sender, distType)
    if not sender or sender == "" then return false end
    if distType == "PARTY" then return true end
    local cleanSender = string.match(sender, "^([^-]+)") or sender
    local myName = UnitName("player")
    if cleanSender == myName then return true end

    if IsInRaid and IsInRaid() then
        local num = GetNumGroupMembers()
        for i = 1, num do
            local rName, rank = GetRaidRosterInfo(i)
            if rName then
                local cleanR = string.match(rName, "^([^-]+)") or rName
                if cleanR == cleanSender then
                    if rank and rank >= 1 then
                        return true
                    end
                end
            end
        end
        if num <= 5 then
            for i = 1, num do
                local rName = GetRaidRosterInfo(i)
                if rName and (string.match(rName, "^([^-]+)") == cleanSender) then
                    return true
                end
            end
        end
    end
    if BG and (BG.DEBUG or BGDEBUG) then return true end
    return false
end

local function OnReceiveComplete(sender, codes)
    local fullCode = table.concat(codes)
    local code = fullCode:match("^!AIMAP!(.+)!END!$")
    if not code then return end

    local cleanSender = string.match(sender, "^([^-]+)") or sender
    local rdb = BiaoGe and BiaoGe.RaidMap
    local autoPopup = (rdb == nil) or (rdb.enableAutoPopup ~= false)

    local ok = RaidMap.RenderByCode(code, false, cleanSender)
    if ok then
        RaidMap.SetViewMode(true)
        if autoPopup then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 战术站位图]|r 收到来自 |cff00ff00%s|r 的战术站位图推送 (已进入安全查阅模式)！", cleanSender))
            BG.PlaySound(1)
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[BGLite 战术站位图]|r 收到来自 |cff00ff00%s|r 的站位图推送 (已静默收录至历史记录，输入 /bgmap 随时查看)。", cleanSender))
        end
    end
end

local addonListener = CreateFrame("Frame")
addonListener:RegisterEvent("CHAT_MSG_ADDON")
addonListener:SetScript("OnEvent", function(self, event, prefix, msg, distType, sender)
    if not MAP_PREFIXES[prefix] then return end
    if distType ~= "RAID" and distType ~= "PARTY" then return end
    if not IsAuthorizedSender(sender, distType) then return end

    if msg:match("^!AIMAP!") then
        isReceiving[sender] = true
        receiveBuffers[sender] = {}
    end

    if isReceiving[sender] then
        table.insert(receiveBuffers[sender], msg)
        if msg:match("!END!$") then
            local codes = receiveBuffers[sender]
            isReceiving[sender] = nil
            receiveBuffers[sender] = nil
            OnReceiveComplete(sender, codes)
        end
    end
end)

--------------------------------------------------------------------------------
-- 13. 团队工具内专属控制卡片构建
--------------------------------------------------------------------------------
function RaidMap.CreateRaidToolPanel(parent)
    if not parent then return end
    RaidMap.InitDB()

    local box = CreateFrame("Frame", "BG_RaidMapToolBox", parent, "BackdropTemplate")
    box:SetSize(315, 68)
    box:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 12)
    box:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.06, 0.08, 0.12, 0.94)
    box:SetBackdropBorderColor(0.25, 0.75, 1.0, 0.85)

    local title = box:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -6)
    title:SetText(BG.STC_b1("【战术站位图 (奥杜尔/通用)】"))

    local cbAuto = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    cbAuto:SetSize(18, 18)
    cbAuto:SetPoint("TOPRIGHT", -8, -4)
    cbAuto.text = cbAuto:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cbAuto.text:SetPoint("RIGHT", cbAuto, "LEFT", -2, 0)
    cbAuto.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    cbAuto.text:SetText("自动弹出")
    cbAuto:SetChecked(BiaoGe.RaidMap.enableAutoPopup)
    cbAuto:SetScript("OnClick", function(self)
        BiaoGe.RaidMap.enableAutoPopup = self:GetChecked()
        BG.PlaySound(1)
    end)
    cbAuto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("站位图自动接收弹出", 1, 1, 1)
        GameTooltip:AddLine("勾选(默认)：当团长或助理广播站位图时，屏幕上自动弹出站位图看板并高亮您的站位。\n反选：仅静默存入历史记录，不打扰屏幕。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    cbAuto:SetScript("OnLeave", GameTooltip_Hide)

    local btnOpen = BG.CreateButton(box)
    btnOpen:SetSize(90, 24)
    btnOpen:SetPoint("BOTTOMLEFT", 10, 8)
    btnOpen:SetText("打开站位图")
    btnOpen:SetScript("OnClick", function()
        if mapFrame and mapFrame:IsShown() then
            mapFrame:Hide()
        else
            if BiaoGe.maps and #BiaoGe.maps > 0 and BiaoGe.maps[1].code then
                RaidMap.RenderByCode(BiaoGe.maps[1].code, true)
            else
                RaidMap.LoadBossTacticalPreset(5)
            end
        end
        BG.PlaySound(1)
    end)

    local btnPreset = BG.CreateButton(box)
    btnPreset:SetSize(100, 24)
    btnPreset:SetPoint("LEFT", btnOpen, "RIGHT", 6, 0)
    btnPreset:SetText("奥杜尔预设")
    btnPreset:SetScript("OnClick", function()
        RaidMap.LoadBossTacticalPreset(currentBossID or 5)
        BG.PlaySound(1)
    end)

    local btnReset = BG.CreateButton(box)
    btnReset:SetSize(86, 24)
    btnReset:SetPoint("LEFT", btnPreset, "RIGHT", 6, 0)
    btnReset:SetText("重置位置")
    btnReset:SetScript("OnClick", function()
        local f = RaidMap.CreateUI()
        f:ClearAllPoints()
        f:SetPoint(unpack(f.defaultPoint))
        local point, relativeTo, relativePoint, xOfs, yOfs = f:GetPoint(1)
        BiaoGe.point["BG.RaidMapFrame"] = { point, nil, relativePoint, xOfs, yOfs }
        BiaoGe.RaidMap.mapScale = 0.85
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图] 看板位置与缩放已重置为屏幕中央默认值！|r")
        BG.PlaySound(1)
    end)

    return box
end

--------------------------------------------------------------------------------
-- 14. 命令行支持
--------------------------------------------------------------------------------
SLASH_BGLITEMAP1 = "/bgmap"
SLASH_BGLITEMAP2 = "/tjmap"
SLASH_BGLITEMAP3 = "/bglitemap"
SlashCmdList["BGLITEMAP"] = function()
    if mapFrame and mapFrame:IsShown() then
        mapFrame:Hide()
    else
        if BiaoGe and BiaoGe.maps and #BiaoGe.maps > 0 and BiaoGe.maps[1].code then
            RaidMap.RenderByCode(BiaoGe.maps[1].code, true)
        else
            RaidMap.LoadBossTacticalPreset(currentBossID or 5)
        end
    end
end
