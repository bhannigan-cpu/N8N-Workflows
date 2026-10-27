## Supplier SKU State Sales Report

This repository includes multiple ways to run the same supplier sales report:

- `discover_order_financials_field_paths.sql` - helper query for `tbl_fact_order_financials`
- `supplier_sku_state_sales_from_order_financials.sql` - direct BigQuery script built for `tbl_fact_order_financials`
- `discover_supplier_sales_field_paths.sql` - helper query to discover the correct state, SKU, SKU name, and quantity fields
- `supplier_sku_state_sales_report_simple.sql` - simpler direct BigQuery script with explicit field expressions
- `supplier_sku_state_sales_report.sql` - direct BigQuery script with field auto-detection
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

### Best option if you have order financials

If you can use:

- `wf-gcp-us-ae-sf-prod.curated_data_hub.tbl_fact_order_financials`

then start with:

1. `discover_order_financials_field_paths.sql`
2. `supplier_sku_state_sales_from_order_financials.sql`

This is likely the best source for the request because it should already contain
order-level sales facts and state-level destination data.

The order financials script expects you to paste explicit expressions for:

- supplier ID
- supplier name
- state
- SKU
- SKU name
- quantity
- revenue
- order ID
- order date

That keeps the report much easier to debug than the older nested retail table
approach.

### Recommended first: simple BigQuery script

Open `supplier_sku_state_sales_report_simple.sql` in the BigQuery editor and run it.

This version avoids `INFORMATION_SCHEMA` lookups and is the best option if the
auto-detect script fails.

If you do not know the right field names yet, run
`discover_supplier_sales_field_paths.sql` first and copy the returned
`suggested_expression` values into the simple script.

The first values to check are:

- `supplier_name_input`
- `supplier_id_input`
- `lookback_weeks_input`
- `state_sql`
- `sku_sql`
- `sku_name_sql`
- `quantity_sql`

The `*_sql` values are regular SQL expressions using the table aliases already
present in the query, so you can point them directly at the fields your dataset
actually uses.

### Auto-detect BigQuery script

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
