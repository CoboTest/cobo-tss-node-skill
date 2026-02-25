#!/usr/bin/env bash
set -euo pipefail

# Show Cobo TSS Node info
# Usage: node-info.sh --env <dev|prod> [--dir DIR] [--group [GROUP_ID]]

source "$(dirname "$0")/env-common.sh"

GROUP=""
GROUP_ID=""

# Manual parse to handle --group with optional value
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --group)
      GROUP="yes"
      if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
        GROUP_ID="$2"; shift 2
      else
        shift
      fi
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$ENV" ]]; then
  echo "❌ --env is required (dev or prod)"
  exit 1
fi
[[ -z "$DIR" ]] && DIR=$(env_default_dir "$ENV")

BIN="$DIR/cobo-tss-node"
KEYFILE="$DIR/.password"

[[ ! -x "$BIN" ]] && echo "❌ Binary not found: $BIN" && exit 1
[[ ! -f "$KEYFILE" ]] && echo "❌ Key file not found: $KEYFILE" && exit 1

cd "$DIR"
if [[ -n "$GROUP" ]]; then
  "$BIN" info group $GROUP_ID \
    --key-file "$KEYFILE" \
    --db "db/secrets.db"
else
  "$BIN" info \
    --key-file "$KEYFILE" \
    --db "db/secrets.db"
fi
