# Visionary top-35 miss analysis

This SQL returns the requested Amazon-winning Visionary parts in a spreadsheet-style format.

## Output columns

- Wayfair L6M sales rank
- L6M visits
- L6M CVR, displayed in the same style as the source SQL (for example `0.81` means 0.81%)
- L6M wholesale cost no rebates
- L6M availability
- gaps versus the current top-35 average for each metric
- `hurting_most_metric`
- `hurting_most_reason`

## Hurting-most logic

The query compares each part against the current top-35 Visionary benchmark set:

- lower visits are worse
- lower CVR is worse
- higher wholesale cost no rebates is worse
- lower availability is worse

The metric with the largest normalized negative gap is labeled as the main thing hurting the part.
CVR is included in the hurting-most logic and displayed as a percent value without the percent sign, matching the source SQL style.
