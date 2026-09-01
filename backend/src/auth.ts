/**
 * 后台登录 + 写操作鉴权。
 *
 * 打开后台地址要先输密码。密码对了就发一个签名 cookie, 之后这个浏览器里读和写
 * 都不用再问 —— 上传横幅、停用、删除都靠这个 cookie。
 *
 * ## 为什么不再用 prompt() 问口令
 * 上一版没有登录页, 写操作靠 `x-dash-pw` 请求头, 口令用 prompt() 问一次存在
 * sessionStorage。结果在手机浏览器上是坏的: 相当多的国内浏览器内核直接吞掉
 * prompt(), 立刻返回 null, 于是每次点「删除」「停用」都走进"用户取消了"分支,
 * 表面上就是**按钮全部失效**。密码要用真正的 <input> 收, 不能用 prompt()。
 *
 * ## 为什么登录必须用 fetch() 而不是顶层表单 POST
 * Chromium 给顶层表单 POST 算 Origin 头时会套用页面的 referrer policy,
 * no-referrer 下会发 `Origin: null` —— 本站的登录表单看起来像跨站请求, 被自己
 * 的来源检查挡掉, 把管理员锁在门外。fetch() 不受 referrer policy 影响。
 * 登录本身也不做来源检查: 要伪造登录得先知道密码, 那时已经没什么可防的了。
 *
 * ## 密码的来源
 * D1 的 config.dash_password 优先 (在后台页面上改过的), 没有那行就用部署时
 * `wrangler secret put DASH_PASSWORD` 设的那个。忘了密码就把那行删掉:
 *
 *   wrangler d1 execute tilmach-stats --remote \
 *     --command "DELETE FROM config WHERE k='dash_password'"
 */

import { Env, b64urlEncode, json, timingSafeEqual } from './shared';

/** 会话 cookie 名 */
const COOKIE = 'xdash';

/** 会话有效期。到期就重新输一次密码。 */
const SESSION_TTL_MS = 7 * 86400_000;
const SESSION_MSG = 'tilmach-dash-session-v1:';

/** 脚本 / curl 用的旁路: 带上这个头也算通过写鉴权 */
const PW_HEADER = 'x-dash-pw';

/** 限流: 同一 IP 在一个 15 分钟窗口里最多试这么多次 */
const FAIL_WINDOW_MS = 15 * 60_000;
const FAIL_LIMIT = 8;

/** config 表里存"改过的口令"的那一行 */
const PW_ROW = 'dash_password';
const PW_FMT = 'hmac-sha256:v1:';
const PW_MSG = 'tilmach-dash-pw-v1:';

/** 口令长度下限。这是个挂在公网上的输入框, 8 位太短 */
const PW_MIN = 10;
const PW_MAX = 128;

async function hmac(key: string, msg: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64urlEncode(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(msg)));
}

// ──────────────────────────────────────────── 会话
/**
 * 签名密钥取"当前有效的那份口令凭据"(D1 里的哈希, 或者初始 secret)。
 * 好处是**改密码等于把所有会话作废** —— 密码泄露时换一个就够, 不用另做一套
 * 会话吊销。代价是改密码的那个响应必须顺手换一张新 cookie, 否则管理员会被
 * 自己刚改的密码当场踢出去 (见 changePassword)。
 */
async function sessionKey(env: Env): Promise<string> {
  return (await loadStored(env)) ?? env.DASH_PASSWORD;
}

async function mintSession(env: Env): Promise<string> {
  const exp = Date.now() + SESSION_TTL_MS;
  return `${exp}.${await hmac(await sessionKey(env), SESSION_MSG + exp)}`;
}

async function sessionValid(env: Env, token: string | null): Promise<boolean> {
  if (!token) return false;
  const dot = token.indexOf('.');
  if (dot < 1) return false;
  const exp = Number(token.slice(0, dot));
  if (!Number.isFinite(exp) || exp < Date.now()) return false;
  const want = await hmac(await sessionKey(env), SESSION_MSG + exp);
  return timingSafeEqual(token.slice(dot + 1), want);
}

function readCookie(request: Request, name: string): string | null {
  const raw = request.headers.get('cookie');
  if (!raw) return null;
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    if (part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return null;
}

/**
 * 这个请求是不是已登录。
 *
 * **只在后台自己的路由上调它** —— 它要读一次 D1。给 App 的 /v1/* 和 /img/*
 * 必须在这之前就返回, 不能为了判断登录态给每个 App 请求加一次数据库读。
 */
export async function hasSession(request: Request, env: Env): Promise<boolean> {
  return sessionValid(env, readCookie(request, COOKIE));
}

/** SameSite=Lax 而不是 Strict: 从别处点链接/书签进来是顶层 GET, Lax 会带上
 *  cookie (Strict 不会, 那样每次都得重新登录); 跨站 POST 依然不带, CSRF 照样挡住。 */
function setCookie(token: string, maxAgeSec: number): string {
  return `${COOKIE}=${token}; Path=/; Max-Age=${maxAgeSec}; HttpOnly; Secure; SameSite=Lax`;
}

/** POST /login  表单字段: password */
export async function handleLogin(request: Request, env: Env): Promise<Response> {
  if (!env.DASH_PASSWORD) {
    return json({ error: '后台还没设密码，先跑 wrangler secret put DASH_PASSWORD' }, 500);
  }
  const ip = request.headers.get('cf-connecting-ip') ?? '0.0.0.0';
  const gate = await checkFailures(env, ip);
  if (gate > 0) return json({ error: `试错太多次了，${gate} 分钟后再来` }, 429);

  const form = await request.formData().catch(() => null);
  const given = String(form?.get('password') ?? '');
  if (!await verifyPassword(env, await loadStored(env), given)) {
    await recordFailure(env, ip);
    // 稍微拖一下, 让在线爆破更不划算 (常量时间比较已经挡住了计时侧信道)
    await new Promise((r) => setTimeout(r, 400));
    return json({ error: given ? '密码不对' : '请输入密码' }, 401);
  }
  return json({ ok: true }, 200, {
    'set-cookie': setCookie(await mintSession(env), SESSION_TTL_MS / 1000),
  });
}

/** POST /logout */
export function handleLogout(): Response {
  return json({ ok: true }, 200, { 'set-cookie': setCookie('', 0) });
}

// ──────────────────────────────────────────── 当前有效的口令
/**
 * 口令有两处来源:
 *   1. 部署时 `wrangler secret put DASH_PASSWORD` 设的那个 —— 初始口令, 同时**永远**
 *      是下面那串哈希的"胡椒";
 *   2. 在后台页面上改过之后, D1 的 config 表里 `dash_password` 那一行 ——
 *      一旦存在就以它为准。
 *
 * 为什么改口令只能落到 D1: Worker 改不了自己的 secret, 那需要一个 Cloudflare API
 * token, 等于为了改口令把一把权限更大的钥匙常驻在线上环境里, 不划算。
 *
 * 存进 D1 的**既不是明文也不是普通哈希**, 而是 HMAC(key = DASH_PASSWORD, msg = 口令):
 * 密钥不在数据库里, 所以光拖走一份 D1 备份也没法离线爆破。代价是 DASH_PASSWORD
 * 这个 secret 不能再随手换 —— 换了等于把改过的口令作废, 得先删掉那一行。
 */

/** 返回 D1 里存的那串哈希; null = 没改过, 以 env.DASH_PASSWORD 为准 */
async function loadStored(env: Env): Promise<string | null> {
  const row = await env.DB.prepare('SELECT v FROM config WHERE k = ?1')
    .bind(PW_ROW).first<{ v: string }>().catch(() => null);
  return row?.v?.startsWith(PW_FMT) ? row.v : null;
}

async function fingerprint(env: Env, password: string): Promise<string> {
  return PW_FMT + await hmac(env.DASH_PASSWORD, PW_MSG + password);
}

async function verifyPassword(env: Env, stored: string | null, password: string): Promise<boolean> {
  if (!password) return false;
  return stored
    ? timingSafeEqual(stored, await fingerprint(env, password))
    : timingSafeEqual(password, env.DASH_PASSWORD);
}

/**
 * 写操作的来源检查。/admin/* 都是后台页面里的 fetch(), 浏览器一定会带上准确的
 * Origin, 所以严格判断是安全的。
 *
 * (曾经也用在登录表单上, 那是个错误: 顶层表单 POST 的 Origin 头会受 referrer
 *  policy 影响, Chromium 在 no-referrer 下发 `Origin: null`, 结果把管理员自己
 *  锁在门外。现在没有登录表单了, 但这个坑值得记着。)
 */
export function sameOrigin(request: Request): boolean {
  const origin = request.headers.get('origin');
  // 没有 Origin 只可能来自 curl 这类非浏览器客户端, 构不成 CSRF
  if (!origin) return true;
  // `null` 是不透明来源 (sandbox iframe 等)。写操作不接受。
  if (origin === 'null') return false;
  try {
    return new URL(origin).host === new URL(request.url).host;
  } catch {
    return false;
  }
}

/**
 * 每个 /admin/* 请求进来先过这里。
 * 返回 null = 放行; 返回 Response = 直接把它回给客户端。
 *
 * 两条通过途径: 登录会话 cookie (页面用的), 或者 x-dash-pw 请求头 (curl / 脚本用的)。
 * 401 是给页面看的信号: 前端收到 401 就跳回登录页。
 */
export async function requireWrite(request: Request, env: Env): Promise<Response | null> {
  if (!env.DASH_PASSWORD) return json({ error: '后台还没设密码，先跑 wrangler secret put DASH_PASSWORD' }, 500);
  if (!sameOrigin(request)) return json({ error: '请求来源不对' }, 403);

  if (await hasSession(request, env)) return null;

  const ip = request.headers.get('cf-connecting-ip') ?? '0.0.0.0';
  const gate = await checkFailures(env, ip);
  if (gate > 0) return json({ error: `试错太多次了，${gate} 分钟后再来` }, 429);

  const given = request.headers.get(PW_HEADER) ?? '';
  if (!await verifyPassword(env, await loadStored(env), given)) {
    if (given) await recordFailure(env, ip);
    await new Promise((r) => setTimeout(r, 400));
    return json({ error: given ? '密码不对' : '需要登录' }, 401);
  }
  return null;
}

// ──────────────────────────────────────────── 改密码

/** 返回一句"为什么不合格"; null = 可以用 */
function checkStrength(pw: string): string | null {
  if (pw.length < PW_MIN) return `新密码至少 ${PW_MIN} 位`;
  if (pw.length > PW_MAX) return `新密码最多 ${PW_MAX} 位`;
  if (pw !== pw.trim()) return '新密码开头或结尾有空格，复制时很容易漏掉';
  const kinds = [/[a-z]/, /[A-Z]/, /[0-9]/, /[^A-Za-z0-9]/]
    .filter((re) => re.test(pw)).length;
  if (kinds < 2) return '新密码要混用两种以上字符（大小写字母、数字、符号）';
  return null;
}

/**
 * POST /admin/password  表单: next, confirm
 *
 * 不需要 `current` —— 走到这里说明 requireWrite 已经确认过身份了。
 */
export async function changePassword(request: Request, env: Env): Promise<Response> {
  const form = await request.formData().catch(() => null);
  if (!form) return json({ error: '表单解析失败' }, 400);
  const next = String(form.get('next') ?? '');
  const confirm = String(form.get('confirm') ?? '');

  if (next !== confirm) return json({ error: '两次输入的新密码不一样' }, 400);
  const weak = checkStrength(next);
  if (weak) return json({ error: weak }, 400);

  const stored = await loadStored(env);
  if (await verifyPassword(env, stored, next)) {
    return json({ error: '新密码和现在这个一样' }, 400);
  }

  await env.DB.prepare(
    `INSERT INTO config (k, v, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT(k) DO UPDATE SET v = ?2, updated_at = ?3`,
  ).bind(PW_ROW, await fingerprint(env, next), Date.now()).run();

  // 会话签名密钥跟着口令凭据变, 所以刚才那张 cookie 已经失效了。
  // 顺手换一张新的, 否则改完密码下一次操作就被自己踢回登录页。
  // (别的浏览器上的会话确实作废了 —— 这正是想要的。)
  return json({ ok: true }, 200, {
    'set-cookie': setCookie(await mintSession(env), SESSION_TTL_MS / 1000),
  });
}

// ──────────────────────────────────────────── 失败计数

async function ipHash(env: Env, ip: string): Promise<string> {
  // 拿 secret 当盐: 数据库被看到也反推不出访问者 IP。
  // 用 DASH_PASSWORD 而不是"当前有效口令" —— 盐要稳定, 否则一改密码就把攻击者的
  // 计数清零, 白送对方一轮 8 次。
  const digest = await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(`${ip}:${env.DASH_PASSWORD}`));
  return b64urlEncode(digest).slice(0, 22);
}

/** 返回还需要等几分钟; 0 表示可以试 */
async function checkFailures(env: Env, ip: string): Promise<number> {
  const win = Math.floor(Date.now() / FAIL_WINDOW_MS);
  const row = await env.DB.prepare('SELECT n FROM login_fail WHERE ip_hash=?1 AND win=?2')
    .bind(await ipHash(env, ip), win).first<{ n: number }>().catch(() => null);
  if (!row || row.n < FAIL_LIMIT) return 0;
  const msLeft = (win + 1) * FAIL_WINDOW_MS - Date.now();
  return Math.max(1, Math.ceil(msLeft / 60_000));
}

async function recordFailure(env: Env, ip: string): Promise<void> {
  const win = Math.floor(Date.now() / FAIL_WINDOW_MS);
  const h = await ipHash(env, ip);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO login_fail (ip_hash, win, n) VALUES (?1, ?2, 1)
       ON CONFLICT(ip_hash, win) DO UPDATE SET n = n + 1`).bind(h, win),
    // 顺手清掉两个窗口以前的记录, 不用另开定时任务
    env.DB.prepare('DELETE FROM login_fail WHERE win < ?1').bind(win - 2),
  ]).catch(() => { /* 限流表写不进去不该拦住正常写入 */ });
}
