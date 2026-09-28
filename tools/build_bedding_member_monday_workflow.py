#!/usr/bin/env python3
"""Compatibility wrapper — use build_loyalty_promo_wsc_lift_workflow.py."""

from pathlib import Path
import runpy

runpy.run_path(
    str(Path(__file__).with_name("build_loyalty_promo_wsc_lift_workflow.py")),
    run_name="__main__",
)
