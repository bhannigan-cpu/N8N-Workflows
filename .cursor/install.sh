#!/usr/bin/env bash
set -euo pipefail

cd /workspace

export N8N_USER_FOLDER="${N8N_USER_FOLDER:-/workspace/.n8n-data}"
export N8N_RUNNERS_ENABLED="${N8N_RUNNERS_ENABLED:-true}"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/workspace/.npm-global}"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
mkdir -p "$N8N_USER_FOLDER" "$NPM_CONFIG_PREFIX/bin"

if ! command -v n8n >/dev/null 2>&1; then
  npm install -g n8n@1.97.1
  sudo ln -sf "$NPM_CONFIG_PREFIX/bin/n8n" /usr/local/bin/n8n
fi

# Validate exported workflow JSON in the repo root (skip non-workflow JSON if added later).
shopt -s nullglob
workflow_files=(/workspace/*.json)
if ((${#workflow_files[@]} == 0)); then
  echo "No workflow JSON files found in /workspace" >&2
  exit 1
fi

for f in "${workflow_files[@]}"; do
  jq -e '.name and (.nodes | type == "array") and (.nodes | length > 0)' "$f" >/dev/null
  echo "Validated workflow JSON: $(basename "$f")"
done

# Import workflows on first install (build pod / fresh data dir). Re-import only when forced.
if [[ -f "$N8N_USER_FOLDER/.n8n/database.sqlite" && "${WORKFLOW_FORCE_REIMPORT:-}" != "1" ]]; then
  echo "n8n database already initialized; skipping workflow import (set WORKFLOW_FORCE_REIMPORT=1 to refresh)."
else
  for f in "${workflow_files[@]}"; do
    n8n import:workflow --input="$f"
    echo "Imported workflow: $(basename "$f")"
  done
fi

n8n list:workflow
