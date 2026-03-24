-- ============================================================================
-- 018: Row Level Security Policies
-- Since KaldrClaw bots connect via the service_role key (full access),
-- these policies are mainly for safety if the anon key is ever exposed,
-- and to establish the pattern for future multi-tenant expansion.
--
-- Strategy:
-- - Service role bypasses RLS (this is how bots connect)
-- - Anon role gets NO access (locked down)
-- - Authenticated role (future dashboard) gets read access
-- ============================================================================

-- Helper: deny all access to anon by default on every table
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN (
        'bot_configs', 'projects', 'tasks', 'activity_log', 'decisions',
        'revenue', 'fleet_memory', 'briefings', 'wellness', 'goals',
        'contacts', 'conversations', 'reminders', 'content_queue', 'email_summaries'
      )
  LOOP
    -- Allow service_role full access (bots use this)
    EXECUTE format(
      'CREATE POLICY "service_role_full_%s" ON %I FOR ALL TO service_role USING (true) WITH CHECK (true)',
      tbl, tbl
    );

    -- Allow authenticated users read access (future dashboard)
    EXECUTE format(
      'CREATE POLICY "authenticated_read_%s" ON %I FOR SELECT TO authenticated USING (true)',
      tbl, tbl
    );
  END LOOP;
END $$;
