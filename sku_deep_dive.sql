WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 26 WEEK) AS l6m_start_week
),

target_skus AS (
  SELECT 'Cathay' AS requested_supplier, 'Strong traffic, low conversion' AS requested_issue, 'DRVU1120' AS sku UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1045' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1040' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1028' UNION ALL
  SELECT 'Cathay', 'Slow traffic and low conversion', 'EIFT1029' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1051' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1272' UNION ALL
  SELECT 'Sunham', 'Strong traffic, low conversion', 'LCST1304' UNION ALL
  SELECT 'Sunham', 'Slow traffic and low conversion', 'LCST1128' UNION ALL
  SELECT 'Sunham', 'Slow traffic and low conversion', 'LCST1287'
),

sku_dim AS (
  SELECT
    target_skus.requested_supplier,
    target_skus.requested_issue,
    target_skus.sku,
    retail_dim_sku.skuid,
    retail_dim_sku.skuname AS matched_sku,
    retail_dim_sku.skufullname AS sku_full_name,
    retail_dim_sku.prstatusname,
    retail_dim_sku.skustatusreasonname,
    retail_dim_sku.mkcname,
    retail_dim_sku.clinternalref,
    retail_dim_sku.directorgroup,
    retail_dim_sku.origmaname,
    retail_dim_sku.cskumaname,
    retail_dim_sku.pricegroupname,
    retail_dim_sku.svclassname,
    retail_dim_sku.incastlegatename,
    retail_dim_sku.prhasmapname,
    retail_dim_sku.wppname
  FROM target_skus
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON UPPER(retail_dim_sku.skuname) = target_skus.sku
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY target_skus.sku
    ORDER BY
      CASE WHEN LOWER(retail_dim_sku.prstatusname) = 'active' THEN 0 ELSE 1 END,
      retail_dim_sku.skuid
  ) = 1
),

supplier_rows AS (
  SELECT
    sku_dim.sku,
    retail_dim_supplier.origsuid AS supplier_id,
    retail_dim_supplier.origsuname AS supplier_name
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

supplier_summary AS (
  SELECT
    sku,
    STRING_AGG(DISTINCT CAST(supplier_id AS STRING), ', ' ORDER BY CAST(supplier_id AS STRING)) AS supplier_ids,
    STRING_AGG(DISTINCT supplier_name, ', ' ORDER BY supplier_name) AS supplier_names
  FROM supplier_rows
  GROUP BY sku
),

traffic_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    sku_dim.sku,
    traffic_source.id AS traffic_source_id,
    COALESCE(traffic_source.skuvisits, 0) AS visits,
    COALESCE(traffic_source.skuconverted, 0) AS converted
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.traffic_source) AS traffic_source
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) BETWEEN params.l6m_start_week AND params.current_week_start
),

deduped_traffic AS (
  SELECT
    week_start,
    sku,
    traffic_source_id,
    ANY_VALUE(visits) AS visits,
    ANY_VALUE(converted) AS converted
  FROM traffic_rows
  GROUP BY
    week_start,
    sku,
    traffic_source_id
),

traffic_l6m AS (
  SELECT
    sku,
    SUM(visits) AS visits_l6m,
    SUM(converted) AS converted_l6m,
    SAFE_DIVIDE(SUM(converted), SUM(visits)) AS cvr_l6m,
    COUNT(DISTINCT IF(visits > 0, week_start, NULL)) AS weeks_with_traffic_l6m,
    SAFE_DIVIDE(SUM(visits), COUNT(DISTINCT week_start)) AS avg_weekly_visits_l6m
  FROM deduped_traffic
  GROUP BY sku
),

current_catalog_rows AS (
  SELECT
    sku_dim.sku,
    retail_sku_store_date.soid,
    COALESCE(retail_sku_store_date.active_sku_count_flag, 0) AS active_sku_count_flag,
    COALESCE(retail_sku_store_date.five_plus_reviews_num, 0) AS five_plus_reviews_num,
    COALESCE(retail_sku_store_date.five_plus_reviews_denom, 0) AS five_plus_reviews_denom,
    COALESCE(retail_sku_store_date.rec_tag_cov_num, 0) AS rec_tag_cov_num,
    COALESCE(retail_sku_store_date.rec_tag_cov_denom, 0) AS rec_tag_cov_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

catalog_readiness AS (
  SELECT
    sku,
    MAX(active_sku_count_flag) AS active_sku_count_flag,
    SAFE_DIVIDE(SUM(five_plus_reviews_num), SUM(five_plus_reviews_denom)) AS five_plus_review_coverage,
    SAFE_DIVIDE(SUM(rec_tag_cov_num), SUM(rec_tag_cov_denom)) AS recommended_tag_coverage,
    SUM(rec_tag_cov_denom) - SUM(rec_tag_cov_num) AS missing_recommended_tag_count
  FROM current_catalog_rows
  GROUP BY sku
),

availability_rows AS (
  SELECT
    sku_dim.sku,
    retail_ops.id AS ops_id,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(retail_ops.availability_global_num, 0)
      ELSE 0
    END AS availability_num,
    CASE
      WHEN UPPER(retail_ops_dims.program) NOT IN ('CASTLEGATE', 'DROPSHIP')
      THEN COALESCE(retail_ops.availability_global_denom, 0)
      ELSE 0
    END AS availability_denom,
    COALESCE(retail_ops.physicallyoos_num, 0) AS physically_oos_num,
    COALESCE(retail_ops.availability_waterfall_denom, 0) AS availability_waterfall_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.opdimensions) AS retail_ops_dims
  LEFT JOIN UNNEST(supplier_part_struct.ops) AS retail_ops
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_availability AS (
  SELECT
    sku,
    ops_id,
    MAX(availability_num) AS availability_num,
    MAX(availability_denom) AS availability_denom,
    MAX(physically_oos_num) AS physically_oos_num,
    MAX(availability_waterfall_denom) AS availability_waterfall_denom
  FROM availability_rows
  GROUP BY
    sku,
    ops_id
),

availability_current AS (
  SELECT
    sku,
    SAFE_DIVIDE(SUM(availability_num), SUM(availability_denom)) AS current_availability,
    SAFE_DIVIDE(SUM(physically_oos_num), SUM(availability_waterfall_denom)) AS current_physical_oos_rate
  FROM deduped_availability
  GROUP BY sku
),

mrpi_rows AS (
  SELECT
    sku_dim.sku,
    supplier_struct.id AS supplier_struct_id,
    COALESCE(supplier_struct.mrpi28d_numerator, 0) AS mrpi_num,
    COALESCE(supplier_struct.mrpi28d_denominator, 0) AS mrpi_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

mrpi_current AS (
  SELECT
    sku,
    SAFE_DIVIDE(SUM(mrpi_num), SUM(mrpi_denom)) AS current_mrpi
  FROM (
    SELECT
      sku,
      supplier_struct_id,
      ANY_VALUE(mrpi_num) AS mrpi_num,
      ANY_VALUE(mrpi_denom) AS mrpi_denom
    FROM mrpi_rows
    GROUP BY sku, supplier_struct_id
  )
  GROUP BY sku
),

wsi_rows AS (
  SELECT
    sku_dim.sku,
    wpi_wsi.id AS wpi_wsi_id,
    SAFE_CAST(wpi_wsi.indexdate AS DATE) AS index_date,
    COALESCE(wpi_wsi.WSI28D_Numerator, 0) AS wsi_num,
    COALESCE(wpi_wsi.WSI28D_Denominator, 0) AS wsi_denom
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.wpi_wsi) AS wpi_wsi
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

wsi_current AS (
  SELECT
    sku,
    SAFE_DIVIDE(SUM(wsi_num), SUM(wsi_denom)) AS current_wsi
  FROM (
    SELECT
      sku,
      wpi_wsi_id,
      ARRAY_AGG(
        STRUCT(wsi_num, wsi_denom, index_date)
        ORDER BY index_date DESC NULLS LAST
        LIMIT 1
      )[OFFSET(0)].wsi_num AS wsi_num,
      ARRAY_AGG(
        STRUCT(wsi_num, wsi_denom, index_date)
        ORDER BY index_date DESC NULLS LAST
        LIMIT 1
      )[OFFSET(0)].wsi_denom AS wsi_denom
    FROM wsi_rows
    GROUP BY sku, wpi_wsi_id
  )
  GROUP BY sku
),

combined AS (
  SELECT
    sku_dim.requested_supplier,
    sku_dim.requested_issue,
    sku_dim.sku,
    sku_dim.matched_sku,
    sku_dim.skuid,
    sku_dim.sku_full_name,
    sku_dim.prstatusname,
    sku_dim.skustatusreasonname,
    supplier_summary.supplier_names,
    supplier_summary.supplier_ids,
    sku_dim.mkcname,
    sku_dim.clinternalref,
    sku_dim.pricegroupname,
    sku_dim.svclassname,
    sku_dim.incastlegatename,
    sku_dim.prhasmapname,
    sku_dim.wppname,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(sku_dim.prstatusname, '')), r'active|live')
      THEN 1
      ELSE 0
    END AS is_live_or_active_status,
    traffic_l6m.visits_l6m,
    traffic_l6m.converted_l6m,
    traffic_l6m.cvr_l6m,
    traffic_l6m.weeks_with_traffic_l6m,
    traffic_l6m.avg_weekly_visits_l6m,
    catalog_readiness.active_sku_count_flag,
    catalog_readiness.five_plus_review_coverage,
    catalog_readiness.recommended_tag_coverage,
    catalog_readiness.missing_recommended_tag_count,
    availability_current.current_availability,
    availability_current.current_physical_oos_rate,
    mrpi_current.current_mrpi,
    wsi_current.current_wsi,
    CASE
      WHEN sku_dim.skuid IS NULL THEN 'Unknown SKU'
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) = 0 THEN 'No measurable traffic'
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) < 50 THEN 'Weak traffic'
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) < 250 THEN 'Limited traffic'
      ELSE 'Meaningful traffic'
    END AS traffic_readout,
    CASE
      WHEN COALESCE(traffic_l6m.visits_l6m, 0) = 0 THEN 'Cannot evaluate CVR without visits'
      WHEN COALESCE(traffic_l6m.cvr_l6m, 0) < 0.01 THEN 'Very weak conversion'
      WHEN COALESCE(traffic_l6m.cvr_l6m, 0) < 0.02 THEN 'Weak conversion'
      ELSE 'Conversion not the primary blocker'
    END AS conversion_readout,
    CASE
      WHEN sku_dim.skuid IS NULL THEN 'Unknown'
      WHEN REGEXP_CONTAINS(LOWER(CONCAT(COALESCE(sku_dim.prstatusname, ''), ' ', COALESCE(sku_dim.skustatusreasonname, ''), ' ', COALESCE(sku_dim.pricegroupname, ''))), r'price|pricing|map|margin|lmgr|guardrail|quarantine') THEN 'Yes'
      WHEN COALESCE(mrpi_current.current_mrpi, 0) >= 0.20 OR COALESCE(wsi_current.current_wsi, 0) >= 0.20 THEN 'Likely'
      ELSE 'No'
    END AS pricing_suppression_signal,
    CASE
      WHEN sku_dim.skuid IS NULL THEN 'SKU not found in retail_dim_sku.'
      WHEN REGEXP_CONTAINS(LOWER(CONCAT(COALESCE(sku_dim.prstatusname, ''), ' ', COALESCE(sku_dim.skustatusreasonname, ''), ' ', COALESCE(sku_dim.pricegroupname, ''))), r'price|pricing|map|margin|lmgr|guardrail|quarantine') THEN CONCAT('Catalog/status text points to pricing: ', COALESCE(NULLIF(sku_dim.skustatusreasonname, ''), sku_dim.prstatusname, 'pricing-related status'))
      WHEN COALESCE(mrpi_current.current_mrpi, 0) >= 0.20 THEN 'MRPI is elevated, indicating retail price competitiveness pressure.'
      WHEN COALESCE(wsi_current.current_wsi, 0) >= 0.20 THEN 'WSI is elevated, indicating wholesale/search competitiveness pressure.'
      ELSE 'No direct pricing suppression signal in status, MRPI, or WSI.'
    END AS pricing_suppression_reason,
    CASE
      WHEN catalog_readiness.recommended_tag_coverage IS NULL THEN 'Unknown'
      WHEN catalog_readiness.recommended_tag_coverage < 1 THEN 'Yes'
      ELSE 'No'
    END AS missing_tags,
    CASE
      WHEN catalog_readiness.five_plus_review_coverage IS NULL THEN 'Unknown'
      WHEN catalog_readiness.five_plus_review_coverage >= 1 THEN 'Yes'
      ELSE 'No'
    END AS has_five_plus_reviews
  FROM sku_dim
  LEFT JOIN supplier_summary
    ON supplier_summary.sku = sku_dim.sku
  LEFT JOIN traffic_l6m
    ON traffic_l6m.sku = sku_dim.sku
  LEFT JOIN catalog_readiness
    ON catalog_readiness.sku = sku_dim.sku
  LEFT JOIN availability_current
    ON availability_current.sku = sku_dim.sku
  LEFT JOIN mrpi_current
    ON mrpi_current.sku = sku_dim.sku
  LEFT JOIN wsi_current
    ON wsi_current.sku = sku_dim.sku
)

SELECT
  *,
  CASE
    WHEN skuid IS NULL THEN 'This SKU did not match retail_dim_sku, so the first step is validating the SKU identifier before interpreting ad performance.'
    WHEN COALESCE(is_live_or_active_status, 0) = 0 THEN CONCAT('Traffic is likely constrained because the SKU status is not live/active. Status: ', COALESCE(prstatusname, 'N/A'), '; reason: ', COALESCE(skustatusreasonname, 'N/A'), '.')
    WHEN pricing_suppression_signal IN ('Yes', 'Likely') AND COALESCE(visits_l6m, 0) < 250 THEN CONCAT('Traffic is likely weak because visibility is being limited by pricing competitiveness/suppression signals. ', pricing_suppression_reason)
    WHEN missing_tags = 'Yes' AND COALESCE(visits_l6m, 0) < 250 THEN CONCAT('Traffic is likely weak because merchandising completeness is low: recommended tag coverage is ', CAST(ROUND(COALESCE(recommended_tag_coverage, 0) * 100, 1) AS STRING), '%, with ', CAST(COALESCE(missing_recommended_tag_count, 0) AS STRING), ' recommended tags missing.')
    WHEN current_availability IS NOT NULL AND current_availability < 0.90 AND COALESCE(visits_l6m, 0) < 250 THEN CONCAT('Traffic may be weak because availability is constrained: current availability is ', CAST(ROUND(current_availability * 100, 1) AS STRING), '%.')
    WHEN COALESCE(visits_l6m, 0) < 250 THEN 'Traffic is weak, but the report did not find a single clear pricing, tag, review, or availability blocker; next step is search/ad placement and bid diagnostics.'
    ELSE 'Traffic is present; the main question is why shoppers are not converting.'
  END AS traffic_story,
  CASE
    WHEN COALESCE(visits_l6m, 0) = 0 THEN 'Conversion cannot be diagnosed because the SKU had no measurable L6M visits.'
    WHEN has_five_plus_reviews <> 'Yes' THEN CONCAT('Conversion is likely weak because the SKU lacks 5+ review coverage. Current 5+ review coverage is ', COALESCE(CAST(ROUND(five_plus_review_coverage * 100, 1) AS STRING), 'N/A'), '%.')
    WHEN missing_tags = 'Yes' THEN CONCAT('Conversion may be weak because product tagging is incomplete. Recommended tag coverage is ', CAST(ROUND(COALESCE(recommended_tag_coverage, 0) * 100, 1) AS STRING), '%.')
    WHEN pricing_suppression_signal IN ('Yes', 'Likely') THEN CONCAT('Conversion may be weak because shoppers are seeing an uncompetitive price/value equation. ', pricing_suppression_reason)
    WHEN current_availability IS NOT NULL AND current_availability < 0.90 THEN CONCAT('Conversion may be weak because availability is constrained at ', CAST(ROUND(current_availability * 100, 1) AS STRING), '%.')
    WHEN COALESCE(cvr_l6m, 0) < 0.02 THEN 'Conversion is weak, but the standard readiness checks do not identify one dominant blocker; the next likely levers are PDP trust and expectation-setting: dimensions, scale imagery, material/color accuracy, price/value, shipping promise, and promo competitiveness.'
    ELSE 'CVR is not obviously weak over L6M; if ad ROAS is still poor, investigate traffic quality, query matching, and campaign structure.'
  END AS conversion_story,
  CASE
    WHEN skuid IS NULL THEN 'Validate SKU mapping.'
    WHEN COALESCE(is_live_or_active_status, 0) = 0 THEN 'Resolve SKU live/active status before adding spend; confirm the status reason in catalog tools and only scale ads once the SKU is findable and purchasable.'
    WHEN pricing_suppression_signal IN ('Yes', 'Likely') THEN 'Resolve pricing competitiveness before increasing bids: review MAP/MSRP/cost inputs, margin guardrail or quarantine signals, and whether retail price aligns with perceived quality. If quality/value is the issue, adjust cost/price or use promo support before scaling traffic.'
    WHEN missing_tags = 'Yes' THEN 'Complete merchandising tags before scaling ads: fill recommended tags that map to customer search/filter behavior, especially material, color, size, style, pattern, product features, and option-level attributes. After tags are complete, re-check search visibility and category placement.'
    WHEN has_five_plus_reviews <> 'Yes' THEN 'Prioritize review generation before scaling traffic: enroll in review acceleration or supplier-funded review programs, focus on SKUs closest to the 5+ review threshold, and avoid relying on higher bids until shoppers have enough social proof to convert.'
    WHEN current_availability IS NOT NULL AND current_availability < 0.90 THEN 'Fix availability before scaling ads: recover inventory/availability, validate supplier part purchasability, and avoid sending paid traffic to a SKU that may be intermittently unavailable.'
    WHEN COALESCE(visits_l6m, 0) < 250 THEN 'Traffic is the bottleneck: audit ad eligibility, campaign inclusion, bids, keyword/category coverage, and search placement. Pair that with merchandising cleanup: complete tags, ensure the title/class/category are aligned with how customers search, and confirm images make the item recognizable in browse/search results.'
    WHEN COALESCE(cvr_l6m, 0) < 0.02 THEN 'Conversion is the bottleneck: improve PDP expectation-setting before adding more traffic. Add accurate dimensions and scale imagery, high-resolution true-to-life photos, close-ups of texture/material/finish, clear material quality callouts, color descriptions/undertones, images in varied lighting or backgrounds, and side-by-side option imagery where applicable. Also review price/value alignment and promo competitiveness.'
    ELSE 'Monitor and scale carefully: no major blocker was flagged, so validate traffic quality, query matching, campaign structure, and competitor alternatives before materially increasing spend.'
  END AS recommended_action
FROM combined
ORDER BY
  requested_supplier,
  requested_issue,
  sku;
