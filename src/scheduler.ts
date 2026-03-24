import { supabase } from "./boot";
import { sendScheduledMessage } from "./relay";
import type { BotConfig } from "./types";

let schedulerInterval: ReturnType<typeof setInterval> | null = null;

export function startScheduler(botConfig: BotConfig, sendTelegram: (text: string) => Promise<void>) {
  console.log("[SCHEDULER] Starting reminder checker (every 60s)");

  schedulerInterval = setInterval(async () => {
    try {
      await checkReminders(botConfig, sendTelegram);
      await updateHeartbeat(botConfig.bot_name);
    } catch (err: any) {
      console.error("[SCHEDULER] Error:", err.message);
    }
  }, 60_000); // Check every 60 seconds

  // Also run immediately on start
  checkReminders(botConfig, sendTelegram).catch(console.error);
  updateHeartbeat(botConfig.bot_name).catch(console.error);
}

export function stopScheduler() {
  if (schedulerInterval) {
    clearInterval(schedulerInterval);
    schedulerInterval = null;
    console.log("[SCHEDULER] Stopped");
  }
}

async function checkReminders(
  botConfig: BotConfig,
  sendTelegram: (text: string) => Promise<void>
) {
  const now = new Date().toISOString();

  // Find due reminders
  const { data: reminders } = await supabase
    .from("reminders")
    .select("*")
    .eq("bot_name", botConfig.bot_name)
    .in("status", ["pending", "snoozed"])
    .lte("remind_at", now)
    .order("priority", { ascending: true })
    .limit(5);

  if (!reminders?.length) return;

  for (const reminder of reminders) {
    console.log(`[SCHEDULER] Firing reminder: ${reminder.title}`);

    // Send to Telegram
    const message = `**Reminder:** ${reminder.title}${reminder.description ? `\n${reminder.description}` : ""}`;
    await sendTelegram(message);

    // Mark as delivered
    await supabase
      .from("reminders")
      .update({
        status: "delivered",
        delivered_at: now,
        delivery_count: (reminder.delivery_count || 0) + 1,
      })
      .eq("id", reminder.id);

    // If recurring, schedule next occurrence
    if (reminder.is_recurring && reminder.recurrence_rule) {
      const nextTime = calculateNextOccurrence(
        reminder.remind_at,
        reminder.recurrence_rule
      );
      if (nextTime && (!reminder.recurrence_end || nextTime < reminder.recurrence_end)) {
        await supabase.from("reminders").insert({
          bot_name: botConfig.bot_name,
          title: reminder.title,
          description: reminder.description,
          remind_at: nextTime,
          is_recurring: true,
          recurrence_rule: reminder.recurrence_rule,
          recurrence_end: reminder.recurrence_end,
          priority: reminder.priority,
          delivery_channel: reminder.delivery_channel,
          related_id: reminder.related_id,
          related_type: reminder.related_type,
          action_type: reminder.action_type,
          created_by: "system",
        });
      }
    }

    // Log
    await supabase.from("activity_log").insert({
      bot_name: botConfig.bot_name,
      action: "reminder_fired",
      category: "reminder",
      severity: "info",
      summary: `Reminder: ${reminder.title}`,
      related_id: reminder.id,
      related_type: "reminder",
    });
  }
}

function calculateNextOccurrence(
  currentTime: string,
  rule: string
): string | null {
  const now = new Date(currentTime);

  switch (rule) {
    case "daily":
      now.setDate(now.getDate() + 1);
      return now.toISOString();
    case "weekdays":
      do {
        now.setDate(now.getDate() + 1);
      } while (now.getDay() === 0 || now.getDay() === 6);
      return now.toISOString();
    case "weekly":
      now.setDate(now.getDate() + 7);
      return now.toISOString();
    case "monthly":
      now.setMonth(now.getMonth() + 1);
      return now.toISOString();
    default:
      return null;
  }
}

async function updateHeartbeat(botName: string) {
  await supabase
    .from("bot_sessions")
    .update({
      last_heartbeat_at: new Date().toISOString(),
      last_active_at: new Date().toISOString(),
      health_status: "healthy",
    })
    .eq("bot_name", botName)
    .eq("status", "active");
}
