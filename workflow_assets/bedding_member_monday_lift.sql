-- =============================================================================
-- BEDDING MEMBER MONDAY / LOYALTY LIFT
-- =============================================================================
-- Pulls Cost Performance Hub Single Promo Detail–equivalent participating SKUs
-- for a loyalty promo period in Bedding, joins Wayfair US daily GRS for:
--   1) the loyalty promo window, and
--   2) the last 10 non-promo days before the promo (L10),
-- then computes daily averages and lift at SKU grain.
--
-- EDIT THE inputs CTE before each run.
-- =============================================================================

WITH inputs AS (

-------------------------------------------
------- Enter Loyalty Promo Period --------
-------------------------------------------

SELECT
  0 AS Promo_Period_Id,              -- REQUIRED: CPH / Partner Home promo period ID
  'Bedding' AS Marketing_Category,   -- marketing category filter (mkcname)
  'Wayfair' AS Store_Brand,
  'United States' AS Store_Country,
  'Wayfair US' AS Brand_Catalog_Name,
  1 AS Brand_Catalog_Id,             -- 1 = Wayfair US
  10 AS L10_Non_Promo_Days,          -- baseline lookback: last N non-promo days

  -- Optional date overrides (leave NULL to use promo period start/end from CPH)
  CAST(NULL AS DATE) AS Promo_Start_Override,
  CAST(NULL AS DATE) AS Promo_End_Override

),

promo_window AS (
  SELECT
    inputs.Promo_Period_Id,
    inputs.Marketing_Category,
    inputs.Store_Brand,
    inputs.Store_Country,
    inputs.Brand_Catalog_Name,
    inputs.Brand_Catalog_Id,
    inputs.L10_Non_Promo_Days,
    COALESCE(inputs.Promo_Start_Override, MIN(DATE(eng.PromoStartDate))) AS promo_start_date,
    COALESCE(inputs.Promo_End_Override, MAX(DATE(eng.PromoEndDate))) AS promo_end_date,
    ANY_VALUE(eng.PromoPeriodName) AS promo_period_name
  FROM inputs
  LEFT JOIN `wf-gcp-us-ae-eunarta-prod.reporting.tbl_promo_parts_engagement` AS eng
    ON eng.PromoPeriodId = inputs.Promo_Period_Id
   AND eng.BrandCatalog_ID = inputs.Brand_Catalog_Id
  GROUP BY
    inputs.Promo_Period_Id,
    inputs.Marketing_Category,
    inputs.Store_Brand,
    inputs.Store_Country,
    inputs.Brand_Catalog_Name,
    inputs.Brand_Catalog_Id,
    inputs.L10_Non_Promo_Days,
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
    eng.Supplier_ID AS supplier_id,
    ANY_VALUE(eng.Supplier_Name) AS supplier_name,
    ANY_VALUE(eng.SRM) AS srm,
    eng.SKU AS sku,
    ANY_VALUE(dim_sku.clname) AS class_name,
    ANY_VALUE(COALESCE(eng.MarketingCategory_SU, dim_sku.mkcname)) AS marketing_category,
    MAX(ABS(eng.DiscountPercent)) AS discount_pct,
    MAX(ABS(eng.RecommendedDiscountPercent)) AS rec_discount_pct,
    MAX(ABS(eng.B2B_DiscountPercent)) AS b2b_discount_pct,
    SUM(COALESCE(eng.WSC_L12M, 0)) AS wsc_rev_l12m,
    SUM(COALESCE(eng.GRS_L12M, 0)) AS grs_l12m,
    COUNT(DISTINCT eng.SupplierPart_ID) AS participating_part_count
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_promo_parts_engagement` AS eng
  CROSS JOIN promo_window
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS dim_sku
    ON dim_sku.skuname = eng.SKU
  WHERE eng.PromoPeriodId = promo_window.Promo_Period_Id
    AND eng.BrandCatalog_ID = promo_window.Brand_Catalog_Id
    AND eng.Discount_Status = 'Active'
    AND ABS(COALESCE(eng.DiscountPercent, 0)) > 0
    AND COALESCE(eng.MarketingCategory_SU, dim_sku.mkcname) = promo_window.Marketing_Category
  GROUP BY
    promo_window.Promo_Period_Id,
    promo_window.promo_period_name,
    promo_window.promo_start_date,
    promo_window.promo_end_date,
    promo_window.Brand_Catalog_Name,
    promo_window.Store_Brand,
    promo_window.Store_Country,
    eng.Supplier_ID,
    eng.SKU
),

-- Last N Wayfair US non-promo days before the loyalty event
non_promo_dates AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    non_promo.Date AS sales_date,
    'non_promo' AS period_type
  FROM promo_window
  JOIN `wf-gcp-us-ae-eunarta-prod.staging.tbl_Pricing_tmp_NonPromo_Dates_Month_Week_FullData` AS non_promo
    ON non_promo.store = 'Wayfair US'
   AND non_promo.region = 'North America'
   AND non_promo.PromoFlag_T0T1 = 'N'
   AND non_promo.Date < promo_window.promo_start_date
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY promo_window.Promo_Period_Id
    ORDER BY non_promo.Date DESC
  ) <= promo_window.L10_Non_Promo_Days
),

promo_dates AS (
  SELECT
    promo_window.Promo_Period_Id AS promo_period_id,
    calendar_date AS sales_date,
    'loyalty' AS period_type
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
    MAX(IF(period_type = 'non_promo', sales_date, NULL)) AS non_promo_end_date
  FROM analysis_dates
  GROUP BY promo_period_id
),

currency AS (
  SELECT ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

order_rows AS (
  SELECT
    participating_skus.sku,
    analysis_dates.period_type,
    retail_sku_store_date.date AS sales_date,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM participating_skus
  JOIN analysis_dates
    ON analysis_dates.promo_period_id = participating_skus.promo_period_id
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.brandname = participating_skus.Store_Brand
   AND retail_sku_store_date.styname = participating_skus.Store_Country
   AND retail_sku_store_date.agg_level = 'DAILY'
   AND retail_sku_store_date.date = analysis_dates.sales_date
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
   AND retail_dim_sku.skuname = participating_skus.sku
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  CROSS JOIN currency
  WHERE orders.id IS NOT NULL
),

deduped_orders AS (
  SELECT
    sku,
    period_type,
    sales_date,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM order_rows
  GROUP BY sku, period_type, sales_date, order_id
),

sku_period_sales AS (
  SELECT
    sku,
    SUM(IF(period_type = 'loyalty', grs, 0)) AS loyalty_sales_total,
    SUM(IF(period_type = 'non_promo', grs, 0)) AS non_promo_sales_total
  FROM deduped_orders
  GROUP BY sku
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
  participating_skus.brand_catalog,
  participating_skus.supplier_id,
  participating_skus.supplier_name,
  participating_skus.srm,
  participating_skus.sku,
  participating_skus.class_name,
  participating_skus.marketing_category,
  ROUND(participating_skus.discount_pct, 4) AS discount_pct,
  ROUND(participating_skus.rec_discount_pct, 4) AS rec_discount_pct,
  ROUND(participating_skus.b2b_discount_pct, 4) AS b2b_discount_pct,
  ROUND(participating_skus.wsc_rev_l12m, 2) AS wsc_rev_l12m,
  ROUND(participating_skus.grs_l12m, 2) AS grs_l12m,
  participating_skus.participating_part_count,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_sales.non_promo_sales_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
    2
  ) AS non_promo_avg,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_sales.loyalty_sales_total, 0), NULLIF(date_counts.promo_day_count, 0)),
    2
  ) AS loyalty_avg,
  ROUND(
    SAFE_DIVIDE(COALESCE(sku_period_sales.loyalty_sales_total, 0), NULLIF(date_counts.promo_day_count, 0))
    - SAFE_DIVIDE(COALESCE(sku_period_sales.non_promo_sales_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
    2
  ) AS incremental_sales,
  ROUND(
    SAFE_DIVIDE(
      SAFE_DIVIDE(COALESCE(sku_period_sales.loyalty_sales_total, 0), NULLIF(date_counts.promo_day_count, 0))
      - SAFE_DIVIDE(COALESCE(sku_period_sales.non_promo_sales_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
      NULLIF(
        SAFE_DIVIDE(COALESCE(sku_period_sales.non_promo_sales_total, 0), NULLIF(date_counts.non_promo_day_count, 0)),
        0
      )
    ),
    4
  ) AS lift_pct
FROM participating_skus
LEFT JOIN sku_period_sales
  ON sku_period_sales.sku = participating_skus.sku
LEFT JOIN date_counts
  ON date_counts.promo_period_id = participating_skus.promo_period_id
ORDER BY loyalty_avg DESC, non_promo_avg DESC, sku
;
