# cobo-tss-node-skill

🔐 AI agent skill for managing a [Cobo TSS Node](https://www.cobo.com/mpc-wallet) — the client-side MPC threshold signing component for Cobo's co-managed custody.

Works with any AI agent framework that supports skill/plugin systems (OpenClaw, Claude Code, Codex, etc.)

## For Humans 👤

### Install the Skill

Tell your agent:

> Install the cobo-tss-node skill from https://github.com/CoboTest/cobo-tss-node-skill

### Deploy a New TSS Node

> **You:** Deploy a Cobo TSS Node (dev environment) on this machine and start it as a service
>
> **Agent:** ✅ Installed cobo-tss-node v0.12.0 (dev → ~/.cobo-tss-node-dev)
> ✅ Key file created
> ✅ Node initialized — TSS Node ID: `cobo7x3...a9f`
> ✅ Systemd service installed and started
> ⚠️ Save this Node ID for Cobo Portal registration

### Monitor & Troubleshoot

> **You:** Check TSS Node health
>
> **Agent:**
> ✅ Service: running
> ✅ Database: 42KB
> ✅ Config: OK
> 📌 Version: v0.12.0
> 💾 Disk: 28GB available

> **You:** Show me the recent logs
>
> **Agent:** _(displays last 50 lines of service logs)_

> **You:** What groups does this node have?
>
> **Agent:** _(lists MPC groups with threshold, participants, public keys)_

### Routine Maintenance

> **You:** Run a key share checkup for group abc123
>
> **Agent:** ✅ Signature verified — key share is intact

> **You:** Back up the TSS Node
>
> **Agent:** ✅ Backup saved to ~/.cobo-tss-node-dev/backups/20260225-120000/ (db + config + keyfile + checksums)

> **You:** Update to the latest version
>
> **Agent:** Stopping → downloading v0.13.0 → migrating → restarting... ✅ Updated

> **You:** Export key shares for group abc123 (disaster recovery)
>
> **Agent:** ✅ Encrypted shares exported to ~/.cobo-tss-node-dev/recovery/20260225-130000/

### Service Control

> **You:** Stop / Start / Restart the TSS Node

> **You:** Uninstall the service (keep data)

## For Agents 🤖

### Install

Clone into your agent's skill directory:

```bash
# OpenClaw
cd ~/.openclaw/workspace/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# Claude Code
cd ~/.claude/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# Or any custom path your agent framework uses for skills
```

After cloning, `SKILL.md` provides complete instructions for all operations. Compatible with any agent framework that reads `SKILL.md` for tool discovery.

[![Version](https://img.shields.io/badge/version-0.3.0-blue)](https://github.com/CoboTest/cobo-tss-node-skill/releases) [![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Related

- [cobo-tss-node-release](https://github.com/CoboTest/cobo-tss-node-release) — Pre-built binaries
- [Cobo MPC Wallet](https://www.cobo.com/mpc-wallet) — Product page

## License

MIT
