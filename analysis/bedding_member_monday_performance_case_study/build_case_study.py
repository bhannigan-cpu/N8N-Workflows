#!/usr/bin/env python3
"""Build a Bedding Member Monday performance case study from CSV results."""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


DEFAULT_CSV = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/"
    "NH_-_Cost_Performance_Hub_Single_Promo_Detail_Table_-_Sheet1__1__4aab.csv"
)
OUTPUT_DIR = Path("/workspace/analysis/bedding_member_monday_performance_case_study/output")
DISCOUNT_BUCKET_LABELS = ["<10%", "10-14.9%", "15-19.9%", "20-24.9%", "25%+"]
BASELINE_TIER_LABELS = [
    "Low baseline",
    "Mid-low baseline",
    "Mid-high baseline",
    "High baseline",
]


def parse_currency(value: object) -> float:
    if value is None or pd.isna(value):
        return 0.0
    text = str(value).replace("$", "").replace(",", "").strip()
    return float(text) if text else 0.0


def parse_percent(value: object) -> float | None:
    if value is None or pd.isna(value):
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", str(value))
    return float(match.group(0)) / 100.0 if match else None


def fmt_currency(value: float) -> str:
    return f"${value:,.0f}"


def fmt_currency_2(value: float) -> str:
    return f"${value:,.2f}"


def fmt_pct(value: float | None, digits: int = 1) -> str:
    if value is None or pd.isna(value):
        return "n/a"
    return f"{value * 100:.{digits}f}%"


def load_sku_data(csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(csv_path, dtype=str)
    df = df.rename(
        columns={
            "Brand Catalog": "brand_catalog",
            "Supplier ID": "supplier_id",
            "Supplier Name": "supplier_name",
            "SRM": "srm",
            "SKU": "sku",
            "Class Name": "class_name",
            "Marketing Category SKU": "marketing_category",
            "Discount": "discount_pct",
            "Non Promo Avg": "non_promo_avg",
            "Loyalty Avg": "loyalty_avg",
            "Lift": "lift_pct",
        }
    )
    df["discount_pct"] = df["discount_pct"].map(parse_percent)
    df["lift_pct"] = df["lift_pct"].map(parse_percent)
    df["non_promo_avg"] = df["non_promo_avg"].map(parse_currency)
    df["loyalty_avg"] = df["loyalty_avg"].map(parse_currency)
    needs_lift = df["lift_pct"].isna() & (df["non_promo_avg"] > 0)
    df.loc[needs_lift, "lift_pct"] = (
        df.loc[needs_lift, "loyalty_avg"] - df.loc[needs_lift, "non_promo_avg"]
    ) / df.loc[needs_lift, "non_promo_avg"]
    df["incremental_sales"] = df["loyalty_avg"] - df["non_promo_avg"]
    df["active_on_event"] = df["loyalty_avg"] > 0
    df["positive_lift"] = df["incremental_sales"] > 0
    return df


def weighted_avg(series: pd.Series, weights: pd.Series) -> float | None:
    valid = series.notna() & weights.notna() & (weights > 0)
    if valid.any():
        return float((series[valid] * weights[valid]).sum() / weights[valid].sum())
    valid = series.notna()
    return float(series[valid].mean()) if valid.any() else None


def summarize(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    records = []
    for keys, group in df.groupby(group_cols, dropna=False, observed=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        baseline = float(group["non_promo_avg"].sum())
        sales = float(group["loyalty_avg"].sum())
        incremental = sales - baseline
        weighted_lift = incremental / baseline if baseline else None
        sku_count = int(group["sku"].nunique())
        active_skus = int(group.loc[group["active_on_event"], "sku"].nunique())
        positive_skus = int(group.loc[group["positive_lift"], "sku"].nunique())
        weighted_discount = weighted_avg(group["discount_pct"], group["non_promo_avg"])
        records.append(
            {
                **dict(zip(group_cols, keys, strict=True)),
                "sku_count": sku_count,
                "active_skus": active_skus,
                "positive_lift_skus": positive_skus,
                "positive_lift_sku_rate": positive_skus / sku_count if sku_count else None,
                "non_promo_avg": baseline,
                "loyalty_avg": sales,
                "incremental_sales": incremental,
                "weighted_lift_pct": weighted_lift,
                "avg_discount_pct": float(group["discount_pct"].mean()),
                "weighted_discount_pct": weighted_discount,
                "lift_per_discount_point": (
                    weighted_lift / weighted_discount
                    if weighted_lift is not None and weighted_discount and weighted_discount > 0
                    else None
                ),
            }
        )
    return pd.DataFrame(records).sort_values(["loyalty_avg", "incremental_sales"], ascending=False)


def build_discount_buckets(df: pd.DataFrame) -> pd.DataFrame:
    bucketed = df.copy()
    bucketed["discount_bucket"] = pd.cut(
        bucketed["discount_pct"],
        bins=[-math.inf, 0.0999, 0.1499, 0.1999, 0.2499, math.inf],
        labels=DISCOUNT_BUCKET_LABELS,
    )
    summary = summarize(bucketed, ["discount_bucket"])
    summary["discount_bucket"] = pd.Categorical(summary["discount_bucket"].astype(str), categories=DISCOUNT_BUCKET_LABELS, ordered=True)
    return summary.sort_values("discount_bucket")


def build_baseline_tiers(df: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, float]]:
    tiered = df[df["non_promo_avg"] > 0].copy()
    quantiles = tiered["non_promo_avg"].quantile([0.25, 0.5, 0.75]).to_dict()
    tiered["baseline_success_tier"] = pd.qcut(
        tiered["non_promo_avg"],
        q=4,
        labels=BASELINE_TIER_LABELS,
        duplicates="drop",
    )
    summary = summarize(tiered, ["baseline_success_tier"])
    summary["baseline_success_tier"] = pd.Categorical(
        summary["baseline_success_tier"].astype(str),
        categories=BASELINE_TIER_LABELS,
        ordered=True,
    )
    return summary.sort_values("baseline_success_tier"), quantiles


def save_grouped_sales_chart(summary: pd.DataFrame, label_col: str, title: str, out: Path, top_n: int | None = None) -> None:
    plot_df = summary.copy()
    if top_n:
        plot_df = plot_df.head(top_n)
    plot_df = plot_df.sort_values("loyalty_avg", ascending=False)
    x_positions = list(range(len(plot_df)))
    width = 0.36
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar([idx - width / 2 for idx in x_positions], plot_df["non_promo_avg"], width=width, label="Non-promo avg", color="#9b7ce3")
    ax.bar([idx + width / 2 for idx in x_positions], plot_df["loyalty_avg"], width=width, label="Loyalty avg", color="#4b347f")
    ax.set_xticks(x_positions, plot_df[label_col].astype(str), rotation=25, ha="right")
    ax.set_ylabel("Sales dollars")
    ax.set_title(title)
    ax.yaxis.set_major_formatter(lambda y, _pos: f"${y:,.0f}")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.12), ncol=2, frameon=False)
    max_sales = max(plot_df["loyalty_avg"].max(), plot_df["non_promo_avg"].max())
    for idx, row in enumerate(plot_df.itertuples()):
        ax.text(idx, max(row.loyalty_avg, row.non_promo_avg) + max_sales * 0.025, fmt_pct(row.weighted_lift_pct), ha="center", va="bottom", fontsize=8)
    ax.set_ylim(0, max_sales * 1.25)
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def save_lift_bar_chart(summary: pd.DataFrame, label_col: str, title: str, out: Path) -> None:
    plot_df = summary.copy()
    fig, ax = plt.subplots(figsize=(10, 5.8))
    bars = ax.bar(plot_df[label_col].astype(str), plot_df["weighted_lift_pct"] * 100, color="#4b347f")
    ax.axhline(0, color="#59636e", linewidth=1)
    ax.set_ylabel("Weighted lift %")
    ax.set_title(title)
    ax.yaxis.set_major_formatter(lambda y, _pos: f"{y:.0f}%")
    for bar, row in zip(bars, plot_df.itertuples(), strict=True):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{row.weighted_lift_pct * 100:.0f}%", ha="center", va="bottom" if row.weighted_lift_pct >= 0 else "top", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def abbreviate_supplier(name: str) -> str:
    clean_name = re.sub(r"[^A-Za-z0-9 &]", "", name).strip()
    words = [word for word in clean_name.split() if word.lower() not in {"inc", "llc", "ltd", "co"}]
    if not words:
        return clean_name[:10]
    candidate = " ".join(words[:2])
    return candidate if len(candidate) <= 13 else words[0][:13]


def save_supplier_chart(supplier_summary: pd.DataFrame, out: Path) -> None:
    plot_df = supplier_summary[(supplier_summary["non_promo_avg"] > 0) & supplier_summary["weighted_discount_pct"].notna() & supplier_summary["weighted_lift_pct"].notna()].copy()
    plot_df = plot_df.sort_values("loyalty_avg", ascending=False).head(14)
    plot_df["lift_pct"] = plot_df["weighted_lift_pct"] * 100
    plot_df["discount_pct"] = plot_df["weighted_discount_pct"] * 100
    plot_df["display_lift_pct"] = plot_df["lift_pct"].clip(lower=-110, upper=100)
    plot_df["display_name"] = plot_df["supplier_name"].map(abbreviate_supplier)
    x_min = max(0, plot_df["discount_pct"].min() - 3)
    x_max = plot_df["discount_pct"].max() + 4
    bar_width = max(0.35, (x_max - x_min) / 70)
    plot_df["x_plot"] = plot_df["discount_pct"]
    plot_df["label_offset"] = 7
    for _key, group in plot_df.groupby((plot_df["discount_pct"] / 1.0).round()):
        if len(group) == 1:
            continue
        offsets = [(idx - (len(group) - 1) / 2) * bar_width * 1.45 for idx in range(len(group))]
        plot_df.loc[group.index, "x_plot"] = group["discount_pct"].to_numpy() + offsets
        plot_df.loc[group.index, "label_offset"] = [7 + (idx % 3) * 8 for idx in range(len(group))]
    fig, ax = plt.subplots(figsize=(11, 7))
    ax.axhline(0, color="#59636e", linewidth=1)
    ax.grid(True, axis="both", alpha=0.25)
    ax.set_xlabel("Weighted discount %")
    ax.set_ylabel("Weighted lift %")
    ax.set_title("Supplier lift vs. promotional investment")
    ax.xaxis.set_major_formatter(lambda x, _pos: f"{x:.0f}%")
    ax.yaxis.set_major_formatter(lambda y, _pos: f"{y:.0f}%")
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(min(-20, plot_df["display_lift_pct"].min() - 20), max(60, plot_df["display_lift_pct"].max() + 30))
    colors = ["#16a163" if value > 0 else "#c84c4c" if value < 0 else "#9aa6b2" for value in plot_df["incremental_sales"]]
    ax.bar(plot_df["x_plot"], plot_df["display_lift_pct"], width=bar_width, color=colors, alpha=0.82, edgecolor="white", linewidth=0.7)
    for row in plot_df.itertuples():
        label = f"{row.display_name}\n{row.lift_pct:,.0f}%"
        offset = row.label_offset if row.display_lift_pct >= 0 else -row.label_offset
        ax.text(row.x_plot, row.display_lift_pct + offset, label, ha="center", va="bottom" if row.display_lift_pct >= 0 else "top", fontsize=7, color="#0b1f44")
    if (plot_df["lift_pct"] != plot_df["display_lift_pct"]).any():
        ax.text(0.99, 0.02, "Bars capped at -110% and 100% for readability; labels show actual lift", ha="right", va="bottom", transform=ax.transAxes, fontsize=8, color="#59636e")
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def save_top_incremental_chart(supplier_summary: pd.DataFrame, out: Path) -> None:
    plot_df = supplier_summary[supplier_summary["incremental_sales"] > 0].copy()
    plot_df = plot_df.sort_values("incremental_sales", ascending=True).tail(10)
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.barh(plot_df["supplier_name"], plot_df["incremental_sales"], color="#16a163")
    ax.set_xlabel("Incremental loyalty sales dollars")
    ax.set_title("Supplier success stories: largest incremental sales gains")
    ax.xaxis.set_major_formatter(lambda x, _pos: f"${x:,.0f}")
    max_incremental = max(plot_df["incremental_sales"]) if len(plot_df) else 0
    for y_pos, row in enumerate(plot_df.itertuples()):
        ax.text(row.incremental_sales + max_incremental * 0.01, y_pos, fmt_currency(row.incremental_sales), va="center", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=180)
    plt.close(fig)


def markdown_table(df: pd.DataFrame, columns: list[str], limit: int | None = None) -> str:
    table_df = df.loc[:, columns].copy()
    if limit is not None:
        table_df = table_df.head(limit)
    headers = list(table_df.columns)
    body = [[("" if pd.isna(value) else str(value)) for value in row] for row in table_df.itertuples(index=False, name=None)]
    widths = [max(len(header), *(len(row[idx]) for row in body)) if body else len(header) for idx, header in enumerate(headers)]

    def render_row(values: list[str]) -> str:
        return "| " + " | ".join(value.ljust(widths[idx]) for idx, value in enumerate(values)) + " |"

    return "\n".join([render_row(headers), "| " + " | ".join("-" * width for width in widths) + " |", *(render_row(row) for row in body)])


def format_report_table(df: pd.DataFrame) -> pd.DataFrame:
    formatted = df.copy()
    for col in ["non_promo_avg", "loyalty_avg", "incremental_sales"]:
        formatted[col] = formatted[col].map(fmt_currency_2)
    for col in ["weighted_lift_pct", "weighted_discount_pct", "positive_lift_sku_rate"]:
        if col in formatted:
            formatted[col] = formatted[col].map(fmt_pct)
    return formatted


def metric_definitions() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {"metric": "baseline_success_tier", "definition": "Quartile based on each SKU's non-promo average. High baseline SKUs are the historically stronger SKUs."},
            {"metric": "active_skus", "definition": "Count of participating SKUs with more than $0 in loyalty sales."},
            {"metric": "weighted_lift_pct", "definition": "Incremental sales divided by non-promo average."},
            {"metric": "weighted_discount_pct", "definition": "Discount weighted by non-promo average sales."},
        ]
    )


def write_report(out_dir: Path, sku_df: pd.DataFrame, class_summary: pd.DataFrame, supplier_summary: pd.DataFrame, discount_summary: pd.DataFrame, baseline_tier_summary: pd.DataFrame, quantiles: dict[str, float]) -> None:
    baseline = float(sku_df["non_promo_avg"].sum())
    sales = float(sku_df["loyalty_avg"].sum())
    incremental = sales - baseline
    lift = incremental / baseline
    active_skus = int(sku_df.loc[sku_df["active_on_event"], "sku"].nunique())
    positive_skus = int(sku_df.loc[sku_df["positive_lift"], "sku"].nunique())
    total_skus = int(sku_df["sku"].nunique())
    weighted_discount = weighted_avg(sku_df["discount_pct"], sku_df["non_promo_avg"])
    high_tier = baseline_tier_summary[baseline_tier_summary["baseline_success_tier"].astype(str) == "High baseline"].iloc[0]
    low_tier = baseline_tier_summary[baseline_tier_summary["baseline_success_tier"].astype(str) == "Low baseline"].iloc[0]
    best_class = class_summary[class_summary["weighted_lift_pct"].notna()].sort_values("weighted_lift_pct", ascending=False).iloc[0]
    biggest_class = class_summary.sort_values("loyalty_avg", ascending=False).iloc[0]
    best_supplier = supplier_summary[supplier_summary["incremental_sales"] > 0].sort_values("incremental_sales", ascending=False).iloc[0]
    class_table = format_report_table(class_summary)
    supplier_table = format_report_table(supplier_summary.sort_values("incremental_sales", ascending=False))
    discount_table = format_report_table(discount_summary)
    tier_table = format_report_table(baseline_tier_summary)
    report = f"""# Bedding Member Monday Performance Case Study

## Executive takeaway

The Bedding Member Monday file generated **{fmt_currency_2(sales)}** in loyalty sales versus a recent non-promo average of **{fmt_currency_2(baseline)}**, creating **{fmt_currency_2(incremental)} in incremental sales** and **{fmt_pct(lift)} weighted lift**.

## What changed during the event

- **Overall lift:** {fmt_pct(lift)}
- **Incremental sales:** {fmt_currency_2(incremental)}
- **Participation breadth:** {active_skus} of {total_skus} participating SKUs recorded loyalty sales; {positive_skus} SKUs generated positive incremental dollars.
- **Weighted supplier investment:** {fmt_pct(weighted_discount)} average discount, weighted by non-promo average.
- **Best class by lift:** {best_class.class_name} at {fmt_pct(best_class.weighted_lift_pct)}.
- **Largest class by loyalty sales:** {biggest_class.class_name} with {fmt_currency_2(biggest_class.loyalty_avg)}.

![Class sales lift](charts/class_sales_lift.png)

## Are normally successful SKUs performing better or worse?

Using each SKU's non-promo average as a proxy for normal/historical success, the highest-baseline quartile did **not** outperform. High-baseline SKUs (above roughly {fmt_currency_2(quantiles[0.75])} in non-promo average) delivered **{fmt_pct(high_tier.weighted_lift_pct)} weighted lift**, while low-baseline SKUs delivered **{fmt_pct(low_tier.weighted_lift_pct)} weighted lift**.

This suggests the event was better at surfacing incremental demand for lower-baseline or discovery-oriented SKUs than at materially accelerating the already-successful Bedding SKUs. The strongest existing products still generated the majority of sales dollars, but their relative lift was roughly flat/slightly down, so future loyalty events should pair hero SKUs with selective challenger SKUs rather than relying only on historically strong items.

![Baseline success tier lift](charts/baseline_success_tier_lift.png)

{markdown_table(tier_table, ["baseline_success_tier", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_avg", "loyalty_avg", "incremental_sales", "weighted_lift_pct"])}

## Class-level insights

{markdown_table(class_table, ["class_name", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_avg", "loyalty_avg", "incremental_sales", "weighted_lift_pct"])}

![Discount bucket lift](charts/discount_bucket_lift.png)

## Promotional investment vs. lift

{markdown_table(discount_table, ["discount_bucket", "sku_count", "weighted_discount_pct", "non_promo_avg", "loyalty_avg", "incremental_sales", "weighted_lift_pct"])}

![Supplier lift vs investment](charts/supplier_lift_vs_investment.png)

## Supplier-level insights

{markdown_table(supplier_table, ["supplier_name", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_avg", "loyalty_avg", "incremental_sales", "weighted_lift_pct"], limit=15)}

## Supplier success stories

The largest incremental supplier win was **{best_supplier.supplier_name}**, with **{fmt_currency_2(best_supplier.incremental_sales)}** in incremental sales and **{fmt_pct(best_supplier.weighted_lift_pct)}** weighted lift.

![Top incremental supplier gains](charts/top_supplier_incremental_sales.png)

## Files generated

- `bedding_member_monday_sku_data.csv`: cleaned SKU-level extract.
- `class_summary.csv`: class-level performance.
- `supplier_summary.csv`: supplier-level performance.
- `discount_bucket_summary.csv`: lift by discount-investment bucket.
- `baseline_success_tier_summary.csv`: normal-success tier performance.
- `bedding_member_monday_case_study.xlsx`: workbook with all summary tabs.
- `charts/*.png`: visual assets for supplier-facing materials.
"""
    (out_dir / "Bedding_Member_Monday_Performance_Case_Study.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--out", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    charts_dir = args.out / "charts"
    charts_dir.mkdir(parents=True, exist_ok=True)
    sku_df = load_sku_data(args.csv)
    class_summary = summarize(sku_df, ["class_name"])
    supplier_summary = summarize(sku_df, ["supplier_id", "supplier_name", "srm"])
    discount_summary = build_discount_buckets(sku_df)
    baseline_tier_summary, quantiles = build_baseline_tiers(sku_df)
    sku_df.to_csv(args.out / "bedding_member_monday_sku_data.csv", index=False)
    class_summary.to_csv(args.out / "class_summary.csv", index=False)
    supplier_summary.to_csv(args.out / "supplier_summary.csv", index=False)
    discount_summary.to_csv(args.out / "discount_bucket_summary.csv", index=False)
    baseline_tier_summary.to_csv(args.out / "baseline_success_tier_summary.csv", index=False)
    with pd.ExcelWriter(args.out / "bedding_member_monday_case_study.xlsx") as writer:
        metric_definitions().to_excel(writer, sheet_name="Metric Definitions", index=False)
        sku_df.to_excel(writer, sheet_name="SKU Data", index=False)
        class_summary.to_excel(writer, sheet_name="Class Summary", index=False)
        supplier_summary.to_excel(writer, sheet_name="Supplier Summary", index=False)
        discount_summary.to_excel(writer, sheet_name="Discount Buckets", index=False)
        baseline_tier_summary.to_excel(writer, sheet_name="Baseline Tiers", index=False)
    plt.style.use("seaborn-v0_8-whitegrid")
    save_grouped_sales_chart(class_summary, "class_name", "Daily avg sales vs. loyalty sales by class", charts_dir / "class_sales_lift.png")
    save_grouped_sales_chart(discount_summary, "discount_bucket", "Daily avg sales vs. loyalty sales by discount bucket", charts_dir / "discount_bucket_lift.png")
    save_lift_bar_chart(baseline_tier_summary, "baseline_success_tier", "Weighted lift by normal-success baseline tier", charts_dir / "baseline_success_tier_lift.png")
    save_supplier_chart(supplier_summary, charts_dir / "supplier_lift_vs_investment.png")
    save_top_incremental_chart(supplier_summary, charts_dir / "top_supplier_incremental_sales.png")
    write_report(args.out, sku_df, class_summary, supplier_summary, discount_summary, baseline_tier_summary, quantiles)
    print(f"Rows extracted: {len(sku_df)}")
    print("Detail total:", fmt_currency_2(float(sku_df["non_promo_avg"].sum())), fmt_currency_2(float(sku_df["loyalty_avg"].sum())))
    print(f"Output written to {args.out}")


if __name__ == "__main__":
    main()
