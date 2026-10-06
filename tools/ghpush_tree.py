#!/usr/bin/env python3
"""
ghpush_tree.py — 用 GitHub Git Data API 推送为【单次整树提交】

为什么需要它：本机 github.com:443 不通（DNS 被污染），git push 用不了，
只能走 api.github.com。而 Contents API 是逐文件提交（历史会很碎），
这个脚本改成 blob → tree → commit → force-update-ref，一次成型。

用法：
    python3 tools/ghpush_tree.py                # 推送 HEAD 的工作区状态
    python3 tools/ghpush_tree.py --dry-run      # 只看会推什么
    python3 tools/ghpush_tree.py -m "自定义提交信息"
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REPO = os.environ.get("GH_REPO", "ihamn/train")
API = "https://api.github.com"
BIN_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".apk", ".deb", ".xz", ".zst", ".ico")


def token():
    p = os.path.expanduser("~/.github_token")
    if not os.path.exists(p):
        sys.exit("找不到 token 文件: %s" % p)
    return open(p).read().strip()


def api(tok, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        print("  HTTP %d %s" % (e.code, e.read().decode()[:200]), file=sys.stderr)
        raise


def build_tree(tok, files):
    """按目录层级组装 tree（GitHub API 需要嵌套 tree）"""
    root = {}
    for f in files:
        parts = f.split("/")
        node = root
        for p in parts[:-1]:
            node = node.setdefault(p, {})
        node[parts[-1]] = None       # 叶子占位
    return materialize(tok, root)


def materialize(tok, node):
    items = []
    for name, sub in node.items():
        if sub is None:
            continue
        items.append({"path": name, "mode": "040000", "type": "tree",
                      "sha": materialize(tok, sub)})
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("-m", "--message", default=None)
    # 用占位参数把"叶子文件"也带上，稍后统一处理
    a = ap.parse_args()

    tok = token()
    out = subprocess.run(["git", "ls-files", "-z"], capture_output=True).stdout.decode()
    files = sorted([f for f in out.split("\0") if f])
    msg = a.message or subprocess.run(["git", "log", "-1", "--pretty=%B"],
                                     capture_output=True).stdout.decode().strip()
    print("仓库     %s" % REPO)
    print("文件数   %d" % len(files))
    print("提交信息 %s" % msg.splitlines()[0][:60])
    if a.dry_run:
        for f in files:
            print("   ", f)
        return

    # 1) 上传全部 blob，同时记录路径 → sha
    blob_sha = {}
    for i, f in enumerate(files, 1):
        raw = open(f, "rb").read()
        isbin = f.lower().endswith(BIN_EXT)
        body = {"content": base64.b64encode(raw).decode() if isbin else raw.decode("utf-8"),
                "encoding": "base64" if isbin else "utf-8"}
        blob_sha[f] = api(tok, "POST", "/repos/%s/git/blobs" % REPO, body)["sha"]
        print("  blob [%2d/%d] %s" % (i, len(files), f[:56]))

    # 2) 建树（叶子用 blob sha）
    def tree_items(prefix=""):
        """按当前层级返回该层的 tree 项"""
        dirs, leaves = {}, []
        for f in files:
            if not f.startswith(prefix):
                continue
            rest = f[len(prefix):]
            if "/" in rest:
                dirs.setdefault(rest.split("/")[0], None)
            else:
                leaves.append(rest)
        items = [{"path": leaf, "mode": "100644", "type": "blob",
                  "sha": blob_sha[prefix + leaf]} for leaf in leaves]
        for d in dirs:
            items.append({"path": d, "mode": "040000", "type": "tree",
                          "sha": make_tree(prefix + d + "/")})
        return items

    def make_tree(prefix):
        return api(tok, "POST", "/repos/%s/git/trees" % REPO,
                   {"tree": tree_items(prefix)})["sha"]

    tree = make_tree("")
    print("tree     %s" % tree[:10])

    # 3) 建提交（无父提交 = 历史的唯一根）
    commit = api(tok, "POST", "/repos/%s/git/commits" % REPO,
                 {"message": msg, "tree": tree, "parents": []})
    print("commit   %s" % commit["sha"][:10])

    # 4) 强行把 main 指过去
    api(tok, "PATCH", "/repos/%s/git/refs/heads/main" % REPO,
        {"sha": commit["sha"], "force": True})
    print("\n✅ 已推送（单次整树提交，历史已替换）")
    print("   https://github.com/%s" % REPO)


if __name__ == "__main__":
    main()
