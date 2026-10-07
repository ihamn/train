"""像素密度验证：逐档替换 DENSITY 参数，在模拟器里量行数/行距/每行最长字符/每帧耗时。

用法：python tools/check_fire_density.py
（依赖：node 在 PATH；QXQY_STUDIO 指向模拟器 studio/index.js）
"""
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROBE = ROOT / "workspace" / "train" / "fire_density.lua"
SAVE = ROOT / "workspace" / "train" / "train.save.json"
CASE = "tests/fire-density.case.json"
SIM_INDEX_OLD = "1073741850"
SIM_INDEX_NEW = "1073742004"

CONFIGS = [
    # name,            COLS, ROWS, FONT, SIZE_K, ROW_K
    ("base16x27",        16,  27,   20, "1.10", "0.955"),
    ("A_32x27_f20",      32,  27,   20, "1.10", "0.955"),
    ("B_32x54_f10",      32,  54,   10, "1.20", "0.955"),
    ("C_24x40_f13",      24,  40,   13, "1.15", "0.955"),
]

base_src = PROBE.read_text(encoding="utf-8")


def variant(name, cols, rows, font, sk, rk):
    src = base_src
    src = re.sub(r'name = "[^"]+",', 'name = "%s",' % name, src, count=1)
    src = re.sub(r"COLS = \d+,", "COLS = %s," % cols, src, count=1)
    src = re.sub(r"ROWS = \d+,", "ROWS = %s," % rows, src, count=1)
    src = re.sub(r"FONT = [\d.]+,", "FONT = %s," % font, src, count=1)
    src = re.sub(r"SIZE_K = [\d.]+,", "SIZE_K = %s," % sk, src, count=1)
    src = re.sub(r"ROW_K = [\d.]+,", "ROW_K = %s," % rk, src, count=1)
    return src.replace(SIM_INDEX_OLD, SIM_INDEX_NEW)


def write_save(src):
    d = json.loads(SAVE.read_text(encoding="utf-8"))
    for s in d["assets"]["scripts"]:
        s["source"] = src
    SAVE.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")


def run_case():
    env = dict(os.environ)
    out = subprocess.run(
        ["node", "tools/run-cases.mjs", CASE],
        cwd=str(ROOT), capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
    )
    return out.stdout + out.stderr


print("%-14s %-28s %s" % ("档位", "裁决", "密度汇总（模拟器实测）"))
print("-" * 120)
for name, cols, rows, font, sk, rk in CONFIGS:
    write_save(variant(name, cols, rows, font, sk, rk))
    out = run_case()
    verdict = ""
    for line in out.splitlines():
        if line.startswith("## "):
            verdict = line.strip()
            break
    summary = ""
    for line in out.splitlines():
        if "TR density=" in line:
            summary = line.split("TR density=", 1)[1].strip()
            break
    if not summary:
        for line in out.splitlines():
            if "✗" in line:
                summary = line.strip()
                break
    print("%-14s %-28s %s" % (name, verdict, summary))

# 还原交付存档
subprocess.run([sys.executable, "tools/make_m0_save.py"], cwd=str(ROOT),
               capture_output=True, text=True, encoding="utf-8", errors="replace")
print("-" * 120)
print("已用 make_m0_save.py 还原交付存档")
