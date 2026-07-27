#!/usr/bin/env python3
"""Build a Member Monday loyalty lift case study from the exported PDF.

The source spreadsheet was provided as a PDF export. Some long text fields wrap
or overlap in PDF table extraction, so this script normalizes the known supplier
names and class-name split before calculating lift and investment metrics.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import pdfplumber


DEFAULT_PDF = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/"
    "Member_Monday_Loyalty_Lift_-_Discount_vs_Lift_a50b.pdf"
)
OUTPUT_DIR = Path("/workspace/analysis/member_monday/output")

SUPPLIER_INFO = {
    "119490": ("Bes Home Corp.", "Benjamin Hannigan"),
    "78708": (
        "Foshan Shiyue (Visionary) Trading Limited Company",
        "Benjamin Hannigan",
    ),
    "1987": ("JLA Home", "Missy Paragamian"),
    "37327": ("Instyle Products Corp.", "Rikki Sartor"),
    "2554": ("Pem America", "Benjamin Hannigan"),
    "7344": ("Victoria Classics", "Supplier Service Desk"),
    "1748": ("Revman International", "Missy Paragamian"),
    "22695": ("ELEGANCE LINEN", "Benjamin Hannigan"),
    "225555": ("Maple Leaf curtain Corp._1", "Asia Supplier Service Desk"),
    "24282": ("Nanshing America, Inc.", "Jaiden Lawlor"),
    "23665": ("Cozy Line Home Fashions, Inc.", "Jaiden Lawlor"),
    "32808": ("CAN_Cathay Home Inc.", "Paige Beattie"),
    "24696": (
        "Daniel Linen/Home Sweet Home Dreams Inc.",
        "Supplier Service Desk",
    ),
    "112418": ("SAF IJAZ", "Supplier Service Desk"),
    "358408": ("Xinyun Keji (Shanghai) Trading Co., Ltd.", "Jessica Gu"),
    "2387": ("Cloud9 Design Inc.", "Supplier Service Desk"),
    "17102": ("Trade-Linker", "Jaiden Lawlor"),
    "173557": ("Penson & Co.", "Jynn Jiang"),
    "43431": ("ocean home fashion inc", "Asia Supplier Service Desk"),
}

SKU_PREFIX_BY_SUPPLIER = {
    "78708": "VSIO",
    "225555": "ACCQ",
}

KNOWN_CLASSES = {
    "Curtains & Drapes",
    "Blinds and Shades",
    "Valances & Kitchen Curtains",
    "Curtain Hardware & Accessories",
}

DISCOUNT_BUCKET_LABELS = ["<10%", "10-14.9%", "15-19.9%", "20-24.9%", "25%+"]


def parse_currency(value: object) -> float:
    if value is None:
        return 0.0
    text = str(value).strip()
    if not text:
        return 0.0
    text = text.replace("$", "").replace(",", "")
    try:
        return float(text)
    except ValueError:
        return 0.0


def parse_percent(value: object) -> float | None:
    if value is None:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?%", str(value))
    if not match:
        return None
    return float(match.group(0).replace("%", "")) / 100.0


def fmt_currency(value: float) -> str:
    return f"${value:,.0f}"


def fmt_currency_2(value: float) -> str:
    return f"${value:,.2f}"


def fmt_pct(value: float | None, digits: int = 1) -> str:
    if value is None or pd.isna(value):
        return "n/a"
    return f"{value * 100:.{digits}f}%"


def clean_sku(supplier_id: str, value: object) -> str:
    text = "" if value is None else str(value).strip()
    if re.fullmatch(r"[A-Z0-9]{3,}\d+", text):
        return text
    digits = re.search(r"(\d{3,5})$", text)
    if supplier_id in SKU_PREFIX_BY_SUPPLIER and digits:
        return f"{SKU_PREFIX_BY_SUPPLIER[supplier_id]}{digits.group(1)}"
    compact = re.sub(r"[^A-Z0-9]", "", text.upper())
    match = re.search(r"[A-Z]{2,5}\d{3,5}$", compact)
    return match.group(0) if match else compact


def clean_class_and_rec_discount(row: list[object]) -> tuple[str, float | None]:
    class_raw = "" if row[4] is None else str(row[4]).strip()
    rec_raw = row[5]
    if class_raw == "Valances & Kitchen Curt":
        return "Valances & Kitchen Curtains", parse_percent(rec_raw)
    if class_raw in KNOWN_CLASSES:
        return class_raw, parse_percent(rec_raw)
    if class_raw.startswith("Valances & Kitchen Curtains"):
        return "Valances & Kitchen Curtains", parse_percent(rec_raw)
    return class_raw, parse_percent(rec_raw)


def extract_pdf_rows(pdf_path: Path) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    with pdfplumber.open(str(pdf_path)) as pdf:
        for page_num, page in enumerate(pdf.pages, start=1):
            table = page.extract_table() or []
            for source_row_num, row in enumerate(table, start=1):
                if not row or not row[0]:
                    continue
                supplier_id = str(row[0]).strip()
                if supplier_id in {"Supplier ID", "Total"} or not supplier_id.isdigit():
                    continue

                supplier_name, srm = SUPPLIER_INFO.get(
                    supplier_id,
                    (
                        "" if row[1] is None else str(row[1]).strip(),
                        "" if row[2] is None else str(row[2]).strip(),
                    ),
                )
                class_name, rec_discount_pct = clean_class_and_rec_discount(row)
                l10_daily_avg = parse_currency(row[10])
                member_monday_sales = parse_currency(row[11])
                member_monday_lift_pct = parse_percent(row[12])
                if member_monday_lift_pct is None and l10_daily_avg > 0:
                    member_monday_lift_pct = (
                        member_monday_sales - l10_daily_avg
                    ) / l10_daily_avg

                rows.append(
                    {
                        "source_page": page_num,
                        "source_row": source_row_num,
                        "supplier_id": supplier_id,
                        "supplier_name": supplier_name,
                        "srm": srm,
                        "sku": clean_sku(supplier_id, row[3]),
                        "class_name": class_name,
                        "rec_discount_pct": rec_discount_pct,
                        "discount_pct": parse_percent(row[6]),
                        "b2b_discount_pct": parse_percent(row[7]),
                        "wsc_rev_l12m": parse_currency(row[8]),
                        "grs_l12m": parse_currency(row[9]),
                        "l10_non_promo_daily_avg": l10_daily_avg,
                        "member_monday_sales": member_monday_sales,
                        "member_monday_lift_pct": member_monday_lift_pct,
                    }
                )

    df = pd.DataFrame(rows)
    df["incremental_sales"] = (
        df["member_monday_sales"] - df["l10_non_promo_daily_avg"]
    )
    df["active_on_member_monday"] = df["member_monday_sales"] > 0
    df["positive_lift"] = df["incremental_sales"] > 0
    return df


def extract_pdf_total(pdf_path: Path) -> dict[str, float] | None:
    with pdfplumber.open(str(pdf_path)) as pdf:
        for page in pdf.pages:
            for row in page.extract_table() or []:
                if row and row[0] == "Total":
                    return {
                        "l10_non_promo_daily_avg": parse_currency(row[10]),
                        "member_monday_sales": parse_currency(row[11]),
                        "weighted_lift_pct": parse_percent(row[12]) or 0.0,
                    }
    return None


def weighted_avg(series: pd.Series, weights: pd.Series) -> float | None:
    valid = series.notna() & weights.notna() & (weights > 0)
    if not valid.any():
        valid = series.notna()
        if not valid.any():
            return None
        return float(series[valid].mean())
    return float((series[valid] * weights[valid]).sum() / weights[valid].sum())


def summarize(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    records = []
    for keys, group in df.groupby(group_cols, dropna=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        baseline = float(group["l10_non_promo_daily_avg"].sum())
        sales = float(group["member_monday_sales"].sum())
        incremental = sales - baseline
        weighted_lift = incremental / baseline if baseline else None
        weighted_discount = weighted_avg(
            group["discount_pct"], group["l10_non_promo_daily_avg"]
        )
        weighted_b2b = weighted_avg(
            group["b2b_discount_pct"], group["l10_non_promo_daily_avg"]
        )
        weighted_rec = weighted_avg(
            group["rec_discount_pct"], group["l10_non_promo_daily_avg"]
        )
        sku_count = int(group["sku"].nunique())
        active_skus = int(group.loc[group["active_on_member_monday"], "sku"].nunique())
        positive_skus = int(group.loc[group["positive_lift"], "sku"].nunique())
        records.append(
            {
                **dict(zip(group_cols, keys, strict=True)),
                "sku_count": sku_count,
                "active_skus": active_skus,
                "positive_lift_skus": positive_skus,
                "positive_lift_sku_rate": positive_skus / sku_count
                if sku_count
                else None,
                "l10_non_promo_daily_avg": baseline,
                "member_monday_sales": sales,
                "incremental_sales": incremental,
                "weighted_lift_pct": weighted_lift,
                "avg_discount_pct": float(group["discount_pct"].mean()),
                "weighted_discount_pct": weighted_discount,
                "weighted_b2b_discount_pct": weighted_b2b,
                "weighted_rec_discount_pct": weighted_rec,
                "lift_per_discount_point": (weighted_lift / weighted_discount)
                if weighted_lift is not None
                and weighted_discount is not None
                and weighted_discount > 0
                else None,
            }
        )
    return pd.DataFrame(records).sort_values(
        ["member_monday_sales", "incremental_sales"], ascending=False
    )


def build_discount_buckets(df: pd.DataFrame) -> pd.DataFrame:
    bucketed = df.copy()
    bucketed["discount_bucket"] = pd.cut(
        bucketed["discount_pct"],
        bins=[-math.inf, 0.0999, 0.1499, 0.1999, 0.2499, math.inf],
        labels=DISCOUNT_BUCKET_LABELS,
    )
    summary = summarize(bucketed, ["discount_bucket"])
    summary["discount_bucket"] = pd.Categorical(
        summary["discount_bucket"].astype(str),
        categories=DISCOUNT_BUCKET_LABELS,
        ordered=True,
    )
    return summary.sort_values("discount_bucket")


def save_chart_class_sales(class_summary: pd.DataFrame, out: Path) -> None:
    plot_df = class_summary.sort_values("member_monday_sales")
    y = range(len(plot_df))
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.barh(
        [idx - 0.18 for idx in y],
        plot_df["l10_non_promo_daily_avg"],
        height=0.35,
        label="L10 non-promo daily avg",
        color="#9aa6b2",
    )
    ax.barh(
        [idx + 0.18 for idx in y],
        plot_df["member_monday_sales"],
        height=0.35,
        label="Member Monday sales",
        color="#2f6fed",
    )
    ax.set_yticks(list(y), plot_df["class_name"])
    ax.set_xlabel("Sales dollars")
    ax.set_title("Member Monday sales vs. recent non-promo daily average by class")
    ax.xaxis.set_major_formatter(lambda x, _pos: f"${x:,.0f}")
    ax.legend(loc="lower right")
    for idx, row in enumerate(plot_df.itertuples()):
        lift_label = fmt_pct(row.weighted_lift_pct)
        ax.text(
            row.member_monday_sales + max(plot_df["member_monday_sales"]) * 0.01,
            idx + 0.18,
            lift_label,
            va="center",
            fontsize=9,
        )
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def save_chart_supplier_scatter(supplier_summary: pd.DataFrame, out: Path) -> None:
    def abbreviate_supplier(name: str) -> str:
        clean_name = re.sub(r"[^A-Za-z0-9 &]", "", name).strip()
        words = [word for word in clean_name.split() if word.lower() not in {"inc", "llc", "ltd", "co"}]
        if not words:
            return clean_name[:10]
        candidate = " ".join(words[:2])
        return candidate if len(candidate) <= 13 else words[0][:13]

    plot_df = supplier_summary[
        (
            (supplier_summary["l10_non_promo_daily_avg"] > 0)
            | (supplier_summary["member_monday_sales"] > 0)
        )
        & supplier_summary["weighted_discount_pct"].notna()
        & supplier_summary["weighted_lift_pct"].notna()
    ].copy()
    plot_df = plot_df.sort_values("member_monday_sales", ascending=False).head(14)
    plot_df["lift_pct"] = plot_df["weighted_lift_pct"] * 100
    plot_df["discount_pct"] = plot_df["weighted_discount_pct"] * 100
    plot_df["display_lift_pct"] = plot_df["lift_pct"].clip(lower=-110, upper=200)
    plot_df["display_name"] = plot_df["supplier_name"].map(abbreviate_supplier)

    x_min = max(0, plot_df["discount_pct"].min() - 3)
    x_max = plot_df["discount_pct"].max() + 4
    bar_width = max(0.45, (x_max - x_min) / 55)
    plot_df["x_plot"] = plot_df["discount_pct"]
    for _key, group in plot_df.groupby(plot_df["discount_pct"].round(1)):
        if len(group) == 1:
            continue
        offsets = [
            (idx - (len(group) - 1) / 2) * bar_width * 0.85
            for idx in range(len(group))
        ]
        plot_df.loc[group.index, "x_plot"] = group["discount_pct"].to_numpy() + offsets

    fig, ax = plt.subplots(figsize=(11, 7))
    ax.axhline(0, color="#59636e", linewidth=1)
    ax.grid(True, axis="both", alpha=0.25)
    ax.set_xlabel("Weighted discount %")
    ax.set_ylabel("Weighted lift %")
    ax.set_title("Supplier lift vs. promotional investment")
    ax.xaxis.set_major_formatter(lambda x, _pos: f"{x:.0f}%")
    ax.yaxis.set_major_formatter(lambda y, _pos: f"{y:.0f}%")

    ax.set_xlim(x_min, x_max)
    ax.set_ylim(
        min(-20, plot_df["display_lift_pct"].min() - 20),
        max(60, plot_df["display_lift_pct"].max() + 30),
    )

    colors = [
        "#16a163" if value > 0 else "#c84c4c" if value < 0 else "#9aa6b2"
        for value in plot_df["incremental_sales"]
    ]
    ax.bar(
        plot_df["x_plot"],
        plot_df["display_lift_pct"],
        width=bar_width,
        color=colors,
        alpha=0.82,
        edgecolor="white",
        linewidth=0.7,
    )

    for row in plot_df.itertuples():
        label = f"{row.display_name}\n{row.lift_pct:,.0f}%"
        label_offset = 7 if row.display_lift_pct >= 0 else -7
        ax.text(
            row.x_plot,
            row.display_lift_pct + label_offset,
            label,
            ha="center",
            va="bottom" if row.display_lift_pct >= 0 else "top",
            fontsize=7,
            color="#0b1f44",
        )
    if (plot_df["lift_pct"] != plot_df["display_lift_pct"]).any():
        ax.text(
            0.99,
            0.02,
            "Bars capped at -110% and 200% for readability; labels show actual lift",
            ha="right",
            va="bottom",
            transform=ax.transAxes,
            fontsize=8,
            color="#59636e",
        )
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def save_chart_discount_buckets(bucket_summary: pd.DataFrame, out: Path) -> None:
    plot_df = bucket_summary.copy()
    x_positions = list(range(len(plot_df)))
    width = 0.36
    fig, ax = plt.subplots(figsize=(10, 5.8))
    baseline_bars = ax.bar(
        [idx - width / 2 for idx in x_positions],
        plot_df["l10_non_promo_daily_avg"],
        width=width,
        label="L10 non-promo daily avg",
        color="#9b7ce3",
    )
    member_monday_bars = ax.bar(
        [idx + width / 2 for idx in x_positions],
        plot_df["member_monday_sales"],
        width=width,
        label="Member Monday sales",
        color="#4b347f",
    )
    ax.set_xticks(
        x_positions,
        [f"{bucket} B2C Disc." for bucket in plot_df["discount_bucket"].astype(str)],
    )
    ax.set_xlabel("Discount Applied on B2C")
    ax.set_ylabel("Sales dollars")
    ax.set_title("Daily avg sales vs. Member Monday sales by discount bucket")
    ax.yaxis.set_major_formatter(lambda y, _pos: f"${y:,.0f}")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.12), ncol=2, frameon=False)
    max_sales = max(
        plot_df["member_monday_sales"].max(),
        plot_df["l10_non_promo_daily_avg"].max(),
    )
    for idx, row in enumerate(plot_df.itertuples()):
        ax.text(
            idx,
            max(row.member_monday_sales, row.l10_non_promo_daily_avg)
            + max_sales * 0.025,
            fmt_pct(row.weighted_lift_pct),
            ha="center",
            va="bottom",
            fontsize=9,
        )
    for bars in [baseline_bars, member_monday_bars]:
        for bar in bars:
            height = bar.get_height()
            if height <= 0:
                continue
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                height + max_sales * 0.01,
                fmt_currency(height),
                ha="center",
                va="bottom",
                fontsize=7,
                rotation=90,
            )
    ax.set_ylim(0, max_sales * 1.22)
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def save_chart_top_incremental(supplier_summary: pd.DataFrame, out: Path) -> None:
    plot_df = supplier_summary[supplier_summary["incremental_sales"] > 0].copy()
    plot_df = plot_df.sort_values("incremental_sales", ascending=True).tail(10)
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.barh(plot_df["supplier_name"], plot_df["incremental_sales"], color="#16a163")
    ax.set_xlabel("Incremental Member Monday sales dollars")
    ax.set_title("Supplier success stories: largest incremental sales gains")
    ax.xaxis.set_major_formatter(lambda x, _pos: f"${x:,.0f}")
    for y_pos, row in enumerate(plot_df.itertuples()):
        ax.text(
            row.incremental_sales + max(plot_df["incremental_sales"]) * 0.01,
            y_pos,
            fmt_currency(row.incremental_sales),
            va="center",
            fontsize=9,
        )
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def markdown_table(df: pd.DataFrame, columns: list[str], limit: int | None = None) -> str:
    table_df = df.loc[:, columns].copy()
    if limit is not None:
        table_df = table_df.head(limit)
    headers = list(table_df.columns)
    body = [
        ["" if pd.isna(value) else str(value) for value in row]
        for row in table_df.itertuples(index=False, name=None)
    ]
    widths = [
        max(len(header), *(len(row[idx]) for row in body)) if body else len(header)
        for idx, header in enumerate(headers)
    ]

    def render_row(values: list[str]) -> str:
        return "| " + " | ".join(
            value.ljust(widths[idx]) for idx, value in enumerate(values)
        ) + " |"

    separator = "| " + " | ".join("-" * width for width in widths) + " |"
    lines = [render_row(headers), separator]
    lines.extend(render_row(row) for row in body)
    return "\n".join(lines)


def metric_definitions() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "metric": "sku_count",
                "definition": "Count of unique participating SKUs in the group.",
            },
            {
                "metric": "active_skus",
                "definition": (
                    "Count of participating SKUs that recorded more than $0 in "
                    "Member Monday sales."
                ),
            },
            {
                "metric": "positive_lift_skus",
                "definition": (
                    "Count of participating SKUs where Member Monday sales were "
                    "greater than the recent non-promo daily average."
                ),
            },
            {
                "metric": "positive_lift_sku_rate",
                "definition": "Positive lift SKUs divided by total participating SKUs.",
            },
            {
                "metric": "l10_non_promo_daily_avg",
                "definition": (
                    "Recent non-promotional daily sales average used as the baseline."
                ),
            },
            {
                "metric": "member_monday_sales",
                "definition": "Sales recorded for the SKU/group on Member Monday.",
            },
            {
                "metric": "incremental_sales",
                "definition": (
                    "Member Monday sales minus the recent non-promo daily average."
                ),
            },
            {
                "metric": "weighted_lift_pct",
                "definition": (
                    "Incremental sales divided by the recent non-promo daily average."
                ),
            },
            {
                "metric": "weighted_discount_pct",
                "definition": (
                    "Supplier discount investment weighted by baseline sales, so "
                    "higher-volume SKUs influence the average more than low-volume SKUs."
                ),
            },
            {
                "metric": "lift_per_discount_point",
                "definition": (
                    "Weighted lift divided by weighted discount. A value of 2.0 means "
                    "the group produced 2 percentage points of sales lift for every "
                    "1 percentage point of discount investment. Use this as an "
                    "efficiency indicator, not as a dollar ROI."
                ),
            },
        ]
    )


def prep_report_tables(
    class_summary: pd.DataFrame,
    supplier_summary: pd.DataFrame,
    bucket_summary: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    class_table = class_summary.copy()
    for col in [
        "l10_non_promo_daily_avg",
        "member_monday_sales",
        "incremental_sales",
    ]:
        class_table[col] = class_table[col].map(fmt_currency_2)
    for col in [
        "weighted_lift_pct",
        "weighted_discount_pct",
        "positive_lift_sku_rate",
    ]:
        class_table[col] = class_table[col].map(fmt_pct)

    supplier_table = supplier_summary.copy()
    supplier_table = supplier_table.sort_values(
        "incremental_sales", ascending=False
    )
    for col in [
        "l10_non_promo_daily_avg",
        "member_monday_sales",
        "incremental_sales",
    ]:
        supplier_table[col] = supplier_table[col].map(fmt_currency_2)
    for col in [
        "weighted_lift_pct",
        "weighted_discount_pct",
        "positive_lift_sku_rate",
    ]:
        supplier_table[col] = supplier_table[col].map(fmt_pct)

    success_table = supplier_summary[
        (supplier_summary["incremental_sales"] > 0)
        & (supplier_summary["member_monday_sales"] >= 10)
    ].copy()
    success_table = success_table.sort_values(
        ["incremental_sales", "weighted_lift_pct"], ascending=False
    )
    for col in [
        "l10_non_promo_daily_avg",
        "member_monday_sales",
        "incremental_sales",
    ]:
        success_table[col] = success_table[col].map(fmt_currency_2)
    for col in [
        "weighted_lift_pct",
        "weighted_discount_pct",
        "positive_lift_sku_rate",
    ]:
        success_table[col] = success_table[col].map(fmt_pct)

    bucket_table = bucket_summary.copy()
    for col in [
        "l10_non_promo_daily_avg",
        "member_monday_sales",
        "incremental_sales",
    ]:
        bucket_table[col] = bucket_table[col].map(fmt_currency_2)
    for col in ["weighted_lift_pct", "weighted_discount_pct"]:
        bucket_table[col] = bucket_table[col].map(fmt_pct)

    return class_table, supplier_table, success_table, bucket_table


def write_report(
    out_dir: Path,
    sku_df: pd.DataFrame,
    class_summary: pd.DataFrame,
    supplier_summary: pd.DataFrame,
    bucket_summary: pd.DataFrame,
    source_totals: dict[str, float] | None = None,
) -> None:
    extracted_baseline = float(sku_df["l10_non_promo_daily_avg"].sum())
    extracted_sales = float(sku_df["member_monday_sales"].sum())
    if source_totals:
        baseline = source_totals["l10_non_promo_daily_avg"]
        sales = source_totals["member_monday_sales"]
        lift = source_totals["weighted_lift_pct"]
    else:
        baseline = extracted_baseline
        sales = extracted_sales
        lift = (sales - baseline) / baseline if baseline else None
    incremental = sales - baseline
    qa_note = (
        "The cleaned SKU-detail reconstruction ties to the PDF total within "
        f"{fmt_currency_2(abs(extracted_baseline - baseline))} on the baseline "
        f"and {fmt_currency_2(abs(extracted_sales - sales))} on Member Monday sales."
    )
    active_skus = int(sku_df.loc[sku_df["active_on_member_monday"], "sku"].nunique())
    positive_skus = int(sku_df.loc[sku_df["positive_lift"], "sku"].nunique())
    total_skus = int(sku_df["sku"].nunique())
    weighted_discount = weighted_avg(
        sku_df["discount_pct"], sku_df["l10_non_promo_daily_avg"]
    )

    best_class = class_summary.sort_values("weighted_lift_pct", ascending=False).iloc[0]
    biggest_class = class_summary.sort_values("member_monday_sales", ascending=False).iloc[
        0
    ]
    success_suppliers = supplier_summary[
        (supplier_summary["incremental_sales"] > 0)
        & (supplier_summary["member_monday_sales"] >= 10)
    ].sort_values("incremental_sales", ascending=False)
    best_supplier = success_suppliers.iloc[0]
    scaled_efficiency_candidates = success_suppliers[
        (success_suppliers["active_skus"] >= 5)
        & (success_suppliers["l10_non_promo_daily_avg"] >= 100)
        & success_suppliers["weighted_discount_pct"].notna()
    ]
    if scaled_efficiency_candidates.empty:
        scaled_efficiency_candidates = success_suppliers[
            success_suppliers["weighted_discount_pct"].notna()
        ]
    scaled_efficiency_supplier = scaled_efficiency_candidates.sort_values(
        "lift_per_discount_point", ascending=False
    ).iloc[0]
    breakout_supplier = success_suppliers[
        success_suppliers["weighted_lift_pct"].notna()
    ].sort_values("weighted_lift_pct", ascending=False).iloc[0]

    class_table, supplier_table, success_table, bucket_table = prep_report_tables(
        class_summary, supplier_summary, bucket_summary
    )

    report = f"""# Member Monday Loyalty Lift Case Study: Window Category

## Executive takeaway

Member Monday generated **{fmt_currency_2(sales)}** in participating SKU sales versus a recent non-promo daily average of **{fmt_currency_2(baseline)}**, creating **{fmt_currency_2(incremental)} in incremental sales** and a **{fmt_pct(lift)} weighted lift**. The event gives suppliers a practical proof point that loyalty-led traffic can move window-category demand when promotion depth is paired with the right SKU selection.

**Important reading note:** the source file compares a one-day Member Monday result to each SKU's recent non-promo daily average. I treat the `Discount` field as the supplier promotional investment level and calculate portfolio lift as `(Member Monday Sales - L10 Non Promo Daily Avg) / L10 Non Promo Daily Avg`.

**Data QA note:** {qa_note}

## Metric definitions

- **Active SKUs:** participating SKUs that had more than `$0` in Member Monday sales. It answers, "How many of the submitted SKUs actually sold during the event?"
- **Lift per discount point:** weighted sales lift divided by weighted discount investment. For example, a value of `2.0` means the supplier generated about 2 percentage points of sales lift for every 1 percentage point of discount. Use it as an efficiency read, not a margin or dollar ROI calculation.
- **Weighted lift:** total incremental sales divided by the total recent non-promo daily average for that group.
- **Weighted discount:** the `Discount` field averaged by baseline sales, so higher-volume SKUs influence the supplier/class average more than low-volume SKUs.

## What changed on Member Monday

- **Overall lift:** {fmt_pct(lift)} on {fmt_currency_2(sales)} in Member Monday sales.
- **Incremental sales:** {fmt_currency_2(incremental)} above the recent non-promo daily average.
- **Participation breadth:** {active_skus} of {total_skus} participating SKUs recorded Member Monday sales; {positive_skus} SKUs generated positive incremental dollars.
- **Weighted supplier investment:** {fmt_pct(weighted_discount)} average `Discount` rate, weighted by the recent non-promo daily average.
- **Best class by lift:** {best_class.class_name} at {fmt_pct(best_class.weighted_lift_pct)} weighted lift.
- **Largest class by event sales:** {biggest_class.class_name} with {fmt_currency_2(biggest_class.member_monday_sales)} in Member Monday sales.

![Class sales lift](charts/class_sales_lift.png)

## Class-level insights

{markdown_table(class_table, [
    "class_name",
    "sku_count",
    "active_skus",
    "positive_lift_sku_rate",
    "weighted_discount_pct",
    "l10_non_promo_daily_avg",
    "member_monday_sales",
    "incremental_sales",
    "weighted_lift_pct",
])}

### How to use these class insights with suppliers

- **Lead with the proof point:** {best_class.class_name} delivered the strongest class-level lift, showing that even specialized window classes respond when promoted through the loyalty event.
- **Separate scale from rate:** {biggest_class.class_name} produced the largest Member Monday dollar volume, while smaller classes can show higher lift rates because their baseline is lower.
- **Use the active-SKU rate as a merchandising filter:** classes with many participating SKUs but fewer active SKUs should be reviewed for search placement, inventory, and item attractiveness before simply increasing discount depth.

![Class/investment lift buckets](charts/discount_bucket_lift.png)

In the discount-bucket chart, light purple bars show the recent non-promo daily average and dark purple bars show Member Monday sales.

## Promotional investment vs. lift

{markdown_table(bucket_table, [
    "discount_bucket",
    "sku_count",
    "weighted_discount_pct",
    "l10_non_promo_daily_avg",
    "member_monday_sales",
    "incremental_sales",
    "weighted_lift_pct",
])}

The investment story is not purely "deeper discount equals better lift." Mid- and higher-discount buckets both produced wins, but SKU relevance and baseline demand materially shaped outcomes. This is a useful supplier message: Member Monday works best when suppliers fund a compelling offer **and** nominate SKUs with enough demand signal to convert loyalty traffic.

![Supplier lift vs investment](charts/supplier_lift_vs_investment.png)

## Supplier-level insights

{markdown_table(supplier_table, [
    "supplier_name",
    "sku_count",
    "active_skus",
    "positive_lift_sku_rate",
    "weighted_discount_pct",
    "l10_non_promo_daily_avg",
    "member_monday_sales",
    "incremental_sales",
    "weighted_lift_pct",
], limit=15)}

## Supplier success stories

{markdown_table(success_table, [
    "supplier_name",
    "sku_count",
    "active_skus",
    "positive_lift_sku_rate",
    "weighted_discount_pct",
    "l10_non_promo_daily_avg",
    "member_monday_sales",
    "incremental_sales",
    "weighted_lift_pct",
], limit=10)}

![Top incremental supplier gains](charts/top_supplier_incremental_sales.png)

### Storylines for supplier conversations

1. **Scaled incremental win:** {best_supplier.supplier_name} produced the largest positive incremental sales gain at **{fmt_currency_2(best_supplier.incremental_sales)}** over baseline, with **{fmt_currency_2(best_supplier.member_monday_sales)}** in Member Monday sales.
2. **Scaled efficiency win:** {scaled_efficiency_supplier.supplier_name} paired meaningful scale with efficient lift, generating **{fmt_pct(scaled_efficiency_supplier.weighted_lift_pct)}** lift at a **{fmt_pct(scaled_efficiency_supplier.weighted_discount_pct)}** weighted discount.
3. **Low-baseline breakout:** {breakout_supplier.supplier_name} produced the highest supplier lift rate among positive suppliers. Use this as an upside story, but frame it as a low-baseline result that should be validated with repeat events.
4. **Assortment learning:** suppliers with many participating SKUs but low active-SKU rates are candidates for tighter SKU curation. The event can still work, but the next round should prioritize items with stronger recent traffic, inventory, imagery, and price competitiveness.

## Recommended supplier-facing message

> Member Monday created measurable incremental demand in the window category. Across participating SKUs, the event lifted sales **{fmt_pct(lift)}** above recent non-promo daily averages. The strongest results came when suppliers paired meaningful discount funding with SKUs that already had enough customer demand to convert loyalty traffic. For the next event, we should use this case study to ask suppliers for targeted funding on proven SKUs, then expand selectively into similar items/classes.

## Files generated

- `member_monday_sku_data.csv`: cleaned SKU-level extract.
- `class_summary.csv`: class-level performance and investment metrics.
- `supplier_summary.csv`: supplier-level performance and investment metrics.
- `discount_bucket_summary.csv`: lift by supplier discount-investment bucket.
- `member_monday_case_study.xlsx`: workbook with all summary tabs.
- `charts/*.png`: visual assets for supplier-facing materials.
"""
    (out_dir / "Member_Monday_Loyalty_Lift_Case_Study.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    charts_dir = args.out / "charts"
    charts_dir.mkdir(parents=True, exist_ok=True)

    source_totals = extract_pdf_total(args.pdf)
    sku_df = extract_pdf_rows(args.pdf)
    class_summary = summarize(sku_df, ["class_name"])
    supplier_summary = summarize(sku_df, ["supplier_id", "supplier_name", "srm"])
    bucket_summary = build_discount_buckets(sku_df)

    sku_df.to_csv(args.out / "member_monday_sku_data.csv", index=False)
    class_summary.to_csv(args.out / "class_summary.csv", index=False)
    supplier_summary.to_csv(args.out / "supplier_summary.csv", index=False)
    bucket_summary.to_csv(args.out / "discount_bucket_summary.csv", index=False)

    with pd.ExcelWriter(args.out / "member_monday_case_study.xlsx") as writer:
        metric_definitions().to_excel(
            writer, sheet_name="Metric Definitions", index=False
        )
        sku_df.to_excel(writer, sheet_name="SKU Data", index=False)
        class_summary.to_excel(writer, sheet_name="Class Summary", index=False)
        supplier_summary.to_excel(writer, sheet_name="Supplier Summary", index=False)
        bucket_summary.to_excel(writer, sheet_name="Discount Buckets", index=False)

    plt.style.use("seaborn-v0_8-whitegrid")
    save_chart_class_sales(class_summary, charts_dir / "class_sales_lift.png")
    save_chart_supplier_scatter(
        supplier_summary, charts_dir / "supplier_lift_vs_investment.png"
    )
    save_chart_discount_buckets(bucket_summary, charts_dir / "discount_bucket_lift.png")
    save_chart_top_incremental(
        supplier_summary, charts_dir / "top_supplier_incremental_sales.png"
    )
    write_report(
        args.out,
        sku_df,
        class_summary,
        supplier_summary,
        bucket_summary,
        source_totals,
    )

    print(f"Rows extracted: {len(sku_df)}")
    print(
        "Extracted detail totals:",
        fmt_currency_2(float(sku_df["l10_non_promo_daily_avg"].sum())),
        fmt_currency_2(float(sku_df["member_monday_sales"].sum())),
    )
    if source_totals:
        print(
            "PDF total:",
            fmt_currency_2(source_totals["l10_non_promo_daily_avg"]),
            fmt_currency_2(source_totals["member_monday_sales"]),
            fmt_pct(source_totals["weighted_lift_pct"], digits=2),
        )
    print(f"Output written to {args.out}")


if __name__ == "__main__":
    main()
