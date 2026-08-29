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
