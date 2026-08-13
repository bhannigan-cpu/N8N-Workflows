#!/usr/bin/env python3
"""Transform SKU performance CSV into a supplier performance report.

Priority and issue rules are derived from few-shot analysis of the
supplier 12684 reference report (supplier_12684_performance_report PDF).
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any


ISSUE_LABELS = {
    "availability": "Availability",
    "conversion": "Conversion Rate",
    "visits_yoy": "Customer Visits (YoY)",
    "revenue_yoy": "Revenue (YoY)",
    "revenue": "Revenue",
    "incidence": "Incidence Rate",
    "customer_exposure": "Customer Issue Exposure",
    "image": "Image Coverage",
    "tag_coverage": "Required Tag Coverage",
}


def parse_money(value: str | None) -> float:
    if not value or value.strip() in {"", "—"}:
        return 0.0
    cleaned = value.replace("$", "").replace(",", "").strip()
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def parse_pct(value: str | None) -> float | None:
    if not value or value.strip() in {"", "—"}:
        return None
    cleaned = value.replace("%", "").replace("+", "").strip()
    try:
        return float(cleaned)
    except ValueError:
        return None


def format_money(value: float) -> str:
    if value < 0:
        return f"-${abs(value):,.2f}"
    return f"${value:,.2f}"


def format_pct(value: float | None, signed: bool = False) -> str:
    if value is None:
        return "—"
    prefix = "+" if signed and value > 0 else ""
    return f"{prefix}{value:.1f}%"


def format_rate(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.2f}%"


def format_visits(value: int | float | None) -> str:
    if value is None:
        return "—"
    return f"{int(value):,}"


def format_money_compact(value: float) -> str:
    if value < 0:
        return f"-${abs(value):,.0f}"
    return f"${value:,.0f}"


def parse_float(value: str | None) -> float | None:
    if not value or value.strip() in {"", "—"}:
        return None
    try:
        return float(value.strip())
    except ValueError:
        return None


def display_priority(priority: str) -> str:
    return "LOW" if priority == "MONITOR" else priority


def recommended_focus(sku: SkuRow) -> str:
    actions: list[str] = []
    if sku.visits_yoy_pct is not None and sku.visits_yoy_pct < -20:
        actions.append("Restore traffic")
    if sku.conversion_below_target:
        actions.append("Improve conversion")
    if sku.availability_below_target:
        actions.append("Fix availability")
    if sku.incidence_above_target:
        actions.append("Address incidence")
    if sku.wholesale_revenue <= 0 and sku.py_wholesale_revenue > 0:
        actions.append("Restore sales")
    elif sku.revenue_yoy_pct is not None and sku.revenue_yoy_pct < -20:
        actions.append("Recover revenue")
    return "; ".join(actions) if actions else "Monitor"


def incidence_label(sku: SkuRow) -> tuple[str, str]:
    if sku.incidence_rate_pct is None:
        return "No data", "neutral"
    if sku.incidence_above_target:
        return "High", "bad"
    return "On target", "good"


def metric_class(metric: str, value: float | None) -> str:
    if value is None:
        return "neutral"
    if metric == "revenue_yoy":
        if value >= 0:
            return "good"
        if value >= -20:
            return "warn"
        return "bad"
    if metric == "visits_yoy":
        if value >= 0:
            return "good"
        if value >= -20:
            return "warn"
        return "bad"
    if metric == "conversion":
        if value >= 0.8:
            return "good"
        return "bad"
    if metric == "wsi":
        if value < 0:
            return "good"
        if value == 0:
            return "neutral"
        return "bad"
    return "neutral"


def format_wsi(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.2f}"


@dataclass
class SkuRow:
    supplier_id: str
    sku: str
    wholesale_revenue: float
    pct_of_sales: float | None
    py_wholesale_revenue: float
    revenue_yoy_pct: float | None
    revenue_pop_pct: float | None
    availability_pct: float | None
    availability_below_target: bool
    conversion_pct: float | None
    conversion_below_target: bool
    visit_count: int
    visits_yoy_pct: float | None
    visits_pop_pct: float | None
    visits_yoy_trend: str
    req_tag_below_target: bool
    image_below_target: bool
    incidence_above_target: bool
    gie_above_target: bool
    wsi: float | None = None
    py_wsi: float | None = None
    wsi_yoy_change: float | None = None
    wsi_yoy_trend: str = ""
    incidence_rate_pct: float | None = None
    priority: str = "MONITOR"
    issues: list[str] = field(default_factory=list)

    @classmethod
    def from_csv(cls, row: dict[str, str]) -> "SkuRow":
        return cls(
            supplier_id=row["SuID"],
            sku=row["PrSKU"],
            wholesale_revenue=parse_money(row.get("Wholesale_Revenue")),
            pct_of_sales=parse_pct(row.get("Pct_of_Sales")),
            py_wholesale_revenue=parse_money(row.get("PY_Wholesale_Revenue")),
            revenue_yoy_pct=parse_pct(row.get("Wholesale_Revenue_YoY_Pct")),
            revenue_pop_pct=parse_pct(row.get("Wholesale_Revenue_PoP_Pct")),
            availability_pct=parse_pct(row.get("Availability_Pct")),
            availability_below_target=row.get("Availability_vs_Target_80") == "Below Target",
            conversion_pct=parse_pct(row.get("SKU_Conversion_Rate_Pct")),
            conversion_below_target=row.get("Conversion_vs_Target_0_8") == "Below Target",
            visit_count=int(float(row.get("SKU_Visit_Count") or 0)),
            visits_yoy_pct=parse_pct(row.get("SKU_Visits_YoY_Pct")),
            visits_pop_pct=parse_pct(row.get("SKU_Visits_PoP_Pct")),
            visits_yoy_trend=(row.get("SKU_Visits_YoY_Trend") or "").strip(),
            req_tag_below_target=row.get("Req_Tag_vs_Target_90") == "Below Target",
            image_below_target=row.get("Image_Coverage_vs_Target_100") == "Below Target",
            incidence_above_target=row.get("Incidence_Rate_vs_Target_5") == "At/Over Target",
            gie_above_target=row.get("GIE_vs_Target_5") == "At/Over Target",
            wsi=parse_float(row.get("Item_Level_WSI")),
            py_wsi=parse_float(row.get("PY_Item_Level_WSI")),
            wsi_yoy_change=parse_float(row.get("WSI_YoY_Change")),
            wsi_yoy_trend=(row.get("WSI_YoY_Trend") or "").strip(),
            incidence_rate_pct=parse_pct(row.get("Incidence_Rate_Pct")),
        )


def detect_issues(sku: SkuRow) -> list[str]:
    """Issue labels mirror the supplier 12684 reference report."""
    issues: list[str] = []

    if sku.wholesale_revenue <= 0 and sku.py_wholesale_revenue > 0:
        issues.append(ISSUE_LABELS["revenue"])
    elif sku.wholesale_revenue <= 0:
        issues.append(ISSUE_LABELS["revenue"])

    if sku.availability_below_target:
        issues.append(ISSUE_LABELS["availability"])
    if sku.conversion_below_target:
        issues.append(ISSUE_LABELS["conversion"])
    if sku.visits_yoy_pct is not None and sku.visits_yoy_pct < -20:
        issues.append(ISSUE_LABELS["visits_yoy"])
    if sku.revenue_yoy_pct is not None and sku.revenue_yoy_pct < -20:
        issues.append(ISSUE_LABELS["revenue_yoy"])
    if sku.incidence_above_target:
        issues.append(ISSUE_LABELS["incidence"])
    if sku.gie_above_target:
        issues.append(ISSUE_LABELS["customer_exposure"])
    if sku.image_below_target:
        issues.append(ISSUE_LABELS["image"])
    if sku.req_tag_below_target:
        issues.append(ISSUE_LABELS["tag_coverage"])

    return issues


def scorecard_issues(sku: SkuRow) -> list[str]:
    return [issue for issue in detect_issues(sku) if issue != ISSUE_LABELS["tag_coverage"]]


def assign_priority(sku: SkuRow, issues: list[str]) -> str:
    """Priority tiers inferred from supplier 12684 few-shot examples."""
    rev_yoy = sku.revenue_yoy_pct
    visits_yoy = sku.visits_yoy_pct
    issue_count = len(issues)

    if sku.wholesale_revenue <= 0:
        return "CRITICAL"

    if rev_yoy is not None and rev_yoy <= -70:
        return "CRITICAL"
    if rev_yoy is not None and rev_yoy <= -50 and issue_count >= 2:
        return "CRITICAL"
    if sku.availability_below_target and rev_yoy is not None and rev_yoy <= -40:
        return "CRITICAL"
    if visits_yoy is not None and visits_yoy <= -60 and rev_yoy is not None and rev_yoy < 0:
        return "CRITICAL"

    if rev_yoy is not None and rev_yoy <= -30:
        return "HIGH"
    if visits_yoy is not None and visits_yoy <= -40:
        return "HIGH"
    if sku.availability_below_target and rev_yoy is not None and rev_yoy < -10:
        return "HIGH"
    if issue_count >= 3 and rev_yoy is not None and rev_yoy < 0:
        return "HIGH"

    if issue_count >= 1:
        return "MEDIUM"
    if rev_yoy is not None and rev_yoy < -15:
        return "MEDIUM"
    if rev_yoy is not None and rev_yoy < 0:
        return "MEDIUM"

    return "MONITOR"


def priority_rank(priority: str) -> int:
    return {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "MONITOR": 3}.get(priority, 4)


def issue_sort_key(issue: str) -> int:
    order = list(ISSUE_LABELS.values())
    try:
        return order.index(issue)
    except ValueError:
        return len(order)


def format_issues(issues: list[str], max_visible: int = 4) -> str:
    if not issues:
        return "No major issues flagged"
    visible = sorted(issues, key=issue_sort_key)[:max_visible]
    hidden = max(0, len(issues) - len(visible))
    text = " ".join(visible)
    if hidden:
        text += f" +{hidden} more"
    return text


def load_skus(csv_path: Path) -> list[SkuRow]:
    with csv_path.open(newline="", encoding="utf-8-sig") as handle:
        rows = [SkuRow.from_csv(row) for row in csv.DictReader(handle)]

    for sku in rows:
        sku.issues = detect_issues(sku)
        sku.priority = assign_priority(sku, scorecard_issues(sku))

    rows.sort(key=lambda item: (-item.wholesale_revenue, item.sku))
    return rows


def build_summary(skus: list[SkuRow]) -> dict[str, Any]:
    total_revenue = sum(sku.wholesale_revenue for sku in skus)
    priority_counts = Counter(sku.priority for sku in skus)
    issue_counts = Counter(issue for sku in skus for issue in sku.issues)

    revenue_decliners = [
        sku
        for sku in skus
        if sku.revenue_yoy_pct is not None and sku.revenue_yoy_pct < -20
    ]
    zero_revenue = [
        sku
        for sku in skus
        if sku.wholesale_revenue <= 0 and sku.py_wholesale_revenue > 0
    ]
    below_availability = [sku for sku in skus if sku.availability_below_target]
    declining_visits = [
        sku for sku in skus if sku.visits_yoy_pct is not None and sku.visits_yoy_pct < -20
    ]
    below_conversion = [sku for sku in skus if sku.conversion_below_target]

    revenue_at_risk = sum(sku.wholesale_revenue for sku in revenue_decliners)

    return {
        "total_revenue": total_revenue,
        "priority_counts": priority_counts,
        "issue_counts": issue_counts,
        "revenue_decliners": revenue_decliners,
        "zero_revenue": zero_revenue,
        "below_availability": below_availability,
        "declining_visits": declining_visits,
        "below_conversion": below_conversion,
        "revenue_at_risk": revenue_at_risk,
    }


def render_report(
    skus: list[SkuRow],
    *,
    supplier_id: str,
    current_period: str,
    prior_period: str,
    prior_year_period: str,
    report_date: str,
) -> str:
    summary = build_summary(skus)
    supplier_id = supplier_id or (skus[0].supplier_id if skus else "Unknown")

    top_decliners = sorted(
        [sku for sku in skus if sku.revenue_yoy_pct is not None and sku.revenue_yoy_pct < 0],
        key=lambda item: item.revenue_yoy_pct or 0,
    )

    action_list = sorted(
        skus,
        key=lambda item: (
            priority_rank(item.priority),
            -(len(item.issues)),
            item.revenue_yoy_pct if item.revenue_yoy_pct is not None else 0,
            -item.wholesale_revenue,
        ),
    )[:25]

    alert_parts = []
    def count_label(count: int, singular: str, plural: str | None = None) -> str:
        word = singular if count == 1 else (plural or f"{singular}s")
        return f"{count} {word}"

    if summary["revenue_decliners"]:
        alert_parts.append(
            f"{count_label(len(summary['revenue_decliners']), 'SKU')} are showing significant year-over-year revenue declines (>20%), "
            f"representing {format_money(summary['revenue_at_risk'])} in current revenue at risk."
        )
    if summary["zero_revenue"]:
        alert_parts.append(
            f"{count_label(len(summary['zero_revenue']), 'SKU')} have stopped generating revenue compared to last year."
        )
    if summary["below_availability"]:
        alert_parts.append(
            f"{count_label(len(summary['below_availability']), 'SKU')} are below the 80% availability target."
        )
    if summary["declining_visits"]:
        alert_parts.append(
            f"{count_label(len(summary['declining_visits']), 'SKU')} have seen visits decline more than 20% year-over-year."
        )
    alert_text = " ".join(alert_parts) if alert_parts else "No critical performance alerts this period."

    issue_ranking = summary["issue_counts"].most_common()

    recommended_actions = []
    if summary["below_availability"]:
        recommended_actions.append(
            f"Address Availability Gaps — {len(summary['below_availability'])} SKUs are below 80% availability. "
            "Review inventory levels and fulfillment to prevent lost sales on in-demand products."
        )
    if summary["revenue_decliners"]:
        recommended_actions.append(
            "Recover Top Revenue Decliners — Focus on your highest-revenue SKUs with YoY declines. "
            "Investigate traffic drops, competitive pricing, and content quality for these products first."
        )
    if summary["zero_revenue"]:
        recommended_actions.append(
            f"Reactivate Zero-Revenue SKUs — {len(summary['zero_revenue'])} SKUs generated revenue last year but not this period. "
            "Check if products are discontinued, out of stock, or have catalog/content issues."
        )
    if summary["declining_visits"]:
        recommended_actions.append(
            f"Reverse Visit Declines — {len(summary['declining_visits'])} SKUs have lost more than 20% of visits year-over-year. "
            "Review pricing competitiveness, imagery, and product visibility for these items."
        )
    if any(sku.incidence_above_target or sku.gie_above_target for sku in skus):
        recommended_actions.append(
            "Reduce Customer Issue Rates — SKUs with elevated incidence rates and customer exposure should be reviewed "
            "for product quality, accuracy of listing details, and imagery."
        )

    def table_rows(items: list[SkuRow], columns: str) -> str:
        rows_html = []
        for sku in items:
            if columns == "decliners":
                rows_html.append(
                    f"""
                    <tr>
                      <td>{sku.sku}</td>
                      <td>{format_money(sku.wholesale_revenue)}</td>
                      <td>{format_money(sku.py_wholesale_revenue) if sku.py_wholesale_revenue else "—"}</td>
                      <td>{format_pct(sku.revenue_yoy_pct)}</td>
                      <td>{format_issues(sku.issues)}</td>
                    </tr>
                    """
                )
            elif columns == "priority":
                rows_html.append(
                    f"""
                    <tr>
                      <td><span class="badge {sku.priority.lower()}">{sku.priority}</span></td>
                      <td>{sku.sku}</td>
                      <td>{format_money(sku.wholesale_revenue)}</td>
                      <td>{format_pct(sku.revenue_yoy_pct)}</td>
                      <td>{format_rate(sku.availability_pct)}</td>
                      <td>{format_rate(sku.conversion_pct)}</td>
                      <td>{format_issues(sku.issues)}</td>
                    </tr>
                    """
                )
            else:
                rows_html.append(
                    f"""
                    <tr>
                      <td><span class="badge {sku.priority.lower()}">{sku.priority}</span></td>
                      <td>{sku.sku}</td>
                      <td>{format_money(sku.wholesale_revenue)}</td>
                      <td>{format_pct(sku.pct_of_sales)}</td>
                      <td>{format_pct(sku.revenue_yoy_pct, signed=True)}</td>
                      <td>{format_pct(sku.revenue_pop_pct, signed=True)}</td>
                      <td>{format_rate(sku.availability_pct)}</td>
                      <td>{format_rate(sku.conversion_pct)}</td>
                      <td>{format_visits(sku.visit_count)}</td>
                      <td>{format_pct(sku.visits_yoy_pct, signed=True)}</td>
                    </tr>
                    """
                )
        return "\n".join(rows_html)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>SKU Performance Review — Supplier {supplier_id}</title>
  <style>
    :root {{
      --navy: #1f4e79;
      --light-blue: #eaf2f8;
      --alert: #fff4e5;
      --critical: #c0392b;
      --high: #d35400;
      --medium: #b7950b;
      --monitor: #1e8449;
    }}
    body {{
      font-family: Arial, Helvetica, sans-serif;
      color: #222;
      line-height: 1.45;
      margin: 0;
      background: #f5f7fa;
    }}
    .page {{
      max-width: 1100px;
      margin: 0 auto;
      background: white;
      box-shadow: 0 0 24px rgba(0,0,0,0.08);
    }}
    .hero, section {{
      padding: 28px 36px;
      border-bottom: 1px solid #e5e7eb;
    }}
    h1, h2, h3 {{
      color: var(--navy);
      margin-top: 0;
    }}
    .meta {{
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 12px;
      margin-top: 18px;
    }}
    .meta div {{
      background: var(--light-blue);
      padding: 12px 14px;
      border-radius: 8px;
      font-size: 14px;
    }}
    .alert {{
      background: var(--alert);
      border-left: 4px solid #f39c12;
      padding: 16px 18px;
      margin-top: 18px;
      border-radius: 6px;
    }}
    .stat-grid {{
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 12px;
      margin-top: 18px;
    }}
    .stat {{
      background: #f8fafc;
      border: 1px solid #dbe4ee;
      border-radius: 10px;
      padding: 16px;
      text-align: center;
    }}
    .stat .value {{
      font-size: 28px;
      font-weight: 700;
      color: var(--navy);
    }}
    .stat .label {{
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: #555;
      margin-top: 6px;
    }}
    .priority-grid {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
    }}
    .priority-card {{
      border-radius: 10px;
      padding: 18px;
      color: white;
      text-align: center;
    }}
    .priority-card.critical {{ background: var(--critical); }}
    .priority-card.high {{ background: var(--high); }}
    .priority-card.medium {{ background: var(--medium); }}
    .priority-card.monitor {{ background: var(--monitor); }}
    .priority-card .value {{ font-size: 32px; font-weight: 700; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      margin-top: 12px;
    }}
    th, td {{
      border: 1px solid #d9e2ec;
      padding: 8px 10px;
      text-align: left;
      vertical-align: top;
    }}
    th {{
      background: var(--light-blue);
      color: #111;
    }}
    tr:nth-child(even) td {{ background: #fafbfc; }}
    .badge {{
      display: inline-block;
      padding: 3px 8px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      color: white;
    }}
    .badge.critical {{ background: var(--critical); }}
    .badge.high {{ background: var(--high); }}
    .badge.medium {{ background: var(--medium); }}
    .badge.monitor {{ background: var(--monitor); }}
    ol li {{ margin-bottom: 10px; }}
    .footer {{
      font-size: 12px;
      color: #666;
      padding: 20px 36px 32px;
    }}
    .issue-list li {{
      display: flex;
      justify-content: space-between;
      padding: 8px 0;
      border-bottom: 1px solid #edf2f7;
    }}
  </style>
</head>
<body>
  <div class="page">
    <section class="hero">
      <h1>SKU Performance Review — Supplier {supplier_id}</h1>
      <div class="meta">
        <div><strong>Current Period</strong><br>{current_period}</div>
        <div><strong>Month-over-Month Comparison</strong><br>{current_period} vs {prior_period}</div>
        <div><strong>Year-over-Year Comparison</strong><br>{current_period} vs {prior_year_period}</div>
      </div>
      <div class="alert"><strong>⚠ Performance Alert: Action Required</strong><br>{alert_text}</div>
      <div class="stat-grid">
        <div class="stat"><div class="value">{summary['priority_counts'].get('CRITICAL', 0)}</div><div class="label">Critical Priority SKUs</div></div>
        <div class="stat"><div class="value">{summary['priority_counts'].get('HIGH', 0)}</div><div class="label">High Priority SKUs</div></div>
        <div class="stat"><div class="value">{len(summary['below_availability'])}</div><div class="label">Below Availability Target</div></div>
        <div class="stat"><div class="value">{len(summary['declining_visits'])}</div><div class="label">Declining Visits (YoY)</div></div>
        <div class="stat"><div class="value">{len(summary['below_conversion'])}</div><div class="label">Below Conversion Target</div></div>
      </div>
      <p style="margin-top:18px;"><strong>Report Date:</strong> {report_date} &nbsp;|&nbsp;
      <strong>Total SKUs Analyzed:</strong> {len(skus)} &nbsp;|&nbsp;
      <strong>Total Wholesale Revenue:</strong> {format_money(summary['total_revenue'])}</p>
    </section>

    <section>
      <h2>Priority Breakdown</h2>
      <p>SKUs categorized by severity of performance issues</p>
      <div class="priority-grid">
        <div class="priority-card critical"><div class="value">{summary['priority_counts'].get('CRITICAL', 0)}</div>Critical</div>
        <div class="priority-card high"><div class="value">{summary['priority_counts'].get('HIGH', 0)}</div>High</div>
        <div class="priority-card medium"><div class="value">{summary['priority_counts'].get('MEDIUM', 0)}</div>Medium</div>
        <div class="priority-card monitor"><div class="value">{summary['priority_counts'].get('MONITOR', 0)}</div>Monitor</div>
      </div>
    </section>

    <section>
      <h2>Top Issues Across Your Catalog</h2>
      <p>Most common performance gaps driving underperformance</p>
      <ul class="issue-list">
        {''.join(f'<li><span>{issue}</span><strong>{count} SKUs</strong></li>' for issue, count in issue_ranking) or '<li>No major issues flagged across the catalog.</li>'}
      </ul>
    </section>

    <section>
      <h2>Recommended Actions</h2>
      <p>Priority improvements to recover revenue and catalog health</p>
      <ol>
        {''.join(f'<li>{action}</li>' for action in recommended_actions) or '<li>Continue monitoring current performance trends.</li>'}
      </ol>
    </section>

    <section>
      <h2>Top Revenue Decliners</h2>
      <p>Highest-revenue SKUs with significant year-over-year declines — address these first</p>
      <table>
        <thead>
          <tr>
            <th>SKU</th><th>Current Revenue</th><th>Prior Year Revenue</th><th>YoY Change</th><th>Key Issues</th>
          </tr>
        </thead>
        <tbody>
          {table_rows(top_decliners, 'decliners') if top_decliners else '<tr><td colspan="5">No year-over-year revenue decliners this period.</td></tr>'}
        </tbody>
      </table>
    </section>

    <section>
      <h2>Action Priority List</h2>
      <p>Top {min(25, len(skus))} SKUs requiring immediate attention, ranked by issue severity</p>
      <table>
        <thead>
          <tr>
            <th>Priority</th><th>SKU</th><th>Revenue</th><th>YoY</th><th>Avail.</th><th>Conv.</th><th>Issues</th>
          </tr>
        </thead>
        <tbody>{table_rows(action_list, 'priority')}</tbody>
      </table>
    </section>

    <section>
      <h2>Complete SKU Breakdown</h2>
      <p>Full catalog performance for {current_period} — all {len(skus)} SKUs sorted by revenue</p>
      <table>
        <thead>
          <tr>
            <th>Priority</th><th>SKU</th><th>Revenue</th><th>% Sales</th><th>Rev YoY</th><th>Rev MoM</th>
            <th>Avail.</th><th>Conv.</th><th>Visits</th><th>Visits YoY</th>
          </tr>
        </thead>
        <tbody>{table_rows(skus, 'full')}</tbody>
      </table>
    </section>

    <section>
      <h2>Performance Targets Reference</h2>
      <p>Benchmarks used to evaluate SKU health</p>
      <table>
        <thead><tr><th>Metric</th><th>Target</th><th>Why It Matters</th></tr></thead>
        <tbody>
          <tr><td>Availability</td><td>≥ 80%</td><td>Ensures customers can purchase when they visit your product page</td></tr>
          <tr><td>Conversion Rate</td><td>≥ 0.8%</td><td>Measures how effectively visits turn into orders</td></tr>
          <tr><td>Image Coverage</td><td>100%</td><td>Quality imagery is essential for conversion in home goods</td></tr>
          <tr><td>Incidence Rate</td><td>≤ 5%</td><td>Lower return/complaint rates protect your brand and ranking</td></tr>
        </tbody>
      </table>
    </section>

    <div class="footer">
      Confidential — Supplier Performance Review | Generated {report_date}<br>
      Questions? Contact your Wayfair Category Manager.
    </div>
  </div>
</body>
</html>
"""


def build_scorecard_summary(skus: list[SkuRow]) -> dict[str, Any]:
    total = len(skus)
    below_conversion = [sku for sku in skus if sku.conversion_below_target]
    established = [sku for sku in skus if sku.py_wholesale_revenue > 0]
    traffic_sales_pressure = [
        sku
        for sku in established
        if sku.revenue_yoy_pct is not None
        and sku.revenue_yoy_pct < 0
        and sku.visits_yoy_pct is not None
        and sku.visits_yoy_pct < 0
    ]
    wsi_with_data = [sku for sku in skus if sku.wsi is not None]
    wsi_favorable = [sku for sku in wsi_with_data if sku.wsi is not None and sku.wsi < 0]
    wsi_improved = [
        sku
        for sku in wsi_with_data
        if sku.wsi_yoy_trend == "Improved"
        or (sku.wsi_yoy_change is not None and sku.wsi_yoy_change < 0)
    ]
    at_avail_target = [sku for sku in skus if not sku.availability_below_target]
    at_image_target = [sku for sku in skus if not sku.image_below_target]

    working_parts: list[str] = []
    if at_avail_target:
        working_parts.append("AVAILABILITY")
    if at_image_target:
        working_parts.append("IMAGES")
    working_label = " + ".join(working_parts) if working_parts else "CORE METRICS"
    working_detail = f"{len(at_avail_target)}/{total} SKUs at target availability"
    if at_image_target:
        working_detail += f"; {len(at_image_target)}/{total} at 100% image coverage"

    wsi_detail = "Have favorable negative WSI"
    if wsi_with_data and wsi_improved:
        wsi_detail += f"; {len(wsi_improved)}/{len(wsi_with_data)} improved YoY"

    return {
        "conversion_count": len(below_conversion),
        "conversion_total": total,
        "traffic_sales_count": len(traffic_sales_pressure),
        "traffic_sales_total": len(established),
        "wsi_favorable_count": len(wsi_favorable),
        "wsi_total": len(wsi_with_data),
        "wsi_detail": wsi_detail,
        "working_label": working_label,
        "working_detail": working_detail,
    }


def render_scorecard(
    skus: list[SkuRow],
    *,
    supplier_id: str,
    supplier_name: str,
    current_period: str,
    top_n: int = 10,
) -> str:
    supplier_id = supplier_id or (skus[0].supplier_id if skus else "Unknown")
    supplier_name = supplier_name or f"SUPPLIER {supplier_id}"
    period_label = current_period.split()[0].upper() if current_period else "CURRENT"
    visible_skus = skus[:top_n]
    summary = build_scorecard_summary(visible_skus)

    matrix_rows = []
    for sku in visible_skus:
        priority = display_priority(sku.priority).lower()
        incidence_text, incidence_tone = incidence_label(sku)
        rev_yoy = sku.revenue_yoy_pct
        visits_yoy = sku.visits_yoy_pct
        conversion = sku.conversion_pct
        wsi = sku.wsi

        matrix_rows.append(
            f"""
            <tr>
              <td class="sku">{sku.sku}</td>
              <td class="num">{format_money_compact(sku.wholesale_revenue)}</td>
              <td class="num {metric_class('revenue_yoy', rev_yoy)}">{format_pct(rev_yoy, signed=True) if rev_yoy is not None else "—"}</td>
              <td class="num {metric_class('visits_yoy', visits_yoy)}">{format_pct(visits_yoy, signed=True) if visits_yoy is not None else "—"}</td>
              <td class="num {metric_class('conversion', conversion)}">{format_rate(conversion)}</td>
              <td class="num {metric_class('wsi', wsi)}">{format_wsi(wsi)}</td>
              <td class="num {incidence_tone}">{incidence_text}</td>
              <td class="priority {priority}">{display_priority(sku.priority)}</td>
              <td class="focus">{recommended_focus(sku)}</td>
            </tr>
            """
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>{supplier_name} | {period_label} TOP {top_n} SKU SCORECARD</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      padding: 24px;
      background: #eceff3;
      font-family: Arial, Helvetica, sans-serif;
      color: #1f2937;
    }}
    .scorecard {{
      width: 1380px;
      margin: 0 auto;
      background: #f4f6f8;
      border: 1px solid #cfd8e3;
      box-shadow: 0 8px 24px rgba(0,0,0,0.08);
    }}
    .header-bar {{
      background: #173a63;
      color: #fff;
      text-align: center;
      font-size: 28px;
      font-weight: 700;
      letter-spacing: 0.04em;
      padding: 18px 24px;
      text-transform: uppercase;
    }}
    .subtitle-bar {{
      background: #5d9fd6;
      color: #fff;
      text-align: center;
      font-size: 18px;
      font-style: italic;
      padding: 12px 24px;
    }}
    .summary-row {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 0;
      background: #eef2f6;
      border-bottom: 1px solid #d7dee8;
    }}
    .summary-box {{
      padding: 18px 20px 20px;
      border-right: 1px solid #d7dee8;
      min-height: 132px;
    }}
    .summary-box:last-child {{ border-right: none; }}
    .summary-box .label {{
      font-size: 15px;
      font-weight: 700;
      margin-bottom: 10px;
    }}
    .summary-box .value {{
      font-size: 34px;
      font-weight: 800;
      line-height: 1.05;
      margin-bottom: 8px;
    }}
    .summary-box .detail {{
      font-size: 14px;
      color: #4b5563;
      line-height: 1.35;
    }}
    .summary-box.warn .label,
    .summary-box.warn .value {{ color: #d35400; }}
    .summary-box.alert .label,
    .summary-box.alert .value {{ color: #c0392b; }}
    .summary-box.good .label,
    .summary-box.good .value {{ color: #1e7e34; }}
    .matrix-title {{
      padding: 18px 24px 10px;
      font-size: 24px;
      font-weight: 800;
      color: #173a63;
      letter-spacing: 0.02em;
    }}
    table {{
      width: calc(100% - 48px);
      margin: 0 24px 24px;
      border-collapse: collapse;
      background: #fff;
      font-size: 15px;
    }}
    th {{
      background: #173a63;
      color: #fff;
      font-weight: 700;
      text-align: center;
      padding: 12px 10px;
      border: 1px solid #173a63;
      font-size: 14px;
      line-height: 1.2;
    }}
    td {{
      border: 1px solid #d7dee8;
      padding: 11px 10px;
      vertical-align: middle;
      text-align: center;
      background: #fff;
    }}
    td.sku {{
      text-align: left;
      font-weight: 800;
      color: #173a63;
      white-space: nowrap;
    }}
    td.focus {{
      text-align: left;
      font-size: 14px;
      color: #374151;
    }}
    td.good {{
      background: #d9f2df;
      color: #166534;
      font-weight: 700;
    }}
    td.warn {{
      background: #fff1d6;
      color: #b45309;
      font-weight: 700;
    }}
    td.bad {{
      background: #fde2e1;
      color: #b42318;
      font-weight: 700;
    }}
    td.neutral {{
      background: #f3f4f6;
      color: #6b7280;
      font-weight: 600;
    }}
    td.priority {{
      color: #fff;
      font-weight: 800;
      letter-spacing: 0.03em;
      text-transform: uppercase;
      font-size: 14px;
    }}
    td.priority.low {{ background: #1e7e34; }}
    td.priority.medium {{ background: #c9a000; }}
    td.priority.high {{ background: #e67e22; }}
    td.priority.critical {{ background: #c0392b; }}
    .footer-bar {{
      background: #173a63;
      color: #fff;
      text-align: center;
      font-size: 13px;
      line-height: 1.45;
      padding: 14px 24px;
    }}
  </style>
</head>
<body>
  <div class="scorecard">
    <div class="header-bar">{supplier_name} | {period_label} TOP {top_n} SKU SCORECARD</div>
    <div class="subtitle-bar">Where performance is breaking down—and the specific levers to prioritize by SKU</div>

    <div class="summary-row">
      <div class="summary-box warn">
        <div class="label">Conversion Opportunity</div>
        <div class="value">{summary['conversion_count']} OF {summary['conversion_total']} SKUs</div>
        <div class="detail">Below the 0.8% conversion target</div>
      </div>
      <div class="summary-box alert">
        <div class="label">Traffic + Sales Pressure</div>
        <div class="value">{summary['traffic_sales_count']} OF {summary['traffic_sales_total']}</div>
        <div class="detail">Established SKUs down in both revenue and visits YoY</div>
      </div>
      <div class="summary-box good">
        <div class="label">WSI Is Generally Healthy</div>
        <div class="value">{summary['wsi_favorable_count']} OF {summary['wsi_total']} SKUs</div>
        <div class="detail">{summary['wsi_detail']}</div>
      </div>
      <div class="summary-box good">
        <div class="label">What Is Working</div>
        <div class="value">{summary['working_label']}</div>
        <div class="detail">{summary['working_detail']}</div>
      </div>
    </div>

    <div class="matrix-title">SKU-BY-SKU PRIORITY MATRIX</div>
    <table>
      <thead>
        <tr>
          <th>SKU</th>
          <th>Revenue<br>({current_period})</th>
          <th>Revenue<br>YoY</th>
          <th>Visits<br>YoY</th>
          <th>Conversion</th>
          <th>WSI<br>(negative = good)</th>
          <th>Incidence<br>Risk</th>
          <th>Priority</th>
          <th>Recommended<br>Focus</th>
        </tr>
      </thead>
      <tbody>
        {''.join(matrix_rows)}
      </tbody>
    </table>

    <div class="footer-bar">
      Priority reflects severity across revenue trend, traffic trend, conversion vs. 0.8% target, incidence, and zero-sales risk.
      WSI is shown separately; negative values are favorable.
    </div>
  </div>
</body>
</html>
"""


FEW_SHOT_PROMPT = """You are generating a Supplier SKU Performance Review report.

Use the reference report below as the formatting and classification few-shot example.
Apply the same section structure, issue labels, priority tiers, and narrative style to new CSV data.

## Reference report (Supplier 12684 — few-shot example)

Structure:
1. Title: SKU Performance Review — Supplier {supplier_id}
2. Period metadata: current period, MoM comparison, YoY comparison
3. Performance alert paragraph with counts for:
   - YoY revenue declines >20% (with revenue at risk)
   - zero-revenue SKUs vs prior year
   - SKUs below 80% availability
   - SKUs with visits down >20% YoY
4. Summary stat cards: Critical, High, Below Availability, Declining Visits, Below Conversion
5. Priority breakdown: CRITICAL / HIGH / MEDIUM / MONITOR counts
6. Top issues across catalog (issue label + SKU count)
7. Recommended actions (numbered list, only include relevant actions)
8. Top revenue decliners table
9. Action priority list (top 25 by severity)
10. Complete SKU breakdown sorted by revenue
11. Performance targets reference

Priority rules (from reference):
- CRITICAL: zero current revenue, YoY revenue <= -70%, or severe multi-issue decline
- HIGH: YoY revenue <= -30%, visits YoY <= -40%, or availability miss with meaningful decline
- MEDIUM: any flagged issue or modest negative trend
- MONITOR: stable/growing performance without major issue flags

Issue labels (use exactly):
- Availability
- Conversion Rate
- Customer Visits (YoY)
- Revenue (YoY)
- Revenue
- Incidence Rate
- Customer Issue Exposure
- Image Coverage
- Required Tag Coverage

Issue detection from CSV columns:
- Availability_vs_Target_80 == "Below Target" -> Availability
- Conversion_vs_Target_0_8 == "Below Target" -> Conversion Rate
- SKU_Visits_YoY_Pct < -20 -> Customer Visits (YoY)
- Wholesale_Revenue_YoY_Pct < -20 -> Revenue (YoY)
- Wholesale_Revenue == 0 and PY_Wholesale_Revenue > 0 -> Revenue
- Incidence_Rate_vs_Target_5 == "At/Over Target" -> Incidence Rate
- GIE_vs_Target_5 == "At/Over Target" -> Customer Issue Exposure
- Image_Coverage_vs_Target_100 == "Below Target" -> Image Coverage
- Req_Tag_vs_Target_90 == "Below Target" -> Required Tag Coverage

## New data to transform

{csv_data}

Generate the full report for supplier {supplier_id} in the same format as the reference.
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate supplier performance report from CSV")
    parser.add_argument(
        "--csv",
        default="/home/ubuntu/.cursor/projects/workspace/uploads/results-20260813-130330_-_results-20260813-130330_31c4.csv",
        help="Input CSV path",
    )
    parser.add_argument("--output", default="/workspace/output/supplier_17662_performance_report.html")
    parser.add_argument("--prompt-output", default="/workspace/output/few_shot_prompt.txt")
    parser.add_argument("--supplier-id", default="")
    parser.add_argument("--current-period", default="July 2026")
    parser.add_argument("--prior-period", default="June 2026")
    parser.add_argument("--prior-year-period", default="July 2025")
    parser.add_argument("--format", choices=["scorecard", "full"], default="scorecard")
    parser.add_argument("--supplier-name", default="")
    parser.add_argument("--top-n", type=int, default=10)
    parser.add_argument("--report-date", default=datetime.now().strftime("%B %-d, %Y"))
    args = parser.parse_args()

    csv_path = Path(args.csv)
    output_path = Path(args.output)
    prompt_path = Path(args.prompt_output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    skus = load_skus(csv_path)
    supplier_id = args.supplier_id or (skus[0].supplier_id if skus else "Unknown")
    supplier_name = args.supplier_name or f"SUPPLIER {supplier_id}"

    if args.format == "scorecard":
        html = render_scorecard(
            skus,
            supplier_id=supplier_id,
            supplier_name=supplier_name,
            current_period=args.current_period,
            top_n=args.top_n,
        )
    else:
        html = render_report(
            skus,
            supplier_id=supplier_id,
            current_period=args.current_period,
            prior_period=args.prior_period,
            prior_year_period=args.prior_year_period,
            report_date=args.report_date,
        )
    output_path.write_text(html, encoding="utf-8")

    prompt = FEW_SHOT_PROMPT.format(
        supplier_id=supplier_id,
        csv_data=csv_path.read_text(encoding="utf-8-sig"),
    )
    prompt_path.write_text(prompt, encoding="utf-8")

    print(f"Wrote report: {output_path}")
    print(f"Wrote few-shot prompt: {prompt_path}")
    print(f"Supplier: {supplier_id} | SKUs: {len(skus)} | Total revenue: {format_money(sum(s.wholesale_revenue for s in skus))}")


if __name__ == "__main__":
    main()
