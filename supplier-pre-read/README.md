# Monthly Supplier Pre-Read (Cursor workflow)

Repeatable process for turning a **Monthly Supplier Report** PDF into a supplier-call **Pre-Read** in your Payless format.

## Go-forward usage

In this Cursor conversation (or a new one with this repo/context):

1. Upload the supplier **Monthly Supplier Report** PDF (Looker export).
2. Upload the **class/category Monthly Supplier Report** PDF (e.g. Blinds & Shades) for comps.
3. Say which supplier / team (e.g. Payless Decor Team) and the meeting date if known.
4. Optionally attach anything else still missing:
   - branded competitiveness chart / % uncompetitive
   - promotions / key asks / assortment notes
5. I will:
   - extract LCM metrics, traffic, CVR, ads, B2B, availability, fill rate from the **supplier** report
   - crop supplier dashboard screenshots
   - compute over/under indexing vs class using **only MoM % and YoY %** from the class/category report
   - draft a Pre-Read matching `templates/SECTION_MAP.md`

### Class/category comparison rules

- Use the class/category MSR for **percentage comps only** (MoM %, YoY %, CVR indexing).
- **Never** put class/category dollar values or visit counts into the Pre-Read comparison text.
- Supplier absolute $ / visit figures stay; class contributes rates only.

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

1. **Class/category Monthly Supplier Report** each month (for MoM/YoY % comps only)  
2. **Branded Competitiveness** (% uncompetitive + chart) when you want that section filled  
3. Any month-specific **Key Asks** (promotions, assortment, tickets)

## Related automation

There is also an n8n form workflow draft on branch/PR for BigQuery-backed ad hoc pre-reads (`Ad Hoc Supplier Pre-Read`). This Cursor PDF→Pre-Read flow is complementary: better for screenshot fidelity and your exact Google Doc voice.
