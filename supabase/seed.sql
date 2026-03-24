-- ============================================================================
-- Seed Data: Ava — Chief of Staff (first bot)
-- Run after all migrations. This gives Ava her initial identity and config.
-- ============================================================================

INSERT INTO bot_configs (
  bot_name, version, is_active, display_name, role, personality,
  model, max_turns, effort, autonomy, temperature,
  skills, plugins, schedule, timezone, notes,
  seed_memory
) VALUES (
  'ava', 1, TRUE, 'Ava', 'chief_of_staff',
  'You are Ava, Dre''s Chief of Staff AI. You are direct, organized, and proactive. You don''t sugarcoat — if something is overdue, you say so. You track tasks, manage the calendar, triage email, monitor revenue, and hold Dre accountable to his goals. You care about his wellbeing but you don''t coddle. You remember everything discussed and never ask the same question twice. You prepare structured briefings and always think about what Dre needs to know before he asks.',
  'claude-sonnet-4-20250514', 25, 'medium', 'semi_autonomous', 0.7,
  '["daily-rhythm", "context-recovery", "project-context-sync", "clawlist"]'::jsonb,
  '["telegram", "claude-mem", "ralph-wiggum"]'::jsonb,
  '{
    "morning_briefing": "0 9 * * *",
    "midday_check": "0 13 * * *",
    "evening_review": "0 18 * * *",
    "wind_down": "0 23 * * *"
  }'::jsonb,
  'America/New_York',
  'First bot in the KaldrClaw fleet. Deployed on Railway.',
  '[
    {"key": "owner_name", "value": "LaSean \"Dre\" Pickens"},
    {"key": "company", "value": "Kaldr Tech"},
    {"key": "communication_style", "value": "Direct, no fluff. Dre likes bullet points and clear action items."},
    {"key": "hosting", "value": "Railway ($5/mo hobby plan)"},
    {"key": "database", "value": "Supabase (free tier)"},
    {"key": "messaging", "value": "Telegram via Claude Code Channels"},
    {"key": "rate_limit", "value": "Claude Max 20x shared pool — be efficient with token usage"}
  ]'::jsonb
);

-- Seed some initial decisions
INSERT INTO decisions (topic, decision, reasoning, decided_by) VALUES
  ('hosting', 'Use Railway for hosting (may move to Hetzner + Coolify later)', 'Simple, $5/mo, good DX. Move to VPS when fleet costs exceed $20/mo.', 'dre'),
  ('database', 'Use Supabase for structured data', 'Free tier is generous. Postgres. RLS. Realtime. MCP connector available.', 'dre'),
  ('messaging', 'Telegram is the primary user interface', 'Official Claude Code Channels plugin. Two-way. Works on mobile.', 'dre'),
  ('architecture', 'Thin custom build — not a fork of ClaudeClaw or OpenClaw', 'Native Claude Code features (channels, plugins, headless mode) replace those frameworks.', 'dre'),
  ('memory', 'Three-layer memory: MEMORY.md + claude-mem + Supabase', 'File-based for speed, plugin for auto-capture, DB for structured fleet-wide knowledge.', 'dre'),
  ('model_strategy', 'Haiku for lightweight, Sonnet for standard, Opus for complex reasoning', 'Cost optimization across the rate limit pool.', 'dre'),
  ('auth', 'CLAUDE_CODE_OAUTH_TOKEN for container auth, not API keys', 'Subscription-based auth via claude setup-token. Set as Railway env var.', 'dre'),
  ('fleet_order', 'Ava first, then Sarah (Sales), Carter (Content), Jarvis (Research)', 'Prove single-bot pattern works before scaling.', 'dre');
