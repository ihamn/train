#!/usr/bin/env node
/**
 * Headless qxqy-autotest runner over the delivered save.
 *
 * Why: the DSH `runCase` tool answers with a multi-hundred-KB snapshot, which is
 * expensive to read turn after turn. This runs the same code path
 * (createStudio -> playRunCase -> replayCase) in one short-lived process and
 * prints only the verdicts.
 *
 * usage:
 *   QXQY_STUDIO="D:/miliastra-beyond-simulator/studio/index.js" \
 *     node tools/run-cases.mjs [--canvas mobile-16-9] [case.json ...]
 *
 * default: every tests/m0-*.case.json whose name does not end in -shot-*
 */
import { readFileSync, readdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)))
const ENTRY = process.env.QXQY_STUDIO
if (!ENTRY) {
  console.error('缺少 QXQY_STUDIO：请指向模拟器仓库的 studio/index.js')
  process.exit(2)
}
const { createStudio } = await import(pathToFileURL(ENTRY).href)

const argv = process.argv.slice(2)
let canvasId = ''
const files = []
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--canvas') { canvasId = argv[++i]; continue }
  files.push(argv[i])
}
if (!files.length) {
  const dir = join(ROOT, 'tests')
  for (const name of readdirSync(dir).filter((n) => /^m0-.*\.case\.json$/.test(n)).sort()) {
    if (/-shot-/.test(name)) continue
    files.push(join(dir, name))
  }
}

const save = JSON.parse(readFileSync(join(ROOT, 'workspace', 'train', 'train.save.json'), 'utf8'))
const studio = createStudio(save, { workspacePath: ROOT })

let failures = 0
for (const file of files) {
  const raw = JSON.parse(readFileSync(file, 'utf8'))
  // 用例可以自带 canvasId（例如 m0-layout-pc 的 1600×900 期望值）；命令行的是兜底
  const useCanvas = raw.canvasId || canvasId
  let report
  try {
    report = studio.playRunCase(raw, useCanvas ? { canvasId: useCanvas } : {})
  } catch (err) {
    console.log(`\n## ${raw.name || file}\n  ERROR ${err && err.message ? err.message : err}`)
    failures += 1
    continue
  }
  const label = raw.name || file.split(/[\\/]/).pop()
  console.log(`\n## ${label}  ${report.passed ? 'PASS' : 'FAIL'}  (${report.results.filter((r) => r.ok).length}/${report.results.length} asserts)`)
  if (!report.passed) {
    failures += 1
    console.log(`  failedAt=${report.failedAt} frame=${report.frame}`)
    for (const row of report.results) {
      if (row.ok) continue
      console.log(`  ✗ [${row.kind}] at=${row.at} actual=${JSON.stringify(row.actual)} expected=${JSON.stringify(row.expected)} ${row.message || ''}`)
    }
  }
  const logs = (report.snapshot?.logs || []).map((row) => row.text)
  const head = logs.slice(0, 12)
  console.log('  logs(head): ' + JSON.stringify(head))
  if (logs.length > 12) console.log('  logs(tail): ' + JSON.stringify(logs.slice(-6)))
  studio.playStop()
}

console.log(`\n${failures === 0 ? 'ALL GREEN' : failures + ' case(s) FAILED'}  (canvas=${canvasId || 'editor default'})`)
process.exit(failures === 0 ? 0 : 1)
