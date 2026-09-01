/**
 * 后台登录页。
 *
 * 只有一个密码框 —— 这个后台只有作者一个人用, 用户名那一栏没有意义。
 *
 * 提交走 fetch() 而**不是**顶层表单 POST: Chromium 给顶层表单 POST 算 Origin 头
 * 时会套用页面的 referrer policy, 曾经因此发出 `Origin: null`, 被本站自己的来源
 * 检查当成跨站请求挡掉, 把管理员锁在门外。详见 auth.ts 顶部。
 */

import { html } from './shared';

export function loginPage(status = 200): Response {
  return html(PAGE, status, {
    // 登录页不该被缓存, 也不该被别的站嵌进 iframe
    'cache-control': 'no-store',
    'x-frame-options': 'DENY',
    'referrer-policy': 'strict-origin-when-cross-origin',
  });
}

const PAGE = `<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#1B5AD6">
<title>XAMAL 后台</title>
<style>
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  :root{
    --blue:#2B6FF0; --blue-dk:#1B5AD6; --ink:#141A22; --dim:#6B7684;
    --line:#E7EDF5; --danger:#D94A3D;
  }
  html,body{height:100%}
  body{
    margin:0; display:grid; place-items:center; padding:24px;
    font:15px/1.6 system-ui,-apple-system,"Segoe UI","PingFang SC","Noto Sans SC",sans-serif;
    color:var(--ink); background:#0F3EA8; position:relative; overflow:hidden;
  }
  /* 背景: 深蓝底 + 三团柔光。用 radial-gradient 而不是贴图, 省一个请求 */
  body::before{
    content:''; position:absolute; inset:-20%; z-index:0;
    background:
      radial-gradient(42% 38% at 18% 16%, rgba(120,180,255,.55), transparent 70%),
      radial-gradient(46% 42% at 84% 26%, rgba(74,132,246,.55), transparent 72%),
      radial-gradient(60% 55% at 50% 104%, rgba(12,40,110,.75), transparent 70%),
      linear-gradient(160deg,#2E74F2 0%,#1B55CE 46%,#12388F 100%);
    filter:saturate(1.05);
  }
  .card{
    position:relative; z-index:1; width:100%; max-width:372px;
    background:rgba(255,255,255,.97); border-radius:26px; padding:34px 28px 26px;
    box-shadow:0 24px 60px rgba(8,28,72,.34), 0 2px 6px rgba(8,28,72,.16);
    animation:rise .42s cubic-bezier(.2,.8,.25,1) both;
  }
  @keyframes rise{from{opacity:0;transform:translateY(14px) scale(.985)}}
  @media (prefers-reduced-motion:reduce){.card{animation:none}}

  .mark{
    width:62px; height:62px; margin:0 auto 16px; border-radius:19px;
    background:linear-gradient(150deg,#4A87F7,#1B5AD6);
    box-shadow:0 10px 22px rgba(27,90,214,.38); display:grid; place-items:center;
  }
  .mark svg{width:34px;height:34px;color:#fff}
  h1{font-size:20px; text-align:center; margin:0 0 4px; letter-spacing:-.2px}
  .sub{text-align:center; color:var(--dim); font-size:13px; margin:0 0 22px}

  label{display:block; font-size:12.5px; color:var(--dim); margin:0 0 7px 2px}
  .field{position:relative}
  input{
    width:100%; height:50px; padding:0 46px 0 15px; font-size:16px; color:var(--ink);
    background:#F5F8FC; border:1.5px solid var(--line); border-radius:14px;
    outline:none; transition:border-color .16s, background .16s, box-shadow .16s;
    font-family:inherit;
  }
  input::placeholder{color:#AEB8C6}
  input:focus{
    background:#fff; border-color:var(--blue);
    box-shadow:0 0 0 4px rgba(43,111,240,.14);
  }
  .eye{
    position:absolute; right:6px; top:6px; width:38px; height:38px;
    display:grid; place-items:center; border:0; background:none; cursor:pointer;
    color:#9AA5B4; border-radius:10px; padding:0;
  }
  .eye:hover{color:var(--blue); background:rgba(43,111,240,.08)}
  .eye svg{width:20px;height:20px}

  button.go{
    width:100%; height:50px; margin-top:18px; border:0; cursor:pointer;
    font:600 15.5px/1 inherit; color:#fff; letter-spacing:.3px; border-radius:14px;
    background:linear-gradient(135deg,#3B7BF5,var(--blue-dk));
    box-shadow:0 10px 22px rgba(27,90,214,.32); transition:transform .12s, box-shadow .2s;
  }
  button.go:hover{box-shadow:0 12px 26px rgba(27,90,214,.42)}
  button.go:active{transform:translateY(1px)}

  .err{
    display:flex; align-items:center; gap:8px; margin:0 0 16px;
    padding:10px 13px; border-radius:12px; font-size:13px;
    color:#8E2B21; background:#FDECEA; border:1px solid #F7D4D0;
  }
  .err[hidden]{display:none}
  .err svg{flex:none;color:var(--danger)}
  button.go:disabled{opacity:.7; cursor:default}
  .foot{margin:20px 0 0; text-align:center; color:#98A3B2; font-size:11.5px}
</style>
</head><body>
<main class="card">
  <div class="mark" aria-hidden="true">
    <svg viewBox="0 0 24 24"><path fill="currentColor" d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94
      2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v2h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.33 9.19
      6.79 8h-2c.65 1.61 1.57 3.13 2.75 4.5l-4.87 4.8L4.09 19l4.9-4.9 3.05 3.05.83-2.08zM18.5
      10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z"/></svg>
  </div>
  <h1>XAMAL 后台</h1>
  <p class="sub">活跃度统计 · 运营位管理</p>

  <div class="err" id="err" role="alert" hidden>
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="currentColor"
      d="M12 2 1 21h22L12 2Zm0 6 1 7h-2l1-7Zm0 9.2a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4Z"/></svg>
    <span id="errText"></span>
  </div>

  <form id="f" autocomplete="on">
    <label for="pw">访问密码</label>
    <div class="field">
      <input id="pw" name="password" type="password" placeholder="••••••••"
             autocomplete="current-password" autofocus required
             enterkeyhint="go" aria-describedby="foot">
      <button class="eye" type="button" id="toggle"
              aria-label="显示密码" aria-pressed="false">
        <svg viewBox="0 0 24 24" id="eyeIcon"><path fill="currentColor" d="M12 5C6.5 5 2.7 9.1 1.5
          12c1.2 2.9 5 7 10.5 7s9.3-4.1 10.5-7c-1.2-2.9-5-7-10.5-7Zm0 12c-2.8 0-5-2.2-5-5s2.2-5
          5-5 5 2.2 5 5-2.2 5-5 5Zm0-8a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z"/></svg>
      </button>
    </div>
    <button class="go" id="go" type="submit">进入后台</button>
  </form>

  <p class="foot" id="foot">xamal-soft · 数据只用来判断这个免费 App 还值不值得维护</p>
</main>
<script>
  var pw = document.getElementById('pw');
  var eye = document.getElementById('toggle');
  var err = document.getElementById('err');
  var errText = document.getElementById('errText');
  var go = document.getElementById('go');

  eye.addEventListener('click', function () {
    var show = pw.type === 'password';
    pw.type = show ? 'text' : 'password';
    eye.setAttribute('aria-pressed', String(show));
    eye.setAttribute('aria-label', show ? '隐藏密码' : '显示密码');
    pw.focus();
  });

  function fail(msg) {
    errText.textContent = msg;
    err.hidden = false;
    go.disabled = false;
    go.textContent = '进入后台';
    pw.select();
  }

  // fetch() 提交, 不是表单 POST —— 见文件头的说明
  document.getElementById('f').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!pw.value) { fail('请输入密码'); return; }
    err.hidden = true;
    go.disabled = true;
    go.textContent = '正在进入…';
    try {
      var fd = new FormData();
      fd.append('password', pw.value);
      var r = await fetch('/login', {
        method: 'POST', body: fd, headers: { accept: 'application/json' },
      });
      var d = await r.json().catch(function () { return {}; });
      if (r.ok && d.ok) { location.replace('/'); return; }
      fail(d.error || ('登录失败（HTTP ' + r.status + '）'));
    } catch (_) {
      fail('网络不通，稍后再试');
    }
  });
</script>
</body></html>`;
