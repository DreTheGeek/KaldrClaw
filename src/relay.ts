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

    // 2. Build the prompt with context
    const prompt = await buildPrompt(botConfig, messageText);

    // 3. Spawn Claude Code CLI
    const response = await spawnClaude(prompt, botConfig.model);

    // 4. Log outbound response
    await supabase.from("conversations").insert({
      bot_name: botConfig.bot_name,
      channel: "telegram",
      direction: "outbound",
      sender: botConfig.bot_name,
      content: response,
      session_id: sessionId,
    });

    // 5. Log activity
    await supabase.from("activity_log").insert({
      bot_name: botConfig.bot_name,
      action: "message_processed",
      category: "conversation",
      severity: "info",
      summary: `Processed message from ${userId}`,
      duration_ms: Date.now() - startTime,
      session_id: sessionId,
    });

    return response;
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

async function buildPrompt(
  botConfig: BotConfig,
  messageText: string
): Promise<string> {
  // Fetch recent decisions the bot should know about
  const { data: decisions } = await supabase
    .from("decisions")
    .select("topic, decision")
    .eq("is_active", true)
    .limit(20);

  // Fetch active tasks
  const { data: tasks } = await supabase
    .from("tasks")
    .select("title, status, priority, due_date")
    .in("status", ["pending", "in_progress", "blocked"])
    .order("priority", { ascending: true })
    .limit(10);

  // Fetch active goals
  const { data: goals } = await supabase
    .from("goals")
    .select("title, category, progress_pct, target_date")
    .eq("status", "active")
    .limit(10);

  let context = "";

  if (decisions?.length) {
    context += "\n## Active Decisions (never re-ask these)\n";
    context += decisions
      .map((d: any) => `- **${d.topic}:** ${d.decision}`)
      .join("\n");
  }

  if (tasks?.length) {
    context += "\n\n## Active Tasks\n";
    context += tasks
      .map(
        (t: any) =>
          `- [${t.status}] ${t.title} (${t.priority}${t.due_date ? `, due ${t.due_date}` : ""})`
      )
      .join("\n");
  }

  if (goals?.length) {
    context += "\n\n## Active Goals\n";
    context += goals
      .map(
        (g: any) =>
          `- ${g.title} (${g.category}, ${g.progress_pct}%${g.target_date ? `, target ${g.target_date}` : ""})`
      )
      .join("\n");
  }

  const prompt = context
    ? `${context}\n\n---\n\nUser message: ${messageText}`
    : messageText;

  return prompt;
}

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
      HOME: "/root",
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
