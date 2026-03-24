import { Bot } from "grammy";
import { boot, supabase } from "./boot";
import { handleMessage } from "./relay";
import { startScheduler, stopScheduler } from "./scheduler";

// ============================================================================
// KaldrClaw — Universal AI Agent Fleet Engine
// ============================================================================

const BOT_NAME = process.env.BOT_NAME;
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_USER_ID = process.env.TELEGRAM_USER_ID;

if (!BOT_NAME) throw new Error("BOT_NAME env var is required");
if (!TELEGRAM_BOT_TOKEN) throw new Error("TELEGRAM_BOT_TOKEN env var is required");
if (!process.env.SUPABASE_URL) throw new Error("SUPABASE_URL env var is required");
if (!process.env.SUPABASE_SERVICE_ROLE_KEY) throw new Error("SUPABASE_SERVICE_ROLE_KEY env var is required");

async function main() {
  console.log("===========================================");
  console.log(`  KaldrClaw — Starting ${BOT_NAME}`);
  console.log("===========================================");

  // 1. Boot — load config from Supabase, hydrate workspace
  const { config, profile } = await boot(BOT_NAME);

  // 2. Initialize Telegram bot
  const bot = new Bot(TELEGRAM_BOT_TOKEN!);

  // Auth middleware — only allow the owner
  bot.use(async (ctx, next) => {
    if (TELEGRAM_USER_ID && ctx.from?.id?.toString() !== TELEGRAM_USER_ID) {
      console.log(`[AUTH] Rejected message from ${ctx.from?.id} (${ctx.from?.username})`);
      return; // Silently ignore unauthorized users
    }
    await next();
  });

  // Handle text messages
  bot.on("message:text", async (ctx) => {
    const text = ctx.message.text;
    const userId = ctx.from?.id?.toString() || "unknown";

    console.log(`[MSG] From ${ctx.from?.username || userId}: ${text.slice(0, 100)}`);

    // Show typing indicator
    await ctx.replyWithChatAction("typing");

    // Process through Claude Code
    const response = await handleMessage(config, userId, text);

    // Split long messages (Telegram 4096 char limit)
    const chunks = splitMessage(response, 4000);
    for (const chunk of chunks) {
      await ctx.reply(chunk, { parse_mode: "Markdown" }).catch(async () => {
        // Fallback without markdown if parsing fails
        await ctx.reply(chunk);
      });
    }
  });

  // Handle /start command
  bot.command("start", async (ctx) => {
    await ctx.reply(
      `${config.display_name} online. ${config.personality}\n\nSend me a message to get started.`
    );
  });

  // Handle /status command
  bot.command("status", async (ctx) => {
    const { data: session } = await supabase
      .from("bot_sessions")
      .select("*")
      .eq("bot_name", BOT_NAME)
      .eq("status", "active")
      .order("started_at", { ascending: false })
      .limit(1)
      .single();

    const { count: taskCount } = await supabase
      .from("tasks")
      .select("*", { count: "exact", head: true })
      .in("status", ["pending", "in_progress"]);

    const { count: reminderCount } = await supabase
      .from("reminders")
      .select("*", { count: "exact", head: true })
      .eq("status", "pending");

    await ctx.reply(
      `**${config.display_name} Status**\n` +
        `Health: ${session?.health_status || "unknown"}\n` +
        `Model: ${config.model}\n` +
        `Active tasks: ${taskCount || 0}\n` +
        `Pending reminders: ${reminderCount || 0}\n` +
        `Uptime since: ${session?.started_at || "unknown"}`
    );
  });

  // 3. Start the scheduler (reminders, heartbeats)
  const sendTelegram = async (text: string) => {
    if (TELEGRAM_USER_ID) {
      const chunks = splitMessage(text, 4000);
      for (const chunk of chunks) {
        await bot.api.sendMessage(TELEGRAM_USER_ID, chunk).catch(console.error);
      }
    }
  };
  startScheduler(config, sendTelegram);

  // 4. Graceful shutdown
  const shutdown = async () => {
    console.log("[SHUTDOWN] Shutting down gracefully...");
    stopScheduler();

    await supabase
      .from("bot_sessions")
      .update({ status: "terminated", ended_at: new Date().toISOString() })
      .eq("bot_name", BOT_NAME)
      .eq("status", "active");

    await supabase.from("activity_log").insert({
      bot_name: BOT_NAME,
      action: "bot_stopped",
      category: "system",
      severity: "info",
      summary: `${config.display_name} shutting down`,
    });

    bot.stop();
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  // 5. Launch
  console.log(`[TELEGRAM] Starting bot polling...`);
  bot.start({
    onStart: () => {
      console.log(`[TELEGRAM] ${config.display_name} is live on Telegram!`);

      // Send startup message if we have the user ID
      if (TELEGRAM_USER_ID) {
        bot.api
          .sendMessage(
            TELEGRAM_USER_ID,
            `${config.display_name} is online and ready.`
          )
          .catch(console.error);
      }
    },
  });
}

function splitMessage(text: string, maxLength: number): string[] {
  if (text.length <= maxLength) return [text];

  const chunks: string[] = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= maxLength) {
      chunks.push(remaining);
      break;
    }

    // Try to split at paragraph, then newline, then space
    let splitAt = remaining.lastIndexOf("\n\n", maxLength);
    if (splitAt === -1 || splitAt < maxLength * 0.5) {
      splitAt = remaining.lastIndexOf("\n", maxLength);
    }
    if (splitAt === -1 || splitAt < maxLength * 0.5) {
      splitAt = remaining.lastIndexOf(" ", maxLength);
    }
    if (splitAt === -1) {
      splitAt = maxLength;
    }

    chunks.push(remaining.slice(0, splitAt));
    remaining = remaining.slice(splitAt).trimStart();
  }

  return chunks;
}

// Run
main().catch((err) => {
  console.error("[FATAL]", err);
  process.exit(1);
});
