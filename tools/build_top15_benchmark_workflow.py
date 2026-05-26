#!/usr/bin/env python3
"""Build a workflow variant with a Top 15 benchmark row."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/THE_FINAL_PRODUCT_-_MONDAY_9AM_ET_-_ALL_STORES_ALL_SUBENTITIES_4ec0.json"
)
OUTPUT_PATH = ROOT / "workflow_exports" / "the-final-product-monday-9am-et-all-stores-all-subentities-benchmark-row.json"
BENCHMARK_SQL_PATH = ROOT / "workflow_assets" / "top15_category_benchmark.sql"
BENCHMARK_BUCKET_PATH = ROOT / "workflow_assets" / "top15_benchmark_bucket.js"
BENCHMARK_NODE_NAME = "Top 15 Category Benchmark"
BENCHMARK_BUCKET_NODE_NAME = "Benchmark Buckets"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def replace_once(text: str, old: str, new: str, *, label: str) -> str:
    if old not in text:
        raise ValueError(f"Expected to find {label} while patching formatter.")
    return text.replace(old, new, 1)


def patch_formatter(js_code: str) -> str:
    js_code = replace_once(
        js_code,
        """  const numericValues = rows
    .map(function(row) {""",
        """  const numericValues = asArray(rows)
    .filter(function(row) {
      return !row.is_benchmark;
    })
    .map(function(row) {""",
        label="heatmap rows block",
    )

    js_code = replace_once(
        js_code,
        """      const style = getCellStyle(row, col.key, heatmapStyles);
      const styleAttribute = style ? ` style="${style}"` : "";
      return `<td${styleAttribute}>${formatCell(row, col.key)}</td>`;""",
        """      const heatmapStyle = getCellStyle(row, col.key, heatmapStyles);
      const benchmarkStyle = row.is_benchmark
        ? "font-weight: 700; background-color: #edf4ff; border-top: 2px solid #1f4e79; border-bottom: 2px solid #1f4e79;"
        : "";
      const style = [heatmapStyle, benchmarkStyle].filter(Boolean).join(" ");
      const styleAttribute = style ? ` style="${style}"` : "";
      return `<td${styleAttribute}>${formatCell(row, col.key)}</td>`;""",
        label="table cell style block",
    )

    js_code = replace_once(
        js_code,
        """const supplierColumns = [""",
        """const topCurrentGrsRows = asArray(data.topCurrentGrs).concat(asArray(data.topCurrentGrsBenchmark));

const supplierColumns = [""",
        label="supplier columns block",
    )

    js_code = replace_once(
        js_code,
        '  ${makeTable("Top 15 Current GRS", data.topCurrentGrs, [',
        '  ${makeTable("Top 15 Current GRS", topCurrentGrsRows, [',
        label="top 15 table source",
    )

    js_code = replace_once(
        js_code,
        """    { label: "WSC", key: "current_wsc" },
    { label: "Visits", key: "current_visits" },""",
        """    { label: "WSC", key: "current_wsc" },
    { label: "WSC WoW %", key: "wow_wsc_pct_change" },
    { label: "WSC YoY %", key: "yoy_wsc_pct_change" },
    { label: "Visits", key: "current_visits" },""",
        label="top 15 wsc columns",
    )

    return js_code


def patch_top15_sql(sql: str) -> str:
    sql = replace_once(
        sql,
        """    SUM(IF(wg.week_start = params.current_week_start, wg.weekly_grs, 0)) AS current_grs,
    SUM(IF(wg.week_start = params.current_week_start, wg.weekly_wsc, 0)) AS current_wsc,
    SUM(IF(wg.week_start = params.prior_week_start, wg.weekly_grs, 0)) AS prior_week_grs,
    SUM(IF(wg.week_start = params.prior_year_week_start, wg.weekly_grs, 0)) AS prior_year_grs""",
        """    SUM(IF(wg.week_start = params.current_week_start, wg.weekly_grs, 0)) AS current_grs,
    SUM(IF(wg.week_start = params.current_week_start, wg.weekly_wsc, 0)) AS current_wsc,
    SUM(IF(wg.week_start = params.prior_week_start, wg.weekly_wsc, 0)) AS prior_week_wsc,
    SUM(IF(wg.week_start = params.prior_year_week_start, wg.weekly_wsc, 0)) AS prior_year_wsc,
    SUM(IF(wg.week_start = params.prior_week_start, wg.weekly_grs, 0)) AS prior_week_grs,
    SUM(IF(wg.week_start = params.prior_year_week_start, wg.weekly_grs, 0)) AS prior_year_grs""",
        label="grs metrics wsc block",
    )

    sql = replace_once(
        sql,
        """    availability_metrics.current_availability,
    grs_metrics.current_wsc,
    availability_metrics.prior_week_availability,""",
        """    availability_metrics.current_availability,
    grs_metrics.current_wsc,
    grs_metrics.prior_week_wsc,
    grs_metrics.prior_year_wsc,
    grs_metrics.current_wsc - grs_metrics.prior_week_wsc AS wow_wsc_change,
    SAFE_DIVIDE(grs_metrics.current_wsc - grs_metrics.prior_week_wsc, NULLIF(grs_metrics.prior_week_wsc, 0)) AS wow_wsc_pct_change,
    grs_metrics.current_wsc - grs_metrics.prior_year_wsc AS yoy_wsc_change,
    SAFE_DIVIDE(grs_metrics.current_wsc - grs_metrics.prior_year_wsc, NULLIF(grs_metrics.prior_year_wsc, 0)) AS yoy_wsc_pct_change,
    availability_metrics.prior_week_availability,""",
        label="final metrics wsc block",
    )

    sql = replace_once(
        sql,
        """    current_availability,
    current_wsc,
    prior_week_availability,""",
        """    current_availability,
    current_wsc,
    prior_week_wsc,
    prior_year_wsc,
    wow_wsc_change,
    wow_wsc_pct_change,
    yoy_wsc_change,
    yoy_wsc_pct_change,
    prior_week_availability,""",
        label="ranked metrics wsc block",
    )

    sql = replace_once(
        sql,
        """    supplier_name,
    supplier_id,
    SUM(IF(week_start = params.current_week_start, visits, 0)) AS current_visits,
    SUM(IF(week_start = params.prior_year_week_start, visits, 0)) AS prior_year_visits,
    SUM(IF(week_start = params.current_week_start, converted, 0)) AS current_converted,
    SUM(IF(week_start = params.prior_year_week_start, converted, 0)) AS prior_year_converted""",
        """    supplier_name,
    supplier_id,
    SUM(IF(week_start = params.current_week_start, visits, 0)) AS current_visits,
    SUM(IF(week_start = params.prior_week_start, visits, 0)) AS prior_week_visits,
    SUM(IF(week_start = params.prior_year_week_start, visits, 0)) AS prior_year_visits,
    SUM(IF(week_start = params.current_week_start, converted, 0)) AS current_converted,
    SUM(IF(week_start = params.prior_year_week_start, converted, 0)) AS prior_year_converted""",
        label="traffic metrics prior week visits block",
    )

    sql = replace_once(
        sql,
        """    traffic_metrics.current_visits,
    traffic_metrics.prior_year_visits,
    traffic_metrics.current_visits - traffic_metrics.prior_year_visits AS yoy_visits_change,
    SAFE_DIVIDE(
      traffic_metrics.current_visits - traffic_metrics.prior_year_visits,
      NULLIF(traffic_metrics.prior_year_visits, 0)
    ) AS yoy_visits_pct_change,""",
        """    traffic_metrics.current_visits,
    traffic_metrics.prior_week_visits,
    traffic_metrics.prior_year_visits,
    traffic_metrics.current_visits - traffic_metrics.prior_week_visits AS wow_visits_change,
    SAFE_DIVIDE(
      traffic_metrics.current_visits - traffic_metrics.prior_week_visits,
      NULLIF(traffic_metrics.prior_week_visits, 0)
    ) AS wow_visits_pct_change,
    traffic_metrics.current_visits - traffic_metrics.prior_year_visits AS yoy_visits_change,
    SAFE_DIVIDE(
      traffic_metrics.current_visits - traffic_metrics.prior_year_visits,
      NULLIF(traffic_metrics.prior_year_visits, 0)
    ) AS yoy_visits_pct_change,""",
        label="final metrics wow visits block",
    )

    sql = replace_once(
        sql,
        """    current_visits,
    prior_year_visits,
    yoy_visits_change,
    yoy_visits_pct_change,
    current_cvr,""",
        """    current_visits,
    prior_week_visits,
    prior_year_visits,
    wow_visits_change,
    wow_visits_pct_change,
    yoy_visits_change,
    yoy_visits_pct_change,
    current_cvr,""",
        label="ranked metrics wow visits block",
    )

    return sql


def benchmark_node(existing_credentials: dict) -> dict:
    return {
        "parameters": {
            "projectId": {
                "__rl": True,
                "value": "wf-gcp-us-ae-eunarta-proc-prod",
                "mode": "list",
                "cachedResultName": "wf-gcp-us-ae-eunarta-proc-prod",
                "cachedResultUrl": "https://console.cloud.google.com/bigquery?project=wf-gcp-us-ae-eunarta-proc-prod",
            },
            "sqlQuery": load_text(BENCHMARK_SQL_PATH),
            "options": {},
        },
        "type": "n8n-nodes-base.googleBigQuery",
        "typeVersion": 2.1,
        "position": [-48, 64],
        "id": "5ad90286-8795-4f6c-80f0-050e3c0a71d1",
        "name": BENCHMARK_NODE_NAME,
        "credentials": existing_credentials,
    }


def benchmark_bucket_node() -> dict:
    return {
        "parameters": {
            "jsCode": load_text(BENCHMARK_BUCKET_PATH),
        },
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [240, 64],
        "id": "bb841089-3fea-4aaf-8b2c-97d61652ef13",
        "name": BENCHMARK_BUCKET_NODE_NAME,
    }


def ensure_connection_list(connections: dict, source_name: str) -> list:
    entry = connections.setdefault(source_name, {})
    return entry.setdefault("main", [[]])[0]


def append_connection_if_missing(connection_list: list, node_name: str, index: int) -> None:
    if not any(item.get("node") == node_name and item.get("index") == index for item in connection_list):
        connection_list.append({"node": node_name, "type": "main", "index": index})


def set_single_connection(connections: dict, source_name: str, target_name: str, target_index: int) -> None:
    connections[source_name] = {
        "main": [[{"node": target_name, "type": "main", "index": target_index}]]
    }


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}

    benchmark_bigquery = benchmark_node(nodes["MRPI"]["credentials"])
    if BENCHMARK_NODE_NAME in nodes:
        nodes[BENCHMARK_NODE_NAME].update(benchmark_bigquery)
    else:
        workflow["nodes"].append(benchmark_bigquery)

    if BENCHMARK_BUCKET_NODE_NAME in nodes:
        nodes[BENCHMARK_BUCKET_NODE_NAME]["parameters"]["jsCode"] = load_text(BENCHMARK_BUCKET_PATH)
    else:
        workflow["nodes"].append(benchmark_bucket_node())

    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["Merge"]["parameters"]["numberInputs"] = 6
    nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"] = patch_top15_sql(
        nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"]
    )
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = patch_formatter(
        nodes["Code in JavaScript"]["parameters"]["jsCode"]
    )

    schedule_connections = ensure_connection_list(workflow["connections"], "Schedule Trigger")
    append_connection_if_missing(schedule_connections, BENCHMARK_NODE_NAME, 0)
    set_single_connection(workflow["connections"], BENCHMARK_NODE_NAME, BENCHMARK_BUCKET_NODE_NAME, 0)
    set_single_connection(workflow["connections"], BENCHMARK_BUCKET_NODE_NAME, "Merge", 5)

    save_json(OUTPUT_PATH, validate_workflow(workflow))
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
