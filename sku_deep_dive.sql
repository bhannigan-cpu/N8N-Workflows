WITH params AS (
  SELECT
    DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH) AS current_month_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 DAY) AS current_month_end,
    DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH), INTERVAL 1 MONTH) AS prior_month_start,
    DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH), INTERVAL 1 DAY) AS prior_month_end,
    DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH), INTERVAL 1 YEAR) AS prior_year_month_start,
    DATE_SUB(DATE_ADD(DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH), INTERVAL 1 YEAR), INTERVAL 1 MONTH), INTERVAL 1 DAY) AS prior_year_month_end,
    DATE_SUB(DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH), INTERVAL 5 MONTH) AS l6m_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start
),

target_skus AS (
  SELECT 'Cathay' AS requested_supplier, 'Strong traffic, low conversion' AS requested_issue, 'DRVU1120' AS prsku UNION ALL
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
    target_skus.prsku,
    retail_dim_sku.skuid,
    retail_dim_sku.skufullname AS sku_full_name,
    retail_dim_sku.prstatusname,
    retail_dim_sku.skustatusreasonname,
    retail_dim_sku.mkcname,
    retail_dim_sku.clinternalref,
    retail_dim_sku.pricegroupname,
    retail_dim_sku.svclassname,
    retail_dim_sku.incastlegatename,
    retail_dim_sku.prhasmapname,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(retail_dim_sku.prstatusname, '')), r'active|live') THEN 1
      ELSE 0
    END AS is_live_or_active_status
  FROM target_skus
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON UPPER(retail_dim_sku.skuname) = target_skus.prsku
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY target_skus.prsku
    ORDER BY
      CASE WHEN REGEXP_CONTAINS(LOWER(COALESCE(retail_dim_sku.prstatusname, '')), r'active|live') THEN 0 ELSE 1 END,
      retail_dim_sku.skuid
  ) = 1
),

sku_launch AS (
  SELECT
    UPPER(prsku) AS prsku,
    MIN(skuLaunchDate) AS sku_launch_date
  FROM `wf-gcp-us-ae-merch-prod.bi_merch_reporting.tbl_findability_sku_store_date_option_combination`
  WHERE UPPER(prsku) IN (SELECT prsku FROM target_skus)
  GROUP BY prsku
),

revenue AS (
  SELECT
    UPPER(sku.SKUName) AS prsku,
    SUM(CASE WHEN a.OrderDate BETWEEN params.current_month_start AND params.current_month_end THEN a.ProductCostNoRebates ELSE 0 END) AS wsc_current_month,
    SUM(CASE WHEN a.OrderDate BETWEEN params.prior_month_start AND params.prior_month_end THEN a.ProductCostNoRebates ELSE 0 END) AS wsc_prior_month,
    SUM(CASE WHEN a.OrderDate BETWEEN params.prior_year_month_start AND params.prior_year_month_end THEN a.ProductCostNoRebates ELSE 0 END) AS wsc_prior_year_month,
    SUM(CASE WHEN a.OrderDate BETWEEN params.current_month_start AND params.current_month_end THEN a.grossrevenuestable ELSE 0 END) AS grs_current_month
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_order_product_revenue_cost` AS a
    ON a.skuid = sku_dim.skuid
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS sku
    ON sku.skuid = a.skuid
  CROSS JOIN params
  WHERE a.SoID = 49
    AND a.OrderDate BETWEEN params.prior_year_month_start AND params.current_month_end
  GROUP BY prsku
),

visits AS (
  SELECT
    UPPER(sku.SKUName) AS prsku,
    SUM(CASE WHEN v.VisitDate BETWEEN params.current_month_start AND params.current_month_end THEN v.skuvisits ELSE 0 END) AS visits_current_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.prior_month_start AND params.prior_month_end THEN v.skuvisits ELSE 0 END) AS visits_prior_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.prior_year_month_start AND params.prior_year_month_end THEN v.skuvisits ELSE 0 END) AS visits_prior_year_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.current_month_start AND params.current_month_end THEN v.skuconverted ELSE 0 END) AS converted_current_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.prior_month_start AND params.prior_month_end THEN v.skuconverted ELSE 0 END) AS converted_prior_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.prior_year_month_start AND params.prior_year_month_end THEN v.skuconverted ELSE 0 END) AS converted_prior_year_month,
    SUM(CASE WHEN v.VisitDate BETWEEN params.l6m_start AND params.current_month_end THEN v.skuvisits ELSE 0 END) AS visits_l6m,
    SUM(CASE WHEN v.VisitDate BETWEEN params.l6m_start AND params.current_month_end THEN v.skuconverted ELSE 0 END) AS converted_l6m
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_sku_visit` AS v
    ON v.skuid = sku_dim.skuid
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS sku
    ON sku.skuid = v.skuid
  CROSS JOIN params
  WHERE v.SoID = 49
    AND v.VisitDate BETWEEN params.prior_year_month_start AND params.current_month_end
  GROUP BY prsku
),

availability AS (
  SELECT
    UPPER(a.SKU) AS prsku,
    SAFE_DIVIDE(SUM(CASE WHEN a.Date BETWEEN params.current_month_start AND params.current_month_end AND a.ProgramID = 0 THEN a.Availability ELSE 0 END),
      SUM(CASE WHEN a.Date BETWEEN params.current_month_start AND params.current_month_end AND a.ProgramID = 0 THEN a.TotalCatalogue ELSE 0 END)) AS availability_current_month,
    SAFE_DIVIDE(SUM(CASE WHEN a.Date BETWEEN params.prior_month_start AND params.prior_month_end AND a.ProgramID = 0 THEN a.Availability ELSE 0 END),
      SUM(CASE WHEN a.Date BETWEEN params.prior_month_start AND params.prior_month_end AND a.ProgramID = 0 THEN a.TotalCatalogue ELSE 0 END)) AS availability_prior_month,
    SAFE_DIVIDE(SUM(CASE WHEN a.Date BETWEEN params.prior_year_month_start AND params.prior_year_month_end AND a.ProgramID = 0 THEN a.Availability ELSE 0 END),
      SUM(CASE WHEN a.Date BETWEEN params.prior_year_month_start AND params.prior_year_month_end AND a.ProgramID = 0 THEN a.TotalCatalogue ELSE 0 END)) AS availability_prior_year_month
  FROM `wf-gcp-us-ae-gat-prod.analyticstech_reporting.tbl_fact_availability_waterfall_lost_sales_distribution_SKU_Store_reporting` AS a
  CROSS JOIN params
  WHERE a.SoID = 49
    AND UPPER(a.SKU) IN (SELECT prsku FROM target_skus)
    AND a.Date BETWEEN params.prior_year_month_start AND params.current_month_end
  GROUP BY prsku
),

sku_rank_latest_month AS (
  SELECT
    UPPER(rank_source.SKU) AS prsku,
    AVG(rank_source.SKURank) AS avg_sku_rank_latest_month,
    COUNT(*) AS rank_impressions_latest_month,
    CASE
      WHEN AVG(rank_source.SKURank) <= 50 THEN 'Yes'
      WHEN AVG(rank_source.SKURank) IS NULL THEN 'Unknown'
      ELSE 'No'
    END AS is_page_1_latest_month
  FROM `wf-gcp-us-ae-sf-prod.curated_clickstream.tbl_dash_clicks_solr_request_sku_list` AS rank_source
  CROSS JOIN params
  WHERE rank_source.Event_SoID = 49
    AND rank_source.SessionStartDate >= params.current_month_start
    AND rank_source.SessionStartDate <= params.current_month_end
    AND UPPER(rank_source.SKU) IN (SELECT prsku FROM target_skus)
    AND rank_source.SKURank IS NOT NULL
  GROUP BY prsku
),

ad_spend AS (
  SELECT
    sku_dim.prsku,
    SUM(COALESCE(supplier_struct.sponsoredproducttotalspend, 0)) AS ad_spend_ltm
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) BETWEEN DATE_SUB(params.current_month_start, INTERVAL 12 MONTH) AND params.current_month_end
  GROUP BY sku_dim.prsku
),

tag_coverage AS (
  SELECT
    UPPER(t.prsku) AS prsku,
    SAFE_DIVIDE(
      SUM(CASE WHEN st.stagstprid = 0 AND st.complete = 1 THEN 1 ELSE 0 END),
      SUM(CASE WHEN st.stagstprid = 0 THEN 1 ELSE 0 END)
    ) AS required_tag_coverage
  FROM `wf-gcp-us-ae-merch-prod.bi_merch_reporting.tbl_catalog_content_sku_date_bclg` AS t
  LEFT JOIN UNNEST(t.schematag) AS st
  WHERE t.currentperiod = 1
    AND t.isskuactiveandbclgassociationactive = 1
    AND t.bclgid = 1
    AND UPPER(t.prsku) IN (SELECT prsku FROM target_skus)
  GROUP BY prsku
),

image_coverage AS (
  SELECT
    UPPER(t.prsku) AS prsku,
    SAFE_DIVIDE(
      SUM(CASE WHEN oc.isimagerycoverageeligible = 1 AND oc.ocisimagerycovered = 1 THEN 1 ELSE 0 END),
      SUM(CASE WHEN oc.isimagerycoverageeligible = 1 THEN 1 ELSE 0 END)
    ) AS image_coverage
  FROM `wf-gcp-us-ae-merch-prod.bi_merch_reporting.tbl_catalog_content_sku_date_bclg` AS t
  LEFT JOIN UNNEST(t.optioncombination) AS oc
  WHERE t.currentperiod = 1
    AND t.isskuactiveandbclgassociationactive = 1
    AND t.bclgid = 1
    AND UPPER(t.prsku) IN (SELECT prsku FROM target_skus)
  GROUP BY prsku
),

review_coverage AS (
  SELECT
    sku_dim.prsku,
    SAFE_DIVIDE(SUM(COALESCE(retail_sku_store_date.five_plus_reviews_num, 0)), SUM(COALESCE(retail_sku_store_date.five_plus_reviews_denom, 0))) AS five_plus_review_coverage
  FROM sku_dim
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
    ON retail_sku_store_date.skuid = sku_dim.skuid
  CROSS JOIN params
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
  GROUP BY sku_dim.prsku
),

mrpi_current AS (
  SELECT
    prsku,
    SAFE_DIVIDE(SUM(mrpi_num), SUM(mrpi_denom)) AS current_mrpi
  FROM (
    SELECT
      sku_dim.prsku,
      supplier_struct.id AS supplier_struct_id,
      ANY_VALUE(COALESCE(supplier_struct.mrpi28d_numerator, 0)) AS mrpi_num,
      ANY_VALUE(COALESCE(supplier_struct.mrpi28d_denominator, 0)) AS mrpi_denom
    FROM sku_dim
    JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
      ON retail_sku_store_date.skuid = sku_dim.skuid
    LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
    CROSS JOIN params
    WHERE retail_sku_store_date.brandname = 'Wayfair'
      AND retail_sku_store_date.styname = 'United States'
      AND retail_sku_store_date.agg_level = 'WEEKLY'
      AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
    GROUP BY sku_dim.prsku, supplier_struct_id
  )
  GROUP BY prsku
),

wsi AS (
  SELECT
    UPPER(a.SKU) AS prsku,
    SAFE_DIVIDE(SUM(CASE WHEN a.InsertDate BETWEEN params.current_month_start AND params.current_month_end THEN a.WSI28D_Numerator ELSE 0 END),
      SUM(CASE WHEN a.InsertDate BETWEEN params.current_month_start AND params.current_month_end THEN a.WSI28D_Denominator ELSE 0 END)) AS item_level_wsi,
    SAFE_DIVIDE(SUM(CASE WHEN a.InsertDate BETWEEN params.prior_month_start AND params.prior_month_end THEN a.WSI28D_Numerator ELSE 0 END),
      SUM(CASE WHEN a.InsertDate BETWEEN params.prior_month_start AND params.prior_month_end THEN a.WSI28D_Denominator ELSE 0 END)) AS prior_month_wsi
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_indices_metrics_combined` AS a
  CROSS JOIN params
  WHERE a.BrandCatalog_ID = 1
    AND UPPER(a.SKU) IN (SELECT prsku FROM target_skus)
    AND a.InsertDate BETWEEN params.prior_month_start AND params.current_month_end
  GROUP BY prsku
),

price_rows AS (
  SELECT
    UPPER(prsku) AS prsku,
    Competitor,
    AVG(WayfairPrice) AS wf_retail,
    AVG(CompetitorProductPrice) AS competitor_retail,
    SAFE_DIVIDE(SUM(RPI28DVisits_Numerator), SUM(RPI28DVisits_Denominator)) AS rpi28_visits
  FROM `wf-gcp-us-ae-pricing-prod.pricing_dw.tbl_fact_price_cost_combined_competitors_metrics`
  CROSS JOIN params
  WHERE bclgId = 1
    AND indexdate = DATE '9999-12-31'
    AND insertdate BETWEEN params.current_month_start AND params.current_month_end
    AND UPPER(prsku) IN (SELECT prsku FROM target_skus)
    AND CompetitorProductPrice > 0
    AND WayfairPrice > 0
  GROUP BY prsku, Competitor
),

price_current AS (
  SELECT
    prsku,
    ARRAY_AGG(STRUCT(Competitor, wf_retail, competitor_retail, rpi28_visits) ORDER BY competitor_retail ASC LIMIT 1)[OFFSET(0)].Competitor AS competitor_name,
    ARRAY_AGG(STRUCT(Competitor, wf_retail, competitor_retail, rpi28_visits) ORDER BY competitor_retail ASC LIMIT 1)[OFFSET(0)].wf_retail AS wf_retail,
    ARRAY_AGG(STRUCT(Competitor, wf_retail, competitor_retail, rpi28_visits) ORDER BY competitor_retail ASC LIMIT 1)[OFFSET(0)].competitor_retail AS competitor_retail,
    ARRAY_AGG(STRUCT(Competitor, wf_retail, competitor_retail, rpi28_visits) ORDER BY competitor_retail ASC LIMIT 1)[OFFSET(0)].rpi28_visits AS rpi28_visits
  FROM price_rows
  GROUP BY prsku
),

assembled AS (
  SELECT
    sku_dim.requested_supplier,
    sku_dim.requested_issue,
    sku_dim.prsku,
    sku_launch.sku_launch_date,
    sku_dim.sku_full_name,
    sku_dim.prstatusname,
    revenue.wsc_current_month,
    SAFE_DIVIDE(revenue.wsc_current_month - revenue.wsc_prior_month, revenue.wsc_prior_month) AS wsc_mom_pct,
    SAFE_DIVIDE(revenue.wsc_current_month - revenue.wsc_prior_year_month, revenue.wsc_prior_year_month) AS wsc_yoy_pct,
    SAFE_DIVIDE(revenue.wsc_current_month, revenue.grs_current_month) AS pct_of_sales,
    ad_spend.ad_spend_ltm,
    sku_rank_latest_month.avg_sku_rank_latest_month,
    sku_rank_latest_month.is_page_1_latest_month,
    availability.availability_current_month,
    availability.availability_prior_month,
    SAFE_DIVIDE(availability.availability_current_month - availability.availability_prior_month, availability.availability_prior_month) AS availability_mom_pct,
    SAFE_DIVIDE(visits.converted_l6m, visits.visits_l6m) AS cvr_l6m,
    SAFE_DIVIDE(visits.converted_current_month, visits.visits_current_month) AS cvr_current_month,
    SAFE_DIVIDE(visits.converted_prior_month, visits.visits_prior_month) AS cvr_prior_month,
    SAFE_DIVIDE(visits.converted_current_month, visits.visits_current_month) - SAFE_DIVIDE(visits.converted_prior_month, visits.visits_prior_month) AS cvr_mom_pp,
    visits.visits_current_month,
    visits.visits_prior_month,
    SAFE_DIVIDE(visits.visits_current_month - visits.visits_prior_month, visits.visits_prior_month) AS visits_mom_pct,
    tag_coverage.required_tag_coverage,
    image_coverage.image_coverage,
    review_coverage.five_plus_review_coverage,
    wsi.item_level_wsi,
    wsi.item_level_wsi - wsi.prior_month_wsi AS wsi_mom_change,
    price_current.wf_retail,
    price_current.competitor_retail,
    price_current.competitor_name,
    mrpi_current.current_mrpi,
    CASE
      WHEN mrpi_current.current_mrpi > 0 THEN 'Uncompetitive'
      WHEN mrpi_current.current_mrpi IS NULL THEN 'Unknown'
      ELSE 'Competitive'
    END AS wf_competitiveness,
    CASE
      WHEN mrpi_current.current_mrpi > 0.05 OR price_current.wf_retail > price_current.competitor_retail THEN 'Review pricing / Merchandising'
      WHEN COALESCE(revenue.wsc_current_month, 0) < COALESCE(revenue.wsc_prior_month, 0) THEN 'Review WSC decline drivers'
      ELSE 'Monitor financials'
    END AS financials_ask,
    CASE
      WHEN sku_rank_latest_month.avg_sku_rank_latest_month > 50 AND SAFE_DIVIDE(visits.converted_l6m, visits.visits_l6m) >= 0.008 THEN 'Increase spend / improve rank'
      WHEN sku_rank_latest_month.avg_sku_rank_latest_month > 50 THEN 'Fix rank drivers before scaling spend'
      WHEN SAFE_DIVIDE(visits.converted_l6m, visits.visits_l6m) < 0.008 THEN 'Optimize PDP before more spend'
      ELSE 'Optimize spend'
    END AS ads_ask,
    CASE
      WHEN availability.availability_current_month < 0.80 THEN 'Improve Availability'
      WHEN availability.availability_current_month < availability.availability_prior_month THEN 'Watch availability decline'
      ELSE 'Maintain Availability'
    END AS availability_ask,
    CASE
      WHEN visits.visits_current_month < visits.visits_prior_month AND sku_rank_latest_month.avg_sku_rank_latest_month > 50 THEN 'Improve rank to recover visits'
      WHEN visits.visits_current_month < visits.visits_prior_month THEN 'Review traffic decline'
      WHEN visits.visits_current_month > visits.visits_prior_month AND SAFE_DIVIDE(visits.converted_l6m, visits.visits_l6m) < 0.008 THEN 'Traffic improved; fix CVR'
      ELSE 'Monitor visits'
    END AS visits_ask,
    CONCAT(
      IF(COALESCE(review_coverage.five_plus_review_coverage, 0) < 1, 'Needs 5+ reviews. ', ''),
      IF(COALESCE(tag_coverage.required_tag_coverage, 1) < 0.90, 'Complete required tags. ', ''),
      IF(COALESCE(image_coverage.image_coverage, 1) < 1, 'Improve imagery coverage. ', ''),
      IF(SAFE_DIVIDE(visits.converted_l6m, visits.visits_l6m) < 0.008, 'Audit PDP: dimensions, material/quality callouts, color accuracy, close-up/scale imagery, shipping promise, price-value. ', ''),
      IF(mrpi_current.current_mrpi > 0, 'Price/value appears uncompetitive; review retail vs market. ', '')
    ) AS pdp_feedback
  FROM sku_dim
  LEFT JOIN sku_launch ON sku_launch.prsku = sku_dim.prsku
  LEFT JOIN revenue ON revenue.prsku = sku_dim.prsku
  LEFT JOIN visits ON visits.prsku = sku_dim.prsku
  LEFT JOIN availability ON availability.prsku = sku_dim.prsku
  LEFT JOIN sku_rank_latest_month ON sku_rank_latest_month.prsku = sku_dim.prsku
  LEFT JOIN ad_spend ON ad_spend.prsku = sku_dim.prsku
  LEFT JOIN tag_coverage ON tag_coverage.prsku = sku_dim.prsku
  LEFT JOIN image_coverage ON image_coverage.prsku = sku_dim.prsku
  LEFT JOIN review_coverage ON review_coverage.prsku = sku_dim.prsku
  LEFT JOIN wsi ON wsi.prsku = sku_dim.prsku
  LEFT JOIN price_current ON price_current.prsku = sku_dim.prsku
  LEFT JOIN mrpi_current ON mrpi_current.prsku = sku_dim.prsku
)

SELECT
  requested_supplier,
  requested_issue,
  prsku,
  sku_launch_date,
  avg_sku_rank_latest_month,
  is_page_1_latest_month,
  wsc_current_month,
  pct_of_sales,
  wsc_mom_pct,
  wsc_yoy_pct,
  financials_ask,
  ad_spend_ltm,
  ads_ask,
  availability_current_month,
  availability_ask,
  availability_mom_pct,
  cvr_l6m,
  cvr_current_month,
  cvr_mom_pp,
  visits_current_month,
  visits_prior_month,
  visits_mom_pct,
  visits_ask,
  required_tag_coverage,
  image_coverage,
  five_plus_review_coverage,
  pdp_feedback,
  item_level_wsi,
  wsi_mom_change,
  wf_retail,
  competitor_retail,
  competitor_name,
  current_mrpi,
  wf_competitiveness
FROM assembled
ORDER BY
  requested_supplier,
  requested_issue,
  prsku;
