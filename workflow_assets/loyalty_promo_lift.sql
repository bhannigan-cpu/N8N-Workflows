-- =============================================================================
-- LOYALTY PROMO LIFT (WSC)
-- =============================================================================
-- Pulls Cost Performance Hub Single Promo Detail–equivalent participating SKUs
-- for a loyalty promo period + product marketing category, joins Wayfair US daily WSC
-- for:
--   1) the loyalty promo window (from the promo period dates), and
--   2) the last N non-promo days before the promo start (default L10),
-- then computes daily averages and lift at SKU grain.
--
-- Product marketing category filter uses retail_dim_sku.mkcname
-- (not supplier MarketingCategory_SU).
--
-- WSC source of truth:
--   wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_order_product_revenue_cost
--   SoID = 49 (Wayfair US), SUM(ProductCostNoRebates) by OrderDate + SKU
--
-- L10 non-promo dates:
--   Days before promo start that fall outside real NA promo windows from
--   tbl_promo_calendar. Extended Discounts / Frequency / Super Rooms /
--   Source Rooms are ignored (they do not count as promo for this baseline).
--   Fallback: FullData days with Final='N' or Final='Y' only from those
--   ignored promo types (and not a concurrent T0/T1 event).
--
-- Placeholders are filled by the n8n "Build SQL Query" node from Configure Inputs:
--   __PROMO_PERIOD_ID__
--   __MARKETING_CATEGORY__          -- product marketing category (mkcname)
--   __STORE_BRAND__
--   __STORE_COUNTRY__
--   __BRAND_CATALOG_NAME__
--   __BRAND_CATALOG_ID__
--   __L10_NON_PROMO_DAYS__
--   __PROMO_START_OVERRIDE__   -- DATE 'YYYY-MM-DD' or NULL
--   __PROMO_END_OVERRIDE__     -- DATE 'YYYY-MM-DD' or NULL
-- =============================================================================

WITH inputs AS (
  SELECT
    __PROMO_PERIOD_ID__ AS Promo_Period_Id,
    '__MARKETING_CATEGORY__' AS Product_Marketing_Category,
    '__STORE_BRAND__' AS Store_Brand,
    '__STORE_COUNTRY__' AS Store_Country,
    '__BRAND_CATALOG_NAME__' AS Brand_Catalog_Name,
    __BRAND_CATALOG_ID__ AS Brand_Catalog_Id,
    __L10_NON_PROMO_DAYS__ AS L10_Non_Promo_Days,
    __PROMO_START_OVERRIDE__ AS Promo_Start_Override,
    __PROMO_END_OVERRIDE__ AS Promo_End_Override,
    49 AS Wayfair_US_SoID
),

promo_window AS (
  SELECT
    inputs.Promo_Period_Id,
    inputs.Product_Marketing_Category,
    inputs.Store_Brand,
    inputs.Store_Country,
    inputs.Brand_Catalog_Name,
    inputs.Brand_Catalog_Id,
    inputs.L10_Non_Promo_Days,
    inputs.Wayfair_US_SoID,
    COALESCE(inputs.Promo_Start_Override, MIN(DATE(eng.PromoStartDate))) AS promo_start_date,
    COALESCE(inputs.Promo_End_Override, MAX(DATE(eng.PromoEndDate))) AS promo_end_date,
    ANY_VALUE(eng.PromoPeriodName) AS promo_period_name
  FROM inputs
  LEFT JOIN `wf-gcp-us-ae-eunarta-prod.reporting.tbl_promo_parts_engagement` AS eng
    ON eng.PromoPeriodId = inputs.Promo_Period_Id
   AND eng.BrandCatalog_ID = inputs.Brand_Catalog_Id
  GROUP BY
    inputs.Promo_Period_Id,
    inputs.Product_Marketing_Category,
    inputs.Store_Brand,
    inputs.Store_Country,
    inputs.Brand_Catalog_Name,
    inputs.Brand_Catalog_Id,
    inputs.L10_Non_Promo_Days,
    inputs.Wayfair_US_SoID,
    inputs.Promo_Start_Override,
    inputs.Promo_End_Override
),

-- Participating loyalty SKUs (CPH Single Promo Detail equivalent, rolled to SKU)
participating_skus AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    promo_window.promo_period_name,
    promo_window.promo_start_date,
    promo_window.promo_end_date,
    promo_window.Brand_Catalog_Name AS brand_catalog,
    promo_window.Store_Brand,
    promo_window.Store_Country,
    promo_window.Wayfair_US_SoID,
    eng.Supplier_ID AS supplier_id,
    ANY_VALUE(eng.Supplier_Name) AS supplier_name,
    ANY_VALUE(eng.SRM) AS srm,
    eng.SKU AS sku,
    ANY_VALUE(dim_sku.clname) AS class_name,
    ANY_VALUE(dim_sku.mkcname) AS product_marketing_category,
    MAX(ABS(eng.DiscountPercent)) AS discount_pct,
    MAX(ABS(eng.RecommendedDiscountPercent)) AS rec_discount_pct,
    MAX(ABS(eng.B2B_DiscountPercent)) AS b2b_discount_pct,
    SUM(COALESCE(eng.WSC_L12M, 0)) AS wsc_rev_l12m,
    SUM(COALESCE(eng.GRS_L12M, 0)) AS grs_l12m,
    COUNT(DISTINCT eng.SupplierPart_ID) AS participating_part_count
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_promo_parts_engagement` AS eng
  CROSS JOIN promo_window
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS dim_sku
    ON dim_sku.skuname = eng.SKU
  WHERE eng.PromoPeriodId = promo_window.Promo_Period_Id
    AND eng.BrandCatalog_ID = promo_window.Brand_Catalog_Id
    AND eng.Discount_Status = 'Active'
    AND ABS(COALESCE(eng.DiscountPercent, 0)) > 0
    AND dim_sku.mkcname = promo_window.Product_Marketing_Category
  GROUP BY
    promo_window.Promo_Period_Id,
    promo_window.promo_period_name,
    promo_window.promo_start_date,
    promo_window.promo_end_date,
    promo_window.Brand_Catalog_Name,
    promo_window.Store_Brand,
    promo_window.Store_Country,
    promo_window.Wayfair_US_SoID,
    eng.Supplier_ID,
    eng.SKU
),

-- Resolve SKU names → skuid (needed for the order-cost fact join)
sku_keys AS (
  SELECT
    participating_skus.promo_period_id,
    participating_skus.sku,
    participating_skus.Wayfair_US_SoID,
    retail_dim_sku.skuid
  FROM participating_skus
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON UPPER(retail_dim_sku.skuname) = UPPER(participating_skus.sku)
),

-- Real NA promo windows for L10 baseline.
-- Extended Discounts / Frequency / Super Rooms / Source Rooms do NOT count as
-- promo (NARTA guidance: ignore those quarterly rows when picking non-promo days).
-- tbl_promo_calendar columns: Geo, PromoName, PromoStartDate, PromoEndDate, Tier
real_na_promo_windows AS (
  SELECT DISTINCT
    DATE(cal.PromoStartDate) AS window_start,
    DATE(cal.PromoEndDate) AS window_end,
    cal.PromoName AS promo_name
  FROM `wf-gcp-us-ae-eunarta-prod.staging.tbl_promo_calendar` AS cal
  WHERE UPPER(COALESCE(cal.Geo, '')) = 'NA'
    AND cal.PromoStartDate IS NOT NULL
    AND cal.PromoEndDate IS NOT NULL
    AND cal.PromoPeriodId IS NOT NULL
    AND COALESCE(CAST(cal.Tier AS STRING), '') != 'Q'
    AND NOT REGEXP_CONTAINS(
      LOWER(COALESCE(cal.PromoName, '')),
      r'extended|frequency|super ?room|source ?room'
    )
),

-- Candidate days before loyalty promo start (look back far enough to find N days).
candidate_baseline_days AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    promo_window.L10_Non_Promo_Days,
    day AS sales_date
  FROM promo_window
  CROSS JOIN UNNEST(
    GENERATE_DATE_ARRAY(
      DATE_SUB(promo_window.promo_start_date, INTERVAL 400 DAY),
      DATE_SUB(promo_window.promo_start_date, INTERVAL 1 DAY)
    )
  ) AS day
),

-- True non-promo = not inside any real NA promo window (extended/super room ignored).
calendar_non_promo_dates AS (
  SELECT
    candidate_baseline_days.promo_period_id,
    candidate_baseline_days.sales_date,
    'non_promo' AS period_type,
    'promo_calendar_excl_extended' AS non_promo_source
  FROM candidate_baseline_days
  WHERE NOT EXISTS (
    SELECT 1
    FROM real_na_promo_windows AS w
    WHERE candidate_baseline_days.sales_date BETWEEN w.window_start AND w.window_end
  )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY candidate_baseline_days.promo_period_id
    ORDER BY candidate_baseline_days.sales_date DESC
  ) <= candidate_baseline_days.L10_Non_Promo_Days
),

-- Fallback: FullData days where Final='N' OR Final='Y' only due to extended/super room
-- (and not also a T0/T1 event that day).
fulldata_non_promo_dates AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    non_promo.Date AS sales_date,
    'non_promo' AS period_type,
    'fulldata_excl_extended' AS non_promo_source
  FROM promo_window
  JOIN `wf-gcp-us-ae-eunarta-prod.staging.tbl_Pricing_tmp_NonPromo_Dates_Month_Week_FullData` AS non_promo
    ON CAST(non_promo.soid AS INT64) = promo_window.Wayfair_US_SoID
   AND non_promo.Date < promo_window.promo_start_date
   AND (
      non_promo.PromoFlag_Final = 'N'
      OR (
        REGEXP_CONTAINS(
          LOWER(CONCAT(
            COALESCE(non_promo.PromoName_Final, ''), ' ',
            COALESCE(non_promo.PromoName_T0T1, ''), ' ',
            COALESCE(non_promo.PromoName_NARTA, '')
          )),
          r'extended|frequency|super ?room|source ?room'
        )
        AND COALESCE(non_promo.PromoFlag_T0T1, 'N') = 'N'
      )
    )
  WHERE NOT EXISTS (
    SELECT 1
    FROM calendar_non_promo_dates
    WHERE calendar_non_promo_dates.promo_period_id = promo_window.Promo_Period_Id
  )
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY promo_window.Promo_Period_Id
    ORDER BY non_promo.Date DESC
  ) <= promo_window.L10_Non_Promo_Days
),

-- Last-resort fallback: prior calendar days before promo start.
fallback_non_promo_dates AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    calendar_date AS sales_date,
    'non_promo' AS period_type,
    'calendar_fallback' AS non_promo_source
  FROM promo_window
  CROSS JOIN UNNEST(
    GENERATE_DATE_ARRAY(
      DATE_SUB(promo_window.promo_start_date, INTERVAL promo_window.L10_Non_Promo_Days DAY),
      DATE_SUB(promo_window.promo_start_date, INTERVAL 1 DAY)
    )
  ) AS calendar_date
  WHERE NOT EXISTS (
    SELECT 1
    FROM calendar_non_promo_dates
    WHERE calendar_non_promo_dates.promo_period_id = promo_window.Promo_Period_Id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM fulldata_non_promo_dates
    WHERE fulldata_non_promo_dates.promo_period_id = promo_window.Promo_Period_Id
  )
),

non_promo_dates AS (
  SELECT * FROM calendar_non_promo_dates
  UNION ALL
  SELECT * FROM fulldata_non_promo_dates
  UNION ALL
  SELECT * FROM fallback_non_promo_dates
),

promo_dates AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    calendar_date AS sales_date,
    'loyalty' AS period_type,
    CAST(NULL AS STRING) AS non_promo_source
  FROM promo_window
  CROSS JOIN UNNEST(
    GENERATE_DATE_ARRAY(promo_window.promo_start_date, promo_window.promo_end_date)
  ) AS calendar_date
),

analysis_dates AS (
  SELECT * FROM promo_dates
  UNION ALL
  SELECT * FROM non_promo_dates
),

date_counts AS (
  SELECT
    promo_period_id,
    COUNTIF(period_type = 'loyalty') AS promo_day_count,
    COUNTIF(period_type = 'non_promo') AS non_promo_day_count,
    MIN(IF(period_type = 'non_promo', sales_date, NULL)) AS non_promo_start_date,
    MAX(IF(period_type = 'non_promo', sales_date, NULL)) AS non_promo_end_date,
    MIN(sales_date) AS analysis_start_date,
    MAX(sales_date) AS analysis_end_date,
    ANY_VALUE(IF(period_type = 'non_promo', non_promo_source, NULL)) AS non_promo_source,
    STRING_AGG(
      IF(period_type = 'non_promo', CAST(sales_date AS STRING), NULL)
      ORDER BY sales_date DESC
    ) AS non_promo_dates_list
  FROM analysis_dates
  GROUP BY promo_period_id
),

-- Daily WSC from retail order financials (SoT for wholesale cost / ProductCostNoRebates).
-- Pattern matches Cathay/Sunham scorecard + WBR category scripts: SoID 49 by OrderDate + skuid.
order_wsc_by_day AS (
  SELECT
    sku_keys.promo_period_id,
    sku_keys.sku,
    DATE(orders.OrderDate) AS sales_date,
    SUM(COALESCE(orders.ProductCostNoRebates, orders.productcost, 0)) AS daily_wsc
  FROM sku_keys
  JOIN date_counts
    ON date_counts.promo_period_id = sku_keys.promo_period_id
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_order_product_revenue_cost` AS orders
    ON orders.skuid = sku_keys.skuid
   AND orders.SoID = sku_keys.Wayfair_US_SoID
   AND DATE(orders.OrderDate) BETWEEN date_counts.analysis_start_date AND date_counts.analysis_end_date
  GROUP BY
    sku_keys.promo_period_id,
    sku_keys.sku,
    DATE(orders.OrderDate)
),

sku_daily_wsc AS (
  SELECT
    order_wsc_by_day.sku,
    analysis_dates.period_type,
    order_wsc_by_day.sales_date,
    order_wsc_by_day.daily_wsc
  FROM order_wsc_by_day
  JOIN analysis_dates
    ON analysis_dates.promo_period_id = order_wsc_by_day.promo_period_id
   AND analysis_dates.sales_date = order_wsc_by_day.sales_date
),

sku_period_wsc AS (
  SELECT
    sku,
    SUM(IF(period_type = 'loyalty', daily_wsc, 0)) AS loyalty_wsc_total,
    SUM(IF(period_type = 'non_promo', daily_wsc, 0)) AS non_promo_wsc_total,
    COUNTIF(period_type = 'loyalty' AND daily_wsc > 0) AS loyalty_days_with_wsc,
    COUNTIF(period_type = 'non_promo' AND daily_wsc > 0) AS non_promo_days_with_wsc
  FROM sku_daily_wsc
  GROUP BY sku
),

run_diagnostics AS (
  SELECT
    participating.promo_period_id,
    participating.participating_sku_count,
    COALESCE(keys.sku_key_count, 0) AS sku_key_count,
    COALESCE(wsc.skus_with_any_wsc, 0) AS skus_with_any_wsc,
    COALESCE(wsc.loyalty_wsc_total_sum, 0) AS loyalty_wsc_total_sum,
    COALESCE(wsc.non_promo_wsc_total_sum, 0) AS non_promo_wsc_total_sum
  FROM (
    SELECT promo_period_id, COUNT(*) AS participating_sku_count
    FROM participating_skus
    GROUP BY promo_period_id
  ) AS participating
  LEFT JOIN (
    SELECT promo_period_id, COUNT(DISTINCT sku) AS sku_key_count
    FROM sku_keys
    GROUP BY promo_period_id
  ) AS keys
    ON keys.promo_period_id = participating.promo_period_id
  LEFT JOIN (
    SELECT
      order_wsc_by_day.promo_period_id,
      COUNT(DISTINCT order_wsc_by_day.sku) AS skus_with_any_wsc,
      SUM(IF(analysis_dates.period_type = 'loyalty', order_wsc_by_day.daily_wsc, 0)) AS loyalty_wsc_total_sum,
      SUM(IF(analysis_dates.period_type = 'non_promo', order_wsc_by_day.daily_wsc, 0)) AS non_promo_wsc_total_sum
    FROM order_wsc_by_day
    JOIN analysis_dates
      ON analysis_dates.promo_period_id = order_wsc_by_day.promo_period_id
     AND analysis_dates.sales_date = order_wsc_by_day.sales_date
    GROUP BY order_wsc_by_day.promo_period_id
  ) AS wsc
    ON wsc.promo_period_id = participating.promo_period_id
)

SELECT
  participating_skus.promo_period_id,
  participating_skus.promo_period_name,
  CAST(participating_skus.promo_start_date AS STRING) AS promo_start_date,
  CAST(participating_skus.promo_end_date AS STRING) AS promo_end_date,
  date_counts.promo_day_count,
  CAST(date_counts.non_promo_start_date AS STRING) AS non_promo_start_date,
  CAST(date_counts.non_promo_end_date AS STRING) AS non_promo_end_date,
  date_counts.non_promo_day_count,
  date_counts.non_promo_source,
  date_counts.non_promo_dates_list,
  CAST(date_counts.analysis_start_date AS STRING) AS analysis_start_date,
  CAST(date_counts.analysis_end_date AS STRING) AS analysis_end_date,
  run_diagnostics.participating_sku_count,
  run_diagnostics.sku_key_count,
  run_diagnostics.skus_with_any_wsc,
  ROUND(run_diagnostics.loyalty_wsc_total_sum, 2) AS loyalty_wsc_total_sum,
  ROUND(run_diagnostics.non_promo_wsc_total_sum, 2) AS non_promo_wsc_total_sum,
  participating_skus.brand_catalog,
  participating_skus.supplier_id,
  participating_skus.supplier_name,
  participating_skus.srm,
  participating_skus.sku,
  participating_skus.class_name,
  participating_skus.product_marketing_category,
  ROUND(participating_skus.discount_pct, 4) AS discount_pct,
  ROUND(participating_skus.rec_discount_pct, 4) AS rec_discount_pct,
  ROUND(participating_skus.b2b_discount_pct, 4) AS b2b_discount_pct,
  ROUND(participating_skus.wsc_rev_l12m, 2) AS wsc_rev_l12m,
  ROUND(participating_skus.grs_l12m, 2) AS grs_l12m,
  participating_skus.participating_part_count,
  COALESCE(sku_period_wsc.loyalty_days_with_wsc, 0) AS loyalty_days_with_wsc,
  COALESCE(sku_period_wsc.non_promo_days_with_wsc, 0) AS non_promo_days_with_wsc,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_wsc.non_promo_wsc_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
    2
  ) AS non_promo_avg,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_wsc.loyalty_wsc_total, 0), NULLIF(date_counts.promo_day_count, 0)),
    2
  ) AS loyalty_avg,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_wsc.loyalty_wsc_total, 0), NULLIF(date_counts.promo_day_count, 0))
    - SAFE_DIVIDE(COALESCE(sku_period_wsc.non_promo_wsc_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
    2
  ) AS incremental_wsc,
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(COALESCE(sku_period_wsc.loyalty_wsc_total, 0), NULLIF(date_counts.promo_day_count, 0))
      - SAFE_DIVIDE(COALESCE(sku_period_wsc.non_promo_wsc_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
      NULLIF(
        SAFE_DIVIDE(COALESCE(sku_period_wsc.non_promo_wsc_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
        0
      )
    ),
    4
  ) AS lift_pct
FROM participating_skus
LEFT JOIN sku_period_wsc
  ON sku_period_wsc.sku = participating_skus.sku
LEFT JOIN date_counts
  ON date_counts.promo_period_id = participating_skus.promo_period_id
LEFT JOIN run_diagnostics
  ON run_diagnostics.promo_period_id = participating_skus.promo_period_id
ORDER BY loyalty_avg DESC, non_promo_avg DESC, sku
;
