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

RaidMap.bosses = RaidMap.bosses or {}
RaidMap.bossList = RaidMap.bossList or {}
RaidMap.fbs = RaidMap.fbs or {}
RaidMap.fbOrder = RaidMap.fbOrder or {}

if not RaidMap.RegisterFB then
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
end

if not RaidMap.RegisterBoss then
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
end

function RaidMap.GetBoss(bossID)
    if not RaidMap.bosses then return nil end
    return RaidMap.bosses[bossID]
end

function RaidMap.GetAllBosses()
    return RaidMap.bossList or {}
end

RaidMap.BOSS_LIST = RaidMap.bossList

function RaidMap.GetRegisteredFBs()
    local list = {}
    for _, fbKey in ipairs(RaidMap.fbOrder or {}) do
        table.insert(list, RaidMap.fbs[fbKey])
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
-- 5. 战术首领数据源已统一由 Core/RaidTool/RaidMap_Data/ULD.lua 加载
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 6. 战术看板 UI 构建与布局
--------------------------------------------------------------------------------
local currentBossID = 4
local currentPhase = 1
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
    local f = mapFrame or BG.RaidMapFrame
    local canvas = (f and f.mapCanvas) or parent
    parent = canvas or parent

    local g = parent.tacticalGrid or (f and f.tacticalGrid)
    if g then
        g:Show()
        return
    end

    g = CreateFrame("Frame", nil, parent)
    g:SetAllPoints()
    g:SetFrameLevel(parent:GetFrameLevel() + 1)
    parent.tacticalGrid = g
    if f then f.tacticalGrid = g end
    if canvas then canvas.tacticalGrid = g end

    local bgTex = g:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.04, 0.05, 0.08, 0.45)

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

    -- 动态自适应初始尺寸：默认高度设为游戏窗口高度的 75%，保持最佳视界比例
    local screenH = UIParent and UIParent:GetHeight() or 768
    local defaultH = math.max(660, math.floor(screenH * 0.75))
    local defaultW = math.max(780, math.floor(defaultH * 1.18))

    f:SetSize(defaultW, defaultH)
    f.originalWidth = defaultW
    f.originalHeight = defaultH
    f.minW = 180
    f.minH = 36
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    -- 默认正中央居中
    f.defaultPoint = { "CENTER", UIParent, "CENTER", 0, 0 }
    local saved = BiaoGe.point[frameName]
    if saved and type(saved) == "table" and #saved >= 1 then
        local p1 = saved[1] or "CENTER"
        local p2 = UIParent
        local p3 = saved[3] or "CENTER"
        local p4 = saved[4] or 0
        local p5 = saved[5] or 0
        f:SetPoint(p1, p2, p3, p4, p5)
    else
        f:SetPoint(unpack(f.defaultPoint))
    end

    -- 默认缩放设为 100% (1.0)，消除模糊提升清晰度；如果历史保存值为旧版 0.85 则平滑升级为 1.0
    local savedScale = BiaoGe.RaidMap and BiaoGe.RaidMap.mapScale
    if not savedScale or savedScale == 0.85 then
        savedScale = 1.0
    end
    f:SetScale(savedScale)

    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.04, 0.05, 0.08, 0.78)
    f:SetBackdropBorderColor(0.2, 0.6, 0.9, 0.75)

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

    -- 场地地图画布 (Map Canvas - 半透明通透质感)
    local mapCanvas = CreateFrame("Frame", nil, f, "BackdropTemplate")
    mapCanvas:SetPoint("TOPLEFT", 16, -92)
    mapCanvas:SetPoint("BOTTOMRIGHT", -16, 116)
    mapCanvas:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mapCanvas:SetBackdropColor(0.01, 0.02, 0.04, 0.35)
    mapCanvas:SetBackdropBorderColor(0.25, 0.55, 0.85, 0.8)
    f.mapCanvas = mapCanvas

    -- 场地贴图层 (全填充画布，sub-level 1 位于底色之上，高精度呈现 1024x1024 实景)
    local mapTex = mapCanvas:CreateTexture(nil, "BACKGROUND", nil, 1)
    mapTex:SetAllPoints(mapCanvas)
    f.mapTex = mapTex

    -- 场地左上角战术一句话概括 (sub 说明：置于底图左上角，绿字高显)
    local mapSubText = mapCanvas:CreateFontString(nil, "OVERLAY")
    mapSubText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    mapSubText:SetPoint("TOPLEFT", mapCanvas, "TOPLEFT", 12, -10)
    mapSubText:SetTextColor(0.2, 1, 0.4)
    mapSubText:SetText("")
    f.mapSubText = mapSubText

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

    -- 右上角操作区：关闭、最小化与恢复默认大小
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

    local btnResetSize = BG.CreateButton(f)
    btnResetSize:SetSize(88, 20)
    btnResetSize:SetPoint("RIGHT", btnMin, "LEFT", -6, 0)
    btnResetSize:SetText(BG.STC_w1("恢复默认大小"))
    btnResetSize:SetScript("OnClick", function()
        local scrH = UIParent and UIParent:GetHeight() or 768
        local defH = math.max(660, math.floor(scrH * 0.75))
        local defW = math.max(780, math.floor(defH * 1.18))
        f.originalWidth = defW
        f.originalHeight = defH
        f:SetScale(1.0)
        f:SetSize(defW, defH)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        BiaoGe.point[frameName] = { "CENTER", nil, "CENTER", 0, 0 }
        if BiaoGe and BiaoGe.RaidMap then
            BiaoGe.RaidMap.mapScale = 1.0
        end
        RaidMap.LoadBossTacticalPreset(currentBossID, currentPhase)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[BGLite 战术站位图]|r 已恢复屏幕正中心 (%dx%d，屏幕75%%高度) 与 100%% 缩放！", defW, defH))
    end)
    btnResetSize:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("恢复默认大小与居中", 1, 1, 1)
        GameTooltip:AddLine("一键恢复默认窗口尺寸 (屏幕75%高度自适应)、重置到屏幕正中心并恢复 100% 原生缩放比例。\n|cff888888(提示: 鼠标滚轮可在 50%~150% 间平滑微调)|r", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnResetSize:SetScript("OnLeave", GameTooltip_Hide)
    f.btnResetSize = btnResetSize

    btnMin:SetScript("OnClick", function()
        f.isMinimized = not f.isMinimized
        if f.isMinimized then
            f.savedPoint = { f:GetPoint(1) }
            f:SetSize(f.minW, f.minH)
            f.mapCanvas:Hide()
            local grid = f.tacticalGrid or (f.mapCanvas and f.mapCanvas.tacticalGrid)
            if grid then grid:Hide() end
            f.title:Hide()
            f.selfNotice:Hide()
            f.topControls:Hide()
            f.phaseTabBar:Hide()
            if f.tipPanel then f.tipPanel:Hide() end
            if f.btnResetSize then f.btnResetSize:Hide() end
            f.minTitle:Show()
            btnMin:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
        else
            f:SetSize(f.originalWidth, f.originalHeight)
            f.minTitle:Hide()
            f.title:Show()
            f.selfNotice:Show()
            f.topControls:Show()
            f.mapCanvas:Show()
            if f.tipPanel then f.tipPanel:Show() end
            if f.btnResetSize then f.btnResetSize:Show() end
            local bossData = RaidMap.GetBoss(currentBossID)
            if bossData and bossData.phases and #bossData.phases > 0 then
                f.phaseTabBar:Show()
            end
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
            info.value = b.id
            info.checked = (currentBossID == b.id)
            info.func = function()
                currentBossID = b.id
                if LibBG then LibBG:UIDropDownMenu_SetText(dropBoss, b.name) else UIDropDownMenu_SetText(dropBoss, b.name) end
                RaidMap.LoadBossTacticalPreset(b.id, 1)
            end
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
        end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(dropBoss, InitBossMenu)
        LibBG:UIDropDownMenu_SetWidth(dropBoss, 135)
    else
        UIDropDownMenu_Initialize(dropBoss, InitBossMenu)
        UIDropDownMenu_SetWidth(dropBoss, 135)
    end

    if BG.dropDownToggle then
        BG.dropDownToggle(dropBoss)
    end

    local curB = RaidMap.GetBoss(currentBossID)
    local curName = curB and curB.name or "拆解者 XT-002"
    if LibBG and LibBG.UIDropDownMenu_SetText then
        LibBG:UIDropDownMenu_SetText(dropBoss, curName)
    else
        UIDropDownMenu_SetText(dropBoss, curName)
    end

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
    btnAuto:SetSize(92, 24)
    btnAuto:SetPoint("LEFT", 0, 0)
    btnAuto:SetText(BG.STC_b1("同步团队"))
    btnAuto:SetScript("OnClick", function()
        RaidMap.AutoAssignRosterToMap(false)
        BG.PlaySound(1)
    end)
    btnAuto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("一键同步团队人员并自动布阵", 1, 1, 1)
        GameTooltip:AddLine("根据当前团队成员职责自动分配点位：\n- 坦克自动填入 1~2 号位；\n- 治疗自动填入 3~7 号位；\n- 远程自动填入 8~17 号大分散位；\n- 近战统一归入【近战集合组】标记！", 0.85, 0.85, 0.85, true)
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
        wipe(RaidMap.assignedPlayers)
        wipe(RaidMap.meleeRoster)
        if RaidMap.ClearCustomMarkers then RaidMap.ClearCustomMarkers(f) end
        RaidMap.LoadBossTacticalPreset(currentBossID, currentPhase)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图]|r 已恢复当前阶段的标准预设点位！")
    end)
    btnReset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("恢复默认站位阵型", 1, 1, 1)
        GameTooltip:AddLine("一键重置当前 BOSS/阶段的所有点位，消除所有手动拖动位移并清空分配与画板标注。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnReset:SetScript("OnLeave", GameTooltip_Hide)

    -- 3.3 一键全团广播 (SendMap)
    local btnSend = BG.CreateButton(editControls)
    btnSend:SetSize(86, 24)
    btnSend:SetPoint("LEFT", btnReset, "RIGHT", 4, 0)
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

    -- 3.5 简易战术画板/标注工具箱入口按钮
    local btnDraw = BG.CreateButton(editControls)
    btnDraw:SetSize(86, 24)
    btnDraw:SetPoint("LEFT", btnLock, "RIGHT", 4, 0)
    btnDraw:SetText(BG.STC_b1("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:13:13:0:0|t 战术画板"))
    btnDraw:SetScript("OnClick", function()
        local bar = f.drawToolbar or RaidMap.CreateDrawToolbar(f)
        if bar:IsShown() then
            bar:Hide()
        else
            bar:Show()
            bar:Raise()
        end
        BG.PlaySound(1)
    end)
    btnDraw:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("打开简易战术画板", 1, 1, 1)
        GameTooltip:AddLine("呼出悬浮战术标注工具箱：\n- 随心在画板上放置 8 大团队标记（骷髅、大饼、红叉等）；\n- 自由添加战术文字便签（可自定义输入战术提示）；\n- 快速添加单兵玩家标记；\n- 所有图元支持鼠标自由拖拽与右键快速删除！", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnDraw:SetScript("OnLeave", GameTooltip_Hide)
    f.btnDraw = btnDraw

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

    if BG.dropDownToggle then
        BG.dropDownToggle(dropHistory)
    end

    -- 多阶段 Tab 切换栏 (Phase Tabs Bar)
    local phaseTabBar = CreateFrame("Frame", nil, f)
    phaseTabBar:SetPoint("TOPLEFT", 16, -64)
    phaseTabBar:SetPoint("TOPRIGHT", -16, -64)
    phaseTabBar:SetHeight(26)
    phaseTabBar:Hide()
    f.phaseTabBar = phaseTabBar
    f.phaseButtons = {}

    -- 底部战术攻略提示卡片面板 (Tactics Card Panel - 高度扩充至 96px，确保完整展示多行攻略)
    local tipPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    tipPanel:SetPoint("BOTTOMLEFT", 16, 12)
    tipPanel:SetPoint("BOTTOMRIGHT", -16, 12)
    tipPanel:SetHeight(96)
    tipPanel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tipPanel:SetBackdropColor(0.015, 0.025, 0.045, 0.70)
    tipPanel:SetBackdropBorderColor(0.25, 0.55, 0.85, 0.75)
    f.tipPanel = tipPanel

    -- 攻略详细文本 (顶部对齐，多行规整，行距 3 像素，高对比暖黄字)
    local tacticTipText = tipPanel:CreateFontString(nil, "OVERLAY")
    tacticTipText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    tacticTipText:SetPoint("TOPLEFT", tipPanel, "TOPLEFT", 10, -8)
    tacticTipText:SetPoint("BOTTOMRIGHT", tipPanel, "BOTTOMRIGHT", -122, 6)
    tacticTipText:SetJustifyH("LEFT")
    tacticTipText:SetJustifyV("TOP")
    tacticTipText:SetSpacing(3)
    tacticTipText:SetTextColor(1, 0.88, 0.35)
    f.tacticTipText = tacticTipText

    -- 快捷通报本阶段按钮 (垂直居中于攻略卡片右侧)
    local btnFastSend = BG.CreateButton(tipPanel)
    btnFastSend:SetSize(100, 32)
    btnFastSend:SetPoint("RIGHT", tipPanel, "RIGHT", -10, 0)
    btnFastSend:SetText(BG.STC_g1("通报本阶段"))
    btnFastSend:SetScript("OnClick", function()
        local bossID = f.currentBossID or currentBossID
        local phaseIdx = f.currentPhase or currentPhase or 1
        local bossData = RaidMap.GetBoss(bossID)
        local bossName = bossData and bossData.name or "当前BOSS"
        local phaseName = ""
        local tip = f.activeTacticTip or (bossData and bossData.tacticTip) or ""
        if bossData and bossData.phases and #bossData.phases > 0 then
            local curP = bossData.phases[phaseIdx] or bossData.phases[1]
            if curP then
                phaseName = " [" .. (curP.name or ("P" .. phaseIdx)) .. "]"
                tip = curP.tacticTip or tip
            end
        end

        -- 兜底保障：若 tip 仍为空，尝试从界面 tacticTipText 提取并剔除贴图与颜色转义符
        if (not tip or tip == "") and f.tacticTipText and f.tacticTipText:GetText() then
            tip = f.tacticTipText:GetText()
            tip = tip:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end

        local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
        if channel then
            SendChatMessage(string.format("【战术站位】<< %s%s >>", bossName, phaseName), channel)
            for line in string.gmatch(tip, "([^\r\n]+)") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" then
                    SendChatMessage(line, channel)
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[BGLite 战术站位图]|r 已向团队频道通报本阶段战术！")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[战术站位预览]|r " .. bossName .. phaseName)
            for line in string.gmatch(tip, "([^\r\n]+)") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line ~= "" then
                    DEFAULT_CHAT_FRAME:AddMessage(line)
                end
            end
        end
        BG.PlaySound(1)
    end)
    btnFastSend:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("通报当前阶段战术要点", 1, 1, 1)
        GameTooltip:AddLine("将当前选中的阶段（如 P2 激光跑位）核心机制与站位指南直接发送至团队频道聊天栏，方便全团即时查看！", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnFastSend:SetScript("OnLeave", GameTooltip_Hide)
    f.btnFastSend = btnFastSend

    -- 模式切换器
    function RaidMap.SetViewMode(isView)
        f.isViewMode = isView
        if isView then
            f.editControls:Hide()
            if f.drawToolbar then f.drawToolbar:Hide() end
            f.viewBadge:Show()
        else
            f.viewBadge:Hide()
            f.editControls:Show()
        end
    end

    f:SetScript("OnShow", function()
        if RaidMap.AutoAssignRosterToMap then
            RaidMap.AutoAssignRosterToMap(true)
        end
    end)

    mapFrame = f
    BG.RaidMapFrame = f
    _G["BG.RaidMapFrame"] = f
    return f
end

--------------------------------------------------------------------------------
-- 7. 纯正 TuanJian 体系站位图标渲染器 (圆形肖像蒙版 + broder.png 环形外框)
--------------------------------------------------------------------------------
RaidMap.assignedPlayers = {} -- 玩家点位分配持久缓存: [slotIndex] = { name, class, specIcon, specName, role }
RaidMap.meleeRoster = {}     -- 当前团队近战组人员名单 (服务于 [98] 战术标记)

local function CreateDraggablePointIcon(mapCanvas, index, v)
    local width = v.size or 30
    local f = CreateFrame("Button", nil, mapCanvas)
    f:SetSize(width, width)
    f.index = index
    f.v = v

    -- 基于标准基准画布 (748x452) 动态等比映射坐标，保证拉伸或大屏下人员与底图相对位置 100% 严丝合缝
    local baseW = 748
    local baseH = 452
    local curW = mapCanvas:GetWidth()
    local curH = mapCanvas:GetHeight()
    local scaleX = (curW and curW > 100) and (curW / baseW) or 1
    local scaleY = (curH and curH > 100) and (curH / baseH) or 1

    local origX = v.xy[1]
    local origY = (v.xy[2] > 0) and -v.xy[2] or v.xy[2]
    f.baseX = origX
    f.baseY = origY
    f.x = math.floor(origX * scaleX + 0.5)
    f.y = math.floor(origY * scaleY + 0.5)
    f:SetPoint("CENTER", mapCanvas, "TOPLEFT", f.x, f.y)
    f:SetFrameLevel(mapCanvas:GetFrameLevel() + (v.isNPC and 10 or 15))

    -- 暴雪原生圆形肖像透明遮罩
    local mask = f:CreateMaskTexture()
    mask:SetPoint("CENTER")
    mask:SetSize(width - 4, width - 4)
    mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER")
    icon:SetSize(width, width)
    icon:AddMaskTexture(mask)
    f.icon = icon

    -- 官方外边框
    local border = f:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture([[Interface\AddOns\BGLite_Plus\Media\icon\broder.png]])
    f.border = border

    -- 序号
    local numText = f:CreateFontString(nil, "OVERLAY")
    numText:SetFont(BIAOGE_TEXT_FONT, (v.isNPC and width > 40) and 14 or 12, "OUTLINE")
    numText:SetPoint("CENTER", 0, 0)
    f.numText = numText

    -- 玩家/首领名称
    local playerText = f:CreateFontString(nil, "OVERLAY")
    playerText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    playerText:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.playerText = playerText

    -- 玩家自身专属高亮光晕
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("CENTER")
    glow:SetSize(width + 18, width + 18)
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.9, 0.2, 0.95)
    glow:Hide()
    f.glow = glow

    -- 刷新图元展示状态
    function f:UpdateDisplay()
        if v.isNPC then
            if v.isBoss then
                f.border:SetVertexColor(1, 0.2, 0.2)
                f.icon:SetTexture(v.isNPC_icon or "Interface\\Icons\\achievement_boss_algalon_01")
                f.icon:SetAlpha(1.0)
                f.playerText:SetText(v.isNPC_text or "")
                f.playerText:SetTextColor(1, 0.35, 0.35)
                f.numText:SetText("")
            elseif v.isNPC_help then
                f.border:SetVertexColor(0.7, 0.7, 0.7)
                f.icon:SetTexture(v.isNPC_icon or "Interface\\Icons\\ability_steelmelee")
                f.icon:SetAlpha(1.0)
                f.playerText:SetText(v.isNPC_text or "")
                f.playerText:SetTextColor(1, 0.85, 0.1)
                f.numText:SetText("")
            else
                f.border:SetVertexColor(0.3, 0.8, 1)
                f.icon:SetTexture(v.isNPC_icon or "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                f.icon:SetAlpha(1.0)
                f.playerText:SetText(v.isNPC_text or "")
                f.playerText:SetTextColor(0.3, 0.9, 1)
                f.numText:SetText("")
            end
        else
            local p = RaidMap.assignedPlayers[index]
            if p then
                local r, g, b = 1, 1, 1
                if RAID_CLASS_COLORS and p.class and RAID_CLASS_COLORS[p.class] then
                    local c = RAID_CLASS_COLORS[p.class]; r, g, b = c.r, c.g, c.b
                end
                f.border:SetVertexColor(r, g, b)
                f.icon:SetTexture(p.specIcon or (RaidMap.CLASS_ICONS and RaidMap.CLASS_ICONS[p.class]) or "Interface\\Icons\\INV_Misc_QuestionMark")
                f.icon:SetAlpha(1.0)
                f.playerText:SetText(p.name or "")
                f.playerText:SetTextColor(r, g, b)
                f.numText:SetText(tostring(index))
                f.numText:SetTextColor(1, 1, 1)
                f.name = p.name
            else
                f.border:SetVertexColor(0.45, 0.45, 0.45)
                f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                f.icon:SetAlpha(0.25)
                f.playerText:SetText("")
                f.numText:SetText(tostring(index))
                f.numText:SetTextColor(0.65, 0.65, 0.65)
                f.name = nil
            end
        end
    end

    f:UpdateDisplay()

    -- 鼠标交互与自由拖拽调位
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    f:SetScript("OnDragStart", function(self)
        if mapFrame and mapFrame.isViewMode then return end
        self:StartMoving()
        self.isDragging = true
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isDragging then
            self.isDragging = false
            self:StopMovingOrSizing()
            local s = mapCanvas:GetEffectiveScale() or 1
            local curX, curY = GetCursorPosition()
            curX = curX / s
            curY = curY / s
            local pLeft = mapCanvas:GetLeft()
            local pTop = mapCanvas:GetTop()
            if pLeft and pTop then
                local relX = math.floor(curX - pLeft + 0.5)
                local relY = math.floor(curY - pTop + 0.5)
                self.x = relX
                self.y = relY
                local curW = mapCanvas:GetWidth() or 748
                local curH = mapCanvas:GetHeight() or 452
                local scaleX = (curW and curW > 100) and (curW / 748) or 1
                local scaleY = (curH and curH > 100) and (curH / 452) or 1
                self.baseX = math.floor(relX / scaleX + 0.5)
                self.baseY = math.floor(relY / scaleY + 0.5)
                self:ClearAllPoints()
                self:SetPoint("CENTER", mapCanvas, "TOPLEFT", relX, relY)
            end
        end
    end)

    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if IsShiftKeyDown() then
                local curW = mapCanvas:GetWidth() or 748
                local curH = mapCanvas:GetHeight() or 452
                local scaleX = (curW and curW > 100) and (curW / 748) or 1
                local scaleY = (curH and curH > 100) and (curH / 452) or 1
                self.baseX = v.xy[1]
                self.baseY = (v.xy[2] > 0) and -v.xy[2] or v.xy[2]
                self.x = math.floor(self.baseX * scaleX + 0.5)
                self.y = math.floor(self.baseY * scaleY + 0.5)
                self:ClearAllPoints()
                self:SetPoint("CENTER", mapCanvas, "TOPLEFT", self.x, self.y)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00BFFF[站位图]|r %d 号位已重置回默认预设坐标。", index))
            else
                if not v.isNPC then
                    RaidMap.assignedPlayers[index] = nil
                    self:UpdateDisplay()
                    RaidMap.RefreshSelfHighlight(mapFrame)
                end
            end
            BG.PlaySound(1)
        elseif button == "LeftButton" then
            if not v.isNPC then
                RaidMap.ShowPlayerPicker(self)
            end
        end
    end)

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if v.isBoss then
            GameTooltip:AddLine("【首领 BOSS】 " .. (v.isNPC_text or "首领"), 1, 0.25, 0.25)
            local bossData = RaidMap.GetBoss(currentBossID)
            if bossData and bossData.sub then GameTooltip:AddLine(bossData.sub, 0.8, 0.8, 0.8, true) end
        elseif v.isNPC then
            if v.isNPC_icon == "Interface\\Icons\\ability_steelmelee" then
                GameTooltip:AddLine("【⚔️ 近战集合组】 " .. (v.isNPC_text or "近战"), 1, 0.85, 0.1)
                GameTooltip:AddLine("战术职责: BOSS 正背后脚后跟集中输出 (全员集合点)", 0.6, 0.85, 1)
                if RaidMap.meleeRoster and #RaidMap.meleeRoster > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string.format("当前团队近战成员 (%d人):", #RaidMap.meleeRoster), 1, 1, 1)
                    for _, m in ipairs(RaidMap.meleeRoster) do
                        local cCode = RAID_CLASS_COLORS[m.class] and RAID_CLASS_COLORS[m.class].colorStr or "ffffffff"
                        GameTooltip:AddLine("  • |c" .. cCode .. m.name .. "|r (" .. (m.specName or "近战") .. ")")
                    end
                end
            else
                GameTooltip:AddLine("【战术标记】 " .. (v.isNPC_text or "地标"), 0.3, 0.9, 1)
            end
        else
            local p = RaidMap.assignedPlayers[index]
            if p then
                local cCode = RAID_CLASS_COLORS[p.class] and RAID_CLASS_COLORS[p.class].colorStr or "ffffffff"
                GameTooltip:AddLine(string.format("|c%s%s|r (%d 号位)", cCode, p.name, index), 1, 1, 1)
                GameTooltip:AddLine("专精: " .. (p.specName or "未知") .. " | 职责: " .. (p.role or "队员"), 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine(string.format("未分配玩家 (%d 号位)", index), 0.7, 0.7, 0.7)
                GameTooltip:AddLine("左键点击可手动指定队员，或点击上方 [同步团队] 自动入席", 0.3, 1, 0.5, true)
            end
            local roleName = "未知"
            if v.role == "tank" then
                roleName = "坦克位"
            elseif v.role == "healer" then
                roleName = "治疗位"
            elseif v.role == "ranged" then
                roleName = "远程输出位"
            else
                roleName = (index <= 2) and "坦克位" or (index <= 7 and "治疗位" or "远程输出位")
            end
            local fullDesc = v.desc and (roleName .. " - " .. v.desc) or roleName
            GameTooltip:AddLine("预设定位: " .. fullDesc, 0.6, 0.85, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("提示: 鼠标左键拖拽调整位置 | 右键清空 | Shift+右键恢复默认坐标", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    tinsert(mapFrame.icons, f)
    return f
end

-- 玩家选择下拉菜单 (点击点位手动调位)
function RaidMap.ShowPlayerPicker(icon)
    if not icon or icon.v.isNPC then return end
    local menu = {
        {
            text = "清除该槽位玩家",
            func = function()
                RaidMap.assignedPlayers[icon.index] = nil
                icon:UpdateDisplay()
                RaidMap.RefreshSelfHighlight(mapFrame)
            end,
            notCheckable = true,
        },
        {
            text = "── 选择团队成员 ──",
            isTitle = true,
            notCheckable = true,
        },
    }

    local rosterData = RaidMap.GetAutoRosterData()
    if rosterData then
        local all = {}
        for _, t in ipairs(rosterData.tanks) do tinsert(all, t) end
        for _, h in ipairs(rosterData.tankHealers) do tinsert(all, h) end
        for _, h in ipairs(rosterData.raidHealers) do tinsert(all, h) end
        for _, r in ipairs(rosterData.rangeds) do tinsert(all, r) end
        for _, m in ipairs(rosterData.melees) do tinsert(all, m) end

        for _, p in ipairs(all) do
            local cCode = RAID_CLASS_COLORS[p.class] and RAID_CLASS_COLORS[p.class].colorStr or "ffffffff"
            tinsert(menu, {
                text = string.format("|c%s%s|r (%s)", cCode, p.name, p.specName or p.role or ""),
                func = function()
                    RaidMap.assignedPlayers[icon.index] = p
                    icon:UpdateDisplay()
                    RaidMap.RefreshSelfHighlight(mapFrame)
                end,
                notCheckable = true,
            })
        end
    end

    local drop = mapFrame.playerPickerDropdown
    if not drop then
        drop = LibBG and LibBG:Create_UIDropDownMenu("BG_RaidMapPlayerPicker", mapFrame) or CreateFrame("Frame", "BG_RaidMapPlayerPicker", mapFrame, "UIDropDownMenuTemplate")
        mapFrame.playerPickerDropdown = drop
    end

    local function InitPicker(self, level)
        for _, item in ipairs(menu) do
            local info = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.func = item.func
            info.isTitle = item.isTitle
            info.notCheckable = item.notCheckable
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
        end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(drop, InitPicker)
        LibBG:ToggleDropDownMenu(1, nil, drop, icon, 0, 0)
    else
        UIDropDownMenu_Initialize(drop, InitPicker)
        ToggleDropDownMenu(1, nil, drop, icon, 0, 0)
    end
end

--------------------------------------------------------------------------------
-- 7.1 自定义画板与战术标注系统 (团队标记 / 便签 / 玩家标志)
--------------------------------------------------------------------------------
RaidMap.customMarkers = {}

function RaidMap.ClearCustomMarkers(f)
    f = f or mapFrame or BG.RaidMapFrame
    if not f or not f.customMarkers then return end
    for _, marker in ipairs(f.customMarkers) do
        marker:Hide()
    end
    wipe(f.customMarkers)
end

function RaidMap.ShowTextEditPopup(targetMarker, parent)
    parent = parent or mapFrame or BG.RaidMapFrame
    if not parent or not targetMarker then return end

    if not parent.textEditDialog then
        local dlg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        dlg:SetSize(240, 86)
        dlg:SetPoint("CENTER", parent, "CENTER", 0, 40)
        dlg:SetFrameLevel(parent:GetFrameLevel() + 50)
        if dlg.SetBackdrop then
            dlg:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            dlg:SetBackdropColor(0.04, 0.06, 0.1, 0.96)
            dlg:SetBackdropBorderColor(0.2, 0.7, 1, 0.95)
        end
        dlg:EnableMouse(true)

        local title = dlg:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        title:SetPoint("TOPLEFT", 12, -8)
        title:SetText(BG.STC_b1("编辑战术便签文字"))

        local eb = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
        eb:SetSize(210, 22)
        eb:SetPoint("TOPLEFT", 14, -28)
        eb:SetAutoFocus(true)
        eb:SetMaxLetters(30)
        dlg.editBox = eb

        local btnOk = BG.CreateButton(dlg)
        btnOk:SetSize(60, 20)
        btnOk:SetPoint("BOTTOMRIGHT", -78, 8)
        btnOk:SetText(BG.STC_g1("确定"))

        local btnCancel = BG.CreateButton(dlg)
        btnCancel:SetSize(60, 20)
        btnCancel:SetPoint("BOTTOMRIGHT", -12, 8)
        btnCancel:SetText(BG.STC_w1("取消"))

        local function Confirm()
            local text = eb:GetText()
            if dlg.targetMarker and dlg.targetMarker.UpdateText then
                dlg.targetMarker:UpdateText(text ~= "" and text or "战术便签")
            end
            dlg:Hide()
            BG.PlaySound(1)
        end

        btnOk:SetScript("OnClick", Confirm)
        eb:SetScript("OnEnterPressed", Confirm)

        local function Cancel()
            dlg:Hide()
            BG.PlaySound(1)
        end
        btnCancel:SetScript("OnClick", Cancel)
        eb:SetScript("OnEscapePressed", Cancel)

        parent.textEditDialog = dlg
    end

    local dlg = parent.textEditDialog
    dlg.targetMarker = targetMarker
    dlg.editBox:SetText(targetMarker.text or "战术便签")
    dlg:Show()
    dlg.editBox:SetFocus()
    dlg.editBox:HighlightText()
    dlg:Raise()
end

function RaidMap.ShowPlayerCustomMarkerPicker(anchorFrame)
    local f = mapFrame or BG.RaidMapFrame
    if not f then return end

    local menu = {
        {
            text = "── 选择要标注的团队成员 ──",
            isTitle = true,
            notCheckable = true,
        },
    }

    local rosterData = RaidMap.GetAutoRosterData()
    local hasPlayer = false
    if rosterData then
        local all = {}
        for _, t in ipairs(rosterData.tanks) do tinsert(all, t) end
        for _, h in ipairs(rosterData.tankHealers) do tinsert(all, h) end
        for _, h in ipairs(rosterData.raidHealers) do tinsert(all, h) end
        for _, r in ipairs(rosterData.rangeds) do tinsert(all, r) end
        for _, m in ipairs(rosterData.melees) do tinsert(all, m) end

        for _, p in ipairs(all) do
            hasPlayer = true
            local cCode = RAID_CLASS_COLORS[p.class] and RAID_CLASS_COLORS[p.class].colorStr or "ffffffff"
            tinsert(menu, {
                text = string.format("|c%s%s|r (%s)", cCode, p.name, p.specName or p.role or ""),
                func = function()
                    RaidMap.CreateCustomMarker(f.mapCanvas, "player", p)
                    BG.PlaySound(1)
                end,
                notCheckable = true,
            })
        end
    end

    if not hasPlayer then
        local dummyPlayers = {
            { name = "圣盾主坦", class = "PALADIN", specName = "防骑", specIcon = "Interface\\Icons\\spell_holy_auraofprotection" },
            { name = "强袭狂暴", class = "WARRIOR", specName = "狂暴战", specIcon = "Interface\\Icons\\ability_warrior_innerrage" },
            { name = "神圣道标", class = "PALADIN", specName = "奶骑", specIcon = "Interface\\Icons\\spell_holy_holybolt" },
            { name = "苦修护盾", class = "PRIEST", specName = "戒律牧", specIcon = "Interface\\Icons\\spell_holy_powerwordshield" },
            { name = "混沌之箭", class = "WARLOCK", specName = "毁灭术", specIcon = "Interface\\Icons\\spell_shadow_rainoffire" },
            { name = "极寒刺骨", class = "MAGE", specName = "冰法", specIcon = "Interface\\Icons\\spell_frost_frostbolt02" },
        }
        for _, p in ipairs(dummyPlayers) do
            local cCode = RAID_CLASS_COLORS[p.class] and RAID_CLASS_COLORS[p.class].colorStr or "ffffffff"
            tinsert(menu, {
                text = string.format("|c%s%s|r (%s)", cCode, p.name, p.specName),
                func = function()
                    RaidMap.CreateCustomMarker(f.mapCanvas, "player", p)
                    BG.PlaySound(1)
                end,
                notCheckable = true,
            })
        end
    end

    local drop = f.customPlayerPickerDropdown
    if not drop then
        drop = LibBG and LibBG:Create_UIDropDownMenu("BG_RaidMapCustomPlayerPicker", f) or CreateFrame("Frame", "BG_RaidMapCustomPlayerPicker", f, "UIDropDownMenuTemplate")
        f.customPlayerPickerDropdown = drop
    end

    local function InitPicker(self, level)
        for _, item in ipairs(menu) do
            local info = LibBG and LibBG:UIDropDownMenu_CreateInfo() or UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.func = item.func
            info.isTitle = item.isTitle
            info.notCheckable = item.notCheckable
            if LibBG then LibBG:UIDropDownMenu_AddButton(info, level) else UIDropDownMenu_AddButton(info, level) end
        end
    end

    if LibBG and LibBG.UIDropDownMenu_Initialize then
        LibBG:UIDropDownMenu_Initialize(drop, InitPicker)
        LibBG:ToggleDropDownMenu(1, nil, drop, anchorFrame, 0, 0)
    else
        UIDropDownMenu_Initialize(drop, InitPicker)
        ToggleDropDownMenu(1, nil, drop, anchorFrame, 0, 0)
    end
end

function RaidMap.CreateCustomMarker(mapCanvas, markerType, data)
    mapCanvas = mapCanvas or (mapFrame and mapFrame.mapCanvas)
    if not mapCanvas then return end

    local f = mapFrame or BG.RaidMapFrame
    f.customMarkers = f.customMarkers or {}

    local curW = mapCanvas:GetWidth() or 748
    local curH = mapCanvas:GetHeight() or 452
    local scaleX = (curW and curW > 100) and (curW / 748) or 1
    local scaleY = (curH and curH > 100) and (curH / 452) or 1

    -- 在画布中心略带随机偏移生成，避免多图元重叠
    local randOffsetX = math.random(-36, 36)
    local randOffsetY = math.random(-36, 36)
    local baseX = 374 + randOffsetX
    local baseY = -226 + randOffsetY
    local curX = math.floor(baseX * scaleX + 0.5)
    local curY = math.floor(baseY * scaleY + 0.5)

    local marker = CreateFrame("Button", nil, mapCanvas, "BackdropTemplate")
    marker.markerType = markerType
    marker.baseX = baseX
    marker.baseY = baseY
    marker.x = curX
    marker.y = curY
    marker:SetPoint("CENTER", mapCanvas, "TOPLEFT", curX, curY)
    marker:SetFrameLevel(mapCanvas:GetFrameLevel() + 22)

    if markerType == "raidIcon" then
        local iconID = data and data.iconID or 8
        marker.iconID = iconID
        marker:SetSize(32, 32)

        local shadow = marker:CreateTexture(nil, "BACKGROUND")
        shadow:SetPoint("CENTER", 1, -1)
        shadow:SetSize(34, 34)
        shadow:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconID)
        shadow:SetVertexColor(0, 0, 0, 0.6)
        marker.shadow = shadow

        local icon = marker:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconID)
        marker.icon = icon

        local border = marker:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetTexture([[Interface\AddOns\BGLite_Plus\Media\icon\broder.png]])
        border:SetVertexColor(1, 1, 1, 0.45)
        marker.border = border

    elseif markerType == "text" then
        marker.text = (data and data.text) or "战术便签"
        marker:SetHeight(26)
        if marker.SetBackdrop then
            marker:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            marker:SetBackdropColor(0.02, 0.04, 0.08, 0.88)
            marker:SetBackdropBorderColor(1, 0.82, 0.0, 0.9)
        end

        local fontStr = marker:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        fontStr:SetPoint("CENTER", 0, 0)
        fontStr:SetTextColor(1, 0.88, 0.25)
        marker.fontStr = fontStr
        marker.playerText = fontStr

        function marker:UpdateText(newText)
            self.text = newText or self.text or "战术便签"
            self.fontStr:SetText(self.text)
            local w = math.max(68, self.fontStr:GetStringWidth() + 18)
            self:SetWidth(w)
        end
        marker:UpdateText(marker.text)

    elseif markerType == "player" then
        marker.playerData = data
        local pName = data and data.name or "队员"
        local pClass = data and data.class or "WARRIOR"
        marker.text = pName

        local r, g, b = 1, 1, 1
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass] then
            local c = RAID_CLASS_COLORS[pClass]; r, g, b = c.r, c.g, c.b
        end

        marker:SetHeight(26)
        if marker.SetBackdrop then
            marker:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            marker:SetBackdropColor(0.04, 0.07, 0.12, 0.9)
            marker:SetBackdropBorderColor(r, g, b, 0.9)
        end

        local mask = marker:CreateMaskTexture()
        mask:SetPoint("LEFT", 4, 0)
        mask:SetSize(18, 18)
        mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

        local icon = marker:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("LEFT", 4, 0)
        icon:SetSize(18, 18)
        icon:AddMaskTexture(mask)
        icon:SetTexture(data and data.specIcon or (RaidMap.CLASS_ICONS and RaidMap.CLASS_ICONS[pClass]) or "Interface\\Icons\\INV_Misc_QuestionMark")
        marker.icon = icon

        local fontStr = marker:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        fontStr:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        fontStr:SetText(pName)
        fontStr:SetTextColor(r, g, b)
        marker.fontStr = fontStr
        marker.playerText = fontStr

        local w = math.max(80, fontStr:GetStringWidth() + 32)
        marker:SetWidth(w)
    end

    marker:SetMovable(true)
    marker:EnableMouse(true)
    marker:RegisterForDrag("LeftButton")
    marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    marker:SetScript("OnDragStart", function(self)
        if mapFrame and mapFrame.isViewMode then return end
        self:StartMoving()
        self.isDragging = true
        self.wasDragged = true
    end)

    marker:SetScript("OnDragStop", function(self)
        if self.isDragging then
            self.isDragging = false
            self:StopMovingOrSizing()
            local s = mapCanvas:GetEffectiveScale() or 1
            local curX, curY = GetCursorPosition()
            curX = curX / s
            curY = curY / s
            local pLeft = mapCanvas:GetLeft()
            local pTop = mapCanvas:GetTop()
            if pLeft and pTop then
                local relX = math.floor(curX - pLeft + 0.5)
                local relY = math.floor(curY - pTop + 0.5)
                self.x = relX
                self.y = relY
                local curW = mapCanvas:GetWidth() or 748
                local curH = mapCanvas:GetHeight() or 452
                local scaleX = (curW and curW > 100) and (curW / 748) or 1
                local scaleY = (curH and curH > 100) and (curH / 452) or 1
                self.baseX = math.floor(relX / scaleX + 0.5)
                self.baseY = math.floor(relY / scaleY + 0.5)
                self:ClearAllPoints()
                self:SetPoint("CENTER", mapCanvas, "TOPLEFT", relX, relY)
            end
        end
    end)

    marker:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            self:Hide()
            for i, m in ipairs(f.customMarkers) do
                if m == self then
                    table.remove(f.customMarkers, i)
                    break
                end
            end
            BG.PlaySound(1)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[战术画板]|r 已移除图元。")
        elseif button == "LeftButton" then
            if self.wasDragged then
                self.wasDragged = false
                return
            end
            if self.markerType == "text" then
                RaidMap.ShowTextEditPopup(self, f)
            end
        end
    end)

    marker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if self.markerType == "raidIcon" then
            local raidIconNames = {
                [1] = "星星 (Star)", [2] = "大饼 (Circle)", [3] = "菱形 (Diamond)", [4] = "三角 (Triangle)",
                [5] = "月亮 (Moon)", [6] = "方块 (Square)", [7] = "红叉 (Cross)", [8] = "骷髅 (Skull)",
            }
            local name = raidIconNames[self.iconID or 8] or "团队标记"
            GameTooltip:AddLine("【战术标记】 " .. name, 1, 0.85, 0.1)
            GameTooltip:AddLine("|cff00ff00左键按住:|r 自由拖拽摆放位置", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cffff4444右键单击:|r 快速删除此标记", 0.9, 0.9, 0.9)
        elseif self.markerType == "text" then
            GameTooltip:AddLine("【战术便签】", 1, 0.85, 0.1)
            GameTooltip:AddLine(self.text or "", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00e5ff左键单击:|r 修改便签文字", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cff00ff00左键按住:|r 自由拖拽摆放位置", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cffff4444右键单击:|r 快速删除此便签", 0.9, 0.9, 0.9)
        elseif self.markerType == "player" then
            GameTooltip:AddLine("【单兵玩家标记】 " .. (self.text or ""), 0.2, 0.8, 1)
            if self.playerData and self.playerData.class then
                local cName = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[self.playerData.class] or self.playerData.class
                GameTooltip:AddLine("职业专精: " .. (self.playerData.specName or cName), 0.85, 0.85, 0.85)
            end
            GameTooltip:AddLine("|cff00ff00左键按住:|r 自由拖拽摆放位置", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cffff4444右键单击:|r 快速删除此标记", 0.9, 0.9, 0.9)
        end
        GameTooltip:Show()
    end)
    marker:SetScript("OnLeave", GameTooltip_Hide)

    table.insert(f.customMarkers, marker)
    marker:Show()
    return marker
end

function RaidMap.CreateDrawToolbar(f)
    if f.drawToolbar then return f.drawToolbar end

    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetSize(256, 92)
    bar:SetPoint("TOPRIGHT", f.mapCanvas, "TOPRIGHT", -8, -8)
    bar:SetFrameLevel(f.mapCanvas:GetFrameLevel() + 25)
    if bar.SetBackdrop then
        bar:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        bar:SetBackdropColor(0.03, 0.05, 0.09, 0.94)
        bar:SetBackdropBorderColor(0.2, 0.65, 0.95, 0.9)
    end
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = bar:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    title:SetPoint("TOPLEFT", 10, -7)
    title:SetText(BG.STC_b1("战术画板工具箱") .. " |cff888888(可拖动)|r")

    local btnClose = CreateFrame("Button", nil, bar)
    btnClose:SetSize(16, 16)
    btnClose:SetPoint("TOPRIGHT", -6, -6)
    local closeText = btnClose:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    closeText:SetPoint("CENTER", 0, 0)
    closeText:SetText(BG.STC_r1("×"))
    btnClose:SetScript("OnClick", function()
        bar:Hide()
        BG.PlaySound(1)
    end)

    local raidIconNames = {
        [1] = "星星", [2] = "大饼", [3] = "菱形", [4] = "三角",
        [5] = "月亮", [6] = "方块", [7] = "红叉", [8] = "骷髅",
    }
    bar.iconButtons = {}
    for i = 1, 8 do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetSize(25, 25)
        local leftOffset = 8 + (i - 1) * 30
        btn:SetPoint("TOPLEFT", leftOffset, -28)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        btn.tex = tex

        btn:SetScript("OnClick", function()
            RaidMap.CreateCustomMarker(f.mapCanvas, "raidIcon", { iconID = i })
            BG.PlaySound(1)
        end)
        btn:SetScript("OnEnter", function(self)
            self.tex:SetVertexColor(1, 1, 0.4)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("添加【" .. raidIconNames[i] .. "】标记", 1, 1, 1)
            GameTooltip:AddLine("点击在画布中央生成该标记，可自由按住拖拽与右键删除。", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.tex:SetVertexColor(1, 1, 1)
            GameTooltip_Hide()
        end)
        bar.iconButtons[i] = btn
    end

    local btnNote = BG.CreateButton(bar)
    btnNote:SetSize(72, 22)
    btnNote:SetPoint("TOPLEFT", 8, -60)
    btnNote:SetText(BG.STC_y1("[+] 便签"))
    btnNote:SetScript("OnClick", function()
        local marker = RaidMap.CreateCustomMarker(f.mapCanvas, "text", { text = "战术便签" })
        if marker then
            RaidMap.ShowTextEditPopup(marker, f)
        end
        BG.PlaySound(1)
    end)
    btnNote:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("添加【文字战术便签】", 1, 1, 1)
        GameTooltip:AddLine("在画布上生成随心便签（如说明、集合点、开嗜血处），单击编辑文字，可自由拖拽。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnNote:SetScript("OnLeave", GameTooltip_Hide)

    local btnPlayer = BG.CreateButton(bar)
    btnPlayer:SetSize(72, 22)
    btnPlayer:SetPoint("LEFT", btnNote, "RIGHT", 8, 0)
    btnPlayer:SetText(BG.STC_b1("[+] 玩家"))
    btnPlayer:SetScript("OnClick", function()
        RaidMap.ShowPlayerCustomMarkerPicker(btnPlayer)
        BG.PlaySound(1)
    end)
    btnPlayer:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("添加【单兵玩家标记】", 1, 1, 1)
        GameTooltip:AddLine("从团队队员中选取特定人员，生成带有其名字与职业颜色的单兵站位标记。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnPlayer:SetScript("OnLeave", GameTooltip_Hide)

    local btnClear = BG.CreateButton(bar)
    btnClear:SetSize(76, 22)
    btnClear:SetPoint("LEFT", btnPlayer, "RIGHT", 8, 0)
    btnClear:SetText(BG.STC_r1("清空标注"))
    btnClear:SetScript("OnClick", function()
        RaidMap.ClearCustomMarkers(f)
        BG.PlaySound(1)
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[战术画板]|r 已清空当前画布上的所有自定义图元与便签。")
    end)
    btnClear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("清空当前所有自定义标注", 1, 0.2, 0.2)
        GameTooltip:AddLine("一键移除画板上所有手动放置的标记、便签与单兵图元。\n(不影响 BOSS 预设与系统 1~25 号站位点)", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnClear:SetScript("OnLeave", GameTooltip_Hide)

    bar:Hide()
    f.drawToolbar = bar
    return bar
end

function RaidMap.RefreshSelfHighlight(f)
    if not f or not f.icons then return end
    local myName = UnitName("player")
    local mySpot = nil
    local isMeleeGroupMember = false

    for _, icon in ipairs(f.icons) do
        local isMine = false
        if not icon.v.isNPC then
            local p = RaidMap.assignedPlayers[icon.index]
            if p and p.name == myName then
                isMine = true
            end
        elseif icon.v.isNPC_icon == "Interface\\Icons\\ability_steelmelee" and RaidMap.meleeRoster then
            for _, m in ipairs(RaidMap.meleeRoster) do
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
                f.selfNotice:SetText("【您的专属站位: 近战集合组 (BOSS背后输出)】")
            else
                f.selfNotice:SetText(string.format("【您的专属站位: %s (%d号位)】", myName or "", mySpot.index or 0))
            end
        end
    else
        if f.selfNotice then
            f.selfNotice:SetText("")
        end
    end
end

--------------------------------------------------------------------------------
-- 8. 核心 BOSS 专属预设构建与多阶段加载器 (LoadBossTacticalPreset)
--------------------------------------------------------------------------------
function RaidMap.LoadBossTacticalPreset(bossID, phaseIndex)
    local f = RaidMap.CreateUI()
    if not f then return end
    local all = RaidMap.GetAllBosses()
    bossID = bossID or currentBossID
    if (not bossID or bossID == 0) and all and #all > 0 then
        bossID = all[1].id
    end
    bossID = bossID or 5
    if f.currentBossID and f.currentBossID ~= bossID then
        if RaidMap.ClearCustomMarkers then RaidMap.ClearCustomMarkers(f) end
    end
    currentBossID = bossID

    local bossData = RaidMap.GetBoss(bossID)
    if not bossData then
        for _, b in ipairs(all) do
            if b.id == bossID then bossData = b; break end
        end
    end
    if not bossData and all and #all > 0 then
        bossData = all[1]
        bossID = bossData.id
        currentBossID = bossID
    end

    if not bossData then
        f:Show()
        return
    end

    local fbName = bossData.fbName or "奥杜尔"
    local bossName = bossData.name or "首领"
    f.title:SetText(string.format("【%s】 %s", fbName, bossName))

    if f.dropBoss then
        if LibBG and LibBG.UIDropDownMenu_SetText then
            LibBG:UIDropDownMenu_SetText(f.dropBoss, bossName)
        else
            UIDropDownMenu_SetText(f.dropBoss, bossName)
        end
    end

    local activeTbl = nil
    local activeTip = nil
    local activeTex = nil

    -- 多阶段判定与 Tab 栏渲染
    if bossData.phases and #bossData.phases > 0 then
        currentPhase = phaseIndex or 1
        if currentPhase > #bossData.phases then currentPhase = 1 end
        f.phaseTabBar:Show()
        f.mapCanvas:SetPoint("TOPLEFT", 16, -92)

        for i, phase in ipairs(bossData.phases) do
            local btn = f.phaseButtons[i]
            if not btn then
                btn = BG.CreateButton(f.phaseTabBar)
                btn:SetSize(150, 26)
                if i == 1 then
                    btn:SetPoint("LEFT", 0, 0)
                else
                    btn:SetPoint("LEFT", f.phaseButtons[i - 1], "RIGHT", 6, 0)
                end
                f.phaseButtons[i] = btn
            end
            btn:SetSize(150, 26)
            btn:SetText(phase.name)
            btn:Show()
            if i == currentPhase then
                btn:SetBackdropBorderColor(0.2, 1, 0.4, 1)
                btn:SetText(BG.STC_g1(phase.name))
            else
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
                btn:SetText(BG.STC_w1(phase.name))
            end
            btn:SetScript("OnClick", function()
                RaidMap.LoadBossTacticalPreset(bossID, i)
                BG.PlaySound(1)
            end)
        end
        for i = #bossData.phases + 1, #f.phaseButtons do
            f.phaseButtons[i]:Hide()
        end

        local curP = bossData.phases[currentPhase]
        activeTbl = curP.tbl
        activeTip = curP.tacticTip or bossData.tacticTip
        activeTex = curP.mapTex or bossData.mapTex
    else
        currentPhase = 1
        f.currentPhase = 1
        RaidMap.currentPhase = 1
        f.phaseTabBar:Hide()
        for _, b in ipairs(f.phaseButtons) do b:Hide() end
        f.mapCanvas:SetPoint("TOPLEFT", 16, -66)

        activeTbl = bossData.tbl
        activeTip = bossData.tacticTip
        activeTex = bossData.mapTex
    end

    f.currentBossID = bossID
    f.currentPhase = currentPhase
    f.activeTacticTip = activeTip
    RaidMap.currentBossID = bossID
    RaidMap.currentPhase = currentPhase

    -- 场地左上角战术一句话核心概括 (绿字呈现)
    local subDesc = bossData and bossData.sub or ""
    if f.mapSubText then
        f.mapSubText:SetText(subDesc ~= "" and ("【战术核心】 " .. subDesc) or "")
    end

    -- 攻略详细文本 (首排以盾牌图标引导直接接上【xxx站位要点】，不浪费多余行数)
    local shieldIcon = "|TInterface\\AddOns\\BGLite_Plus\\Media\\shield.png:13:13:0:0|t "
    f.tacticTipText:SetText(activeTip and (shieldIcon .. activeTip) or "")

    -- 背景底图渲染与战术网格切换
    local grid = f.tacticalGrid or (f.mapCanvas and f.mapCanvas.tacticalGrid)
    if activeTex then
        f.mapTex:SetTexture(activeTex)
        f.mapTex:SetVertexColor(1, 1, 1, 0.95)
        f.mapTex:Show()
        if grid then grid:Hide() end
    else
        f.mapTex:Hide()
        DrawProceduralTacticalGrid(f.mapCanvas, f.mapCanvas:GetWidth(), f.mapCanvas:GetHeight(), bossID)
    end

    -- 清理旧图标
    for _, icon in ipairs(f.icons) do icon:Hide() end
    wipe(f.icons)

    -- 智能自动带入团队人员 (若处于队伍/团队或启用了拟真调试，选到Boss/阶段即自动分配入席)
    if RaidMap.AutoAssignRosterToMap then
        RaidMap.AutoAssignRosterToMap(true)
    end

    -- 渲染新图元点位 (静态坐标表 tbl 驱动)
    if activeTbl then
        for index, v in pairs(activeTbl) do
            CreateDraggablePointIcon(f.mapCanvas, index, v)
        end
    end

    RaidMap.RefreshSelfHighlight(f)
    RaidMap.SetViewMode(false)
    f:Show()
    f:Raise()
end

RaidMap.ShowDemoTacticalBoard = function(bossID)
    RaidMap.LoadBossTacticalPreset(bossID or 5, 1)
end

function RaidMap.Toggle(bossID)
    local f = mapFrame or BG.RaidMapFrame or _G["BG.RaidMapFrame"]
    if f and f:IsShown() then
        f:Hide()
    else
        RaidMap.LoadBossTacticalPreset(bossID or currentBossID or 5, currentPhase or 1)
        if mapFrame and not mapFrame:IsShown() then
            mapFrame:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- 9. 智能团队职责提取与全自动布阵 (AutoAssignRosterToMap)
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

function RaidMap.AutoAssignRosterToMap(isSilent)
    local f = mapFrame or BG.RaidMapFrame
    if not f then return end

    local rosterData = RaidMap.GetAutoRosterData()
    if not rosterData then
        if not isSilent then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite 战术站位图]|r 当前未处于队伍或团队中，请在组队后点击同步。")
        end
        return
    end

    wipe(RaidMap.assignedPlayers)
    wipe(RaidMap.meleeRoster)

    -- 动态分析当前首领/阶段 activeTbl 中的实际槽位职责类型
    local bossData = RaidMap.GetBoss(currentBossID)
    local curTbl = nil
    if bossData then
        if bossData.phases and #bossData.phases > 0 then
            local cp = currentPhase or 1
            curTbl = bossData.phases[cp] and bossData.phases[cp].tbl
        else
            curTbl = bossData.tbl
        end
    end

    local tankSlots = {}
    local healerSlots = {}
    local rangedSlots = {}

    if curTbl then
        for idx = 1, 40 do
            local spotInfo = curTbl[idx]
            if spotInfo and not spotInfo.isNPC then
                local r = spotInfo.role
                if not r then
                    r = (idx <= 2) and "tank" or (idx <= 7 and "healer" or "ranged")
                end
                if r == "tank" then
                    tinsert(tankSlots, idx)
                elseif r == "healer" then
                    tinsert(healerSlots, idx)
                else
                    tinsert(rangedSlots, idx)
                end
            end
        end
    else
        tankSlots = { 1, 2 }
        healerSlots = { 3, 4, 5, 6, 7 }
        for i = 8, 17 do tinsert(rangedSlots, i) end
    end

    -- 1. 坦克入席 (依次落座当前 Boss 的 tankSlots)
    local overflowTanks = {}
    for i, t in ipairs(rosterData.tanks) do
        if i <= #tankSlots then
            local slot = tankSlots[i]
            RaidMap.assignedPlayers[slot] = t
        else
            tinsert(overflowTanks, t)
        end
    end

    -- 2. 治疗入席 (优先保坦奶骑/戒律入席前排，团补入席后排)
    local allHealers = {}
    for _, h in ipairs(rosterData.tankHealers) do tinsert(allHealers, h) end
    for _, h in ipairs(rosterData.raidHealers) do tinsert(allHealers, h) end

    local overflowHealers = {}
    for i, h in ipairs(allHealers) do
        if i <= #healerSlots then
            local slot = healerSlots[i]
            RaidMap.assignedPlayers[slot] = h
        else
            tinsert(overflowHealers, h)
        end
    end

    -- 3. 远程与溢出人员灵活自适应填补
    local availableRangedSlots = {}
    for _, s in ipairs(rangedSlots) do tinsert(availableRangedSlots, s) end

    -- 3.1 溢出的治疗优先填入空闲的远程散点 (治疗同为远程，站远程位安全且不乱仇恨)
    for _, oh in ipairs(overflowHealers) do
        if #availableRangedSlots > 0 then
            local slot = tremove(availableRangedSlots, 1)
            RaidMap.assignedPlayers[slot] = oh
        end
    end

    -- 3.2 正常远程入席剩余的远程槽位
    local overflowRangeds = {}
    for _, r in ipairs(rosterData.rangeds) do
        if #availableRangedSlots > 0 then
            local slot = tremove(availableRangedSlots, 1)
            RaidMap.assignedPlayers[slot] = r
        else
            -- 远程预设槽位已满，检查是否有空闲的治疗槽位可以自适应借用
            local freeHealerSlot = nil
            for _, hs in ipairs(healerSlots) do
                if not RaidMap.assignedPlayers[hs] then
                    freeHealerSlot = hs
                    break
                end
            end
            if freeHealerSlot then
                RaidMap.assignedPlayers[freeHealerSlot] = r
            else
                tinsert(overflowRangeds, r)
            end
        end
    end

    -- 4. 近战全员归集于近战组 [98]；多余的备用坦克也合并入近战组
    for _, m in ipairs(rosterData.melees) do
        tinsert(RaidMap.meleeRoster, m)
    end
    for _, ot in ipairs(overflowTanks) do
        tinsert(RaidMap.meleeRoster, ot)
    end

    -- 刷新所有槽位显示 (若已有图标)
    if f.icons then
        for _, icon in ipairs(f.icons) do
            if icon.UpdateDisplay then
                icon:UpdateDisplay()
            end
        end
    end

    RaidMap.RefreshSelfHighlight(f)

    if not isSilent then
        local totalAssigned = 0
        for _, _ in pairs(RaidMap.assignedPlayers) do totalAssigned = totalAssigned + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[BGLite 战术站位图]|r 自动分配完毕：%d 位成员已入席指定槽位；近战 %d 人归集于【近战集合组】！",
            totalAssigned, #RaidMap.meleeRoster))
    end
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
        local isBoss = (icon.v and icon.v.isBoss) or (icon.role == "boss")
        local iconType = isBoss and "boss" or "tex"
        local iconTex = (icon.icon and icon.icon:GetTexture()) or ""
        local numText = (icon.numText and icon.numText:GetText()) or ""
        local playerText = (icon.playerText and icon.playerText:GetText()) or ""

        iconStr = iconStr .. format("%d¦%d¦%d¦%d¦%d¦%s¦%s¦%s¦%s¦%s¦%s¦%d¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f&&",
            level, x, y, w, w, iconType, iconTex,
            "", "", "", "",
            1, 1.0, 1.0, 1.0,
            numText, 1.0, 1.0, 1.0,
            playerText, 0.2, 0.8, 1.0
        )
    end

    if f.customMarkers then
        for _, marker in ipairs(f.customMarkers) do
            if marker:IsShown() then
                local level = marker:GetFrameLevel() or 22
                local x = math.floor(marker.x or 0)
                local y = math.floor(marker.y or 0)
                local w = math.floor(marker:GetWidth() or 32)
                local iconTex = ""
                local playerText = ""
                local numText = ""
                local iconType = "tex"

                if marker.markerType == "raidIcon" then
                    iconTex = string.format("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d", marker.iconID or 8)
                elseif marker.markerType == "text" then
                    iconTex = "Interface\\Icons\\INV_Scroll_02"
                    playerText = marker.text or "便签"
                elseif marker.markerType == "player" then
                    iconTex = (marker.playerData and marker.playerData.specIcon) or "Interface\\Icons\\INV_Misc_QuestionMark"
                    playerText = marker.text or ""
                end

                iconStr = iconStr .. format("%d¦%d¦%d¦%d¦%d¦%s¦%s¦%s¦%s¦%s¦%s¦%d¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f¦%s¦%.2f¦%.2f¦%.2f&&",
                    level, x, y, w, w, iconType, iconTex,
                    "", "", "", "",
                    1, 1.0, 1.0, 1.0,
                    numText, 1.0, 1.0, 1.0,
                    playerText, 0.2, 0.8, 1.0
                )
            end
        end
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
    local realTex = bossData and (bossData.mapTex or (bossData.phases and bossData.phases[1] and bossData.phases[1].mapTex))
    local grid = f.tacticalGrid or (f.mapCanvas and f.mapCanvas.tacticalGrid)
    if realTex then
        f.isUsingGrid = false
        f.mapTex:SetTexture(realTex)
        f.mapTex:Show()
        if grid then grid:Hide() end
    else
        f.isUsingGrid = true
        f.mapTex:Hide()
        DrawProceduralTacticalGrid(f.mapCanvas or f, mapWidth, mapHeight, bossIndex)
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

                local isBoss = (iconType == "boss")
                local isNPC = isBoss or isMeleeGroup or (numText == "")
                local v = {
                    xy = { x, y },
                    size = width,
                    isNPC = isNPC,
                    isBoss = isBoss,
                    isNPC_icon = iconTex ~= "" and iconTex or (isBoss and "Interface\\Icons\\achievement_boss_algalon_01" or (isMeleeGroup and "Interface\\Icons\\ability_steelmelee" or nil)),
                    isNPC_text = playerText or "",
                    isNPC_help = isMeleeGroup,
                }

                local idx = tonumber(numText) or (#f.icons + 1)
                local pointIcon = CreateDraggablePointIcon(f.mapCanvas, idx, v)
                if not isNPC and playerText and playerText ~= "" then
                    pointIcon.playerText:SetText(playerText)
                    pointIcon.playerText:SetTextColor(playerColor[1], playerColor[2], playerColor[3])
                    pointIcon.border:SetVertexColor(broderColor[1], broderColor[2], broderColor[3])
                    pointIcon.numText:SetText(numText ~= "" and numText or tostring(idx))
                    pointIcon.name = playerText
                end
                if isMeleeGroup then
                    pointIcon.members = members
                end
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
    -- 团队工具左侧面板已按规范彻底移除，入口已统一移至团队工具右侧面板顶部【战术站位图】按钮
end

--------------------------------------------------------------------------------
-- 14. 命令行支持 (/bgmap, /tjmap, /bglitemap)
--------------------------------------------------------------------------------
SLASH_BGLITEMAP1 = "/bgmap"
SLASH_BGLITEMAP2 = "/tjmap"
SLASH_BGLITEMAP3 = "/bglitemap"
SlashCmdList["BGLITEMAP"] = function(msg)
    RaidMap.Toggle()
end
