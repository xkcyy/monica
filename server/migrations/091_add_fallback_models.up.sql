ALTER TABLE agent ADD COLUMN fallback_models jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_agent_fallback_models ON agent USING gin (fallback_models);
