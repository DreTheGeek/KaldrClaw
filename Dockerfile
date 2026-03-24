FROM node:20-slim

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates unzip gosu \
    && rm -rf /var/lib/apt/lists/*

# Install Bun (as root, then move to shared path)
RUN curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun /usr/local/bun
ENV PATH="/usr/local/bun/bin:$PATH"

# Install Claude Code CLI + MCP servers (pre-installed so they don't download at runtime)
RUN npm install -g @anthropic-ai/claude-code@latest \
    @supabase/mcp-server-supabase@latest

# Create app directory
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile 2>/dev/null || bun install

# Copy source
COPY . .

# Create persist directory
RUN mkdir -p /app/persist /app/persist/.claude /app/persist/workspace /app/persist/workspace/memory

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Entrypoint runs as root to fix volume permissions, then drops to node
ENTRYPOINT ["/app/entrypoint.sh"]
