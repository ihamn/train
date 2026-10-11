# 怎么在这台机器上跑测试（含踩过的坑）

> 适用：云电脑（系统盘会换、D 盘不清）。**能放 D 盘的工具都放 D 盘**。

## 一、三套 Node 测试（都很快）

```powershell
cd D:\train
$env:LUA = "D:\tools\lua\lua.exe"     # ★ 只有第一套需要
node tests/lua-train.test.cjs         # 3 个用例：128 组路线对照 + 4 段完整驾驶 + 不变量/接线/打包一致性
node tests/prototype.test.cjs         # 网页原型（29 个断例）
node tests/endless.test.cjs           # 无尽模式（4 个断例）
```

2026-10-11 实测：**3/3、29/29、4/4 全绿** ✔

`lua-train.test.cjs` 会**真的启动 Lua 解释器**执行 `workspace/train/train_core.lua`（不是 JS mock）——
它把同一组玩家输入同时喂给 JS 参考实现和 Lua，逐帧比对 ✔（客户端接线目前仍只有 mock 验证 ✗，千星原生运行仍待真机）。

## 二、需要 Lua 解释器时怎么装（winget 会失败，见下）

```powershell
# ✗ 直接 winget 安装会失败：它的下载地址是 github.com，本机被墙
#    winget install --id DEVCOM.Lua -e     → InternetOpenUrl() failed 0x80072efd
# ✅ 走 gh-proxy 下载 + 管理式解包（不安装、直接拿 exe）
Invoke-WebRequest "https://gh-proxy.com/https://github.com/DevelopersCommunity/cmake-lua/releases/download/v5.4.6/Lua-5.4.6-win64.msi" -OutFile "D:\tools\lua-5.4.6.msi"
Start-Process msiexec.exe -ArgumentList "/a","D:\tools\lua-5.4.6.msi","/qn","TARGETDIR=D:\tools\lua-extract" -Wait
Copy-Item "D:\tools\lua-extract\<...>\*" "D:\tools\lua\" -Recurse -Force
& D:\tools\lua\lua.exe -v      # → Lua 5.4.6
```

> 为什么这么绕：`LUA` 环境变量必须是**能被 Node 直接 spawn 的单个可执行文件** ✗
> —— `.cmd` 垫片不行（Node 在 Windows 上不 shell 就不能跑 `.cmd` ✗），所以走真 exe + D 盘便携化 ✔

## 三、模拟器用例（千星那套）

```powershell
$env:QXQY_STUDIO = "D:/miliastra-beyond-simulator/studio/index.js"
node tools/run-cases.mjs                        # 跑 tests/*.case.json（交付存档）
node tools/run-cases.mjs tests/fire-v57.case.json   # 单跑某个用例
python tools/make_m0_save.py                    # 重新生成交付存档
node tools/lua-syntax-check.mjs <file.lua>      # 部署真机前的语法关（Fengari = Lua 5.3）
python tools/check_fire_density.py              # 像素火密度四档实测
```

## 四、Windows 行尾符坑（已修，别再踩）

Windows 版 Lua 的 `print` 走文本模式 ⇒ 输出 `\r\n`；Node 里按 `'\n'` 切行 ⇒ 每行尾部残留 `\r`
⇒ 字符串/数字比较全错 ✗（曾让 `lua-train.test.cjs` 三个用例全红，看起来像逻辑 bug ✗）。

**做法**：读子进程输出后先 `stdout.replace(/\r\n/g,'\n')` ✔；文件内容比对前先 `normalize(s)=s.replace(/\r\n/g,'\n')` ✔。

## 五、真机相关（血泪规则，写在 docs/tech-architecture.md §7）

* 部署前必过语法检查；**关卡存的是"导入那一刻的副本"** ⇒ 改文件后要在编辑器里**重新导入**
* 不自动创建/扫描控件、不改挂载点几何、脏检查 + 节流 + 日志有界
* 真机日志：`BeyondLocal\<UID>\Beyond_Debug_Log\*.gia`（**退出关卡时**落盘；只认 ASCII 标记）
