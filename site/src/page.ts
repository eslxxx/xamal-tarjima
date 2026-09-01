/**
 * 下载页 HTML —— logat.xamal.top 的页面本体。
 *
 * 整页一个文件: CSS 全内联, 图片只有 /icon.png 和 /qr.png (见 icon.ts)。
 * 改版本号 / 下载地址只动上面的 SITE, 部署: 在 site/ 下 `npx wrangler deploy`。
 *
 * 配色和圆角沿用 App 的视觉规范 (app/lib/ui/theme.dart):
 * 主蓝 #2B6FF0 / 深蓝 #1B5AD6, 卡片圆角 22, 柔和大范围阴影。
 * 支持系统深色模式 —— 变量在两套 :root 里各声明一遍。
 */

const SITE = {
  appName: 'XAMAL离线翻译',
  version: '1.0.0',
  apkSize: '24.7 MB',
  // 安装包托管的网盘地址。换地址改这里然后重新 deploy。
  androidUrl: 'https://silver.yukaidi.com/s/wxBdFr',
  qq: '657400454',
  vendor: 'xamal-soft',
  team: 'XAMAL 应用开发团队',
  year: '2026',
};

export function pageHtml(): string {
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${SITE.appName} · 下载</title>
<meta name="description" content="${SITE.appName} —— 完全免费的维吾尔语、哈萨克语、汉语离线翻译。没有网络也能翻译，原文和译文不上传。">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#DCE9F8">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0B111D">
<meta property="og:type" content="website">
<meta property="og:title" content="${SITE.appName} · 完全免费的离线翻译">
<meta property="og:description" content="维吾尔语 · 哈萨克语 · 汉语。没有网络也能翻译，原文和译文不上传。">
<meta property="og:image" content="https://logat.xamal.top/icon.png">
<link rel="icon" type="image/png" href="/icon.png">
<link rel="apple-touch-icon" href="/icon.png">
<style>
:root{
  --blue:#2B6FF0; --blue-deep:#1B5AD6;
  --bg-top:#DCE9F8; --bg:#F2F7FD;
  --card:#FFFFFF; --icon-bg:#E3EDFB;
  --ink:#1A1D22; --ink2:#6B7686; --ink3:#9AA4B2;
  --line:rgba(55,74,107,.12);
  --shadow:0 8px 24px rgba(55,74,107,.10),0 1px 4px rgba(55,74,107,.06);
  --shadow-hot:0 14px 34px rgba(43,111,240,.16),0 2px 6px rgba(43,111,240,.10);
  --ok-bg:rgba(38,153,96,.13); --ok:#177C47;
}
@media (prefers-color-scheme:dark){:root{
  --bg-top:#0E1626; --bg:#0B111D;
  --card:#151D2C; --icon-bg:#1B2740;
  --ink:#E8EDF5; --ink2:#93A0B4; --ink3:#66738A;
  --line:rgba(140,165,200,.14);
  --shadow:0 8px 24px rgba(0,0,0,.35),0 1px 4px rgba(0,0,0,.30);
  --shadow-hot:0 14px 34px rgba(23,90,214,.38),0 2px 6px rgba(0,0,0,.40);
  --ok-bg:rgba(74,222,128,.13); --ok:#5BE49B;
}}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%}
body{
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;
  color:var(--ink); background:var(--bg); line-height:1.65; min-height:100vh;
}
body::before{
  content:""; position:fixed; inset:0; z-index:-1;
  background:
    radial-gradient(880px 460px at 50% -160px, rgba(43,111,240,.18), transparent 70%),
    linear-gradient(180deg, var(--bg-top), transparent 560px);
}
.wrap{max-width:1060px;margin:0 auto;padding:0 24px}
a{color:var(--blue)}
svg{display:block}

/* ── 微信提示条 ── */
#wx-tip{
  position:fixed; top:0; left:0; right:0; z-index:50;
  background:#FFF6DE; color:#7A5200; border-bottom:1px solid #EFDCA4;
  padding:10px 16px; font-size:13px; text-align:center;
}
@media (prefers-color-scheme:dark){#wx-tip{background:#33290F;color:#FFD98A;border-color:#5C4A1E}}

/* ── 页头 ── */
.top{display:flex;align-items:center;justify-content:space-between;padding:28px 0 6px}
.brand{display:flex;gap:14px;align-items:center;min-width:0}
.brand img{width:52px;height:52px;border-radius:13px;box-shadow:0 5px 16px rgba(43,111,240,.30)}
.brand .name{font-size:19px;font-weight:700;letter-spacing:.2px}
.brand .langs{font-size:12.5px;color:var(--ink3);margin-top:1px}
.by{font-size:12.5px;color:var(--ink3);letter-spacing:.5px}
@media (max-width:560px){.by{display:none}}

/* ── 主视觉 ── */
.hero{text-align:center;padding:76px 0 30px}
.kick{font-size:12px;font-weight:700;letter-spacing:3px;color:var(--blue);margin-bottom:16px}
h1{font-size:clamp(30px,5.6vw,46px);line-height:1.24;font-weight:800;letter-spacing:.3px}
/* ≤400px 手机: 30px 时第一行"维吾尔语 · 哈萨克语 · 汉语"约 354px 放不下,
   会把"汉语"孤零零甩到第二行。26px 一行放下 (360px 屏也有余量)。 */
@media (max-width:400px){h1{font-size:26px}}
h1 .grad{
  background:linear-gradient(120deg,var(--blue) 20%,var(--blue-deep));
  -webkit-background-clip:text;background-clip:text;color:transparent;
}
.sub{margin:18px auto 0;max-width:580px;font-size:16.5px;color:var(--ink2)}
.pills{margin-top:26px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap}
.pill{
  font-size:13px;font-weight:600;color:var(--blue-deep);
  background:var(--card);border:1px solid var(--line);
  padding:7px 16px;border-radius:999px;box-shadow:var(--shadow);
}
@media (prefers-color-scheme:dark){.pill{color:#8FB4F5}}

/* ── 区块标题 ── */
.sec{text-align:center;margin-top:62px}
.sec .kick{margin-bottom:12px}
.sec h2{font-size:23px;font-weight:800;letter-spacing:.3px}

/* ── 下载卡片 ── */
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:30px}
@media (max-width:860px){.cards{grid-template-columns:1fr;max-width:460px;margin:30px auto 0}}
.card{
  background:var(--card);border:1px solid var(--line);border-radius:22px;
  padding:26px 24px 24px;box-shadow:var(--shadow);
  display:flex;flex-direction:column;
}
.card.hot{border-color:rgba(43,111,240,.50);box-shadow:var(--shadow-hot)}
.plat{display:flex;align-items:center;gap:12px}
.picon{
  width:46px;height:46px;border-radius:13px;flex:none;
  background:var(--icon-bg);color:var(--blue-deep);
  display:flex;align-items:center;justify-content:center;
}
@media (prefers-color-scheme:dark){.picon{color:#8FB4F5}}
.plat h3{font-size:17px;font-weight:700}
.plat .for{font-size:12px;color:var(--ink3);margin-top:1px}
.badge{margin-left:auto;flex:none;font-size:11.5px;font-weight:700;padding:4px 10px;border-radius:999px}
.badge.live{color:var(--ok);background:var(--ok-bg)}
.badge.soon{color:var(--ink3);background:transparent;border:1px solid var(--line)}
.meta{margin-top:16px;font-size:13px;color:var(--ink2)}
.meta b{color:var(--ink);font-weight:700}
.note{margin-top:8px;font-size:12.5px;color:var(--ink3);line-height:1.6}
.btn{
  margin-top:20px;display:flex;align-items:center;justify-content:center;gap:9px;
  height:48px;border-radius:14px;font-size:15.5px;font-weight:700;
  text-decoration:none;border:none;width:100%;font-family:inherit;
}
.btn.dl{
  color:#fff;background:linear-gradient(135deg,var(--blue),var(--blue-deep));
  box-shadow:0 10px 22px rgba(43,111,240,.35);
  transition:transform .15s ease,box-shadow .15s ease;
}
.btn.dl:hover{transform:translateY(-1px);box-shadow:0 13px 26px rgba(43,111,240,.42)}
.btn.dl:active{transform:translateY(0)}
.btn.soon{
  color:var(--ink3);background:transparent;border:1px dashed var(--line);cursor:default;
}
:focus-visible{outline:2px solid var(--blue);outline-offset:2px}

/* ── 特性 ── */
.tiles{display:grid;grid-template-columns:repeat(4,1fr);gap:18px;margin-top:30px}
@media (max-width:980px){.tiles{grid-template-columns:repeat(2,1fr)}}
@media (max-width:600px){.tiles{grid-template-columns:1fr}}
.tile{
  background:var(--card);border:1px solid var(--line);border-radius:18px;
  padding:22px;box-shadow:var(--shadow);
}
.tic{
  width:42px;height:42px;border-radius:12px;margin-bottom:14px;
  background:var(--icon-bg);color:var(--blue-deep);
  display:flex;align-items:center;justify-content:center;
}
@media (prefers-color-scheme:dark){.tic{color:#8FB4F5}}
.tile h4{font-size:15px;font-weight:700;margin-bottom:6px}
.tile p{font-size:13px;color:var(--ink2)}

/* ── 二维码 (只在桌面显示 —— 手机访客自己就在手机上) ── */
.qr-sec{display:none}
@media (min-width:861px){
  .qr-sec{display:flex;justify-content:center;margin-top:60px}
}
.qr-card{
  background:var(--card);border:1px solid var(--line);border-radius:22px;
  box-shadow:var(--shadow);padding:18px 26px 18px 18px;
  display:flex;gap:20px;align-items:center;
}
.qr-card img{width:132px;height:132px;border-radius:12px;border:1px solid var(--line)}
.qr-card .t1{font-size:15.5px;font-weight:700}
.qr-card .t2{font-size:13px;color:var(--ink2);margin-top:5px;max-width:230px}

/* ── 页脚 ── */
footer{margin-top:76px;padding:30px 0 42px;text-align:center}
footer .l1{font-size:13.5px;color:var(--ink2)}
footer .l2{margin-top:7px;font-size:12px;color:var(--ink3)}
</style>
</head>
<body>

<div id="wx-tip" hidden>当前在微信内，无法直接安装应用 —— 点右上角「···」选择<b>在浏览器打开</b>，再回来下载。</div>

<div class="wrap">
  <header class="top">
    <div class="brand">
      <img src="/icon.png" alt="${SITE.appName} 图标" width="52" height="52">
      <div>
        <div class="name">${SITE.appName}</div>
        <div class="langs"><span dir="rtl">ئۇيغۇرچە</span> · Қазақша · 中文</div>
      </div>
    </div>
    <div class="by">${SITE.vendor}</div>
  </header>

  <section class="hero">
    <div class="kick">XAMAL OFFLINE TRANSLATOR</div>
    <h1>维吾尔语 · 哈萨克语 · 汉语<br><span class="grad">离线翻译，随装随用</span></h1>
    <p class="sub">整个翻译引擎装进你的手机 —— 不联网、不登录、不要钱，<br>你输入的每一个字都只留在这台设备上。</p>
    <div class="pills">
      <span class="pill">完全免费</span>
      <span class="pill">全程离线</span>
      <span class="pill">原文不上传</span>
      <span class="pill">无广告</span>
    </div>
  </section>

  <section class="sec">
    <div class="kick">DOWNLOAD</div>
    <h2>选择你的平台</h2>
    <div class="cards">

      <article class="card hot">
        <div class="plat">
          <div class="picon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="7" y="2.5" width="10" height="19" rx="2.6"/><path d="M10.5 18.3h3"/></svg>
          </div>
          <div>
            <h3>Android 版</h3>
            <div class="for">安卓手机 / 平板</div>
          </div>
          <span class="badge live">最新 v${SITE.version}</span>
        </div>
        <div class="meta"><b>${SITE.apkSize}</b> · Android 8.0 及以上 · 64 位</div>
        <div class="note">首次打开会下载约 440 MB 的翻译模型，建议连接 Wi-Fi。安装时如提示「未知来源应用」，选择允许即可。</div>
        <a class="btn dl" href="${SITE.androidUrl}" target="_blank" rel="noopener">
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.5v11"/><path d="m7.5 10.5 4.5 4.5 4.5-4.5"/><path d="M4.5 20.5h15"/></svg>
          下载安装包
        </a>
      </article>

      <article class="card">
        <div class="plat">
          <div class="picon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="5" width="16" height="10.5" rx="1.8"/><path d="M2.5 19h19"/></svg>
          </div>
          <div>
            <h3>Windows 版</h3>
            <div class="for">Windows 电脑</div>
          </div>
          <span class="badge soon">未发布</span>
        </div>
        <div class="meta">桌面版正在准备中</div>
        <div class="note">发布后会第一时间更新到本页。</div>
        <button class="btn soon" disabled>敬请期待</button>
      </article>

      <article class="card">
        <div class="plat">
          <div class="picon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2.5" width="14" height="19" rx="2.4"/><path d="M12 18.2h.01"/></svg>
          </div>
          <div>
            <h3>iOS 版</h3>
            <div class="for">iPhone / iPad</div>
          </div>
          <span class="badge soon">未发布</span>
        </div>
        <div class="meta">苹果版正在准备中</div>
        <div class="note">发布后会第一时间更新到本页。</div>
        <button class="btn soon" disabled>敬请期待</button>
      </article>

    </div>
  </section>

  <section class="sec">
    <div class="kick">WHY XAMAL</div>
    <h2>完全免费，也完全离线</h2>
    <div class="tiles">
      <div class="tile">
        <div class="tic">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.6 13.3 13.3 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.7Z"/><circle cx="7.5" cy="7.5" r="1.4"/></svg>
        </div>
        <h4>完全免费</h4>
        <p>没有广告、没有内购、没有会员，以后也不会有。</p>
      </div>
      <div class="tile">
        <div class="tic">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m2 2 20 20"/><path d="M8.6 15.5a5 5 0 0 1 6.8 0"/><path d="M5.3 12a10 10 0 0 1 4-2.4"/><path d="M14.5 9.6c1.6.5 3 1.4 4.2 2.4"/><path d="M12 19.6h.01"/></svg>
        </div>
        <h4>全程离线</h4>
        <p>飞行模式下照样翻译，一个字都不走流量。</p>
      </div>
      <div class="tile">
        <div class="tic">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-3.6 8-10V5.2L12 2 4 5.2V12c0 6.4 8 10 8 10Z"/><path d="m9 11.8 2.2 2.2 4.3-4.3"/></svg>
        </div>
        <h4>原文不出设备</h4>
        <p>你输入的原文和收到的译文只在本机处理，不上传任何服务器。</p>
      </div>
      <div class="tile">
        <div class="tic">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4.5h8.5a2 2 0 0 1 2 2V11a2 2 0 0 1-2 2H7.5l-3 3v-3H4a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2Z"/><rect x="13" y="9" width="9" height="8" rx="2.5"/></svg>
        </div>
        <h4>母语显示清晰</h4>
        <p>内置维吾尔文、哈萨克文专用字体，小字号也笔画完整。</p>
      </div>
    </div>
  </section>

  <section class="qr-sec">
    <div class="qr-card">
      <img src="/qr.png" alt="下载页二维码" width="132" height="132">
      <div>
        <div class="t1">在电脑上看到这一页？</div>
        <div class="t2">用手机扫一扫，直接打开下载页。</div>
      </div>
    </div>
  </section>

  <footer>
    <div class="l1">${SITE.vendor} 开发 · 联系 QQ ${SITE.qq}</div>
    <div class="l2">© ${SITE.year} ${SITE.team} · 本软件完全免费</div>
  </footer>
</div>

<script>
(function () {
  // 微信内置浏览器不让装 APK —— 提示用户转到系统浏览器。
  // QQ 内置浏览器只是确认一下, 不拦, 不用提示。
  if (/MicroMessenger/i.test(navigator.userAgent)) {
    var el = document.getElementById('wx-tip');
    if (el) el.hidden = false;
  }
})();
</script>

</body>
</html>`;
}
