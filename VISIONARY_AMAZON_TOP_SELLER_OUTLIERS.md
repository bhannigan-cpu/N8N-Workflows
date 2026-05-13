# Visionary Amazon top-seller outlier analysis

This repository does not contain a runnable application, so the deliverable for this request is a reusable BigQuery SQL file that answers the exact business question:

- start from a supplied list of Visionary part numbers that are strong on Amazon
- rank those parts against all Visionary parts by last-6-month sales
- identify which Amazon winners are underperforming inside Visionary
- label the most likely reason they are not succeeding

## Files

- `visionary_amazon_top_seller_outliers.sql`: BigQuery query for supplier `78708`
- `Weekly Supplier Report.json`: original supplier-level reference workflow from the repo

## What the query does

1. Filters the retail fact table to Visionary supplier `78708`.
2. Uses `supplier_part_struct.supplierpartnumber` as the canonical part key.
3. Builds the full Visionary part universe across the last 6 monthly periods.
4. Aggregates part-level GRS, product cost, order count, catalog months, selling months, and availability.
5. Ranks every Visionary part by L6M GRS.
6. Joins the Amazon winner list provided in this task.
7. Flags parts as outliers when they have one or more of these symptoms:
   - no match to Visionary's part-number field
   - no L6M sales
   - bottom-quartile sales rank within Visionary
   - L6M GRS less than half the median of the selected Amazon-winner set
   - recent 3-month revenue materially below the prior 3 months
8. Assigns a reason bucket and a recommended next step.

## Reason buckets

The SQL outputs one of these high-level labels:

- `catalog-match-issue`
- `no-sales`
- `availability-constrained`
- `momentum-loss`
- `traffic-or-conversion`
- `price-or-value`
- `below-peer-benchmark`

## Important caveat

The supplied Visionary query included visits and conversion, but in the existing repo and schema examples those traffic arrays are not validated at supplier-part grain. To avoid inventing a weak join, this query uses part-level sales, product cost, and availability directly, then uses `traffic-or-conversion` as an inference only when availability is healthy but sales are still weak.

## How to use it

1. Run `visionary_amazon_top_seller_outliers.sql` in BigQuery.
2. Review rows where `is_outlier = TRUE`.
3. Use `outlier_bucket`, `why_not_succeeding`, and `recommended_next_step` to prioritize investigation.
4. If you later confirm a part-grain traffic dataset, extend the query to separate low-traffic from low-conversion parts more explicitly.
