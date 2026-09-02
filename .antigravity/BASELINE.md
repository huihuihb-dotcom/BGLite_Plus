# BGLite_Plus 项目基准文档 (BASELINE.md)

## 1. 项目简介
- **项目名称**: BGLite_Plus (BiaoGe Plus - 魔兽世界怀旧服/时光服/正式服金团表格及辅助工具插件)
- **支持版本**: 经典旧世 (Vanilla / SoD)、燃烧的远征 (TBC)、巫妖王之怒 (WLK)、泰坦时光服 (Titan)、大地的裂变 (CTM)、熊猫人之谜 (MOP)、正式服 (Retail)

## 2. 核心架构与模块
- `BGLite_Plus.toc`: 插件入口及加载文件列表。
- `Locales/`: 本地化语言包 (`zhCN.lua`, `zhTW.lua` 等)。
- `Core/RoleOverview.lua`: 角色总览界面及数据配置（团本CD、日常任务、专业CD、声望、货币统计）。
- `Core/RoleOverview_core.lua`: 角色总览核心渲染与逻辑。
- `Core/RoleOverviewSort.lua` & `Core/RoleOverviewOptions.lua`: 角色总览排序与选项设置。
- `Core/Hope.lua`: 心愿清单与装备监控。
- `Core/ItemLib.lua`: 物品库与装备数据。
- `Core/RaidTool.lua`: 团队工具/通报等。

## 3. 角色总览货币列表与自定义设置
- **默认配置调整**: 时光服（Titan）模式下，已将【双倍经验】（`xp`）调整为**默认开启显示**；将货币 `161`（岩石守卫者碎片）与 `1901`（荣誉点数）调整为**默认不显示**，并通过 `BG.Once` 清洗了历史本地缓存，保证即时生效。
- **自定义功能支持**: 在 `RoleOverviewOptions.lua` 中已实现【货币与物品显示自定义队列】，玩家可在设置中随时按需勾选或隐藏任意货币（双倍经验、泰坦余烬、泰坦碎片、金币、橙武等）。
- **双倍经验系统加固**:
  - 完整移植并强化了双倍经验采集（`UpdateXP`）与离线时间推算算法（`BG.UpdateXP`）。
  - 全面加强了边界防御（防除以 0、防服务器时间漂移、防 `v.perNow` 为 nil 拼接错误、防 `BG.fullLevel` 未定义的满级判断报错）。

## 4. 下一步计划 / 待办事项
- 持续优化角色总览、心愿清单及团本工具在时光服等各版本的体验。
