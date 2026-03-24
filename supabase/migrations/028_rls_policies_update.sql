-- ============================================================================
-- 028: RLS Policies for new tables (019–027)
-- Extends the pattern from 018: service_role gets full access (bots),
-- authenticated gets read access (future dashboard), anon gets nothing.
-- ============================================================================

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN (
        'calendar_events', 'bot_sessions', 'integrations', 'notifications',
        'automation_rules', 'knowledge_base', 'templates', 'rate_limits',
        'user_profiles'
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
