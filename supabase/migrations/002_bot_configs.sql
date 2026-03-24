-- ============================================================================
-- 002: Bot Identity & Configuration
-- The core table that makes KaldrClaw universal. Every bot loads its soul,
-- personality, agent config, skills, and MCP overrides from here at boot.
-- Supports versioning so you can roll back personality changes.
-- ============================================================================

CREATE TABLE bot_configs (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name      TEXT        NOT NULL,
  version       INT         NOT NULL DEFAULT 1,
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,

  -- Identity / Soul
  display_name  TEXT        NOT NULL,
  role          TEXT        NOT NULL,                -- 'chief_of_staff', 'sales', 'content', 'research', etc.
  personality   TEXT,                                 -- Free-text soul description
  seed_memory   JSONB       DEFAULT '[]'::jsonb,     -- Array of initial knowledge items loaded at boot

  -- Agent configuration
  model         TEXT        NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  max_turns     INT         NOT NULL DEFAULT 25,
  effort        TEXT        NOT NULL DEFAULT 'medium' CHECK (effort IN ('low', 'medium', 'high')),
  autonomy      TEXT        NOT NULL DEFAULT 'supervised' CHECK (autonomy IN ('supervised', 'semi_autonomous', 'fully_autonomous')),
  temperature   NUMERIC(3,2) DEFAULT 0.7,

  -- Capabilities
  skills        JSONB       DEFAULT '[]'::jsonb,     -- Array of skill names/paths
  mcp_overrides JSONB       DEFAULT '{}'::jsonb,     -- Per-bot MCP server config overrides
  plugins       JSONB       DEFAULT '[]'::jsonb,     -- Plugin names enabled for this bot
  tools_allowed JSONB       DEFAULT '[]'::jsonb,     -- Explicit tool allowlist (empty = all)
  tools_denied  JSONB       DEFAULT '[]'::jsonb,     -- Explicit tool denylist

  -- Scheduling
  schedule      JSONB       DEFAULT '{}'::jsonb,     -- Cron-style schedule config (briefings, loops, etc.)
  timezone      TEXT        NOT NULL DEFAULT 'America/New_York',

  -- Metadata
  notes         TEXT,
  metadata      JSONB       DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),

  -- Only one active version per bot
  CONSTRAINT uq_bot_active_version UNIQUE (bot_name, version)
);

ALTER TABLE bot_configs ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_bot_configs_name ON bot_configs (bot_name);
CREATE INDEX idx_bot_configs_active ON bot_configs (bot_name, is_active) WHERE is_active = TRUE;

CREATE TRIGGER trg_bot_configs_updated
  BEFORE UPDATE ON bot_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
