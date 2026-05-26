# 测试策略

## 测试框架和命令

### 测试栈

| 语言 | 测试框架 | 版本 | 证据 |
|------|---------|------|------|
| TypeScript/React | Vitest | ^4.1.0 | `packages/*/vitest.config.ts` |
| TypeScript | @testing-library/react | ^16.3.0 | `pnpm-workspace.yaml` catalog |
| TypeScript | @testing-library/user-event | ^14.6.0 | `pnpm-workspace.yaml` catalog |
| Go | go test | 标准库 | `server/` 各模块 |
| E2E | Playwright | ^1.58.0 | `package.json` devDependencies |

### 断言和Mock工具

| 工具 | 用途 | 证据 |
|------|------|------|
| Vitest expect | 断言库 | 标准配置 |
| @testing-library/react | React组件测试 | `packages/views/` |
| @testing-library/jest-dom | DOM断言 | `pnpm-workspace.yaml` |
| vi.mock (Vitest) | 模块Mock | 测试文件 |
| vi.hoisted (Vitest) | 静态Mock | 测试文件 |
| sqlc生成的测试支持 | 数据库测试 | `server/pkg/db/` |

### 运行命令

```bash
# 运行所有检查（类型检查 + 单元测试 + Go测试 + E2E）
make check

# 仅TypeScript单元测试
pnpm test

# 仅Go测试
make test

# E2E测试（需要后端和前端运行）
pnpm exec playwright test

# 单个包测试
pnpm --filter @multica/core exec vitest run runtimes/version.test.ts
pnpm --filter @multica/views exec vitest run auth/login-page.test.tsx
pnpm --filter @multica/web exec vitest run app/\(auth\)/login/page.test.tsx

# 单个Go测试
cd server && go test ./internal/handler/ -run TestName

# 覆盖率（TypeScript）
pnpm --filter @multica/core exec vitest run --coverage

# 覆盖率（Go）
cd server && go test -cover ./...
```

## 测试布局

### 测试文件位置

| 测试类型 | 位置模式 | 示例 |
|---------|---------|------|
| 核心包单元测试 | `packages/core/**/*.test.ts` | `packages/core/runtimes/version.test.ts` |
| 共享视图组件测试 | `packages/views/**/*.test.tsx` | `packages/views/auth/login-page.test.tsx` |
| Web应用测试 | `apps/web/**/*.test.tsx` | `apps/web/app/(auth)/login/page.test.tsx` |
| 桌面应用测试 | `apps/desktop/**/*.test.ts` | `apps/desktop/test/` |
| E2E测试 | `e2e/**/*.spec.ts` | `e2e/tests/` |
| Go单元测试 | `server/**/*_test.go` | `server/internal/handler/issue_test.go` |

### 测试设置文件

| 位置 | 用途 | 证据 |
|------|------|------|
| `apps/web/test/setup.ts` | Web测试全局配置 | `apps/web/test/setup.ts` |
| `apps/desktop/test/setup.ts` | 桌面测试全局配置 | `apps/desktop/test/setup.ts` |
| `vitest.config.ts` | Vitest配置 | 各包根目录 |

### 命名约定

| 类型 | 约定 | 示例 |
|------|------|------|
| TypeScript测试文件 | `{Module}.test.ts` 或 `{module}.test.tsx` | `IssueDetail.test.tsx` |
| Go测试文件 | `{package}_test.go` | `issue_test.go` |
| E2E测试文件 | `{feature}.spec.ts` | `issue-creation.spec.ts` |
| 测试工具文件 | `helpers.ts` 或 `fixtures.ts` | `apps/web/test/helpers.tsx` |

## 测试范围矩阵

| 范围 | 覆盖 | 典型目标 | 备注 |
|------|------|---------|------|
| 单元测试 | 是 | Stores, hooks, utilities | Vitest + jsdom |
| 集成测试 | 部分 | API handlers, DB queries | Go测试 + fixture |
| E2E测试 | 是 | 完整用户流程 | Playwright |
| 组件测试 | 是 | React组件 | @testing-library/react |
| 回归测试 | 是 | Bug修复验证 | 测试文件 |

### 单元测试覆盖

| 模块 | 覆盖范围 | 证据 |
|------|---------|------|
| `packages/core/stores/` | Zustand状态管理逻辑 | `packages/core/stores/*.test.ts` |
| `packages/core/queries/` | React Query hooks | `packages/core/queries/*.test.ts` |
| `packages/core/api/` | API客户端 | `packages/core/api/*.test.ts` |
| `packages/views/` | 共享组件 | `packages/views/**/*.test.tsx` |
| `server/internal/` | Service层逻辑 | `server/internal/**/*_test.go` |

### E2E测试覆盖

| 用户流程 | 覆盖 | 证据 |
|---------|------|------|
| 用户登录/注册 | 是 | `e2e/tests/auth/` |
| Issue创建/编辑 | 是 | `e2e/tests/issues/` |
| Agent管理 | 是 | `e2e/tests/agents/` |
| 工作区切换 | 是 | `e2e/tests/workspaces/` |

## Mock和隔离策略

### 主要Mock方式

| Mock目标 | 工具 | 模式 | 证据 |
|---------|------|------|------|
| Zustand stores | `vi.hoisted()` + `Object.assign` | 工厂模式 | `packages/views/**/*.test.tsx` |
| API调用 | `vi.mock('@multica/core/api')` | 模块级Mock | 测试文件 |
| next/navigation | 不Mock（禁止在views中） | - | - |
| react-router-dom | 不Mock（禁止在views中） | - | - |

### Zustand Store Mock示例

```typescript
import { vi } from 'vitest';

// Mock store
const mockWorkspaceStore = vi.fn(() => ({
  currentWorkspace: null,
  setCurrentWorkspace: vi.fn(),
})) as unknown as typeof workspaceStore;

Object.assign(mockWorkspaceStore, { getState: () => mockWorkspaceStore() });
```

### 隔离保证

| 隔离类型 | 保证方式 | 重置时机 |
|---------|---------|---------|
| Store状态 | 每个测试创建新实例 | `beforeEach` |
| API Mock | `vi.clearAllMocks()` | 每个测试后 |
| DOM环境 | jsdom隔离 | 每个测试文件 |
| 数据库状态 | 测试fixture清理 | `afterEach` |

### 常见测试失败原因

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 无限重渲染 | Store选择器返回新对象 | 使用shallow比较或选择原始值 |
| Mock状态泄漏 | 未在beforeEach重置 | 确保每个测试独立 |
| 异步测试超时 | 未等待异步操作 | 使用`waitFor`或`findBy*`查询 |
| E2E测试不稳定 | 网络延迟或时机问题 | 添加适当的等待或retry |

## 覆盖率和质量信号

### 覆盖率工具

| 工具 | 语言 | 配置 | 证据 |
|------|------|------|------|
| Vitest coverage | TypeScript | `--coverage` flag | `vitest.config.ts` |
| Go coverage | Go | `-cover` flag | `Makefile` |

### 当前覆盖率

| 范围 | 覆盖率 | 备注 |
|------|--------|------|
| TypeScript | [TODO] | 需要运行覆盖率命令获取 |
| Go | [TODO] | 需要运行覆盖率命令获取 |
| E2E | 手动验证 | 关键路径已覆盖 |

### 已知缺口

| 缺口 | 影响 | 建议 |
|------|------|------|
| 无API契约测试 | 响应格式变化可能导致静默失败 | 添加schema验证测试 |
| 无性能回归测试 | 大数据集下可能性能下降 | 添加benchmark测试 |
| 无安全扫描测试 | SQL注入等安全问题 | 添加安全测试套件 |

## 测试最佳实践

### 单元测试原则

1. **单一职责**: 每个测试验证一个行为
2. **可读性**: 测试名称清晰描述被测功能
3. **独立性**: 测试之间无依赖
4. **快速**: 单元测试应毫秒级完成

### E2E测试原则

1. **真实性**: 使用真实数据和环境
2. **稳定性**: 添加适当的等待和重试
3. **可维护性**: 使用Page Object模式
4. **隔离性**: 每个测试清理自己的数据

### 测试数据管理

```typescript
// 使用TestApiClient fixture
import { createTestApi } from "./helpers";
import type { TestApiClient } from "./fixtures";

let api: TestApiClient;

test.beforeEach(async ({ page }) => {
  api = await createTestApi();
  await loginAsDefault(page);
});

test.afterEach(async () => {
  await api.cleanup();
});
```

### Go测试模式

```go
func TestIssue_Create(t *testing.T) {
    // 设置测试数据库fixture
    db := setupTestDB(t)
    defer db.Close()

    // 执行测试
    handler := NewIssueHandler(db)
    issue, err := handler.CreateIssue(context.Background(), &CreateIssueInput{...})

    // 断言
    require.NoError(t, err)
    require.NotNil(t, issue.ID)
}
```

## 证据

- `packages/*/vitest.config.ts` - Vitest配置
- `Makefile` - 测试命令
- `package.json` - npm scripts
- `packages/core/**/*.test.ts` - 单元测试示例
- `packages/views/**/*.test.tsx` - 组件测试示例
- `server/**/*_test.go` - Go测试示例
- `e2e/tests/` - E2E测试示例
- `CLAUDE.md` - 测试规则
- `CONTRIBUTING.md` - 测试工作流
