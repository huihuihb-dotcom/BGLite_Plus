local _, ns = ...

local LibBG = ns.LibBG
local L = ns.L

local RR = ns.RR
local NN = ns.NN
local RN = ns.RN
local Size = ns.Size
local RGB = ns.RGB
local GetClassRGB = ns.GetClassRGB
local SetClassCFF = ns.SetClassCFF
local HopeMaxn = ns.HopeMaxn
local HopeMaxb = ns.HopeMaxb
local HopeMaxi = ns.HopeMaxi
local AddTexture = ns.AddTexture
local GetItemID = ns.GetItemID

local pt = print
local RealmID = GetRealmID()
local player = UnitName("player") or BG.playerName or ""

BG.HopeJingzheng = {}

function BG.HopeUI(FB)
    local preWidget
    local framedown
    local frameright
    local framedownH
    local red, greed, blue = 1, 1, 1
    local touming1, touming2 = 0.1, 0.1
    local btwidth = 115
    local titlewidth = 100
    local titlewidth2 = 20

    for n = 1, HopeMaxn[FB], 1 do
        ------------------标题------------------
        do
            local version = BG["HopeFrame" .. FB]:CreateFontString()
            if n == 1 then
                version:SetPoint("TOPLEFT", BG.MainFrame, "TOPLEFT", 10, -60)
            elseif n == 2 then
                version:SetPoint("TOPRIGHT", framedownH, "TOPLEFT", -titlewidth2, -30)
            end
            version:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
            version:SetTextColor(RGB(BG.y2))
            version:SetWidth(titlewidth)
            version:SetWordWrap(false)
            version:SetJustifyH("RIGHT")
            if BG.IsWLKFB(FB) then
                if n == 1 then
                    version:SetText(L["< |cffFFFFFF10人|r|cff00BFFF普通|r >"])
                elseif n == 2 then
                    version:SetText(L["< |cffFFFFFF25人|r|cff00BFFF普通|r >"])
                elseif n == 3 then
                    version:SetPoint("TOPLEFT", frameright, "TOPRIGHT", titlewidth2, 0)
                    version:SetText(L["< |cffFFFFFF10人|r|cffFF0000英雄|r >"])
                elseif n == 4 then
                    version:SetText(L["< |cffFFFFFF25人|r|cffFF0000英雄|r >"])
                    version:SetPoint("TOPRIGHT", framedownH, "TOPLEFT", -titlewidth2, -30)
                end
            elseif BG.IsRetail then
                if n == 1 then
                    version:SetText(L["< |cff00BFFF普通|r >"])
                elseif n == 2 then
                    version:SetText(L["< |cffFF0000英雄|r >"])
                elseif n == 3 then
                    version:SetPoint("TOPRIGHT", framedownH, "TOPLEFT", -titlewidth2, -30)
                    version:SetText(L["< |cffa335ee史诗|r >"])
                end
            else
                if n == 1 then
                    version:SetText(L["< |cff00BFFF普通|r >"])
                elseif n == 2 then
                    version:SetText(L["< |cffFF0000英雄|r >"])
                end
            end
            preWidget = version

            for i = 1, HopeMaxi, 1 do
                local version = BG["HopeFrame" .. FB]:CreateFontString()
                if i == 1 then
                    version:SetPoint("TOPLEFT", preWidget, "TOPRIGHT", titlewidth2, 0)
                    framedown = version
                else
                    version:SetPoint("TOPLEFT", preWidget, "TOPRIGHT", titlewidth2 + 6, 0)
                    frameright = version
                end
                version:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                version:SetTextColor(RGB(BG.y2))
                version:SetText(L["心愿"] .. i)
                version:SetWidth(btwidth)
                version:SetWordWrap(false)
                version:SetJustifyH("LEFT")
                preWidget = version
            end
        end
        for b = 1, HopeMaxb[FB], 1 do
            for i = 1, HopeMaxi, 1 do
                ------------------装备------------------
                do
                    local bt = CreateFrame("EditBox", nil, BG["HopeFrame" .. FB], BG.editTemplate)
                    bt:SetSize(btwidth, 20)
                    bt:SetFrameLevel(110)
                    if i == 1 then
                        bt:SetPoint("TOPLEFT", framedown, "BOTTOMLEFT", 0, -1)
                    else
                        bt:SetPoint("TOPLEFT", framedown, "TOPLEFT", (btwidth + 26) * (i - 1), 0)
                    end
                    bt:SetAutoFocus(false)
                    BG.SetEditStickyFocus(bt)
                    bt:Show()
                    bt.FB = FB
                    bt.bossnum = b
                    bt.hopenandu = n
                    bt.i = i
                    bt.icon = bt:CreateTexture(nil, 'ARTWORK')
                    bt.icon:SetPoint('LEFT', -22, 0)
                    bt.icon:SetSize(16, 16)
                    if BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] then
                        if BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] ~= "" then
                            bt:SetText(BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i])
                            bt:SetCursorPosition(0)
                        else
                            BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = nil
                        end
                    end
                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = bt
                    preWidget = bt
                    if i == 1 then
                        framedown = bt
                        -- if n == 1 or n == 3 and b == HopeMaxb[FB] then
                        if b == HopeMaxb[FB] then
                            framedownH = bt
                        end
                    end
                    -- 创建已掉落文本
                    BG.LootedText(bt)

                    -- 内容改变时
                    bt:SetScript("OnTextChanged", function(self)
                        local itemText = bt:GetText()
                        local itemID = select(1, GetItemInfoInstant(itemText))
                        if itemID then
                            BG.OnItemLoad(itemText):ContinueOnItemLoad(function()
                                local name, link, quality, level, _, _, _, _, _, Texture,
                                _, typeID, _, bindType = GetItemInfo(itemText)
                                BG.AddHText(FB, itemText, itemID, self)
                                self.icon:SetTexture(Texture)
                                BG.BindOnEquip(self, bindType)
                                BG.LevelText(self, level, typeID)
                                BG.IsHave(self)
                            end)
                        else
                            self.icon:SetTexture(nil)
                            BG.BindOnEquip(self)
                            BG.LevelText(self)
                            BG.IsHave(self)
                        end

                        BG.UpdateFilter(self)
                        BG.Update_IsLooted(self)

                        if itemText ~= "" then
                            BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = itemText
                        else
                            BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = nil
                        end
                    end)
                    -- 点击
                    bt:SetScript("OnMouseDown", function(self, button)
                        if button == "RightButton" and not IsAltKeyDown() then
                            self:SetEnabled(false)
                            self:SetText("")
                            if BG.lastfocus then
                                BG.lastfocus:ClearFocus()
                            end
                            return
                        end
                        if BG.IsSetBestPriceKeyDown(button == "RightButton") then
                            if self:GetText() ~= "" then
                                self:SetEnabled(false)
                                bt:ClearFocus()
                                if BG.lastfocus then
                                    BG.lastfocus:ClearFocus()
                                end
                                BG.SetBestPrice(self:GetText(), self)
                            end
                            return
                        end
                        if IsShiftKeyDown() then
                            if self:GetText() ~= "" then
                                self:SetEnabled(false)
                                bt:ClearFocus()
                                BG.InsertLink(self:GetText())
                            end
                            return
                        end
                        if IsAltKeyDown() then
                            if self:GetText() ~= "" then
                                self:SetEnabled(false)
                                bt:ClearFocus()
                                if BG.lastfocus then
                                    BG.lastfocus:ClearFocus()
                                end
                            end
                            return
                        end
                        if IsControlKeyDown() then
                            if self:GetText() ~= "" then
                                self:SetEnabled(false)
                                BG.GoToItemLib(self)
                            end
                            return
                        end
                    end)
                    bt:SetScript("OnMouseUp", function(self, enter)
                        if self:IsEnabled() then
                            local infoType, itemID, itemLink = GetCursorInfo()
                            if infoType == "item" then
                                self:SetText(itemLink)
                                self:ClearFocus()
                                ClearCursor()
                                return
                            end
                        end
                        for n = 1, HopeMaxn[FB], 1 do
                            for b = 1, HopeMaxb[FB] do
                                for i = 1, HopeMaxi do
                                    if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] then
                                        BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]:SetEnabled(true)
                                    end
                                end
                            end
                        end
                        if enter == "RightButton" then
                            self:SetEnabled(true)
                        end
                    end)
                    -- 鼠标悬停在装备时
                    bt:SetScript("OnEnter", function(self)
                        BG.HopeFrameDs[FB .. 1]["nandu" .. n]["boss" .. b]["ds" .. i]:Show()
                        if not tonumber(self:GetText()) then
                            local link = bt:GetText()
                            local itemID = select(1, GetItemInfoInstant(link))
                            if itemID then
                                local point
                                if BG.ButtonIsInRight(self) then
                                    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
                                    point = 'LEFT'
                                else
                                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
                                    point = 'RIGHT'
                                end
                                GameTooltip:ClearLines()
                                GameTooltip:SetHyperlink(BG.SetSpecIDToLink(link))
                                if BG.SetHistoryMoney then
                                    BG.SetHistoryMoney(itemID)
                                end

                                BG.DressUpLastButton = self
                                if IsControlKeyDown() and not IsShiftKeyDown() then
                                    SetCursor("Interface/Cursor/Inspect")
                                    BG.DressUp()
                                end
                                BG.canShowTrunToItemLibCursor = true
                            end
                        end
                    end)
                    bt:SetScript("OnLeave", function(self)
                        BG.HopeFrameDs[FB .. 1]["nandu" .. n]["boss" .. b]["ds" .. i]:Hide()
                        GameTooltip:Hide()
                        BG.HideHistoryMoney()
                        SetCursor(nil)
                        BG.canShowTrunToItemLibCursor = nil
                        if BG.DressUpFrame then
                            BG.DressUpFrame:Hide()
                        end
                        BG.DressUpLastButton = nil
                    end)
                    -- 获得光标时
                    bt:SetScript("OnEditFocusGained", function(self)
                        BG.FrameHide(1)
                        self:HighlightText()
                        BG.lastfocuszhuangbei = self
                        BG.lastfocus = self

                        local infoType, itemID, itemLink = GetCursorInfo()
                        if infoType ~= "item" then
                            BG.SetListzhuangbei(self)
                        end

                        if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1] then
                            BG.lastfocuszhuangbei2 = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1]
                        else
                            BG.lastfocuszhuangbei2 = nil
                        end
                        BG.HopeFrameDs[FB .. 2]["nandu" .. n]["boss" .. b]["ds" .. i]:Show()
                    end)
                    -- 失去光标时
                    bt:SetScript("OnEditFocusLost", function(self)
                        self:ClearHighlightText()
                        BG.HopeFrameDs[FB .. 2]["nandu" .. n]["boss" .. b]["ds" .. i]:Hide()
                    end)
                    -- 按TAB跳转右边
                    bt:SetScript("OnTabPressed", function(self)
                        if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1] then
                            BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1]:SetFocus()
                        elseif BG.HopeFrame[FB]["nandu" .. n]["boss" .. b + 1]["zhuangbei" .. 1] then
                            BG.HopeFrame[FB]["nandu" .. n]["boss" .. b + 1]["zhuangbei" .. 1]:SetFocus()
                        elseif n ~= HopeMaxn[FB] then
                            local nn
                            if n == 3 then
                                nn = 2
                            elseif n == 2 then
                                nn = 4
                            elseif n == 1 then
                                if HopeMaxn[FB] > 2 then
                                    nn = 3
                                else
                                    nn = 2
                                end
                            end
                            BG.HopeFrame[FB]["nandu" .. nn]["boss" .. 1]["zhuangbei" .. 1]:SetFocus()
                        end
                    end)
                    -- 按ENTER
                    bt:SetScript("OnEnterPressed", function(self)
                        self:ClearFocus()
                        if BG.FrameZhuangbeiList then
                            BG.FrameZhuangbeiList:Hide()
                        end
                    end)
                    -- 按箭头跳转
                    bt:SetScript("OnKeyDown", function(self, enter)
                        if not IsModifierKeyDown() then
                            if enter == "UP" then -- 上↑
                                if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b - 1] and
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b - 1]["zhuangbei" .. i] then
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b - 1]["zhuangbei" .. i]:SetFocus()
                                else
                                    local nn
                                    if n == 4 then
                                        nn = 2
                                    elseif n == 3 then
                                        nn = 1
                                    elseif n == 2 then
                                        if HopeMaxn[FB] > 2 then
                                            nn = 4
                                        else
                                            nn = 2
                                        end
                                    elseif n == 1 then
                                        if HopeMaxn[FB] > 2 then
                                            nn = 3
                                        else
                                            nn = 1
                                        end
                                    end
                                    BG.HopeFrame[FB]["nandu" .. nn]["boss" .. HopeMaxb[FB]]["zhuangbei" .. i]:SetFocus()
                                end
                            elseif enter == "DOWN" then -- 下↓
                                if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b + 1] and
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b + 1]["zhuangbei" .. i] then
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b + 1]["zhuangbei" .. i]:SetFocus()
                                else
                                    local nn
                                    if n == 4 then
                                        nn = 2
                                    elseif n == 3 then
                                        nn = 1
                                    elseif n == 2 then
                                        if HopeMaxn[FB] > 2 then
                                            nn = 4
                                        else
                                            nn = 1
                                        end
                                    elseif n == 1 then
                                        if HopeMaxn[FB] > 2 then
                                            nn = 3
                                        else
                                            nn = 1
                                        end
                                    end
                                    BG.HopeFrame[FB]["nandu" .. nn]["boss" .. 1]["zhuangbei" .. i]:SetFocus()
                                end
                            elseif enter == "LEFT" then -- 左←
                                if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i - 1] then
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i - 1]:SetFocus()
                                else
                                    local nn
                                    if HopeMaxn[FB] == 1 then
                                        nn = 1
                                    else
                                        if n == 4 then
                                            nn = 3
                                        elseif n == 3 then
                                            nn = 4
                                        elseif n == 2 then
                                            nn = 1
                                        elseif n == 1 then
                                            nn = 2
                                        end
                                    end
                                    BG.HopeFrame[FB]["nandu" .. nn]["boss" .. b]["zhuangbei" .. HopeMaxi]:SetFocus()
                                end
                            elseif enter == "RIGHT" then -- 右→
                                if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1] then
                                    BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i + 1]:SetFocus()
                                else
                                    local nn
                                    if HopeMaxn[FB] == 1 then
                                        nn = 1
                                    else
                                        if n == 4 then
                                            nn = 3
                                        elseif n == 3 then
                                            nn = 4
                                        elseif n == 2 then
                                            nn = 1
                                        elseif n == 1 then
                                            nn = 2
                                        end
                                    end
                                    BG.HopeFrame[FB]["nandu" .. nn]["boss" .. b]["zhuangbei" .. 1]:SetFocus()
                                end
                            end
                        else
                            if enter == "UP" or enter == "DOWN" then -- 上↑下↓
                                if HopeMaxn[FB] > 2 then
                                    local nn
                                    if n == 1 or n == 2 then
                                        nn = n + 2
                                    else
                                        nn = n - 2
                                    end
                                    if BG.HopeFrame[FB]["nandu" .. nn] then
                                        BG.HopeFrame[FB]["nandu" .. nn]["boss" .. b]["zhuangbei" .. i]:SetFocus()
                                    end
                                end
                            elseif enter == "LEFT" or enter == "RIGHT" then -- 左←右→
                                local nn
                                if n == 1 or n == 3 then
                                    nn = n + 1
                                else
                                    nn = n - 1
                                end
                                if BG.HopeFrame[FB]["nandu" .. nn] then
                                    BG.HopeFrame[FB]["nandu" .. nn]["boss" .. b]["zhuangbei" .. i]:SetFocus()
                                end
                            end
                        end
                    end)
                    -- 按ESC退出
                    bt:SetScript("OnEscapePressed", function(self)
                        self:ClearFocus()
                        if BG.FrameZhuangbeiList then
                            BG.FrameZhuangbeiList:Hide()
                        end
                    end)
                    -- 复原按钮为可点击
                    bt:SetScript("OnShow", function(self)
                        bt:Enable()
                    end)
                end

                ------------------底色材质------------------
                do
                    -- 先做底色材质1（鼠标悬停的）
                    local textrue = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]:CreateTexture()
                    textrue:SetPoint("TOPLEFT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "TOPLEFT", -4, -2)
                    textrue:SetPoint("BOTTOMRIGHT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "BOTTOMRIGHT", -1, 0)
                    textrue:SetColorTexture(red, greed, blue, touming1)
                    textrue:Hide()
                    BG.HopeFrameDs[FB .. 1]["nandu" .. n]["boss" .. b]["ds" .. i] = textrue

                    -- 底色材质2（点击框体后）
                    local textrue = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]:CreateTexture()
                    textrue:SetPoint("TOPLEFT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "TOPLEFT", -4, -2)
                    textrue:SetPoint("BOTTOMRIGHT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "BOTTOMRIGHT", -1, 0)
                    textrue:SetColorTexture(red, greed, blue, touming2)
                    textrue:Hide()
                    BG.HopeFrameDs[FB .. 2]["nandu" .. n]["boss" .. b]["ds" .. i] = textrue

                    -- 底色材质3（团长发的装备高亮）
                    local textrue = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]:CreateTexture()
                    textrue:SetPoint("TOPLEFT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "TOPLEFT", -4, -2)
                    textrue:SetPoint("BOTTOMRIGHT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i], "BOTTOMRIGHT", -1, 0)
                    textrue:SetColorTexture(1, 1, 0, BG.highLightAlpha)
                    textrue:Hide()
                    BG.HopeFrameDs[FB .. 3]["nandu" .. n]["boss" .. b]["ds" .. i] = textrue
                end
            end
            ------------------BOSS名字------------------
            do
                local version = BG["HopeFrame" .. FB]:CreateFontString()
                version:SetPoint("TOPRIGHT", BG.HopeFrame[FB]["nandu" .. n]["boss" .. b].zhuangbei1, "TOPLEFT", -titlewidth2 - 6, -3)
                version:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
                version:SetTextColor(RGB(BG.Boss[FB]["boss" .. b].color))
                version:SetText(BG.Boss[FB]["boss" .. b].name2)
                version:SetWidth(titlewidth)
                version:SetWordWrap(false)
                version:SetJustifyH("RIGHT")

                BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["name"] = version
            end
        end
    end

    if not BG.IsRetail then
        ------------------通报心愿------------------
        do
            local f
            local xinyuan
            if BG.onlyOneHard then
                xinyuan = {
                    { name1 = L["通报心愿"], name2 = "" },
                }
                -- elseif BG.IsRetail then
                --     xinyuan = {
                --         { name1 = L["|cffFFFFFF10人|r|cff00BFFF普通|r"], name2 = "10PT" },
                --         { name1 = L["|cffFFFFFF25人|r|cff00BFFF普通|r"], name2 = "25PT" },
                --         { name1 = L["|cffFFFFFF10人|r|cffFF0000英雄|r"], name2 = "10H" },
                --         { name1 = L["|cffFFFFFF25人|r|cffFF0000英雄|r"], name2 = "25H" },
                --     }
            else
                xinyuan = {
                    { name1 = L["|cffFFFFFF10人|r|cff00BFFF普通|r"], name2 = "10PT" },
                    { name1 = L["|cffFFFFFF25人|r|cff00BFFF普通|r"], name2 = "25PT" },
                    { name1 = L["|cffFFFFFF10人|r|cffFF0000英雄|r"], name2 = "10H" },
                    { name1 = L["|cffFFFFFF25人|r|cffFF0000英雄|r"], name2 = "25H" },
                }
            end

            local function CreateList(n, onClick)
                local tbl = {}
                local tbl_onClick = {}
                for b = 1, HopeMaxb[FB] do
                    local text = ""
                    for i = 1, HopeMaxi do
                        local zb = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                        if zb then
                            local _, link = GetItemInfo(zb:GetText())
                            if link then
                                text = text .. link
                            end
                        end
                    end

                    if text ~= "" then
                        local bosscolorname
                        if onClick then
                            bosscolorname = BG.Boss[FB]["boss" .. b]["name2"] .. ": "
                        else
                            bosscolorname = "|cff" .. BG.Boss[FB]["boss" .. b]["color"] .. BG.Boss[FB]["boss" .. b]["name2"] .. ": |r"
                        end
                        text = bosscolorname .. text
                        tinsert(tbl, text)
                    end
                end
                return tbl
            end

            for n = 1, HopeMaxn[FB] do
                local bt = BG.CreateButton(BG["HopeFrame" .. FB])
                bt:SetSize(120, 25)
                if n == 1 then
                    bt:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -30, -80)
                else
                    bt:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
                end
                bt:SetText(xinyuan[n].name1)
                bt:SetFrameLevel(105)
                f = bt

                -- 鼠标悬停提示
                bt:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(L["———我的心愿———"])
                    local tbl = CreateList(n)
                    if #tbl == 0 then
                        GameTooltip:AddLine(L["没有心愿"])
                    else
                        for i, text in ipairs(tbl) do
                            GameTooltip:AddLine(text)
                        end
                    end
                    GameTooltip:Show()
                end)
                bt:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)

                -- 单击触发
                bt:SetScript("OnClick", function(self)
                    if BG.InBoss() then return end
                    BG.FrameHide(0)
                    if not BiaoGe.HopeSendChannel then return end
                    local targetName = BG.GN("t")
                    if BiaoGe.HopeSendChannel == "RAID" then
                        if not IsInRaid(1) then
                            SendSystemMessage(L["不在团队，无法通报"])
                            BG.PlaySound(1)
                            return
                        end
                    end
                    if BiaoGe.HopeSendChannel == "PARTY" then
                        if not IsInGroup() then
                            SendSystemMessage(L["不在队伍，无法通报"])
                            BG.PlaySound(1)
                            return
                        end
                    end
                    if BiaoGe.HopeSendChannel == "GUILD" then
                        if not IsInGuild() then
                            SendSystemMessage(L["没有公会，无法通报"])
                            BG.PlaySound(1)
                            return
                        end
                    end
                    if BiaoGe.HopeSendChannel == "WHISPER" then
                        if not targetName then
                            SendSystemMessage(L["没有目标，无法通报"])
                            BG.PlaySound(1)
                            return
                        end
                    end

                    self:SetEnabled(false)
                    C_Timer.After(2, function()
                        bt:SetEnabled(true)
                    end)
                    local channel = BiaoGe.HopeSendChannel

                    local text = L["———我的心愿———"]
                    SendChatMessage(text, channel, nil, targetName)

                    local tbl = CreateList(n, true)
                    if #tbl == 0 then
                        BG.After(BG.tongBaoSendCD, function()
                            text = L["没有心愿"]
                            SendChatMessage(text, channel, nil, targetName)
                        end)
                    else
                        local t = BG.tongBaoSendCD
                        for _, text in ipairs(tbl) do
                            BG.After(t, function()
                                SendChatMessage(text, channel, nil, targetName)
                            end)
                            t = t + BG.tongBaoSendCD
                        end
                    end
                    BG.PlaySound(2)
                end)
            end

            -- 频道
            BG.HopeSendTable = {
                RAID = L["频道：团队"],
                PARTY = L["频道：队伍"],
                GUILD = L["频道：公会"],
                WHISPER = L["频道：密语"],
            }
            if not BG.HopeSenddropDown then
                BG.HopeSenddropDown = {}
            end
            if not BiaoGe.HopeSendChannel then
                BiaoGe.HopeSendChannel = "RAID"
            end

            local function AddButton(dropDown, text, channel)
                local info = LibBG:UIDropDownMenu_CreateInfo()
                info.text = text
                info.func = function()
                    BiaoGe.HopeSendChannel = channel
                    LibBG:UIDropDownMenu_SetText(dropDown, BG.HopeSendTable[BiaoGe.HopeSendChannel])
                    BG.FrameHide(0)
                end
                if BiaoGe.HopeSendChannel == channel then
                    info.checked = true
                end
                LibBG:UIDropDownMenu_AddButton(info)
            end

            local dropDown = LibBG:Create_UIDropDownMenu(nil, BG["HopeFrame" .. FB])
            BG.HopeSenddropDown[FB] = dropDown
            BG.dropDownToggle(dropDown)
            dropDown:SetPoint("TOP", f, "BOTTOM", 0, -5)
            LibBG:UIDropDownMenu_SetWidth(dropDown, 100)
            LibBG:UIDropDownMenu_SetAnchor(dropDown, 0, 0, "TOP", dropDown, "BOTTOM")
            LibBG:UIDropDownMenu_SetText(dropDown, BG.HopeSendTable[BiaoGe.HopeSendChannel])
            LibBG:UIDropDownMenu_Initialize(dropDown, function(self, level, menuList)
                BG.FrameHide(0)
                AddButton(dropDown, L["团队"], "RAID")
                AddButton(dropDown, L["队伍"], "PARTY")
                AddButton(dropDown, L["公会"], "GUILD")
                AddButton(dropDown, L["密语目标"], "WHISPER")
            end)
        end
    end

    -- 更新心愿
    BG["HopeFrame" .. FB]:HookScript("OnShow", function(self)
        for n = 1, HopeMaxn[FB] do
            for b = 1, HopeMaxb[FB] do
                for i = 1, HopeMaxi do
                    local bt = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                    if bt and bt:GetText() == "" then
                        for ii = i, HopeMaxi do
                            local _bt = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. ii]
                            if _bt:GetText() ~= "" then
                                bt:SetText(_bt:GetText())
                                _bt:SetText("")
                                break
                            end
                        end
                    end
                end
            end
        end
        BG.UpdateHopeFrame_IsLooted_All()
    end)
end

----------导出导入心愿心愿----------
function BG.HopeDaoChuUI()
    local width_jiange = -7
    local hideFrameTbl = {}
    local function HideOtherFrame(myframe)
        for _, frame in ipairs(hideFrameTbl) do
            if not myframe or frame.frameName ~= myframe.frameName then
                frame:Hide()
            end
        end
    end
    local function ExportHope()
        local FB = BG.FB1
        local tbl = {}
        for n = 1, HopeMaxn[FB] do
            for b = 1, HopeMaxb[FB] do
                local oneboss = {}
                for i = 1, HopeMaxi do
                    local bt = BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                    if bt then
                        local itemID = GetItemID(bt:GetText())
                        if itemID then
                            tinsert(oneboss, itemID)
                        end
                    end
                end
                if #oneboss ~= 0 then
                    local t = "n" .. n .. "b" .. b
                    for i, itemID in ipairs(oneboss) do
                        t = t .. "-" .. itemID
                    end
                    tinsert(tbl, t)
                end
            end
        end
        local t = table.concat(tbl, ",")
        if t == "" then
            return L["心愿清单是空的"]
        else
            return FB .. ":" .. t
        end
    end
    local function ImportHope(text)
        -- 划分副本
        for _, fb in ipairs({ strsplit(".", text) }) do
            local FB, allboss = strsplit(":", fb)
            for _, _FB in ipairs(BG.FBtable) do
                if FB == _FB then
                    local qingkong
                    local count = 0
                    -- 划分boss
                    for _, v in ipairs({ strsplit(",", allboss) }) do
                        local text = { strsplit("-", v) }
                        local n, b = strmatch(text[1], "n(%d+)b(%d+)")
                        n, b = tonumber(n), tonumber(b)
                        if n and b and n <= HopeMaxn[FB] and b <= HopeMaxb[FB] then
                            local i = 1
                            for ii = 2, #text do
                                local itemID = tonumber(text[ii])
                                if itemID then
                                    if not qingkong then
                                        BG.ClearBiaoGe("hope", FB)
                                        qingkong = true
                                    end
                                    if BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] then
                                        local _i = i
                                        local item = Item:CreateFromItemID(itemID)
                                        item:ContinueOnItemLoad(function()
                                            local _, link = GetItemInfo(itemID)
                                            if link then
                                                BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. _i]:SetText(link)
                                                BiaoGe.Hope[RealmID][player][FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. _i] = link
                                                count = count + 1
                                            end
                                        end)
                                        i = i + 1
                                    end
                                end
                            end
                        end
                    end
                    if qingkong then
                        BG.UpdateItemLib_LeftHope_All()
                        BG.UpdateItemLib_RightHope_All()

                        BG.After(0.2, function()
                            SendSystemMessage(BG.BG .. BG.STC_g1(format(
                                L["心愿清单导入成功：%s，一共导入%s件装备。"], BG.GetFBinfo(FB, "shortName"), count)))
                        end)
                    end
                    break
                end
            end
        end
    end

    -- 导入心愿
    do
        local bt = CreateFrame("Button", nil, BG.HopeMainFrame)
        bt:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -35, 4)
        bt:SetNormalFontObject(BG.FontGreen15)
        bt:SetDisabledFontObject(BG.FontDis15)
        bt:SetHighlightFontObject(BG.FontWhite15)
        bt:SetText(L["导入心愿"])
        bt:SetSize(bt:GetFontString():GetWidth(), 30)
        BG.SetTextHighlightTexture(bt)
        BG.ButtonImportHope = bt

        bt:SetScript("OnClick", function(self)
            BG.PlaySound(1)
            HideOtherFrame(bt.bg)

            if not self.bg then
                local sbg, scroll, child
                local bg = CreateFrame("Frame", nil, bt, "BackdropTemplate")
                do
                    bg:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                        edgeSize = 10,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 }
                    })
                    bg:SetBackdropColor(0, 0, 0, 0.8)
                    bg:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -20, -20)
                    bg:SetSize(250, 250)
                    bg:SetFrameLevel(130)
                    bg:EnableMouse(true)
                    bg.frameName = self:GetText()
                    self.bg = bg
                    BG.frameImportHope = bg
                    tinsert(hideFrameTbl, bg)

                    local t = bg:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                    t:SetPoint("TOP", 0, -8)
                    t:SetTextColor(1, 1, 1)
                    t:SetText(bt:GetText())
                    t:SetWordWrap(false)
                end

                sbg = CreateFrame("Frame", nil, bg, "BackdropTemplate")
                do
                    sbg:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeSize = 1,
                    })
                    sbg:SetBackdropColor(0, 0, 0, 0.8)
                    sbg:SetBackdropBorderColor(1, 1, 1, 0.5)
                    sbg:SetPoint("TOPLEFT", 8, -28)
                    sbg:SetSize(bg:GetWidth() - 16, bg:GetHeight() - 70)
                    sbg:SetFrameLevel(130)
                    self.sbg = sbg
                    scroll = CreateFrame("ScrollFrame", nil, sbg, "UIPanelScrollFrameTemplate")
                    scroll:SetPoint("TOPLEFT", 5, -4)
                    scroll:SetPoint("BOTTOMRIGHT", -27, 4)
                    scroll.ScrollBar.scrollStep = BG.scrollStep
                    BG.CreateSrollBarBackdrop(scroll.ScrollBar)
                    BG.HookScrollBarShowOrHide(scroll)

                    self.s = scroll

                    child = CreateFrame("EditBox", nil, scroll)
                    child:SetWidth(sbg:GetWidth())
                    child:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    child:SetMultiLine(true)
                    child:SetAutoFocus(false)
                    child:EnableMouse(true)
                    child:SetTextInsets(5, 28, 5, 10)
                    self.child = child
                    scroll:SetScrollChild(child)
                    child:SetScript("OnEscapePressed", function(self)
                        bg:Hide()
                    end)
                    child:SetScript("OnEnterPressed", function(self)
                        BG.PlaySound(1)
                        ImportHope(child:GetText())
                        bg:Hide()
                    end)
                end

                local bt = BG.CreateButton(bg)
                do
                    bt:SetSize(110, 25)
                    bt:SetPoint("BOTTOMLEFT", 8, 10)
                    bt:SetText(OKAY)
                    bt:SetScript("OnClick", function(self)
                        BG.PlaySound(1)
                        ImportHope(child:GetText())
                        bg:Hide()
                    end)
                    local bt = BG.CreateButton(bg)
                    bt:SetSize(110, 25)
                    bt:SetPoint("BOTTOMRIGHT", -8, 10)
                    bt:SetText(CANCEL)
                    bt:SetScript("OnClick", function(self)
                        bg:Hide()
                    end)
                end
            else
                if self.bg:IsVisible() then
                    self.bg:Hide()
                else
                    self.bg:Show()
                end
            end
            self.child:SetText("")
            self.child:SetFocus()
        end)
    end
    -- 导出心愿
    do
        local bt = CreateFrame("Button", nil, BG.ButtonImportHope)
        bt:SetPoint("RIGHT", BG.ButtonImportHope, "LEFT", width_jiange, 0)
        bt:SetNormalFontObject(BG.FontGreen15)
        bt:SetDisabledFontObject(BG.FontDis15)
        bt:SetHighlightFontObject(BG.FontWhite15)
        bt:SetText(L["导出心愿"])
        bt:SetSize(bt:GetFontString():GetWidth(), 30)
        BG.SetTextHighlightTexture(bt)
        BG.ButtonExportHope = bt

        bt:SetScript("OnClick", function(self)
            BG.PlaySound(1)
            HideOtherFrame(bt.bg)

            if not self.bg then
                local sbg, scroll, child
                local bg = CreateFrame("Frame", nil, bt, "BackdropTemplate")
                do
                    bg:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                        edgeSize = 10,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 }
                    })
                    bg:SetBackdropColor(0, 0, 0, 0.8)
                    bg:SetPoint("TOPRIGHT", BG.MainFrame, "TOPRIGHT", -20, -20)
                    bg:SetSize(250, 250)
                    bg:SetFrameLevel(130)
                    bg:EnableMouse(true)
                    bg.frameName = self:GetText()
                    self.bg = bg
                    BG.frameExportHope = bg
                    tinsert(hideFrameTbl, bg)

                    local t = bg:CreateFontString()
                    t:SetFont(BIAOGE_TEXT_FONT, 15, "OUTLINE")
                    t:SetPoint("TOP", 0, -8)
                    t:SetTextColor(1, 1, 1)
                    t:SetText(bt:GetText())
                    t:SetWordWrap(false)
                end

                sbg = CreateFrame("Frame", nil, bg, "BackdropTemplate")
                do
                    sbg:SetBackdrop({
                        bgFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeFile = "Interface/ChatFrame/ChatFrameBackground",
                        edgeSize = 1,
                    })
                    sbg:SetBackdropColor(0, 0, 0, 0.8)
                    sbg:SetBackdropBorderColor(1, 1, 1, 0.5)
                    sbg:SetPoint("TOPLEFT", 8, -28)
                    sbg:SetSize(bg:GetWidth() - 16, bg:GetHeight() - 70)
                    sbg:SetFrameLevel(130)
                    self.sbg = sbg
                    scroll = CreateFrame("ScrollFrame", nil, sbg, "UIPanelScrollFrameTemplate")
                    scroll:SetPoint("TOPLEFT", 5, -4)
                    scroll:SetPoint("BOTTOMRIGHT", -27, 4)
                    scroll.ScrollBar.scrollStep = BG.scrollStep
                    BG.CreateSrollBarBackdrop(scroll.ScrollBar)
                    BG.HookScrollBarShowOrHide(scroll)

                    self.s = scroll

                    child = CreateFrame("EditBox", nil, scroll)
                    child:SetWidth(scroll:GetWidth())
                    child:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
                    child:SetMultiLine(true)
                    child:SetAutoFocus(false)
                    child:EnableMouse(true)
                    self.child = child
                    scroll:SetScrollChild(child)
                    child:SetScript("OnEscapePressed", function(self)
                        bg:Hide()
                    end)
                end

                local bt = BG.CreateButton(bg)
                do
                    bt:SetSize(110, 25)
                    bt:SetPoint("BOTTOMRIGHT", -8, 10)
                    bt:SetText(CANCEL)
                    bt:SetScript("OnClick", function(self)
                        bg:Hide()
                    end)
                end
            else
                if self.bg:IsVisible() then
                    self.bg:Hide()
                else
                    self.bg:Show()
                end
            end
            self.child:SetText(ExportHope())
            self.child:HighlightText()
            self.child:SetFocus()
            BG.SetScrollBottom(self.s, self.child)
        end)
    end
end

local function GetBossNum(itemID, FB)
    FB = FB or BG.FB1
    local diffs = BG.difficultyTable[FB]
    if not diffs then error(L["表格ID错误"]) end
    for hardIndex, hard in ipairs(diffs) do
        if BG.Loot[FB][hard] then
            local b = 1
            while BG.Loot[FB][hard]["boss" .. b] do
                for _, _itemID in ipairs(BG.Loot[FB][hard]["boss" .. b]) do
                    if BG.IsSame(itemID, _itemID) then
                        return hardIndex, b
                    end
                end
                b = b + 1
            end
        end
    end
end

-- 参数1（必选）：link。类型：string
-- 参数2（可选）：表格ID。不传参数则对当前表格添加心愿。类型：string
-- 返回：true或false，true代表心愿设置成功了。类型：boolean
-- 参数1（必选）：link。类型：string
-- 参数2（可选）：表格ID。不传参数则对当前表格添加心愿。类型：string
-- 返回：true或false，true代表心愿设置成功了。类型：boolean
function BG.SetHope(link, FB, isBiaoGe)
    if type(link) ~= "string" then error(L["物品链接类型错误，需要string类型。"]) end
    local itemID = GetItemID(link)
    if not itemID then error(L["物品链接错误，没有读取到物品ID。"]) end

    FB = FB or BG.FB1
    local n, b = GetBossNum(itemID, FB)
    if not n then
        if isBiaoGe then
            UIErrorsFrame:AddMessage(L["不能设置为心愿，因为该装备未知由哪个物品兑换"], 1, 0, 0)
            return false
        else
            error(L["该物品链接没有匹配到正确的BOSS序号。"])
        end
    end

    local charHopeDB = (BG.GetHopeDB and BG.GetHopeDB())
    if not charHopeDB and BiaoGe and BiaoGe.Hope then
        local rID = GetRealmID()
        local pName = UnitName("player") or BG.playerName or ""
        charHopeDB = BiaoGe.Hope[rID] and BiaoGe.Hope[rID][pName]
    end

    for i = 1, HopeMaxi do
        local hopeFrameExist = BG.HopeFrame and BG.HopeFrame[FB] and BG.HopeFrame[FB]["nandu" .. n] and BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]
        local hopeUI = hopeFrameExist and BG.HopeFrame[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
        local currentLink = (hopeUI and hopeUI:GetText()) or (charHopeDB and charHopeDB[FB] and charHopeDB[FB]["nandu" .. n] and charHopeDB[FB]["nandu" .. n]["boss" .. b] and charHopeDB[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i])

        if not currentLink or currentLink == "" then
            if hopeUI then
                hopeUI:SetText(link)
                hopeUI:SetCursorPosition(0)
            end
            if charHopeDB then
                charHopeDB[FB] = charHopeDB[FB] or {}
                charHopeDB[FB]["nandu" .. n] = charHopeDB[FB]["nandu" .. n] or {}
                charHopeDB[FB]["nandu" .. n]["boss" .. b] = charHopeDB[FB]["nandu" .. n]["boss" .. b] or {}
                charHopeDB[FB]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = link
            end
            if BG.ItemLibMainFrame and BG.ItemLibMainFrame:IsVisible() then
                if BG.UpdateItemLib_LeftHope_All then BG.UpdateItemLib_LeftHope_All() end
                if BG.UpdateItemLib_RightHope_All then BG.UpdateItemLib_RightHope_All() end
            end
            if BG.SetBiaoGeGuanZhu then
                BG.SetBiaoGeGuanZhu(itemID)
            end
            return true
        end
    end
    if isBiaoGe then
        UIErrorsFrame:AddMessage(L["不能设置为心愿，因为该BOSS的心愿格子已满"], 1, 0, 0)
    end
    return false
end

------------------------------------------------------------
-- 喵影 (AtlasLootMY) 配装/偏好清单联动支持 (全防御沙箱)
------------------------------------------------------------
local inMiaoYingSync = false

local function GetMiaoYingFavouritesAddon()
    local AL = _G.AtlasLootMY or _G.AtlasLoot
    if not AL or type(AL) ~= "table" then return nil end
    local Addons = AL.Addons
    if not Addons or type(Addons) ~= "table" or type(Addons.GetAddon) ~= "function" then return nil end
    local ok, fav = pcall(Addons.GetAddon, Addons, "Favourites")
    if ok and fav and type(fav) == "table" then
        return fav
    end
    return nil
end

local function IsInMiaoYingFavourites(itemID)
    if not itemID then return false end
    local numID = tonumber(itemID)
    if not numID then return false end

    -- 若用户主动关闭了喵影联动选项，则不检查 (默认开启，nil 或 1 均视为开启，只有明确为 0 才关闭)
    if BiaoGe and BiaoGe.options and BiaoGe.options["linkMiaoYingHope"] == 0 then
        return false
    end

    local fav = GetMiaoYingFavouritesAddon()
    if not fav or not fav.db or not fav.db.lists then return false end

    -- 严格角色隔离：仅检查当前角色的 Profile lists (基础列表/专属配装)，绝对不检查 globalDb (整体列表)
    for listID, listData in pairs(fav.db.lists) do
        if listData and listData[numID] then
            return true
        end
    end
    return false
end

local function RemoveFromMiaoYingFavourites(itemID)
    if not itemID then return false end
    local numID = tonumber(itemID)
    if not numID then return false end

    local fav = GetMiaoYingFavouritesAddon()
    if not fav or not fav.db or not fav.db.lists then return false end

    local removedAny = false
    -- 严格角色隔离：仅从当前角色的 Profile 列表 (基础列表) 中移除，绝不触碰整体列表 (globalDb)
    for listID, listData in pairs(fav.db.lists) do
        if listData and listData[numID] then
            listData[numID] = nil
            removedAny = true
        end
    end

    if removedAny then
        -- 若当前激活的列表正好是 Profile 列表，同步更新 activeList 和计数
        if fav.activeList and (not fav.db.activeList or fav.db.activeList[2] ~= true) and fav.activeList[numID] then
            fav.activeList[numID] = nil
            if fav.numItems and fav.numItems > 0 then
                fav.numItems = fav.numItems - 1
            end
        end
        if type(fav.CleanUpMainItems) == "function" then
            pcall(fav.CleanUpMainItems, fav)
        end
        if type(fav.UpdateDb) == "function" then
            pcall(fav.UpdateDb, fav)
        end
        if type(fav.OnItemsChanged) == "function" then
            pcall(fav.OnItemsChanged, fav)
        end
        return true
    end
    return false
end

-- 全局检索：根据物品ID在所有已注册的团本战利品表中定位所属副本、难度序号、BOSS序号
local function FindFBAndBoss(itemID)
    if not itemID then return nil end
    local numID = tonumber(itemID)
    if not numID then return nil end

    local priorityFBs = {}
    if BG.FB1 then table.insert(priorityFBs, BG.FB1) end
    if BG.FBtable then
        for _, fb in ipairs(BG.FBtable) do
            if fb ~= BG.FB1 then
                table.insert(priorityFBs, fb)
            end
        end
    end

    for _, fb in ipairs(priorityFBs) do
        local diffs = BG.difficultyTable and BG.difficultyTable[fb]
        if diffs and BG.Loot and BG.Loot[fb] then
            for hardIndex, hard in ipairs(diffs) do
                if BG.Loot[fb][hard] then
                    local b = 1
                    while BG.Loot[fb][hard]["boss" .. b] do
                        for _, _itemID in ipairs(BG.Loot[fb][hard]["boss" .. b]) do
                            local match = false
                            if BG.IsSame then
                                match = BG.IsSame(numID, _itemID)
                            else
                                match = (numID == tonumber(_itemID))
                            end
                            if match then
                                return fb, hardIndex, b
                            end
                        end
                        b = b + 1
                    end
                end
            end
        end
    end
    return nil
end

-- 检查某个物品是否已经存在于心愿单对应的 BOSS 格子中
local function IsItemAlreadyInHope(itemID, fb, n, b)
    local charHopeDB = (BG.GetHopeDB and BG.GetHopeDB())
    if not charHopeDB and BiaoGe and BiaoGe.Hope then
        local rID = GetRealmID()
        local pName = UnitName("player") or BG.playerName or ""
        charHopeDB = BiaoGe.Hope[rID] and BiaoGe.Hope[rID][pName]
    end

    for i = 1, (HopeMaxi or 3) do
        local hopeFrameExist = BG.HopeFrame and BG.HopeFrame[fb] and BG.HopeFrame[fb]["nandu" .. n] and BG.HopeFrame[fb]["nandu" .. n]["boss" .. b]
        local hopeUI = hopeFrameExist and BG.HopeFrame[fb]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
        if hopeUI and (GetItemID(hopeUI:GetText()) == itemID) then
            return true
        end
        if charHopeDB and charHopeDB[fb] and charHopeDB[fb]["nandu" .. n] and charHopeDB[fb]["nandu" .. n]["boss" .. b] then
            local dbLink = charHopeDB[fb]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
            if dbLink and (GetItemID(dbLink) == itemID) then
                return true
            end
        end
    end
    return false
end

-- 安全地将喵影装备填入 BGLite 心愿单
local function SafeSetHopeFromMiaoYing(itemID, isSilent)
    local numID = tonumber(itemID)
    if not numID then return false, "invalid_id" end

    -- 若用户主动关闭联动开关，直接返回
    if BiaoGe and BiaoGe.options and BiaoGe.options["linkMiaoYingHope"] == 0 then
        return false, "disabled"
    end

    local fb, n, b = FindFBAndBoss(numID)
    if not fb or not n or not b then
        return false, "not_raid_boss_drop"
    end

    if IsItemAlreadyInHope(numID, fb, n, b) then
        return true, "already_exists"
    end

    local _, link = GetItemInfo(numID)
    if not link then
        local item = Item:CreateFromItemID(numID)
        item:ContinueOnItemLoad(function()
            local _, loadedLink = GetItemInfo(numID)
            if loadedLink then
                SafeSetHopeFromMiaoYing(numID, isSilent)
            end
        end)
        return false, "loading"
    end

    local ok, success = pcall(BG.SetHope, link, fb, true)
    if ok and success then
        if not isSilent then
            local bossName = (BG.Boss and BG.Boss[fb] and BG.Boss[fb]["boss" .. b] and BG.Boss[fb]["boss" .. b].name2) or ("BOSS " .. b)
            local fbName = (BG.GetFBinfo and BG.GetFBinfo(fb, "shortName")) or fb
            local msg = format(L["已将 %s 自动加入心愿清单（%s - %s）。"], link, fbName, bossName)
            if BG.SendSystemMessage then
                BG.SendSystemMessage(msg)
            elseif SendSystemMessage then
                SendSystemMessage(BG.BG .. BG.STC_g1(msg))
            end
        end
        return true, "added"
    end
    return false, "failed"
end

-- 批量同步喵影【基础列表/角色专属配装】到 BGLite 心愿清单 (严格隔离整体列表)
function BG.SyncAllMiaoYingHope(isSilent)
    if BiaoGe and BiaoGe.options and BiaoGe.options["linkMiaoYingHope"] == 0 then
        if not isSilent and BG.SendSystemMessage then
            BG.SendSystemMessage(L["喵影配装联动当前处于关闭状态，请先在下方勾选开启。"])
        end
        return 0
    end

    local fav = GetMiaoYingFavouritesAddon()
    local profileLists = fav and ((fav.GetProfileLists and fav:GetProfileLists()) or (fav.db and fav.db.lists))
    if not fav or not profileLists then
        if not isSilent and BG.SendSystemMessage then
            BG.SendSystemMessage(L["未检测到喵影(AtlasLootMY)基础配装清单或未启用该插件。"])
        end
        return 0
    end

    local addedCount = 0
    local processedItems = {}

    -- 严格仅扫描当前角色的 profileLists (包含 ProfileBase 基础列表与该角色下的专属列表)，绝对不扫描 globalDb 整体列表
    for listID, listData in pairs(profileLists) do
        if type(listData) == "table" then
            for itemID, val in pairs(listData) do
                if type(itemID) == "number" and val and not processedItems[itemID] then
                    processedItems[itemID] = true
                    local ok, status = SafeSetHopeFromMiaoYing(itemID, true)
                    if ok and status == "added" then
                        addedCount = addedCount + 1
                    end
                end
            end
        end
    end

    if not isSilent then
        if addedCount > 0 then
            local msg = format(L["成功同步喵影【基础列表】至心愿清单，共新增 %d 件装备！"], addedCount)
            if BG.SendSystemMessage then
                BG.SendSystemMessage(msg)
            elseif SendSystemMessage then
                SendSystemMessage(BG.BG .. BG.STC_g1(msg))
            end
        else
            local msg = L["喵影基础列表中的团本装备已全部存在于心愿清单中。"]
            if BG.SendSystemMessage then
                BG.SendSystemMessage(msg)
            elseif SendSystemMessage then
                SendSystemMessage(BG.BG .. BG.STC_g1(msg))
            end
        end
    end
    return addedCount
end

-- 参数1（必选）：link或itemID。类型：string或number
-- 参数2（可选）：表格ID。不传参数则历遍全部表格的心愿进行匹配删除。类型：string
-- 返回：没有返回值
function BG.DeleteHope(LINKorID, FB)
    local itemID
    if type(LINKorID) == "number" then
        itemID = LINKorID
    elseif type(LINKorID) == "string" then
        itemID = GetItemID(LINKorID)
    end
    if not itemID then return end
    local FBs = FB and BG.phaseFBtable and BG.phaseFBtable[FB] or BG.FBtable
    if not FBs then return end

    local charHopeDB = (BG.GetHopeDB and BG.GetHopeDB())
    if not charHopeDB and BiaoGe and BiaoGe.Hope then
        local rID = GetRealmID()
        local pName = UnitName("player") or BG.playerName or ""
        charHopeDB = BiaoGe.Hope[rID] and BiaoGe.Hope[rID][pName]
    end

    for _, fbName in pairs(FBs) do
        for n = 1, (HopeMaxn[fbName] or 3) do
            for b = 1, (HopeMaxb[fbName] or 25) do
                for i = 1, HopeMaxi do
                    local hopeFrameExist = BG.HopeFrame and BG.HopeFrame[fbName] and BG.HopeFrame[fbName]["nandu" .. n] and BG.HopeFrame[fbName]["nandu" .. n]["boss" .. b]
                    local hopeUI = hopeFrameExist and BG.HopeFrame[fbName]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                    local dbLink = charHopeDB and charHopeDB[fbName] and charHopeDB[fbName]["nandu" .. n] and charHopeDB[fbName]["nandu" .. n]["boss" .. b] and charHopeDB[fbName]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]

                    local matched = false
                    if hopeUI and itemID == GetItemID(hopeUI:GetText()) then
                        hopeUI:SetText("")
                        matched = true
                    end
                    if dbLink and itemID == GetItemID(dbLink) then
                        matched = true
                    end
                    if matched and charHopeDB and charHopeDB[fbName] and charHopeDB[fbName]["nandu" .. n] and charHopeDB[fbName]["nandu" .. n]["boss" .. b] then
                        charHopeDB[fbName]["nandu" .. n]["boss" .. b]["zhuangbei" .. i] = nil
                    end
                end
            end
        end
    end

    -- 联动检查并移出喵影基础配装清单 (全防御沙箱 + 防递归保护 + 仅限当前角色专属列表)
    if not inMiaoYingSync and IsInMiaoYingFavourites(itemID) then
        inMiaoYingSync = true
        RemoveFromMiaoYingFavourites(itemID)
        inMiaoYingSync = false
    end
end

-- 参数1（必选）：link或itemID。类型：string或number
-- 参数2（可选）：表格ID。不传参数则历遍全部表格的心愿进行匹配。类型：string
-- 返回：true或false，true代表是心愿。类型：boolean
function BG.IsHope(LINKorID, FB)
    local itemID
    if type(LINKorID) == "number" then
        itemID = LINKorID
    elseif type(LINKorID) == "string" then
        itemID = GetItemID(LINKorID)
    end
    if not itemID then return false end
    local FBs = FB and BG.phaseFBtable and BG.phaseFBtable[FB] or BG.FBtable
    if not FBs then return false end

    local charHopeDB = (BG.GetHopeDB and BG.GetHopeDB())
    if not charHopeDB and BiaoGe and BiaoGe.Hope then
        local rID = GetRealmID()
        local pName = UnitName("player") or BG.playerName or ""
        charHopeDB = BiaoGe.Hope[rID] and BiaoGe.Hope[rID][pName]
    end

    -- 1. 原生 BGLite_Plus 心愿单判定
    for _, fbName in pairs(FBs) do
        for n = 1, (HopeMaxn[fbName] or 3) do
            for b = 1, (HopeMaxb[fbName] or 25) do
                for i = 1, HopeMaxi do
                    local hopeFrameExist = BG.HopeFrame and BG.HopeFrame[fbName] and BG.HopeFrame[fbName]["nandu" .. n] and BG.HopeFrame[fbName]["nandu" .. n]["boss" .. b]
                    local hopeUI = hopeFrameExist and BG.HopeFrame[fbName]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                    if hopeUI and BG.IsSame(itemID, hopeUI) then
                        return true
                    end

                    if charHopeDB and charHopeDB[fbName] and charHopeDB[fbName]["nandu" .. n] and charHopeDB[fbName]["nandu" .. n]["boss" .. b] then
                        local link = charHopeDB[fbName]["nandu" .. n]["boss" .. b]["zhuangbei" .. i]
                        if link and link ~= "" then
                            local dbItemID = GetItemID(link)
                            if dbItemID and (dbItemID == itemID or (BG.IsSame and BG.IsSame(itemID, dbItemID))) then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. 喵影 (AtlasLootMY) 基础配装清单联动判定 (严格角色隔离，不含整体列表)
    if IsInMiaoYingFavourites(itemID) then
        local okCount, count = pcall(GetItemCount, itemID, true)
        if okCount and count and count > 0 then
            return false
        end
        return true
    end

    return false
end

-- 实时挂钩喵影配装事件 (Alt+左键点装备 / 喵影界面收藏 / 移除)
local miaoYingHooked = false
local function HookMiaoYingEvents()
    if miaoYingHooked then return end
    local fav = GetMiaoYingFavouritesAddon()
    if not fav then return end

    if type(fav.AddItemID) == "function" and not fav._BGLite_OrigAddItemID then
        fav._BGLite_OrigAddItemID = fav.AddItemID
        fav.AddItemID = function(self, itemID, ...)
            local res = fav._BGLite_OrigAddItemID(self, itemID, ...)
            local isGlobal = (self.db and self.db.activeList and self.db.activeList[2] == true)
            -- 核心隔离约束：只有处于当前角色的基础列表/Profile列表时，才同步到心愿单；处于整体列表时不录入
            if res and not isGlobal and (not BiaoGe or not BiaoGe.options or BiaoGe.options["linkMiaoYingHope"] ~= 0) then
                SafeSetHopeFromMiaoYing(itemID, false)
            end
            return res
        end
    end

    if type(fav.RemoveItemID) == "function" and not fav._BGLite_OrigRemoveItemID then
        fav._BGLite_OrigRemoveItemID = fav.RemoveItemID
        fav.RemoveItemID = function(self, itemID, ...)
            local res = fav._BGLite_OrigRemoveItemID(self, itemID, ...)
            local isGlobal = (self.db and self.db.activeList and self.db.activeList[2] == true)
            if res and not isGlobal and (not BiaoGe or not BiaoGe.options or BiaoGe.options["linkMiaoYingHope"] ~= 0) then
                if not inMiaoYingSync then
                    inMiaoYingSync = true
                    pcall(BG.DeleteHope, itemID)
                    inMiaoYingSync = false
                end
            end
            return res
        end
    end

    miaoYingHooked = true
end

-- 创建心愿单主界面 (BG.HopeMainFrame) 上的喵影联动控件
local uiControlsCreated = false
function BG.CreateMiaoYingHopeUI()
    if uiControlsCreated then return end
    if not BG.HopeMainFrame then return end
    uiControlsCreated = true

    if BG.HopeDaoChuUI and not BG.ButtonImportHope then
        pcall(BG.HopeDaoChuUI)
    end

    local baseFrameLevel = (BG.HopeMainFrame.GetFrameLevel and BG.HopeMainFrame:GetFrameLevel()) or 100

    -- 1. 复选框：联动喵影配装 (仅基础列表)
    local cb = CreateFrame("CheckButton", "BGLite_Plus_LinkMiaoYingHopeCheckButton", BG.HopeMainFrame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", BG.MainFrame, "BOTTOMLEFT", 35, 105)
    cb:SetFrameLevel(baseFrameLevel + 15)

    local textLabel = cb.text or _G[cb:GetName() .. "Text"]
    if not textLabel then
        textLabel = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        textLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.text = textLabel
    end
    textLabel:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    textLabel:SetText(L["联动喵影配装 (仅基础列表 Alt+左键)"])
    textLabel:SetWordWrap(false)

    -- 默认开启（只要不是明确为 0，就打勾）
    local isChecked = true
    if BiaoGe and BiaoGe.options and BiaoGe.options["linkMiaoYingHope"] == 0 then
        isChecked = false
    end
    cb:SetChecked(isChecked)

    cb:SetScript("OnClick", function(self)
        local val = self:GetChecked() and 1 or 0
        BiaoGe.options = BiaoGe.options or {}
        BiaoGe.options["linkMiaoYingHope"] = val
        BG.PlaySound(1)
        if val == 1 then
            HookMiaoYingEvents()
            BG.SyncAllMiaoYingHope(false)
        end
    end)

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 5)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(BG.STC_g1(L["喵影配装与心愿单 (角色隔离联动)"]), 1, 1, 1)
        GameTooltip:AddLine(L["开启后，仅同步喵影的【基础列表】(当前角色专属配装)，绝对不会同步全账号共享的【整体列表】，确保不同角色的心愿单完全独立不混淆。"], 1, 0.82, 0, true)
        GameTooltip:AddLine(L["在喵影中激活基础列表并按住 Alt+左键 点击装备时，自动填入当前角色对应 BOSS 的心愿单。"], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["在喵影基础列表中移除或在心愿单右键清除装备时，双方也将同步移除。"], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    BG.CheckButtonLinkMiaoYing = cb

    -- 2. 按钮：一键同步喵影【基础列表】配装
    local btnSync = BG.CreateButton(BG.HopeMainFrame)
    btnSync:SetSize(130, 22)
    btnSync:SetPoint("LEFT", textLabel, "RIGHT", 15, 0)
    btnSync:SetFrameLevel(baseFrameLevel + 15)
    btnSync:SetText(L["同步基础列表配装"])
    btnSync:SetScript("OnClick", function()
        HookMiaoYingEvents()
        BG.SyncAllMiaoYingHope(false)
    end)
    btnSync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 5)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["一键同步喵影【基础列表】"], 1, 1, 1)
        GameTooltip:AddLine(L["仅扫描当前角色的喵影基础列表及本角色配装方案，批量填入本角色心愿单，不导入整体列表。"], 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    btnSync:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BG.ButtonSyncMiaoYingHope = btnSync

    -- 3. 按钮：打开喵影配装管理
    local btnOpen = BG.CreateButton(BG.HopeMainFrame)
    btnOpen:SetSize(110, 22)
    btnOpen:SetPoint("LEFT", btnSync, "RIGHT", 8, 0)
    btnOpen:SetFrameLevel(baseFrameLevel + 15)
    btnOpen:SetText(L["打开喵影配装"])
    btnOpen:SetScript("OnClick", function()
        local fav = GetMiaoYingFavouritesAddon()
        if fav and fav.GUI and fav.GUI.Toggle then
            fav.GUI:Toggle()
        else
            local msg = L["未检测到喵影(AtlasLootMY)插件或插件未开启。"]
            if BG.SendSystemMessage then
                BG.SendSystemMessage(msg)
            elseif SendSystemMessage then
                SendSystemMessage(BG.BG .. BG.STC_r1(msg))
            end
        end
    end)
    BG.ButtonOpenMiaoYingFav = btnOpen
end

-- 监听交易成功取消心愿联动
do
    local tradeHooked = false
    local function HookTradeCancel()
        if tradeHooked then return end
        if not BG.CancelGuanZhuAndHopeInTrade then return end
        tradeHooked = true

        local orig_Cancel = BG.CancelGuanZhuAndHopeInTrade
        BG.CancelGuanZhuAndHopeInTrade = function(itemID)
            if orig_Cancel then
                pcall(orig_Cancel, itemID)
            end
            if itemID and IsInMiaoYingFavourites(itemID) then
                local removed = RemoveFromMiaoYingFavourites(itemID)
                if removed then
                    local name = GetItemInfo(itemID) or ("item:" .. itemID)
                    if BG.SendSystemMessage then
                        BG.SendSystemMessage(format(L["已自动满足%s的喵影配装心愿。"], name))
                    end
                end
            end
        end
    end

    if BG.Init then
        BG.Init(HookTradeCancel)
    else
        HookTradeCancel()
    end
end

-- 整体事件驱动初始化与动态挂钩
do
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:SetScript("OnEvent", function(self, event, arg1)
        HookMiaoYingEvents()
        if BG.HopeMainFrame and BG.CreateMiaoYingHopeUI then
            BG.CreateMiaoYingHopeUI()
        end
    end)

    -- 延迟与 Tab 切换安全重试兜底
    C_Timer.After(0.2, function()
        HookMiaoYingEvents()
        if BG.HopeMainFrame and BG.CreateMiaoYingHopeUI then
            BG.CreateMiaoYingHopeUI()
        end
    end)

    if BG.ClickTabButton then
        hooksecurefunc(BG, "ClickTabButton", function(num)
            if num == (BG.HopeMainFrameTabNum or 21) then
                HookMiaoYingEvents()
                if BG.HopeMainFrame and BG.CreateMiaoYingHopeUI then
                    BG.CreateMiaoYingHopeUI()
                end
            end
        end)
    end

    -- 立即尝试首次挂钩
    HookMiaoYingEvents()
end

