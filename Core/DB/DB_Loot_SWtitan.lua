-- ==============================================================================
-- BGLite_Plus P5 祖阿曼 (SWtitan) 掉落数据修补与增强补丁
-- 设计哲学: 严格遵守“零侵入”原则，不修改上游 BGLite 官方文件
-- 作用:
--   1. 补齐缺失: 官方遗漏的 33291 (巫毒纹路腰带) 与 33307 (公式：附魔武器 - 斩杀)
--   2. 安全去重: 采用 SafeAppend，绝不破坏原有表项，重复项自动去重
--   3. 防御更新: 无论官方 BGLite 如何覆盖更新，本补丁在游戏启动时动态在内存中补全
-- ==============================================================================
local AddonName, ns = ...

local function FixAndPatchSWtitanLoot()
    if not BG or not BG.IsTitan then return end

    local FB = "SWtitan"
    local hard = "N"

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

    -- ==========================================================================
    -- 1. boss1 埃基尔松: 官方遗漏 33291 (巫毒纹路腰带), 33307 (公式：附魔武器 - 斩杀)
    -- ==========================================================================
    if lootTable.boss1 then
        SafeAppend(lootTable.boss1, { 33291, 33307 })
    end

    -- ==========================================================================
    -- 2. boss2 ~ boss6 (纳洛拉克、埃基尔松、哈尔拉兹、妖术领主、祖尔金):
    --    官方遗漏 33307 (公式：附魔武器 - 斩杀)
    -- ==========================================================================
    for b = 2, 6 do
        if lootTable["boss" .. b] then
            SafeAppend(lootTable["boss" .. b], { 33307 })
        end
    end
end

-- 立即执行初次修复
FixAndPatchSWtitanLoot()

-- 并在 PLAYER_LOGIN 与 PLAYER_ENTERING_WORLD 进行安全防御修补
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    FixAndPatchSWtitanLoot()
end)
