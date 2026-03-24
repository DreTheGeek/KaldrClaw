-- ============================================================================
-- 007: Revenue Tracking
-- Income from subscriptions, one-time sales, consulting, freelance.
-- Powers the revenue section of morning briefings and monthly reports.
-- ============================================================================

CREATE TABLE revenue (
  id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  source          TEXT        NOT NULL,               -- 'stripe', 'manual', 'invoice', 'cash', etc.
  product         TEXT,                                -- 'myreceptionist', 'hvac_saas', 'consulting', etc.
  description     TEXT,                                -- "March retainer — Dispute Champs"
  amount          NUMERIC(12,2) NOT NULL,
  currency        TEXT        NOT NULL DEFAULT 'USD',

  -- Classification
  revenue_type    TEXT        NOT NULL DEFAULT 'one_time'
                              CHECK (revenue_type IN ('subscription', 'one_time', 'consulting', 'freelance', 'affiliate', 'other')),
  is_recurring    BOOLEAN     NOT NULL DEFAULT FALSE,
  recurrence_interval TEXT,                            -- 'monthly', 'quarterly', 'yearly'
  next_billing    DATE,                                -- When the next charge is expected

  -- Status
  status          TEXT        NOT NULL DEFAULT 'received'
                              CHECK (status IN ('pending', 'received', 'refunded', 'cancelled', 'overdue')),
  received_at     TIMESTAMPTZ,                         -- When money actually arrived
  period_start    DATE,                                -- For subscriptions: billing period start
  period_end      DATE,                                -- For subscriptions: billing period end

  -- External references
  stripe_id       TEXT,                                -- Stripe payment/subscription ID
  invoice_id      TEXT,                                -- Invoice number

  -- Who recorded it
  bot_name        TEXT,
  recorded_by     TEXT        DEFAULT 'dre',

  tags            TEXT[]      DEFAULT '{}',
  metadata        JSONB       DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE revenue ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_revenue_source ON revenue (source);
CREATE INDEX idx_revenue_product ON revenue (product);
CREATE INDEX idx_revenue_type ON revenue (revenue_type);
CREATE INDEX idx_revenue_status ON revenue (status);
CREATE INDEX idx_revenue_received ON revenue (received_at DESC);
CREATE INDEX idx_revenue_recurring ON revenue (is_recurring, next_billing) WHERE is_recurring = TRUE;
CREATE INDEX idx_revenue_period ON revenue (period_start, period_end);

CREATE TRIGGER trg_revenue_updated
  BEFORE UPDATE ON revenue
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
