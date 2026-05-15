#!/usr/bin/env python3
"""Build the final product workflow with action items."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/THE_FINAL_PRODUCT_9614.json"
)
FORMATTER_PATH = ROOT / "workflow_assets" / "email_formatter_final_action_items.js"
OUTPUT_PATH = ROOT / "workflow_exports" / "the-final-product-action-items.json"
WORKFLOW_NAME = "THE FINAL PRODUCT - MONDAY 9AM ET"
SCHEDULE_RULE = {
    "field": "weeks",
    "weeksInterval": 1,
    "triggerAtDay": [1],
    "triggerAtHour": 9,
    "triggerAtMinute": 0,
}
TIMEZONE = "America/New_York"


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    nodes = {node["name"]: node for node in workflow["nodes"]}
    workflow["name"] = WORKFLOW_NAME
    nodes["Schedule Trigger"]["parameters"]["rule"] = {"interval": [SCHEDULE_RULE]}
    nodes["Code in JavaScript"]["parameters"]["jsCode"] = load_text(FORMATTER_PATH)
    workflow["active"] = True
    workflow.setdefault("settings", {})
    workflow["settings"]["timezone"] = TIMEZONE
    save_json(OUTPUT_PATH, validate_workflow(workflow))
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
