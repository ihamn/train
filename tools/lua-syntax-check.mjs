// lua-syntax-check.mjs —— 本地 Lua 5.3 语法检查（用模拟器里的 Fengari）
// 用法: node tools/lua-syntax-check.mjs <file.lua> [...]
// 为什么需要它: 编辑器的"校验失败"是最后一道关，代价是一次导入 + 一次进出关卡 ✗
//   本项目已两次把括号写错（spike.lua:103 / :153）都被编辑器抓到 ⇒ 部署前先本地过一遍 ✓
import { createRequire } from 'node:module'
import fs from 'node:fs'

const require = createRequire(import.meta.url)
const FENGARI = 'D:/miliastra-beyond-simulator/node_modules/fengari'
let fg
try {
  fg = require(FENGARI)
} catch (e) {
  console.error('找不到 Fengari（' + FENGARI + '）：' + e.message)
  process.exit(2)
}
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fg

const files = process.argv.slice(2)
if (files.length === 0) { console.error('用法: node tools/lua-syntax-check.mjs <file.lua> ...'); process.exit(2) }

let bad = 0
for (const f of files) {
  if (!fs.existsSync(f)) { console.log(`  ? ${f} 不存在`); bad++; continue }
  const code = fs.readFileSync(f, 'utf8')
  const L = lauxlib.luaL_newstate()
  lualib.luaL_openlibs(L)
  const status = lauxlib.luaL_loadstring(L, to_luastring(code))
  if (status === lua.LUA_OK) {
    const n = code.split('\n').length
    console.log(`  ✓ ${f}  语法 OK（${n} 行）`)
  } else {
    const err = to_jsstring(lua.lua_tostring(L, -1))
    console.log(`  ✗ ${f}  语法错误: ${err}`)
    bad++
  }
  lua.lua_close(L)
}
console.log(bad === 0 ? '语法检查：全部通过' : `语法检查：${bad} 个失败`)
process.exit(bad === 0 ? 0 : 1)
