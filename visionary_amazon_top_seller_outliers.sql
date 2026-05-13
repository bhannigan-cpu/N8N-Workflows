-- Visionary Amazon winners that are not top 35 on Wayfair
-- Output: visits, CVR, L6M wholesale cost-no-rebates, availability,
-- and which of those metrics appears to be hurting the most.
WITH params AS (
  SELECT
    78708 AS supplier_id,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -5 MONTH) AS lookback_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH) AS lookback_end
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
    part_number
  FROM catalog_rows
  GROUP BY supplier_id, part_number
),

sales_rows AS (
  SELECT
    retail_dim_supplier.origsuid AS supplier_id,
    UPPER(TRIM(supplier_part_struct.supplierpartnumber)) AS part_number,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs,
    COALESCE(orders.productcostnorebates, 0) * COALESCE(currency.exchange_rate, 1) AS wholesale_cost_no_rebates
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
    supplier_id,
    part_number,
    order_id,
    MAX(grs) AS grs,
    MAX(wholesale_cost_no_rebates) AS wholesale_cost_no_rebates
  FROM sales_rows
  GROUP BY supplier_id, part_number, order_id
),

part_sales AS (
  SELECT
    deduped_orders.supplier_id,
    deduped_orders.part_number,
    SUM(deduped_orders.grs) AS l6m_grs,
    SUM(deduped_orders.wholesale_cost_no_rebates) AS l6m_wholesale_cost_no_rebates,
    COUNT(DISTINCT deduped_orders.order_id) AS l6m_order_count
  FROM deduped_orders
  GROUP BY deduped_orders.supplier_id, deduped_orders.part_number
),

traffic_rows AS (
  SELECT
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
    supplier_id,
    part_number,
    traffic_id,
    MAX(visits) AS visits,
    MAX(converted) AS converted
  FROM traffic_rows
  GROUP BY supplier_id, part_number, traffic_id
),

part_traffic AS (
  SELECT
    deduped_traffic.supplier_id,
    deduped_traffic.part_number,
    SUM(deduped_traffic.visits) AS l6m_visits,
    SUM(deduped_traffic.converted) AS l6m_converted,
    SAFE_DIVIDE(SUM(deduped_traffic.converted), NULLIF(SUM(deduped_traffic.visits), 0)) AS l6m_cvr
  FROM deduped_traffic
  GROUP BY deduped_traffic.supplier_id, deduped_traffic.part_number
),

availability_rows AS (
  SELECT
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
    supplier_id,
    part_number,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom
  FROM availability_rows
  GROUP BY supplier_id, part_number, ops_id
),

part_availability AS (
  SELECT
    deduped_availability.supplier_id,
    deduped_availability.part_number,
    SAFE_DIVIDE(SUM(deduped_availability.availability_num), NULLIF(SUM(deduped_availability.availability_denom), 0)) AS l6m_availability
  FROM deduped_availability
  GROUP BY deduped_availability.supplier_id, deduped_availability.part_number
),

part_summary AS (
  SELECT
    part_catalog.supplier_id,
    part_catalog.supplier_name,
    part_catalog.part_number,
    COALESCE(part_sales.l6m_grs, 0) AS l6m_grs,
    COALESCE(part_sales.l6m_wholesale_cost_no_rebates, 0) AS l6m_wholesale_cost_no_rebates,
    COALESCE(part_sales.l6m_order_count, 0) AS l6m_order_count,
    COALESCE(part_traffic.l6m_visits, 0) AS l6m_visits,
    CAST(NULL AS FLOAT64) AS l6m_cvr,
    part_availability.l6m_availability
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

top_35_benchmarks AS (
  SELECT
    AVG(IF(sales_rank <= 35, l6m_visits, NULL)) AS top_35_avg_visits,
    CAST(NULL AS FLOAT64) AS top_35_avg_cvr,
    AVG(IF(sales_rank <= 35, l6m_wholesale_cost_no_rebates, NULL)) AS top_35_avg_wholesale_cost_no_rebates,
    AVG(IF(sales_rank <= 35, l6m_availability, NULL)) AS top_35_avg_availability
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

scored_parts AS (
  SELECT
    requested_parts.requested_part_number,
    requested_parts.match_status,
    requested_parts.part_number AS matched_part_number,
    requested_parts.sales_rank,
    requested_parts.l6m_grs,
    requested_parts.l6m_visits,
    requested_parts.l6m_cvr,
    requested_parts.l6m_wholesale_cost_no_rebates,
    requested_parts.l6m_availability,
    top_35_benchmarks.top_35_avg_visits,
    top_35_benchmarks.top_35_avg_cvr,
    top_35_benchmarks.top_35_avg_wholesale_cost_no_rebates,
    top_35_benchmarks.top_35_avg_availability,
    SAFE_DIVIDE(requested_parts.l6m_visits - top_35_benchmarks.top_35_avg_visits, NULLIF(top_35_benchmarks.top_35_avg_visits, 0)) AS visits_gap_pct_to_top_35_avg,
    CAST(NULL AS FLOAT64) AS cvr_gap_bps_to_top_35_avg,
    SAFE_DIVIDE(requested_parts.l6m_wholesale_cost_no_rebates - top_35_benchmarks.top_35_avg_wholesale_cost_no_rebates, NULLIF(top_35_benchmarks.top_35_avg_wholesale_cost_no_rebates, 0)) AS wholesale_cost_gap_pct_to_top_35_avg,
    (requested_parts.l6m_availability - top_35_benchmarks.top_35_avg_availability) * 10000 AS availability_gap_bps_to_top_35_avg,
    GREATEST(-COALESCE(SAFE_DIVIDE(requested_parts.l6m_visits - top_35_benchmarks.top_35_avg_visits, NULLIF(top_35_benchmarks.top_35_avg_visits, 0)), 0), 0) AS visits_hurt_score,
    0 AS cvr_hurt_score,
    GREATEST(COALESCE(SAFE_DIVIDE(requested_parts.l6m_wholesale_cost_no_rebates - top_35_benchmarks.top_35_avg_wholesale_cost_no_rebates, NULLIF(top_35_benchmarks.top_35_avg_wholesale_cost_no_rebates, 0)), 0), 0) AS wholesale_cost_hurt_score,
    GREATEST(-COALESCE(SAFE_DIVIDE(requested_parts.l6m_availability - top_35_benchmarks.top_35_avg_availability, NULLIF(top_35_benchmarks.top_35_avg_availability, 0)), 0), 0) AS availability_hurt_score
  FROM requested_parts
  CROSS JOIN top_35_benchmarks
),

final_output AS (
  SELECT
    *,
    CASE
      WHEN match_status = 'NOT_FOUND' THEN ''
      WHEN GREATEST(visits_hurt_score, cvr_hurt_score, wholesale_cost_hurt_score, availability_hurt_score) = 0 THEN ''
      WHEN visits_hurt_score >= cvr_hurt_score
        AND visits_hurt_score >= wholesale_cost_hurt_score
        AND visits_hurt_score >= availability_hurt_score
      THEN 'Visits'
      WHEN cvr_hurt_score >= wholesale_cost_hurt_score
        AND cvr_hurt_score >= availability_hurt_score
      THEN 'CVR'
      WHEN wholesale_cost_hurt_score >= availability_hurt_score
      THEN 'Wholesale cost no rebates'
      ELSE 'Availability'
    END AS hurting_most_metric,
    CASE
      WHEN match_status = 'NOT_FOUND' THEN 'No Wayfair match found for this part number.'
      WHEN GREATEST(visits_hurt_score, cvr_hurt_score, wholesale_cost_hurt_score, availability_hurt_score) = 0 THEN ''
      WHEN visits_hurt_score >= cvr_hurt_score
        AND visits_hurt_score >= wholesale_cost_hurt_score
        AND visits_hurt_score >= availability_hurt_score
      THEN FORMAT('Visits are %.1f%% below the current top-35 average.', ABS(visits_gap_pct_to_top_35_avg) * 100)
      WHEN cvr_hurt_score >= wholesale_cost_hurt_score
        AND cvr_hurt_score >= availability_hurt_score
      THEN FORMAT('CVR is %.0f bps below the current top-35 average.', ABS(cvr_gap_bps_to_top_35_avg))
      WHEN wholesale_cost_hurt_score >= availability_hurt_score
      THEN FORMAT('Wholesale cost no rebates is %.1f%% above the current top-35 average.', ABS(wholesale_cost_gap_pct_to_top_35_avg) * 100)
      ELSE FORMAT('Availability is %.0f bps below the current top-35 average.', ABS(availability_gap_bps_to_top_35_avg))
    END AS hurting_most_reason
  FROM scored_parts
)

SELECT
  requested_part_number AS `Part Number`,
  sales_rank AS `Catalog Rank`,
  ROUND(l6m_visits, 0) AS `Visits`,
  ROUND(l6m_cvr, 2) AS `Conv Rate`,
  ROUND(l6m_grs, 0) AS `Sales`,
  ROUND(l6m_availability * 100, 2) AS `Availability`,
  hurting_most_metric AS `Hurting Most`,
  hurting_most_reason AS `Reason`
FROM final_output
ORDER BY
  CASE WHEN sales_rank IS NULL THEN 1 ELSE 0 END,
  sales_rank,
  requested_part_number;
