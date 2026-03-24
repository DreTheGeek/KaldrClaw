#!/bin/bash
set -e

echo "========================================="
echo "  KaldrClaw — Initializing ${BOT_NAME:-unknown}"
echo "========================================="

# 1. Set up persistent volume symlinks
# Railway volume is mounted at /app/persist
# Symlink Claude Code's home config and workspace to the volume
mkdir -p /app/persist/.claude /app/persist/workspace /app/persist/workspace/memory

# Claude Code stores sessions, auth, plugins at ~/.claude
ln -sfn /app/persist/.claude /root/.claude

# Workspace where SOUL.md, MEMORY.md, CLAUDE.md live
export WORKSPACE_DIR=/app/persist/workspace

echo "[INIT] Volume symlinks ready"
echo "[INIT] Workspace: $WORKSPACE_DIR"
echo "[INIT] Claude home: /root/.claude -> /app/persist/.claude"

# 2. Start the relay
echo "[INIT] Starting KaldrClaw relay..."
exec bun run /app/src/index.ts
