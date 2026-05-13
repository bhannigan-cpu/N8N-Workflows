-- Visionary Amazon winner review for Wayfair
-- Focus: requested Amazon-winning parts that rank outside the top 40 on Wayfair.
WITH params AS (
  SELECT
    78708 AS supplier_id,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS current_month_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -6 MONTH) AS lookback_start,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS lookback_end,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -3 MONTH) AS recent_3m_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -6 MONTH) AS prior_3m_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -1 MONTH) AS latest_closed_month_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -2 MONTH) AS prior_closed_month_start
),

input_parts AS (
  SELECT part_number
  FROM UNNEST([
    '709690137316',
    '721410948293',
    '709690137323',
    '721410948309',
    '709690137330',
    'CL009LBF084',
    'CL009LBF096',
    'CL009LBF108',
    'CL009LBF090',
    'CL009LBF102',
    '721410948200',
    '721410948217',
    '721410948224',
    '721410948316',
    '721410948323',
    '709690137163',
    '704287184254',
    '709690137170',
    '704287184261',
    '709690137187',
    'CL016PWBT084',
    'CL016PWBT090',
    'CL016PWBT096',
    'CL016PWBT102',
    'CL016PWBT108',
    'CL017JSP084',
    'CL017JSP090',
    'CL017JSP096',
    'CL017JSP102',
    'CL017JSP108',
    '721410948019',
    '721410948026',
    '721410948033',
    '721410948491',
    '721410948507'
  ]) AS part_number
),

currency AS (
  SELECT ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

catalog_rows AS (
  SELECT DISTINCT
    DATE_TRUNC(retail_sku_store_date.date, MONTH) AS month_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    UPPER(TRIM(supplier_part_struct.supplierpartnumber)) AS part_number
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.agg_level = 'MONTHLY'
    AND retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND retail_sku_store_date.date >= params.lookback_start
    AND retail_sku_store_date.date < params.lookback_end
    AND supplier_part_struct.supplierpartnumber IS NOT NULL
    AND TRIM(supplier_part_struct.supplierpartnumber) <> ''
),

part_catalog AS (
  SELECT
    supplier_id,
    ANY_VALUE(supplier_name) AS supplier_name,
    part_number,
    COUNT(DISTINCT month_start) AS catalog_months
  FROM catalog_rows
  GROUP BY supplier_id, part_number
),

sales_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, MONTH) AS month_start,
    retail_dim_supplier.origsuid AS supplier_id,
    UPPER(TRIM(supplier_part_struct.supplierpartnumber)) AS part_number,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs,
    COALESCE(orders.productcostnorebates, 0) * COALESCE(currency.exchange_rate, 1) AS product_cost
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_sku_store_date.agg_level = 'MONTHLY'
    AND retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND retail_sku_store_date.date >= params.lookback_start
    AND retail_sku_store_date.date < params.lookback_end
    AND supplier_part_struct.supplierpartnumber IS NOT NULL
    AND TRIM(supplier_part_struct.supplierpartnumber) <> ''
),

deduped_orders AS (
  SELECT
    month_start,
    supplier_id,
    part_number,
    order_id,
    MAX(grs) AS grs,
    MAX(product_cost) AS product_cost
  FROM sales_rows
  GROUP BY month_start, supplier_id, part_number, order_id
),

part_sales AS (
  SELECT
    deduped_orders.supplier_id,
    deduped_orders.part_number,
    SUM(deduped_orders.grs) AS l6m_grs,
    SUM(deduped_orders.product_cost) AS l6m_product_cost,
    COUNT(DISTINCT deduped_orders.order_id) AS l6m_order_count,
    COUNT(DISTINCT IF(deduped_orders.grs > 0, deduped_orders.month_start, NULL)) AS selling_months,
    SUM(IF(deduped_orders.month_start = params.latest_closed_month_start, deduped_orders.grs, 0)) AS latest_month_grs,
    SUM(IF(deduped_orders.month_start = params.prior_closed_month_start, deduped_orders.grs, 0)) AS prior_month_grs,
    SUM(IF(deduped_orders.month_start >= params.recent_3m_start, deduped_orders.grs, 0)) AS recent_3m_grs,
    SUM(IF(deduped_orders.month_start >= params.prior_3m_start AND deduped_orders.month_start < params.recent_3m_start, deduped_orders.grs, 0)) AS prior_3m_grs,
    COUNT(DISTINCT IF(deduped_orders.month_start = params.latest_closed_month_start, deduped_orders.order_id, NULL)) AS latest_month_orders,
    COUNT(DISTINCT IF(deduped_orders.month_start = params.prior_closed_month_start, deduped_orders.order_id, NULL)) AS prior_month_orders,
    COUNT(DISTINCT IF(deduped_orders.month_start >= params.recent_3m_start, deduped_orders.order_id, NULL)) AS recent_3m_orders,
    COUNT(DISTINCT IF(deduped_orders.month_start >= params.prior_3m_start AND deduped_orders.month_start < params.recent_3m_start, deduped_orders.order_id, NULL)) AS prior_3m_orders
  FROM deduped_orders
  CROSS JOIN params
  GROUP BY deduped_orders.supplier_id, deduped_orders.part_number
),

traffic_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, MONTH) AS month_start,
    retail_dim_supplier.origsuid AS supplier_id,
    UPPER(TRIM(supplier_part_struct.supplierpartnumber)) AS part_number,
    traffic_source.id AS traffic_id,
    COALESCE(traffic_source.skuvisits, 0) AS visits,
    COALESCE(traffic_source.skuconverted, 0) AS converted
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.agg_level = 'MONTHLY'
    AND retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND retail_sku_store_date.date >= params.lookback_start
    AND retail_sku_store_date.date < params.lookback_end
    AND supplier_part_struct.supplierpartnumber IS NOT NULL
    AND TRIM(supplier_part_struct.supplierpartnumber) <> ''
),

deduped_traffic AS (
  SELECT
    month_start,
    supplier_id,
    part_number,
    traffic_id,
    MAX(visits) AS visits,
    MAX(converted) AS converted
  FROM traffic_rows
  GROUP BY month_start, supplier_id, part_number, traffic_id
),

part_traffic AS (
  SELECT
    deduped_traffic.supplier_id,
    deduped_traffic.part_number,
    SUM(deduped_traffic.visits) AS l6m_visits,
    SUM(deduped_traffic.converted) AS l6m_converted,
    SUM(IF(deduped_traffic.month_start = params.latest_closed_month_start, deduped_traffic.visits, 0)) AS latest_month_visits,
    SUM(IF(deduped_traffic.month_start = params.prior_closed_month_start, deduped_traffic.visits, 0)) AS prior_month_visits,
    SUM(IF(deduped_traffic.month_start >= params.recent_3m_start, deduped_traffic.visits, 0)) AS recent_3m_visits,
    SUM(IF(deduped_traffic.month_start >= params.prior_3m_start AND deduped_traffic.month_start < params.recent_3m_start, deduped_traffic.visits, 0)) AS prior_3m_visits,
    SUM(IF(deduped_traffic.month_start = params.latest_closed_month_start, deduped_traffic.converted, 0)) AS latest_month_converted,
    SUM(IF(deduped_traffic.month_start = params.prior_closed_month_start, deduped_traffic.converted, 0)) AS prior_month_converted,
    SUM(IF(deduped_traffic.month_start >= params.recent_3m_start, deduped_traffic.converted, 0)) AS recent_3m_converted,
    SUM(IF(deduped_traffic.month_start >= params.prior_3m_start AND deduped_traffic.month_start < params.recent_3m_start, deduped_traffic.converted, 0)) AS prior_3m_converted
  FROM deduped_traffic
  CROSS JOIN params
  GROUP BY deduped_traffic.supplier_id, deduped_traffic.part_number
),

availability_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, MONTH) AS month_start,
    retail_dim_supplier.origsuid AS supplier_id,
    UPPER(TRIM(supplier_part_struct.supplierpartnumber)) AS part_number,
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
  WHERE retail_sku_store_date.agg_level = 'MONTHLY'
    AND retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.origsuid = params.supplier_id
    AND retail_sku_store_date.date >= params.lookback_start
    AND retail_sku_store_date.date < params.lookback_end
    AND supplier_part_struct.supplierpartnumber IS NOT NULL
    AND TRIM(supplier_part_struct.supplierpartnumber) <> ''
),

deduped_availability AS (
  SELECT
    month_start,
    supplier_id,
    part_number,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom
  FROM availability_rows
  GROUP BY month_start, supplier_id, part_number, ops_id
),

part_availability AS (
  SELECT
    deduped_availability.supplier_id,
    deduped_availability.part_number,
    SAFE_DIVIDE(SUM(deduped_availability.availability_num), NULLIF(SUM(deduped_availability.availability_denom), 0)) AS l6m_availability,
    SAFE_DIVIDE(
      SUM(IF(deduped_availability.month_start = params.latest_closed_month_start, deduped_availability.availability_num, 0)),
      NULLIF(SUM(IF(deduped_availability.month_start = params.latest_closed_month_start, deduped_availability.availability_denom, 0)), 0)
    ) AS latest_month_availability,
    SAFE_DIVIDE(
      SUM(IF(deduped_availability.month_start = params.prior_closed_month_start, deduped_availability.availability_num, 0)),
      NULLIF(SUM(IF(deduped_availability.month_start = params.prior_closed_month_start, deduped_availability.availability_denom, 0)), 0)
    ) AS prior_month_availability,
    SAFE_DIVIDE(
      SUM(IF(deduped_availability.month_start >= params.recent_3m_start, deduped_availability.availability_num, 0)),
      NULLIF(SUM(IF(deduped_availability.month_start >= params.recent_3m_start, deduped_availability.availability_denom, 0)), 0)
    ) AS recent_3m_availability,
    SAFE_DIVIDE(
      SUM(IF(deduped_availability.month_start >= params.prior_3m_start AND deduped_availability.month_start < params.recent_3m_start, deduped_availability.availability_num, 0)),
      NULLIF(SUM(IF(deduped_availability.month_start >= params.prior_3m_start AND deduped_availability.month_start < params.recent_3m_start, deduped_availability.availability_denom, 0)), 0)
    ) AS prior_3m_availability
  FROM deduped_availability
  CROSS JOIN params
  GROUP BY deduped_availability.supplier_id, deduped_availability.part_number
),

part_summary AS (
  SELECT
    part_catalog.supplier_id,
    part_catalog.supplier_name,
    part_catalog.part_number,
    part_catalog.catalog_months,
    COALESCE(part_sales.l6m_grs, 0) AS l6m_grs,
    COALESCE(part_sales.l6m_product_cost, 0) AS l6m_product_cost,
    COALESCE(part_sales.l6m_order_count, 0) AS l6m_order_count,
    COALESCE(part_sales.selling_months, 0) AS selling_months,
    COALESCE(part_sales.latest_month_grs, 0) AS latest_month_grs,
    COALESCE(part_sales.prior_month_grs, 0) AS prior_month_grs,
    COALESCE(part_sales.recent_3m_grs, 0) AS recent_3m_grs,
    COALESCE(part_sales.prior_3m_grs, 0) AS prior_3m_grs,
    COALESCE(part_sales.latest_month_orders, 0) AS latest_month_orders,
    COALESCE(part_sales.prior_month_orders, 0) AS prior_month_orders,
    COALESCE(part_sales.recent_3m_orders, 0) AS recent_3m_orders,
    COALESCE(part_sales.prior_3m_orders, 0) AS prior_3m_orders,
    COALESCE(part_traffic.l6m_visits, 0) AS l6m_visits,
    COALESCE(part_traffic.l6m_converted, 0) AS l6m_converted,
    COALESCE(part_traffic.latest_month_visits, 0) AS latest_month_visits,
    COALESCE(part_traffic.prior_month_visits, 0) AS prior_month_visits,
    COALESCE(part_traffic.recent_3m_visits, 0) AS recent_3m_visits,
    COALESCE(part_traffic.prior_3m_visits, 0) AS prior_3m_visits,
    COALESCE(part_traffic.latest_month_converted, 0) AS latest_month_converted,
    COALESCE(part_traffic.prior_month_converted, 0) AS prior_month_converted,
    COALESCE(part_traffic.recent_3m_converted, 0) AS recent_3m_converted,
    COALESCE(part_traffic.prior_3m_converted, 0) AS prior_3m_converted,
    part_availability.l6m_availability,
    part_availability.latest_month_availability,
    part_availability.prior_month_availability,
    part_availability.recent_3m_availability,
    part_availability.prior_3m_availability,
    SAFE_DIVIDE(COALESCE(part_traffic.l6m_converted, 0), NULLIF(COALESCE(part_traffic.l6m_visits, 0), 0)) AS l6m_cvr,
    SAFE_DIVIDE(COALESCE(part_traffic.latest_month_converted, 0), NULLIF(COALESCE(part_traffic.latest_month_visits, 0), 0)) AS latest_month_cvr,
    SAFE_DIVIDE(COALESCE(part_traffic.prior_month_converted, 0), NULLIF(COALESCE(part_traffic.prior_month_visits, 0), 0)) AS prior_month_cvr,
    SAFE_DIVIDE(COALESCE(part_traffic.recent_3m_converted, 0), NULLIF(COALESCE(part_traffic.recent_3m_visits, 0), 0)) AS recent_3m_cvr,
    SAFE_DIVIDE(COALESCE(part_traffic.prior_3m_converted, 0), NULLIF(COALESCE(part_traffic.prior_3m_visits, 0), 0)) AS prior_3m_cvr
  FROM part_catalog
  LEFT JOIN part_sales
    ON part_sales.supplier_id = part_catalog.supplier_id
    AND part_sales.part_number = part_catalog.part_number
  LEFT JOIN part_traffic
    ON part_traffic.supplier_id = part_catalog.supplier_id
    AND part_traffic.part_number = part_catalog.part_number
  LEFT JOIN part_availability
    ON part_availability.supplier_id = part_catalog.supplier_id
    AND part_availability.part_number = part_catalog.part_number
),

ranked_parts AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY l6m_grs DESC, l6m_order_count DESC, part_number) AS sales_rank
  FROM part_summary
),

top_40_benchmarks AS (
  SELECT
    COUNTIF(sales_rank <= 40) AS top_40_part_count,
    MIN(IF(sales_rank <= 40, l6m_grs, NULL)) AS top_40_floor_grs,
    MIN(IF(sales_rank <= 40, l6m_order_count, NULL)) AS top_40_floor_orders,
    AVG(IF(sales_rank <= 40, l6m_visits, NULL)) AS top_40_avg_visits,
    AVG(IF(sales_rank <= 40, l6m_cvr, NULL)) AS top_40_avg_cvr,
    AVG(IF(sales_rank <= 40, l6m_availability, NULL)) AS top_40_avg_availability,
    AVG(IF(sales_rank <= 40, l6m_product_cost, NULL)) AS top_40_avg_product_cost
  FROM ranked_parts
),

requested_parts AS (
  SELECT
    input_parts.part_number AS requested_part_number,
    ranked_parts.*,
    CASE
      WHEN ranked_parts.part_number IS NULL THEN 'NOT_FOUND'
      ELSE 'MATCHED'
    END AS match_status
  FROM input_parts
  LEFT JOIN ranked_parts
    ON ranked_parts.part_number = input_parts.part_number
),

exception_analysis AS (
  SELECT
    requested_parts.requested_part_number,
    requested_parts.match_status,
    requested_parts.supplier_name,
    requested_parts.part_number AS matched_part_number,
    requested_parts.sales_rank,
    CASE
      WHEN requested_parts.match_status = 'NOT_FOUND' THEN 'No Wayfair match'
      WHEN requested_parts.sales_rank <= 40 THEN 'Top 40'
      ELSE 'Outside Top 40'
    END AS top_40_status,
    requested_parts.catalog_months,
    requested_parts.selling_months,
    requested_parts.l6m_grs,
    requested_parts.l6m_product_cost,
    requested_parts.l6m_order_count,
    requested_parts.l6m_visits,
    requested_parts.l6m_cvr,
    requested_parts.l6m_availability,
    requested_parts.latest_month_grs,
    requested_parts.prior_month_grs,
    SAFE_DIVIDE(requested_parts.latest_month_grs - requested_parts.prior_month_grs, NULLIF(requested_parts.prior_month_grs, 0)) AS mom_grs_pct,
    requested_parts.recent_3m_grs,
    requested_parts.prior_3m_grs,
    SAFE_DIVIDE(requested_parts.recent_3m_grs - requested_parts.prior_3m_grs, NULLIF(requested_parts.prior_3m_grs, 0)) AS recent_3m_grs_pct,
    requested_parts.recent_3m_orders,
    requested_parts.prior_3m_orders,
    SAFE_DIVIDE(requested_parts.recent_3m_orders - requested_parts.prior_3m_orders, NULLIF(requested_parts.prior_3m_orders, 0)) AS recent_3m_orders_pct,
    requested_parts.recent_3m_visits,
    requested_parts.prior_3m_visits,
    SAFE_DIVIDE(requested_parts.recent_3m_visits - requested_parts.prior_3m_visits, NULLIF(requested_parts.prior_3m_visits, 0)) AS recent_3m_visits_pct,
    requested_parts.recent_3m_cvr,
    requested_parts.prior_3m_cvr,
    (requested_parts.recent_3m_cvr - requested_parts.prior_3m_cvr) * 10000 AS recent_3m_cvr_bps,
    requested_parts.latest_month_availability,
    requested_parts.prior_month_availability,
    requested_parts.recent_3m_availability,
    requested_parts.prior_3m_availability,
    top_40_benchmarks.top_40_floor_grs,
    top_40_benchmarks.top_40_floor_orders,
    top_40_benchmarks.top_40_avg_visits,
    top_40_benchmarks.top_40_avg_cvr,
    top_40_benchmarks.top_40_avg_availability,
    top_40_benchmarks.top_40_avg_product_cost,
    requested_parts.l6m_grs - top_40_benchmarks.top_40_floor_grs AS grs_gap_to_top_40,
    requested_parts.l6m_order_count - top_40_benchmarks.top_40_floor_orders AS orders_gap_to_top_40,
    SAFE_DIVIDE(requested_parts.l6m_visits - top_40_benchmarks.top_40_avg_visits, NULLIF(top_40_benchmarks.top_40_avg_visits, 0)) AS visits_gap_pct_to_top_40_avg,
    (requested_parts.l6m_cvr - top_40_benchmarks.top_40_avg_cvr) * 10000 AS cvr_gap_bps_to_top_40_avg,
    (requested_parts.l6m_availability - top_40_benchmarks.top_40_avg_availability) * 10000 AS availability_gap_bps_to_top_40_avg,
    CASE
      WHEN requested_parts.match_status = 'NOT_FOUND' THEN 100
      ELSE 0
    END
    + CASE
      WHEN requested_parts.sales_rank > 100 THEN 30
      WHEN requested_parts.sales_rank > 70 THEN 22
      WHEN requested_parts.sales_rank > 40 THEN 14
      ELSE 0
    END
    + CASE
      WHEN SAFE_DIVIDE(requested_parts.recent_3m_grs - requested_parts.prior_3m_grs, NULLIF(requested_parts.prior_3m_grs, 0)) <= -0.40 THEN 20
      WHEN SAFE_DIVIDE(requested_parts.recent_3m_grs - requested_parts.prior_3m_grs, NULLIF(requested_parts.prior_3m_grs, 0)) <= -0.20 THEN 10
      ELSE 0
    END
    + CASE
      WHEN SAFE_DIVIDE(requested_parts.recent_3m_orders - requested_parts.prior_3m_orders, NULLIF(requested_parts.prior_3m_orders, 0)) <= -0.30 THEN 12
      ELSE 0
    END
    + CASE
      WHEN SAFE_DIVIDE(requested_parts.recent_3m_visits - requested_parts.prior_3m_visits, NULLIF(requested_parts.prior_3m_visits, 0)) <= -0.25 THEN 12
      ELSE 0
    END
    + CASE
      WHEN (requested_parts.recent_3m_cvr - requested_parts.prior_3m_cvr) * 10000 <= -75 THEN 12
      ELSE 0
    END
    + CASE
      WHEN requested_parts.l6m_availability IS NOT NULL
        AND requested_parts.l6m_availability < 0.90
        AND (requested_parts.l6m_availability - top_40_benchmarks.top_40_avg_availability) * 10000 <= -200
      THEN 16
      ELSE 0
    END
    + CASE
      WHEN requested_parts.l6m_product_cost > top_40_benchmarks.top_40_avg_product_cost * 1.10
        AND (requested_parts.l6m_cvr - top_40_benchmarks.top_40_avg_cvr) * 10000 < -50
      THEN 8
      ELSE 0
    END AS issue_score
  FROM requested_parts
  CROSS JOIN top_40_benchmarks
),

final_exceptions AS (
  SELECT
    *,
    CASE
      WHEN match_status = 'NOT_FOUND' THEN 'No Wayfair mapping found'
      WHEN l6m_availability IS NOT NULL
        AND l6m_availability < 0.90
        AND availability_gap_bps_to_top_40_avg <= -200
      THEN 'Availability is the main constraint'
      WHEN recent_3m_visits_pct <= -0.25 AND recent_3m_cvr_bps <= -75
      THEN 'Traffic and conversion are both down'
      WHEN recent_3m_visits_pct <= -0.25
      THEN 'Traffic is down materially'
      WHEN recent_3m_cvr_bps <= -75
      THEN 'Conversion is down materially'
      WHEN l6m_product_cost > top_40_avg_product_cost * 1.10
        AND cvr_gap_bps_to_top_40_avg < -50
      THEN 'Price or value positioning looks weak'
      WHEN recent_3m_grs_pct <= -0.20 AND recent_3m_orders_pct <= -0.20
      THEN 'Demand has deteriorated'
      ELSE 'Below the top-40 Wayfair bar without one dominant failure mode'
    END AS primary_issue,
    ARRAY_TO_STRING(
      ARRAY(
        SELECT metric
        FROM UNNEST([
          CASE WHEN sales_rank > 40 THEN 'Wayfair sales rank outside top 40' END,
          CASE WHEN grs_gap_to_top_40 < 0 THEN 'L6M GRS below the top-40 floor' END,
          CASE WHEN recent_3m_grs_pct <= -0.20 THEN 'GRS down in the last 3 months' END,
          CASE WHEN recent_3m_orders_pct <= -0.20 THEN 'Orders down in the last 3 months' END,
          CASE WHEN recent_3m_visits_pct <= -0.25 THEN 'Visits down in the last 3 months' END,
          CASE WHEN recent_3m_cvr_bps <= -75 THEN 'CVR down in the last 3 months' END,
          CASE WHEN l6m_availability IS NOT NULL AND l6m_availability < 0.90 THEN 'Availability below target' END,
          CASE WHEN cvr_gap_bps_to_top_40_avg <= -50 THEN 'CVR below the top-40 average' END,
          CASE WHEN visits_gap_pct_to_top_40_avg <= -0.20 THEN 'Visits below the top-40 average' END,
          CASE WHEN l6m_product_cost > top_40_avg_product_cost * 1.10 THEN 'Product cost above the top-40 average' END
        ]) AS metric
        WHERE metric IS NOT NULL
      ),
      '; '
    ) AS slacking_metrics,
    ARRAY_TO_STRING(
      ARRAY(
        SELECT reason
        FROM UNNEST([
          CASE
            WHEN match_status = 'NOT_FOUND'
            THEN 'The supplied part number did not map to a Visionary supplier part number in the Wayfair retail fact table.'
          END,
          CASE
            WHEN sales_rank > 40 AND grs_gap_to_top_40 < 0
            THEN FORMAT('This part ranks %d on Wayfair and sits $%.0f below the current top-40 revenue floor.', sales_rank, ABS(grs_gap_to_top_40))
          END,
          CASE
            WHEN recent_3m_grs_pct <= -0.20
            THEN FORMAT('Revenue is down %.1f%% in the last 3 months versus the prior 3 months.', ABS(recent_3m_grs_pct) * 100)
          END,
          CASE
            WHEN recent_3m_orders_pct <= -0.20
            THEN FORMAT('Orders are down %.1f%% over the same comparison window.', ABS(recent_3m_orders_pct) * 100)
          END,
          CASE
            WHEN recent_3m_visits_pct <= -0.25
            THEN FORMAT('Visits are down %.1f%%, so traffic erosion is part of the story.', ABS(recent_3m_visits_pct) * 100)
          END,
          CASE
            WHEN recent_3m_cvr_bps <= -75
            THEN FORMAT('CVR is down %.0f bps, so the PDP or offer is converting worse than it did previously.', ABS(recent_3m_cvr_bps))
          END,
          CASE
            WHEN l6m_availability IS NOT NULL AND l6m_availability < 0.90 AND availability_gap_bps_to_top_40_avg <= -200
            THEN FORMAT('Availability is %.1f%%, which trails the top-40 average by %.0f bps and likely limits demand capture.', l6m_availability * 100, ABS(availability_gap_bps_to_top_40_avg))
          END,
          CASE
            WHEN l6m_product_cost > top_40_avg_product_cost * 1.10 AND cvr_gap_bps_to_top_40_avg < -50
            THEN 'Product cost is elevated relative to the top-40 set while conversion lags, which can indicate a price or value problem.'
          END,
          CASE
            WHEN recent_3m_visits_pct > -0.10 AND recent_3m_cvr_bps <= -75
            THEN 'Traffic is not collapsing, so the weaker performance is more likely a conversion problem than a traffic problem.'
          END,
          CASE
            WHEN recent_3m_visits_pct <= -0.25 AND recent_3m_cvr_bps > -50
            THEN 'Conversion is relatively stable, so the main problem appears to be traffic loss rather than offer quality.'
          END
        ]) AS reason
        WHERE reason IS NOT NULL
      ),
      ' '
    ) AS why_it_might_be_slacking
  FROM exception_analysis
)

SELECT
  requested_part_number,
  sales_rank AS wayfair_l6m_sales_rank,
  top_40_status,
  ROUND(l6m_grs, 0) AS l6m_grs_usd,
  l6m_order_count,
  ROUND(l6m_visits, 0) AS l6m_visits,
  ROUND(l6m_cvr * 100, 2) AS l6m_cvr_pct,
  ROUND(l6m_availability * 100, 2) AS l6m_availability_pct,
  ROUND(top_40_floor_grs, 0) AS top_40_floor_grs_usd,
  ROUND(grs_gap_to_top_40, 0) AS gap_to_top_40_grs_usd,
  ROUND(latest_month_grs, 0) AS latest_month_grs_usd,
  ROUND(prior_month_grs, 0) AS prior_month_grs_usd,
  ROUND(mom_grs_pct * 100, 1) AS mom_grs_pct,
  ROUND(recent_3m_grs, 0) AS recent_3m_grs_usd,
  ROUND(prior_3m_grs, 0) AS prior_3m_grs_usd,
  ROUND(recent_3m_grs_pct * 100, 1) AS recent_3m_grs_change_pct,
  ROUND(recent_3m_orders_pct * 100, 1) AS recent_3m_orders_change_pct,
  ROUND(recent_3m_visits_pct * 100, 1) AS recent_3m_visits_change_pct,
  ROUND(recent_3m_cvr_bps, 0) AS recent_3m_cvr_change_bps,
  ROUND(cvr_gap_bps_to_top_40_avg, 0) AS cvr_gap_to_top_40_avg_bps,
  ROUND(availability_gap_bps_to_top_40_avg, 0) AS availability_gap_to_top_40_avg_bps,
  ROUND(visits_gap_pct_to_top_40_avg * 100, 1) AS visits_gap_to_top_40_avg_pct,
  issue_score,
  primary_issue,
  slacking_metrics,
  why_it_might_be_slacking
FROM final_exceptions
WHERE match_status = 'NOT_FOUND' OR sales_rank > 40
ORDER BY issue_score DESC, wayfair_l6m_sales_rank, requested_part_number;
