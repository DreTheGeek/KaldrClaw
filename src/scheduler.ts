import { supabase } from "./boot";
import { handleMessage } from "./relay";
import type { BotConfig } from "./types";

let schedulerInterval: ReturnType<typeof setInterval> | null = null;
let botConfigRef: BotConfig | null = null;
let sendTelegramRef: ((text: string) => Promise<void>) | null = null;

export function startScheduler(botConfig: BotConfig, sendTelegram: (text: string) => Promise<void>) {
  console.log("[SCHEDULER] Starting reminder checker (every 60s)");
  botConfigRef = botConfig;
  sendTelegramRef = sendTelegram;

  schedulerInterval = setInterval(async () => {
    try {
      await checkReminders(botConfig, sendTelegram);
      await updateHeartbeat(botConfig.bot_name);
    } catch (err: any) {
      console.error("[SCHEDULER] Error:", err.message);
    }
  }, 60_000);

  // Run immediately on start
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
    console.log(`[SCHEDULER] Firing: ${reminder.title} (${reminder.action_type})`);

    // Route based on action type
    if (reminder.action_type === "briefing" || reminder.action_type === "check_in") {
      // Briefings and check-ins go through Claude for a smart response
      await handleBriefing(botConfig, reminder, sendTelegram);
    } else {
      // Simple reminders just send the text
      const message = `**Reminder:** ${reminder.title}${reminder.description ? `\n${reminder.description}` : ""}`;
      await sendTelegram(message);
    }

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
      const nextTime = calculateNextOccurrence(reminder.remind_at, reminder.recurrence_rule);
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
      action: `${reminder.action_type || "reminder"}_fired`,
      category: "scheduled",
      severity: "info",
      summary: `Scheduled: ${reminder.title}`,
      related_id: reminder.id,
      related_type: "reminder",
    });
  }
}

// ============================================================================
// BRIEFING ENGINE — Generates smart briefings through Claude
// ============================================================================

async function handleBriefing(
  botConfig: BotConfig,
  reminder: any,
  sendTelegram: (text: string) => Promise<void>
) {
  const briefingType = reminder.title.toLowerCase().includes("morning")
    ? "morning"
    : reminder.title.toLowerCase().includes("wind")
    ? "wind_down"
    : reminder.title.toLowerCase().includes("afternoon")
    ? "afternoon_checkin"
    : "evening_checkin";

  let prompt = "";

  switch (briefingType) {
    case "morning":
      prompt = `You are delivering the MORNING BRIEFING. It is 9 AM ET.

Use your Gmail MCP to check for important unread emails.
Use your Calendar MCP to check today's schedule.

Then compile a briefing in this format:

**Good morning, Dre.**

📅 **Today's Schedule**
[List calendar events or "Clear day — deep work time"]

📧 **Email Highlights**
[Top 3-5 important emails with action needed, or "Inbox clear"]

✅ **Active Tasks** (from context below)
[List pending tasks with priorities]

🎯 **Goals Progress**
[Active goals and their status]

💪 **Accountability**
[Wellness check: did you sleep well? Workout planned? Hydration reminder.]

🔥 **Top Priority Today**
[The ONE thing that matters most today]

Keep it tight. No fluff. Lead with what matters.`;
      break;

    case "wind_down":
      prompt = `You are delivering the WIND-DOWN briefing. It is 11 PM ET.

Compile a brief end-of-day summary:

**Time to wrap up, Dre.**

📊 **What got done today**
[Completed tasks, messages processed, decisions made]

📋 **Tomorrow's priorities**
[Top 3 things for tomorrow based on deadlines and goals]

💪 **Wellness check**
[Did you take breaks? Family time? Workout?]

🛌 **Reminder:** Rest isn't optional. Recharge for tomorrow.

If it's past midnight and he's still working on non-urgent tasks, be more direct about stopping.`;
      break;

    case "afternoon_checkin":
      prompt = `You are delivering the 2 PM ACCOUNTABILITY CHECK-IN.

Quick check-in:
- Have you taken a break in the last 3 hours?
- Have you had water today?
- Any physical activity?
- How's the HVAC launch progress?

Keep it to 3-4 lines. Casual but firm. You're his Chief of Staff, not his mom.`;
      break;

    case "evening_checkin":
      prompt = `You are delivering the 7 PM ACCOUNTABILITY CHECK-IN.

Check in on:
- Family time today?
- Dinner?
- Top tasks completed since 2 PM?
- What's the plan for the rest of the evening?

Keep it brief. If he hasn't mentioned family time all day, flag it.`;
      break;
  }

  try {
    // Send through Claude to get a smart, contextual response
    const response = await handleMessage(botConfig, "system", prompt);

    // Send the briefing to Telegram
    await sendTelegram(response);

    // Save to briefings table
    await supabase.from("briefings").insert({
      bot_name: botConfig.bot_name,
      briefing_type: briefingType === "afternoon_checkin" || briefingType === "evening_checkin" ? "ad_hoc" : briefingType === "morning" ? "morning" : "wind_down",
      briefing_date: new Date().toISOString().split("T")[0],
      content: response,
      data_sources: briefingType === "morning" ? ["email", "calendar", "tasks", "goals", "wellness"] : ["tasks", "goals", "wellness"],
      delivered_at: new Date().toISOString(),
      delivery_channel: "telegram",
    });

    console.log(`[SCHEDULER] Briefing delivered: ${briefingType}`);
  } catch (err: any) {
    console.error(`[SCHEDULER] Briefing failed: ${err.message}`);
    await sendTelegram(`⚠️ Briefing failed: ${err.message}`);
  }
}

function calculateNextOccurrence(currentTime: string, rule: string): string | null {
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
