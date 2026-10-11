#!/usr/bin/env python3
"""生成列车项目的千星模拟器完整存档：workspace/train/train.save.json

规格来源：
  1. workspace/train/train_client.template.lua 的 names 列表与查找路径
  2. tests/lua-train-checks.lua 第 39–73 行的 mock 控件树（**名字与层级就是规格**）
  3. 模拟器实测的权威模式（qxqy_studio_get）：资产分 server/client 两类；
     `mountTargets` 证明脚本可挂在**服务端控件节点**（如 container）上，
     但**不能挂 `客户端控件容器` 根**（sc1 不在 mountTargets 里）。

布局基准 = **mobile-16-9 (1280×720)**（技能规定：2D 游戏整屏构图必须在手机 16:9 完整可见；
PC 1600×900 由锚点/留边容纳，不按 PC 铺满）。原点左下、Y 向上。
固定尺寸控件统一 anchor=(0,0)、pivot=(0,0)，于是 box.left == anchoredPositionX。

用法：python tools/make_train_save.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAVE_PATH = ROOT / "workspace" / "train" / "train.save.json"
LUA_PATH = ROOT / "workspace" / "train" / "train_game.lua"

PLATFORMS = ["KEYBOARD", "TOUCHSCREEN", "CONTROLLER_CONSOLE", "CONTROLLER_MOBILE"]
CANVAS_ID = "mobile-16-9"
CANVAS_W, CANVAS_H = 1280, 720
SAVE_FORMAT = "qxqy-simulator-save"
SERVER_ASSET = "server-control-template"
CLIENT_ASSET = "client-control-template"
SCRIPT_GUID = 1073742200
SCRIPT_PATH = "train.lua"          # 平铺名（真机映射名不允许带斜杠）

C_PANEL = 0xFF101826
C_TEXT = 0xFFFFFFFF
C_HINT = 0xCC000000
C_BTN = 0xFF2A3550
C_GOLD = 0xFFFFD166
C_BLUE = 0xFF6096D6
C_GREEN = 0xFF6EE7A8
C_RED = 0xFFFF6B4A

# 官方素材号（见 docs/ui-assets.md）。★ 模拟器只画 100001–100006，其余显示缺失框（预览限制）
ART_BLOCK = 100001     # 方形（拉长不糊；模拟器能画）
ART_RING = 100006      # 圆环（表盘底；模拟器能画）
ART_UP = 100148        # 双上箭头 —— 加速档按钮（用户指定）
ART_DOWN = 100147      # 双下箭头 —— 减速档按钮（用户指定）
ART_PLAY = 100181      # 播放
ART_DOTS = 100158      # 省略号（暂停）
ART_CHECK = 100102     # 勾（结束）
ART_ARROW_R = 100166   # 右箭头圆（继续）
ART_STAR = 100187      # 星描边（试玩）
ART_STAR_F = 100188    # 星实心（无尽）

_next = {"n": 0, "guid": 1073742000}


def nid():
    _next["n"] += 1
    return "n%d" % _next["n"]


def ngid():
    _next["guid"] += 1
    return _next["guid"]


def rect(amin, amax, offset, size, pivot=(0.0, 0.0)):
    return {
        "scale": {"x": 1, "y": 1, "z": 1},
        "rotation": {"x": 0, "y": 0, "z": 0},
        "anchorMin": {"x": amin[0], "y": amin[1]},
        "anchorMax": {"x": amax[0], "y": amax[1]},
        "offset": {"x": offset[0], "y": offset[1]},
        "size": {"x": size[0], "y": size[1]},
        "pivot": {"x": pivot[0], "y": pivot[1]},
    }


def make_node(kind, name, offset, size, pivot=(0.0, 0.0), **extra):
    node = {
        "id": nid(),
        "kind": kind,
        "name": name,
        "guid": ngid(),
        "giaRelatedGuids": [],
        "active": True,
        "visible": True,
        "canControllerFocus": False,
        "syncAllDevices": True,
        "giaRaw": {"genericField501": 0, "footerField505": 0},
        "transformByPlatform": {
            platform: rect((0, 0), (0, 0), offset, size, pivot) for platform in PLATFORMS
        },
        "children": [],
        "scriptMappingIds": [],
    }
    node.update(extra)
    return node


def image(name, image_id, color, offset, size, fill=False):
    return make_node(
        "image", name, offset, size,
        imageSource="StaticReference",
        imageId=image_id,
        imageColor=color,
        enableMask=False,
        enableSoftEdge=False,
        softEdgeMode="Percentage",
        softEdgeWidthX=8,
        softEdgeWidthY=8,
        horizontalSoftRange=85,
        verticalSoftRange=85,
        enableFill=bool(fill),
        fillType="Radial360" if fill else "Horizontal",
        fillHorizontalType="Left",
        fillVerticalType="Bottom",
        fillRadial90Type="BottomLeft",
        fillRadialType="Bottom",
        fillAmount=0 if fill else 1,
        reverseMaskArea=False,
    )


def textbox(name, offset, size, size_px=24, text=""):
    return make_node(
        "textbox", name, offset, size,
        fontSize=size_px, adaptiveFontSize=False, minimumFontSize=16,
        fontColor=C_TEXT, bgColor=0x00000000, enableOutline=True,
        outlineColor=0x66000000, horizontalAlignment="Left", verticalAlignment="Middle",
        text=text,
    )


def container(name, offset, size, show_cursor=False):
    return make_node(
        "container", name, offset, size,
        isolateNavigation=False,
        disableKeyEventPassthrough=False,
        disableCursorEventPassthrough=False,
        showCursor=show_cursor,
    )


def btn(name, art, x, y, w, h, label, label_px=18):
    """按钮 = 底板图片（可点击）+ 盖在上面的文字标签。"""
    return [
        image(name, art, C_BTN, (x, y), (w, h)),
        textbox(name + "_T", (x + 6, y + h // 2 - 12), (w - 12, 24), label_px, label),
    ]


def build_children():
    """同级列表【先出现的画在上层】。坐标按 mobile-16-9 (1280×720)。"""
    kids = []

    # ---- 顶部：提示条 + 进度条 ----
    kids.append(textbox("HINT", (640, 646), (600, 36), 22, "点击出发"))
    kids.append(image("HINT_BG", ART_BLOCK, C_HINT, (626, 640), (628, 48)))

    prog = container("PROGRESS", (40, 620), (560, 56))
    segs = [image("PROGRESS_MARKER", ART_BLOCK, C_GOLD, (0, 24), (8, 20))]
    for i in range(1, 12):
        segs.append(image("SEG%d" % i, ART_BLOCK, C_BLUE, (0, 0), (40, 12)))
    prog["children"] = segs            # marker 先出现 = 画在上层

    # ---- 左侧读数 ----
    kids.append(textbox("SPEED", (24, 500), (360, 48), 36, "0.0 km/h"))
    kids.append(textbox("GEAR", (24, 452), (320, 38), 26, "0"))
    kids.append(textbox("TEMP", (24, 408), (320, 38), 26, "0%"))
    kids.append(textbox("SCORE", (24, 364), (320, 38), 26, "0"))
    kids.append(textbox("TARGET", (24, 320), (320, 34), 22, "不限速"))
    kids.append(textbox("STATUS", (24, 278), (560, 34), 22, "第 1 站 · 剩余 0 m"))

    # ---- 右侧：两个表盘（★ 实心圆 100002 + 径向填充 ⇒ 填充显示为扇形；替代 37+43 帧美术）
    #      注意都必须在 720 高以内：y + 220 + 标签 ≤ 720
    kids.append(textbox("SPEED_DIAL_T", (1040, 692), (200, 26), 18, "速度"))
    kids.append(image("SPEED_DIAL", 100002, C_GREEN, (1030, 462), (220, 220), fill=True))
    kids.append(textbox("TEMP_DIAL_T", (1040, 512), (200, 26), 18, "轴温"))
    kids.append(image("TEMP_DIAL", 100002, C_RED, (1030, 282), (220, 220), fill=True))

    # ---- 底部按钮一行（含用户指定的加速/减速素材号） ----
    row = [
        ("START", ART_PLAY, "出发"),
        ("UP", ART_UP, "加速档"),
        ("DOWN", ART_DOWN, "减速档"),
        ("PAUSE", ART_DOTS, "暂停"),
        ("CONTINUE", ART_ARROW_R, "续行"),
        ("END", ART_CHECK, "结束"),
        ("TRIAL", ART_STAR, "试玩"),
        ("ENDLESS", ART_STAR_F, "无尽"),
    ]
    for i, (name, art, label) in enumerate(row):
        for n in btn(name, art, 30 + i * 156, 40, 144, 60, label):
            kids.append(n)

    # ---- 场景容器（局部 720 宽；脚本写 TIE1..4 的 x/y） ----
    scene = container("SCENE", (280, 200), (720, 140))
    scene["children"] = [
        image("TIE%d" % i, ART_BLOCK, C_BLUE, ((i - 1) * 180, 60), (60, 20))
        for i in range(1, 5)
    ]
    # ---- 表盘目标环容器（局部 240 宽；脚本写 TARGET_RANGE 的 x/w） ----
    dial = container("DIAL", (40, 200), (240, 40))
    dial["children"] = [image("TARGET_RANGE", ART_BLOCK, C_GREEN, (0, 0), (240, 6))]

    kids.append(prog)
    kids.append(scene)
    kids.append(dial)
    return kids


def build_server_project():
    """★ 顺序很重要：先建挂载用的容器节点（拿到 n1），再建它下面的控件。"""
    stage = container("TRAIN_UI", (0, 0), (CANVAS_W, CANVAS_H), show_cursor=True)
    mount_id = stage["id"]
    stage["children"] = build_children()

    root = make_node("server-container", "客户端控件容器", (0, 0), (0, 0), pivot=(0.5, 0.5))
    root["transformByPlatform"] = {
        platform: rect((0, 0), (1, 1), (0, 0), (0, 0), (0.5, 0.5)) for platform in PLATFORMS
    }
    root["guid"] = 1073741850
    root["children"] = [stage]
    return {
        "layoutSchemaVersion": 2,
        "version": 1,
        "meta": {"name": "列车 · 控件树", "assetType": SERVER_ASSET,
                 "sourceFormat": "authoring", "sourceFile": ""},
        "canvasId": CANVAS_ID,
        "selectedId": mount_id,
        "root": root,
    }, mount_id


def build_client_project():
    """客户端控件模板（保留：模拟器用它注册可实例化模板；本工程脚本不实例化，仅备用）。"""
    img = image("T_IMG", ART_BLOCK, C_TEXT, (0, 0), (100, 100))
    txt = textbox("T_TEXT", (0, 0), (200, 40), 24, "")
    root = make_node("server-container", "客户端控件模板", (0, 0), (0, 0), pivot=(0.5, 0.5))
    root["transformByPlatform"] = {
        platform: rect((0, 0), (1, 1), (0, 0), (0, 0), (0.5, 0.5)) for platform in PLATFORMS
    }
    root["guid"] = 1073742300
    root["children"] = [img, txt]
    return {
        "layoutSchemaVersion": 2,
        "version": 1,
        "meta": {"name": "列车 · 模板集", "assetType": CLIENT_ASSET,
                 "sourceFormat": "authoring", "sourceFile": ""},
        "canvasId": CANVAS_ID,
        "selectedId": img["id"],
        "root": root,
    }


def main():
    script_source = LUA_PATH.read_text(encoding="utf-8")
    server, mount_id = build_server_project()
    save = {
        "format": SAVE_FORMAT,
        "version": 4,
        "meta": {"name": "列车 · 控件树 + 接线脚本", "note": "由 tools/make_train_save.py 生成"},
        "activeAssetType": SERVER_ASSET,
        "canvasId": CANVAS_ID,
        "serverLogic": {"version": 1, "rules": []},
        "controlGuidChanges": [],
        "scriptSync": None,
        "assets": {
            # ★ 插件的存档格式按【角色】命名（qxqy_studio_get 的 save 段实测）：
            #   assets.server / assets.client —— 不是按 assetType 命名（写成 "server-control-template" 会被忽略 ✗）
            "server": server,
            "client": build_client_project(),
            "scripts": [{
                "id": "s1",
                "guid": SCRIPT_GUID,
                "path": SCRIPT_PATH,
                "source": script_source,
                "controlId": mount_id,          # ★ 挂在控件节点上（不能挂 客户端控件容器 根）
                "controlAsset": SERVER_ASSET,
            }],
        },
    }
    SAVE_PATH.write_text(json.dumps(save, ensure_ascii=False), encoding="utf-8")

    def walk(node, depth=0):
        yield depth, node
        for k in node.get("children", []):
            yield from walk(k, depth + 1)

    names = [n["name"] for _, n in walk(server["root"])]
    print("wrote %s (%d bytes)" % (SAVE_PATH, SAVE_PATH.stat().st_size))
    print("canvas %s %dx%d" % (CANVAS_ID, CANVAS_W, CANVAS_H))
    print("mount id=%s  controls=%d" % (mount_id, len(names)))
    print("names: " + ", ".join(names))


if __name__ == "__main__":
    main()
