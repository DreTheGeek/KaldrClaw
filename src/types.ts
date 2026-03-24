export interface BotConfig {
  id: string;
  bot_name: string;
  slug: string;
  display_name: string;
  role: string;
  personality: string;
  soul_text: string;
  seed_memory: Array<{ key: string; value: string }>;
  seed_files: Record<string, string>;
  model: string;
  max_turns: number;
  effort: string;
  autonomy: string;
  skills: string[];
  mcp_overrides: Record<string, any>;
  plugins: string[];
  schedule: Record<string, string>;
  timezone: string;
  status: string;
}

export interface UserProfile {
  id: string;
  display_name: string;
  timezone: string;
  peak_hours_start: string;
  peak_hours_end: string;
  wake_time: string;
  sleep_time: string;
  communication_style: string;
  accountability_level: string;
  wellness_goals: Record<string, any>;
  company_name: string;
  products: Array<{ name: string; status: string; priority: string }>;
}

export interface Reminder {
  id: string;
  title: string;
  description: string;
  remind_at: string;
  is_recurring: boolean;
  recurrence_rule: string;
  priority: string;
  related_type: string;
  related_id: string;
}
