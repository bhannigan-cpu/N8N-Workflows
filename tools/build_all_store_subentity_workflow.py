#!/usr/bin/env python3
"""Build a workflow variant without store/subentity filters."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.update_n8n_workflow import save_json, validate_workflow


INPUT_PATH = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/THE_FINAL_PRODUCT_-_MONDAY_9AM_ET_e8e4.json"
)
OUTPUT_PATH = ROOT / "workflow_exports" / "the-final-product-monday-9am-et-all-stores-all-subentities.json"
WORKFLOW_NAME = "THE FINAL PRODUCT - MONDAY 9AM ET - ALL STORES ALL SUBENTITIES"
FILTER_BLOCK_RE = re.compile(
    r"  WHERE retail_sku_store_date\.brandname = 'Wayfair'\n"
    r"\s+AND retail_sku_store_date\.styname = 'United States'\n"
    r"\s+AND"
)


def strip_filters(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: strip_filters(inner_value) for key, inner_value in value.items()}
    if isinstance(value, list):
        return [strip_filters(item) for item in value]
    if isinstance(value, str):
        value = FILTER_BLOCK_RE.sub("  WHERE", value)
        return value
    return value


def count_occurrences(value: Any, needle: str) -> int:
    if isinstance(value, dict):
        return sum(count_occurrences(inner_value, needle) for inner_value in value.values())
    if isinstance(value, list):
        return sum(count_occurrences(item, needle) for item in value)
    if isinstance(value, str):
        return value.count(needle)
    return 0


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    stripped = validate_workflow(strip_filters(workflow))
    stripped["name"] = WORKFLOW_NAME

    remaining_brand_filters = count_occurrences(stripped, "brandname = 'Wayfair'")
    remaining_subentity_filters = count_occurrences(stripped, "styname = 'United States'")
    if remaining_brand_filters != 0 or remaining_subentity_filters != 0:
        raise ValueError(
            "Expected all store/subentity filters to be removed, "
            f"found brand filters={remaining_brand_filters}, "
            f"subentity filters={remaining_subentity_filters}."
        )

    save_json(OUTPUT_PATH, stripped)
    print(f"Workflow written to: {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
