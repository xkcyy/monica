BEGIN;

DO $$
DECLARE
  ws_id uuid;
  owner_user_id uuid;
  owner_member_id uuid;
  claude_runtime_id uuid;
  codex_runtime_id uuid;
  build_project_id uuid;
  repo_ref jsonb := '{"url":"https://github.com/xkcyy/monica","default_branch_hint":"main"}'::jsonb;
  guidance_skill_id uuid;
  workflow_skill_id uuid;
  role_routing_skill_id uuid;
  claude_agent_id uuid;
  codex_agent_id uuid;
  reviewer_agent_id uuid;
  planner_agent_id uuid;
  bugfix_agent_id uuid;
  frontend_agent_id uuid;
  summarizer_agent_id uuid;
  next_number integer;
BEGIN
  SELECT id INTO ws_id
  FROM workspace
  WHERE slug = 'monica'
  ORDER BY created_at ASC
  LIMIT 1;

  IF ws_id IS NULL THEN
    INSERT INTO workspace (
      name, slug, description, context, repos, issue_prefix
    ) VALUES (
      'monica',
      'monica',
      'Recovered workspace for building the local Multica/Monica checkout.',
      'This workspace was seeded from committed repository evidence and the local production Docker deployment. It is for building the current project, not for fabricating historical agent runs.',
      jsonb_build_array(jsonb_build_object('url', 'https://github.com/xkcyy/monica')),
      'MON'
    )
    RETURNING id INTO ws_id;
  ELSE
    UPDATE workspace
    SET
      description = COALESCE(NULLIF(description, ''), 'Recovered workspace for building the local Multica/Monica checkout.'),
      context = COALESCE(
        NULLIF(context, ''),
        'This workspace was seeded from committed repository evidence and the local production Docker deployment. It is for building the current project, not for fabricating historical agent runs.'
      ),
      repos = CASE
        WHEN repos @> jsonb_build_array(jsonb_build_object('url', 'https://github.com/xkcyy/monica')) THEN repos
        ELSE repos || jsonb_build_array(jsonb_build_object('url', 'https://github.com/xkcyy/monica'))
      END,
      issue_prefix = COALESCE(NULLIF(issue_prefix, ''), 'MON'),
      updated_at = now()
    WHERE id = ws_id;
  END IF;

  SELECT m.user_id, m.id INTO owner_user_id, owner_member_id
  FROM member m
  WHERE m.workspace_id = ws_id AND m.role = 'owner'
  ORDER BY m.created_at ASC
  LIMIT 1;

  IF owner_user_id IS NULL THEN
    SELECT id INTO owner_user_id
    FROM "user"
    ORDER BY onboarded_at DESC NULLS LAST, created_at DESC
    LIMIT 1;

    IF owner_user_id IS NULL THEN
      INSERT INTO "user" (email, name, onboarded_at)
      VALUES ('dev@localhost', 'dev', now())
      ON CONFLICT (email) DO UPDATE SET onboarded_at = COALESCE("user".onboarded_at, EXCLUDED.onboarded_at)
      RETURNING id INTO owner_user_id;
    END IF;

    INSERT INTO member (workspace_id, user_id, role)
    VALUES (ws_id, owner_user_id, 'owner')
    ON CONFLICT (workspace_id, user_id) DO UPDATE SET role = 'owner'
    RETURNING id INTO owner_member_id;
  END IF;

  SELECT id INTO claude_runtime_id
  FROM agent_runtime
  WHERE workspace_id = ws_id AND provider = 'claude'
  ORDER BY status = 'online' DESC, last_seen_at DESC NULLS LAST, created_at ASC
  LIMIT 1;

  IF claude_runtime_id IS NULL THEN
    INSERT INTO agent_runtime (
      workspace_id, daemon_id, name, runtime_mode, provider, status,
      device_info, metadata, owner_id, timezone, visibility, last_seen_at
    ) VALUES (
      ws_id,
      '019e21bc-824b-77fd-ada0-6141d2a0b5d3',
      'Claude (recovered-local)',
      'local',
      'claude',
      'offline',
      '',
      '{"seeded_from":"repository_recovery"}'::jsonb,
      owner_user_id,
      'Asia/Shanghai',
      'private',
      now()
    )
    ON CONFLICT (workspace_id, daemon_id, provider) DO UPDATE
      SET updated_at = now()
    RETURNING id INTO claude_runtime_id;
  END IF;

  SELECT id INTO codex_runtime_id
  FROM agent_runtime
  WHERE workspace_id = ws_id AND provider = 'codex'
  ORDER BY status = 'online' DESC, last_seen_at DESC NULLS LAST, created_at ASC
  LIMIT 1;

  IF codex_runtime_id IS NULL THEN
    INSERT INTO agent_runtime (
      workspace_id, daemon_id, name, runtime_mode, provider, status,
      device_info, metadata, owner_id, timezone, visibility, last_seen_at
    ) VALUES (
      ws_id,
      '019e21bc-824b-77fd-ada0-6141d2a0b5d3',
      'Codex (recovered-local)',
      'local',
      'codex',
      'offline',
      '',
      '{"seeded_from":"repository_recovery"}'::jsonb,
      owner_user_id,
      'Asia/Shanghai',
      'private',
      now()
    )
    ON CONFLICT (workspace_id, daemon_id, provider) DO UPDATE
      SET updated_at = now()
    RETURNING id INTO codex_runtime_id;
  END IF;

  INSERT INTO skill (
    workspace_id, name, description, content, config, created_by
  ) VALUES (
    ws_id,
    'multica-codebase-guidelines',
    'Repository-specific architecture, boundaries, and verification rules for this Multica/Monica checkout.',
    '# Multica Codebase Guidelines

Use this skill when working in the monica repository.

- The backend is Go under `server/`.
- The web app is Next.js under `apps/web/`.
- The desktop app is Electron under `apps/desktop/`.
- Shared headless logic belongs in `packages/core/`.
- Shared UI primitives belong in `packages/ui/`.
- Shared business views belong in `packages/views/`.
- React Query owns server state; Zustand owns client state.
- Keep `packages/core` free of `react-dom`, `localStorage`, and `process.env`.
- Keep `packages/ui` free of `@multica/core`.
- Keep `packages/views` free of `next/*` and `react-router-dom`.
- For API responses consumed by UI, parse with schemas and fallbacks rather than casting raw JSON.
- Before claiming completion, run the smallest command that proves the claim.
',
    '{"seeded_from":"repository_recovery","evidence":["CLAUDE.md","AGENTS.md"]}'::jsonb,
    owner_user_id
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET description = EXCLUDED.description,
        content = EXCLUDED.content,
        config = EXCLUDED.config,
        updated_at = now()
  RETURNING id INTO guidance_skill_id;

  INSERT INTO skill (
    workspace_id, name, description, content, config, created_by
  ) VALUES (
    ws_id,
    'agent-development-workflow',
    'Conservative workflow recovered from git history and runtime code: plan, isolate, implement, verify, review, finish.',
    '# Agent Development Workflow

This is a forward-looking workflow seed, not a historical transcript.

1. Read the issue, workspace context, and project resources.
2. Check out the project repository with `multica repo checkout` when code changes are needed.
3. Use an isolated worktree or task workdir.
4. Keep implementation scoped to the issue.
5. Run focused tests or type checks before reporting completion.
6. Summarize changed files, verification commands, and known gaps in the issue comments.
7. Do not fabricate task history, run messages, or usage data.
',
    '{"seeded_from":"repository_recovery","historical_records_fabricated":false}'::jsonb,
    owner_user_id
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET description = EXCLUDED.description,
        content = EXCLUDED.content,
        config = EXCLUDED.config,
        updated_at = now()
  RETURNING id INTO workflow_skill_id;

  INSERT INTO skill (
    workspace_id, name, description, content, config, created_by
  ) VALUES (
    ws_id,
    'agent-role-routing',
    'Routing guide for the recovered Claude Code and Codex agent set.',
    '# Agent Role Routing

Use only the Claude Code and Codex runtimes for this recovered workspace.

- Claude Code Builder: primary implementation lead and cross-cutting repository maintenance.
- Codex Builder: focused code edits, mechanical refactors, and verification support.
- Code Reviewer: correctness review, risk assessment, and missing-test checks.
- Product Planner: project planning, issue shaping, PRD/spec drafting, and backlog decomposition.
- Bug Fixer: root-cause debugging and small regression fixes.
- Frontend Builder: Next.js, Electron renderer, packages/views, and packages/ui implementation work.
- Documentation Summarizer: release notes, docs cleanup, long-thread summaries, and evidence-bound recovery notes.

Do not create or imply historical task/run/message records from this routing guide. It is a usable forward configuration derived from committed code, runtime support, and template roles.
',
    '{"seeded_from":"repository_recovery","scope":"claude_codex_only"}'::jsonb,
    owner_user_id
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET description = EXCLUDED.description,
        content = EXCLUDED.content,
        config = EXCLUDED.config,
        updated_at = now()
  RETURNING id INTO role_routing_skill_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Claude Code Builder',
    'Primary local Claude Code agent for implementation, debugging, and repository maintenance.',
    NULL,
    'local',
    '{}'::jsonb,
    claude_runtime_id,
    'private',
    6,
    owner_user_id,
    'Work as the primary implementation agent for this repository. Follow CLAUDE.md and the attached codebase/workflow skills. Prefer small, verified changes; never invent historical execution records.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        updated_at = now()
  RETURNING id INTO claude_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Codex Builder',
    'Local Codex agent for code edits, analysis, and verification in this repository.',
    NULL,
    'local',
    '{}'::jsonb,
    codex_runtime_id,
    'private',
    6,
    owner_user_id,
    'Work as the Codex implementation agent for this repository. Follow AGENTS.md and the attached codebase/workflow skills. Keep work scoped, verify with concrete commands, and do not fabricate historical runs.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        updated_at = now()
  RETURNING id INTO codex_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Code Reviewer',
    'Review-focused local agent for correctness, regressions, and missing verification.',
    NULL,
    'local',
    '{}'::jsonb,
    claude_runtime_id,
    'private',
    3,
    owner_user_id,
    'Review diffs and implementation plans for correctness first. Lead with concrete findings and file references. Do not comment on style unless it creates a real maintenance or behavior risk.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        updated_at = now()
  RETURNING id INTO reviewer_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Product Planner',
    'Planning-focused Claude Code agent for PRDs, issue shaping, and implementation decomposition.',
    NULL,
    'local',
    '{}'::jsonb,
    claude_runtime_id,
    'private',
    4,
    owner_user_id,
    'Turn rough project goals into clear plans, PRDs, issue breakdowns, acceptance criteria, and implementation sequencing. Stay evidence-bound to the current repository and do not fabricate historical records.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        description = EXCLUDED.description,
        instructions = EXCLUDED.instructions,
        max_concurrent_tasks = EXCLUDED.max_concurrent_tasks,
        updated_at = now()
  RETURNING id INTO planner_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Bug Fixer',
    'Codex agent for root-cause debugging and small verified fixes.',
    NULL,
    'local',
    '{}'::jsonb,
    codex_runtime_id,
    'private',
    4,
    owner_user_id,
    'Debug systematically. Reproduce the symptom, trace backward to the root cause, fix the cause at the right layer, and verify with the smallest relevant test or command before reporting completion.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        description = EXCLUDED.description,
        instructions = EXCLUDED.instructions,
        max_concurrent_tasks = EXCLUDED.max_concurrent_tasks,
        updated_at = now()
  RETURNING id INTO bugfix_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Frontend Builder',
    'Codex agent for Next.js, Electron renderer, shared views, and UI implementation work.',
    NULL,
    'local',
    '{}'::jsonb,
    codex_runtime_id,
    'private',
    4,
    owner_user_id,
    'Build production-quality frontend changes in apps/web, apps/desktop renderer, packages/views, and packages/ui. Follow existing design tokens, package boundaries, accessibility requirements, and focused verification.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        description = EXCLUDED.description,
        instructions = EXCLUDED.instructions,
        max_concurrent_tasks = EXCLUDED.max_concurrent_tasks,
        updated_at = now()
  RETURNING id INTO frontend_agent_id;

  INSERT INTO agent (
    workspace_id, name, description, avatar_url, runtime_mode,
    runtime_config, runtime_id, visibility, max_concurrent_tasks, owner_id,
    instructions, custom_env, custom_args, mcp_config, model
  ) VALUES (
    ws_id,
    'Documentation Summarizer',
    'Claude Code agent for docs, release notes, summaries, and evidence-bound recovery notes.',
    NULL,
    'local',
    '{}'::jsonb,
    claude_runtime_id,
    'private',
    3,
    owner_user_id,
    'Summarize long repository, issue, and deployment context into concise decisions, action items, open questions, and source-grounded notes. Never invent owners, dates, or historical execution details.',
    '{}'::jsonb,
    '[]'::jsonb,
    NULL,
    NULL
  )
  ON CONFLICT (workspace_id, name) DO UPDATE
    SET runtime_id = EXCLUDED.runtime_id,
        description = EXCLUDED.description,
        instructions = EXCLUDED.instructions,
        max_concurrent_tasks = EXCLUDED.max_concurrent_tasks,
        updated_at = now()
  RETURNING id INTO summarizer_agent_id;

  INSERT INTO agent_skill (agent_id, skill_id)
  VALUES
    (claude_agent_id, guidance_skill_id),
    (claude_agent_id, workflow_skill_id),
    (claude_agent_id, role_routing_skill_id),
    (codex_agent_id, guidance_skill_id),
    (codex_agent_id, workflow_skill_id),
    (codex_agent_id, role_routing_skill_id),
    (reviewer_agent_id, guidance_skill_id),
    (reviewer_agent_id, workflow_skill_id),
    (reviewer_agent_id, role_routing_skill_id),
    (planner_agent_id, guidance_skill_id),
    (planner_agent_id, workflow_skill_id),
    (planner_agent_id, role_routing_skill_id),
    (bugfix_agent_id, guidance_skill_id),
    (bugfix_agent_id, workflow_skill_id),
    (bugfix_agent_id, role_routing_skill_id),
    (frontend_agent_id, guidance_skill_id),
    (frontend_agent_id, workflow_skill_id),
    (frontend_agent_id, role_routing_skill_id),
    (summarizer_agent_id, guidance_skill_id),
    (summarizer_agent_id, workflow_skill_id),
    (summarizer_agent_id, role_routing_skill_id)
  ON CONFLICT DO NOTHING;

  UPDATE agent a
  SET status = 'idle',
      updated_at = now()
  FROM agent_runtime ar
  WHERE a.runtime_id = ar.id
    AND a.workspace_id = ws_id
    AND a.name IN (
      'Claude Code Builder',
      'Codex Builder',
      'Code Reviewer',
      'Product Planner',
      'Bug Fixer',
      'Frontend Builder',
      'Documentation Summarizer'
    )
    AND a.status = 'offline'
    AND ar.status = 'online'
    AND NOT EXISTS (
      SELECT 1
      FROM agent_task_queue t
      WHERE t.agent_id = a.id
        AND t.status IN ('queued', 'dispatched', 'running')
    );

  SELECT id INTO build_project_id
  FROM project
  WHERE workspace_id = ws_id AND title = '构建当前项目'
  ORDER BY created_at ASC
  LIMIT 1;

  IF build_project_id IS NULL THEN
    INSERT INTO project (
      workspace_id, title, description, icon, status,
      lead_type, lead_id, priority
    ) VALUES (
      ws_id,
      '构建当前项目',
      '从当前仓库、提交历史和本地生产部署恢复出的项目建设任务。不包含伪造的历史 agent run。',
      'Code2',
      'in_progress',
      'agent',
      claude_agent_id,
      'high'
    )
    RETURNING id INTO build_project_id;
  ELSE
    UPDATE project
    SET
      description = COALESCE(NULLIF(description, ''), '从当前仓库、提交历史和本地生产部署恢复出的项目建设任务。不包含伪造的历史 agent run。'),
      status = CASE WHEN status = 'planned' THEN 'in_progress' ELSE status END,
      priority = CASE WHEN priority = 'none' THEN 'high' ELSE priority END,
      lead_type = COALESCE(NULLIF(lead_type, ''), 'agent'),
      lead_id = COALESCE(lead_id, claude_agent_id),
      updated_at = now()
    WHERE id = build_project_id;
  END IF;

  INSERT INTO project_resource (
    project_id, workspace_id, resource_type, resource_ref, label, position, created_by
  ) VALUES (
    build_project_id,
    ws_id,
    'github_repo',
    repo_ref,
    'monica repository',
    0,
    owner_user_id
  )
  ON CONFLICT (project_id, resource_type, resource_ref) DO UPDATE
    SET label = EXCLUDED.label,
        position = EXCLUDED.position;

  IF NOT EXISTS (
    SELECT 1
    FROM squad
    WHERE workspace_id = ws_id AND name = 'Monica Build Squad' AND archived_at IS NULL
  ) THEN
    INSERT INTO squad (
      workspace_id, name, description, leader_id, creator_id, instructions
    ) VALUES (
      ws_id,
      'Monica Build Squad',
      'Recovered working squad for building the current project with Claude Code, Codex, and review coverage.',
      claude_agent_id,
      owner_user_id,
      'Use the project resource repo as the source of truth. Claude Code Builder and Codex Builder are the only builder agents. Product Planner shapes work, Bug Fixer handles regressions, Frontend Builder owns UI work, Documentation Summarizer captures context, and Code Reviewer reviews risk before completion.'
    );
  END IF;

  UPDATE squad
  SET instructions = 'Use the project resource repo as the source of truth. Claude Code Builder and Codex Builder are the only builder agents. Product Planner shapes work, Bug Fixer handles regressions, Frontend Builder owns UI work, Documentation Summarizer captures context, and Code Reviewer reviews risk before completion.',
      updated_at = now()
  WHERE workspace_id = ws_id
    AND name = 'Monica Build Squad'
    AND archived_at IS NULL;

  INSERT INTO squad_member (squad_id, member_type, member_id, role)
  SELECT s.id, v.member_type, v.member_id, v.role
  FROM squad s
  CROSS JOIN (
    VALUES
      ('agent', claude_agent_id, 'implementation lead'),
      ('agent', codex_agent_id, 'implementation support'),
      ('agent', reviewer_agent_id, 'reviewer'),
      ('agent', planner_agent_id, 'planner'),
      ('agent', bugfix_agent_id, 'debugging'),
      ('agent', frontend_agent_id, 'frontend'),
      ('agent', summarizer_agent_id, 'documentation')
  ) AS v(member_type, member_id, role)
  WHERE s.workspace_id = ws_id
    AND s.name = 'Monica Build Squad'
    AND s.archived_at IS NULL
  ON CONFLICT (squad_id, member_type, member_id) DO UPDATE
    SET role = EXCLUDED.role;

  IF NOT EXISTS (
    SELECT 1 FROM issue
    WHERE workspace_id = ws_id
      AND project_id = build_project_id
      AND title = '恢复项目上下文与仓库资源'
      AND status NOT IN ('done', 'cancelled')
  ) THEN
    UPDATE workspace
    SET issue_counter = issue_counter + 1
    WHERE id = ws_id
    RETURNING issue_counter INTO next_number;

    INSERT INTO issue (
      workspace_id, title, description, status, priority,
      assignee_type, assignee_id, creator_type, creator_id,
      position, number, project_id, acceptance_criteria, context_refs
    ) VALUES (
      ws_id,
      '恢复项目上下文与仓库资源',
      '把当前 monica 仓库地址、workspace context、project resource 和恢复边界补进生产库，确保 agent 能从项目上下文定位代码库。',
      'todo',
      'high',
      'agent',
      claude_agent_id,
      'member',
      owner_user_id,
      0,
      next_number,
      build_project_id,
      '["workspace repos includes https://github.com/xkcyy/monica","project has a github_repo resource for the monica repository","no historical agent_task_queue rows are fabricated"]'::jsonb,
      jsonb_build_array(jsonb_build_object('type','github_repo','url','https://github.com/xkcyy/monica'))
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM issue
    WHERE workspace_id = ws_id
      AND project_id = build_project_id
      AND title = '建立 Claude Code / Codex 开发智能体'
      AND status NOT IN ('done', 'cancelled')
  ) THEN
    UPDATE workspace
    SET issue_counter = issue_counter + 1
    WHERE id = ws_id
    RETURNING issue_counter INTO next_number;

    INSERT INTO issue (
      workspace_id, title, description, status, priority,
      assignee_type, assignee_id, creator_type, creator_id,
      position, number, project_id, acceptance_criteria, context_refs
    ) VALUES (
      ws_id,
      '建立 Claude Code / Codex 开发智能体',
      '用当前在线 runtime 创建 Claude Code Builder、Codex Builder 和 Code Reviewer，并关联恢复出的代码库规范与 agent 开发流程技能。',
      'todo',
      'high',
      'agent',
      codex_agent_id,
      'member',
      owner_user_id,
      0,
      next_number,
      build_project_id,
      '["Claude Code Builder exists and is bound to the claude runtime","Codex Builder exists and is bound to the codex runtime","Code Reviewer exists and has review-focused instructions","all three agents have the recovered skills attached"]'::jsonb,
      jsonb_build_array(
        jsonb_build_object('type','agent','name','Claude Code Builder'),
        jsonb_build_object('type','agent','name','Codex Builder'),
        jsonb_build_object('type','agent','name','Code Reviewer')
      )
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM issue
    WHERE workspace_id = ws_id
      AND project_id = build_project_id
      AND title = '整理真实开发过程证据边界'
      AND status NOT IN ('done', 'cancelled')
  ) THEN
    UPDATE workspace
    SET issue_counter = issue_counter + 1
    WHERE id = ws_id
    RETURNING issue_counter INTO next_number;

    INSERT INTO issue (
      workspace_id, title, description, status, priority,
      assignee_type, assignee_id, creator_type, creator_id,
      position, number, project_id, acceptance_criteria, context_refs
    ) VALUES (
      ws_id,
      '整理真实开发过程证据边界',
      '基于 git 历史和已提交 runtime 代码记录可确认的 Agent 使用方式，同时明确仓库外数据（task records、run messages、daemon logs、local sessions）无法从 git 还原。',
      'backlog',
      'medium',
      'agent',
      reviewer_agent_id,
      'member',
      owner_user_id,
      0,
      next_number,
      build_project_id,
      '["document what was inferred from committed code and git history","separate workflow configuration from historical execution evidence","do not insert fabricated task/run/message/usage history"]'::jsonb,
      jsonb_build_array(
        jsonb_build_object('type','git_remote','url','https://github.com/xkcyy/monica'),
        jsonb_build_object('type','note','text','Historical agent runs require external Multica DB/session/log exports.')
      )
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM issue
    WHERE workspace_id = ws_id
      AND project_id = build_project_id
      AND title = '补充 Claude/Codex 角色型智能体配置'
      AND status NOT IN ('done', 'cancelled')
  ) THEN
    UPDATE workspace
    SET issue_counter = issue_counter + 1
    WHERE id = ws_id
    RETURNING issue_counter INTO next_number;

    INSERT INTO issue (
      workspace_id, title, description, status, priority,
      assignee_type, assignee_id, creator_type, creator_id,
      position, number, project_id, acceptance_criteria, context_refs
    ) VALUES (
      ws_id,
      '补充 Claude/Codex 角色型智能体配置',
      '在不新增 Gemini/OpenClaw/OpenCode agent 的前提下，基于提交历史、内置 template 和当前 runtime，为 Claude Code 与 Codex 补充规划、调试、前端、文档总结等角色型 agent。',
      'todo',
      'medium',
      'agent',
      planner_agent_id,
      'member',
      owner_user_id,
      0,
      next_number,
      build_project_id,
      '["only claude and codex runtimes are used by builder and role agents","no gemini/openclaw/opencode agents are created","role agents are attached to codebase/workflow/routing skills","no historical task/run/message rows are fabricated"]'::jsonb,
      jsonb_build_array(
        jsonb_build_object('type','agent','name','Product Planner'),
        jsonb_build_object('type','agent','name','Bug Fixer'),
        jsonb_build_object('type','agent','name','Frontend Builder'),
        jsonb_build_object('type','agent','name','Documentation Summarizer')
      )
    );
  END IF;
END $$;

COMMIT;
