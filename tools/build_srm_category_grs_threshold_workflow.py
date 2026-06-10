#!/usr/bin/env python3
"""Build SRM workflow variant with category column and GRS threshold filters."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/Weekly_Supplier_Report__SRM__86c1.json"
)
OUTPUT_PATH = ROOT / "workflow_exports" / "weekly-supplier-report-srm-category-grs-threshold.json"
GRS_THRESHOLD = 7000


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    if old not in text:
        raise ValueError(f"Expected to find {label} while patching workflow.")
    return text.replace(old, new, 1)


def patch_wsc_grs_sql(sql: str) -> str:
    sql = replace_once(
        sql,
        """weekly_grs AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol,
    SUM(grs) AS weekly_grs,
    SUM(wsc) AS weekly_wsc
  FROM deduped_grs_orders
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol
),

grs_metrics AS (""",
        """weekly_grs AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol,
    SUM(grs) AS weekly_grs,
    SUM(wsc) AS weekly_wsc
  FROM deduped_grs_orders
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    currency_symbol
),

category_order_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuname AS supplier_name,
    retail_dim_supplier.origsuid AS supplier_id,
    COALESCE(retail_dim_sku.mkcname, 'Unknown') AS marketing_category,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku` AS retail_dim_sku
    ON retail_dim_sku.skuid = retail_sku_store_date.skuid
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_category_orders AS (
  SELECT
    week_start,
    supplier_name,
    supplier_id,
    marketing_category,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM category_order_rows
  GROUP BY
    week_start,
    supplier_name,
    supplier_id,
    marketing_category,
    order_id
),

top_marketing_category AS (
  SELECT
    supplier_name,
    supplier_id,
    marketing_category
  FROM (
    SELECT
      supplier_name,
      supplier_id,
      marketing_category,
      SUM(grs) AS category_grs,
      ROW_NUMBER() OVER (
        PARTITION BY supplier_id
        ORDER BY SUM(grs) DESC, marketing_category
      ) AS category_rank
    FROM deduped_category_orders
    GROUP BY
      supplier_name,
      supplier_id,
      marketing_category
  )
  WHERE category_rank = 1
),

grs_metrics AS (""",
        label="insert marketing category ctes",
    )

    sql = replace_once(
        sql,
        """    grs_metrics.currency_symbol,
    grs_metrics.current_grs,""",
        """    grs_metrics.currency_symbol,
    top_marketing_category.marketing_category,
    grs_metrics.current_grs,""",
        label="final metrics marketing category select",
    )

    sql = replace_once(
        sql,
        """  LEFT JOIN availability_metrics
    ON availability_metrics.supplier_id = grs_metrics.supplier_id""",
        """  LEFT JOIN top_marketing_category
    ON top_marketing_category.supplier_id = grs_metrics.supplier_id
  LEFT JOIN availability_metrics
    ON availability_metrics.supplier_id = grs_metrics.supplier_id""",
        label="final metrics marketing category join",
    )

    sql = replace_once(
        sql,
        """    currency_symbol,
    current_grs,""",
        """    currency_symbol,
    marketing_category,
    current_grs,""",
        label="ranked metrics marketing category select",
    )

    sql = replace_once(
        sql,
        """  WHERE current_grs > 0
  QUALIFY rank <= 15""",
        f"""  WHERE current_grs > {GRS_THRESHOLD}
  QUALIFY rank <= 15""",
        label="top grs threshold",
    )

    sql = sql.replace(
        """  WHERE current_grs > 0
    AND prior_week_grs > 0
    AND wow_grs_pct IS NOT NULL""",
        f"""  WHERE current_grs > {GRS_THRESHOLD}
    AND prior_week_grs > 0
    AND wow_grs_pct IS NOT NULL""",
    )

    sql = sql.replace(
        """  WHERE current_grs > 0
    AND prior_year_grs > 0
    AND yoy_grs_pct IS NOT NULL""",
        f"""  WHERE current_grs > {GRS_THRESHOLD}
    AND prior_year_grs > 0
    AND yoy_grs_pct IS NOT NULL""",
    )

    return sql


def add_grs_threshold_to_supplier_query(sql: str) -> str:
    sql = replace_once(
        sql,
        """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start
),""",
        """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),""",
        label="currency cte",
    )

    sql = replace_once(
        sql,
        """final_metrics AS (
  SELECT
    supplier_name,
    supplier_id,""",
        f"""grs_threshold_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuid AS supplier_id,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_grs_threshold AS (
  SELECT
    week_start,
    supplier_id,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM grs_threshold_rows
  GROUP BY
    week_start,
    supplier_id,
    order_id
),

current_grs_threshold AS (
  SELECT
    supplier_id,
    SUM(grs) AS current_grs
  FROM deduped_grs_threshold
  GROUP BY supplier_id
),

final_metrics AS (
  SELECT
    supplier_metrics.supplier_name,
    supplier_metrics.supplier_id,
    current_grs_threshold.current_grs,""",
        label="insert current grs threshold ctes",
    )

    sql = replace_once(
        sql,
        """  FROM supplier_metrics
),""",
        """  FROM supplier_metrics
  INNER JOIN current_grs_threshold
    ON current_grs_threshold.supplier_id = supplier_metrics.supplier_id
),""",
        label="join current grs threshold",
    )

    sql = replace_once(
        sql,
        """  WHERE current_mrpi IS NOT NULL""",
        f"""  WHERE current_mrpi IS NOT NULL
    AND current_grs > {GRS_THRESHOLD}""",
        label="mrpi threshold top value",
    )
    sql = replace_once(
        sql,
        """  WHERE current_mrpi IS NOT NULL
    AND prior_week_mrpi IS NOT NULL""",
        f"""  WHERE current_mrpi IS NOT NULL
    AND current_grs > {GRS_THRESHOLD}
    AND prior_week_mrpi IS NOT NULL""",
        label="mrpi threshold movers",
    )
    return sql


def patch_traffic_sql(sql: str) -> str:
    sql = replace_once(
        sql,
        """WITH params AS (
  SELECT
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -1 WEEK) AS current_week_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -53 WEEK) AS prior_year_week_start
),""",
        """WITH params AS (
  SELECT
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -1 WEEK) AS current_week_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -53 WEEK) AS prior_year_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),""",
        label="traffic currency cte",
    )

    sql = replace_once(
        sql,
        """final_metrics AS (
  SELECT
    supplier_name,
    supplier_id,""",
        f"""grs_threshold_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuid AS supplier_id,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_grs_threshold AS (
  SELECT
    week_start,
    supplier_id,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM grs_threshold_rows
  GROUP BY
    week_start,
    supplier_id,
    order_id
),

current_grs_threshold AS (
  SELECT
    supplier_id,
    SUM(grs) AS current_grs
  FROM deduped_grs_threshold
  GROUP BY supplier_id
),

final_metrics AS (
  SELECT
    supplier_metrics.supplier_name,
    supplier_metrics.supplier_id,
    current_grs_threshold.current_grs,""",
        label="traffic insert threshold ctes",
    )

    sql = replace_once(
        sql,
        """  FROM supplier_metrics
),""",
        """  FROM supplier_metrics
  INNER JOIN current_grs_threshold
    ON current_grs_threshold.supplier_id = supplier_metrics.supplier_id
),""",
        label="traffic join threshold",
    )

    sql = sql.replace(
        """  WHERE current_visits > 0""",
        f"""  WHERE current_visits > 0
    AND current_grs > {GRS_THRESHOLD}""",
    )

    return sql


def patch_wsi_sql(sql: str) -> str:
    sql = replace_once(
        sql,
        """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start
),""",
        """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start
),

currency AS (
  SELECT
    ANY_VALUE(ExchangeRate) AS exchange_rate
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.vw_local_currency_conversion`
  WHERE CuyShortName = 'USD'
),""",
        label="wsi currency cte",
    )

    sql = replace_once(
        sql,
        """final_metrics AS (
  SELECT
    supplier_name,
    supplier_id,""",
        f"""grs_threshold_rows AS (
  SELECT
    DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) AS week_start,
    retail_dim_supplier.origsuid AS supplier_id,
    orders.id AS order_id,
    COALESCE(orders.grossrevenuestable, 0) * COALESCE(currency.exchange_rate, 1) AS grs
  FROM `wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg` AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN UNNEST(supplier_struct.supplier_part_struct) AS supplier_part_struct
  LEFT JOIN UNNEST(supplier_part_struct.orders) AS orders
  LEFT JOIN `wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier` AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  CROSS JOIN currency
  CROSS JOIN params
  WHERE retail_dim_supplier.srmcontactname = 'Hannigan, Benjamin'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND DATE_TRUNC(retail_sku_store_date.date, WEEK(SUNDAY)) = params.current_week_start
),

deduped_grs_threshold AS (
  SELECT
    week_start,
    supplier_id,
    order_id,
    ANY_VALUE(grs) AS grs
  FROM grs_threshold_rows
  GROUP BY
    week_start,
    supplier_id,
    order_id
),

current_grs_threshold AS (
  SELECT
    supplier_id,
    SUM(grs) AS current_grs
  FROM deduped_grs_threshold
  GROUP BY supplier_id
),

final_metrics AS (
  SELECT
    supplier_metrics.supplier_name,
    supplier_metrics.supplier_id,
    current_grs_threshold.current_grs,""",
        label="wsi insert threshold ctes",
    )

    sql = replace_once(
        sql,
        """  FROM supplier_metrics
),""",
        """  FROM supplier_metrics
  INNER JOIN current_grs_threshold
    ON current_grs_threshold.supplier_id = supplier_metrics.supplier_id
),""",
        label="wsi join threshold",
    )

    sql = replace_once(
        sql,
        """  WHERE current_wsi IS NOT NULL""",
        f"""  WHERE current_wsi IS NOT NULL
    AND current_grs > {GRS_THRESHOLD}""",
        label="wsi top threshold",
    )
    sql = replace_once(
        sql,
        """  WHERE current_wsi IS NOT NULL
    AND prior_week_wsi IS NOT NULL""",
        f"""  WHERE current_wsi IS NOT NULL
    AND current_grs > {GRS_THRESHOLD}
    AND prior_week_wsi IS NOT NULL""",
        label="wsi movers threshold",
    )
    return sql


def patch_formatter(js_code: str) -> str:
    js_code = replace_once(
        js_code,
        """const supplierColumns = [
  { label: "Rank", key: "rank" },
  { label: "Supplier", key: "supplier_name" },
  { label: "Supplier ID", key: "supplier_id" }
];""",
        """const supplierColumns = [
  { label: "Rank", key: "rank" },
  { label: "Supplier", key: "supplier_name" },
  { label: "Supplier ID", key: "supplier_id" }
];

const topCurrentGrsColumns = [
  ...supplierColumns,
  { label: "Marketing Category", key: "marketing_category" }
];""",
        label="supplier columns formatter block",
    )

    js_code = replace_once(
        js_code,
        """  ${makeTable("Top 15 Current GRS", topCurrentGrsRows, [
    ...supplierColumns,""",
        """  ${makeTable("Top 15 Current GRS", topCurrentGrsRows, [
    ...topCurrentGrsColumns,""",
        label="top 15 supplier columns block",
    )

    return js_code


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}

    nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"] = patch_wsc_grs_sql(
        nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"]
    )
    nodes["MRPI"]["parameters"]["sqlQuery"] = add_grs_threshold_to_supplier_query(
        nodes["MRPI"]["parameters"]["sqlQuery"]
    )
    nodes["Visits/CVR"]["parameters"]["sqlQuery"] = patch_traffic_sql(
        nodes["Visits/CVR"]["parameters"]["sqlQuery"]
    )
    nodes["WSI"]["parameters"]["sqlQuery"] = patch_wsi_sql(
        nodes["WSI"]["parameters"]["sqlQuery"]
    )
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = patch_formatter(
        nodes["Code in JavaScript"]["parameters"]["jsCode"]
    )

    save_json(OUTPUT_PATH, validate_workflow(workflow))
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
