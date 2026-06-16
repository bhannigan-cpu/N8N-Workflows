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
