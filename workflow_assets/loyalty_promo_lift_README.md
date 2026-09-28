# Loyalty Promo WSC Lift (n8n)

Reusable loyalty case-study workflow. For each new loyalty promo, edit two inputs and run.

## Quick start for a new loyalty event

1. Import `Loyalty Promo WSC Lift.json` into n8n (or re-import to refresh).
2. Open the **Configure Inputs** node and set:
   - `promo_period_id` — CPH / Partner Home promo period ID
   - `marketing_category` — supplier marketing category (e.g. `Bedding`, `Window`)
3. Click **Manual Trigger**.

Everything else updates from those inputs:
- participating SKUs come from that promo + category
- promo start/end come from the promo period (unless overridden)
- L10 non-promo baseline auto-selects the last 10 non-promo Wayfair US days **before promo start**

## Configure Inputs fields

| Field | Required | Default | Purpose |
| --- | --- | --- | --- |
| `promo_period_id` | yes | `0` (must change) | Loyalty promo period ID |
| `marketing_category` | yes | `Bedding` | Marketing category filter |
| `brand_catalog_id` | no | `1` | Wayfair US |
| `brand_catalog_name` | no | `Wayfair US` | Label only |
| `store_brand` | no | `Wayfair` | Retail store brand |
| `store_country` | no | `United States` | Retail country |
| `l10_non_promo_days` | no | `10` | Baseline lookback length |
| `promo_start_override` | no | blank | `YYYY-MM-DD` if promo dates need override |
| `promo_end_override` | no | blank | `YYYY-MM-DD` if promo dates need override |

## What the workflow does

1. **Configure Inputs** — plug in promo ID + marketing category
2. **Build SQL Query** — injects those inputs into the lift SQL
3. **Pull Loyalty WSC Lift SKUs** — BigQuery:
   - CPH participating SKUs (`tbl_promo_parts_engagement`)
   - loyalty-window **WSC**
   - L10 non-promo **WSC**
   - daily averages + lift
4. **Build Analysis** — category / class / supplier / discount / baseline / SKU summaries
5. **Create Spreadsheet** + append tabs
6. **Send Case Study Email**

## Metric

Uses **WSC** (`orders.productcostnorebates`, USD), not GRS.

- `non_promo_avg` = L10 non-promo WSC / N days
- `loyalty_avg` = promo-window WSC / promo day count
- `incremental_wsc` = loyalty_avg − non_promo_avg
- `lift_pct` = incremental_wsc / non_promo_avg

## Files

| Path | Purpose |
| --- | --- |
| `Loyalty Promo WSC Lift.json` | Importable workflow |
| `workflow_exports/loyalty-promo-wsc-lift.json` | Same export |
| `workflow_assets/loyalty_promo_lift.sql` | BigQuery template |
| `workflow_assets/loyalty_promo_lift_build_sql.js` | Input → SQL builder |
| `workflow_assets/loyalty_promo_lift_analysis.js` | Analysis / report Code node |
| `tools/build_loyalty_promo_wsc_lift_workflow.py` | Regenerates workflow JSON |

`Bedding Member Monday Loyalty Lift.json` is kept as an alias of the same reusable workflow.

## Rebuild

```bash
python3 tools/build_loyalty_promo_wsc_lift_workflow.py
```
