/**
 * Tilmach 活跃度统计 Worker。
 *
 *   POST /v1/ping    客户端上报 (公开)
 *   GET  /           后台页面 (HTTP Basic, 用户名随意, 密码 = DASH_PASSWORD)
 *   GET  /api/stats  后台数据 (同样需要认证)
 *
 * 设计上刻意不采集任何可定位到个人的信息 —— 没有 IP、没有硬件标识、
 * 没有地理位置、没有用户输入的文本。详见 schema.sql 的注释。
 */

export interface Env {
  DB: D1Database;
  DASH_PASSWORD: string;
  APP_TAG: string;
}

const MAX_BODY = 32 * 1024;      // 一次最多 32KB, 正常一次几百字节
const MAX_DAYS = 90;             // 一次最多补 90 天
const MAX_COUNT = 100_000;       // 单日计数上限, 超过视为异常
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/**
 * 今天往前/后推 n 天的 YYYY-MM-DD。
 *
 * 用 UTC+8 而不是 UTC 算日期边界: 客户端上报的是**设备本地日期**, 而用户基本都在
 * 新疆/国内 (UTC+6~+8)。如果后台按 UTC 切天, 每天 UTC 00:00 之前的那 8 个小时里,
 * 用户已经进入"新的一天"而后台还在算前一天 —— "今日活跃"会长期偏低。
 */
const TZ_OFFSET_MS = 8 * 3600_000;

function dayOffset(n: number): string {
  const d = new Date(Date.now() + TZ_OFFSET_MS + n * 86400_000);
  return d.toISOString().slice(0, 10);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/v1/ping' && request.method === 'POST') {
      return ingest(request, env);
    }
    if (url.pathname === '/api/stats' && request.method === 'GET') {
      const bad = requireAuth(request, env);
      return bad ?? stats(env);
    }
    if (url.pathname === '/' && request.method === 'GET') {
      const bad = requireAuth(request, env);
      return bad ?? new Response(DASHBOARD_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
      });
    }
    return new Response('Not found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;

// ──────────────────────────────────────────── 认证

function requireAuth(request: Request, env: Env): Response | null {
  const want = env.DASH_PASSWORD;
  if (!want) return json({ error: '后台未设置密码，先 wrangler secret put DASH_PASSWORD' }, 500);

  const header = request.headers.get('authorization') ?? '';
  if (header.startsWith('Basic ')) {
    try {
      const decoded = atob(header.slice(6));
      const pass = decoded.slice(decoded.indexOf(':') + 1);
      if (timingSafeEqual(pass, want)) return null;
    } catch { /* 落到下面返回 401 */ }
  }
  return new Response('需要登录', {
    status: 401,
    headers: { 'www-authenticate': 'Basic realm="tilmach-stats", charset="UTF-8"' },
  });
}

/** 常量时间比较, 避免用响应时间猜密码 */
function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

// ──────────────────────────────────────────── 上报

async function ingest(request: Request, env: Env): Promise<Response> {
  const len = Number(request.headers.get('content-length') ?? '0');
  if (len > MAX_BODY) return json({ error: 'body too large' }, 413);

  let body: any;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  // APP_TAG 只是过滤扫描器的门槛, 不是安全边界 (APK 可反编译)。
  // 但没配置时必须**拒绝**而不是放行 —— 忘记设 secret 就变成任何人都能往
  // 数据库里灌数据, 这种 fail-open 的默认值是要出事的。
  if (!env.APP_TAG) {
    return json({ error: '服务端未配置 APP_TAG，先 wrangler secret put APP_TAG' }, 503);
  }
  if (body?.tag !== env.APP_TAG) {
    return json({ error: 'bad tag' }, 403);
  }

  const installId = String(body?.install_id ?? '');
  if (!UUID_RE.test(installId)) return json({ error: 'bad install_id' }, 400);

  const appVersion = typeof body?.app_version === 'string'
    ? body.app_version.slice(0, 32) : null;

  const rawDays = Array.isArray(body?.days) ? body.days : [];
  if (rawDays.length === 0 || rawDays.length > MAX_DAYS) {
    return json({ error: 'bad days' }, 400);
  }

  // 只接受合理时间范围内的日期。客户端用的是设备本地日期, 时区可能比 UTC 早一天,
  // 所以未来侧放宽到 +2 天。
  const lo = dayOffset(-MAX_DAYS);
  const hi = dayOffset(2);

  const rows: { day: string; launches: number; translations: number }[] = [];
  for (const d of rawDays) {
    const day = String(d?.day ?? '');
    if (!DAY_RE.test(day) || day < lo || day > hi) continue;
    const launches = clampCount(d?.launches);
    const translations = clampCount(d?.translations);
    if (launches === 0 && translations === 0) continue;
    rows.push({ day, launches, translations });
  }
  if (rows.length === 0) return json({ ok: true, accepted: 0 });

  const now = Date.now();
  const days = rows.map((r) => r.day).sort();

  // upsert: 客户端发的是绝对值, 所以直接覆盖。重复上报天然幂等。
  const stmts = rows.map((r) =>
    env.DB.prepare(
      `INSERT INTO daily (install_id, day, launches, translations, app_version, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(install_id, day) DO UPDATE SET
         launches = ?3, translations = ?4, app_version = ?5, updated_at = ?6`,
    ).bind(installId, r.day, r.launches, r.translations, appVersion, now),
  );

  // installs 表: first_day 取最小值 (min 保证补传旧数据时会把首见日期往前修正)
  stmts.push(
    env.DB.prepare(
      `INSERT INTO installs (install_id, first_day, last_day, app_version, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5)
       ON CONFLICT(install_id) DO UPDATE SET
         first_day = MIN(first_day, ?2),
         last_day  = MAX(last_day,  ?3),
         app_version = ?4,
         updated_at = ?5`,
    ).bind(installId, days[0], days[days.length - 1], appVersion, now),
  );

  try {
    await env.DB.batch(stmts);
  } catch (e) {
    return json({ error: 'db error' }, 500);
  }
  return json({ ok: true, accepted: rows.length });
}

function clampCount(v: unknown): number {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(n, MAX_COUNT);
}

// ──────────────────────────────────────────── 统计查询

async function stats(env: Env): Promise<Response> {
  const today = dayOffset(0);
  const d7 = dayOffset(-6);
  const d30 = dayOffset(-29);

  const q = <T>(sql: string, ...binds: unknown[]) =>
    env.DB.prepare(sql).bind(...binds).all<T>();

  const [totals, trend, versions, cohorts, heavy] = await Promise.all([
    // 总安装 / 今日活跃 / 7日活跃 / 30日活跃 / 累计翻译次数
    q<{ installs: number; dau: number; wau: number; mau: number; translations: number }>(
      `SELECT
         (SELECT COUNT(*) FROM installs)                                   AS installs,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day = ?1)     AS dau,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day >= ?2)    AS wau,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day >= ?3)    AS mau,
         (SELECT COALESCE(SUM(translations),0) FROM daily)                 AS translations`,
      today, d7, d30),

    // 最近 30 天曲线
    q<{ day: string; users: number; launches: number; translations: number; newcomers: number }>(
      `SELECT d.day,
              COUNT(DISTINCT d.install_id) AS users,
              SUM(d.launches)              AS launches,
              SUM(d.translations)          AS translations,
              (SELECT COUNT(*) FROM installs i WHERE i.first_day = d.day) AS newcomers
         FROM daily d
        WHERE d.day >= ?1
        GROUP BY d.day
        ORDER BY d.day`,
      d30),

    // 版本分布 (只看最近 30 天还活跃的)
    q<{ app_version: string; users: number }>(
      `SELECT COALESCE(app_version,'未知') AS app_version,
              COUNT(DISTINCT install_id)   AS users
         FROM daily WHERE day >= ?1
        GROUP BY app_version ORDER BY users DESC`,
      d30),

    // 留存: 按首见日期分组, 看有多少人在 D1 / D7 / D30 之后还回来过
    q<{ first_day: string; cohort: number; d1: number; d7: number; d30: number }>(
      `SELECT i.first_day,
              COUNT(*) AS cohort,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day = date(i.first_day, '+1 day')) THEN 1 ELSE 0 END) AS d1,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day >= date(i.first_day, '+7 day')) THEN 1 ELSE 0 END) AS d7,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day >= date(i.first_day, '+30 day')) THEN 1 ELSE 0 END) AS d30
         FROM installs i
        WHERE i.first_day >= ?1
        GROUP BY i.first_day ORDER BY i.first_day DESC LIMIT 30`,
      dayOffset(-90)),

    // 粘性: 最近 7 天里每人平均每天启动/翻译多少次
    q<{ avg_launches: number; avg_translations: number; active_days: number }>(
      `SELECT ROUND(AVG(launches), 1)      AS avg_launches,
              ROUND(AVG(translations), 1)  AS avg_translations,
              COUNT(*)                     AS active_days
         FROM daily WHERE day >= ?1`,
      d7),
  ]);

  return json({
    generated_at: new Date().toISOString(),
    totals: totals.results?.[0] ?? {},
    stickiness: heavy.results?.[0] ?? {},
    trend: trend.results ?? [],
    versions: versions.results ?? [],
    cohorts: cohorts.results ?? [],
  });
}

// ──────────────────────────────────────────── 后台页面
//
// 故意不引任何 CDN 上的图表库: 少一个外部依赖、少一个可能挂掉的点,
// 也避免后台页面把访问信息泄给第三方。图就用手写 SVG, 够看趋势就行。

const DASHBOARD_HTML = `<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tilmach 活跃度</title>
<style>
  :root{--blue:#2B6FF0;--ink:#1A1D22;--dim:#6B7480;--line:#E6EBF2;--bg:#F7FAFE}
  *{box-sizing:border-box}
  body{margin:0;padding:24px;background:var(--bg);color:var(--ink);
       font:15px/1.6 system-ui,-apple-system,"Segoe UI","Noto Sans SC",sans-serif}
  h1{font-size:22px;margin:0 0 4px}
  .sub{color:var(--dim);font-size:13px;margin-bottom:22px}
  .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:24px}
  .tile{background:#fff;border:1px solid var(--line);border-radius:14px;padding:16px 18px}
  .tile .k{color:var(--dim);font-size:12.5px}
  .tile .v{font-size:28px;font-weight:650;letter-spacing:-.5px;margin-top:2px}
  .tile .n{color:var(--dim);font-size:11.5px;margin-top:2px}
  section{background:#fff;border:1px solid var(--line);border-radius:14px;padding:18px;margin-bottom:18px}
  h2{font-size:14px;margin:0 0 14px;color:var(--dim);font-weight:600}
  table{width:100%;border-collapse:collapse;font-size:13.5px}
  th{text-align:left;color:var(--dim);font-weight:600;padding:6px 8px;border-bottom:1px solid var(--line)}
  td{padding:6px 8px;border-bottom:1px solid #F2F5F9}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  .empty{color:var(--dim);padding:12px 0}
  svg{display:block;width:100%;height:auto;overflow:visible}
</style></head><body>
<h1>Tilmach 活跃度</h1>
<div class="sub" id="ts">加载中…</div>
<div class="tiles" id="tiles"></div>
<section><h2>最近 30 天 · 每日活跃安装数（深色为当天新增）</h2><div id="chart"></div></section>
<section><h2>留存（按首次使用日期分组）</h2><div id="cohorts"></div></section>
<section><h2>版本分布（最近 30 天活跃）</h2><div id="versions"></div></section>
<script>
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const pct = (a, b) => b > 0 ? Math.round(a * 100 / b) + '%' : '—';

function tiles(t, s) {
  const items = [
    ['累计安装', t.installs ?? 0, '清除数据或重装会算作新安装'],
    ['今日活跃', t.dau ?? 0, ''],
    ['7 日活跃', t.wau ?? 0, t.installs ? pct(t.wau ?? 0, t.installs) + ' 的安装还在用' : ''],
    ['30 日活跃', t.mau ?? 0, ''],
    ['累计翻译次数', t.translations ?? 0, ''],
    ['人均每天启动', s.avg_launches ?? 0, '最近 7 天'],
    ['人均每天翻译', s.avg_translations ?? 0, '最近 7 天'],
  ];
  document.getElementById('tiles').innerHTML = items.map(([k, v, n]) =>
    '<div class="tile"><div class="k">' + esc(k) + '</div><div class="v">' + esc(v) +
    '</div><div class="n">' + esc(n) + '</div></div>').join('');
}

// 堆叠柱状图: 浅色 = 老用户, 深色 = 当天新增。手写 SVG, 不引图表库。
function chart(rows) {
  const box = document.getElementById('chart');
  if (!rows.length) { box.innerHTML = '<div class="empty">还没有数据</div>'; return; }
  const W = 900, H = 220, padL = 34, padB = 26, padT = 8;
  const max = Math.max(1, ...rows.map(r => r.users));
  const bw = (W - padL) / rows.length;
  const y = v => padT + (H - padT - padB) * (1 - v / max);

  let g = '';
  // 横向参考线 + 刻度
  for (let i = 0; i <= 2; i++) {
    const v = Math.round(max * i / 2), yy = y(v);
    g += '<line x1="' + padL + '" y1="' + yy + '" x2="' + W + '" y2="' + yy +
         '" stroke="#EDF1F7"/><text x="' + (padL - 6) + '" y="' + (yy + 4) +
         '" text-anchor="end" font-size="10" fill="#9AA4B2">' + v + '</text>';
  }
  rows.forEach((r, i) => {
    const x = padL + i * bw + bw * 0.18, w = Math.max(1, bw * 0.64);
    const nw = Math.min(r.newcomers || 0, r.users);
    const old = r.users - nw;
    // 老用户在下, 新增叠在上 —— 一眼能看出增长来自拉新还是留存
    if (old > 0) g += '<rect x="' + x + '" y="' + y(old) + '" width="' + w +
      '" height="' + (y(0) - y(old)) + '" fill="#9DC0F0" rx="1.5"/>';
    if (nw > 0) g += '<rect x="' + x + '" y="' + y(r.users) + '" width="' + w +
      '" height="' + (y(old) - y(r.users)) + '" fill="#2B6FF0" rx="1.5"/>';
    // 只在首尾和中间标日期, 避免糊成一团
    if (i === 0 || i === rows.length - 1 || i === (rows.length >> 1)) {
      g += '<text x="' + (x + w / 2) + '" y="' + (H - padB + 15) +
        '" text-anchor="middle" font-size="10" fill="#9AA4B2">' +
        esc(r.day.slice(5)) + '</text>';
    }
  });
  box.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" ' +
    'aria-label="最近 30 天每日活跃安装数">' + g + '</svg>';
}

function table(elId, cols, rows, emptyText) {
  const el = document.getElementById(elId);
  if (!rows.length) { el.innerHTML = '<div class="empty">' + esc(emptyText) + '</div>'; return; }
  const head = cols.map(c => '<th' + (c.num ? ' class="num"' : '') + '>' + esc(c.label) + '</th>').join('');
  const body = rows.map(r => '<tr>' + cols.map(c =>
    '<td' + (c.num ? ' class="num"' : '') + '>' + esc(c.get(r)) + '</td>').join('') + '</tr>').join('');
  el.innerHTML = '<table><thead><tr>' + head + '</tr></thead><tbody>' + body + '</tbody></table>';
}

fetch('/api/stats', { credentials: 'same-origin' })
  .then(r => r.ok ? r.json() : Promise.reject(r.status))
  .then(d => {
    document.getElementById('ts').textContent =
      '数据更新于 ' + new Date(d.generated_at).toLocaleString('zh-CN') +
      ' · 不采集 IP、位置、硬件标识和任何文本内容';
    tiles(d.totals || {}, d.stickiness || {});
    chart(d.trend || []);
    table('cohorts', [
      { label: '首次使用', get: r => r.first_day },
      { label: '人数', num: true, get: r => r.cohort },
      { label: '次日回访', num: true, get: r => r.d1 + ' (' + pct(r.d1, r.cohort) + ')' },
      { label: '7 天后仍在用', num: true, get: r => r.d7 + ' (' + pct(r.d7, r.cohort) + ')' },
      { label: '30 天后仍在用', num: true, get: r => r.d30 + ' (' + pct(r.d30, r.cohort) + ')' },
    ], d.cohorts || [], '还没有足够数据算留存');
    table('versions', [
      { label: '版本', get: r => r.app_version },
      { label: '活跃安装', num: true, get: r => r.users },
    ], d.versions || [], '还没有数据');
  })
  .catch(e => { document.getElementById('ts').textContent = '加载失败: ' + e; });
</script>
</body></html>`;
