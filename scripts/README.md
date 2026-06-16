# Bedding SKU launch list

Use `list_bedding_sku_launches.sh` to query BigQuery for SKUs launched in the
Bedding product marketing category over a recent day window.

```bash
scripts/list_bedding_sku_launches.sh --days 14 --format csv
```

The script defaults to:

- Execution project: `wf-gcp-us-ae-eunarta-proc-prod`
- SKU table: `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku`
- SKU column: `prsku`
- Product marketing category column: `productmarketingcategory`
- Launch date column: `launchdate`
- Category value: `Bedding`

If the catalog table uses different names, pass them as options:

```bash
scripts/list_bedding_sku_launches.sh \
  --days 30 \
  --sku-table wf-gcp-us-ae-retail-prod.cm_reporting.your_sku_table \
  --sku-column prsku \
  --category-column productmarketingcategory \
  --launch-date-column launchdate \
  --product-name-column productname \
  --format csv
```

To discover candidate SKU/catalog tables in BigQuery:

```sql
SELECT table_name
FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.TABLES`
WHERE LOWER(table_name) LIKE '%sku%'
   OR LOWER(table_name) LIKE '%product%'
   OR LOWER(table_name) LIKE '%launch%'
ORDER BY table_name;
```

Then inspect likely columns:

```sql
SELECT column_name, data_type
FROM `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = '<table_name>'
  AND (
    LOWER(column_name) LIKE '%launch%'
    OR LOWER(column_name) LIKE '%market%'
    OR LOWER(column_name) LIKE '%category%'
    OR LOWER(column_name) LIKE '%sku%'
  )
ORDER BY column_name;
```

## New SKUs with supplier L12M GRS

Use `../sql/new_skus_with_supplier_l12m_grs.sql` in the BigQuery editor to list
all SKUs launched in the last 90 days with their supplier and supplier-level GRS
metrics.

The SQL reports:

- SKU and launch date proxy
- Supplier key, supplier ID, and supplier name
- Supplier L12M GRS
- Supplier prior-L12M GRS
- Supplier L12M GRS change
- Supplier L12M GRS growth rate

The growth rate is calculated as:

```text
(supplier_l12m_grs - supplier_prior_l12m_grs) / supplier_prior_l12m_grs
```

Because the SKU dimension table does not expose `launchdate`, this query uses
the first date a SKU/supplier pair appears in
`cm_reporting.retail_sku_store_date_agg` as the launch date proxy. It
dynamically detects the SKU column from common SKU field names on that table,
then uses `retail_dim_supplier` and the currency conversion table from the
weekly supplier workflow.
