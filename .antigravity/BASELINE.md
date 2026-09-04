# BGLite_Plus 项目基准文档 (BASELINE.md)

## 1. 项目简介
- **项目名称**: BGLite_Plus (BiaoGe Plus - 魔兽世界怀旧服/时光服/正式服金团表格及辅助工具插件)
- **支持版本**: 经典旧世 (Vanilla / SoD)、燃烧的远征 (TBC)、巫妖王之怒 (WLK)、泰坦时光服 (Titan)、大地的裂变 (CTM)、熊猫人之谜 (MOP)、正式服 (Retail)

## 2. 核心架构与模块
- `BGLite_Plus.toc`: 插件入口及加载文件列表。
- `README.md`: 完整的用户与开发者说明文档。
- `Locales/`: 本地化语言包 (`zhCN.lua`, `zhTW.lua` 等)。
- `Core/RoleOverview.lua`: 角色总览界面及数据配置（团本CD、日常任务、专业CD、声望、货币统计）。
- `Core/RoleOverview_core.lua`: 角色总览核心渲染与逻辑。
- `Core/RoleOverviewSort.lua` & `Core/RoleOverviewOptions.lua`: 角色总览排序与选项设置。
- `Core/Hope.lua`: 心愿清单与装备监控。
- `Core/ItemLib.lua`: 物品库与装备数据。
- `Core/RaidTool.lua`: 团队工具/通报等。
- `Core/WhoHistory.lua`: O键角色查询历史记录侧边栏与名单导出。
- `Core/TeamInfo.lua`: 团队 YY 频道与招募通告追踪、右侧抽屉侧边栏。

## 3. 角色总览货币列表与自定义设置
- **默认配置调整**: 时光服（Titan）模式下，已将【双倍经验】（`xp`）调整为**默认开启显示**；将货币 `161`（岩石守卫者碎片）与 `1901`（荣誉点数）调整为**默认不显示**，并通过 `BG.Once` 清洗了历史本地缓存，保证即时生效。
- **自定义功能支持**: 在 `RoleOverviewOptions.lua` 中已实现【货币与物品显示自定义队列】，玩家可在设置中随时按需勾选或隐藏任意货币（双倍经验、泰坦余烬、泰坦碎片、金币、橙武等）。
- **时光服默认团本显示调整 (2026-09-02)**:
  - 针对时光服（Titan）模式，已将【黑曜石】（`OStitan`）、【永恒之眼】（`EOEtitan`）、【毒蛇神殿】（`SSCtitan`）、【风暴要塞】（`TKtitan`）调整为**默认开启显示**。
  - 通过 `BG.Once` 清洗了历史本地缓存，保证现有存档及新安装玩家无需手动重置即可即时默认展示。
## 4. 团队工具 (RaidTool) 核心机制与近期优化
* **进组自动密语与团队发言：仅团长/管理生效安全机制 (2026-09-02)**：
  * **背景问题**：此前玩家开启“自动密语新进队成员”或“自动在团队/小队频道发言”后，自己进入他人所开团队时，一旦有新人进团或产生进队系统消息，也会自动向新进队员发送密语或团队通知，造成误发与打扰。
  * **解决方案**：
    1. 在【新进成员自动通知】标题右侧新增复选框【仅团长/助理】（`notifyOnlyLeader`，默认开启）。
    2. 引入权限判定 `IsLeaderOrAssistant()`（校验 `UnitIsGroupLeader("player")` 与 `UnitIsGroupAssistant("player")`）。
    3. 在 `CHAT_MSG_SYSTEM` 事件监听及 `SendNewMemberNotification` 触发与延时发送前双重校验：当处于非队长且非团长/助理身份时，自动彻底拦截密语与团队发言，杜绝进别人团时的误发。

* **语音/YY号/DD全频道识别与安全超链接 (2026-09-02)**：
  * **机制**：通过 `ChatFrame_AddMessageEventFilter` 监听全频道聊天消息，自动识别语音/YY/DD/KOOK/VX号并转为魔兽点击超链接。
  * **修复与增强**：
    1. **平台标签保持一致 (DD/KOOK/YY)**：识别喊话中的 `DD` 时超链接精准展示为 `[DD 123456]`，避免此前所有语音统一写死变成 `[YY ...]` 的问题，同时复制弹窗与 Alt+点击广播同步识别并显示对应平台（如 `DD 频道号` / `请进DD语音频道：123456`）。
    2. **超链接防第三方破坏屏障 (彻底杜绝 `BGLiteCop[YY:...]` 乱码)**：
       - **病根定位**：第三方插件（或原版 BiaoGe `YY.lua`）在后续过滤器中盲目使用 `[yY]+%s*(%d+)` 正则二次扫整条消息，把已生成的 `BGLiteCopyYY:xxx` 中的 `yYY:` 切断为 `BGLiteCop`，并把显示文字 `[YY xxx]` 二次包围成 `[[YY:xxx]]`。
       - **解决策略**：
         a. 协议前缀全面升级为中性安全前缀 `garrmission:BGVoice_<TAG>_<NUM>`，杜绝包含任何易被正则命中的关键词；
         b. 显示文本采用管道颜色打断设计 `[%s|r|cff00BFFF %s]`（如 `[DD|r|cff00BFFF 38233332]`）：魔兽客户端原生渲染为完全连贯的单体超链接，但在底层物理打断了任意第三方插件对“字母+空格+纯数字”的粗暴正则表达式扫描，实现**100%免疫外部第三方插件的二次污染与乱码破坏**，完全无需外部插件做任何改动。
    3. 增强括号识别与吸收逻辑（支持中英文方括号 `[]` `【】` 及圆括号 `()` `（）`），杜绝玩家输入中括号时的多重嵌套 `[[YY xxxx]]` 格式破坏。
    4. 强化防重复过滤机制，已包含超链接的消息跳过二次处理。

* **团队阵容管理：实时自动同步 + 纯粹方块 Tab 预设栏 (2026-09-02)**：
  * **机制**：支持 40 人小队网格拖拽调队、跨队自动升团、一键应用到当前团队。
  * **全自动实时同步**：事件监听 `GROUP_ROSTER_UPDATE`、`RAID_ROSTER_UPDATE`、`PARTY_MEMBERS_CHANGED`，团队/队伍来人、退人、离队或在游戏内调队时，面板打开即**实时自动同步刷新**，无需手动点击。
  * **界面精简重构**：
    1. **移除清空网格**：不再提供冗余的手动清空网格按钮，网格始终自动贴合当前/预设阵容。
    2. **顶部核心操作栏**：仅保留【同步当前团队】、【保存为预设】（弹窗输入名称保存）、【应用此阵容】（一键调队）。
    3. **底部纯粹方块 Tab 预设展示栏**：移除杂乱操作按钮，下方整片区域用于平铺展示保存好的方块 Tab。
    4. **快捷交互与自愈恢复**：
       - 左键点击 Tab 直接载入阵容并高亮；Alt+左键点击覆盖保存当前网格；右键点击直接删除该预设。
       - **职业与名字全持久化**：预设数据同步持久化保存玩家姓名与职业（Class Color），脱离队伍或跨服离线加载也能完整着色。
       - **开窗智能恢复**：非团队状态下打开面板时，自动恢复并展示上次选中的预设方案，无需反复点击载入。
       - **保存弹窗预填**：点击【保存为预设】时，弹窗输入框自动预填当前选中的预设名称，便于一键覆盖或修改。
       - **记忆上次退出 Tab**：点击小地图图标或重新打开主面板时，自动记忆并恢复上次退出的 Tab 界面（如装备库/心愿单/团队工具/表格），不再强制重置回第一个表格 Tab。

* **O键角色查询历史记录与名单导出 (2026-09-02)**：
  * **侧边栏自动注入**：按下 O 键打开官方【查询】（`WhoFrame`）时，自动在查询框右侧显示“查询记录”黑底侧边栏。
  * **搜索记录持久化**：每次在官方输入框输入名字按回车或点查询时，自动保存至 `BiaoGe.whoFrame.history` 并写入 WTF。
  * **快捷交互**：左键点击历史项自动填入并直接查询；右键点击从历史中移除。
  * **名单导出**：右上角配备【导出名单】按钮，可一键批量导出当前 `/who` 结果。
  * **设置开关与布局**：在【插件设置 - 角色总览】中新增【O键角色查询记录侧边栏】开关复选框（左侧），并将【角色总览缩放比例】滑块移至右侧（快捷键下方），双列排版更加整齐匀称。

## 5. 团队 YY 频道与招募通告追踪模块 (TeamInfo) (2026-09-02)
* **模块定位**: `Core/TeamInfo.lua`，提供当前团队 YY 频道与招募通告的自动化采集、多条时序持久化展示、团长变更追踪、右侧抽屉侧边栏与一键带时间戳导出。
* **数据采集与过滤机制**:
  1. **集结号（MeetingHorn）直读与 MHH 协议原生解码**: 
     - 进组时自动检索集结号各层级活动缓存；
     - 监听公共频道集结号原生广播（`MHH@团长.活动名.说明`），自动解码为 `[集结号] 《活动名》 说明`。
  2. **公共频道 15 分钟滑动窗口缓存池**: 结合时光服专属特征词库（风剑/橙锤/片/包/百元/均分/速推/TN硬补/恶鱼工具/432/TOC/NAXX/SW/ZAM/合剂/考核等）与 YY 正则反查团长喊话。
  3. **严苛语义特征引擎 (`IsValidRecruitOrRuleMessage`)**: 彻底拦截网易有爱、大脚等插件自动入队欢迎语（`<有爱提示>...`）及普通闲聊，仅收录包含实质开团规则、YY号或时光服关键词的有效通告。
  4. **团长换人时序追踪 (`Leader Change Tracking`)**: 实时监听团队领袖变更，自动追加 `[时间] [团队变动] 团长由 <旧团长> 变更为: <新团长>`，并自动针对新团长重新检索 YY 与通告。
* **右侧抽屉侧边栏 (Side Drawer) + 顶部控制按钮架构**:
  - **顶部入口按钮**: 在主框架顶部【拍卖记录】旁边增加绿色文字按钮 `[团队信息]`，点击随时平滑展开/收起右侧抽屉面板。
  - **右侧抽屉侧边栏**: 挂载在主框架右侧边缘（宽 340，高 480），彻底解放底部空间，装备过滤图标 100% 毫无遮挡！
  - **完整通告滚动列表**: 面板主体内置带滚动条的多条通告卡片，每条清晰展示 `[时间] [来源] 正文`，右键点击单条可直接复制到聊天框。
  - **三态视觉指示器**:
    1. **状态 1：进本前 / 组队未绑定态**: 翠绿边框，显示 `[当前队伍(未绑定)]`，配备橙色 `[绑定开团]` 按钮与 `[抓取]` 按钮；
    2. **状态 2：已进本 / 表格已绑定态**: 亮蓝边框，显示 `[TOC已绑定]`，进本时自动固化或点击绑定开团固化到 `BiaoGe[FB].teamInfo`；
    3. **状态 3：单人查账 / 历史存档态**: 暗灰边框，显示 `[TOC存档]`，只读展示该副本历史记录。
* **Reload 零丢失与全状态持久化自愈**:
  - `TeamInfo.currentGroupData` 双向同步至 `BiaoGe.currentGroupData`；
  - 只要 `BiaoGe[FB].teamInfo` 存在数据，重载游戏或重登后自动识别为已绑定状态并完美还原所有历史通告，杜绝重载丢失。

## 6. 角色总览技能点自定义与满级过滤细分 (2026-09-02)
* **副职业技能点自定义显示**:
  * 在设置界面新增【专业与生活技能显示自定义队列】，支持玩家按需勾选【主专业】（0）、【钓鱼】（356）、【烹饪】（185）、【急救】（129）及【考古学】（794）。
  * 支持【全部勾选】与【恢复默认】（默认仅展示主专业），即时刷新角色总览面板。
  * `Core/RoleOverview.lua` 完善了技能名称的本地化安全回退机制，确保各版本客户端下准确显示技能名。
* **装备栏位扩展（主副手武器、戒指、套装、项链披风）**:
  * **机制**: `BiaoGe.equip` 针对每个角色已全量采集保存了 1～19 全部位装备（包含 link、itemID、quality、iLevel）。
  * **新增可选列**:
    1. **武器** (`weapons`): 主手 (16) + 副手 (17) + 远程/圣物 (18)。
    2. **饰品** (`trinkets`): 饰品1 (13) + 饰品2 (14)。
    3. **戒指** (`rings`): 手指1 (11) + 手指2 (12)。
    4. **套装** (`tier`): 头部 (1) + 肩部 (3) + 胸部 (5) + 手套 (10) + 腿部 (7)。
    5. **项链/披风** (`neck_back`): 颈部 (2) + 披风 (15)。
  * **渲染引擎升级**: `RoleOverview_core.lua` 将原单一的 `CreateTrinkets` 升级为通用的 `CreateEquipIcons(t_paizi, equip, slots, isNewUI)`，自适应栏位图标渲染与悬浮装等角标。
* **满级角色过滤设置精确定义与资源面板细分**:
  * **准确重定义原有开关**: 将原有设置 `roleOverviewOnlyFullLevel` 精准定义为【CD展示仅显示满级角色】，明确其仅作用于团本 CD 列表的满级过滤。
  * **新增资源面板满级过滤**: 新增设置 `roleOverviewResOnlyFullLevel`【资源面板仅显示满级角色】（默认关闭为 0），开启后金币、货币与技能点等资源列表仅展示满级角色，关闭时低等级小号依然在资源列表中统计展示。
  * **设置界面排版优化**: 将基础开关重新规范为双列对齐排版，使 CD/资源/阵营/天赋/Buff/查询侧边栏/快捷键/缩放比例层次清晰匀称。
* **角色排序设置完整接入 (2026-09-02)**:
  * 在【插件设置 - 角色总览】基础开关第 5 行接入【排序方式：】下拉选择框与【修改排序】按键。
  * 完美集成 6 大排序模式：装等-职业-名字、职业-装等-名字、装等-名字、职业-名字、纯名字及自定义拖拽排序。
  * 选择【自定义排序】时动态呼出【修改排序】按钮，一键打开 `BGRoleOverviewSortFrame` 鼠标自由拖拽换位窗口，拖动实时保存并刷新总览面板。

## 7. 历史账单完整功能与 TeamInfo 联合存储机制 (2026-09-03)
* **模块定位**: `Core/History.lua`，完全独立于 BGLite 基础包，为玩家提供完整的历史账单存储、多快照管理、只读查看、一键应用还原与进本自动归档撤回能力。
* **TeamInfo 联合存储与自愈还原**:
  1. **保存历史 (Manual Save / Auto Archive)**：在 `BG.SaveBiaoGe(FB)` 归档当前 BOSS 装备、买家、金额、欠款、交易与拍卖记录的同时，深度拷贝当前副本搭载的 `BiaoGe[FB].teamInfo` 至 `BiaoGe.History[FB][DT].teamInfo`。
  2. **应用历史 (Apply History)**：点击【应用】按钮一键将历史快照数据完整还原到当前活跃表格，并同步还原 `BiaoGe[FB].teamInfo`，自动触发 `TeamInfo.UpdateUI()` 即时刷新右侧抽屉面板。
  3. **历史查账联动 (History Archive Viewing)**：
     - 点击下拉菜单中的历史账单条目进入只读历史模式（`BG.HistoryMainFrame`）；
     - `TeamInfo.GetCardState()` 智能检测当前处于历史模式，自动读取该历史快照中的 `teamInfo` 并以状态 3（只读历史存档态）在右侧抽屉展示当时的 YY 与招募时序通告；
     - 点击【返回】退出历史模式后，自动恢复展示当前队伍/表格的实时通告。
* **历史账单下拉菜单交互与渲染规范**:
  - 顶部右上角常驻【历史表格（N个）】下拉按钮与【保存】按钮；
  - 下拉列表展示历史时间与总人数/工资概要，支持单项点击查看、ALT+左键改名、ALT+右键删除单项、底部一键清空该副本全部历史。
  - **装备历史价格走势图模块 (2026-09-03)**：
    - 完整接入 `BG.GetHistoryMoney`、`BG.SetHistoryMoney` 与 `BG.HideHistoryMoney`；
    - 自动化为所有常规表格和历史表格的装备框注入 `OnEnterDelay` / `OnLeaveDelay` 悬停 Hook（在登录、切本、打开界面时动态挂载）；
    - 当鼠标在表格任意装备上悬停时，右下角自动弹出带有渐变彩色柱状图的【装备历史价格走势图】，展示该装备近 15 次在不同日期的成交日期、买家名字/职业着色与成交金额。
  - **保存与渲染完全 1:1 对标原版 BiaoGe 标准实现 (2026-09-03)**：
    - 在文件顶层完整声明 `GetMaxb(FB)`，确保保存、创建、回填与列表渲染各环节调用零报错；
    - `BG.SaveBiaoGe(FB)` 严格 1:1 对齐原版 BiaoGe 标准实现，精准读取 `BG.Maxb[FB]`，并联合存储 `teamInfo`；
    - 所见即所得将 `BG.Frame[FB]["boss" .. BG.Maxb[FB] + 2]` 中的人数与工资金额存入标题，彻底杜绝多余猜测；
    - 杂项与支出栏只读框严格挂载至对应的 `scrollFrame` 子框架，由 ScrollFrame 自动裁切超出视口的行，彻底杜绝多余格子溢出到总览下方；
    - 总览与工资栏严格限制为 5 行，固定显示粉色【总收入/总支出/净收入】与天蓝色【分钱人数/人均工资】，金额与项目完美对齐。
* **进本自动归档与一键撤回**:
  - 监听并支持进本清空前自动将原账单归档为历史表格1；
  - 聊天框附带 `[撤回清空]` 超链接，点击一键恢复历史表格1数据并删除临时存档。

## 8. 角色总览副本简称与 TeamInfo 拍卖过滤优化 (2026-09-03)
* **角色总览副本简称支持 (Role Overview Short Names)**:
  - 在 `Core/RoleOverview.lua` 为全版本全副本（SoD/60/TBC/WLK/Titan/CTM/MOP/Retail）定义了标准紧凑简称 `shortName`（如 SW、TOC、NAXX、OS、EOE、SSC、TK、MC、宝库、ULD、ICC、RS、BT、HS、GL、ML、KZ、TAQ、AQL、BWL、DS、FL、SOO 等）。
  - 在 `Core/RoleOverviewOptions.lua` 基础设置第 4 行右侧新增【显示副本简称】复选框（`roleOverviewShortName`，默认关闭/否），位于【快捷键：】设置正上方。
  - 在 `Core/RoleOverview_core.lua` 中升级表头宽度自适应计算，开启时表头显示紧凑简称，自动压缩列宽，显著减少横向视口占用。
* **TeamInfo 金团拍卖与升级噪音深度过滤**:
  - 在 `NOISE_KEYWORDS` 黑名单中扩充 `"拍卖开始"`、`"流拍"`、`"建议升级"` 等关键字，彻底拦截金团拍卖插件的打本喊话与装备建议。
  - 从 `RULE_EXTRA_KEYWORDS` 规则词库中移除 `"流拍"`，避免金团流拍被误判为开团规则。
  - 在 `AddRecruitEntry` 中增加进栈前多重噪音过滤防御。
  - **当前数据容量确认**：团队信息通告池每个副本与组队状态严格保存 **100 行** 历史通告（超出自动循环淘汰首条）。
* **全局 Tab 与副本切换常驻联动机制 (2026-09-03)**:
  - **顶部按钮常驻**：将 `TeamInfo.topBtn` 层级提升至 `(MainFrame:GetFrameLevel() + 35)`，并在切换底部 Tab（表格/对账/装备库/心愿单/团队工具/设置等）及各副本 Tab 时始终保持显示与顶层可见。
  - **右侧抽屉框体常驻**：深度 Hook `BG.ClickTabButton`、`BG.UpdateAuctionLogFrame` 及 `BG.MainFrame:OnShow`，当开启右侧团队信息时，切换任意 Tab 均与左侧拍卖记录保持 1:1 同步常驻在右侧，高度自适应当前主界面，彻底消除切 Tab 时抽屉丢失或隐藏的问题。

* **「交易记录」模块完整搬运至 BGLite_Plus (2026-09-03)**:
  - **功能确认**：原版 BiaoGe 完整具备【交易记录】功能，包含：
    1. 自动监听玩家间交易事件（`TRADE_ACCEPT_UPDATE`、`UI_INFO_MESSAGE` 交易成功/取消/背包满等）；
    2. 记录交易发生时间、地点、交易双方角色名与职业着色、我方交出物品/金钱、对方交出物品/金钱、交易前后财产等；
    3. 具备多服/多角色下拉筛选、买家搜索过滤、按时间/地点双向排序、保留时长自定义清理（3/7/15/30天/永久）、以及点击单条弹出详细对账明细框（`ShowTradeHistoryInfo`）与单条右键删除等能力。
  - **模块化搬迁**：已在 `BGLite_Plus/Core/TradeHistory.lua` 中建立独立完整模块，并在 `BGLite_Plus.toc` 中完成注册。
  - **Tab 入口对齐**：底部 Tab 栏严格按照规范位于【对账】右侧、【邮件记录】左侧，在 `BGLite` / `BGLite_Plus` 启动时自动呈现。
  - **界面纯净优化**：左下角原本跳转设置的【交易选项设置】按钮已安全注释保留，面板保持极简清晰。

* **团队工具字号与视觉对齐优化 (2026-09-03)**:
  - 排查发现团队工具此前部分控件 hardcode 写入了 `11 ~ 12` 像素小字号，导致比交易列表（基准 `13 ~ 15`）视觉偏小。
  - 已系统性将左侧复选框、密语/发言输入框、预设管理弹窗及右侧 40人阵列小队队员姓名统一提升至 **`13 ~ 14`** 像素，标题提升至 **`15 ~ 16`** 像素，与交易记录、表格及全插件字号体系完美对齐。
* **角色总览设置默认勾选状态修复 (2026-09-03)**:
  - 修复了 `CreateCheckButton` 内部无默认值时盲目 fallback 为 `true` 的问题，建立了严格的 `defaultOptionsMap` 映射表。
  - 确保【显示副本简称】（`roleOverviewShortName`）**默认关闭/不勾选（0）**，仅在用户主动点击勾选时生效。
* **团队信息留存面板标题润色 (2026-09-03)**:
  - 将侧边栏标题从「团队信息与招募通告」优化为「**团队关键信息留存**」，更贴合团本开团规则、喊话存证与对账保障的业务定位。
* **角色总览多快捷斜杠命令与冲突解决 (2026-09-03)**:
  - 针对其他插件（如 Baganator 等背包/战场插件）可能抢占 `/bgr` 的情况，注册了更独特、好记的专属别名命令：
    - **`/bgcd`**（推荐，副本CD/角色总览）
    - **`/bgrole`**（角色总览）
    - **`/bgzl`**（总览拼音首字母）
    - **`/bgliter`**
    - 同时加入冲突清除逻辑保留 `/bgr`。
* **主菜单右下角新增【CD总览】按钮注入 (2026-09-03)**:
  - 在主界面右下角【通报：】文字左侧自适应挂载【CD总览】按钮（`BG.ButtonRoleOverview`）。
  - 完美布局：**`[ CD总览 ]`** `通报：` `[ 账单 ]` `[ 流拍 ]` `[ 消费 ]` `[ 欠款 ]` `[ 通报频道 ▾ ]`，左侧功能区与右侧通报区层次分明，零遮挡、零越界。
  - 点击直接呼出/关闭角色CD总览面板，具备悬停说明与专属命令指引。
* **团队工具 UI 重构与高度截断预留 (2026-09-03)**:
  - **高度截断预留空间**：将双面板高度统一截断为 `470px`（左面板 345x470，右面板 610x470），在主容器底部整齐留出 `70~90px` 的扩展开发区域，方便后续在此挂载新的扩展条与新功能模块。
  - **全方位字号与控件升级**：
    - 主标题统一升级为 **`18`** 像素；
    - 所有复选框（自动邀请/公会限制/转团队/进组通知/YY转换）尺寸扩至 `20x20`，字号提升至 **`14`** 像素；
    - 所有输入框高度由 `22` 扩至 `24~25`，输入字号提升至 **`14`** 像素；
    - 40 人小队网格队员槽位高度由 `20` 提升至 **`23`**，名字字号全面升级至 **`14`** 像素（职业染色粗体高亮）；
    - 顶部操作按钮升级至 `110x26`（**`14`** 像素），底部预设 Tab 按钮升级至 `26px` 高度（**`14`** 像素）。
  - **默认预设历史一次性清洗与升级迁移 (2026-09-03)**：
    - 借助 `BG.Once("RaidTool_PresetHistory_v105")` 机制，在用户升级到 1.0.5 时自动执行一次旧数据向新默认预设（如 DD/YY进组话术）的平滑刷新，执行后打上版本标记，确保后续用户自定义增删预设完全保留且永不被重复覆盖。
* **职业筛选即时生效与过滤引擎接管修复 (2026-09-03)**:
  - **故障成因**:
    1. **Key 不一致**: `BGLite/function2.lua` 和 `ItemLib.lua` 使用带服全称 `BG.playerName`（如 `"波比兔-席瓦莱恩"`），而 `FilterClassItem.lua` 和 `DB_FilterClassItem.lua` 使用了短名 `UnitName("player")`（如 `"波比兔"`），导致点击修改的方案与底层读取的表完全失联；
    2. **闭包引用固化**: `BGLite/function2.lua` 在加载时内部闭包 `local db` 提前执行并将 `chooseID` 强制设为 `nil`，后续无法被外部更新；
    3. **装备库未即时联动重算**: 界面停留在装备库时，`BG.UpdateAllFilter()` 未主动触发 `UpdateItemLib()` 重算列表。
  - **修复与架构实施 (保持 BGLite 绝对只读)**:
    1. **统一数据源与双向映射**: 建立 `BG.GetFilterClassItemDB()`，自动处理短名与带服全名的双向 table 引用指针同步，无论任何历史代码按哪个 key 读取均能获取同一份实时数据；
    2. **接管重写过滤引擎**: 在 `BGLite_Plus/Core/FilterClassItem.lua` 末尾完整重写 `BG.FilterAll`、`BG.FilterItem`、`BG.UpdateFilter` 和 `BG.UpdateAllFilter`，彻底摆脱上游只读依赖中的死锁闭包；
    3. **毫秒级联动刷新**: 点击方案按钮时，方案号实时写入，`BG.UpdateAllFilter()` 同步刷新表格变灰、心愿清单变灰、并在装备库处于显示状态时立即重新过滤装备列表并更新顶部方案名称与件数统计，彻底告别 reload。
* **表格装备悬停 GameTooltip 与历史价格走势图同步展示修复 (2026-09-03)**:
  - **故障成因**:
    - 在接入常规表格历史价格走势图 Hook 时，直接对装备格 `bt` 调用了 `BG.OnEnterDelay(bt, ...)`；
    - 上游依赖 `BGLite/function1.lua` 的 `OnEnterDelay` 在未传 `isHook=true` 时直接采用 `self:SetScript("OnEnter", ...)` 覆盖原有脚本；
    - 注入回调中仅调用了 `BG.SetHistoryMoney`，未调用原生 `GameTooltip:SetHyperlink` 和 `GameTooltip:Show`，导致原生的装备属性/装等浮窗与底色高亮被彻底冲掉抹杀。
  - **修复实施**:
    - 在 [History.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/History.lua) 常规表格装备格悬停回调中，完整补充原生装备 Tooltip 绘制链路（`GameTooltip:SetOwner`、`GameTooltip:SetHyperlink`、`BG.SetZUGSetTooltip` 以及 `BG.FrameDs` 底色高亮）；
    - 鼠标悬停时：**鼠标处即时弹出完整的魔兽原生装备属性 Tooltip，右下角同步弹出带有渐变彩色柱状图的历史价格走势图**；移出时两者同步关闭，双浮窗完美协同共存。
* **历史表格详情右侧团队信息面板直显优化 (2026-09-03)**:
  - **故障成因**:
    - 点开历史表格详情（`BG.HistoryMainFrame:Show()`）时，`FBMainFrame` 被隐藏（Hide）；
    - 原 `FBMainFrame` 的 `OnHide` 钩子无条件调用了 `SafeHide(ns.TeamInfo.sideFrame)`，导致右侧团队信息面板被联动关闭；
    - 虽在底层刷新了历史快照数据，但由于面板已处于隐藏状态，玩家必须手动再次点击顶栏【团队信息】按钮才会出现。
  - **修复实施**:
    - 在 [Init.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/Init.lua) 的 `FBMainFrame:HookScript("OnHide")` 中增加豁免判断：若当前正在查看历史表格（`BG.HistoryMainFrame:IsShown()`），则不隐藏团队信息面板；
    - 在 [History.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/History.lua) 的 `HistoryMainFrame` `OnShow` 及点击历史列表项载入详情时，显式调用 `ns.TeamInfo.sideFrame:Show()` 与 `ns.TeamInfo.UpdateUI()`，确保右侧团队信息面板直接展开并呈现该历史账单快照留存的团队数据（YY号、团长、招募记录）；
    - 退出历史表格时（点击【返回】），恢复常规活跃表格的团队信息面板显隐与数据状态。
* **交易记录 Tab 按钮恢复与生命周期自启动修复 (2026-09-03)**:
  - **故障成因**:
    1. **BGLite 上游裁剪切断 UI 入口**: `BGLite/Core/BiaoGe.lua` 在创建完交易记录 Tab 按钮后，上游作者为了精简而显式调用了 `bt:Hide()`，并将其从 `BG.tabButtons` 锚点链表直接 `tremove`，切断了底部 Tab 栏的点击与展示入口；
    2. **生命周期队列错过失效**: `BGLite_Plus/Core/TradeHistory.lua` 底部调用了 `BG.Init(InitTradeHistoryModule)`，但 `BGLite` 的 `BG.Init` 回调队列早在 `BGLite` 自身的 `ADDON_LOADED` 事件期间就已经执行完毕并注销了事件。作为后加载模块的 `TradeHistory.lua` 把函数塞入队列后**从未被触发执行**，导致交易记录的事件监听未注册、UI 与滚动列表从未初始化；
    3. **增强包集成遗漏**: `Init.lua` 中未将 `TradeHistory` 纳入增强模块初始化与 `ClickTabButton` 显隐调度体系。
  - **修复实施**:
    1. **自启动与显式调用**: 在 [TradeHistory.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/TradeHistory.lua) 中导出 `ns.InitTradeHistoryModule`，并改写底部自启动逻辑（利用 `IsLoggedIn()` 与 `PLAYER_LOGIN` 自愈执行，不再依赖失效的 `BG.Init` 队列）；并在 [Init.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/Init.lua) 的 `InitPlusUI()` 中显式调度初始化；
    2. **底部 Tab 按钮恢复**: 在 `Init.lua` 中为 `BG.TradeHistoryMainFrameTabNum`（101）补建【交易记录】Tab 按钮（`BG.ButtonTabTrade`），并为其注入带说明的悬停 Tooltip 提示；
    3. **切 Tab 生命周期联动**: 在 `HideAllSubFrames` 及 `BG.ClickTabButton` Hook 中完整纳入 `BG.TradeHistoryMainFrame`，确保切 Tab 时正常显隐与 OnShow 列表数据自刷新。

* **交易选项设置隐藏与 Tab 挂载顺序精简 (2026-09-03)**:
  - **隐藏交易选项设置**: 动态遍历 `BG.TradeHistoryMainFrame` 子组件，精确定位「交易选项设置」按钮并实施彻底隐藏与移出视口处理（移至 -9999, -9999 并挂载 `OnShow` 抑制），杜绝无关设置按钮干扰；
  - **保持自然挂载排列**: 移除了冗余的 Tab 链表强制重排与对调逻辑，保持原生态自然的加载追加链路，精简代码体量与运行开销。

* **超低频、极轻量声望工具类 Reputation.lua 设计与集成 (2026-09-03)**:
  - **背景与合法性**: 上游 BGLite 在精简时裁掉了原版 BiaoGe 的 `bagSync.lua`，导致声望失去实时采集与保存。声望 API（`GetFactionInfoByID`、`UPDATE_FACTION`、`SavedVariables`）为魔兽官方 100% 公开且无保护的合法只读接口，无任何违规封禁风险；
  - **极致性能与慢速策略**:
    1. **超长延迟初次扫描**: 角色登录或重载后静默等待 30 秒（`INITIAL_DELAY = 30`），避开加载高峰；
    2. **战斗状态完全避让**: 若处于战斗中（`InCombatLockdown()`）绝对不执行任何声望读取，仅挂载脱战待办，脱战 5 秒后再执行；
    3. **10 秒超长防抖合并**: 收到 `UPDATE_FACTION`（刷怪/批量交任务）时不立即扫描，重置 10 秒定时器，全部刷完 10 秒后仅执行一次，彻底杜绝高频 CPU 消耗；
    4. **数据与无缝渲染**: 严格对齐原版结构写入 `BiaoGe.bag[realmID][player].faction[ID]`，无缝点亮角色总览的跨号声望查看；
    5. **对外提供标准工具 API**: 暴露 `ns.Reputation.GetReputation(id, player, realm)`、`ns.Reputation.GetAllReputations()` 等只读接口供全局调用。

* **团队信息 UI 敏感词治理与语音(DD)全模式扩充 (2026-09-03)**:
  - **合规防封治理**: 将 [TeamInfo.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/TeamInfo.lua) 中所有暴露给玩家视觉与游戏内聊天频道的敏感关键字“YY”全面替换为中性合规的**“语音频道”**（包括侧边栏操作行标签、Tooltip 提示、系统绑定通知、捕获记录与空提示），彻底杜绝游戏内审查违规与封禁风险；
  - **底层识别能力全量扩充**: 扩充 `TITAN_KEYWORDS` 特征库与 `YY_PATTERNS` 正则捕获器，同步支持 `DD`、`dd`、`进DD`、`上DD`、`语音`、`滴滴` 等时光服团长各类防封缩写喊话，实现毫秒级自适应提取；
  - **多语言词条补齐**: 在 [zhCN.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Locales/zhCN.lua) 与 [zhTW.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Locales/zhTW.lua) 中同步补全简体/繁体标准本地化词条。

* **团队信息侧边栏默认展开与持久化状态记忆 (2026-09-03)**:
  - **默认展开机制**: 严格对齐左侧拍卖记录（`showAuctionLogFrame or 1`）的标准设计，在 `TeamInfo.CreateUI()` 初始化中将 `BiaoGe.options.showTeamInfoFrame` 缺省值设为 `1`，实现首次打开与全新环境出厂默认直接展开；
  - **状态双向记忆**: 玩家点击右上角【X】关闭时记录为 `0`，点击顶栏按钮展开时记录为 `1`，自动持久化至 WTF，切 Tab、切副本及重载游戏时严格遵循玩家上一次的手动设置状态。

* **预设心理价格 (BestPrice) 模块恢复与全自动竞拍联动 (2026-09-03)**:
  - **模块背景与定位**: 完整重构并移植原版 BiaoGe 被裁剪的买家预算管理功能，完全在 `BGLite_Plus` 内部独立封装，对上游只读依赖零侵入；
  - **存储与槽位机制**: 数据结构对齐 `BiaoGe.bestPrice[realmID][player]`，支持 10 个预设装备槽位，记录 `{ enabled, equipment, price }`；
  - **双重交互入口**:
    1. **快捷入口**: 全局重写 `BG.IsSetBestPriceKeyDown`，在表格、心愿单、装备库中按住 `Alt` 并右键点击装备，直接弹出快捷价格设置弹窗；
    2. **主管理面板**: 在主界面方案栏挂载动态更新的【心理价格(x)】常驻按钮，支持 10 格清单配置、独立启用/停用、数值修改与一键清空；
  - **开拍全自动接管**: 挂钩 `BG.HookCreateAuction(auctionFrame)`，当拍卖清单中的装备时，自动填入心理上限并触发 `AuctionWA` 的自动出价流程，执行加一手逐级跟进、能捡漏绝不多花、封顶智能保护。版本提升至 `1.0.7`；
  - **表格单元格 Alt+右键 点击拦截修复**: 针对 BGLite 精简时移除了 `FBUIfunction.lua` 中装备格子点击分支的缺陷，在 `BestPrice.lua` 中通过 `BestPrice.HookAllTableButtons()` 包装全局表格装备格子的 `OnMouseDown` 事件，优先截获 `Alt + 右键` 并直接触发 `BG.SetBestPrice`，彻底打通表格与心愿清单的快捷加价通路。

* **预设价格 (AuctionPreset) 模块落成与团长拍卖发起深度联动 (2026-09-04)**:
  - **模块背景与定位**: 完整重构并移植原版 BiaoGe 专为团长及拍卖发起人打造的底价批量管理系统，完全在 `BGLite_Plus` 内部独立封装，对上游只读依赖零侵入；
  - **底部分页 Tab 挂载**: 注册全局 `BG.AuctionPresetMainFrameTabNum = 104`，通过 `BG.Create_TabButton` 挂载底部【预设价格】独立 Tab，与主界面原生生命周期无缝衔接；
  - **存储与数据结构**: 对齐原版 `BiaoGe.auctionPreset[FB].money[itemID]`（起拍价）与 `[itemID .. "tips"]`（起拍语说明），支持历史配置自动继承；
  - **列表与批量工具**: 包含副本下拉切换、装备名搜索、按装等/品质/价格排序、批量底价设定与全部清空；
  - **副本名称中文转换**: 针对底层数据键名仅为英文字母代码（MC、BWL、TAQ等）的问题，接入 `BG.GetFBinfo(FB, "localName")` 自动转换为魔兽客户端官方中文全称（如“熔火之心 (MC)”、“黑翼之巢 (BWL)”），下拉菜单与提示文案更直观清晰；
  - **排序严格弱序与弹窗编辑框兼容性修复 (2026-09-04)**:
    1. 针对 `table.sort` 报错 `attempt to index local 'b' (a nil value)`：彻底重构比较函数，修复了三元逻辑在升序时导致偏序破坏进而引发快排哨兵越界的核心 Bug，改用严格的 `if sortAsc ... else ...` 判定并加入完整 `nil` 防御；
    2. 针对点击【批量底价】弹窗确定时 `attempt to index field 'editBox' (a nil value)`：规范 `hasEditBox = 1`，并加入对 `self.editBox`、`self.EditBox`、`_G[name .. 'EditBox']` 以及父级容器的多层 fallback 获取，兼容时光服与探索服新旧弹窗系统。
  - **交易记录模块架构重构：直接复用上游原生框架 (2026-09-04)**:
    - **设计决策与精简**: 用户指出上游 BGLite 已内置完整的 `TradeHistory.lua` 逻辑与 UI，重写整个模块会导致两套子框架叠加；
    - **重构实施**: 将 [TradeHistory.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/TradeHistory.lua) 代码从 1150 行精简至 65 行纯胶水层，不再重复 `CreateFrame`，直接调用 `BG.Create_TabButton(BG.TradeHistoryMainFrameTabNum, L["交易记录"], BG.TradeHistoryMainFrame, 100)` 恢复上游底部 Tab 入口；
    - **彻底根治透光**: 移除了重复生成的第二套 Frame，上游 UI 原生管理唯一的 `notText`，彻底消除了重叠透光与数据渲染异常。
  - **项目说明文档全面焕新 (README.md) (2026-09-04)**:
    - 完整同步补充了预设心理价格 (BestPrice)、预设起拍底价 (AuctionPreset)、团队信息侧边栏 (TeamInfo)、交易记录等重磅功能的交互与使用指南；
    - 补齐了最新的文件目录拓扑与快捷按键交互清单，与当前代码库架构完全对齐；
    - 增设**【💡 我们的开发理念：最纯粹、最专注、最优雅】**核心板块，明确强调“社区最纯洁（零广告/零捆绑）、最专注功能（实战为王）、UI主打简洁（暗黑原生）、专业开发者匠心打磨”的产品定位。
  - **拍卖发起智能联动**:
    1. **单件开拍自动带入**: 挂钩 `BG.StartAuction`，弹出开拍小框时自动检索并填入该装备预设起拍底价；
    2. **Boss 点击全开拍**: 团长按住 `Alt + 点击 Boss 名字`，自动逐一拉起该 Boss 掉落的所有预设装备开拍；
    3. **Tooltip 悬停增强**: 悬停装备按住 Alt 时自动展示【预设起拍价】与【预设起拍语】。版本提升至 `1.0.8`。
  - **合规性改造：全面对齐官方规范，彻底剥离历史表格 (History) 模块 (2026-09-04)**:
    - **背景与合规驱动**: 官方新版对历史拍卖数据进行了彻底的去持久化清理（剔除全量聊天持久化与进本自动归档），为保证插件 100% 遵守国服合规规范、消除 RMT 与隐私溯源争议，同时避免 SavedVariables 无限膨胀，正式决定移除历史账单与快照功能；
    - **模块下线与清理**:
      1. 从 [BGLite_Plus.toc](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/BGLite_Plus.toc) 中正式剔除 `Core\History.lua`，并物理删除冗余历史源码；
      2. 移除主界面右上角【保存】按钮与【历史表格】下拉列表，移除只读历史模式（`BG.HistoryMainFrame`）与装备历史价格走势图；
      3. 在 [TeamInfo.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/TeamInfo.lua) 中移除历史快照检测分支，保持团队信息抽屉专注于当前活跃副本与队伍；
      4. 在 [Init.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/Init.lua) 中移除针对历史主框架的所有显隐拦截逻辑；
    - **旧数据一次性自愈清洗**:
      - 借助 `BG.Once("CleanLegacyHistory_Compliance_260904", 260904)` 机制，在玩家首次载入时自动清空历史残留的 `BiaoGe.History` 与 `BiaoGe.HistoryList` 庞大存档表，彻底为玩家的 WTF 文件瘦身减负。
    - **ClearBiaoGe 联动同步清理 TeamInfo**:
      - 挂钩原生 `hooksecurefunc(BG, "ClearBiaoGe")`，在玩家手动清空表格或新 CD 进本自动全清时，同步重置 `BiaoGe[FB].teamInfo = nil` 并解除队伍绑定，彻底消除旧团队信息残留，确保数据合规与状态 100% 同步。
  - **团队信息欢迎消息单条保留与集结号乱码彻底截断 (2026-09-04)**:
    - **欢迎语音消息单条保留 (Upsert)**：新增 `IsWelcomeAnnouncement` 识别入队欢迎指引；针对换人进队时因携带不同玩家名导致“欢迎XX请上YY”刷屏几十条的痛点，实施就地覆盖更新策略，全团始终只保留最新 1 条入队欢迎提示，并自动提取语音号，彻底杜绝垃圾信息淹没有效规则；
  - **合体多副本进本自动清空防误杀补丁 (ClearProtect) (2026-09-04)**:
    - **背景与 Bug 根因**: 官方 BGLite v2.4.1 在精简 `ClearBiaoGe.lua` 的进本 `CheckCD` 逻辑时，移除了旧版的所有 Boss 区间与同团判定（删除了 `BG.bossPositionStartEnd` 与 `IsNotSameTeam` 检查），粗暴执行 `BG.ClearBiaoGe("biaoge", FB)`。导致时光服 P5双本（`SWtitan`: 祖阿曼 1~7、太阳井 8~13）以及 WLK/CTM 等合体副本在连打时，打完前一个副本进下一个新CD副本，整表账目被瞬间清空抹杀；
    - **模块落成**: 新增 [ClearProtect.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/ClearProtect.lua)，挂载于 `BGLite_Plus.toc`，版本升级至 `1.0.8`；
    - **核心技术设计**:
      1. **还原并增强 `IsNotSameTeam` 判定**: 综合校验在团状态、历史团队成员名单、24小时时效、同服及团队重合度（>= 60% 为同一团队连打）；
      2. **子副本干净免清空原则 (Zero-Dirty Skip)**: 进本自动清空时，若当前进入的子副本区间（如祖阿曼 1~7）没有任何装备/买家/金额，且同表其他区间（如太阳井 8~13）已有账目，**无条件跳过清空，100% 保护已有账目**；
      3. **同团连打局部清空原则 (Partial Clear)**: 若当前子副本有旧残留，但同表其他副本有当前团记账，**仅精准清空当前子副本对应的 Boss 槽位（`BG.ClearBiaoGeByIndex`）**，绝不越界误伤其他副本与拍卖/支出记录；
      4. **UI/系统提示与音效抑制**: 拦截并吞掉误导性的“已自动清空表格”黄字与清空音效，替换为友好的保护提示（如“检测到同表多副本连打，已自动保护已有副本账目”），彻底消除团长恐慌；
      5. **操作意图完全尊重**: 针对玩家在主界面点击【清空表格】弹窗或右键自选清空，通过 `_isManualClearingBiaoGe` 标记完全放行玩家的主动清空意愿。
  - **团队信息进入新队伍未同步 Bug 根因与状态机重构 (2026-09-04)**:
    - **现象与根因剖析**: 用户反馈在副本外进入别人的新团队后，侧边栏未能及时展示新团队的 YY 和通告，必须手动点击【清空表格】才出现。根因在于 `TeamInfo.GetCardState()` 状态机存在严重颠倒缺陷：此前在组队模式下判断了 `or (fbData and fbData.leader and fbData.leader ~= "")`，导致只要当前主界面选中的副本（如上一次打完的 TOC/SW）存有历史 `teamInfo`，右侧抽屉就会被误判为【状态 2：已绑定态】强行展示旧副本的历史团队数据；而新团队抓取到的数据存在 `currentGroupData` 里被完全遮挡，直到点击清空把 `fbData` 删掉，新团队信息才得以漏出呈现；
    - **架构重构与自愈治理**:
      1. **重构 `GetCardState()` 状态优先级**: 严密规范——仅当玩家身处对应副本内部（`IsInInstance()` 且匹配 `FBID`），或当前队伍明确已手动绑定该副本时，才允许展示状态 2（蓝框绑定态）；玩家在副本外面组队时，**100% 走状态 1（翠绿边框，组队未绑定态），且 100% 呈现当前活跃队伍数据 `currentGroupData`**，绝不允许被未进本的旧副本存档遮挡劫持；
      2. **换团队与进组自愈重置**: 在 `OnGroupUpdate` 中增加团长变更校验，当在副本外检测到新团长，自动将队伍数据重置为全新状态并解除旧副本绑定；在 `GROUP_JOINED` 事件触发时，预先清空旧队伍缓存，触发 4 波次扫描（0.2s, 1.0s, 2.5s, 5.0s）并即时刷新 UI；
      3. **跨 Tab 持续常驻新团队**: 玩家在副本外组队时，主界面任意切换副本 Tab，右侧均始终呈现当前真实活跃队伍信息，彻底解决非得点清空才同步的恶性交互问题。
  - **角色总览自定义备注配置补全与弹窗健壮性增强 (2026-09-04)**:
    - **功能与配置补齐**: 底层已具备完整的角色备注持久化（`BiaoGe.roleOverviewNote[realmID][player]`）与单元格渲染逻辑，但在设置界面中缺少交互入口。在 [RoleOverviewOptions.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/RoleOverviewOptions.lua) 基础开关第 5 行左侧补齐【显示角色备注】复选框与【宽度：】数字微调输入框（40~300 范围限制，默认 100 像素），支持即时刷新重绘；
    - **弹窗交互兼容性加固**: 在 [RoleOverview_core.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/RoleOverview_core.lua) 中增强 `BG.AddRoleOverviewNote` 弹窗输入框兼容性，覆盖 `self.data`、`self.EditBox`、`self.editBox` 及全局命名检索，并适配 Enter 回车提交与 Esc 撤销，杜绝在各魔兽客户端版本中报错；
    - **全语言本地化补齐**: 在中繁英（zhCN/zhTW/enUS）本地化字典中完整补全【显示角色备注】、【宽度:】及说明引导文案。
  - **团队工具「团队小游戏 (R点/骰子大比拼)」模块落成 (2026-09-04)**:
    - **模块定位与入口**:
      - 新增独立核心模块 [Core/RaidGame.lua](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/Core/RaidGame.lua)，挂载于 [BGLite_Plus.toc](file:///e:/World%20of%20Warcraft/_classic_titan_/Interface/AddOns/BGLite_Plus/BGLite_Plus.toc)；
      - 巧妙利用团队工具左侧组队助手与右侧阵容管理此前高度截断（470px）在底部预留的留白空间，构建高 82px、宽 965px 的【🎲 团队小游戏 (R点/骰子)】常驻控制底栏；
      - 界面一览无余，无需切换 Tab 即可一屏掌控组队、调队与小游戏互动。
    - **胜出规则矩阵与配置**:
      - 支持 6 种规则算法：**选最大 (1人)**、**2个最大 (前2名)**、**1大1小 (双向)**、**3个最大 (前3名)**、**3个最小 (前3名)**、**选最小 (1人)**；
      - 支持自定义限时（15s / 20s / 30s / 45s / 60s）与可编辑的开场客套话（支持 `{rule}`、`{time}` 动态占位符）。
    - **防刷机制与违规剔除顺延 (disallowMultiple)**:
      - 默认勾选【禁止多次R点 (多次剔除资格)】；
      - 系统实时追踪每位玩家在单次游戏中的有效投掷次数。若玩家多次参与 R 点，直接标记为违规取消资格，其胜出名额严格按规则顺延给下一名合法玩家；
      - 并在团队总结与排行榜中明确公示违规名单与被取消资格原因，确保绝对公平。
    - **双重捕获与全员无缝兼容**:
      - 玩家点击弹窗按钮采用 `SecureActionButtonTemplate` 绑定宏 `/roll 100`，由暴雪服务器直接生成权威系统 Roll 点；
      - 监听 `CHAT_MSG_SYSTEM` 事件，严格校验 `1-100` 点范围；未安装插件的团队成员在聊天框手动输入 `/roll 100` 同样 100% 自动纳入抓取与排行。
    - **插件信道广播与全员弹窗交互**:
      - 注册专用信道前缀 `BGL_GAME`（`C_ChatInfo.RegisterAddonMessagePrefix` 与 `SendAddonMessage`）；
      - 团长发起时向全团广播 `START`，全团装有插件的玩家即刻弹出暗黑质感、可自由拖拽的【🎲 幸运掷骰】面板，伴随清脆掷骰音效与倒计时条；
      - 注册快捷命令 `/bgroll`、`/bggame`、`/bgrgame`，支持玩家随时重新呼出弹窗。
    - **倒计时归零自动团队通报与完整榜单**:
      - 倒计时结束时广播 `END`，按钮自动禁用截止；
      - 团长端自动在团队/小队频道发送精美排版通报，包括胜出者名单、点数与违规剔除顺延说明；
      - 底栏配备【📋 完整榜单】按钮，可随时呼出滚动列表查阅全团每位参与者的名次、姓名、职业染色与点数明细。
    - **下拉菜单 nil 报错与投掷原生 API 修复 (2026-09-04)**:
      - **EasyMenu 报错**: 将全局 `EasyMenu` 改为上游标准 `LibBG:EasyMenu` 并复用 `BG.dropDown` 锚点，彻底根治 `attempt to call a nil value`；
      - **投掷原生 API 对接**: 弃用存在安全环境与点击拦截缺陷的 `SecureActionButtonTemplate`，改用普通轻量按钮直接调用暴雪官方原生公开接口 `RandomRoll(1, 100)`（与魔兽官方聊天框骰子按钮行为 100% 一致），点击即投，响应极快且零安全报错。
    - **Plus 专属版本查询信令系统落成 (PlusVersionCheck / PlusMyVer) (2026-09-04)**:
      - **信道与信令架构**: 注册专属信道前缀 `BGLite_Plus`，建立专属于 Plus 增强包的双向握手信令；
      - **查询信令**: `"PlusVersionCheck"`（可在 `RAID`、`PARTY`、`GUILD` 频道广播查询）；
      - **应答信令**: `"PlusMyVer-" .. ns.ver`（例如 `"PlusMyVer-1.0.9"`）；
      - **全自动采集与主界面底部控件落地**:
        1. 进组或团队名单变更（`GROUP_ROSTER_UPDATE` 1.5s 防抖）自动向团队发起版本查询；
        2. 全团装有 Plus 的成员自动回传自身版本并记录至 `ns.raidPlusVersion[sender]`；
        3. **底部版本栏架构统一**: 移除了小游戏底栏的“Plus就绪”统计，使小游戏底栏聚焦于游戏本身的已投掷与极值数据；
        4. **主框架最底部专属控件**: 在 `BG.MainFrame` 最底部新增 `BG.ButtonRaidPlusVer`，青色高亮展示 `Plus：M/N`；
        5. **状态跟随完全对齐 BGLite 原生标准**:
           - **单人状态 / 5人小队状态**：100% 跟随【公会插件】显示 `Plus：X/Y`（在线公会成员装有 Plus 数量），鼠标悬停弹出公会成员详细版本浮窗；
           - **大型团队/团本状态（IsInRaid(1)）**：自动切换为跟随【团队插件 / 拍卖WA】显示 `Plus：X/25`，鼠标悬停弹出全团各成员职业着色与 Plus 版本明细，与原生公会/团队切换节奏完全一致！
        6. **全团/全公会版本穿透浮窗**: 鼠标悬停在 `Plus：M/N` 按钮上时，弹出精美 Tooltip，使用职业排序与染色，清晰呈现名字、职责图标及对应所安装的 Plus 版本号（在线未安装显灰色“无”，离线显“未知(离线)”），与 BGLite 原生底部栏风格与交互无缝融合。
    - **弹窗动态规则提示与违规特别处理重构 (2026-09-04)**:
      - **默认不勾选规范**: 将【禁止多次R点】调整为出厂默认**不勾选（false）**，并借助 `BG.Once` 清洗旧缓存；
      - **弹窗警示动态跟随**: 彻底告别写死，根据当前模式动态呈现：
        - 勾选（禁止多次）：醒目红字提示 `* 严禁多次R点，多次投掷将直接取消获胜资格！`；
        - 未勾选（默认）：黄字提示 `* 仅首次R点成绩有效，重复投掷不计入成绩。`；
      - **彻底移除自动清空拦截兜底模块 (ClearProtect) (2026-09-04)**:
      - **决策背景**: 遵照架构规范，完全交由官方原生 BGLite 自主处理进本自动清空与连打判断，避免插件外部 Hook 产生逻辑交叉干扰；
      - **改动落实**:
        1. 物理删除 `Core/ClearProtect.lua` 文件；
        2. 从 `BGLite_Plus.toc` 中彻底移除 `Core\ClearProtect.lua` 的加载声明；
        3. 彻底解绑对 `BG.ClearBiaoGe`、`BG.SendSystemMessage`、`BG.PlaySound` 及 `StaticPopupDialogs["QINGKONGBIAOGE"]` 的 Hook，让官方原汁原味自主运转。
    - **手动清空表格联动清空团队信息与新增抽屉一键清空按钮 (2026-09-04)**:
      - **问题根因剖析**:
        1. 原版点击【清空表格】（`ClearBiaoGe`）仅清空 `BiaoGe[FB]` 数据；
        2. 此前 `TeamInfo.lua` 的 Hook 仅执行了 `BiaoGe[FB].teamInfo = nil`，而**未清空内存中的实时队伍通告缓存 `TeamInfo.currentGroupData.recruits` 与 `yy`**；
        3. 处于组队状态时，右侧抽屉根据状态机优先渲染活跃队伍数据 `currentGroupData`，导致视觉上右侧通告和 YY 毫发无损，给玩家“点了清空表格但右侧团队信息完全不清空”的疑惑。
    - **团队信息严格跟随副本 Tab 切换与状态机架构修正 (2026-09-04)**:
      - **问题根因**:
        1. **缺少切本 Hook**: 原代码仅 Hook 了底部 Tab（`ClickTabButton`）和拍卖记录，**漏掉了主界面顶部副本切换按钮 `BG.ClickFBbutton(FB)`**，导致玩家点击切换副本时右侧抽屉未被调度重绘；
        2. **状态机一刀切串台**: 组队状态下此前代码一刀切强制返回 `currentGroupData`，完全无视所切换到的副本是否有自己的团队存档，导致无论切到哪个副本，右侧全部显示同一份队伍通告甚至同一份标签。
      - **改动落实**:
        1. 挂钩 `BG.ClickFBbutton`：用户在顶部切换任意副本 Tab（TOC、NAXX、ULD、SW 等）时，100% 触发右侧抽屉毫秒级同步重绘；
        2. 状态机严格跟随副本：
           - 若切换到的副本有保存的团队存档（`hasFBData`），优先展示该副本的存档（暗灰边框 `[<副本>存档]`）；
           - 若当前队伍已绑定当前副本（或身处本内），展示绑定态（亮蓝边框 `[<副本>已绑定]`）；
           - 若当前队伍已绑定其他副本，切换到新副本时严格展示新副本存档，绝不把其他副本的队伍通告串台；
           - 仅当队伍未绑定且当前副本为空时，才显示当前队伍未绑定态（翠绿边框 `[当前队伍(未绑定)]`）并提供【绑定开团】。

## 9. 下一步计划 / 待办事项
- 观察团队环境下主界面底部 `Plus：M/N` 按钮的自适应宽度与右移对齐。
- 观察鼠标悬停在底部 `Plus：M/N` 上时各职业着色及职责图标的呈现效果。
- 观察时光服实战中在团队环境下发起小游戏时全团弹窗的弹出与投掷流畅度。
- 观察团队中无插件玩家手动输入 `/roll 100` 与有插件玩家点击弹窗的并行捕获准确度。
- 观察多次投掷被取消资格并在通报中顺延下一名获胜者的实际表现。
- 观察时光服实战中在野外进组时新团队 YY 号和招募通告的即时刷新表现。
- 持续收集时光服玩家在实战团本中的喊话样本，丰富特征词库。
- 观察玩家在不同客户端语言环境下的职业方案切换表现。
- 跟踪实战团本中开拍带有心理价格的装备时自动接管出价的流畅度。
- 跟踪团长实战中通过【预设价格】批量开拍各副本掉落的稳定性。









