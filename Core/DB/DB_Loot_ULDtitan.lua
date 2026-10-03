-- ==============================================================================
-- BGLite_Plus 奥杜尔 (ULDtitan) 掉落数据修补与增强补丁
-- 设计哲学: 遵循 BASELINE 增量原则，不暴力整表覆盖上游 BGLite
-- 作用:
--   1. 基础继承: 完整保留上游 BGLite 官方更新的 348+ 件合体掉落与 ExchangeItems 映射
--   2. 无效清洗: 彻底剔除时光服客户端不存在/未开放的小怪无效物品 (消除大红问号)
--   3. 官方修补: 补齐上游 BGLite 官方遗漏的全部 T8 套装兑换物 (Token) 与守护者徽记
-- ==============================================================================
local AddonName, ns = ...

local function FixAndPatchUlduarLoot()
    if not BG or not BG.IsTitan then return end

    local FB = "ULDtitan"
    local hard = "N"

    -- 确保顶部 Tab 按钮名称正常显示为“奥杜尔”
    for _, v in ipairs(BG.FBtable2 or {}) do
        if v.FB == FB then
            if not v.shortName or v.shortName == "" then
                v.shortName = "奥杜尔"
            end
            if not v.localName or v.localName == "" or v.localName == UNKNOWN then
                v.localName = "奥杜尔"
            end
        end
    end

    if not BG.Loot or not BG.Loot[FB] or not BG.Loot[FB][hard] then return end

    local lootTable = BG.Loot[FB][hard]

    -- 辅助函数：安全追加不重复物品
    local function SafeAppend(list, itemsToAdd)
        if not list then return end
        local existing = {}
        for _, id in ipairs(list) do
            existing[tonumber(id)] = true
        end
        for _, id in ipairs(itemsToAdd) do
            local num = tonumber(id)
            if num and not existing[num] then
                existing[num] = true
                tinsert(list, num)
            end
        end
    end

    -- 辅助函数：清洗无效物品列表
    local function SafeRemove(list, itemsToRemove)
        if not list then return end
        local removeMap = {}
        for _, id in ipairs(itemsToRemove) do
            removeMap[tonumber(id)] = true
        end
        for i = #list, 1, -1 do
            if removeMap[tonumber(list[i])] then
                tremove(list, i)
            end
        end
    end

    -- ==========================================================================
    -- 1. 彻底清洗时光服不存在/未实装的无效装备 (消除游戏内大红问号)
    -- ==========================================================================
    local INVALID_ITEMS = {
        45521, -- 辟地 (尤格萨隆无效旧版ID)
        45538, -- 泰坦石坠 (旧版小怪)
        45539, -- 聚焦能量坠饰 (旧版小怪)
        45540, -- 持剑者的徽记之戒 (旧版小怪)
        45541, -- 变更斗篷 (旧版小怪)
        45542, -- 岩石卫士胫甲 (旧版小怪)
        45543, -- 灾祸护肩 (旧版小怪)
        45544, -- 苦痛大地护腿 (旧版小怪)
        45547, -- 圣物猎人的腰带 (旧版小怪)
        45548, -- 沉睡者束带 (旧版小怪)
        45549, -- 混乱之箍 (旧版小怪)
        45605, -- 达斯卡尔之牙 (旧版小怪)
        45506, -- 切碎者
    }

    for b = 1, 15 do
        if lootTable["boss" .. b] then
            SafeRemove(lootTable["boss" .. b], INVALID_ITEMS)
        end
    end

    -- ==========================================================================
    -- 2. 修复上游 BGLite 官方更新遗漏的全部 T8 套装代币 (Token)
    --    (上游只在 tbl 维护了成品映射，但忘记加入 Boss 的主掉落池，导致摸尸对账和表格选不到)
    -- ==========================================================================
    -- boss8 霍迪尔 (T8 胸部): 45632(征服者), 45633(保卫者), 45634(胜利者)
    if lootTable.boss8 then
        SafeAppend(lootTable.boss8, { 45632, 45633, 45634 })
    end

    -- boss9 托里姆 (T8 头部): 45638(征服者), 45639(保卫者), 45640(胜利者)
    if lootTable.boss9 then
        SafeAppend(lootTable.boss9, { 45638, 45639, 45640 })
    end

    -- boss10 弗蕾亚 (T8 腿部): 45653(征服者), 45654(保卫者), 45655(胜利者)
    if lootTable.boss10 then
        SafeAppend(lootTable.boss10, { 45653, 45654, 45655 })
    end

    -- boss11 米米尔隆 (T8 手部): 45641(征服者), 45642(保卫者), 45643(胜利者)
    if lootTable.boss11 then
        SafeAppend(lootTable.boss11, { 45641, 45642, 45643 })
    end

    -- boss13 尤格-萨隆 (T8 肩部): 45656(征服者), 45657(保卫者), 45658(胜利者)
    if lootTable.boss13 then
        SafeAppend(lootTable.boss13, { 45656, 45657, 45658 })
    end

    -- ==========================================================================
    -- 3. 补齐 boss15 杂项中遗漏的关键任务道具 (四大守护者徽记)
    -- ==========================================================================
    -- 45784 托里姆的徽记, 45787 米米尔隆的徽记
    if lootTable.boss15 then
        SafeAppend(lootTable.boss15, { 45784, 45787 })
    end
end

-- 立即执行初次修复
FixAndPatchUlduarLoot()

-- 并在 PLAYER_LOGIN 与 PLAYER_ENTERING_WORLD 进行安全防御修补
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    FixAndPatchUlduarLoot()
end)

