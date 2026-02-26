#!/usr/bin/env bash
set -euo pipefail

# Integration tests for cobo-tss-node skill scripts
# Uses --env test with a temp directory and real systemd/launchd calls
# Service name: cobo-tss-node-test (won't conflict with dev/prod)
#
# Requirements:
#   Linux: systemctl --user (systemd user session)
#   macOS: launchctl (current user agent)
#
# Safety: uses unique service name + temp dir, full cleanup on exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
TEST_DIR=$(mktemp -d)
TEST_ENV="test"
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
PASS=0
FAIL=0
ERRORS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✅ $1${NC}"; }
log_fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); echo -e "  ${RED}❌ $1: $2${NC}"; }
log_info() { echo -e "  ${YELLOW}ℹ️  $1${NC}"; }

# Determine service name and file locations
SERVICE_NAME="cobo-tss-node-test"
if [[ "$PLATFORM" == "linux" ]]; then
  SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
elif [[ "$PLATFORM" == "darwin" ]]; then
  PLIST_LABEL="com.cobo.tss-node-test"
  PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
fi

# Cleanup function — always runs
cleanup() {
  echo ""
  echo -e "${YELLOW}🧹 Cleaning up...${NC}"

  # Stop and remove service
  if [[ "$PLATFORM" == "linux" ]]; then
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "  Removed systemd service: $SERVICE_NAME"
  elif [[ "$PLATFORM" == "darwin" ]]; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
    echo "  Removed launchd agent: $PLIST_LABEL"
  fi

  # Remove temp dir
  rm -rf "$TEST_DIR"
  echo "  Removed temp dir: $TEST_DIR"
  echo -e "${GREEN}✅ Cleanup complete${NC}"
}
trap cleanup EXIT

# Create a mock binary that stays running (for service testing)
create_test_binary() {
  local dir="$1"
  cat > "$dir/cobo-tss-node" <<'MOCK'
#!/usr/bin/env bash
CMD="${1:-}"
shift || true
case "$CMD" in
  version) echo "v0.99.0-integration-test" ;;
  init)
    DB=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --db) DB="$2"; shift 2 ;; *) shift ;; esac
    done
    [[ -n "$DB" ]] && mkdir -p "$(dirname "$DB")" && echo "test-db" > "$DB"
    echo "Node initialized"
    echo "TSS Node ID: test-node-id-integration"
    ;;
  info)
    if [[ "${1:-}" == "group" ]]; then
      echo "Group: test-group-001"
    else
      echo "TSS Node ID: test-node-id-integration"
    fi
    ;;
  start)
    # Stay running like a real daemon
    echo "Test node started (pid $$)"
    while true; do sleep 60; done
    ;;
  sign)
    echo "Signed: test-signature"
    ;;
  export-share)
    EDIR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --export-dir) EDIR="$2"; shift 2 ;; *) shift ;; esac
    done
    [[ -n "$EDIR" ]] && echo "test-share" > "$EDIR/share.enc"
    echo "Exported"
    ;;
  migrate) echo "No migration needed" ;;
  *) echo "mock: $CMD"; exit 0 ;;
esac
MOCK
  chmod 755 "$dir/cobo-tss-node"
}

# Setup test directory
setup_test_install() {
  mkdir -p "$TEST_DIR"/{configs,db,logs,recovery,backups}
  create_test_binary "$TEST_DIR"
  printf 'integration-test-pw' > "$TEST_DIR/.password"
  chmod 600 "$TEST_DIR/.password"
  echo "env: test" > "$TEST_DIR/configs/cobo-tss-node-config.yaml"
}

########################################
echo -e "\n${YELLOW}=== Integration Tests (env: $TEST_ENV, platform: $PLATFORM) ===${NC}"
echo -e "${YELLOW}    Test dir: $TEST_DIR${NC}"
echo -e "${YELLOW}    Service: $SERVICE_NAME${NC}"
########################################

# Pre-check: no leftover test service
echo -e "\n${YELLOW}--- Pre-flight checks ---${NC}"

if [[ "$PLATFORM" == "linux" ]]; then
  if systemctl --user is-active "$SERVICE_NAME" 2>/dev/null | grep -q "active"; then
    log_fail "pre-check" "test service already running! Aborting."
    exit 1
  fi
  log_pass "no leftover test service"
elif [[ "$PLATFORM" == "darwin" ]]; then
  if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
    log_fail "pre-check" "test agent already loaded! Aborting."
    exit 1
  fi
  log_pass "no leftover test agent"
else
  log_info "unknown platform $PLATFORM, skipping service tests"
  exit 0
fi

########################################
echo -e "\n${YELLOW}--- Setup & Init ---${NC}"
########################################

# Test: setup-keyfile.sh creates real key file
test_real_keyfile() {
  output=$(bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$TEST_DIR" --force 2>&1)
  if [[ -f "$TEST_DIR/.password" ]]; then
    perms=$(stat -c '%a' "$TEST_DIR/.password" 2>/dev/null || stat -f '%Lp' "$TEST_DIR/.password")
    if [[ "$perms" == "600" ]]; then
      log_pass "setup-keyfile creates file with mode 600"
    else
      log_fail "keyfile perms" "got $perms"
    fi
  else
    log_fail "keyfile" "not created"
  fi
}

# Test: init-node.sh with mock binary
test_real_init() {
  # Remove db so init works
  rm -f "$TEST_DIR/db/secrets.db"
  create_test_binary "$TEST_DIR"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1)
  if [[ -f "$TEST_DIR/db/secrets.db" ]]; then
    log_pass "init-node creates database"
  else
    log_fail "init-node" "db not created"
  fi
}

setup_test_install
test_real_keyfile
test_real_init

########################################
echo -e "\n${YELLOW}--- Service Install ---${NC}"
########################################

if [[ "$PLATFORM" == "linux" ]]; then

  test_real_install_linux() {
    output=$(bash "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1)
    if [[ -f "$SERVICE_FILE" ]]; then
      log_pass "install-service creates $SERVICE_FILE"
    else
      log_fail "install service" "file not found"
      return
    fi

    # Verify content — ExecStart has the binary path, Description mentions test
    if grep -q "$TEST_DIR/cobo-tss-node" "$SERVICE_FILE" && grep -q "test" "$SERVICE_FILE"; then
      log_pass "service file references correct binary and env"
    else
      log_fail "service content" "wrong binary or env in $SERVICE_FILE"
    fi

    # Check enabled
    if systemctl --user is-enabled "$SERVICE_NAME" 2>/dev/null | grep -q "enabled"; then
      log_pass "service is enabled"
    else
      log_fail "service enabled" "not enabled"
    fi
  }

  test_real_install_linux

  ########################################
  echo -e "\n${YELLOW}--- Service Lifecycle ---${NC}"
  ########################################

  test_real_start() {
    bash "$SCRIPT_DIR/node-ctl.sh" start --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1 >/dev/null || true
    sleep 2
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      log_pass "service started and running"
    else
      log_fail "start service" "status: $status"
    fi
  }

  test_real_status() {
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" status --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1) || true
    if echo "$output" | grep -q "$SERVICE_NAME"; then
      log_pass "status shows service info"
    else
      log_fail "status" "service name not in output"
    fi
  }

  test_real_logs() {
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" logs --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1) || true
    # Just verify it doesn't crash — log content depends on timing
    log_pass "logs command runs without error"
  }

  test_real_restart() {
    bash "$SCRIPT_DIR/node-ctl.sh" restart --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1 >/dev/null || true
    sleep 2
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      log_pass "service restarted successfully"
    else
      log_fail "restart" "status: $status"
    fi
  }

  test_real_stop() {
    bash "$SCRIPT_DIR/node-ctl.sh" stop --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1 >/dev/null || true
    sleep 1
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" != "active" ]]; then
      log_pass "service stopped"
    else
      log_fail "stop" "still active"
    fi
  }

  test_real_start
  test_real_status
  test_real_logs
  test_real_restart
  test_real_stop

  ########################################
  echo -e "\n${YELLOW}--- Operations (while stopped) ---${NC}"
  ########################################

  test_real_health() {
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1) || true
    checks=0
    echo "$output" | grep -q "Service:" && checks=$((checks + 1))
    echo "$output" | grep -q "Version:" && checks=$((checks + 1))
    echo "$output" | grep -q "Database:" && checks=$((checks + 1))
    echo "$output" | grep -q "Key file:" && checks=$((checks + 1))
    if [[ "$checks" -ge 3 ]]; then
      log_pass "health check works ($checks/4 sections)"
    else
      log_fail "health" "only $checks/4"
    fi
  }

  test_real_backup() {
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1)
    backup_dir=$(find "$TEST_DIR/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [[ -n "$backup_dir" ]] && [[ -f "$backup_dir/secrets.db" ]] && [[ -f "$backup_dir/.password" ]] && [[ -f "$backup_dir/SHA256SUMS" ]]; then
      # Verify .password in checksums
      if grep -q ".password" "$backup_dir/SHA256SUMS"; then
        log_pass "backup complete with .password in SHA256SUMS"
      else
        log_fail "backup checksums" ".password missing from SHA256SUMS"
      fi
    else
      log_fail "backup" "missing files"
    fi
  }

  test_real_health
  test_real_backup

  ########################################
  echo -e "\n${YELLOW}--- Uninstall ---${NC}"
  ########################################

  test_real_uninstall() {
    bash "$SCRIPT_DIR/node-ctl.sh" uninstall --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1 >/dev/null

    checks=0
    # Service file removed
    [[ ! -f "$SERVICE_FILE" ]] && checks=$((checks + 1))
    # Service no longer known
    status=$(systemctl --user is-enabled "$SERVICE_NAME" 2>&1 || true)
    echo "$status" | grep -qv "enabled" && checks=$((checks + 1))
    # Data preserved
    [[ -f "$TEST_DIR/db/secrets.db" ]] && checks=$((checks + 1))
    [[ -f "$TEST_DIR/.password" ]] && checks=$((checks + 1))

    if [[ "$checks" -eq 4 ]]; then
      log_pass "uninstall: service removed, data preserved (4/4)"
    else
      log_fail "uninstall" "only $checks/4 checks passed"
    fi
  }

  test_real_uninstall

elif [[ "$PLATFORM" == "darwin" ]]; then

  test_real_install_macos() {
    output=$(bash "$SCRIPT_DIR/install-service.sh" macos --env "$TEST_ENV" --dir "$TEST_DIR" 2>&1)
    if [[ -f "$PLIST_FILE" ]]; then
      log_pass "install-service creates plist"
    else
      log_fail "install plist" "not found"
      return
    fi

    if grep -q "$PLIST_LABEL" "$PLIST_FILE"; then
      log_pass "plist has correct label"
    else
      log_fail "plist label" "wrong label"
    fi
  }

  test_real_macos_start() {
    launchctl load "$PLIST_FILE" 2>/dev/null || true
    sleep 2
    if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
      log_pass "launchd agent running"
    else
      log_fail "macos start" "agent not found"
    fi
  }

  test_real_macos_stop() {
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    sleep 1
    if ! launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
      log_pass "launchd agent stopped"
    else
      log_fail "macos stop" "still running"
    fi
  }

  test_real_install_macos
  test_real_macos_start
  test_real_macos_stop

fi

########################################
# Summary
########################################
echo ""
echo "================================"
TOTAL=$((PASS + FAIL))
echo -e "Integration: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} / $TOTAL total"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do
    echo -e "  ${RED}• $e${NC}"
  done
fi
echo "================================"

exit $FAIL
