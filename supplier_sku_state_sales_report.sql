-- Supplier SKU and state sales report for BigQuery.
--
-- How to use:
-- 1. Open this script in the BigQuery SQL editor.
-- 2. Update the DECLARE values below if you want a different supplier or field override.
-- 3. Run the script. BigQuery will return multiple result sets in this order:
--    a. resolved configuration
--    b. overall supplier totals
--    c. state totals ranked by revenue
--    d. top-selling state for each SKU
--    e. full state ranking for every SKU
--    f. full SKU-by-state detail

DECLARE supplier_name_input STRING DEFAULT 'HLC.ME';
DECLARE supplier_id_input STRING DEFAULT '29955';
DECLARE lookback_weeks_input INT64 DEFAULT 52;

-- Optional overrides if auto-detection picks the wrong field path.
-- Examples:
--   'supplier_struct.supplier_part_struct.orders.ship_to_state'
--   'supplier_struct.supplier_part_struct.sku'
DECLARE state_field_override STRING DEFAULT '';
DECLARE sku_field_override STRING DEFAULT '';
DECLARE sku_name_field_override STRING DEFAULT '';
DECLARE quantity_field_override STRING DEFAULT '';

DECLARE state_field STRING;
DECLARE sku_field STRING;
DECLARE sku_name_field STRING;
DECLARE quantity_field STRING;

DECLARE state_expr STRING;
DECLARE sku_expr STRING;
DECLARE sku_name_expr STRING;
DECLARE quantity_expr STRING;
DECLARE extra_joins STRING DEFAULT '';
DECLARE warning_message STRING DEFAULT '';
DECLARE report_sql STRING;

SET state_field = COALESCE(
  NULLIF(REGEXP_REPLACE(state_field_override, r'^retail_sku_store_date\.', ''), ''),
  (
    WITH candidates AS (
      SELECT
        REGEXP_REPLACE(field_path, r'^retail_sku_store_date\.', '') AS field_path,
        CASE
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(state_name)$') THEN 1000
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(ship_to_state|destination_state|customer_state|order_state|bill_to_state|store_state_name)$') THEN 900
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(state|state_code|statecode)$') THEN 800
          ELSE 0
        END
        - CASE
            WHEN REGEXP_CONTAINS(LOWER(field_path), r'(styname|statement|country)') THEN 10000
            ELSE 0
          END AS score
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
      WHERE table_name = 'retail_sku_store_date_agg'
        AND REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)([a-z0-9_]*state[a-z0-9_]*)$')
    )
    SELECT field_path
    FROM candidates
    WHERE score > 0
    ORDER BY score DESC, field_path
    LIMIT 1
  )
);

SET sku_field = COALESCE(
  NULLIF(REGEXP_REPLACE(sku_field_override, r'^retail_sku_store_date\.', ''), ''),
  (
    WITH candidates AS (
      SELECT
        REGEXP_REPLACE(field_path, r'^retail_sku_store_date\.', '') AS field_path,
        CASE
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku_id|skuid)$') THEN 1000
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku)$') THEN 950
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(part_number|partnumber)$') THEN 900
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(supplier_part_id|supplierpartid)$') THEN 875
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_id|productid|item_id|itemid)$') THEN 850
          ELSE 0
        END AS score
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
      WHERE table_name = 'retail_sku_store_date_agg'
        AND REGEXP_CONTAINS(
          LOWER(field_path),
          r'(^|\.)(sku_id|skuid|sku|part_number|partnumber|supplier_part_id|supplierpartid|product_id|productid|item_id|itemid)$'
        )
    )
    SELECT field_path
    FROM candidates
    WHERE score > 0
    ORDER BY score DESC, field_path
    LIMIT 1
  )
);

SET sku_name_field = COALESCE(
  NULLIF(REGEXP_REPLACE(sku_name_field_override, r'^retail_sku_store_date\.', ''), ''),
  (
    WITH candidates AS (
      SELECT
        REGEXP_REPLACE(field_path, r'^retail_sku_store_date\.', '') AS field_path,
        CASE
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku_name|skuname)$') THEN 1000
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_name|productname)$') THEN 950
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(part_name|partname)$') THEN 900
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(item_name|itemname)$') THEN 850
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_title|producttitle)$') THEN 800
          ELSE 0
        END AS score
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
      WHERE table_name = 'retail_sku_store_date_agg'
        AND REGEXP_CONTAINS(
          LOWER(field_path),
          r'(^|\.)(sku_name|skuname|product_name|productname|part_name|partname|item_name|itemname|product_title|producttitle)$'
        )
    )
    SELECT field_path
    FROM candidates
    WHERE score > 0
    ORDER BY score DESC, field_path
    LIMIT 1
  )
);

SET quantity_field = COALESCE(
  NULLIF(REGEXP_REPLACE(quantity_field_override, r'^retail_sku_store_date\.', ''), ''),
  (
    WITH candidates AS (
      SELECT
        REGEXP_REPLACE(field_path, r'^retail_sku_store_date\.', '') AS field_path,
        CASE
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(quantity)$') THEN 1000
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(qty)$') THEN 950
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(units)$') THEN 900
          WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(unit_count)$') THEN 850
          ELSE 0
        END AS score
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
      WHERE table_name = 'retail_sku_store_date_agg'
        AND REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(quantity|qty|units|unit_count)$')
    )
    SELECT field_path
    FROM candidates
    WHERE score > 0
    ORDER BY score DESC, field_path
    LIMIT 1
  )
);

ASSERT state_field IS NOT NULL AS 'Unable to auto-detect a state field. Set state_field_override and rerun.';
ASSERT sku_field IS NOT NULL AS 'Unable to auto-detect a SKU field. Set sku_field_override and rerun.';

SET state_expr = CASE
  WHEN STARTS_WITH(state_field, 'supplier_struct.supplier_part_struct.orders.') THEN CONCAT('orders.', SUBSTR(state_field, LENGTH('supplier_struct.supplier_part_struct.orders.') + 1))
  WHEN STARTS_WITH(state_field, 'orders.') THEN state_field
  WHEN STARTS_WITH(state_field, 'supplier_struct.supplier_part_struct.') THEN CONCAT('supplier_part_struct.', SUBSTR(state_field, LENGTH('supplier_struct.supplier_part_struct.') + 1))
  WHEN STARTS_WITH(state_field, 'supplier_part_struct.') THEN state_field
  WHEN STARTS_WITH(state_field, 'supplier_struct.') THEN state_field
  WHEN STARTS_WITH(state_field, 'traffic_source.') THEN state_field
  WHEN STARTS_WITH(state_field, 'store_struct.') THEN state_field
  WHEN STARTS_WITH(state_field, 'stores.') THEN state_field
  ELSE CONCAT('retail_sku_store_date.', state_field)
END;

SET sku_expr = CASE
  WHEN STARTS_WITH(sku_field, 'supplier_struct.supplier_part_struct.orders.') THEN CONCAT('orders.', SUBSTR(sku_field, LENGTH('supplier_struct.supplier_part_struct.orders.') + 1))
  WHEN STARTS_WITH(sku_field, 'orders.') THEN sku_field
  WHEN STARTS_WITH(sku_field, 'supplier_struct.supplier_part_struct.') THEN CONCAT('supplier_part_struct.', SUBSTR(sku_field, LENGTH('supplier_struct.supplier_part_struct.') + 1))
  WHEN STARTS_WITH(sku_field, 'supplier_part_struct.') THEN sku_field
  WHEN STARTS_WITH(sku_field, 'supplier_struct.') THEN sku_field
  WHEN STARTS_WITH(sku_field, 'traffic_source.') THEN sku_field
  WHEN STARTS_WITH(sku_field, 'store_struct.') THEN sku_field
  WHEN STARTS_WITH(sku_field, 'stores.') THEN sku_field
  ELSE CONCAT('retail_sku_store_date.', sku_field)
END;

SET sku_name_expr = CASE
  WHEN sku_name_field IS NULL THEN sku_expr
  WHEN STARTS_WITH(sku_name_field, 'supplier_struct.supplier_part_struct.orders.') THEN CONCAT('orders.', SUBSTR(sku_name_field, LENGTH('supplier_struct.supplier_part_struct.orders.') + 1))
  WHEN STARTS_WITH(sku_name_field, 'orders.') THEN sku_name_field
  WHEN STARTS_WITH(sku_name_field, 'supplier_struct.supplier_part_struct.') THEN CONCAT('supplier_part_struct.', SUBSTR(sku_name_field, LENGTH('supplier_struct.supplier_part_struct.') + 1))
  WHEN STARTS_WITH(sku_name_field, 'supplier_part_struct.') THEN sku_name_field
  WHEN STARTS_WITH(sku_name_field, 'supplier_struct.') THEN sku_name_field
  WHEN STARTS_WITH(sku_name_field, 'traffic_source.') THEN sku_name_field
  WHEN STARTS_WITH(sku_name_field, 'store_struct.') THEN sku_name_field
  WHEN STARTS_WITH(sku_name_field, 'stores.') THEN sku_name_field
  ELSE CONCAT('retail_sku_store_date.', sku_name_field)
END;

SET quantity_expr = CASE
  WHEN quantity_field IS NULL THEN '0'
  WHEN STARTS_WITH(quantity_field, 'supplier_struct.supplier_part_struct.orders.') THEN CONCAT('COALESCE(CAST(orders.', SUBSTR(quantity_field, LENGTH('supplier_struct.supplier_part_struct.orders.') + 1), ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'orders.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'supplier_struct.supplier_part_struct.') THEN CONCAT('COALESCE(CAST(supplier_part_struct.', SUBSTR(quantity_field, LENGTH('supplier_struct.supplier_part_struct.') + 1), ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'supplier_part_struct.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'supplier_struct.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'traffic_source.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'store_struct.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  WHEN STARTS_WITH(quantity_field, 'stores.') THEN CONCAT('COALESCE(CAST(', quantity_field, ' AS NUMERIC), 0)')
  ELSE CONCAT('COALESCE(CAST(retail_sku_store_date.', quantity_field, ' AS NUMERIC), 0)')
END;

IF STARTS_WITH(state_field, 'traffic_source.')
  OR STARTS_WITH(sku_field, 'traffic_source.')
  OR STARTS_WITH(COALESCE(sku_name_field, ''), 'traffic_source.')
  OR STARTS_WITH(COALESCE(quantity_field, ''), 'traffic_source.')
THEN
  SET extra_joins = CONCAT(extra_joins, '\n  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source');
END IF;

IF STARTS_WITH(state_field, 'store_struct.')
  OR STARTS_WITH(sku_field, 'store_struct.')
  OR STARTS_WITH(COALESCE(sku_name_field, ''), 'store_struct.')
  OR STARTS_WITH(COALESCE(quantity_field, ''), 'store_struct.')
THEN
  SET extra_joins = CONCAT(extra_joins, '\n  LEFT JOIN UNNEST(retail_sku_store_date.store_struct) AS store_struct');
END IF;

IF STARTS_WITH(state_field, 'stores.')
  OR STARTS_WITH(sku_field, 'stores.')
  OR STARTS_WITH(COALESCE(sku_name_field, ''), 'stores.')
  OR STARTS_WITH(COALESCE(quantity_field, ''), 'stores.')
THEN
  SET extra_joins = CONCAT(extra_joins, '\n  LEFT JOIN UNNEST(retail_sku_store_date.stores) AS stores');
END IF;

IF sku_name_field IS NULL THEN
  SET warning_message = CONCAT(
    warning_message,
    'No SKU name field was auto-detected; sku_name will mirror sku_key. '
  );
END IF;

IF quantity_field IS NULL THEN
  SET warning_message = CONCAT(
    warning_message,
    'No quantity field was auto-detected; units_sold will be 0 unless quantity_field_override is set.'
  );
END IF;

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
    LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders%s
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
  state_expr,
  sku_expr,
  sku_name_expr,
  sku_expr,
  quantity_expr,
  extra_joins
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
  state_field AS resolved_state_field,
  sku_field AS resolved_sku_field,
  COALESCE(sku_name_field, '(uses sku field)') AS resolved_sku_name_field,
  COALESCE(quantity_field, '(no quantity field detected)') AS resolved_quantity_field,
  NULLIF(TRIM(warning_message), '') AS warning_message;

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
    detail.state_name,
    ANY_VALUE(detail.currency_symbol) AS currency_symbol,
    COUNT(DISTINCT detail.sku_key) AS sku_count,
    SUM(detail.order_count) AS total_orders,
    SUM(detail.units_sold) AS total_units_sold,
    SUM(detail.gross_revenue) AS total_gross_revenue
  FROM sku_state_sales AS detail
  GROUP BY detail.state_name
),
state_totals_with_top_sku AS (
  SELECT
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
)
SELECT
  ROW_NUMBER() OVER (
    ORDER BY total_gross_revenue DESC, total_units_sold DESC, state_name
  ) AS state_rank,
  state_name,
  currency_symbol,
  sku_count,
  total_orders,
  total_units_sold,
  total_gross_revenue,
  revenue_share_of_supplier,
  top_sku_key,
  top_sku_name,
  top_sku_revenue,
  top_sku_revenue_share_of_state
FROM state_totals_with_top_sku
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
  COUNT(*) OVER (PARTITION BY sku_key, sku_name) AS states_with_sales_for_sku
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
