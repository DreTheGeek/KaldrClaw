-- ============================================================================
-- 027: User Profiles
-- Multi-user support that makes KaldrClaw truly universal. Each person who
-- deploys KaldrClaw gets a profile their bots read to personalize behavior:
-- work patterns, communication style, wellness goals, business context.
-- ============================================================================

CREATE TABLE user_profiles (
  id                      UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  display_name            TEXT        NOT NULL,
  email                   TEXT,
  phone                   TEXT,
  timezone                TEXT        NOT NULL DEFAULT 'America/New_York',

  -- Work patterns
  peak_hours_start        TIME,
  peak_hours_end          TIME,
  wake_time               TIME,
  sleep_time              TIME,
  work_days               TEXT[]      DEFAULT '{Mon,Tue,Wed,Thu,Fri}',

  -- Communication preferences
  communication_style     TEXT        CHECK (communication_style IN ('direct', 'detailed', 'casual')),
  notification_channel    TEXT        DEFAULT 'telegram',
  quiet_hours_start       TIME,
  quiet_hours_end         TIME,
  preferred_briefing_format TEXT      CHECK (preferred_briefing_format IN ('bullet', 'narrative', 'minimal')),

  -- Accountability / wellness
  wellness_goals          JSONB       DEFAULT '{}'::jsonb,  -- Default goals per wellness category
  accountability_level    TEXT        DEFAULT 'medium'
                                      CHECK (accountability_level IN ('gentle', 'medium', 'strict', 'drill_sergeant')),

  -- Social handles
  social_handles          JSONB       DEFAULT '{}'::jsonb,  -- {"twitter": "@handle", "linkedin": "url", "github": "username"}

  -- Business context
  company_name            TEXT,
  company_url             TEXT,
  products                JSONB       DEFAULT '[]'::jsonb,  -- Array of product objects
  tech_stack              TEXT[]      DEFAULT '{}',

  -- Profile
  avatar_url              TEXT,
  bio                     TEXT,

  -- Metadata
  metadata                JSONB       DEFAULT '{}'::jsonb,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Email lookup (login / invite flow)
CREATE UNIQUE INDEX idx_user_profiles_email ON user_profiles (email)
  WHERE email IS NOT NULL;

-- Display name search
CREATE INDEX idx_user_profiles_name ON user_profiles (display_name);

CREATE TRIGGER trg_user_profiles_updated
  BEFORE UPDATE ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
