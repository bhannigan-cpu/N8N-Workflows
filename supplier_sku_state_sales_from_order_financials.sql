-- Supplier SKU/state sales report using:
-- `wf-gcp-us-ae-sf-prod.curated_data_hub.tbl_fact_order_financials`
--
-- Recommended flow:
-- 1. Run discover_order_financials_field_paths.sql
-- 2. Copy the suggested_expression values into the DECLAREs below
-- 3. Run this script
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

-- Paste values from discover_order_financials_field_paths.sql.
-- Examples:
--   supplier_id_sql: CAST(src.supplier_id AS STRING)
--   supplier_name_sql: src.supplier_name
--   state_sql: src.destination_state
--   sku_sql: src.partnumber
--   sku_name_sql: src.partname
--   quantity_sql: COALESCE(CAST(src.quantity AS NUMERIC), 0)
--   revenue_sql: COALESCE(CAST(src.gross_revenue AS NUMERIC), 0)
--   order_id_sql: CAST(src.order_id AS STRING)
--   order_date_sql: DATE(src.order_date)
DECLARE supplier_id_sql STRING DEFAULT '';
DECLARE supplier_name_sql STRING DEFAULT '';
DECLARE state_sql STRING DEFAULT '';
DECLARE sku_sql STRING DEFAULT '';
DECLARE sku_name_sql STRING DEFAULT '';
DECLARE quantity_sql STRING DEFAULT '';
DECLARE revenue_sql STRING DEFAULT '';
DECLARE order_id_sql STRING DEFAULT '';
DECLARE order_date_sql STRING DEFAULT '';

DECLARE report_sql STRING;

ASSERT TRIM(supplier_id_sql) <> '' OR TRIM(supplier_name_sql) <> ''
  AS 'Set supplier_id_sql or supplier_name_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(state_sql) <> ''
  AS 'Set state_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(sku_sql) <> ''
  AS 'Set sku_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(quantity_sql) <> ''
  AS 'Set quantity_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(revenue_sql) <> ''
  AS 'Set revenue_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(order_id_sql) <> ''
  AS 'Set order_id_sql. Run discover_order_financials_field_paths.sql first.';
ASSERT TRIM(order_date_sql) <> ''
  AS 'Set order_date_sql. Run discover_order_financials_field_paths.sql first.';

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
  base_rows AS (
    SELECT
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown Supplier') AS supplier_name,
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown Supplier ID') AS supplier_id,
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown') AS state_name,
      COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown SKU') AS sku_key,
      COALESCE(
        NULLIF(TRIM(CAST(%s AS STRING)), ''),
        COALESCE(NULLIF(TRIM(CAST(%s AS STRING)), ''), 'Unknown SKU')
      ) AS sku_name,
      CAST(%s AS STRING) AS order_id,
      %s AS units_sold,
      %s AS gross_revenue,
      %s AS order_date
    FROM `wf-gcp-us-ae-sf-prod.curated_data_hub.tbl_fact_order_financials` AS src
    CROSS JOIN params
    WHERE %s BETWEEN params.start_date AND params.end_date
      AND (
        (params.supplier_id <> '' AND CAST(%s AS STRING) = params.supplier_id)
        OR (params.supplier_name <> '' AND LOWER(CAST(%s AS STRING)) = LOWER(params.supplier_name))
      )
  ),
  deduped_sales AS (
    SELECT
      supplier_name,
      supplier_id,
      state_name,
      sku_key,
      sku_name,
      order_id,
      order_date,
      SUM(units_sold) AS units_sold,
      SUM(gross_revenue) AS gross_revenue
    FROM base_rows
    WHERE order_id IS NOT NULL
    GROUP BY
      supplier_name,
      supplier_id,
      state_name,
      sku_key,
      sku_name,
      order_id,
      order_date
  )
  SELECT
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(units_sold) AS units_sold,
    SUM(gross_revenue) AS gross_revenue,
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date
  FROM deduped_sales
  GROUP BY
    supplier_name,
    supplier_id,
    state_name,
    sku_key,
    sku_name
  """,
  IF(TRIM(supplier_name_sql) = '', "'Unknown Supplier'", supplier_name_sql),
  IF(TRIM(supplier_id_sql) = '', "'Unknown Supplier ID'", supplier_id_sql),
  state_sql,
  sku_sql,
  IF(TRIM(sku_name_sql) = '', sku_sql, sku_name_sql),
  sku_sql,
  order_id_sql,
  quantity_sql,
  revenue_sql,
  order_date_sql,
  order_date_sql,
  IF(TRIM(supplier_id_sql) = '', "'Unknown Supplier ID'", supplier_id_sql),
  IF(TRIM(supplier_name_sql) = '', "'Unknown Supplier'", supplier_name_sql)
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
  supplier_id_sql AS supplier_id_expression,
  supplier_name_sql AS supplier_name_expression,
  state_sql AS state_expression,
  sku_sql AS sku_expression,
  sku_name_sql AS sku_name_expression,
  quantity_sql AS quantity_expression,
  revenue_sql AS revenue_expression,
  order_id_sql AS order_id_expression,
  order_date_sql AS order_date_expression;

SELECT
  ANY_VALUE(supplier_name) AS supplier_name,
  ANY_VALUE(supplier_id) AS supplier_id,
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
  order_count,
  units_sold,
  gross_revenue,
  first_order_date,
  last_order_date
FROM sku_state_sales
ORDER BY gross_revenue DESC, units_sold DESC, state_name, sku_name, sku_key;
