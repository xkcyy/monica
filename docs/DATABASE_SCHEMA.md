# 数据库设计说明

> 基于 `server/migrations/001–090` 的完整迁移分析，截至 2026-05-20。
> 当前共 **45 张活跃表**（含 2 张已删除），90 个迁移文件。
> 数据库为 PostgreSQL 17（pgvector 镜像），使用 sqlc 生成 Go 查询代码。

---

## 目录

- [1. 全局约定](#1-全局约定)
- [2. ER 关系总览](#2-er-关系总览)
- [3. 账号与身份](#3-账号与身份)
- [4. 工作区与团队](#4-工作区与团队)
- [5. 工作管理](#5-工作管理)
- [6. 项目管理](#6-项目管理)
- [7. Agent 系统](#7-agent-系统)
- [8. Skills](#8-skills)
- [9. Chat](#9-chat)
- [10. Squads](#10-squads)
- [11. Autopilots](#11-autopilots)
- [12. 任务执行明细](#12-任务执行明细)
- [13. 用量汇总](#13-用量汇总)
- [14. 通知与收件箱](#14-通知与收件箱)
- [15. Daemon](#15-daemon)
- [16. 附件](#16-附件)
- [17. GitHub 集成](#17-github-集成)
- [18. 其他表](#18-其他表)
- [19. 已删除的表](#19-已删除的表)
- [20. 索引清单](#20-索引清单)

---

## 1. 全局约定

| 约定 | 说明 |
|---|---|
| **主键** | 所有表使用 `UUID` 主键，`DEFAULT gen_random_uuid()` |
| **时间列** | 统一使用 `TIMESTAMPTZ`，默认 `now()`，UTC 存储 |
| **多态外键** | `*_type` + `*_id` 组合表示多态引用（如 `assignee_type`/`assignee_id` 指向 member 或 agent） |
| **枚举约束** | 使用 `CHECK (col IN (...))` 而非 PostgreSQL ENUM 类型，方便扩展 |
| **JSONB** | 用于半结构化数据（settings、config、metadata、details 等） |
| **级联删除** | 工作区级资源统一 `ON DELETE CASCADE`；跨域引用用 `ON DELETE SET NULL` |
| **多租户** | 所有业务表包含 `workspace_id`，查询强制过滤 |
| **排序位置** | 使用 `FLOAT` 类型的 `position` 列支持拖拽排序 |
| **软删除** | agent/squad 使用 `archived_at` 时间戳标记归档状态 |

---

## 2. ER 关系总览

```
user ─┬─< member >─ workspace
      ├─< personal_access_token
      ├─< feedback
      └─< notification_preference

workspace ─┬─< member
           ├─< agent ────< agent_skill >──── skill ──< skill_file
           ├─< agent_runtime
           ├─< issue ─┬─< issue_to_label >── issue_label
           │          ├─< issue_dependency
           │          ├─< issue_subscriber
           │          ├─< issue_reaction
           │          ├─< comment ───< comment_reaction
           │          ├─< issue_pull_request >── github_pull_request
           │          └─< agent_task_queue ─┬─< task_message
           │                                 └─< task_usage
           ├─< project ──< project_resource
           ├─< autopilot ─┬─< autopilot_trigger
           │              └─< autopilot_run
           ├─< chat_session ──< chat_message
           ├─< squad ──< squad_member
           ├─< inbox_item
           ├─< attachment
           ├─< activity_log
           ├─< pinned_item
           ├─< daemon_token
           ├─< github_installation
           ├─< task_usage_daily
           ├─< task_usage_dashboard_daily
           └── task_usage_rollup_state (singleton)
```

---

## 3. 账号与身份

### 3.1 `user`（用户）

用户是系统的核心身份实体。支持邮箱验证码和 Google OAuth 两种登录方式。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | 001 | |
| `name` | TEXT | NOT NULL | 001 | 用户显示名 |
| `email` | TEXT | UNIQUE, NOT NULL | 001 | 登录邮箱，全局唯一 |
| `avatar_url` | TEXT | | 001 | 头像地址 |
| `language` | TEXT | | 060 | 用户语言偏好 |
| `onboarded_at` | TIMESTAMPTZ | | 050 | 完成引导的时间，NULL 表示未完成 |
| `onboarding_state` | JSONB | | 051 | 引导流程状态持久化 |
| `cloud_waitlist` | BOOLEAN | | 052 | 是否加入云运行时等待列表 |
| `starter_content_state` | TEXT | | 054 | 初始内容导入/跳过状态 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**设计决策：** `onboarded_at` 用时间戳而非布尔值，既表示完成状态又能记录完成时间。`onboarding_state` 使用 JSONB 存储多步骤引导进度，便于扩展新步骤而不需要加列。

---

### 3.2 `verification_code`（验证码）

邮箱登录使用的一次性验证码。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 009 | |
| `email` | TEXT | NOT NULL | 009 | 目标邮箱 |
| `code` | TEXT | NOT NULL | 009 | 6 位数字验证码 |
| `attempts` | INT | NOT NULL DEFAULT 0 | 010 | 验证尝试次数 |
| `expires_at` | TIMESTAMPTZ | NOT NULL | 009 | 过期时间 |
| `used` | BOOLEAN | NOT NULL DEFAULT FALSE | 009 | 是否已使用 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 009 | |

**索引：** `idx_verification_code_email` ON (email, used, expires_at)

---

### 3.3 `personal_access_token`（个人访问令牌）

供 CLI 和自动化使用的长期令牌。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 011 | |
| `user_id` | UUID | FK → user(id) ON DELETE CASCADE | 011 | 令牌所有者 |
| `name` | TEXT | NOT NULL | 011 | 令牌名称（如 "CI Pipeline"） |
| `token_hash` | TEXT | NOT NULL, UNIQUE | 011 | SHA-256 哈希，原始令牌不存储 |
| `token_prefix` | TEXT | NOT NULL | 011 | 前 8 位，用于 UI 展示识别 |
| `expires_at` | TIMESTAMPTZ | | 011 | 过期时间，NULL 表示永不过期 |
| `last_used_at` | TIMESTAMPTZ | | 011 | 最近使用时间 |
| `revoked` | BOOLEAN | NOT NULL DEFAULT FALSE | 011 | 是否已撤销 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 011 | |

**索引：**
- `idx_pat_user` ON (user_id, revoked)
- `idx_pat_token_hash` ON (token_hash) UNIQUE

**设计决策：** 只存储哈希和前缀，原始令牌仅在创建时返回一次。

---

## 4. 工作区与团队

### 4.1 `workspace`（工作区）

工作区是所有业务资源的隔离边界和多租户分区键。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `name` | TEXT | NOT NULL | 001 | 工作区名称 |
| `slug` | TEXT | UNIQUE, NOT NULL | 001 | URL 路径标识（如 `my-team`） |
| `description` | TEXT | | 001 | 工作区描述 |
| `settings` | JSONB | NOT NULL DEFAULT '{}' | 001 | 工作区级设置 |
| `context` | TEXT | | 006 | 注入给该工作区 agent 的统一上下文指令 |
| `issue_prefix` | TEXT | NOT NULL DEFAULT '' | 020 | Issue 编号前缀（如 `MUL`） |
| `issue_counter` | INT | NOT NULL DEFAULT 0 | 020 | 当前 Issue 编号计数器 |
| `repos` | JSONB | NOT NULL DEFAULT '[]' | 014 | 仓库白名单与上下文配置 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**设计决策：**
- `slug` 是 URL 路由的核心，有保留词保护（见 `reserved_slugs.json`）
- `issue_prefix` + `issue_counter` 实现人类可读编号（如 `MUL-123`），通过事务原子递增
- `repos` 存储仓库白名单，控制 agent 可访问的代码仓库范围

---

### 4.2 `member`（成员）

用户与工作区的多对多关联，携带角色信息。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `user_id` | UUID | FK → user(id) ON DELETE CASCADE | 001 | |
| `role` | TEXT | NOT NULL | 001 | CHECK IN ('owner', 'admin', 'member') |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| | | UNIQUE(workspace_id, user_id) | | |

**角色权限：**
- `owner`：工作区最高权限，不可移除自己，可执行所有操作
- `admin`：可管理成员、agent、设置
- `member`：标准操作权限

**索引：** `idx_member_workspace` ON (workspace_id)

---

### 4.3 `workspace_invitation`（工作区邀请）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 041 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 041 | |
| `inviter_id` | UUID | FK → user(id) | 041 | 发起邀请的人 |
| `invitee_email` | TEXT | NOT NULL | 041 | 被邀请者邮箱 |
| `invitee_user_id` | UUID | FK → user(id) | 041 | 已注册用户的 ID（可空） |
| `role` | TEXT | CHECK IN ('admin', 'member') | 041 | 邀请角色 |
| `status` | TEXT | DEFAULT 'pending' | 041 | CHECK IN ('pending', 'accepted', 'declined', 'expired') |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 041 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 041 | |
| `expires_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() + 7 days | 041 | 7 天后自动过期 |

**索引：**
- `idx_invitation_unique_pending` UNIQUE ON (workspace_id, invitee_email) WHERE status = 'pending'
- `idx_invitation_invitee_email` ON (invitee_email) WHERE status = 'pending'
- `idx_invitation_invitee_user` ON (invitee_user_id) WHERE status = 'pending'

**设计决策：** 部分唯一索引确保同一工作区+邮箱同一时间只有一个待处理邀请。

---

### 4.4 `notification_preference`（通知偏好）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 064 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 064 | |
| `user_id` | UUID | FK → user(id) ON DELETE CASCADE | 064 | |
| `preferences` | JSONB | NOT NULL DEFAULT '{}' | 064 | 按事件类型配置通知开关 |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 064 | |
| | | UNIQUE(workspace_id, user_id) | | |

---

## 5. 工作管理

### 5.1 `issue`（任务/议题）

核心任务单元。人和 agent 都可以是创建者或负责人。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `number` | INT | NOT NULL DEFAULT 0 | 020 | 工作区内递增编号，如 123 |
| `title` | TEXT | NOT NULL | 001 | |
| `description` | TEXT | | 001 | 富文本描述 |
| `status` | TEXT | DEFAULT 'backlog' | 001 | CHECK IN ('backlog','todo','in_progress','in_review','done','blocked','cancelled') |
| `priority` | TEXT | DEFAULT 'none' | 001 | CHECK IN ('urgent','high','medium','low','none') |
| `assignee_type` | TEXT | CHECK IN ('member','agent','squad') | 001, 084 | 多态负责人类型 |
| `assignee_id` | UUID | | 001 | 多态负责人 ID |
| `creator_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 001 | 创建者类型 |
| `creator_id` | UUID | NOT NULL | 001 | 创建者 ID |
| `parent_issue_id` | UUID | FK → issue(id) ON DELETE SET NULL | 001 | 父 issue，用于子任务 |
| `project_id` | UUID | FK → project(id) ON DELETE SET NULL | 034 | 所属项目 |
| `acceptance_criteria` | JSONB | NOT NULL DEFAULT '[]' | 001 | 验收标准列表 |
| `context_refs` | JSONB | NOT NULL DEFAULT '[]' | 001 | 上下文引用 |
| `position` | FLOAT | NOT NULL DEFAULT 0 | 001 | 拖拽排序位置 |
| `due_date` | TIMESTAMPTZ | | 001 | 截止日期 |
| `origin_type` | TEXT | CHECK IN ('autopilot','quick_create') | 042, 060 | 来源类型 |
| `origin_id` | UUID | | 042 | 来源 ID（如 autopilot_run.id） |
| `first_executed_at` | TIMESTAMPTZ | | 050 | 首次被 agent 执行的时间 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**约束：** `uq_issue_workspace_number` UNIQUE (workspace_id, number)

**索引：**
- `idx_issue_workspace` ON (workspace_id)
- `idx_issue_assignee` ON (assignee_type, assignee_id)
- `idx_issue_status` ON (workspace_id, status)
- `idx_issue_parent` ON (parent_issue_id)
- `idx_issue_project` ON (project_id)
- `idx_issue_workspace_number` ON (workspace_id, number)
- `idx_issue_origin` ON (origin_type, origin_id) WHERE origin_type IS NOT NULL
- `idx_issue_search` — 全文搜索索引（GIN，title + description + comment content）

**设计决策：**
- `assignee_type` 扩展为支持 `squad`，是唯一一次 assign 多态类型的扩展
- `number` 与 `workspace.issue_counter` 在同一事务中原子递增，生成人类可读编号（如 `MUL-123`）
- `origin_type` 记录自动化来源，方便按来源过滤和追踪

---

### 5.2 `comment`（评论）

Issue 下的评论和系统活动记录，支持嵌套回复。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 025 | 冗余存储，加速工作区级查询 |
| `parent_id` | UUID | FK → comment(id) ON DELETE CASCADE | 017 | 父评论，用于回复线程 |
| `author_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 001 | |
| `author_id` | UUID | NOT NULL | 001 | |
| `content` | TEXT | NOT NULL | 001 | 富文本内容 |
| `type` | TEXT | DEFAULT 'comment' | 001 | CHECK IN ('comment','status_change','progress_update','system') |
| `resolved` | BOOLEAN | NOT NULL DEFAULT FALSE | | 是否已解决 |
| `resolved_by_type` | TEXT | | | |
| `resolved_by_id` | UUID | | | |
| `resolved_at` | TIMESTAMPTZ | | 069 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**索引：**
- `idx_comment_issue` ON (issue_id)
- `idx_timeline_keyset` ON (issue_id, created_at, id) — 用于 keyset 分页

**设计决策：** `type` 字段区分用户评论和系统生成的状态变更记录。`parent_id` 支持评论回复线程，018 迁移添加了级联删除保证回复随父评论一起删除。

---

### 5.3 `issue_label`（标签）

工作区级别的标签定义。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `name` | TEXT | NOT NULL | 001 | 标签名 |
| `color` | TEXT | NOT NULL | 001 | 十六进制颜色值 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 059 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 059 | |

---

### 5.4 `issue_to_label`（Issue-标签关联）

多对多关联表。

| 列名 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | |
| `label_id` | UUID | FK → issue_label(id) ON DELETE CASCADE | |
| | | PK (issue_id, label_id) | 联合主键 |

---

### 5.5 `issue_dependency`（Issue 依赖关系）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | |
| `depends_on_issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | |
| `type` | TEXT | NOT NULL | 001 | CHECK IN ('blocks','blocked_by','related') |

---

### 5.6 `issue_subscriber`（Issue 订阅者）

追踪谁关注某个 issue 的通知。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 015 | |
| `user_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 015 | |
| `user_id` | UUID | NOT NULL | 015 | |
| `reason` | TEXT | NOT NULL | 015 | CHECK IN ('creator','assignee','commenter','mentioned','manual') |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 015 | |
| | | PK (issue_id, user_type, user_id) | | |

**索引：** `idx_issue_subscriber_user` ON (user_type, user_id)

**设计决策：** `reason` 字段记录订阅原因，创建者、负责人、评论者、被提及者自动订阅，也可手动订阅/取消。016 迁移对已有数据做了回填。

---

### 5.7 `issue_reaction`（Issue 表情回应）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 027 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 027 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 027 | |
| `actor_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 027 | |
| `actor_id` | UUID | NOT NULL | 027 | |
| `emoji` | TEXT | NOT NULL | 027 | Emoji 字符 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 027 | |
| | | UNIQUE (issue_id, actor_type, actor_id, emoji) | | |

---

### 5.8 `comment_reaction`（评论表情回应）

与 `issue_reaction` 结构一致，关联到评论。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 026 | |
| `comment_id` | UUID | FK → comment(id) ON DELETE CASCADE | 026 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 026 | |
| `actor_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 026 | |
| `actor_id` | UUID | NOT NULL | 026 | |
| `emoji` | TEXT | NOT NULL | 026 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 026 | |
| | | UNIQUE (comment_id, actor_type, actor_id, emoji) | | |

---

### 5.9 `pinned_item`（置顶项）

用户级别的 issue/project 置顶。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 038 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 038 | |
| `user_id` | UUID | FK → user(id) ON DELETE CASCADE | 038 | |
| `item_type` | TEXT | NOT NULL CHECK IN ('issue','project') | 038 | |
| `item_id` | UUID | NOT NULL | 038 | |
| `position` | FLOAT | NOT NULL DEFAULT 0 | 038 | 排序 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 038 | |
| | | UNIQUE (workspace_id, user_id, item_type, item_id) | | |

**索引：** `idx_pinned_item_user_ws` ON (workspace_id, user_id, position)

---

## 6. 项目管理

### 6.1 `project`（项目）

比 issue 更高一级的聚合单元。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 034 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 034 | |
| `title` | TEXT | NOT NULL | 034 | |
| `description` | TEXT | | 034 | |
| `icon` | TEXT | | 034 | 项目图标 |
| `status` | TEXT | DEFAULT 'planned' | 034 | CHECK IN ('planned','in_progress','paused','completed','cancelled') |
| `priority` | TEXT | | 035 | CHECK IN ('urgent','high','medium','low','none') |
| `lead_type` | TEXT | CHECK IN ('member','agent') | 034 | 负责人类型 |
| `lead_id` | UUID | | 034 | 负责人 ID |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 034 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 034 | |

**索引：**
- `idx_project_workspace` ON (workspace_id)
- `idx_project_search` — 全文搜索索引

---

### 6.2 `project_resource`（项目资源）

项目关联的外部资源（链接、文档等）。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 065 | |
| `project_id` | UUID | FK → project(id) ON DELETE CASCADE | 065 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 065 | |
| `resource_type` | TEXT | NOT NULL | 065 | 资源类型标识 |
| `resource_ref` | JSONB | NOT NULL | 065 | 资源引用（URL、ID 等） |
| `label` | TEXT | | 065 | 显示标签 |
| `position` | INT | NOT NULL DEFAULT 0 | 065 | 排序 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 065 | |
| `created_by` | UUID | | 065 | 创建者 |
| | | UNIQUE (project_id, resource_type, resource_ref) | | |

**索引：**
- `idx_project_resource_project` ON (project_id, position)
- `idx_project_resource_workspace` ON (workspace_id)

---

## 7. Agent 系统

### 7.1 `agent`（AI 工作者）

Agent 是系统中的一等公民，可以像人一样被分配任务、创建 issue、发表评论。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `runtime_id` | UUID | | 004 | 绑定的运行时 |
| `name` | TEXT | NOT NULL | 001 | UNIQUE(workspace_id, name) (046) |
| `description` | TEXT | NOT NULL DEFAULT '' | | LENGTH <= 500 (060) |
| `avatar_url` | TEXT | | 001 | |
| `runtime_mode` | TEXT | NOT NULL | 001 | CHECK IN ('local','cloud') |
| `runtime_config` | JSONB | NOT NULL DEFAULT '{}' | 001 | 运行时配置（旧字段，保留兼容） |
| `visibility` | TEXT | DEFAULT 'private' | 030 | CHECK IN ('workspace','private') |
| `status` | TEXT | DEFAULT 'offline' | 001 | CHECK IN ('idle','working','blocked','error','offline') |
| `max_concurrent_tasks` | INT | NOT NULL DEFAULT 1 | 023 | 最大并发任务数 |
| `instructions` | TEXT | | 021 | 系统指令 / prompt |
| `model` | TEXT | | 050 | 使用的 LLM 模型 |
| `custom_env` | JSONB | NOT NULL DEFAULT '{}' | 040 | 注入给 CLI 子进程的环境变量 |
| `custom_args` | TEXT | | 041 | 注入给 CLI 的额外参数 |
| `mcp_config` | JSONB | NOT NULL DEFAULT '{}' | 046 | 外部工具/服务 MCP 配置 |
| `owner_id` | UUID | FK → user(id) | 001 | 创建者（private 可见性的控制者） |
| `archived_at` | TIMESTAMPTZ | | 031 | 软删除/归档时间 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**索引：** `idx_agent_workspace` ON (workspace_id)

**设计决策：**
- 046 迁移添加了 `UNIQUE(workspace_id, name)` 约束，防止同一工作区内 agent 重名
- 030 迁移将默认可见性从 `workspace` 改为 `private`，遵循最小权限原则
- `archived_at` 实现软删除，归档后的 agent 不再出现在列表中但保留历史数据

---

### 7.2 `agent_runtime`（运行时）

Agent 执行任务的实际环境。Daemon 在本机注册后成为一个 runtime。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 004 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 004 | |
| `daemon_id` | TEXT | | 004 | Daemon 标识 |
| `daemon_uuid` | UUID | | 048 | Daemon UUID（持久身份） |
| `name` | TEXT | NOT NULL | 004 | 运行时名称 |
| `runtime_mode` | TEXT | NOT NULL | 004 | CHECK IN ('local','cloud') |
| `provider` | TEXT | NOT NULL | 004 | CLI 提供者（如 `claude_code`） |
| `status` | TEXT | DEFAULT 'offline' | 004 | CHECK IN ('online','offline') |
| `device_info` | TEXT | NOT NULL DEFAULT '' | 004 | 设备信息 |
| `metadata` | JSONB | NOT NULL DEFAULT '{}' | 004 | 运行时元数据 |
| `owner_id` | UUID | | 032 | 运行时所有者 |
| `timezone` | TEXT | | 081 | 运行时时区 |
| `visibility` | TEXT | DEFAULT 'workspace' | 083 | CHECK IN ('workspace','private') |
| `custom_pricing` | JSONB | NOT NULL DEFAULT '[]' | | 自定义模型定价 |
| `last_seen_at` | TIMESTAMPTZ | | 004 | 最后心跳时间 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 004 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 004 | |
| | | UNIQUE (workspace_id, daemon_id, provider) | | |

**索引：** `idx_agent_runtime_workspace` ON (workspace_id)

**设计决策：** 004 迁移从 agent 表中拆分出 runtime，实现多 agent 共享同一 runtime 的架构。032 迁移添加 `owner_id` 实现运行时的可见性控制。

---

### 7.3 `agent_task_queue`（任务队列）

Agent 执行任务的核心队列。支持 issue 任务、chat 任务和 autopilot 任务。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `agent_id` | UUID | FK → agent(id) ON DELETE CASCADE | 001 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | nullable (033) |
| `chat_session_id` | UUID | FK → chat_session(id) ON DELETE SET NULL | 033 | |
| `autopilot_run_id` | UUID | FK → autopilot_run(id) ON DELETE SET NULL | 042 | |
| `status` | TEXT | DEFAULT 'queued' | 001 | CHECK IN ('queued','dispatched','running','completed','failed','cancelled') |
| `priority` | INT | NOT NULL DEFAULT 0 | 001 | |
| `trigger_comment_id` | UUID | | 028 | 触发任务的评论 ID |
| `trigger_summary` | TEXT | | 061 | 触发摘要 |
| `session_id` | TEXT | | 020 | Claude Code session ID，支持 resume |
| `work_dir` | TEXT | | 020 | 工作目录 |
| `is_leader_task` | BOOLEAN | NOT NULL DEFAULT FALSE | 090 | 是否为 squad leader 角色 |
| `attempt` | INT | NOT NULL DEFAULT 1 | 055 | 当前尝试次数 |
| `max_attempts` | INT | NOT NULL DEFAULT 2 | 055 | 最大尝试次数 |
| `parent_task_id` | UUID | FK → agent_task_queue(id) ON DELETE SET NULL | 055 | 重试链的父任务 |
| `failure_reason` | TEXT | | 055 | 失败原因分类 |
| `last_heartbeat_at` | TIMESTAMPTZ | | 055 | 任务级心跳 |
| `dispatched_at` | TIMESTAMPTZ | | 001 | |
| `started_at` | TIMESTAMPTZ | | 001 | |
| `completed_at` | TIMESTAMPTZ | | 001 | |
| `result` | JSONB | | 001 | |
| `error` | TEXT | | 001 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**索引：**
- `idx_agent_task_queue_agent` ON (agent_id, status)
- `idx_agent_task_queue_parent` ON (parent_task_id)
- `idx_agent_task_queue_issue_id` ON (issue_id) (035)
- `idx_task_queue_claim_candidate` ON (status, priority DESC, created_at) WHERE status = 'queued' (067)
- `idx_agent_task_queue_queued` ON (agent_id, status, created_at) (080)

**生命周期：** `queued` → `dispatched` → `running` → `completed`/`failed`/`cancelled`

**设计决策：**
- 033 迁移将 `issue_id` 改为 nullable，因为 chat 任务不需要关联 issue
- 055 迁移添加重试/租约机制：`attempt`、`max_attempts`、`parent_task_id` 形成重试链
- `session_id` + `work_dir` 支持 Claude Code session 恢复，同一 (agent, issue) 对可跨任务复用 session

---

## 8. Skills

### 8.1 `skill`（技能）

可复用的知识包，可导入并挂载到 agent。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 008 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 008 | |
| `name` | TEXT | NOT NULL | 008 | UNIQUE(workspace_id, name) |
| `description` | TEXT | NOT NULL DEFAULT '' | 008 | |
| `content` | TEXT | NOT NULL DEFAULT '' | 008 | 技能正文 |
| `config` | JSONB | NOT NULL DEFAULT '{}' | 008 | 技能配置 |
| `created_by` | UUID | FK → user(id) | 008 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 008 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 008 | |

**索引：** `idx_skill_workspace` ON (workspace_id)

---

### 8.2 `skill_file`（技能文件）

技能关联的文件内容，构成文件树。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 008 | |
| `skill_id` | UUID | FK → skill(id) ON DELETE CASCADE | 008 | |
| `path` | TEXT | NOT NULL | 008 | 文件路径 |
| `content` | TEXT | NOT NULL | 008 | 文件内容 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 008 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 008 | |
| | | UNIQUE(skill_id, path) | | |

**索引：** `idx_skill_file_skill` ON (skill_id)

---

### 8.3 `agent_skill`（Agent-技能关联）

多对多关联表，记录 agent 挂载了哪些技能。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `agent_id` | UUID | FK → agent(id) ON DELETE CASCADE | 008 | |
| `skill_id` | UUID | FK → skill(id) ON DELETE CASCADE | 008 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 008 | |
| | | PK (agent_id, skill_id) | | |

**索引：**
- `idx_agent_skill_skill` ON (skill_id)
- `idx_agent_skill_agent` ON (agent_id)

---

## 9. Chat

### 9.1 `chat_session`（聊天会话）

用户与 agent 之间的持久化对话。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 033 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 033 | |
| `agent_id` | UUID | FK → agent(id) ON DELETE CASCADE | 033 | |
| `creator_id` | UUID | FK → user(id) ON DELETE CASCADE | 033 | |
| `title` | TEXT | NOT NULL DEFAULT '' | 033 | |
| `session_id` | TEXT | | 033 | CLI session ID |
| `work_dir` | TEXT | | 033 | 工作目录 |
| `runtime_id` | UUID | | 060 | 绑定的运行时 |
| `status` | TEXT | DEFAULT 'active' | 033 | CHECK IN ('active','archived') |
| `unread_since` | TIMESTAMPTZ | | 040 | 未读消息起点 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 033 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 033 | |

**索引：**
- `idx_chat_session_workspace` ON (workspace_id)
- `idx_chat_session_creator` ON (creator_id, workspace_id)

---

### 9.2 `chat_message`（聊天消息）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 033 | |
| `chat_session_id` | UUID | FK → chat_session(id) ON DELETE CASCADE | 033 | |
| `role` | TEXT | NOT NULL CHECK IN ('user','assistant') | 033 | |
| `content` | TEXT | NOT NULL | 033 | |
| `task_id` | UUID | | 033 | 关联的 agent 任务 |
| `failure_reason` | TEXT | | 062 | 发送失败原因 |
| `elapsed_ms` | BIGINT | | 063 | 响应耗时（毫秒） |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 033 | |

**索引：** `idx_chat_message_session` ON (chat_session_id, created_at)

---

## 10. Squads

### 10.1 `squad`（小队）

多个 agent/成员组成的协作单元，由 leader agent 负责任务分配。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 084 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 084 | |
| `name` | TEXT | NOT NULL | 084 | |
| `avatar_url` | TEXT | | 086 | |
| `description` | TEXT | NOT NULL DEFAULT '' | 084 | |
| `instructions` | TEXT | | 088 | 小队级指令 |
| `leader_id` | UUID | FK → agent(id) ON DELETE RESTRICT | 084 | Leader agent |
| `creator_id` | UUID | NOT NULL | 084 | |
| `archived_at` | TIMESTAMPTZ | | 085 | 归档时间 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 084 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 084 | |

**索引：** `idx_squad_workspace` ON (workspace_id)

**设计决策：** `leader_id` 使用 `ON DELETE RESTRICT` 防止误删正在领导的 agent。087 迁移移除了 name 的 UNIQUE 约束以支持更灵活的命名。

---

### 10.2 `squad_member`（小队成员）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 084 | |
| `squad_id` | UUID | FK → squad(id) ON DELETE CASCADE | 084 | |
| `member_type` | TEXT | NOT NULL CHECK IN ('agent','member') | 084 | |
| `member_id` | UUID | NOT NULL | 084 | |
| `role` | TEXT | NOT NULL DEFAULT '' | 084 | 成员角色描述 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 084 | |
| | | UNIQUE(squad_id, member_type, member_id) | | |

**索引：**
- `idx_squad_member_squad` ON (squad_id)
- `idx_squad_member_entity` ON (member_type, member_id)

---

## 11. Autopilots

### 11.1 `autopilot`（自动化规则）

定时或手动触发的自动化规则引擎。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 042 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 042 | |
| `title` | TEXT | NOT NULL | 042 | |
| `description` | TEXT | | 042 | |
| `assignee_id` | UUID | FK → agent(id) ON DELETE CASCADE | 042 | 执行 agent |
| `status` | TEXT | DEFAULT 'active' | 042 | CHECK IN ('active','paused','archived') |
| `execution_mode` | TEXT | DEFAULT 'create_issue' | 042 | CHECK IN ('create_issue','run_only') |
| `issue_title_template` | TEXT | | 042 | 自动创建 issue 的标题模板 |
| `concurrency_policy` | TEXT | DEFAULT 'skip' | 042 | CHECK IN ('skip','queue','replace') |
| `created_by_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 042 | |
| `created_by_id` | UUID | NOT NULL | 042 | |
| `last_run_at` | TIMESTAMPTZ | | 042 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |

**索引：**
- `idx_autopilot_workspace` ON (workspace_id)
- `idx_autopilot_assignee` ON (assignee_id)

**执行模式：**
- `create_issue`：每次运行创建一个 issue 并分配给 agent
- `run_only`：直接运行 agent 不创建 issue

---

### 11.2 `autopilot_trigger`（触发器）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 042 | |
| `autopilot_id` | UUID | FK → autopilot(id) ON DELETE CASCADE | 042 | |
| `kind` | TEXT | NOT NULL | 042 | CHECK IN ('schedule','webhook','api') |
| `enabled` | BOOLEAN | NOT NULL DEFAULT true | 042 | |
| `cron_expression` | TEXT | | 042 | Cron 表达式（kind = schedule 时） |
| `timezone` | TEXT | DEFAULT 'UTC' | 042 | |
| `next_run_at` | TIMESTAMPTZ | | 042 | 下次触发时间 |
| `webhook_token` | TEXT | | 042 | Webhook 验证令牌 |
| `label` | TEXT | | 042 | 触发器标签 |
| `last_fired_at` | TIMESTAMPTZ | | 042 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |

**索引：**
- `idx_autopilot_trigger_autopilot` ON (autopilot_id)
- `idx_autopilot_trigger_next_run` ON (next_run_at) WHERE enabled = true AND kind = 'schedule'

---

### 11.3 `autopilot_run`（运行记录）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 042 | |
| `autopilot_id` | UUID | FK → autopilot(id) ON DELETE CASCADE | 042 | |
| `trigger_id` | UUID | FK → autopilot_trigger(id) ON DELETE SET NULL | 042 | |
| `source` | TEXT | NOT NULL | 042 | CHECK IN ('schedule','manual','webhook','api') |
| `status` | TEXT | DEFAULT 'pending' | 042 | CHECK IN ('pending','issue_created','running','skipped','completed','failed') |
| `issue_id` | UUID | FK → issue(id) ON DELETE SET NULL | 042 | |
| `task_id` | UUID | FK → agent_task_queue(id) ON DELETE SET NULL | 042 | |
| `triggered_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |
| `completed_at` | TIMESTAMPTZ | | 042 | |
| `failure_reason` | TEXT | | 042 | |
| `trigger_payload` | JSONB | | 042 | 触发时的输入参数 |
| `result` | JSONB | | 042 | 运行结果 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 042 | |

**索引：**
- `idx_autopilot_run_autopilot` ON (autopilot_id, created_at DESC)
- `idx_autopilot_run_status` ON (autopilot_id, status) WHERE status IN ('pending','issue_created','running')

---

## 12. 任务执行明细

### 12.1 `task_message`（任务消息流）

Agent 执行任务时的实时消息流，记录工具调用和输出。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 026 | |
| `task_id` | UUID | FK → agent_task_queue(id) ON DELETE CASCADE | 026 | |
| `seq` | INTEGER | NOT NULL | 026 | 序列号，保证消息顺序 |
| `type` | TEXT | NOT NULL | 026 | 消息类型 |
| `tool` | TEXT | | 026 | 工具名称（工具调用时） |
| `content` | TEXT | | 026 | 消息内容 |
| `input` | JSONB | | 026 | 工具输入 |
| `output` | TEXT | | 026 | 工具输出 |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 026 | |

**索引：** `idx_task_message_task_id_seq` ON (task_id, seq)

---

### 12.2 `task_usage`（任务用量）

每次任务执行消耗的 token 统计。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 032 | |
| `task_id` | UUID | FK → agent_task_queue(id) ON DELETE CASCADE | 032 | |
| `provider` | TEXT | NOT NULL DEFAULT '' | 032 | |
| `model` | TEXT | NOT NULL | 032 | |
| `input_tokens` | BIGINT | NOT NULL DEFAULT 0 | 032 | |
| `output_tokens` | BIGINT | NOT NULL DEFAULT 0 | 032 | |
| `cache_read_tokens` | BIGINT | NOT NULL DEFAULT 0 | 032 | |
| `cache_write_tokens` | BIGINT | NOT NULL DEFAULT 0 | 032 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 032 | |
| `updated_at` | TIMESTAMPTZ | | 072 | |
| | | UNIQUE (task_id, provider, model) | | |

**索引：**
- `idx_task_usage_task_id` ON (task_id)
- `idx_task_usage_updated_at` ON (updated_at) (074)
- `idx_task_usage_created_at` ON (created_at) (075)

---

## 13. 用量汇总

### 13.1 `task_usage_daily`（日维汇总）

按 runtime 维度的每日用量聚合。由 rollup 函数定期从 `task_usage` 计算。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `bucket_date` | DATE | NOT NULL | 073 | |
| `workspace_id` | UUID | NOT NULL | 073 | |
| `runtime_id` | UUID | NOT NULL | 073 | |
| `provider` | TEXT | NOT NULL | 073 | |
| `model` | TEXT | NOT NULL | 073 | |
| `input_tokens` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `output_tokens` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `cache_read_tokens` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `cache_write_tokens` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `event_count` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 073 | |
| | | PK (bucket_date, workspace_id, runtime_id, provider, model) | | |

**索引：**
- `idx_task_usage_daily_runtime_date` ON (runtime_id, bucket_date DESC)
- `idx_task_usage_daily_workspace_date` ON (workspace_id, bucket_date DESC)

**设计决策：** 073 迁移引入物化汇总替代直接查询 `task_usage`。rollup 函数使用 REPLACE 语义（幂等），支持安全重放。077 迁移添加了基于触发器的增量失效机制（dirty table），确保 `task_usage` 更新后对应的日维行被标记重算。

---

### 13.2 `task_usage_dashboard_daily`（仪表盘汇总）

按 agent 维度的每日用量聚合，用于仪表盘展示。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `bucket_date` | DATE | NOT NULL | 084 | |
| `workspace_id` | UUID | NOT NULL | 084 | |
| `agent_id` | UUID | NOT NULL | 084 | |
| `project_id` | UUID | | 084 | nullable |
| `model` | TEXT | NOT NULL | 084 | |
| `input_tokens` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `output_tokens` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `cache_read_tokens` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `cache_write_tokens` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `task_count` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `event_count` | BIGINT | NOT NULL DEFAULT 0 | 084 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 084 | |
| | | UNIQUE NULLS NOT DISTINCT (bucket_date, workspace_id, agent_id, project_id, model) | | |

---

### 13.3 `task_usage_rollup_state`（Rollup 状态机）

单行表，追踪 rollup 进度。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | SMALLINT | PK DEFAULT 1 CHECK (id = 1) | 073 | 永远只有一行 |
| `watermark_at` | TIMESTAMPTZ | NOT NULL DEFAULT '1970-01-01' | 073 | 已处理到的时间点 |
| `last_run_started_at` | TIMESTAMPTZ | | 073 | |
| `last_run_finished_at` | TIMESTAMPTZ | | 073 | |
| `last_run_rows` | BIGINT | NOT NULL DEFAULT 0 | 073 | |
| `last_error` | TEXT | | 073 | |

---

### 13.4 `task_usage_daily_dirty`（增量失效标记）

记录需要重算的日维桶。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `bucket_date` | DATE | NOT NULL | 077 | |
| `workspace_id` | UUID | NOT NULL | 077 | |
| `runtime_id` | UUID | NOT NULL | 077 | |
| `provider` | TEXT | NOT NULL | 077 | |
| `model` | TEXT | NOT NULL | 077 | |
| `enqueued_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 077 | |
| | | PK (bucket_date, workspace_id, runtime_id, provider, model) | | |

**索引：** `idx_task_usage_daily_dirty_enqueued_at` ON (enqueued_at)

---

## 14. 通知与收件箱

### 14.1 `inbox_item`（收件箱条目）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `recipient_type` | TEXT | NOT NULL | 001 | CHECK IN ('member','agent') |
| `recipient_id` | UUID | NOT NULL | 001 | |
| `type` | TEXT | NOT NULL | 001 | 事件类型 |
| `severity` | TEXT | DEFAULT 'info' | 001 | CHECK IN ('action_required','attention','info') |
| `actor_type` | TEXT | | 012 | 触发者类型 |
| `actor_id` | UUID | | 012 | 触发者 ID |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | |
| `title` | TEXT | NOT NULL | 001 | |
| `body` | TEXT | | 001 | |
| `details` | JSONB | NOT NULL DEFAULT '{}' | 019 | 附加详情 |
| `read` | BOOLEAN | NOT NULL DEFAULT FALSE | 001 | |
| `archived` | BOOLEAN | NOT NULL DEFAULT FALSE | 001 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**索引：** `idx_inbox_recipient` ON (recipient_type, recipient_id, read)

---

## 15. Daemon

### 15.1 `daemon_token`（守护进程令牌）

Daemon 注册后的身份令牌，替代早期 pairing 方案。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 029 | |
| `token_hash` | TEXT | NOT NULL, UNIQUE | 029 | 令牌哈希 |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 029 | |
| `daemon_id` | TEXT | NOT NULL | 029 | Daemon 标识 |
| `expires_at` | TIMESTAMPTZ | NOT NULL | 029 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 029 | |

**索引：**
- `idx_daemon_token_hash` UNIQUE ON (token_hash)
- `idx_daemon_token_workspace_daemon` ON (workspace_id, daemon_id)

---

## 16. 附件

### 16.1 `attachment`（附件）

统一的文件附件表，支持 issue、评论、chat 多种关联。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 029 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 029 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 029 | nullable |
| `comment_id` | UUID | FK → comment(id) ON DELETE CASCADE | 029 | nullable |
| `chat_session_id` | UUID | | 083 | |
| `chat_message_id` | UUID | | 083 | |
| `uploader_type` | TEXT | NOT NULL CHECK IN ('member','agent') | 029 | |
| `uploader_id` | UUID | NOT NULL | 029 | |
| `filename` | TEXT | NOT NULL | 029 | |
| `url` | TEXT | NOT NULL | 029 | 文件存储地址 |
| `content_type` | TEXT | NOT NULL | 029 | MIME 类型 |
| `size_bytes` | BIGINT | NOT NULL | 029 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 029 | |

**索引：**
- `idx_attachment_issue` ON (issue_id) WHERE issue_id IS NOT NULL
- `idx_attachment_comment` ON (comment_id) WHERE comment_id IS NOT NULL
- `idx_attachment_workspace` ON (workspace_id)

---

## 17. GitHub 集成

### 17.1 `github_installation`（GitHub 安装）

工作区连接的 GitHub App Installation。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 079 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 079 | |
| `installation_id` | BIGINT | NOT NULL, UNIQUE | 079 | GitHub Installation ID |
| `account_login` | TEXT | NOT NULL | 079 | |
| `account_type` | TEXT | DEFAULT 'User' | 079 | CHECK IN ('User','Organization') |
| `account_avatar_url` | TEXT | | 079 | |
| `connected_by_id` | UUID | FK → user(id) ON DELETE SET NULL | 079 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 079 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 079 | |

**索引：** `idx_github_installation_workspace` ON (workspace_id)

---

### 17.2 `github_pull_request`（GitHub PR 镜像）

从 GitHub webhook 同步的 PR 数据。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 079 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 079 | |
| `installation_id` | BIGINT | NOT NULL | 079 | |
| `repo_owner` | TEXT | NOT NULL | 079 | |
| `repo_name` | TEXT | NOT NULL | 079 | |
| `pr_number` | INTEGER | NOT NULL | 079 | |
| `title` | TEXT | NOT NULL | 079 | |
| `state` | TEXT | NOT NULL | 079 | CHECK IN ('open','closed','merged','draft') |
| `html_url` | TEXT | NOT NULL | 079 | |
| `branch` | TEXT | | 079 | |
| `author_login` | TEXT | | 079 | |
| `author_avatar_url` | TEXT | | 079 | |
| `merged_at` | TIMESTAMPTZ | | 079 | |
| `closed_at` | TIMESTAMPTZ | | 079 | |
| `pr_created_at` | TIMESTAMPTZ | NOT NULL | 079 | |
| `pr_updated_at` | TIMESTAMPTZ | NOT NULL | 079 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 079 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 079 | |
| | | UNIQUE (workspace_id, repo_owner, repo_name, pr_number) | | |

**索引：** `idx_github_pull_request_workspace` ON (workspace_id)

---

### 17.3 `issue_pull_request`（Issue-PR 关联）

Issue 与 GitHub PR 的多对多关联。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 079 | |
| `pull_request_id` | UUID | FK → github_pull_request(id) ON DELETE CASCADE | 079 | |
| `linked_by_type` | TEXT | | 079 | |
| `linked_by_id` | UUID | | 079 | |
| `linked_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 079 | |
| | | PK (issue_id, pull_request_id) | | |

**索引：** `idx_issue_pull_request_pr` ON (pull_request_id)

---

## 18. 其他表

### 18.1 `activity_log`（活动日志）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE CASCADE | 001 | |
| `issue_id` | UUID | FK → issue(id) ON DELETE CASCADE | 001 | |
| `actor_type` | TEXT | CHECK IN ('member','agent','system') | 001 | |
| `actor_id` | UUID | | 001 | |
| `action` | TEXT | NOT NULL | 001 | |
| `details` | JSONB | NOT NULL DEFAULT '{}' | 001 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

**索引：** `idx_activity_log_issue` ON (issue_id)

---

### 18.2 `feedback`（用户反馈）

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 057 | |
| `user_id` | UUID | FK → user(id) ON DELETE CASCADE | 057 | |
| `workspace_id` | UUID | FK → workspace(id) ON DELETE SET NULL | 057 | |
| `message` | TEXT | NOT NULL | 057 | |
| `metadata` | JSONB | NOT NULL DEFAULT '{}' | 057 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 057 | |

**索引：** `idx_feedback_user_created` ON (user_id, created_at DESC)

---

### 18.3 `daemon_connection`（Daemon 连接）

记录 daemon 的连接状态。此表保留在 schema 中但已被 `agent_runtime` 取代为主要状态源。

| 列名 | 类型 | 约束 | 迁移 | 说明 |
|---|---|---|---|---|
| `id` | UUID | PK | 001 | |
| `agent_id` | UUID | FK → agent(id) ON DELETE CASCADE | 001 | |
| `daemon_id` | TEXT | NOT NULL | 001 | |
| `status` | TEXT | DEFAULT 'disconnected' | 001 | CHECK IN ('connected','disconnected') |
| `last_heartbeat_at` | TIMESTAMPTZ | | 001 | |
| `runtime_info` | JSONB | NOT NULL DEFAULT '{}' | 001 | |
| `created_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |
| `updated_at` | TIMESTAMPTZ | NOT NULL DEFAULT now() | 001 | |

---

## 19. 已删除的表

| 表名 | 创建迁移 | 删除迁移 | 说明 |
|---|---|---|---|
| `daemon_pairing_session` | 005 | 029 | Daemon 配对会话，被 `daemon_token` 直接令牌方案取代 |
| `runtime_usage` | 013 | 046 | 按 runtime 维度的用量汇总，被 `task_usage` + `task_usage_daily` 替代 |

---

## 20. 索引清单

以下是除主键和唯一约束外的所有辅助索引：

### 单列 / 组合索引

| 表 | 索引名 | 列 | 条件 |
|---|---|---|---|
| `user` | `user_email_key` | (email) | UNIQUE |
| `workspace` | `workspace_slug_key` | (slug) | UNIQUE |
| `verification_code` | `idx_verification_code_email` | (email, used, expires_at) | |
| `personal_access_token` | `idx_pat_user` | (user_id, revoked) | |
| `member` | `idx_member_workspace` | (workspace_id) | |
| `workspace_invitation` | `idx_invitation_unique_pending` | (workspace_id, invitee_email) | WHERE status = 'pending' |
| `workspace_invitation` | `idx_invitation_invitee_email` | (invitee_email) | WHERE status = 'pending' |
| `workspace_invitation` | `idx_invitation_invitee_user` | (invitee_user_id) | WHERE status = 'pending' |
| `issue` | `idx_issue_workspace` | (workspace_id) | |
| `issue` | `idx_issue_assignee` | (assignee_type, assignee_id) | |
| `issue` | `idx_issue_status` | (workspace_id, status) | |
| `issue` | `idx_issue_parent` | (parent_issue_id) | |
| `issue` | `idx_issue_project` | (project_id) | |
| `issue` | `idx_issue_workspace_number` | (workspace_id, number) | |
| `issue` | `idx_issue_origin` | (origin_type, origin_id) | WHERE origin_type IS NOT NULL |
| `comment` | `idx_comment_issue` | (issue_id) | |
| `comment` | `idx_timeline_keyset` | (issue_id, created_at, id) | |
| `issue_label` | `idx_issue_label_workspace` | (workspace_id) | |
| `issue_subscriber` | `idx_issue_subscriber_user` | (user_type, user_id) | |
| `issue_reaction` | `idx_issue_reaction_issue_id` | (issue_id) | |
| `comment_reaction` | `idx_comment_reaction_comment_id` | (comment_id) | |
| `inbox_item` | `idx_inbox_recipient` | (recipient_type, recipient_id, read) | |
| `agent_task_queue` | `idx_agent_task_queue_agent` | (agent_id, status) | |
| `agent_task_queue` | `idx_agent_task_queue_parent` | (parent_task_id) | |
| `agent_task_queue` | `idx_agent_task_queue_issue_id` | (issue_id) | |
| `agent_task_queue` | `idx_task_queue_claim_candidate` | (status, priority DESC, created_at) | WHERE status = 'queued' |
| `agent_task_queue` | `idx_agent_task_queue_queued` | (agent_id, status, created_at) | |
| `agent` | `idx_agent_workspace` | (workspace_id) | |
| `agent_runtime` | `idx_agent_runtime_workspace` | (workspace_id) | |
| `skill` | `idx_skill_workspace` | (workspace_id) | |
| `skill_file` | `idx_skill_file_skill` | (skill_id) | |
| `agent_skill` | `idx_agent_skill_skill` | (skill_id) | |
| `agent_skill` | `idx_agent_skill_agent` | (agent_id) | |
| `chat_session` | `idx_chat_session_workspace` | (workspace_id) | |
| `chat_session` | `idx_chat_session_creator` | (creator_id, workspace_id) | |
| `chat_message` | `idx_chat_message_session` | (chat_session_id, created_at) | |
| `task_message` | `idx_task_message_task_id_seq` | (task_id, seq) | |
| `task_usage` | `idx_task_usage_task_id` | (task_id) | |
| `task_usage` | `idx_task_usage_updated_at` | (updated_at) | |
| `task_usage` | `idx_task_usage_created_at` | (created_at) | |
| `task_usage_daily` | `idx_task_usage_daily_runtime_date` | (runtime_id, bucket_date DESC) | |
| `task_usage_daily` | `idx_task_usage_daily_workspace_date` | (workspace_id, bucket_date DESC) | |
| `task_usage_daily_dirty` | `idx_task_usage_daily_dirty_enqueued_at` | (enqueued_at) | |
| `task_usage_dashboard_daily` | (复合主键索引) | (bucket_date, workspace_id, agent_id, project_id, model) | |
| `daemon_token` | `idx_daemon_token_hash` | (token_hash) | UNIQUE |
| `daemon_token` | `idx_daemon_token_workspace_daemon` | (workspace_id, daemon_id) | |
| `attachment` | `idx_attachment_issue` | (issue_id) | WHERE issue_id IS NOT NULL |
| `attachment` | `idx_attachment_comment` | (comment_id) | WHERE comment_id IS NOT NULL |
| `attachment` | `idx_attachment_workspace` | (workspace_id) | |
| `pinned_item` | `idx_pinned_item_user_ws` | (workspace_id, user_id, position) | |
| `project` | `idx_project_workspace` | (workspace_id) | |
| `project_resource` | `idx_project_resource_project` | (project_id, position) | |
| `project_resource` | `idx_project_resource_workspace` | (workspace_id) | |
| `autopilot` | `idx_autopilot_workspace` | (workspace_id) | |
| `autopilot` | `idx_autopilot_assignee` | (assignee_id) | |
| `autopilot_trigger` | `idx_autopilot_trigger_autopilot` | (autopilot_id) | |
| `autopilot_trigger` | `idx_autopilot_trigger_next_run` | (next_run_at) | WHERE enabled AND kind = 'schedule' |
| `autopilot_run` | `idx_autopilot_run_autopilot` | (autopilot_id, created_at DESC) | |
| `autopilot_run` | `idx_autopilot_run_status` | (autopilot_id, status) | WHERE status IN (...) |
| `squad` | `idx_squad_workspace` | (workspace_id) | |
| `squad_member` | `idx_squad_member_squad` | (squad_id) | |
| `squad_member` | `idx_squad_member_entity` | (member_type, member_id) | |
| `github_installation` | `idx_github_installation_workspace` | (workspace_id) | |
| `github_pull_request` | `idx_github_pull_request_workspace` | (workspace_id) | |
| `issue_pull_request` | `idx_issue_pull_request_pr` | (pull_request_id) | |
| `activity_log` | `idx_activity_log_issue` | (issue_id) | |
| `feedback` | `idx_feedback_user_created` | (user_id, created_at DESC) | |
| `notification_preference` | (unique 约束索引) | (workspace_id, user_id) | UNIQUE |

### 全文搜索索引

| 表 | 类型 | 覆盖列 | 迁移 |
|---|---|---|---|
| `issue` | GIN (to_tsvector) | title + description | 032, 036 |
| `comment` | GIN (to_tsvector) | content | 033 |
| `project` | GIN (to_tsvector) | title + description | 039 |

---

> 文档基于 90 个迁移文件自动生成，反映截至 2026-05-20 的最终 schema 状态。
> 源文件位于 `server/migrations/`，sqlc 查询位于 `server/pkg/db/queries/`。
