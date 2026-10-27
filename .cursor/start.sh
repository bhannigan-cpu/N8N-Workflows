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

# Dev instance owner (UI/API); password is for local Cloud Agent use only.
export N8N_INSTANCE_OWNER_MANAGED_BY_ENV="${N8N_INSTANCE_OWNER_MANAGED_BY_ENV:-true}"
export N8N_INSTANCE_OWNER_EMAIL="${N8N_INSTANCE_OWNER_EMAIL:-cursor-agent@localhost}"
export N8N_INSTANCE_OWNER_FIRST_NAME="${N8N_INSTANCE_OWNER_FIRST_NAME:-Cursor}"
export N8N_INSTANCE_OWNER_LAST_NAME="${N8N_INSTANCE_OWNER_LAST_NAME:-Agent}"
if [[ -z "${N8N_INSTANCE_OWNER_PASSWORD_HASH:-}" ]]; then
  export N8N_INSTANCE_OWNER_PASSWORD_HASH="$(
    node -e "const bcrypt=require('bcryptjs'); console.log(bcrypt.hashSync('CursorAgentDev1', 10));"
  )"
fi

mkdir -p "$N8N_USER_FOLDER"

if ! command -v n8n >/dev/null 2>&1; then
  echo "n8n is not installed; run .cursor/install.sh first" >&2
  exit 1
fi

exec n8n start
