--standardSQL
-- Low-scan SKU count by brand and category for Thread Made Home (supplier 22255).
--
-- This request should not require scanning retail_sku_store_date_agg. That
-- weekly aggregate is useful for sales/performance metrics, but it is far too
-- large for a simple "which SKUs are in which brand/category" lookup.
--
-- This script first uses INFORMATION_SCHEMA metadata to find a flatter
-- SKU/catalog-style table in cm_reporting with supplier, SKU, brand, and
-- category/class fields. Metadata scans are tiny. It then dynamically queries
-- only those columns from the best candidate table.
--
-- If the selected table looks wrong, run just the "candidate_source_tables"
-- SELECT below and use one of the other candidate table names/fields.

DECLARE target_supplier_id STRING DEFAULT '22255';
-- Keep FALSE for the first run. Review result set 1, then change to TRUE once
-- the selected source table is a flat SKU/catalog table.
DECLARE run_report BOOL DEFAULT FALSE;
DECLARE report_sql STRING;

CREATE TEMP FUNCTION normalize_match(value STRING) AS (
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
SELECT 43, 'World Menagerie';

CREATE TEMP TABLE candidate_source_tables AS
WITH field_paths AS (
  SELECT
    table_name,
    field_path
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
  WHERE NOT REGEXP_CONTAINS(LOWER(table_name), r'(agg|fact|order|traffic|visit|weekly|daily|event|log)')
    -- Prefer flat dimension/catalog tables. Nested paths usually require
    -- UNNESTs and are more likely to sit on wider/heavier fact tables.
    AND NOT REGEXP_CONTAINS(field_path, r'\.')
),

classified_fields AS (
  SELECT
    table_name,
    field_path,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'^(origsuid|original_supplier_id|supplier_id|supplierid|suid)$')
        THEN 'supplier_id'
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'^(origsuname|supplier_name|suppliername)$')
        THEN 'supplier_name'
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'^(prsku|sku|sku_id|skuid|product_sku|productsku|part_number|partnumber)$')
        THEN 'sku'
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(manufacturer_brand|supplier_brand|brand_catalog|product_brand|brand).*(name)$|^(brandname|brand_name)$')
        THEN 'brand'
      WHEN REGEXP_CONTAINS(LOWER(field_path), r'(category|class|dept|department).*(name)$|^(clname|classname|categoryname|departmentname)$')
        THEN 'category'
      ELSE NULL
    END AS field_type,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(table_name), r'(sku|product|catalog|part|class|category)') THEN 200
      ELSE 0
    END
    + CASE
        WHEN REGEXP_CONTAINS(LOWER(field_path), r'^(origsuid|prsku|sku|brandname|brand_name|clname|classname|categoryname|category_name)$') THEN 50
        ELSE 0
      END AS score
  FROM field_paths
),

ranked_fields AS (
  SELECT
    table_name,
    field_type,
    field_path,
    score,
    ROW_NUMBER() OVER (
      PARTITION BY table_name, field_type
      ORDER BY score DESC, field_path
    ) AS field_rank
  FROM classified_fields
  WHERE field_type IS NOT NULL
),

table_fields AS (
  SELECT
    table_name,
    MAX(IF(field_type = 'supplier_id', field_path, NULL)) AS supplier_id_field,
    MAX(IF(field_type = 'supplier_name', field_path, NULL)) AS supplier_name_field,
    MAX(IF(field_type = 'sku', field_path, NULL)) AS sku_field,
    MAX(IF(field_type = 'brand', field_path, NULL)) AS brand_field,
    MAX(IF(field_type = 'category', field_path, NULL)) AS category_field,
    SUM(score) AS table_score
  FROM ranked_fields
  WHERE field_rank = 1
  GROUP BY table_name
)
SELECT
  'wf-gcp-us-ae-retail-prod' AS project_id,
  'cm_reporting' AS dataset_id,
  table_name,
  supplier_id_field,
  supplier_name_field,
  sku_field,
  brand_field,
  category_field,
  table_score
FROM table_fields
WHERE supplier_id_field IS NOT NULL
  AND sku_field IS NOT NULL
  AND brand_field IS NOT NULL
  AND category_field IS NOT NULL
ORDER BY table_score DESC, table_name;

-- Result set 1: review this. It should be a short metadata-only result, not a
-- TB-scale scan. The first row is the source used by the final report.
SELECT
  *
FROM candidate_source_tables
ORDER BY table_score DESC, table_name
LIMIT 20;

ASSERT (SELECT COUNT(*) FROM candidate_source_tables) > 0 AS
  'No flat SKU/catalog source was found in cm_reporting metadata. Run the candidate_source_tables logic against another dataset that has product catalog fields, then use the explicit template at the bottom of this file.';

SET report_sql = (
  SELECT FORMAT(
    """
    WITH selected_source AS (
      SELECT DISTINCT
        CAST(src.`%s` AS STRING) AS supplier_id,
        %s AS supplier_name,
        CAST(src.`%s` AS STRING) AS sku,
        CAST(src.`%s` AS STRING) AS source_brand,
        COALESCE(NULLIF(TRIM(CAST(src.`%s` AS STRING)), ''), 'Unknown category') AS category
      FROM `%s.%s.%s` AS src
      WHERE CAST(src.`%s` AS STRING) = @target_supplier_id
    ),

    brand_lookup AS (
      SELECT
        sort_order,
        requested_brand,
        normalize_match(requested_brand) AS brand_key
      FROM requested_brands
    ),

    matched_source AS (
      SELECT DISTINCT
        brand_lookup.sort_order,
        brand_lookup.requested_brand,
        selected_source.sku,
        selected_source.category,
        selected_source.source_brand,
        selected_source.supplier_id,
        selected_source.supplier_name
      FROM brand_lookup
      JOIN selected_source
        ON normalize_match(selected_source.source_brand) = brand_lookup.brand_key
      WHERE selected_source.sku IS NOT NULL
        AND selected_source.source_brand IS NOT NULL
    ),

    category_counts AS (
      SELECT
        sort_order,
        requested_brand,
        category,
        COUNT(DISTINCT sku) AS sku_count,
        STRING_AGG(DISTINCT source_brand, ', ' ORDER BY source_brand) AS matched_source_brands
      FROM matched_source
      GROUP BY
        sort_order,
        requested_brand,
        category
    ),

    brand_totals AS (
      SELECT
        brand_lookup.sort_order,
        COUNT(DISTINCT matched_source.sku) AS total_sku_count
      FROM brand_lookup
      LEFT JOIN matched_source
        ON matched_source.sort_order = brand_lookup.sort_order
      GROUP BY brand_lookup.sort_order
    )

    SELECT
      brand_lookup.requested_brand AS brand,
      COALESCE(category_counts.category, 'No matching SKUs found') AS category,
      COALESCE(category_counts.sku_count, 0) AS sku_count,
      COALESCE(brand_totals.total_sku_count, 0) AS total_sku_count_for_brand,
      category_counts.matched_source_brands,
      @target_supplier_id AS supplier_id,
      '%s.%s.%s' AS source_table
    FROM brand_lookup
    LEFT JOIN category_counts
      ON category_counts.sort_order = brand_lookup.sort_order
    LEFT JOIN brand_totals
      ON brand_totals.sort_order = brand_lookup.sort_order
    ORDER BY
      brand_lookup.sort_order,
      sku_count DESC,
      category
    """,
    supplier_id_field,
    IF(
      supplier_name_field IS NULL,
      "'Unknown supplier'",
      FORMAT("CAST(src.`%s` AS STRING)", supplier_name_field)
    ),
    sku_field,
    brand_field,
    category_field,
    project_id,
    dataset_id,
    table_name,
    supplier_id_field,
    project_id,
    dataset_id,
    table_name
  )
  FROM candidate_source_tables
  ORDER BY table_score DESC, table_name
  LIMIT 1
);

IF run_report THEN
  -- Result set 2: the requested SKU counts by brand/category.
  EXECUTE IMMEDIATE report_sql
  USING target_supplier_id AS target_supplier_id;
ELSE
  SELECT
    'Metadata discovery only. Review result set 1, confirm the first source table is a flat SKU/catalog source, then set run_report = TRUE to run the SKU count.' AS next_step;
END IF;

-- Explicit low-scan template:
-- If you already know the right flat catalog table/columns, skip auto-discovery
-- and use this shape directly. Replace the table and field names only.
--
-- WITH requested_brands AS (...same brand list above...),
-- source AS (
--   SELECT DISTINCT
--     CAST(supplier_id AS STRING) AS supplier_id,
--     CAST(sku AS STRING) AS sku,
--     CAST(brand_name AS STRING) AS source_brand,
--     COALESCE(CAST(category_name AS STRING), CAST(class_name AS STRING), 'Unknown category') AS category
--   FROM `project.dataset.flat_product_catalog_or_sku_dimension`
--   WHERE CAST(supplier_id AS STRING) = '22255'
-- )
-- SELECT source_brand, category, COUNT(DISTINCT sku) AS sku_count
-- FROM source
-- GROUP BY source_brand, category;
