#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-wf-gcp-us-ae-eunarta-proc-prod}"
SKU_TABLE="${SKU_TABLE:-wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku}"
SKU_COLUMN="${SKU_COLUMN:-prsku}"
CATEGORY_COLUMN="${CATEGORY_COLUMN:-productmarketingcategory}"
LAUNCH_DATE_COLUMN="${LAUNCH_DATE_COLUMN:-launchdate}"
PRODUCT_NAME_COLUMN="${PRODUCT_NAME_COLUMN:-}"
DAYS="${DAYS:-7}"
CATEGORY="${CATEGORY:-Bedding}"
FORMAT="${FORMAT:-pretty}"

usage() {
  cat <<'USAGE'
List SKUs launched in the Bedding product marketing category over the last N days.

Usage:
  scripts/list_bedding_sku_launches.sh [options]

Options:
  -d, --days DAYS                  Lookback window in days, including today. Default: 7
      --category CATEGORY          Product marketing category value. Default: Bedding
      --project-id PROJECT_ID      BigQuery execution project.
                                   Default: wf-gcp-us-ae-eunarta-proc-prod
      --sku-table TABLE            Fully-qualified SKU dimension table.
                                   Default: wf-gcp-us-ae-retail-prod.cm_reporting.retail_dim_sku
      --sku-column COLUMN          SKU identifier column. Default: prsku
      --category-column COLUMN     Product marketing category column.
                                   Default: productmarketingcategory
      --launch-date-column COLUMN  SKU launch date column. Default: launchdate
      --product-name-column COLUMN Optional product name/title column to include.
      --format FORMAT              bq output format: pretty, csv, json, prettyjson, etc.
                                   Default: pretty
  -h, --help                       Show this help text.

Environment variables with the same uppercase names can also be used, for example:
  DAYS=14 SKU_TABLE=project.dataset.table scripts/list_bedding_sku_launches.sh

Before first use, confirm the exact SKU table and column names in BigQuery. If your
catalog table uses different names, pass them with the options above.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2-}"

  [[ -n "$value" && "$value" != --* ]] || die "$option requires a value"
}

validate_days() {
  [[ "$DAYS" =~ ^[1-9][0-9]*$ ]] || die "--days must be a positive integer"
}

validate_table() {
  [[ "$SKU_TABLE" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_]+\.[A-Za-z0-9_$-]+$ ]] \
    || die "--sku-table must be a fully-qualified table in project.dataset.table format"
}

validate_column_path() {
  local label="$1"
  local value="$2"

  [[ -n "$value" ]] || die "$label cannot be empty"
  [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]] \
    || die "$label must be a column name or dot-delimited field path"
}

quote_column_path() {
  local path="$1"
  local quoted=""
  local segment
  IFS='.' read -ra segments <<<"$path"

  for segment in "${segments[@]}"; do
    if [[ -n "$quoted" ]]; then
      quoted+="."
    fi
    quoted+="\`${segment}\`"
  done

  printf '%s' "$quoted"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--days)
      require_value "$1" "${2-}"
      DAYS="${2:-}"
      shift 2
      ;;
    --category)
      require_value "$1" "${2-}"
      CATEGORY="${2:-}"
      shift 2
      ;;
    --project-id)
      require_value "$1" "${2-}"
      PROJECT_ID="${2:-}"
      shift 2
      ;;
    --sku-table)
      require_value "$1" "${2-}"
      SKU_TABLE="${2:-}"
      shift 2
      ;;
    --sku-column)
      require_value "$1" "${2-}"
      SKU_COLUMN="${2:-}"
      shift 2
      ;;
    --category-column)
      require_value "$1" "${2-}"
      CATEGORY_COLUMN="${2:-}"
      shift 2
      ;;
    --launch-date-column)
      require_value "$1" "${2-}"
      LAUNCH_DATE_COLUMN="${2:-}"
      shift 2
      ;;
    --product-name-column)
      require_value "$1" "${2-}"
      PRODUCT_NAME_COLUMN="${2:-}"
      shift 2
      ;;
    --format)
      require_value "$1" "${2-}"
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v bq >/dev/null 2>&1 || die "the Google Cloud bq CLI is required"

validate_days
validate_table
validate_column_path "--sku-column" "$SKU_COLUMN"
validate_column_path "--category-column" "$CATEGORY_COLUMN"
validate_column_path "--launch-date-column" "$LAUNCH_DATE_COLUMN"

[[ -n "$CATEGORY" ]] || die "--category cannot be empty"
[[ -n "$PROJECT_ID" ]] || die "--project-id cannot be empty"
[[ -n "$FORMAT" ]] || die "--format cannot be empty"

SKU_EXPR="$(quote_column_path "$SKU_COLUMN")"
CATEGORY_EXPR="$(quote_column_path "$CATEGORY_COLUMN")"
LAUNCH_DATE_EXPR="$(quote_column_path "$LAUNCH_DATE_COLUMN")"

PRODUCT_NAME_SELECT=""
PRODUCT_NAME_OUTPUT=""
if [[ -n "$PRODUCT_NAME_COLUMN" ]]; then
  validate_column_path "--product-name-column" "$PRODUCT_NAME_COLUMN"
  PRODUCT_NAME_EXPR="$(quote_column_path "$PRODUCT_NAME_COLUMN")"
  PRODUCT_NAME_SELECT="    CAST(sku.${PRODUCT_NAME_EXPR} AS STRING) AS product_name,"
  PRODUCT_NAME_OUTPUT="  product_name,"
fi

bq query \
  --project_id="$PROJECT_ID" \
  --use_legacy_sql=false \
  --format="$FORMAT" \
  --parameter="days_back:INT64:${DAYS}" \
  --parameter="marketing_category:STRING:${CATEGORY}" <<SQL
WITH params AS (
  SELECT
    DATE_SUB(CURRENT_DATE(), INTERVAL (@days_back - 1) DAY) AS window_start,
    CURRENT_DATE() AS window_end
),

sku_launches AS (
  SELECT
    CAST(sku.${SKU_EXPR} AS STRING) AS sku,
${PRODUCT_NAME_SELECT}
    CAST(sku.${CATEGORY_EXPR} AS STRING) AS marketing_category,
    SAFE_CAST(sku.${LAUNCH_DATE_EXPR} AS DATE) AS launch_date
  FROM \`${SKU_TABLE}\` AS sku
)

SELECT DISTINCT
  sku,
${PRODUCT_NAME_OUTPUT}
  marketing_category,
  launch_date
FROM sku_launches
CROSS JOIN params
WHERE LOWER(TRIM(marketing_category)) = LOWER(TRIM(@marketing_category))
  AND launch_date BETWEEN params.window_start AND params.window_end
ORDER BY
  launch_date DESC,
  sku;
SQL
