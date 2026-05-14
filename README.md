## Supplier SKU State Sales Report

This repository now includes an importable n8n workflow:

- `Supplier SKU State Sales Report.json`

### What it does

The workflow builds a supplier-level sales report at SKU and state grain.

For the configured supplier, it returns:

- every SKU/state row with revenue, units sold, and order count
- total revenue, units, and orders by state
- a ranked state summary showing which states sell the most product
- a per-SKU summary showing the top-selling state for each SKU

### Default supplier

The workflow is preconfigured for:

- supplier: `HLC.ME`
- suID: `29955`

### How to use it

1. Import `Supplier SKU State Sales Report.json` into n8n.
2. Open the `Report Config` node.
3. Set:
   - `supplier_name`
   - `supplier_id`
   - `lookback_weeks`
   - optional field overrides if auto-detection picks the wrong BigQuery field
4. Run the workflow manually.

### Notes on field detection

The workflow first queries `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` for
`retail_sku_store_date_agg` to detect likely fields for:

- state
- SKU key
- SKU name
- quantity

If the dataset uses different field names than the guessed defaults, set one or
more of these override values in `Report Config`:

- `state_field_override`
- `sku_field_override`
- `sku_name_field_override`
- `quantity_field_override`

### Output

The final `Build Supplier Report` node returns:

- `overallTotals`
- `stateTotals`
- `skuSummary`
- `topSkusByState`
- `skuStateDetail`
- `markdownReport`
- `htmlReport`
