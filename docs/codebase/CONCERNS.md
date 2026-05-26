# 代码库关注点

## 顶层风险（按优先级排序）

| 严重性 | 风险 | 证据 | 影响 | 建议操作 |
|--------|------|------|------|---------|
| 高 | `router.go` 集中承载大量路由和中间件 | `server/cmd/server/router.go` | 改动容易波及多个领域 | 考虑按领域拆分路由模块 |
| 高 | `api/client.ts` 是共享API面，高churn | `packages/core/api/client.ts` | 请求/响应类型变更会连带影响所有消费方 | 添加API契约测试 |
| 高 | runtime/daemon/task 路径跨越多层次 | CLI → daemon handler → realtime → DB → UI | 端到端改动风险高 | 添加集成测试覆盖 |
| 中 | 无分布式追踪 | 无OpenTelemetry配置 | 调试跨服务问题困难 | 引入OpenTelemetry |
| 中 | `ARCHITECTURE.md` 与README中的pgvector描述不一致 | 迁移使用pgcrypto/pg_bigm，未见vector扩展 | 向量搜索功能状态不明确 | [ASK USER] 确认向量搜索状态 |
| 中 | 环境变量命名不一致 | CORS_ALLOWED_ORIGINS vs ALLOWED_ORIGINS | 配置混淆 | 统一环境变量命名 |
| 低 | 无API响应时间P50/P95指标 | `server/internal/metrics/` | 性能盲点 | 添加histogram指标 |
| 低 | 无前端性能监控 | 无web-vitals | 用户体验盲点 | 添加web-vitals集成 |

## 技术债务

### 重要债务项

| 债务项 | 存在原因 | 位置 | 忽略风险 | 建议修复 |
|--------|---------|------|---------|---------|
| Router.go 路由集中 | 初始设计未考虑路由分组 | `server/cmd/server/router.go` | 改动风险高，难以测试 | 按领域拆分路由模块 |
| API Client Schema验证测试缺失 | 早期未建立契约测试意识 | `packages/core/api/` | API变更静默破坏桌面应用 | 添加schema验证E2E测试 |
| 无分布式追踪 | 项目初期聚焦核心功能 | 全局 | 调试困难，性能分析不足 | 引入OpenTelemetry |
| 测试覆盖率数据缺失 | 尚未运行覆盖率工具 | 全局 | 无法量化测试质量 | 定期运行覆盖率报告 |
| 环境变量命名不一致 | 渐进式功能添加 | `.env.example`, router.go | 自托管部署配置混淆 | 统一命名规范 |

### 架构债务

| 债务项 | 描述 | 当前状态 | 风险 | 建议 |
|--------|------|---------|------|------|
| WebSocket多节点支持 | Redis中继架构存在但未充分测试 | `server/cmd/server/main.go` | 多节点部署可能出现消息丢失 | 补充集成测试 |
| 桌面应用与Web API兼容性 | API响应兼容性规则已有文档但未充分测试 | `CLAUDE.md` | 桌面应用静默失败 | 强化schema验证 |
| 多个Autopilot trigger类型 | schema支持但部分未暴露产品入口 | `server/migrations/` | 功能碎片化 | 统一trigger实现 |

## 安全关注

| 风险 | OWASP类别 | 证据 | 当前缓解 | 差距 |
|------|-----------|------|---------|------|
| SQL注入 | A03:2021 | sqlc参数化查询 | 使用sqlc生成的类型化查询 | 已缓解 |
| 认证令牌泄露 | A07:2021 | JWT/ PAT | 令牌不记录日志 | 无已知问题 |
| CORS配置错误 | A01:2021 | router.go | 使用白名单 | 无已知问题 |
| 文件上传漏洞 | A03:2021 | file.go | S3/本地存储抽象 | [TODO] 安全扫描 |
| 密码/密钥硬编码 | A02:2021 | 无发现 | 所有密钥通过环境变量 | 已缓解 |
| XSS | A03:2021 | 前端渲染 | React自动转义 | 已缓解 |
| CSRF | A01:2021 | API认证 | JWT + SameSite cookie | 已缓解 |

## 性能和扩展性关注

| 关注点 | 证据 | 当前症状 | 扩展风险 | 建议改进 |
|--------|------|---------|---------|---------|
| 数据库查询性能 | `server/pkg/db/queries/` | 无明显症状 | 大数据集下可能出现慢查询 | 添加查询性能监控 |
| WebSocket连接数 | `server/internal/realtime/` | 无明显症状 | 大量并发用户可能瓶颈 | 添加连接数指标 |
| 无API限流 | API handlers | 无保护 | DoS攻击风险 | 实现限流中间件 |
| 迁移90+个文件 | `server/migrations/` | 启动时间可能较长 | 新环境搭建变慢 | 考虑迁移合并 |
| 无缓存层 | API handlers | 每次请求查询数据库 | 高频读取场景性能问题 | 考虑添加Redis缓存 |

## 脆弱/高变化区域

### 高变化文件

| 文件 | 变化原因 | 30天提交数 | 安全变更策略 |
|------|---------|-----------|-------------|
| `server/internal/daemon/daemon.go` | Daemon功能持续迭代 | 122 | 保持测试覆盖 |
| `server/cmd/server/router.go` | 新API端点添加 | 121 | 按领域分组路由 |
| `server/internal/handler/daemon.go` | Daemon协议迭代 | 94 | 添加协议版本处理 |
| `server/internal/handler/issue.go` | Issue功能丰富 | 83 | 保持API兼容性 |
| `packages/core/api/client.ts` | 新API端点 | 75 | 添加schema验证 |
| `apps/web/features/issues/components/issue-detail.tsx` | UI迭代 | 69 | 组件测试覆盖 |

### 脆弱模式

| 模式 | 位置 | 脆弱原因 | 安全变更策略 |
|------|------|---------|-------------|
| 直接使用URL参数做写查询 | handlers | 历史上曾导致#1661 | 使用loader解析后再用entity.ID |
| Switch无default | 前端组件 | 新枚举值静默忽略 | 强制要求default分支 |
| Store选择器返回新对象 | Zustand stores | 导致无限重渲染 | 使用shallow比较 |
| API响应无schema验证 | API client使用处 | 响应格式变化静默失败 | 使用parseWithFallback |

## `[ASK USER]` 问题

1. **[ASK USER]** 向量搜索功能（pgvector）是否计划中？README提到但迁移中未使用。
2. **[ASK USER]** Autopilot的webhook/api trigger类型是计划功能还是内部能力？
3. **[ASK USER]** 环境变量命名统一：HTTP CORS使用`CORS_ALLOWED_ORIGINS`，WebSocket使用`ALLOWED_ORIGINS`，是否应该统一？
4. **[ASK USER]** 是否需要实现API限流功能？
5. **[ASK USER]** 测试覆盖率目标是多少？

## 意图与现实差异

| 文档描述 | 现实状态 | 影响 |
|---------|---------|------|
| README提到pgvector | 迁移使用pgcrypto/pg_bigm，未见vector扩展 | 向量搜索状态不明确 |
| README提到PostgreSQL 17 | Docker镜像使用pgvector/pgvector:pg17 | 基本一致，镜像包含pgvector |
| Autopilot支持webhook/api trigger | schema支持但无产品入口 | 功能碎片化或计划中 |
| CLI_AND_DAEMON.md描述CLI | 有更新但可能过时 | 用户文档可能不一致 |

## 证据

- `docs/codebase/.codebase-scan.txt` - 代码库扫描结果
- `server/cmd/server/router.go` - 路由集中问题
- `packages/core/api/client.ts` - API客户端高churn
- `CLAUDE.md` - 架构决策文档
- `README.md` - 项目概述
- `docs/codebase/ARCHITECTURE.md` - 现有架构文档
- `packages/core/api/schema.ts` - API响应解析
- `server/internal/handler/` - handler层风险
