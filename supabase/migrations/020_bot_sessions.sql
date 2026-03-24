-- ============================================================================
-- 020: Bot Sessions
-- Tracks every Claude Code session across the fleet for health monitoring,
-- resource accounting, and crash recovery. The orchestrator uses this to
-- know which bots are alive, which need restarts, and how much context
-- each bot has consumed.
-- ============================================================================

CREATE TABLE bot_sessions (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT        NOT NULL,
  session_id          TEXT        NOT NULL,          -- Claude Code's own session identifier

  -- Lifecycle
  status              TEXT        NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active', 'idle', 'crashed', 'terminated', 'compacted')),
  model_used          TEXT,                          -- sonnet, opus, haiku, etc.
  started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at      TIMESTAMPTZ DEFAULT NOW(),
  ended_at            TIMESTAMPTZ,

  -- Resource tracking
  tokens_consumed     INT         DEFAULT 0,
  messages_processed  INT         DEFAULT 0,
  tools_used          INT         DEFAULT 0,
  errors_encountered  INT         DEFAULT 0,

  -- Context management
  compaction_count    INT         DEFAULT 0,         -- How many times context was compacted
  current_context_pct NUMERIC(5,2),                  -- Estimated context usage % (0.00–100.00)

  -- Health monitoring
  last_heartbeat_at   TIMESTAMPTZ DEFAULT NOW(),
  health_status       TEXT        NOT NULL DEFAULT 'healthy'
                                  CHECK (health_status IN ('healthy', 'degraded', 'unresponsive')),

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE bot_sessions ENABLE ROW LEVEL SECURITY;

-- Active sessions per bot (fleet dashboard)
CREATE INDEX idx_bot_sessions_active ON bot_sessions (bot_name, status)
  WHERE status IN ('active', 'idle');

-- Session lookup by Claude Code session ID
CREATE INDEX idx_bot_sessions_session_id ON bot_sessions (session_id);

-- Health checks: find unresponsive bots
CREATE INDEX idx_bot_sessions_heartbeat ON bot_sessions (last_heartbeat_at)
  WHERE status = 'active';

-- Health status filter
CREATE INDEX idx_bot_sessions_health ON bot_sessions (health_status)
  WHERE health_status != 'healthy';

-- Chronological session history
CREATE INDEX idx_bot_sessions_started ON bot_sessions (bot_name, started_at DESC);

CREATE TRIGGER trg_bot_sessions_updated
  BEFORE UPDATE ON bot_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
