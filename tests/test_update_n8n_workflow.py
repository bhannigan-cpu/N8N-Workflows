import copy
import unittest

from tools.update_n8n_workflow import (
    EditSpecError,
    add_connection,
    apply_edit_spec,
    remove_connection,
    summarize_changes,
    validate_workflow,
)


def sample_workflow():
    return {
        "name": "Sample Workflow",
        "nodes": [
            {
                "id": "1",
                "name": "Schedule Trigger",
                "type": "n8n-nodes-base.scheduleTrigger",
                "parameters": {"rule": {"interval": [{"triggerAtHour": 10}]}},
            },
            {
                "id": "2",
                "name": "Code",
                "type": "n8n-nodes-base.code",
                "parameters": {"jsCode": "return [{ json: { subject: 'Weekly Action Items' } }];"},
            },
            {
                "id": "3",
                "name": "Send Email",
                "type": "n8n-nodes-base.gmail",
                "parameters": {"sendTo": "old@example.com"},
            },
        ],
        "connections": {
            "Schedule Trigger": {
                "main": [[{"node": "Code", "type": "main", "index": 0}]],
            },
            "Code": {
                "main": [[{"node": "Send Email", "type": "main", "index": 0}]],
            },
        },
    }


class UpdateN8NWorkflowTests(unittest.TestCase):
    def test_update_node_parameters_sets_nested_values(self):
        workflow = sample_workflow()
        updated, _ = apply_edit_spec(
            workflow,
            {
                "operations": [
                    {
                        "op": "updateNodeParameters",
                        "nodeName": "Schedule Trigger",
                        "changes": {"rule.interval[0].triggerAtHour": 8},
                    }
                ]
            },
        )

        hour = updated["nodes"][0]["parameters"]["rule"]["interval"][0]["triggerAtHour"]
        self.assertEqual(hour, 8)

    def test_replace_in_node_string_updates_code(self):
        workflow = sample_workflow()
        updated, _ = apply_edit_spec(
            workflow,
            {
                "operations": [
                    {
                        "op": "replaceInNodeString",
                        "nodeName": "Code",
                        "path": "parameters.jsCode",
                        "search": "Weekly Action Items",
                        "replace": "Supplier Digest",
                    }
                ]
            },
        )

        js_code = updated["nodes"][1]["parameters"]["jsCode"]
        self.assertIn("Supplier Digest", js_code)
        self.assertNotIn("Weekly Action Items", js_code)

    def test_connection_helpers_add_and_remove_links(self):
        workflow = sample_workflow()
        updated = copy.deepcopy(workflow)

        add_connection(
            updated,
            from_node="Schedule Trigger",
            to_node="Send Email",
            output_index=0,
            input_index=0,
        )
        self.assertIn(
            {"node": "Send Email", "type": "main", "index": 0},
            updated["connections"]["Schedule Trigger"]["main"][0],
        )

        remove_connection(
            updated,
            from_node="Schedule Trigger",
            to_node="Send Email",
            output_index=0,
            input_index=0,
        )
        self.assertNotIn(
            {"node": "Send Email", "type": "main", "index": 0},
            updated["connections"]["Schedule Trigger"]["main"][0],
        )

    def test_validate_workflow_rejects_duplicate_node_names(self):
        workflow = sample_workflow()
        workflow["nodes"][2]["name"] = "Code"
        with self.assertRaises(Exception):
            validate_workflow(workflow)

    def test_apply_edit_spec_raises_for_unknown_node(self):
        workflow = sample_workflow()
        with self.assertRaises(EditSpecError):
            apply_edit_spec(
                workflow,
                {
                    "operations": [
                        {
                            "op": "setNodeValue",
                            "nodeName": "Missing Node",
                            "path": "parameters.subject",
                            "value": "Nope",
                        }
                    ]
                },
            )

    def test_summarize_changes_reports_node_updates(self):
        before = sample_workflow()
        after = copy.deepcopy(before)
        after["name"] = "Updated Sample Workflow"
        after["nodes"][2]["parameters"]["sendTo"] = "new@example.com"

        summary = summarize_changes(before, after)
        self.assertTrue(any("Renamed workflow" in item for item in summary))
        self.assertTrue(any('Updated node "Send Email"' in item for item in summary))


if __name__ == "__main__":
    unittest.main()
