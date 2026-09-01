/**
 * XAMAL 后台 Worker。
 *
 *   公开 (给 App 用, 不需要登录):
 *     POST /v1/ping     客户端上报活跃度
 *     GET  /v1/config   App 拉运营位横幅和最新版本
 *     GET  /img/<id>    横幅图片
 *   要登录 (见 auth.ts):
 *     GET  /            没登录 → 登录页; 登录了 → 仪表盘
 *     POST /login       验密码, 发会话 cookie
 *     POST /logout      清掉 cookie
 *     GET  /api/stats   统计数据
 *     GET  /api/banners 运营位列表
 *     POST /admin/*     上传/改/删横幅、发布版本、改密码
 *
 * 为什么整个后台都要登录: 上传横幅会把图片和一个可点的跳转链接推到**每一个用户**
 * 的设置页, 发布版本等于指定 APK 下载地址。而 `lg.xamal.top` 这个域名并不隐蔽 ——
 * 每张 TLS 证书都会进公开的 Certificate Transparency 日志, 扫描器照着那份名单
 * 挨个试。统计数字本身泄露危害不大, 但和写操作共用一道门更简单, 也少一类"忘了
 * 哪个接口没关"的问题。
 *
 * 设计上刻意不采集任何可定位到 App 用户的信息 —— 没有 IP、没有硬件标识、
 * 没有地理位置、没有用户输入的文本。详见 schema.sql 的注释。
 */

import {
  createBanner, deleteBanner, listBanners, publicConfig, serveImage, setRelease, updateBanner,
} from './banners';
import { changePassword, handleLogin, handleLogout, hasSession, requireWrite } from './auth';
import { DASHBOARD_HTML } from './dashboard';
import { Env, html, json } from './shared';
import { ingest } from './ingest';
import { loginPage } from './login_page';
import { stats } from './stats';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // ── 给 App 的公开接口。必须排在最前面: 后面的分支会为了判断登录态读一次 D1,
    //    没必要让每个 App 请求都付这个代价。
    if (path === '/v1/ping' && method === 'POST') return ingest(request, env);
    if (path === '/v1/config' && method === 'GET') return publicConfig(request, env);
    if (path.startsWith('/img/') && method === 'GET') {
      return serveImage(path.slice(5), env);
    }

    // ── 登录 / 退出
    if (path === '/login' && method === 'POST') return handleLogin(request, env);
    if (path === '/logout' && method === 'POST') return handleLogout();

    // ── 后台首页: 没登录就给登录页 (仍然是 200 —— 这就是这个地址该显示的东西)
    if (path === '/' && method === 'GET') {
      if (!await hasSession(request, env)) return loginPage();
      return html(DASHBOARD_HTML, 200, {
        'cache-control': 'no-store',
        'x-frame-options': 'DENY',
        'referrer-policy': 'strict-origin-when-cross-origin',
      });
    }

    // ── 后台的读接口: 401 让前端跳回登录页
    if ((path === '/api/stats' || path === '/api/banners') && method === 'GET') {
      if (!await hasSession(request, env)) return json({ error: '需要登录' }, 401);
      return path === '/api/stats' ? stats(env) : listBanners(env);
    }

    // ── 写操作: 会话 (或 x-dash-pw) + 同源
    if (path.startsWith('/admin/') && method === 'POST') {
      const denied = await requireWrite(request, env);
      if (denied) return denied;

      if (path === '/admin/banners') return createBanner(request, env);
      if (path === '/admin/release') return setRelease(request, env);
      if (path === '/admin/password') return changePassword(request, env);

      const m = /^\/admin\/banners\/([A-Za-z0-9_-]{16,32})(\/delete)?$/.exec(path);
      if (m) {
        return m[2] ? deleteBanner(m[1], env) : updateBanner(m[1], request, env);
      }
    }

    return new Response('Not found', { status: 404 });
  },
} satisfies ExportedHandler<Env>;
