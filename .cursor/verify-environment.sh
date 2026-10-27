#!/usr/bin/env bash
set -euo pipefail

export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/workspace/.npm-global}"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
export N8N_USER_FOLDER="${N8N_USER_FOLDER:-/workspace/.n8n-data}"
export N8N_HOST="${N8N_HOST:-127.0.0.1}"
export N8N_PORT="${N8N_PORT:-5678}"

echo "== Workflow JSON validation =="
for f in /workspace/*.json; do
  [[ -f "$f" ]] || continue
  jq -e '.name and (.nodes | length > 0)' "$f" >/dev/null
done

echo "== n8n health =="
for _ in $(seq 1 60); do
  if curl -fsS "http://${N8N_HOST}:${N8N_PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS "http://${N8N_HOST}:${N8N_PORT}/healthz"
echo

echo "== Imported workflows =="
n8n list:workflow

echo "== Execute manual-trigger workflow (first node only may fail on external creds) =="
WF_ID="$(n8n list:workflow | awk -F'|' '$2=="Loyalty Promo WSC Lift" { print $1; exit }')"
if [[ -n "$WF_ID" && "$WF_ID" != "null" ]]; then
  echo "Found workflow id: $WF_ID"
  # Dry run: confirm workflow is registered; full execute needs GCP/Gmail credentials.
  n8n export:workflow --id="$WF_ID" --output=/tmp/loyalty-export.json
  jq -e 'if type == "array" then .[0].name else .name end | . == "Loyalty Promo WSC Lift"' /tmp/loyalty-export.json >/dev/null
  echo "Round-trip export OK for Loyalty Promo WSC Lift"
else
  echo "Loyalty Promo WSC Lift not found in n8n database" >&2
  exit 1
fi

echo "Environment verification passed."
