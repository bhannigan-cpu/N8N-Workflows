#!/usr/bin/env python3
"""Build a Member Pop-Up Sale case study from the exported CSV."""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


DEFAULT_CSV = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/"
    "Member_Pop_Up_Sale_-_Sheet1_a9b3.csv"
)
OUTPUT_DIR = Path("/workspace/analysis/member_pop_up_sale_case_study/output")
DISCOUNT_BUCKET_LABELS = ["<10%", "10-14.9%", "15-19.9%", "20-24.9%", "25%+"]


def parse_currency(value: object) -> float:
    if value is None or pd.isna(value):
        return 0.0
    text = str(value).replace("$", "").replace(",", "").strip()
    return float(text) if text else 0.0


def parse_percent(value: object) -> float | None:
    if value is None or pd.isna(value):
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", str(value))
    if not match:
        return None
    return float(match.group(0)) / 100.0


def fmt_currency(value: float) -> str:
    return f"${value:,.0f}"


def fmt_currency_2(value: float) -> str:
    return f"${value:,.2f}"


def fmt_pct(value: float | None, digits: int = 1) -> str:
    if value is None or pd.isna(value):
        return "n/a"
    return f"{value * 100:.{digits}f}%"


def read_displayed_total(csv_path: Path) -> dict[str, float]:
    with csv_path.open(newline="") as handle:
        row = next(csv.reader(handle))
    return {
        "non_promo_daily_avg": parse_currency(row[8]),
        "member_pop_up_sales": parse_currency(row[9]),
        "weighted_lift_pct": parse_percent(row[10]) or 0.0,
    }


def load_sku_data(csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(csv_path, skiprows=2, dtype=str)
    df = df[df["SKU"].notna() & df["Marketing Category SKU"].notna()].copy()
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
            "Non Promo Daily Avg": "non_promo_daily_avg",
            "Member Monday Daily Avg": "member_pop_up_sales",
            "Lift": "lift_pct",
        }
    )
    df["discount_pct"] = df["discount_pct"].map(parse_percent)
    df["lift_pct"] = df["lift_pct"].map(parse_percent)
    df["non_promo_daily_avg"] = df["non_promo_daily_avg"].map(parse_currency)
    df["member_pop_up_sales"] = df["member_pop_up_sales"].map(parse_currency)
    needs_lift = df["lift_pct"].isna() & (df["non_promo_daily_avg"] > 0)
    df.loc[needs_lift, "lift_pct"] = (
        df.loc[needs_lift, "member_pop_up_sales"]
        - df.loc[needs_lift, "non_promo_daily_avg"]
    ) / df.loc[needs_lift, "non_promo_daily_avg"]
    df["incremental_sales"] = df["member_pop_up_sales"] - df["non_promo_daily_avg"]
    df["active_on_event"] = df["member_pop_up_sales"] > 0
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
    for keys, group in df.groupby(group_cols, dropna=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        baseline = float(group["non_promo_daily_avg"].sum())
        sales = float(group["member_pop_up_sales"].sum())
        incremental = sales - baseline
        weighted_lift = incremental / baseline if baseline else None
        sku_count = int(group["sku"].nunique())
        active_skus = int(group.loc[group["active_on_event"], "sku"].nunique())
        positive_skus = int(group.loc[group["positive_lift"], "sku"].nunique())
        weighted_discount = weighted_avg(group["discount_pct"], group["non_promo_daily_avg"])
        records.append(
            {
                **dict(zip(group_cols, keys, strict=True)),
                "sku_count": sku_count,
                "active_skus": active_skus,
                "positive_lift_skus": positive_skus,
                "positive_lift_sku_rate": positive_skus / sku_count if sku_count else None,
                "non_promo_daily_avg": baseline,
                "member_pop_up_sales": sales,
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
    return pd.DataFrame(records).sort_values(
        ["member_pop_up_sales", "incremental_sales"], ascending=False
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


def save_grouped_sales_chart(summary: pd.DataFrame, label_col: str, title: str, out: Path, top_n: int | None = None) -> None:
    plot_df = summary.copy()
    if top_n:
        plot_df = plot_df.head(top_n)
    plot_df = plot_df.sort_values("member_pop_up_sales", ascending=False)
    x_positions = list(range(len(plot_df)))
    width = 0.36
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar(
        [idx - width / 2 for idx in x_positions],
        plot_df["non_promo_daily_avg"],
        width=width,
        label="Non-promo daily avg",
        color="#9b7ce3",
    )
    ax.bar(
        [idx + width / 2 for idx in x_positions],
        plot_df["member_pop_up_sales"],
        width=width,
        label="Member Pop-Up Sale",
        color="#4b347f",
    )
    ax.set_xticks(x_positions, plot_df[label_col].astype(str), rotation=25, ha="right")
    ax.set_ylabel("Sales dollars")
    ax.set_title(title)
    ax.yaxis.set_major_formatter(lambda y, _pos: f"${y:,.0f}")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, 1.12), ncol=2, frameon=False)
    max_sales = max(plot_df["member_pop_up_sales"].max(), plot_df["non_promo_daily_avg"].max())
    for idx, row in enumerate(plot_df.itertuples()):
        ax.text(
            idx,
            max(row.member_pop_up_sales, row.non_promo_daily_avg) + max_sales * 0.025,
            fmt_pct(row.weighted_lift_pct),
            ha="center",
            va="bottom",
            fontsize=8,
        )
    ax.set_ylim(0, max_sales * 1.25)
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
    plot_df = supplier_summary[
        (supplier_summary["non_promo_daily_avg"] > 0)
        & supplier_summary["weighted_discount_pct"].notna()
        & supplier_summary["weighted_lift_pct"].notna()
    ].copy()
    plot_df = plot_df.sort_values("member_pop_up_sales", ascending=False).head(14)
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
    ax.set_xlabel("Incremental Member Pop-Up Sale sales dollars")
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
    for col in ["non_promo_daily_avg", "member_pop_up_sales", "incremental_sales"]:
        formatted[col] = formatted[col].map(fmt_currency_2)
    for col in ["weighted_lift_pct", "weighted_discount_pct", "positive_lift_sku_rate"]:
        if col in formatted:
            formatted[col] = formatted[col].map(fmt_pct)
    return formatted


def metric_definitions() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {"metric": "sku_count", "definition": "Count of unique participating SKUs."},
            {"metric": "active_skus", "definition": "Count of participating SKUs with more than $0 in Member Pop-Up Sale sales."},
            {"metric": "positive_lift_skus", "definition": "Count of SKUs where Member Pop-Up Sale sales exceeded non-promo daily average sales."},
            {"metric": "weighted_lift_pct", "definition": "Incremental sales divided by non-promo daily average sales."},
            {"metric": "weighted_discount_pct", "definition": "Discount weighted by non-promo daily average sales."},
            {"metric": "lift_per_discount_point", "definition": "Weighted lift divided by weighted discount; an efficiency indicator, not dollar ROI."},
        ]
    )


def write_report(out_dir: Path, sku_df: pd.DataFrame, displayed_total: dict[str, float], marketing_summary: pd.DataFrame, class_summary: pd.DataFrame, supplier_summary: pd.DataFrame, discount_summary: pd.DataFrame) -> None:
    baseline = displayed_total["non_promo_daily_avg"]
    sales = displayed_total["member_pop_up_sales"]
    lift = displayed_total["weighted_lift_pct"]
    incremental = sales - baseline
    extracted_baseline = float(sku_df["non_promo_daily_avg"].sum())
    extracted_sales = float(sku_df["member_pop_up_sales"].sum())
    active_skus = int(sku_df.loc[sku_df["active_on_event"], "sku"].nunique())
    positive_skus = int(sku_df.loc[sku_df["positive_lift"], "sku"].nunique())
    total_skus = int(sku_df["sku"].nunique())
    weighted_discount = weighted_avg(sku_df["discount_pct"], sku_df["non_promo_daily_avg"])
    meaningful_categories = marketing_summary[
        (marketing_summary["weighted_lift_pct"].notna())
        & (marketing_summary["member_pop_up_sales"] >= 100)
    ]
    if meaningful_categories.empty:
        meaningful_categories = marketing_summary[marketing_summary["weighted_lift_pct"].notna()]
    best_category = meaningful_categories.sort_values("weighted_lift_pct", ascending=False).iloc[0]
    biggest_category = marketing_summary.sort_values("member_pop_up_sales", ascending=False).iloc[0]
    best_supplier = supplier_summary[supplier_summary["incremental_sales"] > 0].sort_values("incremental_sales", ascending=False).iloc[0]
    marketing_table = format_report_table(marketing_summary)
    class_table = format_report_table(class_summary.sort_values("member_pop_up_sales", ascending=False))
    supplier_table = format_report_table(supplier_summary.sort_values("incremental_sales", ascending=False))
    discount_table = format_report_table(discount_summary)
    report = f"""# Member Pop-Up Sale Loyalty Lift Case Study

## Executive takeaway

The Member Pop-Up Sale generated **{fmt_currency_2(sales)}** in event sales versus a recent non-promo daily average of **{fmt_currency_2(baseline)}**, creating **{fmt_currency_2(incremental)} in incremental sales** and **{fmt_pct(lift)} weighted lift**.

**Data QA note:** The displayed CSV total is used for the headline. Cleaned SKU-detail rows sum to {fmt_currency_2(extracted_baseline)} baseline sales and {fmt_currency_2(extracted_sales)} event sales.

## What changed during the Member Pop-Up Sale

- **Overall lift:** {fmt_pct(lift)}
- **Incremental sales:** {fmt_currency_2(incremental)}
- **Participation breadth:** {active_skus} of {total_skus} participating SKUs recorded event sales; {positive_skus} SKUs generated positive incremental dollars.
- **Weighted supplier investment:** {fmt_pct(weighted_discount)} average discount, weighted by recent non-promo daily average.
- **Largest marketing category by event sales:** {biggest_category.marketing_category} with {fmt_currency_2(biggest_category.member_pop_up_sales)}.
- **Best marketing category by lift:** {best_category.marketing_category} at {fmt_pct(best_category.weighted_lift_pct)}.

![Marketing category sales lift](charts/marketing_category_sales_lift.png)

## Marketing-category insights

{markdown_table(marketing_table, ["marketing_category", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_daily_avg", "member_pop_up_sales", "incremental_sales", "weighted_lift_pct"], limit=15)}

![Discount bucket lift](charts/discount_bucket_lift.png)

## Promotional investment vs. lift

{markdown_table(discount_table, ["discount_bucket", "sku_count", "weighted_discount_pct", "non_promo_daily_avg", "member_pop_up_sales", "incremental_sales", "weighted_lift_pct"])}

![Supplier lift vs investment](charts/supplier_lift_vs_investment.png)

## Supplier-level insights

{markdown_table(supplier_table, ["supplier_name", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_daily_avg", "member_pop_up_sales", "incremental_sales", "weighted_lift_pct"], limit=15)}

## Supplier success stories

The largest incremental supplier win was **{best_supplier.supplier_name}**, with **{fmt_currency_2(best_supplier.incremental_sales)}** in incremental sales and **{fmt_pct(best_supplier.weighted_lift_pct)}** weighted lift.

![Top incremental supplier gains](charts/top_supplier_incremental_sales.png)

## Class-level support detail

{markdown_table(class_table, ["class_name", "sku_count", "active_skus", "positive_lift_sku_rate", "weighted_discount_pct", "non_promo_daily_avg", "member_pop_up_sales", "incremental_sales", "weighted_lift_pct"], limit=20)}

## Files generated

- `member_pop_up_sale_sku_data.csv`: cleaned SKU-level extract.
- `marketing_category_summary.csv`: marketing-category performance.
- `class_summary.csv`: class-level performance.
- `supplier_summary.csv`: supplier-level performance.
- `discount_bucket_summary.csv`: lift by discount-investment bucket.
- `member_pop_up_sale_case_study.xlsx`: workbook with all summary tabs.
- `charts/*.png`: visual assets for supplier-facing materials.
"""
    (out_dir / "Member_Pop_Up_Sale_Loyalty_Lift_Case_Study.md").write_text(report)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--out", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    charts_dir = args.out / "charts"
    charts_dir.mkdir(parents=True, exist_ok=True)

    displayed_total = read_displayed_total(args.csv)
    sku_df = load_sku_data(args.csv)
    marketing_summary = summarize(sku_df, ["marketing_category"])
    class_summary = summarize(sku_df, ["class_name"])
    supplier_summary = summarize(sku_df, ["supplier_id", "supplier_name", "srm"])
    discount_summary = build_discount_buckets(sku_df)

    sku_df.to_csv(args.out / "member_pop_up_sale_sku_data.csv", index=False)
    marketing_summary.to_csv(args.out / "marketing_category_summary.csv", index=False)
    class_summary.to_csv(args.out / "class_summary.csv", index=False)
    supplier_summary.to_csv(args.out / "supplier_summary.csv", index=False)
    discount_summary.to_csv(args.out / "discount_bucket_summary.csv", index=False)

    with pd.ExcelWriter(args.out / "member_pop_up_sale_case_study.xlsx") as writer:
        metric_definitions().to_excel(writer, sheet_name="Metric Definitions", index=False)
        sku_df.to_excel(writer, sheet_name="SKU Data", index=False)
        marketing_summary.to_excel(writer, sheet_name="Marketing Summary", index=False)
        class_summary.to_excel(writer, sheet_name="Class Summary", index=False)
        supplier_summary.to_excel(writer, sheet_name="Supplier Summary", index=False)
        discount_summary.to_excel(writer, sheet_name="Discount Buckets", index=False)

    plt.style.use("seaborn-v0_8-whitegrid")
    save_grouped_sales_chart(marketing_summary, "marketing_category", "Daily avg sales vs. Member Pop-Up Sale sales by marketing category", charts_dir / "marketing_category_sales_lift.png", top_n=12)
    save_grouped_sales_chart(class_summary, "class_name", "Daily avg sales vs. Member Pop-Up Sale sales by class", charts_dir / "class_sales_lift.png", top_n=12)
    save_grouped_sales_chart(discount_summary, "discount_bucket", "Daily avg sales vs. Member Pop-Up Sale sales by discount bucket", charts_dir / "discount_bucket_lift.png")
    save_supplier_chart(supplier_summary, charts_dir / "supplier_lift_vs_investment.png")
    save_top_incremental_chart(supplier_summary, charts_dir / "top_supplier_incremental_sales.png")
    write_report(args.out, sku_df, displayed_total, marketing_summary, class_summary, supplier_summary, discount_summary)

    print(f"Rows extracted: {len(sku_df)}")
    print("Displayed total:", fmt_currency_2(displayed_total["non_promo_daily_avg"]), fmt_currency_2(displayed_total["member_pop_up_sales"]), fmt_pct(displayed_total["weighted_lift_pct"], digits=2))
    print("Detail total:", fmt_currency_2(float(sku_df["non_promo_daily_avg"].sum())), fmt_currency_2(float(sku_df["member_pop_up_sales"].sum())))
    print(f"Output written to {args.out}")


if __name__ == "__main__":
    main()
