# 产品能力树

> 基于当前代码库在 2026-05-19 的深度调研结果整理。  
> 这个版本按“产品能力”而不是“代码层级”组织。

## 1. 入口与终端

### 1.1 Web 应用
主工作台入口。承载登录、工作区切换、issue/project/agent/runtime/skill/autopilot/chat/inbox/settings 等完整日常操作。

### 1.2 桌面应用
Electron 端的工作台壳层。复用 Web 的主要业务页面，同时提供原生窗口覆盖层、标签组、daemon 管理和自动更新。

### 1.3 CLI（`multica`）
面向开发者、自动化和终端工作流的管理入口。可管理登录、工作区、issue、project、agent、skill、autopilot、runtime、squad、attachment、版本和 daemon。

### 1.4 文档站
独立的文档入口。用于产品和使用说明，不参与业务执行。

## 2. 账号与工作区

### 2.1 登录与会话
支持邮箱验证码登录、Google OAuth、退出登录，以及 PAT 方式的 CLI 认证。会话通过 token/cookie 维持。

### 2.2 Onboarding
面向新用户的首次引导。目标是尽快完成工作区、runtime、agent 的基础配置，让用户进入可用状态。

### 2.3 工作区管理
工作区是所有资源的隔离边界。支持创建、切换、更新、删除、离开、slug 路由访问和 starter content 导入。

### 2.4 成员与邀请
支持成员列表、成员角色、邀请创建/撤销/接受/拒绝，是团队协作的基础权限系统。

### 2.5 个人设置与令牌
包含个人资料、外观、API tokens、通知偏好等个人级配置。

### 2.6 权限与可见性
工作区角色（owner/admin/member）和资源可见性（如 agent private/workspace）共同决定谁能看见和操作什么。

## 3. 工作管理

### 3.1 Issue 管理
核心任务单元。支持列表、看板、详情、快速创建、批量更新/删除、搜索、排序、过滤、状态流转、负责人分配和子任务管理。

### 3.2 评论与讨论
支持富文本评论、回复、解决/取消解决、reaction、`@member` / `@agent` 提及，以及基于评论触发的 agent 任务。

### 3.3 标签、依赖与置顶
支持标签、多标签关系、issue 依赖关系、置顶项和订阅者管理，让工作能够被更细粒度地组织。

### 3.4 项目管理
项目是比 issue 更高一级的聚合单元。支持列表、详情、状态、优先级、负责人和资源附件。

### 3.5 收件箱与通知
将被分配、被提及、被评论、被订阅等事件汇总到 inbox，并支持已读、归档和通知偏好设置。

### 3.6 搜索与命令面板
支持 issue/project/workspace 搜索，以及 Cmd+K 风格的快速导航和快捷动作入口。

### 3.7 用量与仪表盘
支持 workspace、runtime、agent 维度的用量统计和 dashboard 汇总，用来观察执行规模与成本趋势。

## 4. Agent 生产系统

### 4.1 Agent 管理
Agent 是一等协作对象。支持创建、编辑、归档、恢复、模板化创建，以及头像、模型、指令、环境变量、参数、MCP 配置等设置。

### 4.2 Runtime / Daemon
Runtime 是 agent 真正执行工作的环境。Daemon 在本机发现可用 CLI、注册 runtime、心跳保活、领取任务、流式回传进度，并在异常后做恢复。

### 4.3 Skills
技能是可复用的知识包。支持创建、导入、挂载到 agent、携带文件内容，并在任务开始时注入给具体 CLI。

### 4.4 Chat
提供与 agent 的持久化多轮对话。消息、附件、pending task 和 unread 状态都属于同一会话体系。

### 4.5 Squads
小队把多个 agent/成员组织成稳定路由层，由 leader agent 负责分配与评价，适合中大型团队的任务分发。

### 4.6 Autopilots
自动化规则引擎。支持定时或手动触发、运行历史、创建 issue 或直接运行 agent。数据模型还预留了 `webhook` / `api` trigger 类型，但当前入口并未完全闭合。

## 5. 平台与集成

### 5.1 GitHub 集成
支持 GitHub App setup、webhook 处理、installation 存储、PR 关联，以及合并后推进 issue 状态。

### 5.2 文件与附件存储
支持本地文件系统和 S3 兼容对象存储，媒体访问可通过签名 URL / cookie 控制。

### 5.3 邮件能力
支持 Resend 和 SMTP，用于验证码、邀请、通知等场景。

### 5.4 实时通信
通过 WebSocket 推送 issue、task、chat、inbox、workspace 等变化；在多实例场景下可选 Redis relay。

### 5.5 分析与监控
支持 PostHog 事件分析、Prometheus 指标和健康检查端点。

### 5.6 安全与配置
JWT、PAT、daemon token、workspace repo 白名单、origin 限制、CloudFront 签名等共同构成访问控制和部署约束。

## 6. 完整产品功能树

```text
Multica
├─ 入口与终端
│  ├─ Web 应用：浏览器主工作台
│  │  ├─ Landing：首页、下载页、关于页、更新日志
│  │  ├─ Auth：登录、OAuth 回调、邀请接受、工作区创建、onboarding
│  │  └─ Workspace Dashboard：工作区内所有核心业务页面
│  ├─ 桌面应用：Electron 工作台
│  │  ├─ 工作区标签：每个工作区独立 tab 组，支持桌面内导航
│  │  ├─ 窗口覆盖层：创建工作区、接受邀请、onboarding 等 pre-workspace 流程
│  │  ├─ Daemon 面板：查看/管理本机 daemon 状态
│  │  └─ Updates 面板：桌面端版本检查和更新
│  ├─ CLI：终端管理面
│  │  ├─ setup/config/auth/login：配置、登录、profile、云端/自托管连接
│  │  ├─ daemon：start/stop/status/restart/logs/disk-usage
│  │  ├─ workspace：list/get/members/update/watch/unwatch
│  │  ├─ issue：list/get/create/update/assign/status/search
│  │  ├─ issue comment/subscriber/label：评论、订阅者、标签关系管理
│  │  ├─ issue runs/run-messages/rerun/cancel-task：执行历史、消息、重跑、取消
│  │  ├─ project：list/get/create/update/delete/status/resource
│  │  ├─ agent：list/get/create/update/archive/restore/tasks/avatar/skills
│  │  ├─ skill：list/get/create/update/delete/import/files
│  │  ├─ autopilot：list/get/create/update/delete/trigger/runs/triggers
│  │  ├─ runtime：list/usage/activity/update
│  │  ├─ squad：list/get/create/update/delete/member/activity
│  │  ├─ repo：checkout
│  │  ├─ attachment：download
│  │  └─ version/update：版本查看与 CLI 更新
│  └─ 文档站：产品和使用说明
├─ 账号与工作区
│  ├─ 登录与会话：让人类用户、CLI 和桌面端进入系统
│  │  ├─ 邮箱验证码：发送验证码、验证验证码、尝试次数和过期控制
│  │  ├─ Google OAuth：Google 登录与回调
│  │  ├─ Logout：清除会话
│  │  ├─ 当前用户：读取和更新个人信息
│  │  ├─ PAT：创建、查看、撤销个人访问令牌，供 CLI/自动化使用
│  │  └─ Signup 控制：允许注册、邮箱白名单、域名白名单
│  ├─ Onboarding：让新用户完成从空账号到可用工作区的闭环
│  │  ├─ Welcome：产品欢迎与开始入口
│  │  ├─ Workspace：创建或选择工作区
│  │  ├─ Runtime Connect：安装/连接本机 runtime
│  │  ├─ Agent：创建第一个 agent
│  │  ├─ First Issue：创建第一个可分配任务
│  │  ├─ Starter Content：导入或跳过初始内容
│  │  └─ Cloud Waitlist：云运行时等待列表入口
│  ├─ 工作区管理：多租户和团队隔离边界
│  │  ├─ Workspace CRUD：创建、读取、更新、删除
│  │  ├─ Slug 路由：所有 dashboard 页面按 workspace slug 访问
│  │  ├─ Workspace Context：给该工作区 agent 的统一上下文
│  │  ├─ Repositories：工作区仓库白名单/上下文
│  │  ├─ Issue Prefix/Counter：工作区 issue 编号体系
│  │  ├─ Starter State：记录初始内容导入/跳过状态
│  │  └─ Leave Workspace：成员主动离开工作区
│  ├─ 成员与邀请：团队协作身份管理
│  │  ├─ Member List：成员列表、头像、邮箱、角色
│  │  ├─ Member Detail：成员详情页和成员相关工作
│  │  ├─ Role Update：owner/admin/member 角色调整
│  │  ├─ Remove Member：移除成员
│  │  ├─ Invitation List：工作区待处理邀请
│  │  ├─ Create Invitation：邀请新成员
│  │  ├─ Revoke Invitation：撤销邀请
│  │  ├─ Accept/Decline Invitation：接受或拒绝邀请
│  │  └─ My Invitations：个人收到的邀请列表
│  ├─ 个人设置与偏好
│  │  ├─ Profile：姓名、头像、邮箱等个人信息
│  │  ├─ Appearance：主题/外观偏好
│  │  ├─ API Tokens：个人访问令牌管理
│  │  ├─ Notifications：通知偏好
│  │  └─ Language：用户语言偏好
│  └─ 权限与可见性
│     ├─ Workspace Role：工作区内 owner/admin/member 权限
│     ├─ Resource Permissions：按资源类型判断可操作性
│     ├─ Agent Visibility：private/workspace 可见性
│     └─ Runtime Visibility：private/workspace 可见性
├─ 工作管理
│  ├─ Issue 管理：Multica 的核心任务对象
│  │  ├─ Issue List：按工作区列出 issue
│  │  ├─ Board View：按状态分列的看板视图
│  │  ├─ List View：表格/列表视图
│  │  ├─ Grouped View：分组 issue 视图
│  │  ├─ My Issues：分配给我、我创建的、我的 agent 相关 issue
│  │  ├─ Issue Detail：标题、描述、状态、优先级、负责人、项目、截止日期
│  │  ├─ Quick Create：快速创建，并可触发 agent 创建/补全工作
│  │  ├─ Batch Update/Delete：批量状态、优先级、负责人和删除
│  │  ├─ Search Issues：按标题/描述/评论等搜索
│  │  ├─ Parent/Children：父子 issue 和子任务进度
│  │  ├─ Acceptance Criteria：验收标准 JSON 数据
│  │  ├─ Due Date：截止日期
│  │  ├─ Position：手动排序位置
│  │  ├─ Origin：记录 autopilot 或 quick_create 来源
│  │  └─ Pull Requests：关联 GitHub PR
│  ├─ Issue 执行
│  │  ├─ Active Task：查看 issue 当前活跃任务
│  │  ├─ Task Runs：查看 issue 历史执行记录
│  │  ├─ Run Messages：查看单次执行消息流
│  │  ├─ Rerun：按当前 agent assignment 重新入队
│  │  ├─ Cancel Task：取消运行中或排队中的任务
│  │  └─ Issue Usage：查看 issue 相关用量
│  ├─ 评论与讨论
│  │  ├─ Comment List/Create/Update/Delete：评论 CRUD
│  │  ├─ Reply Thread：评论回复
│  │  ├─ Resolve/Unresolve：评论解决状态
│  │  ├─ Comment Reactions：评论 emoji reaction
│  │  ├─ Issue Reactions：issue emoji reaction
│  │  ├─ Mentions：提及 member 或 agent
│  │  └─ Timeline：活动和评论混合时间线
│  ├─ 标签、订阅与关系
│  │  ├─ Label CRUD：工作区标签管理
│  │  ├─ Attach/Detach Label：issue 标签关系
│  │  ├─ Issue Subscribers：订阅者列表、订阅、取消订阅
│  │  ├─ Assignee Frequency：负责人频率建议
│  │  ├─ Issue Dependencies：issue 依赖/阻塞关系
│  │  └─ Pins：置顶、排序、取消置顶
│  ├─ 项目管理
│  │  ├─ Project List/Search：项目列表和搜索
│  │  ├─ Project Detail：项目详情和项目内 issue
│  │  ├─ Project CRUD：创建、更新、删除
│  │  ├─ Project Status/Priority：项目状态和优先级
│  │  ├─ Project Lead：负责人可为成员或 agent
│  │  ├─ Project Resources：项目资源列表、创建、删除
│  │  └─ Project Issue Metrics：项目 issue 指标
│  ├─ 收件箱与通知
│  │  ├─ Inbox List：个人/工作区通知列表
│  │  ├─ Unread Count：未读数量
│  │  ├─ Mark Read：单条已读
│  │  ├─ Mark All Read：全部已读
│  │  ├─ Archive Item：单条归档
│  │  ├─ Archive All/Read/Completed：批量归档
│  │  └─ Notification Preferences：通知偏好读取和更新
│  ├─ 搜索与命令面板
│  │  ├─ Search Command：全局命令面板
│  │  ├─ Navigation Actions：跳转到 issues/projects/settings 等
│  │  ├─ Recent Issues：最近访问 issue
│  │  └─ Local Filters：issue/project/inbox 本地筛选
│  └─ 用量与仪表盘
│     ├─ Workspace Usage Daily：工作区按日用量
│     ├─ Workspace Usage Summary：工作区用量汇总
│     ├─ Dashboard Usage Daily：仪表盘日维度用量
│     ├─ Dashboard Usage By Agent：按 agent 聚合用量
│     ├─ Agent Runtime Time：agent 运行时长
│     ├─ Runtime Daily：runtime 日维度统计
│     └─ Cost Estimation：基于模型用量估算成本
├─ Agent 生产系统
│  ├─ Agent 管理：AI 工作者身份
│  │  ├─ Agent List：agent 列表、状态、runtime/provider 概览
│  │  ├─ Agent Detail：agent 详情页
│  │  ├─ Create/Update Agent：创建和编辑 agent
│  │  ├─ Create From Template：从模板创建 agent
│  │  ├─ Archive/Restore：归档和恢复 agent
│  │  ├─ Avatar：上传/编辑头像
│  │  ├─ Runtime Picker：绑定 runtime
│  │  ├─ Model Picker：选择模型
│  │  ├─ Visibility Picker：private/workspace 可见性
│  │  ├─ Concurrency：最大并发任务数
│  │  ├─ Instructions：agent 系统指令
│  │  ├─ Custom Env：注入 CLI 子进程的环境变量
│  │  ├─ Custom Args：注入 CLI 的参数
│  │  ├─ MCP Config：外部工具/服务配置
│  │  ├─ Skills Tab：agent 挂载 skill
│  │  ├─ Activity Tab：当前任务、近 30 天表现、近期工作
│  │  ├─ Presence：在线、工作中、离线、不稳定等展示
│  │  ├─ Cancel Agent Tasks：取消该 agent 的任务
│  │  └─ Templates Catalog：静态 agent 模板目录
│  ├─ Runtime / Daemon：执行环境和本机守护进程
│  │  ├─ Runtime List：runtime 列表、状态、provider、owner
│  │  ├─ Runtime Detail：runtime 详情页
│  │  ├─ Runtime Update：更新 runtime 相关 CLI
│  │  ├─ Runtime Usage：token/成本/时间统计
│  │  ├─ Usage By Agent/Hour：按 agent 或小时聚合
│  │  ├─ Runtime Activity：任务活动热力/图表
│  │  ├─ Models Request：发起模型列表查询并读取结果
│  │  ├─ Local Skills Request：发起本地 skill 列表查询并读取结果
│  │  ├─ Import Local Skill：从 runtime 导入本地 skill
│  │  ├─ Runtime Delete：删除 runtime
│  │  ├─ Connect Remote：连接远端 runtime 入口
│  │  ├─ Custom Pricing：自定义模型价格
│  │  ├─ Daemon Register/Deregister/Heartbeat：daemon 生命周期
│  │  ├─ Daemon WebSocket：daemon 实时通道
│  │  ├─ Task Claim/Pending：runtime 领取/查看待处理任务
│  │  ├─ Task Start/Progress/Complete/Fail：任务生命周期上报
│  │  ├─ Task Usage/Messages：上报用量和消息
│  │  ├─ GC Check：issue/chat/autopilot/task 维度 GC 检查
│  │  ├─ Recover Orphans：恢复孤儿任务
│  │  └─ Pin Session：绑定任务 session
│  ├─ Skills：可复用能力包
│  │  ├─ Skill List：skill 列表
│  │  ├─ Skill Detail：skill 详情和文件树
│  │  ├─ Create/Update/Delete Skill：skill CRUD
│  │  ├─ Manual Create：手动创建 skill
│  │  ├─ URL Import：从 clawhub.ai、skills.sh、github.com 等导入
│  │  ├─ Runtime Import：从本地 runtime skill 列表导入
│  │  ├─ Skill Files：文件列表、upsert、删除
│  │  ├─ File Tree/Viewer：skill 文件浏览
│  │  ├─ Edit Permission：skill 编辑权限判断
│  │  └─ Agent Skill Assignment：分配给 agent
│  ├─ Chat：与 agent 的持久化对话
│  │  ├─ Chat FAB/Window：浮动聊天入口和窗口
│  │  ├─ Chat Session CRUD：创建、列表、读取、更新、删除会话
│  │  ├─ Send/List Messages：发送和读取消息
│  │  ├─ Attachments：聊天附件
│  │  ├─ Pending Task：会话关联待处理任务
│  │  ├─ Mark Read：标记会话已读
│  │  ├─ Offline/No Agent Banner：无 agent 或离线提示
│  │  ├─ Resize Handles：聊天窗口尺寸调整
│  │  └─ Context Anchor：聊天上下文锚点
│  ├─ Squads：团队级 agent 路由
│  │  ├─ Squad List：小队列表
│  │  ├─ Squad Detail：小队详情页
│  │  ├─ Create/Update/Delete Squad：创建、更新、归档
│  │  ├─ Avatar/Name/Description：基础资料编辑
│  │  ├─ Leader：设置 leader agent
│  │  ├─ Members：成员列表、添加、移除
│  │  ├─ Member Role：成员角色更新
│  │  ├─ Instructions：小队指令
│  │  ├─ Create Agent From Squad：在小队中创建 agent
│  │  ├─ Assign Issue To Squad：issue 可指派给 squad
│  │  └─ Leader Evaluation：记录 squad leader 对 issue 的评价
│  └─ Autopilots：自动化调度
│     ├─ Autopilot List：自动化规则列表
│     ├─ Autopilot Detail：详情和触发器
│     ├─ Create/Update/Delete Autopilot：规则 CRUD
│     ├─ Manual Trigger：手动触发一次运行
│     ├─ Runs：运行历史
│     ├─ Trigger Create/Update/Delete：触发器管理
│     ├─ Schedule Trigger：cron + timezone 定时触发
│     ├─ Execution Mode create_issue：每次运行创建 issue 并分配给 agent
│     ├─ Execution Mode run_only：直接运行 agent 的数据模型/UI 能力
│     ├─ Skipped/Failed/Completed Status：运行状态追踪
│     └─ Webhook/API Trigger：schema 预留，但当前未找到完整入站触发入口
└─ 平台与集成
   ├─ GitHub 集成
   │  ├─ GitHub Connect：工作区发起 GitHub 连接
   │  ├─ Setup Callback：安装回调和 state 校验
   │  ├─ Installations：安装列表和删除
   │  ├─ Webhook：PR 等事件接收和签名校验
   │  ├─ Pull Request Link：PR 与 issue 自动/手动关联
   │  └─ Auto Advance：PR 合并后推进 issue
   ├─ 文件与附件存储
   │  ├─ Upload File：统一上传入口
   │  ├─ Attachment Metadata：附件元数据读取和删除
   │  ├─ Attachment Content：附件内容读取
   │  ├─ Issue Attachments：issue 附件列表
   │  ├─ Local Storage：本地文件存储后端
   │  ├─ S3 Storage：S3 兼容对象存储
   │  └─ CloudFront Signing：签名 URL/cookie 媒体访问
   ├─ 邮件能力
   │  ├─ Verification Code Email：验证码邮件
   │  ├─ Invitation Email：邀请邮件
   │  ├─ Resend Provider：Resend 发送
   │  ├─ SMTP Provider：SMTP 发送
   │  └─ Dev Fallback：未配置发送通道时记录验证码
   ├─ 实时通信
   │  ├─ Browser/Desktop WebSocket：前端实时同步
   │  ├─ Daemon WebSocket：daemon 控制和唤醒通道
   │  ├─ Workspace Events：issue/comment/agent/task/project/skill 等事件
   │  ├─ User Events：inbox/invitation 等用户定向事件
   │  ├─ Redis Relay：多实例实时中继
   │  └─ Realtime Health：实时层健康检查
   ├─ 分析与监控
   │  ├─ PostHog Analytics：产品/服务端分析事件
   │  ├─ Feedback：用户反馈创建
   │  ├─ Prometheus Metrics：后端指标
   │  ├─ Health/Ready：健康和就绪检查
   │  └─ Runtime Metrics：runtime usage/activity 图表数据
   └─ 安全与配置
      ├─ JWT Session：用户会话 token
      ├─ Personal Access Token：CLI/API 个人令牌
      ├─ Daemon Token：daemon 范围令牌
      ├─ Workspace Repo Allowlist：仓库访问白名单
      ├─ CORS/Origins：HTTP 与 WS origin 限制
      ├─ CloudFront Cookies：媒体访问签名
      ├─ Environment Config：数据库、邮件、OAuth、GitHub、存储、分析等配置
      └─ CSP：内容安全策略
```

## 7. 研究结论

Multica 的核心不是“一个 AI 功能”，而是“把人和 agent 放进同一个工作系统里”：

- **Issue** 是工作骨架
- **Agent** 是执行者
- **Runtime/Daemon** 是执行引擎
- **Skills** 是能力沉淀
- **Autopilot** 是自动化调度
- **Squads** 是团队级路由
- **Inbox / Chat / Realtime** 是协作反馈闭环

换句话说，这个产品的主线是：**把 AI 执行、团队协作、任务编排、知识复用和多端入口统一到一个工作区里**。

## 8. 证据

- `README.md`
- `README.zh-CN.md`
- `CLI_AND_DAEMON.md`
- `CLI_INSTALL.md`
- `docs/product-overview.md`
- `docs/codebase/ARCHITECTURE.md`
- `docs/codebase/STRUCTURE.md`
- `apps/web/app/`
- `apps/desktop/src/renderer/src/routes.tsx`
- `packages/views/`
- `packages/core/api/client.ts`
- `server/cmd/server/router.go`
- `server/cmd/multica/`
- `server/migrations/*.sql`
