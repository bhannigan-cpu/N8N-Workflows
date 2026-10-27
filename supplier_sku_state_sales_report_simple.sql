-- Simpler Supplier SKU and state sales report for BigQuery.
--
-- Use this version if the auto-detect script fails or if your BigQuery role
-- cannot query INFORMATION_SCHEMA.COLUMN_FIELD_PATHS.
--
-- How to use:
-- 1. Open this script in the BigQuery SQL editor.
-- 2. Confirm the supplier values.
-- 3. Update the field expressions below if your schema uses different names.
-- 4. Run the script.
--
-- Result sets:
--   1. resolved inputs
--   2. overall supplier totals
--   3. states ranked by revenue
--   4. top-selling state for each SKU
--   5. full state ranking for every SKU
--   6. full SKU-by-state detail

DECLARE supplier_name_input STRING DEFAULT 'HLC.ME';
DECLARE supplier_id_input STRING DEFAULT '29955';
DECLARE lookback_weeks_input INT64 DEFAULT 52;

-- Update these expressions if your dataset uses different field names.
-- These should be valid SQL expressions in the context of the FROM clause below,
-- where these aliases exist:
--   retail_sku_store_date
--   supplier_struct
--   supplier_part_struct
--   orders
--
-- Run discover_supplier_sales_field_paths.sql first if you do not know these.
--
-- Common alternatives you may need:
--   state_sql: orders.destination_state, orders.customer_state,
--              store_struct.state_name, retail_sku_store_date.state_name
--   sku_sql: supplier_part_struct.sku, supplier_part_struct.supplierpartid,
--            supplier_part_struct.partnumber
--   sku_name_sql: supplier_part_struct.skuname,
--                 supplier_part_struct.productname,
--                 supplier_part_struct.partname
--   quantity_sql: COALESCE(CAST(supplier_part_struct.quantity AS NUMERIC), 0),
--                 COALESCE(CAST(orders.quantity AS NUMERIC), 0)
DECLARE state_sql STRING DEFAULT '';
DECLARE sku_sql STRING DEFAULT '';
DECLARE sku_name_sql STRING DEFAULT '';
DECLARE quantity_sql STRING DEFAULT '';

DECLARE report_sql STRING;

ASSERT TRIM(state_sql) <> '' AS 'Set state_sql to a valid state expression. Run discover_supplier_sales_field_paths.sql first.';
ASSERT TRIM(sku_sql) <> '' AS 'Set sku_sql to a valid SKU expression. Run discover_supplier_sales_field_paths.sql first.';
ASSERT TRIM(quantity_sql) <> '' AS 'Set quantity_sql to a valid quantity expression. Run discover_supplier_sales_field_paths.sql first.';

SET report_sql = FORMAT(
  """
  CREATE TEMP TABLE sku_state_sales AS
  WITH params AS (
    SELECT
      @supplier_name AS supplier_name,
      @supplier_id AS supplier_id,
      DATE_SUB(CURRENT_DATE(), INTERVAL @lookback_weeks WEEK) AS start_date,
      CURRENT_DATE() AS end_date
  ),
  currency AS (
    SELECT
      ANY_VALUE(ExchangeRate) AS exchange_rate,
      ANY_VALUE(currency_symbol) AS currency_symbol
    FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
    WHERE CuyShortName = 'USD'
  ),
  base_rows AS (
    SELECT
      retail_dim_supplier.origsuname AS supplier_name,
      CAST(retail_dim_supplier.origsuid AS STRING) AS supplier_id,
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown') AS state_name,
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown SKU') AS sku_key,
      COALESCE(
        NULLIF(TRIM(CAST(%s AS STRING)), ''),
        COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown SKU')
      ) AS sku_name,
      orders.id AS order_id,
      %s AS units_sold,
      COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS gross_revenue,
      currency.currency_symbol AS currency_symbol,
      DATE(retail_sku_store_date.date) AS order_date
    FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
    LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
    LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
    LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
      ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
    CROSS JOIN currency
    CROSS JOIN params
    WHERE retail_sku_store_date.brandname = 'Wayfair'
      AND retail_sku_store_date.agg_level = 'DAILY'
      AND DATE(retail_sku_store_date.date) BETWEEN params.start_date AND params.end_date
      AND (
        (params.supplier_id <> '' AND CAST(retail_dim_supplier.origsuid AS STRING) = params.supplier_id)
        OR (params.supplier_name <> '' AND LOWER(retail_dim_supplier.origsuname) = LOWER(params.supplier_name))
      )
  ),
  deduped_sales AS (
    SELECT
      supplier_name,
      supplier_id,
      state_name,
      sku_key,
      sku_name,
      currency_symbol,
      order_id,
      MAX(units_sold) AS units_sold,
      MAX(gross_revenue) AS gross_revenue,
      MIN(order_date) AS first_order_date,
      MAX(order_date) AS last_order_date
    FROM base_rows
    WHERE order_id IS NOT NULL
    GROUP BY
      supplier_name,
      supplier_id,
      state_name,
      sku_key,
      sku_name,
      currency_symbol,
      order_id
  )
  SELECT
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name,
    currency_symbol,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(units_sold) AS units_sold,
    SUM(gross_revenue) AS gross_revenue,
    MIN(first_order_date) AS first_order_date,
    MAX(last_order_date) AS last_order_date
  FROM deduped_sales
  GROUP BY
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name,
    currency_symbol
  """,
  state_sql,
  sku_sql,
  sku_name_sql,
  sku_sql,
  quantity_sql
);

EXECUTE IMMEDIATE report_sql
USING
  supplier_name_input AS supplier_name,
  supplier_id_input AS supplier_id,
  lookback_weeks_input AS lookback_weeks;

SELECT
  supplier_name_input AS supplier_name,
  supplier_id_input AS supplier_id,
  lookback_weeks_input AS lookback_weeks,
  state_sql AS state_expression,
  sku_sql AS sku_expression,
  sku_name_sql AS sku_name_expression,
  quantity_sql AS quantity_expression;

SELECT
  ANY_VALUE(supplier_name) AS supplier_name,
  ANY_VALUE(supplier_id) AS supplier_id,
  ANY_VALUE(currency_symbol) AS currency_symbol,
  COUNT(DISTINCT state_name) AS states_with_sales,
  COUNT(DISTINCT sku_key) AS skus_with_sales,
  SUM(order_count) AS total_orders,
  SUM(units_sold) AS total_units_sold,
  SUM(gross_revenue) AS total_gross_revenue
FROM sku_state_sales;

WITH state_top_sku AS (
  SELECT
    state_name,
    sku_key,
    sku_name,
    gross_revenue,
    units_sold,
    order_count,
    ROW_NUMBER() OVER (
      PARTITION BY state_name
      ORDER BY gross_revenue DESC, units_sold DESC, sku_name, sku_key
    ) AS sku_rank_in_state
  FROM sku_state_sales
),
state_totals AS (
  SELECT
    state_name,
    ANY_VALUE(currency_symbol) AS currency_symbol,
    COUNT(DISTINCT sku_key) AS sku_count,
    SUM(order_count) AS total_orders,
    SUM(units_sold) AS total_units_sold,
    SUM(gross_revenue) AS total_gross_revenue
  FROM sku_state_sales
  GROUP BY state_name
)
SELECT
  ROW_NUMBER() OVER (
    ORDER BY totals.total_gross_revenue DESC, totals.total_units_sold DESC, totals.state_name
  ) AS state_rank,
  totals.state_name,
  totals.currency_symbol,
  totals.sku_count,
  totals.total_orders,
  totals.total_units_sold,
  totals.total_gross_revenue,
  SAFE_DIVIDE(totals.total_gross_revenue, SUM(totals.total_gross_revenue) OVER ()) AS revenue_share_of_supplier,
  top_sku.sku_key AS top_sku_key,
  top_sku.sku_name AS top_sku_name,
  top_sku.gross_revenue AS top_sku_revenue,
  SAFE_DIVIDE(top_sku.gross_revenue, totals.total_gross_revenue) AS top_sku_revenue_share_of_state
FROM state_totals AS totals
LEFT JOIN state_top_sku AS top_sku
  ON top_sku.state_name = totals.state_name
 AND top_sku.sku_rank_in_state = 1
ORDER BY state_rank;

WITH sku_rankings AS (
  SELECT
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name,
    currency_symbol,
    order_count,
    units_sold,
    gross_revenue,
    SAFE_DIVIDE(gross_revenue, SUM(gross_revenue) OVER (PARTITION BY sku_key, sku_name)) AS revenue_share_of_sku,
    COUNT(*) OVER (PARTITION BY sku_key, sku_name) AS states_with_sales_for_sku,
    ROW_NUMBER() OVER (
      PARTITION BY sku_key, sku_name
      ORDER BY gross_revenue DESC, units_sold DESC, state_name
    ) AS state_rank_for_sku
  FROM sku_state_sales
)
SELECT
  supplier_name,
  supplier_id,
  sku_key,
  sku_name,
  currency_symbol,
  state_name AS top_state_name,
  order_count AS top_state_order_count,
  units_sold AS top_state_units_sold,
  gross_revenue AS top_state_gross_revenue,
  revenue_share_of_sku,
  states_with_sales_for_sku
FROM sku_rankings
WHERE state_rank_for_sku = 1
ORDER BY top_state_gross_revenue DESC, top_state_units_sold DESC, sku_name, sku_key;

WITH sku_rankings AS (
  SELECT
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name,
    currency_symbol,
    order_count,
    units_sold,
    gross_revenue,
    SAFE_DIVIDE(gross_revenue, SUM(gross_revenue) OVER (PARTITION BY sku_key, sku_name)) AS revenue_share_of_sku,
    ROW_NUMBER() OVER (
      PARTITION BY sku_key, sku_name
      ORDER BY gross_revenue DESC, units_sold DESC, state_name
    ) AS state_rank_for_sku
  FROM sku_state_sales
)
SELECT
  supplier_name,
  supplier_id,
  sku_key,
  sku_name,
  currency_symbol,
  state_rank_for_sku,
  state_name,
  order_count,
  units_sold,
  gross_revenue,
  revenue_share_of_sku
FROM sku_rankings
ORDER BY sku_name, sku_key, state_rank_for_sku;

SELECT
  supplier_name,
  supplier_id,
  state_name,
  sku_key,
  sku_name,
  currency_symbol,
  order_count,
  units_sold,
  gross_revenue,
  first_order_date,
  last_order_date
FROM sku_state_sales
ORDER BY gross_revenue DESC, units_sold DESC, state_name, sku_name, sku_key;
