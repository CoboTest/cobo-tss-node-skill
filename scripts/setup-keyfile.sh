#!/usr/bin/env bash
set -euo pipefail

# Create a password key file for non-interactive cobo-tss-node operations
# Usage: setup-keyfile.sh --env <dev|prod> [--dir DIR] [--password PASSWORD]

source "$(dirname "$0")/env-common.sh"

PASSWORD=""
parse_env_args "$@"
for arg in "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"; do
  case "$arg" in
    --password) PASSWORD="${EXTRA_ARGS[1]}" ;;
  esac
done

KEYFILE="$DIR/.password"

if [[ -f "$KEYFILE" ]]; then
  echo "⚠️  Key file already exists: $KEYFILE"
  read -p "Overwrite? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
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
