#!/usr/bin/env bash
set -euo pipefail

# Install Cobo TSS Node as a system service
# Usage: install-service.sh <linux|macos> --env <dev|prod> [--dir DIR]

PLATFORM="${1:-}"
shift || true

source "$(dirname "$0")/env-common.sh"
parse_env_args "$@"

BIN="$DIR/cobo-tss-node"
KEYFILE="$DIR/.password"
CONFIG="$DIR/configs/cobo-tss-node-config.yaml"
START_FLAG=$(env_start_flag "$ENV")
SERVICE_NAME=$(env_service_name "$ENV")
PLIST_LABEL=$(env_plist_label "$ENV")

[[ ! -x "$BIN" ]] && echo "❌ Binary not found: $BIN" && exit 1
[[ ! -f "$KEYFILE" ]] && echo "❌ Key file not found: $KEYFILE" && exit 1

case "$PLATFORM" in
  linux)
    SERVICE_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"
    mkdir -p "$SERVICE_DIR"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Cobo TSS Node ($ENV)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
ExecStart=$BIN start $START_FLAG --key-file $KEYFILE --config $CONFIG --db $DIR/db/secrets.db
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$DIR/db $DIR/logs $DIR/recovery $DIR/configs
PrivateTmp=true

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}.service"

    echo "✅ Systemd user service installed: $SERVICE_FILE"
    echo "   Environment: $ENV"
    echo "   Service name: $SERVICE_NAME"
    echo ""
    echo "Commands:"
    echo "  systemctl --user start $SERVICE_NAME"
    echo "  systemctl --user stop $SERVICE_NAME"
    echo "  systemctl --user status $SERVICE_NAME"
    echo "  journalctl --user -u $SERVICE_NAME -f"
    echo ""
    echo "⚠️  For service to run after logout: loginctl enable-linger $(whoami)"
    ;;

  macos)
    PLIST_DIR="$HOME/Library/LaunchAgents"
    PLIST_FILE="$PLIST_DIR/${PLIST_LABEL}.plist"
    LOG_DIR="$DIR/logs"
    mkdir -p "$PLIST_DIR" "$LOG_DIR"

    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>start</string>
        <string>$START_FLAG</string>
        <string>--key-file</string>
        <string>$KEYFILE</string>
        <string>--config</string>
        <string>$CONFIG</string>
        <string>--db</string>
        <string>$DIR/db/secrets.db</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd-stderr.log</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

    # Auto-load the agent
    launchctl bootstrap "gui/$(id -u)" "$PLIST_FILE" 2>/dev/null || true

    echo "✅ LaunchAgent installed and loaded: $PLIST_FILE"
    echo "   Environment: $ENV"
    echo "   Label: $PLIST_LABEL"
    echo ""
    echo "Commands:"
    echo "  launchctl kickstart gui/$(id -u)/$PLIST_LABEL"
    echo "  launchctl bootout gui/$(id -u)/$PLIST_LABEL"
    echo "  launchctl list | grep cobo"
    echo "  tail -f $LOG_DIR/launchd-stdout.log"
    ;;

  *)
    echo "Usage: install-service.sh <linux|macos> --env <dev|prod> [--dir DIR]"
    exit 1
    ;;
esac
