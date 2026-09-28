#!/usr/bin/env python3
"""Build the Window category Buyer's Remorse n8n workflow JSON."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "workflow_exports" / "weekly-window-buyer-remorse-alert.json"

INSTANCE_ID = "03eaefce1798e2883471ae7d5d2dfbc186343411ac19c565c97d8bae537d45f1"

BQ_CRED = {"id": "61aSuNTfPEjWsHyK", "name": "Google BigQuery account 352"}
GMAIL_CRED = {"id": "ZmmontG7EgaANggr", "name": "Gmail account 287"}
# OpenAI credential is intentionally omitted from the export so n8n prompts
# you to attach the correct account on import.


def nid() -> str:
    return str(uuid.uuid4())


SQL_QUERY = r"""-- =============================================================================
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
"""

LLM_SYSTEM_PROMPT = """You are a Soft Home / Window category specialist helping Wayfair Supplier Relationship Managers (SRMs) diagnose buyer's-remorse spikes.

For each SKU, analyze the provided 1–3★ PDP reviews and return-survey comments.
Focus on product-quality and expectation issues that an SRM can take to a supplier.
Typical Window defect themes include: light filtration / opacity mismatch, color mismatch vs listing photos, fit/dimensions (length, width, coverage, panel count), and missing product pieces (hardware, tie-backs, liners, second panel).

Return exactly these three fields:
- pdp_summary: 1–2 short bullets on 1–3★ perception issues
- return_summary: 1–2 short bullets on return drivers
- recommended_action: 1–2 concrete SRM/supplier fixes

Be concise, specific, and actionable. If comments are thin, say so and recommend the highest-leverage listing/product check."""

LLM_USER_PROMPT = """=Analyze this Window SKU for buyer's remorse.

SRM: {{ $json.srm }}
Supplier: {{ $json.supplier_name }}
Internal SKU: {{ $json.internal_sku }}
Display SKU: {{ $json.display_sku }}
Product: {{ $json.sku_display_name }}
PDP: {{ $json.pdp_url }}

Metrics:
- Ordered units (6W): {{ $json.ordered_units_6w }}
- Returns (6W): {{ $json.return_count_6w }}
- Category buyer's remorse: {{ $json.category_buyer_remorse_rate_pct }}%
- Recent 6W buyer's remorse: {{ $json.recent_buyer_remorse_rate_pct }}%
- L6M buyer's remorse: {{ $json.l6m_buyer_remorse_rate_pct }}%
- Delta vs L6M (pts): {{ $json.remorse_rate_l6m_delta_pts }}
- Review count (6W): {{ $json.review_count_6w }}
- Avg star rating (6W): {{ $json.avg_star_rating_6w }}
- Return feedback count (6W): {{ $json.return_feedback_count_6w }}

Customer PDP reviews (<=3★):
{{ $json.customer_pdp_reviews }}

Customer return comments:
{{ $json.customer_return_comments }}
"""

OUTPUT_SCHEMA = {
    "type": "object",
    "properties": {
        "pdp_summary": {
            "type": "string",
            "description": "1-2 bullets on 1-3 star PDP perception issues (light filtration, color mismatch, fit/dimensions, missing pieces).",
        },
        "return_summary": {
            "type": "string",
            "description": "1-2 bullets on return drivers from return-survey comments.",
        },
        "recommended_action": {
            "type": "string",
            "description": "1-2 concrete SRM/supplier fixes.",
        },
    },
    "required": ["pdp_summary", "return_summary", "recommended_action"],
    "additionalProperties": False,
}

JS_CODE = r"""// Join BigQuery rows to LLM structured outputs by index, group by SRM, build emails.
const bqRows = $('Execute a SQL query').all().map((item) => item.json);
const llmRows = $input.all().map((item) => item.json);

const srmEmailMap = {
  'Hannigan, Benjamin': 'bhannigan@wayfair.com',
  'Carvalho, Madison': 'bhannigan@wayfair.com',
};
const fallbackEmail = 'bhannigan@wayfair.com';
const TOP_N = 25;

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function fmtMoney(value) {
  const num = Number(value);
  if (Number.isNaN(num)) return '';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(num);
}

function fmtNum(value) {
  const num = Number(value);
  if (Number.isNaN(num)) return '';
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(num);
}

function fmtPct(value) {
  if (value === null || value === undefined || value === '') return '';
  const num = Number(value);
  if (Number.isNaN(num)) return String(value);
  return `${num.toFixed(2)}%`;
}

function firstNameFromSrm(srm) {
  if (!srm) return 'SRM';
  const parts = String(srm).split(',');
  if (parts.length >= 2) return parts[1].trim().split(/\s+/)[0] || 'SRM';
  return String(srm).trim().split(/\s+/)[0] || 'SRM';
}

function topComments(text, limit = 2) {
  if (!text) return '';
  const chunks = String(text)
    .split(' || ')
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, limit);
  return chunks.join('<br/>');
}

function csvEscape(value) {
  const s = String(value ?? '');
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

if (!bqRows.length) {
  return [
    {
      json: {
        srm: 'N/A',
        recipient_email: fallbackEmail,
        subject: "[Action Required] Weekly Top Offending SKUs by Buyer's Remorse - Window",
        emailHtml:
          '<html><body style="font-family:Arial,sans-serif;">' +
          '<h2>Weekly Window Return Alert</h2>' +
          '<p>No qualifying Window SKUs this week (threshold: &gt;9.5% remorse, +3.0 pts vs L6M, ≥5 returns).</p>' +
          '<p style="color:#666;font-size:12px;">Window Return Automation</p>' +
          '</body></html>',
      },
    },
  ];
}

const enriched = bqRows.map((row, idx) => {
  const llm = llmRows[idx] || {};
  const output = llm.output || llm;
  return {
    ...row,
    pdp_summary: output.pdp_summary || llm.pdp_summary || '',
    return_summary: output.return_summary || llm.return_summary || '',
    recommended_action: output.recommended_action || llm.recommended_action || '',
  };
});

const bySrm = {};
for (const row of enriched) {
  const srm = row.srm || 'Unknown SRM';
  if (!bySrm[srm]) bySrm[srm] = [];
  bySrm[srm].push(row);
}

const emails = [];
for (const [srm, rows] of Object.entries(bySrm)) {
  const capped = rows
    .slice()
    .sort((a, b) => Number(a.rank_per_srm || 999) - Number(b.rank_per_srm || 999))
    .slice(0, TOP_N);

  const firstName = firstNameFromSrm(srm);
  const recipient = srmEmailMap[srm] || fallbackEmail;

  const headerCells = [
    'Rank',
    'SKU',
    'Product / Supplier',
    'GRS L12M',
    'WSC L12M',
    'Orders 6W',
    'Returns 6W',
    '6W Remorse',
    'L6M Remorse',
    'Delta pts',
    'Top PDP Reviews',
    'Top Return Comments',
    'PDP Summary',
    'Return Summary',
    'Recommended Action',
  ];

  const tableRowsHtml = capped
    .map((r) => {
      const skuLabel = escapeHtml(r.display_sku || r.internal_sku || '');
      const skuCell = r.pdp_url
        ? `<a href="${escapeHtml(r.pdp_url)}">${skuLabel}</a>`
        : skuLabel;
      const productSupplier = `${escapeHtml(r.sku_display_name || '')}<br/><span style="color:#555;">${escapeHtml(r.supplier_name || '')}</span>`;
      const cells = [
        escapeHtml(r.rank_per_srm),
        skuCell,
        productSupplier,
        escapeHtml(fmtMoney(r.grs_l12m_usd)),
        escapeHtml(fmtMoney(r.wsc_l12m_usd)),
        escapeHtml(fmtNum(r.ordered_units_6w)),
        escapeHtml(fmtNum(r.return_count_6w)),
        escapeHtml(fmtPct(r.recent_buyer_remorse_rate_pct)),
        escapeHtml(fmtPct(r.l6m_buyer_remorse_rate_pct)),
        escapeHtml(r.remorse_rate_l6m_delta_pts),
        topComments(r.customer_pdp_reviews),
        topComments(r.customer_return_comments),
        escapeHtml(r.pdp_summary).replace(/\n/g, '<br/>'),
        escapeHtml(r.return_summary).replace(/\n/g, '<br/>'),
        escapeHtml(r.recommended_action).replace(/\n/g, '<br/>'),
      ];
      return `<tr>${cells.map((c) => `<td style="vertical-align:top;padding:6px;border:1px solid #ddd;font-size:12px;">${c}</td>`).join('')}</tr>`;
    })
    .join('');

  const csvHeader = [
    'rank_per_srm',
    'srm',
    'supplier_name',
    'internal_sku',
    'display_sku',
    'pdp_url',
    'sku_display_name',
    'grs_l12m_usd',
    'wsc_l12m_usd',
    'ordered_units_6w',
    'return_count_6w',
    'recent_buyer_remorse_rate_pct',
    'l6m_buyer_remorse_rate_pct',
    'remorse_rate_l6m_delta_pts',
    'customer_pdp_reviews',
    'customer_return_comments',
    'pdp_summary',
    'return_summary',
    'recommended_action',
  ];

  const csvLines = [csvHeader.join(',')];
  for (const r of capped) {
    csvLines.push(
      [
        r.rank_per_srm,
        r.srm,
        r.supplier_name,
        r.internal_sku,
        r.display_sku,
        r.pdp_url,
        r.sku_display_name,
        r.grs_l12m_usd,
        r.wsc_l12m_usd,
        r.ordered_units_6w,
        r.return_count_6w,
        r.recent_buyer_remorse_rate_pct,
        r.l6m_buyer_remorse_rate_pct,
        r.remorse_rate_l6m_delta_pts,
        r.customer_pdp_reviews,
        r.customer_return_comments,
        r.pdp_summary,
        r.return_summary,
        r.recommended_action,
      ]
        .map(csvEscape)
        .join(',')
    );
  }

  const emailHtml = `
<html>
<body style="font-family:Arial,Helvetica,sans-serif;color:#222;">
  <h2 style="margin-bottom:4px;">Weekly Window Return Alert</h2>
  <p style="margin-top:0;">Hi ${escapeHtml(firstName)}, below are your top offending Window SKUs by buyer's remorse (max ${TOP_N}). Category benchmark: <b>9.5%</b>; spike threshold: <b>+3.0 pts vs L6M</b>; min returns: <b>5</b>.</p>
  <table cellpadding="0" cellspacing="0" style="border-collapse:collapse;width:100%;max-width:1400px;">
    <thead>
      <tr style="background:#f3f4f6;">
        ${headerCells.map((h) => `<th style="text-align:left;padding:6px;border:1px solid #ddd;font-size:12px;">${h}</th>`).join('')}
      </tr>
    </thead>
    <tbody>
      ${tableRowsHtml}
    </tbody>
  </table>
  <h3 style="margin-top:24px;">CSV (copy/paste into Sheets)</h3>
  <pre style="white-space:pre-wrap;font-size:11px;background:#fafafa;border:1px solid #eee;padding:12px;">${escapeHtml(csvLines.join('\n'))}</pre>
  <p style="color:#666;font-size:12px;margin-top:24px;">Weekly Window Return Alert · Window Return Automation</p>
</body>
</html>`.trim();

  emails.push({
    json: {
      srm,
      recipient_email: recipient,
      subject: `[Action Required] Weekly Top Offending SKUs by Buyer's Remorse - ${firstName}`,
      emailHtml,
      sku_count: capped.length,
    },
  });
}

return emails;
"""


def build() -> dict:
    ids = {
        "schedule": nid(),
        "bq": nid(),
        "llm": nid(),
        "openai": nid(),
        "parser": nid(),
        "code": nid(),
        "gmail": nid(),
    }

    nodes = [
        {
            "parameters": {
                "rule": {
                    "interval": [
                        {
                            "field": "weeks",
                            "weeksInterval": 1,
                            "triggerAtDay": [1],
                            "triggerAtHour": 9,
                            "triggerAtMinute": 0,
                        }
                    ]
                }
            },
            "type": "n8n-nodes-base.scheduleTrigger",
            "typeVersion": 1.3,
            "position": [0, 0],
            "id": ids["schedule"],
            "name": "Schedule Trigger",
        },
        {
            "parameters": {
                "projectId": {
                    "__rl": True,
                    "value": "wf-gcp-us-ae-retail-prod",
                    "mode": "list",
                    "cachedResultName": "wf-gcp-us-ae-retail-prod",
                    "cachedResultUrl": "https://console.cloud.google.com/bigquery?project=wf-gcp-us-ae-retail-prod",
                },
                "sqlQuery": SQL_QUERY,
                "options": {},
            },
            "type": "n8n-nodes-base.googleBigQuery",
            "typeVersion": 2.1,
            "position": [280, 0],
            "id": ids["bq"],
            "name": "Execute a SQL query",
            "credentials": {"googleBigQueryOAuth2Api": BQ_CRED},
        },
        {
            "parameters": {
                "promptType": "define",
                "text": LLM_USER_PROMPT,
                "hasOutputParser": True,
                "messages": {
                    "messageValues": [
                        {
                            "type": "SystemMessagePromptTemplate",
                            "message": LLM_SYSTEM_PROMPT,
                        }
                    ]
                },
                "batching": {},
            },
            "type": "@n8n/n8n-nodes-langchain.chainLlm",
            "typeVersion": 1.7,
            "position": [560, 0],
            "id": ids["llm"],
            "name": "Basic LLM Chain",
        },
        {
            "parameters": {
                "model": {
                    "__rl": True,
                    "value": "gpt-4o-mini",
                    "mode": "list",
                    "cachedResultName": "gpt-4o-mini",
                },
                "options": {"temperature": 0.2},
            },
            "type": "@n8n/n8n-nodes-langchain.lmChatOpenAi",
            "typeVersion": 1.2,
            "position": [560, 220],
            "id": ids["openai"],
            "name": "OpenAI Chat Model",
        },
        {
            "parameters": {
                "schemaType": "manual",
                "inputSchema": json.dumps(OUTPUT_SCHEMA, indent=2),
            },
            "type": "@n8n/n8n-nodes-langchain.outputParserStructured",
            "typeVersion": 1.2,
            "position": [780, 220],
            "id": ids["parser"],
            "name": "Structured Output Parser",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": JS_CODE,
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [900, 0],
            "id": ids["code"],
            "name": "Code in JavaScript",
        },
        {
            "parameters": {
                # Hardcoded To per request (all emails go to Benjamin).
                # To send each SRM only their own list, use: ={{ $json.recipient_email }}
                "sendTo": "bhannigan@wayfair.com",
                "subject": "={{ $json.subject }}",
                "emailType": "html",
                "message": "={{ $json.emailHtml }}",
                "options": {},
            },
            "type": "n8n-nodes-base.gmail",
            "typeVersion": 2.2,
            "position": [1160, 0],
            "id": ids["gmail"],
            "name": "Send a message",
            "webhookId": nid(),
            "credentials": {"gmailOAuth2": GMAIL_CRED},
        },
    ]

    connections = {
        "Schedule Trigger": {
            "main": [[{"node": "Execute a SQL query", "type": "main", "index": 0}]]
        },
        "Execute a SQL query": {
            "main": [[{"node": "Basic LLM Chain", "type": "main", "index": 0}]]
        },
        "Basic LLM Chain": {
            "main": [[{"node": "Code in JavaScript", "type": "main", "index": 0}]]
        },
        "OpenAI Chat Model": {
            "ai_languageModel": [
                [{"node": "Basic LLM Chain", "type": "ai_languageModel", "index": 0}]
            ]
        },
        "Structured Output Parser": {
            "ai_outputParser": [
                [{"node": "Basic LLM Chain", "type": "ai_outputParser", "index": 0}]
            ]
        },
        "Code in JavaScript": {
            "main": [[{"node": "Send a message", "type": "main", "index": 0}]]
        },
    }

    return {
        "name": "Weekly Window Buyer's Remorse Alert",
        "nodes": nodes,
        "connections": connections,
        "active": False,
        "settings": {
            "executionOrder": "v1",
            "binaryMode": "separate",
            "availableInMCP": False,
        },
        "versionId": nid(),
        "meta": {
            "templateCredsSetupCompleted": True,
            "instanceId": INSTANCE_ID,
        },
        "tags": [],
        "pinData": {},
    }


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    workflow = build()
    OUT.write_text(json.dumps(workflow, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")
    print(f"Nodes: {[n['name'] for n in workflow['nodes']]}")


if __name__ == "__main__":
    main()
