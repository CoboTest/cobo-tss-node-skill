#!/usr/bin/env bash
set -euo pipefail

# Test suite for cobo-tss-node skill scripts
# All tests use temp directories — never touches ~/.cobo-tss-node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0
ERRORS=()

trap "rm -rf $TEST_DIR" EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✅ $1${NC}"; }
log_fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); echo -e "  ${RED}❌ $1: $2${NC}"; }

# Default test env
TEST_ENV="dev"

# Create mock systemctl/launchctl to avoid touching real services
create_mock_systemctl() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"

  cat > "$bin_dir/systemctl" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_SYSTEMCTL_LOG:-/dev/null}"
echo "systemctl $*" >> "$LOG"
case "${*}" in
  *is-active*) echo "inactive" ;;
  *status*)    echo "○ cobo-tss-node: inactive (mock)" ;;
  *) ;;
esac
exit 0
MOCK
  chmod 755 "$bin_dir/systemctl"

  cat > "$bin_dir/launchctl" <<'MOCK'
#!/usr/bin/env bash
LOG="${MOCK_SYSTEMCTL_LOG:-/dev/null}"
echo "launchctl $*" >> "$LOG"
case "${*}" in
  *list*) echo "- 0 com.cobo.tss-node-dev" ;;
  *) ;;
esac
exit 0
MOCK
  chmod 755 "$bin_dir/launchctl"
}

# Create a mock cobo-tss-node binary
create_mock_binary() {
  local dir="$1"
  cat > "$dir/cobo-tss-node" <<'MOCK'
#!/usr/bin/env bash
CMD="${1:-}"
shift || true
case "$CMD" in
  version) echo "v0.13.0-mock" ;;
  init)
    DB=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --db) DB="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -n "$DB" ]] && mkdir -p "$(dirname "$DB")" && echo "mock-db" > "$DB"
    echo "Node initialized"
    echo "TSS Node ID: cobo-tss-node-mock-id-12345"
    ;;
  info)
    if [[ "${1:-}" == "group" ]]; then
      echo "Group: mock-group-001"
      echo "Threshold: 2/3"
    else
      echo "TSS Node ID: cobo-tss-node-mock-id-12345"
      echo "Created: 2025-01-01"
    fi
    ;;
  start) echo "Node started" ;;
  sign)
    echo "Signed message successfully"
    echo "Signature: 0xdeadbeef"
    ;;
  export-share)
    EDIR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --export-dir) EDIR="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ -n "$EDIR" ]] && echo "mock-share-data" > "$EDIR/share.enc"
    echo "Exported shares"
    ;;
  migrate) echo "Migration complete (no changes)" ;;
  change-password) echo "Password changed" ;;
  *) echo "Unknown command: $CMD"; exit 1 ;;
esac
MOCK
  chmod 755 "$dir/cobo-tss-node"
}

# Setup a test install directory
setup_test_dir() {
  local dir="$1"
  mkdir -p "$dir"/{configs,db,logs,recovery,backups}
  create_mock_binary "$dir"
  printf 'test-password-123' > "$dir/.password"
  chmod 600 "$dir/.password"
  echo "env: development" > "$dir/configs/cobo-tss-node-config.yaml"
  echo "mock-db-content" > "$dir/db/secrets.db"
}

# Helper: run with mock HOME + mock systemctl
run_with_mock_env() {
  local fake_home="$1"; shift
  local mock_bin="$TEST_DIR/mock-bin"
  local mock_log="$TEST_DIR/mock-svc-calls.log"
  create_mock_systemctl "$mock_bin"
  > "$mock_log"
  HOME="$fake_home" PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG="$mock_log" bash "$@" 2>&1
}

########################################
echo -e "\n${YELLOW}=== setup-keyfile.sh ===${NC}"
########################################

test_setup_keyfile_create() {
  local d="$TEST_DIR/keyfile-create"
  mkdir -p "$d"
  output=$(bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if [[ -f "$d/.password" ]]; then
    perms=$(stat -c '%a' "$d/.password" 2>/dev/null || stat -f '%Lp' "$d/.password")
    if [[ "$perms" == "600" ]]; then
      log_pass "creates key file with mode 600"
    else
      log_fail "key file permissions" "expected 600 got $perms"
    fi
  else
    log_fail "creates key file" "file not found"
  fi
}

test_setup_keyfile_no_overwrite() {
  local d="$TEST_DIR/keyfile-noforce"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1
  output=$(bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1 < /dev/null) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "refuses overwrite without --force (non-interactive)"
  else
    log_fail "overwrite protection" "rc=$rc"
  fi
}

test_setup_keyfile_force() {
  local d="$TEST_DIR/keyfile-force"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "first" 2>&1
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "second" --force 2>&1
  content=$(cat "$d/.password")
  if [[ "$content" == "second" ]]; then
    log_pass "--force overwrites existing key file"
  else
    log_fail "--force overwrite" "got '$content'"
  fi
}

test_setup_keyfile_no_newline() {
  local d="$TEST_DIR/keyfile-nonewline"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "exact" 2>&1
  bytes=$(wc -c < "$d/.password" | tr -d ' ')
  if [[ "$bytes" == "5" ]]; then
    log_pass "no trailing newline in password file"
  else
    log_fail "trailing newline" "expected 5 bytes got $bytes"
  fi
}

test_setup_keyfile_create
test_setup_keyfile_no_overwrite
test_setup_keyfile_force
test_setup_keyfile_no_newline

########################################
echo -e "\n${YELLOW}=== init-node.sh ===${NC}"
########################################

test_init_node_success() {
  local d="$TEST_DIR/init-ok"
  mkdir -p "$d"/configs
  create_mock_binary "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  echo "env: dev" > "$d/configs/cobo-tss-node-config.yaml"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if [[ -f "$d/db/secrets.db" ]] && echo "$output" | grep -q "initialized"; then
    log_pass "initializes node and creates db"
  else
    log_fail "init node" "db missing or no success message"
  fi
}

test_init_node_existing_db() {
  local d="$TEST_DIR/init-exists"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "already exists"; then
    log_pass "refuses init when db exists"
  else
    log_fail "existing db check" "rc=$rc"
  fi
}

test_init_node_no_binary() {
  local d="$TEST_DIR/init-nobin"
  mkdir -p "$d"/configs
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without binary"
  else
    log_fail "no binary check" "should have failed"
  fi
}

test_init_node_no_keyfile() {
  local d="$TEST_DIR/init-nokey"
  mkdir -p "$d"/configs
  create_mock_binary "$d"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without key file"
  else
    log_fail "no keyfile check" "should have failed"
  fi
}

test_init_node_success
test_init_node_existing_db
test_init_node_no_binary
test_init_node_no_keyfile

########################################
echo -e "\n${YELLOW}=== node-info.sh ===${NC}"
########################################

test_node_info_basic() {
  local d="$TEST_DIR/info-basic"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-info.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if echo "$output" | grep -q "mock-id-12345"; then
    log_pass "shows node info"
  else
    log_fail "node info" "expected mock ID, got: $output"
  fi
}

test_node_info_group() {
  local d="$TEST_DIR/info-group"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-info.sh" --env "$TEST_ENV" --dir "$d" --group 2>&1)
  if echo "$output" | grep -q "mock-group"; then
    log_pass "shows group info"
  else
    log_fail "group info" "got: $output"
  fi
}

test_node_info_basic
test_node_info_group

########################################
echo -e "\n${YELLOW}=== node-ctl.sh ===${NC}"
########################################

test_ctl_health() {
  local d="$TEST_DIR/ctl-health"
  local mock_bin="$TEST_DIR/mock-bin"
  setup_test_dir "$d"
  create_mock_systemctl "$mock_bin"
  output=$(PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG=/dev/null \
    bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) || true
  checks=0
  echo "$output" | grep -q "Version:" && checks=$((checks + 1))
  echo "$output" | grep -q "Database:" && checks=$((checks + 1))
  echo "$output" | grep -q "Config:" && checks=$((checks + 1))
  echo "$output" | grep -q "Key file:" && checks=$((checks + 1))
  echo "$output" | grep -q "Disk available:" && checks=$((checks + 1))
  if [[ "$checks" -ge 4 ]]; then
    log_pass "health check covers all sections ($checks/5)"
  else
    log_fail "health check" "only $checks/5 sections found"
  fi
}

test_ctl_health_keyfile_perms() {
  local d="$TEST_DIR/ctl-health-perms"
  local mock_bin="$TEST_DIR/mock-bin"
  setup_test_dir "$d"
  create_mock_systemctl "$mock_bin"
  output=$(PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG=/dev/null \
    bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) || true
  if echo "$output" | grep -q "mode 600"; then
    log_pass "health reports correct key file mode 600"
  else
    log_fail "health key perms" "didn't find mode 600"
  fi
}

test_ctl_health_bad_perms() {
  local d="$TEST_DIR/ctl-health-badperms"
  local mock_bin="$TEST_DIR/mock-bin"
  setup_test_dir "$d"
  create_mock_systemctl "$mock_bin"
  chmod 644 "$d/.password"
  output=$(PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG=/dev/null \
    bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) || true
  if echo "$output" | grep -q "⚠️"; then
    log_pass "health warns on bad key file permissions"
  else
    log_fail "health bad perms" "no warning found"
  fi
}

test_ctl_sign_auto() {
  local d="$TEST_DIR/ctl-sign"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" sign --env "$TEST_ENV" --dir "$d" mock-group-001 2>&1)
  if echo "$output" | grep -q "Signed\|Signature"; then
    log_pass "sign with auto message"
  else
    log_fail "sign auto" "got: $output"
  fi
}

test_ctl_sign_no_group() {
  local d="$TEST_DIR/ctl-sign-nogrp"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" sign --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "usage"; then
    log_pass "sign fails without group-id"
  else
    log_fail "sign no group" "rc=$rc"
  fi
}

test_ctl_export() {
  local d="$TEST_DIR/ctl-export"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" export --env "$TEST_ENV" --dir "$d" mock-group-001 2>&1)
  recovery_dirs=$(find "$d/recovery" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$recovery_dirs" -ge 1 ]]; then
    log_pass "export creates recovery directory"
  else
    log_fail "export" "no recovery dir created"
  fi
}

test_ctl_backup() {
  local d="$TEST_DIR/ctl-backup"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1)
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [[ -z "$backup_dir" ]]; then
    log_fail "backup" "no backup dir created"
    return
  fi
  files_ok=0
  [[ -f "$backup_dir/secrets.db" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/cobo-tss-node-config.yaml" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/.password" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/SHA256SUMS" ]] && files_ok=$((files_ok + 1))
  if [[ "$files_ok" -eq 4 ]]; then
    log_pass "backup creates all 4 expected files"
  else
    log_fail "backup files" "only $files_ok/4 found"
  fi
}

test_ctl_backup_sha_includes_dotfile() {
  local d="$TEST_DIR/ctl-backup-sha"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  if grep -q ".password" "$backup_dir/SHA256SUMS" 2>/dev/null; then
    log_pass "SHA256SUMS includes .password (dotfile fix)"
  else
    log_fail "SHA256SUMS dotfile" ".password not in checksums"
  fi
}

test_ctl_backup_password_perms() {
  local d="$TEST_DIR/ctl-backup-perms"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  perms=$(stat -c '%a' "$backup_dir/.password" 2>/dev/null || stat -f '%Lp' "$backup_dir/.password")
  if [[ "$perms" == "600" ]]; then
    log_pass "backup .password has mode 600"
  else
    log_fail "backup password perms" "got $perms"
  fi
}

test_ctl_groups() {
  local d="$TEST_DIR/ctl-groups"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" groups --env "$TEST_ENV" --dir "$d" 2>&1)
  if echo "$output" | grep -q "mock-group"; then
    log_pass "groups lists groups"
  else
    log_fail "groups" "got: $output"
  fi
}

test_ctl_help() {
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" help 2>&1)
  if echo "$output" | grep -q "Service Management" && echo "$output" | grep -q "Maintenance"; then
    log_pass "help shows all sections"
  else
    log_fail "help" "incomplete output"
  fi
}

test_ctl_unknown() {
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" nonexistent --env "$TEST_ENV" --dir /tmp 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "unknown"; then
    log_pass "unknown command exits with error"
  else
    log_fail "unknown command" "rc=$rc"
  fi
}

test_ctl_no_binary() {
  local d="$TEST_DIR/ctl-nobin"
  mkdir -p "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "health fails without binary"
  else
    log_fail "no binary" "should have failed"
  fi
}

test_ctl_health
test_ctl_health_keyfile_perms
test_ctl_health_bad_perms
test_ctl_sign_auto
test_ctl_sign_no_group
test_ctl_export
test_ctl_backup
test_ctl_backup_sha_includes_dotfile
test_ctl_backup_password_perms
test_ctl_groups
test_ctl_help
test_ctl_unknown
test_ctl_no_binary

########################################
echo -e "\n${YELLOW}=== install-service.sh ===${NC}"
########################################

test_install_service_linux_content() {
  local d="$TEST_DIR/svc-linux"
  local fake_home="$TEST_DIR/svc-linux-home"
  setup_test_dir "$d"
  mkdir -p "$fake_home/.config/systemd/user"

  output=$(run_with_mock_env "$fake_home" "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$d")

  svc_file=$(find "$fake_home/.config/systemd/user/" -name "*.service" | head -1)
  if [[ -z "$svc_file" || ! -f "$svc_file" ]]; then
    log_fail "linux service file" "not created"
    return
  fi

  checks=0
  grep -q "ExecStart=" "$svc_file" && checks=$((checks + 1))
  grep -q "key-file" "$svc_file" && checks=$((checks + 1))
  grep -q "NoNewPrivileges=true" "$svc_file" && checks=$((checks + 1))
  grep -q "backups" "$svc_file" && checks=$((checks + 1))
  grep -q "ProtectHome=false" "$svc_file" && checks=$((checks + 1))

  if [[ "$checks" -ge 5 ]]; then
    log_pass "linux service file has all expected directives ($checks/5)"
  else
    log_fail "linux service content" "only $checks/5 checks passed"
  fi
}

test_install_service_linux_calls_systemctl() {
  local d="$TEST_DIR/svc-linux-calls"
  local fake_home="$TEST_DIR/svc-linux-calls-home"
  local mock_log="$TEST_DIR/mock-svc-calls.log"
  setup_test_dir "$d"
  mkdir -p "$fake_home/.config/systemd/user"

  run_with_mock_env "$fake_home" "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$d" >/dev/null

  checks=0
  grep -q "daemon-reload" "$mock_log" && checks=$((checks + 1))
  grep -q "enable" "$mock_log" && checks=$((checks + 1))

  if [[ "$checks" -eq 2 ]]; then
    log_pass "install-service calls daemon-reload + enable"
  else
    log_fail "systemctl calls" "only $checks/2 calls found"
  fi
}

test_install_service_macos_content() {
  local d="$TEST_DIR/svc-macos"
  local fake_home="$TEST_DIR/svc-macos-home"
  setup_test_dir "$d"
  mkdir -p "$fake_home/Library/LaunchAgents"

  output=$(run_with_mock_env "$fake_home" "$SCRIPT_DIR/install-service.sh" macos --env "$TEST_ENV" --dir "$d")

  plist=$(find "$fake_home/Library/LaunchAgents/" -name "*.plist" | head -1)
  if [[ -z "$plist" || ! -f "$plist" ]]; then
    log_fail "macos plist" "not created"
    return
  fi

  checks=0
  grep -q "com.cobo" "$plist" && checks=$((checks + 1))
  grep -q "key-file" "$plist" && checks=$((checks + 1))
  grep -q "KeepAlive" "$plist" && checks=$((checks + 1))
  grep -q "ThrottleInterval" "$plist" && checks=$((checks + 1))

  if [[ "$checks" -ge 4 ]]; then
    log_pass "macos plist has all expected keys ($checks/4)"
  else
    log_fail "macos plist content" "only $checks/4 checks passed"
  fi
}

test_install_service_no_platform() {
  output=$(bash "$SCRIPT_DIR/install-service.sh" --env "$TEST_ENV" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without platform arg"
  else
    log_fail "no platform" "should have failed"
  fi
}

test_install_service_linux_content
test_install_service_linux_calls_systemctl
test_install_service_macos_content
test_install_service_no_platform

########################################
echo -e "\n${YELLOW}=== node-ctl.sh service management ===${NC}"
########################################

test_ctl_start_stop_restart() {
  local d="$TEST_DIR/ctl-svc"
  local mock_log="$TEST_DIR/mock-svc-calls.log"
  setup_test_dir "$d"

  local mock_bin="$TEST_DIR/mock-bin"
  create_mock_systemctl "$mock_bin"

  for cmd in start stop restart status; do
    > "$mock_log"
    PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG="$mock_log" \
      bash "$SCRIPT_DIR/node-ctl.sh" "$cmd" --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    if grep -q "systemctl\|launchctl" "$mock_log" 2>/dev/null; then
      log_pass "node-ctl $cmd calls service manager"
    else
      log_fail "node-ctl $cmd" "no service call logged"
    fi
  done
}

test_ctl_uninstall_linux() {
  local d="$TEST_DIR/ctl-uninstall"
  local fake_home="$TEST_DIR/ctl-uninstall-home"
  local mock_log="$TEST_DIR/mock-svc-calls.log"
  local mock_bin="$TEST_DIR/mock-bin"
  setup_test_dir "$d"
  create_mock_systemctl "$mock_bin"

  # Install first
  mkdir -p "$fake_home/.config/systemd/user"
  HOME="$fake_home" PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG="$mock_log" \
    bash "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null

  svc_file=$(find "$fake_home/.config/systemd/user/" -name "*.service" | head -1)
  if [[ -z "$svc_file" || ! -f "$svc_file" ]]; then
    log_fail "uninstall setup" "service file not created"
    return
  fi

  # Uninstall
  > "$mock_log"
  HOME="$fake_home" PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG="$mock_log" \
    bash "$SCRIPT_DIR/node-ctl.sh" uninstall --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null

  checks=0
  [[ ! -f "$svc_file" ]] && checks=$((checks + 1))
  grep -q "disable" "$mock_log" && checks=$((checks + 1))
  grep -q "daemon-reload" "$mock_log" && checks=$((checks + 1))
  [[ -d "$d/db" ]] && checks=$((checks + 1))

  if [[ "$checks" -eq 4 ]]; then
    log_pass "uninstall removes service, calls disable+reload, keeps data"
  else
    log_fail "uninstall linux" "only $checks/4 checks passed"
  fi
}

test_ctl_uninstall_preserves_data() {
  local d="$TEST_DIR/ctl-uninstall-data"
  local fake_home="$TEST_DIR/ctl-uninstall-data-home"
  local mock_bin="$TEST_DIR/mock-bin"
  setup_test_dir "$d"
  create_mock_systemctl "$mock_bin"
  mkdir -p "$fake_home/.config/systemd/user"

  HOME="$fake_home" PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG=/dev/null \
    bash "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  HOME="$fake_home" PATH="$mock_bin:$PATH" MOCK_SYSTEMCTL_LOG=/dev/null \
    bash "$SCRIPT_DIR/node-ctl.sh" uninstall --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null

  checks=0
  [[ -f "$d/db/secrets.db" ]] && checks=$((checks + 1))
  [[ -f "$d/.password" ]] && checks=$((checks + 1))
  [[ -f "$d/configs/cobo-tss-node-config.yaml" ]] && checks=$((checks + 1))
  [[ -x "$d/cobo-tss-node" ]] && checks=$((checks + 1))

  if [[ "$checks" -eq 4 ]]; then
    log_pass "uninstall preserves all data (db, password, config, binary)"
  else
    log_fail "uninstall data" "only $checks/4 files remain"
  fi
}

test_ctl_start_stop_restart
test_ctl_uninstall_linux
test_ctl_uninstall_preserves_data

########################################
echo -e "\n${YELLOW}=== start-node.sh ===${NC}"
########################################

test_start_node_runs() {
  local d="$TEST_DIR/start-ok"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/start-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if echo "$output" | grep -q "started\|Starting"; then
    log_pass "start-node runs with mock binary"
  else
    log_fail "start node" "got: $output"
  fi
}

test_start_node_no_config() {
  local d="$TEST_DIR/start-noconf"
  mkdir -p "$d"
  create_mock_binary "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/start-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "start-node fails without config"
  else
    log_fail "no config check" "should have failed"
  fi
}

test_start_node_runs
test_start_node_no_config

########################################
# Summary
########################################
echo ""
echo "================================"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} / $TOTAL total"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do
    echo -e "  ${RED}• $e${NC}"
  done
fi
echo "================================"
echo "Test dir: $TEST_DIR (cleaned up on exit)"

exit $FAIL
