#!/usr/bin/env bash
set -euo pipefail

# Cobo TSS Node daily operations controller
# Usage: node-ctl.sh <command> --env <dev|prod> [--dir DIR] [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env-common.sh"

CMD="${1:-help}"
shift || true

# Parse --env and --dir from remaining args
ENV=""
DIR=""
REMAINING=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    *)     REMAINING+=("$1"); shift ;;
  esac
done

# For help, env is optional
if [[ "$CMD" != "help" && "$CMD" != "--help" && "$CMD" != "-h" ]]; then
  if [[ -z "$ENV" ]]; then
    # Try to detect from DIR/.env marker
    if [[ -n "$DIR" && -f "$DIR/.env" ]]; then
      ENV=$(cat "$DIR/.env")
    else
      echo "❌ --env is required (dev or prod)"
      echo "Usage: node-ctl.sh <command> --env <dev|prod> [--dir DIR] [options]"
      exit 1
    fi
  fi
  [[ -z "$DIR" ]] && DIR=$(env_default_dir "$ENV")
fi

BIN="$DIR/cobo-tss-node"
KEYFILE="$DIR/.password"
CONFIG="$DIR/configs/cobo-tss-node-config.yaml"
DB="db/secrets.db"
START_FLAG=$(env_start_flag "${ENV:-prod}")
SERVICE_NAME=$(env_service_name "${ENV:-prod}")
PLIST_LABEL=$(env_plist_label "${ENV:-prod}")

# Detect platform
detect_platform() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "unknown" ;;
  esac
}

PLATFORM=$(detect_platform)
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# Service control abstraction
svc_cmd() {
  local action="$1"
  case "$PLATFORM" in
    linux)
      case "$action" in
        start)   systemctl --user start "$SERVICE_NAME" ;;
        stop)    systemctl --user stop "$SERVICE_NAME" ;;
        restart) systemctl --user restart "$SERVICE_NAME" ;;
        status)  systemctl --user status "$SERVICE_NAME" --no-pager ;;
        enable)  systemctl --user enable "$SERVICE_NAME" ;;
        disable) systemctl --user disable "$SERVICE_NAME" ;;
        is-active) systemctl --user is-active "$SERVICE_NAME" 2>/dev/null ;;
      esac
      ;;
    macos)
      case "$action" in
        start)   launchctl load "$PLIST_FILE" 2>/dev/null || launchctl kickstart "gui/$(id -u)/$PLIST_LABEL" ;;
        stop)    launchctl unload "$PLIST_FILE" 2>/dev/null || launchctl kill SIGTERM "gui/$(id -u)/$PLIST_LABEL" ;;
        restart) svc_cmd stop; sleep 2; svc_cmd start ;;
        status)
          if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
            echo "● $SERVICE_NAME ($ENV): running"
            launchctl list | grep "$PLIST_LABEL"
          else
            echo "○ $SERVICE_NAME ($ENV): not running"
          fi
          ;;
        is-active)
          launchctl list 2>/dev/null | grep -q "$PLIST_LABEL" && echo "active" || echo "inactive"
          ;;
      esac
      ;;
    *)
      echo "❌ Unsupported platform: $PLATFORM"
      exit 1
      ;;
  esac
}

check_bin() {
  [[ -x "$BIN" ]] || { echo "❌ Binary not found: $BIN"; exit 1; }
  [[ -f "$KEYFILE" ]] || { echo "❌ Key file not found: $KEYFILE"; exit 1; }
}

case "$CMD" in

  info)
    check_bin
    echo "📍 Environment: $ENV | Dir: $DIR"
    cd "$DIR"
    $BIN info --key-file "$KEYFILE" --db "$DB"
    ;;

  status)
    echo "📍 Environment: $ENV | Dir: $DIR"
    svc_cmd status
    ;;

  start)
    echo "🚀 Starting $SERVICE_NAME ($ENV)..."
    svc_cmd start
    sleep 2
    svc_cmd status
    ;;

  stop)
    echo "🛑 Stopping $SERVICE_NAME ($ENV)..."
    svc_cmd stop
    echo "✅ Stopped"
    ;;

  restart)
    echo "🔄 Restarting $SERVICE_NAME ($ENV)..."
    svc_cmd restart
    sleep 2
    svc_cmd status
    ;;

  logs)
    FOLLOW=""
    LINES=50
    for arg in "${REMAINING[@]+"${REMAINING[@]}"}"; do
      case "$arg" in
        --follow|-f) FOLLOW="yes" ;;
        --lines=*) LINES="${arg#--lines=}" ;;
      esac
    done
    case "$PLATFORM" in
      linux)
        if [[ -n "$FOLLOW" ]]; then
          journalctl --user -u "$SERVICE_NAME" -f
        else
          journalctl --user -u "$SERVICE_NAME" -n "$LINES" --no-pager
        fi
        ;;
      macos)
        LOG_FILE="$DIR/logs/launchd-stdout.log"
        if [[ -n "$FOLLOW" ]]; then
          tail -f "$LOG_FILE"
        else
          tail -n "$LINES" "$LOG_FILE"
        fi
        ;;
    esac
    ;;

  health)
    check_bin
    echo "🏥 Health Check ($ENV)"
    echo "========================"
    echo "📍 Dir: $DIR"

    STATUS=$(svc_cmd is-active)
    if [[ "$STATUS" == "active" ]]; then
      echo "✅ Service ($SERVICE_NAME): running"
    else
      echo "❌ Service ($SERVICE_NAME): $STATUS"
    fi

    echo "📌 Version: $($BIN version 2>&1 | head -1)"

    if [[ -f "$DIR/$DB" ]]; then
      DB_SIZE=$(du -h "$DIR/$DB" | cut -f1)
      echo "✅ Database: $DIR/$DB ($DB_SIZE)"
    else
      echo "❌ Database: not found"
    fi

    if [[ -f "$CONFIG" ]]; then
      echo "✅ Config: $CONFIG"
    else
      echo "❌ Config: not found"
    fi

    PERMS=$(stat -c '%a' "$KEYFILE" 2>/dev/null || stat -f '%Lp' "$KEYFILE" 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
      echo "✅ Key file: $KEYFILE (mode $PERMS)"
    else
      echo "⚠️  Key file: $KEYFILE (mode $PERMS — should be 600)"
    fi

    DISK_AVAIL=$(df -h "$DIR" | awk 'NR==2{print $4}')
    echo "💾 Disk available: $DISK_AVAIL"

    echo ""
    echo "📋 Node Info:"
    cd "$DIR"
    $BIN info --key-file "$KEYFILE" --db "$DB" 2>&1 || echo "  (could not read node info)"
    ;;

  sign)
    check_bin
    GROUP_ID="${REMAINING[0]:-}"
    MESSAGE="${REMAINING[1]:-}"
    [[ -z "$GROUP_ID" ]] && echo "Usage: node-ctl.sh sign --env <dev|prod> <group-id> [message]" && exit 1
    [[ -z "$MESSAGE" ]] && MESSAGE="checkup-$(date +%Y-%m-%d)"
    echo "✍️  Signing message for group $GROUP_ID ($ENV)..."
    cd "$DIR"
    $BIN sign --key-file "$KEYFILE" --db "$DB" --group-id "$GROUP_ID" --message "$MESSAGE"
    ;;

  export)
    check_bin
    GROUP_IDS="${REMAINING[0]:-}"
    [[ -z "$GROUP_IDS" ]] && echo "Usage: node-ctl.sh export --env <dev|prod> <group-id1,group-id2,...>" && exit 1
    EXPORT_DIR="$DIR/recovery/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$EXPORT_DIR"
    echo "📦 Exporting shares to $EXPORT_DIR ($ENV)..."
    cd "$DIR"
    $BIN export-share --key-file "$KEYFILE" --db "$DB" --group-ids "$GROUP_IDS" --export-dir "$EXPORT_DIR"
    echo "✅ Exported to $EXPORT_DIR"
    ls -la "$EXPORT_DIR"
    ;;

  groups)
    check_bin
    cd "$DIR"
    $BIN info group --key-file "$KEYFILE" --db "$DB"
    ;;

  group)
    check_bin
    GROUP_ID="${REMAINING[0]:-}"
    [[ -z "$GROUP_ID" ]] && echo "Usage: node-ctl.sh group --env <dev|prod> <group-id>" && exit 1
    cd "$DIR"
    $BIN info group "$GROUP_ID" --key-file "$KEYFILE" --db "$DB"
    ;;

  change-password)
    check_bin
    echo "🔑 Changing database password ($ENV)..."
    cd "$DIR"
    $BIN change-password --key-file "$KEYFILE" --db "$DB"
    echo "✅ Password changed"
    ;;

  migrate)
    check_bin
    DRY_RUN=""
    for arg in "${REMAINING[@]+"${REMAINING[@]}"}"; do
      [[ "$arg" == "--dry-run" ]] && DRY_RUN="--dry-run"
    done
    echo "🔧 Running database migration ($ENV)${DRY_RUN:+ (dry run)}..."
    cd "$DIR"
    $BIN migrate $DRY_RUN --key-file "$KEYFILE" --db "$DB"
    echo "✅ Migration complete"
    ;;

  update)
    VERSION=""
    for arg in "${REMAINING[@]+"${REMAINING[@]}"}"; do
      case "$arg" in
        --version=*) VERSION="${arg#--version=}" ;;
      esac
    done

    echo "🛑 Stopping service ($ENV)..."
    svc_cmd stop 2>/dev/null || true
    sleep 2

    if [[ -x "$BIN" ]]; then
      CURRENT_VER=$($BIN version 2>&1 | head -1)
      cp "$BIN" "$BIN.bak"
      echo "📦 Backed up current binary ($CURRENT_VER)"
    fi

    INSTALL_ARGS=(--env "$ENV" --dir "$DIR")
    [[ -n "$VERSION" ]] && INSTALL_ARGS+=(--version "$VERSION")
    if ! bash "$SCRIPT_DIR/install.sh" "${INSTALL_ARGS[@]}"; then
      echo "❌ Update failed. Rolling back..."
      if [[ -f "$BIN.bak" ]]; then
        cp "$BIN.bak" "$BIN"
        echo "✅ Rolled back to previous binary"
        svc_cmd start 2>/dev/null || true
      fi
      exit 1
    fi

    echo "🔧 Running migration..."
    cd "$DIR"
    $BIN migrate --key-file "$KEYFILE" --db "$DB" 2>&1 || echo "  (no migration needed)"

    echo "🚀 Starting service..."
    svc_cmd start
    sleep 2
    svc_cmd status

    NEW_VER=$($BIN version 2>&1 | head -1)
    echo ""
    echo "✅ Updated to $NEW_VER ($ENV)"
    ;;

  backup)
    BACKUP_DIR="$DIR/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "📦 Backing up $ENV to $BACKUP_DIR..."

    cp "$DIR/$DB" "$BACKUP_DIR/secrets.db"
    cp "$CONFIG" "$BACKUP_DIR/cobo-tss-node-config.yaml"
    cp "$KEYFILE" "$BACKUP_DIR/.password"
    chmod 600 "$BACKUP_DIR/.password"

    (cd "$BACKUP_DIR" && sha256sum * > SHA256SUMS 2>/dev/null || shasum -a 256 * > SHA256SUMS)

    echo "✅ Backup complete ($ENV):"
    ls -la "$BACKUP_DIR"
    echo ""
    echo "⚠️  Store this backup securely (contains encrypted keys + password)"
    ;;

  uninstall)
    echo "🗑️  Uninstalling service $SERVICE_NAME ($ENV)..."
    svc_cmd stop 2>/dev/null || true
    case "$PLATFORM" in
      linux)
        systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/${SERVICE_NAME}.service"
        systemctl --user daemon-reload
        echo "✅ Systemd service removed"
        ;;
      macos)
        launchctl unload "$PLIST_FILE" 2>/dev/null || true
        rm -f "$PLIST_FILE"
        echo "✅ LaunchAgent removed"
        ;;
    esac
    echo "📂 Data preserved in $DIR"
    echo "   To fully remove: rm -rf $DIR"
    ;;

  help|--help|-h)
    cat <<'EOF'
Cobo TSS Node Controller

Usage: node-ctl.sh <command> --env <dev|prod> [--dir DIR] [options]

Environments:
  dev     Development   (default dir: ~/.cobo-tss-node-dev, flag: --dev)
  prod    Production    (default dir: ~/.cobo-tss-node,     flag: --prod)

Node Info:
  info                Show Node ID and metadata

Service Management:
  status              Show service status
  start               Start service
  stop                Stop service
  restart             Restart service
  logs [-f|--follow]  View logs (--follow for live tail)

Operations:
  health              Full health check
  sign <gid> [msg]    Sign message for key share checkup
  export <gid,...>    Export key shares for disaster recovery
  groups              List all MPC groups
  group <gid>         Show group detail

Maintenance:
  change-password     Change database password
  migrate [--dry-run] Run database migration
  update [--version=] Update binary (stops → install → migrate → start)
  backup              Backup database, config, and key file
  uninstall           Remove service (preserves data)
EOF
    ;;

  *)
    echo "Unknown command: $CMD"
    echo "Run 'node-ctl.sh help' for usage"
    exit 1
    ;;
esac
