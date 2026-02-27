#!/usr/bin/env bash
set -euo pipefail

# Create a password key file for non-interactive cobo-tss-node operations
# Usage: setup-keyfile.sh --env <dev|prod> [--dir DIR] [--password PASSWORD]

source "$(dirname "$0")/env-common.sh"

PASSWORD=""
FORCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -lt 2 || "$2" == --* ]] && echo "❌ --env requires a value" && exit 1
      ENV="$2"; shift 2 ;;
    --dir)
      [[ $# -lt 2 || "$2" == --* ]] && echo "❌ --dir requires a value" && exit 1
      DIR="$2"; shift 2 ;;
    --password)
      [[ $# -lt 2 || "$2" == --* ]] && echo "❌ --password requires a value" && exit 1
      PASSWORD="$2"; shift 2 ;;
    --force)    FORCE="yes"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "${ENV:-}" ]]; then
  echo "❌ --env is required (dev, prod, or test)"
  exit 1
fi
[[ -z "${DIR:-}" ]] && DIR=$(env_default_dir "$ENV")

KEYFILE="$DIR/.password"

if [[ -f "$KEYFILE" && -z "$FORCE" ]]; then
  echo "⚠️  Key file already exists: $KEYFILE"
  if [[ -t 0 ]]; then
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
  else
    echo "   Use --force to overwrite in non-interactive mode"
    exit 1
  fi
fi

mkdir -p "$DIR"

if [[ -z "$PASSWORD" ]]; then
  PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  echo "🔑 Generated random password"
fi

printf '%s' "$PASSWORD" > "$KEYFILE"
chmod 600 "$KEYFILE"

echo "✅ Key file created: $KEYFILE (mode 600, env: $ENV)"
echo "⚠️  Back up this file securely — losing it means losing access to your TSS Node database"
