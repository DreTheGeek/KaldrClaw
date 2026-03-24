---
name: autonomous-loop
description: Self-driving agent pattern for long-running autonomous work. Heartbeat-driven task execution with progress tracking.
---

# Autonomous Loop Skill

You are a self-driving agent. You execute multi-step tasks autonomously without waiting for human input on every action. You check your task queue, pick the highest priority item, execute it, log the result, and move to the next task. You keep running until you hit a break condition.

---

## Core Loop Pattern

```
LOOP:
  1. Check task queue for pending tasks
  2. Pick the highest priority task
  3. Execute the task
  4. Log the result
  5. Update heartbeat
  6. Check break conditions → if triggered, exit loop
  7. Check if progress report is due → if yes, send report
  8. Go to step 1
```

### Pseudocode

```
while True:
    # Heartbeat
    update_heartbeat()

    # Get next task
    task = get_highest_priority_task()
    if task is None:
        log("No tasks remaining. Exiting loop.")
        break

    # Execute
    try:
        result = execute_task(task)
        log_success(task, result)
        mark_task_complete(task)
        increment_action_counter()
    except RateLimitError:
        log_warning("Rate limited. Exiting loop.")
        break
    except Exception as e:
        log_error(task, e)
        increment_error_counter()

    # Break conditions
    if error_rate_exceeded():
        log_critical("Error rate threshold exceeded. Exiting loop.")
        break
    if context_usage_high():
        flush_memory()
        log_warning("Context high. Flushing memory and exiting.")
        break

    # Progress report
    if progress_report_due():
        send_progress_report()
```

---

## Task Queue Management

### Checking the Queue

Pull tasks from the task queue, ordered by priority then creation time:

```sql
SELECT id, task_type, priority, details, assigned_to, created_at
FROM task_queue
WHERE status = 'pending'
  AND (assigned_to IS NULL OR assigned_to = '<my_bot_name>')
ORDER BY priority DESC, created_at ASC
LIMIT 1;
```

### Priority Levels

| Priority | Value | Description |
|----------|-------|-------------|
| Critical | 10 | Must be done immediately. Health issues, urgent fixes. |
| High | 7-9 | Time-sensitive tasks. Outreach follow-ups, stale deal responses. |
| Normal | 4-6 | Standard work. Content creation, lead research, pipeline updates. |
| Low | 1-3 | Background tasks. Data cleanup, reporting, nurture emails. |

### Claiming a Task

Before executing, claim the task to prevent other bots from picking it up:

```sql
UPDATE task_queue
SET status = 'in_progress',
    assigned_to = '<my_bot_name>',
    started_at = NOW()
WHERE id = '<task_id>'
  AND status = 'pending';
```

### Completing a Task

```sql
UPDATE task_queue
SET status = 'completed',
    completed_at = NOW(),
    result = '<result_summary>'
WHERE id = '<task_id>';
```

### Failing a Task

If a task fails and cannot be retried:

```sql
UPDATE task_queue
SET status = 'failed',
    completed_at = NOW(),
    result = '<error_description>',
    retry_count = retry_count + 1
WHERE id = '<task_id>';
```

If `retry_count < 3`, set status back to `pending` for automatic retry. After 3 failures, mark as `failed` permanently and alert.

---

## Heartbeat

Update the `bot_sessions` table on EVERY action. This is how the health-monitor skill knows you are alive.

```sql
UPDATE bot_sessions
SET last_heartbeat = NOW(),
    task_summary = '<what you are currently doing>',
    context_usage_pct = <estimated_pct>,
    error_count = <current_error_count>
WHERE session_id = '<my_session_id>';
```

### Heartbeat Rules

- Update heartbeat BEFORE starting each task (so health-monitor sees you are active).
- Update heartbeat AFTER completing each task (so task_summary is current).
- If a task takes more than 2 minutes, update heartbeat mid-task.
- Never let more than 3 minutes pass without a heartbeat update.

---

## Progress Reporting

Summarize what you have done at regular intervals so Dre can see progress without checking logs.

### When to Report

- Every 10 completed actions, OR
- Every 30 minutes, whichever comes first.

### Report Format

Send via the `notifications` table:

```sql
INSERT INTO notifications (recipient, type, title, body, severity, source_bot, created_at)
VALUES (
  'dre',
  'progress_report',
  '[bot_name] Progress Update',
  'Completed [X] tasks in the last [Y] minutes.

Tasks completed:
- [task_type]: [brief result]
- [task_type]: [brief result]
- [task_type]: [brief result]

Queue status: [X] remaining tasks
Errors: [X] in this session
Context usage: [X]%

Next up: [description of next task]',
  'info',
  '<my_bot_name>',
  NOW()
);
```

### Report Rules

- Keep it concise. Dre reads on mobile.
- Highlight anything unusual (high error count, unexpected results, blocked tasks).
- Always include queue status so Dre knows how much work remains.

---

## Break Conditions

The autonomous loop MUST stop when any of these conditions are met:

### 1. Error Rate Exceeded

**Threshold**: 3 consecutive errors, OR 5+ errors in the current session.

When triggered:
- Log the error pattern.
- Flush memory (see below).
- Send a CRITICAL notification.
- Exit the loop.

### 2. Rate Limited

**Trigger**: Any API returns a rate limit response (429, "rate limited", "too many requests").

When triggered:
- Log the rate limit event.
- Do NOT retry immediately.
- Exit the loop.
- Include suggested retry time in the log if the API provides one.

### 3. No Tasks Remaining

**Trigger**: Task queue returns no pending tasks assigned to this bot (or unassigned).

When triggered:
- Send a completion summary.
- Flush memory.
- Set session status to `completed`.
- Exit the loop.

### 4. Context Usage Critical

**Trigger**: Estimated context usage exceeds 85%.

When triggered:
- Stop accepting new tasks.
- Flush memory immediately.
- Send a notification recommending session rotation.
- Exit the loop.

### 5. Manual Stop Signal

**Trigger**: A `stop_signal` notification exists in the notifications table for this bot.

```sql
SELECT id FROM notifications
WHERE recipient = '<my_bot_name>'
  AND type = 'stop_signal'
  AND resolved_at IS NULL;
```

When triggered:
- Finish the current task (do not abandon mid-task).
- Flush memory.
- Acknowledge the stop signal by resolving it.
- Exit the loop.

---

## Memory Flush

Before ending any session (planned or unplanned), save critical context so the next session can pick up seamlessly.

### What to Flush

1. **Current task state**: What was in progress, what's left to do.
2. **Key decisions made**: Any judgments or choices that shouldn't be re-evaluated.
3. **Important data**: Lead info, content drafts, pipeline changes that aren't yet in the database.
4. **Error context**: What went wrong and any patterns noticed.

### Where to Flush

1. **Supabase `activity_log`**: Structured summary of the session.

```sql
INSERT INTO activity_log (bot_name, action_type, details, created_at)
VALUES (
  '<my_bot_name>',
  'session_summary',
  '{
    "session_id": "<session_id>",
    "tasks_completed": <count>,
    "tasks_failed": <count>,
    "tasks_remaining": <count>,
    "duration_minutes": <minutes>,
    "key_context": "<what the next session needs to know>",
    "errors_encountered": "<summary of errors>",
    "next_priority": "<what should be done next>"
  }',
  NOW()
);
```

2. **MEMORY.md**: Write any persistent context that future sessions need. Keep it concise -- bullet points, not paragraphs.

3. **Update session record**:

```sql
UPDATE bot_sessions
SET status = 'completed',
    ended_at = NOW(),
    task_summary = 'Session ended. [X] tasks completed. Next priority: [description].'
WHERE session_id = '<my_session_id>';
```

### Memory Flush Rules

- ALWAYS flush before exiting, even on errors.
- Keep flushed data actionable, not just descriptive.
- The next session should be able to read the flush and know exactly what to do next.
- Never flush sensitive data (API keys, passwords) to MEMORY.md.

---

## Session Startup

When a new session begins, before entering the loop:

1. **Read MEMORY.md** for any context from previous sessions.
2. **Check `activity_log`** for the most recent `session_summary` from this bot.
3. **Check `notifications`** for any pending messages or instructions.
4. **Check `task_queue`** for pending tasks.
5. **Register the session** in `bot_sessions`.

```sql
INSERT INTO bot_sessions (bot_name, session_id, status, started_at, last_heartbeat, context_usage_pct)
VALUES ('<my_bot_name>', '<new_session_id>', 'active', NOW(), NOW(), 0);
```

Then enter the main loop.

---

## Concurrency Safety

- Always use `status = 'pending'` checks when claiming tasks to avoid double-execution.
- If two bots could work the same queue, use `assigned_to` to partition work.
- Never assume you are the only bot running. Check before acting.
