#!/bin/bash
set -e

echo "========================================="
echo "  KaldrClaw — Initializing ${BOT_NAME:-unknown}"
echo "========================================="

# 1. Set up persistent volume symlinks
# Railway volume is mounted at /app/persist
mkdir -p /app/persist/.claude /app/persist/workspace /app/persist/workspace/memory

# Claude Code stores sessions, auth, plugins at ~/.claude
# node user home is /home/node
ln -sfn /app/persist/.claude /home/node/.claude

# Workspace where SOUL.md, MEMORY.md, CLAUDE.md live
export WORKSPACE_DIR=/app/persist/workspace
export HOME=/home/node

echo "[INIT] Volume symlinks ready"
echo "[INIT] Workspace: $WORKSPACE_DIR"
echo "[INIT] Claude home: /home/node/.claude -> /app/persist/.claude"
echo "[INIT] Running as: $(whoami)"

# 2. Start the relay
echo "[INIT] Starting KaldrClaw relay..."
exec bun run /app/src/index.ts
