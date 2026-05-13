# Visionary Amazon winner top-40 exception analysis

This SQL is optimized for a more readable output.

## What it answers

- Rank the supplied Amazon-winning Visionary parts by Wayfair L6M sales.
- Return all requested parts, with a flag showing whether each one falls outside the top 40 on Wayfair.
- For those parts, show which metrics are weak and which periods are down.
- Add a weighted issue score plus a plain-English explanation of what is likely slacking.

## Metrics included

- Wayfair L6M sales rank
- L6M GRS, orders, visits, CVR, and availability
- Gap to the current top-40 GRS floor
- Latest closed month GRS vs prior month GRS
- Recent 3 months vs prior 3 months for GRS, orders, visits, and CVR
- Gaps to top-40 average visits, CVR, and availability
- Weighted issue score, primary issue, slacking metrics, and narrative diagnosis

## Output intent

This output is meant to be read row by row for the requested Amazon-winning parts. Use `outside_top_40_flag` to isolate the ones missing the top 40, while still keeping the full list visible for debugging and comparison.
