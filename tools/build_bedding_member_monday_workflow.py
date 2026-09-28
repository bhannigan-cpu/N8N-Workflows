#!/usr/bin/env python3
"""Build the Bedding Member Monday / Loyalty Lift n8n workflow JSON."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "workflow_assets" / "bedding_member_monday_lift.sql"
ANALYSIS_PATH = ROOT / "workflow_assets" / "bedding_member_monday_analysis.js"
OUT = ROOT / "workflow_exports" / "bedding-member-monday-loyalty-lift.json"
ROOT_OUT = ROOT / "Bedding Member Monday Loyalty Lift.json"

INSTANCE_ID = "03eaefce1798e2883471ae7d5d2dfbc186343411ac19c565c97d8bae537d45f1"
BQ_CRED = {"id": "61aSuNTfPEjWsHyK", "name": "Google BigQuery account 352"}
GMAIL_CRED = {"id": "ZmmontG7EgaANggr", "name": "Gmail account 287"}
SHEETS_CRED = {"id": "eI9KdqVYqhKdz25D", "name": "Google Sheets account 610"}


def nid() -> str:
    return str(uuid.uuid4())


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip() + "\n"


def sheet_append_node(
    *,
    name: str,
    node_id: str,
    position: list[int],
    sheet_title: str,
    source_node: str,
) -> dict:
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


def build() -> dict:
    ids = {
        "manual": nid(),
        "bq": nid(),
        "analysis": nid(),
        "create": nid(),
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

    sql_query = load_text(SQL_PATH)
    analysis_js = load_text(ANALYSIS_PATH)

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
                "projectId": {
                    "__rl": True,
                    "value": "wf-gcp-us-ae-retail-prod",
                    "mode": "list",
                    "cachedResultName": "wf-gcp-us-ae-retail-prod",
                    "cachedResultUrl": "https://console.cloud.google.com/bigquery?project=wf-gcp-us-ae-retail-prod",
                },
                "sqlQuery": sql_query,
                "options": {},
            },
            "type": "n8n-nodes-base.googleBigQuery",
            "typeVersion": 2.1,
            "position": [260, 300],
            "id": ids["bq"],
            "name": "Pull Loyalty Lift SKUs",
            "credentials": {"googleBigQueryOAuth2Api": BQ_CRED},
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": analysis_js,
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [540, 300],
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
            "position": [820, 300],
            "id": ids["create"],
            "name": "Create Spreadsheet",
            "credentials": {"googleSheetsOAuth2Api": SHEETS_CRED},
        },
        {
            "parameters": {
                "mode": "runOnceForAllItems",
                "jsCode": expand_rows_code("sku_data"),
            },
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [1100, -60],
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
            "position": [1100, 80],
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
            "position": [1100, 220],
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
            "position": [1100, 360],
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
            "position": [1100, 500],
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
            "position": [1100, 640],
            "id": ids["baseline_rows"],
            "name": "Prepare Baseline Rows",
        },
        sheet_append_node(
            name="Append SKU Data",
            node_id=ids["append_sku"],
            position=[1380, -60],
            sheet_title="SKU Data",
            source_node="Prepare SKU Rows",
        ),
        sheet_append_node(
            name="Append Category Summary",
            node_id=ids["append_category"],
            position=[1380, 80],
            sheet_title="Category Summary",
            source_node="Prepare Category Rows",
        ),
        sheet_append_node(
            name="Append Class Summary",
            node_id=ids["append_class"],
            position=[1380, 220],
            sheet_title="Class Summary",
            source_node="Prepare Class Rows",
        ),
        sheet_append_node(
            name="Append Supplier Summary",
            node_id=ids["append_supplier"],
            position=[1380, 360],
            sheet_title="Supplier Summary",
            source_node="Prepare Supplier Rows",
        ),
        sheet_append_node(
            name="Append Discount Buckets",
            node_id=ids["append_discount"],
            position=[1380, 500],
            sheet_title="Discount Buckets",
            source_node="Prepare Discount Rows",
        ),
        sheet_append_node(
            name="Append Baseline Tiers",
            node_id=ids["append_baseline"],
            position=[1380, 640],
            sheet_title="Baseline Tiers",
            source_node="Prepare Baseline Rows",
        ),
        {
            "parameters": {
                "sendTo": "bhannigan@wayfair.com",
                "subject": "={{ $('Build Analysis').item.json.subject }}",
                "emailType": "html",
                "message": "={{ $('Build Analysis').item.json.emailHtml }}",
                "options": {},
            },
            "type": "n8n-nodes-base.gmail",
            "typeVersion": 2.2,
            "position": [1100, 820],
            "id": ids["gmail"],
            "name": "Send Case Study Email",
            "webhookId": nid(),
            "credentials": {"gmailOAuth2": GMAIL_CRED},
        },
    ]

    connections = {
        "Manual Trigger": {
            "main": [[{"node": "Pull Loyalty Lift SKUs", "type": "main", "index": 0}]]
        },
        "Pull Loyalty Lift SKUs": {
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
                    {"node": "Send Case Study Email", "type": "main", "index": 0},
                ]
            ]
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
        "name": "Bedding Member Monday Loyalty Lift",
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
    OUT.write_text(payload, encoding="utf-8")
    ROOT_OUT.write_text(payload, encoding="utf-8")
    print(f"Wrote {OUT}")
    print(f"Wrote {ROOT_OUT}")
    print(f"Nodes: {[node['name'] for node in workflow['nodes']]}")


if __name__ == "__main__":
    main()
