FROM node:20-slim

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest

# Create app directory
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile 2>/dev/null || bun install

# Copy source
COPY . .

# Create persist directory (volume mount point)
RUN mkdir -p /app/persist /app/persist/.claude /app/persist/workspace /app/persist/workspace/memory

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
