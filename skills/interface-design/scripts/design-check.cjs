#!/usr/bin/env node
/**
 * design-check.cjs —— 界面设计稿的确定性视觉检查
 *
 * 用法：node design-check.cjs <html 路径或 URL> [--viewport 1440x900] [--shots <目录>]
 *
 * 每屏的期望焦点写在设计稿里：<section class="screen" data-focus=".cta">
 * 脚本真截图、真做灰度+高斯模糊（眯眼的物理本质就是低通滤波）、真算出画面上
 * 最吸引眼球的区域，再按几何映射回 DOM 元素，与声明的期望焦点核对。
 *
 * 退出码：0 通过 · 1 焦点不匹配或无可辨焦点 · 2 输入或选择器错误 · 3 依赖缺失
 */

const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// ---------- 依赖自检 ----------
function loadPlaywright() {
  try { return require('playwright'); } catch (_) { /* 继续找全局安装 */ }
  try {
    const root = execSync('npm root -g', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return require(path.join(root, 'playwright'));
  } catch (_) { /* 两条路都不通 */ }
  console.error('缺少 playwright，无法跑视觉检查。装它：');
  console.error('  npm i -g playwright && npx playwright install chromium');
  console.error('装不了时在报告里写明本次未跑视觉检查及原因，不要凭想象填写检查结论。');
  process.exit(3);
}

// ---------- 参数 ----------
const argv = process.argv.slice(2);
const target = argv.find((a) => !a.startsWith('--'));
if (!target) {
  console.error('用法：node design-check.cjs <html 路径或 URL> [--viewport 1440x900] [--shots <目录>]');
  process.exit(2);
}
const flag = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const [VW, VH] = flag('viewport', '1440x900').split('x').map(Number);
const url = /^https?:\/\//.test(target) ? target : 'file://' + path.resolve(target);
if (!/^https?:/.test(target) && !fs.existsSync(path.resolve(target))) {
  console.error(`找不到文件：${path.resolve(target)}`);
  process.exit(2);
}
const shotDir = flag('shots', /^https?:/.test(target) ? process.cwd() : path.dirname(path.resolve(target)));
const shotBase = path.join(shotDir, path.basename(target).replace(/\.\w+$/, ''));

const { chromium } = loadPlaywright();

// ---------- 页面内采集：DOM 事实 ----------
function collectDom() {
  const sx = window.scrollX, sy = window.scrollY;
  const abs = (el) => { const r = el.getBoundingClientRect(); return { x: r.x + sx, y: r.y + sy, w: r.width, h: r.height }; };
  const sel = (el) => {
    if (!el || el === document.body) return 'body';
    const id = el.id ? '#' + el.id : '';
    const cls = typeof el.className === 'string' && el.className.trim()
      ? '.' + el.className.trim().split(/\s+/).join('.') : '';
    return el.tagName.toLowerCase() + id + cls;
  };
  const isVisible = (el) => {
    const cs = getComputedStyle(el), b = abs(el);
    return b.w > 3 && b.h > 3 && cs.visibility !== 'hidden' && cs.display !== 'none' && parseFloat(cs.opacity) > 0;
  };

  const all = [...document.querySelectorAll('body *')].filter(isVisible);
  const elements = all.map((el) => {
    const cs = getComputedStyle(el), b = abs(el);
    return {
      sel: sel(el), ...b, area: b.w * b.h,
      text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 36),
      ownText: [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent.trim()).join(' ').trim(),
      fontSize: cs.fontSize, color: cs.color, bg: cs.backgroundColor,
    };
  });

  // 屏：带 data-focus 的元素；一个都没有时整页当单屏，期望焦点为空
  let screenEls = [...document.querySelectorAll('[data-focus]')].filter(isVisible);
  const declared = screenEls.length > 0;
  if (!declared) screenEls = [document.body];
  const screens = screenEls.map((el) => {
    const wanted = declared ? el.getAttribute('data-focus') : null;
    let want = null, wantErr = null;
    if (wanted) {
      let hit = null;
      try { hit = el.querySelector(wanted) || (document.querySelector(wanted)); } catch (e) { wantErr = '选择器语法无效'; }
      if (!wantErr && (!hit || !el.contains(hit))) wantErr = '选择器匹配不到元素';
      if (hit && el.contains(hit)) want = { sel: sel(hit), ...abs(hit), text: (hit.textContent || '').trim().slice(0, 36) };
    }
    return { sel: sel(el), ...abs(el), wanted, want, wantErr };
  });

  return { elements, screens, declared, pageW: document.documentElement.scrollWidth, pageH: document.documentElement.scrollHeight };
}

// ---------- 页面内分析：眯眼 ----------
// 灰度 + 高斯模糊后按网格采样，格亮度偏离页面背景亮度即为「跳出来」，
// 四邻域连通成区域，区域内偏差总和就是它抢走的注意力。
function analyzeScreens({ b64, pageW, pageH, boxes, blurDiv }) {
  return new Promise(async (resolve) => {
    const img = new Image();
    img.src = 'data:image/png;base64,' + b64;
    await img.decode();

    const out = boxes.map((box) => {
      const bw = Math.max(1, Math.round(box.w)), bh = Math.max(1, Math.round(box.h));
      const blur = Math.max(4, Math.round(bw / blurDiv));
      const c = document.createElement('canvas');
      c.width = bw; c.height = bh;
      const ctx = c.getContext('2d', { willReadFrequently: true });
      ctx.filter = `grayscale(1) blur(${blur}px)`;
      ctx.drawImage(img, box.x, box.y, bw, bh, 0, 0, bw, bh);
      const data = ctx.getImageData(0, 0, bw, bh).data;

      const COLS = 48, ROWS = Math.max(4, Math.round(COLS * bh / bw));
      const cw = bw / COLS, ch = bh / ROWS;
      const grid = [], hist = new Array(256).fill(0);
      for (let r = 0; r < ROWS; r++) {
        const row = [];
        for (let q = 0; q < COLS; q++) {
          let sum = 0, n = 0;
          const x0 = Math.floor(q * cw), x1 = Math.max(x0 + 1, Math.floor((q + 1) * cw));
          const y0 = Math.floor(r * ch), y1 = Math.max(y0 + 1, Math.floor((r + 1) * ch));
          for (let y = y0; y < y1; y += 2) for (let x = x0; x < x1; x += 2) { sum += data[(y * bw + x) * 4]; n++; }
          const v = Math.round(sum / Math.max(1, n));
          row.push(v); hist[v]++;
        }
        grid.push(row);
      }
      let bg = 0, best = -1;
      for (let i = 0; i < 256; i++) if (hist[i] > best) { best = hist[i]; bg = i; }

      let maxDev = 0;
      for (let r = 0; r < ROWS; r++) for (let q = 0; q < COLS; q++) maxDev = Math.max(maxDev, Math.abs(grid[r][q] - bg));
      // 焦点用自适应阈值——只有相对最跳的那些区域才算争夺注意力。
      const thresh = Math.max(10, maxDev * 0.25);
      // 墨水占比另用固定低阈值——问的是「多少地方不是空白」，与谁最跳无关。
      // 两者共用一个阈值时，一个强色块会把阈值抬高到滤掉所有正文，满屏文字反而算出低占比。
      const INK = 8;

      const seen = Array.from({ length: ROWS }, () => new Array(COLS).fill(false));
      const blobs = [];
      let inkCells = 0;
      for (let r = 0; r < ROWS; r++) for (let q = 0; q < COLS; q++) {
        if (Math.abs(grid[r][q] - bg) >= INK) inkCells++;
        if (seen[r][q] || Math.abs(grid[r][q] - bg) < thresh) continue;
        const stack = [[r, q]]; seen[r][q] = true;
        let ink = 0, x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1;
        while (stack.length) {
          const [rr, qq] = stack.pop();
          ink += Math.abs(grid[rr][qq] - bg);
          x0 = Math.min(x0, qq * cw); x1 = Math.max(x1, (qq + 1) * cw);
          y0 = Math.min(y0, rr * ch); y1 = Math.max(y1, (rr + 1) * ch);
          for (const [dr, dq] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const nr = rr + dr, nq = qq + dq;
            if (nr >= 0 && nr < ROWS && nq >= 0 && nq < COLS && !seen[nr][nq] && Math.abs(grid[nr][nq] - bg) >= thresh) {
              seen[nr][nq] = true; stack.push([nr, nq]);
            }
          }
        }
        blobs.push({ ink, cx: box.x + (x0 + x1) / 2, cy: box.y + (y0 + y1) / 2, w: x1 - x0, h: y1 - y0 });
      }
      blobs.sort((a, b) => b.ink - a.ink);
      return { blobs: blobs.slice(0, 8), inkRatio: inkCells / (COLS * ROWS) };
    });
    resolve(out);
  });
}

// ---------- 静态事实 ----------
function collectFacts() {
  const parse = (c) => { const m = c.match(/[\d.]+/g); return m ? m.slice(0, 3).map(Number) : [0, 0, 0]; };
  const alpha = (c) => { const m = c.match(/rgba?\([^)]*\)/); if (!m) return 1; const p = m[0].match(/[\d.]+/g); return p && p.length > 3 ? Number(p[3]) : 1; };
  const lum = ([r, g, b]) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const contrast = (a, b) => { const l1 = lum(a), l2 = lum(b); return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05); };
  const hsl = ([r, g, b]) => {
    r /= 255; g /= 255; b /= 255;
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
    let h = 0; if (d) { h = mx === r ? ((g - b) / d + (g < b ? 6 : 0)) : mx === g ? ((b - r) / d + 2) : ((r - g) / d + 4); h *= 60; }
    const l = (mx + mn) / 2, s = d ? d / (1 - Math.abs(2 * l - 1)) : 0;
    return [h, s, l];
  };
  const sel = (el) => {
    const cls = typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).join('.') : '';
    return el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + cls;
  };
  const effBg = (el) => {
    let n = el;
    while (n && n !== document.documentElement) {
      const c = getComputedStyle(n).backgroundColor;
      if (alpha(c) > 0) return parse(c);
      n = n.parentElement;
    }
    return [255, 255, 255];
  };
  const isVisible = (el) => {
    const r = el.getBoundingClientRect(), cs = getComputedStyle(el);
    return r.width > 3 && r.height > 3 && cs.visibility !== 'hidden' && cs.display !== 'none' && parseFloat(cs.opacity) > 0;
  };

  const vis = [...document.querySelectorAll('body *')].filter(isVisible);
  const ownText = (el) => [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent.trim()).join(' ').trim();
  const textEls = vis.filter((el) => ownText(el).length > 0);

  // 字阶
  const sizes = {};
  textEls.forEach((el) => { const s = getComputedStyle(el).fontSize; (sizes[s] ??= []).push(ownText(el).slice(0, 20)); });

  // 文本对比度：深字被调淡（可能是刻意降级的元信息）与浅字置于深底（读得清与否）分开归类
  const faded = [], onDark = [];
  textEls.forEach((el) => {
    const cs = getComputedStyle(el), fg = parse(cs.color), bg = effBg(el);
    const ratio = +contrast(fg, bg).toFixed(2);
    if (ratio >= 7) return;
    const rec = { sel: sel(el), text: ownText(el).slice(0, 26), color: cs.color, size: cs.fontSize, ratio };
    (lum(fg) < lum(bg) ? faded : onDark).push(rec);
  });

  // 红色系使用点
  const reds = [];
  vis.forEach((el) => {
    const cs = getComputedStyle(el);
    [['文字', cs.color], ['背景', cs.backgroundColor], ['边框', cs.borderTopColor]].forEach(([kind, c]) => {
      if (alpha(c) === 0) return;
      const [h, s, l] = hsl(parse(c));
      if (s > 0.35 && l > 0.15 && l < 0.75 && (h >= 340 || h <= 18)) {
        reds.push({ kind, color: c, sel: sel(el), text: (el.textContent || '').trim().slice(0, 26) });
      }
    });
  });

  // 非中性色种类
  const accents = {};
  vis.forEach((el) => {
    const cs = getComputedStyle(el);
    [cs.color, cs.backgroundColor].forEach((c) => {
      if (alpha(c) === 0) return;
      const [, s, l] = hsl(parse(c));
      if (s > 0.25 && l > 0.12 && l < 0.88) (accents[c] ??= new Set()).add(sel(el));
    });
  });

  // 并列组：同一父下同 tag 的可见兄弟，≥2 个成组
  const groups = [];
  const props = ['fontSize', 'fontWeight', 'color', 'backgroundColor', 'borderTopWidth', 'borderRadius', 'paddingTop'];
  vis.concat([document.body]).forEach((p) => {
    const kids = [...p.children].filter((k) => vis.includes(k));
    const byTag = {};
    kids.forEach((k) => (byTag[k.tagName] ??= []).push(k));
    Object.entries(byTag).forEach(([tag, members]) => {
      if (members.length < 2) return;
      const variants = {};
      members.forEach((m) => { const cs = getComputedStyle(m); props.forEach((pr) => (variants[pr] ??= new Set()).add(cs[pr])); });
      const differing = Object.entries(variants).filter(([, s]) => s.size > 1).map(([pr, s]) => `${pr} 有 ${s.size} 种（${[...s].join(' / ')}）`);
      const gaps = [];
      for (let i = 1; i < members.length; i++) {
        const a = members[i - 1].getBoundingClientRect(), b = members[i].getBoundingClientRect();
        gaps.push(Math.round(b.top - a.bottom));
      }
      groups.push({ parent: sel(p), tag: tag.toLowerCase(), count: members.length, differing, gaps, samples: members.map((m) => (m.textContent || '').trim().slice(0, 18)) });
    });
  });

  // 逐屏文本密度
  const screenEls = [...document.querySelectorAll('[data-focus]')].filter(isVisible);
  const scope = screenEls.length ? screenEls : [document.body];
  const density = scope.map((s) => {
    const blocks = [...s.querySelectorAll('*')].filter((el) => isVisible(el) && ownText(el).length > 0).map((el) => ownText(el).length);
    if (ownText(s).length) blocks.push(ownText(s).length);
    const total = blocks.reduce((a, b) => a + b, 0);
    return { sel: sel(s), total, blocks: blocks.length, avg: blocks.length ? Math.round(total / blocks.length) : 0, max: blocks.length ? Math.max(...blocks) : 0 };
  });

  return { sizes, faded, onDark, reds, accents: Object.fromEntries(Object.entries(accents).map(([k, v]) => [k, [...v]])), groups, density };
}

// ---------- 主流程 ----------
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1 });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(350);

  const dom = await page.evaluate(collectDom);
  const facts = await page.evaluate(collectFacts);

  // 选择器错误先于一切报出——期望焦点定不下来，后面的核对就没有意义
  const selErr = dom.screens.filter((s) => s.wantErr);
  if (selErr.length) {
    selErr.forEach((s) => console.error(`${s.sel} 的 data-focus="${s.wanted}" ${s.wantErr}`));
    console.error('把 data-focus 改成该屏内真实存在的选择器。');
    await browser.close();
    process.exit(2);
  }

  if (dom.pageH > 12000) {
    console.log(`提示：页面高 ${dom.pageH}px，超出单次分析的稳妥范围，建议拆文件后逐份检查。\n`);
  }

  const shot = await page.screenshot({ fullPage: true });
  const boxes = dom.screens.map((s) => ({ x: Math.round(s.x), y: Math.round(s.y), w: Math.round(s.w), h: Math.round(s.h) }));
  const analysis = await page.evaluate(analyzeScreens, {
    b64: shot.toString('base64'), pageW: dom.pageW, pageH: dom.pageH, boxes, blurDiv: 60,
  });

  // 落两张图：原样与眯眼后
  fs.writeFileSync(shotBase + '.png', shot);
  await page.addStyleTag({ content: `html{filter:grayscale(1) blur(${Math.max(4, Math.round(VW / 60))}px)!important}` });
  await page.waitForTimeout(200);
  await page.screenshot({ path: shotBase + '.squint.png', fullPage: true });
  await browser.close();

  // ---------- 焦点核对 ----------
  let failed = false;
  const p = console.log;
  p(`视口 ${VW}×${VH} · 页面 ${dom.pageW}×${dom.pageH} · ${dom.screens.length} 屏\n`);
  p('=== 焦点核对 ===');
  if (!dom.declared) {
    p('未声明 data-focus。整页按单屏处理，只输出吸引力排序，不做核对。');
    p('声明方式：给每屏根元素加 data-focus="该屏期望焦点的选择器"。\n');
  }

  dom.screens.forEach((s, i) => {
    const { blobs, inkRatio } = analysis[i];
    const den = facts.density[i] || { total: 0, blocks: 0, avg: 0, max: 0 };
    p(`${dom.screens.length > 1 ? `屏 ${i + 1} · ` : ''}${s.sel}`);

    if (!blobs.length) {
      p('  ✗ 本屏无可辨焦点：没有任何区域在眯眼后跳出来。');
      failed = true;
      p('');
      return;
    }

    const totalInk = blobs.reduce((a, b) => a + b.ink, 0) || 1;
    const inScreen = dom.elements.filter((e) => e.x >= s.x - 1 && e.y >= s.y - 1 && e.x + e.w <= s.x + s.w + 1 && e.y + e.h <= s.y + s.h + 1);
    const nameOf = (b) => {
      const area = Math.max(1, b.w * b.h);
      const hits = inScreen.filter((e) => e.x <= b.cx && b.cx <= e.x + e.w && e.y <= b.cy && b.cy <= e.y + e.h);
      if (!hits.length) return { sel: '(无匹配元素)', text: '' };
      hits.sort((a, c) => Math.abs(a.area - area) - Math.abs(c.area - area));
      return hits[0];
    };

    p('  吸引力排序：');
    blobs.slice(0, 4).forEach((b, k) => {
      const el = nameOf(b);
      p(`    ${k + 1}. ${el.sel}  ${(b.ink / totalInk * 100).toFixed(1)}%${el.text ? `  「${el.text}」` : ''}`);
    });

    if (s.want) {
      const lead = blobs[0];
      const hit = lead.cx >= s.want.x && lead.cx <= s.want.x + s.want.w && lead.cy >= s.want.y && lead.cy <= s.want.y + s.want.h;
      const actual = nameOf(lead);
      p(`  期望焦点  ${s.want.sel}${s.want.text ? `「${s.want.text}」` : ''}`);
      if (hit) {
        p('  ✓ 焦点匹配');
      } else {
        p(`  实际焦点  ${actual.sel}${actual.text ? `「${actual.text}」` : ''}  吸引力 ${(lead.ink / totalInk * 100).toFixed(1)}%`);
        p('  ✗ 焦点不匹配：眯眼后先跳出来的不是你声明的那个元素。');
        p('    改法二选一——削弱抢焦点的元素（去掉它的高饱和背景、缩小面积、降字重），');
        p('    或增强期望焦点（放大、加重、给它唯一的强调色）。');
        failed = true;
      }
      if (blobs[1]) {
        const ratio = lead.ink / blobs[1].ink;
        if (ratio < 1.5) {
          const second = nameOf(blobs[1]);
          p(`  ⚠ 焦点竞争：第一名仅领先 ${ratio.toFixed(2)}x（${actual.sel} vs ${second.sel}），两者在抢同一份注意力。`);
        }
      }
    }

    p(`  【版面密度】墨水占比 ${(inkRatio * 100).toFixed(1)}% · 字符总量 ${den.total} · 文本块 ${den.blocks} 个 · 平均 ${den.avg} 字 · 最长块 ${den.max} 字`);
    // 阈值按中文正文标定（实测：焦点正确的清爽单屏约 19%，塞满文字的单屏约 55%）。
    // 英文稿同样字数占的横向空间更多，四条字符类阈值按 1.6 倍放宽再看。
    if (inkRatio > 0.45) p('    ⚠ 墨水占比过高，版面接近塞满，留白已不足以承担分组。');
    if (den.total > 300) p('    ⚠ 一屏承载超过 300 字，先问哪些是这屏唯一目标必需的，其余下沉或分屏。');
    if (den.max > 80) p('    ⚠ 存在超过 80 字的文本块，读者要一口气读完才能取到信息，拆成短句或提取结论前置。');
    if (den.blocks > 10) p('    ⚠ 文本块超过 10 个，逐块说出它承载的信息，说不出的删。');
    p('');
  });

  // ---------- 事实清单 ----------
  p('=== 事实清单（脚本只报事实，逐条判断由你做，刻意违反要写清违反传达了什么）===\n');

  const sizeKeys = Object.keys(facts.sizes).sort((a, b) => parseFloat(b) - parseFloat(a));
  p(`【字阶】${sizeKeys.length} 种${sizeKeys.length > 3 ? '  ✗ 超过 3 种' : '  ✓'}`);
  sizeKeys.forEach((s) => p(`    ${s} ×${facts.sizes[s].length}  例：${facts.sizes[s].slice(0, 2).join(' | ')}`));

  p(`\n【灰字】被调淡的文本 ${facts.faded.length} 处，逐处核对是否只承载来源、时间戳、标签这类可跳过的元信息：`);
  facts.faded.length ? facts.faded.forEach((t) => p(`    ${t.ratio}:1  ${t.size}  ${t.color}  ${t.sel}  「${t.text}」`)) : p('    无');

  if (facts.onDark.length) {
    p(`\n【深底浅字】${facts.onDark.length} 处，对比度低于 7:1，核对小字号处是否仍读得清：`);
    facts.onDark.forEach((t) => p(`    ${t.ratio}:1  ${t.size}  ${t.sel}  「${t.text}」`));
  }

  p(`\n【红色扫描】红色系 ${facts.reds.length} 处，逐处核对是否落在错误、危险、删除、警告的语义上：`);
  facts.reds.length ? facts.reds.forEach((r) => p(`    ${r.kind} ${r.color}  ${r.sel}  「${r.text}」`)) : p('    无');

  const accKeys = Object.keys(facts.accents);
  p(`\n【强调色】非中性色 ${accKeys.length} 种，核对每种在整份稿子里是否只有一个含义：`);
  accKeys.forEach((c) => p(`    ${c}  用在 ${facts.accents[c].slice(0, 4).join(', ')}${facts.accents[c].length > 4 ? ` 等 ${facts.accents[c].length} 处` : ''}`));

  p('\n【并列组】说出每组共同的总体名词；说不出的成员拆出去，有先后或从属关系的改用序号、时间轴、嵌套：');
  facts.groups.forEach((g) => {
    p(`    ${g.parent} > ${g.tag} ×${g.count}${g.count > 4 ? '  ✗ 超过 4 个' : ''}`);
    p(`      成员：${g.samples.join(' | ')}`);
    if (g.gaps.length) {
      const uniq = [...new Set(g.gaps)];
      p(`      组内间距：${g.gaps.join(', ')}px${uniq.length > 1 ? '  ⚠ 组内间距不齐' : ''}`);
    }
  });

  const uneven = facts.groups.filter((g) => g.differing.length);
  p(`\n【同级同装】并列组内样式不一致的 ${uneven.length} 组。差异要么编码一个真实的信息差异，要么去掉：`);
  uneven.length ? uneven.forEach((g) => {
    p(`    ${g.parent} > ${g.tag} ×${g.count}`);
    g.differing.forEach((d) => p(`      ${d}`));
  }) : p('    无');

  p(`\n截图：${shotBase}.png`);
  p(`眯眼图：${shotBase}.squint.png`);
  p('眯眼图是脚本判定的原始依据，看它可以核对上面的排序，也能看出脚本量不到的整体观感。');

  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('检查过程出错：' + e.message);
  process.exit(2);
});
