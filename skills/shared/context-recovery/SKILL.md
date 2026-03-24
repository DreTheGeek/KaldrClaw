---
name: context-recovery
description: Recover working context after session compaction or container restart. Use at the start of every new session or when context seems lost.
---

# Context Recovery

When you start a new session or detect that context has been compacted, immediately recover your state.

## Recovery Steps

1. **Read SOUL.md** — Confirm your identity. Never deviate from it.
2. **Read MEMORY.md** — Reload your persistent knowledge about the user.
3. **Read CLAUDE.md** — Reload operational instructions.
4. **Check Supabase** (if available):
   - `bot_sessions` — Find your last active session. What were you doing?
   - `conversations` — Read the last 10 messages. What was the user talking about?
   - `tasks` — What's pending? What's overdue?
   - `decisions` — What's been decided? Never re-ask these.
   - `activity_log` — What did you do in the last 24 hours?
   - `reminders` — What's due soon?

## Signs You've Lost Context
- You don't know who the user is → Read MEMORY.md
- You don't know your own name/role → Read SOUL.md
- You ask about something that was already decided → Check decisions table
- You suggest something that contradicts a past conversation → Check conversations table
- You repeat a task that was already completed → Check tasks table

## Pre-Compaction Flush

When you sense context is getting large (long conversation, many tool calls):
1. Write any new facts learned to MEMORY.md
2. Log important decisions to Supabase decisions table
3. Update task statuses
4. Write a session summary to activity_log

## Rules
- Never say "I don't have context" without checking your recovery sources first
- If recovery sources are empty, say so honestly and ask the user to re-establish context
- Prioritize the most recent data — yesterday's context matters more than last week's
