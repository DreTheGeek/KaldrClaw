-- ============================================================================
-- 009: Briefing History
-- Morning (9 AM), midday, evening, wind-down (11 PM) briefings.
-- Stores the full content, what data sources were consulted, delivery time,
-- and whether the user acknowledged it. Bots reference past briefings to
-- avoid repeating information and to track what was communicated.
-- ============================================================================

CREATE TABLE briefings (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT        NOT NULL,
  briefing_type   TEXT        NOT NULL
                              CHECK (briefing_type IN ('morning', 'midday', 'evening', 'wind_down', 'ad_hoc')),
  briefing_date   DATE        NOT NULL,               -- The date this briefing covers

  -- Content
  content         TEXT        NOT NULL,                -- The full briefing text as delivered
  sections        JSONB       DEFAULT '[]'::jsonb,     -- [{section_name, content, data_source}]
  data_sources    TEXT[]      DEFAULT '{}',            -- ['email', 'calendar', 'revenue', 'tasks', 'wellness']

  -- Delivery
  delivered_at    TIMESTAMPTZ,
  acknowledged    BOOLEAN     NOT NULL DEFAULT FALSE,
  acknowledged_at TIMESTAMPTZ,
  delivery_channel TEXT       DEFAULT 'telegram',      -- 'telegram', 'email', etc.

  -- Quality
  items_count     INT,                                 -- How many items were in the briefing
  action_items    JSONB       DEFAULT '[]'::jsonb,     -- [{description, priority, due}]

  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW()
  -- No updated_at — briefings are effectively immutable once delivered
);

ALTER TABLE briefings ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_briefings_bot_date ON briefings (bot_name, briefing_date DESC);
CREATE INDEX idx_briefings_type ON briefings (briefing_type, briefing_date DESC);
CREATE INDEX idx_briefings_unacked ON briefings (acknowledged) WHERE acknowledged = FALSE;
CREATE UNIQUE INDEX idx_briefings_unique_per_day ON briefings (bot_name, briefing_type, briefing_date);
