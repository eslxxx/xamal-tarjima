/**
 * XAMAL 下载页 Worker —— logat.xamal.top。
 *
 *   GET /         下载页 (page.ts, 全部内容内联)
 *   GET /icon.png 应用图标 (icon.ts 内嵌, 页头/favicon/og:image 共用)
 *   GET /qr.png   指向本页的二维码 (桌面访客扫码用)
 *
 * 一个 Worker 顶整个站: 没有静态资产绑定、没有外部图床 —— 下载页的可用性
 * 不依赖任何第三方。图片以 base64 常量编进代码 (tools/make_site_icon.py 生成),
 * 两张加起来 30KB 左右。
 *
 * 部署: site/ 下 `npx wrangler deploy` (自定义域名 logat.xamal.top,
 * 和后台 lg.xamal.top 同一个 zone, DNS 和证书由 wrangler 自动建)。
 */

import { ICON_PNG_B64, QR_PNG_B64 } from './icon';
import { pageHtml } from './page';

function binary(b64: string, type: string, cache: string): Response {
  // atob 返回 latin1 字符串, 逐字节转回 Uint8Array 才是原始 PNG。
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return new Response(bytes, {
    headers: { 'content-type': type, 'cache-control': cache },
  });
}

export default {
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;

    if (request.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 });
    }

    // 版本号之类写在 page.ts 里, 常有更新 —— 只缓存一分钟。
    if (path === '/' || path === '/index.html') {
      return new Response(pageHtml(), {
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'public, max-age=60',
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'strict-origin-when-cross-origin',
        },
      });
    }

    // 图片基本不变; 就算换了图标, 文件名加个版本参数就能绕过。
    if (path === '/icon.png') return binary(ICON_PNG_B64, 'image/png', 'public, max-age=86400');
    if (path === '/qr.png') return binary(QR_PNG_B64, 'image/png', 'public, max-age=86400');

    return new Response('Not found', { status: 404 });
  },
} satisfies ExportedHandler;
