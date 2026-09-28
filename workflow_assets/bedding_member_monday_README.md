# Deprecated filename

This workflow was generalized into **Loyalty Promo WSC Lift**.

Use:
- `Loyalty Promo WSC Lift.json`
- `workflow_assets/loyalty_promo_lift_README.md`

For each new loyalty event, edit **Configure Inputs**:
1. `promo_period_id`
2. `product_marketing_category` (product `mkcname`, not supplier category)

Metric is **WSC** (not GRS). L10 non-promo days auto-update from the promo start date (extended discounts / super rooms ignored).
