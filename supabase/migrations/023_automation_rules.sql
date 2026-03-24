-- ============================================================================
-- 023: Automation Rules
-- Trigger-action workflows that bots (especially Ava) learn and execute.
-- Examples:
--   "When email from [client] → create high-priority task"
--   "When no break in 3 hours → send wellness reminder"
--   "When revenue exceeds $5k monthly → send celebration"
--   "When task overdue by 2 days → escalate priority"
-- Supports cooldowns, max-fire limits, and conditional guards.
-- ============================================================================

CREATE TABLE automation_rules (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT        NOT NULL,
  name                TEXT        NOT NULL,
  description         TEXT,
  is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

  -- Trigger definition
  trigger_type        TEXT        NOT NULL
                                  CHECK (trigger_type IN ('event', 'schedule', 'condition', 'webhook')),
  trigger_config      JSONB       NOT NULL DEFAULT '{}'::jsonb,  -- Event name, cron expression, condition query, etc.

  -- Action definition
  action_type         TEXT        NOT NULL
                                  CHECK (action_type IN ('create_task', 'send_notification', 'send_message', 'update_record', 'call_api', 'run_skill')),
  action_config       JSONB       NOT NULL DEFAULT '{}'::jsonb,  -- What to create, who to notify, etc.

  -- Additional guards
  conditions          JSONB       DEFAULT '{}'::jsonb,  -- Only fire if these conditions are true

  -- Rate limiting
  cooldown_seconds    INT,                           -- Minimum time between firings
  last_fired_at       TIMESTAMPTZ,
  fire_count          INT         DEFAULT 0,
  max_fires           INT,                           -- NULL = unlimited

  -- Status
  status              TEXT        NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active', 'paused', 'disabled', 'error')),
  last_error          TEXT,

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;

-- Active rules per bot (loaded at bot startup)
CREATE INDEX idx_automation_rules_active ON automation_rules (bot_name, is_active)
  WHERE is_active = TRUE;

-- Filter by trigger type (event-driven rules vs. scheduled)
CREATE INDEX idx_automation_rules_trigger ON automation_rules (trigger_type);

-- Status for admin dashboard
CREATE INDEX idx_automation_rules_status ON automation_rules (status);

-- Rules in error state for debugging
CREATE INDEX idx_automation_rules_errors ON automation_rules (status)
  WHERE status = 'error';

CREATE TRIGGER trg_automation_rules_updated
  BEFORE UPDATE ON automation_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
