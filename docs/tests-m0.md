# M0 平台前提测试 · TDD 用例设计

> 步骤 2 产物。**先写用例，后写 Lua**。
> 被测对象：`workspace/train/spike.lua`（挂在控件 `STAGE` 上）
> 用例文件：`tests/m0-frames.case.json`、`tests/m0-move.case.json`、`tests/m0-layout-mobile.case.json`、`tests/m0-layout-pc.case.json`

---

## 1. 被测前提

来源 `HANDOFF.md` §6「M0（最优先）：在千星沙箱里验证四个前提」。

| 编号 | 前提原话 | 模拟器（纯 2D UI+Lua）可测？ |
|---|---|---|
| **P1** | 放 3 个图片控件 → 按条件切换显示 → 逐帧换图可行？ | ✅ 可测 |
| **P2** | 能摆一条轨道？（用现有资产拼） | ✅ 可测（UI 控件层，不是 3D 轨道） |
| **P3** | 能让一个实体沿轨道移动？（运动器够不够） | ❌ 需真机（3D 实体 + 运动器） |
| **P3'** | 界面控件运行时能不能移动/改大小？ | ✅ 可测（本次新增，见下） |
| **P4** | 界面控件能叠在 3D 画面上？ | ❌ 需真机 |

### 1.1 为什么要新增 P3'

`HANDOFF.md` 与 `README.md` 把「界面控件运行时不能移动/改大小，只能显示/隐藏 ⇒ 动画只能用逐帧换图」
列为**已查证**的平台硬约束，整条美术路线（N 张预渲染帧 + 切换显示）建立在这条之上。

但官方《客户端控件API文档》（`mhtakr07vej4`）把这些字段标为**读写且 Tweenable**：

```
ClientUIBaseControl:
  anchoredPositionX/Y  number  读写、Tweenable
  sizeDeltaX/Y         number  读写、Tweenable
  localScaleX/Y/Z      number  读写、Tweenable
  SetAnchoredPosition(x, y) / SetSizeDelta(x, y) / GetAnchoredPosition() / GetSizeDelta()
game.Tween(object, tweenDataTable, duration) → Tween:Play()
```

若这条在千星真机成立，列车就不必预渲染 N 帧：**1 张图 + 位置插值**即可，能省掉
`tools/make_frames.py` 的整条流水线和大量图片控件。这是本次测试里价值最高的一条。

模拟器按「只开放官方 API 文档列出的字段/方法」实现，`anchoredPositionX/Y`、`sizeDeltaX/Y`
都在可写面上，所以模拟器能给出**第一条证据**；真机结论仍需步骤 7。

---

## 2. 被测对象契约（spec）

`spike.lua`，单文件，无 `require`。常量：

```
FRAME_COUNT   = 6        帧控件 F0..F5
FRAME_INTERVAL= 0.12 s   换帧间隔
MOVE_PER_TICK = 10 px    列车每帧右移
GROW_PER_TICK = 4 px     车厢每帧变宽
```

行为：

| 阶段 | 行为 |
|---|---|
| `OnInit` | `script:EnableUpdate(true)`（模拟器与官方文档一致：不调用则 `OnUpdate` 不执行） |
| `OnStart` | 取控件引用；`k = 0`；应用 `frame 0`；`LOCO.anchoredPositionX = 100`；`WAGON.sizeDeltaX = 120` |
| `OnUpdate(dt)` | `k = k + 1`；帧累加器 ≥ `FRAME_INTERVAL` 则 `idx = (idx+1) % 6` 并只激活 `F{idx}`；`LOCO.anchoredPositionX = 100 + 10k`；`WAGON.sizeDeltaX = 120 + 4k`；`HUD.text = "M0 frame=" .. idx` |
| 日志 | 每次换帧 `print("M0 frame idx=" .. idx)`；`k % 15 == 0` 时 `print("M0 move k=" .. k)` |

控件（`workspace/train/spike.lua` 依赖的名称，全部挂在 `STAGE` 下）：

```
BG        图片 100001  全屏 stretch
BALLAST   图片 100001  道砟  stretch-horizontal
RAIL_HI   图片 100001  上轨  stretch-horizontal
RAIL_LO   图片 100001  下轨  stretch-horizontal
TIE_0..5  图片 100001  轨枕  bottom-left
LOCO      图片 100002  车头  bottom-left  anchor/pivot 0,0  size 200×70  offset(100,400)
WAGON     图片 100003  车厢  bottom-left  anchor/pivot 0,0  size 120×70  offset(320,400)
F0..F5    图片 100001–100006  六帧同一矩形  bottom-left  anchor/pivot 0,0  size 140×140  offset(900,430)
HUD       文本框        bottom-left  anchor/pivot 0,0  size 600×40  offset(20,640)
```

> 模拟器只预览图元 `100001–100006`，其余 `imageId` 显示缺失框；`F0..F5` 用六个**不同图元**
> 代替真实 sprite 帧，是为了让「换帧」在截图上肉眼可辨。真机换真图属于步骤 4/7。

---

## 3. 预期值推导（不取自跑出来的数字）

### 3.1 换帧时刻

`dt = 1/30`，换帧落地为**整数 tick 分频**：`ticksPerFrame = round(0.12 / dt) = 4`。
（为什么不用「累加秒数 ≥ 0.12」：`0.12 / (1/30) = 3.6` 不是整数，累加器会落在 `0.12`
的浮点毛刺两侧，实测第 5、6 次换帧各早 1 帧 —— 见 `records/playtest.md`。整数分频可精确复现。）

switch 发生在 `tick % 4 == 0` 的帧，`idx = floor(tick / 4) % 6`：

| tick 区间 | idx | 时间区间（tick/30） |
|---|---|---|
| 0–3 | 0 | 0 – 0.100 |
| 4–7 | 1 | 0.133 – 0.233 |
| 8–11 | 2 | 0.267 – 0.367 |
| 12–15 | 3 | 0.400 – 0.500 |
| 16–19 | 4 | 0.533 – 0.633 |
| 20–23 | 5 | 0.667 – 0.767 |
| 24–27 | **0（绕回）** | 0.800 – 0.900 |

断言时刻取各区间中段（离边界 ≥1 tick）：`0.05→idx0`、`0.20→idx1`、`0.45→idx3`、
`0.70→idx5`、`0.85→idx0`。**`0.85` 处的 `idx0` 是"绕回"证据**，
单看前几次切换无法区分"循环"和"停在最后一帧"。

### 3.2 位置与尺寸

第 n 帧后：`LOCO.anchoredPositionX = 100 + 10n`、`WAGON.sizeDeltaX = 120 + 4n`。

断言时刻必须**落在步进区间内部**，不能压 `n/30` 边界：运行器的时间戳按 1e-9 取整
（`nextTick`），而 `1/30` 在该精度下不精确，压边界的 `at=0.5` 会滑到第 16 帧
（实测 `x=260`）。规则：`at × 30` 的小数部分取 0.4–0.6。

| 断言时刻 | `at×30` | 落到第 n 帧 | LOCO x | WAGON 宽 |
|---|---|---|---|---|
| 0 | 0 | 0 | 100 | 120 |
| 0.48 | 14.4 | 15 | 250 | 180 |
| 0.98 | 29.4 | 30 | 400 | 240 |

### 3.3 渲染位置（关键：区分"字段写进去了"和"画面真的动了"）

布局函数（`studio/ui/layout.js: computeRect`，Unity 语义）：

```
left = parentLeft + anchorMinX*parentW + offsetX - sizeX*pivotX
```

`STAGE` 为全屏 stretch（`parentLeft = 0`）；`LOCO` 取 `anchor=(0,0)`、`pivot=(0,0)`、`sizeX = 200`：

```
box.left == anchoredPositionX
```

于是 `box.left` 在 `t=0 / 0.48 / 0.98` 应为 `100 / 250 / 400`。
**字段可写 ≠ 画面跟随**；断言 `box.left` 才能证明运行时改动进入了渲染布局。

### 3.4 画布

`BG` 为双向 stretch ⇒ `width/height == 画布宽高`；轨道为水平 stretch ⇒ `width == 画布宽`。
同一份布局在两个 P0 画布上分别断言：

| 用例 | canvasId | BG 宽×高 | 轨道宽 |
|---|---|---|---|
| `m0-layout-mobile` | `mobile-16-9` | 1280×720 | 1280 |
| `m0-layout-pc` | `pc-16-9` | 1600×900 | 1600 |

`LOCO/F0..F5/HUD` 走 `anchor=bottom-left` 固定偏移，两个画布下坐标相同（PC 下留边，不裁切）。

---

## 4. 用例清单

| # | 用例名 | 断言要点 | 覆盖 |
|---|---|---|---|
| T1 | `m0-frames` | F0..F5 的 `active` 在推导时刻的值；HUD `text`；换帧日志；绕回 | P1 |
| T2 | `m0-move` | `anchoredPositionX`/`sizeDeltaX` 字段值 **且** `box.left` 同步变化 | P3' |
| T3 | `m0-layout-mobile` | 轨道/车/HUD 存在且激活、**六帧恰好一个激活**；stretch 控件宽度 == 1280 | P2 |
| T4 | `m0-layout-pc` | 同上，宽度 == 1600 | P2 |

> T3/T4 最初写成"六个帧控件全部激活"，在 Red 阶段恰好成立、Green 阶段必然失败。
> 那是用例把 Red 状态当成了期望，属于用例缺陷 —— 已改为"存在 + 恰一激活"，
> 与 P1 的规则一致（见 `records/playtest.md`）。

断言只用 `qxqy-autotest` 的 `control` / `tree` / `log` / `lua` 四类，不新造检查手段。

---

## 5. 有效 Red 的定义

骨架版 `spike.lua` 只保留 `OnInit` / `OnStart` / `OnUpdate` 三个空函数与一行 `print("M0 boot")`：

* 骨架能在模拟器里挂载、能启动试玩、控件齐全 ⇒ **不是路径 / JSON / 挂载故障**；
* 但 T1 的换帧断言、T2 的位置与尺寸断言全部失败 ⇒ 目标生产行为缺失。

Red 必须在 `runCase` 里复现为 T1/T2 的失败报告（含 `failedAt` 与现场快照），
而不是靠"我感觉没写"。

---

## 6. 本测试证明不了的事

| 事项 | 原因 |
|---|---|
| P3 3D 实体 + 运动器沿轨移动 | 模拟器是纯 2D UI+Lua，没有实体/运动器 |
| P4 界面控件叠在 3D 画面上 | 同上，无 3D 渲染 |
| 单网格 65,535 顶点上限、文本像素实际顶点数 | 模拟器不模拟顶点预算 |
| 真机上 `anchoredPositionX` 是否同样生效 | 模拟器绿灯不等于真机通过 |
| 官方素材（真实 `imageId`）的显示效果 | 模拟器只预览 6 个图元 |

以上一律标 `unknown`，需步骤 7 真机回传，不得用模拟器结果冒充。
