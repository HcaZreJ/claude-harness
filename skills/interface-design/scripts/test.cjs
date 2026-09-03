// design-check.cjs 的验收测试。跑法：node test.cjs
const { execFileSync } = require('child_process');
const path = require('path');

const CHECK = path.join(__dirname, 'design-check.cjs');
const FIX = (n) => path.join(__dirname, 'fixtures', n);

function run(file, args = []) {
  try {
    const out = execFileSync('node', [CHECK, FIX(file), '--shots', require('os').tmpdir(), ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status, out: (e.stdout || '') + (e.stderr || '') };
  }
}

const cases = [
  ['焦点被抢的页面报不匹配，并点名实际抢焦点的元素', () => {
    const r = run('bad.html');
    return r.code === 1 && /✗ 焦点不匹配/.test(r.out) && /card\.hot/.test(r.out);
  }],
  ['焦点正确的页面通过', () => {
    const r = run('good.html');
    return r.code === 0 && /✓ 焦点匹配/.test(r.out);
  }],
  ['多屏逐屏核对：第一屏过、第二屏不过，报告点名是哪一屏', () => {
    const r = run('multi.html');
    return r.code === 1 && /#s1[\s\S]*?✓ 焦点匹配/.test(r.out) && /#s2[\s\S]*?✗ 焦点不匹配/.test(r.out);
  }],
  ['未声明 data-focus 时只输出排序，不判定失败', () => {
    const r = run('nofocus.html');
    return r.code === 0 && /未声明 data-focus/.test(r.out) && /吸引力/.test(r.out);
  }],
  ['data-focus 指向不存在的元素时报错并指出选择器', () => {
    const r = run('badselector.html');
    return r.code === 2 && /选择器匹配不到/.test(r.out) && /does-not-exist/.test(r.out);
  }],
  ['红色扫描列出红色系使用点', () => {
    const r = run('bad.html');
    return /【红色扫描】/.test(r.out) && /card\.hot/.test(r.out) && /rgb\(220, 38, 38\)/.test(r.out);
  }],
  ['同级同装检查报出并列组内不一致的样式属性', () => {
    const r = run('bad.html');
    return /【同级同装】/.test(r.out) && /backgroundColor/.test(r.out);
  }],
  ['文字过量页面报出密度指标与超标字阶', () => {
    const r = run('dense.html');
    return /【版面密度】/.test(r.out) && /字符总量/.test(r.out) && /最长块/.test(r.out)
        && /【字阶】/.test(r.out) && /超过 3/.test(r.out);
  }],
];

let pass = 0;
cases.forEach(([name, fn], i) => {
  let ok = false, err = '';
  try { ok = fn(); } catch (e) { err = ' — ' + e.message; }
  console.log(`${ok ? '✓' : '✗'} ${i + 1}. ${name}${err}`);
  if (ok) pass++;
});
console.log(`\n${pass}/${cases.length} 通过`);
process.exit(pass === cases.length ? 0 : 1);
