-- ============================================================================
-- 006: Decisions
-- Decisions made by the user (or bots) that the fleet should remember and
-- never re-ask about. "We're using Railway, not Fly.io." "Stripe for payments."
-- Bots query this before making suggestions to avoid contradicting past decisions.
-- ============================================================================

CREATE TABLE decisions (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  topic         TEXT        NOT NULL,                 -- Short label: 'hosting', 'payment_processor', 'bot_framework'
  decision      TEXT        NOT NULL,                 -- The actual decision: "Use Railway for hosting"
  reasoning     TEXT,                                  -- Why this was chosen
  alternatives  JSONB       DEFAULT '[]'::jsonb,      -- [{name, reason_rejected}]

  decided_by    TEXT        NOT NULL DEFAULT 'dre',   -- Who made it
  bot_name      TEXT,                                  -- Which bot recorded it (NULL = user-entered)

  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,    -- FALSE = superseded or reversed
  superseded_by UUID        REFERENCES decisions(id), -- Points to the newer decision
  expires_at    TIMESTAMPTZ,                           -- Some decisions are temporary

  tags          TEXT[]      DEFAULT '{}',
  metadata      JSONB       DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE decisions ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_decisions_topic ON decisions (topic);
CREATE INDEX idx_decisions_active ON decisions (is_active) WHERE is_active = TRUE;
CREATE INDEX idx_decisions_bot ON decisions (bot_name);
CREATE INDEX idx_decisions_tags ON decisions USING GIN (tags);

CREATE TRIGGER trg_decisions_updated
  BEFORE UPDATE ON decisions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
