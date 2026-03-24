-- ============================================================================
-- 014: Reminders / Scheduled Actions
-- Persistent reminders that survive container restarts. Replaces /loop for
-- critical schedules. Supports one-time and recurring patterns.
-- The bot queries "what reminders are due?" every few minutes.
-- ============================================================================

CREATE TABLE reminders (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT        NOT NULL,
  title           TEXT        NOT NULL,
  description     TEXT,

  -- Scheduling
  remind_at       TIMESTAMPTZ NOT NULL,                -- When to fire (next occurrence for recurring)
  is_recurring    BOOLEAN     NOT NULL DEFAULT FALSE,
  recurrence_rule TEXT,                                -- 'daily', 'weekdays', 'weekly', 'monthly', cron expression
  recurrence_end  TIMESTAMPTZ,                         -- When to stop recurring (NULL = forever)

  -- Status
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'delivered', 'snoozed', 'cancelled', 'expired')),
  delivered_at    TIMESTAMPTZ,
  snoozed_until   TIMESTAMPTZ,
  delivery_count  INT         NOT NULL DEFAULT 0,      -- How many times this has fired (for recurring)

  -- Delivery
  delivery_channel TEXT       NOT NULL DEFAULT 'telegram',
  priority        TEXT        NOT NULL DEFAULT 'medium'
                              CHECK (priority IN ('critical', 'high', 'medium', 'low')),

  -- Context
  related_id      UUID,                                -- FK to task, goal, contact, etc.
  related_type    TEXT,                                -- 'task', 'goal', 'contact', 'project'
  action_type     TEXT,                                -- 'remind', 'check_in', 'follow_up', 'deadline_warning'
  created_by      TEXT        NOT NULL DEFAULT 'dre',

  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_reminders_due ON reminders (remind_at)
  WHERE status IN ('pending', 'snoozed');
CREATE INDEX idx_reminders_bot ON reminders (bot_name, status);
CREATE INDEX idx_reminders_status ON reminders (status);
CREATE INDEX idx_reminders_recurring ON reminders (is_recurring, remind_at)
  WHERE is_recurring = TRUE AND status = 'pending';
CREATE INDEX idx_reminders_related ON reminders (related_type, related_id)
  WHERE related_id IS NOT NULL;

CREATE TRIGGER trg_reminders_updated
  BEFORE UPDATE ON reminders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
