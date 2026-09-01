/**
 * 共用的类型和小工具。
 */

export interface Env {
  DB: D1Database;
  /** 横幅图片本体。key = banner id, 值是二进制 */
  IMG: KVNamespace;
  DASH_PASSWORD: string;
  APP_TAG: string;
}

export function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}

export function html(body: string, status = 200, headers: HeadersInit = {}): Response {
  return new Response(body, {
    status,
    headers: { 'content-type': 'text/html; charset=utf-8', ...headers },
  });
}

/**
 * 今天往前/后推 n 天的 YYYY-MM-DD。
 *
 * 用 UTC+8 而不是 UTC 算日期边界: 客户端上报的是**设备本地日期**, 而用户基本都在
 * 新疆/国内 (UTC+6~+8)。如果后台按 UTC 切天, 每天 UTC 00:00 之前的那 8 个小时里,
 * 用户已经进入"新的一天"而后台还在算前一天 —— "今日活跃"会长期偏低。
 */
export const TZ_OFFSET_MS = 8 * 3600_000;

export function dayOffset(n: number): string {
  return new Date(Date.now() + TZ_OFFSET_MS + n * 86400_000).toISOString().slice(0, 10);
}

/** 常量时间比较, 避免用响应时间猜密码 */
export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

export function b64urlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = '';
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** 短随机 id, 用作横幅主键和图片 KV key。22 个 base64url 字符 = 128 bit */
export function randomId(): string {
  return b64urlEncode(crypto.getRandomValues(new Uint8Array(16)));
}

export function escapeHtml(s: unknown): string {
  return String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}
