-- ============================================================================
-- 005: Activity Log
-- Append-only audit trail of what each bot did and when.
-- Actions, tool usage, errors. JSONB details for maximum flexibility.
-- This table will grow fast — designed for partitioning/cleanup via pg_cron.
-- ============================================================================

CREATE TABLE activity_log (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name    TEXT        NOT NULL,
  action      TEXT        NOT NULL,                   -- 'briefing_sent', 'task_created', 'email_triaged', 'error', etc.
  category    TEXT,                                    -- 'task', 'email', 'calendar', 'revenue', 'system', 'error'
  severity    TEXT        NOT NULL DEFAULT 'info'
                          CHECK (severity IN ('debug', 'info', 'warn', 'error', 'critical')),

  -- What happened
  summary     TEXT,                                    -- Human-readable one-liner
  details     JSONB       DEFAULT '{}'::jsonb,         -- Full structured payload (tool args, response, error stack, etc.)

  -- Context
  related_id  UUID,                                    -- FK to whatever entity this action relates to
  related_type TEXT,                                   -- 'task', 'project', 'briefing', 'email_summary', etc.
  session_id  TEXT,                                    -- Claude Code session identifier
  duration_ms INT,                                     -- How long the action took

  created_at  TIMESTAMPTZ DEFAULT NOW()
  -- No updated_at — this is append-only
);

ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_activity_bot ON activity_log (bot_name, created_at DESC);
CREATE INDEX idx_activity_action ON activity_log (action);
CREATE INDEX idx_activity_category ON activity_log (category);
CREATE INDEX idx_activity_severity ON activity_log (severity) WHERE severity IN ('warn', 'error', 'critical');
CREATE INDEX idx_activity_created ON activity_log (created_at DESC);
CREATE INDEX idx_activity_related ON activity_log (related_type, related_id) WHERE related_id IS NOT NULL;
