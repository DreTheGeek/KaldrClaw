-- ============================================================================
-- 013: Conversation History
-- Telegram message logs. Who said what, when. Bot responses. Thread context.
-- Enables "what did we talk about yesterday?" and helps bots maintain
-- continuity across sessions and container restarts.
-- ============================================================================

CREATE TABLE conversations (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT        NOT NULL,
  channel         TEXT        NOT NULL DEFAULT 'telegram'
                              CHECK (channel IN ('telegram', 'email', 'api', 'internal', 'sms')),

  -- Message content
  direction       TEXT        NOT NULL
                              CHECK (direction IN ('inbound', 'outbound')),   -- user→bot or bot→user
  sender          TEXT        NOT NULL,               -- 'dre', 'ava', 'sarah', etc.
  content         TEXT        NOT NULL,
  content_type    TEXT        NOT NULL DEFAULT 'text'
                              CHECK (content_type IN ('text', 'image', 'file', 'voice', 'command')),

  -- Threading
  thread_id       TEXT,                               -- Group related messages into a conversation thread
  reply_to_id     UUID        REFERENCES conversations(id),
  telegram_msg_id BIGINT,                             -- Native Telegram message ID for reference

  -- Context
  session_id      TEXT,                               -- Claude Code session that processed this
  intent          TEXT,                               -- Classified intent: 'task_create', 'question', 'chitchat', etc.
  sentiment       TEXT,                               -- 'positive', 'neutral', 'negative', 'urgent'

  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW()
  -- No updated_at — messages are immutable
);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_conversations_bot ON conversations (bot_name, created_at DESC);
CREATE INDEX idx_conversations_thread ON conversations (thread_id, created_at) WHERE thread_id IS NOT NULL;
CREATE INDEX idx_conversations_channel ON conversations (channel, created_at DESC);
CREATE INDEX idx_conversations_sender ON conversations (sender, created_at DESC);
CREATE INDEX idx_conversations_session ON conversations (session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_conversations_created ON conversations (created_at DESC);
