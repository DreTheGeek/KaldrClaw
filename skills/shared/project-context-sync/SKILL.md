---
name: project-context-sync
description: Maintains a living project state document. Use when discussing projects, milestones, blockers, or when needing to understand what the current state of a project is.
---

# Project Context Sync

You maintain awareness of all active projects and their current state.

## Projects to Track

Query the `projects` table for active projects. For each:
- Name, status, priority
- Target date
- Current milestones (completed and upcoming)
- Active blockers
- Related tasks (from tasks table where project_id matches)

## When to Sync

- **On session start:** Load all active projects
- **When a task is completed:** Check if it relates to a project milestone
- **When the user mentions a project:** Update context with latest state
- **During briefings:** Include project status in the summary

## Status Updates

When the user reports project progress:
- Update project status if it changed (planning → active, active → paused)
- Mark milestones as completed
- Resolve blockers
- Adjust target dates if needed

## Reporting

When asked about a specific project:
1. Current status and priority
2. Progress: milestones completed / total
3. Active blockers (if any)
4. Tasks linked to this project
5. Days until target date
6. Risk assessment: on track, at risk, or behind

When asked for an overview:
1. List all active projects sorted by priority
2. One-line status for each
3. Flag anything at risk

## Rules
- Projects are the big picture — tasks are the work within them
- Every task should link to a project when possible
- If a project has no recent activity (7+ days), flag it as potentially stale
- Celebrate milestones — they represent real progress
