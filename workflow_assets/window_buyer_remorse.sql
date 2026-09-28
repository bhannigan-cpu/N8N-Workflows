-- =============================================================================
-- CATEGORY BUYER'S REMORSE SPIKE ALERT  (Window)
-- =============================================================================
-- QUALIFICATION (per SKU, within the configured category)
--   • Recent buyer's remorse rate  >  category average buyer's remorse rate
--   • Recent rate is at least +3.0 percentage points vs. the L6M baseline
--   • At least 5 returns in the 6-week evaluation window
--   • Ranked by L12M GRS (USD) desc; top N SKUs per SRM are returned
-- =============================================================================

WITH inputs AS (

-------------------------------------------
--------- Enter Store Name Below ----------
-------------------------------------------

SELECT
  'Wayfair' AS Store_Brand -- e.g. Wayfair, AllModern, Joss & Main
, 'United States' AS Store_Country -- e.g. United States, Canada
, 'Wayfair US' AS Brand_Catalog_Name -- e.g. Wayfair US, Wayfair CA
, 1 AS Display_SKU_BclgID -- 1 = Wayfair US display SKUs
, 'https://www.wayfair.com/v/product/show_pdp?sku=' AS PDP_URL_Prefix

-------------------------------------------
---------- Enter Category Below -----------
-------------------------------------------

, 'Window' AS Marketing_Category -- marketing category (mkcname)

-------------------------------------------
---------- Enter SRM Name Below -----------
-------------------------------------------

, TRUE AS Filter_To_Listed_SRMs -- Set FALSE to include every SRM in the category
, [
    'Hannigan, Benjamin',
    'Carvalho, Madison'
  ] AS SRM_Names -- Enter one or more names exactly as they appear in srmcontactname

-------------------------------------------
-- Enter Category Buyer's Remorse Rate ----
-------------------------------------------

, 0.095 AS Category_Buyer_Remorse_Rate -- Enter as a decimal (9.5% → 0.095)

-------------------------------------------
-------------------------------------------
-------------------------------------------

-- Thresholds (usually leave these as-is)
, 0.03 AS Spike_Threshold -- +3.0 pts vs L6M baseline
, 5 AS Min_Return_Count -- minimum returns in the 6-week window
, 25 AS Top_N_Per_SRM -- max SKUs returned per SRM

),

recent_period_metrics AS (
  -- CTE 1: Aggregates 6-Week Evaluation Window (8 weeks ago to 2 weeks ago)
  -- based on RETURN OCCURRENCE DATES
  SELECT
    retail_dim_sku.skuname AS sku,
    REGEXP_EXTRACT(retail_dim_sku.skufullname, r'\((.*?)\)') AS sku_display_name,
    retail_dim_supplier.srmcontactname AS srm_contact_name,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_sku.mkcname AS marketing_category,

    ROUND(SUM(orders.cartqty), 0) AS recent_ordered_units,
    ROUND(SUM(orders.returnqty), 0) AS recent_return_qty,

    -- Buyer's Remorse Rate (6-Week Evaluation Window)
    SAFE_DIVIDE(SUM(ops.remorse_return_rate_op_num), NULLIF(SUM(ops.remorse_return_rate_op_denom), 0)) AS recent_buyer_remorse_rate_op

  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  CROSS JOIN inputs
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.ops) AS ops
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  WHERE
    retail_sku_store_date.brandname = inputs.Store_Brand
    AND retail_sku_store_date.styname = inputs.Store_Country
    AND retail_sku_store_date.date >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 8 WEEK)
    AND retail_sku_store_date.date < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK)
    AND retail_dim_sku.mkcname = inputs.Marketing_Category
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND (
      NOT inputs.Filter_To_Listed_SRMs
      OR retail_dim_supplier.srmcontactname IN UNNEST(inputs.SRM_Names)
    )
  GROUP BY 1, 2, 3, 4, 5
),

l6m_period_metrics AS (
  -- CTE 2: Aggregates Trailing 6-Month (L6M / 26-Week) Baseline based on
  -- RETURN OCCURRENCE DATES
  SELECT
    retail_dim_sku.skuname AS sku,
    SAFE_DIVIDE(SUM(ops.remorse_return_rate_op_num), NULLIF(SUM(ops.remorse_return_rate_op_denom), 0)) AS l6m_buyer_remorse_rate_op
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  CROSS JOIN inputs
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.ops) AS ops
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  WHERE
    retail_sku_store_date.brandname = inputs.Store_Brand
    AND retail_sku_store_date.styname = inputs.Store_Country
    AND retail_sku_store_date.date >= DATE_SUB(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK), INTERVAL 26 WEEK)
    AND retail_sku_store_date.date < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK)
    AND retail_dim_sku.mkcname = inputs.Marketing_Category
    AND retail_sku_store_date.agg_level = 'MONTHLY'
  GROUP BY 1
),

l12m_financials AS (
  -- CTE 3: Aggregates Trailing 12-Month (L12M / 52-Week) Financials (GRS & WSC USD)
  SELECT
    retail_dim_sku.skuname AS sku,
    ROUND(
      (
        SUM(DISTINCT (CAST(ROUND(COALESCE(orders.grossrevenuestable * COALESCE(dim_currency.ExchangeRate, 1), 0)*(1/1000*1.0), 9) AS NUMERIC)
          + (CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 1, 15)) AS INT64) AS NUMERIC) * 4294967296
          + CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 16, 8)) AS INT64) AS NUMERIC)) * 0.000000001))
        -
        SUM(DISTINCT (CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 1, 15)) AS INT64) AS NUMERIC) * 4294967296
          + CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 16, 8)) AS INT64) AS NUMERIC)) * 0.000000001)
      ) / (1/1000*1.0), 2
    ) AS grs_l12m_usd,

    ROUND(
      (
        SUM(DISTINCT (CAST(ROUND(COALESCE(orders.productcostnorebates * COALESCE(dim_currency.ExchangeRate, 1), 0)*(1/1000*1.0), 9) AS NUMERIC)
          + (CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 1, 15)) AS INT64) AS NUMERIC) * 4294967296
          + CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 16, 8)) AS INT64) AS NUMERIC)) * 0.000000001))
        -
        SUM(DISTINCT (CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 1, 15)) AS INT64) AS NUMERIC) * 4294967296
          + CAST(CAST(CONCAT('0x', SUBSTR(TO_HEX(MD5(CAST(orders.id AS STRING))), 16, 8)) AS INT64) AS NUMERIC)) * 0.000000001)
      ) / (1/1000*1.0), 2
    ) AS wsc_l12m_usd

  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  CROSS JOIN inputs
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion` AS dim_currency
    ON dim_currency.CuyShortName = 'USD'
  WHERE
    retail_sku_store_date.brandname = inputs.Store_Brand
    AND retail_sku_store_date.styname = inputs.Store_Country
    AND retail_sku_store_date.date >= DATE_SUB(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK), INTERVAL 52 WEEK)
    AND retail_sku_store_date.date < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK)
    AND retail_dim_sku.mkcname = inputs.Marketing_Category
    AND retail_sku_store_date.agg_level = 'MONTHLY'
  GROUP BY 1
),

filtered_offending_skus AS (
  -- CTE 4: Qualification + SRM ranking
  --   recent remorse  >  category average remorse
  --   AND recent remorse − L6M remorse  >=  +3.0 pts
  --   AND >= Min_Return_Count returns in the 6-week window
  SELECT
    r.srm_contact_name AS srm,
    r.supplier_name,
    r.marketing_category,
    r.sku,
    r.sku_display_name,
    COALESCE(f.grs_l12m_usd, 0) AS grs_l12m_usd,
    COALESCE(f.wsc_l12m_usd, 0) AS wsc_l12m_usd,
    r.recent_ordered_units AS ordered_units_6w,
    r.recent_return_qty AS return_count_6w,

    ROUND(inputs.Category_Buyer_Remorse_Rate * 100, 2) AS category_buyer_remorse_rate_pct,
    ROUND(r.recent_buyer_remorse_rate_op * 100, 2) AS recent_buyer_remorse_rate_pct,
    ROUND(COALESCE(l.l6m_buyer_remorse_rate_op, 0) * 100, 2) AS l6m_buyer_remorse_rate_pct,
    ROUND((r.recent_buyer_remorse_rate_op - COALESCE(l.l6m_buyer_remorse_rate_op, 0)) * 100, 2) AS remorse_rate_l6m_delta_pts,

    ROW_NUMBER() OVER (
      PARTITION BY r.srm_contact_name
      ORDER BY COALESCE(f.grs_l12m_usd, 0) DESC, r.recent_return_qty DESC
    ) AS srm_sku_rank
  FROM recent_period_metrics r
  CROSS JOIN inputs
  LEFT JOIN l6m_period_metrics l
    ON r.sku = l.sku
  LEFT JOIN l12m_financials f
    ON r.sku = f.sku
  WHERE
    r.recent_return_qty >= inputs.Min_Return_Count
    AND r.recent_buyer_remorse_rate_op > inputs.Category_Buyer_Remorse_Rate
    AND (r.recent_buyer_remorse_rate_op - COALESCE(l.l6m_buyer_remorse_rate_op, 0)) >= inputs.Spike_Threshold
),

all_pdp_reviews AS (
  -- CTE 5: Actionable Customer Reviews (<=3 Stars, Non-Empty Text, Non-Actionable Keywords Excluded)
  SELECT
    j.PrSKU AS sku,
    COUNT(DISTINCT r.PrvID) AS review_count_6w,
    ROUND(AVG(r.PrvRating), 2) AS avg_star_rating_6w,
    STRING_AGG(
      CONCAT(
        '[', CAST(r.PrvRating AS STRING), '★ - ', FORMAT_DATE('%Y-%m-%d', DATE(r.PrvDateSubmitted)), ']: ',
        COALESCE(NULLIF(TRIM(REPLACE(r.PrvPrComments, '\n', ' ')), ''), 'No text comment provided')
      ),
      ' || '
      ORDER BY r.PrvDateSubmitted DESC
    ) AS customer_reviews_all
  FROM `wf-gcp-us-ae-sql-data-prod.elt_review.tbl_product_review` r
  JOIN `wf-gcp-us-ae-bulk-prod.csn_review.tbl_join_product_product_review` j
    ON r.PrvID = j.PrvID
  WHERE
    r.PrvStatus = 6
    AND r.PrvRating <= 3
    AND r.PrvPrComments IS NOT NULL
    AND TRIM(r.PrvPrComments) != ''
    AND r.PrvDateSubmitted >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 8 WEEK)
    AND r.PrvDateSubmitted < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK)
    AND NOT REGEXP_CONTAINS(
      LOWER(r.PrvPrComments),
      r'(?i)(' ||
        r'(ordered|bought|purchased)\s+(multiple|several|both|two|2|three|3|different)|' ||
        r'best fit|see which (one|window|curtain|shade|blind)|decid(e|ing) between|keep (only )?(one|the other)|' ||
        r'\b(fedex|ups|usps|carrier|driver)\b|shipping delay|arrived late|lost in transit|' ||
        r'ordered (by mistake|accidentally|wrong (size|item|color))|changed (my|our) mind|no longer need(ed)?|' ||
        r'found (it )?(cheaper|elsewhere)|price dropped' ||
      r')'
    )
  GROUP BY 1
),

all_return_comments AS (
  -- CTE 6: Actionable Customer Return Comments (Non-Actionable Keywords Excluded)
  SELECT
    x.prsku AS sku,
    COUNT(DISTINCT cf.externalid) AS return_feedback_count_6w,
    STRING_AGG(
      CONCAT(
        '[', FORMAT_DATE('%Y-%m-%d', DATE(cf.feedbackdate)), ']: ',
        COALESCE(NULLIF(TRIM(REPLACE(cf.feedbackcomment, '\n', ' ')), ''), 'No text comment provided')
      ),
      ' || '
      ORDER BY cf.feedbackdate DESC
    ) AS customer_return_comments_all
  FROM `wf-gcp-us-ae-merch-prod.bi_merch_reporting.tbl_customer_feedback_sku_date_bclg_supplier_part_order` x
  CROSS JOIN inputs
  CROSS JOIN UNNEST(x.customerfeedback) AS cf
  WHERE
    cf.feedbacktype = 'RETURNS'
    AND x.brandcatalogname = inputs.Brand_Catalog_Name
    AND cf.returns_validreturnflag = 1
    AND DATE(cf.feedbackdate) >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 8 WEEK)
    AND DATE(cf.feedbackdate) < DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK)
    AND cf.feedbackcomment IS NOT NULL
    AND TRIM(cf.feedbackcomment) != ''
    AND NOT REGEXP_CONTAINS(
      LOWER(cf.feedbackcomment),
      r'(?i)(' ||
        r'(ordered|bought|purchased)\s+(multiple|several|both|two|2|three|3|different)|' ||
        r'best fit|see which (one|window|curtain|shade|blind)|decid(e|ing) between|keep (only )?(one|the other)|' ||
        r'\b(fedex|ups|usps|carrier|driver)\b|shipping delay|arrived late|lost in transit|' ||
        r'ordered (by mistake|accidentally|wrong (size|item|color))|changed (my|our) mind|no longer need(ed)?|' ||
        r'found (it )?(cheaper|elsewhere)|price dropped' ||
      r')'
    )
  GROUP BY 1
),

display_sku_mapping AS (
  -- CTE 7: Maps Internal SKU (PrSKU) to Customer-Facing Display SKU (PrDisplaySKU)
  SELECT
    m.PrSKU AS sku,
    m.PrDisplaySKU AS display_sku,
    CONCAT(inputs.PDP_URL_Prefix, m.PrDisplaySKU) AS pdp_url
  FROM `wf-gcp-us-ae-bulk-prod.csn_product.tbl_current_pr_display_sku` m
  CROSS JOIN inputs
  WHERE m.bclgid = inputs.Display_SKU_BclgID
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.PrSKU ORDER BY m.PrDisplaySKU) = 1
)

-- Final SELECT: Top N qualifying SKUs per SRM, prioritized by GRS L12M DESC
SELECT
  s.srm,
  s.srm_sku_rank AS rank_per_srm,
  s.supplier_name,
  s.marketing_category,
  s.sku AS internal_sku,
  d.display_sku,
  d.pdp_url,
  s.sku_display_name,
  s.grs_l12m_usd,
  s.wsc_l12m_usd,
  s.ordered_units_6w,
  s.return_count_6w,
  s.category_buyer_remorse_rate_pct,
  s.recent_buyer_remorse_rate_pct,
  s.l6m_buyer_remorse_rate_pct,
  s.remorse_rate_l6m_delta_pts,
  COALESCE(rev.review_count_6w, 0) AS review_count_6w,
  rev.avg_star_rating_6w,
  COALESCE(rev.customer_reviews_all, 'No actionable customer reviews (<=3★ with comments) submitted in this 6-week window') AS customer_pdp_reviews,
  COALESCE(ret.return_feedback_count_6w, 0) AS return_feedback_count_6w,
  COALESCE(ret.customer_return_comments_all, 'No customer return feedback submitted in this 6-week window') AS customer_return_comments

FROM filtered_offending_skus s
CROSS JOIN inputs
LEFT JOIN display_sku_mapping d
  ON s.sku = d.sku
LEFT JOIN all_pdp_reviews rev
  ON s.sku = rev.sku
LEFT JOIN all_return_comments ret
  ON s.sku = ret.sku
WHERE
  s.srm_sku_rank <= inputs.Top_N_Per_SRM
ORDER BY
  s.srm ASC,
  s.srm_sku_rank ASC
