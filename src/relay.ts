import { supabase } from "./boot";
import type { BotConfig } from "./types";

const CLAUDE_PATH = process.env.CLAUDE_PATH || "claude";
const WORKSPACE = process.env.WORKSPACE_DIR || "/app/workspace";

// Track the active session ID for --resume
let sessionId: string | null = null;

export async function handleMessage(
  botConfig: BotConfig,
  userId: string,
  messageText: string
): Promise<string> {
  const startTime = Date.now();

  try {
    // 1. Log inbound message
    await supabase.from("conversations").insert({
      bot_name: botConfig.bot_name,
      channel: "telegram",
      direction: "inbound",
      sender: userId,
      content: messageText,
      session_id: sessionId,
    });

    // 2. Build the prompt with full database context
    const prompt = await buildPrompt(botConfig, messageText);

    // 3. Spawn Claude Code CLI
    const rawResponse = await spawnClaude(prompt, botConfig.model);

    // 4. Parse response for action tags and execute them
    const { cleanResponse, actions } = parseActions(rawResponse);
    await executeActions(botConfig, actions);

    // 5. Log outbound response
    await supabase.from("conversations").insert({
      bot_name: botConfig.bot_name,
      channel: "telegram",
      direction: "outbound",
      sender: botConfig.bot_name,
      content: cleanResponse,
      session_id: sessionId,
    });

    // 6. Log activity
    await supabase.from("activity_log").insert({
      bot_name: botConfig.bot_name,
      action: "message_processed",
      category: "conversation",
      severity: "info",
      summary: `Processed message from ${userId}`,
      duration_ms: Date.now() - startTime,
      session_id: sessionId,
      details: actions.length ? { actions_taken: actions.map(a => a.type) } : {},
    });

    return cleanResponse;
  } catch (err: any) {
    console.error("[RELAY] Error:", err.message);

    await supabase.from("activity_log").insert({
      bot_name: botConfig.bot_name,
      action: "message_error",
      category: "error",
      severity: "error",
      summary: `Failed to process message: ${err.message}`,
      duration_ms: Date.now() - startTime,
    });

    return "Something went wrong processing your message. I've logged the error.";
  }
}

// ============================================================================
// CONTEXT INJECTION — Feed Claude everything it needs from the database
// ============================================================================

async function buildPrompt(
  botConfig: BotConfig,
  messageText: string
): Promise<string> {
  // Fetch all context in parallel
  const [decisions, tasks, goals, recentConversations, reminders, projects] =
    await Promise.all([
      supabase
        .from("decisions")
        .select("topic, decision")
        .eq("is_active", true)
        .limit(20)
        .then((r) => r.data || []),
      supabase
        .from("tasks")
        .select("title, status, priority, due_date, project_id, description")
        .in("status", ["pending", "in_progress", "blocked"])
        .order("priority", { ascending: true })
        .limit(15)
        .then((r) => r.data || []),
      supabase
        .from("goals")
        .select("title, category, progress_pct, target_date, current_value, target_value, target_unit")
        .eq("status", "active")
        .limit(10)
        .then((r) => r.data || []),
      supabase
        .from("conversations")
        .select("sender, content, created_at")
        .eq("bot_name", botConfig.bot_name)
        .order("created_at", { ascending: false })
        .limit(6)
        .then((r) => r.data?.reverse() || []),
      supabase
        .from("reminders")
        .select("title, remind_at, priority")
        .eq("bot_name", botConfig.bot_name)
        .eq("status", "pending")
        .order("remind_at", { ascending: true })
        .limit(5)
        .then((r) => r.data || []),
      supabase
        .from("projects")
        .select("name, status, priority, target_date")
        .in("status", ["active", "planning"])
        .limit(10)
        .then((r) => r.data || []),
    ]);

  let context = `## SYSTEM INSTRUCTIONS
When you need to create, update, or complete items, include action tags in your response.
The relay will parse these and write to the database automatically.
Always include the tag AND a natural response to the user.

Available action tags (put each on its own line):
[TASK_CREATE: title | priority: critical/high/medium/low | due: YYYY-MM-DD]
[TASK_COMPLETE: title]
[GOAL_CREATE: title | category: fitness/business/family/health/learning/financial | target: number unit | due: YYYY-MM-DD]
[GOAL_UPDATE: title | progress: number]
[REMEMBER: key | value]
[REMINDER: title | when: YYYY-MM-DDTHH:MM | recurring: daily/weekly/none]
[DECISION: topic | decision text]

Example: If the user says "create a task to launch HVAC", respond naturally AND include:
[TASK_CREATE: Launch HVAC software | priority: critical | due: 2026-04-15]
`;

  if (decisions.length) {
    context += "\n## Active Decisions (never re-ask these)\n";
    context += decisions.map((d: any) => `- **${d.topic}:** ${d.decision}`).join("\n");
  }

  if (projects.length) {
    context += "\n\n## Active Projects\n";
    context += projects
      .map((p: any) => `- ${p.name} [${p.status}] (${p.priority}${p.target_date ? `, target ${p.target_date}` : ""})`)
      .join("\n");
  }

  if (tasks.length) {
    context += "\n\n## Active Tasks\n";
    context += tasks
      .map((t: any) => `- [${t.status}] ${t.title} (${t.priority}${t.due_date ? `, due ${t.due_date}` : ""})`)
      .join("\n");
  } else {
    context += "\n\n## Active Tasks\nNo tasks yet.";
  }

  if (goals.length) {
    context += "\n\n## Active Goals\n";
    context += goals
      .map((g: any) => `- ${g.title} (${g.category}, ${g.progress_pct}%${g.target_date ? `, target ${g.target_date}` : ""})`)
      .join("\n");
  }

  if (reminders.length) {
    context += "\n\n## Upcoming Reminders\n";
    context += reminders
      .map((r: any) => `- ${r.title} (${r.remind_at}, ${r.priority})`)
      .join("\n");
  }

  if (recentConversations.length) {
    context += "\n\n## Recent Conversation\n";
    context += recentConversations
      .map((c: any) => `${c.sender}: ${c.content.slice(0, 200)}`)
      .join("\n");
  }

  return `${context}\n\n---\n\nUser message: ${messageText}`;
}

// ============================================================================
// ACTION PARSING — Extract structured actions from Claude's response
// ============================================================================

interface Action {
  type: string;
  params: Record<string, string>;
  raw: string;
}

function parseActions(response: string): { cleanResponse: string; actions: Action[] } {
  const actions: Action[] = [];
  let cleanResponse = response;

  // Parse [TASK_CREATE: title | priority: X | due: Y]
  const taskCreateRegex = /\[TASK_CREATE:\s*(.+?)(?:\s*\|\s*priority:\s*(\w+))?(?:\s*\|\s*due:\s*([\d-]+))?\]/gi;
  for (const match of response.matchAll(taskCreateRegex)) {
    actions.push({
      type: "task_create",
      params: { title: match[1].trim(), priority: match[2] || "medium", due_date: match[3] || "" },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [TASK_COMPLETE: title]
  const taskCompleteRegex = /\[TASK_COMPLETE:\s*(.+?)\]/gi;
  for (const match of response.matchAll(taskCompleteRegex)) {
    actions.push({
      type: "task_complete",
      params: { title: match[1].trim() },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [GOAL_CREATE: title | category: X | target: N unit | due: Y]
  const goalCreateRegex = /\[GOAL_CREATE:\s*(.+?)(?:\s*\|\s*category:\s*(\w+))?(?:\s*\|\s*target:\s*([\d.]+)\s*(\w+))?(?:\s*\|\s*due:\s*([\d-]+))?\]/gi;
  for (const match of response.matchAll(goalCreateRegex)) {
    actions.push({
      type: "goal_create",
      params: {
        title: match[1].trim(),
        category: match[2] || "other",
        target_value: match[3] || "",
        target_unit: match[4] || "",
        target_date: match[5] || "",
      },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [GOAL_UPDATE: title | progress: N]
  const goalUpdateRegex = /\[GOAL_UPDATE:\s*(.+?)\s*\|\s*progress:\s*([\d.]+)\]/gi;
  for (const match of response.matchAll(goalUpdateRegex)) {
    actions.push({
      type: "goal_update",
      params: { title: match[1].trim(), progress: match[2] },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [REMEMBER: key | value]
  const rememberRegex = /\[REMEMBER:\s*(.+?)\s*\|\s*(.+?)\]/gi;
  for (const match of response.matchAll(rememberRegex)) {
    actions.push({
      type: "remember",
      params: { key: match[1].trim(), value: match[2].trim() },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [REMINDER: title | when: datetime | recurring: rule]
  const reminderRegex = /\[REMINDER:\s*(.+?)(?:\s*\|\s*when:\s*([\dT:-]+))?(?:\s*\|\s*recurring:\s*(\w+))?\]/gi;
  for (const match of response.matchAll(reminderRegex)) {
    actions.push({
      type: "reminder_create",
      params: { title: match[1].trim(), when: match[2] || "", recurring: match[3] || "none" },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Parse [DECISION: topic | decision]
  const decisionRegex = /\[DECISION:\s*(.+?)\s*\|\s*(.+?)\]/gi;
  for (const match of response.matchAll(decisionRegex)) {
    actions.push({
      type: "decision",
      params: { topic: match[1].trim(), decision: match[2].trim() },
      raw: match[0],
    });
    cleanResponse = cleanResponse.replace(match[0], "").trim();
  }

  // Clean up any leftover empty lines from tag removal
  cleanResponse = cleanResponse.replace(/\n{3,}/g, "\n\n").trim();

  return { cleanResponse, actions };
}

// ============================================================================
// ACTION EXECUTION — Write parsed actions to Supabase
// ============================================================================

async function executeActions(botConfig: BotConfig, actions: Action[]) {
  for (const action of actions) {
    try {
      switch (action.type) {
        case "task_create": {
          const { error } = await supabase.from("tasks").insert({
            bot_name: botConfig.bot_name,
            title: action.params.title,
            priority: action.params.priority,
            due_date: action.params.due_date || null,
            status: "pending",
            created_by: botConfig.bot_name,
          });
          if (error) console.error("[ACTION] Task create failed:", error.message);
          else console.log(`[ACTION] Task created: ${action.params.title}`);
          break;
        }

        case "task_complete": {
          const { error } = await supabase
            .from("tasks")
            .update({ status: "completed", completed_at: new Date().toISOString() })
            .ilike("title", `%${action.params.title}%`)
            .in("status", ["pending", "in_progress"]);
          if (error) console.error("[ACTION] Task complete failed:", error.message);
          else console.log(`[ACTION] Task completed: ${action.params.title}`);
          break;
        }

        case "goal_create": {
          const { error } = await supabase.from("goals").insert({
            title: action.params.title,
            category: action.params.category,
            target_value: action.params.target_value ? parseFloat(action.params.target_value) : null,
            target_unit: action.params.target_unit || null,
            target_date: action.params.target_date || null,
            bot_name: botConfig.bot_name,
            status: "active",
          });
          if (error) console.error("[ACTION] Goal create failed:", error.message);
          else console.log(`[ACTION] Goal created: ${action.params.title}`);
          break;
        }

        case "goal_update": {
          const { error } = await supabase
            .from("goals")
            .update({
              current_value: parseFloat(action.params.progress),
              progress_pct: parseFloat(action.params.progress),
            })
            .ilike("title", `%${action.params.title}%`)
            .eq("status", "active");
          if (error) console.error("[ACTION] Goal update failed:", error.message);
          else console.log(`[ACTION] Goal updated: ${action.params.title}`);
          break;
        }

        case "remember": {
          const { error } = await supabase.from("fleet_memory").upsert(
            {
              bot_name: botConfig.bot_name,
              category: "learned",
              key: action.params.key,
              value: action.params.value,
              source: "conversation",
            },
            { onConflict: "bot_name,category,key" }
          );
          if (error) console.error("[ACTION] Remember failed:", error.message);
          else console.log(`[ACTION] Remembered: ${action.params.key}`);
          break;
        }

        case "reminder_create": {
          const remindAt = action.params.when || new Date(Date.now() + 3600000).toISOString();
          const { error } = await supabase.from("reminders").insert({
            bot_name: botConfig.bot_name,
            title: action.params.title,
            remind_at: remindAt,
            is_recurring: action.params.recurring !== "none",
            recurrence_rule: action.params.recurring !== "none" ? action.params.recurring : null,
            created_by: botConfig.bot_name,
          });
          if (error) console.error("[ACTION] Reminder create failed:", error.message);
          else console.log(`[ACTION] Reminder created: ${action.params.title}`);
          break;
        }

        case "decision": {
          const { error } = await supabase.from("decisions").insert({
            topic: action.params.topic,
            decision: action.params.decision,
            decided_by: "dre",
            bot_name: botConfig.bot_name,
          });
          if (error) console.error("[ACTION] Decision failed:", error.message);
          else console.log(`[ACTION] Decision recorded: ${action.params.topic}`);
          break;
        }
      }
    } catch (err: any) {
      console.error(`[ACTION] Error executing ${action.type}:`, err.message);
    }
  }
}

// ============================================================================
// CLAUDE SPAWN — Execute Claude Code CLI
// ============================================================================

async function spawnClaude(prompt: string, model: string): Promise<string> {
  const args: string[] = [
    "-p",
    prompt,
    "--output-format",
    "text",
    "--dangerously-skip-permissions",
    "--model",
    model || "sonnet",
  ];

  // Resume existing session if we have one
  if (sessionId) {
    args.push("--resume", sessionId);
  }

  console.log(`[RELAY] Spawning claude with model=${model}, resume=${sessionId || "new"}`);

  const proc = Bun.spawn([CLAUDE_PATH, ...args], {
    cwd: WORKSPACE,
    env: {
      ...process.env,
      HOME: process.env.HOME || "/home/node",
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    console.error("[RELAY] Claude stderr:", stderr);
    throw new Error(`Claude exited with code ${exitCode}: ${stderr.slice(0, 200)}`);
  }

  // Extract session ID for future --resume
  const sessionMatch = stdout.match(/Session ID: ([a-f0-9-]+)/i);
  if (sessionMatch) {
    sessionId = sessionMatch[1];
    console.log(`[RELAY] Session ID: ${sessionId}`);
  }

  // Clean up the response — remove session ID line if present
  const response = stdout
    .replace(/Session ID: [a-f0-9-]+\n?/gi, "")
    .trim();

  return response || "I processed your message but had no response.";
}

export function sendScheduledMessage(
  botConfig: BotConfig,
  prompt: string
): Promise<string> {
  return handleMessage(botConfig, "system", prompt);
}
