# 掉落自动拍卖功能改动记录归档 (2026-09-11)

> **文档说明**：本文档记录 2026-09-11 期间针对【掉落自动拍卖】模块（`Core/AutoAuctionOnLoot.lua` 与 `Core/AuctionPreset.lua`）的所有改动细节、业务动机、故障排查经历以及已知隐患。供文件回滚（Revert）后进行精准、小步、针对性的二次修补提供参考依据。

---

## 一、 改动动机与用户需求

1. **白色装备误拍问题**：
   - 用户反馈小怪掉落的普通白色装备（如 `[布质护手]`、`[亚麻长靴]`）会弹出倒计时并自动发起全团拍卖；
   - 团长指出：BGLite 官方“记录入库”到金团表格的逻辑是准确的，要求**只有被真正记录进金团拍卖表格的装备，才展开自动拍卖**，未录入表格的绝不拍卖。
2. **开关默认值与操作引导**：
   - 自动拍卖总开关出厂默认关闭（防止团长未配价格直接开拍）；
   - 在自动拍卖开关旁边增加说明描述，建议配合预设价格使用；
   - 推荐最佳实践：`先批量设底价(100/300) -> 设特殊价(如升级物品1000) -> 设是否启用橙装/套装 -> 最后开启自动拍卖`。
3. **运行故障与线上报错**：
   - 下午更新后用户反馈即使勾选了自动拍卖也毫无反应；
   - 进团后控制台抛出报错：`BGLite_Plus/Core/AutoAuctionOnLoot.lua:55: attempt to call a nil value`。

---

## 二、 涉及文件与修改点总览

### 1. `Core/AuctionPreset.lua`（预设价格界面 UI）
- **底部常驻指引**：
  - 在“拾取后自动拍卖”开关左侧，将原本简单的提示重构为常驻最佳实践指引：
    `建议配合预设价格使用。最佳实践：1.批量设底价(如100/300) 2.设特殊价格(如升级物品1000) 3.设橙装/套装 4.开启自动拍卖`
  - 动态适配：当有装备单独设为“不自动（保留人工）”时，动态显示当前人工处理件数与流程简图。
- **新增黄色 `[?]` 帮助按钮与悬停浮窗**：
  - 在复选框文字右侧增加 `autoHelpBtn`（文字显示为 `|cffffd100[?]|r`）；
  - 鼠标悬停在复选框或 `[?]` 上时，弹出统一的 Tooltip 操作指南。

### 2. `Core/AutoAuctionOnLoot.lua`（核心拍卖与事件流逻辑）
- **默认值与配置自愈**：
  - `EnsureOptions()` 中将 `BiaoGe.options.autoAuctionOnLoot` 出厂默认值调整为 `0`；
  - 接入 `BG.Once("autoAuctionDefaultOff", 260911, function() ... end)` 规范化重置历史配置为关闭。
- **白装与误判拦截**：
  - 重构 `IsSetTokenOrRaidItem`：剔除了原代币名称匹配中的泛用防具词（“头盔”、“胸甲”、“护腿”、“肩铠”、“护手”、“护腕”、“腰带”、“长靴”），仅保留专属套装代币前缀（失落/战败/征服者/保卫者/胜利者/北伐奖章/圣洁徽记等）及非直接穿戴槽位检测；
  - 在 `QueueItemForAuction` 入口处加入对 `quality <= 1`（灰白物品）及超链接含有 `|cffffffff` / `|cff9d9d9d` 的绝对物理拦截；普通绿装非官方白名单一律拦截。
- **金团表格权威绑定 (`FindItemInBiaoGeTable`)**：
  - 新增 `FindItemInBiaoGeTable(itemID, link, FB)` 函数；
  - 遍历当前 FB、`BG.FB2`、`BG.FB1`、预设界面副本以及全部有效副本表格，检测装备是否已被 BGLite 权威写入表格 `BiaoGe[FB]["boss"..b]["zhuangbei"..i]`；
  - 提取所属准确 Boss 名称和槽位 Key。
- **触发源调整与时序对账**：
  - 移除了 `LOOT_OPENED` 摸尸体事件（避免未拾取前介入及小怪尸体扫描）；
  - `CHAT_MSG_LOOT` 移除 `not isMine` 过滤（只要全团任何人拾取入库金团表格，团长统一自动开拍）；
  - 接入三段式延迟对账（0.15s -> 0.40s -> 0.80s），等待 BGLite 的 `Loot.lua` 异步写入金团表格。
- **底层报错防御与 API 兼容**：
  - 实现自治安全的 `SafeGetItemID(text)`，解决 `GetItemID` 全局未定义导致的运行时崩盘；
  - 解决暴雪现代客户端中 `GetLootMethod` 被移至 `C_PartyInfo.GetLootMethod` 导致的 line 55 空指针报错；
  - 优先调用 BGLite 原生维护的 `BG.IsML` / `BG.IsLeader` / `BG.ImMLorLeader()` 进行极速权限判定。

---

## 三、 目前不稳定与存在故障的原因分析（还原后需要重点关注）

1. **时序与入库判定过度复杂**：
   - BGLite 自带的 `Loot.lua` 内部写入表格是通过 `BG.After(0.1)` 异步完成的；
   - 增强包在外部通过 `C_Timer.After` 延时轮询去查 `BiaoGe[FB]`，容易在网络卡顿、高频掉落、重载瞬间或特定副本别名不匹配时出现时序死锁或漏单；
2. **触发源取舍两难**：
   - **若保留 `LOOT_OPENED`**：摸尸体时物品还在尸体上，此时 BGLite 表格尚未录入，若强制要求 `requireInTable` 则直接被拦截；若不要求 `requireInTable`，小怪尸体又会被无脑扫描；
   - **若只保留 `CHAT_MSG_LOOT`**：只有物品进包后才触发；如果某些团长习惯直接在尸体上拍完再分（不拾取进包），或者团长不是分配者，则可能完全无法触发；
3. **改动侵入面过大**：
   - 增加了多层过滤、跨表全量扫描、三段定时器闭包，增加了逻辑维护的脆弱度。

---

## 四、 还原（Revert）与二次修补建议

### 1. 还原指令
在终端执行以下 Git 命令即可彻底还原这 2 个文件至修改前的干净状态：
```powershell
cd "e:\World of Warcraft\_classic_titan_\Interface\AddOns\BGLite_Plus"
git checkout HEAD Core/AutoAuctionOnLoot.lua Core/AuctionPreset.lua
```

### 2. 二次修补设计建议（轻量化方案）
后续若要重新修补，建议采取**极简、轻量、高内聚**的改法：
1. **白装拦截最简方案**：
   - 不必做复杂的表格检索逆向绑定，只需在 `QueueItemForAuction` 最开头加上 2 行纯色值与品质拦截：
     ```lua
     if link:find("|cffffffff") or link:find("|cff9d9d9d") then return end
     local _, _, q = GetItemInfo(link)
     if q and q <= 1 then return end
     ```
   - 并在代币正则中去除普通装备词（“长靴”、“护手”等），白装问题即可在 5 行代码内 100% 根除。
2. **默认关闭与说明最简方案**：
   - 仅修改 `EnsureOptions` 的初始值为 `0`；
   - 在 UI 上只增加说明文本和悬停，不改动复杂的底层调度结构。
3. **权限校验最简方案**：
   - 直接使用 `if BG and (BG.IsML or BG.IsLeader) then return true end`，彻底不调用任何可能报 nil 的原生 `GetLootMethod`。

---

## 五、 完整 Git Diff 源码存档

### 1. `Core/AuctionPreset.lua` Diff
```diff
--- a/Core/AuctionPreset.lua
+++ b/Core/AuctionPreset.lua
@@ -914,12 +914,13 @@ function ns.InitAuctionPresetModule()
             rowFrames[ri] = row
         end
 
-        -- 底部说明栏
+        -- 底部说明栏（位于自动拍卖开关左侧，紧邻开关并直接展示最佳实践）
         local bottomTip = f:CreateFontString(nil, "ARTWORK")
-        bottomTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
+        bottomTip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
         bottomTip:SetPoint("BOTTOMLEFT", 15, 8)
         bottomTip:SetTextColor(0.8, 0.8, 0.8)
-        bottomTip:SetText("提示：取消勾选装备后的【自动】即可禁止自动开拍，留待最后单独人工处理。")
+
+        local defaultTipText = "|cffffd100建议配合预设价格使用。最佳实践：|r|cff00ff001.|r批量设底价(如100/300) |cff00ff002.|r设特殊价格(如升级物品1000) |cff00ff003.|r设橙装/套装 |cff00ff004.|r开启自动拍卖"
 
         UpdateBottomTipCount = function()
             if not bottomTip then return end
@@ -931,9 +932,9 @@ function ns.InitAuctionPresetModule()
                 end
             end
             if manualCount > 0 then
-                bottomTip:SetText(string.format("提示：已设置 |cffff8000%d|r 件装备【不自动拍卖】(保留最后人工处理)。取消勾选【自动】即可设置。", manualCount))
+                bottomTip:SetText(string.format("|cffff8000已设 %d 件人工处理|r |cff666666| |r|cffffd100最佳实践：|r批量设底价(100/300) → 设特殊价(1000) → 设橙装/套装 → 开启自动拍卖", manualCount))
             else
-                bottomTip:SetText("提示：取消勾选装备后的【自动】即可禁止自动开拍，留待最后单独人工处理。")
+                bottomTip:SetText(defaultTipText)
             end
         end
 
@@ -952,24 +953,48 @@ function ns.InitAuctionPresetModule()
             BiaoGe.options = BiaoGe.options or {}
             BiaoGe.options.autoAuctionOnLoot = self:GetChecked() and 1 or 0
             if self:GetChecked() then
-                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已开启【拾取后自动拍卖】功能。团长拾取到Boss装备后将自动发起全团拍卖。")
+                DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已开启【拾取后自动拍卖】功能。团长拾取Boss装备进包且自动录入表格后，将发起全团自动拍卖。")
             else
                 DEFAULT_CHAT_FRAME:AddMessage("|cff00BFFF[BGLite]|r 已关闭【拾取后自动拍卖】功能。")
             end
         end)
-        autoCheck:SetScript("OnEnter", function(self)
-            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
+
+        -- 自动拍卖开关旁边的说明图标按钮 [?]
+        local autoHelpBtn = CreateFrame("Button", nil, f)
+        autoHelpBtn:SetSize(18, 18)
+        autoHelpBtn:SetPoint("LEFT", autoText, "RIGHT", 2, 0)
+        local autoHelpText = autoHelpBtn:CreateFontString(nil, "ARTWORK")
+        autoHelpText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
+        autoHelpText:SetPoint("CENTER", 0, 0)
+        autoHelpText:SetText("|cffffd100[?]|r")
+
+        -- 限制底部说明文本在开关左侧，防止重叠
+        bottomTip:SetPoint("RIGHT", autoCheck, "LEFT", -8, 0)
+        bottomTip:SetJustifyH("LEFT")
+
+        -- 最佳实践悬停说明
+        local function ShowAutoAuctionTooltip(owner)
+            GameTooltip:SetOwner(owner, "ANCHOR_TOP", 0, 4)
             GameTooltip:ClearLines()
-            GameTooltip:AddLine(L["拾取后自动拍卖"] or "拾取后自动拍卖", 1, 0.82, 0, true)
-            GameTooltip:AddLine("开启后，当团长拾取 Boss 掉落的装备进包时：", 0.9, 0.9, 0.9, true)
-            GameTooltip:AddLine("• 自动聚合同 Boss 掉落的所有未拍卖装备", 0, 1, 0)
-            GameTooltip:AddLine("• 优先按本页面设置的预设底价起拍", 0.4, 0.8, 1)
-            GameTooltip:AddLine("• 战斗中自动挂起等待，脱战后安全弹出", 1, 0.8, 0.2)
-            GameTooltip:AddLine("• 默认显示 5 秒倒计时浮动条，可点击立即全拍或取消", 0.8, 0.8, 0.8)
+            GameTooltip:AddLine(L["拾取后自动拍卖 - 使用指南与最佳实践"] or "拾取后自动拍卖 - 使用指南与最佳实践", 1, 0.82, 0, true)
+            GameTooltip:AddLine("建议配合预设价格使用，避免未预设起拍价导致误拍。", 0.9, 0.9, 0.9, true)
+            GameTooltip:AddLine(" ", 1, 1, 1)
+            GameTooltip:AddLine("★ 最佳实践操作流程：", 1, 0.82, 0, true)
+            GameTooltip:AddLine("  1. 先批量设置全部装备价格：|cffffffff点击顶栏【批量底价】，如设为 100 或 300G|r", 0, 1, 0, true)
+            GameTooltip:AddLine("  2. 再设置特殊价格：|cffffffff在列表中单独修改特殊装备（比如升级物品设为 1000G+）|r", 0, 1, 0, true)
+            GameTooltip:AddLine("  3. 确认是否启用橙装自动：|cffffffff橙装默认出厂人工保护；可按需点击【自动拍卖▾】调整|r", 0, 1, 0, true)
+            GameTooltip:AddLine("  4. 最后开启自动拍卖：|cffffffff全部价格与特殊选项核对无误后，再勾选开启此开关|r", 0, 1, 0, true)
+            GameTooltip:AddLine(" ", 1, 1, 1)
+            GameTooltip:AddLine("安全机制：仅当装备被金团表格正式记录入库后才会展开自动拍卖，白装/小怪杂物绝不误拍。", 0.4, 0.8, 1, true)
             GameTooltip:Show()
-        end)
+        end
+
+        autoCheck:SetScript("OnEnter", ShowAutoAuctionTooltip)
         autoCheck:SetScript("OnLeave", GameTooltip_Hide)
+        autoHelpBtn:SetScript("OnEnter", ShowAutoAuctionTooltip)
+        autoHelpBtn:SetScript("OnLeave", GameTooltip_Hide)
         f.autoAuctionCheck = autoCheck
+        f.autoHelpBtn = autoHelpBtn
 
         -- 免确认秒拍复选框
         local instantCheck = CreateFrame("CheckButton", "BGLite_AuctionPreset_InstantCheck", f, "UICheckButtonTemplate")
```

### 2. `Core/AutoAuctionOnLoot.lua` Diff
```diff
--- a/Core/AutoAuctionOnLoot.lua
+++ b/Core/AutoAuctionOnLoot.lua
@@ -4,15 +4,24 @@ local L = ns.L or {}
 local AutoAuctionOnLoot = {}
 ns.AutoAuctionOnLoot = AutoAuctionOnLoot
 
+-- 安全提取装备 ID 工具函数（杜绝全局 GetItemID 不存在导致的运行时报错崩溃）
+local function SafeGetItemID(text)
+    if not text then return nil end
+    if type(text) == "number" then return text end
+    local id = text:match("item:(%d+)") or text:match("Hitem:(%d+)")
+    return id and tonumber(id) or nil
+end
+local GetItemID = ns.GetItemID or SafeGetItemID
+
 -- 1. 配置项缺省自愈与默认开启
 local function EnsureOptions()
     BiaoGe = BiaoGe or {}
     BiaoGe.options = BiaoGe.options or {}
     -- 一次性安全自愈迁移：重置历史开启状态为默认关闭 0，建议团长按最佳实践配置预设后再主动开启
-    -- 注意：BG.Once 必须传入 3 个参数：(name, dt, func)
     if BG and BG.Once then
-        BG.Once("AutoAuctionDefaultOff_20260911", function()
+        BG.Once("autoAuctionDefaultOff", 260911, function()
             BiaoGe.options.autoAuctionOnLoot = 0
         end)
     end
@@ -27,10 +36,10 @@ local function EnsureOptions()
     end
 end
 
--- 2. 权限与环境校验 (严格限定大型团队副本 Raid，严禁 5 人小队或野外触发)
+-- 2. 权限与环境校验 (严格限定大型团队副本 Raid，严禁 5 人小队或野外普通怪物触发)
 local function CanInitiateAuction(isManualTest)
-    -- 2.1 若为手动测试指令 (/bgloot test)，直接允许通过
-    if isManualTest then return true end
+    -- 2.1 若为手动测试指令 (/bgloot test) 或开发者调试模式，直接放行
+    if isManualTest or (BG and (BG.DeBug or BG.DEBUG)) then return true end
 
     -- 2.2 核心限制：必须处于团队 (Raid) 中！5 人小队 (Party)、单人、野外一律严格拦截
     local inRaid = IsInRaid and (IsInRaid(1) or IsInRaid())
@@ -49,27 +58,32 @@ local function CanInitiateAuction(isManualTest)
         end
     end
 
-    -- 2.4 身份检测：必须是团队领袖 (团长) 或 物品分配者 (Master Looter)
+    -- 2.4 身份检测：优先直接使用 BGLite 权威计算的团长/分配者状态
+    if BG and (BG.IsML or BG.IsLeader or (BG.ImMLorLeader and BG.ImMLorLeader())) then
+        return true
+    end
+
+    -- 团队领袖 (团长) 兜底检测
     if UnitIsGroupLeader and UnitIsGroupLeader("player") then
         return true
     end
 
-    if IsMasterLooter and IsMasterLooter() then
-        return true
-    end
-
-    -- 经典旧世/时光服/WLK 中，若当前玩家是分配者，GetLootMethod 返回的 raidMaster/partyMaster 为 0
-    local lootmethod, partyMaster, raidMaster = GetLootMethod()
-    if lootmethod == "master" then
-        if raidMaster == 0 or partyMaster == 0 then
-            return true
-        elseif raidMaster and UnitIsUnit("raid" .. raidMaster, "player") then
-            return true
+    -- 物品分配者 (Master Looter) 兜底检测 (兼容 C_PartyInfo 新 API，杜绝 GetLootMethod 为空报错)
+    local GetLootMethodFunc = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
+    if GetLootMethodFunc then
+        local lootmethod, partyMaster, raidMaster = GetLootMethodFunc()
+        if lootmethod == "master" or lootmethod == 2 then
+            if raidMaster == 0 or partyMaster == 0 then
+                return true
+            elseif raidMaster and UnitIsUnit("raid" .. raidMaster, "player") then
+                return true
+            end
         end
     end
 
-    if BG and (BG.IsML or BG.IsLeader) then
+    if type(IsMasterLooter) == "function" and IsMasterLooter() then
         return true
     end
 
     return false
@@ -389,6 +403,63 @@ local combatWatcher = CreateFrame("Frame")
     end
 end)
 
+-- 检查物品是否已被正式【记录进拍卖表格】(BiaoGe[FB])
+local function FindItemInBiaoGeTable(itemID, link, FB)
+    if not BiaoGe then return false end
+    local targetID = itemID and tonumber(itemID)
+    if not targetID and link then
+        targetID = SafeGetItemID(link)
+    end
+    if not targetID then return false end
+
+    -- 确定待检查副本列表：优先传入FB -> BG.FB2 -> BG.FB1 -> 预设当前FB -> 全量BiaoGe
+    local fbsToCheck = {}
+    local addedFB = {}
+    local function AddFB(fbName)
+        if fbName and type(fbName) == "string" and fbName ~= "" and BiaoGe[fbName] and not addedFB[fbName] then
+            tinsert(fbsToCheck, fbName)
+            addedFB[fbName] = true
+        end
+    end
+
+    AddFB(FB)
+    AddFB(BG and BG.FB2)
+    AddFB(BG and BG.FB1)
+    AddFB(BiaoGe.auctionPreset and BiaoGe.auctionPreset.currentFB)
+
+    for fbName, fbData in pairs(BiaoGe) do
+        if type(fbData) == "table" and fbData.boss1 ~= nil then
+            AddFB(fbName)
+        end
+    end
+
+    for _, fbName in ipairs(fbsToCheck) do
+        local maxb = (BG and BG.Maxb and BG.Maxb[fbName]) or 30
+        for b = 1, maxb do
+            if BiaoGe[fbName]["boss" .. b] then
+                local maxi = (BG and BG.GetMaxi and BG.GetMaxi(fbName, b)) or 30
+                for i = 1, maxi do
+                    local txt = BiaoGe[fbName]["boss" .. b]["zhuangbei" .. i]
+                    if txt and txt ~= "" then
+                        local id = SafeGetItemID(txt)
+                        if (id and id == targetID) or (link and (txt == link or txt:find(link, 1, true))) then
+                            local bName = nil
+                            if BG and BG.Boss and BG.Boss[fbName] and BG.Boss[fbName]["boss" .. b] then
+                                bName = BG.Boss[fbName]["boss" .. b].name2 or BG.Boss[fbName]["boss" .. b].name
+                            end
+                            return true, b, i, bName, fbName
+                        end
+                    end
+                end
+            end
+        end
+    end
+    return false
+end
+AutoAuctionOnLoot.FindItemInBiaoGeTable = FindItemInBiaoGeTable
+
 -- 判断是否为套装代币 (Token) 或团本指定兑换物
 local function IsSetTokenOrRaidItem(itemID, link, name, FB)
@@ -420,11 +491,10 @@ local function IsSetTokenOrRaidItem(itemID, link, name, FB)
     end
 
-    -- 3. 套装代币专有名称特征模式匹配
+    -- 3. 套装代币专有名称特征模式匹配（严格限定专属前缀，绝不包含头盔/胸甲等泛用防具槽位词）
     local checkText = name or link or ""
     local isTokenName = checkText:find("失落的") or checkText:find("战败的") or checkText:find("征服者的")
        or checkText:find("保卫者的") or checkText:find("胜利者的") or checkText:find("勇猛") or checkText:find("英雄")
-       or checkText:find("头盔") or checkText:find("胸甲") or checkText:find("护腿") or checkText:find("肩铠")
-       or checkText:find("护手") or checkText:find("护腕") or checkText:find("腰带") or checkText:find("长靴")
        or checkText:find("圣洁勋服") or checkText:find("圣洁徽记") or checkText:find("北伐奖章") or checkText:find("十字军奖章")
        or checkText:find("代币") or checkText:find("印记") or checkText:find("徽记") or checkText:find("奖章")
@@ -522,12 +592,48 @@ function AutoAuctionOnLoot.QueueItemForAuction(link, explicitBossName, isManualT
     EnsureOptions()
     if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
     if not CanInitiateAuction(isManualTest) then return end
     if not link or link == "" then return end
 
     local itemID = GetItemInfoInstant(link)
     if not itemID then return end
 
+    -- 绝对物理防御：链接中直接包含白色 |cffffffff 或灰色 |cff9d9d9d 的物品，100% 绝对拦截！
+    if not isManualTest and (link:find("|cffffffff") or link:find("|cff9d9d9d")) then
+        return
+    end
+
+    -- 解析物品详细信息
+    local name, _, quality, level, _, _, _, _, _, Texture, _, classID, subclassID, bindType = GetItemInfo(link)
+    if not quality then
+        if link:find("|cffa335ee") then quality = 4
+        elseif link:find("|cffff8000") then quality = 5
+        elseif link:find("|cffe6cc80") then quality = 6
+        elseif link:find("|cff0070dd") then quality = 3
+        else quality = 1 end
+    end
+
+    -- 绝对物理防御：灰色(0)和白色(1)物品绝对不进入拍卖流程！
+    if not isManualTest and quality and quality <= 1 then
+        return
+    end
+
+    -- 绿色(2)物品必须是官方白名单物品，否则一律拦截
+    if not isManualTest and quality == 2 and not (BG and BG.Loot and BG.Loot.whitelist and (BG.Loot.whitelist[itemID] or (tonumber(itemID) and BG.Loot.whitelist[tonumber(itemID)]))) then
+        return
+    end
+
     -- 解析副本
     local FB = (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"
 
+    -- 核心关键机制：必须已被正式【记录进拍卖表格】，才展开自动拍卖！
+    local inTable, tableBossNum, tableSlot, tableBossName, foundFB = FindItemInBiaoGeTable(itemID, link, FB)
+    if not isManualTest and requireInTable and not inTable then
+        return
+    end
+    if foundFB then FB = foundFB end
+
@@ -627,31 +718,7 @@ function AutoAuctionOnLoot.QueueItemForAuction(link, explicitBossName, isManualT
     debounceTimer = C_Timer.NewTimer(1.5, ProcessPendingAuctions)
 end
 
--- 7. 触发源 A：LOOT_OPENED (摸尸体/打开掉落列表时立即捕获)
-local lootOpenedFrame = CreateFrame("Frame")
-lootOpenedFrame:RegisterEvent("LOOT_OPENED")
-lootOpenedFrame:SetScript("OnEvent", function(self, event, ...)
-    ...
-end)
-
--- 8. 触发源 B：CHAT_MSG_LOOT (装备进包/分配时捕获，采用绝对可靠的通用超链接正则)
+-- 7. 触发源 A：CHAT_MSG_LOOT (仅当装备被 BGLite 确认【记录进拍卖表格】后延时捕获)
 local lootMsgFrame = CreateFrame("Frame")
 lootMsgFrame:RegisterEvent("CHAT_MSG_LOOT")
 lootMsgFrame:SetScript("OnEvent", function(self, event, msg, ...)
@@ -660,39 +727,56 @@ lootMsgFrame:SetScript("OnEvent", function(self, event, msg, ...)
     if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
     if not CanInitiateAuction() then return end
 
     local link = msg:match("(|c%x+|Hitem:%d+.-|h%[.-%]|h|r)")
     if not link then return end
 
+    if link:find("|cffffffff") or link:find("|cff9d9d9d") then return end
+
+    local itemID = SafeGetItemID(link) or (GetItemInfoInstant and GetItemInfoInstant(link))
+    if not itemID then return end
+
+    local function TryQueueAfterTableCheck(attempt)
+        attempt = attempt or 1
+        local FB = (BG and BG.FB2) or (BG and BG.FB1) or "TOCtitan"
+        local inTable, b, i, bossName, foundFB = FindItemInBiaoGeTable(itemID, link, FB)
+        if inTable then
+            local activeFB = foundFB or FB
+            local slotKey = tostring(activeFB) .. "_" .. tostring(b) .. "_" .. tostring(i)
+            AutoAuctionOnLoot.QueueItemForAuction(link, bossName, false, slotKey, true)
+        elseif attempt < 3 then
+            C_Timer.After(attempt == 1 and 0.25 or 0.40, function()
+                TryQueueAfterTableCheck(attempt + 1)
+            end)
+        end
+    end
+
+    C_Timer.After(0.15, function()
+        TryQueueAfterTableCheck(1)
+    end)
 end)
 
--- 9. 触发源 C：BG.AddLootItem 外部调用的额外兜底
+-- 8. 触发源 B：BG.AddLootItem 外部调用的额外兜底
 if BG and BG.AddLootItem then
     hooksecurefunc(BG, "AddLootItem", function(FB, numb, link, Texture, level, Hope, count, typeID, lootplayer)
         if not link then return end
+        EnsureOptions()
+        if BiaoGe.options.autoAuctionOnLoot ~= 1 then return end
+        if not CanInitiateAuction() then return end
+
         local bName = nil
         if numb and BG and BG.Boss and FB and BG.Boss[FB] and BG.Boss[FB]["boss" .. numb] then
             bName = BG.Boss[FB]["boss" .. numb].name2 or BG.Boss[FB]["boss" .. numb].name
         end
-        AutoAuctionOnLoot.QueueItemForAuction(link, bName)
+        C_Timer.After(0.2, function()
+            AutoAuctionOnLoot.QueueItemForAuction(link, bName, false, nil, true)
+        end)
     end)
 end
```
