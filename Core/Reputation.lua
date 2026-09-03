if BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local L = ns.L
local LibBG = ns.LibBG

local player = UnitName("player")
local realmID = GetRealmID()

local Rep = {}
ns.Reputation = Rep

-- 延迟防抖时间（秒）：有多慢就多慢，交物资/刷怪时累积 10 秒后才合并且只执行一次
local DEBOUNCE_DELAY = 10
-- 登入游戏后延迟初次扫描时间（秒）：完全避开登录加载高峰期
local INITIAL_DELAY = 30

local timerHandle = nil
local pendingCombatUpdate = false

-- 核心安全存储函数
local function DoSaveReputation()
    if InCombatLockdown() then
        pendingCombatUpdate = true
        return
    end

    if not BG.factionTbl or #BG.factionTbl == 0 then
        return
    end

    BiaoGe = BiaoGe or {}
    BiaoGe.bag = BiaoGe.bag or {}
    BiaoGe.bag[realmID] = BiaoGe.bag[realmID] or {}
    BiaoGe.bag[realmID][player] = BiaoGe.bag[realmID][player] or {}
    BiaoGe.bag[realmID][player].faction = BiaoGe.bag[realmID][player].faction or {}

    local currentFactionDB = BiaoGe.bag[realmID][player].faction
    local hasChanges = false

    for _, ID in ipairs(BG.factionTbl) do
        local name, description, standingID, barMin, barMax, barValue = GetFactionInfoByID(ID)
        if name and standingID then
            local curVal = barValue - barMin
            local maxVal = barMax - barMin
            local old = currentFactionDB[ID]

            if not old or old.standingID ~= standingID or old.currentValue ~= curVal or old.maxValue ~= maxVal then
                currentFactionDB[ID] = {
                    name = name,
                    standingID = standingID,
                    currentValue = curVal,
                    maxValue = maxVal,
                    factionID = ID,
                }
                hasChanges = true
            end
        end
    end

    -- 若有变动且总览面板当前可见，则安全轻量刷新显示
    if hasChanges and BG.FBCDFrame and BG.FBCDFrame:IsVisible() and BG.SetFBCD then
        if BG.FBCDFrame.click then
            pcall(BG.SetFBCD, nil, nil, true, true)
        else
            pcall(BG.SetFBCD, BG.FBCDFrame.lastSelf, BG.FBCDFrame.lastPosition)
        end
    end
end

-- 超长防抖请求（有多慢就多慢）
local function RequestReputationUpdate(delay)
    if timerHandle then
        timerHandle:Cancel()
        timerHandle = nil
    end

    local waitSec = delay or DEBOUNCE_DELAY
    timerHandle = C_Timer.NewTimer(waitSec, function()
        timerHandle = nil
        if InCombatLockdown() then
            pendingCombatUpdate = true
        else
            DoSaveReputation()
        end
    end)
end

-- 公共 API 接口
function Rep.SaveReputation(force)
    if force then
        DoSaveReputation()
    else
        RequestReputationUpdate(DEBOUNCE_DELAY)
    end
end

function Rep.GetReputation(factionID, targetPlayer, targetRealmID)
    local p = targetPlayer or player
    local r = targetRealmID or realmID
    if BiaoGe and BiaoGe.bag and BiaoGe.bag[r] and BiaoGe.bag[r][p] and BiaoGe.bag[r][p].faction then
        return BiaoGe.bag[r][p].faction[factionID]
    end
    return nil
end

function Rep.GetAllReputations(targetPlayer, targetRealmID)
    local p = targetPlayer or player
    local r = targetRealmID or realmID
    if BiaoGe and BiaoGe.bag and BiaoGe.bag[r] and BiaoGe.bag[r][p] and BiaoGe.bag[r][p].faction then
        return BiaoGe.bag[r][p].faction
    end
    return nil
end

-- 事件监听与生命周期管理
local function InitReputationModule()
    if Rep.hasInited then return end
    Rep.hasInited = true

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_FACTION")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_FACTION" then
            -- 战斗中绝不计算，只记脱战待办
            if InCombatLockdown() then
                pendingCombatUpdate = true
                return
            end
            -- 非战斗中，触发 10 秒超长防抖合并更新
            RequestReputationUpdate(DEBOUNCE_DELAY)
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- 脱战后，如果有累积未办的声望更新，延迟 5 秒再执行
            if pendingCombatUpdate then
                pendingCombatUpdate = false
                RequestReputationUpdate(5)
            end
        end
    end)

    -- 首次进入游戏后，超长延迟 30 秒才进行第一次静默采样
    C_Timer.After(INITIAL_DELAY, function()
        if InCombatLockdown() then
            pendingCombatUpdate = true
        else
            DoSaveReputation()
        end
    end)
end

ns.InitReputationModule = InitReputationModule

if IsLoggedIn() then
    InitReputationModule()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        InitReputationModule()
    end)
end
