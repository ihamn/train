# 试玩与验证记录

每条都写清**来源**（HTML / 模拟器 / 真机）与**结果**。模拟器通过 ≠ 真机通过。

---

## 2026-10-06（本轮）· 模拟器 · M0 平台前提探针

运行端：`simulator`（千星沙箱 UI 模拟器，DSH 会话 `--D-train--`）
证据来源：`qxqy_studio_play` 用例回放、`qxqy_studio_play_screenshot`、`qxqy_studio_ui_screenshot`

### HTML 效果展示

**未做（n/a）**，并说明理由：本轮是 M0 **平台能力探针**，要回答的是
"千星能不能逐帧换图"、"界面控件运行时能不能移动"，HTML 无法回答其中任何一条；
它也不是体验/美术方向的判断，所以不触发"先给 HTML 判断好不好玩"这一步。
⇒ 步骤 3 的欠账记在 `docs/production-plan.md`，**M1 做内容前必须补齐**。

### 试玩结果

| 用例 | 结果 | 关键实测 |
|---|---|---|
| `m0-frames` | **Red → Green** | Red `failedAt 0.0667`（F1 `active=true`，期望 `false` —— 骨架不换帧）；Green 14/14 |
| `m0-move` | **Red → Green** | Red `failedAt 0.5333`（`anchoredPositionX=100`，期望 250）；Green 12/12 |
| `m0-layout-mobile` | Green 8/8 | BG 1280×720、轨道宽 1280、六帧恰一激活 |
| `m0-layout-pc` | Green 8/8 | BG 1600×900、轨道宽 1600、`LOCO.left=100`（与手机一致） |
| `m0-shot-f4` | Green 4/4 | tick=19：`F4` 激活、`F3` 否、`LOCO.left=290`、`WAGON.sizeDeltaX=196` |

换帧日志（Green，整数 tick 分频，每 4 tick 一帧）：
`idx=1@0.133 · 2@0.267 · 3@0.400 · 4@0.533 · 5@0.667 · 0@0.800`（绕回）。

稳定性：连续运行 863 帧 / 28.77 秒，帧循环与移动日志无中断，`mountError: null`。

### 截图（自洽性检查）

| 文件 | 帧 | HUD | 可见图元 | 车头 x | 车厢宽 | 自洽 |
|---|---|---|---|---|---|---|
| `records/m0/play-mobile-f38-frame3.png` | 38 | `frame=3` | 四角星（F3/100004） | 480 | 272 | ✓ |
| `records/m0/play-mobile-f70-frame5.png` | 70 | `frame=5` | 圆环（F5/100006） | 800 | 400 | ✓ |
| `records/m0/play-pc-f50-frame0.png` | 50 | `frame=0` | 方块（F0/100001） | 600 | 320 | ✓ |
| `records/m0/stage-editor-mobile-16-9.png` | — | — | 编辑器舞台：轨道 + 车 + 帧位 | 100 | 120 | ✓（设计值） |

三张试玩截图都是 `tick = 38/70/50`、`idx = floor(tick/4) % 6` 与 `x = 100+10·tick`、
`宽 = 120+4·tick` 的**互相印证**，不是"看起来对"。

### 本轮发现的缺陷与处理

1. **实现缺陷：帧计时浮点相位漂移。**
   首版用"累加秒数 ≥ `FRAME_INTERVAL`(0.12) 就换帧"。`0.12 ÷ (1/30) = 3.6` 不是整数，
   累加器反复落在 0.12 的浮点毛刺两侧，**实测第 5、6 次换帧各早 1 tick**
   （日志 `idx=5@0.6`、`idx=0@0.7333`，理想值是 0.6333/0.7667）。
   改为**整数 tick 分频**：`ticksPerFrame = round(0.12/dt) = 4`，`idx = floor(tick/4) % 6`。
   → 缺陷在实现，不在期望值；用例的期望值来自整数 tick 推导，未改。

2. **运行器边界：断言时刻不能压步进边界。**
   断言放在 `at=0.5` 时实测 `LOCO.anchoredPositionX=260`（第 16 帧），期望 250（第 15 帧）。
   原因不在 Lua：运行器 `nextTick` 把时间戳按 1e-9 取整，`1/30` 在该精度下不精确，
   压边界的断言会滑到下一帧。→ 断言时刻改到 `0.48 / 0.98`（`at×30` 小数部分 0.4–0.6）。
   已写进 `docs/tech-architecture.md` §5 与 `docs/tests-m0.md` §3.2。

3. **用例缺陷（我自己的）：T3/T4 把 Red 状态写成了期望。**
   `m0-layout-mobile/pc` 最初断言"六个帧控件全部 `active`" —— 在 Red 阶段恰好成立
   （骨架不换帧），到 Green 阶段必然失败（只剩一帧激活）。
   改为"存在 + 非帧控件激活 + 六帧恰一激活"，与 P1 的规则一致。

### 未验证（需真机，不要在报告里含糊过去）

* M0 前提③：3D 实体 + 运动器沿轨移动
* M0 前提④：界面控件叠在 3D 画面上
* 前提③' 在真机上是否同样成立（模拟器已成立）
* 顶点上限 65,535 / 运行时实体 1,000 / 控件预算
* 官方素材真实 `imageId` 的显示（模拟器只预览 100001–100006）
* 文本像素能否在运行时由 Lua 字符串拼接生成

---

## 2026-10-06（本轮）· 导出物 · 模拟器侧 GIA 往返校验

导出脚本：`tools/export_gia.mjs`（用模拟器自己的 `studio/index.js` 的 `exportData`/`importData`）。
产物：`workspace/train/export/`（整合包 21.3 KB、服务器控件模板 14.2 KB、脚本 3.4 KB、报告 4.7 KB）。

往返校验（把导出物重新导入全新 studio 再比对）：

| 导出物 | 结果 |
|---|---|
| 服务器控件模板.gia | 控件名 20/20，missing/extra 均空 |
| 脚本.gia | 路径与源码一致（挂载不带，符合"脚本 GIA 不含挂载"的既有说明） |
| 整合包.gia | 控件名 20/20；脚本路径/源码一致；**挂载保留** `n1` / `server-control-template` |

导出警告（一并列入真机待验）：HUD 垂直居中按**推定值**导出；新模板写显式空 `Info.related`；
未知 protobuf 字段不进入 Authoring JSON。

**这仍不是真机通过** —— 只证明模拟器编解码自洽。真机流程与逐条回传清单见
`docs/export-and-realdevice.md`。

`qxqy_script_sync` 状态：`config: null`、`discover: candidates: []`
⇒ 本机未配置实机脚本目录，脚本映射需在千星侧手动关联 `D:\train\workspace\train\spike.lua`。

---

## 真机记录

### 2026-10-06 · 本机 PC · 原神 7.1.0 + 千星沙箱编辑器 BeyondEditor

环境：原神装在 `E:\Genshin Impact`（窗口模式 1455×757），千星编辑器
`BeyondAssets\BeyondAssistEditor\BeyondEditor.exe`（与游戏 TCP 相连）；
本机 UID 目录 `BeyondLocal\190800866`，试玩关卡 `1073741826`。
**观察方式：全部由 AI 侧自动完成**（抓原神窗口 + 读游戏日志 + 扫关卡存档），用户不需要截图。

已确证：

| 项 | 证据 |
|---|---|
| GIA 已进千星 | `BeyondLocal\Beyond_Local_Export\` 三个导出物（18:28） |
| 关卡数据里有全部 20 个控件名 | 扫 `1073741826.gil` / `_1.gis`：`STAGE×6 LOCO×12 WAGON×12 RAIL_HI/RAIL_LO/BALLAST/TIE_0/TIE_5/BG×2 HUD/F0/F5×4` |
| 客户端脚本落盘且与交付源码一致 | `external_lua_file\default_import_file\workspace\train\spike.lua` = UTF-8 BOM(3B) + 我的 3306B，去掉 BOM 后逐字节相同 |
| **两次试玩真的启动了** | `18:45:11.870` 与 `18:48:01.870` 各一次 `BeyondLevelPlayModule SetCurLevelData guid:0 … isTrial:True`；第一次于 `18:46:05` 进 `BeyondSettleScene` |
| **试玩里没有我的 UI** | 18:51:25 抓原神窗口：3D 草地 + 角色 + 小地图 + 退出按钮，**没有 HUD 文字、没有轨道、没有列车**（连文本框都没有） |
| 未见脚本致命错误 | 无 `ErrorLog.txt`（按官方说明，只有正常日志报不出的错才生成） |
| 编辑器侧一次连接失败 | 编辑器日志 18:48:04 `Tcp Connector fail`（编辑器↔游戏 TCP 被拒，当时游戏正在切场景；随后重连成功） |

### 真机第二轮（同日 18:48 / 18:57 试玩）—— 找到真根因

**✗ 我在第一轮写的"容器没放进关卡"判断是错的，此处更正。** 证据来自千星自己导出的客户端脚本日志：
`...\BeyondLocal\190800866\Beyond_Debug_Log\2026-10-06_18-48-05_155_190800866.gia`

```
M0 boot                    ← OnInit 执行了：脚本挂载正常、容器激活正常
M0 missing train controls  ← OnStart 里 root:FindChild("LOCO") 返回 nil（命中我的守卫分支）
```

⇒ 真正的根因是**控件查找 API**，不是容器放置：
官方《客户端控件API文档》里 `FindChild(path)` 是"按路径查找子控件"，
**直接子控件对应的是 `GetChild(name)`**。模拟器对裸名字宽容（`observed-contract` 写的
"无斜杠也可找直接子节点"是模拟器策略），真机不认。

修复（`workspace/train/spike.lua`）：查找改为 `GetChild` → `FindChild` → 深度优先扫描三级，
并**把查找方式与真实层级打进客户端脚本日志**（失败时 dump 两层控件名），
让下一轮真机日志直接给出答案，而不是再靠猜。

模拟器回归：`m0-frames-v2` 10/10、`m0-move-v2` 6/6 全绿；
日志显示 `M0 mount name=STAGE prefab=1073742001` / `M0 resolve loco=GetChild wagon=GetChild hud=GetChild`
⇒ 模拟器同样走 `GetChild` 成功，两个运行端语义一致。

**观察通道升级**：真机不再需要人截图或读日志——
* `tools/watch-realdevice.ps1` 轮询 `Beyond_Debug_Log`，新 dump 自动复制 + 解码成文本
* 同一脚本在检测到 `isTrial:True` 时自动连拍原神窗口（18:57 那次就是这么拍到的）
* `tools/capture-play.ps1` / `tools/focus-window.ps1` 分别负责"盯试玩连拍"与"按窗口抓图"

**脚本下发（18:59 配置）**：`qxqy_script_sync` 配置已写入存档
（`workspaceDir/clientSubdir = workspace/train`，
`clientImportRoot = ...\1073741826\external_lua_file\default_import_file`），
preview 结果：`status: 覆盖`、`beforeHash 3ea3204e…`（设备上的旧内容）、
`pendingGuidChanges: 0`、`sourceMismatch: false`。**复制需用户点一次「确认复制」**（AI 不绕过该确认）。

**待清理**：设备上 `spike.lua` 与 `spike_1.lua` 内容相同、关卡里两个都被引用
（`spike×6 / spike_1×2 / workspace/train×4`），像是建了两个脚本映射；建议删掉一个。

真机回归 R1（换帧）/R2（移动）/R4（UI 叠 3D）**仍待下一轮试玩**。

### 真机第三轮（准备中）—— 两条更正 + 探针升级

**更正 1（我之前的预判是错的）**：我曾判断 `100001–100006` 是"模拟器占位图元、真机会显示缺失框"。
查用户自己的 [`千星素材号实测表.md`](../千星素材号实测表.md)（或 `D:\moniji\千星素材号实测表.md`）：
**它们是真实的官方素材号**——"基础形状"分类 = 方块 / 圆形 / 三角形 / 四角星 / 五角星 / 圆环，
且实测过"100001 拉长不糊"、这几个号**确实出现在真实关卡 `.gil` 里**。
所以 M0 探针用的图元在真机上会正常渲染，不是假号。

同时记下两条对 M1 有用的素材结论（同一份表）：
* **底板-单色 `106xxx`** 才是做底衬/进度条/线框的正路（`106036/106050/106051` 线框、
  `106044/106062/106063` 长条、`106091~106096` 渐变长条），但它们**尚未在真机验证**
* 素材号（`100xxx`）与模板索引（`1073741xxx`）是**两套数字**，不要混用

**更正 2**：18:57 那批连拍里我看到的"编辑器界面"画面其实是**沙箱编辑器视图**，
加上 19:12 那批拍到了浏览器窗口（`SetForegroundWindow` 从后台进程被系统拒绝），
所以"试玩里没有 UI"这个结论**目前的证据是 18:51 那张**运行时画面（3D 草地 + 角色 + 小地图，
连满屏深色 `BG` 都没出现）。截图这条通道对遮挡不鲁棒，**脚本日志才是主仪器**。

**探针升级（真机自诊断 + 自愈）**：`spike.lua` 在 `OnStart` 现在会打印
`GetUICanvasSize()`、`GetClientUIRoots()` 数量与名字、每个控件的
`active / visible / activeInHierarchy` 原始值，然后 `SetActive(true)+SetVisible(true)`
主动打开（`apply_frame` 之后仍只留一帧可见）。
依据：官方加工稿写客户端控件 `active` **默认为 false**，而容器是活的（脚本在跑），
所以"子控件未激活"是当前首要嫌疑，这一轮日志会直接给出答案。

**无头回归**：新增 `tools/run-cases.mjs`（与 DSH `runCase` 同一套 `createStudio → playRunCase → replayCase`
代码路径，但只输出判定，不再每次吞几百 KB 快照）：

```
## m0-frames  PASS (14/14)   ## m0-layout-mobile PASS (8/8)
## m0-layout-pc PASS (8/8)  ## m0-move PASS (12/12)      ALL GREEN (42 asserts)
```

### 真机第四轮 —— 外部代码复查抓到一个我自己的致命 bug

外部复查（另一位 AI 看代码）指出：v3 的"自愈"写在**致命 `return` 之后**，永远执行不到。
**我核对了，确认成立，这是我的 bug：**

```lua
if loco == nil or wagon == nil or hud == nil then
  ... dump ...
  printerr("M0 missing train controls ...")
  return                     -- ★ 早退：后面全部跳过
end
force_show(root, "STAGE")    -- ← 自愈在这之后，永远不执行
apply_frame(0)               -- ← 连"点亮第一帧"也没了
```

⇒ 真机只要按名字找不到任一控件，就**一个 `SetActive(true)` 都不会发生**。
**第二轮"连满屏深色 BG 都没出现"与"控件找不到"是同一件事，不是两个问题**
（BG 属于没被点亮的那些子控件）。第一轮日志最后一行正是 `M0 missing train controls`，
即真机走的就是这条 return ⇒ v3 的自愈从未生效。

同时确认：外部指出的另外三条也成立或未证伪，已全部转成 v4 的可观测项：

| 外部判断 | 我的处理 |
|---|---|
| 靠 `name` 找控件在真机不可靠（`name` 是编辑器备注名还是引擎名，两轮日志都没证明） | v4 加 **census**：把直接子控件的真实 `name`/`prefab`/`active`/`visible` 全打出来 |
| 容器状态客户端改不了，得在编辑器确认 | 成立。我此前"`M0 boot` ⇒ 容器开着"是**从模拟器模型外推**，不是真机证据，已降级为待确认 |
| `anchoredPositionX`/`sizeDeltaX` 可能只读（写了不报错也不生效） | v4 加 **writeback**：写后读回打分，读回不一致即可判定只读 |
| `script:EnableUpdate` 该用点号 | 官方文档写的是冒号、模拟器也接受冒号（`colon=true`），真机未证 ⇒ v4 冒号失败自动退点号，并加 **OnUpdate 存活日志**（`tick=1/30` 必打） |

**v4 行为**：先 `force_show(root)`；缺失只 `note_missing`（一条 `M0 missing list=…` 汇总），
**绝不早退**；找不齐也照样进 `OnUpdate` 打存活证据。模拟器仍 **ALL GREEN（42 断言）**，
日志形状：`M0 enableUpdate colon=true` → `M0 show STAGE …` → `M0 canvas=…` → `M0 roots=1` →
`M0 census children=19` → `M0 child[1] name=HUD …`。

**未采纳（暂缓而非否定）**：外部建议的第二步"别靠名字，用
`InstantiateClientUIControl(模板索引, …)` 在 OnStart 里自建控件"。
理由与顺序：官方文档要求**只有存为模板的客户端控件父节点**才支持动态创建，
而当前工程只有 GIA 导入进来的服务端控件模板，且**真机导入可能重排模板索引**。
先用 v4 的 census 把"真机上到底有什么、叫什么、什么状态"变成事实，再决定要不要走实例化。

**卡点（决定"代码问题"还是"编辑器问题"）**：编辑器里那个「客户端控件容器」当前是否
**激活 + 可见**？若不是，客户端 Lua 怎么改都无效（容器是服务端控件，可能还要服务端节点图
`显示界面控件`）；若是，则问题基本落在"名字/层级"这一层。

抓屏脚本：`tools/capture-play.ps1`（盯日志自动连拍**原神窗口**）、`tools/focus-window.ps1`
（枚举顶层窗口、提到前台、按窗口抓图）。两者都只做只读观察，不改游戏状态。

### 真机第五轮 —— 改成 zuma 架构（v5），并厘清几何约定

**触发**：查用户自己已上线的工程 `zuma.lua`（设备上的 214 KB 版本），得到一批**真机已验证**的契约，
把前面所有推断校正过来：

| 真机结论（来源：zuma.lua 注释与代码） | 影响 |
|---|---|
| `InstantiateClientUIControl` ×9、`GetChild`/`FindChild` **×0** | 本工程的 UI 全是**运行时按模板建**的；"按名字找"根本不适用 |
| `SetImage` ×6、`.imageId =` ×0 | 运行时换图走 `SetImage`（`imageId` 只读） |
| `SetAnchoredPosition` ×6、`SetSizeDelta` ×8、`.anchoredPositionX =` **×0** | 运行时移动/改尺寸**可行**，但要用**方法式**；字段式未经验证 |
| `visible` 是**只读字段**（写会报）；`imageType` 真机只读 | 统一走 `SetVisible` |
| `EnableUpdate` 不开就没有 `OnUpdate` | 冒号写法正确，外部说的"该用点号"**不成立** |
| `GetClientUIRoots()` = 显示中的容器画布默认容器节点，**0 = 没有可见画布** | 空屏的第一判据 |
| 挂载点 **0×0 会裁掉全部子控件**："脚本全跑通、屏幕全空" | 已写进脚本（`SetSizeDelta(画布)` 兜底） |
| 模板索引是 2^30 起的大数字，可用 `typeof()` 探针自动认 | v5 的 `detect_templates` 直接复用该思路 |
| 平台上限：**单控件组 1000 / 单屏 10000** | 20 个控件远未触顶 |

**v5 的改动**：存档里**故意不再摆控件**（服务端控件模板留空：`客户端控件容器 → STAGE`），
`spike.lua` 在 `OnStart` 里探测模板索引 → 建 15 个控件（BG/道砟/双轨/6 轨枕/车头/车厢/6 帧/HUD）→
几何**显式钉死**锚点(0,0)+中心(0,0) → 用 `SetImage` 设素材 → 用方法式写位置/尺寸。

**几何约定的厘清**（这条以前搞错过）：
`SetAnchoredPosition` 相对**父矩形左下角**。运行时挂载点矩形以原点为中心
（模拟器实测 `STAGE.left = −640`，即 −W/2），**与真机一致** ——
zuma 里的 `SetAnchoredPosition(0, -h/2 + 20)` 正是"画布中心下方 20"。
⇒ box 坐标 = 画布坐标 − W/2；用例期望值必须按这个空间推，不能沿用编辑器空间。

**模拟器回归（无头）**：
```
## m0-frames PASS (14/14)  ## m0-layout-mobile PASS (8/8)
## m0-layout-pc PASS (8/8) ## m0-move PASS (12/12)   ALL GREEN (42 asserts)
```
真机日志里应出现的关键行：`M0 detect image=… (ClientUIImageControl) text=… (ClientUITextBoxControl)`
→ `M0 start built=15 missing=0` → `M0 update tick=1` → `M0 writeback x=… want=…`。

**⚠️ 现场被重置**（用户误删存档后重建）：`BeyondLocal` 下现在只剩关卡 **1073741825**，
`external_lua_file` 与 `Beyond_Debug_Log` **均为空** ⇒ 上一轮的 zuma 脚本与我的 spike.lua 都不在了，
需要按 `docs/export-and-realdevice.md` §1.5 的**三件事**重做（单控件模板 ×2 + 容器 + 平铺映射），
**不再需要导入 GIA**。

### 真机第六轮 —— UI 首次出现（20:29），随后一次卡死（20:35），已定位并回退

**20:29 那一轮的 dump（22.9 KB，v5 脚本）是决定性的：**

```
M0 canvas=1814.8623046875x899.99981689453   ← 真机画布是浮点
M0 roots=0                                   ← 官方判据"没有显示中的画布"（待解）
M0 mount name=                               ← 挂载控件没有名字
M0 detect image=1073741852 text=1073741851   ← 自动认到本工程 zuma 的模板
M0 start built=15 missing=0
M0 update tick=1 … 420+                      ← OnUpdate 真机在跑（14 秒无错）
M0 writeback x=110/400/700… = want            ← SetAnchoredPosition 真机生效
M0 writeback w=124/240/360… = want            ← SetSizeDelta 真机生效
（无一条 M0 writefail）
```

⇒ **M0 的 ①（逐帧更新/换帧）、②（控件拼轨道）、③′（运行时移动/改尺寸）、④（UI 叠在 3D 上）
在真机上都有了证据**；只剩 ③（3D 实体 + 运动器）未验证。
用户肉眼反馈：**"出现东西了，但只盖住左下角"** ⇒ 渲染成立、范围被裁。

**20:35 真机卡死**（`YuanShen` PID 4420 `Responding=False`、CPU 已 2119 秒）。
`Stop-Process` 与 `taskkill /F` **都无法结束它**（原神反作弊保护），后来自行退出；当前实例健康。

**归因与回退**：v5 → v5.3 只多了两处改动，都指向嫌疑，已全部回退成 v6：
1. 对**挂载点**做 `SetAnchorMin/SetAnchorMax/SetPivot/SetAnchoredPosition`
   （挂载点很可能是 zuma 自己的容器，动它的几何会牵动宿主工程的布局）
2. 满屏元素改用**拉伸锚点**（`anchorMin(0,0)+anchorMax(1,1)`）
3. 另外把模板探测窗口从 `2^30+1..+512` 收窄到两个实测窗口（探测次数 ~60 → ~35）

**教训（写进规范）**：真机上**不要改挂载点的锚点/中心/位置**；拉伸锚点先别用；
探测窗口要窄。v6 已推送设备（`6C9D2A572E15`），模拟器回归 **ALL GREEN（42 断言）**。

### 事故收尾（同日）—— 服务端自行清理，未走客服

用户反馈：**未联系客服解决，服务端自己把卡住的关卡会话清掉了**，账号恢复正常。
（此前备好的客服材料包保留在 `records/support-2026-10-06/` 与
`records/客服材料_2026-10-06.zip`，作为事故证据与"下次直接复用"的模板。）

**性质定性**：**AI 侧的实现失误** —— 改动（v5.3）未经真机最小验证就上线，
导致关卡包里的客户端脚本令客户端无响应；且因为服务端会在登录后自动把玩家送进该关卡，
用户**没有任何自助手段**脱困。**不是平台缺陷**。

**硬性规则已写入 [`docs/tech-architecture.md`](../docs/tech-architecture.md) §7**，
后续任何真机工作必须遵守（不改挂载点几何 / 不用拉伸锚点 / 探测窗口收窄 /
真机探针先只读诊断再建控件 / 先备一键停用 / 改脚本必须保存关卡）。

### 真机第七轮 —— v8 也卡死：我两次判断都错了，改用阶梯式隔离测试

**2026-10-07 时间线**：只读探针真机跑通（12/12、负向断言成立、零风险）→ 把 v8（自建容器方案）
放上设备 → 用户保存关卡（11:09）→ 试玩 → **客户端再次无响应**
（`Responding=False`、CPU 已 3895 秒、进程杀不掉，只能重启电脑）。

**关键证据**：这次**连一条客户端脚本日志都没有**（最后一条 dump 仍是 11:08 只读探针的）
⇒ 挂住的位置在"建控件日志之前"，即 `OnInit/OnStart` 的很早期。

**两个被推翻的判断（记录在案）**：

1. ❌「卡死嫌疑 = 改挂载点几何 + 拉伸锚点」—— v8 **完全没碰挂载点**，仍然卡死
2. ❌「模拟器全绿 ⇒ 真机基本稳」—— 同一份代码模拟器 42 断言全绿，真机直接冻；
   **模拟器不能复现这一类平台级挂死**，绿灯不等于安全

**新的首要嫌疑**：v8 相对**真机已验证安全**的 v5 新增三件事 ——
① 自建容器 ② 容器嵌套 15 个控件 ③ **带轴参数的方法调用** `GetAnchorMin(1)/GetAnchorMax(1)/GetPivot(1)`。
其中 ③ 发生在所有建控件动作**之前**，与"无任何日志"的现象吻合
（模拟器的 Lua 绑定接受这种写法，真机原生绑定未必接受）。

**做法改变（硬规则）**：

* **不再在用户自己的 zuma 关卡（`1073741825`）里做真机测试** —— 它同时是用户的作品，风险不可接受
* 真机测试改用**独立空关卡**（只放一个客户端控件容器 + 我们的脚本映射，与 zuma 完全隔离）
* **阶梯式递增**：每步只加一个新动作，且上一步必须是真机已验证安全的 ——
  ① 只打日志（✅ 已验证安全）→ ② 直接在挂载点下建 15 个控件（✅ 已验证安全，只是会偏）→
  ③ 自建容器（❓ 就是这步冻的，v9 要去掉轴参数调用重做）
* 事故材料：`records/support-2026-10-06/追加_第二次无响应_2026-10-07.md`
  （含 output_log 两件 + 卡死截图 + 可复制的客服话术）
