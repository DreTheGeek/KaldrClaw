-- ============================================================================
-- 022: Notifications
-- System-generated alerts, distinct from user-facing reminders (014).
-- These are operational signals: "Rate limit hit", "MCP server down",
-- "Stripe payment failed", "HVAC site returning 500", "Container restarted".
-- Supports severity levels, delivery channels, dedup, and required actions.
-- ============================================================================

CREATE TABLE notifications (
  id                  UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name            TEXT,                          -- Which bot generated this (NULL = system-wide)

  -- Content
  title               TEXT        NOT NULL,
  message             TEXT        NOT NULL,
  notification_type   TEXT        NOT NULL
                                  CHECK (notification_type IN ('system', 'integration', 'security', 'performance', 'billing', 'error')),
  severity            TEXT        NOT NULL DEFAULT 'info'
                                  CHECK (severity IN ('info', 'warning', 'error', 'critical')),

  -- Status lifecycle
  status              TEXT        NOT NULL DEFAULT 'unread'
                                  CHECK (status IN ('unread', 'read', 'acknowledged', 'dismissed', 'actioned')),
  read_at             TIMESTAMPTZ,
  acknowledged_at     TIMESTAMPTZ,

  -- Context / linking
  source              TEXT,                          -- Which system generated this (e.g., "health_monitor", "stripe_webhook")
  related_id          UUID,                          -- FK to whatever entity this is about
  related_type        TEXT,                          -- Type of the related entity (e.g., "integration", "bot_session")

  -- Delivery
  delivery_channel    TEXT        DEFAULT 'dashboard'
                                  CHECK (delivery_channel IN ('telegram', 'email', 'dashboard', 'all')),
  delivered_at        TIMESTAMPTZ,
  delivery_status     TEXT        DEFAULT 'pending'
                                  CHECK (delivery_status IN ('pending', 'delivered', 'failed')),

  -- Action required
  action_required     BOOLEAN     DEFAULT FALSE,
  action_type         TEXT,                          -- What kind of action (e.g., "restart_bot", "renew_token")
  action_url          TEXT,                          -- Deep link to take action

  -- Deduplication
  dedup_key           TEXT,                          -- Prevent duplicate alerts for the same issue

  -- Metadata
  metadata            JSONB       DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Unread notifications per bot (dashboard badge count, alert feed)
CREATE INDEX idx_notifications_unread ON notifications (bot_name, status)
  WHERE status = 'unread';

-- Severity filtering (show criticals first)
CREATE INDEX idx_notifications_severity ON notifications (severity, created_at DESC);

-- Delivery queue: pending deliveries
CREATE INDEX idx_notifications_delivery ON notifications (delivery_status)
  WHERE delivery_status = 'pending';

-- Dedup: prevent flooding from the same issue
CREATE INDEX idx_notifications_dedup ON notifications (dedup_key)
  WHERE dedup_key IS NOT NULL;

-- Chronological feed
CREATE INDEX idx_notifications_created ON notifications (created_at DESC);

-- Action-required items
CREATE INDEX idx_notifications_action ON notifications (action_required)
  WHERE action_required = TRUE;

CREATE TRIGGER trg_notifications_updated
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
