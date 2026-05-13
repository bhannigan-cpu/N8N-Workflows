#!/usr/bin/env python3
"""Build uploaded top15/WSC workflow variants."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/weekly-supplier-report-closest-top15-wsc.json"
)
FORMATTER_DOLLAR = ROOT / "workflow_assets" / "email_formatter_closest_top15_wsc_dollar.js"
FORMATTER_DOLLAR_COMPACT = ROOT / "workflow_assets" / "email_formatter_closest_top15_wsc_dollar_compact.js"
OUTPUT_DOLLAR = ROOT / "workflow_exports" / "weekly-supplier-report-closest-top15-wsc-dollar.json"
OUTPUT_DOLLAR_COMPACT = ROOT / "workflow_exports" / "weekly-supplier-report-closest-top15-wsc-dollar-compact.json"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def load_workflow() -> dict:
    return validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))


def build_variant(formatter_path: Path, output_path: Path) -> None:
    workflow = load_workflow()
    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = load_text(formatter_path)
    save_json(output_path, validate_workflow(workflow))


def main() -> int:
    build_variant(FORMATTER_DOLLAR, OUTPUT_DOLLAR)
    build_variant(FORMATTER_DOLLAR_COMPACT, OUTPUT_DOLLAR_COMPACT)
    print(f"WSC dollar workflow written to: {OUTPUT_DOLLAR}")
    print(f"Compact workflow written to:    {OUTPUT_DOLLAR_COMPACT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
