/**
 * 后台的统计查询 (GET /api/stats)。
 */

import { Env, dayOffset, json } from './shared';

export async function stats(env: Env): Promise<Response> {
  const today = dayOffset(0);
  const d7 = dayOffset(-6);
  const d30 = dayOffset(-29);

  const q = <T>(sql: string, ...binds: unknown[]) =>
    env.DB.prepare(sql).bind(...binds).all<T>();

  const [totals, trend, versions, cohorts, heavy] = await Promise.all([
    q<Record<string, number>>(
      `SELECT
         (SELECT COUNT(*) FROM installs)                                     AS installs,
         (SELECT COUNT(*) FROM installs WHERE first_day = ?1)                AS new_today,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day = ?1)       AS dau,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day >= ?2)      AS wau,
         (SELECT COUNT(DISTINCT install_id) FROM daily WHERE day >= ?3)      AS mau,
         (SELECT COALESCE(SUM(launches),0)     FROM daily)                   AS launches,
         (SELECT COALESCE(SUM(translations),0) FROM daily)                   AS translations,
         (SELECT COALESCE(SUM(launches),0)     FROM daily WHERE day = ?1)    AS launches_today,
         (SELECT COALESCE(SUM(translations),0) FROM daily WHERE day = ?1)    AS translations_today`,
      today, d7, d30),

    // 最近 30 天曲线
    q<{ day: string; users: number; launches: number; translations: number; newcomers: number }>(
      `SELECT d.day,
              COUNT(DISTINCT d.install_id) AS users,
              SUM(d.launches)              AS launches,
              SUM(d.translations)          AS translations,
              (SELECT COUNT(*) FROM installs i WHERE i.first_day = d.day) AS newcomers
         FROM daily d
        WHERE d.day >= ?1
        GROUP BY d.day
        ORDER BY d.day`,
      d30),

    // 版本分布 (只看最近 30 天还活跃的)
    q<{ app_version: string; users: number }>(
      `SELECT COALESCE(app_version,'未知') AS app_version,
              COUNT(DISTINCT install_id)   AS users
         FROM daily WHERE day >= ?1
        GROUP BY app_version ORDER BY users DESC`,
      d30),

    // 留存: 按首见日期分组, 看有多少人在 D1 / D7 / D30 之后还回来过
    q<{ first_day: string; cohort: number; d1: number; d7: number; d30: number }>(
      `SELECT i.first_day,
              COUNT(*) AS cohort,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day = date(i.first_day, '+1 day')) THEN 1 ELSE 0 END) AS d1,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day >= date(i.first_day, '+7 day')) THEN 1 ELSE 0 END) AS d7,
              SUM(CASE WHEN EXISTS (SELECT 1 FROM daily x WHERE x.install_id = i.install_id
                    AND x.day >= date(i.first_day, '+30 day')) THEN 1 ELSE 0 END) AS d30
         FROM installs i
        WHERE i.first_day >= ?1
        GROUP BY i.first_day ORDER BY i.first_day DESC LIMIT 30`,
      dayOffset(-90)),

    // 粘性: 最近 7 天里每人平均每天启动/翻译多少次
    q<{ avg_launches: number; avg_translations: number; active_days: number }>(
      `SELECT ROUND(AVG(launches), 1)      AS avg_launches,
              ROUND(AVG(translations), 1)  AS avg_translations,
              COUNT(*)                     AS active_days
         FROM daily WHERE day >= ?1`,
      d7),
  ]);

  return json({
    generated_at: new Date().toISOString(),
    totals: totals.results?.[0] ?? {},
    stickiness: heavy.results?.[0] ?? {},
    trend: trend.results ?? [],
    versions: versions.results ?? [],
    cohorts: cohorts.results ?? [],
  }, 200, { 'cache-control': 'no-store' });
}
