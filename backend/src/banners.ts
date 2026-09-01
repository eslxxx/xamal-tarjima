/**
 * 运营位横幅 + 版本发布。
 *
 * 一条横幅就是**一整张图** + 一个可选的跳转链接。刻意不做"标题/副标题/按钮文案"
 * 那一套字段: 图片自己就能表达排版, App 端只负责圆角裁剪、轮播和点击, 这样
 * 后台想换什么样式都不用改 App。
 *
 * 图片本体存 KV, 元信息存 D1。KV 的读会被 Cloudflare 边缘缓存, 适合
 * "很少改、很多人读"; D1 不适合放二进制。
 */

import { Env, json, randomId } from './shared';

const MAX_IMG = 2 * 1024 * 1024;   // 单张 2MB
const MAX_BANNERS = 20;
const CONFIG_TTL = 1800;           // App 侧和边缘缓存都按 30 分钟算

export interface BannerRow {
  id: string;
  mime: string;
  bytes: number;
  link_url: string | null;
  note: string | null;
  enabled: number;
  sort: number;
  created_at: number;
}

/** 只认这几种, 而且按**文件头**判断 —— content-type 是客户端说什么就是什么, 不能信 */
function sniffMime(buf: Uint8Array): string | null {
  const b = buf;
  if (b.length < 12) return null;
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return 'image/webp';
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) return 'image/gif';
  return null;
}

/** 只允许 https 链接, 且不允许 javascript:/data: 这类 */
function cleanLink(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (!s) return null;
  try {
    const u = new URL(s);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
    return u.toString().slice(0, 500);
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────── 公开接口

/** GET /v1/config —— App 启动后拉一次 */
export async function publicConfig(request: Request, env: Env): Promise<Response> {
  const origin = new URL(request.url).origin;

  const [rows, release] = await Promise.all([
    env.DB.prepare(
      `SELECT id, link_url FROM banners WHERE enabled = 1
        ORDER BY sort ASC, created_at DESC LIMIT ?1`).bind(MAX_BANNERS).all<BannerRow>(),
    env.DB.prepare(`SELECT v FROM config WHERE k = 'latest_release'`).first<{ v: string }>(),
  ]);

  let latest: unknown = null;
  if (release?.v) {
    try { latest = JSON.parse(release.v); } catch { /* 存坏了就当没有 */ }
  }

  return json({
    banners: (rows.results ?? []).map((r) => ({
      id: r.id,
      img: `${origin}/img/${r.id}`,
      link: r.link_url,
    })),
    latest,
    ttl: CONFIG_TTL,
  }, 200, {
    // 让边缘替我们扛住流量; App 侧也会缓存
    'cache-control': `public, max-age=${CONFIG_TTL}`,
  });
}

/** GET /img/<id> —— 横幅图片 */
export async function serveImage(id: string, env: Env): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{16,32}$/.test(id)) return new Response('Not found', { status: 404 });

  const obj = await env.IMG.getWithMetadata<{ mime: string }>(id, 'arrayBuffer');
  if (!obj.value) return new Response('Not found', { status: 404 });

  return new Response(obj.value, {
    headers: {
      'content-type': obj.metadata?.mime ?? 'image/png',
      // 图片内容永不变 (换图 = 换 id), 所以可以放心长缓存
      'cache-control': 'public, max-age=31536000, immutable',
      'x-content-type-options': 'nosniff',
    },
  });
}

// ──────────────────────────────────────────── 后台读

export async function listBanners(env: Env): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT id, mime, bytes, link_url, note, enabled, sort, created_at
       FROM banners ORDER BY sort ASC, created_at DESC`).all<BannerRow>();
  const release = await env.DB
    .prepare(`SELECT v, updated_at FROM config WHERE k = 'latest_release'`)
    .first<{ v: string; updated_at: number }>();

  let latest: unknown = null;
  if (release?.v) {
    try { latest = JSON.parse(release.v); } catch { /* 忽略 */ }
  }
  return json({ banners: rows.results ?? [], latest }, 200, { 'cache-control': 'no-store' });
}

// ──────────────────────────────────────────── 后台写

/** POST /admin/banners  multipart: file, link_url, note */
export async function createBanner(request: Request, env: Env): Promise<Response> {
  const form = await request.formData().catch(() => null);
  if (!form) return json({ error: '表单解析失败' }, 400);

  const file = form.get('file');
  if (!(file instanceof File) || file.size === 0) return json({ error: '没有选择图片' }, 400);
  if (file.size > MAX_IMG) {
    return json({ error: `图片太大了（${(file.size / 1048576).toFixed(1)}MB），上限 2MB` }, 413);
  }

  const buf = new Uint8Array(await file.arrayBuffer());
  const mime = sniffMime(buf);
  if (!mime) return json({ error: '只支持 PNG / JPEG / WebP / GIF' }, 415);

  const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM banners').first<{ n: number }>();
  if ((count?.n ?? 0) >= MAX_BANNERS) {
    return json({ error: `最多 ${MAX_BANNERS} 条，先删掉一些` }, 409);
  }

  const id = randomId();
  const note = String(form.get('note') ?? '').trim().slice(0, 200) || null;
  const link = cleanLink(form.get('link_url'));
  const now = Date.now();

  // 先写 KV 再写 D1: 万一 D1 失败, KV 里留一个没人引用的对象 (下面会清掉),
  // 反过来则会出现"列表里有这条但图片 404"的破图。
  await env.IMG.put(id, buf, { metadata: { mime } });
  try {
    await env.DB.prepare(
      `INSERT INTO banners (id, mime, bytes, link_url, note, enabled, sort, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6, ?7)`,
    ).bind(id, mime, buf.byteLength, link, note, now / 1000 | 0, now).run();
  } catch (e) {
    await env.IMG.delete(id).catch(() => {});
    return json({ error: '写数据库失败' }, 500);
  }
  return json({ ok: true, id });
}

export async function deleteBanner(id: string, env: Env): Promise<Response> {
  const row = await env.DB.prepare('SELECT id FROM banners WHERE id = ?1').bind(id).first();
  if (!row) return json({ error: '这条不存在' }, 404);
  await env.DB.prepare('DELETE FROM banners WHERE id = ?1').bind(id).run();
  await env.IMG.delete(id).catch(() => {});
  return json({ ok: true });
}

export async function updateBanner(id: string, request: Request, env: Env): Promise<Response> {
  const form = await request.formData().catch(() => null);
  if (!form) return json({ error: '表单解析失败' }, 400);

  const sets: string[] = [];
  const binds: unknown[] = [];
  if (form.has('enabled')) {
    sets.push(`enabled = ?${binds.length + 1}`);
    binds.push(form.get('enabled') === '1' ? 1 : 0);
  }
  if (form.has('sort')) {
    const n = Math.trunc(Number(form.get('sort')));
    sets.push(`sort = ?${binds.length + 1}`);
    binds.push(Number.isFinite(n) ? n : 0);
  }
  if (form.has('link_url')) {
    sets.push(`link_url = ?${binds.length + 1}`);
    binds.push(cleanLink(form.get('link_url')));
  }
  if (form.has('note')) {
    sets.push(`note = ?${binds.length + 1}`);
    binds.push(String(form.get('note') ?? '').trim().slice(0, 200) || null);
  }
  if (!sets.length) return json({ error: '没有要改的字段' }, 400);

  binds.push(id);
  const res = await env.DB.prepare(
    `UPDATE banners SET ${sets.join(', ')} WHERE id = ?${binds.length}`).bind(...binds).run();
  if (!res.meta.changes) return json({ error: '这条不存在' }, 404);
  return json({ ok: true });
}

/** POST /admin/release —— 设置"更新版本"里显示的最新版 */
export async function setRelease(request: Request, env: Env): Promise<Response> {
  const form = await request.formData().catch(() => null);
  if (!form) return json({ error: '表单解析失败' }, 400);

  const version = String(form.get('version') ?? '').trim().slice(0, 32);
  if (version && !/^\d+(\.\d+){0,3}$/.test(version)) {
    return json({ error: '版本号只能是 1.0.2 这样的数字和点' }, 400);
  }

  // 版本号留空 = 撤下更新提示
  if (!version) {
    await env.DB.prepare(`DELETE FROM config WHERE k = 'latest_release'`).run();
    return json({ ok: true, cleared: true });
  }

  const payload = {
    version,
    notes: String(form.get('notes') ?? '').trim().slice(0, 1000) || null,
    url: cleanLink(form.get('url')),
  };
  await env.DB.prepare(
    `INSERT INTO config (k, v, updated_at) VALUES ('latest_release', ?1, ?2)
     ON CONFLICT(k) DO UPDATE SET v = ?1, updated_at = ?2`,
  ).bind(JSON.stringify(payload), Date.now()).run();
  return json({ ok: true });
}
