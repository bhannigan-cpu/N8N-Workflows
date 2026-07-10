-- Active Bedroom suppliers split into US and APS supplier groups.
WITH bedroom_suppliers AS (
  SELECT DISTINCT
    suid,
    suname,
    SupplierMarketingCategory,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(SupplierMarketingCategory), r'(^|[^A-Z])US([^A-Z]|$)') THEN 'US'
      WHEN REGEXP_CONTAINS(UPPER(SupplierMarketingCategory), r'(^|[^A-Z])APS([^A-Z]|$)') THEN 'APS'
    END AS supplier_group
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_Supplier_Tiering_Consolidation_CM`
  WHERE SupplierStatus = 'Active'
    AND SupplierMarketingCategory LIKE '%Bedroom%'
    AND (
      REGEXP_CONTAINS(UPPER(SupplierMarketingCategory), r'(^|[^A-Z])US([^A-Z]|$)')
      OR REGEXP_CONTAINS(UPPER(SupplierMarketingCategory), r'(^|[^A-Z])APS([^A-Z]|$)')
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
