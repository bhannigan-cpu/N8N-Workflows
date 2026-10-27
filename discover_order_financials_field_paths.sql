-- Helper query for:
-- `wf-gcp-us-ae-sf-prod.curated_data_hub.tbl_fact_order_financials`
--
-- Run this first to identify likely columns for:
-- - supplier_id
-- - supplier_name
-- - state
-- - SKU key
-- - SKU name
-- - quantity
-- - revenue
-- - order_id
-- - order_date
--
-- Copy the `suggested_expression` values into
-- `supplier_sku_state_sales_from_order_financials.sql`.

WITH field_paths AS (
  SELECT
    REGEXP_REPLACE(field_path, r'^tbl_fact_order_financials\.', '') AS field_path
  FROM `wf-gcp-us-ae-sf-prod.curated_data_hub.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
  WHERE table_name = 'tbl_fact_order_financials'
),
classified AS (
  SELECT
    'supplier_id' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(supplier_id|supplierid)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(origsuid|su_id|suid)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(vendor_id|vendorid|partner_id|partnerid)$') THEN 900
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(supplier_id|supplierid|origsuid|su_id|suid|vendor_id|vendorid|partner_id|partnerid)$'
  )

  UNION ALL

  SELECT
    'supplier_name' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(supplier_name|suppliername)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(origsuname)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(vendor_name|vendorname|partner_name|partnername)$') THEN 900
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(supplier_name|suppliername|origsuname|vendor_name|vendorname|partner_name|partnername)$'
  )

  UNION ALL

  SELECT
    'state' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(ship_to_state|ship_state|shipping_state)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(destination_state|customer_state|order_state|bill_to_state)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(state_name)$') THEN 900
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(state|state_code|statecode)$') THEN 850
      ELSE 0
    END
    - CASE
        WHEN REGEXP_CONTAINS(LOWER(field_path), r'(country|statement)') THEN 10000
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
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(product_title|producttitle|title)$') THEN 800
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(sku_name|skuname|product_name|productname|part_name|partname|item_name|itemname|product_title|producttitle|title)$'
  )

  UNION ALL

  SELECT
    'quantity' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(quantity)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(qty)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(units|unit_count|order_quantity|item_quantity)$') THEN 900
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(quantity|qty|units|unit_count|order_quantity|item_quantity)$'
  )

  UNION ALL

  SELECT
    'revenue' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(gross_revenue|grossrevenuestable)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(revenue|sales|gross_sales)$') THEN 950
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(gmv|bookings|booking_amount)$') THEN 900
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(net_revenue|net_sales)$') THEN 850
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(gross_revenue|grossrevenuestable|revenue|sales|gross_sales|gmv|bookings|booking_amount|net_revenue|net_sales)$'
  )

  UNION ALL

  SELECT
    'order_id' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(order_id|orderid)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(id)$') THEN 700
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(order_id|orderid|id)$')

  UNION ALL

  SELECT
    'order_date' AS field_type,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(order_date|order_created_date|created_date)$') THEN 1000
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(date)$') THEN 850
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(^|\.)(ship_date|transaction_date)$') THEN 800
      ELSE 0
    END AS score
  FROM field_paths
  WHERE REGEXP_CONTAINS(
    LOWER(field_path),
    r'(^|\.)(order_date|order_created_date|created_date|date|ship_date|transaction_date)$'
  )
)
SELECT
  field_type,
  field_path,
  CONCAT('src.', field_path) AS suggested_expression,
  score
FROM classified
WHERE score > 0
ORDER BY field_type, score DESC, field_path;
