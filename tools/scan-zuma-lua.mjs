// 扫 zuma.lua（真机验证过的产物）提取「可用做法」速查表
// 目的：不再靠猜 API / 不再靠试探，直接照抄它的用法。
import fs from 'node:fs'

const p = 'D:/train/workspace/train/zuma.reference.lua'
if (!fs.existsSync(p)) { console.error('找不到参考文件：' + p); process.exit(1) }
const src = fs.readFileSync(p, 'utf8')
const lines = src.split('\n')

const uniq = (arr) => [...new Set(arr)].sort()
const collect = (re) => {
  const out = []
  for (const m of src.matchAll(re)) out.push(m[1])
  return uniq(out)
}

console.log('=== 文件规模 ===')
console.log('  行数 ' + lines.length + '，字节 ' + src.length)

console.log('\n=== game.* 调用（权威 API 名，照抄即可） ===')
const gameApis = collect(/\bgame\.([A-Za-z_][A-Za-z0-9_]*)/g)
console.log('  共 ' + gameApis.length + ' 个：' + gameApis.join('  '))

console.log('\n=== script.* 用法 ===')
const scriptApis = collect(/\bscript\.([A-Za-z_][A-Za-z0-9_]*)/g)
const scriptColon = collect(/\bscript:([A-Za-z_][A-Za-z0-9_]*)/g)
console.log('  点号：' + scriptApis.join('  '))
console.log('  冒号：' + scriptColon.join('  '))

console.log('\n=== 控件方法（冒号调用） ===')
const methods = collect(/\b[A-Za-z_][A-Za-z0-9_]*:([A-Z][A-Za-z0-9_]*)\s*\(/g)
console.log('  共 ' + methods.length + ' 个：' + methods.join('  '))

console.log('\n=== 控件字段（点号写入/读取） ===')
const fields = collect(/\b[A-Za-z_][A-Za-z0-9_]*\.([a-z][A-Za-z0-9_]*)\s*=/g)
console.log('  共 ' + fields.length + ' 个：' + fields.join('  '))

console.log('\n=== 模板 / 素材编号（真机可用的实数） ===')
const ids = uniq([...src.matchAll(/\b(1073\d{6}|1000\d{2})\b/g)].map((m) => m[1]))
console.log('  ' + ids.join('  '))

console.log('\n=== 三个生命周期各在做什么（行号范围 + 关键调用计数） ===')
const marks = []
lines.forEach((l, i) => { if (/^function\s+(OnInit|OnStart|OnUpdate|OnDestroy|OnEnable|OnDisable)/.test(l)) marks.push({ i: i + 1, name: RegExp.$1 }) })
for (let k = 0; k < marks.length; k++) {
  const from = marks[k].i, to = k + 1 < marks.length ? marks[k + 1].i : lines.length
  const body = lines.slice(from - 1, to - 1).join('\n')
  const nInst = (body.match(/InstantiateClientUIControl/g) || []).length
  const nSet = (body.match(/:(Set|Add)[A-Za-z]+\s*\(/g) || []).length
  const nPrint = (body.match(/printerr|print\s*\(/g) || []).length
  console.log(`  ${marks[k].name}  行 ${from}~${to - 1}（${to - from} 行）  实例化=${nInst}  设属性=${nSet}  打印=${nPrint}`)
}

console.log('\n=== 输入相关（光标/按键） ===')
const inputLines = lines.map((l, i) => ({ i: i + 1, l })).filter((x) => /CursorEvent|KeyEvent|AddEventListener|GetCursor|OnClick/.test(x.l))
console.log('  命中 ' + inputLines.length + ' 行，前 12 行：')
inputLines.slice(0, 12).forEach((x) => console.log('    ' + x.i + ': ' + x.l.trim().slice(0, 110)))

console.log('\n=== 注释里的「坑/注意」（平台事实金矿，前 30 条） ===')
const pits = lines.map((l, i) => ({ i: i + 1, l })).filter((x) => /⚠|注意|踩|坑|不能|必须|不支持|失败/.test(x.l) && /^\s*--/.test(x.l))
console.log('  命中 ' + pits.length + ' 行')
pits.slice(0, 30).forEach((x) => console.log('    ' + x.i + ': ' + x.l.trim().slice(0, 118)))
