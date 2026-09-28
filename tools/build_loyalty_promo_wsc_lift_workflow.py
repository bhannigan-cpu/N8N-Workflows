#!/usr/bin/env python3
"""Build the reusable Loyalty Promo WSC Lift n8n workflow JSON."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "workflow_assets" / "loyalty_promo_lift.sql"
BUILD_SQL_PATH = ROOT / "workflow_assets" / "loyalty_promo_lift_build_sql.js"
ANALYSIS_PATH = ROOT / "workflow_assets" / "loyalty_promo_lift_analysis.js"
PREPARE_EMAIL_PATH = ROOT / "workflow_assets" / "loyalty_promo_lift_prepare_email.js"
OUT = ROOT / "workflow_exports" / "loyalty-promo-wsc-lift.json"
ROOT_OUT = ROOT / "Loyalty Promo WSC Lift.json"
# Keep prior filename as a convenience alias for the same workflow.
LEGACY_OUT = ROOT / "Bedding Member Monday Loyalty Lift.json"
LEGACY_EXPORT = ROOT / "workflow_exports" / "bedding-member-monday-loyalty-lift.json"

INSTANCE_ID = "03eaefce1798e2883471ae7d5d2dfbc186343411ac19c565c97d8bae537d45f1"
BQ_CRED = {"id": "61aSuNTfPEjWsHyK", "name": "Google BigQuery account 352"}
GMAIL_CRED = {"id": "ZmmontG7EgaANggr", "name": "Gmail account 287"}
SHEETS_CRED = {"id": "eI9KdqVYqhKdz25D", "name": "Google Sheets account 610"}


def nid() -> str:
    return str(uuid.uuid4())


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def sheet_append_node(*, name: str, node_id: str, position: list[int], sheet_title: str) -> dict:
    return {
        "parameters": {
            "operation": "append",
            "documentId": {
                "__rl": True,
                "value": "={{ $('Create Spreadsheet').item.json.spreadsheetId }}",
                "mode": "id",
            },
            "sheetName": {
                "__rl": True,
                "value": sheet_title,
                "mode": "name",
            },
            "columns": {
                "mappingMode": "autoMapInputData",
                "value": {},
                "matchingColumns": [],
                "schema": [],
            },
            "options": {},
        },
        "type": "n8n-nodes-base.googleSheets",
        "typeVersion": 4.7,
        "position": position,
        "id": node_id,
        "name": name,
        "credentials": {"googleSheetsOAuth2Api": SHEETS_CRED},
    }


def expand_rows_code(array_key: str) -> str:
    return f"""const analysis = $('Build Analysis').first().json;
const rows = analysis.{array_key} || [];
if (!rows.length) {{
  // Returning no items skips the downstream Append node for this tab.
  return [];
}}
return rows.map((row) => ({{ json: row }}));
"""


def assignment(name: str, value, value_type: str) -> dict:
    return {
        "id": nid(),
        "name": name,
        "value": value,
        "type": value_type,
    }


def build_sql_code(sql_template: str) -> str:
    raw = load_text(BUILD_SQL_PATH)
    # Keep the builder JS readable in source control; inject SQL at build time.
    if "__SQL_TEMPLATE__" not in raw:
        raise ValueError("loyalty_promo_lift_build_sql.js is missing __SQL_TEMPLATE__ placeholder")
    # JSON-encode so backticks / escapes in SQL are safe inside the JS string literal.
    encoded = json.dumps(sql_template)
    return raw.replace(
        "const SQL_TEMPLATE = String.raw`__SQL_TEMPLATE__`;",
        f"const SQL_TEMPLATE = {encoded};",
    )


def build() -> dict:
    ids = {
        "manual": nid(),
        "configure": nid(),
        "build_sql": nid(),
        "bq": nid(),
        "analysis": nid(),
        "create": nid(),
        "prepare_email": nid(),
        "sku_rows": nid(),
        "class_rows": nid(),
        "supplier_rows": nid(),
        "discount_rows": nid(),
        "baseline_rows": nid(),
        "category_rows": nid(),
        "append_sku": nid(),
        "append_class": nid(),
        "append_supplier": nid(),
        "append_discount": nid(),
        "append_baseline": nid(),
        "append_category": nid(),
        "gmail": nid(),
    }

    sql_template = load_text(SQL_PATH)
    build_sql_js = build_sql_code(sql_template)
    analysis_js = load_text(ANALYSIS_PATH)
    prepare_email_js = load_text(PREPARE_EMAIL_PATH)

    nodes = [
        {
            "parameters": {},
            "type": "n8n-nodes-base.manualTrigger",
            "typeVersion": 1,
            "position": [0, 300],
            "id": ids["manual"],
            "name": "Manual Trigger",
        },
        {
            "parameters": {
                "mode": "manual",
                "duplicateItem": False,
                "assignments": {
                    "assignments": [
                        assignment("promo_period_id", 0, "number"),
                        assignment("product_marketing_category", "Bedding", "string"),
                        assignment("brand_catalog_id", 1, "number"),
                        assignment("brand_catalog_name", "Wayfair US", "string"),
                        assignment("store_brand", "Wayfair", "string"),
                        assignment("store_country", "United States", "string"),
                        assignment("l10_non_promo_days", 10, "number"),
                        assignment("promo_start_override", "", "string"),
                        assignment("promo_end_override", "", "string"),
                    ]
                },
                "options": {},
            },
            "type": "n8n-nodes-base.set",
            "typeVersion": 3.4,
            "position": [240, 300],
            "id": ids["configure"],
            "name": "Configure Inputs",
            "notesInFlow": True,
            "notes": (
                "EDIT THESE TWO FIRST for each loyalty event:\n"
                "1) promo_period_id — CPH / Partner Home promo period ID\n"
                "2) product_marketing_category — product mkcname "
                "(e.g. Bedding or Window), NOT supplier marketing category\n\n"
                "Optional:\n"
                "- l10_non_promo_days (default 10)\n"
                "- promo_start_override / promo_end_override as YYYY-MM-DD "
                "(leave blank to use promo period dates)\n\n"
                "L10 non-promo days auto-shift to the last N non-promo dates "
                "before the promo start (extended discounts / super rooms ignored)."
            ),
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": build_sql_js,
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [500, 300],
            "id": ids["build_sql"],
            "name": "Build SQL Query",
        },
        {
            "parameters": {
                "projectId": {
                    "__rl": True,
                    "value": "wf-gcp-us-ae-retail-prod",
                    "mode": "list",
                    "cachedResultName": "wf-gcp-us-ae-retail-prod",
                    "cachedResultUrl": "https://console.cloud.google.com/bigquery?project=wf-gcp-us-ae-retail-prod",
                },
                "sqlQuery": "={{ $json.sqlQuery }}",
                "options": {},
            },
            "type": "n8n-nodes-base.googleBigQuery",
            "typeVersion": 2.1,
            "position": [760, 300],
            "id": ids["bq"],
            "name": "Pull Loyalty WSC Lift SKUs",
            "credentials": {"googleBigQueryOAuth2Api": BQ_CRED},
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": analysis_js,
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1020, 300],
            "id": ids["analysis"],
            "name": "Build Analysis",
        },
        {
            "parameters": {
                "resource": "spreadsheet",
                "title": "={{ $json.spreadsheetTitle }}",
                "sheetsUi": {
                    "sheetValues": [
                        {"title": "SKU Data"},
                        {"title": "Category Summary"},
                        {"title": "Class Summary"},
                        {"title": "Supplier Summary"},
                        {"title": "Discount Buckets"},
                        {"title": "Baseline Tiers"},
                    ]
                },
                "options": {},
            },
            "type": "n8n-nodes-base.googleSheets",
            "typeVersion": 4.7,
            "position": [1280, 300],
            "id": ids["create"],
            "name": "Create Spreadsheet",
            "credentials": {"googleSheetsOAuth2Api": SHEETS_CRED},
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": prepare_email_js,
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 820],
            "id": ids["prepare_email"],
            "name": "Prepare Email With Sheet Link",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("sku_data"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, -60],
            "id": ids["sku_rows"],
            "name": "Prepare SKU Rows",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("category_summary"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 80],
            "id": ids["category_rows"],
            "name": "Prepare Category Rows",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("class_summary"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 220],
            "id": ids["class_rows"],
            "name": "Prepare Class Rows",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("supplier_summary"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 360],
            "id": ids["supplier_rows"],
            "name": "Prepare Supplier Rows",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("discount_summary"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 500],
            "id": ids["discount_rows"],
            "name": "Prepare Discount Rows",
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("baseline_summary"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1560, 640],
            "id": ids["baseline_rows"],
            "name": "Prepare Baseline Rows",
        },
        sheet_append_node(
            name="Append SKU Data",
            node_id=ids["append_sku"],
            position=[1840, -60],
            sheet_title="SKU Data",
        ),
        sheet_append_node(
            name="Append Category Summary",
            node_id=ids["append_category"],
            position=[1840, 80],
            sheet_title="Category Summary",
        ),
        sheet_append_node(
            name="Append Class Summary",
            node_id=ids["append_class"],
            position=[1840, 220],
            sheet_title="Class Summary",
        ),
        sheet_append_node(
            name="Append Supplier Summary",
            node_id=ids["append_supplier"],
            position=[1840, 360],
            sheet_title="Supplier Summary",
        ),
        sheet_append_node(
            name="Append Discount Buckets",
            node_id=ids["append_discount"],
            position=[1840, 500],
            sheet_title="Discount Buckets",
        ),
        sheet_append_node(
            name="Append Baseline Tiers",
            node_id=ids["append_baseline"],
            position=[1840, 640],
            sheet_title="Baseline Tiers",
        ),
        {
            "parameters": {
                "sendTo": "bhannigan@wayfair.com",
                "subject": "={{ $json.subject }}",
                "emailType": "html",
                "message": "={{ $json.emailHtml }}",
                "options": {},
            },
            "type": "n8n-nodes-base.gmail",
            "typeVersion": 2.2,
            "position": [1840, 820],
            "id": ids["gmail"],
            "name": "Send Case Study Email",
            "webhookId": nid(),
            "credentials": {"gmailOAuth2": GMAIL_CRED},
        },
    ]

    connections = {
        "Manual Trigger": {
            "main": [[{"node": "Configure Inputs", "type": "main", "index": 0}]]
        },
        "Configure Inputs": {
            "main": [[{"node": "Build SQL Query", "type": "main", "index": 0}]]
        },
        "Build SQL Query": {
            "main": [[{"node": "Pull Loyalty WSC Lift SKUs", "type": "main", "index": 0}]]
        },
        "Pull Loyalty WSC Lift SKUs": {
            "main": [[{"node": "Build Analysis", "type": "main", "index": 0}]]
        },
        "Build Analysis": {
            "main": [[{"node": "Create Spreadsheet", "type": "main", "index": 0}]]
        },
        "Create Spreadsheet": {
            "main": [
                [
                    {"node": "Prepare SKU Rows", "type": "main", "index": 0},
                    {"node": "Prepare Category Rows", "type": "main", "index": 0},
                    {"node": "Prepare Class Rows", "type": "main", "index": 0},
                    {"node": "Prepare Supplier Rows", "type": "main", "index": 0},
                    {"node": "Prepare Discount Rows", "type": "main", "index": 0},
                    {"node": "Prepare Baseline Rows", "type": "main", "index": 0},
                    {"node": "Prepare Email With Sheet Link", "type": "main", "index": 0},
                ]
            ]
        },
        "Prepare Email With Sheet Link": {
            "main": [[{"node": "Send Case Study Email", "type": "main", "index": 0}]]
        },
        "Prepare SKU Rows": {
            "main": [[{"node": "Append SKU Data", "type": "main", "index": 0}]]
        },
        "Prepare Category Rows": {
            "main": [[{"node": "Append Category Summary", "type": "main", "index": 0}]]
        },
        "Prepare Class Rows": {
            "main": [[{"node": "Append Class Summary", "type": "main", "index": 0}]]
        },
        "Prepare Supplier Rows": {
            "main": [[{"node": "Append Supplier Summary", "type": "main", "index": 0}]]
        },
        "Prepare Discount Rows": {
            "main": [[{"node": "Append Discount Buckets", "type": "main", "index": 0}]]
        },
        "Prepare Baseline Rows": {
            "main": [[{"node": "Append Baseline Tiers", "type": "main", "index": 0}]]
        },
    }

    return {
        "name": "Loyalty Promo WSC Lift",
        "nodes": nodes,
        "connections": connections,
        "active": False,
        "settings": {
            "executionOrder": "v1",
            "binaryMode": "separate",
            "availableInMCP": False,
        },
        "versionId": nid(),
        "meta": {
            "templateCredsSetupCompleted": True,
            "instanceId": INSTANCE_ID,
        },
        "tags": [],
        "pinData": {},
    }


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    workflow = build()
    payload = json.dumps(workflow, indent=2) + "\n"
    for path in (OUT, ROOT_OUT, LEGACY_OUT, LEGACY_EXPORT):
        path.write_text(payload, encoding="utf-8")
        print(f"Wrote {path}")
    print(f"Nodes: {[node['name'] for node in workflow['nodes']]}")


if __name__ == "__main__":
    main()
