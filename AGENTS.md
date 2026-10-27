# AGENTS.md

## Cursor Cloud specific instructions

This repository is not a traditional buildable app. It contains an **n8n workflow export**
(`Weekly Supplier Report.json`) and a saved Cursor chat (`N8N output issues _ Cursor.html`).
The "application" is **n8n**; developing here means importing, editing, and running this
workflow in a local n8n instance.

### Environment
- n8n is installed globally by the update script (`npm install -g n8n`).
- npm's global prefix is set to `~/.npm-global` and `~/.npm-global/bin` is added to `PATH`
  via `~/.bashrc` (the default system npm prefix `/` is not writable). New shells pick this
  up automatically; if `n8n` is not found, run `export PATH="$HOME/.npm-global/bin:$PATH"`.
- n8n state (SQLite DB, encryption key) lives in `~/.n8n`.

### Running
- Start the editor: `n8n start` → opens at http://localhost:5678.
- First run requires creating an owner account through the web UI (any email/password works
  locally, e.g. `dev@example.com` / `N8nDevPass1`).
- Import the workflow: `n8n import:workflow --input="Weekly Supplier Report.json"`. This works
  even while the server is running (SQLite upserts by the workflow `id`); reload the editor
  page to see re-imported changes.

### Testing workflow logic without credentials
The workflow's live nodes need Google BigQuery, Google Sheets, and Gmail credentials, which
are **not** provided in this environment. To exercise the report logic (which lives in the
`Code` nodes such as `Sales Buckets`, `Prepare for Sheets`, and the email builders) without
credentials, **pin sample data** onto an upstream node (e.g. `WSC/GRS Movers`) and then
"Execute step" on the downstream `Code` node. Pinned data can be added by editing the
workflow JSON's `pinData` section and re-importing.
