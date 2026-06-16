-- Bedding product-category SKUs launched in the last 90 days with supplier.
--
-- "Launched" is defined here as the first date the SKU/supplier pair appears
-- in cm_reporting.retail_sku_store_date_agg.

DECLARE as_of_date DATE DEFAULT CURRENT_DATE();
DECLARE lookback_days INT64 DEFAULT 90;
DECLARE sku_column STRING;
DECLARE category_column STRING;
DECLARE sku_expr STRING;
DECLARE category_expr STRING;

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

SET category_column = (
  SELECT column_name
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
  WHERE table_name = 'retail_sku_store_date_agg'
    AND LOWER(column_name) IN (
      'productmarketingcategory',
      'product_marketing_category',
      'marketingcategory',
      'marketing_category',
      'productcategory',
      'product_category',
      'category',
      'clname',
      'classname',
      'class_name',
      'saclass',
      'saclassname',
      'sa_class_name',
      'department',
      'departmentname',
      'department_name'
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

ASSERT category_column IS NOT NULL AS
  'Could not find a product category column on cm_reporting.retail_sku_store_date_agg. Check INFORMATION_SCHEMA.COLUMNS and add the category column name to this script.';

SET sku_expr = FORMAT('`%s`', sku_column);
SET category_expr = FORMAT('`%s`', category_column);

EXECUTE IMMEDIATE FORMAT("""
WITH params AS (
  SELECT
    @as_of_date AS as_of_date,
    DATE_SUB(@as_of_date, INTERVAL (@lookback_days - 1) DAY) AS window_start
),

sku_supplier_first_seen AS (
  SELECT
    CAST(retail_sku_store_date.%s AS STRING) AS sku,
    CAST(retail_sku_store_date.%s AS STRING) AS product_category,
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
    AND LOWER(TRIM(CAST(retail_sku_store_date.%s AS STRING))) = 'bedding'
    AND supplier_struct.supplierkey IS NOT NULL
  GROUP BY
    1,
    2,
    3
),

new_skus AS (
  SELECT
    sku,
    product_category,
    supplier_key,
    launch_date
  FROM sku_supplier_first_seen
  CROSS JOIN params
  WHERE launch_date BETWEEN params.window_start AND params.as_of_date
)

SELECT
  new_skus.sku,
  new_skus.product_category,
  new_skus.launch_date,
  retail_dim_supplier.origsuid AS supplier_id,
  retail_dim_supplier.origsuname AS supplier_name,
  new_skus.supplier_key
FROM new_skus
LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
  ON retail_dim_supplier.supplierkey = new_skus.supplier_key
ORDER BY
  new_skus.launch_date DESC,
  new_skus.sku;
""", sku_expr, category_expr, sku_expr, category_expr)
USING
  as_of_date AS as_of_date,
  lookback_days AS lookback_days;
