DROP INDEX IF EXISTS idx_agent_fallback_models;

ALTER TABLE agent DROP COLUMN IF EXISTS fallback_models;
