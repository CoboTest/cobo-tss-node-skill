# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.4.0] - 2026-02-27

### Added
- Checksum verification (SHA256SUMS) in `install.sh` — verifies binary integrity after download
- YAML config validation in `node-ctl.sh health` — checks config file is parseable
- Backup auto-cleanup with `--keep=N` (default: 10 most recent)
- `loginctl enable-linger` detection in `install-service.sh` and `health` check
- `test` environment support in `env-common.sh` — isolated service name for testing
- Test suite: 33+ tests with real systemd/launchd, platform-specific, auto-cleanup
- GitHub Actions CI: runs on both ubuntu-latest and macos-latest
- CI status badge in README

### Fixed
- `ProtectHome=false` in systemd service (was `read-only`, conflicted with `ReadWritePaths`)
- Added `backups/` to `ReadWritePaths` in systemd service
- `setup-keyfile.sh`: `--force` flag for non-interactive overwrite, `-t 0` TTY detection
- `SHA256SUMS` now includes dotfiles (`.password`) in backups
- `node-ctl.sh health`: no longer crashes when service is not installed

## [0.3.1] - 2026-02-26

### Fixed
- Remove `--sandbox` reference from SKILL.md (internal-only environment)
- macOS: auto-remove quarantine flag on installed binary to avoid Gatekeeper blocking

## [0.3.0] - 2026-02-26

### Added
- `node-ctl.sh info` command — view Node ID without separate script
- Error handling in `install.sh` — friendly messages on network/version failures
- Auto-rollback in `node-ctl.sh update` — restores `.bak` binary if download fails
- `CHANGELOG.md`
- Version and license badges in README
- Environment-based deployment (`--env dev|prod`)
- Separate directories, service names, and configs per environment
- Dev and prod can run side-by-side on the same machine
- `env-common.sh` shared helpers for environment resolution

### Fixed
- Chat example paths now consistent with dev environment
- Install section shows multiple framework paths (OpenClaw, Claude Code, custom)

## [0.1.0] - 2026-02-25

### Added
- Initial release
- `install.sh` — download binary from public GitHub releases
- `setup-keyfile.sh` — create password file for non-interactive operations
- `init-node.sh` — initialize node keys and database
- `node-info.sh` — view Node ID and group info
- `start-node.sh` — start node in foreground
- `install-service.sh` — systemd (Linux) / launchd (macOS) service installation
- `node-ctl.sh` — unified daily operations CLI
  - Service: status, start, stop, restart, logs
  - Operations: health, sign, export, groups, group
  - Maintenance: backup, update, migrate, change-password, uninstall
- `SKILL.md` with full CLI reference, configuration guide, troubleshooting, and maintenance schedule
- README in English and Chinese with agent chat examples

[0.4.0]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.1.0...v0.3.0
[0.1.0]: https://github.com/CoboTest/cobo-tss-node-skill/releases/tag/v0.1.0
