---
name: cobo-tss-node
description: "Manage a Cobo TSS Node for MPC threshold signing. Use when: setting up a new TSS Node, starting/stopping the node service, checking node status or health, signing for key share checkups, exporting shares for disaster recovery, backing up or updating the node, installing as a systemd or launchd service. NOT for: Cobo WaaS API integration, on-chain transaction building, or wallet UI."
version: 0.4.0
metadata:
  {
    "openclaw":
      {
        "emoji": "🔐",
        "requires": { "bins": ["curl", "python3"] },
      },
  }
---

# Cobo TSS Node

Manage a Cobo TSS Node — the client-side MPC signing component for Cobo's co-managed custody.

## When to Use

✅ **USE this skill when:**

- Installing the Cobo TSS Node binary
- Initializing a new TSS Node (generating keys + Node ID)
- Starting/stopping/restarting the node service
- Installing as a system service (Linux systemd / macOS launchd)
- Checking node health, viewing groups, or reading logs
- Periodic key share checkup signing
- Exporting shares for disaster recovery
- Backing up or updating the node

❌ **DON'T use this skill when:**

- Interacting with Cobo WaaS REST API → use Cobo SDK
- Building on-chain transactions directly
- Managing Cobo Portal (web UI operations)

## Environments

| Environment | Default Directory | Start Flag | Service Name |
|-------------|-------------------|------------|--------------|
| `dev` | `~/.cobo-tss-node-dev` | `--dev` | `cobo-tss-node-dev` |
| `prod` | `~/.cobo-tss-node` | `--prod` | `cobo-tss-node` |

All scripts require `--env <dev|prod>`. Dev and prod can run side-by-side on the same machine with separate data directories, services, and configs.

## Quick Start

```bash
./scripts/install.sh --env dev              # Download binary (dev)
./scripts/setup-keyfile.sh --env dev        # Create password file
./scripts/init-node.sh --env dev            # Initialize (outputs Node ID)
./scripts/install-service.sh linux --env dev  # Install systemd service
./scripts/node-ctl.sh start --env dev       # Start
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/install.sh` | Download binary from GitHub releases |
| `scripts/setup-keyfile.sh` | Create `.password` key file (mode 600) |
| `scripts/init-node.sh` | Initialize node keys and database |
| `scripts/node-info.sh` | View Node ID and group info |
| `scripts/start-node.sh` | Start node in foreground |
| `scripts/install-service.sh` | Install as systemd (Linux) or launchd (macOS) service |
| `scripts/node-ctl.sh` | Unified daily operations CLI |

## Daily Operations

All post-install operations go through `node-ctl.sh`:

```bash
./scripts/node-ctl.sh <command> --env <dev|prod> [--dir DIR]
```

### Node Info

```bash
./scripts/node-ctl.sh info --env prod
```

Displays Node ID and metadata. Equivalent to `cobo-tss-node info`.

### Service Management

| Command | Description |
|---------|-------------|
| `status` | Show service status (systemctl/launchctl) |
| `start` | Start the TSS Node service |
| `stop` | Stop the service |
| `restart` | Restart the service |
| `logs` | View recent logs (last 50 lines) |
| `logs -f` | Tail logs in real time |
| `logs --lines=200` | View more log lines |

Linux uses `journalctl`, macOS reads from `~/.cobo-tss-node/logs/launchd-stdout.log`.

### Health Check

```bash
./scripts/node-ctl.sh health
```

Checks in one command:
- ✅/❌ Service running status
- 📌 Binary version
- ✅/❌ Database exists + file size
- ✅/❌ Config file present
- ✅/⚠️ Key file permissions (must be 600)
- 💾 Available disk space
- 📋 Node ID and metadata

### MPC Group Management

```bash
./scripts/node-ctl.sh groups              # List all MPC groups
./scripts/node-ctl.sh group <group-id>    # Inspect a specific group
```

Shows group details: participants, threshold, public key, protocol type.

### Key Share Checkup (Periodic Signing)

```bash
./scripts/node-ctl.sh sign <group-id> [message]
```

- ⚠️ **This is NOT an MPC co-signing operation.** It uses the local key share directly to sign a message, verifying that the share exists and is intact.
- Purpose: prove key share integrity — confirm the share hasn't been corrupted or lost
- If no message given, auto-generates: `checkup-YYYY-MM-DD`
- **Recommended:** run weekly or after any infrastructure changes
- This is a local-only operation (no network/WebSocket needed, no MPC ceremony involved)

### Disaster Recovery Export

```bash
./scripts/node-ctl.sh export <group-id1,group-id2,...>
```

- Exports encrypted key share files to a timestamped directory: `~/.cobo-tss-node/recovery/YYYYMMDD-HHMMSS/`
- Exported files are encrypted — need the database password to restore
- **Recommended:** export after every keygen or key reshare, store offsite

### Backup

```bash
./scripts/node-ctl.sh backup
```

Creates a timestamped backup at `~/.cobo-tss-node/backups/YYYYMMDD-HHMMSS/` containing:
- `secrets.db` — encrypted database (key shares, session data)
- `cobo-tss-node-config.yaml` — configuration
- `.password` — key file
- `SHA256SUMS` — integrity checksums

⚠️ Store backups securely — contains everything needed to restore the node.

### Update Binary

```bash
./scripts/node-ctl.sh update                    # Update to latest
./scripts/node-ctl.sh update --version=v0.13.0  # Update to specific version
```

What it does:
1. Stops the service
2. Backs up current binary as `cobo-tss-node.bak`
3. Downloads and installs new version
4. Runs database migration (if needed)
5. Restarts the service
6. Shows new version

### Database Migration

```bash
./scripts/node-ctl.sh migrate              # Run migration
./scripts/node-ctl.sh migrate --dry-run    # Preview only
```

Run after binary updates. The `update` command does this automatically.

### Change Password

```bash
./scripts/node-ctl.sh change-password
```

Changes the database encryption password. Also updates the key file.

### Uninstall Service

```bash
./scripts/node-ctl.sh uninstall
```

Removes the systemd/launchd service but **keeps all data** in `~/.cobo-tss-node/`. To fully remove: `rm -rf ~/.cobo-tss-node`.

## Recommended Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Health check | Daily | `node-ctl.sh health --env prod` |
| Key share checkup | Weekly | `node-ctl.sh sign --env prod <group-id>` |
| Backup | Weekly | `node-ctl.sh backup --env prod` |
| Log review | Weekly | `node-ctl.sh logs --env prod --lines=500` |
| Export shares | After keygen/reshare | `node-ctl.sh export --env prod <group-ids>` |
| Update binary | On new release | `node-ctl.sh update --env prod` |
| Password rotation | Quarterly | `node-ctl.sh change-password --env prod` |

## Configuration Reference

Config file: `~/.cobo-tss-node/configs/cobo-tss-node-config.yaml`

Key sections:
- **`env`**: `development` / `production`
- **`db.path`**: database file path
- **`callback.cb_server`**: risk control callback URL + public key (v1)
- **`callback.cb_server_v2`**: risk control callback URL + public key (v2)
- **`event.server`**: event publish endpoints (keygen/keysign/reshare notifications)
- **`embedded_risk_control_rules`**: local allow/reject rules for keygen, keysign, reshare
- **`log`**: stdout + file logging config
- **`metrics`**: InfluxDB monitoring endpoint

## Directory Layout

```
# Production: ~/.cobo-tss-node/
# Development: ~/.cobo-tss-node-dev/

~/.cobo-tss-node/                    # (or ~/.cobo-tss-node-dev/)
├── cobo-tss-node                    # binary
├── cobo-tss-node.bak               # previous binary (after update)
├── .password                        # key file (chmod 600)
├── .env                             # environment marker (dev/prod)
├── configs/
│   ├── cobo-tss-node-config.yaml           # active config
│   └── cobo-tss-node-config.yaml.template  # template reference
├── db/
│   └── secrets.db                   # AES-GCM encrypted database
├── logs/                            # log files
├── recovery/                        # exported key shares
│   └── YYYYMMDD-HHMMSS/
└── backups/                         # full backups
    └── YYYYMMDD-HHMMSS/
        ├── secrets.db
        ├── cobo-tss-node-config.yaml
        ├── .password
        └── SHA256SUMS
```

## Key Design Decisions

- **`--key-file`** used on all commands for non-interactive operation (required for service mode)
- **Database** is AES-GCM encrypted; `.password` file must be mode `600`
- **Linux service** runs with `NoNewPrivileges`, `ProtectSystem=strict`, `ReadWritePaths` limited to db/logs/recovery
- **macOS agent** uses `KeepAlive` + `ThrottleInterval` for auto-restart on failure
- **Backups** include SHA256 checksums for integrity verification

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Service won't start | Missing config file | `cp configs/*.template configs/cobo-tss-node-config.yaml` |
| "password" prompt on start | Missing `--key-file` | Reinstall service: `install-service.sh linux` |
| Permission denied on `.password` | Wrong file mode | `chmod 600 ~/.cobo-tss-node/.password` |
| Init fails | DB already exists | Check with `node-info.sh`; delete `db/secrets.db` only if intentional |
| WebSocket connection failed | Wrong environment flag | Match `--dev`/`--prod` to your Cobo Portal environment |
| Service exits immediately | Port or resource conflict | Check `node-ctl.sh logs` for error details |
| Migration fails | Version incompatibility | Try `migrate --dry-run` first; contact Cobo support if persistent |
