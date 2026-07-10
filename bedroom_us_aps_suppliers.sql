-- Active Bedroom suppliers split into US and APS supplier groups.
-- APS suppliers are explicitly identified by the APS prefix; US suppliers are
-- the remaining active Bedroom suppliers in this tiering table.
WITH bedroom_suppliers AS (
  SELECT DISTINCT
    suid,
    suname,
    SupplierMarketingCategory,
    CASE
      WHEN SupplierMarketingCategory LIKE 'APS %' THEN 'APS'
      ELSE 'US'
    END AS supplier_group
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_Supplier_Tiering_Consolidation_CM`
  WHERE SupplierStatus = 'Active'
    AND SupplierMarketingCategory LIKE '%Bedroom%'
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
