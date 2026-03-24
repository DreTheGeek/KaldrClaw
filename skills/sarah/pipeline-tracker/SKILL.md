---
name: pipeline-tracker
description: Manage the sales pipeline. Track leads through stages, flag stale deals, report on metrics.
---

# Pipeline Tracker Skill

You manage the Kaldr Tech sales pipeline. You track every lead from first contact through close, flag deals that are going stale, and produce metrics Dre needs to make decisions.

---

## Pipeline Stages

Every deal moves through these stages in order:

```
prospect → contacted → demo_scheduled → proposal_sent → negotiation → closed_won → closed_lost
```

### Stage Definitions

| Stage | Definition | Entry Criteria | Exit Criteria |
|-------|-----------|----------------|---------------|
| **prospect** | Identified as a potential buyer but no outreach yet. | Lead captured with score 5+. | First outreach sent. |
| **contacted** | Outreach has been sent. Waiting for or received initial response. | First email/DM sent. | Demo or call scheduled. |
| **demo_scheduled** | A demo, call, or meeting is booked. | Calendar invite sent and confirmed. | Demo completed. |
| **proposal_sent** | Pricing or proposal has been delivered. | Proposal/quote emailed. | Prospect responds with questions, objections, or acceptance. |
| **negotiation** | Active back-and-forth on terms, pricing, or scope. | Prospect engaged on proposal details. | Verbal or written agreement, or deal killed. |
| **closed_won** | Deal signed. Customer onboarding begins. | Contract signed or payment received. | N/A (terminal state). |
| **closed_lost** | Deal is dead. Capture the reason. | Prospect declined, ghosted after 30+ days, or disqualified. | N/A (terminal state). |

---

## Updating the Pipeline

### Contacts Table: `deal_stage` Field

When moving a deal to a new stage, update the `contacts` table:

```sql
UPDATE contacts
SET deal_stage = 'new_stage',
    deal_stage_updated_at = NOW(),
    updated_at = NOW()
WHERE id = '<contact_id>';
```

Always log the stage change in the `activity_log` table:

```sql
INSERT INTO activity_log (bot_name, action_type, details, created_at)
VALUES (
  'sarah',
  'pipeline_update',
  '{"contact_id": "<id>", "from_stage": "contacted", "to_stage": "demo_scheduled", "reason": "Demo booked for Thursday 2pm"}',
  NOW()
);
```

### Rules for Stage Movement

- Stages move **forward only** under normal circumstances. The only backward movement allowed is from `negotiation` back to `proposal_sent` (if they need a revised proposal).
- Never skip stages. If someone goes from prospect to wanting a proposal, still log `contacted` and `demo_scheduled` (even if the "demo" was informal).
- Always include a reason/note when changing stages.

---

## Stale Deal Detection

A deal is **stale** when there has been no activity for too long relative to its stage.

### Staleness Thresholds

| Stage | Stale After | Action |
|-------|------------|--------|
| **prospect** | 3 days | Auto-move to contacted (send first outreach) or disqualify. |
| **contacted** | 7 days | Flag for follow-up. Send next message in cadence. |
| **demo_scheduled** | 2 days past scheduled date | Confirm demo happened. If no-show, send reschedule message. |
| **proposal_sent** | 5 days | Flag for follow-up. Send "any questions on the proposal?" nudge. |
| **negotiation** | 7 days | Escalate to Dre. This deal needs human touch. |

### Stale Detection Query

```sql
SELECT c.id, c.name, c.company, c.deal_stage, c.deal_stage_updated_at,
       EXTRACT(DAY FROM NOW() - c.deal_stage_updated_at) AS days_in_stage
FROM contacts c
WHERE c.deal_stage NOT IN ('closed_won', 'closed_lost')
  AND c.deal_stage_updated_at < NOW() - INTERVAL '7 days'
ORDER BY c.deal_stage_updated_at ASC;
```

### Stale Deal Response

When a stale deal is detected:

1. Log an alert in `activity_log` with `action_type = 'stale_deal_alert'`.
2. Determine the appropriate follow-up action based on the stage.
3. For `contacted` and `proposal_sent`: auto-draft and send follow-up using the cold-outreach skill's cadence.
4. For `negotiation`: notify Dre via the notifications table. Do NOT auto-send.
5. For `demo_scheduled` past date with no update: send a reschedule request.

---

## Pipeline Metrics

Track and report these metrics:

### Conversion Rates

Calculate stage-to-stage conversion rates:

```
prospect → contacted:       [count moved forward] / [count entered stage]
contacted → demo_scheduled: [count moved forward] / [count entered stage]
demo_scheduled → proposal:  [count moved forward] / [count entered stage]
proposal → negotiation:     [count moved forward] / [count entered stage]
negotiation → closed_won:   [count moved forward] / [count entered stage]
```

Overall conversion: `closed_won / total prospects`

### Average Deal Size

```sql
SELECT AVG(deal_value) AS avg_deal_size,
       MIN(deal_value) AS min_deal,
       MAX(deal_value) AS max_deal
FROM contacts
WHERE deal_stage = 'closed_won'
  AND deal_stage_updated_at > NOW() - INTERVAL '90 days';
```

### Time to Close

Average number of days from `prospect` to `closed_won`:

```sql
SELECT AVG(EXTRACT(DAY FROM closed_at - created_at)) AS avg_days_to_close
FROM contacts
WHERE deal_stage = 'closed_won'
  AND closed_at > NOW() - INTERVAL '90 days';
```

### Pipeline Velocity

```
Pipeline Velocity = (Number of Deals x Average Deal Value x Win Rate) / Average Sales Cycle Length
```

This tells you how much revenue per day is flowing through the pipeline.

### Active Pipeline Value

```sql
SELECT deal_stage,
       COUNT(*) AS deal_count,
       SUM(deal_value) AS total_value
FROM contacts
WHERE deal_stage NOT IN ('closed_won', 'closed_lost')
GROUP BY deal_stage
ORDER BY
  CASE deal_stage
    WHEN 'prospect' THEN 1
    WHEN 'contacted' THEN 2
    WHEN 'demo_scheduled' THEN 3
    WHEN 'proposal_sent' THEN 4
    WHEN 'negotiation' THEN 5
  END;
```

---

## Morning Sales Brief

Generate this report every morning and send to Dre via Telegram.

### Format

```
SALES BRIEF -- [Date]

PIPELINE SNAPSHOT
- Total active deals: [count]
- Pipeline value: $[total]
- Deals by stage:
  - Prospect: [count] ($[value])
  - Contacted: [count] ($[value])
  - Demo Scheduled: [count] ($[value])
  - Proposal Sent: [count] ($[value])
  - Negotiation: [count] ($[value])

STALE DEALS (need attention)
- [Company] -- stuck in [stage] for [X] days
- [Company] -- stuck in [stage] for [X] days

YESTERDAY'S ACTIVITY
- [X] new prospects added
- [X] outreach messages sent
- [X] demos completed
- [X] proposals sent
- [X] deals closed ([won/lost])

THIS WEEK'S WINS
- [Company] closed for $[value]

PRIORITY ACTIONS
1. [Most urgent action]
2. [Second priority]
3. [Third priority]
```

### Brief Rules

- Keep it scannable. Dre reads this on his phone.
- Bold the numbers that matter most.
- If pipeline is empty or thin, say so directly. Don't sugarcoat.
- Always end with 1-3 concrete next actions.

---

## Closed-Lost Tracking

When a deal is marked `closed_lost`, always capture:

1. **Reason** -- pricing, timing, went with competitor, no budget, ghosted, not a fit.
2. **Competitor** -- if they chose a competitor, which one and why.
3. **Reopen date** -- when (if ever) to revisit this lead. Default: 90 days for timing/budget, never for not-a-fit.

```sql
UPDATE contacts
SET deal_stage = 'closed_lost',
    lost_reason = 'chose ServiceTitan - wanted enterprise features we don''t have yet',
    reopen_date = NOW() + INTERVAL '90 days',
    deal_stage_updated_at = NOW(),
    updated_at = NOW()
WHERE id = '<contact_id>';
```

---

## Integration Notes

- **Pipeline data lives in**: `contacts` table, `deal_stage` column.
- **Activity history lives in**: `activity_log` table.
- **Notifications go to**: `notifications` table (Dre picks them up via Telegram bot).
- **Coordinate with**: `cold-outreach` skill for follow-up drafts, `lead-generation` skill for new prospects.
