-- ============================================================================
-- 021: Integrations
-- Registry of external service connections: MCP servers, APIs, OAuth tokens.
-- Tracks connection health so the fleet can self-diagnose integration
-- failures and alert before tokens expire.
-- ============================================================================

CREATE TABLE integrations (
  id                    UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  bot_name              TEXT,                          -- NULL = shared across fleet
  service_name          TEXT        NOT NULL,          -- gmail, calendar, supabase, stripe, github, tavily, telegram, blotato, etc.
  service_type          TEXT        NOT NULL
                                    CHECK (service_type IN ('mcp_server', 'api', 'oauth', 'webhook')),
  connection_status     TEXT        NOT NULL DEFAULT 'disconnected'
                                    CHECK (connection_status IN ('connected', 'disconnected', 'error', 'expired', 'configuring')),

  -- Authentication
  auth_method           TEXT        CHECK (auth_method IN ('oauth', 'api_key', 'token', 'none')),
  token_expires_at      TIMESTAMPTZ,
  last_auth_at          TIMESTAMPTZ,

  -- Health tracking
  last_success_at       TIMESTAMPTZ,
  last_error_at         TIMESTAMPTZ,
  last_error_message    TEXT,
  consecutive_failures  INT         DEFAULT 0,
  is_healthy            BOOLEAN     DEFAULT TRUE,

  -- Configuration
  endpoint_url          TEXT,
  config_overrides      JSONB       DEFAULT '{}'::jsonb,

  -- Metadata
  metadata              JSONB       DEFAULT '{}'::jsonb,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;

-- Lookup by service name (e.g., "is Gmail connected?")
CREATE INDEX idx_integrations_service ON integrations (service_name);

-- Filter by connection status
CREATE INDEX idx_integrations_status ON integrations (connection_status);

-- Find unhealthy services for alerting
CREATE INDEX idx_integrations_unhealthy ON integrations (is_healthy)
  WHERE is_healthy = FALSE;

-- Token expiration monitoring
CREATE INDEX idx_integrations_token_expiry ON integrations (token_expires_at)
  WHERE token_expires_at IS NOT NULL;

-- Bot-specific integrations
CREATE INDEX idx_integrations_bot ON integrations (bot_name)
  WHERE bot_name IS NOT NULL;

CREATE TRIGGER trg_integrations_updated
  BEFORE UPDATE ON integrations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
