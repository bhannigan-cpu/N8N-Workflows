#!/usr/bin/env python3
"""Build current SRM workflow variant with Window and Bedding benchmark rows."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/Weekly_Supplier_Report__SRM__4484.json"
)
OUTPUT_PATH = ROOT / "workflow_exports" / "weekly-supplier-report-srm-4484-window-bedding-benchmark.json"
BENCHMARK_SQL_PATH = ROOT / "workflow_assets" / "top15_window_bedding_benchmark.sql"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["Top 15 Category Benchmark"]["parameters"]["sqlQuery"] = load_text(BENCHMARK_SQL_PATH)
    save_json(OUTPUT_PATH, validate_workflow(workflow))
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
