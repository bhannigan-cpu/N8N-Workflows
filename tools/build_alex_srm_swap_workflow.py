#!/usr/bin/env python3
"""Build an uploaded workflow with SRM and date-window fixes."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/THE_FINAL_PRODUCT_-_MONDAY_9AM_ET_ALEX_9da5.json"
)
OUTPUT_PATH = ROOT / "workflow_exports" / "the-final-product-monday-9am-et-alex-sarkisian.json"
OLD_SRM = "Hannigan, Benjamin"
NEW_SRM = "Sarkisian, Alex"
WEEKLY_SOURCE = "`wf-gcp-us-ae-retail-prod.cm_reporting.retail_sku_store_date_agg`"
SUPPLIER_DIM = "`wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_supplier`"

WEEKLY_PARAMS_WITH_PRIOR_YEAR = """WITH latest_complete_week AS (
  SELECT
    DATE_TRUNC(MAX(retail_sku_store_date.date), WEEK(SUNDAY)) AS current_week_start
  FROM {weekly_source} AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN {supplier_dim} AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = '{srm_name}'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.date < DATE_TRUNC(CURRENT_DATE("America/New_York"), WEEK(SUNDAY))
),

params AS (
  SELECT
    current_week_start,
    DATE_SUB(current_week_start, INTERVAL 1 WEEK) AS prior_week_start,
    DATE_SUB(current_week_start, INTERVAL 53 WEEK) AS prior_year_week_start
  FROM latest_complete_week
)""".format(
    weekly_source=WEEKLY_SOURCE,
    supplier_dim=SUPPLIER_DIM,
    srm_name=NEW_SRM,
)

WEEKLY_PARAMS = """WITH latest_complete_week AS (
  SELECT
    DATE_TRUNC(MAX(retail_sku_store_date.date), WEEK(SUNDAY)) AS current_week_start
  FROM {weekly_source} AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN {supplier_dim} AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = '{srm_name}'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.date < DATE_TRUNC(CURRENT_DATE("America/New_York"), WEEK(SUNDAY))
),

params AS (
  SELECT
    current_week_start,
    DATE_SUB(current_week_start, INTERVAL 1 WEEK) AS prior_week_start
  FROM latest_complete_week
)""".format(
    weekly_source=WEEKLY_SOURCE,
    supplier_dim=SUPPLIER_DIM,
    srm_name=NEW_SRM,
)

WEEKLY_PARAMS_TRAFFIC = """WITH latest_complete_week AS (
  SELECT
    DATE_TRUNC(MAX(retail_sku_store_date.date), WEEK(SUNDAY)) AS current_week_start
  FROM {weekly_source} AS retail_sku_store_date
  LEFT JOIN UNNEST(retail_sku_store_date.supplier_struct) AS supplier_struct
  LEFT JOIN {supplier_dim} AS retail_dim_supplier
    ON retail_dim_supplier.supplierkey = supplier_struct.supplierkey
  WHERE retail_sku_store_date.brandname = 'Wayfair'
    AND retail_sku_store_date.styname = 'United States'
    AND retail_dim_supplier.srmcontactname = '{srm_name}'
    AND retail_sku_store_date.agg_level = 'WEEKLY'
    AND retail_sku_store_date.date < DATE_TRUNC(CURRENT_DATE("America/New_York"), WEEK(SUNDAY))
),

params AS (
  SELECT
    current_week_start,
    DATE_SUB(current_week_start, INTERVAL 53 WEEK) AS prior_year_week_start
  FROM latest_complete_week
)""".format(
    weekly_source=WEEKLY_SOURCE,
    supplier_dim=SUPPLIER_DIM,
    srm_name=NEW_SRM,
)

FIXED_WSI_INDEX = "    AND CAST(wpi_wsi.indexdate AS STRING) = '2025-04-02'"
DYNAMIC_WSI_INDEX = """    AND CAST(wpi_wsi.indexdate AS DATE) = (
      SELECT MAX(CAST(wpi_wsi_inner.indexdate AS DATE))
      FROM {weekly_source} AS retail_sku_store_date_inner
      LEFT JOIN UNNEST(retail_sku_store_date_inner.supplier_struct) AS supplier_struct_inner
      LEFT JOIN UNNEST(supplier_struct_inner.wpi_wsi) AS wpi_wsi_inner
      LEFT JOIN {supplier_dim} AS retail_dim_supplier_inner
        ON retail_dim_supplier_inner.supplierkey = supplier_struct_inner.supplierkey
      CROSS JOIN params
      WHERE retail_sku_store_date_inner.brandname = 'Wayfair'
        AND retail_sku_store_date_inner.styname = 'United States'
        AND retail_dim_supplier_inner.srmcontactname = '{srm_name}'
        AND retail_sku_store_date_inner.agg_level = 'WEEKLY'
        AND DATE_TRUNC(retail_sku_store_date_inner.date, WEEK(SUNDAY)) IN (
          params.current_week_start,
          params.prior_week_start
        )
    )""".format(
    weekly_source=WEEKLY_SOURCE,
    supplier_dim=SUPPLIER_DIM,
    srm_name=NEW_SRM,
)


def replace_strings(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: replace_strings(inner_value) for key, inner_value in value.items()}
    if isinstance(value, list):
        return [replace_strings(item) for item in value]
    if isinstance(value, str):
        return value.replace(OLD_SRM, NEW_SRM)
    return value


def count_strings(value: Any, needle: str) -> int:
    if isinstance(value, dict):
        return sum(count_strings(inner_value, needle) for inner_value in value.values())
    if isinstance(value, list):
        return sum(count_strings(item, needle) for item in value)
    if isinstance(value, str):
        return value.count(needle)
    return 0


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    if old not in text:
        raise ValueError(f"Expected to find {label} in SQL but it was missing.")
    return text.replace(old, new, 1)


def patch_sql_queries(workflow: dict[str, Any]) -> dict[str, Any]:
    nodes = {node["name"]: node for node in workflow["nodes"]}

    nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"] = replace_once(
        nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"],
        """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 53 WEEK) AS prior_year_week_start
)""",
        WEEKLY_PARAMS_WITH_PRIOR_YEAR,
        label="weekly params with prior year",
    )

    for node_name in ["MRPI", "Availability", "WSI"]:
        nodes[node_name]["parameters"]["sqlQuery"] = replace_once(
            nodes[node_name]["parameters"]["sqlQuery"],
            """WITH params AS (
  SELECT
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 1 WEEK) AS current_week_start,
    DATE_SUB(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL 2 WEEK) AS prior_week_start
)""",
            WEEKLY_PARAMS,
            label=f"{node_name} weekly params",
        )

    nodes["Visits/CVR"]["parameters"]["sqlQuery"] = replace_once(
        nodes["Visits/CVR"]["parameters"]["sqlQuery"],
        """WITH params AS (
  SELECT
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -1 WEEK) AS current_week_start,
    DATE_ADD(DATE_TRUNC(CURRENT_DATE(), WEEK(SUNDAY)), INTERVAL -53 WEEK) AS prior_year_week_start
)""",
        WEEKLY_PARAMS_TRAFFIC,
        label="traffic params",
    )

    for node_name in ["WSC/GRS Movers", "WSI"]:
        nodes[node_name]["parameters"]["sqlQuery"] = replace_once(
            nodes[node_name]["parameters"]["sqlQuery"],
            FIXED_WSI_INDEX,
            DYNAMIC_WSI_INDEX,
            label=f"{node_name} fixed WSI indexdate",
        )

    return workflow


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    replaced = validate_workflow(replace_strings(workflow))
    replaced = validate_workflow(patch_sql_queries(replaced))

    old_count = count_strings(replaced, OLD_SRM)
    new_count = count_strings(replaced, NEW_SRM)
    if old_count != 0:
        raise ValueError(f"Expected 0 remaining '{OLD_SRM}' strings, found {old_count}.")
    if new_count == 0:
        raise ValueError(f"Expected at least one '{NEW_SRM}' string after replacement.")

    save_json(OUTPUT_PATH, replaced)
    print(f"Workflow written to: {OUTPUT_PATH}")
    print(f"Replaced SRM references: {new_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
