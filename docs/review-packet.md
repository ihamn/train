# 给 ChatGPT 的审核包（一屏，可直接粘贴）

> 你是谁：写出 `workspace/train/train_core.lua` / `train_client.template.lua` / `train_game.lua`
> 与 `prototype/` 的 AI。下面是**别人（DSH 会话）**在模拟器/真机上把你的代码接进千星之后的改动与实测结论。
> 请做**逐条 diff 级审核 + 回答文末 4 个问题**，不要重写整份代码。

## 一、这次改了你三个地方（都在 `train_client.template.lua`，已重新打包 `train_game.lua`）

1. **补 `showCursor = true`**（`OnStart` 里，pcall 包住 + 打印结果）
   原因：平台事实里 `AddCursorEventListener` 的前置条件是控件要能显示常驻光标；**实测真机运行时可写**
   （日志 `TRAIN showCursor=true`）⇒ 你认下的"遗漏"已补上并验证。

2. **`bind()` 包 `pcall` 并计数**，`OnStart` 末尾打印 `TRAIN bound=N failed=M`
   原因：**模拟器未实现 `AddCursorEventListener`** ⇒ 一条 API 缺口会让整段接线验证中断（实测
   `TRAIN stopped: train.lua:324: attempt to call a nil value (method 'AddCursorEventListener')`）。
   包住后模拟器能跑完，真机/模拟器各自通过这行日志自报有没有这个 API（模拟器实测 `bound=0 failed=8`）。

3. **表盘改用「实心圆 100002 + 径向填充 `fillAmount`」，替代你原来的 37+43 帧美术**
   原因：80 帧 = 80 个控件 + **80 张要上传的素材**，是整条链路里最重最易错的一段。
   现在：`SPEED_DIAL` / `TEMP_DIAL` 两个图片控件，`enableFill=true / fillType=Radial360`，
   脚本每帧按 `fill('SPEED_DIAL', v.speedAngle/180)`、`fill('TEMP_DIAL', v.temperatureAngle/210)` 写
   `fillAmount`（0..1，带脏检查；不可写时只打一行日志，不刷屏）。
   **你原来的 `SPEED_F*` / `TEMP_F*` 查找代码保留未删** ⇒ 那些控件不存在时 `visible()` 自动跳过（无副作用）。

## 二、已实测的平台事实（**这部分请当作前提，不要再推测**）

| 事实 | 证据 |
|---|---|
| 布局基准 = 手机 16:9(**1280×720**)，PC 由锚点/留边容纳 | 千星模拟器技能明文规定；已按此重排 |
| `root.showCursor = true` **运行时可写** | 真机 ✔ + 模拟器 ✔ |
| `FindChild(name)` 与**层级路径**（`PROGRESS/SEG1`、`SCENE/TIE1`、`DIAL/TARGET_RANGE`）成立 | 模拟器：你 `names` 表里的 50 个控件**全部找到**，越过了"缺少控件"断言 |
| **模拟器没有 `AddCursorEventListener`** | `TRAIN bound=0 failed=8`（真机待你那边/真机日志确认） |
| 模拟器只画 `100001–100006` 图元，其他显示"缺失框" | 出图实测（真机正常） |
| 文本框**没有行间距参数** | 官方编辑器 + 客户端 API 文档 0 次出现；行距只能靠"一行一个文本框" |
| 锚点/轴心是**字段**（`anchorMinX/pivotX`），`SetAnchorMin/SetAnchorMax/SetPivot` **不存在** | 真机两次卡死换来的结论 |
| 顶点上限 **65535**；文本长度上限 ~1500 字符（超了只记日志不抛错） | 用户确认 + 真机日志 |
| 关卡存的是**导入那一刻的脚本副本** ⇒ 改文件后必须重新导入 | 真机踩过 |

## 三、我按你的契约摆出来的控件树（50 个，画布 1280×720）

```
客户端控件容器(服务端资源分组)
└─ TRAIN_UI(容器节点，脚本挂这里；showCursor=true；1280×720)
   ├─ HINT / HINT_BG / SPEED / GEAR / TEMP / SCORE / TARGET / STATUS      (8)
   ├─ SPEED_DIAL / TEMP_DIAL + 两个标签                                     (4)
   ├─ START / UP / DOWN / PAUSE / CONTINUE / END / TRIAL / ENDLESS          (8)  ← 图片，可点击
   │   每个按钮上方叠一个 <名字>_T 文本框当标签                             (8)
   ├─ PROGRESS(容器 600×56)  ├ PROGRESS_MARKER + SEG1..SEG11               (12)
   ├─ SCENE(容器 720×140)    └ TIE1..TIE4                                  (4)
   └─ DIAL(容器 240×40)      └ TARGET_RANGE                                (1)
```
素材号：加速档按钮 `100148`、减速档 `100147`（用户指定）、播放 `100181`、
结束 `100102`、续行 `100166`、试玩 `100187`、无尽 `100188`、暂停 `100158`；
底板统一 `100001`（可拉长不糊）；表盘底 `100002`。

## 四、请你回答这 4 个问题

1. **表盘改动是否可接受**：你原设计是 37/43 帧固定美术（每帧 5°，为避免依赖未验证的旋转属性）。
   改成"实心圆 + 径向填充"后角度是连续的 ⇒ 精度更好，但**视觉语言变了**（扇形而不是指针）。
   在你看来，为了"0 张上传素材"换掉指针是否划算？如果保留指针，你建议哪条不依赖旋转属性的做法？
2. **归一化映射对不对**：你用 `speedAngle=180*speed/120`、`temperatureAngle=210*heat`。
   我把它们除以 180 / 210 作为 `fillAmount` ⇒ 即 `speed/120`、`heat`。这符合你的本意吗？
   （`fillAmount` 从哪个方向起算、是否需要 `fillRadial360Type` 对齐，我按"文档字段"处理，未做视觉微调。）
3. **`names` 表里的 80 个帧控件**：现在树里没有它们（`visible()` 会跳过 ⇒ 无副作用）。
   你希望**从查找表里删掉**（省 80 次查找与一次 hide 循环），还是保留以备将来做指针？
4. **`train_core.lua` 是否还有布局耦合**：你确认过网页原型那套 720×1280 竖屏只是网页设计尺寸。
   我按横屏重排了控件树。请确认 `train_core.lua` / `view()` 的返回值里**没有任何**依赖具体像素尺寸的东西
   （我扫过一遍没发现，但你对这份代码更熟）。

## 五、我这边接下来做的（不需要你改）

* 补一个 `qxqy-autotest` 用例把"控件齐、文案对、渲染不报错"钉住
* 导出 GIA → 真机导入 → 实机试玩（`TRAIN bound=? failed=?` 会告诉我们真机有没有 `AddCursorEventListener`）
