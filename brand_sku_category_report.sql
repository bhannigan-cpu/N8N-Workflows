--standardSQL
-- SKU count by brand and category for Thread Made Home (supplier 22255).
--
-- Paste this into a BigQuery node/query editor. The script uses the same
-- reporting table and supplier join pattern as Weekly Supplier Report.json.
-- It normalizes brand names so trademark symbols in the request do not block
-- matches against source-system names that omit them.

DECLARE target_supplier_id INT64 DEFAULT 22255;
DECLARE target_country STRING DEFAULT 'United States';

-- Use the last complete reporting week, matching the existing workflow.
DECLARE target_week_start DATE DEFAULT DATE_SUB(
  DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)),
  INTERVAL 1 WEEK
);

CREATE TEMP FUNCTION normalize_brand(value STRING) AS (
  REGEXP_REPLACE(
    LOWER(TRIM(REGEXP_REPLACE(COALESCE(value, ''), r'[®™]', ''))),
    r'\s+',
    ' '
  )
);

WITH requested_brands AS (
  SELECT 1 AS sort_order, 'Alcott Hill®' AS requested_brand UNION ALL
  SELECT 2, 'AllModern' UNION ALL
  SELECT 3, 'Red Barrel Studio®' UNION ALL
  SELECT 4, 'Gracie Oaks' UNION ALL
  SELECT 5, 'House of Hampton®' UNION ALL
  SELECT 6, 'Astoria Grand' UNION ALL
  SELECT 7, 'Latitude Run®' UNION ALL
  SELECT 8, 'Villeroy & Boch' UNION ALL
  SELECT 9, 'Ivy Bronx' UNION ALL
  SELECT 10, 'Lenox' UNION ALL
  SELECT 11, 'Winston Porter' UNION ALL
  SELECT 12, 'Mercer41' UNION ALL
  SELECT 13, 'Bungalow Rose' UNION ALL
  SELECT 14, 'Lark Manor™' UNION ALL
  SELECT 15, 'Highland Dunes' UNION ALL
  SELECT 16, 'Charlton Home®' UNION ALL
  SELECT 17, 'Ophelia & Co.' UNION ALL
  SELECT 18, 'August Grove®' UNION ALL
  SELECT 19, 'Rosecliff Heights' UNION ALL
  SELECT 20, 'Rosalind Wheeler' UNION ALL
  SELECT 21, 'The Holiday Aisle®' UNION ALL
  SELECT 22, 'Beachcrest Home™' UNION ALL
  SELECT 23, 'Jonathan Adler' UNION ALL
  SELECT 24, 'Symple Stuff' UNION ALL
  SELECT 25, 'Ebern Designs' UNION ALL
  SELECT 26, 'Canora Grey' UNION ALL
  SELECT 27, 'Rosdorf Park' UNION ALL
  SELECT 28, 'Wildon Home®' UNION ALL
  SELECT 29, '17 Stories' UNION ALL
  SELECT 30, 'Harriet Bee' UNION ALL
  SELECT 31, 'Bay Isle Home™' UNION ALL
  SELECT 32, 'Dakota Fields' UNION ALL
  SELECT 33, 'Breakwater Bay' UNION ALL
  SELECT 34, 'Elrene Home Fashions' UNION ALL
  SELECT 35, 'East Urban Home' UNION ALL
  SELECT 36, 'Wade Logan®' UNION ALL
  SELECT 37, 'Millwood Pines' UNION ALL
  SELECT 38, 'George Oliver' UNION ALL
  SELECT 39, 'Brayden Studio®' UNION ALL
  SELECT 40, 'Darby Home Co' UNION ALL
  SELECT 41, 'Zoomie Kids' UNION ALL
  SELECT 42, 'The Twillery Co.®' UNION ALL
  SELECT 43, 'World Menagerie'
),

brand_lookup AS (
  SELECT
    sort_order,
    requested_brand,
    normalize_brand(requested_brand) AS brand_key
  FROM requested_brands
),

source_rows AS (
  SELECT DISTINCT
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name,

    COALESCE(
      NULLIF(JSON_VALUE(row_json, '$.sku'), ''),
      NULLIF(JSON_VALUE(row_json, '$.SKU'), ''),
      NULLIF(JSON_VALUE(row_json, '$.prsku'), ''),
      NULLIF(JSON_VALUE(row_json, '$.PrSKU'), ''),
      NULLIF(JSON_VALUE(row_json, '$.product_sku'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ProductSKU'), '')
    ) AS sku,

    COALESCE(
      NULLIF(JSON_VALUE(row_json, '$.manufacturer_brand_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.manufacturerbrandname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ManufacturerBrandName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.supplier_brand_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.supplierbrandname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.SupplierBrandName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.brand_catalog_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.brandcatalogname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.BrandCatalogName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.product_brand_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.productbrandname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ProductBrandName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.brand_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.brandname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.BrandName'), '')
    ) AS matched_brand,

    COALESCE(
      NULLIF(JSON_VALUE(row_json, '$.category_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.categoryname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.CategoryName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.product_category_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.productcategoryname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ProductCategoryName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.class_name'), ''),
      NULLIF(JSON_VALUE(row_json, '$.classname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ClassName'), ''),
      NULLIF(JSON_VALUE(row_json, '$.clname'), ''),
      NULLIF(JSON_VALUE(row_json, '$.ClName'), ''),
      'Unknown category'
    ) AS category
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN UNNEST([TO_JSON_STRING(retail_sku_store_date)]) AS row_json
  WHERE retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.styname = target_country
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = target_week_start
    AND retail_dim_supplier.origsuid = target_supplier_id
),

normalized_source AS (
  SELECT
    supplier_id,
    supplier_name,
    sku,
    matched_brand,
    normalize_brand(matched_brand) AS brand_key,
    category
  FROM source_rows
  WHERE sku IS NOT NULL
    AND matched_brand IS NOT NULL
),

category_counts AS (
  SELECT
    brand_lookup.sort_order,
    brand_lookup.requested_brand,
    normalized_source.category,
    COUNT(DISTINCT normalized_source.sku) AS sku_count,
    STRING_AGG(DISTINCT normalized_source.matched_brand, ', ' ORDER BY normalized_source.matched_brand) AS matched_source_brands
  FROM brand_lookup
  JOIN normalized_source
    ON normalized_source.brand_key = brand_lookup.brand_key
  GROUP BY
    brand_lookup.sort_order,
    brand_lookup.requested_brand,
    normalized_source.category
),

brand_totals AS (
  SELECT
    brand_lookup.sort_order,
    COUNT(DISTINCT normalized_source.sku) AS total_sku_count
  FROM brand_lookup
  LEFT JOIN normalized_source
    ON normalized_source.brand_key = brand_lookup.brand_key
  GROUP BY brand_lookup.sort_order
)

SELECT
  brand_lookup.requested_brand AS brand,
  COALESCE(category_counts.category, 'No matching SKUs found') AS category,
  COALESCE(category_counts.sku_count, 0) AS sku_count,
  COALESCE(brand_totals.total_sku_count, 0) AS total_sku_count_for_brand,
  category_counts.matched_source_brands,
  target_supplier_id AS supplier_id,
  target_week_start AS week_start
FROM brand_lookup
LEFT JOIN category_counts
  ON category_counts.sort_order = brand_lookup.sort_order
LEFT JOIN brand_totals
  ON brand_totals.sort_order = brand_lookup.sort_order
ORDER BY
  brand_lookup.sort_order,
  sku_count DESC,
  category;
