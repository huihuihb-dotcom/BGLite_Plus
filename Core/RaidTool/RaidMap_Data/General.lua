if BG and BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local RaidMap = ns.RaidMap or _G.RaidMap
if not RaidMap or not RaidMap.RegisterBoss then return end

--------------------------------------------------------------------------------
-- 通用战术板 (General Board)
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 0,
    fb = "GENERAL",
    fbName = "通用板",
    name = "通用圆形战术板",
    sub = "全版本通用圆形竞技场",
    useProceduralGrid = true,
    targets = {
        {
            type = "boss",
            name = "BOSS 目标",
            iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            relX = 0,
            relY = 90,
            size = 48,
            color = { 1, 0.2, 0.2 },
        },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, nil, rosterData)
    end,
})
