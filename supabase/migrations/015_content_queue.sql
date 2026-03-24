-- ============================================================================
-- 015: Content Queue
-- Social media drafts, scheduled posts, approval status. Ready for when
-- the content bot (Carter) comes online. Supports multi-platform posting,
-- media attachments, and an approval workflow.
-- ============================================================================

CREATE TABLE content_queue (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name        TEXT,                                -- Which bot created/manages this content
  platform        TEXT        NOT NULL
                              CHECK (platform IN (
                                'twitter', 'linkedin', 'instagram', 'facebook',
                                'tiktok', 'youtube', 'blog', 'newsletter', 'telegram', 'threads'
                              )),

  -- Content
  content_text    TEXT        NOT NULL,
  content_type    TEXT        NOT NULL DEFAULT 'post'
                              CHECK (content_type IN ('post', 'thread', 'story', 'reel', 'article', 'newsletter', 'comment', 'reply')),
  title           TEXT,                                -- For articles/newsletters
  media_urls      TEXT[]      DEFAULT '{}',            -- Attached images/videos
  hashtags        TEXT[]      DEFAULT '{}',
  link_url        TEXT,                                -- URL being shared

  -- Workflow
  status          TEXT        NOT NULL DEFAULT 'draft'
                              CHECK (status IN ('idea', 'draft', 'review', 'approved', 'scheduled', 'posted', 'failed', 'cancelled')),
  scheduled_for   TIMESTAMPTZ,                         -- When to post
  posted_at       TIMESTAMPTZ,
  approved_by     TEXT,                                -- Who approved it
  approved_at     TIMESTAMPTZ,

  -- Performance (filled in after posting)
  external_id     TEXT,                                -- Platform's post ID
  impressions     INT,
  engagements     INT,
  clicks          INT,

  -- Context
  campaign        TEXT,                                -- Group posts into a campaign
  target_audience TEXT,                                -- Who this is for
  notes           TEXT,

  tags            TEXT[]      DEFAULT '{}',
  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE content_queue ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_content_platform ON content_queue (platform);
CREATE INDEX idx_content_status ON content_queue (status);
CREATE INDEX idx_content_scheduled ON content_queue (scheduled_for)
  WHERE status IN ('approved', 'scheduled');
CREATE INDEX idx_content_bot ON content_queue (bot_name);
CREATE INDEX idx_content_campaign ON content_queue (campaign) WHERE campaign IS NOT NULL;
CREATE INDEX idx_content_tags ON content_queue USING GIN (tags);

CREATE TRIGGER trg_content_queue_updated
  BEFORE UPDATE ON content_queue
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
