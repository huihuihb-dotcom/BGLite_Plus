if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG
local RGB = ns.RGB
local SetClassCFF = ns.SetClassCFF
local GetClassRGB = ns.GetClassRGB

local RaidComp = ns.RaidComp or _G.RaidComp
if not RaidComp then return end

local RaidCompUI = {}
ns.RaidCompUI = RaidCompUI
_G.RaidCompUI = RaidCompUI

local selectedChannel = "RAID"

-- 怀旧服安全职业颜色转换辅助函数 (替代原生缺少的 GetClassColor)
local function GetClassColorHex(class)
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        if c.colorStr then
            return string.sub(c.colorStr, 3) -- 去除前置alpha
        end
        return string.format("%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
    end
    return "ffffff"
end

--------------------------------------------------------------------------------
-- 1. 团队工具底部常驻概览条 (Bottom Bar)
--------------------------------------------------------------------------------
function RaidCompUI.CreateBottomBar(parent)
    if RaidCompUI.bottomBar then return RaidCompUI.bottomBar end

    local bar = CreateFrame("Frame", "BG_RaidCompBottomBar", parent, "BackdropTemplate")
    bar:SetSize(965, 74)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -508)
    bar:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bar:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    bar:SetBackdropBorderColor(0.2, 0.65, 0.95, 0.9)
    bar:EnableMouse(true)
    RaidCompUI.bottomBar = bar

    -- 左分区：阵容与专精人数
    local titleLeft = bar:CreateFontString(nil, "OVERLAY")
    titleLeft:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    titleLeft:SetPoint("TOPLEFT", 14, -8)
    titleLeft:SetText(BG.STC_g1("【团队阵容与专精分析】"))

    local textRoster = bar:CreateFontString(nil, "OVERLAY")
    textRoster:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    textRoster:SetPoint("TOPLEFT", 14, -28)
    textRoster:SetText("成员: 0人 (坦:0 奶:0 近战:0 远程:0)")
    bar.textRoster = textRoster

    local textScan = bar:CreateFontString(nil, "OVERLAY")
    textScan:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    textScan:SetPoint("TOPLEFT", 14, -48)
    textScan:SetText(BG.STC_dis("已识别专精: 0/0"))
    bar.textScan = textScan

    local btnScan = BG.CreateButton(bar)
    btnScan:SetSize(76, 20)
    btnScan:SetPoint("LEFT", textScan, "RIGHT", 6, 0)
    btnScan:SetText("重新扫描")
    btnScan:SetScript("OnClick", function()
        RaidComp.StartScan(true)
        BG.PlaySound(1)
    end)
    btnScan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("重新全团天赋扫描", 1, 1, 1)
        GameTooltip:AddLine("清空缓存，重新逐一读取全团成员的天赋树以判定最新专精。", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btnScan:SetScript("OnLeave", GameTooltip_Hide)

    -- 分隔竖线 1
    local sep1 = bar:CreateLine()
    sep1:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    sep1:SetStartPoint("TOPLEFT", 325, -6)
    sep1:SetEndPoint("BOTTOMLEFT", 325, 6)
    sep1:SetThickness(1)

    -- 中分区：Buff覆盖率与缺口告警
    local titleMid = bar:CreateFontString(nil, "OVERLAY")
    titleMid:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    titleMid:SetPoint("TOPLEFT", 340, -8)
    titleMid:SetText(BG.STC_b1("全团核心增益 (Buff/Debuff)"))

    local textCoverage = bar:CreateFontString(nil, "OVERLAY")
    textCoverage:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    textCoverage:SetPoint("TOPLEFT", 340, -28)
    textCoverage:SetText("覆盖率: 0%")
    bar.textCoverage = textCoverage

    local textMissing = bar:CreateFontString(nil, "OVERLAY")
    textMissing:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    textMissing:SetPoint("TOPLEFT", 340, -48)
    textMissing:SetPoint("RIGHT", bar, "LEFT", 670, 0)
    textMissing:SetJustifyH("LEFT")
    textMissing:SetText(BG.STC_dis("正在检测团队增益缺口..."))
    bar.textMissing = textMissing

    -- 鼠标悬停中分区查看完整缺失清单
    local midHover = CreateFrame("Frame", nil, bar)
    midHover:SetPoint("TOPLEFT", 335, -4)
    midHover:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 675, 4)
    midHover:EnableMouse(true)
    midHover:SetScript("OnEnter", function(self)
        local diag = RaidComp.GetFullBuffDiagnostics()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(format(BG.STC_g1("全团 Buff/Debuff 覆盖详情 (共 %d 项)"), diag.totalBuffs))
        GameTooltip:AddLine(format("已覆盖: |cff00ff00%d|r 项  |  缺失: |cffff2020%d|r 项", diag.coveredCount, diag.missingCount))
        GameTooltip:AddLine(" ")
        if diag.missingCount > 0 then
            GameTooltip:AddLine(BG.STC_r1("[当前缺失核心增益 (急需补充)]:"))
            for _, m in ipairs(diag.missingList) do
                GameTooltip:AddDoubleLine("- " .. m.def.name, m.def.needSpec or "", 1, 0.3, 0.3, 1, 0.82, 0)
            end
        else
            GameTooltip:AddLine(BG.STC_g1("[全团齐备] 全团增益已 100% 齐备，团队战斗力拉满！"))
        end
        GameTooltip:Show()
    end)
    midHover:SetScript("OnLeave", GameTooltip_Hide)

    -- 分隔竖线 2
    local sep2 = bar:CreateLine()
    sep2:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    sep2:SetStartPoint("TOPLEFT", 685, -6)
    sep2:SetEndPoint("BOTTOMLEFT", 685, 6)
    sep2:SetThickness(1)

    -- 右分区：查看详细矩阵 + 通报到频道
    local btnShowMatrix = BG.CreateButton(bar)
    btnShowMatrix:SetSize(120, 26)
    btnShowMatrix:SetPoint("TOPLEFT", 700, -10)
    btnShowMatrix:SetText("全家福详细矩阵")
    btnShowMatrix:SetScript("OnClick", function()
        RaidCompUI.ToggleMatrixModal()
        BG.PlaySound(1)
    end)
    btnShowMatrix:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(BG.STC_g1("打开 Buff/Debuff 全家福大矩阵"), 1, 1, 1)
        GameTooltip:AddLine("以 25 人团大看板形式，直观查阅伤害、急速、暴击、法伤、破甲等 24 项增益的具体提供者与缺失项。", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnShowMatrix:SetScript("OnLeave", GameTooltip_Hide)

    -- 频道选择下拉按钮
    local dropLib = LibBG or {
        UIDropDownMenu_SetWidth = function(self, ...) if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(...) end end,
        UIDropDownMenu_Initialize = function(self, ...) if UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(...) end end,
        UIDropDownMenu_CreateInfo = function(self) return UIDropDownMenu_CreateInfo and UIDropDownMenu_CreateInfo() or {} end,
        UIDropDownMenu_AddButton = function(self, ...) if UIDropDownMenu_AddButton then UIDropDownMenu_AddButton(...) end end,
        UIDropDownMenu_SetSelectedValue = function(self, ...) if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(...) end end,
        UIDropDownMenu_SetText = function(self, ...) if UIDropDownMenu_SetText then UIDropDownMenu_SetText(...) end end,
    }

    local channelDropdown = CreateFrame("Button", "BG_RaidCompChannelDropdown", bar, "UIDropDownMenuTemplate")
    channelDropdown:SetPoint("TOPLEFT", 685, -38)
    dropLib:UIDropDownMenu_SetWidth(channelDropdown, 65)

    local function InitChannelMenu(self, level)
        local channels = {
            { text = "团队 (RAID)", val = "RAID" },
            { text = "团队警告 (RW)", val = "RAID_WARNING" },
            { text = "小队 (PARTY)", val = "PARTY" },
            { text = "公会 (GUILD)", val = "GUILD" },
            { text = "说 (SAY)", val = "SAY" },
        }
        for _, c in ipairs(channels) do
            local info = dropLib:UIDropDownMenu_CreateInfo()
            info.text = c.text
            info.value = c.val
            info.checked = (selectedChannel == c.val)
            info.func = function()
                selectedChannel = c.val
                dropLib:UIDropDownMenu_SetSelectedValue(channelDropdown, c.val)
                dropLib:UIDropDownMenu_SetText(channelDropdown, c.val)
            end
            dropLib:UIDropDownMenu_AddButton(info, level)
        end
    end
    dropLib:UIDropDownMenu_Initialize(channelDropdown, InitChannelMenu)
    dropLib:UIDropDownMenu_SetSelectedValue(channelDropdown, "RAID")
    dropLib:UIDropDownMenu_SetText(channelDropdown, "团队")

    -- 通报按钮
    local btnReport = BG.CreateButton(bar)
    btnReport:SetSize(80, 24)
    btnReport:SetPoint("LEFT", channelDropdown, "RIGHT", -12, 2)
    btnReport:SetText("通报缺口")
    btnReport:SetScript("OnClick", function()
        RaidComp.SendReportToChat(selectedChannel)
    end)
    btnReport:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(BG.STC_g1("一键通报阵容与Buff缺口"))
        GameTooltip:AddLine("向当前选中频道通报团队人数、核心缺口以及推荐招募职业，并附带插件推广信息。", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(BG.STC_y1("尾缀: ") .. RaidComp.PROMO_TEXT, 0.6, 0.8, 1, true)
        GameTooltip:Show()
    end)
    btnReport:SetScript("OnLeave", GameTooltip_Hide)

    bar:SetScript("OnShow", function()
        RaidComp.StartScan(false)
        RaidCompUI.UpdateBottomBarUI()
    end)

    return bar
end

--------------------------------------------------------------------------------
-- 2. 全家福详细矩阵大看板 (Matrix Modal Frame)
--------------------------------------------------------------------------------
local modalFrame = nil
local cardButtons = {}
local rosterRows = {}

function RaidCompUI.CreateMatrixModal()
    if modalFrame then return modalFrame end

    local f = CreateFrame("Frame", "BG_RaidCompMatrixModalFrame", UIParent, "BackdropTemplate")
    f:SetSize(930, 615)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 15)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    f:SetBackdropBorderColor(0.2, 0.7, 1, 0.95)
    f:EnableMouse(true)
    f:Hide()
    modalFrame = f

    -- 标题与关闭按钮
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText(BG.STC_g1("【25人团队阵容天赋分析 & Buff/Debuff 全家福矩阵】"))

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- 顶部摘要与一键重新扫描
    local topSummary = f:CreateFontString(nil, "OVERLAY")
    topSummary:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    topSummary:SetPoint("TOPLEFT", 18, -38)
    topSummary:SetText("正在计算中...")
    f.topSummary = topSummary

    local btnRescan = BG.CreateButton(f)
    btnRescan:SetSize(80, 22)
    btnRescan:SetPoint("TOPRIGHT", -45, -34)
    btnRescan:SetText("刷新扫描")
    btnRescan:SetScript("OnClick", function()
        RaidComp.StartScan(true)
        BG.PlaySound(1)
    end)

    -- 主分割线
    local hLine = f:CreateLine()
    hLine:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    hLine:SetStartPoint("TOPLEFT", 15, -60)
    hLine:SetEndPoint("TOPRIGHT", -15, -60)
    hLine:SetThickness(1)

    -- 左半区：四列卡片网格容器 (宽 645px, 高 490px，宽裕容纳物理9项卡片)
    local matrixContainer = CreateFrame("Frame", nil, f)
    matrixContainer:SetSize(645, 490)
    matrixContainer:SetPoint("TOPLEFT", 15, -66)
    f.matrixContainer = matrixContainer

    -- 右半区：团队 25 人专精明细滚动列表 (宽 250px, 高 490px)
    local rosterPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rosterPanel:SetSize(250, 490)
    rosterPanel:SetPoint("TOPRIGHT", -15, -66)
    rosterPanel:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    rosterPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
    rosterPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local rTitle = rosterPanel:CreateFontString(nil, "OVERLAY")
    rTitle:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    rTitle:SetPoint("TOPLEFT", 10, -8)
    rTitle:SetText(BG.STC_b1("团队成员专精扫描列表"))

    local scrollFrame = CreateFrame("ScrollFrame", "BG_RaidCompRosterScroll", rosterPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 6)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(220, 600)
    scrollFrame:SetScrollChild(scrollChild)
    f.rosterScrollChild = scrollChild

    -- 底部建议与通报栏 (清晰留白，彻底避免被上方卡片覆盖)
    local bLine = f:CreateLine()
    bLine:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    bLine:SetStartPoint("BOTTOMLEFT", 15, 48)
    bLine:SetEndPoint("BOTTOMRIGHT", -15, 48)
    bLine:SetThickness(1)

    local tipRec = f:CreateFontString(nil, "OVERLAY")
    tipRec:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    tipRec:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 17)
    tipRec:SetWidth(730)
    tipRec:SetJustifyH("LEFT")
    tipRec:SetText("[招募建议] 推荐补充职业: 无")
    f.tipRec = tipRec

    local btnModalReport = BG.CreateButton(f)
    btnModalReport:SetSize(116, 26)
    btnModalReport:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 11)
    btnModalReport:SetText("通报到当前频道")
    btnModalReport:SetScript("OnClick", function()
        RaidComp.SendReportToChat(selectedChannel)
    end)

    f:SetScript("OnShow", function()
        RaidCompUI.UpdateMatrixModalUI()
    end)

    return f
end

-- 切换大看板显隐
function RaidCompUI.ToggleMatrixModal()
    local f = RaidCompUI.CreateMatrixModal()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        RaidCompUI.UpdateMatrixModalUI()
    end
end

--------------------------------------------------------------------------------
-- 3. 界面数据刷新引擎 (Update UI)
--------------------------------------------------------------------------------
-- 刷新底部精简栏
function RaidCompUI.UpdateBottomBarUI()
    local bar = RaidCompUI.bottomBar
    if not bar then return end

    local ok, err = pcall(function()
        local stats = RaidComp.GetRosterStats()
        local diag = RaidComp.GetFullBuffDiagnostics()

        bar.textRoster:SetText(format("成员: |cff00ff00%d|r 人 (坦:%d  奶:%d  近战:%d  远程:%d)",
            stats.total, stats.tanks, stats.healers, stats.melees, stats.rangeds))

        local scanText = format("已识别专精: %d/%d", stats.inspectedCount, stats.total)
        if stats.isScanning then
            scanText = scanText .. " |cffffcc00(扫描中...)|r"
        end
        bar.textScan:SetText(scanText)

        local pct = math.floor((diag.coveredCount / math.max(diag.totalBuffs, 1)) * 100)
        local pctColor = (pct == 100) and "00ff00" or ((pct >= 80) and "ffff00" or "ff4444")
        bar.textCoverage:SetText(format("核心增益覆盖: |cff%s%d|r / %d (|cff%s%d%%|r)",
            pctColor, diag.coveredCount, diag.totalBuffs, pctColor, pct))

        if diag.missingCount == 0 then
            bar.textMissing:SetText(BG.STC_g1("[√] 全团核心 Buff/Debuff 已 100% 齐备！"))
        else
            local missStr = ""
            local showMax = math.min(#diag.missingList, 3)
            for i = 1, showMax do
                local item = diag.missingList[i]
                local sep = (i == showMax) and "" or ", "
                missStr = missStr .. item.def.shortName .. sep
            end
            if #diag.missingList > 3 then
                missStr = missStr .. " 等" .. #diag.missingList .. "项"
            end
            bar.textMissing:SetText(BG.STC_r1("[缺] " .. missStr))
        end
    end)
    if not ok and err then
        print("|cffff2020[BGLite PLUS 底部栏刷新错误]|r: " .. tostring(err))
    end
end

-- 刷新详细大矩阵面板 (全量安全沙箱保护)
function RaidCompUI.UpdateMatrixModalUI()
    local f = modalFrame
    if not f or not f:IsShown() then return end

    local ok, err = pcall(function()
        local stats = RaidComp.GetRosterStats()
        local diag = RaidComp.GetFullBuffDiagnostics()

        f.topSummary:SetText(format("团队总人数: |cff00ff00%d|r人 (坦:%d 奶:%d 近:%d 远:%d)  |  专精识别: %d/%d  |  Buff覆盖: |cff00ff00%d|r/%d",
            stats.total, stats.tanks, stats.healers, stats.melees, stats.rangeds, stats.inspectedCount, stats.total, diag.coveredCount, diag.totalBuffs))

        -- 绘制四大列 Buff 网格卡片
        local colWidth = 156
        local cardHeight = 44
        local startX = 2
        local startY = -4

        local catOrder = { "CORE", "SPELL", "PHYSICAL", "SURVIVAL" }
        for colIdx, catId in ipairs(catOrder) do
            local catData = diag.categoryResults[catId]
            if catData then
                local cX = startX + (colIdx - 1) * (colWidth + 6)
                local cY = startY

                -- 列标题
                local catHeaderKey = "catHeader_" .. catId
                if not f[catHeaderKey] then
                    local h = f.matrixContainer:CreateFontString(nil, "OVERLAY")
                    h:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    f[catHeaderKey] = h
                end
                f[catHeaderKey]:ClearAllPoints()
                f[catHeaderKey]:SetPoint("TOPLEFT", f.matrixContainer, "TOPLEFT", cX, cY)
                local headColor = (catData.covered == catData.total) and "00ff00" or "00BFFF"
                f[catHeaderKey]:SetText(format("|cff%s%s (%d/%d)|r", headColor, catData.name, catData.covered, catData.total))

                cY = cY - 22

                for itemIdx, item in ipairs(catData.items) do
                    local cardKey = catId .. "_" .. itemIdx
                    local btn = cardButtons[cardKey]
                    if not btn then
                        btn = CreateFrame("Button", nil, f.matrixContainer, "BackdropTemplate")
                        btn:SetSize(colWidth, cardHeight)
                        btn:SetBackdrop({
                            bgFile = "Interface/ChatFrame/ChatFrameBackground",
                            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                            edgeSize = 8,
                            insets = { left = 2, right = 2, top = 2, bottom = 2 },
                        })

                        btn.iconTxt = btn:CreateFontString(nil, "OVERLAY")
                        btn.iconTxt:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                        btn.iconTxt:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -5)

                        btn.nameTxt = btn:CreateFontString(nil, "OVERLAY")
                        btn.nameTxt:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                        btn.nameTxt:SetPoint("LEFT", btn.iconTxt, "RIGHT", 4, 0)
                        btn.nameTxt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                        btn.nameTxt:SetJustifyH("LEFT")

                        btn.descTxt = btn:CreateFontString(nil, "OVERLAY")
                        btn.descTxt:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
                        btn.descTxt:SetPoint("TOPLEFT", btn, "TOPLEFT", 6, -24)
                        btn.descTxt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                        btn.descTxt:SetJustifyH("LEFT")

                        cardButtons[cardKey] = btn
                    end

                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", f.matrixContainer, "TOPLEFT", cX, cY)
                    btn:Show()

                    btn.itemData = item

                    if item.isCovered then
                        btn:SetBackdropColor(0.08, 0.22, 0.12, 0.85)
                        btn:SetBackdropBorderColor(0.2, 0.8, 0.3, 0.9)
                        btn.iconTxt:SetText(BG.STC_g1("[√]"))
                        btn.nameTxt:SetText(BG.STC_w1(item.def.shortName))
                        btn.descTxt:SetText(BG.STC_g2("已覆盖 (" .. #item.providers .. "人)"))
                    else
                        btn:SetBackdropColor(0.24, 0.08, 0.08, 0.85)
                        btn:SetBackdropBorderColor(0.9, 0.2, 0.2, 0.9)
                        btn.iconTxt:SetText(BG.STC_r1("[×]"))
                        btn.nameTxt:SetText(BG.STC_r1(item.def.shortName))
                        btn.descTxt:SetText(BG.STC_r2("缺: " .. (item.def.needSpec or "")))
                    end

                    btn:SetScript("OnEnter", function(self)
                        local data = self.itemData
                        if not data then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine(data.def.name, 1, 1, 1)
                        GameTooltip:AddLine(data.def.desc, 0.8, 0.8, 0.8, true)
                        GameTooltip:AddLine(" ")
                        if data.isCovered then
                            GameTooltip:AddLine(BG.STC_g1("[已覆盖] 状态正常"))
                            GameTooltip:AddLine("提供该增益的团队成员:")
                            for _, p in ipairs(data.providers) do
                                GameTooltip:AddLine("  - " .. p, 0.2, 1, 0.4)
                            end
                        else
                            GameTooltip:AddLine(BG.STC_r1("[缺失] 急需补充！"))
                            GameTooltip:AddLine("建议补充职业或专精:")
                            GameTooltip:AddLine("  - " .. (data.def.needSpec or "未知"), 1, 0.82, 0)
                        end
                        GameTooltip:Show()
                    end)
                    btn:SetScript("OnLeave", GameTooltip_Hide)

                    cY = cY - (cardHeight + 4)
                end
            end
        end

        -- 绘制右侧团队成员专精滚动列表 (安全兜底，杜绝 nil pairs 报错)
        local rosterList = {}
        local rawRoster = RaidComp.rosterData or {}
        for _, m in pairs(rawRoster) do
            if m and m.name then
                tinsert(rosterList, m)
            end
        end
        table.sort(rosterList, function(a, b)
            if a.class ~= b.class then return tostring(a.class) < tostring(b.class) end
            return tostring(a.name) < tostring(b.name)
        end)

        for i, row in ipairs(rosterRows) do row:Hide() end

        local roleTextPrefix = {
            tank = "[坦]",
            healer = "[奶]",
            melee = "[近]",
            ranged = "[远]",
        }

        local rY = 0
        for i, m in ipairs(rosterList) do
            local row = rosterRows[i]
            if not row then
                row = CreateFrame("Button", nil, f.rosterScrollChild)
                row:SetSize(210, 20)
                row.text = row:CreateFontString(nil, "OVERLAY")
                row.text:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
                row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                rosterRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.rosterScrollChild, "TOPLEFT", 0, rY)
            row:Show()

            local roleTag = roleTextPrefix[m.specRole] or "[-]"
            local classColor = GetClassColorHex(m.class)
            local nameColored = "|cff" .. classColor .. m.name .. "|r"
            local specDisplayName = m.specName or "未知"
            if m.isEstimated then
                specDisplayName = "|cffffaa00[推]|r" .. specDisplayName
            end

            row.text:SetText(format("%s %s - %s", roleTag, nameColored, specDisplayName))

            -- 鼠标悬停显示详细来源与天赋
            row:EnableMouse(true)
            row.memberData = m
            row.nameColored = nameColored

            -- 点击支持手动指定团队定位与专精 (弹出便捷下拉选单)
            row:SetScript("OnClick", function(self, btnClick)
                local mem = self.memberData
                if not mem then return end

                local menuList = {
                    { text = "|cff00ffff" .. mem.name .. " (手动指定职责/专精)|r", isTitle = true, notCheckable = true },
                }

                local classSpecs = (RaidComp.SPEC_INFO and RaidComp.SPEC_INFO[mem.class]) or {}
                for sIdx, sInfo in ipairs(classSpecs) do
                    local roleTitle = (sInfo.role == "tank") and "坦克" or ((sInfo.role == "healer") and "治疗" or ((sInfo.role == "melee") and "近战" or "远程"))
                    tinsert(menuList, {
                        text = format("%s - %s", sInfo.name, roleTitle),
                        notCheckable = false,
                        checked = (mem.specName == sInfo.name),
                        func = function()
                            if RaidComp.ManualSetMemberSpecRole then
                                RaidComp.ManualSetMemberSpecRole(mem.name, sInfo.name, sInfo.role)
                            end
                            DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite PLUS]|r 已将成员 |cff%s%s|r 团队定位修正为: 【%s - %s】",
                                GetClassColorHex(mem.class), mem.name, sInfo.name, roleTitle))
                        end
                    })
                end

                -- 通用快速职责切换
                tinsert(menuList, { text = "快速切换团队定位:", isTitle = true, notCheckable = true })
                local quickRoles = {
                    { tag = "tank", name = "坦克(Tank)" },
                    { tag = "healer", name = "治疗(Healer)" },
                    { tag = "melee", name = "近战输出(Melee DPS)" },
                    { tag = "ranged", name = "远程输出(Ranged DPS)" },
                }
                for _, qr in ipairs(quickRoles) do
                    tinsert(menuList, {
                        text = qr.name,
                        notCheckable = false,
                        checked = (mem.specRole == qr.tag),
                        func = function()
                            if RaidComp.ManualSetMemberSpecRole then
                                RaidComp.ManualSetMemberSpecRole(mem.name, mem.specName, qr.tag)
                            end
                            DEFAULT_CHAT_FRAME:AddMessage(format("|cff00BFFF[BGLite PLUS]|r 已将成员 |cff%s%s|r 团队定位快速修正为: 【%s】",
                                GetClassColorHex(mem.class), mem.name, qr.name))
                        end
                    })
                end

                local menuFrame = CreateFrame("Frame", "BG_RaidCompMemberMenu", UIParent, "UIDropDownMenuTemplate")
                local dropLib = LibBG or {
                    EasyMenu = function(menu, frame, anchor, x, y, displayMode)
                        if EasyMenu then EasyMenu(menu, frame, anchor, x, y, displayMode) end
                    end
                }
                dropLib:EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
            end)

            if not row.hasHookedTooltip then
                row.hasHookedTooltip = true
                row:SetScript("OnEnter", function(self)
                    local mem = self.memberData
                    if not mem then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(self.nameColored, 1, 1, 1)
                    local clsName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[mem.class]) or mem.class
                    GameTooltip:AddLine("职业: " .. clsName, 0.9, 0.9, 0.9)
                    GameTooltip:AddLine("专精: |cff00ff00" .. (mem.specName or "未知") .. "|r", 0.9, 0.9, 0.9)
                    local roleDesc = (mem.specRole == "tank") and "坦克(防护)" or ((mem.specRole == "healer") and "治疗(恢复)" or "伤害输出(DPS)")
                    GameTooltip:AddLine("团队职责: " .. roleDesc, 0.9, 0.9, 0.9)
                    if mem.points and mem.points ~= "" then
                        GameTooltip:AddLine("天赋点数: |cff55ffff" .. mem.points .. "|r", 0.8, 0.8, 1)
                    end
                    local srcColor = mem.isEstimated and "ffaa00" or "00ff88"
                    GameTooltip:AddLine("数据来源: |cff" .. srcColor .. (mem.source or "多源识别") .. "|r", 1, 1, 1)
                    if mem.isEstimated then
                        GameTooltip:AddLine("说明: 队友当前不在附近视距内，已依据团队职责/职业常识进行智能预判", 1, 0.82, 0, true)
                    else
                        GameTooltip:AddLine("说明: 已通过跨插件网络/数据库接口成功获取精准专精", 0.7, 1, 0.7, true)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ffcc[提示]|r 点击条目可手动调整该成员的专精与团队定位！", 0.2, 1, 0.8, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
            end

            rY = rY - 21
        end
        f.rosterScrollChild:SetHeight(math.max(math.abs(rY) + 20, 420))

    -- 底部建议文案
    if #diag.recommendations > 0 then
        local recStr = ""
        for i = 1, math.min(#diag.recommendations, 3) do
            local rec = diag.recommendations[i]
            local cls, spc = strsplit("-", rec.specKey)
            local clsName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
            local full = (spc and spc ~= "") and (spc .. clsName) or clsName
            recStr = recStr .. "[" .. full .. " (可补" .. rec.count .. "项)] "
        end
        f.tipRec:SetText("[招募建议] 推荐优先招募: " .. BG.STC_g1(recStr))
        else
            f.tipRec:SetText("[招募建议] 团队增益已十分齐备，可按需补充核心输出或高装等打手！")
        end
    end)
    if not ok and err then
        print("|cffff2020[BGLite PLUS 矩阵看板渲染错误]|r: " .. tostring(err))
    end
end

-- 全局总刷新
function RaidComp.UpdateUI()
    RaidCompUI.UpdateBottomBarUI()
    RaidCompUI.UpdateMatrixModalUI()
end

-- 模块初始化与挂载到 RaidTool
function ns.InitRaidCompModule()
    if BG and BG.RaidToolMainFrame then
        RaidCompUI.CreateBottomBar(BG.RaidToolMainFrame)
        -- 启动首次扫描 (安全校验函数就绪)
        C_Timer.After(1.0, function()
            local comp = ns.RaidComp or _G.RaidComp
            if comp and comp.StartScan then
                comp.StartScan(false)
            end
        end)
    end
end
