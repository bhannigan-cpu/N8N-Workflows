/*
  SKU-Level Scorecard Query for Cathay and Sunham
  Period: March (current year vs prior year), plus MoM vs previous month
  Source patterns: EURTA_NARTA repo
*/

DECLARE CY_START DATE DEFAULT '2026-03-01';
DECLARE CY_END   DATE DEFAULT '2026-03-31';
DECLARE PY_START DATE DEFAULT '2025-03-01';
DECLARE PY_END   DATE DEFAULT '2025-03-31';

-- Previous month (for MoM)
DECLARE PM_START DATE DEFAULT DATE_SUB(CY_START, INTERVAL 1 MONTH);
DECLARE PM_END   DATE DEFAULT DATE_SUB(CY_START, INTERVAL 1 DAY);

-------------------------------------------------------------------------------
-- Supplier/SKU spine from the requested explicit lists
-------------------------------------------------------------------------------
WITH sku_spine AS (
  SELECT * FROM UNNEST([
    STRUCT('Cathay' AS SupplierName, 14556 AS SuID, 'Strong traffic, low conversion' AS TrafficConversionSegment, 'DRVU1120' AS PrSKU),
    STRUCT('Cathay' AS SupplierName, 14556 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'EIFT1045' AS PrSKU),
    STRUCT('Cathay' AS SupplierName, 14556 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'EIFT1040' AS PrSKU),
    STRUCT('Cathay' AS SupplierName, 14556 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'EIFT1028' AS PrSKU),
    STRUCT('Cathay' AS SupplierName, 14556 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'EIFT1029' AS PrSKU),
    STRUCT('Sunham' AS SupplierName, 16941 AS SuID, 'Strong traffic, low conversion' AS TrafficConversionSegment, 'LCST1051' AS PrSKU),
    STRUCT('Sunham' AS SupplierName, 16941 AS SuID, 'Strong traffic, low conversion' AS TrafficConversionSegment, 'LCST1272' AS PrSKU),
    STRUCT('Sunham' AS SupplierName, 16941 AS SuID, 'Strong traffic, low conversion' AS TrafficConversionSegment, 'LCST1304' AS PrSKU),
    STRUCT('Sunham' AS SupplierName, 16941 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'LCST1128' AS PrSKU),
    STRUCT('Sunham' AS SupplierName, 16941 AS SuID, 'Slow traffic and low conversion' AS TrafficConversionSegment, 'LCST1287' AS PrSKU)
  ])
),

target_retail_keys AS (
  SELECT DISTINCT
    k.SuID,
    k.PrSKU,
    sku.skuid,
    su.supplierkey
  FROM sku_spine k
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` sku
    ON sku.SKUName = k.PrSKU
  JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` su
    ON su.origsuid = k.SuID
),

-------------------------------------------------------------------------------
-- 1. WHOLESALE REVENUE -- uses retail_dim_supplier instead of tbl_supplier_part
-------------------------------------------------------------------------------
revenue AS (
  SELECT
    k.SuID,
    k.PrSKU,

    -- Current year month
    SUM(CASE WHEN a.OrderDate BETWEEN CY_START AND CY_END
             THEN a.ProductCostNoRebates END) AS WholesaleRevenue,
    SUM(CASE WHEN a.OrderDate BETWEEN CY_START AND CY_END
             THEN a.grossrevenuestable   END) AS GRS,

    -- Prior year same month
    SUM(CASE WHEN a.OrderDate BETWEEN PY_START AND PY_END
             THEN a.ProductCostNoRebates END) AS PY_WholesaleRevenue,
    SUM(CASE WHEN a.OrderDate BETWEEN PY_START AND PY_END
             THEN a.grossrevenuestable   END) AS PY_GRS,

    -- Previous month (for MoM)
    SUM(CASE WHEN a.OrderDate BETWEEN PM_START AND PM_END
             THEN a.ProductCostNoRebates END) AS PM_WholesaleRevenue,
    SUM(CASE WHEN a.OrderDate BETWEEN PM_START AND PM_END
             THEN a.grossrevenuestable   END) AS PM_GRS
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_order_product_revenue_cost` a
  JOIN target_retail_keys k
    ON a.skuid = k.skuid
   AND a.supplierkey = k.supplierkey
  WHERE a.SoID = 49
    AND (
      a.OrderDate BETWEEN CY_START AND CY_END
      OR a.OrderDate BETWEEN PY_START AND PY_END
      OR a.OrderDate BETWEEN PM_START AND PM_END
    )
  GROUP BY 1, 2
),

-------------------------------------------------------------------------------
-- 2. SKU VISITS & CONVERSION
-------------------------------------------------------------------------------
visits AS (
  SELECT
    k.SuID,
    k.PrSKU,

    -- Current year month
    SUM(CASE WHEN v.VisitDate BETWEEN CY_START AND CY_END
             THEN v.skuvisits    END) AS SkuVisits,
    SUM(CASE WHEN v.VisitDate BETWEEN CY_START AND CY_END
             THEN v.skuconverted END) AS SkuConverted,

    -- Prior year same month
    SUM(CASE WHEN v.VisitDate BETWEEN PY_START AND PY_END
             THEN v.skuvisits    END) AS PY_SkuVisits,
    SUM(CASE WHEN v.VisitDate BETWEEN PY_START AND PY_END
             THEN v.skuconverted END) AS PY_SkuConverted,

    -- Previous month (for MoM)
    SUM(CASE WHEN v.VisitDate BETWEEN PM_START AND PM_END
             THEN v.skuvisits    END) AS PM_SkuVisits,
    SUM(CASE WHEN v.VisitDate BETWEEN PM_START AND PM_END
             THEN v.skuconverted END) AS PM_SkuConverted
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_fact_sku_visit` v
  JOIN target_retail_keys k
    ON v.skuid = k.skuid
   AND v.supplierkey = k.supplierkey
  WHERE v.SoID = 49
    AND (
      v.VisitDate BETWEEN CY_START AND CY_END
      OR v.VisitDate BETWEEN PY_START AND PY_END
      OR v.VisitDate BETWEEN PM_START AND PM_END
    )
  GROUP BY 1, 2
),

-------------------------------------------------------------------------------
-- 3. AVAILABILITY -- SKU-level
-------------------------------------------------------------------------------
availability AS (
  SELECT
    k.SuID,
    k.PrSKU,

    -- Current year month
    SUM(CASE WHEN a.Date BETWEEN CY_START AND CY_END AND a.ProgramID = 0
             THEN a.Availability   END) AS Avail_Num,
    SUM(CASE WHEN a.Date BETWEEN CY_START AND CY_END AND a.ProgramID = 0
             THEN a.TotalCatalogue END) AS Avail_Denom,

    -- Prior year same month
    SUM(CASE WHEN a.Date BETWEEN PY_START AND PY_END AND a.ProgramID = 0
             THEN a.Availability   END) AS PY_Avail_Num,
    SUM(CASE WHEN a.Date BETWEEN PY_START AND PY_END AND a.ProgramID = 0
             THEN a.TotalCatalogue END) AS PY_Avail_Denom,

    -- Previous month (for MoM)
    SUM(CASE WHEN a.Date BETWEEN PM_START AND PM_END AND a.ProgramID = 0
             THEN a.Availability   END) AS PM_Avail_Num,
    SUM(CASE WHEN a.Date BETWEEN PM_START AND PM_END AND a.ProgramID = 0
             THEN a.TotalCatalogue END) AS PM_Avail_Denom
  FROM `wf-gcp-us-ae-gat-prod.analyticstech_reporting.tbl_fact_availability_waterfall_lost_sales_distribution_SKU_Store_reporting` a
  JOIN (SELECT DISTINCT SuID, PrSKU FROM sku_spine) k
    ON a.ParentSuID = k.SuID
   AND a.SKU = k.PrSKU
  WHERE a.SoID = 49
    AND (
      a.Date BETWEEN CY_START AND CY_END
      OR a.Date BETWEEN PY_START AND PY_END
      OR a.Date BETWEEN PM_START AND PM_END
    )
  GROUP BY 1, 2
),

-------------------------------------------------------------------------------
-- 4. WSI (Item-Level)
-------------------------------------------------------------------------------
wsi AS (
  SELECT
    k.SuID,
    k.PrSKU,

    -- Current year month
    SUM(CASE WHEN a.InsertDate BETWEEN CY_START AND CY_END
             THEN a.WSI28D_Numerator   END) AS WSI_Num,
    SUM(CASE WHEN a.InsertDate BETWEEN CY_START AND CY_END
             THEN a.WSI28D_Denominator END) AS WSI_Denom,

    -- Prior year same month
    SUM(CASE WHEN a.InsertDate BETWEEN PY_START AND PY_END
             THEN a.WSI28D_Numerator   END) AS PY_WSI_Num,
    SUM(CASE WHEN a.InsertDate BETWEEN PY_START AND PY_END
             THEN a.WSI28D_Denominator END) AS PY_WSI_Denom,

    -- Previous month (for MoM)
    SUM(CASE WHEN a.InsertDate BETWEEN PM_START AND PM_END
             THEN a.WSI28D_Numerator   END) AS PM_WSI_Num,
    SUM(CASE WHEN a.InsertDate BETWEEN PM_START AND PM_END
             THEN a.WSI28D_Denominator END) AS PM_WSI_Denom
  FROM `wf-gcp-us-ae-eunarta-prod.reporting.tbl_indices_metrics_combined` a
  JOIN (SELECT DISTINCT SuID, PrSKU FROM sku_spine) k
    ON a.Supplier_ID = k.SuID
   AND a.SKU = k.PrSKU
  WHERE a.BrandCatalog_ID = 1
    AND (
      a.InsertDate BETWEEN CY_START AND CY_END
      OR a.InsertDate BETWEEN PY_START AND PY_END
      OR a.InsertDate BETWEEN PM_START AND PM_END
    )
  GROUP BY 1, 2
),

-------------------------------------------------------------------------------
-- 5+6. TAG COVERAGE + IMAGE COVERAGE -- point-in-time
-------------------------------------------------------------------------------
catalog_base AS (
  SELECT
    k.SuID,
    k.PrSKU,
    t.schematag,
    t.optioncombination
  FROM `wf-gcp-us-ae-merch-prod.bi_merch_reporting.tbl_catalog_content_sku_date_bclg` t
  JOIN (SELECT DISTINCT SuID, PrSKU FROM sku_spine) k
    ON t.prsku = k.PrSKU
  WHERE t.currentperiod = 1
    AND t.isskuactiveandbclgassociationactive = 1
    AND t.bclgid = 1
    AND EXISTS (
      SELECT 1
      FROM UNNEST(t.supplierpart) AS sp_cat
      WHERE sp_cat.supplierid = k.SuID
    )
),

tag_metrics AS (
  SELECT
    SuID,
    PrSKU,
    COUNTIF(st.stagstprid = 0 AND st.complete = 1) AS ReqTag_Num,
    COUNTIF(st.stagstprid = 0) AS ReqTag_Denom
  FROM catalog_base
  LEFT JOIN UNNEST(schematag) AS st
  GROUP BY 1, 2
),

image_metrics AS (
  SELECT
    SuID,
    PrSKU,
    COUNTIF(oc.isimagerycoverageeligible = 1 AND oc.ocisimagerycovered = 1) AS ImgCov_Num,
    COUNTIF(oc.isimagerycoverageeligible = 1) AS ImgCov_Denom
  FROM catalog_base
  LEFT JOIN UNNEST(optioncombination) AS oc
  GROUP BY 1, 2
),

catalog_metrics AS (
  SELECT
    COALESCE(t.SuID, i.SuID) AS SuID,
    COALESCE(t.PrSKU, i.PrSKU) AS PrSKU,
    t.ReqTag_Num,
    t.ReqTag_Denom,
    i.ImgCov_Num,
    i.ImgCov_Denom
  FROM tag_metrics t
  FULL OUTER JOIN image_metrics i
    ON t.SuID = i.SuID
   AND t.PrSKU = i.PrSKU
),

-------------------------------------------------------------------------------
-- 7+8. INCIDENCE RATE (KPIID=123) + GIE (KPIID=872) -- supplier-level
--      Uses ReportMonth. IR excludes StoreID 368; GIE includes all stores.
--      Pull current and previous month for MoM.
-------------------------------------------------------------------------------
ops_metrics AS (
  SELECT
    a.OrigParentSuID AS SuID,

    -- Current month IR (exclude store 368)
    SUM(CASE WHEN a.KPIID = 123
              AND a.StoreID != 368
              AND a.ReportMonth BETWEEN CY_START AND CY_END
             THEN a.numerator   END) AS IR_Num,
    SUM(CASE WHEN a.KPIID = 123
              AND a.StoreID != 368
              AND a.ReportMonth BETWEEN CY_START AND CY_END
             THEN a.denominator END) AS IR_Denom,

    -- Current month GIE (all stores)
    SUM(CASE WHEN a.KPIID = 872
              AND a.ReportMonth BETWEEN CY_START AND CY_END
             THEN a.numerator   END) AS GIE_Num,
    SUM(CASE WHEN a.KPIID = 872
              AND a.ReportMonth BETWEEN CY_START AND CY_END
             THEN a.denominator END) AS GIE_Denom,

    -- Previous month IR (exclude store 368)
    SUM(CASE WHEN a.KPIID = 123
              AND a.StoreID != 368
              AND a.ReportMonth BETWEEN PM_START AND PM_END
             THEN a.numerator   END) AS PM_IR_Num,
    SUM(CASE WHEN a.KPIID = 123
              AND a.StoreID != 368
              AND a.ReportMonth BETWEEN PM_START AND PM_END
             THEN a.denominator END) AS PM_IR_Denom,

    -- Previous month GIE (all stores)
    SUM(CASE WHEN a.KPIID = 872
              AND a.ReportMonth BETWEEN PM_START AND PM_END
             THEN a.numerator   END) AS PM_GIE_Num,
    SUM(CASE WHEN a.KPIID = 872
              AND a.ReportMonth BETWEEN PM_START AND PM_END
             THEN a.denominator END) AS PM_GIE_Denom
  FROM `wf-gcp-us-ae-gat-prod.analyticstech_reporting.tbl_agg_pops_scorecard_daily` a
  JOIN (SELECT DISTINCT SuID FROM sku_spine) s
    ON a.OrigParentSuID = s.SuID
  WHERE a.KPIID IN (123, 872)
    AND (
      a.ReportMonth BETWEEN CY_START AND CY_END
      OR a.ReportMonth BETWEEN PM_START AND PM_END
    )
  GROUP BY 1
),

-------------------------------------------------------------------------------
-- FINAL ASSEMBLY
-------------------------------------------------------------------------------
assembled AS (
  SELECT
    k.SupplierName,
    k.SuID,
    k.TrafficConversionSegment,
    k.PrSKU,

    -- Revenue + YoY + MoM
    COALESCE(r.WholesaleRevenue, 0)               AS WholesaleRevenue,
    COALESCE(r.GRS, 0)                            AS GRS,
    SAFE_DIVIDE(r.WholesaleRevenue, r.GRS)        AS Pct_of_Sales,
    COALESCE(r.PY_WholesaleRevenue, 0)            AS PY_WholesaleRevenue,
    SAFE_DIVIDE(r.WholesaleRevenue - r.PY_WholesaleRevenue,
                r.PY_WholesaleRevenue)            AS WholesaleRevenue_YoY_Pct,
    COALESCE(r.PM_WholesaleRevenue, 0)            AS PM_WholesaleRevenue,
    SAFE_DIVIDE(r.WholesaleRevenue - r.PM_WholesaleRevenue,
                r.PM_WholesaleRevenue)            AS WholesaleRevenue_MoM_Pct,

    -- Availability + YoY + MoM
    SAFE_DIVIDE(av.Avail_Num, av.Avail_Denom)     AS Availability,
    SAFE_DIVIDE(av.PY_Avail_Num, av.PY_Avail_Denom) AS PY_Availability,
    SAFE_DIVIDE(av.PM_Avail_Num, av.PM_Avail_Denom) AS PM_Availability,

    -- Conversion + YoY + MoM
    SAFE_DIVIDE(vi.SkuConverted, vi.SkuVisits)    AS ConversionRate,
    SAFE_DIVIDE(vi.PY_SkuConverted, vi.PY_SkuVisits) AS PY_ConversionRate,
    SAFE_DIVIDE(vi.PM_SkuConverted, vi.PM_SkuVisits) AS PM_ConversionRate,

    -- Visits + YoY + MoM
    COALESCE(vi.SkuVisits, 0)                     AS SkuVisits,
    COALESCE(vi.PY_SkuVisits, 0)                  AS PY_SkuVisits,
    COALESCE(vi.PM_SkuVisits, 0)                  AS PM_SkuVisits,

    -- Catalog metrics (no MoM)
    SAFE_DIVIDE(cm.ReqTag_Num, cm.ReqTag_Denom)   AS ReqTagCoverage,
    SAFE_DIVIDE(cm.ImgCov_Num, cm.ImgCov_Denom)   AS ImageCoverage,

    -- OPS metrics + MoM
    SAFE_DIVIDE(om.IR_Num, om.IR_Denom)           AS IncidenceRate,
    SAFE_DIVIDE(om.PM_IR_Num, om.PM_IR_Denom)     AS PM_IncidenceRate,
    SAFE_DIVIDE(om.GIE_Num, om.GIE_Denom)         AS GIE_Pct_of_WSCNR,
    SAFE_DIVIDE(om.PM_GIE_Num, om.PM_GIE_Denom)   AS PM_GIE_Pct_of_WSCNR,

    -- WSI + YoY + MoM
    SAFE_DIVIDE(w.WSI_Num, w.WSI_Denom)           AS ItemLevel_WSI,
    SAFE_DIVIDE(w.PY_WSI_Num, w.PY_WSI_Denom)     AS PY_ItemLevel_WSI,
    SAFE_DIVIDE(w.PM_WSI_Num, w.PM_WSI_Denom)     AS PM_ItemLevel_WSI
  FROM sku_spine k
  LEFT JOIN revenue        r  ON r.SuID = k.SuID AND r.PrSKU  = k.PrSKU
  LEFT JOIN visits         vi ON vi.SuID = k.SuID AND vi.PrSKU = k.PrSKU
  LEFT JOIN availability   av ON av.SuID = k.SuID AND av.PrSKU = k.PrSKU
  LEFT JOIN wsi            w  ON w.SuID = k.SuID AND w.PrSKU  = k.PrSKU
  LEFT JOIN catalog_metrics cm ON cm.SuID = k.SuID AND cm.PrSKU = k.PrSKU
  LEFT JOIN ops_metrics    om ON om.SuID = k.SuID
)

SELECT
  SupplierName,
  SuID,
  TrafficConversionSegment,
  PrSKU,

  -- Revenue
  CONCAT('$', FORMAT("%.2f", ROUND(WholesaleRevenue, 2)))      AS Wholesale_Revenue,
  FORMAT("%.2f%%", ROUND(Pct_of_Sales * 100, 2))              AS Pct_of_Sales,
  CONCAT('$', FORMAT("%.2f", ROUND(PY_WholesaleRevenue, 2)))  AS PY_Wholesale_Revenue,
  FORMAT("%.2f%%", ROUND(WholesaleRevenue_YoY_Pct * 100, 2))  AS Wholesale_Revenue_YoY_Pct,
  FORMAT("%.2f%%", ROUND(WholesaleRevenue_MoM_Pct * 100, 2))  AS Wholesale_Revenue_MoM_Pct,

  -- Availability
  FORMAT("%.2f%%", ROUND(Availability * 100, 2))              AS Availability_Pct,
  CASE WHEN Availability >= 0.80 THEN 'Above Target'
       WHEN Availability IS NULL THEN NULL
       ELSE 'Below Target' END                                AS Availability_vs_Target_80,
  FORMAT("%.2f%%", ROUND(PY_Availability * 100, 2))           AS PY_Availability_Pct,
  FORMAT("%.2f%%", ROUND((Availability - PY_Availability) * 100, 2))
                                                                AS Availability_YoY_PP_Change,
  FORMAT("%.2f%%", ROUND(SAFE_DIVIDE(Availability - PY_Availability,
                                     PY_Availability) * 100, 2))
                                                                AS Availability_YoY_Pct,
  FORMAT("%.2f%%", ROUND((Availability - PM_Availability) * 100, 2))
                                                                AS Availability_MoM_PP_Change,
  FORMAT("%.2f%%", ROUND(SAFE_DIVIDE(Availability - PM_Availability,
                                     PM_Availability) * 100, 2))
                                                                AS Availability_MoM_Pct,

  -- Conversion
  FORMAT("%.2f%%", ROUND(ConversionRate * 100, 2))            AS SKU_Conversion_Rate_Pct,
  CASE WHEN ConversionRate >= 0.008 THEN 'Above Target'
       WHEN ConversionRate IS NULL THEN NULL
       ELSE 'Below Target' END                                AS Conversion_vs_Target_0_8,
  FORMAT("%.2f%%", ROUND(PY_ConversionRate * 100, 2))         AS PY_SKU_Conversion_Rate_Pct,
  FORMAT("%.2f bps", ROUND((ConversionRate - PY_ConversionRate) * 10000, 2))
                                                                AS Conversion_YoY_BPS_Change,
  FORMAT("%.2f bps", ROUND((ConversionRate - PM_ConversionRate) * 10000, 2))
                                                                AS Conversion_MoM_BPS_Change,

  -- Visits
  SkuVisits                                                   AS SKU_Visit_Count,
  PY_SkuVisits                                                AS PY_SKU_Visit_Count,
  PM_SkuVisits                                                AS PM_SKU_Visit_Count,
  FORMAT("%.2f%%", ROUND(SAFE_DIVIDE(SkuVisits - PY_SkuVisits,
                                     PY_SkuVisits) * 100, 2))
                                                                AS SKU_Visits_YoY_Pct,
  FORMAT("%.2f%%", ROUND(SAFE_DIVIDE(SkuVisits - PM_SkuVisits,
                                     PM_SkuVisits) * 100, 2))
                                                                AS SKU_Visits_MoM_Pct,
  CASE WHEN SkuVisits > PY_SkuVisits  THEN 'Improved'
       WHEN SkuVisits < PY_SkuVisits  THEN 'Declined'
       WHEN SkuVisits = PY_SkuVisits  THEN 'Flat'
       ELSE NULL END                                          AS SKU_Visits_YoY_Trend,
  CASE WHEN SkuVisits > PM_SkuVisits  THEN 'Improved'
       WHEN SkuVisits < PM_SkuVisits  THEN 'Declined'
       WHEN SkuVisits = PM_SkuVisits  THEN 'Flat'
       ELSE NULL END                                          AS SKU_Visits_MoM_Trend,

  -- Catalog metrics
  FORMAT("%.2f%%", ROUND(ReqTagCoverage * 100, 2))            AS Req_Tag_Coverage_Pct,
  CASE WHEN ReqTagCoverage >= 0.90 THEN 'Above Target'
       WHEN ReqTagCoverage IS NULL THEN NULL
       ELSE 'Below Target' END                                AS Req_Tag_vs_Target_90,

  FORMAT("%.2f%%", ROUND(ImageCoverage * 100, 2))             AS Image_Coverage_Pct,
  CASE WHEN ImageCoverage >= 1.0 THEN 'At/Above Target'
       WHEN ImageCoverage IS NULL THEN NULL
       ELSE 'Below Target' END                                AS Image_Coverage_vs_Target_100,

  -- Incidence Rate
  FORMAT("%.2f%%", ROUND(IncidenceRate * 100, 2))             AS Incidence_Rate_Pct,
  CASE WHEN IncidenceRate <= 0.05 THEN 'At/Under Target'
       WHEN IncidenceRate IS NULL THEN NULL
       ELSE 'Above Target' END                                AS Incidence_Rate_vs_Target_5,
  FORMAT("%.2f%%", ROUND((IncidenceRate - PM_IncidenceRate) * 100, 2))
                                                                AS Incidence_Rate_MoM_PP_Change,

  -- GIE
  FORMAT("%.2f%%", ROUND(GIE_Pct_of_WSCNR * 100, 2))
                                                                AS Gross_Incidence_Exposure_Pct_of_WSCNR,
  CASE WHEN GIE_Pct_of_WSCNR <= 0.05 THEN 'At/Under Target'
       WHEN GIE_Pct_of_WSCNR IS NULL THEN NULL
       ELSE 'Above Target' END                                AS GIE_vs_Target_5,
  FORMAT("%.2f%%", ROUND((GIE_Pct_of_WSCNR - PM_GIE_Pct_of_WSCNR) * 100, 2))
                                                                AS Gross_Incidence_Exposure_Pct_of_WSCNR_MoM_PP_Change,

  -- WSI
  ROUND(ItemLevel_WSI, 2)                                     AS Item_Level_WSI,
  ROUND(PY_ItemLevel_WSI, 2)                                  AS PY_Item_Level_WSI,
  ROUND(ItemLevel_WSI - PY_ItemLevel_WSI, 2)                  AS WSI_YoY_Change,
  ROUND(ItemLevel_WSI - PM_ItemLevel_WSI, 2)                  AS WSI_MoM_Change,
  CASE WHEN ItemLevel_WSI > PY_ItemLevel_WSI  THEN 'Improved'
       WHEN ItemLevel_WSI < PY_ItemLevel_WSI  THEN 'Declined'
       WHEN ItemLevel_WSI = PY_ItemLevel_WSI  THEN 'Flat'
       ELSE NULL END                                          AS WSI_YoY_Trend,
  CASE WHEN ItemLevel_WSI > PM_ItemLevel_WSI  THEN 'Improved'
       WHEN ItemLevel_WSI < PM_ItemLevel_WSI  THEN 'Declined'
       WHEN ItemLevel_WSI = PM_ItemLevel_WSI  THEN 'Flat'
       ELSE NULL END                                          AS WSI_MoM_Trend

FROM assembled
ORDER BY SupplierName, TrafficConversionSegment, WholesaleRevenue DESC NULLS LAST;
