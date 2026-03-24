# KaldrClaw

Universal AI agent fleet engine. Claude Code + Telegram + Supabase.

One repo. One Dockerfile. Multiple bots. Set `BOT_NAME` and deploy.

## What It Does

Your bots run 24/7 on Railway, respond via Telegram, and have access to your email, calendar, web search, and a 25-table Supabase database. Bot identity (personality, skills, schedule) loads from the database at boot — not from the repo.

**Built-in capabilities:**
- Read and send email (Gmail MCP)
- Read and manage calendar (Google Calendar MCP)
- Web search (Brave Search) and page scraping (Firecrawl)
- Task, project, and goal tracking with action tags
- Contact/CRM management
- Wellness and accountability tracking
- Scheduled briefings (morning, afternoon, evening, wind-down)
- Persistent memory across restarts (Railway volume + Supabase)
- 36 skills: sales, marketing, content, SEO, documents, research, and more

## Architecture

```
Telegram ← grammY bot → spawns claude -p → response back to Telegram
                              ↕
                    Supabase (25 tables)
                    Gmail / Calendar / Search MCP servers
                    36 skills loaded from /skills/
```

- **Engine:** Bun + TypeScript + grammY
- **Brain:** Claude Code CLI (spawned per message via `claude -p`)
- **Database:** Supabase (25 tables — tasks, projects, contacts, revenue, wellness, goals, and more)
- **Identity:** Loaded from `bot_configs` table at boot
- **MCP:** Gmail, Calendar, Supabase, Brave Search, Firecrawl, GitHub (all headless-compatible)
- **Hosting:** Railway (one service per bot, same repo)

## Quick Start

1. Fork this repo
2. Set up a [Supabase](https://supabase.com) project and run the migrations in `supabase/migrations/` (001-028)
3. Insert your bot config into the `bot_configs` table (personality, skills, schedule)
4. Insert your user profile into `user_profiles`
5. Create a Telegram bot via [@BotFather](https://t.me/BotFather)
6. Get a Claude Code auth token: `claude setup-token`
7. Get a Google refresh token: `GOOGLE_CLIENT_ID=xxx GOOGLE_CLIENT_SECRET=yyy npx tsx scripts/get-google-token.ts`
8. Deploy to [Railway](https://railway.com) with these env vars:

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `BOT_NAME` | Name matching your `bot_configs` row |
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token` |
| `TELEGRAM_BOT_TOKEN` | From @BotFather |
| `TELEGRAM_USER_ID` | Your Telegram user ID |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key |
| `TZ` | Your timezone (e.g., `America/New_York`) |

### Optional (for Gmail, Calendar, Search)

| Variable | Description |
|----------|-------------|
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |
| `GOOGLE_REFRESH_TOKEN` | From the token generator script |
| `BRAVE_API_KEY` | Brave Search API key (free tier: 2,000/mo) |
| `FIRECRAWL_API_KEY` | Firecrawl API key for web scraping |
| `GITHUB_TOKEN` | GitHub PAT for repo access |

### Railway Setup

1. New Project > Deploy from GitHub repo
2. Add all env vars above
3. Attach a volume at `/app/persist`
4. Deploy

## Adding a New Bot

Same repo. New Railway service. Different identity.

1. Insert a row into `bot_configs` with your bot's soul, personality, and config
2. Create a new Telegram bot via @BotFather
3. Add a new Railway service from the same repo
4. Set `BOT_NAME` to your new bot's name + all required env vars
5. Attach a volume at `/app/persist`
6. Deploy

All bots share the same Supabase database. They can see each other's tasks, decisions, and fleet memory.

## Skills (36 included)

Skills are markdown instruction files loaded at boot. Shared skills go to all bots. Bot-specific skills load based on `BOT_NAME`.

### Shared (all bots)
`daily-rhythm` `context-recovery` `clawlist` `project-context-sync` `autonomous-loop` `health-monitor` `deep-research` `superpowers` `pdf` `docx` `xlsx` `internal-comms` `skill-creator` `mcp-builder` `marketing-writer` `copywriting` `content-strategy` `social-content` `cold-email` `email-sequence` `ai-seo` `claude-seo` `revops` `sales-enablement` `pricing-strategy` `context-compression` `memory-systems` `multi-agent-patterns` `openclaw-workspace`

### Ava (Chief of Staff)
`accountability`

### Sarah (Sales)
`cold-outreach` `lead-generation` `pipeline-tracker`

### Carter (Content)
`brand-voice` `social-publishing` `trend-research`

## Database (25 tables)

| Table | Purpose |
|-------|---------|
| `bot_configs` | Bot identity, personality, model config, skills, MCP overrides |
| `user_profiles` | User preferences, work patterns, wellness goals |
| `projects` | High-level initiatives with milestones and blockers |
| `tasks` | Multi-status tasks with recurrence, subtasks, project links |
| `goals` | Measurable commitments with progress tracking |
| `contacts` | CRM-lite: people, relationships, deal pipeline, follow-ups |
| `decisions` | Things bots never re-ask |
| `revenue` | Income tracking with Stripe integration |
| `fleet_memory` | Cross-bot knowledge sharing |
| `conversations` | Telegram message history with threading |
| `briefings` | Scheduled briefing history |
| `wellness` | Fitness, sleep, hydration, family time tracking with streaks |
| `reminders` | Persistent scheduled actions that survive restarts |
| `email_summaries` | Triaged email cache |
| `calendar_events` | Cached calendar events with conflict detection |
| `content_queue` | Social media draft → approval → publish pipeline |
| `notifications` | System alerts with severity and delivery tracking |
| `automation_rules` | Trigger-action workflows |
| `knowledge_base` | Long-form reference material with full-text search |
| `templates` | Reusable content structures |
| `rate_limits` | Per-bot token budget tracking |
| `bot_sessions` | Active session health monitoring |
| `integrations` | External service connection status |
| `activity_log` | Append-only audit trail |

## How It Works

1. Container starts > `entrypoint.sh` fixes volume permissions, drops to node user
2. `boot.ts` queries Supabase for `bot_configs` where `bot_name = $BOT_NAME`
3. Writes SOUL.md, CLAUDE.md, MEMORY.md, .mcp.json to workspace from database
4. Copies shared + bot-specific skills into `.claude/skills/`
5. Starts grammY Telegram bot polling
6. Starts scheduler (checks reminders every 60s, sends heartbeats)
7. Each message: builds context (decisions, tasks, goals, projects, conversations from Supabase) > spawns `claude -p` > parses action tags from response > writes to Supabase > sends clean response to Telegram

## Built by Kaldr Tech

[kaldrtech.com](https://kaldrtech.com)
