-- ============================================================================
-- BGLite_Plus: Core\ClearProtect.lua
-- 模块职责：
-- 1. 修复合体多副本（如时光服 P5双本 SWtitan: 祖阿曼 1~7 / 太阳井 8~13；
--    WLK NAXX/黑曜石/蓝龙；CTM 暮光/黑翼血环/风神等）在新CD进本时被一刀切整表清空的恶性 Bug。
-- 2. 重建并增强 IsNotSameTeam 算法，精准判定同团连打活动。
-- 3. 严格贯彻“数据隔离原则”与“子副本干净免清空原则”：
--    - 若当前进入的子副本无脏数据，且同表其他副本有账目：完全跳过清空，100%保护已有账目。
--    - 若当前进入的子副本有旧残留，且同团连打：仅清空当前子副本对应的 Boss 槽位，绝不越界误杀。
-- 4. 拦截并平滑替换原版误导性的清空黄字提示与音效，消除团长恐慌。
-- ============================================================================

local AddonName, ns = ...
local L = ns.L or {}
local BG = BG

-- 1. 团队一致性判定 (还原并增强原版 IsNotSameTeam)
local function IsNotSameTeam(FB)
    FB = FB or BG.FB1
    if not IsInRaid(1) then
        return true, "不在团队里"
    end
    if not (BiaoGe and BiaoGe[FB] and BiaoGe[FB].raidRoster and BiaoGe[FB].raidRoster.roster) then
        return true, "表格无历史成员名单"
    end
    -- 记录超过 24 小时 (86400秒)
    if GetServerTime() - (BiaoGe[FB].raidRoster.time or 0) >= 86400 then
        return true, "表格成员记录已超过24小时"
    end
    -- 服务器不同
    if BG.realmName and BiaoGe[FB].raidRoster.realm and BG.realmName ~= BiaoGe[FB].raidRoster.realm then
        return true, "服务器不同"
    end
    local currentRoster = BG.raidRosterInfo or {}
    local historyRoster = BiaoGe[FB].raidRoster.roster or {}
    local maxCount = math.max(#currentRoster, #historyRoster)
    if maxCount == 0 then
        return true, "名单为空"
    end

    local sameCount = 0
    for _, vv in ipairs(currentRoster) do
        for _, name in ipairs(historyRoster) do
            if vv.name == name then
                sameCount = sameCount + 1
                break
            end
        end
    end
    if (sameCount / maxCount) < 0.6 then
        return true, "团队成员重合度低于60%"
    end
    return false
end
BG.IsNotSameTeam = BG.IsNotSameTeam or IsNotSameTeam

-- 2. 检查指定 Boss 区间是否存在记账数据（装备/买家/金额/关注/欠款）
local function HasDataInRange(FB, startB, endB)
    if not (FB and BiaoGe and BiaoGe[FB] and BG.Frame and BG.Frame[FB]) then return false end
    for b = startB, endB do
        if BG.Frame[FB]["boss" .. b] then
            local maxi = (BG.GetMaxi and BG.GetMaxi(FB, b)) or BG.Maxi or 22
            for i = 1, maxi do
                local f = BG.Frame[FB]["boss" .. b]
                if f["zhuangbei" .. i] and f["zhuangbei" .. i]:GetText() ~= "" then return true end
                if f["maijia" .. i] and f["maijia" .. i]:GetText() ~= "" then return true end
                if f["jine" .. i] and f["jine" .. i]:GetText() ~= "" then return true end
                if BiaoGe[FB]["boss" .. b] and (BiaoGe[FB]["boss" .. b]["guanzhu" .. i] or BiaoGe[FB]["boss" .. b]["qiankuan" .. i]) then return true end
            end
        end
    end
    return false
end

-- 3. 手动清空与网络接收标记（放行手动与网络覆盖）
if StaticPopupDialogs and StaticPopupDialogs["QINGKONGBIAOGE"] then
    local orig_OnAccept = StaticPopupDialogs["QINGKONGBIAOGE"].OnAccept
    StaticPopupDialogs["QINGKONGBIAOGE"].OnAccept = function(...)
        BG._isManualClearingBiaoGe = true
        local ok, res = pcall(orig_OnAccept, ...)
        BG._isManualClearingBiaoGe = nil
        if not ok then error(res) end
        return res
    end
end

-- 4. 抑制原版进本自动清空成功消息与音效
local suppressAutoClearNotice = false
local suppressNoticeText = nil

local orig_SendSystemMessage = BG.SendSystemMessage
BG.SendSystemMessage = function(msg, ...)
    if suppressAutoClearNotice and msg and string.find(msg, "已自动清空表格") then
        suppressAutoClearNotice = false
        if suppressNoticeText then
            local notice = suppressNoticeText
            suppressNoticeText = nil
            return orig_SendSystemMessage(notice, ...)
        end
        return
    end
    return orig_SendSystemMessage(msg, ...)
end

local orig_PlaySound = BG.PlaySound
BG.PlaySound = function(sound, ...)
    if suppressAutoClearNotice and sound == "qingkong" then
        return
    end
    return orig_PlaySound(sound, ...)
end

-- 5. 核心拦截：Hook BG.ClearBiaoGe 接管进本自动清空
BG.Init3(function()
    local orig_ClearBiaoGe = BG.ClearBiaoGe
    if not orig_ClearBiaoGe then return end

    BG.ClearBiaoGe = function(_type, FB, ...)
        if _type ~= "biaoge" or not FB then
            return orig_ClearBiaoGe(_type, FB, ...)
        end

        -- 手动清空或非副本中 -> 尊重用户操作，直接放行
        if BG._isManualClearingBiaoGe or not IsInInstance() then
            return orig_ClearBiaoGe(_type, FB, ...)
        end

        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        local curFB = BG.FBIDtable and BG.FBIDtable[instanceID]

        -- 如果并非当前所在副本对应的表格 -> 放行
        if not curFB or curFB ~= FB then
            return orig_ClearBiaoGe(_type, FB, ...)
        end

        local range = BG.bossPositionStartEnd and BG.bossPositionStartEnd[instanceID]
        local maxB = (BG.Maxb and BG.Maxb[FB]) or (ns.Maxb and ns.Maxb[FB]) or 20

        -- 判定是否为合体副本中的子副本（其 Boss 区间仅为整表的一部分）
        local isSubRaid = range and (range[1] > 1 or range[2] < (maxB - 1))
        if not isSubRaid then
            -- 普通单副本，按原版自动清空逻辑放行
            return orig_ClearBiaoGe(_type, FB, ...)
        end

        local startB, endB = range[1], range[2]

        -- 检查当前子副本区间是否有记账数据
        local curSubHasData = HasDataInRange(FB, startB, endB)

        -- 检查同表其它 Boss 区间是否有记账数据
        local otherSubHasData = false
        for b = 1, maxB do
            if (b < startB or b > endB) and HasDataInRange(FB, b, b) then
                otherSubHasData = true
                break
            end
        end

        local sameTeam = not IsNotSameTeam(FB)

        -- 场景 1：连打免清空（当前子副本无数据，同表其他副本有账目）
        -- 典型例子：打完太阳井(8~13)进祖阿曼(1~7)，祖阿曼是干净的
        if not curSubHasData and otherSubHasData then
            suppressAutoClearNotice = true
            suppressNoticeText = string.format(
                "|cff00BFFF[BGLite+]|r 检测到同表多副本连打，已自动保护 < %s > 中已有副本账目（已安全跳过自动清空）。",
                BG.GetFBinfo(FB, "shortName") or FB
            )
            -- 返回分钱人数以匹配上游返回类型契约
            return (BG.GetFBinfo(FB, "maxplayers") or 25)
        end

        -- 场景 2：同团连打局部清空（当前子副本有旧残留，同表其他副本有当前团的有效账目，且为同团连打）
        -- 典型例子：祖阿曼以前打过留了旧账，打完太阳井进祖阿曼，只清空祖阿曼 1~7
        if curSubHasData and otherSubHasData and sameTeam then
            if BG.ClearBiaoGeByIndex then
                for b = startB, endB do
                    BG.ClearBiaoGeByIndex(FB, b)
                end
            end
            suppressAutoClearNotice = true
            suppressNoticeText = string.format(
                "|cff00BFFF[BGLite+]|r 检测到同团连打，仅自动清空当前副本（Boss %s-%s）旧记录，同表其他副本账目已完整保留。",
                startB, endB
            )
            return (BG.GetFBinfo(FB, "maxplayers") or 25)
        end

        -- 场景 3：整表全新重置（新团全新开荒 / 换团新CD）
        return orig_ClearBiaoGe(_type, FB, ...)
    end
end)
