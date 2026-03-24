-- ============================================================================
-- 012: Contacts & Relationships
-- CRM-lite for people Dre interacts with professionally. The bot uses this to
-- prepare for meetings, suggest follow-ups, and enrich briefings with
-- relationship context. "You haven't talked to Cheryl in 2 weeks."
-- ============================================================================

CREATE TABLE contacts (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  name              TEXT        NOT NULL,
  email             TEXT,
  phone             TEXT,
  company           TEXT,
  role              TEXT,                               -- Their job title / role
  relationship_type TEXT        NOT NULL DEFAULT 'contact'
                                CHECK (relationship_type IN (
                                  'lead', 'client', 'partner', 'vendor', 'mentor',
                                  'mentee', 'investor', 'friend', 'family', 'contact'
                                )),

  -- Context
  how_met           TEXT,                               -- "AI Junkies group", "LinkedIn DM", etc.
  importance        TEXT        NOT NULL DEFAULT 'medium'
                                CHECK (importance IN ('critical', 'high', 'medium', 'low')),

  -- Touchpoints
  last_touchpoint   TIMESTAMPTZ,                        -- Last meaningful interaction
  last_touchpoint_type TEXT,                            -- 'email', 'call', 'meeting', 'telegram', 'text'
  next_followup     DATE,                               -- When to follow up
  followup_notes    TEXT,                               -- What to follow up about

  -- Communication preferences
  preferred_channel TEXT,                               -- 'email', 'telegram', 'phone', 'text'
  timezone          TEXT,

  -- CRM fields
  deal_value        NUMERIC(12,2),                      -- If there's revenue potential
  deal_stage        TEXT,                               -- 'prospect', 'negotiation', 'closed', 'churned'
  lifetime_value    NUMERIC(12,2) DEFAULT 0,

  -- Ownership
  bot_name          TEXT,
  tags              TEXT[]      DEFAULT '{}',
  notes             TEXT,
  metadata          JSONB       DEFAULT '{}'::jsonb,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_contacts_name ON contacts (name);
CREATE INDEX idx_contacts_email ON contacts (email) WHERE email IS NOT NULL;
CREATE INDEX idx_contacts_company ON contacts (company) WHERE company IS NOT NULL;
CREATE INDEX idx_contacts_type ON contacts (relationship_type);
CREATE INDEX idx_contacts_followup ON contacts (next_followup) WHERE next_followup IS NOT NULL;
CREATE INDEX idx_contacts_importance ON contacts (importance);
CREATE INDEX idx_contacts_tags ON contacts USING GIN (tags);

CREATE TRIGGER trg_contacts_updated
  BEFORE UPDATE ON contacts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
