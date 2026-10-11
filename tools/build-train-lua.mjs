// 无模块加载依赖的千星单文件；核心仍保留为可独立测试的 Lua 模块。
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const base=path.join(root,'workspace/train');
const core=fs.readFileSync(path.join(base,'train_core.lua'),'utf8');
const template=fs.readFileSync(path.join(base,'train_client.template.lua'),'utf8');
const output=template.replace('__TRAIN_CORE__',()=>`(function()\n${core}\nend)()`);
fs.writeFileSync(path.join(base,'train_game.lua'),output);
console.log('Built workspace/train/train_game.lua');
