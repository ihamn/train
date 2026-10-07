#!/usr/bin/env node
/**
 * 从完整存档导出千星 GIA（真机导入用），并在模拟器侧做往返校验。
 *
 * 为什么用脚本而不是顶栏「导出」按钮：顶栏导出是人工 UI 动作；这里调的是
 * 「模拟器自己的 GIA 编解码器」（studio/index.js 的 exportData / importData），
 * 出同一批格式，好处是能在同一进程里把导出的 GIA 再导入回来比对 ——
 * 导出物不是"看起来生成了"，而是过了一遍往返。
 *
 * 用法：
 *   QXQY_STUDIO="D:/miliastra-beyond-simulator/studio/index.js" node tools/export_gia.mjs
 *
 * 产物：workspace/train/export/
 *   · <存档名> · 资产包.gia  整合包：服务端 UIControlGroup + 客户端模板并排同一 Root.graph，
 *                            脚本源码与其控件挂载（scriptMappingIds）一起带走
 *   · 服务端控件.gia         资产包 GIA（已改动项）拆出的控制类资产
 *   · <存档名> · 脚本.gia    同一批拆出的脚本类资产
 *   · export-report.json     导出清单 + 往返校验结果
 *
 * 边界：本脚本只生成文件与做模拟器侧校验，**不代表真机导入通过**。
 * 真机结果记 records/playtest.md；模拟器绿灯不是发布通过。
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)))
const STUDIO_ENTRY = process.env.QXQY_STUDIO
if (!STUDIO_ENTRY) {
  console.error('缺少 QXQY_STUDIO：请指向模拟器仓库的 studio/index.js')
  process.exit(2)
}

const { createStudio } = await import(pathToFileURL(STUDIO_ENTRY).href)

const SAVE_PATH = join(ROOT, 'workspace', 'train', 'train.save.json')
const OUT_DIR = join(ROOT, 'workspace', 'train', 'export')
mkdirSync(OUT_DIR, { recursive: true })

const save = JSON.parse(readFileSync(SAVE_PATH, 'utf8'))
if (save.format !== 'qxqy-simulator-save') throw new Error(`不是模拟器存档：${save.format}`)

// 用交付存档喂一台独立的 studio 实例：导出的是"存档里那一份"，不是 DSH 会话里的内存态
const studio = createStudio(save, { workspacePath: ROOT })

const expectedNames = []
const collect = (nodes) => { for (const node of nodes || []) { expectedNames.push(node.name); collect(node.children) } }
collect(save.assets.server.root.children)
const expectedScript = save.assets.scripts[0]

function writeArtifact(result) {
  const bytes = Buffer.from(result.data, 'base64')
  writeFileSync(join(OUT_DIR, result.filename), bytes)
  return { file: result.filename, bytes: bytes.length, warnings: result.warnings || [] }
}

/** 导入一份 GIA 到全新 studio，取它认出来的控件名与脚本 */
function inspectGia(base64, filename) {
  const fresh = createStudio()
  const back = fresh.importData('gia', base64, filename)
  // 服务端控件容器的根自身没有 parentId；其余行就是我们要比对的控件
  const names = (back.snapshot.tree || []).filter((row) => row.parentId !== null).map((row) => row.name)
  const script = (back.snapshot.scripts || [])[0] || null
  return {
    names,
    missing: expectedNames.filter((n) => !names.includes(n)),
    extra: names.filter((n) => !expectedNames.includes(n)),
    warnings: back.warnings || [],
    script: script && {
      path: script.path,
      controlId: script.controlId,
      controlAsset: script.controlAsset,
      sourceSame: script.source === expectedScript.source,
    },
  }
}

const artifacts = []
const warnings = []
const roundtrip = []

// ── 1. 资产包 GIA（已改动项）：官方三类各自独立文件 ───────────────────────────
const pack = studio.exportData('archive-gia')
for (const entry of pack.files || []) {
  artifacts.push(writeArtifact(entry))
  if (entry.mimeType === 'application/octet-stream' && /控件|界面/.test(entry.filename)) {
    roundtrip.push({ gia: entry.filename, purpose: '资产包里的控制类 GIA', ...inspectGia(entry.data, entry.filename) })
  } else if (entry.mimeType === 'application/octet-stream') {
    const fresh = createStudio()
    const back = fresh.importData('gia', entry.data, entry.filename)
    const script = (back.snapshot.scripts || [])[0] || null
    roundtrip.push({
      gia: entry.filename,
      purpose: '资产包里的脚本 GIA',
      controls: null,
      script: script && {
        path: script.path,
        controlId: script.controlId,
        controlAsset: script.controlAsset,
        sourceSame: script.source === expectedScript.source,
      },
      warnings: back.warnings || [],
    })
  }
}
warnings.push(...(pack.warnings || []))

// ── 2. 整合包 GIA：服务端 + 客户端并排，脚本带挂载关系 ───────────────────────
const combined = studio.exportData('gia-combined')
artifacts.push(writeArtifact(combined))
warnings.push(...(combined.warnings || []))
roundtrip.push({ gia: combined.filename, purpose: '整合包（推荐导入千星用这个）', ...inspectGia(combined.data, combined.filename) })

const report = { save: SAVE_PATH, outDir: OUT_DIR, artifacts, warnings, roundtrip }
writeFileSync(join(OUT_DIR, 'export-report.json'), JSON.stringify(report, null, 2))
console.log(JSON.stringify(report, null, 2))
