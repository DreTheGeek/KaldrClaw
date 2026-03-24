-- ============================================================================
-- 004: Tasks
-- Multi-status task tracking. Tasks belong to projects (optional).
-- Can be assigned between bots. Supports recurrence for things like
-- daily standups and weekly reviews. Tags for flexible categorization.
-- ============================================================================

CREATE TABLE tasks (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  project_id      UUID        REFERENCES projects(id) ON DELETE SET NULL,
  parent_task_id  UUID        REFERENCES tasks(id) ON DELETE SET NULL,  -- Subtask support

  title           TEXT        NOT NULL,
  description     TEXT,
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'in_progress', 'blocked', 'completed', 'cancelled')),
  priority        TEXT        NOT NULL DEFAULT 'medium'
                              CHECK (priority IN ('critical', 'high', 'medium', 'low')),

  -- Assignment
  assigned_to     TEXT,                               -- Bot name or person
  created_by      TEXT,                               -- Who/what created it
  bot_name        TEXT,                               -- Which bot owns/manages this task

  -- Dates
  due_date        TIMESTAMPTZ,
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,

  -- Recurrence: NULL means one-time task
  is_recurring    BOOLEAN     NOT NULL DEFAULT FALSE,
  recurrence_rule TEXT,                               -- Cron expression or 'daily', 'weekly', 'monthly'
  next_occurrence TIMESTAMPTZ,                        -- When the next recurrence fires
  last_occurred   TIMESTAMPTZ,                        -- When it last fired

  -- Categorization
  tags            TEXT[]      DEFAULT '{}',
  blocked_reason  TEXT,                               -- Why it's blocked

  -- Metadata
  notes           TEXT,
  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_tasks_status ON tasks (status);
CREATE INDEX idx_tasks_project ON tasks (project_id);
CREATE INDEX idx_tasks_assigned ON tasks (assigned_to);
CREATE INDEX idx_tasks_bot ON tasks (bot_name);
CREATE INDEX idx_tasks_due ON tasks (due_date) WHERE status NOT IN ('completed', 'cancelled');
CREATE INDEX idx_tasks_priority ON tasks (priority);
CREATE INDEX idx_tasks_recurring ON tasks (is_recurring, next_occurrence) WHERE is_recurring = TRUE;
CREATE INDEX idx_tasks_tags ON tasks USING GIN (tags);
CREATE INDEX idx_tasks_parent ON tasks (parent_task_id) WHERE parent_task_id IS NOT NULL;

CREATE TRIGGER trg_tasks_updated
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
