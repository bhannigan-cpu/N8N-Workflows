# Bedding Member Monday Loyalty Lift (n8n)

Packages the Bedding Member Monday performance case study into an importable n8n workflow.

## What it does

1. **Pull participating loyalty SKUs** for Bedding from Cost Performance Hub / Partner Home promo participation (`tbl_promo_parts_engagement`) — the same grain as CPH **Single Promo Detail**.
2. **Pull Wayfair US daily GRS** for those SKUs during the loyalty promo window.
3. **Pull Wayfair US daily GRS** for the last **10 non-promo days** before the event (`tbl_Pricing_tmp_NonPromo_Dates_Month_Week_FullData`).
4. **Compute daily averages + lift** at SKU level:
   - `non_promo_avg = L10 non-promo GRS / 10`
   - `loyalty_avg = promo-window GRS / promo day count`
   - `lift_pct = (loyalty_avg - non_promo_avg) / non_promo_avg`
5. **Build the member analysis** at:
   - category
   - class
   - supplier
   - discount bucket
   - baseline-success tier
   - SKU
6. **Write a Google Sheet** with those tabs and **email** the executive case study.

## Files

| Path | Purpose |
| --- | --- |
| `Bedding Member Monday Loyalty Lift.json` | Importable n8n workflow |
| `workflow_exports/bedding-member-monday-loyalty-lift.json` | Same export under `workflow_exports/` |
| `workflow_assets/bedding_member_monday_lift.sql` | BigQuery lift query |
| `workflow_assets/bedding_member_monday_analysis.js` | n8n Code node analysis |
| `tools/build_bedding_member_monday_workflow.py` | Regenerates the workflow JSON |

## How to run

1. Import `Bedding Member Monday Loyalty Lift.json` into n8n.
2. Confirm BigQuery / Gmail / Google Sheets credentials resolve (same accounts as Weekly Supplier Report).
3. Open **Pull Loyalty Lift SKUs** and edit the `inputs` CTE:
   - set `Promo_Period_Id` to the loyalty promo period ID from CPH / Partner Home
   - leave `Marketing_Category = 'Bedding'` (or change for another category)
   - optionally override promo start/end dates
4. Click **Manual Trigger**.

## Output

- Google Sheet titled `Bedding Loyalty Lift - {promo name} - {start date}` with tabs:
  - SKU Data
  - Category Summary
  - Class Summary
  - Supplier Summary
  - Discount Buckets
  - Baseline Tiers
- Email to `bhannigan@wayfair.com` with the executive takeaway plus class / supplier / discount tables

## Metric definitions

- **Active SKUs:** participating SKUs with loyalty daily avg > $0
- **Weighted lift %:** incremental sales / non-promo average
- **Weighted discount %:** discount weighted by non-promo average
- **Baseline success tier:** quartile of SKU non-promo average (proxy for normal/historical success)

## Rebuild

```bash
python3 tools/build_bedding_member_monday_workflow.py
```

## Notes / assumptions

- Participating SKUs come from active discounted parts on the chosen promo period, filtered to Bedding — equivalent to exporting CPH Single Promo Detail for that promo + category.
- Non-promo baseline uses Business Trends / NARTA non-promo calendar flags (`PromoFlag_T0T1 = 'N'`), not merely the prior 10 calendar days.
- Class name is resolved from `retail_dim_sku.clname` when not present on the promo engagement row.
- If BigQuery returns a missing-column error on `WSC_L12M` / `GRS_L12M` / `MarketingCategory_SU`, adjust those field names in the SQL to match the live `tbl_promo_parts_engagement` schema in your project.
