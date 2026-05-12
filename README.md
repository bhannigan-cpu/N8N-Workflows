# N8N workflow updater

This repo now includes a small CLI that can generate new N8N workflow JSON files from either:

- freeform edit suggestions, or
- a deterministic edit spec for common workflow changes.

The generated file is a normal N8N export that you can re-import into N8N.

## Files

- `tools/update_n8n_workflow.py` - main updater CLI
- `tests/test_update_n8n_workflow.py` - focused unit tests
- `examples/edit-spec.example.json` - sample deterministic change request

## 1) Freeform suggestions

This mode uses an OpenAI-compatible API and writes a new workflow export plus a summary file.

```bash
export OPENAI_API_KEY="your-api-key"

python tools/update_n8n_workflow.py \
  --input "Weekly Supplier Report.json" \
  --instructions "Change the schedule trigger to 8 AM UTC, update the email subject to Supplier Digest, and rename the workflow to Weekly Supplier Report REAL"
```

Optional environment variables:

- `OPENAI_BASE_URL` - override the default `https://api.openai.com/v1`
- `N8N_WORKFLOW_MODEL` - override the default model (`gpt-4.1-mini`)

Output:

- `generated-workflows/<input-name>__updated__<timestamp>.json`
- `generated-workflows/<input-name>__updated__<timestamp>.changes.md`

## 2) Deterministic edit specs

If you want predictable, reviewable edits without using an LLM, provide a JSON edit spec.

```bash
python tools/update_n8n_workflow.py \
  --input "Weekly Supplier Report.json" \
  --edit-spec "examples/edit-spec.example.json"
```

Supported edit operations:

- `renameWorkflow`
- `setWorkflowValue`
- `removeWorkflowValue`
- `setNodeValue`
- `removeNodeValue`
- `updateNodeParameters`
- `replaceInNodeString`
- `addConnection`
- `removeConnection`

## Edit spec shape

```json
{
  "summary": "Optional human-readable change note",
  "operations": [
    {
      "op": "updateNodeParameters",
      "nodeName": "Schedule Trigger",
      "changes": {
        "rule.interval[0].triggerAtHour": 8
      }
    }
  ]
}
```

### Common examples

Update a nested node parameter:

```json
{
  "op": "updateNodeParameters",
  "nodeName": "Schedule Trigger",
  "changes": {
    "rule.interval[0].triggerAtHour": 8
  }
}
```

Replace text inside a code node:

```json
{
  "op": "replaceInNodeString",
  "nodeName": "Code in JavaScript",
  "path": "parameters.jsCode",
  "search": "Weekly Supplier Performance Summary",
  "replace": "Supplier Digest"
}
```

Change a top-level node field:

```json
{
  "op": "setNodeValue",
  "nodeName": "Send a message1",
  "path": "parameters.subject",
  "value": "Supplier Digest"
}
```

Add a connection:

```json
{
  "op": "addConnection",
  "fromNode": "Prepare for Sheets",
  "toNode": "Code in JavaScript",
  "outputType": "main",
  "outputIndex": 0,
  "inputType": "main",
  "inputIndex": 0
}
```

## Importing back into N8N

1. Run the updater to generate a new `.json` file.
2. In N8N, choose **Import from File**.
3. Select the generated JSON file from `generated-workflows/`.
4. Review credentials and node mappings before activating the workflow.

## Running tests

```bash
python -m unittest discover -s tests
```
