#!/usr/bin/env python3
"""Build a narrative supplier performance workflow variant."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.build_top15_benchmark_workflow import (
    BENCHMARK_BUCKET_NODE_NAME,
    BENCHMARK_NODE_NAME,
    append_connection_if_missing,
    benchmark_bucket_node,
    benchmark_node,
    ensure_connection_list,
    patch_top15_sql,
    set_single_connection,
)
from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/THE_FINAL_PRODUCT_-_MONDAY_9AM_ET_-_ALL_STORES_ALL_SUBENTITIES_4ec0.json"
)
FORMATTER_PATH = ROOT / "workflow_assets" / "supplier_performance_narrative_formatter.js"
OUTPUT_PATH = ROOT / "workflow_exports" / "the-final-product-monday-9am-et-all-stores-all-subentities-narrative.json"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}

    benchmark_bigquery = benchmark_node(nodes["MRPI"]["credentials"])
    if BENCHMARK_NODE_NAME in nodes:
        nodes[BENCHMARK_NODE_NAME].update(benchmark_bigquery)
    else:
        workflow["nodes"].append(benchmark_bigquery)

    if BENCHMARK_BUCKET_NODE_NAME in nodes:
        nodes[BENCHMARK_BUCKET_NODE_NAME]["parameters"]["jsCode"] = benchmark_bucket_node()["parameters"]["jsCode"]
    else:
        workflow["nodes"].append(benchmark_bucket_node())

    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["Merge"]["parameters"]["numberInputs"] = 6
    nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"] = patch_top15_sql(
        nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"]
    )
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = load_text(FORMATTER_PATH)

    schedule_connections = ensure_connection_list(workflow["connections"], "Schedule Trigger")
    append_connection_if_missing(schedule_connections, BENCHMARK_NODE_NAME, 0)
    set_single_connection(workflow["connections"], BENCHMARK_NODE_NAME, BENCHMARK_BUCKET_NODE_NAME, 0)
    set_single_connection(workflow["connections"], BENCHMARK_BUCKET_NODE_NAME, "Merge", 5)

    save_json(OUTPUT_PATH, validate_workflow(workflow))
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
