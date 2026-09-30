if BG and BG.IsBlackListPlayer then return end
local AddonName, ns = ...

local RaidMap = ns.RaidMap or _G.RaidMap
if not RaidMap or not RaidMap.RegisterBoss then return end

local FB_KEY = "ULDtitan"
local FB_NAME = "奥杜尔"

--------------------------------------------------------------------------------
-- 1. 拆解者 XT-002 (Boss ID = 4)
-- 战术逻辑：单阶段。主坦在正北背靠北墙（使BOSS背对全团），近战在BOSS正背后脚跟集中输出；
-- 治疗靠近坦克与中场；远程在南半场大扇形宽幅分散（保持 10 码间距），白光跑右(东)，黑光跑左(西)。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 4,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "拆解者 XT-002",
    sub = "主坦背墙拉北面防招架 | 咆哮全团开减伤抬血 | 灼热白光向右 重力黑水向左",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m4.png",
    tacticTip = "【拆解者站位要点】\n1. 主坦在正北背靠废品堆拉怪，使 BOSS 背对全团防招架提速，近战脚后跟输出；\n2. 【震耳咆哮】为全场巨量百分比掉血(与面向无关)，读条时治疗预读、全团开大减伤覆盖；\n3. 远程与治疗大扇形严格分散 10 码以上，严禁扎堆；\n4. 点名【灼热之光】(白光)迅速向右(东)单跑，【重力炸弹】(黑水)迅速向左(西)跑出人群！",
    tbl = {
        -- 坦克 (1~2号位)
        [1] = { xy = { 374, -70 } },  -- 主坦 MT (正北靠墙)
        [2] = { xy = { 340, -80 } },  -- 副坦 ST

        -- 治疗 (3~7号位)
        [3] = { xy = { 300, -115 } }, -- 核心保坦奶骑 (主坦左翼)
        [4] = { xy = { 448, -115 } }, -- 核心保坦戒律 (主坦右翼)
        [5] = { xy = { 260, -230 } }, -- 团补 A
        [6] = { xy = { 374, -245 } }, -- 团补 B
        [7] = { xy = { 488, -230 } }, -- 团补 C

        -- 远程 DPS (8~17号位 - 南半场大扇形保持10码)
        [8]  = { xy = { 160, -280 } },
        [9]  = { xy = { 220, -305 } },
        [10] = { xy = { 280, -325 } },
        [11] = { xy = { 340, -340 } },
        [12] = { xy = { 408, -340 } },
        [13] = { xy = { 468, -325 } },
        [14] = { xy = { 528, -305 } },
        [15] = { xy = { 588, -280 } },
        [16] = { xy = { 250, -370 } }, -- 二排分散
        [17] = { xy = { 498, -370 } }, -- 二排分散

        -- 战术图元与首领标记
        [98] = {
            xy = { 374, -165 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "近战",
            isNPC_icon = "Interface\\Icons\\ability_steelmelee",
            size = 38,
        },
        [100] = {
            xy = { 374, -115 },
            isNPC = true,
            isBoss = true,
            isNPC_text = "XT-002",
            isNPC_icon = "Interface\\Icons\\achievement_boss_xt002deconstructor_01",
            size = 54,
        },
        [90] = {
            xy = { 100, -115 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "左出怪",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
            size = 34,
        },
        [91] = {
            xy = { 648, -115 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "右出怪",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
            size = 34,
        },
        [92] = {
            xy = { 180, -220 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "黑光跑左",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
            size = 32,
        },
        [93] = {
            xy = { 568, -220 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "白光跑右",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
            size = 32,
        },
    },
})

--------------------------------------------------------------------------------
-- 2. 钢铁议会 (Boss ID = 5) —— 【多阶段 2 Tabs】
-- 阶段划分：P1 三首领起手布局 -> P2 困难模式斩杀(压倒能量赴死自爆)
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 5,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "钢铁议会",
    sub = "简单:破钢->符文->唤雷 | 中等:留符文 | 困难:唤雷->符文->破钢(转P2赴死斩杀)",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m5.png",
    phases = {
        [1] = {
            name = "P1·起手站位(3种模式)",
            tacticTip = "【钢铁议会3种击杀顺序与要点】\n1. 模式选择：【简单】破钢->符文->唤雷(留唤雷最便当)；【中等】留符文最后；【困难】唤雷->符文->破钢(留破钢触发252掉落)；\n2. 三坦拉位：主坦将破钢定在北面，副坦A拉唤雷在东(远离大团)，副坦B拉符文在西；\n3. 圈色机制：出【能量符文】(蓝圈)全团进圈+50%伤害；出【死亡符文】(绿圈)坦克秒拉走、近战立刻出圈；\n4. 超载警示：唤雷者读条【超载】近战远离20码！若打困难模式请切【P2斩杀】看板！",
            tbl = {
                -- 坦克 (1~3号位 - 破钢北/唤雷东/符文西)
                [1] = { xy = { 374, -65 },  role = "tank",   desc = "主坦 MT (抗破钢者靠北墙)" },
                [2] = { xy = { 590, -125 }, role = "tank",   desc = "副坦 A (拉唤雷者在东侧)" },
                [3] = { xy = { 180, -135 }, role = "tank",   desc = "副坦 B (拉符文大师在西侧)" },

                -- 治疗 (4~7号位)
                [4] = { xy = { 320, -115 }, role = "healer", desc = "核心保坦奶骑" },
                [5] = { xy = { 428, -115 }, role = "healer", desc = "核心保坦戒律" },
                [6] = { xy = { 260, -260 }, role = "healer", desc = "团补 A" },
                [7] = { xy = { 440, -260 }, role = "healer", desc = "团补 B" },

                -- 远程 DPS (8~17号位 - 集中在中南偏西，随时踩蓝圈，远离东侧唤雷者)
                [8]  = { xy = { 180, -240 }, role = "ranged", desc = "远程输出" },
                [9]  = { xy = { 230, -250 }, role = "ranged", desc = "远程输出" },
                [10] = { xy = { 280, -260 }, role = "ranged", desc = "远程输出" },
                [11] = { xy = { 330, -265 }, role = "ranged", desc = "远程输出" },
                [12] = { xy = { 374, -280 }, role = "ranged", desc = "远程输出" },
                [13] = { xy = { 420, -280 }, role = "ranged", desc = "远程输出" },
                [14] = { xy = { 220, -320 }, role = "ranged", desc = "远程输出" },
                [15] = { xy = { 280, -330 }, role = "ranged", desc = "远程输出" },
                [16] = { xy = { 340, -340 }, role = "ranged", desc = "远程输出" },
                [17] = { xy = { 400, -340 }, role = "ranged", desc = "远程输出" },

                -- 首领与战术图元
                [100] = {
                    xy = { 374, -110 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "破钢者(简单先杀/困难留)",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_theironcouncil_01",
                    size = 52,
                },
                [101] = {
                    xy = { 550, -145 },
                    isNPC = true,
                    isNPC_text = "唤雷者(困难先杀/简单留)",
                    isNPC_icon = "Interface\\Icons\\spell_nature_lightning",
                    size = 42,
                },
                [102] = {
                    xy = { 215, -165 },
                    isNPC = true,
                    isNPC_text = "符文大师(中等留最后)",
                    isNPC_icon = "Interface\\Icons\\spell_arcane_rune",
                    size = 42,
                },
                [98] = {
                    xy = { 245, -205 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战集火区",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 290, -215 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "踩蓝圈+50%伤",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
                    size = 34,
                },
                [91] = {
                    xy = { 480, -170 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "避唤雷超载20码",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
                    size = 30,
                },
            },
        },
        [2] = {
            name = "P2·破钢斩杀(赴死)",
            tacticTip = "【P2 困难破钢斩杀要点】\n1. 压倒能量自爆：破钢者对当前坦施加【压倒能量】(+200%伤害)，倒数剩余5秒时下一棒坦必须秒嘲讽接怪！\n2. 边缘赴死献祭：中【压倒能量】坦克立刻开加速狂奔至场地边缘【赴死献祭点】自爆赴死，严禁炸大团！\n3. 全团集中嗜血：全团开嗜血在破钢者背后集中抱团踩蓝圈全力 RUSH！\n4. 极限强刷抬血：破钢者伤害逐层暴增并释放全屏大电击，治疗交全团大减伤(光环/牺牲)无脑刷血！",
            tbl = {
                -- 坦克轮换 (1号当前坦、2号换嘲接怪副坦、3号备用坦)
                [1] = { xy = { 374, -65 },  role = "tank",   desc = "主坦 (1棒吃压倒能量/5秒赴死)" },
                [2] = { xy = { 320, -75 },  role = "tank",   desc = "副坦 A (2棒接嘲讽/5秒赴死)" },
                [3] = { xy = { 428, -75 },  role = "tank",   desc = "副坦 B (3棒接嘲讽/应急抗怪)" },

                -- 核心治疗 (4~7号位 - 破钢者背后紧密抱团强刷团血)
                [4] = { xy = { 330, -180 }, role = "healer", desc = "核心治疗 (圣光大刷)" },
                [5] = { xy = { 418, -180 }, role = "healer", desc = "核心治疗 (戒律大罩/压制)" },
                [6] = { xy = { 300, -230 }, role = "healer", desc = "团补 A (大团强刷)" },
                [7] = { xy = { 448, -230 }, role = "healer", desc = "团补 B (大团强刷)" },

                -- 远程输出 (8~17号位 - 破钢者正背后集中吃嗜血与蓝圈增伤)
                [8]  = { xy = { 350, -220 }, role = "ranged", desc = "远程集火 RUSH" },
                [9]  = { xy = { 374, -230 }, role = "ranged", desc = "远程集火 RUSH" },
                [10] = { xy = { 398, -220 }, role = "ranged", desc = "远程集火 RUSH" },
                [11] = { xy = { 330, -260 }, role = "ranged", desc = "远程集火 RUSH" },
                [12] = { xy = { 374, -270 }, role = "ranged", desc = "远程集火 RUSH" },
                [13] = { xy = { 418, -260 }, role = "ranged", desc = "远程集火 RUSH" },
                [14] = { xy = { 300, -300 }, role = "ranged", desc = "远程集火 RUSH" },
                [15] = { xy = { 350, -310 }, role = "ranged", desc = "远程集火 RUSH" },
                [16] = { xy = { 398, -310 }, role = "ranged", desc = "远程集火 RUSH" },
                [17] = { xy = { 448, -300 }, role = "ranged", desc = "远程集火 RUSH" },

                -- 首领与斩杀图元
                [100] = {
                    xy = { 374, -100 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "破钢者(全力斩杀)",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_theironcouncil_01",
                    size = 56,
                },
                [98] = {
                    xy = { 374, -150 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战背后嗜血",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 38,
                },
                [90] = {
                    xy = { 374, -245 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "大团集中吃蓝圈",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
                    size = 42,
                },
                [91] = {
                    xy = { 650, -110 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "坦克赴死献祭点(东)",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
                    size = 44,
                },
                [92] = {
                    xy = { 100, -110 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "备用献祭点(西)",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
                    size = 40,
                },
                [93] = {
                    xy = { 510, -85 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "压倒能量倒数5秒狂奔",
                    isNPC_icon = "Interface\\Icons\\ability_rogue_sprint",
                    size = 34,
                },
            },
        },
    },
})

--------------------------------------------------------------------------------
-- 3. 霍迪尔 (Boss ID = 8)
-- 战术逻辑：单阶段。以场地中央【暖炉火堆】为绝对战术轴心！全团抱团取暖消除极度寒冷；
-- 雷云进火堆传导暴击，日光吃急速；闪霜大落冰前迅速站上积雪雪堆避难。
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 8,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "霍迪尔",
    sub = "以暖炉火堆为轴心抱团 | 坦拉北侧怪背对 | 踩雪避落冰 雷云进堆传电",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m8.png",
    tacticTip = "【霍迪尔站位要点】\n1. 场地中央暖炉火堆是全团生存与增伤核心，全团严密围拢在火堆10码内消除极度寒冷层数；\n2. 坦把霍迪尔定在火堆北面10码处，近战脚跟输出并蹭火堆Buff；\n3. 获【风暴之力(雷云)】点名的玩家第一时间跳入火堆人群，为所有法系传导100%暴伤；\n4. 闪霜大落冰前迅速站上积雪，切勿贪打！",
    tbl = {
        -- 坦克 (1~2号位 - 火堆北侧)
        [1] = { xy = { 374, -65 } },
        [2] = { xy = { 340, -75 } },

        -- 治疗与远程 (3~17号位 - 严密围绕中央火堆 10 码内环形抱团)
        [3]  = { xy = { 320, -170 } },
        [4]  = { xy = { 428, -170 } },
        [5]  = { xy = { 290, -210 } },
        [6]  = { xy = { 458, -210 } },
        [7]  = { xy = { 300, -250 } },
        [8]  = { xy = { 448, -250 } },
        [9]  = { xy = { 335, -270 } },
        [10] = { xy = { 413, -270 } },
        [11] = { xy = { 374, -280 } },
        [12] = { xy = { 270, -180 } },
        [13] = { xy = { 478, -180 } },
        [14] = { xy = { 255, -230 } },
        [15] = { xy = { 493, -230 } },
        [16] = { xy = { 320, -310 } },
        [17] = { xy = { 428, -310 } },

        -- 首领与战术图元
        [100] = {
            xy = { 374, -100 },
            isNPC = true,
            isBoss = true,
            isNPC_text = "霍迪尔",
            isNPC_icon = "Interface\\Icons\\achievement_boss_hodir_01",
            size = 52,
        },
        [90] = {
            xy = { 374, -215 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "火堆抱团",
            isNPC_icon = "Interface\\Icons\\spell_fire_lavaspawn",
            size = 46,
        },
        [98] = {
            xy = { 374, -150 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "近战",
            isNPC_icon = "Interface\\Icons\\ability_steelmelee",
            size = 36,
        },
        [91] = {
            xy = { 374, -180 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "雷云进堆",
            isNPC_icon = "Interface\\Icons\\spell_nature_lightning",
            size = 32,
        },
        [92] = {
            xy = { 160, -320 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "落冰踩雪",
            isNPC_icon = "Interface\\Icons\\spell_frost_frostnova",
            size = 32,
        },
    },
})

--------------------------------------------------------------------------------
-- 4. 托利姆 (Boss ID = 9) —— 【多阶段 2 Tabs】
-- 阶段划分：P1 内外场双线分兵作战 -> P2 托利姆跳入竞技场全员斩杀
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 9,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "托利姆",
    sub = "P1内外场分兵破门 | P2看墙壁立柱放电跑半场 | 8码大分散防连锁 | 失衡换坦",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m9.png",
    phases = {
        [1] = {
            name = "P1·内外场分兵",
            tacticTip = "【P1 内外场分兵要点】\n1. 外场防守大团在竞技场中央中圈集合拉怪，分散防西芙暴风雪；严禁站王座正前！\n2. 内场冲锋组迅速破门沿走廊突破，2分45秒内冲上王座击杀小怪触发托利姆跳下！",
            tbl = {
                -- 内场冲锋组 (1号副坦、3号保坦奶、8~11号突破DPS)
                [1]  = { xy = { 180, -165 } }, -- 内场副坦
                [3]  = { xy = { 150, -185 } }, -- 内场保坦奶骑
                [8]  = { xy = { 130, -220 } }, -- 内场近战/狂暴战
                [9]  = { xy = { 165, -235 } }, -- 内场盗贼
                [10] = { xy = { 120, -265 } }, -- 内场爆发远程
                [11] = { xy = { 160, -280 } }, -- 内场爆发远程

                -- 外场竞技场大团 (2号主坦、4~7号治疗、12~17号远程防守组)
                [2]  = { xy = { 480, -170 } }, -- 外场主坦
                [4]  = { xy = { 420, -210 } }, -- 外场治疗 A
                [5]  = { xy = { 540, -210 } }, -- 外场治疗 B
                [6]  = { xy = { 440, -250 } }, -- 外场治疗 C
                [7]  = { xy = { 520, -250 } }, -- 外场治疗 D
                [12] = { xy = { 380, -270 } }, -- 外场远程
                [13] = { xy = { 430, -300 } }, -- 外场远程
                [14] = { xy = { 480, -315 } }, -- 外场远程
                [15] = { xy = { 530, -300 } }, -- 外场远程
                [16] = { xy = { 580, -270 } }, -- 外场远程
                [17] = { xy = { 480, -350 } }, -- 外场远程后方

                -- 图元
                [100] = {
                    xy = { 150, -85 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "托利姆王座",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_thorim",
                    size = 46,
                },
                [90] = {
                    xy = { 200, -210 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "内场门",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
                    size = 36,
                },
                [91] = {
                    xy = { 480, -220 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "外场中圈",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
                    size = 42,
                },
                [98] = {
                    xy = { 160, -135 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "内场突破",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
            },
        },
        [2] = {
            name = "P2·竞技场斩杀",
            tacticTip = "【P2 竞技场斩杀要点】\n1. 核心致命【闪电充能】：看清外圈哪侧墙壁立柱放电，全团迅速跑往无电的另一半场规避！\n2. 全体人员(近战/远程/治疗)必须严格保持 8 码距离分散，严防【连锁闪电】串死队友！\n3. 换坦节奏：托利姆释放【失衡打击】(受物理伤害+200%)时，副坦必须秒嘲讽换坦；\n4. 困难模式防暴风雪走位，治疗秒驱散冰霜新星！",
            tbl = {
                -- 双坦 (1~2号位)
                [1] = { xy = { 460, -90 } },
                [2] = { xy = { 500, -90 } },

                -- 治疗 (3~7号位 - 竞技场中圈散开)
                [3] = { xy = { 400, -180 } },
                [4] = { xy = { 560, -180 } },
                [5] = { xy = { 380, -230 } },
                [6] = { xy = { 480, -230 } },
                [7] = { xy = { 580, -230 } },

                -- 远程 DPS (8~17号位 - 保持8码大分散，随时准备换边)
                [8]  = { xy = { 330, -260 } },
                [9]  = { xy = { 380, -280 } },
                [10] = { xy = { 430, -295 } },
                [11] = { xy = { 480, -305 } },
                [12] = { xy = { 530, -295 } },
                [13] = { xy = { 580, -280 } },
                [14] = { xy = { 630, -260 } },
                [15] = { xy = { 380, -345 } },
                [16] = { xy = { 480, -355 } },
                [17] = { xy = { 580, -345 } },

                -- 图元
                [100] = {
                    xy = { 480, -135 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "托利姆",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_thorim",
                    size = 54,
                },
                [98] = {
                    xy = { 480, -180 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 340, -220 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "西侧避雷区",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
                    size = 38,
                },
                [91] = {
                    xy = { 620, -220 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "东侧避雷区",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
                    size = 38,
                },
                [92] = {
                    xy = { 290, -135 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "西立柱看放电",
                    isNPC_icon = "Interface\\Icons\\spell_nature_lightning",
                    size = 32,
                },
                [93] = {
                    xy = { 670, -135 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "东立柱看放电",
                    isNPC_icon = "Interface\\Icons\\spell_nature_lightning",
                    size = 32,
                },
            },
        },
    },
})

--------------------------------------------------------------------------------
-- 5. 弗蕾雅 (Boss ID = 10) —— 【多阶段 2 Tabs】
-- 阶段划分：P1 小怪轮换控血与大树 -> P2 狂暴风筝大走位避自然炸弹
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 10,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "弗蕾雅",
    sub = "P1大树秒转/三怪控血/蘑菇消沉默 | P2水池风筝躲自然炸弹 | 自然之怒出人群",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m10.png",
    phases = {
        [1] = {
            name = "P1·小怪与大树",
            tacticTip = "【P1 小怪与大树要点】\n1. 主坦把弗蕾雅拉在生命温室正北水池边背对全团；副坦中场接怪；\n2. 刷新【艾欧娜尔的礼物】(回血大树)所有DPS第一优先级秒掉！\n3. 三元素小怪(水灵/树人/暴风)必须控血并在12秒内同时击杀！\n4. 古树波站健康蘑菇下消沉默，大地震颤必须停手断条！",
            tbl = {
                -- 坦克 (1~2号位)
                [1] = { xy = { 374, -65 } },  -- 主坦 MT (水池边拉弗蕾雅)
                [2] = { xy = { 320, -140 } }, -- 副坦 ST (中场聚小怪)

                -- 治疗 (3~7号位 - 扇形分散防连线)
                [3] = { xy = { 280, -180 } },
                [4] = { xy = { 468, -180 } },
                [5] = { xy = { 250, -230 } },
                [6] = { xy = { 374, -240 } },
                [7] = { xy = { 498, -230 } },

                -- 远程 DPS (8~17号位 - 南半场大分散保持10码防缠绕)
                [8]  = { xy = { 180, -270 } },
                [9]  = { xy = { 235, -295 } },
                [10] = { xy = { 290, -315 } },
                [11] = { xy = { 345, -330 } },
                [12] = { xy = { 403, -330 } },
                [13] = { xy = { 458, -315 } },
                [14] = { xy = { 513, -295 } },
                [15] = { xy = { 568, -270 } },
                [16] = { xy = { 260, -365 } },
                [17] = { xy = { 488, -365 } },

                -- 图元
                [100] = {
                    xy = { 374, -100 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "弗蕾雅",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_freya_01",
                    size = 52,
                },
                [98] = {
                    xy = { 374, -150 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 510, -140 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "秒转大树",
                    isNPC_icon = "Interface\\Icons\\spell_nature_healingtouch",
                    size = 38,
                },
                [91] = {
                    xy = { 230, -165 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "三怪控血",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
                    size = 36,
                },
                [92] = {
                    xy = { 374, -200 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "蘑菇防沉默",
                    isNPC_icon = "Interface\\Icons\\inv_mushroom_11",
                    size = 34,
                },
            },
        },
        [2] = {
            name = "P2·水池大风筝",
            tacticTip = "【P2 斩杀与风筝要点】\n1. 避开炸弹：地面密集刷新【自然炸弹】(绿球)，倒数后全场自爆，全团必须看清落点迅速走位规避！\n2. 点名跑毒：中【自然之怒】(高伤绿圈)的玩家必须第一时间向外跑出人群，严禁传染队友！\n3. 全团沿温室水池外围跟随主坦顺时针大走位风筝，边走边打，稳健斩杀！",
            tbl = {
                [1] = { xy = { 280, -90 } }, -- 主坦带位
                [2] = { xy = { 240, -110 } },
                [3] = { xy = { 330, -130 } },
                [4] = { xy = { 380, -150 } },
                [5] = { xy = { 420, -170 } },
                [6] = { xy = { 460, -190 } },
                [7] = { xy = { 500, -210 } },
                [8]  = { xy = { 310, -180 } },
                [9]  = { xy = { 350, -200 } },
                [10] = { xy = { 390, -220 } },
                [11] = { xy = { 430, -240 } },
                [12] = { xy = { 470, -260 } },
                [13] = { xy = { 510, -280 } },
                [14] = { xy = { 550, -300 } },
                [15] = { xy = { 380, -270 } },
                [16] = { xy = { 430, -300 } },
                [17] = { xy = { 480, -330 } },

                [100] = {
                    xy = { 260, -135 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "弗蕾雅",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_freya_01",
                    size = 52,
                },
                [98] = {
                    xy = { 290, -155 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战跟随",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 450, -110 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "顺时针风筝",
                    isNPC_icon = "Interface\\Icons\\spell_nature_cyclone",
                    size = 36,
                },
                [91] = {
                    xy = { 180, -180 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "避开炸弹",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
                    size = 32,
                },
                [92] = {
                    xy = { 150, -280 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "自然之怒外圈跑",
                    isNPC_icon = "Interface\\Icons\\spell_nature_elementalshields",
                    size = 34,
                },
            },
        },
    },
})

--------------------------------------------------------------------------------
-- 6. 米米尔隆 (Boss ID = 11) —— 【多阶段 4 Tabs】
-- 阶段划分：P1 烈焰战车 -> P2 激光扫射顺时针走位 -> P3 飞机头与突击怪 -> P4 三合一均血同死
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 11,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "米米尔隆",
    sub = "P1避地雷等离子 | P2顺时针转圈躲激光 | P3突击机器人转火 | P4修血同时杀",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m11.png",
    phases = {
        [1] = {
            name = "P1·烈焰战车",
            tacticTip = "【P1 战车与地雷要点】\n1. 主坦在中场偏北拉住战车背对全团，副坦注意凝固汽油抗伤；\n2. 近战脚后跟输出，严禁触碰战车排出的【感应地雷】；\n3. 远程与治疗四散站位，灭火组水球迅速灭火。",
            tbl = {
                [1] = { xy = { 374, -65 } },
                [2] = { xy = { 340, -80 } },
                [3] = { xy = { 280, -150 } },
                [4] = { xy = { 468, -150 } },
                [5] = { xy = { 250, -220 } },
                [6] = { xy = { 374, -230 } },
                [7] = { xy = { 498, -220 } },
                [8]  = { xy = { 180, -270 } },
                [9]  = { xy = { 240, -295 } },
                [10] = { xy = { 300, -315 } },
                [11] = { xy = { 360, -330 } },
                [12] = { xy = { 388, -330 } },
                [13] = { xy = { 448, -315 } },
                [14] = { xy = { 508, -295 } },
                [15] = { xy = { 568, -270 } },
                [16] = { xy = { 270, -365 } },
                [17] = { xy = { 478, -365 } },

                [100] = {
                    xy = { 374, -100 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "烈焰战车",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_mimiron_01",
                    size = 52,
                },
                [98] = {
                    xy = { 374, -150 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 420, -135 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战避地雷",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
                    size = 32,
                },
            },
        },
        [2] = {
            name = "P2·激光顺时针跑位",
            tacticTip = "【P2 激光扫射顺时针走位要点】\n1. BOSS 升上中台无仇恨！读条【P3Wx2激光弹幕】4秒后 360° 顺时针旋转喷射激光，扫到即死！\n2. 全员必须看清面向，统一按【顺时针大圈同向跑动】，严禁逆行或掉队！\n3. 平时大团分散躲避红圈火箭打击！",
            tbl = {
                -- 顺时针环形发散站位 (随时准备顺时针绕场大跑动)
                [1] = { xy = { 374, -75 } },
                [2] = { xy = { 450, -95 } },
                [3] = { xy = { 520, -145 } },
                [4] = { xy = { 550, -210 } },
                [5] = { xy = { 520, -275 } },
                [6] = { xy = { 450, -325 } },
                [7] = { xy = { 374, -345 } },
                [8]  = { xy = { 298, -325 } },
                [9]  = { xy = { 228, -275 } },
                [10] = { xy = { 198, -210 } },
                [11] = { xy = { 228, -145 } },
                [12] = { xy = { 298, -95 } },
                [13] = { xy = { 470, -170 } },
                [14] = { xy = { 470, -250 } },
                [15] = { xy = { 278, -250 } },
                [16] = { xy = { 278, -170 } },
                [17] = { xy = { 374, -380 } },

                [100] = {
                    xy = { 374, -210 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "VX-001",
                    isNPC_icon = "Interface\\Icons\\inv_gizmo_02",
                    size = 52,
                },
                [90] = {
                    xy = { 460, -135 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "顺时针跑圈",
                    isNPC_icon = "Interface\\Icons\\spell_nature_cyclone",
                    size = 40,
                },
                [98] = {
                    xy = { 374, -150 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战跟随",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
            },
        },
        [3] = {
            name = "P3·空中飞机头",
            tacticTip = "【P3 空中指挥艇与小怪要点】\n1. 飞机头在空中飞，常规近战打不到，由猎人/术士/鸟德等远程主打！\n2. 防骑在西侧拉住突击机器人背对人群；击杀后拾取【磁力核心】丢在飞机头正下方吸下来昏迷易伤，近战立刻爆发打头！\n3. 炸弹机器人远程减速风筝击杀，严防进近战自爆！",
            tbl = {
                [1] = { xy = { 374, -75 } },
                [2] = { xy = { 210, -180 } }, -- 副坦/防骑拉突击机器人
                [3] = { xy = { 260, -170 } },
                [4] = { xy = { 488, -170 } },
                [5] = { xy = { 250, -240 } },
                [6] = { xy = { 374, -260 } },
                [7] = { xy = { 498, -240 } },
                [8]  = { xy = { 180, -290 } },
                [9]  = { xy = { 240, -310 } },
                [10] = { xy = { 300, -325 } },
                [11] = { xy = { 360, -340 } },
                [12] = { xy = { 388, -340 } },
                [13] = { xy = { 448, -325 } },
                [14] = { xy = { 508, -310 } },
                [15] = { xy = { 568, -290 } },
                [16] = { xy = { 270, -370 } },
                [17] = { xy = { 478, -370 } },

                [100] = {
                    xy = { 374, -130 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "指挥艇(空中)",
                    isNPC_icon = "Interface\\Icons\\inv_misc_head_clockworkgnome_01",
                    size = 52,
                },
                [90] = {
                    xy = { 200, -145 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "突击怪坦位",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
                    size = 36,
                },
                [91] = {
                    xy = { 374, -185 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "吸怪落地点",
                    isNPC_icon = "Interface\\Icons\\spell_arcane_portalironforge",
                    size = 36,
                },
                [92] = {
                    xy = { 540, -160 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "风筝炸弹",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
                    size = 32,
                },
                [98] = {
                    xy = { 260, -140 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战小怪",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
            },
        },
        [4] = {
            name = "P4·三合一合体修血",
            tacticTip = "【P4 机械合体与修血要点】\n1. 底盘(战车)、身躯(炮台)、头部(飞机头)三合一机械合体！\n2. 终极团灭点【修血同死】：三个部位必须在15秒内同时打爆，否则满血复活！\n3. 近战主打底盘与躯干，远程主打头部并随时停手控血；依然走位躲激光与地雷！",
            tbl = {
                [1] = { xy = { 374, -65 } },
                [2] = { xy = { 340, -80 } },
                [3] = { xy = { 280, -160 } },
                [4] = { xy = { 468, -160 } },
                [5] = { xy = { 260, -230 } },
                [6] = { xy = { 374, -250 } },
                [7] = { xy = { 488, -230 } },
                [8]  = { xy = { 180, -280 } },
                [9]  = { xy = { 240, -305 } },
                [10] = { xy = { 300, -325 } },
                [11] = { xy = { 360, -340 } },
                [12] = { xy = { 388, -340 } },
                [13] = { xy = { 448, -325 } },
                [14] = { xy = { 508, -305 } },
                [15] = { xy = { 568, -280 } },
                [16] = { xy = { 270, -370 } },
                [17] = { xy = { 478, -370 } },

                [100] = {
                    xy = { 374, -115 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "V-07-TR-0N",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_mimiron_01",
                    size = 56,
                },
                [98] = {
                    xy = { 374, -165 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "近战打底盘",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 460, -145 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "远程修头部",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
                    size = 34,
                },
            },
        },
    },
})

--------------------------------------------------------------------------------
-- 7. 维扎克斯将军 (Boss ID = 12)
-- 战术逻辑：单阶段。全场无自然回蓝！近战正脚后跟严密重叠输出；
-- 远程与治疗严格分成 A/B 两组扎堆踩黑水吃急速与省蓝；暗影印记点名单人向正南(6点)狂奔！
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 12,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "维扎克斯将军",
    sub = "近战秒断灼热烈焰 | 暗影涌动坦风筝近战跟背 | 远程踩黑水省蓝 | 印记向南单跑",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m12.png",
    tacticTip = "【维扎克斯将军站位要点】\n1. 绝对打断：近战必须分配专人严格盯防秒断【灼热烈焰】，漏断直接全团易伤猝死！\n2. 风筝规避：将军开启【暗影涌动】(+100%伤害)时，坦克立刻后退风筝，近战跟随背后输出严禁去正面！\n3. 回蓝站位：远程/治疗分为A/B两堆踩【暗影废墟】(黑水)施法(-75%耗蓝/+100%急速)；\n4. 点名印记：被点名【无面者印记】的玩家必须立刻一人向正南(6点)单跑，严禁吸血灭团！",
    tbl = {
        -- 坦克 (1~2号位 - 台阶前拉怪)
        [1] = { xy = { 374, -65 } },
        [2] = { xy = { 340, -75 } },

        -- 远程与治疗 A 组 (西南抱团点 - 3, 4, 8, 9, 10, 11, 12号位)
        [3]  = { xy = { 210, -250 } }, -- A组奶骑
        [4]  = { xy = { 240, -260 } }, -- A组戒律
        [8]  = { xy = { 190, -280 } }, -- A组法系
        [9]  = { xy = { 220, -290 } }, -- A组法系
        [10] = { xy = { 250, -280 } }, -- A组法系
        [11] = { xy = { 200, -320 } }, -- A组法系
        [12] = { xy = { 240, -320 } }, -- A组法系

        -- 远程与治疗 B 组 (东南抱团点 - 5, 6, 7, 13, 14, 15, 16, 17号位)
        [5]  = { xy = { 508, -250 } }, -- B组治疗
        [6]  = { xy = { 538, -260 } }, -- B组治疗
        [7]  = { xy = { 568, -250 } }, -- B组治疗
        [13] = { xy = { 498, -280 } }, -- B组法系
        [14] = { xy = { 528, -290 } }, -- B组法系
        [15] = { xy = { 558, -280 } }, -- B组法系
        [16] = { xy = { 508, -320 } }, -- B组法系
        [17] = { xy = { 548, -320 } }, -- B组法系

        -- 首领与战术图元
        [100] = {
            xy = { 374, -100 },
            isNPC = true,
            isBoss = true,
            isNPC_text = "维扎克斯将军",
            isNPC_icon = "Interface\\Icons\\achievement_boss_generalvezax_01",
            size = 52,
        },
        [98] = {
            xy = { 374, -155 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "近战秒断跟背",
            isNPC_icon = "Interface\\Icons\\ability_steelmelee",
            size = 36,
        },
        [90] = {
            xy = { 225, -270 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "A组黑水",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
            size = 42,
        },
        [91] = {
            xy = { 533, -270 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "B组黑水",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
            size = 42,
        },
        [92] = {
            xy = { 374, -360 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "印记向南跑",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
            size = 36,
        },
        [93] = {
            xy = { 260, -85 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "暗影涌动坦风筝",
            isNPC_icon = "Interface\\Icons\\ability_rogue_sprint",
            size = 34,
        },
    },
})

--------------------------------------------------------------------------------
-- 8. 尤格萨隆 (Boss ID = 13) —— 【多阶段 3 Tabs】
-- 阶段划分：P1 炸萨拉 -> P2 内场脑房与外场救人 -> P3 疯狂背对与信标
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 13,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "尤格萨隆",
    sub = "外场大圆环分散站位 | 南侧6点进门组秒进脑房 | 背对尤格防心智归零",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m13.png",
    phases = {
        [1] = {
            name = "P1·中场撞云炸萨拉",
            tacticTip = "【P1 炸萨拉要点】\n1. 全团在中圈站位，绝对严禁踩踏扩散的绿云！\n2. 坦克把无面者小怪拉到萨拉正脚下拉爆炸伤萨拉，炸满8只进P2！",
            tbl = {
                [1] = { xy = { 374, -170 } },
                [2] = { xy = { 340, -180 } },
                [3] = { xy = { 280, -220 } },
                [4] = { xy = { 468, -220 } },
                [5] = { xy = { 250, -270 } },
                [6] = { xy = { 374, -280 } },
                [7] = { xy = { 498, -270 } },
                [8]  = { xy = { 200, -310 } },
                [9]  = { xy = { 260, -325 } },
                [10] = { xy = { 320, -340 } },
                [11] = { xy = { 374, -345 } },
                [12] = { xy = { 428, -340 } },
                [13] = { xy = { 488, -325 } },
                [14] = { xy = { 548, -310 } },
                [15] = { xy = { 280, -370 } },
                [16] = { xy = { 374, -380 } },
                [17] = { xy = { 468, -370 } },

                [100] = {
                    xy = { 374, -210 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "萨拉",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_yoggsaron_01",
                    size = 52,
                },
                [98] = {
                    xy = { 374, -150 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "小怪拉脚下炸",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
            },
        },
        [2] = {
            name = "P2·脑房与触手",
            tacticTip = "【P2 内外场双线要点】\n1. 外场呈大环形大分散，远程优先解救被大触须缠绕的队友，治疗第一时间驱散疾病；\n2. 正南6点传送门为【进门组】专属集结位，门开1秒内进脑房切触手抽大脑！\n3. 外场双坦分别在左右拉住重触手！",
            tbl = {
                -- 坦克拉重触手
                [1] = { xy = { 220, -140 } },
                [2] = { xy = { 528, -140 } },

                -- 外场治疗与远程
                [3] = { xy = { 250, -210 } },
                [4] = { xy = { 498, -210 } },
                [5] = { xy = { 210, -260 } },
                [6] = { xy = { 538, -260 } },
                [7] = { xy = { 374, -260 } },

                -- 进门组集结位 (正南 6 点)
                [8]  = { xy = { 340, -330 } },
                [9]  = { xy = { 374, -330 } },
                [10] = { xy = { 408, -330 } },
                [11] = { xy = { 340, -360 } },
                [12] = { xy = { 374, -360 } },
                [13] = { xy = { 408, -360 } },
                [14] = { xy = { 180, -310 } },
                [15] = { xy = { 568, -310 } },
                [16] = { xy = { 240, -345 } },
                [17] = { xy = { 508, -345 } },

                [100] = {
                    xy = { 374, -130 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "尤格萨隆",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_yoggsaron_01",
                    size = 54,
                },
                [90] = {
                    xy = { 374, -300 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "脑房传送门",
                    isNPC_icon = "Interface\\Icons\\spell_arcane_portalshattrath",
                    size = 42,
                },
                [98] = {
                    xy = { 374, -345 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "进门组",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
            },
        },
        [3] = {
            name = "P3·疯狂斩杀",
            tacticTip = "【P3 疯狂斩杀要点】\n1. 尤格萨隆本体破壳！读条【疯狂凝视】全团所有人必须立刻转身背对 BOSS，心智归零将被心控！\n2. 副坦拉住【不朽守护者】(信标怪)拉开击杀；全团猛抽本体斩杀！",
            tbl = {
                [1] = { xy = { 374, -75 } },
                [2] = { xy = { 520, -170 } }, -- 副坦拉信标小怪
                [3] = { xy = { 300, -160 } },
                [4] = { xy = { 448, -160 } },
                [5] = { xy = { 260, -220 } },
                [6] = { xy = { 374, -230 } },
                [7] = { xy = { 488, -220 } },
                [8]  = { xy = { 180, -270 } },
                [9]  = { xy = { 240, -290 } },
                [10] = { xy = { 300, -305 } },
                [11] = { xy = { 360, -315 } },
                [12] = { xy = { 388, -315 } },
                [13] = { xy = { 448, -305 } },
                [14] = { xy = { 508, -290 } },
                [15] = { xy = { 568, -270 } },
                [16] = { xy = { 270, -350 } },
                [17] = { xy = { 478, -350 } },

                [100] = {
                    xy = { 374, -110 },
                    isNPC = true,
                    isBoss = true,
                    isNPC_text = "尤格本体",
                    isNPC_icon = "Interface\\Icons\\achievement_boss_yoggsaron_01",
                    size = 54,
                },
                [98] = {
                    xy = { 374, -160 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "背对BOSS",
                    isNPC_icon = "Interface\\Icons\\ability_steelmelee",
                    size = 36,
                },
                [90] = {
                    xy = { 520, -210 },
                    isNPC = true,
                    isNPC_help = true,
                    isNPC_text = "信标小怪拉开",
                    isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
                    size = 36,
                },
            },
        },
    },
})

--------------------------------------------------------------------------------
-- 9. 观察者阿加隆 (Boss ID = 14)
-- 战术逻辑：单阶段。主坦在正北拉住阿加隆背靠星空，4层相位冲孔后副坦嘲讽换坦；
-- 坍缩星单点击杀，死后留黑洞；阿加隆读条【大爆炸】外场必须留坦克硬吃，其他人跳洞避难！
--------------------------------------------------------------------------------
RaidMap.RegisterBoss({
    id = 14,
    fb = FB_KEY,
    fbName = FB_NAME,
    name = "观察者阿加隆",
    sub = "主坦4层相位换坦 | 单杀坍缩星逐个爆 | 外场留坦抗大爆炸其他人进洞",
    mapTex = "Interface\\AddOns\\BGLite_Plus\\Media\\icon\\ULDtitan\\m14.png",
    tacticTip = "【阿加隆站位要点】\n1. 换坦与消层：主坦抗到 4 层【相位冲孔】副坦秒嘲讽接怪，主坦进黑洞消 Debuff；\n2. 坍缩星修血：严禁AOE！必须单点逐个击杀，每次爆炸全团大掉血，抬满血再杀下一个；\n3. 大爆炸生死规则：外场绝不可空人(否则直接全灭)！留一名坦克开大技能/无敌硬吃，全团其他人倒数2秒跳黑洞！\n4. 出洞节奏：大爆炸伤害判定后所有人立刻出洞归位，副坦将活化星宿带入黑洞消除！",
    tbl = {
        -- 坦克 (1~2号位)
        [1] = { xy = { 374, -65 } },
        [2] = { xy = { 340, -75 } },

        -- 治疗与远程 (3~17号位 - 紧贴黑洞避难点两翼)
        [3]  = { xy = { 300, -145 } },
        [4]  = { xy = { 448, -145 } },
        [5]  = { xy = { 260, -210 } },
        [6]  = { xy = { 374, -220 } },
        [7]  = { xy = { 488, -210 } },
        [8]  = { xy = { 220, -260 } },
        [9]  = { xy = { 275, -280 } },
        [10] = { xy = { 330, -295 } },
        [11] = { xy = { 374, -300 } },
        [12] = { xy = { 418, -295 } },
        [13] = { xy = { 473, -280 } },
        [14] = { xy = { 528, -260 } },
        [15] = { xy = { 260, -340 } },
        [16] = { xy = { 374, -350 } },
        [17] = { xy = { 488, -340 } },

        -- 图元
        [100] = {
            xy = { 374, -100 },
            isNPC = true,
            isBoss = true,
            isNPC_text = "阿加隆",
            isNPC_icon = "Interface\\Icons\\achievement_boss_algalon_01",
            size = 54,
        },
        [98] = {
            xy = { 374, -155 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "近战",
            isNPC_icon = "Interface\\Icons\\ability_steelmelee",
            size = 36,
        },
        [90] = {
            xy = { 374, -250 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "全员跳洞(留1坦在外)",
            isNPC_icon = "Interface\\Icons\\spell_shadow_twilight",
            size = 44,
        },
        [91] = {
            xy = { 560, -220 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "副坦风筝星宿",
            isNPC_icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
            size = 34,
        },
        [92] = {
            xy = { 374, -30 },
            isNPC = true,
            isNPC_help = true,
            isNPC_text = "外场吃大爆炸位",
            isNPC_icon = "Interface\\Icons\\spell_holy_divineintervention",
            size = 34,
        },
    },
})
