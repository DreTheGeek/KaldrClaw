import { createClient } from "@supabase/supabase-js";
import { writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import type { BotConfig, UserProfile } from "./types";

const WORKSPACE = process.env.WORKSPACE_DIR || "/app/workspace";

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export { supabase };

export async function boot(botName: string): Promise<{
  config: BotConfig;
  profile: UserProfile | null;
}> {
  console.log(`[BOOT] Loading bot config for: ${botName}`);

  // 1. Load bot config from Supabase
  const { data: config, error: configErr } = await supabase
    .from("bot_configs")
    .select("*")
    .eq("bot_name", botName)
    .eq("is_active", true)
    .order("version", { ascending: false })
    .limit(1)
    .single();

  if (configErr || !config) {
    throw new Error(
      `Failed to load bot config for "${botName}": ${configErr?.message || "not found"}`
    );
  }

  console.log(`[BOOT] Loaded: ${config.display_name} (${config.role})`);

  // 2. Load user profile (first active profile)
  const { data: profile } = await supabase
    .from("user_profiles")
    .select("*")
    .limit(1)
    .single();

  // 3. Hydrate workspace — write files Claude Code needs
  if (!existsSync(WORKSPACE)) {
    mkdirSync(WORKSPACE, { recursive: true });
  }

  // Write SOUL.md
  if (config.soul_text) {
    writeFileSync(join(WORKSPACE, "SOUL.md"), config.soul_text);
    console.log("[BOOT] Wrote SOUL.md");
  }

  // Write CLAUDE.md with base instructions + bot context
  const claudeMd = buildClaudeMd(config, profile);
  writeFileSync(join(WORKSPACE, "CLAUDE.md"), claudeMd);
  console.log("[BOOT] Wrote CLAUDE.md");

  // Write MEMORY.md from seed memory
  if (config.seed_memory?.length) {
    const memoryContent = config.seed_memory
      .map((m: any) => `### ${m.key}\n${m.value}`)
      .join("\n\n");
    const memoryDir = join(WORKSPACE, "memory");
    if (!existsSync(memoryDir)) mkdirSync(memoryDir, { recursive: true });
    writeFileSync(join(WORKSPACE, "MEMORY.md"), memoryContent);
    console.log("[BOOT] Wrote MEMORY.md");
  }

  // Write .claude.json MCP config so Claude Code can access tools
  const mcpConfig = buildMcpConfig();
  writeFileSync(join(WORKSPACE, ".claude.json"), JSON.stringify(mcpConfig, null, 2));
  console.log("[BOOT] Wrote .claude.json (MCP config)");

  // Initialize git repo in workspace (Claude Code expects this)
  const gitDir = join(WORKSPACE, ".git");
  if (!existsSync(gitDir)) {
    try {
      const proc = Bun.spawnSync(["git", "init"], { cwd: WORKSPACE });
      if (proc.exitCode === 0) console.log("[BOOT] Initialized git in workspace");
    } catch {}
  }

  // Write any additional seed files
  if (config.seed_files && typeof config.seed_files === "object") {
    for (const [filename, content] of Object.entries(config.seed_files)) {
      const filePath = join(WORKSPACE, filename);
      const dir = join(filePath, "..");
      if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
      writeFileSync(filePath, content as string);
      console.log(`[BOOT] Wrote ${filename}`);
    }
  }

  // 4. Log boot to activity_log
  await supabase.from("activity_log").insert({
    bot_name: botName,
    action: "bot_started",
    category: "system",
    severity: "info",
    summary: `${config.display_name} booted successfully`,
    details: {
      model: config.model,
      autonomy: config.autonomy,
      skills: config.skills,
    },
  });

  // 5. Create a session record
  await supabase.from("bot_sessions").insert({
    bot_name: botName,
    session_id: `boot-${Date.now()}`,
    status: "active",
    model_used: config.model,
    health_status: "healthy",
  });

  console.log(`[BOOT] ${config.display_name} is ready.`);
  return { config, profile };
}

function buildClaudeMd(config: BotConfig, profile: UserProfile | null): string {
  let md = `# KALDRCLAW OPERATIONAL INSTRUCTIONS

You are ${config.display_name}, a KaldrClaw bot — an autonomous AI agent.

## YOUR IDENTITY
Read SOUL.md for your full identity. Never modify it.

## YOUR MEMORY
Read MEMORY.md for your knowledge. Update it when you learn new things.

## COMMUNICATION STYLE
- Direct. No fluff. No filler.
- Lead with the answer, then context if needed.
- Present problems with solutions, never problems alone.
`;

  if (profile) {
    md += `
## ABOUT YOUR USER
- **Name:** ${profile.display_name}
- **Timezone:** ${profile.timezone}
- **Communication style:** ${profile.communication_style || "direct"}
- **Accountability level:** ${profile.accountability_level || "medium"}
${profile.company_name ? `- **Company:** ${profile.company_name}` : ""}
${profile.peak_hours_start ? `- **Peak hours:** ${profile.peak_hours_start} - ${profile.peak_hours_end}` : ""}
`;
  }

  md += `
## MODEL ROUTING
- Use Haiku subagents for: heartbeats, quick checks, yes/no questions
- Use Sonnet (your default) for: conversations, briefings, task management
- Use Opus subagent for: strategic planning, complex analysis, important decisions

## AUTONOMY: ${config.autonomy?.toUpperCase() || "SUPERVISED"}
${config.autonomy === "fully_autonomous" ? "Act without asking. Only notify after the fact." : ""}
${config.autonomy === "semi_autonomous" ? "Act on routine tasks. Confirm on anything that costs money, sends external messages, or is irreversible." : ""}
${config.autonomy === "supervised" ? "Plan and confirm before acting. Show your reasoning. Wait for approval." : ""}

## MEMORY RULES
- Write important facts to memory when you learn them
- Before session compaction: flush all important context to memory
- Never lose a decision, preference, or task
`;

  return md;
}

function buildMcpConfig(): Record<string, any> {
  const config: Record<string, any> = { mcpServers: {} };

  // Supabase MCP — direct database access for the bot
  if (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    config.mcpServers["supabase"] = {
      command: "npx",
      args: [
        "-y",
        "@supabase/mcp-server-supabase@latest",
        "--supabase-url",
        process.env.SUPABASE_URL,
        "--supabase-service-role-key",
        process.env.SUPABASE_SERVICE_ROLE_KEY,
      ],
    };
  }

  // GitHub MCP
  if (process.env.GITHUB_TOKEN) {
    config.mcpServers["github"] = {
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-github"],
      env: { GITHUB_TOKEN: process.env.GITHUB_TOKEN },
    };
  }

  // Tavily web search MCP
  if (process.env.TAVILY_API_KEY) {
    config.mcpServers["tavily"] = {
      command: "npx",
      args: ["-y", "tavily-mcp"],
      env: { TAVILY_API_KEY: process.env.TAVILY_API_KEY },
    };
  }

  return config;
}
