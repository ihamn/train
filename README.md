> **2026-10-10 网页小样已重写**：打开 [`prototype/index.html`](prototype/index.html) 或原路径 [`prototype/v2/index.html`](prototype/v2/index.html)。恢复设计文档的七档力模型、距离计分、过热与停靠；列车朝右。规则来源与试行参数见 [`prototype/README.md`](prototype/README.md)。下文为旧阶段记录，平台结论以带日期的真机记录为准。

> **2026-10-11 站间无尽首版**：开始面板选择“无尽远行”，每趟到站后继续下一趟或结束，累计成绩和里程保留。33 项模型/生成测试通过，手机手感待试玩；说明见 [`prototype/README.md`](prototype/README.md)。

> **2026-10-11 Lua v1**：[`workspace/train/train_game.lua`](workspace/train/train_game.lua) 是千星挂载用单文件，包含试行与无尽玩法。纯核心和网页经过相同驾驶输入对照；编辑器控件、美术与真机尚待接线验证，说明见 [`docs/lua-v1.md`](docs/lua-v1.md)。

> ## 🤖 给 AI / 新接手的人
> **先读 [`HANDOFF.md`](HANDOFF.md)** —— 那里有平台硬约束、已定的美术路线、
> 工具链用法、待办清单。读完那份就够接手，不需要读开发对话。

---

# train — 千星奇域「列车」项目

一个小游戏实验：**2.5D 等距视角的像素风列车游戏**，目标是投稿《千星之约·奇域创作大赛》。

## 这仓库里有什么

```
tools/                    工具链（Python + Pillow）
  make_train_sprite.py    程序化生成列车 sprite（参数可调）
  make_frames.py          底图 + sprite + 路径 → N 帧序列
  pixelize.py             照片 → 像素图（降采样/量化/抖动/抠背景）
  png2blocks.py           PNG → 文本像素网格（同色合并压缩）
cli_meta.py               ECMA-335 + IL 解析器（逆向用，独立）

至冬列车/                  列车 sprite 定稿
*.md                      设计文档与调研记录
```

## 核心设计文档

| 文件 | 内容 |
|---|---|
| `官方列车小游戏_实现汇总.md` | 原神 7.0 活动小游戏《开列车》的机制逆向汇总 |
| `列车小游戏_设计拆解.md` | 同一套机制的**设计原则**提炼（可迁移） |
| `列车仪表_加速度表与代偿.md` | 加速度表的推导过程与存疑清单 |
| `找火车游戏_线索整理.md` | 童年 Flash 火车游戏的寻找记录 |
| `找火车游戏_候选总表.md` | 跨站（4399/2345/7k7k/俄语站）候选清单 |

## 关键技术约束（已查证）

千星平台：
```
· 单网格顶点上限   65,535（每个「■」字符 ≈ 4 顶点）
· 运行时实体上限   1,000
· 没有字符串拼接节点 → 节点图里无法在运行时生成文本像素
                        （客户端 Lua 的 `..` 是标准能力，能否用它喂 textbox.text
                          生成文本像素尚未做探针，见 docs/tech-architecture.md §6）
· 界面控件运行时不能移动/改大小，只能【显示/隐藏】
  ⇒ 动画只能用「逐帧换图」实现
  ⚠️ 本条已于 2026-10-06 被证据取代（superseded）：
     官方《客户端控件API文档》(mhtakr07vej4) 把 anchoredPositionX/Y、sizeDeltaX/Y
     标为【读写 + Tweenable】；模拟器实测写入后 box.left 同步变化
     （tests/m0-move.case.json：250 / 400 与渲染布局一致）。
     ⇒ 动画可以走「1 张图 + 位置插值」，逐帧换图不再是唯一解。
     真机仍待验；详见 docs/production-plan.md 与 records/playtest.md。
```

因此本项目的美术路线是：
```
静态部分（轨道/地形/仪表盘） → 文本像素（设计时生成，1 个控件顶几十个）
动态部分（列车/指针）        → 【路线 A】1 张图 + 位置插值      ← 新增，模拟器已证可行
                               【路线 B】N 张预渲染帧 + 切换显示 ← 原方案，仍可用
                               A/B 取舍等真机确认（阻塞项 R1）
```

## 素材来源

列车外观参考自原神 7.0 至冬大世界列车的游戏内截图
（见 `至冬列车_素材设定图.png`，为手绘 sprite 的依据）。

## 环境

- Termux / Android
- Python 3 + Pillow
- git + gh（可选，用于推送）
