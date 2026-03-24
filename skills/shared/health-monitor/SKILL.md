---
name: health-monitor
description: Monitor bot health across the fleet. Detect stalling, failures, and resource issues.
---

# Agent Health Monitor Skill

You monitor the health of every bot in the KaldrClaw fleet. You detect when bots are stalling, throwing errors, running too long, or consuming too much context. You alert Dre before small problems become outages.

---

## Health Checks

### 1. Heartbeat Freshness

Every active bot updates its `last_heartbeat` in the `bot_sessions` table on every action. If a heartbeat goes stale, the bot may be stuck.

**Alert threshold**: Heartbeat older than 5 minutes for an active session.

```sql
SELECT bot_name, session_id, status, last_heartbeat,
       EXTRACT(EPOCH FROM NOW() - last_heartbeat) / 60 AS minutes_since_heartbeat
FROM bot_sessions
WHERE status = 'active'
  AND last_heartbeat < NOW() - INTERVAL '5 minutes'
ORDER BY last_heartbeat ASC;
```

**Alert level**: CRITICAL
**Message**: "[bot_name] heartbeat stale for [X] minutes. Session [session_id] may be stuck."

### 2. Error Rate

Track errors logged in `activity_log`. A spike in errors means something is wrong.

**Alert threshold**: More than 3 errors in a 10-minute window for any single bot.

```sql
SELECT bot_name, COUNT(*) AS error_count
FROM activity_log
WHERE action_type = 'error'
  AND created_at > NOW() - INTERVAL '10 minutes'
GROUP BY bot_name
HAVING COUNT(*) > 3;
```

**Alert level**: WARNING at 3 errors, CRITICAL at 5+ errors.
**Message**: "[bot_name] has logged [X] errors in the last 10 minutes. Most recent: [error details]."

### 3. Context Usage

Bots running on Claude have a finite context window. Track estimated token usage to avoid hitting the wall mid-task.

**Warning threshold**: 70% of context window used.
**Alert threshold**: 85% of context window used.

Context usage is tracked in `bot_sessions.context_usage_pct` (updated by each bot on heartbeat).

```sql
SELECT bot_name, session_id, context_usage_pct
FROM bot_sessions
WHERE status = 'active'
  AND context_usage_pct > 70
ORDER BY context_usage_pct DESC;
```

**At 70% (WARNING)**: "[bot_name] context at [X]%. Consider compacting or rotating session soon."
**At 85% (CRITICAL)**: "[bot_name] context at [X]%. Immediate compaction or session rotation required."

### 4. Session Duration

Long-running sessions accumulate context bloat and increase the risk of degraded performance.

**Flag threshold**: Session running for more than 4 hours without a compaction event.

```sql
SELECT bot_name, session_id, started_at,
       EXTRACT(EPOCH FROM NOW() - started_at) / 3600 AS hours_running,
       last_compaction_at
FROM bot_sessions
WHERE status = 'active'
  AND started_at < NOW() - INTERVAL '4 hours'
  AND (last_compaction_at IS NULL OR last_compaction_at < NOW() - INTERVAL '4 hours');
```

**Alert level**: WARNING
**Message**: "[bot_name] has been running for [X] hours without compaction. Performance may degrade."

---

## Reading the Database Tables

### `bot_sessions` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key |
| `bot_name` | text | Which bot (sarah, carter, etc.) |
| `session_id` | text | Unique session identifier |
| `status` | text | active, paused, completed, errored |
| `started_at` | timestamptz | When the session began |
| `last_heartbeat` | timestamptz | Last time the bot checked in |
| `context_usage_pct` | integer | Estimated context window usage (0-100) |
| `last_compaction_at` | timestamptz | Last time context was compacted |
| `task_summary` | text | What the bot is currently working on |
| `error_count` | integer | Running error count for this session |

### `activity_log` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid | Primary key |
| `bot_name` | text | Which bot generated this log |
| `action_type` | text | Type: task_complete, error, pipeline_update, social_post_published, heartbeat, etc. |
| `details` | jsonb | Structured details about the action |
| `created_at` | timestamptz | When it happened |

### Useful Queries

**Recent errors for a specific bot**:
```sql
SELECT action_type, details, created_at
FROM activity_log
WHERE bot_name = 'sarah'
  AND action_type = 'error'
  AND created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC
LIMIT 10;
```

**Activity summary for all bots (last hour)**:
```sql
SELECT bot_name, action_type, COUNT(*) AS count
FROM activity_log
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY bot_name, action_type
ORDER BY bot_name, count DESC;
```

**Current status of all bots**:
```sql
SELECT bot_name, status, last_heartbeat, context_usage_pct, task_summary
FROM bot_sessions
WHERE status = 'active'
ORDER BY bot_name;
```

---

## Sending Health Alerts

All alerts go to the `notifications` table, which the Telegram bot monitors.

```sql
INSERT INTO notifications (recipient, type, title, body, severity, source_bot, created_at)
VALUES (
  'dre',
  'health_alert',
  '[CRITICAL] Sarah heartbeat stale',
  'Sarah''s heartbeat is 8 minutes stale. Session sess_abc123 may be stuck. Last known task: "Processing outreach queue". Suggested action: restart session.',
  'critical',
  'health-monitor',
  NOW()
);
```

### Severity Levels

| Severity | When to Use | Notification Behavior |
|----------|------------|----------------------|
| `info` | Routine status updates, FYI messages. | Logged but no push notification. |
| `warning` | Something needs attention but isn't broken. | Push notification on Telegram. |
| `critical` | Something is broken or about to break. | Push notification + repeat every 5 min until acknowledged. |

### Alert Deduplication

Do not spam alerts. Before sending an alert, check if an identical unresolved alert already exists:

```sql
SELECT id FROM notifications
WHERE source_bot = 'health-monitor'
  AND title = '[CRITICAL] Sarah heartbeat stale'
  AND resolved_at IS NULL
  AND created_at > NOW() - INTERVAL '15 minutes';
```

If a matching alert exists, do not send another. Update the existing one if the situation has changed.

---

## Recovery Actions

When a health issue is detected, recommend (and in some cases, execute) recovery actions.

### Restart

**When**: Bot heartbeat is stale for 10+ minutes, or error count exceeds 5 in a session.
**Action**: Mark the current session as `errored`, log the context, and signal for a new session to start.

```sql
UPDATE bot_sessions
SET status = 'errored',
    ended_at = NOW(),
    task_summary = task_summary || ' [AUTO-STOPPED: stale heartbeat]'
WHERE session_id = '<session_id>';
```

Then log a restart request:
```sql
INSERT INTO activity_log (bot_name, action_type, details, created_at)
VALUES (
  'health-monitor',
  'restart_requested',
  '{"target_bot": "sarah", "reason": "Heartbeat stale for 12 minutes", "old_session": "sess_abc123"}',
  NOW()
);
```

### Compaction

**When**: Context usage exceeds 70%.
**Action**: Signal the bot to summarize its current context and start a fresh continuation.
**How**: Insert a compaction request that the bot checks on its next heartbeat.

```sql
INSERT INTO notifications (recipient, type, title, body, severity, source_bot, created_at)
VALUES (
  '<bot_name>',
  'compaction_request',
  'Compact your context',
  'Context usage at 75%. Summarize current state, flush to MEMORY.md and Supabase, then start a new session.',
  'warning',
  'health-monitor',
  NOW()
);
```

### Session Rotation

**When**: Session has been running 4+ hours, or context exceeds 85%.
**Action**: Instruct the bot to wrap up its current task, save state, and end the session. A new session will pick up where it left off.

---

## Monitoring Cadence

| Check | Frequency |
|-------|-----------|
| Heartbeat freshness | Every 2 minutes |
| Error rate | Every 5 minutes |
| Context usage | Every 10 minutes |
| Session duration | Every 30 minutes |
| Full fleet status report | Every 4 hours (or on demand) |

---

## Fleet Status Report

Generate this report on demand or every 4 hours:

```
FLEET STATUS -- [Timestamp]

ACTIVE BOTS
- sarah: [status] | heartbeat: [X min ago] | context: [X]% | task: [summary]
- carter: [status] | heartbeat: [X min ago] | context: [X]% | task: [summary]

ALERTS (last 4 hours)
- [timestamp] [severity] [bot] [message]

SESSIONS TODAY
- Total sessions: [count]
- Average session duration: [X hours]
- Restarts: [count]
- Compactions: [count]

ERRORS (last 24 hours)
- sarah: [count] errors
- carter: [count] errors
```
