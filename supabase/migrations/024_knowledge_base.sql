-- ============================================================================
-- 024: Knowledge Base
-- Long-form reference material: meeting notes, research findings, saved
-- articles, strategy docs, how-to guides, transcripts. Supports full-text
-- search via tsvector, tagging, and linking to projects/contacts/tasks.
-- ============================================================================

CREATE TABLE knowledge_base (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT,                          -- NULL = shared across fleet

  -- Content
  title               TEXT        NOT NULL,
  content             TEXT        NOT NULL,
  content_type        TEXT        NOT NULL DEFAULT 'note'
                                  CHECK (content_type IN ('note', 'article', 'research', 'meeting_notes', 'guide', 'reference', 'transcript')),

  -- Organization
  category            TEXT,
  tags                TEXT[]      DEFAULT '{}',
  project_id          UUID        REFERENCES projects(id) ON DELETE SET NULL,

  -- Source tracking
  source_type         TEXT        CHECK (source_type IN ('user', 'bot', 'import', 'web')),
  source_url          TEXT,
  source_author       TEXT,

  -- Status
  status              TEXT        NOT NULL DEFAULT 'published'
                                  CHECK (status IN ('draft', 'published', 'archived')),
  pinned              BOOLEAN     NOT NULL DEFAULT FALSE,

  -- Full-text search
  search_vector       TSVECTOR,

  -- Relations
  related_contact_id  UUID        REFERENCES contacts(id) ON DELETE SET NULL,
  related_task_id     UUID        REFERENCES tasks(id) ON DELETE SET NULL,

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;

-- Full-text search (primary search mechanism)
CREATE INDEX idx_knowledge_base_search ON knowledge_base USING GIN (search_vector);

-- Tag-based filtering
CREATE INDEX idx_knowledge_base_tags ON knowledge_base USING GIN (tags);

-- Content type filter
CREATE INDEX idx_knowledge_base_type ON knowledge_base (content_type);

-- Category filter
CREATE INDEX idx_knowledge_base_category ON knowledge_base (category)
  WHERE category IS NOT NULL;

-- Pinned items (quick access)
CREATE INDEX idx_knowledge_base_pinned ON knowledge_base (pinned)
  WHERE pinned = TRUE;

-- Project-linked knowledge
CREATE INDEX idx_knowledge_base_project ON knowledge_base (project_id)
  WHERE project_id IS NOT NULL;

-- Bot-specific knowledge
CREATE INDEX idx_knowledge_base_bot ON knowledge_base (bot_name)
  WHERE bot_name IS NOT NULL;

-- Status filter
CREATE INDEX idx_knowledge_base_status ON knowledge_base (status);

-- Auto-populate search_vector on insert/update
CREATE OR REPLACE FUNCTION knowledge_base_search_vector_trigger()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.category, '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_knowledge_base_search_vector
  BEFORE INSERT OR UPDATE OF title, content, category ON knowledge_base
  FOR EACH ROW EXECUTE FUNCTION knowledge_base_search_vector_trigger();

CREATE TRIGGER trg_knowledge_base_updated
  BEFORE UPDATE ON knowledge_base
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
