#!/usr/bin/env node
/*
 * render-assets.mjs — 把概念 SVG 导出成鸿蒙工程要用的图标资源。
 *
 * 概念 SVG 里有两层，用 id 标好：
 *   <g id="layer-background">  背景层（品牌蓝，不透明满幅）
 *   <g id="layer-foreground">  前景层（白色图形，透明底）
 * 这个脚本按需隐藏其中一层，再让无头 Chrome 把 SVG 光栅化成 PNG：
 *   foreground.png  只有前景层，1024×1024，RGBA 透明底 —— 分层图标前景层
 *   background.png  只有背景层，1024×1024，RGB（去掉 alpha）—— 分层图标背景层
 *   startIcon.png   两层合成 + 圆角，1024×1024，RGBA —— 启动页图标
 *   icon-composite.png 两层合成，1024×1024，RGBA —— 给设计稿/文档用
 *
 * 用法：
 *   node tools/render-assets.mjs --concept concepts/concept-a-photo-card.svg --out app-icon
 *   node tools/render-assets.mjs --concept concepts/concept-a-photo-card.svg --out ../entry/src/main/resources/base/media --install
 *
 * --install 会直接覆盖目标目录里的 foreground.png / background.png / startIcon.png，
 * 另有 --name-prefix 可给输出加前缀（用于同时保留多套方案）。
 */
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const CANVAS = 1024;
/** 圆角方形遮罩半径，与鸿蒙桌面图标观感一致（24% 边长）。 */
const MASK_RX = Math.round(CANVAS * 0.227);

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return i > -1 ? process.argv[i + 1] : fallback;
}
const has = (name) => process.argv.includes('--' + name);

function layerSvg(svgText, mode) {
  if (mode === 'composite') {
    return svgText;
  }
  const css = mode === 'foreground'
    ? '#layer-background{display:none}'
    : '#layer-foreground{display:none}';
  return svgText.replace('</svg>', '  <style>' + css + '</style>\n</svg>');
}

function renderPng(svgText, outPath, size) {
  const dir = mkdtempSync(path.join(tmpdir(), 'idicon-'));
  try {
    writeFileSync(path.join(dir, 'art.svg'), svgText);
    writeFileSync(path.join(dir, 'page.html'),
      '<!doctype html><html><head><meta charset="utf-8"><style>' +
      'html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
      'img{display:block;width:' + size + 'px;height:' + size + 'px}</style></head>' +
      '<body><img src="art.svg" alt=""></body></html>');
    execFileSync(CHROME, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
      '--default-background-color=00000000',
      '--window-size=' + size + ',' + size,
      '--screenshot=' + outPath,
      'file://' + path.join(dir, 'page.html'),
    ], { stdio: ['ignore', 'ignore', 'pipe'] });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** 读 PNG 的 IHDR，确认尺寸与色彩类型（6 = RGBA，2 = RGB）。 */
function pngInfo(file) {
  const buf = readFileSync(file);
  const sig = buf.subarray(0, 8).toString('hex');
  if (sig !== '89504e470d0a1a0a') {
    throw new Error('not a PNG: ' + file);
  }
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
    bitDepth: buf[24],
    colorType: buf[25],
  };
}

function flattenToRgb(file) {
  execFileSync('python3', ['-c', `
from PIL import Image
im = Image.open(${JSON.stringify(file)})
if im.mode != 'RGB':
    bg = Image.new('RGB', im.size, (255, 255, 255))
    bg.paste(im.convert('RGBA'), mask=im.convert('RGBA').split()[3])
    bg.save(${JSON.stringify(file)}, 'PNG', optimize=True)
`]);
}

function main() {
  const concept = path.resolve(ROOT, arg('concept', 'concepts/concept-a-photo-card.svg'));
  const outDir = path.resolve(ROOT, arg('out', 'app-icon'));
  const prefix = arg('name-prefix', '');
  const svg = readFileSync(concept, 'utf8');
  mkdirSync(outDir, { recursive: true });

  const plan = [
    { file: prefix + 'foreground.png', svg: layerSvg(svg, 'foreground'), rgb: false, vector: true },
    { file: prefix + 'background.png', svg: layerSvg(svg, 'background'), rgb: true, vector: true },
    { file: prefix + 'startIcon.png', svg: startIconSvg(svg), rgb: false, vector: true },
    { file: prefix + 'icon-composite.png', svg: layerSvg(svg, 'composite'), rgb: false },
    // AGC 应用市场要 216×216 直角图标（非分层图）。
    { file: prefix + 'icon-216.png', svg: layerSvg(svg, 'composite'), rgb: false, size: 216 },
  ];

  for (const item of plan) {
    const out = path.join(outDir, item.file);
    const size = item.size || CANVAS;
    if (item.vector) {
      // 顺带留下每层的矢量源，方便以后改配色或改形状。
      writeFileSync(out.replace(/\.png$/, '.svg'), item.svg);
    }
    renderPng(item.svg, out, size);
    if (item.rgb) {
      flattenToRgb(out);
    }
    const info = pngInfo(out);
    console.log(item.file.padEnd(24), info.width + '×' + info.height,
      info.colorType === 6 ? 'RGBA' : 'RGB');
    if (info.width !== size || info.height !== size) {
      throw new Error('unexpected size for ' + item.file);
    }
  }
  console.log('\n写到 ' + outDir);
  if (!has('install')) {
    console.log('（没有 --install，只是预览产物；加 --install 才会覆盖工程资源）');
  }
}

/** 启动页图标：合成两层后套一层圆角方形，圆角外透明。 */
function startIconSvg(svgText) {
  const body = svgText
    .replace(/^[\s\S]*?<\/title>/, '')
    .replace(/<\/svg>\s*$/, '');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
    + 'width="1024" height="1024" role="img" aria-label="启动页图标">'
    + '<defs><clipPath id="startClip">'
    + '<rect x="0" y="0" width="1024" height="1024" rx="' + MASK_RX + '"/>'
    + '</clipPath></defs>'
    + '<g clip-path="url(#startClip)">' + body + '</g></svg>';
}

main();
