-- Active Bedroom suppliers split into US and APS supplier groups.
-- This uses the table's built-in MasterGroup classification instead of trying
-- to infer US/APS from SupplierMarketingCategory text.
WITH source_suppliers AS (
  SELECT DISTINCT
    suid,
    suname,
    SupplierMarketingCategory,
    MasterGroup
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_Supplier_Tiering_Consolidation_CM`
  WHERE SupplierStatus = 'Active'
    AND SupplierMarketingCategory LIKE '%Bedroom%'
    AND MasterGroup IN ('US', 'APS')
),

us_suppliers AS (
  SELECT
    'US' AS supplier_group,
    suid,
    suname,
    SupplierMarketingCategory,
    MasterGroup
  FROM source_suppliers
  WHERE MasterGroup = 'US'
),

aps_suppliers AS (
  SELECT
    'APS' AS supplier_group,
    suid,
    suname,
    SupplierMarketingCategory,
    MasterGroup
  FROM source_suppliers
  WHERE MasterGroup = 'APS'
)

SELECT
  supplier_group,
  suid,
  suname,
  SupplierMarketingCategory,
  MasterGroup
FROM us_suppliers

UNION ALL

SELECT
  supplier_group,
  suid,
  suname,
  SupplierMarketingCategory,
  MasterGroup
FROM aps_suppliers

ORDER BY
  CASE supplier_group
    WHEN 'US' THEN 1
    WHEN 'APS' THEN 2
  END,
  suname,
  suid;
