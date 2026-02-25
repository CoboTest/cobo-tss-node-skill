# cobo-tss-node-skill

🔐 AI Agent 技能：管理 [Cobo TSS Node](https://www.cobo.com/mpc-wallet) — Cobo MPC 联合托管方案的客户端门限签名节点。

支持任何具备技能/插件系统的 AI Agent 框架（OpenClaw、Claude Code、Codex 等）。

## For Humans 👤

### 安装技能

告诉你的 AI Agent：

> 从 https://github.com/CoboTest/cobo-tss-node-skill 安装 cobo-tss-node 技能

### 部署新节点

> **你:** 在这台机器上部署一个 Cobo TSS Node（dev 环境），安装为服务并启动
>
> **Agent:** ✅ 安装 cobo-tss-node v0.12.0 完成（dev → ~/.cobo-tss-node-dev）
> ✅ 密钥文件已创建
> ✅ 节点初始化完成 — TSS Node ID: `cobo7x3...a9f`
> ✅ systemd 服务已安装并启动
> ⚠️ 请保存 Node ID，在 Cobo Portal 注册时需要

### 监控与排查

> **你:** 检查 TSS Node 运行状态
>
> **Agent:**
> ✅ 服务：运行中
> ✅ 数据库：42KB
> ✅ 配置文件：正常
> 📌 版本：v0.12.0
> 💾 磁盘剩余：28GB

> **你:** 看下最近的日志
>
> **Agent:**_（显示最近 50 行服务日志）_

> **你:** 这个节点有哪些 group？
>
> **Agent:**_（列出 MPC group 及其门限、参与方、公钥）_

### 日常维护

> **你:** 对 group abc123 做一次密钥分片校验
>
> **Agent:** ✅ 签名验证通过 — 密钥分片完好

> **你:** 备份 TSS Node
>
> **Agent:** ✅ 备份已保存到 ~/.cobo-tss-node/backups/20260225-120000/（数据库 + 配置 + 密钥文件 + 校验和）

> **你:** 升级到最新版本
>
> **Agent:** 停止服务 → 下载 v0.13.0 → 数据库迁移 → 重启... ✅ 升级完成

> **你:** 导出 group abc123 的密钥分片（灾难恢复用）
>
> **Agent:** ✅ 加密分片已导出到 ~/.cobo-tss-node/recovery/20260225-130000/

### 服务控制

> **你:** 停止 / 启动 / 重启 TSS Node

> **你:** 卸载服务（保留数据）

## For Agents 🤖

### 安装

克隆到你的 Agent 技能目录：

```bash
# OpenClaw
cd ~/.openclaw/workspace/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# Claude Code
cd ~/.claude/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# 或你的 Agent 框架使用的任意技能目录
```

克隆后，`SKILL.md` 包含所有操作的完整说明。兼容任何读取 `SKILL.md` 进行工具发现的 Agent 框架。

## 相关项目

- [cobo-tss-node-release](https://github.com/CoboTest/cobo-tss-node-release) — 预编译二进制
- [Cobo MPC Wallet](https://www.cobo.com/mpc-wallet) — 产品页面

## 协议

MIT
