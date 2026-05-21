#!/usr/bin/env python3
"""Build an uploaded workflow with swapped SRM contact names."""

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


def main() -> int:
    workflow = validate_workflow(json.loads(INPUT_PATH.read_text(encoding="utf-8")))
    replaced = validate_workflow(replace_strings(workflow))

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
