if BG and BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local RaidMap = ns.RaidMap or _G.RaidMap
if not RaidMap or not RaidMap.RegisterBoss then return end

local FB_KEY = "ULDtitan"
local FB_NAME = "奥杜尔"

--------------------------------------------------------------------------------
-- 1. 拆解者 XT-002 (Boss ID = 4)
-- 战术逻辑：主坦在正北背靠北墙（使BOSS背对全团），近战在BOSS正背后脚跟集中输出；
-- 保坦治疗（奶骑/戒律牧）靠近主坦两翼 20 码，防止发光炸弹/重力炸弹与全团互炸；
-- 远程在南半场大扇形宽幅分散（保持 10 码间距），白光跑右(东)，黑光跑左(西)，两侧为废料出怪口。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 4,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m4.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "拆解者 XT-002",
    sub = "主坦背墙拉北面 | 近战正背后 | 远程南半场大分散 | 白光跑右 黑光跑左",
    tacticTip = "【拆解者站位要点】\n1. 主坦在 12 点正北背靠北墙拉怪，使 BOSS 背对全团，避免正面震耳发聩AOE；\n2. 保坦奶（奶骑/戒律）靠近坦克两翼 20 码，道标与牺牲无死角覆盖；\n3. 近战集中在 BOSS 正背后 6 点脚后跟输出；\n4. 远程与团补在南半场大扇形分散保持 10 码；\n5. 点名发光炸弹(白光)迅速向右侧(东)跑出人群，重力炸弹(黑光)迅速向左侧(西)跑出人群！",
    targets = {
        { type = "boss", name = "XT-002 拆解者", iconTex = "Interface\\Icons\\achievement_boss_xt002deconstructor_01", relX = 0, relY = 90, size = 52, color = { 1, 0.25, 0.25 } },
        { type = "npc",  name = "左废料出怪点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", relX = -240, relY = 110, size = 36, color = { 0.2, 1, 0.3 } },
        { type = "npc",  name = "右废料出怪点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = 240, relY = 110, size = 36, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "重力炸弹(黑光跑左)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", relX = -200, relY = -110, size = 34, color = { 0.8, 0.3, 1 } },
        { type = "npc",  name = "发光炸弹(白光跑右)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = 200, relY = -110, size = 34, color = { 1, 1, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 45,
            tankHealerLeft = { x = -75, y = 125 }, -- 核心保坦治疗紧贴主坦左翼 20 码
            tankHealerRight = { x = 75, y = 125 }, -- 核心保坦治疗紧贴主坦右翼 20 码
            rangedMode = "arc", -- 南半场大扇形大分散 (保持 10 码间距防黑白光互炸)
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 2. 钢铁议会 (Boss ID = 5)
-- 战术逻辑：破钢者拉正北靠墙，副坦拉唤雷者在东侧（防超载AOE），副坦拉符文大师在西侧；
-- 保坦治疗紧跟主坦防止融化；远程踩蓝色增伤符文，出绿色死亡符文全员后撤。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 5,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m5.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "钢铁议会",
    sub = "破钢拉北面 | 唤雷拉东侧防超载 | 蓝圈踩增伤 绿圈后撤",
    tacticTip = "【钢铁议会站位要点】\n1. 主坦将破钢者定在北侧靠墙；\n2. 保坦奶在主坦侧后方 20 码，融化之拳第一时间给压制与大光；\n3. 副坦A拉住唤雷者在东侧远离人群（读条超载时全团20码规避）；\n4. 副坦B拉符文大师在中偏西，近战先集中集火，出蓝色增伤符文全团踩入增加50%伤害；\n5. 出绿色死亡符文全团迅速向后撤退风筝。",
    targets = {
        { type = "boss", name = "破钢者 (大)", iconTex = "Interface\\Icons\\achievement_boss_ironcouncil_01", relX = 0, relY = 90, size = 50, color = { 1, 0.2, 0.2 } },
        { type = "boss", name = "唤雷者 (中)", iconTex = "Interface\\Icons\\spell_nature_lightning", relX = 180, relY = 40, size = 42, color = { 1, 0.6, 0.2 } },
        { type = "boss", name = "符文大师 (小)", iconTex = "Interface\\Icons\\spell_arcane_rune", relX = -130, relY = 50, size = 42, color = { 0.3, 0.8, 1 } },
        { type = "npc",  name = "增伤蓝圈踩圈位", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = -50, relY = 0, size = 32, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "超载规避警戒线", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = 120, relY = -10, size = 30, color = { 1, 0.3, 0.3 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 140, -- 三大首领分立拉开
            tankHealerLeft = { x = -75, y = 125 },
            tankHealerRight = { x = 75, y = 125 },
            rangedMode = "arc", -- 中南侧内圈扇形包围，距离唤雷者至少 25 码
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 3. 霍迪尔 (Boss ID = 8)
-- 战术逻辑：以场地正中【暖炉火堆】为绝对战术轴心！坦克将霍迪尔拉在火堆北侧背对火堆；
-- 近战背后贴身吃火；远程与治疗围绕火堆抱团取暖解冷冻层数；雷云点名直接进火堆传电！
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 8,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m8.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "霍迪尔",
    sub = "以暖炉火堆为轴心抱团 | 坦拉北侧怪背对 | 踩雪避落冰 雷云进堆传电",
    tacticTip = "【霍迪尔站位要点】\n1. 场地中央暖炉火堆是全团生存与增伤核心，全团严密围拢在火堆 10 码内消除极度寒冷层数；\n2. 坦把霍迪尔定在火堆北面 10 码处，近战脚跟输出并蹭火堆 Buff；\n3. 获【风暴之力(雷云)】点名的玩家第一时间跳入火堆人群，为所有法系传导 100% 暴伤；\n4. 闪霜大落冰前迅速站上积雪，切勿贪打！",
    targets = {
        { type = "boss", name = "霍迪尔 (冰霜之王)", iconTex = "Interface\\Icons\\achievement_boss_hodir_01", relX = 0, relY = 90, size = 52, color = { 0.4, 0.8, 1 } },
        { type = "npc",  name = "暖炉火堆(全团抱团核心)", iconTex = "Interface\\Icons\\spell_fire_lavaspawn", relX = 0, relY = 0, size = 44, color = { 1, 0.5, 0.1 } },
        { type = "npc",  name = "西侧解冻萨满法师", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = -200, relY = 50, size = 32, color = { 0.3, 1, 0.4 } },
        { type = "npc",  name = "东侧解冻德鲁伊牧师", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", relX = 200, relY = 50, size = 32, color = { 0.3, 1, 0.4 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 150, -- 坦在火堆北侧面对霍迪尔
            meleeY = 45, -- 近战在火堆与霍迪尔之间
            tankHealerLeft = { x = -50, y = 110 },
            tankHealerRight = { x = 50, y = 110 },
            rangedMode = "campfire", -- 围绕火堆 10 码内环形排列取暖
            campfirePos = { x = 0, y = 0 },
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 4. 弗蕾雅 (Boss ID = 10)
-- 战术逻辑：生命温室大分散站位，主坦拉BOSS在正北水池边，副坦中场拉小怪波次；
-- 远程南半场大范围分散（距离 10 码以上）防止铁根缠绕和太阳光束连线；大树礼物第一时间全团转火。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 10,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m10.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "弗蕾雅",
    sub = "主坦水池拉北边 | 全团多层大分散防连线 | 秒转大树礼物 控血三元素",
    tacticTip = "【弗蕾雅站位要点】\n1. 主坦把弗蕾雅拉在生命温室正北水池边，背对人群；\n2. 全体远程与治疗在南半场大范围分散开，每人间距保持 10 码以上，严禁扎堆；\n3. 刷新【艾欧娜尔的礼物】所有 DPS 第一时间秒掉，否则 BOSS 持续巨幅回血；\n4. 三元素小怪组（水灵、树人、风暴）必须控血同时 10 秒内击杀，否则互相复活。",
    targets = {
        { type = "boss", name = "弗蕾雅", iconTex = "Interface\\Icons\\achievement_boss_freya_01", relX = 0, relY = 95, size = 52, color = { 0.2, 1, 0.4 } },
        { type = "npc",  name = "艾欧娜尔的礼物(秒转)", iconTex = "Interface\\Icons\\inv_misc_herb_01", relX = -130, relY = -20, size = 38, color = { 1, 0.9, 0.2 } },
        { type = "npc",  name = "三元素小怪控血点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", relX = 130, relY = -20, size = 36, color = { 0.2, 0.8, 1 } },
        { type = "npc",  name = "铁根缠绕救人空地", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", relX = 0, relY = -120, size = 32, color = { 0.8, 0.3, 1 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 160,
            meleeY = 35,
            tankSpread = 50,
            tankHealerLeft = { x = -75, y = 125 },
            tankHealerRight = { x = 75, y = 125 },
            rangedMode = "arc", -- 生命温室南半场大范围分散防连线
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 5. 米米尔隆 (Boss ID = 11)
-- 战术逻辑：创造之厅灭火四象限站位！全团划分为东南、西南、东北、西北 4 个小队象限；
-- 顺时针躲激光弹幕；P3 打空中指挥艇，防骑拉近战小怪，远程风筝自爆机器人；P4 三合一平均血量。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 11,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m11.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "米米尔隆",
    sub = "创造之厅四象限分散 | 顺时针跑激光扫射 | P3风筝炸弹 P4控血同死",
    tacticTip = "【米米尔隆救火站位要点】\n1. 全场划分为东南、西南、东北、西北 4 个象限，各小队严格在各自区域分散，严禁扎堆；\n2. P2 激光弹幕读条时，全团按顺时针大圈同向跑动；\n3. P3 空中指挥艇由术士/猎人打下，近战小怪副坦拉住，地雷机器人猎人风筝；\n4. P4 头部、躯干、底盘三部分必须在 15 秒内同时击杀，否则互相满血复活！",
    targets = {
        { type = "boss", name = "米米尔隆 (机甲合体)", iconTex = "Interface\\Icons\\achievement_boss_mimiron_01", relX = 0, relY = 60, size = 52, color = { 1, 0.4, 0.1 } },
        { type = "npc",  name = "顺时针激光规避箭头", iconTex = "Interface\\Icons\\spell_nature_cyclone", relX = 100, relY = 130, size = 36, color = { 1, 0.8, 0.2 } },
        { type = "npc",  name = "P3 突击机器人集中坦位", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = -140, relY = -20, size = 34, color = { 0.3, 0.8, 1 } },
        { type = "npc",  name = "P3 灭火机器人风筝通道", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", relX = 140, relY = -20, size = 34, color = { 0.8, 0.9, 1 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 140,
            meleeY = 15,
            tankSpread = 50,
            tankHealerLeft = { x = -75, y = 110 },
            tankHealerRight = { x = 75, y = 110 },
            rangedMode = "arc", -- 环形发散排布
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 6. 维扎克斯将军 (Boss ID = 12)
-- 战术逻辑：极度严格的经典“两组集中抱团、近战卡位、绝不乱站”！
-- 主坦北侧拉背靠楼梯，近战正后方重叠不吃印记；远程分为 A/B 两组严密重叠站一个点吃黑水急速增益；
-- 被点名无面印记者单独往正南空地快跑，绝不波及人群！
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 12,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m12.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "维扎克斯将军",
    sub = "主坦北侧背靠台阶 | 远程分为A/B两堆抱团踩黑水 | 点名印记单独往南跑",
    tacticTip = "【维扎克斯将军站位要点】\n1. 全场无自然回蓝！远程必须踩萨隆邪铁黑水(+100%急速, -75%耗蓝)；\n2. 远程与治疗绝对禁止自由散开！必须严格分为 A 组（西南）与 B 组（东南）两个重叠点！\n3. 近战严格重叠在将军正脚后跟输出，绝对不出圈；\n4. 任何远程被点名【无面者的印记】，立即一人单独向正南(6点钟)空地狂奔，严禁传染抱团点！",
    targets = {
        { type = "boss", name = "维扎克斯将军", iconTex = "Interface\\Icons\\achievement_boss_generalvezax_01", relX = 0, relY = 100, size = 52, color = { 0.6, 0.2, 0.9 } },
        { type = "npc",  name = "远程A组黑水抱团点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", relX = -130, relY = -90, size = 42, color = { 1, 0.9, 0.2 } },
        { type = "npc",  name = "远程B组黑水抱团点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", relX = 130, relY = -90, size = 42, color = { 1, 0.5, 0.1 } },
        { type = "npc",  name = "无面印记单人排毒通道(往南)", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = 0, relY = -150, size = 36, color = { 1, 0.2, 0.2 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 165,
            meleeY = 45,
            tankSpread = 40,
            tankHealerLeft = { x = -65, y = 130 },
            tankHealerRight = { x = 65, y = 130 },
            rangedMode = "two_groups", -- 严格 A/B 两组扎堆踩黑水 (西南与东南)
            groupA = { x = -130, y = -90 },
            groupB = { x = 130, y = -90 },
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 7. 尤格萨隆 (Boss ID = 13)
-- 战术逻辑：P1 萨拉中场撞云；P2 外场大环形分散（防疾病与缠绕）；
-- 南侧正门（6点钟）为进门组专属集结位，门开瞬间近战全员进脑房！外场坦拉大触手，法系集火小触手。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 13,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m13.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "尤格萨隆",
    sub = "外场大圆环分散站位 | 南侧6点进门组秒进脑房 | 背对尤格防心智归零",
    tacticTip = "【尤格萨隆站位要点】\n1. 外场必须呈大环形向外散开，绝不能扎堆，避免疾病与抓人触手同时减员；\n2. 南侧 6 点钟是大脑传送门核心集结点，进门组近战在此集合，门开 1 秒内进脑房切触手；\n3. 外场坦分别在 10 点与 2 点拉住重触手；\n4. 读条【疯狂凝视】全团必须立刻转头背对尤格萨隆，心智归零将被心控！",
    targets = {
        { type = "boss", name = "萨拉 / 尤格萨隆本体", iconTex = "Interface\\Icons\\achievement_boss_yoggsaron_01", relX = 0, relY = 50, size = 56, color = { 0.9, 0.2, 0.3 } },
        { type = "npc",  name = "脑房传送门(进门组集结点)", iconTex = "Interface\\Icons\\spell_arcane_portalshattrath", relX = 0, relY = -120, size = 42, color = { 0.8, 0.3, 1 } },
        { type = "npc",  name = "西侧重触手坦克点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", relX = -190, relY = 70, size = 36, color = { 1, 0.5, 0.2 } },
        { type = "npc",  name = "东侧重触手坦克点", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = 190, relY = 70, size = 36, color = { 0.2, 0.8, 1 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 120,
            meleeY = -100, -- 进门组（近战）严格在正南 6 点钟传送门处集结
            tankSpread = 140,
            tankHealerLeft = { x = -80, y = 70 },
            tankHealerRight = { x = 80, y = 70 },
            rangedMode = "arc", -- 外场大圆环大分散
        }, rosterData)
    end,
})

--------------------------------------------------------------------------------
-- 8. 观察者阿加隆 (Boss ID = 14)
-- 战术逻辑：主坦在正北拉住阿加隆背靠星空；副坦外围风筝活化星宿；
-- 远程与治疗在后场弧形散开，紧挨坍缩星黑洞，大爆炸读条全员跳黑洞避难！
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 14,
    hasRealMap = true,
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m14.png",
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "观察者阿加隆",
    sub = "主坦北侧拉怪背对 | 4层相位换坦 | 紧邻黑洞 大爆炸全员跳洞避难",
    tacticTip = "【观察者阿加隆站位要点】\n1. 主坦在北侧拉住阿加隆使其背对全团，相位冲撞 4 层副坦立刻嘲讽换坦；\n2. 击杀坍缩星会在地面留下一处黑洞，远程与近战必须紧靠黑洞边缘战斗；\n3. 阿加隆读条 8 秒【大爆炸】时，除自保坦外，全员必须在倒计时 2 秒前跳入黑洞进入暗影界避难；\n4. 爆炸结束立刻出洞，副坦带好活化星宿风筝进黑洞消除！",
    targets = {
        { type = "boss", name = "观察者阿加隆", iconTex = "Interface\\Icons\\achievement_boss_algalon_01", relX = 0, relY = 95, size = 54, color = { 0.3, 0.8, 1 } },
        { type = "npc",  name = "大爆炸黑洞避难点", iconTex = "Interface\\Icons\\spell_shadow_twilight", relX = 0, relY = -40, size = 42, color = { 0.7, 0.4, 1 } },
        { type = "npc",  name = "副坦风筝活化星宿通道", iconTex = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", relX = 180, relY = -40, size = 34, color = { 0.4, 0.9, 1 } },
    },
    buildSpots = function(cx, cy, width, height, rosterData)
        return RaidMap.GenerateDynamicTacticalSpots(cx, cy, {
            tankY = 165,
            meleeY = 35,
            tankSpread = 40,
            tankHealerLeft = { x = -70, y = 125 },
            tankHealerRight = { x = 70, y = 125 },
            rangedMode = "arc", -- 紧靠黑洞避难点两翼
        }, rosterData)
    end,
})
