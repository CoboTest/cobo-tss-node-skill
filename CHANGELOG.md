# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] - 2026-02-26

### Added
- `node-ctl.sh info` command — view Node ID without separate script
- Error handling in `install.sh` — friendly messages on network/version failures
- Auto-rollback in `node-ctl.sh update` — restores `.bak` binary if download fails
- `CHANGELOG.md`
- Version and license badges in README

### Fixed
- Chat example paths now consistent with dev environment
- For Agents install section now shows multiple framework paths (OpenClaw, Claude Code)

## [0.3.0] - 2026-02-26

### Added
- `node-ctl.sh info` command — view Node ID and metadata
- Error handling in `install.sh` with friendly messages for network/version failures
- Auto-rollback in `node-ctl.sh update` if download fails
- `CHANGELOG.md`
- Version and license badges in README

### Changed
- Agent install paths now show OpenClaw and Claude Code examples
- Chat examples use consistent dev environment paths

## [0.2.0] - 2026-02-26

### Added
- Environment-based deployment (`--env dev|prod`)
- Separate directories, service names, and configs per environment
- Dev and prod can run side-by-side on the same machine
- `env-common.sh` shared helpers for environment resolution
- `.env` marker file for auto-detection

### Changed
- All scripts now require `--env <dev|prod>` parameter

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

[0.3.0]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.2.0...v0.3.0
[0.3.0]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/CoboTest/cobo-tss-node-skill/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/CoboTest/cobo-tss-node-skill/releases/tag/v0.1.0
