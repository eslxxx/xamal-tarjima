-- Tilmach 活跃度统计的表结构。
--
-- 只有两张表, 都不含任何可以定位到个人的字段: 没有 IP、没有硬件标识、
-- 没有地理位置、没有任何用户输入的文本。install_id 是设备端随机生成的 UUID,
-- 清数据/重装就会变成一个新的。

-- 按「安装 × 天」记录的活跃度。客户端每次上报的是绝对值, 这里 upsert,
-- 所以重复上报、离线补传都不会重复计数。
CREATE TABLE IF NOT EXISTS daily (
  install_id   TEXT    NOT NULL,
  day          TEXT    NOT NULL,          -- YYYY-MM-DD, 设备本地日期
  launches     INTEGER NOT NULL DEFAULT 0,
  translations INTEGER NOT NULL DEFAULT 0,
  app_version  TEXT,
  updated_at   INTEGER NOT NULL,          -- unix 毫秒, 服务端时间
  PRIMARY KEY (install_id, day)
);

-- 按天查活跃用户数要扫这个索引
CREATE INDEX IF NOT EXISTS idx_daily_day ON daily(day);

-- 每个安装的汇总。first_day 用来算留存, last_day 用来算流失。
CREATE TABLE IF NOT EXISTS installs (
  install_id  TEXT PRIMARY KEY,
  first_day   TEXT    NOT NULL,
  last_day    TEXT    NOT NULL,
  app_version TEXT,
  updated_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_installs_first ON installs(first_day);
CREATE INDEX IF NOT EXISTS idx_installs_last  ON installs(last_day);

-- ════════════════════════════════════════════════════════════════════
-- 运营位 (App 设置页顶部的横幅)
-- ════════════════════════════════════════════════════════════════════

-- 一条横幅 = 一张图 + 一个可选的跳转链接。图片本体存在 KV 里 (见 wrangler.toml
-- 的 IMG 绑定), 这张表只存元信息 —— D1 不适合放二进制, 而 KV 的读取会被
-- Cloudflare 边缘缓存, 正好适合"很少改、很多人读"的图片。
CREATE TABLE IF NOT EXISTS banners (
  id         TEXT PRIMARY KEY,           -- 短随机 id, 同时是 KV 里的 key
  mime       TEXT    NOT NULL,           -- image/png | image/jpeg | image/webp
  bytes      INTEGER NOT NULL,
  link_url   TEXT,                       -- 点击跳转; 空 = 整块不可点
  note       TEXT,                       -- 只给后台看的备注, 不下发给 App
  enabled    INTEGER NOT NULL DEFAULT 1, -- 0 = 暂时下线但不删图
  sort       INTEGER NOT NULL DEFAULT 0, -- 小的排前面
  created_at INTEGER NOT NULL            -- unix 毫秒
);

CREATE INDEX IF NOT EXISTS idx_banners_order ON banners(enabled, sort, created_at);

-- 杂项配置的键值表。现在放两行:
--   latest_release  给 App 的"更新版本"用, 值是 JSON 字符串
--   dash_password   后台密码被改过之后的凭据 (见 src/auth.ts): 存的是
--                   HMAC(key=DASH_PASSWORD, msg=密码), 不是明文也不是普通哈希,
--                   密钥不在库里, 所以单独拖走这张表反推不出密码。
--                   删掉这一行 = 密码回到 DASH_PASSWORD 这个 secret。
-- 用一张 kv 表而不是给每个配置项建列, 是为了以后加东西不用改表结构 ——
-- D1 的 ALTER TABLE 在有数据时挺麻烦。
CREATE TABLE IF NOT EXISTS config (
  k          TEXT PRIMARY KEY,
  v          TEXT    NOT NULL,
  updated_at INTEGER NOT NULL
);

-- ════════════════════════════════════════════════════════════════════
-- 后台登录的失败计数 (限流)
-- ════════════════════════════════════════════════════════════════════

-- 后台是一个挂在公网上的密码框, 没有限流的话就是在等人慢慢试。
-- 这里存的是**后台访问者**(也就是管理员或攻击者)的 IP 哈希, 和"不采集 App
-- 用户 IP"那条原则不冲突。哈希加了密码当盐, 且只按 15 分钟的窗口保留。
CREATE TABLE IF NOT EXISTS login_fail (
  ip_hash TEXT    NOT NULL,
  win     INTEGER NOT NULL,           -- 15 分钟窗口序号
  n       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip_hash, win)
);
