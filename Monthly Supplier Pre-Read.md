# Monthly Supplier Pre-Read workflow

This repo now includes a second n8n workflow export: `Monthly Supplier Pre-Read.json`.

## What it does

- exposes an n8n form so you can type in a single `supplier_id` / SuID
- optionally lets you override the recipient email and portfolio owner filter
- pulls the last fully closed month, prior month, and same month last year
- builds a supplier pre-read email with:
  - executive summary bullets
  - GRS, visits, CVR, availability, MRPI, and WSI snapshot table
  - optional context notes from the form submission
- emails the pre-read using the same Gmail credential already referenced by the weekly workflow

## Files

- `Weekly Supplier Report.json` - existing weekly portfolio workflow
- `Monthly Supplier Pre-Read.json` - new single-supplier monthly pre-read workflow

## Expected credentials

The workflow is wired to the same credentials already present in the weekly export:

- Google BigQuery account 352
- Gmail account 287

If your n8n instance uses different credential names/IDs, remap them after import.

## How to use in n8n

1. Import `Monthly Supplier Pre-Read.json`.
2. Open the `Form Trigger` node and copy either the test URL or production URL.
3. Submit the form with:
   - `supplier_id`: the supplier SuID you want to pre-read
   - `recipient_email`: where the pre-read should be sent
   - `portfolio_owner`: defaults to `Hannigan, Benjamin`
   - `context_notes`: optional meeting notes or prompts
4. Activate the workflow if you want to use the production URL.
5. Check the email output from the `Build Pre-Read Email` node if you want to preview the HTML before sending.

## Query logic notes

- revenue, traffic, and availability use monthly aggregation from the existing retail reporting tables
- MRPI and WSI use the latest weekly snapshot within each selected month so the pre-read can still surface those operational signals without hard-coding a single index date
- the reporting month is the last fully closed month, not the in-flight current month

## Recommended next n8n refinements

- add a second delivery path that returns the HTML in-browser instead of only emailing it
- parameterize the portfolio owner through an n8n credential or static data lookup
- tighten the SQL if you want exact metric definitions to match a finance-approved monthly source of truth
