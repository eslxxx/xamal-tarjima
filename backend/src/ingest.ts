/**
 * 客户端上报 (POST /v1/ping)。
 *
 * 客户端发的是**最近若干天的绝对计数**, 服务端 upsert。于是:
 *   - 离线一周再联网一次就能补齐;
 *   - 同一份数据重复上报是幂等的, 不需要 ack、不需要"已上传"标记;
 *   - 上报失败时数据留在设备上, 不会丢。
 */

import { Env, dayOffset, json } from './shared';

const MAX_BODY = 32 * 1024;      // 一次最多 32KB, 正常一次几百字节
const MAX_DAYS = 90;             // 一次最多补 90 天
const MAX_COUNT = 100_000;       // 单日计数上限, 超过视为异常
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

function clampCount(v: unknown): number {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(n, MAX_COUNT);
}

export async function ingest(request: Request, env: Env): Promise<Response> {
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
  } catch {
    return json({ error: 'db error' }, 500);
  }
  return json({ ok: true, accepted: rows.length });
}
