WITH params AS (
  SELECT
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -1 WEEK) AS current_week_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -2 WEEK) AS prior_week_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -53 WEEK) AS prior_year_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

order_metrics AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    COALESCE(SUM(orders.grossrevenuestable * COALESCE(currency.exchange_rate, 1)), 0) AS gross_revenue,
    COALESCE(SUM(orders.productcostnorebates * COALESCE(currency.exchange_rate, 1)), 0) AS wsc
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_dim_sku.mkcname = 'Window'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start,
      params.prior_year_week_start
    )
  GROUP BY
    week_start
),

availability_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_ops.id AS ops_id,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(availability_global_num, 0)
      ELSE 0
    END AS availability_num,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(availability_global_denom, 0)
      ELSE 0
    END AS availability_denom
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.opdimensions) AS retail_ops_dims
  LEFT JOIN UNNEST(supplier_part_struct.ops) AS retail_ops
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  CROSS JOIN params
  WHERE retail_dim_sku.mkcname = 'Window'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_availability AS (
  SELECT
    week_start,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom
  FROM availability_rows
  GROUP BY
    week_start,
    ops_id
),

availability_metrics AS (
  SELECT
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, availability_num, 0)),
      SUM(IF(week_start = params.current_week_start, availability_denom, 0))
    ) AS current_availability,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, availability_num, 0)),
      SUM(IF(week_start = params.prior_week_start, availability_denom, 0))
    ) AS prior_week_availability
  FROM deduped_availability
  CROSS JOIN params
),

traffic_metrics AS (
  SELECT
    SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start, COALESCE(traffic_source.skuvisits, 0), 0)) AS current_visits,
    SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.prior_year_week_start, COALESCE(traffic_source.skuvisits, 0), 0)) AS prior_year_visits,
    SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start, COALESCE(traffic_source.skuconverted, 0), 0)) AS current_converted,
    SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.prior_year_week_start, COALESCE(traffic_source.skuconverted, 0), 0)) AS prior_year_converted
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  CROSS JOIN params
  WHERE retail_dim_sku.mkcname = 'Window'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_year_week_start
    )
),

mrpi_metrics AS (
  SELECT
    SAFE_DIVIDE(
      SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start, COALESCE(supplier_struct.mrpi28d_numerator, 0), 0)),
      SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start, COALESCE(supplier_struct.mrpi28d_denominator, 0), 0))
    ) AS current_mrpi,
    SAFE_DIVIDE(
      SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.prior_week_start, COALESCE(supplier_struct.mrpi28d_numerator, 0), 0)),
      SUM(IF(DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.prior_week_start, COALESCE(supplier_struct.mrpi28d_denominator, 0), 0))
    ) AS prior_week_mrpi
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  CROSS JOIN params
  WHERE retail_dim_sku.mkcname = 'Window'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

wsi_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    wpi_wsi.id AS wpi_wsi_id,
    COALESCE(wpi_wsi.WSI28D_Numerator, 0) AS wsi_num,
    COALESCE(wpi_wsi.WSI28D_Denominator, 0) AS wsi_denom
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.wpi_wsi) AS wpi_wsi
  CROSS JOIN params
  WHERE retail_sku_store_date.agg_level = 'WEEKLY'
    AND CAST(wpi_wsi.indexdate AS STRING) = '2025-04-02'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_wsi AS (
  SELECT
    week_start,
    wpi_wsi_id,
    ANY_VALUE(wsi_num) AS wsi_num,
    ANY_VALUE(wsi_denom) AS wsi_denom
  FROM wsi_rows
  GROUP BY
    week_start,
    wpi_wsi_id
),

wsi_metrics AS (
  SELECT
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
)

SELECT
  'Top 15 Benchmark' AS section,
  NULL AS rank,
  'WINDOW BENCHMARK' AS supplier_name,
  NULL AS supplier_id,
  NULL AS current_grs,
  SAFE_DIVIDE(
    current_order.gross_revenue - prior_year_order.gross_revenue,
    NULLIF(prior_year_order.gross_revenue, 0)
  ) AS yoy_grs_pct,
  NULL AS grs_share,
  NULL AS share_yoy_pct_change,
  availability_metrics.current_availability,
  availability_metrics.current_availability - availability_metrics.prior_week_availability AS wow_availability_change,
  NULL AS current_wsc,
  SAFE_DIVIDE(
    current_order.wsc - prior_week_order.wsc,
    NULLIF(prior_week_order.wsc, 0)
  ) AS wow_wsc_pct_change,
  SAFE_DIVIDE(
    current_order.wsc - prior_year_order.wsc,
    NULLIF(prior_year_order.wsc, 0)
  ) AS yoy_wsc_pct_change,
  traffic_metrics.current_visits,
  SAFE_DIVIDE(
    traffic_metrics.current_visits - traffic_metrics.prior_year_visits,
    NULLIF(traffic_metrics.prior_year_visits, 0)
  ) AS yoy_visits_pct_change,
  SAFE_DIVIDE(
    traffic_metrics.current_converted,
    NULLIF(traffic_metrics.current_visits, 0)
  ) AS current_cvr,
  SAFE_DIVIDE(
    SAFE_DIVIDE(traffic_metrics.current_converted, NULLIF(traffic_metrics.current_visits, 0))
      - SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)),
    NULLIF(
      SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)),
      0
    )
  ) AS yoy_cvr_pct_change,
  mrpi_metrics.current_mrpi,
  mrpi_metrics.current_mrpi - mrpi_metrics.prior_week_mrpi AS wow_mrpi_change,
  wsi_metrics.current_wsi,
  wsi_metrics.current_wsi - wsi_metrics.prior_week_wsi AS wow_wsi_change,
  TRUE AS is_benchmark
FROM availability_metrics
CROSS JOIN traffic_metrics
CROSS JOIN mrpi_metrics
CROSS JOIN wsi_metrics
CROSS JOIN params
LEFT JOIN order_metrics AS current_order
  ON current_order.week_start = params.current_week_start
LEFT JOIN order_metrics AS prior_week_order
  ON prior_week_order.week_start = params.prior_week_start
LEFT JOIN order_metrics AS prior_year_order
  ON prior_year_order.week_start = params.prior_year_week_start
;
