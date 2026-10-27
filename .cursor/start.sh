#!/usr/bin/env bash
set -euo pipefail

export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/workspace/.npm-global}"
export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
export N8N_USER_FOLDER="${N8N_USER_FOLDER:-/workspace/.n8n-data}"
export N8N_HOST="${N8N_HOST:-0.0.0.0}"
export N8N_PORT="${N8N_PORT:-5678}"
export N8N_PROTOCOL="${N8N_PROTOCOL:-http}"
export N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE:-false}"
export N8N_DIAGNOSTICS_ENABLED="${N8N_DIAGNOSTICS_ENABLED:-false}"
export N8N_PERSONALIZATION_ENABLED="${N8N_PERSONALIZATION_ENABLED:-false}"
export N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS="${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS:-false}"
export N8N_RUNNERS_ENABLED="${N8N_RUNNERS_ENABLED:-true}"

mkdir -p "$N8N_USER_FOLDER"

if ! command -v n8n >/dev/null 2>&1; then
  echo "n8n is not installed; run .cursor/install.sh first" >&2
  exit 1
fi

exec n8n start
