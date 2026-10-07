# 制作计划与当前进度

跨会话接手先读这份 + `HANDOFF.md`。七步工作流见 `qxqy-game-studio`。

## 当前步骤

**步骤 5–6 + 真机（M0 平台前提探针）—— ④b 已诊断，待验修复方案：**

> ⚠️ 前提 **③「3D 实体 + 运动器」已作废**：本工程是**全 UI 控件**实现（2D+Lua），
> 没有 3D 实体这条路线（用户 2026-10-07 明确澄清）。M0 其余前提均已在真机取证。

**④b「真机 UI 只盖住左下角」= 已诊断（2026-10-07 真机只读探针取证）：**
挂载点 `prefabIndex=1073741846`、`sizeDelta=380×1080`、`GetAnchorMin.x=0`、
`GetAnchorMax.x=1`（**水平拉伸**）、`GetPivot=0.5` ⇒ 解析矩形 **2060×1080、左下角 (−1030,−540)**，
画布只有 x∈[0,1030]/y∈[0,540] 的交集可见。v5 的控件按画布坐标摆在**挂载点左下角**，
所以只露出右上一点。**结论：挂载点不能当布局父级。**
`roots=0` 同时被否证为"有没有 UI"的判据（真机 UI 明明渲染了），见 `docs/tech-architecture.md` §6。

**下一步（v8，需用户点头）**：自建容器方案 ——
① `InstantiateClientUIControl(1073741846, 挂载点)` 建**我们自己的**容器；
② 只对它显式钉几何（锚点 (0,0)/(0,0)、pivot (0,0)、pos (0,0)、size=画布）；
③ 15 个控件全挂它下面 ⇒ 坐标回归干净的画布坐标。
**所有写入都发生在自建控件上，一个动作都不碰宿主的挂载点**（§7 规则 1）；
强先例：zuma 自己的游戏就是 9 次 `InstantiateClientUIControl`，真机运行正常。

**收口方式（v7 已就绪、模拟器 12/12 绿，待用户点头再上真机）**：
`workspace/train/probe_readonly.lua` —— 只打印 `typeof(script.object)`、挂载点
`name/size/pos/scale/active/visible/inHierarchy/prefabIndex/…`、父级几何、`GetAnchor*/GetPivot/GetSizeDelta`
是否能调、`GetUICanvasSize`、`GetClientUIRoots` 数量与名字；**不建控件、不改几何、不开探测扫描**。
用例 `tests/probe-readonly.case.json` 有 12 条断言，其中 5 条是**负向断言**（必须没有
`M0 detect` / `M0 start built=` / `M0 writefail` / `M0 mount pinned`，且 `LOCO`、`BG` 必须不存在）
—— 事故后的硬性要求。

跑法（模拟器，不需要真机）：

```powershell
python -c "import json,pathlib;p=pathlib.Path('workspace/train/train.save.json');d=json.loads(p.read_text(encoding='utf-8'));s=pathlib.Path('workspace/train/probe_readonly.lua').read_text(encoding='utf-8');[e.__setitem__('source',s) for e in d['assets']['scripts']];p.write_text(json.dumps(d,ensure_ascii=False),encoding='utf-8')"
$env:QXQY_STUDIO="D:/miliastra-beyond-simulator/studio/index.js"; node tools/run-cases.mjs tests/probe-readonly.case.json
git checkout -- workspace/train/train.save.json   # 跑完还原交付存档
```

2026-10-07 实测结果：`m0-readonly PASS (12/12)`；模拟器日志形状
`M0 boot → M0 readonly probe → M0 canvas=… → M0 roots=1 → M0 mount type=… size=0x0 … → M0 update tick=1`。

**步骤 3（HTML）不在本轮**：M0 是能力探针，HTML 答不了 ③/④b/roots 任何一条
（这也是它在 M0 阶段被跳过的同一个理由）。**M0 收口后**才按 M1 的 P0 范围补步骤 3。

已完成的步骤：
* 步骤 1 策划案 —— 设计文档已在仓库里，`docs/gdd.md` 是汇总入口（本轮未新增玩法设计）
* 步骤 2 TDD 用例 —— `docs/tests-m0.md` + `tests/m0-*.case.json`（**先写用例，后写 Lua**），42 断言全绿
* 步骤 4 素材 —— 复用已有 `至冬列车/列车_64x20.png` 与 `序列帧_测试.png`；模拟器内用图元 100001–100006 代位
* 步骤 5–6 —— `workspace/train/spike.lua`（v6，运行时按模板建控件）+ `train.save.json`（完整存档）
* 步骤 7（部分）—— 真机四前提取证，见 `records/playtest.md` 第五、六轮

## 本轮退出证据

| 用例 | 断言数 | Red | Green |
|---|---|---|---|
| `m0-frames`（逐帧换图 P1） | 14 | ✗ `failedAt 0.0667` | ✓ 14/14 |
| `m0-move`（运行时移动/改大小 P3'） | 12 | ✗ `failedAt 0.5333` | ✓ 12/12 |
| `m0-layout-mobile`（P2 轨道 + 1280×720） | 8 | ✓（几何锁） | ✓ 8/8 |
| `m0-layout-pc`（P2 轨道 + 1600×900） | 8 | ✓（几何锁） | ✓ 8/8 |
| `m0-shot-f4`（截图检查点） | 4 | — | ✓ 4/4 |

截图：`records/m0/`（手机 ×2 不同帧、PC ×1、编辑器舞台 ×1）。
另有 28.8 秒连续运行记录（863 帧）无报错、`mountError: null`。

## 结论（对 M0 四前提的回答）

真机证据见 `records/playtest.md`「真机第五/六轮」：客户端脚本 dump
`M0 start built=15 missing=0`、`M0 update tick=1…420+`、
`M0 writeback x/w = want`（逐帧一致）、`M0 canvas=1814.86x900`、`roots=0`。

| 前提 | 结论 | 证据强度 |
|---|---|---|
| ① 逐帧换图可行 | **成立** | 模拟器用例（14 断言）+ 截图 + 28s 连续运行 + **真机 `OnUpdate` 在跑** |
| ② 能摆一条轨道 | **成立（UI 层）** | 模拟器用例（8+8 断言）+ 截图 + **真机 15 控件全建成** |
| ③ 实体沿运动器移动 | **未验证** | 模拟器测不了；需在编辑器里摆实体，属用户侧动作 |
| ③' 控件运行时移动/改大小 | **成立** | 模拟器（12 断言，字段+渲染双证）+ **真机方法式写回与目标逐帧一致** |
| ④ 控件叠在 3D 画面上 | **成立（叠加本身）／范围未解** | **真机**：客户端 UI 已画在关卡画面上；但只盖住左下角，裁定为**挂载点几何**问题，尚未取到证据（见"当前步骤"） |

⚠️ **同轮出了一次客户端无响应事故**（v5.3 改动导致，关卡被服务端续进、任何端进去都卡）。
复盘、性质定性与**真机硬性规则**见 `docs/tech-architecture.md` §7；
客服材料包见 `records/support-2026-10-06/`。**真机操作前必须重读该节。**

## 这对美术路线的影响（重要）

`HANDOFF.md`/`README.md` 原记录：「界面控件运行时不能移动/改大小 ⇒ 动画只能用逐帧换图」。
官方《客户端控件API文档》把 `anchoredPositionX/Y`、`sizeDeltaX/Y` 标为**读写 + Tweenable**，
模拟器实测也确认写入后渲染布局跟随。**因此"只能逐帧换图"这条前提不再成立**，
`tools/make_frames.py` 那条"预渲染 N 帧"的路线从**唯一解**变成**备选之一**。

下一步该做的取舍（在真机上确认后再定）：
* 路线 A：1 张列车图 + `anchoredPositionX` 插值 / 每帧写位置 ⇒ 省掉整条帧序列流水线，也省图片控件
* 路线 B：预渲染 N 帧 + 切换显示 ⇒ 需要帧序列工具链，但完全避开对运行时写入的依赖
* 建议 M0.5：真机上放 1 个图片控件，脚本里 `anchoredPositionX` 逐帧累加 + `game.Tween`，用肉眼/录像确认跟手

## 阻塞项

1. **真机验证**（P3 实体/运动器、P4 3D 叠加、以及 ③' 在真机是否成立）——需要用户在有千星沙箱的设备上跑。
2. **顶点/控件预算**（65,535 顶点、1,000 实体）——模拟器不模拟，需要真机或官方工具核对。
3. **文本像素能否运行时生成**——见 `docs/tech-architecture.md` §6 最后一条。

## 下一步（按优先级）

1. **真机验证（导出物已就绪）**：导入 `workspace/train/export/列车 M0 探针 · 整合包.gia` 到千星沙箱，
   按 `docs/export-and-realdevice.md` §4 的 R1–R6 逐条回传。模拟器侧往返已校验
   （控件 20/20、脚本源码一致、挂载保留），但那**不是真机通过**。
2. 依据真机结果定动画路线 A/B（见上）
3. 补步骤 3 HTML（列车沿轨 + 档位/速度/轴温仪表的最小体验）
4. 进 M1：轨道 + 列车沿轨移动，把 `spike.lua` 的探针逻辑换成真实玩法状态机
