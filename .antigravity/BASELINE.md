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

## 3. 角色总览货币列表说明
- 货币 ID `161`: **岩石守卫者的碎片** (Stone Keeper's Shard，图标为岩石)。
  - 用于统计角色背包/货币栏里的冬拥湖岩石守卫者的碎片数量。
  - 在泰坦服/WLK版本中，该货币可在冬拥湖军需官处兑换传家宝、PVP装备、坐骑、宝石与图纸等。

## 4. 下一步计划 / 待办事项
- 持续优化角色总览、心愿清单及团本工具在时光服等各版本的体验。
