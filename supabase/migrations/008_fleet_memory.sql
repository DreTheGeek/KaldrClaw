-- ============================================================================
-- 008: Fleet Memory
-- Cross-bot knowledge sharing. Key-value store with rich metadata.
-- Category-based organization. Expiration support for transient facts.
-- The unique constraint on (bot_name, category, key) prevents duplicate entries
-- while allowing different bots to store their own version of the same fact.
-- ============================================================================

CREATE TABLE fleet_memory (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name    TEXT        NOT NULL,                   -- Which bot stored this (or '_fleet' for global)
  category    TEXT        NOT NULL,                   -- 'preference', 'fact', 'context', 'workflow', 'tool_config', etc.
  key         TEXT        NOT NULL,                   -- Lookup key: 'user_timezone', 'preferred_greeting', etc.
  value       TEXT        NOT NULL,                   -- The stored knowledge
  confidence  NUMERIC(3,2) DEFAULT 1.0,              -- 0.0 to 1.0 — how confident the bot is in this fact

  -- Lifecycle
  source      TEXT,                                    -- Where this came from: 'user_stated', 'inferred', 'tool_output'
  expires_at  TIMESTAMPTZ,                            -- NULL = never expires
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,

  metadata    JSONB       DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT uq_fleet_memory_key UNIQUE (bot_name, category, key)
);

ALTER TABLE fleet_memory ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_fleet_memory_bot ON fleet_memory (bot_name);
CREATE INDEX idx_fleet_memory_category ON fleet_memory (category);
CREATE INDEX idx_fleet_memory_lookup ON fleet_memory (bot_name, category, key) WHERE is_active = TRUE;
CREATE INDEX idx_fleet_memory_expires ON fleet_memory (expires_at) WHERE expires_at IS NOT NULL;

CREATE TRIGGER trg_fleet_memory_updated
  BEFORE UPDATE ON fleet_memory
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
