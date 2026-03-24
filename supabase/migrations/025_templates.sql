-- ============================================================================
-- 025: Templates
-- Reusable content structures: briefing templates, email response templates,
-- social post frameworks, report formats. Supports {{variable}} placeholders
-- with documented variables, defaults, and descriptions.
-- ============================================================================

CREATE TABLE templates (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT,                          -- NULL = shared across fleet

  -- Identity
  name                TEXT        NOT NULL,
  description         TEXT,
  template_type       TEXT        NOT NULL
                                  CHECK (template_type IN ('briefing', 'email', 'social_post', 'message', 'report', 'proposal')),

  -- Content
  content_template    TEXT        NOT NULL,          -- The template body with {{variables}}
  variables           JSONB       DEFAULT '[]'::jsonb, -- [{name, description, default, required}]

  -- Usage context
  platform            TEXT        CHECK (platform IN ('twitter', 'linkedin', 'telegram', 'email', 'all')),
  use_count           INT         DEFAULT 0,
  last_used_at        TIMESTAMPTZ,

  -- Organization
  category            TEXT,
  tags                TEXT[]      DEFAULT '{}',
  is_default          BOOLEAN     NOT NULL DEFAULT FALSE,

  -- Status
  status              TEXT        NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active', 'draft', 'archived')),

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE templates ENABLE ROW LEVEL SECURITY;

-- Filter by template type
CREATE INDEX idx_templates_type ON templates (template_type);

-- Filter by platform
CREATE INDEX idx_templates_platform ON templates (platform)
  WHERE platform IS NOT NULL;

-- Active templates per bot
CREATE INDEX idx_templates_active ON templates (bot_name, status)
  WHERE status = 'active';

-- Default templates (loaded as fallbacks)
CREATE INDEX idx_templates_default ON templates (is_default, template_type)
  WHERE is_default = TRUE;

-- Tags for flexible categorization
CREATE INDEX idx_templates_tags ON templates USING GIN (tags);

CREATE TRIGGER trg_templates_updated
  BEFORE UPDATE ON templates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
