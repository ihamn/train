# 技术架构 —— 千星「列车」M0 探针（workspace/train）

> 交付后可运维手册。**每次结构性改动都要更新这里**；过时条目比没有更糟。
> 本文描述的是当前真实存在的 M0 探针工程，不是 M1 的目标架构。

## 1. 交付物

| 路径 | 作用 |
|---|---|
| `workspace/train/train.save.json` | 千星模拟器完整存档（`format: qxqy-simulator-save`, `version: 4`）。含服务端控件树 + 挂载脚本，脚本源码**内联**在存档里 |
| `workspace/train/spike.lua` | 客户端 Lua 探针脚本（`script.object` = `STAGE`）。与存档内联源码同源，由生成器同步 |
| — 脚本映射路径 | 存档里 `scripts[].path = "spike.lua"`（**平铺文件名，不能带斜杠**）。千星真机的映射名不允许带目录；带目录的 `default_import_file/workspace/train/spike.lua` 是模拟器 `require` 的"导入根"约定，写进 GIA 会生成非法映射名（2026-10-06 真机踩到）。机上的落点是 `<import root>/spike.lua`，与用户 zuma 工程的 `external_lua_file\zuma.lua` 一致 |
| `tools/make_m0_save.py` | 存档生成器：布局 + 内联脚本 → `train.save.json`。**改布局或脚本后必须重跑** |
| `tools/run-cases.mjs` | 无头跑 `tests/m0-*.case.json`（与 `runCase` 同一代码路径，只输出判定）。用法：`QXQY_STUDIO=<simulator/studio/index.js> node tools/run-cases.mjs`。用例自带 `canvasId` 优先，命令行 `--canvas` 兜底 |
| `tools/export_gia.mjs` | GIA 导出器（真机导入用）+ 模拟器侧往返校验。用法见 `docs/export-and-realdevice.md` |
| `tools/watch-realdevice.ps1` | 真机观察：轮询 `Beyond_Debug_Log` 新 dump → 自动复制 + 解码成文本；检测到 `isTrial:True` → 连拍原神窗口。**纯只读** |
| `tools/capture-play.ps1` / `tools/focus-window.ps1` | 前者盯试玩连拍，后者枚举顶层窗口/提前台/按窗口抓图 |
| `workspace/train/export/*.gia` | 导出物：整合包（推荐）/ 服务器控件模板 / 脚本 + `export-report.json` |
| `records/_screen/**` | 抓屏与真机日志解码产物（临时证据，非交付物） |
| `tests/m0-*.case.json` | `qxqy-autotest` 用例（4 个回归 + 1 个截图检查点） |
| `docs/tests-m0.md` | 用例设计、预期值推导、有效 Red 定义、证明边界 |
| `records/m0/*.png` | 模拟器截图证据 |
| `records/playtest.md` | 试玩记录（HTML / 模拟器 / 真机的来源与结果） |

**为什么用生成器而不是编辑器里手点**：`transformByPlatform` 要写满 4 平台 × 7 组分量，
20 个控件手点不可复现；存档本身是交付物，需要可 diff、可重生成；脚本内联源码由生成器
从 `spike.lua` 直接读取，避免存档与 `.lua` 文件漂移。

```bash
python tools/make_m0_save.py        # 重生成存档
# 然后在模拟器里：工作区存档列表 → workspace/train/train.save.json → 加载
```

## 2. 资产结构（服务端控件模板 = 客户端控件容器画布）

```
客户端控件容器  server-container  guid 1073742000   (全屏 stretch，不可挂脚本、不可删)
└─ STAGE       container         guid 1073742001   全屏 stretch     ← 脚本挂载点
   ├─ HUD       textbox  guid …2002  640,20  600×40    显示 "M0 frame=<idx>"
   ├─ F0..F5    image    guid …2003–2008  900,430  140×140   六帧叠放，imageId 100001–100006
   ├─ LOCO      image    guid …2009  100,400  200×70   车头（运行时改锚点 X）
   ├─ WAGON     image    guid …2010  320,400  120×70   车厢（运行时改宽度）
   ├─ TIE_0..5  image    guid …2011–2016  130+180i,300  12×90   轨枕
   ├─ RAIL_HI   image    guid …2017   0,370  宽=画布 ×8   上轨（水平 stretch）
   ├─ RAIL_LO   image    guid …2018   0,320  宽=画布 ×8   下轨（水平 stretch）
   ├─ BALLAST   image    guid …2019   0,300  宽=画布 ×90  道砟（水平 stretch）
   └─ BG        image    guid …2020   全屏 stretch        背景 #FF0E1420
```

布局坐标：千星原点左下、Y 向上。**固定尺寸控件统一 `anchor=(0,0)` + `pivot=(0,0)`**，
于是运行时 `box.left == anchoredPositionX`（推导见 `docs/tests-m0.md` §3.3）。
`BG`/`BALLAST`/`RAIL_*` 用 stretch 锚点，因此自动适配任意画布宽度。

同级绘制顺序：**列表里先出现的画在上层**（`observed-contract` 第 13 条），
所以 `HUD → 帧 → 车 → 轨枕 → 铁轨 → 道砟 → BG` 是"从最上层到最底层"的顺序，不要按直觉重排。

## 3. 脚本与数据流

`workspace/train/spike.lua`，无 `require`，单文件。挂载在 `STAGE`（存档里
`controlId: "n1"`, `controlAsset: "server-control-template"`, 脚本 guid `1073742200`）。

```
OnInit()                     print("M0 boot"); script:EnableUpdate(true)
OnStart()                    root = script.object
                             loco/wagon/hud = root:FindChild("…")
                             frames[i] = root:FindChild("F"..(i-1))
                             校验齐全 → apply_frame(0) → 复位位置/尺寸
OnUpdate(dt)                 tick = tick + 1
                             ticksPerFrame = round(FRAME_INTERVAL / dt)   ← 只算一次
                             nextIdx = floor(tick / ticksPerFrame) % 6
                             nextIdx ≠ idx → apply_frame(nextIdx)
                             loco.anchoredPositionX = 100 + 10·tick
                             wagon.sizeDeltaX       = 120 + 4·tick
                             tick % 15 == 0 → print("M0 move k=…")

apply_frame(i)               for k: frames[k]:SetActive(k-1 == i)   ← 逐帧换图
                             hud.text = "M0 frame="..i
                             print("M0 frame idx="..i)
```

关键点：
* **`script:EnableUpdate(true)` 必须显式调用**。模拟器里 `updateEnabled` 默认 `false`
  （`runtime.js:1155`），官方文档也把 `EnableUpdate` 列为逐帧更新开关；不调用则 `OnUpdate` 永不执行。
* `active` / `visible` 在官方 API 里是**只读**字段，切换用 `SetActive(v)` / `SetVisible(v)`；
  而 `anchoredPositionX/Y`、`sizeDeltaX/Y` 是**读写 + Tweenable**。
* 控件查找走**名字路径**（`FindChild`），不依赖运行时数字 ID。理由见 §5。

## 4. 控件索引（guid）与运行时 ID

| 概念 | 存档字段 | Lua 侧 | 说明 |
|---|---|---|---|
| 控件/模板索引 | 节点 `guid`（如 1073742001） | `control.prefabIndex` | `game.InstantiateClientUIControl` 的首参 |
| 运行时实例 ID | 无（运行时分配） | `control.Id` / `game.GetClientUIControl(id)` | 顺序分配，**不等于 guid** |
| 脚本映射 ID | `assets.scripts[].guid`（1073742200） | `script.scriptMappingId` | 与控件 guid 不得重复 |

本工程刻意只按**名字**取控件，因此真机若重排控件索引，脚本不受影响；
若后续改用 `GetClientUIControl(id)`，就必须按 `qxqy-simulator` 的索引校准流程同步。

## 5. 测试怎么跑

```jsonc
// 单用例
qxqy_studio_play { "action": "runCase", "args": { "case": <tests/m0-frames.case.json>, "canvasId": "mobile-16-9" } }
```

* `runCase` **会重建运行时**，所以每个用例都从 `tick=0` 开始——断言才可预测。
* 用例格式 `qxqy-autotest`/`version: 1`，`dt = 1/30`。断言只用
  `control`（字段，含 `box` 兜底：`left`/`width`）、`tree`、`log`、`lua`（`query.control/logContains/logs/var/signals`）。
* **断言时刻不要压 `n/30` 边界**：运行器时间戳按 1e-9 取整（`nextTick`），`1/30` 在该精度下不精确，
  压在 0.5 上的断言会滑到第 16 帧。规则：`at × 30` 的小数部分落在 0.4–0.6。
* 试玩会话**按真实时间推进**（不是只在 `step` 时推进），所以截图画面会随时间变化；
  要冻结画面用 `pause`。截图的可信用法是**自洽性检查**：HUD 的帧号、当前可见图元、
  车头位置、车厢宽度必须互相吻合。

## 6. 已知边界（不要把模拟器绿灯当成真机通过）

| 事项 | 状态 |
|---|---|
| 3D 实体 + 运动器沿轨移动 | **不适用 / 已移除** —— 本工程是全 UI 控件实现（2D+Lua），不用 3D 实体，也没有运动器路线（用户 2026-10-07 明确） |
| 界面控件叠在 3D 画面上（M0 前提④） | **叠加成立／范围未解**（2026-10-06）：客户端 UI 确实画在关卡画面上，但只盖住左下角，裁定为挂载点几何问题，证据待取 |
| 单网格 65,535 顶点 / 运行时 1,000 实体 / 控件预算 | `unknown` —— 模拟器不模拟这些上限；真机实测的是 **单控件组 1000 / 单屏 10000**（zuma 工程记录） |
| 官方素材真实 `imageId` 的显示 | **部分成立**：`100001–100006` 是**真实的官方素材号**（基础形状），`SetImage` 真机无报错、UI 已出现；逐项可见性受挂载点裁切影响，未逐项确认 |
| 真机上控件位置/尺寸写入 | **方法式成立**（真机写回与目标逐帧一致）：`SetAnchoredPosition` / `SetSizeDelta`。**字段式 `.anchoredPositionX =` 仍未验证**（zuma 工程 0 次使用） |
| 文本像素能否在**运行时**生成（Lua 字符串拼接 → `textbox.text`） | `unknown` —— 仓库原记录说"没有字符串拼接节点"，但那指节点图；Lua 侧 `..` 是标准能力，需单独探针 |
| 客户端 `script` 对象能否挂自定义字段 | **不能（模拟器实测）**：`script._tick = 1` 报 `cannot set _tick, no such field` ⇒ 逐帧计数只能用**模块级局部变量** |
| 脚本体在存档里的位置 | **`assets.scripts[].source`**（不是顶层 `scripts`）。`spike.lua` 只是**映射路径**，运行时取的是存档内联源码 ⇒ **改脚本必须重新生成存档 / 在千星保存关卡** |
| Lua 5.1 语法限制 | 内层匿名函数**不是 vararg**，在其中使用外层 `...` 会报 `cannot use '...' outside a vararg function`（`probe_readonly.lua` 实测踩到） |

## 7. 真机操作硬性规则（2026-10-06 客户端无响应事故后新增，必须遵守）

**事故**：v5.3 的改动上真机后客户端**无响应**（hang，不是闪退）；且因为服务端在登录后
会**自动把玩家送进该千星关卡**，用户没有任何自助手段脱困，最后靠服务端自行清理才恢复。
性质是**我方实现失误**（改动未经真机最小验证就上线），不是平台缺陷。

1. **不改挂载点的几何**：不要对 `script.object`（挂载控件/容器）调用
   `SetAnchorMin/SetAnchorMax/SetPivot/SetAnchoredPosition`。
   只允许 `SetSizeDelta`（zuma.lua 的真机做法也只动尺寸；位置类是本次第一嫌疑）。
2. **不用拉伸锚点**：满屏元素不要用 `anchorMin(0,0)+anchorMax(1,1)`，用显式尺寸。
3. **模板探测窗口必须窄**：只扫已被实测确认的窗口（本工程 `1073741845–1870`、
   模拟器 `1073741995–2320`），认全后立刻 `break`；不要扫 `2^30+1..+512`。
4. **真机探针分两阶段**：先"只读诊断"（打印 `typeof(mount)`、`size/pos/scale/active/visible/inHierarchy`、
   `GetUICanvasSize`、`GetClientUIRoots` 数量；**不建控件、不改几何**），
   确认事实后再开"建控件"。每次真机迭代前先备好**一键停用**（空实现脚本：
   `records/_screen/realdevice/spike.safe-placeholder.lua`）。
5. **改脚本 ≠ 生效**：千星会把映射脚本的**源码打包进关卡**；改磁盘文件后必须在沙箱里
   **保存关卡**才会生效。出事时客户端进不去，只能在**编辑器**里移除挂载 → 保存，
   或等后台/服务端重置会话。
6. **上游前置条件**：动真机前先确认该关卡上挂的脚本**可控可移除**（编辑器能打开该关卡），
   并确认有回滚路径（本仓库的存档与导出物都能重放）。
7. **事故证据包**：`records/support-2026-10-06/`（`output_log.txt`、`output_log.txt.last`、
   两张截图、客户端脚本日志、`报告.md`）。同类问题直接复用，不必重新收集。
