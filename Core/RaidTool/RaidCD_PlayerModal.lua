if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidCD = ns.RaidCD or {}
ns.RaidCD = RaidCD
_G.RaidCD = RaidCD

local function CleanPlayerName(name)
    if not name then return "" end
    return (name:gsub("%-.+", ""))
end

local function IsPlayerInCurrentGroup(name)
    if RaidCD.IsPlayerInCurrentGroup then
        return RaidCD.IsPlayerInCurrentGroup(name)
    end
    if not name or name == "" then return false end
    local clean = CleanPlayerName(name)
    local pName = CleanPlayerName(UnitName("player") or "")
    if clean == pName then return true end
    if IsInRaid and IsInRaid() then
        local count = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers()) or 40
        for i = 1, count do
            local rName = GetRaidRosterInfo(i) or UnitName("raid" .. i)
            if rName and CleanPlayerName(rName) == clean then return true end
        end
        return false
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local partName = UnitName("party" .. i)
            if partName and CleanPlayerName(partName) == clean then return true end
        end
        return false
    end
    return clean == pName
end

--------------------------------------------------------------------------------
-- 6.5 人员选择与排序调整配置弹窗 (跟随团队工具 8 小队网格排布)
--------------------------------------------------------------------------------
local playerModal = nil
local activeModalTab = "select" -- "select" or "sort"

-- 获取团队 40 人网格槽位信息 (与外部团队工具 1~8 队槽位完全同步)
function RaidCD.GetRoster40Slots()
    if RaidTool and RaidTool.SyncCurrentRaidRoster then
        pcall(function() RaidTool.SyncCurrentRaidRoster(false) end)
    end

    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
    local slots = {}
    local rosterList = (ns.RaidTool and ns.RaidTool.currentRosterList) or (RaidTool and RaidTool.currentRosterList) or {}
    local rosterClasses = (ns.RaidTool and ns.RaidTool.currentRosterClasses) or (RaidTool and RaidTool.currentRosterClasses) or {}

    local hasAny = false
    for i = 1, 40 do
        local rawName = rosterList[i]
        if rawName and rawName ~= "" then
            local clean = CleanPlayerName(rawName)
            if not inGroup or IsPlayerInCurrentGroup(clean) then
                hasAny = true
                break
            end
        end
    end

    if hasAny then
        for i = 1, 40 do
            local rawName = rosterList[i]
            local name = rawName and rawName ~= "" and CleanPlayerName(rawName) or nil
            if inGroup and name and not IsPlayerInCurrentGroup(name) then
                name = nil -- 已退组，权威置空！
            end
            local class = name and (rosterClasses[i] or RaidCD.GetPlayerClass(name)) or nil
            slots[i] = {
                name = name,
                class = class,
                isMonitored = name and RaidCD.IsPlayerMonitored(name, class) or false,
            }
        end
        return slots
    end

    -- 回退：从真实在线单位扫描小队/团队
    local isRaid = IsInRaid and IsInRaid()
    if isRaid then
        local groupCounts = {}
        for g = 1, 8 do groupCounts[g] = 0 end
        local num = (GetNumGroupMembers and GetNumGroupMembers() > 0 and GetNumGroupMembers())
            or (GetNumRaidMembers and GetNumRaidMembers() > 0 and GetNumRaidMembers())
            or 40
        for i = 1, num do
            local rName, _, subgroup = GetRaidRosterInfo(i)
            rName = rName or UnitName("raid" .. i)
            if rName and rName ~= "" then
                subgroup = (subgroup and subgroup >= 1 and subgroup <= 8) and subgroup or 1
                groupCounts[subgroup] = groupCounts[subgroup] + 1
                local pos = groupCounts[subgroup]
                if pos <= 5 then
                    local idx = (subgroup - 1) * 5 + pos
                    local clean = CleanPlayerName(rName)
                    local class = select(2, UnitClass("raid" .. i)) or select(2, UnitClass(rName))
                    slots[idx] = {
                        name = clean,
                        class = class,
                        isMonitored = RaidCD.IsPlayerMonitored(clean, class),
                    }
                end
            end
        end
    else
        local pName = UnitName("player")
        if pName then
            local clean = CleanPlayerName(pName)
            local class = select(2, UnitClass("player"))
            slots[1] = {
                name = clean,
                class = class,
                isMonitored = RaidCD.IsPlayerMonitored(clean, class),
            }
        end
        for i = 1, 4 do
            local partName = UnitName("party" .. i)
            if partName then
                local clean = CleanPlayerName(partName)
                local class = select(2, UnitClass("party" .. i))
                slots[1 + i] = {
                    name = clean,
                    class = class,
                    isMonitored = RaidCD.IsPlayerMonitored(clean, class),
                }
            end
        end
    end

    for i = 1, 40 do
        if not slots[i] then
            slots[i] = { name = nil, class = nil, isMonitored = false }
        end
    end

    return slots
end

function RaidCD.TogglePlayerSelectModal(targetTab)
    if playerModal and playerModal:IsShown() then
        if not targetTab or targetTab == activeModalTab then
            playerModal:Hide()
            return
        end
    end

    if targetTab then
        activeModalTab = targetTab
    end

    if not playerModal then
        local f = CreateFrame("Frame", "BG_RaidCDPlayerModal", UIParent, "BackdropTemplate")
        f:SetSize(684, 492)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
        f:SetBackdropBorderColor(0.2, 0.7, 1, 0.9)

        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("|TInterface\\AddOns\\BGLite_Plus\\Media\\shield:16:16:0:0|t " .. BG.STC_g1("团队减伤监控 - 人员选择与排序"))

        local subTip = f:CreateFontString(nil, "OVERLAY")
        subTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        subTip:SetPoint("TOPLEFT", 16, -32)
        subTip:SetText(BG.STC_dis("与外部团队工具 8 个小队网格完全同步。勾选开启技能监控，或在排序页自由调整次序"))

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- 选项卡按钮
        local tabSelect = BG.CreateButton(f)
        tabSelect:SetSize(140, 24)
        tabSelect:SetPoint("TOPLEFT", 16, -56)
        tabSelect:SetText("人员选择 (队伍排列)")

        local tabSort = BG.CreateButton(f)
        tabSort:SetSize(140, 24)
        tabSort:SetPoint("LEFT", tabSelect, "RIGHT", 6, 0)
        tabSort:SetText("调整排序 (顺序排布)")

        f.tabSelect = tabSelect
        f.tabSort = tabSort

        -- 内容容器
        local selectContainer = CreateFrame("Frame", nil, f)
        selectContainer:SetPoint("TOPLEFT", 16, -88)
        selectContainer:SetPoint("BOTTOMRIGHT", -16, 38)
        f.selectContainer = selectContainer

        local sortContainer = CreateFrame("Frame", nil, f)
        sortContainer:SetPoint("TOPLEFT", 16, -88)
        sortContainer:SetPoint("BOTTOMRIGHT", -16, 38)
        f.sortContainer = sortContainer

        local function SwitchTab(tab)
            activeModalTab = tab
            if tab == "select" then
                selectContainer:Show()
                sortContainer:Hide()
                tabSelect:SetText(BG.STC_g1("人员选择 (队伍排列)"))
                tabSort:SetText("调整排序 (顺序排布)")
            else
                selectContainer:Hide()
                sortContainer:Show()
                tabSelect:SetText("人员选择 (队伍排列)")
                tabSort:SetText(BG.STC_g1("调整排序 (顺序排布)"))
            end
            RaidCD.RefreshPlayerModalUI()
        end
        f.SwitchTab = SwitchTab

        tabSelect:SetScript("OnClick", function() SwitchTab("select") BG.PlaySound(1) end)
        tabSort:SetScript("OnClick", function() SwitchTab("sort") BG.PlaySound(1) end)

        -------------------------------------------------------------
        -- Tab 1: 人员选择 (跟随团队工具 8 个小队网格排列: 4列 x 2行)
        -------------------------------------------------------------
        local btnAllOn = BG.CreateButton(selectContainer)
        btnAllOn:SetSize(72, 22)
        btnAllOn:SetPoint("TOPLEFT", 0, 0)
        btnAllOn:SetText("全部开启")
        btnAllOn:SetScript("OnClick", function()
            local slots = RaidCD.GetRoster40Slots()
            for _, s in ipairs(slots) do
                if s.name and s.name ~= "" then
                    RaidCD.SetPlayerMonitored(s.name, true)
                end
            end
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)

        local btnAllOff = BG.CreateButton(selectContainer)
        btnAllOff:SetSize(72, 22)
        btnAllOff:SetPoint("LEFT", btnAllOn, "RIGHT", 5, 0)
        btnAllOff:SetText("全部关闭")
        btnAllOff:SetScript("OnClick", function()
            local slots = RaidCD.GetRoster40Slots()
            for _, s in ipairs(slots) do
                if s.name and s.name ~= "" then
                    RaidCD.SetPlayerMonitored(s.name, false)
                end
            end
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)

        local btnTankHeal = BG.CreateButton(selectContainer)
        btnTankHeal:SetSize(95, 22)
        btnTankHeal:SetPoint("LEFT", btnAllOff, "RIGHT", 5, 0)
        btnTankHeal:SetText("仅坦/疗/减伤")
        btnTankHeal:SetScript("OnClick", function()
            local slots = RaidCD.GetRoster40Slots()
            for _, s in ipairs(slots) do
                if s.name and s.name ~= "" then
                    local isCore = DEFAULT_MONITORED_CLASSES[s.class]
                    RaidCD.SetPlayerMonitored(s.name, isCore and true or false)
                end
            end
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)

        local btnResetPeople = BG.CreateButton(selectContainer)
        btnResetPeople:SetSize(80, 22)
        btnResetPeople:SetPoint("LEFT", btnTankHeal, "RIGHT", 5, 0)
        btnResetPeople:SetText("恢复默认")
        btnResetPeople:SetScript("OnClick", function()
            RaidCD.ResetAllPlayersToDefault()
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)

        local btnSync = BG.CreateButton(selectContainer)
        btnSync:SetSize(80, 22)
        btnSync:SetPoint("LEFT", btnResetPeople, "RIGHT", 5, 0)
        btnSync:SetText("同步队伍")
        btnSync:SetScript("OnClick", function()
            if RaidTool and RaidTool.SyncCurrentRaidRoster then
                RaidTool.SyncCurrentRaidRoster(false)
            end
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)

        local selectTip = selectContainer:CreateFontString(nil, "OVERLAY")
        selectTip:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
        selectTip:SetPoint("LEFT", btnSync, "RIGHT", 8, 0)
        selectTip:SetText(BG.STC_dis("提示：直接点击条目或勾选框即可切换监控"))

        -- 8 个小队框架容器 (4列 x 2行，完全契合团队工具)
        local NUM_GROUPS = 8
        local MEMBERS_PER_GROUP = 5
        local groupWidth = 158
        local groupHeight = 138

        f.groupFrames = {}
        f.slotButtons = {}

        for grp = 1, NUM_GROUPS do
            local col = (grp - 1) % 4
            local row = math.floor((grp - 1) / 4)
            local gX = col * (groupWidth + 6)
            local gY = -28 - row * (groupHeight + 8)

            local gBox = CreateFrame("Frame", nil, selectContainer, "BackdropTemplate")
            gBox:SetSize(groupWidth, groupHeight)
            gBox:SetPoint("TOPLEFT", gX, gY)
            gBox:SetBackdrop({
                bgFile = "Interface/ChatFrame/ChatFrameBackground",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            gBox:SetBackdropColor(0.08, 0.08, 0.08, 0.65)
            gBox:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
            f.groupFrames[grp] = gBox

            local gTitle = gBox:CreateFontString(nil, "OVERLAY")
            gTitle:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
            gTitle:SetPoint("TOPLEFT", 6, -3)
            if grp == 1 then
                gTitle:SetText(BG.STC_y1("第 1 小队 (坦克组)"))
            else
                gTitle:SetText(BG.STC_y1(format("第 %d 小队", grp)))
            end
            gBox.title = gTitle

            for pos = 1, MEMBERS_PER_GROUP do
                local slotIdx = (grp - 1) * MEMBERS_PER_GROUP + pos
                local btn = CreateFrame("Button", nil, gBox, "BackdropTemplate")
                btn:SetSize(groupWidth - 8, 22)
                btn:SetPoint("TOPLEFT", 4, -18 - (pos - 1) * 23)
                btn:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/Buttons/WHITE8X8",
                    edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 },
                })
                btn.slotIndex = slotIdx

                local nameText = btn:CreateFontString(nil, "OVERLAY")
                nameText:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                nameText:SetPoint("LEFT", 4, 0)
                nameText:SetPoint("RIGHT", -22, 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                btn.nameText = nameText

                local cbMonitor = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
                cbMonitor:SetSize(16, 16)
                cbMonitor:SetPoint("RIGHT", -2, 0)
                btn.cbMonitor = cbMonitor

                cbMonitor:SetScript("OnClick", function(self)
                    if btn.pName and btn.pName ~= "" then
                        RaidCD.SetPlayerMonitored(btn.pName, self:GetChecked())
                        RaidCD.RefreshPlayerModalUI()
                    end
                end)

                btn:SetScript("OnClick", function(self)
                    if btn.pName and btn.pName ~= "" then
                        local newState = not btn.cbMonitor:GetChecked()
                        btn.cbMonitor:SetChecked(newState)
                        RaidCD.SetPlayerMonitored(btn.pName, newState)
                        RaidCD.RefreshPlayerModalUI()
                        BG.PlaySound(1)
                    end
                end)

                btn:SetScript("OnEnter", function(self)
                    if not btn.pName or btn.pName == "" then return end
                    self:SetBackdropBorderColor(1, 0.8, 0, 1)

                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    local cCode = "|cffffffff"
                    if btn.pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[btn.pClass] then
                        cCode = RAID_CLASS_COLORS[btn.pClass].colorStr and ("|c" .. RAID_CLASS_COLORS[btn.pClass].colorStr) or cCode
                    end
                    local subStr = format("[第 %d 队]", grp)
                    local classLabel = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[btn.pClass]) or btn.pClass or ""
                    GameTooltip:AddDoubleLine(cCode .. btn.pName .. "|r", BG.STC_w1(subStr))
                    GameTooltip:AddLine(BG.STC_dis("职业: ") .. cCode .. classLabel .. "|r")

                    -- 列出该玩家可用的受监控大招
                    local tracked = {}
                    for _, def in ipairs(RaidCD.SPELLS) do
                        if (not btn.pClass or def.class == btn.pClass) and RaidCD.IsSpellFactionMatch(def.id) and RaidCD.IsSpellEnabled(def.id) then
                            table.insert(tracked, def.name)
                        end
                    end
                    if #tracked > 0 then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(BG.STC_g1("已配置监控技能："), 1, 1, 1)
                        for _, sName in ipairs(tracked) do
                            GameTooltip:AddLine("  • " .. sName, 0.9, 0.9, 0.9)
                        end
                    end

                    local isMon = RaidCD.IsPlayerMonitored(btn.pName, btn.pClass)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(isMon and "|cff00ff00当前正在监控此队员|r (点击可关闭)" or "|cffff5555当前未监控此队员|r (点击可开启)", 0.8, 0.8, 0.8)
                    GameTooltip:Show()
                end)

                btn:SetScript("OnLeave", function(self)
                    if btn.pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[btn.pClass] then
                        self:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)
                    else
                        self:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.4)
                    end
                    GameTooltip_Hide()
                end)

                f.slotButtons[slotIdx] = btn
            end
        end

        -------------------------------------------------------------
        -- Tab 2: 调整排序
        -------------------------------------------------------------
        local sortTip = sortContainer:CreateFontString(nil, "OVERLAY")
        sortTip:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
        sortTip:SetPoint("TOPLEFT", 0, 4)
        sortTip:SetText("排序规则：")

        local modes = {
            { key = "subgroup", text = "小队顺序 (1~8队，默认)" },
            { key = "class",    text = "职业分类 (战/骑/DK/德/牧/萨)" },
            { key = "ready",    text = "就绪优先 (可用大招置顶)" },
            { key = "custom",   text = "自定义手动排序" },
        }
        f.sortRadioButtons = {}
        local lastRadio = sortTip
        for i, m in ipairs(modes) do
            local rb = CreateFrame("CheckButton", nil, sortContainer, "UIRadioButtonTemplate")
            rb:SetSize(16, 16)
            if i == 1 then
                rb:SetPoint("LEFT", sortTip, "RIGHT", 4, 0)
            else
                rb:SetPoint("LEFT", lastRadio.text, "RIGHT", 10, 0)
            end
            rb.text = rb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            rb.text:SetPoint("LEFT", rb, "RIGHT", 2, 0)
            rb.text:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
            rb.text:SetText(m.text)
            rb.sortKey = m.key

            rb:SetScript("OnClick", function()
                local db = BiaoGe and BiaoGe.RaidCD
                if db then
                    db.sortMode = m.key
                end
                RaidCD.UpdateHUD()
                RaidCD.RefreshPlayerModalUI()
                BG.PlaySound(1)
            end)
            table.insert(f.sortRadioButtons, rb)
            lastRadio = rb
        end

        local sortScroll = CreateFrame("ScrollFrame", "BG_RaidCDSortScroll", sortContainer, "UIPanelScrollFrameTemplate")
        sortScroll:SetPoint("TOPLEFT", 0, -28)
        sortScroll:SetPoint("BOTTOMRIGHT", -22, 0)
        local sortChild = CreateFrame("Frame", nil, sortScroll)
        sortChild:SetSize(620, 10)
        sortScroll:SetScrollChild(sortChild)
        f.sortChild = sortChild
        f.sortRows = {}

        local emptySortTip = sortContainer:CreateFontString(nil, "OVERLAY")
        emptySortTip:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        emptySortTip:SetPoint("CENTER", sortContainer, "CENTER", 0, 0)
        emptySortTip:SetText(BG.STC_dis("当前暂无正在监控的队员。请在【人员选择】中勾选需要监控的队员。"))
        f.emptySortTip = emptySortTip

        -- 底部通用按钮
        local btnClose = BG.CreateButton(f)
        btnClose:SetSize(76, 24)
        btnClose:SetPoint("BOTTOMRIGHT", -16, 10)
        btnClose:SetText("关闭")
        btnClose:SetScript("OnClick", function() f:Hide() end)

        local btnResetSortOrder = BG.CreateButton(f)
        btnResetSortOrder:SetSize(140, 24)
        btnResetSortOrder:SetPoint("RIGHT", btnClose, "LEFT", -8, 0)
        btnResetSortOrder:SetText("恢复小队默认排序")
        btnResetSortOrder:SetScript("OnClick", function()
            local db = BiaoGe and BiaoGe.RaidCD
            if db then
                db.sortMode = "subgroup"
                if db.customPlayerOrder then wipe(db.customPlayerOrder) end
            end
            RaidCD.UpdateHUD()
            RaidCD.RefreshPlayerModalUI()
            BG.PlaySound(1)
        end)
        f.btnResetSortOrder = btnResetSortOrder

        playerModal = f
        RaidCD.playerModal = playerModal
    end

    playerModal.SwitchTab(activeModalTab or "select")
    playerModal:Show()
end

function RaidCD.RefreshPlayerModalUI()
    if not playerModal or not playerModal:IsShown() then return end

    if activeModalTab == "select" then
        -- 刷新 8 个小队 40 个槽位 (完全跟随团队工具)
        local slots = RaidCD.GetRoster40Slots()
        local groupCounts = {}
        for g = 1, 8 do groupCounts[g] = 0 end

        for slotIdx = 1, 40 do
            local btn = playerModal.slotButtons[slotIdx]
            if btn then
                local data = slots[slotIdx]
                local name = data and data.name
                local class = data and data.class
                btn.pName = name
                btn.pClass = class

                local grp = math.floor((slotIdx - 1) / 5) + 1
                if name and name ~= "" then
                    groupCounts[grp] = groupCounts[grp] + 1
                    local r, g, b = 1, 1, 1
                    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
                        r = RAID_CLASS_COLORS[class].r
                        g = RAID_CLASS_COLORS[class].g
                        b = RAID_CLASS_COLORS[class].b
                    end
                    btn.nameText:SetText(name)
                    btn.nameText:SetTextColor(r, g, b)
                    btn:SetBackdropColor(r * 0.25, g * 0.25, b * 0.25, 0.85)
                    btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.7)

                    local isMon = RaidCD.IsPlayerMonitored(name, class)
                    btn.cbMonitor:SetChecked(isMon)
                    btn.cbMonitor:Show()
                else
                    btn.nameText:SetText("")
                    btn:SetBackdropColor(0.04, 0.04, 0.04, 0.4)
                    btn:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.3)
                    btn.cbMonitor:Hide()
                end
            end
        end

        -- 根据小队是否有成员更新小队透明度 (第 1 队常亮，其余队伍有成员时亮，无成员时半透明)
        for grp = 1, 8 do
            local gBox = playerModal.groupFrames[grp]
            if gBox then
                if grp == 1 or groupCounts[grp] > 0 then
                    gBox:SetAlpha(1.0)
                else
                    gBox:SetAlpha(0.35)
                end
            end
        end

    else
        -- 刷新排序调整列表 (Tab 2)
        local db = BiaoGe and BiaoGe.RaidCD
        local curMode = (db and db.sortMode) or "subgroup"
        for _, rb in ipairs(playerModal.sortRadioButtons) do
            rb:SetChecked(rb.sortKey == curMode)
        end

        local currentList = RaidCD.GetMonitoredRosterCooldowns()
        if #currentList == 0 then
            playerModal.emptySortTip:Show()
        else
            playerModal.emptySortTip:Hide()
        end

        for _, row in ipairs(playerModal.sortRows) do
            row:Hide()
        end

        for i, p in ipairs(currentList) do
            local row = playerModal.sortRows[i]
            if not row then
                row = CreateFrame("Frame", nil, playerModal.sortChild, "BackdropTemplate")
                row:SetSize(600, 26)
                row:SetBackdrop({
                    bgFile = "Interface/ChatFrame/ChatFrameBackground",
                    edgeFile = "Interface/Buttons/WHITE8X8",
                    edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 },
                })
                row:SetBackdropColor(0.12, 0.12, 0.12, 0.7)
                row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)

                local numText = row:CreateFontString(nil, "OVERLAY")
                numText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                numText:SetPoint("LEFT", 8, 0)
                numText:SetWidth(32)
                numText:SetJustifyH("LEFT")
                row.numText = numText

                local nameText = row:CreateFontString(nil, "OVERLAY")
                nameText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                nameText:SetPoint("LEFT", numText, "RIGHT", 4, 0)
                nameText:SetWidth(150)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                row.nameText = nameText

                local spellIcons = {}
                for sIdx = 1, 6 do
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(18, 18)
                    icon:SetPoint("LEFT", nameText, "RIGHT", (sIdx - 1) * 22 + 8, 0)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    table.insert(spellIcons, icon)
                end
                row.spellIcons = spellIcons

                local btnTop = BG.CreateButton(row)
                btnTop:SetSize(42, 20)
                btnTop:SetPoint("RIGHT", -92, 0)
                btnTop:SetText("置顶")
                row.btnTop = btnTop

                local btnUp = BG.CreateButton(row)
                btnUp:SetSize(38, 20)
                btnUp:SetPoint("LEFT", btnTop, "RIGHT", 4, 0)
                btnUp:SetText("▲")
                row.btnUp = btnUp

                local btnDown = BG.CreateButton(row)
                btnDown:SetSize(38, 20)
                btnDown:SetPoint("LEFT", btnUp, "RIGHT", 4, 0)
                btnDown:SetText("▼")
                row.btnDown = btnDown

                playerModal.sortRows[i] = row
            end

            row:SetPoint("TOPLEFT", playerModal.sortChild, "TOPLEFT", 4, -(i - 1) * 28)

            local numStr = (i <= 3) and format("|cffffd100#%d|r", i) or format("#%d", i)
            row.numText:SetText(numStr)

            local r, g, b = 1, 1, 1
            if RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class] then
                r = RAID_CLASS_COLORS[p.class].r
                g = RAID_CLASS_COLORS[p.class].g
                b = RAID_CLASS_COLORS[p.class].b
            end
            local classCode = RGB(r, g, b) or "|cffffffff"
            local subNum = math.floor((p.sortOrder or 100) / 100)
            if subNum < 1 or subNum > 8 then subNum = 1 end
            row.nameText:SetText(format("|cffaaaaaa[%d队]|r %s%s|r", subNum, classCode, p.name))

            for sIdx, icon in ipairs(row.spellIcons) do
                local sData = p.spells and p.spells[sIdx]
                if sData and sData.def and sData.def.icon then
                    icon:SetTexture(sData.def.icon)
                    icon:Show()
                else
                    icon:Hide()
                end
            end

            row.btnTop:SetScript("OnClick", function()
                RaidCD.MovePlayerCustomOrder(p.name, "top")
                BG.PlaySound(1)
            end)
            row.btnUp:SetScript("OnClick", function()
                RaidCD.MovePlayerCustomOrder(p.name, "up")
                BG.PlaySound(1)
            end)
            row.btnDown:SetScript("OnClick", function()
                RaidCD.MovePlayerCustomOrder(p.name, "down")
                BG.PlaySound(1)
            end)

            row:Show()
        end

        playerModal.sortChild:SetHeight(math.max(150, #currentList * 28 + 20))
    end
end
