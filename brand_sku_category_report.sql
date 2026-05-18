--standardSQL
-- Direct SKU count by requested brand for Thread Made Home (supplier 22255).
--
-- This intentionally does one thing only:
-- count distinct supplier SKUs for the brand list below.
--
-- Source note:
-- This uses the same confirmed table/join pattern as the existing n8n workflow.
-- It counts SKUs present in the selected MONTHLY reporting slice.

DECLARE target_supplier_id INT64 DEFAULT 22255;
DECLARE target_country STRING DEFAULT 'United States';
DECLARE target_month_start DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH);

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

WITH requested_brands AS (
  SELECT 1 AS sort_order, 'Alcott Hill®' AS brand UNION ALL
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

supplier_skus AS (
  SELECT DISTINCT
    COALESCE(
      NULLIF(TRIM(supplier_part_struct.supplierpartnumber), ''),
      CAST(supplier_part_struct.id AS STRING)
    ) AS sku,
    normalize_brand(TO_JSON_STRING(supplier_part_struct)) AS supplier_part_payload
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  WHERE retail_sku_store_date.agg_level = 'MONTHLY'
    AND retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = target_country
    AND retail_sku_store_date.date = target_month_start
    AND retail_dim_supplier.origsuid = target_supplier_id
    AND supplier_part_struct IS NOT NULL
    AND COALESCE(
      NULLIF(TRIM(supplier_part_struct.supplierpartnumber), ''),
      CAST(supplier_part_struct.id AS STRING)
    ) IS NOT NULL
),

brand_counts AS (
  SELECT
    requested_brands.sort_order,
    requested_brands.brand,
    COUNT(DISTINCT supplier_skus.sku) AS sku_count
  FROM requested_brands
  LEFT JOIN supplier_skus
    ON REGEXP_CONTAINS(
      supplier_skus.supplier_part_payload,
      CONCAT(r'(^| )', normalize_brand(requested_brands.brand), r'( |$)')
    )
  GROUP BY
    requested_brands.sort_order,
    requested_brands.brand
)

SELECT
  brand,
  sku_count,
  target_supplier_id AS supplier_id,
  target_month_start AS month_start
FROM brand_counts
ORDER BY sort_order;
