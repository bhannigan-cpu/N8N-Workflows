-- Active Bedroom suppliers split into US and APS supplier groups.
WITH bedroom_suppliers AS (
  SELECT DISTINCT
    suid,
    suname,
    SupplierMarketingCategory,
    CASE
      WHEN SupplierMarketingCategory LIKE 'US %' THEN 'US'
      WHEN SupplierMarketingCategory LIKE 'APS %' THEN 'APS'
    END AS supplier_group
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_Supplier_Tiering_Consolidation_CM`
  WHERE SupplierStatus = 'Active'
    AND SupplierMarketingCategory LIKE '%Bedroom%'
    AND (
      SupplierMarketingCategory LIKE 'US %'
      OR SupplierMarketingCategory LIKE 'APS %'
    )
)

SELECT
  supplier_group,
  suid,
  suname,
  SupplierMarketingCategory
FROM bedroom_suppliers
ORDER BY
  CASE supplier_group
    WHEN 'US' THEN 1
    WHEN 'APS' THEN 2
  END,
  suname,
  suid;
