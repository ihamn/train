#!/usr/bin/env python3
"""校验 workspace/train/train.save.json + train_game.lua 的一致性（每次改动后跑）。

这些检查项都来自**真实踩坑**：
  · 控件越出画布 ⇒ 出图才发现被裁（表盘 y=580+220=800 > 720）
  · PROGRESS 容器窄于脚本定位上限 ⇒ 末端游标越出容器（560 < 600+8）
  · 两个表盘重叠 ⇒ 220 直径只隔 180，重叠 40px
  · 同级顺序错 ⇒ 【先出现的在上层】；标签若晚于底板出现，会被不透明底板盖住
  · 表盘控件不在查找表里 ⇒ controls.SPEED_DIAL 永远 nil、填充代码整段被跳过（ChatGPT 审核发现）
  · 径向填充用 angle 而非 angle/360 ⇒ Radial360 的 1.0 是整圈，会填满 360° 而不是保留扫角

用法：python tools/verify_train_save.py
"""
import json
import pathlib
import sys

# Windows 控制台默认 GBK ⇒ 打印 ✔/✗ 这类字符会 UnicodeEncodeError（踩过）。统一按 UTF-8 输出。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAVE = ROOT / "workspace" / "train" / "train.save.json"
BUNDLE = ROOT / "workspace" / "train" / "train_game.lua"
TEMPLATE = ROOT / "workspace" / "train" / "train_client.template.lua"

CANVAS_W, CANVAS_H = 1280, 720
PROGRESS_SCRIPT_MAX = 600      # 脚本按 0..600 定位 PROGRESS 内的子控件
MARKER_W = 8

fails = []


def check(ok, msg):
    print(("  OK   " if ok else "  FAIL ") + msg)
    if not ok:
        fails.append(msg)


def walk(node, ox=0, oy=0):
    t = node["transformByPlatform"]["KEYBOARD"]
    x = ox + t["offset"]["x"]
    y = oy + t["offset"]["y"]
    yield node, x, y, t["size"]["x"], t["size"]["y"]
    for child in node.get("children", []):
        yield from walk(child, x, y)


def main():
    save = json.loads(SAVE.read_text(encoding="utf-8"))
    root = save["assets"]["server"]["root"]
    nodes = list(walk(root))
    by_name = {n["name"]: (n, x, y, w, h) for n, x, y, w, h in nodes}
    # 同级顺序（用于检查标签是否在底板之前出现）
    # ★ 我生成的存档里父关系**只由嵌套表达**（parentId 是插件快照才加的字段，别依赖它）
    parent_of = {}
    idx_of = {}

    def build_order(n):
        for i, child in enumerate(n.get("children", [])):
            parent_of[child["name"]] = n["name"]
            idx_of[(n["name"], child["name"])] = i
            build_order(child)

    build_order(root)

    def before(a, b):
        """同级里 a 是否比 b 先出现（先出现=在上层）"""
        p = parent_of.get(a)
        return idx_of.get((p, a), 99) < idx_of.get((p, b), 99)

    print("1) 越界（画布 %dx%d）" % (CANVAS_W, CANVAS_H))
    bad = ["%s x=%d..%d y=%d..%d" % (n["name"], x, x + w, y, y + h)
           for n, x, y, w, h in nodes
           if n["kind"] != "server-container" and (x < 0 or y < 0 or x + w > CANVAS_W or y + h > CANVAS_H)]
    check(not bad, "全部控件在画布内" + ("" if not bad else " -> " + "; ".join(bad)))

    print("2) 表盘")
    need = ["SPEED_DIAL", "TEMP_DIAL", "SPEED_DIAL_T", "TEMP_DIAL_T"]
    check(all(k in by_name for k in need), "四个表盘控件都在（%s）" % ", ".join(need))
    if "SPEED_DIAL" in by_name and "TEMP_DIAL" in by_name:
        _, sx, sy, sw, sh = by_name["SPEED_DIAL"]
        _, tx, ty, tw, th = by_name["TEMP_DIAL"]
        overlap = not (sy + sh <= ty or ty + th <= sy or sx + sw <= tx or tx + tw <= sx)
        check(not overlap, "两个表盘不重叠 (speed y=%d..%d, temp y=%d..%d)" % (sy, sy + sh, ty, ty + th))
        for d, lab in (("SPEED_DIAL", "SPEED_DIAL_T"), ("TEMP_DIAL", "TEMP_DIAL_T")):
            check(before(lab, d), "%s 标签在圆之前出现（先出现=在上层）" % d)

    print("3) 进度条容器")
    cw = by_name.get("PROGRESS", (None, 0, 0, 0, 0))[3]
    check(cw >= PROGRESS_SCRIPT_MAX + MARKER_W, "PROGRESS 宽 %d ≥ 脚本上限 %d + marker %d" % (cw, PROGRESS_SCRIPT_MAX, MARKER_W))

    print("4) 按钮层级（标签必须在底板之前）")
    for b in ("START", "UP", "DOWN", "PAUSE", "CONTINUE", "END", "TRIAL", "ENDLESS"):
        if b not in by_name:
            check(False, "缺按钮 %s" % b)
            continue
        check(before(b + "_T", b), "%s 的标签在底板之前" % b)

    print("5) 脚本侧（模板与打包后的单文件）")
    tpl = TEMPLATE.read_text(encoding="utf-8")
    bundle = BUNDLE.read_text(encoding="utf-8")
    for src, label in ((tpl, "模板"), (bundle, "单文件包")):
        check("'SPEED_DIAL'" in src and "'TEMP_DIAL'" in src, "%s 的 names 表含两个表盘名" % label)
        check("speedAngle/360" in src and "temperatureAngle/360" in src, "%s 用 angle/360 归一化（保留扫角）" % label)
        check("fillDead" in src, "%s 有 fillDead（失败即停写）" % label)
    check(bundle.count("AddCursorEventListener") >= 1 and "pcall(function() c:AddCursorEventListener" in bundle,
          "单文件包的绑定仍包在 pcall 里（模拟器兼容）")

    print("")
    if fails:
        print("校验未通过：%d 项" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("校验全部通过 ✔")
    return 0


if __name__ == "__main__":
    sys.exit(main())
