#!/usr/bin/env bash
# Common environment helpers for cobo-tss-node scripts
# Source this file: source "$(dirname "$0")/env-common.sh"

# Supported environments
VALID_ENVS=("dev" "prod" "test")

# Default directory per environment
env_default_dir() {
  local env="$1"
  case "$env" in
    dev)  echo "$HOME/.cobo-tss-node-dev" ;;
    prod) echo "$HOME/.cobo-tss-node" ;;
    test) echo "$HOME/.cobo-tss-node-test" ;;
    *)    echo "❌ Invalid environment: $env (must be dev, prod, or test)" >&2; exit 1 ;;
  esac
}

# Start flag per environment
env_start_flag() {
  local env="$1"
  case "$env" in
    dev)  echo "--dev" ;;
    prod) echo "--prod" ;;
    test) echo "--dev" ;;  # test uses dev API endpoint
    *)    echo "❌ Invalid environment: $env" >&2; exit 1 ;;
  esac
}

# Service name per environment
env_service_name() {
  local env="$1"
  case "$env" in
    dev)  echo "cobo-tss-node-dev" ;;
    prod) echo "cobo-tss-node" ;;
    test) echo "cobo-tss-node-test" ;;
    *)    echo "❌ Invalid environment: $env" >&2; exit 1 ;;
  esac
}

# macOS plist label per environment
env_plist_label() {
  local env="$1"
  case "$env" in
    dev)  echo "com.cobo.tss-node-dev" ;;
    prod) echo "com.cobo.tss-node" ;;
    test) echo "com.cobo.tss-node-test" ;;
    *)    echo "❌ Invalid environment: $env" >&2; exit 1 ;;
  esac
}


# Portable SHA256 — works on both Linux (sha256sum) and macOS (shasum)
portable_sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
# Parse --env and --dir from args, set ENV and DIR
# Usage: parse_env_args "$@"
# After calling: use $ENV, $DIR, and remaining args in $EXTRA_ARGS
ENV=""
DIR=""
EXTRA_ARGS=()

parse_env_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          echo "❌ --env requires a value (dev, prod, or test)"
          exit 1
        fi
        ENV="$2"; shift 2
        ;;
      --dir)
        if [[ $# -lt 2 || "$2" == --* ]]; then
          echo "❌ --dir requires a value"
          exit 1
        fi
        DIR="$2"; shift 2
        ;;
      *)     EXTRA_ARGS+=("$1"); shift ;;
    esac
  done

  # ENV is required and must be valid
  if [[ -z "$ENV" ]]; then
    echo "❌ --env is required (${VALID_ENVS[*]})"
    echo "Usage: $0 --env <${VALID_ENVS[*]}> [--dir DIR] [options]"
    exit 1
  fi
  local valid=false
  for e in "${VALID_ENVS[@]}"; do
    [[ "$e" == "$ENV" ]] && valid=true && break
  done
  if [[ "$valid" != "true" ]]; then
    echo "❌ Invalid environment: $ENV (must be one of: ${VALID_ENVS[*]})"
    exit 1
  fi

  # Default DIR based on ENV
  if [[ -z "$DIR" ]]; then
    DIR=$(env_default_dir "$ENV")
  fi
}
