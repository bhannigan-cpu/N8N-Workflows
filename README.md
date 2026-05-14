## Supplier SKU State Sales Report

This repository includes two ways to run the same supplier sales report:

- `supplier_sku_state_sales_report.sql` - direct BigQuery script
- `Supplier SKU State Sales Report.json` - importable n8n workflow

### What the report does

The report builds supplier sales output at SKU and state grain.

For the configured supplier, it returns:

- every SKU/state row with revenue, units sold, and order count
- total revenue, units, and orders by state
- a ranked state summary showing which states sell the most product
- the top-selling state for each SKU
- a full state ranking for every SKU

### Default supplier

Both versions are preconfigured for:

- supplier: `HLC.ME`
- suID: `29955`

## Run it directly in BigQuery

Open `supplier_sku_state_sales_report.sql` in the BigQuery editor and run it.

The first `DECLARE` values are the only inputs you usually need to change:

- `supplier_name_input`
- `supplier_id_input`
- `lookback_weeks_input`

Optional override fields are also available if the schema uses different names:

- `state_field_override`
- `sku_field_override`
- `sku_name_field_override`
- `quantity_field_override`

### BigQuery outputs

The script returns multiple result sets in this order:

1. resolved configuration and warnings
2. overall supplier totals
3. state totals ranked by revenue
4. top-selling state for each SKU
5. full state ranking for every SKU
6. full SKU-by-state detail

### Field detection

The script queries `wf-gcp-us-ae-retail-prod.cm_reporting.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
for `retail_sku_store_date_agg` to auto-detect likely fields for:

- state
- SKU key
- SKU name
- quantity

If the guessed field is wrong, set one or more of the override values near the
top of the script and rerun it.

## Run it in n8n instead

If you still want the n8n version:

1. Import `Supplier SKU State Sales Report.json` into n8n.
2. Open the `Report Config` node.
3. Set:
   - `supplier_name`
   - `supplier_id`
   - `lookback_weeks`
   - optional field overrides if auto-detection picks the wrong BigQuery field
4. Run the workflow manually.

The final `Build Supplier Report` node returns:

- `overallTotals`
- `stateTotals`
- `skuSummary`
- `topSkusByState`
- `skuStateDetail`
- `markdownReport`
- `htmlReport`
