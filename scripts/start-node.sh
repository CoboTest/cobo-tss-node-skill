#!/usr/bin/env bash
set -euo pipefail

# Start Cobo TSS Node (foreground)
# Usage: start-node.sh --env <dev|prod> [--dir DIR]

source "$(dirname "$0")/env-common.sh"
parse_env_args "$@"

BIN="$DIR/cobo-tss-node"
KEYFILE="$DIR/.password"
CONFIG="$DIR/configs/cobo-tss-node-config.yaml"
START_FLAG=$(env_start_flag "$ENV")

[[ ! -x "$BIN" ]] && echo "❌ Binary not found: $BIN" && exit 1
[[ ! -f "$KEYFILE" ]] && echo "❌ Key file not found: $KEYFILE" && exit 1
[[ ! -f "$CONFIG" ]] && echo "❌ Config not found: $CONFIG" && exit 1

echo "🚀 Starting TSS Node (env: $ENV, flag: $START_FLAG)..."
cd "$DIR"
exec "$BIN" start \
  "$START_FLAG" \
  --key-file "$KEYFILE" \
  --config "$CONFIG" \
  --db "db/secrets.db"
