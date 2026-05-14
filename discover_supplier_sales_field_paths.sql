-- Helper query: discover likely field paths for supplier SKU/state sales reporting.
--
-- Run this first if you do not know which fields hold:
-- - state
-- - SKU key
-- - SKU name
-- - quantity
--
-- The output includes:
-- - field_type
-- - field_path
-- - suggested_expression
-- - score

WITH field_paths AS (
  SELECT
    REGEXP_REPLACE(field_path, r'^retail_sku_store_date\.', '') AS field_path
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
  WHERE table_name = 'retail_sku_store_date_agg'
),
classified AS (
  SELECT
    'state' AS field_type,
    field_path,
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
  FROM field_paths
  WHERE REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)([a-z0-9_]*state[a-z0-9_]*)$')

  UNION ALL

  SELECT
    'sku' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku_id|skuid)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(part_number|partnumber)$') THEN 900
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(supplier_part_id|supplierpartid)$') THEN 875
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_id|productid|item_id|itemid)$') THEN 850
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(sku_id|skuid|sku|part_number|partnumber|supplier_part_id|supplierpartid|product_id|productid|item_id|itemid)$'
  )

  UNION ALL

  SELECT
    'sku_name' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(sku_name|skuname)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_name|productname)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(part_name|partname)$') THEN 900
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(item_name|itemname)$') THEN 850
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_title|producttitle)$') THEN 800
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(sku_name|skuname|product_name|productname|part_name|partname|item_name|itemname|product_title|producttitle)$'
  )

  UNION ALL

  SELECT
    'quantity' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(quantity)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(qty)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(units)$') THEN 900
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(unit_count)$') THEN 850
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(quantity|qty|units|unit_count)$')
)
SELECT
  field_type,
  field_path,
  CASE
    WHEN STARTS_WITH(field_path, 'supplier_struct.supplier_part_struct.orders.') THEN CONCAT('orders.', SUBSTR(field_path, LENGTH('supplier_struct.supplier_part_struct.orders.') + 1))
    WHEN STARTS_WITH(field_path, 'orders.') THEN field_path
    WHEN STARTS_WITH(field_path, 'supplier_struct.supplier_part_struct.') THEN CONCAT('supplier_part_struct.', SUBSTR(field_path, LENGTH('supplier_struct.supplier_part_struct.') + 1))
    WHEN STARTS_WITH(field_path, 'supplier_part_struct.') THEN field_path
    WHEN STARTS_WITH(field_path, 'supplier_struct.') THEN field_path
    WHEN STARTS_WITH(field_path, 'traffic_source.') THEN field_path
    WHEN STARTS_WITH(field_path, 'store_struct.') THEN field_path
    WHEN STARTS_WITH(field_path, 'stores.') THEN field_path
    ELSE CONCAT('retail_sku_store_date.', field_path)
  END AS suggested_expression,
  score
FROM classified
WHERE score > 0
ORDER BY field_type, score DESC, field_path;
