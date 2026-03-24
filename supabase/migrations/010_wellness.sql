-- ============================================================================
-- 010: Accountability / Wellness
-- Daily check-ins tracking fitness, sleep, breaks, hydration, family time,
-- diet. Goals vs actuals. Streaks. This is how Ava holds Dre accountable.
-- One row per day per category, so the bot can query "did you work out today?"
-- ============================================================================

CREATE TABLE wellness (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT        NOT NULL DEFAULT 'ava',
  tracking_date   DATE        NOT NULL,
  category        TEXT        NOT NULL
                              CHECK (category IN (
                                'fitness', 'sleep', 'hydration', 'breaks',
                                'family_time', 'diet', 'mental_health', 'screen_time'
                              )),

  -- Tracking
  goal_value      NUMERIC(10,2),                       -- Target: 8 (hours sleep), 4 (workouts/week), 64 (oz water)
  goal_unit       TEXT,                                 -- 'hours', 'count', 'oz', 'minutes', etc.
  actual_value    NUMERIC(10,2),                        -- What actually happened
  completed       BOOLEAN     NOT NULL DEFAULT FALSE,   -- Did they meet the goal?

  -- Streak tracking
  streak_days     INT         NOT NULL DEFAULT 0,       -- Current consecutive days meeting this goal
  longest_streak  INT         NOT NULL DEFAULT 0,       -- All-time best streak

  -- Details
  notes           TEXT,                                  -- "Ran 3 miles at park", "Skipped — back pain"
  mood            TEXT        CHECK (mood IS NULL OR mood IN ('great', 'good', 'okay', 'rough', 'bad')),
  energy_level    INT         CHECK (energy_level IS NULL OR (energy_level >= 1 AND energy_level <= 10)),

  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),

  -- One entry per day per category
  CONSTRAINT uq_wellness_daily UNIQUE (bot_name, tracking_date, category)
);

ALTER TABLE wellness ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_wellness_date ON wellness (tracking_date DESC);
CREATE INDEX idx_wellness_category ON wellness (category, tracking_date DESC);
CREATE INDEX idx_wellness_streaks ON wellness (category, streak_days DESC);
CREATE INDEX idx_wellness_bot_date ON wellness (bot_name, tracking_date DESC);

CREATE TRIGGER trg_wellness_updated
  BEFORE UPDATE ON wellness
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
