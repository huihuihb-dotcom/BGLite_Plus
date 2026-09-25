local AddonName, ns = ...

-- 全局基础环境加固：纯净魔兽客户端缺失 string.trim 垫片（杜绝依赖 tdInspect 等第三方库注入）
if not string.trim then
    string.trim = function(s)
        if not s then return "" end
        if strtrim then return strtrim(s) end
        return (tostring(s):gsub("^%s*(.-)%s*$", "%1"))
    end
end

-- 全局基础环境加固：暴雪官方 ObjectAPI Item:ContinueOnItemLoad 崩溃防御兜底
-- 彻底根治因无效 itemID 或未就绪链接导致 Blizzard_ObjectAPI/Classic/Item.lua:320 "table index is nil"
do
    local dummyItem = {
        ContinueOnItemLoad = function() end,
        IsItemDataCached = function() return false end,
    }
    if BG and BG.OnItemLoad then
        local raw_OnItemLoad = BG.OnItemLoad
        BG.OnItemLoad = function(item)
            if not item or item == "" or item == 0 then
                return dummyItem
            end
            local obj = raw_OnItemLoad(item)
            if not obj then
                return dummyItem
            end
            local raw_Continue = obj.ContinueOnItemLoad
            if raw_Continue then
                obj.ContinueOnItemLoad = function(self, callback)
                    local key = (self.GetItemKey and self:GetItemKey()) or (self.GetItemID and self:GetItemID())
                    if not key then
                        return
                    end
                    return raw_Continue(self, callback)
                end
            end
            return obj
        end
    end
end

-- 引用 LibBG 下拉菜单库与本地化
ns.LibBG = LibStub:GetLibrary("BiaoGe-LibUIDropDownMenu-4.0", true) or LibStub:GetLibrary("LibUIDropDownMenu-4.0", true) or (BG and BG.LibBG)
local L = ns.L or setmetatable({}, {
    __index = function(t, k)
        return tostring(k)
    end
})
ns.L = L

-- 常量
ns.RR = "\r\n"
ns.NN = "\n\n"
ns.RN = "\r\n\r\n"

-- 基础工具函数
local function Round(number, decimal_places)
    local mult = 10 ^ (decimal_places or 0)
    return math.floor(number * mult + 0.5) / mult
end
ns.Round = Round

local function RGB(str, a)
    if BG and BG.RGB then
        return BG.RGB(str, a)
    end
    return 1, 1, 1, a or 1
end
ns.RGB = RGB

local function RGB_16(name, r, g, b)
    if not r then
        r, g, b = name:GetTextColor()
        name = name:GetText()
    end
    local r = string.format("%02X", math.floor(tonumber(r) * 255 + 0.5))
    local g = string.format("%02X", math.floor(tonumber(g) * 255 + 0.5))
    local b = string.format("%02X", math.floor(tonumber(b) * 255 + 0.5))
    local c = r .. g .. b
    if name then
        return "|cff" .. c .. name .. "|r"
    else
        return c
    end
end
ns.RGB_16 = RGB_16

local function GetClassRGB(name, class, alpha)
    if BG and BG.GetClassRGB then
        return BG.GetClassRGB(name, class, alpha)
    end
    return 1, 1, 1, alpha or 1
end
ns.GetClassRGB = GetClassRGB

local function SetClassCFF(name, class)
    if BG and BG.SetClassCFF then
        return BG.SetClassCFF(name, class)
    end
    return name or ""
end
ns.SetClassCFF = SetClassCFF

local function AddTexture(Texture, y, coord, width)
    if not Texture then return "" end
    local x = 0
    y = y or "-0"
    local coord = coord or ""
    local tex = Texture
    if Texture == "MAINTANK" then
        tex = "132064"
    elseif Texture == "MAINASSIST" then
        tex = "132063"
    elseif Texture == "TANK" then
        return "|A:ui-lfg-roleicon-tank:0:0|a"
    elseif Texture == "HEALER" then
        return "|A:ui-lfg-roleicon-healer:0:0|a"
    elseif Texture == "DAMAGER" then
        return "|A:ui-lfg-roleicon-dps:0:0|a"
    elseif Texture == "LEFT" then
        return "|A:NPE_LeftClick:0:0|a"
    elseif Texture == "RIGHT" then
        return "|A:NPE_RightClick:0:0|a"
    end
    width = width or 0
    return "|T" .. tex .. ":" .. width .. ":" .. width .. ":" .. x .. ":" .. y .. coord .. "|t"
end
ns.AddTexture = AddTexture

local function GetItemID(item)
    if not item then return nil end
    if type(item) == "number" then return item end
    local id = item:match("item:(%d+)")
    return id and tonumber(id) or nil
end
ns.GetItemID = GetItemID

local function GetText_T(text, t)
    return text .. (t or "")
end
ns.GetText_T = GetText_T

local function GetClassColor(class)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        return RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, RAID_CLASS_COLORS[class].colorStr
    end
    return 1, 1, 1, "ffffffff"
end
ns.GetClassColor = GetClassColor

-- 尺寸和数据映射
ns.Size = function(size) return size end
ns.Maxt = setmetatable({}, {
    __index = function(t, fb)
        if BG and BG.BossNumtbl and BG.BossNumtbl[fb] then
            return #BG.BossNumtbl[fb]
        end
        return 3
    end
})
ns.Maxb = setmetatable({}, {
    __index = function(t, fb)
        if BG and BG.Boss and BG.Boss[fb] then
            local count = 0
            for k in pairs(BG.Boss[fb]) do
                if k:match("^boss%d+") then count = count + 1 end
            end
            if count > 0 then return count end
        end
        return 15
    end
})
ns.HopeMaxb = setmetatable({}, {
    __index = function(t, fb)
        local mb = ns.Maxb[fb]
        return mb and (mb - 1) or 10
    end
})
ns.HopeMaxn = setmetatable({}, {
    __index = function(t, fb)
        if BG and BG.difficultyTable and BG.difficultyTable[fb] then
            return #BG.difficultyTable[fb]
        end
        return 2
    end
})
ns.HopeMaxi = (BG and BG.IsRetail and 7) or 7

-- 补齐在 BGLite 中缺失的全局变量、方法与占位函数
if BG then
    if not BG.fullLevel_RoleOverview then
        local maxLvl = GetMaxPlayerLevel and GetMaxPlayerLevel()
        BG.fullLevel_RoleOverview = maxLvl or (BG.IsVanilla and 60) or (BG.IsTBC and 70) or (BG.IsWLK and 80) or (BG.IsCTM and 85) or (BG.IsMOP and 90) or 80
    end
    BG.fullLevel = BG.fullLevel or BG.fullLevel_RoleOverview
    BG.HideHistoryMoney = BG.HideHistoryMoney or function() end
    BG.FilterClassItemDB = BG.FilterClassItemDB or {}
    BG.FilterClassItem_Default = BG.FilterClassItem_Default or {}
    BG.Update_IsLooted = BG.Update_IsLooted or function() end
    BG.UpdateFilter = BG.UpdateFilter or function() end
    BG.AddHText = BG.AddHText or function() end
    BG.LootedText = BG.LootedText or function() end
    BG.BindOnEquip = BG.BindOnEquip or function() end
    BG.LevelText = BG.LevelText or function() end
    BG.IsHave = BG.IsHave or function() end
end

-- 安全获取当前角色的心愿单数据库 (双向同步全名与短名，杜绝键名不一致问题)
function BG.GetHopeDB(realmID, player)
    if not BiaoGe then return nil end
    realmID = realmID or GetRealmID()
    if not realmID then return nil end

    BiaoGe.Hope = BiaoGe.Hope or {}
    BiaoGe.Hope[realmID] = BiaoGe.Hope[realmID] or {}

    local shortName = UnitName("player")
    local fullName = BG.playerName
    local targetPlayer = player or shortName or fullName

    if not targetPlayer or targetPlayer == "" then return nil end

    local realmDB = BiaoGe.Hope[realmID]

    -- 检查现有数据：全名或短名是否存在
    local dbShort = shortName and realmDB[shortName]
    local dbFull = fullName and realmDB[fullName]

    local mainDB = dbShort or dbFull
    if not mainDB then
        mainDB = {}
    end

    -- 双向同步绑定：让全名与短名都指向同一份数据引用
    if shortName and shortName ~= "" then
        realmDB[shortName] = mainDB
    end
    if fullName and fullName ~= "" then
        realmDB[fullName] = mainDB
    end
    if player and player ~= "" and not realmDB[player] then
        realmDB[player] = mainDB
    end

    return realmDB[targetPlayer] or mainDB
end

-- 初始化 BiaoGe.Hope 嵌套数据库 (对齐原版 DB.lua 预分配 n=1..4, b=1..30 彻底防 nil 越界崩溃)
function ns.InitHopeDB()
    if not BiaoGe then return end
    local realmID = GetRealmID()
    if not realmID then return end

    local charHopeDB = BG.GetHopeDB(realmID)
    if not charHopeDB then return end

    local fbList = {}
    if BG then
        if BG.FBtable then for _, fb in ipairs(BG.FBtable) do fbList[fb] = true end end
        if BG.phaseFBtable then
            for fb, tbl in pairs(BG.phaseFBtable) do
                fbList[fb] = true
                if type(tbl) == "table" then
                    for _, subFB in ipairs(tbl) do fbList[subFB] = true end
                end
            end
        end
        if BG.FBCDall_table then for _, fb in ipairs(BG.FBCDall_table) do fbList[fb] = true end end
    end
    local defaultFBs = { "ICC", "TOC", "ULD", "NAXX", "RS", "TOCtitan", "RS25", "ICCtitan", "ULDtitan", "NAXXtitan", "SWP", "BT", "HS", "SSC", "TK", "ZAM", "MC", "BWL", "TAQ", "NAXX60", "ZG", "RAQ", "SSCtitan", "TKtitan" }
    for _, fb in ipairs(defaultFBs) do fbList[fb] = true end

    for FB, _ in pairs(fbList) do
        if type(FB) == "string" and FB ~= "" then
            BiaoGe[FB] = BiaoGe[FB] or {}
            BiaoGe[FB].tradeTbl = BiaoGe[FB].tradeTbl or {}

            charHopeDB[FB] = charHopeDB[FB] or {}
            for n = 1, 4 do
                charHopeDB[FB]["nandu" .. n] = charHopeDB[FB]["nandu" .. n] or {}
                for b = 1, 30 do
                    charHopeDB[FB]["nandu" .. n]["boss" .. b] = charHopeDB[FB]["nandu" .. n]["boss" .. b] or {}
                end
            end
        end
    end
end

-- 全局基础数据库结构自愈补齐 (彻底防止任何模块访问空表报错)
function ns.EnsureAllDBStructures()
    if not BiaoGe then return end
    local realmID = GetRealmID()
    local player = UnitName("player")
    if not realmID then return end

    BiaoGe.playerInfo = BiaoGe.playerInfo or {}
    BiaoGe.playerInfo[realmID] = BiaoGe.playerInfo[realmID] or {}

    BiaoGe.equip = BiaoGe.equip or {}
    BiaoGe.equip[realmID] = BiaoGe.equip[realmID] or {}

    BiaoGe.MONEY = BiaoGe.MONEY or {}
    BiaoGe.MONEY[realmID] = BiaoGe.MONEY[realmID] or {}

    BiaoGe.RaidCD = BiaoGe.RaidCD or {}
    BiaoGe.RaidCD[realmID] = BiaoGe.RaidCD[realmID] or {}

    BiaoGe.QuestCD = BiaoGe.QuestCD or {}
    BiaoGe.QuestCD[realmID] = BiaoGe.QuestCD[realmID] or {}

    BiaoGe.roleOverviewNote = BiaoGe.roleOverviewNote or {}
    BiaoGe.roleOverviewNote[realmID] = BiaoGe.roleOverviewNote[realmID] or {}

    BiaoGe.realmName = BiaoGe.realmName or {}
    local rName = GetRealmName()
    if rName and rName ~= "" then
        BiaoGe.realmName[realmID] = rName
    end

    if player and player ~= "" then
        BiaoGe.playerInfo[realmID][player] = BiaoGe.playerInfo[realmID][player] or {}
        BiaoGe.playerInfo[realmID][player].class = BiaoGe.playerInfo[realmID][player].class or select(2, UnitClass("player"))
        BiaoGe.playerInfo[realmID][player].level = BiaoGe.playerInfo[realmID][player].level or UnitLevel("player")
        BiaoGe.playerInfo[realmID][player].faction = BiaoGe.playerInfo[realmID][player].faction or UnitFactionGroup("player")

        BiaoGe.equip[realmID][player] = BiaoGe.equip[realmID][player] or {}
        BiaoGe.MONEY[realmID][player] = BiaoGe.MONEY[realmID][player] or {}
        BiaoGe.MONEY[realmID][player].skill = BiaoGe.MONEY[realmID][player].skill or {}
        BiaoGe.RaidCD[realmID][player] = BiaoGe.RaidCD[realmID][player] or {}
        BiaoGe.QuestCD[realmID][player] = BiaoGe.QuestCD[realmID][player] or {}
    end

    -- 全副本 BiaoGe[FB]["boss1~40"] 数据结构安全预补全 (零修改 BGLite 原版消除 FBUIfunction.lua:996 报错)
    local fbList = {}
    if BG then
        if BG.FBtable then for _, fb in ipairs(BG.FBtable) do fbList[fb] = true end end
        if BG.phaseFBtable then for _, fb in ipairs(BG.phaseFBtable) do fbList[fb] = true end end
        if BG.FBCDall_table then for _, fb in ipairs(BG.FBCDall_table) do fbList[fb] = true end end
    end
    local defaultFBs = { "ICC", "TOC", "ULD", "NAXX", "RS", "TOCtitan", "RS25", "ICCtitan", "ULDtitan", "NAXXtitan", "SWP", "BT", "HS", "SSC", "TK", "ZAM", "MC", "BWL", "TAQ", "NAXX60", "ZG", "RAQ" }
    for _, fb in ipairs(defaultFBs) do fbList[fb] = true end

    for fb, _ in pairs(fbList) do
        if type(fb) == "string" and fb ~= "" then
            BiaoGe[fb] = BiaoGe[fb] or {}
            BiaoGe[fb].tradeTbl = BiaoGe[fb].tradeTbl or {}
            for b = 1, 40 do
                BiaoGe[fb]["boss" .. b] = BiaoGe[fb]["boss" .. b] or {}
            end
        end
    end

    -- 针对当前所有已存副本表进行 boss1~40 自愈补齐
    for fbKey, tbl in pairs(BiaoGe) do
        if type(tbl) == "table" and type(fbKey) == "string" and fbKey ~= "options" and fbKey ~= "playerInfo" and fbKey ~= "equip" and fbKey ~= "MONEY" and fbKey ~= "RaidCD" and fbKey ~= "QuestCD" and fbKey ~= "roleOverviewNote" and fbKey ~= "realmName" and fbKey ~= "point" and fbKey ~= "duizhang" and fbKey ~= "BossFrame" and fbKey ~= "FilterClassItemDB" and fbKey ~= "Hope" and fbKey ~= "RaidTool" and fbKey ~= "RaidGroups" and fbKey ~= "whoFrame" then
            tbl.tradeTbl = tbl.tradeTbl or {}
            for b = 1, 40 do
                tbl["boss" .. b] = tbl["boss" .. b] or {}
            end
        end
    end
end

-- 确保 BiaoGe.options 默认值健全 (角色总览强制默认怀旧服横向布局 up_down)
local function InitDefaultOptions()
    if not BiaoGe then return end
    BiaoGe.options = BiaoGe.options or {}
    if BiaoGe.options["roleOverviewNotShowLevel"] == nil then
        BiaoGe.options["roleOverviewNotShowLevel"] = 1
    end
    if BiaoGe.options["roleOverviewNotShowiLevel"] == nil then
        BiaoGe.options["roleOverviewNotShowiLevel"] = 0
    end
    if BiaoGe.options["roleOverviewLayout"] == nil or BiaoGe.options["roleOverviewLayout"] == "new" then
        BiaoGe.options["roleOverviewLayout"] = "up_down"
    end
    if BiaoGe.options["roleOverviewShowAllServer"] == nil then
        BiaoGe.options["roleOverviewShowAllServer"] = 1
    end
    if BiaoGe.options["roleOverviewOnlyFullLevel"] == nil then
        BiaoGe.options["roleOverviewOnlyFullLevel"] = 1
    end
    if BiaoGe.options["roleOverviewResOnlyFullLevel"] == nil then
        BiaoGe.options["roleOverviewResOnlyFullLevel"] = 0
    end
    if BiaoGe.options["roleOverviewClassSort"] == nil then
        BiaoGe.options["roleOverviewClassSort"] = "level"
    end
    if BiaoGe.options["roleOverviewSort1"] == nil then
        BiaoGe.options["roleOverviewSort1"] = "iLevel-class-player"
    end
    if BiaoGe.options["roleOverviewShowBuffCD"] == nil then
        BiaoGe.options["roleOverviewShowBuffCD"] = 1
    end
    if BiaoGe.options["searchList"] == nil then
        BiaoGe.options["searchList"] = 1
    end
    if BiaoGe.HopeSendChannel == nil then
        BiaoGe.HopeSendChannel = "RAID"
    end

    ns.EnsureAllDBStructures()
    ns.InitHopeDB()
    if ns.InitRaidToolDB then
        ns.InitRaidToolDB()
    end
end

InitDefaultOptions()
local optFrame = CreateFrame("Frame")
optFrame:RegisterEvent("PLAYER_LOGIN")
optFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
optFrame:SetScript("OnEvent", InitDefaultOptions)

local function BossNum(FB, b, t)
    if BG and BG.BossNumtbl and BG.BossNumtbl[FB] then
        local tbl = BG.BossNumtbl[FB]
        local bb
        if tbl[t + 1] then
            bb = tbl[t + 1] - tbl[t]
        else
            bb = (ns.Maxb[FB] or 10) + 2 - tbl[t]
        end
        return b + tbl[t], bb, t, b
    end
    return b, 1, t, b
end
ns.BossNum = BossNum
