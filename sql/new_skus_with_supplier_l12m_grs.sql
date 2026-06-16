-- Bedding product-category SKUs launched in the last 90 days with supplier.
--
-- Product category comes from retail_dim_sku.
-- Launch date is approximated as the first date the SKU/supplier pair appears
-- in retail_sku_store_date_agg.

DECLARE as_of_date DATE DEFAULT CURRENT_DATE();
DECLARE lookback_days INT64 DEFAULT 90;
DECLARE fact_sku_column STRING;
DECLARE dim_sku_column STRING;
DECLARE dim_category_column STRING;
DECLARE fact_sku_expr STRING;
DECLARE dim_sku_expr STRING;
DECLARE dim_category_expr STRING;

SET fact_sku_column = (
  SELECT column_name
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'retail_sku_store_date_agg'
    AND LOWER(column_name) IN ('prsku', 'sku', 'skuid', 'sku_id', 'skukey', 'sku_key')
  ORDER BY
    CASE LOWER(column_name)
      WHEN 'prsku' THEN 1
      WHEN 'sku' THEN 2
      WHEN 'skuid' THEN 3
      WHEN 'sku_id' THEN 4
      WHEN 'skukey' THEN 5
      WHEN 'sku_key' THEN 6
      ELSE 99
    END
  LIMIT 1
);

SET dim_sku_column = (
  SELECT column_name
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'retail_dim_sku'
    AND LOWER(column_name) IN ('prsku', 'sku', 'skuid', 'sku_id', 'skukey', 'sku_key')
  ORDER BY
    CASE LOWER(column_name)
      WHEN 'prsku' THEN 1
      WHEN 'sku' THEN 2
      WHEN 'skuid' THEN 3
      WHEN 'sku_id' THEN 4
      WHEN 'skukey' THEN 5
      WHEN 'sku_key' THEN 6
      ELSE 99
    END
  LIMIT 1
);

SET dim_category_column = (
  SELECT column_name
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'retail_dim_sku'
    AND LOWER(column_name) IN (
      'productmarketingcategory',
      'product_marketing_category',
      'marketingcategory',
      'marketing_category',
      'productcategory',
      'product_category',
      'category'
    )
  ORDER BY
    CASE LOWER(column_name)
      WHEN 'productmarketingcategory' THEN 1
      WHEN 'product_marketing_category' THEN 2
      WHEN 'marketingcategory' THEN 3
      WHEN 'marketing_category' THEN 4
      WHEN 'productcategory' THEN 5
      WHEN 'product_category' THEN 6
      WHEN 'category' THEN 7
      ELSE 99
    END
  LIMIT 1
);

ASSERT fact_sku_column IS NOT NULL AS
  'Could not find a SKU column on cm_reporting.retail_sku_store_date_agg.';
ASSERT dim_sku_column IS NOT NULL AS
  'Could not find a SKU column on cm_reporting.retail_dim_sku.';
ASSERT dim_category_column IS NOT NULL AS
  'Could not find a Bedding/product category column on cm_reporting.retail_dim_sku.';

SET fact_sku_expr = FORMAT('`%s`', fact_sku_column);
SET dim_sku_expr = FORMAT('`%s`', dim_sku_column);
SET dim_category_expr = FORMAT('`%s`', dim_category_column);

EXECUTE IMMEDIATE FORMAT("""
WITH params AS (
  SELECT
    @as_of_date AS as_of_date,
    DATE_SUB(@as_of_date, INTERVAL (@lookback_days - 1) DAY) AS window_start
),

bedding_skus AS (
  SELECT DISTINCT
    CAST(sku.%s AS STRING) AS sku,
    CAST(sku.%s AS STRING) AS product_category
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS sku
  WHERE LOWER(TRIM(CAST(sku.%s AS STRING))) LIKE '%%bedding%%'
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

new_bedding_skus AS (
  SELECT
    bedding_skus.sku,
    bedding_skus.product_category,
    sku_supplier_first_seen.launch_date,
    sku_supplier_first_seen.supplier_key
  FROM bedding_skus
  INNER JOIN sku_supplier_first_seen
    ON sku_supplier_first_seen.sku = bedding_skus.sku
  CROSS JOIN params
  WHERE sku_supplier_first_seen.launch_date BETWEEN params.window_start AND params.as_of_date
)

SELECT
  new_bedding_skus.sku,
  new_bedding_skus.product_category,
  new_bedding_skus.launch_date,
  retail_dim_supplier.origsuid AS supplier_id,
  retail_dim_supplier.origsuname AS supplier_name,
  new_bedding_skus.supplier_key
FROM new_bedding_skus
LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
  ON retail_dim_supplier.supplierkey = new_bedding_skus.supplier_key
ORDER BY
  new_bedding_skus.launch_date DESC,
  new_bedding_skus.sku;
""", dim_sku_expr, dim_category_expr, dim_category_expr, fact_sku_expr, fact_sku_expr)
USING
  as_of_date AS as_of_date,
  lookback_days AS lookback_days;
