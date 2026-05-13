# Visionary top-35 miss analysis

This SQL returns the requested Amazon-winning Visionary parts in a spreadsheet-style format.

## Output columns

- Wayfair L6M sales rank
- L6M visits
- L6M CVR column is left blank because the current `traffic_source` join path is not reliable at supplier-part grain
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
CVR is excluded from the hurting-most logic until a trustworthy part-level traffic/conversion join is confirmed.
