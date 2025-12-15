-- =============================================================================
-- SmartZap v2 - Consolidated Schema for Supabase
-- Combined Migration: 0001 + 0002 + 0003 + Updates
-- =============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- CAMPAIGNS
-- =============================================================================

CREATE TABLE IF NOT EXISTS campaigns (
  id TEXT PRIMARY KEY DEFAULT concat('c_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Rascunho',
  template_name TEXT,
  template_id TEXT,
  template_variables JSONB,
  scheduled_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  total_recipients INTEGER DEFAULT 0,
  sent INTEGER DEFAULT 0,
  delivered INTEGER DEFAULT 0,
  read INTEGER DEFAULT 0,
  failed INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(created_at DESC);

-- =============================================================================
-- CONTACTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS contacts (
  id TEXT PRIMARY KEY DEFAULT concat('ct_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL UNIQUE,
  email TEXT,
  status TEXT DEFAULT 'Opt-in',
  tags JSONB DEFAULT '[]'::jsonb,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_contacts_phone ON contacts(phone);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON contacts(status);

-- =============================================================================
-- CAMPAIGN CONTACTS (Junction Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS campaign_contacts (
  id TEXT PRIMARY KEY DEFAULT concat('cc_', replace(uuid_generate_v4()::text, '-', '')::text),
  campaign_id TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  contact_id TEXT,
  phone TEXT NOT NULL,
  name TEXT,
  status TEXT DEFAULT 'pending',
  message_id TEXT,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  error TEXT,
  failure_code INTEGER,
  failure_reason TEXT,
  UNIQUE(campaign_id, phone)
);

CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign ON campaign_contacts(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_status ON campaign_contacts(status);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_failure ON campaign_contacts(failure_code);

-- =============================================================================
-- TEMPLATES
-- =============================================================================

CREATE TABLE IF NOT EXISTS templates (
  id TEXT PRIMARY KEY DEFAULT concat('tpl_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL UNIQUE,
  category TEXT,
  language TEXT DEFAULT 'pt_BR',
  status TEXT,
  components JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_templates_name ON templates(name);
CREATE INDEX IF NOT EXISTS idx_templates_status ON templates(status);

-- =============================================================================
-- SETTINGS (Key-Value Store)
-- =============================================================================

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- ACCOUNT ALERTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS account_alerts (
  id TEXT PRIMARY KEY DEFAULT concat('alert_', replace(uuid_generate_v4()::text, '-', '')::text),
  type TEXT NOT NULL,
  code INTEGER,
  message TEXT NOT NULL,
  details JSONB,
  dismissed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_account_alerts_type ON account_alerts(type);
CREATE INDEX IF NOT EXISTS idx_account_alerts_dismissed ON account_alerts(dismissed);

-- =============================================================================
-- BOTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS bots (
  id TEXT PRIMARY KEY DEFAULT concat('bot_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL,
  phone_number_id TEXT NOT NULL,
  flow_id TEXT,
  status TEXT DEFAULT 'draft',
  welcome_message TEXT,
  fallback_message TEXT,
  session_timeout_minutes INTEGER DEFAULT 30,
  trigger_keywords JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bots_phone_number_id ON bots(phone_number_id);
CREATE INDEX IF NOT EXISTS idx_bots_status ON bots(status);

-- =============================================================================
-- FLOWS
-- =============================================================================

CREATE TABLE IF NOT EXISTS flows (
  id TEXT PRIMARY KEY DEFAULT concat('flow_', replace(uuid_generate_v4()::text, '-', '')::text),
  bot_id TEXT NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  nodes JSONB NOT NULL DEFAULT '[]'::jsonb,
  edges JSONB NOT NULL DEFAULT '[]'::jsonb,
  version INTEGER DEFAULT 1,
  status TEXT DEFAULT 'draft',
  is_main_flow BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_flows_bot_id ON flows(bot_id);
CREATE INDEX IF NOT EXISTS idx_flows_status ON flows(status);

-- =============================================================================
-- BOT CONVERSATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS bot_conversations (
  id TEXT PRIMARY KEY DEFAULT concat('conv_', replace(uuid_generate_v4()::text, '-', '')::text),
  bot_id TEXT NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  contact_phone TEXT NOT NULL,
  contact_name TEXT,
  current_node_id TEXT,
  status TEXT DEFAULT 'active',
  assigned_operator_id TEXT,
  csw_started_at TIMESTAMPTZ,
  csw_expires_at TIMESTAMPTZ,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bot_conversations_bot_id ON bot_conversations(bot_id);
CREATE INDEX IF NOT EXISTS idx_bot_conversations_contact ON bot_conversations(contact_phone);
CREATE INDEX IF NOT EXISTS idx_bot_conversations_status ON bot_conversations(status);
CREATE INDEX IF NOT EXISTS idx_bot_conversations_last_message ON bot_conversations(last_message_at DESC);

-- =============================================================================
-- BOT MESSAGES
-- =============================================================================

CREATE TABLE IF NOT EXISTS bot_messages (
  id TEXT PRIMARY KEY DEFAULT concat('msg_', replace(uuid_generate_v4()::text, '-', '')::text),
  conversation_id TEXT NOT NULL REFERENCES bot_conversations(id) ON DELETE CASCADE,
  wa_message_id TEXT,
  direction TEXT NOT NULL, -- 'inbound' | 'outbound'
  origin TEXT NOT NULL,    -- 'client' | 'bot' | 'operator' | 'ai'
  type TEXT NOT NULL,      -- 'text' | 'image' | 'video' | etc.
  content JSONB NOT NULL,
  status TEXT DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bot_messages_conversation ON bot_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_bot_messages_wa_id ON bot_messages(wa_message_id);
CREATE INDEX IF NOT EXISTS idx_bot_messages_created ON bot_messages(created_at DESC);

-- =============================================================================
-- CONVERSATION VARIABLES
-- =============================================================================

CREATE TABLE IF NOT EXISTS conversation_variables (
  id TEXT PRIMARY KEY DEFAULT concat('var_', replace(uuid_generate_v4()::text, '-', '')::text),
  conversation_id TEXT NOT NULL REFERENCES bot_conversations(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  collected_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(conversation_id, key)
);

CREATE INDEX IF NOT EXISTS idx_conversation_variables_conv ON conversation_variables(conversation_id);

-- =============================================================================
-- AI AGENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS ai_agents (
  id TEXT PRIMARY KEY DEFAULT concat('agent_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL,
  system_prompt TEXT NOT NULL,
  model TEXT DEFAULT 'gemini-1.5-flash',
  max_tokens INTEGER DEFAULT 500,
  temperature NUMERIC(3,2) DEFAULT 0.7,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- =============================================================================
-- AI TOOLS
-- =============================================================================

CREATE TABLE IF NOT EXISTS ai_tools (
  id TEXT PRIMARY KEY DEFAULT concat('tool_', replace(uuid_generate_v4()::text, '-', '')::text),
  agent_id TEXT NOT NULL REFERENCES ai_agents(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  parameters_schema JSONB NOT NULL,
  webhook_url TEXT NOT NULL,
  timeout_ms INTEGER DEFAULT 10000,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_tools_agent ON ai_tools(agent_id);

-- =============================================================================
-- TOOL EXECUTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS tool_executions (
  id TEXT PRIMARY KEY DEFAULT concat('exec_', replace(uuid_generate_v4()::text, '-', '')::text),
  tool_id TEXT NOT NULL REFERENCES ai_tools(id) ON DELETE CASCADE,
  conversation_id TEXT NOT NULL,
  input JSONB NOT NULL,
  output JSONB,
  duration_ms INTEGER,
  status TEXT DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tool_executions_tool ON tool_executions(tool_id);
CREATE INDEX IF NOT EXISTS idx_tool_executions_conversation ON tool_executions(conversation_id);

-- =============================================================================
-- FLOW EXECUTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS flow_executions (
  id TEXT PRIMARY KEY DEFAULT concat('fexec_', replace(uuid_generate_v4()::text, '-', '')::text),
  flow_id TEXT NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
  mode TEXT NOT NULL, -- 'campaign' | 'chatbot'
  status TEXT DEFAULT 'pending',
  trigger_source TEXT,
  contact_count INTEGER DEFAULT 0,
  sent_count INTEGER DEFAULT 0,
  delivered_count INTEGER DEFAULT 0,
  read_count INTEGER DEFAULT 0,
  failed_count INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  paused_at TIMESTAMPTZ,
  error_code INTEGER,
  error_message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_flow_executions_flow ON flow_executions(flow_id);
CREATE INDEX IF NOT EXISTS idx_flow_executions_status ON flow_executions(status);

-- =============================================================================
-- NODE EXECUTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS node_executions (
  id TEXT PRIMARY KEY DEFAULT concat('nexec_', replace(uuid_generate_v4()::text, '-', '')::text),
  execution_id TEXT NOT NULL REFERENCES flow_executions(id) ON DELETE CASCADE,
  node_id TEXT NOT NULL,
  node_type TEXT NOT NULL,
  contact_phone TEXT,
  status TEXT DEFAULT 'pending',
  input JSONB,
  output JSONB,
  whatsapp_message_id TEXT,
  error_code INTEGER,
  error_message TEXT,
  duration_ms INTEGER,
  retry_count INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_node_executions_execution ON node_executions(execution_id);
CREATE INDEX IF NOT EXISTS idx_node_executions_node ON node_executions(node_id);
CREATE INDEX IF NOT EXISTS idx_node_executions_status ON node_executions(status);

-- =============================================================================
-- TEMPLATE WORKSPACES
-- =============================================================================

CREATE TABLE IF NOT EXISTS template_workspaces (
  id TEXT PRIMARY KEY DEFAULT concat('ws_', replace(uuid_generate_v4()::text, '-', '')::text),
  name TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- =============================================================================
-- WORKSPACE TEMPLATES
-- =============================================================================

CREATE TABLE IF NOT EXISTS workspace_templates (
  id TEXT PRIMARY KEY DEFAULT concat('wstpl_', replace(uuid_generate_v4()::text, '-', '')::text),
  workspace_id TEXT NOT NULL REFERENCES template_workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  language TEXT DEFAULT 'pt_BR',
  category TEXT DEFAULT 'UTILITY',
  status TEXT DEFAULT 'draft',
  meta_id TEXT,
  meta_status TEXT,
  rejected_reason TEXT,
  submitted_at TIMESTAMPTZ,
  components JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(workspace_id, name)
);

CREATE INDEX IF NOT EXISTS idx_workspace_templates_workspace ON workspace_templates(workspace_id);

-- =============================================================================
-- FROM: 0002_dashboard_stats_rpc.sql
-- =============================================================================

-- Create a function to get dashboard stats efficiently
create or replace function get_dashboard_stats()
returns json
language plpgsql
security definer
as $$
declare
  total_sent bigint;
  total_delivered bigint;
  total_read bigint;
  total_failed bigint;
  active_campaigns bigint;
  delivery_rate integer;
begin
  -- Calculate aggregates in a single pass (or close to it)
  select 
    coalesce(sum(sent), 0),
    coalesce(sum(delivered), 0),
    coalesce(sum(read), 0),
    coalesce(sum(failed), 0)
  into 
    total_sent,
    total_delivered,
    total_read,
    total_failed
  from campaigns;

  -- Count active campaigns
  select count(*)
  into active_campaigns
  from campaigns
  where status in ('Enviando', 'Agendado');

  -- Calculate delivery rate
  if total_sent > 0 then
    delivery_rate := round((total_delivered::numeric / total_sent::numeric) * 100);
  else
    delivery_rate := 0;
  end if;

  return json_build_object(
    'totalSent', total_sent,
    'totalDelivered', total_delivered,
    'totalRead', total_read,
    'totalFailed', total_failed,
    'activeCampaigns', active_campaigns,
    'deliveryRate', delivery_rate
  );
end;
$$;

-- =============================================================================
-- FROM: 0003_enable_realtime.sql
-- Safely enable realtime via DO block
-- =============================================================================

DO $$
BEGIN
  -- Campaigns
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'campaigns') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE campaigns;
  END IF;

  -- Campaign contacts
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'campaign_contacts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE campaign_contacts;
  END IF;

  -- Contacts
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'contacts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE contacts;
  END IF;

  -- Bot conversations
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'bot_conversations') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE bot_conversations;
  END IF;

  -- Bot messages
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'bot_messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE bot_messages;
  END IF;

  -- Flows
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'flows') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE flows;
  END IF;

  -- Flow executions
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'flow_executions') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE flow_executions;
  END IF;

END $$;

-- =============================================================================
-- FROM: 20251206_add_alerts_index.sql
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_account_alerts_dismissed_created 
ON public.account_alerts (dismissed, created_at DESC);

-- =============================================================================
-- RLS: Enable and grant authenticated access
-- =============================================================================

-- Enable RLS on all user-facing tables
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE bots ENABLE ROW LEVEL SECURITY;
ALTER TABLE flows ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_variables ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_tools ENABLE ROW LEVEL SECURITY;
ALTER TABLE tool_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE flow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE node_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE template_workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_templates ENABLE ROW LEVEL SECURITY;

-- Use the built-in "authenticated" role so client requests must be signed-in
CREATE POLICY campaigns_authenticated_all ON campaigns FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY contacts_authenticated_all ON contacts FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY campaign_contacts_authenticated_all ON campaign_contacts FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY templates_authenticated_all ON templates FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY settings_authenticated_all ON settings FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY account_alerts_authenticated_all ON account_alerts FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY bots_authenticated_all ON bots FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY flows_authenticated_all ON flows FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY bot_conversations_authenticated_all ON bot_conversations FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY bot_messages_authenticated_all ON bot_messages FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY conversation_variables_authenticated_all ON conversation_variables FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY ai_agents_authenticated_all ON ai_agents FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY ai_tools_authenticated_all ON ai_tools FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY tool_executions_authenticated_all ON tool_executions FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY flow_executions_authenticated_all ON flow_executions FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY node_executions_authenticated_all ON node_executions FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY template_workspaces_authenticated_all ON template_workspaces FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY workspace_templates_authenticated_all ON workspace_templates FOR ALL TO authenticated USING (true) WITH CHECK (true);
