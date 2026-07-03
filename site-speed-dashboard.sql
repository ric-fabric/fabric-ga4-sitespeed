-- =============================================================================
-- Site Speed x Conversion - BigQuery package for Looker Studio
-- =============================================================================
-- Setup:
--   1. Create dataset: fabric_speed (same region as the GA4 export)
--   2. Run the BACKFILL once to load history
--   3. Save the DAILY query as a scheduled query (runs daily ~08:00,
--      after the GA4 daily export lands):
--        Destination: fabric_speed.speed_sessions
--        Write preference: Append
--        Partitioning: session_date
--   4. Point Looker Studio at fabric_speed.speed_sessions
--
-- Replace project.analytics_XXXXX with the client's export dataset.
-- Customise the page_template CASE for the client's URL structure.
-- =============================================================================


-- =============================================================================
-- DAILY SCHEDULED QUERY  (processes yesterday, appends one row per session)
-- =============================================================================
WITH speed_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
       FROM UNNEST(event_params) WHERE key = 'ttfb') AS ttfb,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
       FROM UNNEST(event_params) WHERE key = 'fcp') AS fcp,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
       FROM UNNEST(event_params) WHERE key = 'lcp') AS lcp,
    (SELECT COALESCE(value.double_value, CAST(value.int_value AS FLOAT64))
       FROM UNNEST(event_params) WHERE key = 'cls') AS cls,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
       FROM UNNEST(event_params) WHERE key = 'inp') AS inp,
    (SELECT COALESCE(value.int_value, CAST(value.double_value AS INT64))
       FROM UNNEST(event_params) WHERE key = 'load') AS page_load,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'connection_type') AS connection_type,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'lcp_element') AS lcp_element,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'nav_type') AS nav_type,
    -- booleans can land as string or int depending on serialisation
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'was_hidden'),
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'was_hidden') AS STRING)
    ) AS was_hidden,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(@run_date, INTERVAL 1 DAY))
    AND event_name = 'site_speed'
),

-- First measured page per session = the landing experience
landing_speed AS (
  SELECT * EXCEPT (rn) FROM (
    SELECT *,
      ROW_NUMBER() OVER (
        PARTITION BY user_pseudo_id, session_id
        ORDER BY event_timestamp
      ) AS rn
    FROM speed_events
    WHERE nav_type = 'navigate'
      AND was_hidden IN ('false', '0')
      AND lcp IS NOT NULL
  )
  WHERE rn = 1
),

sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    ANY_VALUE(device.category) AS device_category,
    COUNTIF(event_name = 'purchase') > 0 AS converted,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS revenue
  FROM `project.analytics_XXXXX.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(@run_date, INTERVAL 1 DAY))
  GROUP BY 1, 2
)

SELECT
  DATE_SUB(@run_date, INTERVAL 1 DAY) AS session_date,
  s.user_pseudo_id,
  s.session_id,
  s.device_category,
  ls.connection_type,
  ls.ttfb, ls.fcp, ls.lcp, ls.cls, ls.inp, ls.page_load,
  ls.lcp_element,
  REGEXP_EXTRACT(ls.page_location, r'https?://[^/]+([^?#]*)') AS landing_path,
  -- Adjust per client URL structure
  CASE
    WHEN REGEXP_CONTAINS(ls.page_location, r'^https?://[^/]+/?(\?|#|$)') THEN 'Homepage'
    WHEN REGEXP_CONTAINS(ls.page_location, r'/product')  THEN 'PDP'
    WHEN REGEXP_CONTAINS(ls.page_location, r'/category|/collections') THEN 'PLP'
    WHEN REGEXP_CONTAINS(ls.page_location, r'/checkout|/basket|/cart') THEN 'Checkout'
    ELSE 'Other'
  END AS page_template,
  -- 250ms buckets, capped so the long tail collapses into one bucket
  CAST(LEAST(FLOOR(ls.lcp / 250) * 250, 8000) AS INT64) AS lcp_bucket,
  CAST(LEAST(FLOOR(ls.ttfb / 200) * 200, 4000) AS INT64) AS ttfb_bucket,
  s.converted,
  s.revenue
FROM sessions s
JOIN landing_speed ls
  USING (user_pseudo_id, session_id);


-- =============================================================================
-- BACKFILL (run once, WRITE_APPEND into the same table)
-- Identical to the daily query but swap the two _TABLE_SUFFIX filters for:
--   WHERE _TABLE_SUFFIX BETWEEN '20260701' AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
-- and replace the session_date line with:
--   PARSE_DATE('%Y%m%d', _TABLE_SUFFIX) via an added event_date passthrough,
--   or simply group the run per day if the export is large.
-- =============================================================================


-- =============================================================================
-- IMPACT MODEL - save as view: fabric_speed.vw_lcp_impact
-- Two scenarios per LCP bucket:
--   A) "to_good":   slow sessions convert at the <=2.5s cohort's rate
--   B) "shift_250": every session gets one bucket (250ms) faster
-- Model B is the conservative, defensible one for client conversations.
-- =============================================================================
WITH base AS (
  SELECT
    device_category,
    lcp_bucket,
    COUNT(*) AS sessions,
    COUNTIF(converted) AS conversions,
    SUM(revenue) AS revenue
  FROM `project.fabric_speed.speed_sessions`
  WHERE session_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
  GROUP BY 1, 2
),
rates AS (
  SELECT *,
    SAFE_DIVIDE(conversions, sessions) AS cr
  FROM base
),
good AS (
  SELECT
    device_category,
    SAFE_DIVIDE(SUM(conversions), SUM(sessions)) AS good_cr
  FROM base
  WHERE lcp_bucket <= 2500
  GROUP BY 1
),
aov AS (
  SELECT SAFE_DIVIDE(SUM(revenue), SUM(conversions)) AS aov
  FROM base
)
SELECT
  r.device_category,
  r.lcp_bucket,
  r.sessions,
  r.conversions,
  r.cr,
  g.good_cr,
  -- Scenario A: everyone at the fast cohort's CR
  GREATEST(r.sessions * (g.good_cr - r.cr), 0) AS incr_conversions_to_good,
  GREATEST(r.sessions * (g.good_cr - r.cr), 0) * a.aov AS incr_revenue_to_good,
  -- Scenario B: one bucket (250ms) faster
  GREATEST(r.sessions * (COALESCE(nxt.cr, r.cr) - r.cr), 0) AS incr_conversions_shift_250,
  GREATEST(r.sessions * (COALESCE(nxt.cr, r.cr) - r.cr), 0) * a.aov AS incr_revenue_shift_250
FROM rates r
JOIN good g USING (device_category)
CROSS JOIN aov a
LEFT JOIN rates nxt
  ON nxt.device_category = r.device_category
 AND nxt.lcp_bucket = r.lcp_bucket - 250
WHERE r.lcp_bucket > 2500
ORDER BY r.device_category, r.lcp_bucket;


-- =============================================================================
-- PAGE TEMPLATE SCORECARD - save as view: fabric_speed.vw_template_p75
-- =============================================================================
SELECT
  page_template,
  device_category,
  COUNT(*) AS sessions,
  APPROX_QUANTILES(lcp, 100)[OFFSET(75)] AS lcp_p75,
  APPROX_QUANTILES(ttfb, 100)[OFFSET(75)] AS ttfb_p75,
  APPROX_QUANTILES(inp, 100)[OFFSET(75)] AS inp_p75,
  ROUND(APPROX_QUANTILES(cls, 100)[OFFSET(75)], 3) AS cls_p75,
  SAFE_DIVIDE(COUNTIF(converted), COUNT(*)) AS session_cr
FROM `project.fabric_speed.speed_sessions`
WHERE session_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 28 DAY)
GROUP BY 1, 2
HAVING sessions >= 100
ORDER BY lcp_p75 DESC;
