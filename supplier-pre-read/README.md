# Monthly Supplier Pre-Read (Cursor workflow)

Repeatable process for turning a **Monthly Supplier Report** PDF into a supplier-call **Pre-Read** in your Payless format.

## Go-forward usage

In this Cursor conversation (or a new one with this repo/context):

1. Upload the new **Monthly Supplier Report** PDF (Looker export).
2. Say which supplier / team (e.g. Payless Decor Team) and the meeting date if known.
3. Optionally attach anything **not** in the Monthly Supplier Report:
   - class over/under indexing notes or screenshot
   - branded competitiveness chart / % uncompetitive
   - promotions / key asks / assortment notes
4. I will:
   - extract LCM metrics, traffic, CVR, ads, B2B, availability, fill rate
   - crop the dashboard screenshots
   - draft a Pre-Read matching `templates/SECTION_MAP.md`
   - leave yellow/TODO markers only where a second source is still needed

Paste the finished draft into your living Google Doc:  
https://docs.google.com/document/d/11VbsFgVPNox_8o5b-_EJ0z3QFTYIMgSkdrzn3_yf0X4

## This folder

| Path | Purpose |
|---|---|
| `templates/SECTION_MAP.md` | Fixed section order + field mapping |
| `assets/` | Cropped charts from the latest Monthly Supplier Report |
| `outputs/Payless_Pre-Read_August_2026.md` | Copy/paste draft for Google Docs |
| `outputs/Payless_Pre-Read_August_2026.html` | Formatted preview with embedded screenshots |
| `outputs/Payless_Pre-Read_August_2026.pdf` | Shareable PDF draft |
| `extract_monthly_report.py` | Helper to re-crop/extract text from a future MSR PDF |

## What the Monthly Supplier Report covers well

- WSC / units (LCM, YTD, L12M) + MoM/YoY
- L12M Performance + WSC Change vs Index screenshots
- Traffic (SKU visits) + CVR
- Advertising spend / RoAS → % of WSC
- B2B share + Pro growth
- Availability + dropship fill rate
- Class mix / top SKUs

## What you still need to provide (or confirm)

These appear in your historical Pre-Reads but are **not** in the Monthly Supplier Report PDF alone:

1. **Over / under indexing vs Blinds & Shades Class** for WSC, Traffic, and CVR  
2. **Branded Competitiveness** (% uncompetitive + chart)  
3. Any month-specific **Key Asks** (promotions, assortment, tickets)

If you tell me which dashboard/view you pull class indexing from, I can treat that as a standard second attachment each month.

## Related automation

There is also an n8n form workflow draft on branch/PR for BigQuery-backed ad hoc pre-reads (`Ad Hoc Supplier Pre-Read`). This Cursor PDF→Pre-Read flow is complementary: better for screenshot fidelity and your exact Google Doc voice.
