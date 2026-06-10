#!/usr/bin/env python3
"""Build an updated export from Weekly_Supplier_Report_CLOSEST.json."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


DEFAULT_INPUT = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/Weekly_Supplier_Report_CLOSEST.json"
)
DEFAULT_OUTPUT = ROOT / "workflow_exports" / "weekly-supplier-report-closest-pricing-step1.json"
FORMATTER_PATH = ROOT / "workflow_assets" / "email_formatter_closest_pricing.js"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def build_workflow(input_path: Path) -> dict:
    workflow = validate_workflow(json.loads(input_path.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = load_text(FORMATTER_PATH)
    return validate_workflow(workflow)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a workflow export from Weekly_Supplier_Report_CLOSEST.json with pricing heatmap updates."
    )
    parser.add_argument("--input", default=str(DEFAULT_INPUT), help="Base workflow JSON path.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output workflow JSON path.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workflow = build_workflow(Path(args.input))
    save_json(Path(args.output), workflow)
    print(f"Updated workflow written to: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
