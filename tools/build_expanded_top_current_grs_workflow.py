#!/usr/bin/env python3
"""Build an updated n8n export with an expanded Top Current GRS bucket."""

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
    "/home/ubuntu/.cursor/projects/workspace/uploads/Weekly_Supplier_Report_REAL.json"
)
DEFAULT_OUTPUT = ROOT / "workflow_exports" / "weekly-supplier-report-real-expanded-top-current-grs.json"
SQL_PATH = ROOT / "workflow_assets" / "top_current_grs_expanded.sql"
EMAIL_FORMATTER_PATH = ROOT / "workflow_assets" / "email_formatter_top_current_grs_expanded.js"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def build_workflow(input_path: Path) -> dict:
    workflow = validate_workflow(json.loads(input_path.read_text(encoding="utf-8")))

    nodes = {node["name"]: node for node in workflow["nodes"]}
    nodes["WSC/GRS Movers"]["parameters"]["sqlQuery"] = load_text(SQL_PATH)
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = load_text(EMAIL_FORMATTER_PATH)

    return validate_workflow(workflow)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create an updated workflow export with an expanded Top Current GRS email bucket."
    )
    parser.add_argument("--input", default=str(DEFAULT_INPUT), help="Base workflow JSON path.")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output workflow JSON path.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    workflow = build_workflow(input_path)
    save_json(output_path, workflow)

    print(f"Updated workflow written to: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
