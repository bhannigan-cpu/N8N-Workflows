# Loyalty Promo WSC Lift (n8n)

Reusable loyalty case-study workflow. For each new loyalty promo, edit two inputs and run.

## Quick start for a new loyalty event

1. **Re-import** `Loyalty Promo WSC Lift.json` into n8n (required after SQL/email fixes).
2. Open the **Configure Inputs** node and set:
   - `promo_period_id` — CPH / Partner Home promo period ID (must be > 0)
   - `marketing_category` — exact CPH spelling (e.g. `Bedding`, `Window`)
3. Click **Manual Trigger**.

Everything else updates from those inputs:
- participating SKUs come from that promo + category
- promo start/end come from the promo period (unless overridden)
- L10 non-promo baseline auto-selects the last 10 days **before promo start** that fall outside real NA promo windows
- **Extended Discounts, Frequency Product Discounts, Super Rooms, and Source Rooms do not count as promo** (ignored when picking L10)

## Configure Inputs fields

| Field | Required | Default | Purpose |
| --- | --- | --- | --- |
| `promo_period_id` | yes | `0` (must change) | Loyalty promo period ID |
| `marketing_category` | yes | `Bedding` | Marketing category filter |
| `brand_catalog_id` | no | `1` | Wayfair US brand catalog |
| `brand_catalog_name` | no | `Wayfair US` | Label only |
| `store_brand` | no | `Wayfair` | Label only |
| `store_country` | no | `United States` | Label only |
| `l10_non_promo_days` | no | `10` | Baseline lookback length |
| `promo_start_override` | no | blank | `YYYY-MM-DD` if promo dates need override |
| `promo_end_override` | no | blank | `YYYY-MM-DD` if promo dates need override |

## What the workflow does

1. **Configure Inputs** — plug in promo ID + marketing category
2. **Build SQL Query** — injects those inputs into the lift SQL
3. **Pull Loyalty WSC Lift SKUs** — BigQuery:
   - CPH participating SKUs (`tbl_promo_parts_engagement`)
   - loyalty-window **WSC** from `retail_fact_order_product_revenue_cost` (SoID 49)
   - L10 non-promo **WSC** for the same SKUs
   - daily averages + lift + run diagnostics
4. **Build Analysis** — category / class / supplier / discount / baseline / SKU summaries
5. **Create Spreadsheet** + append tabs
6. **Prepare Email With Sheet Link** — injects the Google Sheet URL into the email
7. **Send Case Study Email** — HTML case study including the workbook link

## Metric

Uses **WSC** (`ProductCostNoRebates` on the order-cost fact, Wayfair US / SoID 49), not GRS.

L10 baseline days come from `tbl_promo_calendar` (GEO = NA), taking dates before promo start that are **not** inside a real promo window. Names matching Extended / Frequency / Super Room / Source Room are ignored so those long-running discounts do not wipe out the baseline. The email/sheet include `non_promo_dates_list` with the exact days used.

- `non_promo_avg` = L10 non-promo WSC / N days
- `loyalty_avg` = promo-window WSC / promo day count
- `incremental_wsc` = loyalty_avg − non_promo_avg
- `lift_pct` = incremental_wsc / non_promo_avg

## If sales come back as $0

The email includes a yellow diagnostics box when both promo and L10 WSC are zero. Check:

1. **Re-import the latest workflow JSON** — older copies still used `retail_sku_store_date_agg` with `agg_level = 'DAILY'`, which returns no rows.
2. **`promo_period_id`** is the real CPH ID (not left at `0`).
3. **`marketing_category`** matches CPH exactly (case/spelling).
4. **Promo dates** in the email look right; if not, set `promo_start_override` / `promo_end_override`.
5. **Diagnostics row fields** on the SKU sheet / email:
   - `participating_sku_count` > 0 — CPH filter worked
   - `sku_key_count` ≈ participating count — SKU→skuid resolution worked
   - `skus_with_any_wsc` > 0 — order financials matched those dates
6. If the event just ended, wait for order financials to land (often next day) and rerun.
7. Optional smoke check in BigQuery: pick one participating SKU + SoID 49 + the promo date range against `retail_fact_order_product_revenue_cost`.

## Files

| Path | Purpose |
| --- | --- |
| `Loyalty Promo WSC Lift.json` | Importable workflow |
| `workflow_exports/loyalty-promo-wsc-lift.json` | Same export |
| `workflow_assets/loyalty_promo_lift.sql` | BigQuery template |
| `workflow_assets/loyalty_promo_lift_build_sql.js` | Input → SQL builder |
| `workflow_assets/loyalty_promo_lift_analysis.js` | Analysis / report Code node |
| `workflow_assets/loyalty_promo_lift_prepare_email.js` | Injects spreadsheet URL into email |
| `tools/build_loyalty_promo_wsc_lift_workflow.py` | Regenerates workflow JSON |

`Bedding Member Monday Loyalty Lift.json` is kept as an alias of the same reusable workflow.

## Rebuild

```bash
python3 tools/build_loyalty_promo_wsc_lift_workflow.py
```
