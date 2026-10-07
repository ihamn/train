# 千星奇域 · 平台事实清单（喂给 AI 用）

> **用法**：开新会话 / 换 AI 时，**把这份整个贴进上下文**（或让 AI 先读这个文件）。
> **每条都标了来源**：`[zuma]` = 从真机跑通过的 `zuma.lua`（5,289 行）里扫出来的；
> `[doc]` = 官方文档；`[真机]` = 这台机器上实测的日志/现象；`[推]` = 推断（**未验证**）。
> **纪律**：清单里没有的 API，**一律先当"不存在"**，不要凭想象写（这就是 v8/v9 卡死的根源）。

---

## 一、可用的 API（照抄，不要猜）

### `game.*`（权威 8 个，[zuma] 全量扫描）
```
game.InstantiateClientUIControl(prefabIndex, parentControl) -> control
game.DestroyClientUIControl(control)
game.GetClientUIRoots()            -- 返回客户端 UI 根列表
game.GetUICanvasSize()             -- 返回 (w, h) 运行时画布尺寸
game.GetCursorUIPos()              -- 光标坐标（配合光标事件）
game.PrintClientUITree(...)        -- 打控件树（调试）
game.Tween(...)                    -- ★ 平台自带补间（动画优先用它，别自己每帧算）
```

### `script.*`
```
script.object                    -- 点号，宿主控件（脚本挂的那个控件）
script:EnableUpdate(true/false)  -- 冒号
script:GetParam(...)             -- ★ 读脚本参数：**做"档位开关"应该用这个**
```

### 控件方法（**只有这些**，[zuma] 全量扫描）
```
SetActive(bool)  SetVisible(bool)  SetImage(source, id)  SetAnchoredPosition(x, y)
SetSizeDelta(w, h)  SetAsLastSibling()  SetFillRadial360(...)
AddCursorEventListener(evtType, fn)  AddKeyEventListener(evtType, fn)
GetChildren()  GetParam(...)  EnableUpdate(bool)
```

### ★★ 不存在的方法（用了会**静默失败**，是 train 探针"看不见"的根因）
```
SetAnchorMin / SetAnchorMax / SetPivot        ← 千万别用 [真机]
```
**锚点在编辑器里定死；运行时只能改"位置 + 尺寸"。** [zuma]

### 字段
```
可写：name  text  imageColor  fontColor  fontSize  enableOutline  …  [zuma][真机]
不可写：visible ⇒ 报 "cannot set visible, no such field" ⇒ **必须调 SetVisible()** [真机]
可读：anchoredPositionX/Y  sizeDeltaX/Y  prefabIndex  active（visible 用方法/字段要看实现）[真机]
```

### 模板 / 素材号（**这台机器上出现过且可用**）
```
控件模板：1073741852（图片）  1073741851（文本框）  1073741846（容器）  1073741860
官方基础图元：100000  100001  100002  100006（形状占位图）           [zuma][真机]
★ 动态创建的图片控件**不继承模板的图** ⇒ 必须显式 SetImage(Enum.ImageSource.StaticReference, id) [zuma 注释]
★ 图片控件没有描边/渐变，只有：填充色 + 柔边(enableSoftEdge) + 径向填充(SetFillRadial360) [zuma 注释]
```

---

## 二、硬约束（写代码前先算账）

| 约束 | 值 | 来源 |
|---|---|---|
| **运行时实体上限** | **1000** | [doc] 编辑项范围限制 |
| 我们的实测占用 | 祖玛 900+ 控件能跑；**900 之后没余量给别的** | [真机] |
| 建议预算 | **单场景 ≤300 个控件**（给玩法 UI 留 700） | [推] |
| 画布 | 运行时读 `GetUICanvasSize()`；实测过 **1680×900 / 1815×900 / 1280×720** | [真机] |
| 坐标系 | 客户端 UI **左下原点、y 向上**；网页版是左上原点 y 向下 ⇒ **y 要翻** | [doc][真机] |
| 按键 | `Enum.KeyEventType` 是**逐键成员**（`KeyboardNormalAttackKeyDown` 这种）；名字错会报 `KeyEventType expected, got nil` | [zuma 注释] |
| 光标事件前置条件 | 控件要挂 `AddCursorEventListener`，且 **`showCursor` 必须为真**，坐标取 `game.GetCursorUIPos()` | [zuma 注释][doc] |

---

## 三、已验证的做法模板

### 建一个可见的控件（照这个写，不要改路子）
```lua
local c = game.InstantiateClientUIControl(1073741852, host)
c.name = "LOCO"                                     -- 字段可写
c:SetSizeDelta(220, 92)                             -- ★ 尺寸必须显式设（漏了 ⇒ 0 ⇒ 看不见）
c:SetAnchoredPosition(x, y)                         -- ★ 位置只有这一个方法
c:SetImage(Enum.ImageSource.StaticReference, 100002)-- ★ 动态控件不继承模板图
c.imageColor = 4294901760                           -- 颜色（0xAARRGGBB 十进制）
c:SetActive(true); c:SetVisible(true)               -- 方法，不是字段
```
（实测回读：`pos.x / size.x` 打进日志自证 —— 别靠假设 [真机]）

### 动画
- **首选** `game.Tween(...)`（平台自带）[zuma]
- 次选 **每帧改 `SetAnchoredPosition`** —— 祖玛每帧改几百个控件的坐标，真机跑得动 [真机]

### 输入
```lua
area:AddCursorEventListener(Enum.CursorEventType.CursorClick, function(d) ... end)  -- 需要 showCursor=true
kt:AddKeyEventListener(Enum.KeyEventType["KeyboardCraftspersonKey18Down"], fn)      -- 逐键
```

---

## 四、**卡死的三个成因**（每次卡死要等服务器 ~10 分钟回收，务必避开）

1. **启动期爆发**：`OnStart` 里一次建几十个控件 / 写上百年属性 ⇒ v8 就是"12 万图元启动就死" [真机]
   ⇒ **规避**：**分帧建**（每帧 1~2 个），`OnStart` 只做只读打印
2. **无界循环 / 扫描**：用 `while` 依赖外部条件收敛、对区间逐个"建了试" ⇒ v8/v9 卡死 [真机]
   ⇒ **规避**：索引**写死**；必须探测就 `for i = a, a+2`（≤3 次）+ 建完**立刻 Destroy** + 计数
3. **每帧重活 + `syncAllDevices`**：每帧写几何可能触发全项布局 [推]
   ⇒ **规避**：只在值真的变了才写；优先用 Tween/切图/填充

**通用护栏**（每份真机脚本都该有）：
```lua
if tick > 300 then script:EnableUpdate(false); return end   -- 看门狗：自毁不依赖任何 API
if dt == nil or dt <= 0 then return end                     -- 除零保护
```

---

## 五、验证纪律（少走弯路的根本）

1. **一次只改一个变量**（v8/v9 两次都只留下"卡死"，因为变量没分离 ⇒ 修不好）[真机]
2. **真机只跑"模拟器已验证过的那一档"**：模拟器过关只证明**逻辑对**，不证明**代价可接受**（同一份 v9：模拟器流畅、真机无响应）[真机]
3. **判据必须 ASCII**：日志中文是乱码（`凝銘` 这种）⇒ 中文搜不到 ≠ 没有；**自己打 ASCII 版本标语**（`TR build 2026-10-07`）[真机]
4. **别用 `Select-Object -First N` 截断长命令**再下结论（会掐断管道、退出码 -1，看着像失败）[真机]
5. **改脚本 vs 改关卡**：脚本在 `external_lua_file\`，**改磁盘文件即生效（重进关卡）**；但**模拟器存档里存的是内联 `source`**，改磁盘不会影响模拟器 [真机]
6. **控件预算写进日志**：`built=… destroyed=… cap=…`（撞 1000 上限就是"越玩越卡"）[真机]

---

## 六、真机日志在哪、怎么读

```
C:\Users\<user>\AppData\LocalLow\miHoYo\原神\BeyondLocal\<UID>\Beyond_Debug_Log\<日期>_<时间>_<序号>_<UID>.gia
```
- 一次运行一个文件；**最新那个 = 最近一次运行** [真机]
- 里面正文是**乱码编码** ⇒ 只认 ASCII 子串（自己代码里打的英文/数字）[真机]

---

## 七、待补（有资料就并进来）

- [ ] 讲义《千星奇域2D游戏AI工作流》`https://ppt.070077.xyz/beyond-ai/index.html`
      （外链；本地**没有**副本。抓取只拿到标题，页面是 JS 幻灯 ⇒ 需要导出 PDF/截图或贴文字）
- [ ] `Enum` 全量成员表（`KeyEventType` 逐键、`CursorEventType`、`ImageSource`…）
- [ ] 平台自带能力清单：遮罩 / 填充 / 柔边 / 径向填充 / Tween 的参数与限制
- [ ] 客户端控件容器的最佳实践（挂载点选择、激活与可见性、GIA 导入后索引重排）
