#!/usr/bin/env python3
"""生成 M0 探针的千星模拟器完整存档：workspace/train/train.save.json

为什么要脚本生成而不是在编辑器里一个个点：
  1. transformByPlatform 要写满 4 平台 × 7 组分量，手点 20 个控件不可复现；
  2. 存档即交付物（workspace/<slug>/<slug>.save.json），可 diff、可重生成；
  3. 脚本 source 直接内联 spike.lua 当前内容，存档与 .lua 文件不会漂移。

布局基准 = mobile-16-9 (1280×720)，原点左下、Y 向上（千星坐标系）。
固定尺寸控件统一 anchor=(0,0)、pivot=(0,0)，于是
    box.left == anchoredPositionX
（studio/ui/layout.js 的 computeRect 是 Unity 语义：
 left = parentLeft + anchorMinX*parentW + offsetX - sizeX*pivotX）
M0 的「运行时移动是否进入渲染布局」断言就架在这条等式上。

用法：python tools/make_m0_save.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SAVE_PATH = ROOT / "workspace" / "train" / "train.save.json"
LUA_PATH = ROOT / "workspace" / "train" / "spike.lua"

PLATFORMS = ["KEYBOARD", "TOUCHSCREEN", "CONTROLLER_CONSOLE", "CONTROLLER_MOBILE"]
CANVAS_ID = "mobile-16-9"
CANVAS_W, CANVAS_H = 1280, 720
SAVE_FORMAT = "qxqy-simulator-save"
SERVER_ASSET = "server-control-template"
CLIENT_ASSET = "client-control-template"
SCRIPT_GUID = 1073742200
STAGE_ID = "n1"
# 脚本映射路径必须是**平铺文件名**：千星真机的脚本映射名不允许带斜杠，
# 带目录的写法（default_import_file/workspace/train/spike.lua）是模拟器 require 的
# "导入根"约定，写进 GIA 会让真机得到一个非法映射名。
# 用户自己的 zuma 工程就是平铺的：external_lua_file\zuma.lua。
# 映射名 = 本字段；本地文件放在 <import root>/<本字段>。
SCRIPT_PATH = "spike.lua"

# 调色板取自 HANDOFF.md §3（#AARRGGBB 打包整数）
C_BG = 0xFF0E1420
C_BALLAST = 0xFF28324A
C_RAIL = 0xFF7886A0
C_TIE = 0xFF3E4C6C
C_LOCO = 0xFFDEB25C
C_WAGON = 0xFF6096D6
C_FRAME = 0xFFFFFFFF

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


def make_node(kind, name, amin, amax, offset, size, pivot=(0.0, 0.0), **extra):
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
        "giaRaw": {},
        "transformByPlatform": {
            platform: rect(amin, amax, offset, size, pivot) for platform in PLATFORMS
        },
        "children": [],
        "scriptMappingIds": [],
    }
    node.update(extra)
    return node


def image(name, image_id, color, amin, amax, offset, size, pivot=(0.0, 0.0)):
    return make_node(
        "image", name, amin, amax, offset, size, pivot,
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
        enableFill=False,
        fillType="Horizontal",
        fillHorizontalType="Left",
        fillVerticalType="Bottom",
        fillRadial90Type="BottomLeft",
        fillRadialType="Bottom",
        fillAmount=1,
        reverseMaskArea=False,
    )


def build_stage_children():
    """同级列表【先出现的画在上层】（observed-contract: 编辑器 list 位置 0 = 最上）。"""
    kids = []

    # HUD 最上层：文本控件，脚本写 "M0 frame=<idx>"
    kids.append(make_node(
        "textbox", "HUD", (0, 0), (0, 0), (20, 640), (600, 40),
        fontSize=24, adaptiveFontSize=False, minimumFontSize=20,
        fontColor=0xFFFFFFFF, bgColor=0x00000000, enableOutline=True,
        outlineColor=0x33000000, horizontalAlignment="Left", verticalAlignment="Middle",
        text="",
    ))

    # 六帧：同一矩形叠放，imageId 用 100001–100006 六个不同图元代替真实 sprite 帧
    for i in range(6):
        kids.append(image("F%d" % i, 100001 + i, C_FRAME,
                          (0, 0), (0, 0), (900, 430), (140, 140)))

    # 列车：车头（运行时改位置）+ 车厢（运行时改大小）
    kids.append(image("LOCO", 100002, C_LOCO, (0, 0), (0, 0), (100, 400), (200, 70)))
    kids.append(image("WAGON", 100003, C_WAGON, (0, 0), (0, 0), (320, 400), (120, 70)))

    # 轨道：轨枕 → 上轨/下轨 → 道砟 → 背景（越后越底层）
    for i in range(6):
        kids.append(image("TIE_%d" % i, 100001, C_TIE,
                          (0, 0), (0, 0), (130 + 180 * i, 300), (12, 90)))
    # 轨道横跨画布：水平 stretch，offset.y 仍是距锚点(底部)的距离
    kids.append(image("RAIL_HI", 100001, C_RAIL, (0, 0), (1, 0), (0, 370), (0, 8), pivot=(0.0, 0.0)))
    kids.append(image("RAIL_LO", 100001, C_RAIL, (0, 0), (1, 0), (0, 320), (0, 8), pivot=(0.0, 0.0)))
    kids.append(image("BALLAST", 100001, C_BALLAST, (0, 0), (1, 0), (0, 300), (0, 90), pivot=(0.0, 0.0)))
    # 背景：双向 stretch，铺满任意画布
    kids.append(image("BG", 100001, C_BG, (0, 0), (1, 1), (0, 0), (0, 0), pivot=(0.5, 0.5)))

    return kids


def build_server_project(script_source):
    stage = make_node(
        "container", "STAGE", (0, 0), (1, 1), (0, 0), (0, 0), pivot=(0.5, 0.5),
        isolateNavigation=False, disableKeyEventPassthrough=False,
        disableCursorEventPassthrough=False, showCursor=False,
    )
    # v5 起**故意留空**：本工程的 UI 架构是"运行时按模板实例化"（zuma 的实战做法：
    # InstantiateClientUIControl ×9、GetChild ×0）。作者期摆好的具名控件会和运行时建的
    # 撞名，而且会让"服务器控件模板里为什么有内容"这件事说不清。
    # 轨道/列车/六帧/HUD 全部由 spike.lua 在 OnStart 里建。
    stage["children"] = []
    # 生成的 id 顺序：n1 = STAGE，与 STAGE_ID 对齐
    assert stage["id"] == STAGE_ID, stage["id"]

    root = make_node(
        "server-container", "客户端控件容器", (0, 0), (1, 1), (0, 0), (0, 0), pivot=(0.5, 0.5),
    )
    root["guid"] = 1073742000
    root["children"] = [stage]

    return {
        "layoutSchemaVersion": 2,
        "version": 1,
        "meta": {
            "name": "列车 M0 探针",
            "assetType": SERVER_ASSET,
            "sourceFormat": "authoring",
            "sourceFile": "",
        },
        "canvasId": CANVAS_ID,
        "selectedId": STAGE_ID,
        "root": root,
    }


def build_client_project():
    """客户端控件模板工程：**每个顶层子节点就是一个可实例化的模板**。

    为什么要这一份：真机契约里只有"存为模板"的节点支持
    game.InstantiateClientUIControl(prefabIndex, parent) 动态创建
    （zuma 工程的实战做法就是「一个控件一个模板」：图片模板 / 文本框模板 / 容器模板…）。
    模拟器同样只注册模板根节点，所以要让 v5 的"运行时建控件"路径在模拟器里可测，
    就得在这里放两个单控件模板：M0_IMG（图片）与 M0_TEXT（文本框）。
    """
    img = make_node(
        "image", "M0_IMG", (0, 0), (0, 0), (0, 0), (100, 100), pivot=(0.5, 0.5),
        imageSource="StaticReference", imageId=100001, imageColor=C_FRAME,
        enableMask=False, enableSoftEdge=False, softEdgeMode="Percentage",
        softEdgeWidthX=8, softEdgeWidthY=8, horizontalSoftRange=85, verticalSoftRange=85,
        enableFill=False, fillType="Horizontal", fillHorizontalType="Left",
        fillVerticalType="Bottom", fillRadial90Type="BottomLeft", fillRadialType="Bottom",
        fillAmount=1, reverseMaskArea=False,
    )
    txt = make_node(
        "textbox", "M0_TEXT", (0, 0), (0, 0), (0, 0), (200, 40), pivot=(0.5, 0.5),
        fontSize=24, adaptiveFontSize=False, minimumFontSize=20,
        fontColor=0xFFFFFFFF, bgColor=0x00000000, enableOutline=True,
        outlineColor=0x33000000, horizontalAlignment="Left", verticalAlignment="Middle",
        text="",
    )
    # 容器模板：v8 要"自建容器"当布局父级（真机上这个模板索引是 1073741846），
    # 模拟器里没有对应模板就没法测这条路径。
    cont = make_node(
        "container", "M0_CONT", (0, 0), (0, 0), (0, 0), (100, 100), pivot=(0.5, 0.5),
        isolateNavigation=False, disableKeyEventPassthrough=False,
        disableCursorEventPassthrough=False, showCursor=False,
    )
    # 模板工程里根是 server-container，顶层子节点各是一个模板
    root = make_node("server-container", "客户端控件模板", (0, 0), (1, 1), (0, 0), (0, 0), pivot=(0.5, 0.5))
    root["guid"] = 1073742300
    root["children"] = [img, txt, cont]
    return {
        "layoutSchemaVersion": 2,
        "version": 1,
        "meta": {
            "name": "M0 模板集（图片 + 文本框）",
            "assetType": CLIENT_ASSET,
            "sourceFormat": "authoring",
            "sourceFile": "",
        },
        "canvasId": CANVAS_ID,
        "selectedId": img["id"],
        "root": root,
    }


def main():
    script_source = LUA_PATH.read_text(encoding="utf-8")
    save = {
        "format": SAVE_FORMAT,
        "version": 4,
        "meta": {"name": "列车 M0 探针"},
        "activeAssetType": SERVER_ASSET,
        "serverLogic": {"version": 1, "rules": []},
        "controlGuidChanges": [],
        "scriptSync": None,
        "assets": {
            "server": build_server_project(script_source),
            "client": build_client_project(),
            "scripts": [
                {
                    "id": str(SCRIPT_GUID),
                    "guid": SCRIPT_GUID,
                    "path": SCRIPT_PATH,
                    "source": script_source,
                    "controlId": STAGE_ID,
                    "controlAsset": SERVER_ASSET,
                }
            ],
        },
    }
    SAVE_PATH.parent.mkdir(parents=True, exist_ok=True)
    SAVE_PATH.write_text(json.dumps(save, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    controls = ["STAGE"]
    for kid in save["assets"]["server"]["root"]["children"][0]["children"]:
        controls.append(kid["name"])
    print("wrote %s (%d bytes)" % (SAVE_PATH, SAVE_PATH.stat().st_size))
    print("controls (%d): %s" % (len(controls), ", ".join(controls)))
    print("script source: %d chars from %s" % (len(script_source), LUA_PATH.name))


if __name__ == "__main__":
    main()
