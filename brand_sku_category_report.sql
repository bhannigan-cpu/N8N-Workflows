--standardSQL
-- SKU count by requested brand for Thread Made Home (supplier 22255).
--
-- Why this is dynamic:
-- `brandname` in this reporting table is the storefront/site brand
-- (for example, Wayfair). The requested names are product/catalog brands, so
-- this script first finds the row-level product/catalog brand field from table
-- metadata, then runs the count against that field directly.

DECLARE target_supplier_id INT64 DEFAULT 22255;
DECLARE target_country STRING DEFAULT 'United States';
-- Leave NULL to use the latest available MONTHLY slice for this supplier.
DECLARE target_month_start DATE DEFAULT NULL;
DECLARE product_brand_field STRING;
DECLARE report_sql STRING;

CREATE TEMP FUNCTION normalize_brand(value STRING) AS (
  REGEXP_REPLACE(
    LOWER(TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(COALESCE(value, ''), r'[®™]', ''),
      r'[^A-Za-z0-9]+',
      ' '
    ))),
    r'\s+',
    ' '
  )
);

CREATE TEMP TABLE requested_brands AS
SELECT 1 AS sort_order, 'Alcott Hill®' AS brand, normalize_brand('Alcott Hill®') AS brand_key UNION ALL
SELECT 2, 'AllModern', normalize_brand('AllModern') UNION ALL
SELECT 3, 'Red Barrel Studio®', normalize_brand('Red Barrel Studio®') UNION ALL
SELECT 4, 'Gracie Oaks', normalize_brand('Gracie Oaks') UNION ALL
SELECT 5, 'House of Hampton®', normalize_brand('House of Hampton®') UNION ALL
SELECT 6, 'Astoria Grand', normalize_brand('Astoria Grand') UNION ALL
SELECT 7, 'Latitude Run®', normalize_brand('Latitude Run®') UNION ALL
SELECT 8, 'Villeroy & Boch', normalize_brand('Villeroy & Boch') UNION ALL
SELECT 9, 'Ivy Bronx', normalize_brand('Ivy Bronx') UNION ALL
SELECT 10, 'Lenox', normalize_brand('Lenox') UNION ALL
SELECT 11, 'Winston Porter', normalize_brand('Winston Porter') UNION ALL
SELECT 12, 'Mercer41', normalize_brand('Mercer41') UNION ALL
SELECT 13, 'Bungalow Rose', normalize_brand('Bungalow Rose') UNION ALL
SELECT 14, 'Lark Manor™', normalize_brand('Lark Manor™') UNION ALL
SELECT 15, 'Highland Dunes', normalize_brand('Highland Dunes') UNION ALL
SELECT 16, 'Charlton Home®', normalize_brand('Charlton Home®') UNION ALL
SELECT 17, 'Ophelia & Co.', normalize_brand('Ophelia & Co.') UNION ALL
SELECT 18, 'August Grove®', normalize_brand('August Grove®') UNION ALL
SELECT 19, 'Rosecliff Heights', normalize_brand('Rosecliff Heights') UNION ALL
SELECT 20, 'Rosalind Wheeler', normalize_brand('Rosalind Wheeler') UNION ALL
SELECT 21, 'The Holiday Aisle®', normalize_brand('The Holiday Aisle®') UNION ALL
SELECT 22, 'Beachcrest Home™', normalize_brand('Beachcrest Home™') UNION ALL
SELECT 23, 'Jonathan Adler', normalize_brand('Jonathan Adler') UNION ALL
SELECT 24, 'Symple Stuff', normalize_brand('Symple Stuff') UNION ALL
SELECT 25, 'Ebern Designs', normalize_brand('Ebern Designs') UNION ALL
SELECT 26, 'Canora Grey', normalize_brand('Canora Grey') UNION ALL
SELECT 27, 'Rosdorf Park', normalize_brand('Rosdorf Park') UNION ALL
SELECT 28, 'Wildon Home®', normalize_brand('Wildon Home®') UNION ALL
SELECT 29, '17 Stories', normalize_brand('17 Stories') UNION ALL
SELECT 30, 'Harriet Bee', normalize_brand('Harriet Bee') UNION ALL
SELECT 31, 'Bay Isle Home™', normalize_brand('Bay Isle Home™') UNION ALL
SELECT 32, 'Dakota Fields', normalize_brand('Dakota Fields') UNION ALL
SELECT 33, 'Breakwater Bay', normalize_brand('Breakwater Bay') UNION ALL
SELECT 34, 'Elrene Home Fashions', normalize_brand('Elrene Home Fashions') UNION ALL
SELECT 35, 'East Urban Home', normalize_brand('East Urban Home') UNION ALL
SELECT 36, 'Wade Logan®', normalize_brand('Wade Logan®') UNION ALL
SELECT 37, 'Millwood Pines', normalize_brand('Millwood Pines') UNION ALL
SELECT 38, 'George Oliver', normalize_brand('George Oliver') UNION ALL
SELECT 39, 'Brayden Studio®', normalize_brand('Brayden Studio®') UNION ALL
SELECT 40, 'Darby Home Co', normalize_brand('Darby Home Co') UNION ALL
SELECT 41, 'Zoomie Kids', normalize_brand('Zoomie Kids') UNION ALL
SELECT 42, 'The Twillery Co.®', normalize_brand('The Twillery Co.®') UNION ALL
SELECT 43, 'World Menagerie', normalize_brand('World Menagerie');

SET product_brand_field = (
  SELECT field_path
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
  WHERE table_name = 'retail_sku_store_date_agg'
    AND NOT REGEXP_CONTAINS(field_path, r'\.')
    AND LOWER(field_path) != 'brandname'
    AND REGEXP_CONTAINS(LOWER(field_path), r'brand')
  ORDER BY
    CASE
      WHEN LOWER(field_path) IN ('brandcatalogname', 'brand_catalog_name') THEN 1
      WHEN LOWER(field_path) IN ('manufacturerbrandname', 'manufacturer_brand_name') THEN 2
      WHEN LOWER(field_path) IN ('productbrandname', 'product_brand_name') THEN 3
      WHEN LOWER(field_path) IN ('supplierbrandname', 'supplier_brand_name') THEN 4
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'brand.*name|name.*brand') THEN 5
      ELSE 6
    END,
    field_path
  LIMIT 1
);

-- Result set 1: shows the actual product/catalog brand field being used.
SELECT product_brand_field AS product_brand_field_used;

IF product_brand_field IS NULL THEN
  SELECT
    'No row-level product/catalog brand field was found on retail_sku_store_date_agg. Check INFORMATION_SCHEMA for the correct brand field before running the count.' AS error_message;
ELSE
  SET report_sql = FORMAT(
    """
    WITH reporting_month AS (
      SELECT
        COALESCE(@target_month_start, MAX(retail_sku_store_date.date)) AS month_start
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
      LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
      LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
        ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
      WHERE retail_sku_store_date.agg_level = 'MONTHLY'
        AND retail_sku_store_date.brandname = 'Wayfair'
        AND retail_sku_store_date.styname = @target_country
        AND retail_dim_supplier.origsuid = @target_supplier_id
    ),

    supplier_skus AS (
      SELECT DISTINCT
        COALESCE(
          NULLIF(TRIM(supplier_part_struct.supplierpartnumber), ''),
          CAST(supplier_part_struct.id AS STRING)
        ) AS sku,
        CAST(retail_sku_store_date.`%s` AS STRING) AS source_brand,
        normalize_brand(CAST(retail_sku_store_date.`%s` AS STRING)) AS source_brand_key
      FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
      LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
      LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
      LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
        ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
      CROSS JOIN reporting_month
      WHERE retail_sku_store_date.agg_level = 'MONTHLY'
        AND retail_sku_store_date.brandname = 'Wayfair'
        AND retail_sku_store_date.styname = @target_country
        AND retail_sku_store_date.date = reporting_month.month_start
        AND retail_dim_supplier.origsuid = @target_supplier_id
        AND supplier_part_struct IS NOT NULL
        AND COALESCE(
          NULLIF(TRIM(supplier_part_struct.supplierpartnumber), ''),
          CAST(supplier_part_struct.id AS STRING)
        ) IS NOT NULL
    )

    SELECT
      requested_brands.brand,
      COUNT(DISTINCT supplier_skus.sku) AS sku_count,
      @target_supplier_id AS supplier_id,
      (SELECT month_start FROM reporting_month) AS month_start,
      '%s' AS product_brand_field_used
    FROM requested_brands
    LEFT JOIN supplier_skus
      ON supplier_skus.source_brand_key = requested_brands.brand_key
    GROUP BY
      requested_brands.sort_order,
      requested_brands.brand
    ORDER BY requested_brands.sort_order
    """,
    product_brand_field,
    product_brand_field,
    product_brand_field
  );

  -- Result set 2: SKU counts by requested brand.
  EXECUTE IMMEDIATE report_sql
  USING
    target_country AS target_country,
    target_month_start AS target_month_start,
    target_supplier_id AS target_supplier_id;
END IF;
