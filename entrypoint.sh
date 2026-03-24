#!/bin/bash
set -e

echo "========================================="
echo "  KaldrClaw — Initializing ${BOT_NAME:-unknown}"
echo "========================================="

# 1. Fix volume permissions (runs as root)
# Railway volumes mount as root — we need node user to own them
mkdir -p /app/persist/.claude /app/persist/workspace /app/persist/workspace/memory
chown -R node:node /app/persist

# Symlink Claude Code home to the volume
ln -sfn /app/persist/.claude /home/node/.claude
chown -h node:node /home/node/.claude

echo "[INIT] Volume permissions fixed"
echo "[INIT] Workspace: /app/persist/workspace"

# 2. Drop to node user and start the relay
echo "[INIT] Starting KaldrClaw relay as node user..."
exec gosu node env \
  HOME=/home/node \
  WORKSPACE_DIR=/app/persist/workspace \
  bun run /app/src/index.ts
