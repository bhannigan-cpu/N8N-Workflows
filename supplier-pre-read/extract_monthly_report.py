#!/usr/bin/env python3
"""Extract text + standard screenshot crops from a Monthly Supplier Report PDF."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pymupdf


DEFAULT_CLIPS = {
    "performance_dashboard": (0, 185, 1260, 720),
    "traffic": (0, 4180, 1260, 4750),
    "advertising": (500, 3750, 1260, 4180),
    "availability": (700, 1180, 1260, 1650),
    "class_breakdown": (0, 3450, 700, 3750),
    "b2b_ops": (0, 720, 1260, 1200),
}


def extract_text(page: pymupdf.Page) -> str:
    return page.get_text("text")


def find_metrics(text: str) -> dict:
    """Best-effort metric scrape for QA. Numbers are validated against screenshots."""
    metrics: dict[str, str] = {}

    m = re.search(r"Last Completed Month \(LCM\)\s*\n\s*([A-Za-z]+ \d{4})", text)
    if m:
        metrics["lcm_month"] = m.group(1)

    m = re.search(r"Original SuID is\s*\n\s*(\d+)", text)
    if m:
        metrics["suid"] = m.group(1)

    m = re.search(
        r"([A-Za-z0-9 &.'\-]+(?:LLC|Inc|DBA)[^\n]*)\s*\n\s*([\d,]+)\s*\n\s*LCM Sales",
        text,
    )
    if m:
        metrics["supplier_name"] = m.group(1).strip()
        metrics["lcm_sales"] = m.group(2)

    m = re.search(r"% of Sales from B2B\s*\n\s*(\d+%)", text)
    if m:
        metrics["b2b_share"] = m.group(1)

    m = re.search(r"Availability \(2\.0\) - Global\s*\n\s*([\d.]+%)", text)
    if m:
        metrics["availability"] = m.group(1)

    m = re.search(r"Supplier Fill Rate DS\s*\n\s*([\d.]+%)", text)
    if m:
        metrics["fill_rate_ds"] = m.group(1)

    return metrics


def crop_assets(page: pymupdf.Page, out_dir: Path, zoom: float = 2.0) -> list[str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    mat = pymupdf.Matrix(zoom, zoom)
    saved = []
    # Scale clip coords if page width differs from the canonical 1260 Looker export.
    scale_x = page.rect.width / 1260.0
    scale_y = page.rect.height / 5097.1201171875
    for name, (x0, y0, x1, y1) in DEFAULT_CLIPS.items():
        clip = pymupdf.Rect(x0 * scale_x, y0 * scale_y, x1 * scale_x, y1 * scale_y)
        pix = page.get_pixmap(matrix=mat, clip=clip)
        path = out_dir / f"{name}.png"
        pix.save(str(path))
        saved.append(str(path))
    return saved


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Path to Monthly Supplier Report PDF")
    parser.add_argument(
        "--assets-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "assets",
    )
    parser.add_argument(
        "--metrics-json",
        type=Path,
        default=Path(__file__).resolve().parent / "outputs" / "latest_metrics.json",
    )
    args = parser.parse_args()

    doc = pymupdf.open(args.pdf)
    page = doc[0]
    text = extract_text(page)
    metrics = find_metrics(text)
    assets = crop_assets(page, args.assets_dir)
    doc.close()

    args.metrics_json.parent.mkdir(parents=True, exist_ok=True)
    payload = {"source_pdf": str(args.pdf), "metrics": metrics, "assets": assets}
    args.metrics_json.write_text(json.dumps(payload, indent=2))
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
