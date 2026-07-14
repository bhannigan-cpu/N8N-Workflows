# Member Monday Loyalty Lift Case Study: Bedding Category

## Executive takeaway

Member Monday generated **$120,149.08** in participating SKU sales versus a recent non-promo daily average of **$97,553.26**, creating **$22,595.82 in incremental sales** and a **23.2% weighted lift**. The event gives suppliers a practical proof point that loyalty-led traffic can move bedding-category demand when promotion depth is paired with the right SKU selection.

**Important reading note:** the source file compares a one-day Member Monday result to each SKU's recent non-promo daily average. I treat the `Discount` field as the supplier promotional investment level and calculate portfolio lift as `(Member Monday Sales - L10 Non Promo Daily Avg) / L10 Non Promo Daily Avg`.

**Data QA note:** The headline and summaries use the confirmed visible SKU-detail totals: $97,553.26 baseline sales and $120,149.08 Member Monday sales. The PDF displayed total showed $97,551.63 baseline and $124,455.00 Member Monday sales, but the detail-row total is the confirmed total.

## Metric definitions

- **Active SKUs:** participating SKUs that had more than `$0` in Member Monday sales. It answers, "How many of the submitted SKUs actually sold during the event?"
- **Lift per discount point:** weighted sales lift divided by weighted discount investment. For example, a value of `2.0` means the supplier generated about 2 percentage points of sales lift for every 1 percentage point of discount. Use it as an efficiency read, not a margin or dollar ROI calculation.
- **Weighted lift:** total incremental sales divided by the total recent non-promo daily average for that group.
- **Weighted discount:** the `Discount` field averaged by baseline sales, so higher-volume SKUs influence the supplier/class average more than low-volume SKUs.

## What changed on Member Monday

- **Overall lift:** 23.2% on $120,149.08 in Member Monday sales.
- **Incremental sales:** $22,595.82 above the recent non-promo daily average.
- **Participation breadth:** 911 of 2504 participating SKUs recorded Member Monday sales; 719 SKUs generated positive incremental dollars.
- **Weighted supplier investment:** 17.8% average `Discount` rate, weighted by the recent non-promo daily average.
- **Best class by lift:** Accent Pillows at 56.9% weighted lift.
- **Largest class by event sales:** Bedding Sets with $74,572.60 in Member Monday sales.

![Class sales lift](charts/class_sales_lift.png)

## Class-level insights

| class_name           | sku_count | active_skus | positive_lift_sku_rate | weighted_discount_pct | l10_non_promo_daily_avg | member_monday_sales | incremental_sales | weighted_lift_pct |
| -------------------- | --------- | ----------- | ---------------------- | --------------------- | ----------------------- | ------------------- | ----------------- | ----------------- |
| Bedding Sets         | 1459      | 533         | 29.6%                  | 18.9%                 | $61,879.70              | $74,572.60          | $12,692.90        | 20.5%             |
| Sheets & Pillowcases | 320       | 148         | 32.8%                  | 16.4%                 | $18,679.15              | $23,267.68          | $4,588.53         | 24.6%             |
| Blankets And Throws  | 203       | 82          | 29.6%                  | 13.2%                 | $8,907.37               | $10,379.49          | $1,472.12         | 16.5%             |
| Accent Pillows       | 421       | 116         | 22.6%                  | 16.7%                 | $6,505.28               | $10,207.13          | $3,701.85         | 56.9%             |
| Bed Skirts           | 25        | 13          | 36.0%                  | 23.0%                 | $725.92                 | $880.33             | $154.41           | 21.3%             |
| Kids Bedding Sets    | 68        | 17          | 23.5%                  | 13.7%                 | $828.30                 | $816.07             | $-12.23           | -1.5%             |
| Bedding Accessories  | 8         | 2           | 25.0%                  | 22.2%                 | $27.54                  | $25.78              | $-1.76            | -6.4%             |

### How to use these class insights with suppliers

- **Lead with the proof point:** Accent Pillows delivered the strongest class-level lift, showing that even specialized bedding classes respond when promoted through the loyalty event.
- **Separate scale from rate:** Bedding Sets produced the largest Member Monday dollar volume, while smaller classes can show higher lift rates because their baseline is lower.
- **Use the active-SKU rate as a merchandising filter:** classes with many participating SKUs but fewer active SKUs should be reviewed for search placement, inventory, and item attractiveness before simply increasing discount depth.

![Class/investment lift buckets](charts/discount_bucket_lift.png)

In the discount-bucket chart, light purple bars show the recent non-promo daily average and dark purple bars show Member Monday sales.

## Promotional investment vs. lift

| discount_bucket | sku_count | weighted_discount_pct | l10_non_promo_daily_avg | member_monday_sales | incremental_sales | weighted_lift_pct |
| --------------- | --------- | --------------------- | ----------------------- | ------------------- | ----------------- | ----------------- |
| <10%            | 330       | 5.7%                  | $12,112.51              | $16,328.31          | $4,215.80         | 34.8%             |
| 10-14.9%        | 441       | 10.9%                 | $15,446.15              | $15,590.74          | $144.59           | 0.9%              |
| 15-19.9%        | 621       | 15.8%                 | $25,448.56              | $30,245.85          | $4,797.29         | 18.9%             |
| 20-24.9%        | 646       | 21.2%                 | $30,061.28              | $38,752.67          | $8,691.39         | 28.9%             |
| 25%+            | 466       | 31.4%                 | $14,484.76              | $19,231.51          | $4,746.75         | 32.8%             |

The investment story is not purely "deeper discount equals better lift." Mid- and higher-discount buckets both produced wins, but SKU relevance and baseline demand materially shaped outcomes. This is a useful supplier message: Member Monday works best when suppliers fund a compelling offer **and** nominate SKUs with enough demand signal to convert loyalty traffic.

![Supplier lift vs investment](charts/supplier_lift_vs_investment.png)

## Supplier-level insights

| supplier_name                            | sku_count | active_skus | positive_lift_sku_rate | weighted_discount_pct | l10_non_promo_daily_avg | member_monday_sales | incremental_sales | weighted_lift_pct |
| ---------------------------------------- | --------- | ----------- | ---------------------- | --------------------- | ----------------------- | ------------------- | ----------------- | ----------------- |
| Bedshe International Co.,LTD             | 201       | 119         | 47.3%                  | 20.3%                 | $21,940.25              | $30,796.51          | $8,856.26         | 40.4%             |
| Revman International                     | 557       | 240         | 34.6%                  | 21.8%                 | $21,589.50              | $26,863.32          | $5,273.82         | 24.4%             |
| Plutus Partners LLC                      | 11        | 1           | 9.1%                   | 22.0%                 | $165.91                 | $1,837.55           | $1,671.64         | 1007.6%           |
| CAN_Cathay Home Inc.                     | 28        | 15          | 32.1%                  | 26.0%                 | $4,518.61               | $5,727.40           | $1,208.79         | 26.8%             |
| CENTRADE INC.                            | 31        | 15          | 45.2%                  | 17.0%                 | $1,704.95               | $2,740.91           | $1,035.96         | 60.8%             |
| SHENZHENMENGMI TEXTILE CO.,LTD           | 9         | 9           | 66.7%                  | 16.0%                 | $1,762.77               | $2,689.56           | $926.79           | 52.6%             |
| CAN_Beco Industries                      | 91        | 34          | 25.3%                  | 15.0%                 | $6,577.48               | $7,483.68           | $906.20           | 13.8%             |
| CGK HOLDINGS, INC.                       | 22        | 18          | 68.2%                  | 22.0%                 | $1,328.43               | $2,157.38           | $828.95           | 62.4%             |
| Nanyang Dingjiayue Shangmao Youxiansi    | 74        | 11          | 13.5%                  | 15.0%                 | $689.80                 | $1,337.59           | $647.79           | 93.9%             |
| Pem America                              | 114       | 30          | 25.4%                  | 21.5%                 | $1,246.53               | $1,823.80           | $577.27           | 46.3%             |
| Loloi Rugs                               | 42        | 16          | 31.0%                  | 8.6%                  | $749.10                 | $1,313.83           | $564.73           | 75.4%             |
| Bargain Online Shops LLC                 | 52        | 13          | 23.1%                  | 11.4%                 | $1,019.99               | $1,554.19           | $534.20           | 52.4%             |
| Victoria Classics                        | 32        | 10          | 31.2%                  | 19.0%                 | $230.99                 | $684.18             | $453.19           | 196.2%            |
| Daniel Linen/Home Sweet Home Dreams Inc. | 17        | 6           | 17.6%                  | 2.0%                  | $1,395.08               | $1,641.14           | $246.06           | 17.6%             |
| Jiangsu Meideni Textile CO.,LTD          | 26        | 8           | 30.8%                  | 19.4%                 | $345.56                 | $572.82             | $227.26           | 65.8%             |

## Supplier success stories

| supplier_name                         | sku_count | active_skus | positive_lift_sku_rate | weighted_discount_pct | l10_non_promo_daily_avg | member_monday_sales | incremental_sales | weighted_lift_pct |
| ------------------------------------- | --------- | ----------- | ---------------------- | --------------------- | ----------------------- | ------------------- | ----------------- | ----------------- |
| Bedshe International Co.,LTD          | 201       | 119         | 47.3%                  | 20.3%                 | $21,940.25              | $30,796.51          | $8,856.26         | 40.4%             |
| Revman International                  | 557       | 240         | 34.6%                  | 21.8%                 | $21,589.50              | $26,863.32          | $5,273.82         | 24.4%             |
| Plutus Partners LLC                   | 11        | 1           | 9.1%                   | 22.0%                 | $165.91                 | $1,837.55           | $1,671.64         | 1007.6%           |
| CAN_Cathay Home Inc.                  | 28        | 15          | 32.1%                  | 26.0%                 | $4,518.61               | $5,727.40           | $1,208.79         | 26.8%             |
| CENTRADE INC.                         | 31        | 15          | 45.2%                  | 17.0%                 | $1,704.95               | $2,740.91           | $1,035.96         | 60.8%             |
| SHENZHENMENGMI TEXTILE CO.,LTD        | 9         | 9           | 66.7%                  | 16.0%                 | $1,762.77               | $2,689.56           | $926.79           | 52.6%             |
| CAN_Beco Industries                   | 91        | 34          | 25.3%                  | 15.0%                 | $6,577.48               | $7,483.68           | $906.20           | 13.8%             |
| CGK HOLDINGS, INC.                    | 22        | 18          | 68.2%                  | 22.0%                 | $1,328.43               | $2,157.38           | $828.95           | 62.4%             |
| Nanyang Dingjiayue Shangmao Youxiansi | 74        | 11          | 13.5%                  | 15.0%                 | $689.80                 | $1,337.59           | $647.79           | 93.9%             |
| Pem America                           | 114       | 30          | 25.4%                  | 21.5%                 | $1,246.53               | $1,823.80           | $577.27           | 46.3%             |

![Top incremental supplier gains](charts/top_supplier_incremental_sales.png)

### Storylines for supplier conversations

1. **Scaled incremental win:** Bedshe International Co.,LTD produced the largest positive incremental sales gain at **$8,856.26** over baseline, with **$30,796.51** in Member Monday sales.
2. **Scaled efficiency win:** Victoria Classics paired meaningful scale with efficient lift, generating **196.2%** lift at a **19.0%** weighted discount.
3. **Low-baseline breakout:** Plutus Partners LLC produced the highest supplier lift rate among positive suppliers. Use this as an upside story, but frame it as a low-baseline result that should be validated with repeat events.
4. **Assortment learning:** suppliers with many participating SKUs but low active-SKU rates are candidates for tighter SKU curation. The event can still work, but the next round should prioritize items with stronger recent traffic, inventory, imagery, and price competitiveness.

## Recommended supplier-facing message

> Member Monday created measurable incremental demand in the bedding category. Across participating SKUs, the event lifted sales **23.2%** above recent non-promo daily averages. The strongest results came when suppliers paired meaningful discount funding with SKUs that already had enough customer demand to convert loyalty traffic. For the next event, we should use this case study to ask suppliers for targeted funding on proven SKUs, then expand selectively into similar items/classes.

## Files generated

- `member_monday_sku_data.csv`: cleaned SKU-level extract.
- `class_summary.csv`: class-level performance and investment metrics.
- `supplier_summary.csv`: supplier-level performance and investment metrics.
- `discount_bucket_summary.csv`: lift by supplier discount-investment bucket.
- `member_monday_case_study.xlsx`: workbook with all summary tabs.
- `charts/*.png`: visual assets for supplier-facing materials.
