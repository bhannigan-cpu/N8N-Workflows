# Ad Hoc Supplier Pre-Read workflow

This repo now includes an ad hoc n8n workflow export: `Ad Hoc Supplier Pre-Read.json`.

## What changed

The workflow now follows the user's meeting-note format more closely instead of using a generic monthly scorecard layout.

It now:

- exposes an n8n form so you can type in a single `supplier_id` / SuID
- optionally captures:
  - greeting / team name
  - unfindables notes
  - ad hoc notes
- pulls a dashboard-aligned monthly snapshot based on the `monthly_supplier_report` dashboard defaults
- generates the pre-read in sections such as:
  - Business Review
  - Traffic
  - Availability
  - Wayfair Professional
  - Advertising
  - Dropship Performance
  - Promotions
  - Assortment
  - Unfindables
  - Ad Hoc
- moves **Unfindables** near the bottom and labels the bottom freeform section **Ad Hoc**

## Dashboard alignment

The workflow references the dashboard the user provided:

- dashboard: `monthly_supplier_report`
- title: `Monthly Supplier Report`
- slug: `hxVugArzfrkD6YuI94A2dq`
- link: `https://partners.wayfair.com/d/hxVugArzfrkD6YuI94A2dq/monthly-supplier-report`

The automated query currently aligns most directly to the dashboard's monthly WSC, traffic, and availability-style sections. The email also links back to the dashboard so class breakdowns, assortment views, advertising grids, and deeper operational tiles can be reviewed alongside the generated draft.

## Expected credentials

The workflow is wired to the same credentials already present in the weekly export:

- Google BigQuery account 352
- Gmail account 287

If your n8n instance uses different credential names or IDs, remap them after import.

## How to use in n8n

1. Import `Ad Hoc Supplier Pre-Read.json`.
2. Open the `Form Trigger` node and copy either the test URL or production URL.
3. Submit the form with:
   - `supplier_id`: the supplier SuID you want to pre-read
   - `recipient_email`: where the draft should be sent
   - `team_name`: optional salutation override like `Home Weavers team`
   - `portfolio_owner`: defaults to `Hannigan, Benjamin`
   - `unfindables_notes`: optional note block near the bottom
   - `ad_hoc_notes`: optional bottom catch-all section
4. Activate the workflow if you want to use the production URL.
5. Check the output of `Build Ad Hoc Email` if you want to preview the formatted HTML before sending.

## Query notes

- the reporting month is the last fully closed month
- WSC uses `productcostnorebates` so the headline is aligned to the dashboard's sales framing
- traffic and availability are pulled from the same retail reporting source used in the existing workflow
- MRPI and WSI still use the latest weekly snapshot inside each selected month
- some sections in the final pre-read are intentionally narrative / dashboard-assisted rather than fully auto-populated from SQL
