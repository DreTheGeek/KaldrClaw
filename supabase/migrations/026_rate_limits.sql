-- ============================================================================
-- 026: Rate Limits
-- Per-bot per-time-window token consumption tracking and budget management.
-- Prevents runaway costs by tracking input/output tokens, API calls, and
-- estimated USD spend. Supports hourly/daily/weekly/monthly rollups with
-- per-model breakdowns.
-- ============================================================================

CREATE TABLE rate_limits (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT        NOT NULL,

  -- Time window
  period_start        TIMESTAMPTZ NOT NULL,
  period_end          TIMESTAMPTZ NOT NULL,
  period_type         TEXT        NOT NULL
                                  CHECK (period_type IN ('hourly', 'daily', 'weekly', 'monthly')),

  -- Token usage
  tokens_input        INT         DEFAULT 0,
  tokens_output       INT         DEFAULT 0,
  tokens_total        INT         DEFAULT 0,
  messages_count      INT         DEFAULT 0,
  api_calls           INT         DEFAULT 0,

  -- Model breakdown
  model_usage         JSONB       DEFAULT '{}'::jsonb,  -- {"sonnet": {input: X, output: Y}, "haiku": {...}, "opus": {...}}

  -- Budget
  budget_limit_tokens INT,
  budget_limit_usd    NUMERIC(10,2),
  estimated_cost_usd  NUMERIC(10,2) DEFAULT 0,

  -- Alerts
  limit_hit           BOOLEAN     DEFAULT FALSE,
  limit_hit_at        TIMESTAMPTZ,
  throttled           BOOLEAN     DEFAULT FALSE,

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

-- One row per bot per period (prevents duplicate tracking)
CREATE UNIQUE INDEX idx_rate_limits_unique ON rate_limits (bot_name, period_type, period_start);

-- Primary lookup: current period for a bot
CREATE INDEX idx_rate_limits_lookup ON rate_limits (bot_name, period_type, period_start DESC);

-- Find periods where limits were hit (for alerting/reporting)
CREATE INDEX idx_rate_limits_hit ON rate_limits (limit_hit)
  WHERE limit_hit = TRUE;

-- Throttled bots (orchestrator needs to know)
CREATE INDEX idx_rate_limits_throttled ON rate_limits (throttled)
  WHERE throttled = TRUE;

CREATE TRIGGER trg_rate_limits_updated
  BEFORE UPDATE ON rate_limits
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
