#!/usr/bin/env python3
"""Generate the Supplier 22255 SKU performance report PDF."""

from __future__ import annotations

import argparse
import csv
from datetime import date
from pathlib import Path
from typing import Iterable

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


SUPPLIER_ID = "22255"
CURRENT_PERIOD = "June 2026"
MOM_PERIOD = "June 2026 vs May 2026"
YOY_PERIOD = "June 2026 vs June 2025"
REPORT_DATE = date(2026, 8, 6).strftime("%B %-d, %Y")

AVAILABILITY_TARGET = 80.0
CONVERSION_TARGET = 0.8
TAG_TARGET = 90.0
IMAGE_TARGET = 100.0
INCIDENCE_TARGET = 5.0
GIE_TARGET = 5.0

BRAND_BLUE = colors.HexColor("#1F4E79")
BRAND_TEAL = colors.HexColor("#0F766E")
BRAND_ORANGE = colors.HexColor("#B45309")
BRAND_RED = colors.HexColor("#B91C1C")
BRAND_GRAY = colors.HexColor("#4B5563")
LIGHT_BLUE = colors.HexColor("#EAF3FB")
LIGHT_TEAL = colors.HexColor("#ECFDF5")
LIGHT_ORANGE = colors.HexColor("#FFF7ED")
LIGHT_RED = colors.HexColor("#FEF2F2")
LIGHT_GRAY = colors.HexColor("#F3F4F6")


def parse_money(value: str) -> float:
    value = (value or "").replace("$", "").replace(",", "").strip()
    return float(value) if value else 0.0


def parse_pct(value: str) -> float | None:
    value = (value or "").replace("%", "").replace(",", "").replace(" bps", "").strip()
    if value in {"", "--", "—"}:
        return None
    return float(value)


def fmt_money(value: float) -> str:
    return f"${value:,.2f}"


def fmt_signed_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:+.1f}%"


def fmt_pct(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.1f}%"


def load_rows(csv_path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with csv_path.open(newline="", encoding="utf-8-sig") as handle:
        for raw in csv.DictReader(handle):
            row: dict[str, object] = dict(raw)
            row["revenue"] = parse_money(raw["Wholesale_Revenue"])
            row["py_revenue"] = parse_money(raw["PY_Wholesale_Revenue"])
            row["revenue_yoy"] = parse_pct(raw["Wholesale_Revenue_YoY_Pct"])
            row["revenue_mom"] = parse_pct(raw["Wholesale_Revenue_MoM_Pct"])
            row["availability"] = parse_pct(raw["Availability_Pct"])
            row["conversion"] = parse_pct(raw["SKU_Conversion_Rate_Pct"])
            row["visits"] = int(raw["SKU_Visit_Count"] or "0")
            row["visits_yoy"] = parse_pct(raw["SKU_Visits_YoY_Pct"])
            row["visits_mom"] = parse_pct(raw["SKU_Visits_MoM_Pct"])
            row["req_tag"] = parse_pct(raw["Req_Tag_Coverage_Pct"])
            row["image"] = parse_pct(raw["Image_Coverage_Pct"])
            row["incidence"] = parse_pct(raw["Incidence_Rate_Pct"])
            row["gie"] = parse_pct(raw["Gross_Incidence_Exposure_Pct_of_WSCNR"])
            row["issues"] = issues_for_row(row)
            row["priority"] = priority_for_row(row)
            rows.append(row)
    return sorted(rows, key=lambda item: item["revenue"], reverse=True)


def issues_for_row(row: dict[str, object]) -> list[str]:
    issues: list[str] = []
    revenue = row["revenue"]
    revenue_yoy = row["revenue_yoy"]
    availability = row["availability"]
    conversion = row["conversion"]
    visits_yoy = row["visits_yoy"]
    req_tag = row["req_tag"]
    image = row["image"]
    incidence = row["incidence"]
    gie = row["gie"]

    if isinstance(revenue, float) and revenue <= 0:
        issues.append("Revenue")
    if isinstance(revenue_yoy, float) and revenue_yoy <= -20:
        issues.append("Revenue (YoY)")
    if isinstance(availability, float) and availability < AVAILABILITY_TARGET:
        issues.append("Availability")
    if isinstance(conversion, float) and conversion < CONVERSION_TARGET:
        issues.append("Conversion Rate")
    if isinstance(visits_yoy, float) and visits_yoy <= -20:
        issues.append("Customer Visits (YoY)")
    if isinstance(req_tag, float) and req_tag < TAG_TARGET:
        issues.append("Required Tags")
    if isinstance(image, float) and image < IMAGE_TARGET:
        issues.append("Image Coverage")
    if isinstance(incidence, float) and incidence > INCIDENCE_TARGET:
        issues.append("Incidence Rate")
    if isinstance(gie, float) and gie > GIE_TARGET:
        issues.append("Customer Issue Exposure")
    return issues or ["No major issues flagged"]


def priority_for_row(row: dict[str, object]) -> str:
    issue_count = len([issue for issue in row["issues"] if issue != "No major issues flagged"])
    revenue_yoy = row["revenue_yoy"]
    availability = row["availability"]
    if issue_count >= 4:
        return "CRITICAL"
    if issue_count == 3 or (
        isinstance(revenue_yoy, float)
        and revenue_yoy <= -50
        and isinstance(availability, float)
        and availability < AVAILABILITY_TARGET
    ):
        return "HIGH"
    if issue_count == 2:
        return "MEDIUM"
    return "MONITOR"


def counter(rows: Iterable[dict[str, object]], field: str, predicate) -> int:
    return sum(1 for row in rows if predicate(row[field]))


def issue_counts(rows: list[dict[str, object]]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        for issue in row["issues"]:
            if issue == "No major issues flagged":
                continue
            counts[issue] = counts.get(issue, 0) + 1
    return dict(sorted(counts.items(), key=lambda item: item[1], reverse=True))


def priority_counts(rows: list[dict[str, object]]) -> dict[str, int]:
    return {priority: sum(1 for row in rows if row["priority"] == priority) for priority in ("CRITICAL", "HIGH", "MEDIUM", "MONITOR")}


def make_styles():
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            "TitleBlue",
            parent=styles["Title"],
            fontName="Helvetica-Bold",
            fontSize=24,
            textColor=BRAND_BLUE,
            alignment=TA_CENTER,
            spaceAfter=12,
        )
    )
    styles.add(
        ParagraphStyle(
            "SectionTitle",
            parent=styles["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=16,
            textColor=BRAND_BLUE,
            spaceBefore=8,
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            "Subtle",
            parent=styles["BodyText"],
            fontSize=9,
            textColor=BRAND_GRAY,
            leading=12,
        )
    )
    styles.add(
        ParagraphStyle(
            "Cell",
            parent=styles["BodyText"],
            fontSize=7.4,
            leading=9,
            alignment=TA_LEFT,
        )
    )
    styles.add(
        ParagraphStyle(
            "CellSmall",
            parent=styles["BodyText"],
            fontSize=6.5,
            leading=8,
            alignment=TA_LEFT,
        )
    )
    styles.add(
        ParagraphStyle(
            "MetricNumber",
            parent=styles["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=22,
            textColor=BRAND_BLUE,
            alignment=TA_CENTER,
        )
    )
    styles.add(
        ParagraphStyle(
            "MetricLabel",
            parent=styles["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=7.5,
            textColor=BRAND_GRAY,
            alignment=TA_CENTER,
            leading=9,
        )
    )
    return styles


def paragraph(text: str, style) -> Paragraph:
    return Paragraph(text.replace("&", "&amp;"), style)


def section(title: str, subtitle: str, styles) -> list:
    return [
        Paragraph(title, styles["SectionTitle"]),
        Paragraph(subtitle, styles["Subtle"]),
        Spacer(1, 0.08 * inch),
    ]


def table_style(header_bg=BRAND_BLUE, grid=colors.white) -> TableStyle:
    return TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, 0), header_bg),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, 0), 7),
            ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
            ("TOPPADDING", (0, 0), (-1, 0), 5),
            ("GRID", (0, 0), (-1, -1), 0.35, grid),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_GRAY]),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ]
    )


def priority_color(priority: str):
    return {
        "CRITICAL": LIGHT_RED,
        "HIGH": LIGHT_ORANGE,
        "MEDIUM": LIGHT_BLUE,
        "MONITOR": LIGHT_TEAL,
    }[priority]


def build_pdf(rows: list[dict[str, object]], output_path: Path) -> None:
    styles = make_styles()
    total_revenue = sum(row["revenue"] for row in rows)
    rev_decliners = [row for row in rows if isinstance(row["revenue_yoy"], float) and row["revenue_yoy"] <= -20]
    below_availability = counter(rows, "availability", lambda value: isinstance(value, float) and value < AVAILABILITY_TARGET)
    declining_visits = counter(rows, "visits_yoy", lambda value: isinstance(value, float) and value <= -20)
    below_conversion = counter(rows, "conversion", lambda value: isinstance(value, float) and value < CONVERSION_TARGET)
    priority_totals = priority_counts(rows)
    issue_totals = issue_counts(rows)

    story: list = []

    story.append(Paragraph(f"SKU Performance Review - Supplier {SUPPLIER_ID}", styles["TitleBlue"]))
    period_table = Table(
        [
            ["CURRENT PERIOD", "MONTH-OVER-MONTH COMPARISON", "YEAR-OVER-YEAR COMPARISON"],
            [CURRENT_PERIOD, MOM_PERIOD, YOY_PERIOD],
        ],
        colWidths=[2.1 * inch, 2.25 * inch, 2.25 * inch],
        hAlign="CENTER",
    )
    period_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BLUE),
                ("TEXTCOLOR", (0, 0), (-1, 0), BRAND_BLUE),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTNAME", (0, 1), (-1, 1), "Helvetica-Bold"),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.white),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.extend([period_table, Spacer(1, 0.22 * inch)])

    alert_text = (
        f"<b>Performance Alert: Action Required</b><br/>"
        f"{len(rev_decliners)} SKUs are showing significant year-over-year revenue declines (&gt;20%), "
        f"representing {fmt_money(sum(row['revenue'] for row in rev_decliners))} in current revenue at risk. "
        f"{below_availability} SKUs are below the 80% availability target, {declining_visits} SKUs have seen visits decline more "
        f"than 20% year-over-year, and {below_conversion} SKUs are below the 0.8% conversion target."
    )
    alert = Table([[Paragraph(alert_text, styles["BodyText"])]], colWidths=[6.7 * inch])
    alert.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), LIGHT_RED),
                ("BOX", (0, 0), (-1, -1), 1, BRAND_RED),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]
        )
    )
    story.extend([alert, Spacer(1, 0.18 * inch)])

    kpis = [
        (str(priority_totals["CRITICAL"]), "CRITICAL PRIORITY SKUS"),
        (str(priority_totals["HIGH"]), "HIGH PRIORITY SKUS"),
        (str(below_availability), "BELOW AVAILABILITY TARGET"),
        (str(declining_visits), "DECLINING VISITS (YOY)"),
        (str(below_conversion), "BELOW CONVERSION TARGET"),
    ]
    metric_cells = [[Paragraph(num, styles["MetricNumber"]), Paragraph(label, styles["MetricLabel"])] for num, label in kpis]
    metrics = Table([metric_cells], colWidths=[1.31 * inch] * 5)
    metrics.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), LIGHT_GRAY),
                ("BOX", (0, 0), (-1, -1), 0.5, colors.white),
                ("GRID", (0, 0), (-1, -1), 2, colors.white),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ]
        )
    )
    story.extend([metrics, Spacer(1, 0.18 * inch)])
    story.append(
        Paragraph(
            f"<b>Underperforming SKU Analysis &amp; Recommended Actions</b><br/>"
            f"Report Date: {REPORT_DATE} &nbsp;&nbsp;&nbsp; Total SKUs Analyzed: {len(rows)} &nbsp;&nbsp;&nbsp; "
            f"Total Wholesale Revenue: {fmt_money(total_revenue)}",
            styles["Subtle"],
        )
    )

    story.append(PageBreak())
    story.extend(section("Key Performance Highlights", "June 2026 SKU-level summary from the supplier scorecard query", styles))
    highlights = [
        [
            Paragraph("<b>Top Revenue Drivers</b>", styles["BodyText"]),
            Paragraph(
                "ARGD1057 led wholesale revenue at $664.88 (0.83% of supplier sales) with 80.63% availability. "
                "FRRB1329 followed at $556.95 (0.70% of sales) with 83.51% availability. ATGD5370 contributed "
                "$555.82 while maintaining 100.00% availability.",
                styles["BodyText"],
            ),
        ],
        [
            Paragraph("<b>Availability &amp; Performance</b>", styles["BodyText"]),
            Paragraph(
                "ARGD1057, FRRB1329, ATGD5370, ATGD5369, ARGD1058, WLAO4493, and VWB11379 were above the 80% target. "
                "FRRB1391, FRRB1378, KBHZ2883, FRRB1330, EHFA1148, and FRRB1313 fell below target.",
                styles["BodyText"],
            ),
        ],
        [
            Paragraph("<b>Catalog Health</b>", styles["BodyText"]),
            Paragraph(
                "Image coverage reached 100.00% across nearly all SKUs, with WLAO4493 at 83.33%. Required tag coverage "
                "remains materially below the 90% benchmark, ranging from 38.30% to 43.14%.",
                styles["BodyText"],
            ),
        ],
    ]
    highlight_table = Table(highlights, colWidths=[1.7 * inch, 4.9 * inch])
    highlight_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), LIGHT_BLUE),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.white),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.extend([highlight_table, Spacer(1, 0.22 * inch)])

    story.extend(section("Priority Breakdown", "SKUs categorized by severity of performance issues", styles))
    priority_table = Table(
        [[priority_totals["CRITICAL"], priority_totals["HIGH"], priority_totals["MEDIUM"], priority_totals["MONITOR"]], ["Critical", "High", "Medium", "Monitor"]],
        colWidths=[1.55 * inch] * 4,
    )
    priority_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, -1), LIGHT_RED),
                ("BACKGROUND", (1, 0), (1, -1), LIGHT_ORANGE),
                ("BACKGROUND", (2, 0), (2, -1), LIGHT_BLUE),
                ("BACKGROUND", (3, 0), (3, -1), LIGHT_TEAL),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, 0), 22),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("GRID", (0, 0), (-1, -1), 2, colors.white),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    story.extend([priority_table, Spacer(1, 0.18 * inch)])

    story.extend(section("Top Issues Across Your Catalog", "Most common performance gaps driving underperformance", styles))
    issue_rows = [["Issue", "SKUs"]] + [[issue, f"{count} SKUs"] for issue, count in issue_totals.items()]
    issue_table = Table(issue_rows, colWidths=[4.6 * inch, 1.4 * inch])
    issue_table.setStyle(table_style())
    story.append(issue_table)

    story.append(PageBreak())
    story.extend(section("Recommended Actions", "Priority improvements to recover revenue and catalog health", styles))
    actions = [
        ("Address Availability Gaps", f"{below_availability} SKUs are below 80% availability. Review inventory levels, replenishment timing, and fulfillment blockers for low-availability SKUs."),
        ("Recover Top Revenue Decliners", "Focus first on high-revenue SKUs with steep YoY declines: ARGD1057, FRRB1329, ATGD5370, ATGD5369, and ARGD1058."),
        ("Improve Required Tag Coverage", "Every reviewed SKU is below the 90% required-tag benchmark. Complete missing required attributes to improve discoverability and filtering."),
        ("Reverse Visit Declines", f"{declining_visits} SKUs have lost more than 20% of visits year-over-year. Review pricing competitiveness, imagery, and merchandising visibility."),
        ("Protect Catalog Quality", "WLAO4493 needs image coverage remediation, while ARGD1057 should be reviewed for elevated incidence rate and customer issue exposure."),
    ]
    action_rows = [["#", "Action", "Details"]]
    for idx, (title, detail) in enumerate(actions, start=1):
        action_rows.append([str(idx), Paragraph(f"<b>{title}</b>", styles["BodyText"]), Paragraph(detail, styles["BodyText"])])
    action_table = Table(action_rows, colWidths=[0.35 * inch, 1.9 * inch, 4.35 * inch])
    action_table.setStyle(table_style(header_bg=BRAND_TEAL))
    story.append(action_table)

    story.append(PageBreak())
    story.extend(section("Top Revenue Decliners", "Highest-revenue SKUs with significant year-over-year declines - address these first", styles))
    decliner_rows = [["SKU", "Current Revenue", "Prior Year Revenue", "YoY Change", "Key Issues"]]
    for row in rev_decliners:
        decliner_rows.append(
            [
                str(row["PrSKU"]),
                fmt_money(row["revenue"]),
                fmt_money(row["py_revenue"]),
                fmt_signed_pct(row["revenue_yoy"]),
                Paragraph(", ".join(row["issues"][:5]), styles["Cell"]),
            ]
        )
    decliner_table = Table(decliner_rows, colWidths=[0.9 * inch, 1.15 * inch, 1.15 * inch, 0.8 * inch, 2.65 * inch], repeatRows=1)
    decliner_table.setStyle(table_style(header_bg=BRAND_RED))
    story.append(decliner_table)

    story.append(PageBreak())
    story.extend(section("Action Priority List", "All reviewed SKUs ranked by issue severity and current revenue", styles))
    rank_order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "MONITOR": 3}
    ranked = sorted(rows, key=lambda row: (rank_order[row["priority"]], -len(row["issues"]), -row["revenue"]))
    priority_rows = [["Priority", "SKU", "Revenue", "Rev YoY", "Avail.", "Conv.", "Issues"]]
    for row in ranked:
        priority_rows.append(
            [
                row["priority"],
                row["PrSKU"],
                fmt_money(row["revenue"]),
                fmt_signed_pct(row["revenue_yoy"]),
                fmt_pct(row["availability"]),
                fmt_pct(row["conversion"]),
                Paragraph(", ".join(row["issues"][:5]), styles["CellSmall"]),
            ]
        )
    priority_list = Table(priority_rows, colWidths=[0.8 * inch, 0.75 * inch, 0.85 * inch, 0.65 * inch, 0.65 * inch, 0.55 * inch, 2.35 * inch], repeatRows=1)
    priority_list.setStyle(table_style(header_bg=BRAND_ORANGE))
    for idx, row in enumerate(priority_rows[1:], start=1):
        priority_list.setStyle(TableStyle([("BACKGROUND", (0, idx), (0, idx), priority_color(row[0]))]))
    story.append(priority_list)

    story.append(PageBreak())
    story.extend(section("Complete SKU Breakdown", f"Full reviewed-SKU performance for {CURRENT_PERIOD} - all {len(rows)} SKUs sorted by revenue", styles))
    full_rows = [["Priority", "SKU", "Revenue", "% Sales", "Rev YoY", "Rev MoM", "Avail.", "Conv.", "Visits", "Visits YoY"]]
    for row in rows:
        full_rows.append(
            [
                row["priority"],
                row["PrSKU"],
                fmt_money(row["revenue"]),
                row["Pct_of_Sales"],
                fmt_signed_pct(row["revenue_yoy"]),
                fmt_signed_pct(row["revenue_mom"]),
                fmt_pct(row["availability"]),
                fmt_pct(row["conversion"]),
                f"{row['visits']:,}",
                fmt_signed_pct(row["visits_yoy"]),
            ]
        )
    full_table = Table(full_rows, colWidths=[0.67 * inch, 0.7 * inch, 0.78 * inch, 0.55 * inch, 0.6 * inch, 0.6 * inch, 0.55 * inch, 0.5 * inch, 0.58 * inch, 0.67 * inch], repeatRows=1)
    full_table.setStyle(table_style())
    for idx, row in enumerate(full_rows[1:], start=1):
        full_table.setStyle(TableStyle([("BACKGROUND", (0, idx), (0, idx), priority_color(row[0]))]))
    story.append(full_table)

    story.append(PageBreak())
    story.extend(section("Catalog Health Detail", "Content and customer issue metrics by SKU", styles))
    health_rows = [["SKU", "Req. Tags", "Image Coverage", "Incidence Rate", "Issue Exposure", "Catalog/Quality Notes"]]
    for row in rows:
        notes = []
        if isinstance(row["req_tag"], float) and row["req_tag"] < TAG_TARGET:
            notes.append("Required tags below 90%")
        if isinstance(row["image"], float) and row["image"] < IMAGE_TARGET:
            notes.append("Image coverage below 100%")
        if isinstance(row["incidence"], float) and row["incidence"] > INCIDENCE_TARGET:
            notes.append("Incidence above 5%")
        if isinstance(row["gie"], float) and row["gie"] > GIE_TARGET:
            notes.append("Customer issue exposure above 5%")
        health_rows.append(
            [
                row["PrSKU"],
                fmt_pct(row["req_tag"]),
                fmt_pct(row["image"]),
                fmt_pct(row["incidence"]),
                fmt_pct(row["gie"]),
                Paragraph("; ".join(notes) if notes else "No catalog quality issue flagged", styles["Cell"]),
            ]
        )
    health_table = Table(health_rows, colWidths=[0.85 * inch, 0.8 * inch, 0.95 * inch, 0.9 * inch, 0.9 * inch, 2.2 * inch], repeatRows=1)
    health_table.setStyle(table_style(header_bg=BRAND_TEAL))
    story.extend([health_table, Spacer(1, 0.22 * inch)])

    story.extend(section("Performance Targets Reference", "Benchmarks used to evaluate SKU health", styles))
    target_rows = [
        ["Metric", "Target", "Why It Matters"],
        ["Availability", ">= 80%", "Ensures customers can purchase when they visit your product page"],
        ["Conversion Rate", ">= 0.8%", "Measures how effectively visits turn into orders"],
        ["Required Tag Coverage", ">= 90%", "Improves product discoverability, filtering, and listing completeness"],
        ["Image Coverage", "100%", "Quality imagery is essential for conversion in home goods"],
        ["Incidence Rate", "<= 5%", "Lower return and complaint rates protect your brand and ranking"],
        ["Customer Issue Exposure", "<= 5%", "Limits revenue exposure from products with quality or service issues"],
    ]
    target_table = Table(target_rows, colWidths=[1.55 * inch, 1.05 * inch, 4.0 * inch])
    target_table.setStyle(table_style())
    story.append(target_table)

    def footer(canvas, doc):
        canvas.saveState()
        canvas.setFont("Helvetica", 7)
        canvas.setFillColor(BRAND_GRAY)
        canvas.drawString(0.55 * inch, 0.35 * inch, f"Confidential - Supplier Performance Review | Generated {REPORT_DATE}")
        canvas.drawRightString(7.95 * inch, 0.35 * inch, f"Page {doc.page}")
        canvas.restoreState()

    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=letter,
        rightMargin=0.55 * inch,
        leftMargin=0.55 * inch,
        topMargin=0.55 * inch,
        bottomMargin=0.55 * inch,
        title=f"Supplier {SUPPLIER_ID} SKU Performance Review - {CURRENT_PERIOD}",
        author="Cursor Cloud Agent",
    )
    doc.build(story, onFirstPage=footer, onLaterPages=footer)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("output_path", type=Path)
    args = parser.parse_args()
    rows = load_rows(args.csv_path)
    args.output_path.parent.mkdir(parents=True, exist_ok=True)
    build_pdf(rows, args.output_path)


if __name__ == "__main__":
    main()
