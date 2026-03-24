-- ============================================================================
-- 011: Goals & Commitments
-- "Work out 4x this week", "Ship HVAC by April 15", "Family dinner every night"
-- Measurable targets with progress tracking. Bots check these daily to nudge
-- the user and report on progress in briefings.
-- ============================================================================

CREATE TABLE goals (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  title           TEXT        NOT NULL,                -- "Work out 4x this week"
  description     TEXT,
  category        TEXT        NOT NULL
                              CHECK (category IN (
                                'fitness', 'business', 'family', 'health', 'learning',
                                'financial', 'creative', 'social', 'spiritual', 'other'
                              )),
  status          TEXT        NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active', 'completed', 'abandoned', 'paused')),

  -- Measurement
  target_value    NUMERIC(10,2),                       -- 4 (workouts), 1 (ship it), 5000 (revenue)
  target_unit     TEXT,                                 -- 'count', 'dollars', 'boolean', 'hours'
  current_value   NUMERIC(10,2) DEFAULT 0,
  progress_pct    NUMERIC(5,2) DEFAULT 0,              -- 0.00 to 100.00

  -- Timeframe
  timeframe       TEXT        CHECK (timeframe IS NULL OR timeframe IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly', 'one_time')),
  start_date      DATE,
  target_date     DATE,
  completed_at    TIMESTAMPTZ,

  -- Ownership
  owner           TEXT        NOT NULL DEFAULT 'dre',
  bot_name        TEXT,                                -- Which bot tracks this
  project_id      UUID        REFERENCES projects(id) ON DELETE SET NULL,

  -- Accountability
  check_in_frequency TEXT     DEFAULT 'daily',         -- How often the bot should ask about progress
  last_check_in   TIMESTAMPTZ,
  reminders_enabled BOOLEAN   NOT NULL DEFAULT TRUE,

  tags            TEXT[]      DEFAULT '{}',
  notes           TEXT,
  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE goals ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_goals_status ON goals (status);
CREATE INDEX idx_goals_category ON goals (category);
CREATE INDEX idx_goals_owner ON goals (owner);
CREATE INDEX idx_goals_target_date ON goals (target_date) WHERE status = 'active';
CREATE INDEX idx_goals_checkin ON goals (last_check_in) WHERE status = 'active' AND reminders_enabled = TRUE;
CREATE INDEX idx_goals_project ON goals (project_id) WHERE project_id IS NOT NULL;

CREATE TRIGGER trg_goals_updated
  BEFORE UPDATE ON goals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
