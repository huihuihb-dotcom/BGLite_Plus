if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L or {}
local GetItemID = ns.GetItemID or function(link)
    if not link then return nil end
    if type(link) == "number" then return link end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function GetClassRGB(class)
    if ns.GetClassRGB then
        return ns.GetClassRGB(nil, class)
    end
    if RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b, c.colorStr
    end
    return 1, 1, 1, "ffffffff"
end

local function RGB(hex, alpha)
    if ns.RGB then return ns.RGB(hex, alpha) end
    local r = tonumber(strsub(hex, 1, 2), 16) / 255
    local g = tonumber(strsub(hex, 3, 4), 16) / 255
    local b = tonumber(strsub(hex, 5, 6), 16) / 255
    return r, g, b, alpha or 1
end

local function AddTexture(tex, size)
    if not tex then return "" end
    size = size or 16
    return string.format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t ", tostring(tex), size, size)
end

-- 模块命名空间
local LH = {}
ns.LootHistory = LH

LH.MainFrame = nil
LH.filteredList = {}
LH.rowFrames = {}

local VISIBLE_ROWS = 21
local ROW_HEIGHT = 23
local MAX_STORED = 400

-- 模式匹配串预热 (采用暴雪原生本地化常量)
local LOOT_PATTERNS = {}
do
    if LOOT_ITEM_SELF_MULTIPLE then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"), self = true, multi = true }) end
    if LOOT_ITEM_PUSHED_SELF_MULTIPLE then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_PUSHED_SELF_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"), self = true, multi = true }) end
    if LOOT_ITEM_SELF then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_SELF:gsub("%%s", "(.+)"), self = true, multi = false }) end
    if LOOT_ITEM_PUSHED_SELF then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_PUSHED_SELF:gsub("%%s", "(.+)"), self = true, multi = false }) end
    if LOOT_ITEM_MULTIPLE then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"), self = false, multi = true }) end
    if LOOT_ITEM_PUSHED_MULTIPLE then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_PUSHED_MULTIPLE:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)"), self = false, multi = true }) end
    if LOOT_ITEM then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM:gsub("%%s", "(.+)"), self = false, multi = false }) end
    if LOOT_ITEM_PUSHED then table.insert(LOOT_PATTERNS, { pat = LOOT_ITEM_PUSHED:gsub("%%s", "(.+)"), self = false, multi = false }) end
end

-- 获取当前副本掉落历史记录表
function LH.GetHistoryDB(fb)
    fb = fb or BG.FB1
    if not (fb and BiaoGe) then return {} end
    BiaoGe[fb] = BiaoGe[fb] or {}
    BiaoGe[fb].lootHistory = BiaoGe[fb].lootHistory or {}
    return BiaoGe[fb].lootHistory
end

-- 检查某个物品是否已经记入主表格 (防漏少记核心算法)
function LH.CheckIsTabled(fb, itemID)
    fb = fb or BG.FB1
    if not (fb and BiaoGe and BiaoGe[fb] and itemID) then return false, nil end

    local maxb = (ns.Maxb and ns.Maxb[fb]) or 30
    for b = 1, maxb do
        local bossKey = "boss" .. b
        local bossTbl = BiaoGe[fb][bossKey]
        if bossTbl then
            local maxI = (BG.GetMaxi and BG.GetMaxi(fb, b)) or 10
            for i = 1, maxI do
                local zb = bossTbl["zhuangbei" .. i]
                if zb and zb ~= "" then
                    local zbID = GetItemID(zb)
                    if zbID and (zbID == itemID or (BG.IsSame and BG.IsSame(itemID, zbID))) then
                        local bossName = (BG.Boss and BG.Boss[fb] and BG.Boss[fb][bossKey] and BG.Boss[fb][bossKey].name2) or bossKey
                        return true, bossName
                    end
                end
            end
        end
    end
    return false, nil
end

-- 玩家职业反查缓存
local playerClassCache = {}
local function GetPlayerClass(playerName)
    if not playerName or playerName == "" then return nil end
    local short = playerName:match("^([^-]+)") or playerName
    if playerClassCache[short] then return playerClassCache[short] end

    -- 查队友
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, fileName = GetRaidRosterInfo(i)
            if name then
                local sName = name:match("^([^-]+)") or name
                if fileName then playerClassCache[sName] = fileName end
                if sName == short and fileName then return fileName end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                local sName = name:match("^([^-]+)") or name
                local _, fileName = UnitClass(unit)
                if fileName then playerClassCache[sName] = fileName end
                if sName == short and fileName then return fileName end
            end
        end
    end

    if short == UnitName("player") then
        local _, c = UnitClass("player")
        playerClassCache[short] = c
        return c
    end

    return nil
end

-- 解析拾取消息
local function ParseLootMessage(msg)
    if not msg then return nil end

    local lootPlayer, itemLink, count

    -- 依次匹配预置的模式串
    for _, item in ipairs(LOOT_PATTERNS) do
        if item.self then
            if item.multi then
                local l, c = msg:match(item.pat)
                if l then
                    lootPlayer = UnitName("player")
                    itemLink = l
                    count = tonumber(c) or 1
                    break
                end
            else
                local l = msg:match(item.pat)
                if l then
                    lootPlayer = UnitName("player")
                    itemLink = l
                    count = 1
                    break
                end
            end
        else
            if item.multi then
                local p, l, c = msg:match(item.pat)
                if p and l then
                    lootPlayer = p
                    itemLink = l
                    count = tonumber(c) or 1
                    break
                end
            else
                local p, l = msg:match(item.pat)
                if p and l then
                    lootPlayer = p
                    itemLink = l
                    count = 1
                    break
                end
            end
        end
    end

    -- 兼容备用提取 (应对自定义聊天插件格式或非常规拾取格式)
    if not (itemLink and lootPlayer) then
        local p, l, c = msg:match("([^%s:]+)获得了[^：:]*[：:]%s*(|c%x+|Hitem:[^|]+|h%[[^%]]+%]%|r)x?(%d*)")
        if p and l then
            lootPlayer = (p == "你" or p == "You") and UnitName("player") or p
            itemLink = l
            count = tonumber(c) or 1
        else
            local p2, l2, c2 = msg:match("([^%s:]+)%s+receives%s+[^:]*:%s*(|c%x+|Hitem:[^|]+|h%[[^%]]+%]%|r)x?(%d*)")
            if p2 and l2 then
                lootPlayer = (p2 == "You" or p2 == "you") and UnitName("player") or p2
                itemLink = l2
                count = tonumber(c2) or 1
            else
                local l3 = msg:match("(|c%x+|Hitem:[^|]+|h%[[^%]]+%]%|r)")
                if l3 then
                    itemLink = l3
                    lootPlayer = lootPlayer or UnitName("player")
                    count = 1
                end
            end
        end
    end

    if itemLink and lootPlayer then
        lootPlayer = lootPlayer:match("^([^-]+)") or lootPlayer
        return lootPlayer, itemLink, count or 1
    end
    return nil
end

-- 物品重要性与过滤检测
local function IsRecordableLoot(itemID, quality, itemLink)
    if not itemID then return false end

    -- 1. 特殊关键杂项强制记录 (泰坦余烬, 泰坦碎片, 橙片, 图纸, 牌子, 钱袋等)
    local forcedItems = {
        [49426] = true, -- 寒冰纹章
        [47241] = true, -- 凯旋纹章
        [45624] = true, -- 征服纹章
        [40752] = true, -- 勇气纹章
        [40753] = true, -- 英雄纹章
        [45038] = true, -- 瓦兰奈尔的碎片
        [49908] = true, -- 原初萨隆邪铁
        [43950] = true, -- 重新打包的泰坦余烬
        [43951] = true, -- 泰坦余烬
        [43952] = true, -- 泰坦神铁碎片
    }
    if forcedItems[itemID] then return true end

    -- 2. 依据品质过滤 (默认优秀/绿色 2 及以上，或更高)
    if quality and quality >= 2 then
        return true
    end

    -- 3. 装绑或高价值物品
    if itemLink then
        local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(itemLink)
        if classID == 2 or classID == 4 then -- 武器或防具
            return true
        end
    end

    return false
end

-- 记录掉落入库
local function OnLootCaptured(lootPlayer, itemLink, count)
    local itemID = GetItemID(itemLink)
    if not itemID then return end

    local name, _, quality, iLevel, _, _, _, _, equipLoc, texture = GetItemInfo(itemLink)
    quality = quality or select(3, GetItemInfoInstant(itemLink)) or 1

    if not IsRecordableLoot(itemID, quality, itemLink) then
        return
    end

    -- 严格检测当前是否处于团队副本内部，只有在该副本内掉落才关联该副本并更新时间戳
    local inInstance, instanceType = IsInInstance()
    local currentInstanceFB = nil
    if inInstance and BG and BG.FBIDtable then
        local FBID = select(8, GetInstanceInfo())
        if FBID and BG.FBIDtable[FBID] then
            currentInstanceFB = BG.FBIDtable[FBID]
        end
    end

    -- 若玩家身处正规团本，fb采用该团本；若在5人本或野外，严禁污染BG.FB1团本的时间戳与表格数据
    local fb = currentInstanceFB or BG.FB1 or "TOC"
    local db = LH.GetHistoryDB(fb)

    -- 实时记录当前副本表格的打本真实开始与活跃时间 (仅在身处该团本内部时才更新！)
    if currentInstanceFB and BiaoGe and BiaoGe[currentInstanceFB] then
        local nowTs = (GetServerTime and GetServerTime()) or time()
        local curWeekStart = (ns.WorkerReport and ns.WorkerReport.GetCDWeekStart and ns.WorkerReport.GetCDWeekStart(nowTs)) or (nowTs - 7 * 86400)
        local rt = tonumber(BiaoGe[currentInstanceFB].raidTime)
        if not rt or rt < curWeekStart or (nowTs - rt > 16 * 3600) then
            BiaoGe[currentInstanceFB].raidTime = nowTs
        end
        BiaoGe[currentInstanceFB].lastRaidTime = nowTs
        local myName = UnitName("player")
        if myName and myName ~= "" and (not BiaoGe[currentInstanceFB].charName or BiaoGe[currentInstanceFB].charName == "") then
            BiaoGe[currentInstanceFB].charName = myName
            BiaoGe[currentInstanceFB].class = select(2, UnitClass("player")) or "WARRIOR"
        end
    end

    local pClass = GetPlayerClass(lootPlayer)
    local timeStr = date("%H:%M:%S")

    -- 智能获取来源Boss/区域
    local source = ""
    if UnitExists("target") and not UnitIsPlayer("target") then
        local tName = UnitName("target")
        if tName and tName ~= "" then source = tName end
    end
    if source == "" and BG.lastCombatBossName then
        source = BG.lastCombatBossName
    end
    if source == "" then
        source = GetRealZoneText() or fb
    end

    local entry = {
        time = timeStr,
        timestamp = time(),
        player = lootPlayer,
        class = pClass,
        link = itemLink,
        itemID = itemID,
        count = count or 1,
        quality = quality,
        iLevel = iLevel or 0,
        texture = texture or select(5, GetItemInfoInstant(itemLink)),
        source = source,
    }

    -- 倒序插入在最前
    table.insert(db, 1, entry)

    -- 超过上限移除旧数据
    while #db > MAX_STORED do
        table.remove(db)
    end

    -- 如果界面处于打开态，即时刷新
    if LH.MainFrame and LH.MainFrame:IsShown() then
        LH.RefreshList()
    end
end

-------------------------------------------------------------------------------
-- UI 界面构建
-------------------------------------------------------------------------------
function LH.CreateMainFrame(parent)
    if LH.MainFrame then return LH.MainFrame end

    local f = CreateFrame("Frame", "BG_LootHistoryMainFrame", parent or BG.MainFrame, "BackdropTemplate")
    f:SetAllPoints()
    f:Hide()
    LH.MainFrame = f

    -- 顶部标题与说明
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 18, "OUTLINE")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -32)
    title:SetText(BG.STC_g1("【掉落拾取流水记录】") .. " " .. BG.STC_y2("(Beta版)"))

    -- 顶部实时统计文字
    local summaryText = f:CreateFontString(nil, "OVERLAY")
    summaryText:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    summaryText:SetPoint("LEFT", title, "RIGHT", 15, 0)
    summaryText:SetText("")
    f.summaryText = summaryText

    -- 搜索框 (向左调整X轴起始位置，预留出右侧复选框与操作按钮的总宽度，彻底避免窄窗口时清空按钮溢出到外面)
    local searchBox = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    searchBox:SetSize(150, 22)
    searchBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -460, -32)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText("搜索玩家或装备...")
    searchBox:HookScript("OnTextChanged", function(self)
        LH.RefreshList()
    end)
    f.searchBox = searchBox

    -- 复选框 1：仅看未记入表格
    local chkOnlyNotTabled = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkOnlyNotTabled:SetSize(22, 22)
    chkOnlyNotTabled:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    chkOnlyNotTabled.text = chkOnlyNotTabled:CreateFontString(nil, "OVERLAY")
    chkOnlyNotTabled.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    chkOnlyNotTabled.text:SetPoint("LEFT", chkOnlyNotTabled, "RIGHT", 2, 0)
    chkOnlyNotTabled.text:SetText(BG.STC_r1("仅看未记入表格"))
    chkOnlyNotTabled:SetChecked(false)
    chkOnlyNotTabled:SetScript("OnClick", function(self)
        LH.RefreshList()
        BG.PlaySound(1)
    end)
    f.chkOnlyNotTabled = chkOnlyNotTabled

    -- 复选框 2：仅看史诗/精良
    local chkOnlyRare = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkOnlyRare:SetSize(22, 22)
    chkOnlyRare:SetPoint("LEFT", chkOnlyNotTabled.text, "RIGHT", 10, 0)
    chkOnlyRare.text = chkOnlyRare:CreateFontString(nil, "OVERLAY")
    chkOnlyRare.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    chkOnlyRare.text:SetPoint("LEFT", chkOnlyRare, "RIGHT", 2, 0)
    chkOnlyRare.text:SetText(BG.STC_b1("精良/史诗"))
    chkOnlyRare:SetChecked(false)
    chkOnlyRare:SetScript("OnClick", function(self)
        LH.RefreshList()
        BG.PlaySound(1)
    end)
    f.chkOnlyRare = chkOnlyRare

    -- 操作按钮：通报未记入
    local btnReport = BG.CreateButton(f)
    btnReport:SetSize(78, 22)
    btnReport:SetPoint("LEFT", chkOnlyRare.text, "RIGHT", 10, 0)
    btnReport:SetText("通报未记")
    btnReport:SetScript("OnClick", function()
        LH.ReportUnTabledItems()
        BG.PlaySound(1)
    end)
    f.btnReport = btnReport

    -- 操作按钮：清空记录
    local btnClear = BG.CreateButton(f)
    btnClear:SetSize(72, 22)
    btnClear:SetPoint("LEFT", btnReport, "RIGHT", 6, 0)
    btnClear:SetText("清空本场")
    btnClear:SetScript("OnClick", function()
        StaticPopupDialogs["BGLITE_CLEAR_LOOT_HISTORY"] = {
            text = BG.STC_r1("确定要清空当前副本的所有掉落拾取流水记录吗？"),
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                local fb = BG.FB1 or "TOC"
                if BiaoGe and BiaoGe[fb] then
                    BiaoGe[fb].lootHistory = {}
                end
                LH.RefreshList()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("BGLITE_CLEAR_LOOT_HISTORY")
        BG.PlaySound(1)
    end)
    f.btnClear = btnClear

    ---------------------------------------------------------------------------
    -- 表头标题栏
    ---------------------------------------------------------------------------
    local headerFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    headerFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -68)
    headerFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -68)
    headerFrame:SetHeight(24)
    headerFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    headerFrame:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    headerFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    f.headerFrame = headerFrame

    local COLUMNS = {
        { name = "序号", width = 45, justify = "CENTER" },
        { name = "拾取时间", width = 75, justify = "CENTER" },
        { name = "来源/区域", width = 120, justify = "LEFT" },
        { name = "拾取人", width = 110, justify = "LEFT" },
        { name = "掉落物品", width = 280, justify = "LEFT" },
        { name = "数量", width = 50, justify = "CENTER" },
        { name = "金团账本状态", width = 190, justify = "LEFT" },
    }

    local curX = 6
    for i, col in ipairs(COLUMNS) do
        local hText = headerFrame:CreateFontString(nil, "OVERLAY")
        hText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        hText:SetPoint("LEFT", headerFrame, "LEFT", curX, 0)
        hText:SetWidth(col.width)
        hText:SetJustifyH(col.justify)
        hText:SetText(BG.STC_w1(col.name))
        curX = curX + col.width + 6
    end

    ---------------------------------------------------------------------------
    -- 列表滚动容器
    ---------------------------------------------------------------------------
    local contentFrame = CreateFrame("Frame", "BGLite_LootHistoryContentFrame", f)
    contentFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
    contentFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -55, 35)
    f.contentFrame = contentFrame

    -- 防御原生模板 UIPanelScrollBarTemplate 默认调用 parent:SetVerticalScroll
    f.SetVerticalScroll = function(self, value) end

    -- 原生自建滚动条 (彻底避免 FauxScrollFrameTemplate 自动 Hide 导致整表消失的缺陷)
    local scrollBar = CreateFrame("Slider", "BGLite_LootHistoryScrollBar", f, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT", contentFrame, "TOPRIGHT", 6, -16)
    scrollBar:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMRIGHT", 6, 16)
    scrollBar:SetWidth(16)
    f.scrollBar = scrollBar

    f.OnScrollBarValueChanged = function(self, value)
        LH.RefreshScrollView()
    end
    -- 关键修复：必须在 SetValue 之前绑定 OnValueChanged，彻底覆盖模板自带的 parent:SetVerticalScroll 回调
    scrollBar:SetScript("OnValueChanged", function(self, value)
        f:OnScrollBarValueChanged(value)
    end)

    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    scrollBar:SetValueStep(1)
    scrollBar.scrollStep = 1
    scrollBar:SetObeyStepOnDrag(true)

    local function OnMouseWheel(self, delta)
        local cur = scrollBar:GetValue() or 0
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        if delta > 0 then
            scrollBar:SetValue(math.max(minVal, cur - 3))
        else
            scrollBar:SetValue(math.min(maxVal, cur + 3))
        end
    end
    contentFrame:EnableMouseWheel(true)
    contentFrame:SetScript("OnMouseWheel", OnMouseWheel)

    -- 动态计算可见行数
    function LH.UpdateVisibleRowCount()
        local h = contentFrame:GetHeight()
        if not h or h < 100 then
            VISIBLE_ROWS = 21
        else
            VISIBLE_ROWS = math.floor(h / ROW_HEIGHT)
        end
        local total = #LH.filteredList
        local maxScroll = math.max(0, total - VISIBLE_ROWS)
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetShown(maxScroll > 0)
    end

    contentFrame:SetScript("OnSizeChanged", function()
        LH.UpdateVisibleRowCount()
        LH.RefreshScrollView()
    end)

    -- 创建行控件池 (最多 35 行)
    for i = 1, 35 do
        local row = CreateFrame("Frame", nil, contentFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
        row:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
        if i == 1 then
            row:SetPoint("TOP", contentFrame, "TOP", 0, 0)
        else
            row:SetPoint("TOP", LH.rowFrames[i - 1], "BOTTOM", 0, 0)
        end
        row:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = nil,
        })
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", OnMouseWheel)

        -- 斑马纹交替底色
        if i % 2 == 1 then
            row:SetBackdropColor(0.15, 0.15, 0.15, 0.35)
        else
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.45)
        end

        -- 悬停高亮材质
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        local x = 6
        -- 序号
        local tIndex = row:CreateFontString(nil, "OVERLAY")
        tIndex:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        tIndex:SetPoint("LEFT", row, "LEFT", x, 0)
        tIndex:SetWidth(COLUMNS[1].width)
        tIndex:SetJustifyH("CENTER")
        tIndex:SetTextColor(0.6, 0.6, 0.6)
        row.tIndex = tIndex
        x = x + COLUMNS[1].width + 6

        -- 时间
        local tTime = row:CreateFontString(nil, "OVERLAY")
        tTime:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        tTime:SetPoint("LEFT", row, "LEFT", x, 0)
        tTime:SetWidth(COLUMNS[2].width)
        tTime:SetJustifyH("CENTER")
        tTime:SetTextColor(0.8, 0.8, 0.8)
        row.tTime = tTime
        x = x + COLUMNS[2].width + 6

        -- 来源
        local tSource = row:CreateFontString(nil, "OVERLAY")
        tSource:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        tSource:SetPoint("LEFT", row, "LEFT", x, 0)
        tSource:SetWidth(COLUMNS[3].width)
        tSource:SetJustifyH("LEFT")
        tSource:SetWordWrap(false)
        tSource:SetTextColor(0.85, 0.75, 0.35)
        row.tSource = tSource
        x = x + COLUMNS[3].width + 6

        -- 拾取人
        local tPlayer = row:CreateFontString(nil, "OVERLAY")
        tPlayer:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        tPlayer:SetPoint("LEFT", row, "LEFT", x, 0)
        tPlayer:SetWidth(COLUMNS[4].width)
        tPlayer:SetJustifyH("LEFT")
        tPlayer:SetWordWrap(false)
        row.tPlayer = tPlayer
        x = x + COLUMNS[4].width + 6

        -- 掉落物品按钮 (交互式按钮支持 GameTooltip, Shift点击插入, Ctrl点击试穿)
        local btnItem = CreateFrame("Button", nil, row)
        btnItem:SetPoint("LEFT", row, "LEFT", x, 0)
        btnItem:SetSize(COLUMNS[5].width, ROW_HEIGHT)
        btnItem:SetNormalFontObject(BG.FontGold15)
        local itemText = btnItem:CreateFontString(nil, "OVERLAY")
        itemText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        itemText:SetAllPoints()
        itemText:SetJustifyH("LEFT")
        itemText:SetWordWrap(false)
        btnItem:SetFontString(itemText)
        btnItem.text = itemText

        btnItem:SetScript("OnEnter", function(self)
            if self.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        btnItem:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        btnItem:SetScript("OnClick", function(self, button)
            if not self.link then return end
            if IsShiftKeyDown() then
                if BG.InsertLink then
                    BG.InsertLink(self.link)
                else
                    ChatEdit_InsertLink(self.link)
                end
            elseif IsControlKeyDown() then
                DressUpItemLink(self.link)
            end
        end)
        row.btnItem = btnItem
        x = x + COLUMNS[5].width + 6

        -- 数量
        local tCount = row:CreateFontString(nil, "OVERLAY")
        tCount:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        tCount:SetPoint("LEFT", row, "LEFT", x, 0)
        tCount:SetWidth(COLUMNS[6].width)
        tCount:SetJustifyH("CENTER")
        tCount:SetTextColor(1, 1, 1)
        row.tCount = tCount
        x = x + COLUMNS[6].width + 6

        -- 账本记账状态 (已记入 / 红色未记入)
        local tStatus = row:CreateFontString(nil, "OVERLAY")
        tStatus:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        tStatus:SetPoint("LEFT", row, "LEFT", x, 0)
        tStatus:SetWidth(COLUMNS[7].width)
        tStatus:SetJustifyH("LEFT")
        tStatus:SetWordWrap(false)
        row.tStatus = tStatus

        row:Hide()
        table.insert(LH.rowFrames, row)
    end

    -- 无记录居中提示
    local emptyText = f:CreateFontString(nil, "OVERLAY")
    emptyText:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
    emptyText:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
    emptyText:SetText(BG.STC_dis("本场副本暂无掉落拾取记录。在团队副本中击杀怪物或拾取装备时将在此实时呈现。"))
    emptyText:Hide()
    f.emptyText = emptyText

    -- Tab 显示生命周期
    f:SetScript("OnShow", function(self)
        if BG.FrameHide then BG.FrameHide(0) end
        if BG.FBMainFrame then BG.FBMainFrame:Hide() end
        if BG.ItemLibMainFrame then BG.ItemLibMainFrame:Hide() end
        if BG.HopeMainFrame then BG.HopeMainFrame:Hide() end
        if BG.DuiZhangMainFrame then BG.DuiZhangMainFrame:Hide() end
        if BG.TradeHistoryMainFrame then BG.TradeHistoryMainFrame:Hide() end
        if BG.AuctionPresetMainFrame then BG.AuctionPresetMainFrame:Hide() end
        if BG.TabButtonsFB then BG.TabButtonsFB:Hide() end

        LH.UpdateVisibleRowCount()
        LH.RefreshList()
        if BiaoGe then BiaoGe.lastFrame = "LootHistory" end
    end)

    -- 注册底部 Tab 按钮
    BG.LootHistoryMainFrameTabNum = BG.LootHistoryMainFrameTabNum or 107
    if BG.Create_TabButton and not BG.ButtonTabLootHistory then
        local tabBtn = BG.Create_TabButton(BG.LootHistoryMainFrameTabNum, L["掉落记录"] or "掉落记录", f, 90)
        BG.ButtonTabLootHistory = tabBtn
        LH.tabBtn = tabBtn
        if BG.OnEnterDelay then
            BG.OnEnterDelay(tabBtn, function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(L["< 掉落记录 >"] or "< 掉落记录 >", 1, 1, 1, true)
                GameTooltip:AddLine(L["团队副本所有掉落拾取流水记录，实时核对金团表格防漏少记。"] or "团队副本所有掉落拾取流水记录，实时核对金团表格防漏少记。", 1, 0.82, 0, true)
                GameTooltip:Show()
            end, 0.5, true)
        end
    end

    return f
end

-------------------------------------------------------------------------------
-- 数据过滤与列表更新
-------------------------------------------------------------------------------
function LH.RefreshList()
    if not (LH.MainFrame and LH.MainFrame:IsShown()) then return end

    local fb = BG.FB1 or "TOC"
    local rawDB = LH.GetHistoryDB(fb)

    local query = LH.MainFrame.searchBox and LH.MainFrame.searchBox:GetText()
    query = query and query:trim():lower() or ""

    local onlyNotTabled = LH.MainFrame.chkOnlyNotTabled and LH.MainFrame.chkOnlyNotTabled:GetChecked()
    local onlyRare = LH.MainFrame.chkOnlyRare and LH.MainFrame.chkOnlyRare:GetChecked()

    LH.filteredList = {}
    local unTabledCount = 0

    for idx, item in ipairs(rawDB) do
        local isTabled, bossName = LH.CheckIsTabled(fb, item.itemID)
        item.isTabled = isTabled
        item.tabledBoss = bossName

        if not isTabled then
            unTabledCount = unTabledCount + 1
        end

        local matchQuery = true
        if query ~= "" then
            local pName = (item.player or ""):lower()
            local iLink = (item.link or ""):lower()
            if not (pName:find(query, 1, true) or iLink:find(query, 1, true)) then
                matchQuery = false
            end
        end

        local matchFilter = true
        if onlyNotTabled and isTabled then
            matchFilter = false
        end
        if onlyRare and (item.quality or 1) < 3 then
            matchFilter = false
        end

        if matchQuery and matchFilter then
            table.insert(LH.filteredList, item)
        end
    end

    -- 更新统计提示
    if LH.MainFrame.summaryText then
        local total = #rawDB
        if total == 0 then
            LH.MainFrame.summaryText:SetText(BG.STC_dis("暂无掉落数据"))
        else
            local statusPart = unTabledCount > 0
                and string.format("，其中 %s 件尚未记入表格", BG.STC_r1(tostring(unTabledCount)))
                or string.format("，%s", BG.STC_g1("全部装备均已入账"))
            LH.MainFrame.summaryText:SetText(string.format("共记录 %s 件掉落%s", BG.STC_y2(tostring(total)), statusPart))
        end
    end

    -- 无记录提示
    if LH.MainFrame.emptyText then
        LH.MainFrame.emptyText:SetShown(#LH.filteredList == 0)
    end

    LH.UpdateVisibleRowCount()
    LH.RefreshScrollView()
end

-- 滚动呈现渲染
function LH.RefreshScrollView()
    if not (LH.MainFrame and LH.MainFrame:IsShown()) then return end

    local total = #LH.filteredList
    local scrollOffset = math.floor(LH.MainFrame.scrollBar:GetValue() or 0)

    for i = 1, #LH.rowFrames do
        local row = LH.rowFrames[i]
        local dataIdx = scrollOffset + i

        if i <= VISIBLE_ROWS and dataIdx <= total then
            local data = LH.filteredList[dataIdx]
            row.tIndex:SetText(tostring(dataIdx))
            row.tTime:SetText(data.time or "--")
            row.tSource:SetText(data.source or "")

            -- 玩家名与职业着色
            local r, g, b = GetClassRGB(data.class)
            row.tPlayer:SetTextColor(r, g, b)
            row.tPlayer:SetText(data.player or "未知")

            -- 物品与图标
            local iconStr = data.texture and AddTexture(data.texture, 16) or ""
            row.btnItem.link = data.link
            row.btnItem.text:SetText(iconStr .. (data.link or "未知物品"))

            -- 数量
            if (data.count or 1) > 1 then
                row.tCount:SetText(BG.STC_y2("x" .. tostring(data.count)))
            else
                row.tCount:SetText("1")
            end

            -- 账本状态 (已记入 / 红色未记入)
            if data.isTabled then
                local bName = data.tabledBoss and (" (" .. data.tabledBoss .. ")") or ""
                row.tStatus:SetText(BG.STC_g1("已记入表格" .. bName))
            else
                row.tStatus:SetText(BG.STC_r1("未记入表格"))
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

-- 通报未记入的装备到团队
function LH.ReportUnTabledItems()
    local fb = BG.FB1 or "TOC"
    local rawDB = LH.GetHistoryDB(fb)

    local unTabledList = {}
    for _, item in ipairs(rawDB) do
        local isTabled = LH.CheckIsTabled(fb, item.itemID)
        if not isTabled and (item.quality or 1) >= 3 then
            table.insert(unTabledList, item)
        end
    end

    if #unTabledList == 0 then
        SendSystemMessage(BG.BG .. BG.STC_g1("【掉落核对】恭喜！当前副本所有精良及以上掉落均已完整记入金团表格！"))
        return
    end

    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if not channel then
        SendSystemMessage(BG.BG .. BG.STC_y2(string.format("【掉落核对】当前有 %d 件装备未记入金团表格：", #unTabledList)))
        for i, item in ipairs(unTabledList) do
            if i > 8 then
                SendSystemMessage(BG.BG .. "... (更多省略)")
                break
            end
            SendSystemMessage(string.format("[%s] 拾取人: %s -> %s", item.time, item.player, item.link))
        end
        return
    end

    SendChatMessage(string.format("=== 【BiaoGe 掉落核对】发现 %d 件掉落尚未记入账本 ===", #unTabledList), channel)
    for i, item in ipairs(unTabledList) do
        if i > 10 then
            SendChatMessage("... (篇幅受限，请打开表格【掉落记录】Tab 查看全量流水)", channel)
            break
        end
        SendChatMessage(string.format("%d. [%s] 拾取人:%s -> %s", i, item.time, item.player, item.link), channel)
    end
end

-------------------------------------------------------------------------------
-- 监听器初始化
-------------------------------------------------------------------------------
local lootEventFrame = CreateFrame("Frame")
lootEventFrame:RegisterEvent("CHAT_MSG_LOOT")
lootEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
lootEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
lootEventFrame:SetScript("OnEvent", function(self, event, msg, ...)
    if event == "CHAT_MSG_LOOT" then
        -- 仅在团队或小队中记录
        if not (IsInRaid() or IsInGroup()) then return end
        local p, l, c = ParseLootMessage(msg)
        if p and l then
            OnLootCaptured(p, l, c)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 记录进战斗目标名称
        if UnitExists("target") and not UnitIsPlayer("target") then
            BG.lastCombatBossName = UnitName("target")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(10, function()
            if not InCombatLockdown() then
                BG.lastCombatBossName = nil
            end
        end)
    end
end)

function ns.InitLootHistoryModule()
    if not (BG and BG.MainFrame) then return end
    LH.CreateMainFrame(BG.MainFrame)
end
