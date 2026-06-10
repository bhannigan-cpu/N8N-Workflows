WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 53 WEEK) AS prior_year_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate,
    ANY_VALUE(currency_symbol) AS currency_symbol
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

grs_order_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    currency.currency_symbol,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start,
      params.prior_year_week_start
    )
),

deduped_grs_orders AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM grs_order_rows
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol,
    order_id
),

weekly_grs AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol,
    SUM(grs) AS weekly_grs
  FROM deduped_grs_orders
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol
),

grs_metrics AS (
  SELECT
    wg.supplier_name,
    wg.supplier_id,
    ANY_VALUE(wg.currency_symbol) AS currency_symbol,
    SUM(IF(wg.week_start = params.current_week_start, wg.weekly_grs, 0)) AS current_grs,
    SUM(IF(wg.week_start = params.prior_week_start, wg.weekly_grs, 0)) AS prior_week_grs,
    SUM(IF(wg.week_start = params.prior_year_week_start, wg.weekly_grs, 0)) AS prior_year_grs
  FROM weekly_grs AS wg
  CROSS JOIN params
  GROUP BY
    wg.supplier_name,
    wg.supplier_id
),

availability_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name,
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
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_year_week_start
    )
),

deduped_availability AS (
  SELECT
    week_start,
    supplier_id,
    supplier_name,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom
  FROM availability_rows
  GROUP BY
    week_start,
    supplier_id,
    supplier_name,
    ops_id
),

weekly_availability AS (
  SELECT
    week_start,
    supplier_id,
    supplier_name,
    SUM(availability_num) AS availability_num,
    SUM(availability_denom) AS availability_denom
  FROM deduped_availability
  GROUP BY
    week_start,
    supplier_id,
    supplier_name
),

availability_metrics AS (
  SELECT
    supplier_name,
    supplier_id,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, availability_num, 0)),
      SUM(IF(week_start = params.current_week_start, availability_denom, 0))
    ) AS current_availability,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_week_start, availability_num, 0)),
      SUM(IF(week_start = params.prior_week_start, availability_denom, 0))
    ) AS prior_week_availability
  FROM weekly_availability
  CROSS JOIN params
  GROUP BY
    supplier_name,
    supplier_id
),

traffic_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    traffic_source.id AS traffic_source_id,
    COALESCE(traffic_source.skuvisits, 0) AS visits,
    COALESCE(traffic_source.skuconverted, 0) AS converted
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_week_start
    )
),

deduped_traffic AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    traffic_source_id,
    ANY_VALUE(visits) AS visits,
    ANY_VALUE(converted) AS converted
  FROM traffic_rows
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    traffic_source_id
),

weekly_traffic AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    SUM(visits) AS visits,
    SUM(converted) AS converted
  FROM deduped_traffic
  GROUP BY
    week_start,
    supplier_name,
    supplier_id
),

traffic_metrics AS (
  SELECT
    supplier_name,
    supplier_id,
    SUM(IF(week_start = params.current_week_start, visits, 0)) AS current_visits,
    SUM(IF(week_start = params.prior_year_week_start, visits, 0)) AS prior_year_visits,
    SUM(IF(week_start = params.current_week_start, converted, 0)) AS current_converted,
    SUM(IF(week_start = params.prior_year_week_start, converted, 0)) AS prior_year_converted
  FROM weekly_traffic
  CROSS JOIN params
  GROUP BY
    supplier_name,
    supplier_id
),

mrpi_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    supplier_struct.id AS supplier_struct_id,
    COALESCE(supplier_struct.mrpi28d_numerator, 0) AS mrpi_num,
    COALESCE(supplier_struct.mrpi28d_denominator, 0) AS mrpi_denom
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_year_week_start
    )
),

deduped_mrpi AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    supplier_struct_id,
    ANY_VALUE(mrpi_num) AS mrpi_num,
    ANY_VALUE(mrpi_denom) AS mrpi_denom
  FROM mrpi_rows
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    supplier_struct_id
),

weekly_mrpi AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    SUM(mrpi_num) AS mrpi_num,
    SUM(mrpi_denom) AS mrpi_denom
  FROM deduped_mrpi
  GROUP BY
    week_start,
    supplier_name,
    supplier_id
),

mrpi_metrics AS (
  SELECT
    supplier_name,
    supplier_id,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, mrpi_num, 0)),
      SUM(IF(week_start = params.current_week_start, mrpi_denom, 0))
    ) AS current_mrpi,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_year_week_start, mrpi_num, 0)),
      SUM(IF(week_start = params.prior_year_week_start, mrpi_denom, 0))
    ) AS prior_year_mrpi
  FROM weekly_mrpi
  CROSS JOIN params
  GROUP BY
    supplier_name,
    supplier_id
),

wsi_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    wpi_wsi.id AS wpi_wsi_id,
    COALESCE(wpi_wsi.WSI28D_Numerator, 0) AS wsi_num,
    COALESCE(wpi_wsi.WSI28D_Denominator, 0) AS wsi_denom
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.wpi_wsi) AS wpi_wsi
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND CAST(wpi_wsi.indexdate AS STRING) = '2025-04-02'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) IN (
      params.current_week_start,
      params.prior_year_week_start
    )
),

deduped_wsi AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    wpi_wsi_id,
    ANY_VALUE(wsi_num) AS wsi_num,
    ANY_VALUE(wsi_denom) AS wsi_denom
  FROM wsi_rows
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    wpi_wsi_id
),

weekly_wsi AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    SUM(wsi_num) AS wsi_num,
    SUM(wsi_denom) AS wsi_denom
  FROM deduped_wsi
  GROUP BY
    week_start,
    supplier_name,
    supplier_id
),

wsi_metrics AS (
  SELECT
    supplier_name,
    supplier_id,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.current_week_start, wsi_num, 0)),
      SUM(IF(week_start = params.current_week_start, wsi_denom, 0))
    ) AS current_wsi,
    SAFE_DIVIDE(
      SUM(IF(week_start = params.prior_year_week_start, wsi_num, 0)),
      SUM(IF(week_start = params.prior_year_week_start, wsi_denom, 0))
    ) AS prior_year_wsi
  FROM weekly_wsi
  CROSS JOIN params
  GROUP BY
    supplier_name,
    supplier_id
),

final_metrics AS (
  SELECT
    grs_metrics.supplier_name,
    grs_metrics.supplier_id,
    grs_metrics.currency_symbol,
    grs_metrics.current_grs,
    grs_metrics.prior_week_grs,
    grs_metrics.prior_year_grs,
    SAFE_DIVIDE(grs_metrics.current_grs, NULLIF(SUM(grs_metrics.current_grs) OVER (), 0)) AS grs_share,
    SAFE_DIVIDE(grs_metrics.prior_year_grs, NULLIF(SUM(grs_metrics.prior_year_grs) OVER (), 0)) AS prior_year_grs_share,
    grs_metrics.current_grs - grs_metrics.prior_week_grs AS wow_grs_change,
    SAFE_DIVIDE(grs_metrics.current_grs - grs_metrics.prior_week_grs, NULLIF(grs_metrics.prior_week_grs, 0)) AS wow_grs_pct,
    grs_metrics.current_grs - grs_metrics.prior_year_grs AS yoy_grs_change,
    SAFE_DIVIDE(grs_metrics.current_grs - grs_metrics.prior_year_grs, NULLIF(grs_metrics.prior_year_grs, 0)) AS yoy_grs_pct,
    availability_metrics.current_availability,
    availability_metrics.prior_week_availability,
    availability_metrics.current_availability - availability_metrics.prior_week_availability AS wow_availability_change,
    SAFE_DIVIDE(
      availability_metrics.current_availability - availability_metrics.prior_week_availability,
      NULLIF(availability_metrics.prior_week_availability, 0)
    ) AS wow_availability_pct_change,
    traffic_metrics.current_visits,
    traffic_metrics.prior_year_visits,
    traffic_metrics.current_visits - traffic_metrics.prior_year_visits AS yoy_visits_change,
    SAFE_DIVIDE(
      traffic_metrics.current_visits - traffic_metrics.prior_year_visits,
      NULLIF(traffic_metrics.prior_year_visits, 0)
    ) AS yoy_visits_pct_change,
    SAFE_DIVIDE(traffic_metrics.current_converted, NULLIF(traffic_metrics.current_visits, 0)) AS current_cvr,
    SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)) AS prior_year_cvr,
    SAFE_DIVIDE(traffic_metrics.current_converted, NULLIF(traffic_metrics.current_visits, 0))
      - SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)) AS yoy_cvr_change,
    SAFE_DIVIDE(
      SAFE_DIVIDE(traffic_metrics.current_converted, NULLIF(traffic_metrics.current_visits, 0))
        - SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)),
      NULLIF(
        SAFE_DIVIDE(traffic_metrics.prior_year_converted, NULLIF(traffic_metrics.prior_year_visits, 0)),
        0
      )
    ) AS yoy_cvr_pct_change,
    mrpi_metrics.current_mrpi,
    mrpi_metrics.prior_year_mrpi,
    mrpi_metrics.current_mrpi - mrpi_metrics.prior_year_mrpi AS yoy_mrpi_change,
    SAFE_DIVIDE(mrpi_metrics.current_mrpi - mrpi_metrics.prior_year_mrpi, NULLIF(mrpi_metrics.prior_year_mrpi, 0)) AS yoy_mrpi_pct_change,
    (mrpi_metrics.current_mrpi - mrpi_metrics.prior_year_mrpi) * 10000 AS yoy_mrpi_bps_change,
    wsi_metrics.current_wsi,
    wsi_metrics.prior_year_wsi,
    wsi_metrics.current_wsi - wsi_metrics.prior_year_wsi AS yoy_wsi_change,
    SAFE_DIVIDE(wsi_metrics.current_wsi - wsi_metrics.prior_year_wsi, NULLIF(wsi_metrics.prior_year_wsi, 0)) AS yoy_wsi_pct_change,
    (wsi_metrics.current_wsi - wsi_metrics.prior_year_wsi) * 10000 AS yoy_wsi_bps_change
  FROM grs_metrics
  LEFT JOIN availability_metrics
    ON availability_metrics.supplier_id = grs_metrics.supplier_id
  LEFT JOIN traffic_metrics
    ON traffic_metrics.supplier_id = grs_metrics.supplier_id
  LEFT JOIN mrpi_metrics
    ON mrpi_metrics.supplier_id = grs_metrics.supplier_id
  LEFT JOIN wsi_metrics
    ON wsi_metrics.supplier_id = grs_metrics.supplier_id
),

ranked_metrics AS (
  SELECT
    supplier_name,
    supplier_id,
    currency_symbol,
    current_grs,
    prior_week_grs,
    prior_year_grs,
    grs_share,
    prior_year_grs_share,
    grs_share - prior_year_grs_share AS share_yoy_change,
    SAFE_DIVIDE(grs_share - prior_year_grs_share, NULLIF(prior_year_grs_share, 0)) AS share_yoy_pct_change,
    wow_grs_change,
    wow_grs_pct,
    yoy_grs_change,
    yoy_grs_pct,
    current_availability,
    prior_week_availability,
    wow_availability_change,
    wow_availability_pct_change,
    current_visits,
    prior_year_visits,
    yoy_visits_change,
    yoy_visits_pct_change,
    current_cvr,
    prior_year_cvr,
    yoy_cvr_change,
    yoy_cvr_pct_change,
    current_mrpi,
    prior_year_mrpi,
    yoy_mrpi_change,
    yoy_mrpi_pct_change,
    yoy_mrpi_bps_change,
    current_wsi,
    prior_year_wsi,
    yoy_wsi_change,
    yoy_wsi_pct_change,
    yoy_wsi_bps_change
  FROM final_metrics
),

top_grs AS (
  SELECT
    'Top 5 Current GRS' AS section,
    ROW_NUMBER() OVER (ORDER BY current_grs DESC) AS rank,
    *
  FROM ranked_metrics
  WHERE current_grs > 0
  QUALIFY rank <= 5
),

top_wow_movers AS (
  SELECT
    'Top 5 WoW GRS Movers' AS section,
    ROW_NUMBER() OVER (ORDER BY wow_grs_pct DESC) AS rank,
    *
  FROM ranked_metrics
  WHERE current_grs > 0
    AND prior_week_grs > 0
    AND wow_grs_pct IS NOT NULL
  QUALIFY rank <= 5
),

bottom_wow_movers AS (
  SELECT
    'Bottom 5 WoW GRS Movers' AS section,
    ROW_NUMBER() OVER (ORDER BY wow_grs_pct ASC) AS rank,
    *
  FROM ranked_metrics
  WHERE current_grs > 0
    AND prior_week_grs > 0
    AND wow_grs_pct IS NOT NULL
  QUALIFY rank <= 5
),

top_yoy_movers AS (
  SELECT
    'Top 5 YoY GRS Movers' AS section,
    ROW_NUMBER() OVER (ORDER BY yoy_grs_pct DESC) AS rank,
    *
  FROM ranked_metrics
  WHERE current_grs > 0
    AND prior_year_grs > 0
    AND yoy_grs_pct IS NOT NULL
  QUALIFY rank <= 5
),

bottom_yoy_movers AS (
  SELECT
    'Bottom 5 YoY GRS Movers' AS section,
    ROW_NUMBER() OVER (ORDER BY yoy_grs_pct ASC) AS rank,
    *
  FROM ranked_metrics
  WHERE current_grs > 0
    AND prior_year_grs > 0
    AND yoy_grs_pct IS NOT NULL
  QUALIFY rank <= 5
)

SELECT * FROM top_grs
UNION ALL
SELECT * FROM top_wow_movers
UNION ALL
SELECT * FROM bottom_wow_movers
UNION ALL
SELECT * FROM top_yoy_movers
UNION ALL
SELECT * FROM bottom_yoy_movers
ORDER BY
  section,
  rank;
