-- Rank Amazon-winning Visionary part numbers against the full Visionary catalog
-- and label which requested parts are underperforming.
WITH params AS (
  SELECT
    78708 AS supplier_id,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -5 MONTH) AS lookback_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH) AS lookback_end,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -2 MONTH) AS recent_window_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL -5 MONTH) AS prior_window_start
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
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate,
    ANY_VALUE(currency_symbol) AS currency_symbol
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

catalog_rows AS (
  SELECT DISTINCT
    DATE_TRUNC(retail_sku_store_date.date, MONTH) AS month_start,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name,
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
    supplier_id,
    part_number,
    SUM(grs) AS l6m_grs,
    SUM(product_cost) AS l6m_product_cost,
    COUNT(DISTINCT order_id) AS l6m_order_count,
    COUNT(DISTINCT IF(grs > 0, month_start, NULL)) AS selling_months,
    SUM(IF(month_start >= params.recent_window_start, grs, 0)) AS recent_3m_grs,
    SUM(IF(month_start >= params.prior_window_start AND month_start < params.recent_window_start, grs, 0)) AS prior_3m_grs
  FROM deduped_orders
  CROSS JOIN params
  GROUP BY supplier_id, part_number
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
    supplier_id,
    part_number,
    SUM(availability_num) AS availability_num,
    SUM(availability_denom) AS availability_denom,
    SAFE_DIVIDE(SUM(availability_num), NULLIF(SUM(availability_denom), 0)) AS l6m_availability
  FROM deduped_availability
  GROUP BY supplier_id, part_number
),

part_universe AS (
  SELECT
    catalog.supplier_id,
    catalog.supplier_name,
    catalog.part_number,
    catalog.catalog_months,
    COALESCE(sales.l6m_grs, 0) AS l6m_grs,
    COALESCE(sales.l6m_product_cost, 0) AS l6m_product_cost,
    COALESCE(sales.l6m_order_count, 0) AS l6m_order_count,
    COALESCE(sales.selling_months, 0) AS selling_months,
    COALESCE(sales.recent_3m_grs, 0) AS recent_3m_grs,
    COALESCE(sales.prior_3m_grs, 0) AS prior_3m_grs,
    availability.l6m_availability
  FROM part_catalog AS catalog
  LEFT JOIN part_sales AS sales
    ON sales.supplier_id = catalog.supplier_id
    AND sales.part_number = catalog.part_number
  LEFT JOIN part_availability AS availability
    ON availability.supplier_id = catalog.supplier_id
    AND availability.part_number = catalog.part_number
),

ranked_parts AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY l6m_grs DESC, l6m_order_count DESC, part_number) AS sales_rank
  FROM part_universe
),

supplier_stats AS (
  SELECT
    COUNT(*) AS supplier_part_count,
    APPROX_QUANTILES(l6m_grs, 100)[OFFSET(50)] AS supplier_median_grs,
    APPROX_QUANTILES(l6m_product_cost, 100)[OFFSET(50)] AS supplier_median_product_cost,
    APPROX_QUANTILES(COALESCE(l6m_availability, 0), 100)[OFFSET(50)] AS supplier_median_availability,
    APPROX_QUANTILES(l6m_order_count, 100)[OFFSET(50)] AS supplier_median_order_count
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

selected_stats AS (
  SELECT
    APPROX_QUANTILES(l6m_grs, 100)[OFFSET(50)] AS selected_median_grs,
    APPROX_QUANTILES(l6m_product_cost, 100)[OFFSET(50)] AS selected_median_product_cost,
    APPROX_QUANTILES(COALESCE(l6m_availability, 0), 100)[OFFSET(50)] AS selected_median_availability,
    APPROX_QUANTILES(l6m_order_count, 100)[OFFSET(50)] AS selected_median_order_count
  FROM requested_parts
  WHERE match_status = 'MATCHED'
),

scored_parts AS (
  SELECT
    requested_parts.requested_part_number,
    requested_parts.match_status,
    requested_parts.supplier_name,
    requested_parts.part_number AS matched_part_number,
    requested_parts.sales_rank,
    supplier_stats.supplier_part_count,
    SAFE_DIVIDE(requested_parts.sales_rank - 1, NULLIF(supplier_stats.supplier_part_count - 1, 0)) AS sales_rank_pct,
    requested_parts.l6m_grs,
    requested_parts.l6m_product_cost,
    requested_parts.l6m_order_count,
    requested_parts.selling_months,
    requested_parts.catalog_months,
    requested_parts.l6m_availability,
    requested_parts.recent_3m_grs,
    requested_parts.prior_3m_grs,
    SAFE_DIVIDE(requested_parts.recent_3m_grs - requested_parts.prior_3m_grs, NULLIF(requested_parts.prior_3m_grs, 0)) AS recent_3m_grs_delta_pct,
    supplier_stats.supplier_median_grs,
    supplier_stats.supplier_median_product_cost,
    supplier_stats.supplier_median_availability,
    supplier_stats.supplier_median_order_count,
    selected_stats.selected_median_grs,
    selected_stats.selected_median_product_cost,
    selected_stats.selected_median_availability,
    selected_stats.selected_median_order_count,
    CASE
      WHEN requested_parts.match_status = 'NOT_FOUND' THEN TRUE
      WHEN requested_parts.l6m_grs = 0 THEN TRUE
      WHEN SAFE_DIVIDE(requested_parts.sales_rank - 1, NULLIF(supplier_stats.supplier_part_count - 1, 0)) >= 0.75 THEN TRUE
      WHEN requested_parts.l6m_grs < COALESCE(selected_stats.selected_median_grs, supplier_stats.supplier_median_grs) * 0.50 THEN TRUE
      WHEN requested_parts.prior_3m_grs > 0 AND requested_parts.recent_3m_grs < requested_parts.prior_3m_grs * 0.60 THEN TRUE
      ELSE FALSE
    END AS is_outlier
  FROM requested_parts
  CROSS JOIN supplier_stats
  CROSS JOIN selected_stats
),

reasoned_parts AS (
  SELECT
    *,
    CASE
      WHEN match_status = 'NOT_FOUND' THEN 'catalog-match-issue'
      WHEN l6m_grs = 0 THEN 'no-sales'
      WHEN l6m_availability IS NOT NULL AND l6m_availability < 0.85 THEN 'availability-constrained'
      WHEN prior_3m_grs > 0 AND recent_3m_grs < prior_3m_grs * 0.60 THEN 'momentum-loss'
      WHEN l6m_availability IS NOT NULL AND l6m_availability >= 0.90 AND l6m_grs < COALESCE(selected_median_grs, supplier_median_grs) * 0.50 THEN 'traffic-or-conversion'
      WHEN l6m_product_cost > COALESCE(selected_median_product_cost, supplier_median_product_cost) * 1.25 THEN 'price-or-value'
      ELSE 'below-peer-benchmark'
    END AS outlier_bucket,
    ARRAY_TO_STRING(
      ARRAY(
        SELECT reason
        FROM UNNEST([
          CASE
            WHEN match_status = 'NOT_FOUND'
            THEN 'The part number did not match Visionary''s supplierpartnumber field in the retail fact table.'
          END,
          CASE
            WHEN match_status = 'MATCHED' AND l6m_grs = 0
            THEN 'No gross revenue was booked for this part in the last 6 months.'
          END,
          CASE
            WHEN match_status = 'MATCHED' AND l6m_availability IS NOT NULL AND l6m_availability < 0.85
            THEN FORMAT('Availability is only %.1f%% over the last 6 months, so in-stock problems are likely suppressing demand.', l6m_availability * 100)
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND l6m_availability IS NOT NULL
              AND supplier_median_availability IS NOT NULL
              AND l6m_availability < supplier_median_availability - 0.05
            THEN 'Availability trails the Visionary median, which makes this an inventory or fulfillment problem before it is a demand problem.'
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND prior_3m_grs > 0
              AND recent_3m_grs < prior_3m_grs * 0.60
            THEN 'Recent 3-month sales are materially below the prior 3 months, which signals momentum loss.'
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND l6m_availability IS NOT NULL
              AND l6m_availability >= 0.90
              AND l6m_grs < COALESCE(selected_median_grs, supplier_median_grs) * 0.50
            THEN 'Availability is healthy but sales still lag the Amazon-winner peer set, which points to traffic, conversion, content, or assortment issues.'
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND l6m_product_cost > COALESCE(selected_median_product_cost, supplier_median_product_cost) * 1.25
              AND l6m_grs < COALESCE(selected_median_grs, supplier_median_grs)
            THEN 'Product cost is above the peer median while revenue is below the peer median, which can indicate a price/value disadvantage.'
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND catalog_months >= 4
              AND selling_months <= 1
            THEN 'The part has been in the catalog for multiple months but has sold in one month or less, suggesting low demand or poor discoverability.'
          END,
          CASE
            WHEN match_status = 'MATCHED'
              AND sales_rank_pct >= 0.75
            THEN 'It ranks in the bottom quartile of Visionary parts by L6M GRS despite being an Amazon winner.'
          END
        ]) AS reason
        WHERE reason IS NOT NULL
      ),
      ' '
    ) AS why_not_succeeding,
    CASE
      WHEN match_status = 'NOT_FOUND' THEN 'Validate the exact supplierpartnumber mapping before taking action.'
      WHEN l6m_availability IS NOT NULL AND l6m_availability < 0.85 THEN 'Fix in-stock and program availability first.'
      WHEN prior_3m_grs > 0 AND recent_3m_grs < prior_3m_grs * 0.60 THEN 'Check recent assortment, buybox, and PDP changes that may have broken momentum.'
      WHEN l6m_availability IS NOT NULL AND l6m_availability >= 0.90 AND l6m_grs < COALESCE(selected_median_grs, supplier_median_grs) * 0.50 THEN 'Traffic and conversion are the next diagnostics to pull because supply is not the primary constraint.'
      WHEN l6m_product_cost > COALESCE(selected_median_product_cost, supplier_median_product_cost) * 1.25 THEN 'Review price ladders and margin targets against the rest of the Amazon-winner set.'
      ELSE 'Compare merchandising and assortment decisions against the better-performing peer parts.'
    END AS recommended_next_step
  FROM scored_parts
)

SELECT
  requested_part_number,
  match_status,
  supplier_name,
  matched_part_number,
  sales_rank,
  supplier_part_count,
  sales_rank_pct,
  l6m_grs,
  l6m_product_cost,
  l6m_order_count,
  selling_months,
  catalog_months,
  l6m_availability,
  recent_3m_grs,
  prior_3m_grs,
  recent_3m_grs_delta_pct,
  supplier_median_grs,
  selected_median_grs,
  supplier_median_availability,
  selected_median_availability,
  is_outlier,
  outlier_bucket,
  why_not_succeeding,
  recommended_next_step
FROM reasoned_parts
ORDER BY
  is_outlier DESC,
  COALESCE(sales_rank, 999999),
  requested_part_number;
