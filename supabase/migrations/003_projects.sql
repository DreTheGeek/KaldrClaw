-- ============================================================================
-- 003: Projects
-- High-level initiatives like "HVAC Launch", "myreceptionist.net deployment".
-- Tasks (004) are children of projects. Milestones and blockers stored as JSONB
-- arrays so the structure stays flexible as needs evolve.
-- ============================================================================

CREATE TABLE projects (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  name          TEXT        NOT NULL,
  description   TEXT,
  status        TEXT        NOT NULL DEFAULT 'active'
                            CHECK (status IN ('planning', 'active', 'paused', 'completed', 'cancelled')),
  priority      TEXT        NOT NULL DEFAULT 'medium'
                            CHECK (priority IN ('critical', 'high', 'medium', 'low')),
  owner         TEXT,                                 -- Person responsible (e.g., 'dre', 'derrick', etc.)
  bot_name      TEXT,                                 -- Primary bot managing this project

  -- Dates
  start_date    DATE,
  target_date   DATE,
  completed_at  TIMESTAMPTZ,

  -- Structured sub-data
  milestones    JSONB       DEFAULT '[]'::jsonb,     -- [{name, target_date, completed, completed_at}]
  blockers      JSONB       DEFAULT '[]'::jsonb,     -- [{description, severity, resolved, resolved_at}]
  tags          TEXT[]      DEFAULT '{}',

  -- Metadata
  notes         TEXT,
  metadata      JSONB       DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_projects_status ON projects (status);
CREATE INDEX idx_projects_bot ON projects (bot_name);
CREATE INDEX idx_projects_priority ON projects (priority);
CREATE INDEX idx_projects_tags ON projects USING GIN (tags);

CREATE TRIGGER trg_projects_updated
  BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
