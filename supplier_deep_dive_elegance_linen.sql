WITH params AS (
  SELECT
    22695 AS supplier_id,
    'Elegance Linen' AS supplier_name,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 26 WEEK) AS l6m_start_week,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 53 WEEK) AS prior_year_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

supplier_sku_weeks AS (
  SELECT DISTINCT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_sku_store_date.skuid,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name,
    supplier_struct.id AS supplier_struct_id,
    COALESCE(supplier_struct.sponsoredproducttotalspend, 0) AS sponsored_product_spend
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) BETWEEN params.l6m_start_week AND params.current_week_start
),

sku_universe AS (
  SELECT DISTINCT
    skuid
  FROM supplier_sku_weeks
),

sku_dim AS (
  SELECT
    sku_universe.skuid,
    retail_dim_sku.skuname AS sku,
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
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(retail_dim_sku.prstatusname, '')), r'active|live') THEN 1
      ELSE 0
    END AS is_live_or_active_status
  FROM sku_universe
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = sku_universe.skuid
),

traffic_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_universe.skuid,
    traffic_source.id AS traffic_source_id,
    COALESCE(traffic_source.skuvisits, 0) AS visits,
    COALESCE(traffic_source.skuconverted, 0) AS converted
  FROM sku_universe
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_universe.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) BETWEEN params.l6m_start_week AND params.current_week_start
),

deduped_traffic AS (
  SELECT
    week_start,
    skuid,
    traffic_source_id,
    ANY_VALUE(visits) AS visits,
    ANY_VALUE(converted) AS converted
  FROM traffic_rows
  GROUP BY
    week_start,
    skuid,
    traffic_source_id
),

traffic_l6m AS (
  SELECT
    skuid,
    SUM(visits) AS visits_l6m,
    SUM(converted) AS converted_l6m,
    SAFE_DIVIDE(SUM(converted), SUM(visits)) AS cvr_l6m,
    COUNT(DISTINCT IF(visits > 0, week_start, NULL)) AS weeks_with_traffic_l6m,
    SAFE_DIVIDE(SUM(visits), COUNT(DISTINCT week_start)) AS avg_weekly_visits_l6m
  FROM deduped_traffic
  GROUP BY skuid
),

order_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_sku_store_date.skuid,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs,
    COALESCE(orders.componentqty, 0) AS units
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
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) BETWEEN params.l6m_start_week AND params.current_week_start
),

deduped_orders AS (
  SELECT
    week_start,
    skuid,
    order_id,
    ANY_VALUE(grs) AS grs,
    ANY_VALUE(units) AS units
  FROM order_rows
  GROUP BY
    week_start,
    skuid,
    order_id
),

orders_l6m AS (
  SELECT
    skuid,
    SUM(grs) AS grs_l6m,
    COUNT(DISTINCT IF(order_id IS NOT NULL, order_id, NULL)) AS orders_l6m,
    SUM(units) AS units_l6m
  FROM deduped_orders
  GROUP BY skuid
),

ad_spend_l6m AS (
  SELECT
    skuid,
    SUM(sponsored_product_spend) AS sponsored_product_spend_l6m
  FROM (
    SELECT
      week_start,
      skuid,
      supplier_struct_id,
      ANY_VALUE(sponsored_product_spend) AS sponsored_product_spend
    FROM supplier_sku_weeks
    GROUP BY
      week_start,
      skuid,
      supplier_struct_id
  )
  GROUP BY skuid
),

current_catalog_rows AS (
  SELECT
    sku_universe.skuid,
    retail_sku_store_date.soid,
    COALESCE(retail_sku_store_date.active_sku_count_flag, 0) AS active_sku_count_flag,
    COALESCE(retail_sku_store_date.five_plus_reviews_num, 0) AS five_plus_reviews_num,
    COALESCE(retail_sku_store_date.five_plus_reviews_denom, 0) AS five_plus_reviews_denom,
    COALESCE(retail_sku_store_date.rec_tag_cov_num, 0) AS rec_tag_cov_num,
    COALESCE(retail_sku_store_date.rec_tag_cov_denom, 0) AS rec_tag_cov_denom
  FROM sku_universe
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_universe.skuid
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

catalog_readiness AS (
  SELECT
    skuid,
    MAX(active_sku_count_flag) AS active_sku_count_flag,
    SAFE_DIVIDE(SUM(five_plus_reviews_num), SUM(five_plus_reviews_denom)) AS five_plus_review_coverage,
    SAFE_DIVIDE(SUM(rec_tag_cov_num), SUM(rec_tag_cov_denom)) AS recommended_tag_coverage,
    SUM(rec_tag_cov_denom) - SUM(rec_tag_cov_num) AS missing_recommended_tag_count
  FROM current_catalog_rows
  GROUP BY skuid
),

availability_rows AS (
  SELECT
    retail_sku_store_date.skuid,
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
    COALESCE(retail_ops.availability_waterfall_denom, 0) AS availability_waterfall_denom,
    COALESCE(retail_ops.remorse_return_rate_op_num, 0) AS remorse_return_num,
    COALESCE(retail_ops.remorse_return_rate_op_denom, 0) AS remorse_return_denom,
    COALESCE(retail_ops.speed_badging_rate_pdp_num, 0) AS speed_badging_num,
    COALESCE(retail_ops.speed_badging_rate_pdp_denom, 0) AS speed_badging_denom
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
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_availability AS (
  SELECT
    skuid,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom,
    MAX(physically_oos_num) AS physically_oos_num,
    MAX(availability_waterfall_denom) AS availability_waterfall_denom,
    MAX(remorse_return_num) AS remorse_return_num,
    MAX(remorse_return_denom) AS remorse_return_denom,
    MAX(speed_badging_num) AS speed_badging_num,
    MAX(speed_badging_denom) AS speed_badging_denom
  FROM availability_rows
  GROUP BY
    skuid,
    ops_id
),

availability_current AS (
  SELECT
    skuid,
    SAFE_DIVIDE(SUM(availability_num), SUM(availability_denom)) AS current_availability,
    SAFE_DIVIDE(SUM(physically_oos_num), SUM(availability_waterfall_denom)) AS current_physical_oos_rate,
    SAFE_DIVIDE(SUM(remorse_return_num), SUM(remorse_return_denom)) AS current_remorse_return_rate,
    SAFE_DIVIDE(SUM(speed_badging_num), SUM(speed_badging_denom)) AS current_speed_badging_rate
  FROM deduped_availability
  GROUP BY skuid
),

mrpi_rows AS (
  SELECT
    retail_sku_store_date.skuid,
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
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

mrpi_current AS (
  SELECT
    skuid,
    SAFE_DIVIDE(SUM(mrpi_num), SUM(mrpi_denom)) AS current_mrpi
  FROM (
    SELECT
      skuid,
      supplier_struct_id,
      ANY_VALUE(mrpi_num) AS mrpi_num,
      ANY_VALUE(mrpi_denom) AS mrpi_denom
    FROM mrpi_rows
    GROUP BY skuid, supplier_struct_id
  )
  GROUP BY skuid
),

wsi_rows AS (
  SELECT
    retail_sku_store_date.skuid,
    wpi_wsi.id AS wpi_wsi_id,
    SAFE_CAST(wpi_wsi.indexdate AS DATE) AS index_date,
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
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

wsi_current AS (
  SELECT
    skuid,
    SAFE_DIVIDE(SUM(wsi_num), SUM(wsi_denom)) AS current_wsi
  FROM (
    SELECT
      skuid,
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
    GROUP BY skuid, wpi_wsi_id
  )
  GROUP BY skuid
),

sku_metrics AS (
  SELECT
    sku_dim.skuid,
    sku_dim.sku,
    sku_dim.sku_full_name,
    sku_dim.prstatusname,
    sku_dim.skustatusreasonname,
    sku_dim.mkcname,
    sku_dim.clinternalref,
    sku_dim.pricegroupname,
    sku_dim.svclassname,
    sku_dim.incastlegatename,
    sku_dim.prhasmapname,
    sku_dim.wppname,
    sku_dim.is_live_or_active_status,
    COALESCE(traffic_l6m.visits_l6m, 0) AS visits_l6m,
    COALESCE(traffic_l6m.converted_l6m, 0) AS converted_l6m,
    traffic_l6m.cvr_l6m,
    COALESCE(traffic_l6m.weeks_with_traffic_l6m, 0) AS weeks_with_traffic_l6m,
    traffic_l6m.avg_weekly_visits_l6m,
    COALESCE(orders_l6m.grs_l6m, 0) AS grs_l6m,
    COALESCE(orders_l6m.orders_l6m, 0) AS orders_l6m,
    COALESCE(orders_l6m.units_l6m, 0) AS units_l6m,
    COALESCE(ad_spend_l6m.sponsored_product_spend_l6m, 0) AS sponsored_product_spend_l6m,
    COALESCE(catalog_readiness.active_sku_count_flag, 0) AS active_sku_count_flag,
    catalog_readiness.five_plus_review_coverage,
    catalog_readiness.recommended_tag_coverage,
    COALESCE(catalog_readiness.missing_recommended_tag_count, 0) AS missing_recommended_tag_count,
    availability_current.current_availability,
    availability_current.current_physical_oos_rate,
    availability_current.current_remorse_return_rate,
    availability_current.current_speed_badging_rate,
    mrpi_current.current_mrpi,
    wsi_current.current_wsi,
    CASE
      WHEN sku_dim.is_live_or_active_status = 0 THEN 'Not live/active'
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) < 50 THEN 'Low traffic'
      WHEN COALESCE(traffic_l6m.cvr_l6m, 0) < 0.01 THEN 'Very weak CVR'
      WHEN COALESCE(traffic_l6m.cvr_l6m, 0) < 0.02 THEN 'Weak CVR'
      ELSE 'Performing / monitor'
    END AS performance_bucket,
    CONCAT(
      IF(sku_dim.is_live_or_active_status = 0, 'Status; ', ''),
      IF(COALESCE(catalog_readiness.recommended_tag_coverage, 1) < 1, 'Missing tags; ', ''),
      IF(COALESCE(catalog_readiness.five_plus_review_coverage, 0) < 1, 'Needs 5+ reviews; ', ''),
      IF(COALESCE(availability_current.current_availability, 1) < 0.90, 'Availability; ', ''),
      IF(COALESCE(mrpi_current.current_mrpi, 0) >= 0.20 OR COALESCE(wsi_current.current_wsi, 0) >= 0.20, 'Pricing/search competitiveness; ', ''),
      IF(COALESCE(traffic_l6m.cvr_l6m, 1) < 0.02 AND COALESCE(traffic_l6m.visits_l6m, 0) >= 50, 'PDP conversion; ', '')
    ) AS blocker_flags,
    CASE
      WHEN sku_dim.is_live_or_active_status = 0 THEN 'Fix live/active status and suppression reason before investing in traffic.'
      WHEN COALESCE(catalog_readiness.recommended_tag_coverage, 1) < 1 THEN 'Complete recommended tags tied to bedding search/filter behavior: material, size, color, pattern, thread count or fabric attribute where applicable, product type, and set/piece count.'
      WHEN COALESCE(catalog_readiness.five_plus_review_coverage, 0) < 1 THEN 'Prioritize review acquisition before traffic scaling; use review acceleration or supplier-funded reviews for SKUs nearest the 5+ threshold.'
      WHEN COALESCE(availability_current.current_availability, 1) < 0.90 THEN 'Resolve availability and supplier-part purchasability before scaling ads.'
      WHEN COALESCE(mrpi_current.current_mrpi, 0) >= 0.20 OR COALESCE(wsi_current.current_wsi, 0) >= 0.20 THEN 'Audit MAP/MSRP/cost inputs and price-value competitiveness; do not increase bids until pricing/search suppression risk is addressed.'
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) < 50 THEN 'Traffic is the bottleneck: confirm ad eligibility, category placement, search terms, bids, and title/tag alignment.'
      WHEN COALESCE(traffic_l6m.cvr_l6m, 0) < 0.02 THEN 'Conversion is the bottleneck: improve PDP trust with accurate dimensions, scale imagery, true-to-life color, close-ups of material/texture/finish, clear fabric/quality callouts, and stronger price/promo positioning.'
      ELSE 'Monitor and selectively scale traffic; no major readiness blocker flagged.'
    END AS sku_recommended_action
  FROM sku_dim
  LEFT JOIN traffic_l6m
    ON traffic_l6m.skuid = sku_dim.skuid
  LEFT JOIN orders_l6m
    ON orders_l6m.skuid = sku_dim.skuid
  LEFT JOIN ad_spend_l6m
    ON ad_spend_l6m.skuid = sku_dim.skuid
  LEFT JOIN catalog_readiness
    ON catalog_readiness.skuid = sku_dim.skuid
  LEFT JOIN availability_current
    ON availability_current.skuid = sku_dim.skuid
  LEFT JOIN mrpi_current
    ON mrpi_current.skuid = sku_dim.skuid
  LEFT JOIN wsi_current
    ON wsi_current.skuid = sku_dim.skuid
),

summary AS (
  SELECT
    COUNT(*) AS total_skus,
    COUNTIF(is_live_or_active_status = 1) AS live_skus,
    COUNTIF(is_live_or_active_status = 0) AS non_live_skus,
    COUNTIF(COALESCE(visits_l6m, 0) > 0) AS skus_with_traffic_l6m,
    COUNTIF(COALESCE(grs_l6m, 0) > 0) AS skus_with_sales_l6m,
    SUM(visits_l6m) AS visits_l6m,
    SUM(converted_l6m) AS converted_l6m,
    SAFE_DIVIDE(SUM(converted_l6m), SUM(visits_l6m)) AS cvr_l6m,
    SUM(grs_l6m) AS grs_l6m,
    SUM(orders_l6m) AS orders_l6m,
    SUM(units_l6m) AS units_l6m,
    SAFE_DIVIDE(SUM(grs_l6m), SUM(orders_l6m)) AS aov_l6m,
    SUM(sponsored_product_spend_l6m) AS sponsored_product_spend_l6m,
    AVG(five_plus_review_coverage) AS avg_five_plus_review_coverage,
    AVG(recommended_tag_coverage) AS avg_recommended_tag_coverage,
    COUNTIF(COALESCE(five_plus_review_coverage, 0) < 1) AS skus_below_5_review_coverage,
    COUNTIF(COALESCE(recommended_tag_coverage, 1) < 1) AS skus_missing_recommended_tags,
    AVG(current_availability) AS avg_current_availability,
    AVG(current_physical_oos_rate) AS avg_current_physical_oos_rate,
    AVG(current_remorse_return_rate) AS avg_current_remorse_return_rate,
    AVG(current_speed_badging_rate) AS avg_current_speed_badging_rate,
    AVG(current_mrpi) AS avg_current_mrpi,
    AVG(current_wsi) AS avg_current_wsi,
    COUNTIF(COALESCE(current_mrpi, 0) >= 0.20 OR COALESCE(current_wsi, 0) >= 0.20) AS skus_with_pricing_competitiveness_risk,
    COUNTIF(COALESCE(current_availability, 1) < 0.90) AS skus_with_availability_risk,
    COUNTIF(COALESCE(visits_l6m, 0) >= 100 AND COALESCE(cvr_l6m, 0) < 0.02) AS high_traffic_low_cvr_skus,
    COUNTIF(COALESCE(visits_l6m, 0) < 50) AS low_traffic_skus
  FROM sku_metrics
),

ranked_skus AS (
  SELECT
    sku_metrics.*,
    ROW_NUMBER() OVER (
      ORDER BY
        CASE
          WHEN COALESCE(visits_l6m, 0) >= 100 AND COALESCE(cvr_l6m, 0) < 0.02 THEN 0
          WHEN COALESCE(visits_l6m, 0) < 50 THEN 1
          WHEN COALESCE(recommended_tag_coverage, 1) < 1 THEN 2
          WHEN COALESCE(five_plus_review_coverage, 0) < 1 THEN 3
          WHEN COALESCE(current_mrpi, 0) >= 0.20 OR COALESCE(current_wsi, 0) >= 0.20 THEN 4
          ELSE 5
        END,
        grs_l6m DESC,
        visits_l6m DESC
    ) AS opportunity_rank
  FROM sku_metrics
),

output_rows AS (
  SELECT
    'executive_summary' AS section,
    1 AS sort_order,
    CAST(NULL AS STRING) AS sku,
    'Executive readout' AS title,
    CONCAT(
      'Elegance Linen has a meaningful Wayfair scaling opportunity, but the path is not simply more traffic. Over the last 6 months, the supplier had ',
      CAST(COALESCE(ROUND(visits_l6m), 0) AS STRING), ' visits, ',
      CAST(COALESCE(ROUND(converted_l6m), 0) AS STRING), ' converted visits, and a ',
      CAST(COALESCE(ROUND(cvr_l6m * 100, 1), 0) AS STRING), '% CVR across ',
      CAST(total_skus AS STRING), ' SKUs. L6M GRS was $', CAST(COALESCE(ROUND(grs_l6m), 0) AS STRING),
      ' across ', CAST(COALESCE(orders_l6m, 0) AS STRING), ' orders. ',
      'The biggest move-the-needle levers are readiness and trust: ',
      CAST(skus_missing_recommended_tags AS STRING), ' SKUs are missing recommended tags, ',
      CAST(skus_below_5_review_coverage AS STRING), ' SKUs are below 5+ review coverage, ',
      CAST(skus_with_availability_risk AS STRING), ' SKUs have availability risk, and ',
      CAST(skus_with_pricing_competitiveness_risk AS STRING), ' SKUs show pricing/search competitiveness risk.'
    ) AS narrative,
    'Use this supplier conversation to align on a Wayfair growth plan: fix catalog readiness first, then use targeted ad spend on SKUs with the best readiness and conversion profile.' AS recommended_action,
    CAST(NULL AS FLOAT64) AS visits_l6m,
    CAST(NULL AS FLOAT64) AS cvr_l6m,
    CAST(NULL AS FLOAT64) AS grs_l6m,
    CAST(NULL AS INT64) AS orders_l6m,
    total_skus,
    live_skus,
    sponsored_product_spend_l6m,
    avg_five_plus_review_coverage AS five_plus_review_coverage,
    avg_recommended_tag_coverage AS recommended_tag_coverage,
    avg_current_availability AS current_availability,
    avg_current_remorse_return_rate AS current_remorse_return_rate,
    avg_current_mrpi AS current_mrpi,
    avg_current_wsi AS current_wsi,
    'Supplier-level summary' AS blocker_flags
  FROM summary

  UNION ALL

  SELECT
    'growth_lever' AS section,
    10 AS sort_order,
    CAST(NULL AS STRING) AS sku,
    'Traffic and marketplace buy-in' AS title,
    CONCAT(
      'This supplier is reportedly strong on Amazon and TikTok Shop, which suggests product-market fit exists off Wayfair. On Wayfair, the L6M traffic base is ',
      CAST(COALESCE(ROUND(visits_l6m), 0) AS STRING), ' visits across ', CAST(skus_with_traffic_l6m AS STRING), ' SKUs with traffic. ',
      'Sponsored product spend captured in Retail CDL was $', CAST(COALESCE(ROUND(sponsored_product_spend_l6m), 0) AS STRING),
      ', so the supplier conversation should separate two questions: are they funding Wayfair traffic, and are the SKUs ready enough for that traffic to convert?'
    ) AS narrative,
    'Do not pitch blanket spend. Build a funded test around SKUs that are live, tagged, reviewed, available, and not pricing-suppressed; use weaker SKUs as catalog cleanup asks before ad expansion.' AS recommended_action,
    CAST(visits_l6m AS FLOAT64),
    cvr_l6m,
    grs_l6m,
    orders_l6m,
    total_skus,
    live_skus,
    sponsored_product_spend_l6m,
    avg_five_plus_review_coverage,
    avg_recommended_tag_coverage,
    avg_current_availability,
    avg_current_remorse_return_rate,
    avg_current_mrpi,
    avg_current_wsi,
    'Traffic/ad adoption' AS blocker_flags
  FROM summary

  UNION ALL

  SELECT
    'growth_lever' AS section,
    20 AS sort_order,
    CAST(NULL AS STRING) AS sku,
    'Catalog readiness: tags and reviews' AS title,
    CONCAT(
      'Catalog readiness is the most direct unlock for search visibility and shopper trust. Average recommended tag coverage is ',
      CAST(COALESCE(ROUND(avg_recommended_tag_coverage * 100, 1), 0) AS STRING), '%, and average 5+ review coverage is ',
      CAST(COALESCE(ROUND(avg_five_plus_review_coverage * 100, 1), 0) AS STRING), '%. ',
      CAST(skus_missing_recommended_tags AS STRING), ' SKUs are missing recommended tags and ',
      CAST(skus_below_5_review_coverage AS STRING), ' SKUs need stronger review coverage.'
    ) AS narrative,
    'Prioritize tag completion on high-impression bedding attributes: size, material/fabric, color, pattern, thread-count or fabric detail where applicable, set/piece count, closure type, care, and style. Pair that with review acceleration on SKUs closest to reaching 5+ reviews.' AS recommended_action,
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    CAST(NULL AS INT64),
    total_skus,
    live_skus,
    sponsored_product_spend_l6m,
    avg_five_plus_review_coverage,
    avg_recommended_tag_coverage,
    avg_current_availability,
    avg_current_remorse_return_rate,
    avg_current_mrpi,
    avg_current_wsi,
    'Tags/reviews' AS blocker_flags
  FROM summary

  UNION ALL

  SELECT
    'growth_lever' AS section,
    30 AS sort_order,
    CAST(NULL AS STRING) AS sku,
    'PDP conversion and buyer-remorse prevention' AS title,
    CONCAT(
      'If the supplier already wins on Amazon/TikTok, Wayfair PDPs need to recreate that confidence: clear dimensions, accurate color, material quality, and realistic imagery. Current L6M CVR is ',
      CAST(COALESCE(ROUND(cvr_l6m * 100, 1), 0) AS STRING), '%, and buyer-remorse return rate is ',
      CAST(COALESCE(ROUND(avg_current_remorse_return_rate * 100, 1), 0) AS STRING), '%. ',
      'For bedding, conversion often depends on reducing uncertainty around fabric hand-feel, color, set contents, scale, and care expectations.'
    ) AS narrative,
    'Ask for high-resolution true-to-life images, close-ups of texture/finish, color descriptions with undertones, images in varied lighting/backgrounds, side-by-side color or size option imagery, clear material and care copy, and accurate dimensions/set contents. If quality perception lags price, revisit price/value or promo support.' AS recommended_action,
    CAST(visits_l6m AS FLOAT64),
    cvr_l6m,
    grs_l6m,
    orders_l6m,
    total_skus,
    live_skus,
    sponsored_product_spend_l6m,
    avg_five_plus_review_coverage,
    avg_recommended_tag_coverage,
    avg_current_availability,
    avg_current_remorse_return_rate,
    avg_current_mrpi,
    avg_current_wsi,
    'PDP trust/conversion' AS blocker_flags
  FROM summary

  UNION ALL

  SELECT
    'growth_lever' AS section,
    40 AS sort_order,
    CAST(NULL AS STRING) AS sku,
    'Pricing, availability, and operational friction' AS title,
    CONCAT(
      'Pricing/search competitiveness and availability can cap both traffic and conversion. Average MRPI is ',
      CAST(COALESCE(ROUND(avg_current_mrpi * 100, 1), 0) AS STRING), '%, average WSI is ',
      CAST(COALESCE(ROUND(avg_current_wsi * 100, 1), 0) AS STRING), '%, and average current availability is ',
      CAST(COALESCE(ROUND(avg_current_availability * 100, 1), 0) AS STRING), '%. ',
      CAST(skus_with_pricing_competitiveness_risk AS STRING), ' SKUs show pricing/search risk and ',
      CAST(skus_with_availability_risk AS STRING), ' show availability risk.'
    ) AS narrative,
    'Resolve MAP/MSRP/cost inputs, margin guardrail or pricing suppression signals, and availability before scaling bids. Use promos tactically where Wayfair price/value is not competitive with Amazon/TikTok alternatives.' AS recommended_action,
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    CAST(NULL AS FLOAT64),
    CAST(NULL AS INT64),
    total_skus,
    live_skus,
    sponsored_product_spend_l6m,
    avg_five_plus_review_coverage,
    avg_recommended_tag_coverage,
    avg_current_availability,
    avg_current_remorse_return_rate,
    avg_current_mrpi,
    avg_current_wsi,
    'Pricing/availability' AS blocker_flags
  FROM summary

  UNION ALL

  SELECT
    'sku_priority' AS section,
    100 + opportunity_rank AS sort_order,
    sku,
    CONCAT('#', CAST(opportunity_rank AS STRING), ' SKU priority: ', sku) AS title,
    CONCAT(
      sku, ' generated ', CAST(ROUND(visits_l6m) AS STRING), ' L6M visits, ',
      CAST(ROUND(COALESCE(cvr_l6m, 0) * 100, 1) AS STRING), '% CVR, and $',
      CAST(ROUND(grs_l6m) AS STRING), ' L6M GRS. Primary flags: ',
      COALESCE(NULLIF(blocker_flags, ''), 'No major readiness flag'), '.'
    ) AS narrative,
    sku_recommended_action AS recommended_action,
    CAST(visits_l6m AS FLOAT64),
    cvr_l6m,
    CAST(grs_l6m AS FLOAT64),
    orders_l6m,
    CAST(NULL AS INT64) AS total_skus,
    CAST(NULL AS INT64) AS live_skus,
    CAST(sponsored_product_spend_l6m AS FLOAT64),
    five_plus_review_coverage,
    recommended_tag_coverage,
    current_availability,
    current_remorse_return_rate,
    current_mrpi,
    current_wsi,
    COALESCE(NULLIF(blocker_flags, ''), 'No major readiness flag') AS blocker_flags
  FROM ranked_skus
  WHERE opportunity_rank <= 20
)

SELECT *
FROM output_rows
ORDER BY sort_order;
