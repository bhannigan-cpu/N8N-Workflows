# Visionary top-35 miss analysis

This SQL returns only the requested Amazon-winning Visionary parts that rank outside the top 35 on Wayfair by L6M sales.

## Output columns

- Wayfair L6M sales rank
- L6M visits
- L6M CVR
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
