# BGLite 自动确认交易漏单 Bug 技术复盘与防护方案报告

## 一、 缺陷背景与现场复现

### 1. 现象描述
团长在配置中开启【拍卖自动确认交易】（`autoAuctionSureClick == 1`）后，在分批连续拍卖交易中偶发严重漏单：
* **业务表现**：买家放入对应金币，插件自动按下交易，双方确认完成。团长背包金币到账，装备正常移出，但打开团队表格发现**该装备行买家与金额完全空白未记账**，且在【拍卖记录】日志中该装备状态依然显示为**未交易**。
* **高发场景**：第一单为欠款交易，紧接着第二单为正常付全款交易时，第二单大概率漏记。

---

## 二、 底层根因深入剖析 (Root Cause)

该缺陷本质上属于魔兽世界客户端的**事件循环驱动与 UI 状态异步竞争（Race Condition）**：

1. **自动确认缩减了安全窗口**：
   在纯手动交易时，团长核对金额并手动点击交易通常有数秒的人工反应时间；而开启自动确认后，买家放入金币且金额匹配后，系统在 0.5 秒内即调用 `AcceptTrade()`。
2. **异步 `TradeUpdate` 的破坏性清空**：
   在调用 `AcceptTrade()` 锁定交易到服务器返回 `UI_INFO_MESSAGE(ERR_TRADE_COMPLETE)` 的短暂窗口期内，魔兽引擎会抛出 `TRADE_MONEY_CHANGED` 等事件。主插件注册了 `BG.After(0, BG.TradeUpdate)` 将刷新逻辑排入下一帧异步执行。
   此时金币已在服务端转移，`GetTargetTradeMoney()` 返回 `0`，执行 `BG.GetTradeInfo()` -> `BG.TradeIsAutoAuction()` 时，由于金额已归零不满足条件，直接触发了 `wipe(BG.trade.autoAuction)`，将原本算好的记账数据清空！
3. **落盘保存拿到空数据**：
   随后系统消息抛出“交易完成”，落盘函数 `SaveMoney()` 介入执行，此时读取到的 `BG.trade.autoAuction` 已经被前序的异步刷新彻底清空，导致表格静默放弃写入。
4. **拍卖日志未交易联动缺陷**：
   拍卖日志记录打勾依赖 `T.SetItemTradeState()`，它读取 `BG.trade.playeritems`。当中间态被置空后，日志同样无法匹配到移出物品，因此始终显示为未交易。

---

## 三、 防御方案设计与实现 (`Core/TradeFix.lua`)

为了在不侵入修改主插件核心源码的前提下彻底根除漏单，`BGLite_Plus` 实现了独立的防御增强模块，采用**锁机制 + 快照双保险 + 动态安全解锁**的架构：

### 1. 交易提交加锁与有效数据快照
* **Hook `AcceptTrade`**：当触发交易锁定时，立即将 `BG.trade.isAccepted` 置为 `true`。
* **深拷贝快照（Snapshot）**：在锁定瞬间，对当前有效的 `BG.trade.autoAuction` 以及手动记账所需上下文（`targetmoney`, `playeritems`, `targetinfo` 等）进行深拷贝锁存。

### 2. 锁定期间拦截破坏性刷新
* **Hook `BG.TradeUpdate`**：在 `BG.trade.isAccepted` 期间，直接 `return` 拦截后续任何异步触发的界面刷新，防止中间态的清空操作（`wipe`）破坏内存数据。

### 3. 防止 UI 冻结的动态解锁机制
* **监听 `TRADE_ACCEPT_UPDATE`**：
  若团长点击交易后，买家撤回金币或修改物品，暴雪引擎会自动撤销锁定。模块捕捉到 `playerAccepted == 0` 时，立即解开 `isAccepted` 锁，并延迟一帧触发真实刷新，彻底避免了交易中途改钱导致界面卡死的问题。

### 4. 交易关闭与取消的延迟清理
* **监听 `TRADE_CLOSED`**：
  采用 `C_Timer.After(0, ...)` 延迟一帧异步清空快照和锁标志。既防止了异常中断交易时的脏数据残留，又为交易成功同帧内的 `UI_INFO_MESSAGE` 消费快照留出了充裕时间。

### 5. 落盘保存快照兜底
* **Hook `BG.GetTradeSeeText`**：
  在 `saved` 保存阶段，如果发现主数据 `autoAuction` 因任何不可预见原因为空，立即使用快照完整恢复，确保记账和 `T.SetItemTradeState()` 拍卖日志 100% 成功落盘。

---

## 四、 初始化时序安全性保障

* **依赖保障**：`BGLite_Plus.toc` 中声明了 `RequiredDeps: BGLite`。
* **加载时序**：
  1. `BGLite` 文件加载并执行
  2. `ADDON_LOADED("BGLite")` 触发，`BGLite` 完成 `BG.Init` 注册与变量装配
  3. `BGLite_Plus` 文件加载
  4. 全局触发 `PLAYER_LOGIN`
* **结论**：在 `PLAYER_LOGIN` 阶段，主插件的全局变量与核心函数（如 `BG.TradeUpdate`）已绝对就绪，防御模块安全挂载，无任何时序竞态风险。
