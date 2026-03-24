# KaldrClaw

Universal AI agent fleet engine. Claude Code + Telegram + Supabase.

One repo. One Dockerfile. Multiple bots. Set `BOT_NAME` and deploy.

## Quick Start

1. Fork this repo
2. Set up a [Supabase](https://supabase.com) project and run the migrations in `supabase/migrations/`
3. Add your bot config to the `bot_configs` table
4. Create a Telegram bot via [@BotFather](https://t.me/BotFather)
5. Deploy to [Railway](https://railway.com) with these env vars:

| Variable | Description |
|----------|-------------|
| `BOT_NAME` | Name matching your `bot_configs` row |
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token` |
| `TELEGRAM_BOT_TOKEN` | From @BotFather |
| `TELEGRAM_USER_ID` | Your Telegram user ID |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key |
| `TZ` | Your timezone (e.g., `America/New_York`) |

## Architecture

- **Engine:** Bun + TypeScript + grammY
- **Brain:** Claude Code CLI (spawned per message via `claude -p`)
- **Database:** Supabase (25 tables — tasks, projects, memory, contacts, revenue, wellness, and more)
- **Identity:** Loaded from `bot_configs` table at boot — not hardcoded in the repo
- **Hosting:** Railway (one service per bot, same repo)

## Adding a New Bot

1. Insert a row into `bot_configs` with your bot's soul, personality, and config
2. Create a new Telegram bot via @BotFather
3. Add a new Railway service from the same repo
4. Set `BOT_NAME` to your new bot's name
5. Deploy
