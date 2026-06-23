WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 53 WEEK) AS prior_year_week_start
),

target_skus AS (
  SELECT 'Cathay' AS requested_supplier, 'Strong traffic, low conversion' AS requested_issue, 'DRVU1120' AS sku UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1045' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1040' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1028' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1029' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1051' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1272' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1304' UNION ALL
  SELECT 'Sunham', 'Slow traffic and low conversion', 'LCST1128' UNION ALL
  SELECT 'Sunham', 'Slow traffic and low conversion', 'LCST1287'
),

sku_dim AS (
  SELECT
    target_skus.requested_supplier,
    target_skus.requested_issue,
    target_skus.sku,
    retail_dim_sku.skuid,
    retail_dim_sku.skuname AS matched_sku,
    retail_dim_sku.skufullname AS sku_full_name,
    retail_dim_sku.prstatusname,
    retail_dim_sku.skustatusreasonname,
    retail_dim_sku.mkcname,
    retail_dim_sku.clinternalref,
    retail_dim_sku.directorgroup,
    retail_dim_sku.origmaname,
    retail_dim_sku.cskumaname,
    retail_dim_sku.pricegroupname,
    retail_dim_sku.svclassname,
    retail_dim_sku.incastlegatename,
    retail_dim_sku.prhasmapname,
    retail_dim_sku.wppname,
    retail_dim_sku.isvisualduplicatename
  FROM target_skus
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON UPPER(retail_dim_sku.skuname) = target_skus.sku
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY target_skus.sku
    ORDER BY
      CASE WHEN LOWER(retail_dim_sku.prstatusname) = 'active' THEN 0 ELSE 1 END,
      retail_dim_sku.skuid
  ) = 1
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

supplier_rows AS (
  SELECT
    sku_dim.sku,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

supplier_summary AS (
  SELECT
    sku,
    STRING_AGG(DISTINCT CAST(supplier_id AS STRING), ', ' ORDER BY CAST(supplier_id AS STRING)) AS supplier_ids,
    STRING_AGG(DISTINCT supplier_name, ', ' ORDER BY supplier_name) AS supplier_names
  FROM supplier_rows
  GROUP BY sku
),

traffic_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    traffic_source.id AS traffic_source_id,
    COALESCE(traffic_source.skuvisits, 0) AS visits,
    COALESCE(traffic_source.skuconverted, 0) AS converted
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start,
      params.prior_year_week_start
    )
),

deduped_traffic AS (
  SELECT
    week_start,
    sku,
    traffic_source_id,
    ANY_VALUE(visits) AS visits,
    ANY_VALUE(converted) AS converted
  FROM traffic_rows
  GROUP BY
    week_start,
    sku,
    traffic_source_id
),

traffic_metrics AS (
  SELECT
    sku,
    SUM(IF(week_start = params.current_week_start, visits, 0)) AS current_visits,
    SUM(IF(week_start = params.prior_week_start, visits, 0)) AS prior_week_visits,
    SUM(IF(week_start = params.prior_year_week_start, visits, 0)) AS prior_year_visits,
    SUM(IF(week_start = params.current_week_start, converted, 0)) AS current_converted,
    SUM(IF(week_start = params.prior_year_week_start, converted, 0)) AS prior_year_converted,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, converted, 0)),
      SUM(IF(week_start = params.current_week_start, visits, 0))
    ) AS current_cvr,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_year_week_start, converted, 0)),
      SUM(IF(week_start = params.prior_year_week_start, visits, 0))
    ) AS prior_year_cvr
  FROM deduped_traffic
  CROSS JOIN params
  GROUP BY sku
),

order_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs,
    COALESCE(orders.componentqty, 0) AS units
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start,
      params.prior_year_week_start
    )
),

deduped_orders AS (
  SELECT
    week_start,
    sku,
    order_id,
    ANY_VALUE(grs) AS grs,
    ANY_VALUE(units) AS units
  FROM order_rows
  GROUP BY
    week_start,
    sku,
    order_id
),

order_metrics AS (
  SELECT
    sku,
    SUM(IF(week_start = params.current_week_start, grs, 0)) AS current_grs,
    SUM(IF(week_start = params.prior_week_start, grs, 0)) AS prior_week_grs,
    SUM(IF(week_start = params.prior_year_week_start, grs, 0)) AS prior_year_grs,
    COUNT(DISTINCT IF(week_start = params.current_week_start AND order_id IS NOT NULL, order_id, NULL)) AS current_order_count,
    SUM(IF(week_start = params.current_week_start, units, 0)) AS current_units
  FROM deduped_orders
  CROSS JOIN params
  GROUP BY sku
),

availability_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    retail_ops.id AS ops_id,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(retail_ops.availability_global_num, 0)
      ELSE 0
    END AS availability_num,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(retail_ops.availability_global_denom, 0)
      ELSE 0
    END AS availability_denom,
    COALESCE(retail_ops.physicallyoos_num, 0) AS physically_oos_num,
    COALESCE(retail_ops.availability_waterfall_denom, 0) AS availability_waterfall_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.opdimensions) AS retail_ops_dims
  LEFT JOIN UNNEST(supplier_part_struct.ops) AS retail_ops
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_availability AS (
  SELECT
    week_start,
    sku,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom,
    MAX(physically_oos_num) AS physically_oos_num,
    MAX(availability_waterfall_denom) AS availability_waterfall_denom
  FROM availability_rows
  GROUP BY
    week_start,
    sku,
    ops_id
),

availability_metrics AS (
  SELECT
    sku,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, availability_num, 0)),
      SUM(IF(week_start = params.current_week_start, availability_denom, 0))
    ) AS current_availability,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, availability_num, 0)),
      SUM(IF(week_start = params.prior_week_start, availability_denom, 0))
    ) AS prior_week_availability,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, physically_oos_num, 0)),
      SUM(IF(week_start = params.current_week_start, availability_waterfall_denom, 0))
    ) AS current_physical_oos_rate
  FROM deduped_availability
  CROSS JOIN params
  GROUP BY sku
),

review_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    retail_sku_store_date.soid,
    COALESCE(retail_sku_store_date.five_plus_reviews_num, 0) AS five_plus_reviews_num,
    COALESCE(retail_sku_store_date.five_plus_reviews_denom, 0) AS five_plus_reviews_denom,
    COALESCE(retail_sku_store_date.active_sku_count_flag, 0) AS active_sku_count_flag
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

review_metrics AS (
  SELECT
    sku,
    MAX(IF(week_start = params.current_week_start, active_sku_count_flag, 0)) AS active_sku_count_flag,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, five_plus_reviews_num, 0)),
      SUM(IF(week_start = params.current_week_start, five_plus_reviews_denom, 0))
    ) AS current_five_plus_review_coverage,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, five_plus_reviews_num, 0)),
      SUM(IF(week_start = params.prior_week_start, five_plus_reviews_denom, 0))
    ) AS prior_week_five_plus_review_coverage
  FROM review_rows
  CROSS JOIN params
  GROUP BY sku
),

mrpi_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    supplier_struct.id AS supplier_struct_id,
    COALESCE(supplier_struct.mrpi28d_numerator, 0) AS mrpi_num,
    COALESCE(supplier_struct.mrpi28d_denominator, 0) AS mrpi_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_mrpi AS (
  SELECT
    week_start,
    sku,
    supplier_struct_id,
    ANY_VALUE(mrpi_num) AS mrpi_num,
    ANY_VALUE(mrpi_denom) AS mrpi_denom
  FROM mrpi_rows
  GROUP BY
    week_start,
    sku,
    supplier_struct_id
),

mrpi_metrics AS (
  SELECT
    sku,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, mrpi_num, 0)),
      SUM(IF(week_start = params.current_week_start, mrpi_denom, 0))
    ) AS current_mrpi,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, mrpi_num, 0)),
      SUM(IF(week_start = params.prior_week_start, mrpi_denom, 0))
    ) AS prior_week_mrpi
  FROM deduped_mrpi
  CROSS JOIN params
  GROUP BY sku
),

wsi_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    wpi_wsi.id AS wpi_wsi_id,
    SAFE_CAST(wpi_wsi.indexdate AS DATE) AS index_date,
    COALESCE(wpi_wsi.WSI28D_Numerator, 0) AS wsi_num,
    COALESCE(wpi_wsi.WSI28D_Denominator, 0) AS wsi_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.wpi_wsi) AS wpi_wsi
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_wsi AS (
  SELECT
    week_start,
    sku,
    wpi_wsi_id,
    ARRAY_AGG(
      STRUCT(wsi_num, wsi_denom, index_date)
      ORDER BY index_date DESC NULLS LAST
      LIMIT 1
    )[OFFSET(0)].wsi_num AS wsi_num,
    ARRAY_AGG(
      STRUCT(wsi_num, wsi_denom, index_date)
      ORDER BY index_date DESC NULLS LAST
      LIMIT 1
    )[OFFSET(0)].wsi_denom AS wsi_denom
  FROM wsi_rows
  GROUP BY
    week_start,
    sku,
    wpi_wsi_id
),

wsi_metrics AS (
  SELECT
    sku,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, wsi_num, 0)),
      SUM(IF(week_start = params.current_week_start, wsi_denom, 0))
    ) AS current_wsi,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, wsi_num, 0)),
      SUM(IF(week_start = params.prior_week_start, wsi_denom, 0))
    ) AS prior_week_wsi
  FROM deduped_wsi
  CROSS JOIN params
  GROUP BY sku
),

final_metrics AS (
  SELECT
    sku_dim.requested_supplier,
    sku_dim.requested_issue,
    sku_dim.sku,
    sku_dim.matched_sku,
    sku_dim.skuid,
    sku_dim.sku_full_name,
    sku_dim.prstatusname,
    sku_dim.skustatusreasonname,
    supplier_summary.supplier_names,
    supplier_summary.supplier_ids,
    CASE
      WHEN supplier_summary.supplier_names IS NULL THEN 'No current-week supplier row found'
      WHEN LOWER(supplier_summary.supplier_names) LIKE CONCAT('%', LOWER(sku_dim.requested_supplier), '%') THEN 'Matches requested supplier'
      ELSE 'Supplier mismatch or shared SKU'
    END AS supplier_match_status,
    sku_dim.mkcname,
    sku_dim.clinternalref,
    sku_dim.directorgroup,
    sku_dim.origmaname,
    sku_dim.cskumaname,
    sku_dim.pricegroupname,
    sku_dim.svclassname,
    sku_dim.incastlegatename,
    sku_dim.prhasmapname,
    sku_dim.wppname,
    sku_dim.isvisualduplicatename,
    review_metrics.active_sku_count_flag,
    traffic_metrics.current_visits,
    traffic_metrics.prior_week_visits,
    traffic_metrics.prior_year_visits,
    traffic_metrics.current_converted,
    traffic_metrics.prior_year_converted,
    traffic_metrics.current_cvr,
    traffic_metrics.prior_year_cvr,
    traffic_metrics.current_cvr - traffic_metrics.prior_year_cvr AS yoy_cvr_change,
    order_metrics.current_grs,
    order_metrics.prior_week_grs,
    order_metrics.prior_year_grs,
    order_metrics.current_order_count,
    order_metrics.current_units,
    availability_metrics.current_availability,
    availability_metrics.prior_week_availability,
    availability_metrics.current_availability - availability_metrics.prior_week_availability AS wow_availability_change,
    availability_metrics.current_physical_oos_rate,
    review_metrics.current_five_plus_review_coverage,
    review_metrics.prior_week_five_plus_review_coverage,
    mrpi_metrics.current_mrpi,
    mrpi_metrics.prior_week_mrpi,
    wsi_metrics.current_wsi,
    wsi_metrics.prior_week_wsi
  FROM sku_dim
  LEFT JOIN supplier_summary
    ON supplier_summary.sku = sku_dim.sku
  LEFT JOIN traffic_metrics
    ON traffic_metrics.sku = sku_dim.sku
  LEFT JOIN order_metrics
    ON order_metrics.sku = sku_dim.sku
  LEFT JOIN availability_metrics
    ON availability_metrics.sku = sku_dim.sku
  LEFT JOIN review_metrics
    ON review_metrics.sku = sku_dim.sku
  LEFT JOIN mrpi_metrics
    ON mrpi_metrics.sku = sku_dim.sku
  LEFT JOIN wsi_metrics
    ON wsi_metrics.sku = sku_dim.sku
)

SELECT
  *,
  CASE
    WHEN skuid IS NULL THEN 'SKU not found in retail_dim_sku'
    WHEN COALESCE(active_sku_count_flag, 0) = 0
      OR LOWER(COALESCE(prstatusname, '')) NOT LIKE '%active%'
      THEN 'Suppression/status risk'
    WHEN current_visits IS NULL AND current_grs IS NULL THEN 'No current-week retail aggregate data'
    WHEN current_availability IS NOT NULL AND current_availability < 0.90 THEN 'Availability constrained'
    WHEN current_five_plus_review_coverage IS NOT NULL AND current_five_plus_review_coverage < 1 THEN 'Review coverage gap'
    WHEN current_visits >= 100 AND COALESCE(current_cvr, 0) < 0.02 THEN 'Strong traffic, low conversion'
    WHEN COALESCE(current_visits, 0) < 50 AND COALESCE(current_cvr, 0) < 0.02 THEN 'Low traffic and low conversion'
    WHEN COALESCE(current_wsi, 0) >= 0.20 THEN 'Search/wholesale index pressure'
    WHEN COALESCE(current_mrpi, 0) >= 0.20 THEN 'Retail price index pressure'
    ELSE 'No single blocker flagged'
  END AS diagnosis,
  CASE
    WHEN skuid IS NULL THEN 'Validate SKU spelling or CDF mapping before ad changes.'
    WHEN COALESCE(active_sku_count_flag, 0) = 0
      OR LOWER(COALESCE(prstatusname, '')) NOT LIKE '%active%'
      THEN 'Confirm SKU status, suppression, and status reason in catalog tools.'
    WHEN current_visits IS NULL AND current_grs IS NULL
      THEN 'Check findability/suppression and whether the SKU had any US Wayfair weekly activity.'
    WHEN current_availability IS NOT NULL AND current_availability < 0.90
      THEN 'Prioritize inventory/availability recovery before raising bids.'
    WHEN current_five_plus_review_coverage IS NOT NULL AND current_five_plus_review_coverage < 1
      THEN 'Prioritize review generation or review acceleration; low review coverage can suppress conversion.'
    WHEN current_visits >= 100 AND COALESCE(current_cvr, 0) < 0.02
      THEN 'Audit PDP merchandising, price competitiveness, review count, shipping promise, and promo fit.'
    WHEN COALESCE(current_visits, 0) < 50 AND COALESCE(current_cvr, 0) < 0.02
      THEN 'Diagnose visibility first: findability, ad eligibility, bid competitiveness, ranking, and catalog status.'
    WHEN COALESCE(current_wsi, 0) >= 0.20
      THEN 'Review wholesale/search competitiveness and whether bid increases are being offset by weak organic/ad rank signals.'
    WHEN COALESCE(current_mrpi, 0) >= 0.20
      THEN 'Review retail price competitiveness, promo strategy, and price group setup.'
    ELSE 'Monitor weekly trend and compare against class/category benchmarks.'
  END AS recommended_next_step
FROM final_metrics
ORDER BY
  requested_supplier,
  requested_issue,
  sku;
