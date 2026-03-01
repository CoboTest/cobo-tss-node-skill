# cobo-tss-node-skill

[![Version](https://img.shields.io/badge/version-0.4.0-blue)](https://github.com/CoboTest/cobo-tss-node-skill/releases)
[![Tests](https://github.com/CoboTest/cobo-tss-node-skill/actions/workflows/test.yml/badge.svg)](https://github.com/CoboTest/cobo-tss-node-skill/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey)]()
[![Shell](https://img.shields.io/badge/shell-bash-orange)]()

[🇬🇧 English](README.md)

🔐 用于管理 [Cobo TSS Node](https://www.cobo.com/mpc-wallet) 的 AI Agent 技能 —— Cobo 共管托管方案中客户端 MPC 门限签名组件。

适用于任何支持技能/插件系统的 AI Agent 框架（OpenClaw、Claude Code、Codex 等）。

## 给用户 👤

### 安装技能

告诉你的 Agent：

> 从 https://github.com/CoboTest/cobo-tss-node-skill 安装 cobo-tss-node 技能

### 部署新的 TSS Node

> **你：** 在这台机器上部署一个 Cobo TSS Node（dev 环境），并启动为系统服务
>
> **Agent：** ✅ 已安装 cobo-tss-node v0.12.0（dev → ~/.cobo-tss-node-dev）
> ✅ 密钥文件已创建
> ✅ 节点已初始化 —— TSS Node ID：`cobo7x3...a9f`
> ✅ Systemd 服务已安装并启动
> ⚠️ 请保存此 Node ID 用于 Cobo Portal 注册

### 监控与排障

> **你：** 检查 TSS Node 健康状态
>
> **Agent：**
> ✅ 服务：运行中
> ✅ 数据库：42KB
> ✅ 配置：正常
> 📌 版本：v0.12.0
> 💾 磁盘剩余：28GB

> **你：** 看看最近的日志
>
> **Agent：** _（显示最近 50 行服务日志）_

> **你：** 这个节点有哪些 group？
>
> **Agent：** _（列出 MPC 分组：阈值、参与方、公钥）_

### 日常维护

> **你：** 对 group abc123 做一次密钥份额检查
>
> **Agent：** ✅ 签名验证通过 —— 密钥份额完好

> **你：** 备份 TSS Node
>
> **Agent：** ✅ 备份已保存到 ~/.cobo-tss-node-dev/backups/20260225-120000/（数据库 + 配置 + 密钥文件 + 校验和）

> **你：** 升级到最新版本
>
> **Agent：** 停止 → 下载 v0.13.0 → 迁移数据库 → 重启... ✅ 升级完成

> **你：** 导出 group abc123 的密钥份额（灾难恢复）
>
> **Agent：** ✅ 加密份额已导出到 ~/.cobo-tss-node-dev/recovery/20260225-130000/

### 服务控制

> **你：** 停止 / 启动 / 重启 TSS Node

> **你：** 卸载服务（保留数据）

## 给 Agent 🤖

### 安装

克隆到 Agent 的技能目录：

```bash
# OpenClaw
cd ~/.openclaw/workspace/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# Claude Code
cd ~/.claude/skills && git clone https://github.com/CoboTest/cobo-tss-node-skill.git cobo-tss-node

# 或者你的 Agent 框架使用的任何自定义路径
```

克隆后，`SKILL.md` 提供所有操作的完整指令。兼容任何读取 `SKILL.md` 进行工具发现的 Agent 框架。

## 相关链接

- [cobo-tss-node-release](https://github.com/CoboTest/cobo-tss-node-release) — 预编译二进制
- [Cobo MPC 钱包](https://www.cobo.com/mpc-wallet) — 产品页面

## 许可证

MIT
