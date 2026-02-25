#!/usr/bin/env bash
set -euo pipefail

# Initialize Cobo TSS Node
# Usage: init-node.sh --env <dev|prod> [--dir DIR]

source "$(dirname "$0")/env-common.sh"
parse_env_args "$@"

BIN="$DIR/cobo-tss-node"
KEYFILE="$DIR/.password"
CONFIG="$DIR/configs/cobo-tss-node-config.yaml"

[[ ! -x "$BIN" ]] && echo "❌ Binary not found: $BIN" && exit 1
[[ ! -f "$KEYFILE" ]] && echo "❌ Key file not found: $KEYFILE (run setup-keyfile.sh first)" && exit 1

if [[ -f "$DIR/db/secrets.db" ]]; then
  echo "⚠️  Database already exists: $DIR/db/secrets.db"
  echo "   Node may already be initialized. Use node-info.sh --env $ENV to check."
  exit 1
fi

echo "🔧 Initializing TSS Node ($ENV)..."
cd "$DIR"
"$BIN" init \
  --key-file "$KEYFILE" \
  --config "$CONFIG" \
  --db "db/secrets.db"

echo ""
echo "✅ TSS Node initialized! (env: $ENV, dir: $DIR)"
echo ""
echo "📋 Node info:"
"$BIN" info \
  --key-file "$KEYFILE" \
  --db "db/secrets.db"

echo ""
echo "⚠️  Save your TSS Node ID — you'll need it to register on Cobo Portal"
