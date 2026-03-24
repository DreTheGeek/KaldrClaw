-- ============================================================================
-- 019: Calendar Events (cached from Google Calendar MCP)
-- Caches events locally so morning briefings and schedule queries don't
-- re-fetch from the Google Calendar API every time. Enables conflict
-- detection, prep-note attachment, and historical schedule analysis.
-- ============================================================================

CREATE TABLE calendar_events (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT        NOT NULL,

  -- Google Calendar dedup / sync
  google_event_id     TEXT        NOT NULL,          -- Google's event ID for dedup
  calendar_name       TEXT,                          -- Which calendar (primary, work, personal)

  -- Event basics
  title               TEXT        NOT NULL,
  description         TEXT,
  location            TEXT,
  start_time          TIMESTAMPTZ NOT NULL,
  end_time            TIMESTAMPTZ NOT NULL,
  all_day             BOOLEAN     NOT NULL DEFAULT FALSE,
  status              TEXT        NOT NULL DEFAULT 'confirmed'
                                  CHECK (status IN ('confirmed', 'tentative', 'cancelled')),

  -- People
  organizer           TEXT,                          -- Email or name of organizer
  attendees           JSONB       DEFAULT '[]'::jsonb, -- [{email, name, status, optional}]
  contact_id          UUID        REFERENCES contacts(id) ON DELETE SET NULL,  -- Link to known contact
  meeting_link        TEXT,                          -- Zoom/Meet/Teams URL

  -- Recurrence
  is_recurring        BOOLEAN     NOT NULL DEFAULT FALSE,
  recurrence_rule     TEXT,                          -- RRULE string from Google
  recurring_event_id  UUID        REFERENCES calendar_events(id) ON DELETE SET NULL, -- Parent event

  -- Bot analysis
  has_conflict        BOOLEAN     NOT NULL DEFAULT FALSE,
  conflict_with       UUID        REFERENCES calendar_events(id) ON DELETE SET NULL, -- Which event conflicts
  prep_notes          TEXT,                          -- Bot's notes about this meeting
  briefing_included   BOOLEAN     NOT NULL DEFAULT FALSE,  -- Has this been included in a briefing?

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

-- Dedup: one cached copy per Google event per bot
CREATE UNIQUE INDEX idx_calendar_events_dedup ON calendar_events (bot_name, google_event_id);

-- Schedule queries: "what's on my calendar today/this week?"
CREATE INDEX idx_calendar_events_schedule ON calendar_events (bot_name, start_time, end_time);

-- Range scans for briefing generation
CREATE INDEX idx_calendar_events_start ON calendar_events (start_time);

-- Find conflicts quickly
CREATE INDEX idx_calendar_events_conflicts ON calendar_events (has_conflict)
  WHERE has_conflict = TRUE;

-- Contact-linked meetings
CREATE INDEX idx_calendar_events_contact ON calendar_events (contact_id)
  WHERE contact_id IS NOT NULL;

-- Status filter (hide cancelled)
CREATE INDEX idx_calendar_events_status ON calendar_events (status);

-- Unbriefed events
CREATE INDEX idx_calendar_events_unbriefed ON calendar_events (bot_name, briefing_included)
  WHERE briefing_included = FALSE;

CREATE TRIGGER trg_calendar_events_updated
  BEFORE UPDATE ON calendar_events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
