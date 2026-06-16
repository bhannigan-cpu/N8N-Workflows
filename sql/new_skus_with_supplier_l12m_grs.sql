-- New SKUs launched in the last 90 days with supplier L12M GRS and growth.
--
-- This version does not depend on a SKU dimension launch-date field. It uses
-- the first date a SKU/supplier pair appears in retail_sku_store_date_agg as
-- the launch date proxy, then attaches supplier-level L12M GRS metrics.
--
-- Growth definition:
--   supplier_l12m_grs_growth_rate =
--     (supplier_l12m_grs - supplier_prior_l12m_grs) / supplier_prior_l12m_grs

DECLARE as_of_date DATE DEFAULT CURRENT_DATE();
DECLARE new_sku_lookback_days INT64 DEFAULT 90;
DECLARE sku_column STRING;
DECLARE sku_expr STRING;

SET sku_column = (
  SELECT column_name
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'retail_sku_store_date_agg'
    AND LOWER(column_name) IN (
      'prsku',
      'sku',
      'skuid',
      'sku_id',
      'skukey',
      'sku_key',
      'productsku',
      'product_sku'
    )
  ORDER BY
    CASE LOWER(column_name)
      WHEN 'prsku' THEN 1
      WHEN 'sku' THEN 2
      WHEN 'skuid' THEN 3
      WHEN 'sku_id' THEN 4
      WHEN 'skukey' THEN 5
      WHEN 'sku_key' THEN 6
      WHEN 'productsku' THEN 7
      WHEN 'product_sku' THEN 8
      ELSE 99
    END
  LIMIT 1
);

ASSERT sku_column IS NOT NULL AS
  'Could not find a SKU column on cm_reporting.retail_sku_store_date_agg. Check INFORMATION_SCHEMA.COLUMNS and add the SKU column name to this script.';

SET sku_expr = FORMAT('`%s`', sku_column);

EXECUTE IMMEDIATE FORMAT("""
WITH params AS (
  SELECT
    @as_of_date AS as_of_date,
    DATE_SUB(@as_of_date, INTERVAL (@new_sku_lookback_days - 1) DAY) AS new_sku_start_date,
    DATE_SUB(@as_of_date, INTERVAL 12 MONTH) AS current_l12m_start_date,
    DATE_SUB(DATE_SUB(@as_of_date, INTERVAL 12 MONTH), INTERVAL 12 MONTH) AS prior_l12m_start_date,
    DATE_SUB(DATE_SUB(@as_of_date, INTERVAL 12 MONTH), INTERVAL 1 DAY) AS prior_l12m_end_date
),

sku_supplier_first_seen AS (
  SELECT
    CAST(retail_sku_store_date.%s AS STRING) AS sku,
    supplier_struct.supplierkey AS supplier_key,
    MIN(retail_sku_store_date.date) AS launch_date
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.date <= params.as_of_date
    AND retail_sku_store_date.%s IS NOT NULL
    AND supplier_struct.supplierkey IS NOT NULL
  GROUP BY
    1,
    2
),

new_skus AS (
  SELECT
    sku,
    supplier_key,
    launch_date
  FROM sku_supplier_first_seen
  CROSS JOIN params
  WHERE launch_date BETWEEN params.new_sku_start_date AND params.as_of_date
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate,
    ANY_VALUE(currency_symbol) AS currency_symbol
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),

supplier_order_rows AS (
  SELECT
    CASE
      WHEN retail_sku_store_date.date BETWEEN params.current_l12m_start_date AND params.as_of_date
        THEN 'current_l12m'
      WHEN retail_sku_store_date.date BETWEEN params.prior_l12m_start_date AND params.prior_l12m_end_date
        THEN 'prior_l12m'
    END AS grs_period,
    retail_dim_supplier.supplierkey AS supplier_key,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name,
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
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.date BETWEEN params.prior_l12m_start_date AND params.as_of_date
    AND orders.id IS NOT NULL
),

deduped_supplier_orders AS (
  SELECT
    grs_period,
    supplier_key,
    supplier_id,
    supplier_name,
    currency_symbol,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM supplier_order_rows
  WHERE grs_period IS NOT NULL
  GROUP BY
    grs_period,
    supplier_key,
    supplier_id,
    supplier_name,
    currency_symbol,
    order_id
),

supplier_l12m_grs AS (
  SELECT
    supplier_key,
    ANY_VALUE(supplier_id) AS supplier_id,
    ANY_VALUE(supplier_name) AS supplier_name,
    ANY_VALUE(currency_symbol) AS currency_symbol,
    SUM(IF(grs_period = 'current_l12m', grs, 0)) AS supplier_l12m_grs,
    SUM(IF(grs_period = 'prior_l12m', grs, 0)) AS supplier_prior_l12m_grs
  FROM deduped_supplier_orders
  GROUP BY supplier_key
),

supplier_metrics AS (
  SELECT
    supplier_key,
    supplier_id,
    supplier_name,
    currency_symbol,
    supplier_l12m_grs,
    supplier_prior_l12m_grs,
    supplier_l12m_grs - supplier_prior_l12m_grs AS supplier_l12m_grs_change,
    SAFE_DIVIDE(
      supplier_l12m_grs - supplier_prior_l12m_grs,
      NULLIF(supplier_prior_l12m_grs, 0)
    ) AS supplier_l12m_grs_growth_rate
  FROM supplier_l12m_grs
),

new_skus_with_supplier AS (
  SELECT
    new_skus.sku,
    new_skus.launch_date,
    retail_dim_supplier.supplierkey AS supplier_key,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name
  FROM new_skus
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = new_skus.supplier_key
)

SELECT
  new_skus_with_supplier.sku,
  new_skus_with_supplier.launch_date,
  new_skus_with_supplier.supplier_key,
  new_skus_with_supplier.supplier_id,
  new_skus_with_supplier.supplier_name,
  supplier_metrics.currency_symbol,
  supplier_metrics.supplier_l12m_grs,
  supplier_metrics.supplier_prior_l12m_grs,
  supplier_metrics.supplier_l12m_grs_change,
  supplier_metrics.supplier_l12m_grs_growth_rate
FROM new_skus_with_supplier
LEFT JOIN supplier_metrics
  ON supplier_metrics.supplier_key = new_skus_with_supplier.supplier_key
ORDER BY
  new_skus_with_supplier.launch_date DESC,
  new_skus_with_supplier.sku;
""", sku_expr, sku_expr)
USING
  as_of_date AS as_of_date,
  new_sku_lookback_days AS new_sku_lookback_days;
