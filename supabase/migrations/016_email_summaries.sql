-- ============================================================================
-- 016: Email Summaries
-- When the bot triages email, it stores structured summaries here.
-- Briefings reference these. The user can ask "any important emails today?"
-- and the bot answers from this table, not by re-reading Gmail.
-- ============================================================================

CREATE TABLE email_summaries (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT        NOT NULL,

  -- Email identity
  gmail_id        TEXT,                                -- Gmail message ID for deduplication
  thread_id       TEXT,                                -- Gmail thread ID

  -- Parsed fields
  sender_name     TEXT,
  sender_email    TEXT        NOT NULL,
  recipients      TEXT[],                              -- To/CC addresses
  subject         TEXT        NOT NULL,
  received_at     TIMESTAMPTZ NOT NULL,

  -- Bot analysis
  summary         TEXT        NOT NULL,                -- Bot's 1-3 sentence summary
  urgency         TEXT        NOT NULL DEFAULT 'normal'
                              CHECK (urgency IN ('critical', 'high', 'normal', 'low', 'spam')),
  category        TEXT,                                -- 'client', 'billing', 'legal', 'newsletter', 'personal', etc.
  sentiment       TEXT,                                -- 'positive', 'neutral', 'negative', 'urgent'

  -- Actions
  action_needed   BOOLEAN     NOT NULL DEFAULT FALSE,
  action_type     TEXT,                                -- 'reply', 'forward', 'schedule', 'pay', 'review', 'none'
  action_summary  TEXT,                                -- "Reply with updated timeline by Friday"
  action_done     BOOLEAN     NOT NULL DEFAULT FALSE,
  action_done_at  TIMESTAMPTZ,

  -- Follow-up
  followup_date   DATE,
  contact_id      UUID        REFERENCES contacts(id) ON DELETE SET NULL,

  -- Triage
  triaged_at      TIMESTAMPTZ DEFAULT NOW(),
  included_in_briefing UUID   REFERENCES briefings(id),

  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE email_summaries ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_email_gmail_id ON email_summaries (gmail_id) WHERE gmail_id IS NOT NULL;
CREATE INDEX idx_email_thread ON email_summaries (thread_id) WHERE thread_id IS NOT NULL;
CREATE INDEX idx_email_sender ON email_summaries (sender_email);
CREATE INDEX idx_email_urgency ON email_summaries (urgency) WHERE urgency IN ('critical', 'high');
CREATE INDEX idx_email_action ON email_summaries (action_needed, action_done)
  WHERE action_needed = TRUE AND action_done = FALSE;
CREATE INDEX idx_email_followup ON email_summaries (followup_date)
  WHERE followup_date IS NOT NULL AND action_done = FALSE;
CREATE INDEX idx_email_received ON email_summaries (received_at DESC);
CREATE INDEX idx_email_contact ON email_summaries (contact_id) WHERE contact_id IS NOT NULL;

CREATE TRIGGER trg_email_summaries_updated
  BEFORE UPDATE ON email_summaries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
