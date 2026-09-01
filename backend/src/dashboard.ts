/**
 * 后台页面 (XAMAL 后台)。登录之后才会被送到浏览器, 见 index.ts。
 *
 * 三个标签页: 「活跃度」看数据, 「运营位」管 App 设置页顶部的横幅和版本发布,
 * 「密码」改登录密码。
 *
 * 故意不引任何 CDN 上的图表库: 少一个外部依赖、少一个可能挂掉的点, 也避免后台
 * 页面把访问信息泄给第三方。图是手写的内联 SVG。
 *
 * 配色按 dataviz 的规矩来: 两个系列色 (蓝=已有用户, 橙=当天新增) 跑过
 * validate_palette.js, 浅色 (#2B6FF0/#eb6834 on #fff) 与深色
 * (#3987e5/#d95926 on #171B22) 两套都全项通过 —— 深色步值是单独选的, 不是把
 * 浅色翻个亮度。堆叠段之间留 2px 的"表面色缝"而不是描边; 每个图都配图例、
 * 悬浮提示和一份表格视图, 保证任何一个数字都不是只能靠颜色或悬浮才能读到。
 */

export const DASHBOARD_HTML = `<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<meta name="theme-color" content="#2B6FF0">
<title>XAMAL 后台</title>
<style>
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  :root{
    color-scheme:light;
    --plane:#EFF4FB; --card:#FFFFFF;
    --ink:#141A22; --ink2:#5A6675; --muted:#8A94A3;
    --grid:#EAEFF6; --axis:#D3DBE6; --line:#E7EDF5;
    --s1:#2B6FF0; --s2:#eb6834;
    --brand:#2B6FF0; --brand-dk:#1B5AD6;
    --good:#0ca30c; --good-ink:#0a7d0a; --danger:#D03B3B;
    --chip:#F4F7FC; --ring:rgba(20,26,34,.08);
    --shadow:0 1px 2px rgba(24,42,80,.05), 0 8px 24px rgba(24,42,80,.07);
  }
  @media (prefers-color-scheme:dark){
    :root:where(:not([data-theme="light"])){
      color-scheme:dark;
      --plane:#0F1319; --card:#171B22;
      --ink:#EEF2F7; --ink2:#A6B1BF; --muted:#78838f;
      --grid:#242A34; --axis:#333B47; --line:#242A34;
      --s1:#3987e5; --s2:#d95926;
      --brand:#4A87F7; --brand-dk:#3B7BF5;
      --good:#0ca30c; --good-ink:#4cc94c; --danger:#e66767;
      --chip:#1E242D; --ring:rgba(255,255,255,.10);
      --shadow:0 1px 2px rgba(0,0,0,.3), 0 8px 24px rgba(0,0,0,.28);
    }
  }
  body{
    margin:0; background:var(--plane); color:var(--ink);
    font:15px/1.6 system-ui,-apple-system,"Segoe UI","PingFang SC","Noto Sans SC",sans-serif;
  }
  .wrap{max-width:1080px;margin:0 auto;padding:20px 20px 56px}

  /* ── 顶栏 ───────────────────────────────────────── */
  header{display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin-bottom:20px}
  .logo{
    width:38px;height:38px;border-radius:12px;display:grid;place-items:center;flex:none;
    background:linear-gradient(150deg,#4A87F7,#1B5AD6);
    box-shadow:0 6px 14px rgba(27,90,214,.32);
  }
  .logo svg{width:22px;height:22px;color:#fff}
  .title{font-size:17px;font-weight:650;letter-spacing:-.2px;line-height:1.2}
  .title small{display:block;font-weight:400;font-size:12px;color:var(--muted);letter-spacing:0}
  header .grow{flex:1}

  .tabs{display:flex;gap:4px;background:var(--chip);padding:4px;border-radius:12px}
  .tabs button{
    border:0;background:none;cursor:pointer;font:500 13.5px/1 inherit;color:var(--ink2);
    padding:9px 15px;border-radius:9px;transition:background .15s,color .15s;
  }
  .tabs button[aria-selected="true"]{background:var(--card);color:var(--ink);font-weight:600;box-shadow:0 1px 3px rgba(24,42,80,.12)}
  .ghost{
    border:1px solid var(--ring);background:var(--card);color:var(--ink2);cursor:pointer;
    font:500 13px/1 inherit;padding:9px 14px;border-radius:10px;text-decoration:none;
    display:inline-flex;align-items:center;gap:6px;transition:color .15s,border-color .15s;
  }
  .ghost:hover{color:var(--brand);border-color:var(--brand)}

  /* ── 卡片 / 区块 ─────────────────────────────────── */
  section{
    background:var(--card);border:1px solid var(--ring);border-radius:18px;
    padding:20px;margin-bottom:16px;box-shadow:var(--shadow);
  }
  h2{font-size:14.5px;margin:0 0 3px;font-weight:650;letter-spacing:-.1px}
  h2+.hint{margin:0 0 16px}
  .hint{color:var(--muted);font-size:12.5px;margin:0}
  .rowhead{display:flex;align-items:flex-start;gap:12px;margin-bottom:16px}
  .rowhead .grow{flex:1}

  /* ── 头号数字 + 数字卡 ───────────────────────────── */
  .hero{display:flex;align-items:flex-end;gap:26px;flex-wrap:wrap}
  .hero .fig{font-size:52px;font-weight:680;letter-spacing:-2px;line-height:1;margin:2px 0 6px}
  .hero .cap{font-size:13px;color:var(--ink2)}
  .hero .side{flex:1;min-width:220px;color:var(--muted);font-size:12.5px;line-height:1.7}

  .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(158px,1fr));gap:12px}
  .tile{background:var(--card);border:1px solid var(--ring);border-radius:14px;padding:14px 16px}
  .tile .k{color:var(--ink2);font-size:12.5px;line-height:1.4}
  .tile .v{font-size:26px;font-weight:650;letter-spacing:-.6px;line-height:1.25;margin-top:3px}
  .tile .n{color:var(--muted);font-size:11.5px;margin-top:1px;line-height:1.45}

  /* ── 图 ─────────────────────────────────────────── */
  .legend{display:flex;gap:16px;flex-wrap:wrap;margin:0 0 10px}
  .legend span{display:inline-flex;align-items:center;gap:7px;font-size:12.5px;color:var(--ink2)}
  .legend i{width:11px;height:11px;border-radius:3px;flex:none}
  .plot{position:relative}
  svg.chart{display:block;width:100%;height:auto;overflow:visible}
  .tip{
    position:absolute;pointer-events:none;opacity:0;transform:translate(-50%,-100%);
    background:var(--card);color:var(--ink);border:1px solid var(--ring);border-radius:11px;
    padding:9px 12px;font-size:12.5px;line-height:1.55;white-space:nowrap;z-index:5;
    box-shadow:0 6px 20px rgba(24,42,80,.16);transition:opacity .12s;
  }
  .tip b{font-weight:600}
  .tip .r{display:flex;align-items:center;gap:7px;margin-top:3px}
  .tip .r i{width:9px;height:9px;border-radius:2px;flex:none}
  .tip .r em{font-style:normal;color:var(--ink2);margin-right:2px}
  .tip .r span{margin-left:auto;font-variant-numeric:tabular-nums;font-weight:600}
  .band:focus-visible{outline:2px solid var(--brand);outline-offset:-2px}

  /* ── 表格 ───────────────────────────────────────── */
  table{width:100%;border-collapse:collapse;font-size:13.5px}
  th{text-align:left;color:var(--ink2);font-weight:600;padding:8px 10px;border-bottom:1px solid var(--line);white-space:nowrap}
  td{padding:8px 10px;border-bottom:1px solid var(--line);color:var(--ink)}
  tr:last-child td{border-bottom:0}
  td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
  .empty{color:var(--muted);padding:14px 0;font-size:13px}
  details.tv{margin-top:14px}
  details.tv summary{
    cursor:pointer;font-size:12.5px;color:var(--ink2);list-style:none;
    display:inline-flex;align-items:center;gap:6px;user-select:none;
  }
  details.tv summary::-webkit-details-marker{display:none}
  details.tv summary::before{content:'▸';font-size:11px;color:var(--muted);transition:transform .15s}
  details.tv[open] summary::before{transform:rotate(90deg)}
  details.tv summary:hover{color:var(--brand)}
  details.tv .box{margin-top:10px;max-height:320px;overflow:auto}
  .scroll{max-height:392px;overflow:auto}
  /* 滚起来表头要留在上面, 不然滚两行就不知道哪列是哪列了 */
  .scroll thead th,details.tv .box thead th{position:sticky;top:0;background:var(--card);z-index:1}
  /* 版本分布表里的比例条: 单系列, 不需要图例 */
  .prop{position:relative;min-width:120px}
  .prop i{position:absolute;left:10px;top:50%;transform:translateY(-50%);height:8px;border-radius:4px;background:var(--s1)}

  /* ── 运营位管理 ─────────────────────────────────── */
  label.f{display:block;font-size:12.5px;color:var(--ink2);margin:0 0 6px 2px}
  input[type=text],input[type=url],input[type=password],textarea{
    width:100%;font:14px/1.5 inherit;color:var(--ink);background:var(--chip);
    border:1.5px solid transparent;border-radius:11px;padding:11px 13px;outline:none;
    transition:border-color .15s,background .15s;
  }
  input[type=text]:focus,input[type=url]:focus,input[type=password]:focus,textarea:focus{background:var(--card);border-color:var(--brand)}
  textarea{resize:vertical;min-height:74px}
  .grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
  @media (max-width:640px){.grid2{grid-template-columns:1fr}}
  .btn{
    border:0;cursor:pointer;font:600 14px/1 inherit;color:#fff;padding:13px 22px;border-radius:12px;
    background:linear-gradient(135deg,#3B7BF5,var(--brand-dk));
    box-shadow:0 6px 16px rgba(27,90,214,.28);transition:transform .12s,box-shadow .2s,opacity .2s;
  }
  .btn:hover{box-shadow:0 8px 20px rgba(27,90,214,.38)}
  .btn:active{transform:translateY(1px)}
  .btn:disabled{opacity:.55;cursor:default;box-shadow:none}
  .btn.small{padding:9px 15px;font-size:13px;border-radius:10px}
  .btn.plain{background:none;color:var(--ink2);box-shadow:none;border:1px solid var(--ring)}
  .btn.plain:hover{color:var(--brand);border-color:var(--brand);box-shadow:none}
  .btn.del{background:none;color:var(--danger);box-shadow:none;border:1px solid transparent}
  .btn.del:hover{background:rgba(208,59,59,.09);box-shadow:none}
  /* 删除按钮点第一下之后的"待确认"样子 */
  .btn.del.armed{background:var(--danger);color:#fff;border-color:var(--danger)}

  /* 拖放上传区 */
  .drop{
    border:1.5px dashed var(--axis);border-radius:14px;padding:26px 18px;text-align:center;
    color:var(--ink2);cursor:pointer;transition:border-color .15s,background .15s;background:var(--chip);
  }
  .drop:hover,.drop.over{border-color:var(--brand);background:rgba(43,111,240,.06);color:var(--brand)}
  .drop svg{width:26px;height:26px;opacity:.7;margin-bottom:6px}
  .drop b{display:block;font-size:14px;font-weight:600;color:inherit}
  .drop span{font-size:12px;color:var(--muted)}
  .drop.over span,.drop:hover span{color:inherit}
  .preview{margin-top:14px;display:none}
  .preview img{width:100%;max-height:220px;object-fit:contain;border-radius:12px;background:var(--chip)}

  /* 横幅列表 */
  .blist{display:grid;gap:14px}
  .bitem{display:flex;gap:14px;align-items:flex-start;padding:14px;border:1px solid var(--ring);border-radius:14px;background:var(--chip)}
  @media (max-width:640px){.bitem{flex-direction:column}}
  .bitem .thumb{width:200px;flex:none;aspect-ratio:2.4/1;border-radius:10px;overflow:hidden;background:var(--card)}
  @media (max-width:640px){.bitem .thumb{width:100%}}
  .bitem .thumb img{width:100%;height:100%;object-fit:cover;display:block}
  .bitem .meta{flex:1;min-width:0;font-size:12.5px;color:var(--muted);line-height:1.7}
  .bitem .meta .note{color:var(--ink);font-size:14px;font-weight:550;line-height:1.4;margin-bottom:3px}
  .bitem .meta a{color:var(--brand);text-decoration:none;word-break:break-all}
  .bitem .acts{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:9px}
  .badge{font-size:11.5px;padding:3px 9px;border-radius:999px;font-weight:600}
  .badge.on{background:rgba(12,163,12,.13);color:var(--good-ink)}
  .badge.off{background:var(--card);color:var(--muted);border:1px solid var(--ring)}

  /* ── 账号 ───────────────────────────────────────── */
  .narrow{max-width:540px}
  .fld{margin-top:14px}
  /* 规则清单: 打勾靠"○ → ●"的形状变化, 不是只靠变绿 —— 色盲也读得出来 */
  ul.rules{list-style:none;margin:16px 0 0;padding:0;font-size:12.5px;color:var(--muted)}
  ul.rules li{display:flex;align-items:center;gap:8px;line-height:1.95}
  ul.rules li::before{content:'○';font-size:11px;width:12px;text-align:center;flex:none}
  ul.rules li.ok{color:var(--good-ink)}
  ul.rules li.ok::before{content:'●'}
  label.show{
    display:inline-flex;align-items:center;gap:8px;margin-top:14px;
    font-size:12.5px;color:var(--ink2);cursor:pointer;user-select:none;
  }
  label.show input{width:16px;height:16px;accent-color:var(--brand);margin:0}
  pre.cmd{
    margin:12px 0 0;padding:12px 14px;background:var(--chip);border:1px solid var(--ring);
    border-radius:11px;color:var(--ink);white-space:pre-wrap;word-break:break-all;
    font:12.5px/1.7 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  }
  code{
    font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
    color:var(--ink2);background:var(--chip);padding:1px 6px;border-radius:6px;
  }
  .warn{
    display:flex;gap:9px;margin-top:14px;padding:11px 13px;border-radius:11px;
    background:var(--chip);border:1px solid var(--ring);font-size:12.5px;
    color:var(--ink2);line-height:1.6;
  }
  .warn svg{width:16px;height:16px;flex:none;margin-top:2px;color:var(--danger)}
  .toast{
    position:fixed;left:50%;bottom:28px;transform:translate(-50%,12px);opacity:0;
    background:#1E2530;color:#fff;padding:11px 20px;border-radius:999px;font-size:13.5px;
    box-shadow:0 10px 30px rgba(0,0,0,.28);transition:opacity .2s,transform .2s;z-index:20;
    pointer-events:none;max-width:90vw;text-align:center;
  }
  .toast.show{opacity:1;transform:translate(-50%,0)}
  [hidden]{display:none !important}
</style>
</head><body>
<div class="wrap">
<header>
  <div class="logo" aria-hidden="true">
    <svg viewBox="0 0 24 24"><path fill="currentColor" d="M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94
      2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v2h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.33 9.19
      6.79 8h-2c.65 1.61 1.57 3.13 2.75 4.5l-4.87 4.8L4.09 19l4.9-4.9 3.05 3.05.83-2.08zM18.5
      10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z"/></svg>
  </div>
  <div class="title">XAMAL 后台<small id="ts">加载中…</small></div>
  <div class="grow"></div>
  <div class="tabs" role="tablist">
    <button role="tab" id="tab-stats" aria-selected="true" aria-controls="panel-stats">活跃度</button>
    <button role="tab" id="tab-ops" aria-selected="false" aria-controls="panel-ops">运营位</button>
    <button role="tab" id="tab-acct" aria-selected="false" aria-controls="panel-acct">密码</button>
  </div>
  <button class="ghost" id="logout" type="button">退出登录</button>
</header>

<!-- ═══════════ 活跃度 ═══════════ -->
<div id="panel-stats" role="tabpanel" aria-labelledby="tab-stats">
  <section>
    <div class="hero">
      <div>
        <div class="hint">最近 30 天用过的安装</div>
        <div class="fig" id="heroFig">—</div>
        <div class="cap" id="heroCap">&nbsp;</div>
      </div>
      <p class="side">这个数字是判断「还值不值得继续维护」的主要依据。<br>
        统计不含 IP、位置、机型和任何原文译文；用户可在 App 里关掉。</p>
    </div>
  </section>

  <div class="tiles" id="tiles"></div>

  <section>
    <div class="rowhead"><div class="grow">
      <h2>每日活跃安装数</h2>
      <p class="hint">最近 30 天。橙色是当天第一次出现的新安装，蓝色是之前就装过的。</p>
    </div></div>
    <div class="legend">
      <span><i style="background:var(--s1)"></i>已有安装</span>
      <span><i style="background:var(--s2)"></i>当天新增</span>
    </div>
    <div class="plot"><div class="tip" id="tip1"></div><div id="chart1"></div></div>
    <details class="tv"><summary>表格</summary><div class="box" id="table1"></div></details>
  </section>

  <section>
    <div class="rowhead"><div class="grow">
      <h2>每日启动与翻译次数</h2>
      <p class="hint">最近 30 天的总次数，不是人数。上下分成两格、各自一根刻度 ——
        翻译次数比启动次数大一个量级，挤在同一根刻度上启动那条会被压平。</p>
    </div></div>
    <div class="plot"><div class="tip" id="tip2"></div><div id="chart2"></div></div>
    <details class="tv"><summary>表格</summary><div class="box" id="table2"></div></details>
  </section>

  <section>
    <h2>留存</h2>
    <p class="hint">按首次使用的日期分组，看有多少人后来还回来过。</p>
    <div class="scroll" id="cohorts"></div>
  </section>

  <section>
    <h2>版本分布</h2>
    <p class="hint">最近 30 天活跃的安装。</p>
    <div id="versions"></div>
  </section>
</div>
<!-- ═══════════ 运营位 ═══════════ -->
<div id="panel-ops" role="tabpanel" aria-labelledby="tab-ops" hidden>
  <section>
    <h2>上传横幅</h2>
    <p class="hint">显示在 App 设置页最上面。整张图直接铺满，所以文字排版请在图里做好。
      建议 <b>1080 × 450</b>（2.4 : 1），PNG / JPEG / WebP / GIF，单张不超过 2MB。</p>

    <div class="drop" id="drop" tabindex="0" role="button" aria-label="选择或拖入图片">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M19 13v5H5v-5H3v5a2 2 0
        0 0 2 2h14a2 2 0 0 0 2-2v-5h-2Zm-6 .67V4h-2v9.67L7.41 10 6 11.41l6 6 6-6L16.59 10 13 13.67Z"/></svg>
      <b>点击选择图片，或拖到这里</b>
      <span>上传后立刻对所有用户生效</span>
    </div>
    <input type="file" id="file" accept="image/png,image/jpeg,image/webp,image/gif" hidden>
    <div class="preview" id="preview"><img id="previewImg" alt="待上传的横幅预览"></div>

    <div class="grid2" style="margin-top:16px">
      <div>
        <label class="f" for="link">点击后打开的链接（可留空）</label>
        <input type="url" id="link" placeholder="https://…" inputmode="url">
      </div>
      <div>
        <label class="f" for="note">备注（只有后台能看到）</label>
        <input type="text" id="note" placeholder="例如：8 月更新公告">
      </div>
    </div>
    <div style="margin-top:16px"><button class="btn" id="up" disabled>上传</button></div>
  </section>

  <section>
    <div class="rowhead">
      <div class="grow"><h2>已有横幅</h2>
        <p class="hint">数字小的排在前面。停用会立刻从 App 里消失，但图还留着。</p></div>
      <button class="ghost" id="reload">刷新</button>
    </div>
    <div class="blist" id="blist"></div>
  </section>

  <section>
    <h2>版本发布</h2>
    <p class="hint">填了以后，App 设置页的「更新版本」会显示有新版可用。版本号留空并保存 = 撤下提示。</p>
    <div class="grid2">
      <div>
        <label class="f" for="rv">最新版本号</label>
        <input type="text" id="rv" placeholder="1.0.1" inputmode="decimal">
      </div>
      <div>
        <label class="f" for="ru">下载链接</label>
        <input type="url" id="ru" placeholder="https://…" inputmode="url">
      </div>
    </div>
    <div style="margin-top:14px">
      <label class="f" for="rn">更新说明</label>
      <textarea id="rn" placeholder="这一版改了什么，一行一条"></textarea>
    </div>
    <div style="margin-top:16px"><button class="btn" id="saveRel">保存</button></div>
  </section>
</div>
<!-- ═══════════ 密码 ═══════════ -->
<div id="panel-acct" role="tabpanel" aria-labelledby="tab-acct" hidden>
  <section class="narrow">
    <h2>修改登录密码</h2>
    <p class="hint">这个密码既是进后台的门，也是上传横幅、发布版本的凭据。
      改完之后<b>别的浏览器上的登录都会失效</b>，要用新密码重新登录一次。</p>

    <form id="pwForm">
      <div class="fld">
        <label class="f" for="pw1">新密码</label>
        <input type="password" id="pw1" autocomplete="new-password"
               placeholder="••••••••••" required>
      </div>
      <div class="fld">
        <label class="f" for="pw2">再输一次新密码</label>
        <input type="password" id="pw2" autocomplete="new-password"
               placeholder="••••••••••" required>
      </div>

      <ul class="rules" aria-live="polite">
        <li id="r1">至少 10 位</li>
        <li id="r2">混用两种以上字符（大小写字母、数字、符号）</li>
        <li id="r3">两次输入一致</li>
      </ul>

      <label class="show"><input type="checkbox" id="pwShow">显示密码</label>
      <div style="margin-top:20px">
        <button class="btn" type="submit" id="pwGo" disabled>修改密码</button>
      </div>
    </form>
  </section>

  <section class="narrow">
    <h2>忘了密码怎么办</h2>
    <p class="hint">改过的密码存在数据库里。删掉那一行，就回到部署时用
      <code>wrangler secret put DASH_PASSWORD</code> 设的那个初始密码：</p>
    <pre class="cmd">wrangler d1 execute tilmach-stats --remote --command "DELETE FROM config WHERE k='dash_password'"</pre>
    <div class="warn">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor"
        d="M12 2 1 21h22L12 2Zm0 6 1 7h-2l1-7Zm0 9.2a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4Z"/></svg>
      <span>同理，<b>别随手换掉 DASH_PASSWORD 这个 secret</b> ——
        它同时是数据库里那串哈希的密钥，换了会让在这里改过的密码一起作废，
        只能用上面这条命令回到新的初始密码。数据库里存的不是明文也不是普通哈希，
        单独拖走一份 D1 备份反推不出密码。</span>
    </div>
  </section>
</div>
</div>
<div class="toast" id="toast" role="status" aria-live="polite"></div>
<script>
// ── 小工具 ──────────────────────────────────────────
function $(id){ return document.getElementById(id); }
function esc(s){ return String(s==null?'':s).replace(/[&<>"]/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
function num(n){ return (Number(n)||0).toLocaleString('zh-CN'); }
function fmt(n){ n=Number(n)||0;
  if(n>=100000) return (n/10000).toFixed(0)+'万';
  if(n>=10000)  return (n/10000).toFixed(1)+'万';
  return num(n); }
function pct(a,b){ return b>0 ? Math.round(a*100/b)+'%' : '—'; }
function toast(msg){ var t=$('toast'); t.textContent=msg; t.classList.add('show');
  clearTimeout(toast._t); toast._t=setTimeout(function(){ t.classList.remove('show'); },2400); }
function md(d){ return String(d||'').slice(5); }

/** 轴上限取一个整齐的偶数, 这样 0 / max÷2 / max 三条刻度都是整数 */
function niceMax(v){
  v=Math.max(1,Math.ceil(v));
  if(v<=4) return 4; if(v<=8) return 8; if(v<=10) return 10;
  var mag=Math.pow(10,Math.floor(Math.log10(v)));
  var steps=[1,1.2,1.5,2,2.5,3,4,5,6,8,10];
  for(var i=0;i<steps.length;i++){ var c=Math.round(steps[i]*mag); if(c>=v && c%2===0) return c; }
  return 10*mag;
}
/** 顶部 4px 圆角、底部贴基线切平的柱子 */
function barPath(x,y,w,h,r){
  if(h<=0.3) return '';
  r=Math.min(r,w/2,h);
  return 'M'+x+' '+(y+h)+'V'+(y+r)+'a'+r+' '+r+' 0 0 1 '+r+' '+(-r)+
         'h'+(w-2*r)+'a'+r+' '+r+' 0 0 1 '+r+' '+r+'V'+(y+h)+'Z';
}
/**
 * 表格 —— 每张图的「表格视图」孪生体, 也是留存/版本这两块的正主。
 * cols 是表头文字数组; 单元格可以是字符串, {n:数字文本}(右对齐等宽) 或 {h:内联 HTML}。
 */
function table(el,cols,rows,emptyText){
  if(!rows.length){ el.innerHTML='<div class="empty">'+esc(emptyText)+'</div>'; return; }
  var numCol=cols.map(function(_,i){
    return rows.some(function(r){ return r[i] && r[i].n!=null; }); });
  var head=cols.map(function(c,i){
    return '<th'+(numCol[i]?' class="num"':'')+'>'+esc(c)+'</th>'; }).join('');
  var body=rows.map(function(r){ return '<tr>'+cols.map(function(_,i){
    var v=r[i];
    if(v && v.h!=null) return '<td>'+v.h+'</td>';
    if(v && v.n!=null) return '<td class="num">'+esc(v.n)+'</td>';
    return '<td>'+esc(v)+'</td>';
  }).join('')+'</tr>'; }).join('');
  el.innerHTML='<table><thead><tr>'+head+'</tr></thead><tbody>'+body+'</tbody></table>';
}

// ── 标签页 ──────────────────────────────────────────
var TABS=['stats','ops','acct'];
var opsLoaded=false;
function selectTab(which){
  TABS.forEach(function(t){
    var on=(t===which);
    $('tab-'+t).setAttribute('aria-selected',String(on));
    $('panel-'+t).hidden=!on;
  });
  if(which==='ops' && !opsLoaded) loadOps();
}
TABS.forEach(function(t){ $('tab-'+t).onclick=function(){ selectTab(t); }; });

// ── 活跃度 ──────────────────────────────────────────
function tiles(t,s){
  // 六个 —— 正好铺满一行, 不留一个孤零零的尾块
  var items=[
    ['累计安装', fmt(t.installs), (t.new_today?'今天新增 '+num(t.new_today)+' 个':'清数据或重装会算作新安装')],
    ['累计启动次数', fmt(t.launches), '今天 '+num(t.launches_today)+' 次'],
    ['累计翻译次数', fmt(t.translations), '今天 '+num(t.translations_today)+' 次'],
    ['今日活跃', fmt(t.dau), t.installs?pct(t.dau,t.installs)+' 的安装':''],
    ['7 日活跃', fmt(t.wau), t.installs?pct(t.wau,t.installs)+' 的安装':''],
    ['人均每天翻译', (s.avg_translations==null?'—':s.avg_translations+' 次'),
      '最近 7 天，启动 '+(s.avg_launches==null?'—':s.avg_launches)+' 次'],
  ];
  $('tiles').innerHTML=items.map(function(it){
    return '<div class="tile"><div class="k">'+esc(it[0])+'</div><div class="v">'+esc(it[1])+
           '</div><div class="n">'+esc(it[2])+'</div></div>'; }).join('');
}

/** 堆叠柱: 下段=已有安装, 上段=当天新增。两段之间留 2px 表面色缝, 不描边。 */
function chart1(rows){
  var box=$('chart1'), tip=$('tip1');
  if(!rows.length){ box.innerHTML='<div class="empty">还没有数据</div>'; return; }
  var W=920, PH=206, padL=46, padT=10, padB=30, H=PH+padB;
  var max=1; rows.forEach(function(r){ max=Math.max(max,r.users); }); max=niceMax(max);
  var band=(W-padL)/rows.length, bw=Math.min(24,band*0.6);
  var y=function(v){ return padT+(PH-padT)*(1-v/max); };
  var peak=0; rows.forEach(function(r,i){ if(r.users>rows[peak].users) peak=i; });

  var g='';
  [0,1,2].forEach(function(k){
    var v=max*k/2, yy=y(v);
    g+='<line x1="'+padL+'" y1="'+yy+'" x2="'+W+'" y2="'+yy+'" stroke-width="1" style="stroke:var(--'+(k?'grid':'axis')+')"/>'+
       '<text x="'+(padL-9)+'" y="'+(yy+3.6)+'" text-anchor="end" font-size="10.5" '+
       'style="fill:var(--muted);font-variant-numeric:tabular-nums">'+num(v)+'</text>';
  });
  rows.forEach(function(r,i){
    var x=padL+band*i+(band-bw)/2, top=y(r.users), base=y(0);
    var nw=Math.min(r.newcomers||0,r.users), old=r.users-nw;
    if(nw>0 && old>0){
      // 上段(新增)至少留 2.5px 看得见; 两段之间是 2px 表面色的缝, 不描边
      var th=Math.max(y(old)-top,2.5);
      g+='<path d="'+barPath(x,top,bw,th,4)+'" style="fill:var(--s2)"/>';
      g+='<path d="'+barPath(x,top+th+2,bw,base-top-th-2,0)+'" style="fill:var(--s1)"/>';
    } else {
      g+='<path d="'+barPath(x,top,bw,base-top,4)+'" style="fill:var('+(nw>0?'--s2':'--s1')+')"/>';
    }
    if(i===0||i===rows.length-1||i===(rows.length>>1)){
      g+='<text x="'+(x+bw/2)+'" y="'+(H-9)+'" text-anchor="middle" font-size="10.5" '+
         'style="fill:var(--muted)">'+esc(md(r.day))+'</text>';
    }
  });
  // 只给峰值一个直接标注 —— 每根柱子都标数字等于没标
  (function(){ var r=rows[peak], x=padL+band*peak+band/2;
    g+='<text x="'+x+'" y="'+(y(r.users)-8)+'" text-anchor="middle" font-size="11" '+
       'style="fill:var(--ink2);font-weight:600">'+num(r.users)+'</text>'; })();
  // 悬浮/聚焦热区: 整个 band 宽、整个绘图区高, 比柱子本身宽得多
  rows.forEach(function(r,i){
    g+='<rect class="band" x="'+(padL+band*i)+'" y="'+padT+'" width="'+band+'" height="'+(PH-padT)+
       '" fill="transparent" tabindex="0" data-i="'+i+'"><title>'+esc(r.day)+'：活跃 '+r.users+
       ' 个，新增 '+(r.newcomers||0)+'</title></rect>';
  });
  box.innerHTML='<svg class="chart" viewBox="0 0 '+W+' '+H+'" role="img" '+
    'aria-label="最近 30 天每日活跃安装数堆叠柱状图">'+g+'</svg>';

  hookTip(box,tip,{
    n:rows.length, W:W, H:H,
    idxAt:function(vx){ return Math.floor((vx-padL)/band); },
    x:function(i){ return padL+band*i+band/2; },
    y:function(i){ return y(rows[i].users); },
    html:function(i){
      var r=rows[i], nw=Math.min(r.newcomers||0,r.users);
      return '<b>'+esc(r.day)+'</b>'+
        row2('var(--s1)','已有安装',num(r.users-nw))+
        row2('var(--s2)','当天新增',num(nw))+
        '<div class="r"><em>合计</em><span>'+num(r.users)+'</span></div>';
    },
  });
  table($('table1'),['日期','活跃安装','当天新增'],rows.map(function(r){
    return [md(r.day),{n:num(r.users)},{n:num(r.newcomers||0)}]; }),'还没有数据');
}
function row2(color,label,val){
  return '<div class="r"><i style="background:'+color+'"></i><em>'+label+'</em><span>'+val+'</span></div>';
}

/**
 * 悬浮层。热区按 viewBox 坐标算, 所以缩放不影响命中;
 * 键盘 Tab 到 .band 走同一套显示逻辑 —— tooltip 只是补充, 值在下面的表格里也有。
 */
function hookTip(box,tip,o){
  var svg=box.querySelector('svg'); if(!svg) return;
  var cross=svg.querySelector('.cross'), last=-1;
  function show(i){
    if(i<0||i>=o.n) return hide();
    if(i!==last){ tip.innerHTML=o.html(i); last=i; if(o.move) o.move(i); }
    tip.style.left=(o.x(i)/o.W*100)+'%';
    tip.style.top='calc('+(o.y(i)/o.H*100)+'% - 12px)';
    tip.style.opacity='1';
    if(cross){ cross.setAttribute('x1',o.x(i)); cross.setAttribute('x2',o.x(i)); cross.style.opacity='1'; }
  }
  function hide(){ tip.style.opacity='0'; last=-1; if(cross) cross.style.opacity='0'; if(o.move) o.move(-1); }
  function at(e){
    var r=box.getBoundingClientRect(); if(!r.width) return -1;
    return o.idxAt((e.clientX-r.left)/r.width*o.W);
  }
  box.addEventListener('pointermove',function(e){ show(at(e)); });
  box.addEventListener('pointerleave',hide);
  var bands=svg.querySelectorAll('.band');
  for(var k=0;k<bands.length;k++){
    bands[k].addEventListener('focus',function(){ show(+this.getAttribute('data-i')); });
    bands[k].addEventListener('blur',hide);
  }
}

/**
 * 启动次数 / 翻译次数 —— 拆成上下两格小图 (small multiples), 各自一根 y 轴。
 * 翻译次数比启动次数大一个量级, 挤在同一刻度上启动那条会被压成一条直线;
 * 而两条 y 轴画在一张图里 (双轴) 是明令禁止的 —— 所以分格。
 * 两格共用一条竖准线和一个 tooltip。
 */
function chart2(rows){
  var box=$('chart2'), tip=$('tip2');
  if(!rows.length){ box.innerHTML='<div class="empty">还没有数据</div>'; return; }
  var W=920, padL=52, padR=10, PH=112, GAP=34, T1=26, T2=T1+PH+GAP, H=T2+PH+28;
  var iw=W-padL-padR, step=rows.length>1?iw/(rows.length-1):0;
  var x=function(i){ return padL+(rows.length>1?step*i:iw/2); };

  var series=[
    { key:'launches',     name:'启动次数', color:'--s1', top:T1, max:1 },
    { key:'translations', name:'翻译次数', color:'--s2', top:T2, max:1 },
  ];
  series.forEach(function(s){
    rows.forEach(function(r){ s.max=Math.max(s.max,r[s.key]); });
    s.max=niceMax(s.max);
    s.y=function(v){ return s.top+PH*(1-v/s.max); };
  });

  var g='';
  series.forEach(function(s){
    // 小图标题: 文字用 ink2, 身份靠旁边那个彩色圆点 —— 文字不穿数据色
    g+='<circle cx="'+(padL+4)+'" cy="'+(s.top-13)+'" r="4.5" style="fill:var('+s.color+')"/>'+
       '<text x="'+(padL+15)+'" y="'+(s.top-9)+'" font-size="12" style="fill:var(--ink2);font-weight:600">'+
       s.name+'</text>';
    [0,1,2].forEach(function(k){
      var v=s.max*k/2, yy=s.y(v);
      g+='<line x1="'+padL+'" y1="'+yy+'" x2="'+(W-padR)+'" y2="'+yy+'" stroke-width="1" '+
         'style="stroke:var(--'+(k?'grid':'axis')+')"/>'+
         '<text x="'+(padL-9)+'" y="'+(yy+3.6)+'" text-anchor="end" font-size="10.5" '+
         'style="fill:var(--muted);font-variant-numeric:tabular-nums">'+num(v)+'</text>';
    });
  });
  rows.forEach(function(r,i){
    if(i===0||i===rows.length-1||i===(rows.length>>1)){
      g+='<text x="'+x(i)+'" y="'+(H-9)+'" text-anchor="middle" font-size="10.5" '+
         'style="fill:var(--muted)">'+esc(md(r.day))+'</text>';
    }
  });
  g+='<line class="cross" x1="0" y1="'+T1+'" x2="0" y2="'+(T2+PH)+'" stroke-width="1" '+
     'style="stroke:var(--axis);opacity:0;transition:opacity .1s"/>';
  series.forEach(function(s){
    var d=rows.map(function(r,i){ return (i?'L':'M')+x(i)+' '+s.y(r[s.key]); }).join('');
    g+='<path d="'+d+'" fill="none" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" '+
       'style="stroke:var('+s.color+')"/>';
    // 末端点 + 末端直接标注 (只标最后一天, 不给每个点都写数字)
    var li=rows.length-1;
    g+='<circle cx="'+x(li)+'" cy="'+s.y(rows[li][s.key])+'" r="4.5" stroke-width="2" '+
       'style="fill:var('+s.color+');stroke:var(--card)"/>';
    g+='<text x="'+(x(li)-9)+'" y="'+(s.y(rows[li][s.key])-9)+'" text-anchor="end" font-size="11" '+
       'style="fill:var(--ink2);font-weight:600">'+num(rows[li][s.key])+'</text>';
    g+='<circle class="hd hd-'+s.key+'" cx="0" cy="0" r="4.5" stroke-width="2" opacity="0" '+
       'style="fill:var('+s.color+');stroke:var(--card)"/>';
  });
  rows.forEach(function(r,i){
    g+='<rect class="band" x="'+(x(i)-step/2)+'" y="'+T1+'" width="'+Math.max(step,8)+'" height="'+(T2+PH-T1)+
       '" fill="transparent" tabindex="0" data-i="'+i+'"><title>'+esc(r.day)+'：启动 '+r.launches+
       ' 次，翻译 '+r.translations+' 次</title></rect>';
  });
  box.innerHTML='<svg class="chart" viewBox="0 0 '+W+' '+H+'" role="img" '+
    'aria-label="最近 30 天每日启动次数与翻译次数, 上下两格分别是各自的刻度">'+g+'</svg>';
  var svg=box.querySelector('svg');
  series.forEach(function(s){ s.dot=svg.querySelector('.hd-'+s.key); });

  hookTip(box,tip,{
    n:rows.length, W:W, H:H,
    idxAt:function(vx){ return step?Math.round((vx-padL)/step):0; },
    x:function(i){ return x(i); },
    y:function(i){ return series[0].y(rows[i].launches); },
    move:function(i){
      series.forEach(function(s){
        if(!s.dot) return;
        if(i<0){ s.dot.setAttribute('opacity','0'); return; }
        s.dot.setAttribute('cx',x(i)); s.dot.setAttribute('cy',s.y(rows[i][s.key]));
        s.dot.setAttribute('opacity','1');
      });
    },
    html:function(i){
      var r=rows[i];
      return '<b>'+esc(r.day)+'</b>'+
        row2('var(--s1)','启动',num(r.launches)+' 次')+
        row2('var(--s2)','翻译',num(r.translations)+' 次');
    },
  });
  table($('table2'),['日期','启动次数','翻译次数','人均启动'],rows.map(function(r){
    return [md(r.day),{n:num(r.launches)},{n:num(r.translations)},
            {n:r.users?(r.launches/r.users).toFixed(1):'—'}]; }),'还没有数据');
}

/**
 * 留存。窗口还没过完的格子写「—」而不是 0%:
 * 昨天才装上的人不可能"7 天后还在", 写 0% 会把新用户误读成流失。
 */
function cohorts(rows,today){
  var t=Date.parse(today+'T00:00:00Z');
  var ready=function(day,n){ return Date.parse(day+'T00:00:00Z')+n*86400000<=t; };
  var cell=function(r,n,v){
    if(!ready(r.first_day,n)) return {n:'—'};
    return {n:r.cohort?num(v)+' · '+pct(v,r.cohort):'—'};
  };
  table($('cohorts'),['首次使用','新增','次日回来','7 天后还在','30 天后还在'],
    rows.map(function(r){
      return [md(r.first_day),{n:num(r.cohort)},cell(r,1,r.d1),cell(r,7,r.d7),cell(r,30,r.d30)];
    }),'还没有数据');
}

/** 版本分布: 单系列, 所以不要图例; 用行内比例条代替一张饼 */
function versions(rows){
  var tot=0; rows.forEach(function(r){ tot+=r.users; });
  table($('versions'),['版本','活跃安装','占比',''],rows.map(function(r){
    var w=tot?Math.max(2,Math.round(r.users/tot*100)):0;
    return [r.app_version,{n:num(r.users)},{n:pct(r.users,tot)},
      {h:'<div class="prop"><i style="width:'+w+'%"></i></div>'}];
  }),'还没有数据');
}

async function loadStats(){
  var r=await fetch('/api/stats',{headers:{accept:'application/json'}});
  if(r.status===401){ location.href='/'; return; }
  if(!r.ok) throw new Error('HTTP '+r.status);
  var d=await r.json();
  var t=d.totals||{}, s=d.stickiness||{};

  $('heroFig').textContent=fmt(t.mau||0);
  $('heroCap').textContent=(t.installs?'占累计安装 '+pct(t.mau||0,t.installs):'还没有数据')+
    ' · 今天活跃 '+num(t.dau||0)+' 个';
  tiles(t,s);
  // 后端按 UTC+8 切天, 这里也照着算, 免得留存表把窗口算错一天。
  // generated_at 是 ISO 字符串; 万一没有就用本机时间 —— 不能直接 Date.parse(数字)。
  var gen=d.generated_at?Date.parse(d.generated_at):Date.now();
  if(!Number.isFinite(gen)) gen=Date.now();
  var today=new Date(gen+8*3600000).toISOString().slice(0,10);
  chart1(d.trend||[]);
  chart2(d.trend||[]);
  cohorts(d.cohorts||[],today);
  versions(d.versions||[]);
  $('ts').textContent='数据更新于 '+new Date(gen).toLocaleString('zh-CN',{hour12:false});
}

// ── 运营位 ──────────────────────────────────────────
var picked=null, blist=[];

/**
 * 所有写操作都走这里。身份靠登录时拿到的 cookie, 浏览器自动带上, 页面这边什么都
 * 不用管。会话过期就跳回登录页。
 *
 * 上一版用 prompt() 问口令再放到 x-dash-pw 头里, 那是个坑: 不少手机浏览器内核
 * 直接吞掉 prompt() 并立刻返回 null, 于是每次点「删除」「停用」都走进"用户取消"
 * 分支 —— 表面上就是按钮全都不起作用。密码只在登录页的 <input> 里收。
 */
async function post(path,form){
  var r=await fetch(path,{method:'POST',body:form,headers:{accept:'application/json'}});
  var d=await r.json().catch(function(){ return {}; });
  if(r.status===401){ location.replace('/'); throw new Error('登录已过期，正在回到登录页'); }
  if(!r.ok||d.error) throw new Error(d.error||('HTTP '+r.status));
  return d;
}
function kb(n){ n=Number(n)||0;
  return n>=1048576 ? (n/1048576).toFixed(1)+' MB' : Math.max(1,Math.round(n/1024))+' KB'; }

function pick(f){
  if(!f) return;
  if(!/^image\\/(png|jpeg|webp|gif)$/.test(f.type)){ toast('只支持 PNG / JPEG / WebP / GIF'); return; }
  if(f.size>2*1024*1024){ toast('图片 '+kb(f.size)+'，超过 2MB 了'); return; }
  picked=f;
  $('previewImg').src=URL.createObjectURL(f);
  $('preview').style.display='block';
  $('drop').querySelector('b').textContent=f.name+'（'+kb(f.size)+'）';
  $('up').disabled=false;
}
$('drop').onclick=function(){ $('file').click(); };
$('drop').onkeydown=function(e){ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); $('file').click(); } };
$('file').onchange=function(){ pick(this.files&&this.files[0]); };
['dragenter','dragover'].forEach(function(ev){
  $('drop').addEventListener(ev,function(e){ e.preventDefault(); this.classList.add('over'); }); });
['dragleave','drop'].forEach(function(ev){
  $('drop').addEventListener(ev,function(e){ e.preventDefault(); this.classList.remove('over'); }); });
$('drop').addEventListener('drop',function(e){
  pick(e.dataTransfer&&e.dataTransfer.files&&e.dataTransfer.files[0]); });

$('up').onclick=async function(){
  if(!picked) return;
  var b=this; b.disabled=true; b.textContent='上传中…';
  try{
    var fd=new FormData();
    fd.append('file',picked);
    fd.append('link_url',$('link').value.trim());
    fd.append('note',$('note').value.trim());
    await post('/admin/banners',fd);
    picked=null; $('file').value=''; $('link').value=''; $('note').value='';
    $('preview').style.display='none';
    $('drop').querySelector('b').textContent='点击选择图片，或拖到这里';
    toast('上传成功，已经对所有用户生效');
    await loadOps();
  }catch(err){ toast(String(err.message||err)); }
  b.textContent='上传'; b.disabled=!picked;
};

function renderBanners(){
  var el=$('blist');
  if(!blist.length){ el.innerHTML='<div class="empty">还没有横幅。App 里会显示内置的默认图。</div>'; return; }
  el.innerHTML=blist.map(function(b,i){
    return '<div class="bitem">'+
      '<div class="thumb"><img src="/img/'+esc(b.id)+'" alt="横幅预览" loading="lazy"></div>'+
      '<div class="meta">'+
        '<div class="note">'+esc(b.note||'（没写备注）')+'</div>'+
        (b.link_url?'<a href="'+esc(b.link_url)+'" target="_blank" rel="noreferrer noopener">'+esc(b.link_url)+'</a><br>':'点击不跳转<br>')+
        esc(b.mime.replace('image/',''))+' · '+kb(b.bytes)+' · '+
        new Date(b.created_at).toLocaleString('zh-CN',{hour12:false})+
        '<div class="acts">'+
          '<span class="badge '+(b.enabled?'on':'off')+'">'+(b.enabled?'正在显示':'已停用')+'</span>'+
          (i>0?'<button class="btn small plain" data-act="up" data-i="'+i+'">上移</button>':'')+
          '<button class="btn small plain" data-act="toggle" data-i="'+i+'">'+(b.enabled?'停用':'启用')+'</button>'+
          '<button class="btn small del" data-act="del" data-i="'+i+'">删除</button>'+
        '</div>'+
      '</div></div>';
  }).join('');
  var btns=el.querySelectorAll('button[data-act]');
  for(var k=0;k<btns.length;k++) btns[k].onclick=act;
}

async function act(){
  var el=this;
  var i=+el.getAttribute('data-i'), a=el.getAttribute('data-act'), b=blist[i];
  if(!b) return;
  // 删除要点两下。刻意**不用 confirm()** —— 和 prompt() 一样, 一部分手机浏览器内核
  // 会直接吞掉它并返回 false, 那样点「删除」就是毫无反应, 很难查。
  if(a==='del' && el.getAttribute('data-armed')!=='1'){
    el.setAttribute('data-armed','1');
    el.textContent='确认删除';
    el.classList.add('armed');
    clearTimeout(el._t);
    el._t=setTimeout(function(){
      el.removeAttribute('data-armed');
      el.textContent='删除';
      el.classList.remove('armed');
    },4000);
    toast('再点一下「确认删除」，图片会一起删掉，App 里立刻消失');
    return;
  }
  el.disabled=true;
  try{
    if(a==='del'){
      await post('/admin/banners/'+b.id+'/delete',new FormData());
      toast('已删除');
    } else if(a==='toggle'){
      var fd=new FormData(); fd.append('enabled',b.enabled?'0':'1');
      await post('/admin/banners/'+b.id,fd);
      toast(b.enabled?'已停用':'已启用');
    } else if(a==='up'){
      var prev=blist[i-1];
      var f1=new FormData(); f1.append('sort',String(prev.sort===b.sort?prev.sort-1:prev.sort));
      await post('/admin/banners/'+b.id,f1);
      if(prev.sort!==b.sort){
        var f2=new FormData(); f2.append('sort',String(b.sort));
        await post('/admin/banners/'+prev.id,f2);
      }
    }
    await loadOps();
  }catch(err){ toast(String(err.message||err)); el.disabled=false; }
}

$('reload').onclick=function(){ loadOps(); };

$('saveRel').onclick=async function(){
  var b=this; b.disabled=true;
  try{
    var fd=new FormData();
    fd.append('version',$('rv').value.trim());
    fd.append('url',$('ru').value.trim());
    fd.append('notes',$('rn').value.trim());
    var d=await post('/admin/release',fd);
    toast(d.cleared?'已撤下更新提示':'已发布');
  }catch(err){ toast(String(err.message||err)); }
  b.disabled=false;
};

async function loadOps(){
  var r=await fetch('/api/banners',{headers:{accept:'application/json'}});
  if(r.status===401){ location.href='/'; return; }
  if(!r.ok){ toast('横幅列表加载失败'); return; }
  var d=await r.json();
  blist=d.banners||[];
  renderBanners();
  var L=d.latest||{};
  $('rv').value=L.version||'';
  $('ru').value=L.url||'';
  $('rn').value=L.notes||'';
  opsLoaded=true;
}

// ── 密码 ────────────────────────────────────────────
/** 规则清单跟着输入实时打勾, 免得填完一大串才被后端退回来 */
function pwRules(){
  var a=$('pw1').value, b=$('pw2').value, kinds=0;
  [/[a-z]/,/[A-Z]/,/[0-9]/,/[^A-Za-z0-9]/].forEach(function(re){ if(re.test(a)) kinds++; });
  var ok=[a.length>=10 && a.length<=128 && a===a.trim(), kinds>=2, a.length>0 && a===b];
  ['r1','r2','r3'].forEach(function(id,i){ $(id).className=ok[i]?'ok':''; });
  $('pwGo').disabled=!(ok[0]&&ok[1]&&ok[2]);
}
['pw1','pw2'].forEach(function(id){ $(id).oninput=pwRules; });
$('pwShow').onchange=function(){
  var t=this.checked?'text':'password';
  ['pw1','pw2'].forEach(function(id){ $(id).type=t; });
};
$('pwForm').addEventListener('submit',async function(e){
  e.preventDefault();
  var b=$('pwGo'); b.disabled=true; b.textContent='修改中…';
  var next=$('pw1').value;
  try{
    var fd=new FormData();
    fd.append('next',next);
    fd.append('confirm',$('pw2').value);
    // 服务端改完会顺手换一张新 cookie —— 会话签名密钥跟着密码变, 不换就等于
    // 把自己踢下线
    await post('/admin/password',fd);
    ['pw1','pw2'].forEach(function(id){ $(id).value=''; });
    toast('密码已经改好了，其他浏览器上要重新登录');
  }catch(err){ toast(String(err.message||err)); }
  b.textContent='修改密码'; pwRules();
});
pwRules();
$('logout').onclick=async function(){
  this.disabled=true;
  try{ await fetch('/logout',{method:'POST',headers:{accept:'application/json'}}); }catch(e){}
  location.replace('/');
};

// ── 起步 ────────────────────────────────────────────
loadStats().catch(function(err){
  $('heroCap').textContent='加载失败：'+(err.message||err);
  toast('统计加载失败，刷新试试');
});
</script>
</body></html>`;
