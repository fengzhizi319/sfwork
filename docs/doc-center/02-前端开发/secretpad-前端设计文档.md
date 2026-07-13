# SecretPad 前端设计文档

> 文档版本：基于当前仓库代码生成  
> 适用仓库：`/home/charles/code/secretpad/frontend-src`  
> 技术栈：React 18 + Umi 4 + Ant Design 5 + TypeScript 4.9 + Valtio + @antv/x6

---

## 1. 项目概述

SecretPad 前端是隐私计算平台的可视化操作界面，基于 React + Umi + Ant Design 构建，采用 **pnpm workspace + Nx** 的 monorepo 组织方式。核心能力包括：

- 用户登录与权限控制；
- 项目、节点、数据的管理；
- 可视化 DAG（有向无环图）建模与组件配置；
- 任务运行、状态监控、日志查看、结果展示；
- 周期任务、模型管理、模型提交；
- 消息通知、审批投票。


### 结构介绍

---
#### 2. React — UI 构建基石

React 是 Meta 开源的声明式 UI 库，核心概念包括：

- **组件化**：将界面拆分为独立、可复用的组件（如节点卡片、任务流程图、数据表格）
- **虚拟 DOM**：通过差异对比高效更新真实 DOM
- **Hooks**：`useState`、`useEffect` 等让函数组件拥有状态和生命周期能力
- **单向数据流**：数据自上而下传递，可预测性强

在 SecretPad 中，React 负责渲染复杂的隐私计算工作流编辑器、节点拓扑图、任务状态监控面板等交互界面。

---

#### 3. Umi — 企业级 React 应用框架

**Umi** 是蚂蚁集团开源的 React 应用框架，可以理解为"React 之上的脚手架和运行时"。

| 特性 | 说明 |
|------|------|
| **约定式路由** | 文件目录即路由，无需手动配置 |
| **插件化架构** | 内置状态管理、请求库、权限、国际化等，通过配置启用 |
| **编译时优化** | 基于 Webpack/Vite，自动做代码分割、Tree Shaking、按需加载 |
| **MFSU 极速编译** | 模块联邦速度提升，大型项目冷启动快 |
| **一体化方案** | 整合路由、构建、部署、测试，减少技术选型成本 |

SecretPad 选择 Umi 是因为隐私计算平台功能模块多（项目管理、节点管理、任务编排、结果查看），需要框架层面提供统一的路由管理、权限控制和构建优化。

---

#### 4. Ant Design — 企业级 UI 组件库

**Ant Design (AntD)** 同样是蚂蚁集团开源，是 React 生态中最成熟的企业级组件库。

SecretPad 中典型的使用场景：
- **表单**：数据资源配置表单、算法参数配置（使用 Form、Input、Select、Switch）
- **表格**：任务列表、数据表预览（Table 支持排序、筛选、分页）
- **可视化**：节点拓扑图（结合 Graphin 或自定义 Canvas）、任务执行流程（Steps、Timeline）
- **反馈**：任务状态变更的 Message/Notification、长时间任务的 Modal 进度展示
- **布局**：侧边导航菜单（Menu）、多标签页（Tabs）、折叠面板（Collapse）

AntD 的 Design Token 体系也便于 SecretPad 定制主题，匹配隐私计算平台的专业、安全视觉风格。

---

#### 5. pnpm workspace — Monorepo 包管理

**Monorepo** 指将多个相关项目/包放在同一个 Git 仓库中管理。SecretPad 可能包含：
- `apps/secretpad` — 主应用
- `packages/ui-components` — 共享组件库
- `packages/utils` — 通用工具函数
- `packages/sdk` — 隐私计算 API 封装

**pnpm workspace** 的优势：

| 对比点 | pnpm | npm/yarn |
|--------|------|----------|
| **磁盘效率** | 全局内容寻址存储，同版本依赖只存一份 | 每个项目 node_modules 重复安装 |
| **依赖严格** | 默认不允许访问未声明的依赖（防幽灵依赖） | 扁平化 node_modules 容易误引用 |
| **安装速度** | 硬链接机制，二次安装极快 | 相对较慢 |
| **Workspace 协议** | `workspace:*` 自动链接本地包，发布时替换为实际版本 | 需要额外配置 |

pnpm workspace 通过 `pnpm-workspace.yaml` 定义包含的包路径，配合 `pnpm -r` 命令实现跨包脚本执行。

---

#### 6. Nx — Monorepo 构建与任务调度

**Nx** 是 Nrwl 公司出品的 Monorepo 构建工具，专注于**任务编排**和**依赖图分析**。

核心能力：
- **依赖图分析**：自动解析包之间的依赖关系，构建有向无环图（DAG）
- **增量构建**：只构建受代码变更影响的包，而非全量构建
- **并行执行**：利用多核 CPU 并行运行无依赖关系的任务
- **本地缓存**：任务结果缓存到本地，未变更的输入直接复用缓存
- **远程缓存**（Nx Cloud）：团队共享构建缓存，CI 速度大幅提升

在 SecretPad 的 Monorepo 中，Nx 的典型工作流：
```
修改 packages/sdk 中的 API 接口
    ↓
Nx 分析依赖图：sdk → ui-components → secretpad
    ↓
只重新构建 sdk，然后 ui-components，最后 secretpad
    ↓
如果 utils 没改动，直接跳过
```

Nx 与 pnpm workspace 是**互补关系**：pnpm 管依赖安装和包链接，Nx 管构建任务调度和缓存。

---

#### 7. 技术选型的协同逻辑

这四者的组合形成了完整的工程化闭环：

```
React + Ant Design  →  负责"界面长什么样"（视图层）
Umi                 →  负责"应用怎么组织"（框架层）
pnpm workspace      →  负责"包怎么管理"（依赖层）
Nx                  →  负责"构建怎么提速"（构建层）
```

这种架构适合 SecretPad 的原因：
1. **复杂业务**：隐私计算涉及多方节点、多种算法、复杂权限，需要组件高度复用
2. **团队协作**：前后端、不同功能模块的开发者可以在同一仓库协作
3. **构建性能**：Monorepo 随规模增长构建会变慢，Nx 的增量构建和缓存是关键解药
4. **生态一致**：Umi、AntD 同属蚂蚁技术生态，与隐私计算场景（金融级安全要求）契合度高

---
### Nx介绍

#### 一、Nx 是什么

**Nx** 是由 Nrwl（现名 Nx）公司开发的开源构建系统，专门用于管理大型 Monorepo 中的**任务编排**、**依赖关系分析**和**构建优化**。它不仅仅是一个构建工具，而是一套完整的 Monorepo 治理方案。

> 核心理念：**"只构建和测试发生变化的部分"** —— 通过精确的依赖图分析，避免全量构建的浪费。

---

#### 二、核心架构与概念

##### 1. 项目图（Project Graph）

Nx 会自动解析仓库中所有项目（`project.json` 或 `package.json` 中定义）及其依赖关系，构建一个**有向无环图（DAG）**。

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   utils     │─────▶│  ui-shared  │─────▶│   secretpad │
│  (工具库)    │      │  (共享组件)  │      │  (主应用)    │
└─────────────┘      └─────────────┘      └─────────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │   sdk-api   │
                     │  (API封装)   │
                     └─────────────┘
```

- 每个节点是一个**可构建单元**（应用或库）
- 边表示**依赖关系**（import/require）
- Nx 通过 AST 解析代码，自动发现依赖，无需手动维护

##### 2. 任务（Task）与目标（Target）

每个项目可以定义多个**目标**（在 `project.json` 中配置）：

```json
{
  "name": "ui-shared",
  "targets": {
    "build": {
      "executor": "@nx/js:tsc",
      "outputs": ["{options.outputPath}"],
      "dependsOn": ["^build"]
    },
    "lint": {
      "executor": "@nx/linter:eslint"
    },
    "test": {
      "executor": "@nx/jest:jest"
    }
  }
}
```

**关键配置 `dependsOn: ["^build"]`**：
- `^` 表示**依赖项目的同名目标**必须先完成
- 即 `ui-shared` 构建前，其所有依赖（如 `utils`）必须先完成 `build`

##### 3. 任务管道（Task Pipeline）

Nx 在 `nx.json` 中定义全局任务顺序规则：

```json
{
  "targetDefaults": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["production", "^production"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["default", "^production"]
    }
  }
}
```

这表示：
- `build` 之前，所有依赖必须先 `build`
- `test` 之前，自身必须先 `build`

---

#### 三、核心能力详解

##### 1. 增量构建（Affected Commands）

Nx 通过 Git 对比，只构建**受代码变更影响**的项目：

```bash
# 对比当前分支与 main，只构建受影响的项目
nx affected -t build --base=main

# 只测试受影响的库
nx affected -t test --base=main --head=HEAD
```

**SecretPad 场景示例**：
```
你修改了 packages/sdk 的一个 API 类型定义
    ↓
Nx 分析：sdk 被 ui-shared 和 secretpad 依赖
    ↓
受影响项目：sdk → ui-shared → secretpad
    ↓
执行顺序：
  1. sdk:build
  2. ui-shared:build（等待 sdk 完成）
  3. secretpad:build（等待 ui-shared 完成）
  4. 其他无关项目（如 docs、playground）完全跳过
```

##### 2. 计算缓存（Computation Caching）

Nx 对任务结果进行缓存，缓存键由**输入**和**环境**决定：

```bash
# 本地缓存（默认 ~/.cache/nx）
nx build secretpad

# 第二次执行，如果输入文件未变，直接返回缓存结果
# 输出：>  NX   Existing outputs match the cache, left as is
```

**缓存输入定义**（`nx.json`）：

```json
{
  "namedInputs": {
    "default": ["{projectRoot}/**/*", "sharedGlobals"],
    "production": [
      "default",
      "!{projectRoot}/**/*.spec.ts",
      "!{projectRoot}/**/*.test.ts"
    ]
  }
}
```

- `production` 输入排除了测试文件，意味着**修改测试不会触发重新构建**
- 缓存包括：终端输出、产物文件、依赖图状态

##### 3. 分布式任务执行（Distributed Task Execution, DTE）

Nx Cloud 支持将任务分发到多台机器并行执行：

```bash
# 启动 Nx Cloud 代理，CI 中自动分发任务
nx affected -t build test lint --parallel=3 --dte
```

**执行流程**：
1. 主节点分析依赖图，确定任务拓扑
2. 将无依赖关系的任务并行分发到多个代理节点
3. 代理节点完成后上报结果
4. 主节点汇总，确保顺序正确

##### 4. 代码生成（Generators）

Nx 提供脚手架，快速创建标准化项目结构：

```bash
# 生成 React 库
nx g @nx/react:lib ui-components --directory=packages/ui-components

# 生成应用
nx g @nx/react:app secretpad --directory=apps/secretpad
```

生成的项目自动包含：
- 标准化的 `project.json` 配置
- 预设的 TypeScript、ESLint、Jest 配置
- 符合 Nx 依赖规范的导入路径

---

#### 四、Nx 在 SecretPad 中的典型配置

##### 目录结构

```
secretpad/
├── apps/
│   └── secretpad/          # 主应用
│       ├── src/
│       ├── project.json     # Nx 项目配置
│       └── package.json
├── packages/
│   ├── ui-components/      # 共享组件库
│   ├── sdk-api/            # 隐私计算 API 封装
│   └── utils/              # 通用工具
├── nx.json                 # Nx 全局配置
├── tsconfig.base.json       # 共享 TypeScript 配置
└── pnpm-workspace.yaml      # pnpm workspace 配置
```

##### `nx.json` 关键配置

```json
{
  "extends": "nx/presets/npm.json",
  "npmScope": "secretpad",
  "affected": {
    "defaultBase": "main"
  },
  "targetDefaults": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["production", "^production"],
      "cache": true
    },
    "lint": {
      "inputs": ["default", "{workspaceRoot}/.eslintrc.json"],
      "cache": true
    },
    "test": {
      "inputs": ["default", "^production", "{workspaceRoot}/jest.config.js"],
      "cache": true
    }
  },
  "parallel": 4,
  "plugins": [
    "@nx/js",
    "@nx/react",
    "@nx/jest"
  ]
}
```

##### `project.json` 示例（ui-components）

```json
{
  "name": "ui-components",
  "$schema": "../../node_modules/nx/schemas/project-schema.json",
  "sourceRoot": "packages/ui-components/src",
  "projectType": "library",
  "targets": {
    "build": {
      "executor": "@nx/js:tsc",
      "outputs": ["{options.outputPath}"],
      "options": {
        "outputPath": "dist/packages/ui-components",
        "main": "packages/ui-components/src/index.ts",
        "tsConfig": "packages/ui-components/tsconfig.lib.json",
        "assets": ["packages/ui-components/*.md"]
      }
    },
    "lint": {
      "executor": "@nx/linter:eslint",
      "outputs": ["{options.outputFile}"],
      "options": {
        "lintFilePatterns": ["packages/ui-components/**/*.ts"]
      }
    },
    "test": {
      "executor": "@nx/jest:jest",
      "outputs": ["{workspaceRoot}/coverage/packages/ui-components"],
      "options": {
        "jestConfig": "packages/ui-components/jest.config.ts"
      }
    }
  },
  "tags": ["scope:shared", "type:ui"]
}
```

---

#### 五、Nx vs 其他工具

| 维度 | Nx | Turborepo | Rush | pnpm workspace |
|------|-----|-----------|------|----------------|
| **定位** | 完整 Monorepo 平台 | 构建编排（Vercel） | 企业级包管理（微软） | 包管理 + workspace |
| **依赖图** | ✅ 自动 AST 解析 | ✅ 需手动配置 pipeline | ✅ 手动配置 | ❌ 无 |
| **增量构建** | ✅ affected | ✅ filtered | ✅ 支持 | ❌ 无 |
| **缓存** | ✅ 本地 + 远程 | ✅ 本地 + Vercel Remote | ✅ 本地 | ❌ 无 |
| **分布式执行** | ✅ Nx Cloud | ✅ Vercel | ❌ | ❌ |
| **代码生成** | ✅ 丰富 generators | ❌ 无 | ❌ 无 | ❌ 无 |
| **框架集成** | ✅ React/Vue/Node 深度集成 | ⚠️ 通用，需配置 | ⚠️ 通用 | ❌ 无 |

**SecretPad 的选择逻辑**：
- 用 **pnpm workspace** 管理依赖安装和包链接
- 用 **Nx** 接管构建、测试、缓存和任务编排
- 两者互补：pnpm 解决"装什么"，Nx 解决"怎么建"

---

#### 六、高级特性

##### 1. 项目标签与约束（Tags & Constraints）

防止架构腐化，限制包之间的依赖方向：

```json
// nx.json
{
  "implicitDependencies": {
    "ui-components": {
      "tags": ["scope:shared", "type:ui"]
    },
    "secretpad": {
      "tags": ["scope:app", "type:app"]
    }
  },
  "nxCloudAccessToken": "..."
}
```

配合 ESLint 规则，禁止应用层直接依赖基础设施层。

##### 2. 运行时缓存分析

```bash
# 查看任务为什么命中/未命中缓存
nx build secretpad --skip-nx-cache    # 跳过缓存，强制构建
nx print-affected --target=build       # 打印受影响项目列表
nx graph                               # 启动可视化依赖图浏览器
```

##### 3. 自定义 Executor

如果 SecretPad 需要自定义构建步骤（如隐私计算协议的代码生成），可以开发自己的 Executor：

```typescript
// tools/executors/custom-build/executor.ts
import { ExecutorContext } from '@nx/devkit';

export default async function runExecutor(
  options: { protocol: string },
  context: ExecutorContext
) {
  // 自定义逻辑：调用隐私计算协议编译器
  await generateProtocolBindings(options.protocol);
  return { success: true };
}
```

---

#### 七、总结

Nx 在 SecretPad 这类复杂前端 Monorepo 中的核心价值：它把"构建系统"提升到了"工程治理平台"的高度，让 Monorepo 在规模扩大时依然保持高效和可控。

| 痛点 | Nx 解法 |
|------|---------|
| 构建慢 | 增量构建 + 并行执行 + 缓存 |
| 依赖混乱 | 自动依赖图 + 可视化 + 约束规则 |
| 配置重复 | 标准化 Generators + 共享配置 |
| CI 耗时 | 远程缓存 + 分布式任务执行 |
| 团队协作 | 一致的开发工作流 + 代码生成规范 |


---
它把"构建系统"提升到了"工程治理平台"的高度，让 Monorepo 在规模扩大时依然保持高效和可控。
## 2. 系统架构

### 2.1 Monorepo 结构

```
frontend-src/
├── apps/
│   ├── platform/          # 主应用：SecretPad Web（Umi 4 + React 18 + Ant Design 5）
│   └── docs/              # 静态文档站点（Dumi 2）
├── packages/
│   ├── dag/               # 可复用 DAG 图编辑器包
│   └── utils/             # 共享工具库（Registry、Emitter、Future）
├── tooling/
│   ├── eslint/            # @secretflow/config-eslint
│   ├── stylelint/         # @secretflow/config-stylelint
│   ├── tsconfig/          # @secretflow/config-tsconfig
│   ├── tsup/              # @secretflow/config-tsup
│   └── jest/              # @secretflow/testing
├── package.json           # 根脚本 + Nx 编排
├── pnpm-workspace.yaml    # pnpm 工作区声明
├── nx.json                # Nx 任务图与缓存配置
├── .husky/                # Git hooks
└── .lintstagedrc.js       # lint-staged 配置
```

### 2.2 包管理器与构建编排

| 工具 | 说明 |
|------|------|
| **pnpm** | `pnpm@8.8.0`，通过 `only-allow pnpm` 强制使用 |
| **Nx** | 任务编排与缓存，任务依赖：`setup → ^setup`、`build → ^build` |
| **tsup** | packages 构建工具，输出 ESM + CJS + TypeScript 声明 |
| **Umi** | 主应用构建与开发框架 |

### 2.3 Nx 任务流水线

```json
{
  "tasksRunnerOptions": {
    "default": { "options": { "cacheableOperations": ["setup", "build", "lint", "lint:*"] } }
  },
  "targetDefaults": {
    "setup": { "dependsOn": ["^setup"] },
    "build": { "dependsOn": ["^build"] }
  }
}
```

根脚本：

| 脚本 | 说明 |
|------|------|
| `pnpm bootstrap` | 安装依赖并 setup |
| `pnpm dev` | 并行启动所有非 demo 应用的 dev |
| `pnpm build` | 构建所有应用/包 |
| `pnpm lint` | 全量 lint |
| `pnpm ci` | affected lint（js/css/format） |
| `pnpm test` | 全量测试 |

---

## 3. 代码架构

### 3.1 主应用目录结构

```
apps/platform/src/
├── app.ts                         # 全局运行时配置：umi-request 拦截器
├── platform.config.tsx            # 品牌/主题配置
├── global.less                    # 全局样式重置
├── access.ts                      # 权限访问控制配置
│
├── pages/                         # Umi 约定式路由入口（薄封装）
│   ├── index.tsx                  # / 首页
│   ├── dag.tsx                    # /dag
│   ├── login.tsx                  # /login
│   └── ...
│
├── modules/                       # 按功能模块组织，每个模块包含 view/service/model
│   ├── layout/                    # 布局
│   ├── login/                     # 登录
│   ├── new-home/                  # 首页
│   ├── project-list/              # 项目列表
│   ├── create-project/            # 创建项目
│   ├── main-dag/                  # DAG 主编辑器
│   ├── dag-record/                # 只读记录 DAG
│   ├── dag-submit/                # 提交 DAG
│   ├── component-tree/            # 左侧组件面板
│   ├── component-config/          # 右侧组件配置抽屉
│   ├── dag-result/                # 结果展示
│   ├── dag-log/                   # 日志查看
│   ├── pipeline/                  # 流水线列表/模板
│   ├── node/                      # 节点管理
│   ├── my-node/                   # 我的节点
│   ├── data-manager/              # 数据管理
│   ├── data-table-add/            # 新增数据表
│   ├── message/                   # 消息中心
│   ├── model-submission/          # 模型提交
│   ├── periodic-task-detail/      # 周期任务详情
│   └── ...
│
├── components/                    # 共享 UI 组件
│   ├── monaco-editor/             # Monaco 编辑器封装
│   ├── popover-copy/              # 复制气泡
│   ├── platform-wrapper.tsx       # 平台/模式访问控制
│   ├── vote-insts-graph/          # 机构投票图
│   └── ...
│
├── services/secretpad/            # 自动生成的后端 API 客户端
│   ├── index.ts                   # 导出所有控制器
│   ├── typings.d.ts               # 所有 API TypeScript 类型（2600+ 行）
│   ├── GraphController.ts
│   ├── ProjectController.ts
│   ├── AuthController.ts
│   └── ...（共 28+ 个控制器）
│
├── util/                          # 工具与状态管理基础
│   ├── valtio-helper.ts           # Model 基类、useModel/getModel
│   ├── command.ts                 # CommandRegistry
│   └── ...
│
├── wrappers/                      # 路由守卫/包装器
│   ├── theme-wrapper.tsx          # Antd ConfigProvider + 主题
│   ├── login-auth.tsx             # 登录态校验
│   ├── login-wrapper.tsx          # 登录页包装
│   ├── center-auth.tsx            # 中心端权限
│   ├── p2p-center-auth.tsx        # P2P/中心端权限
│   ├── edge-auth.tsx              # 边缘端权限
│   ├── basic-node-auth.tsx        # 基础节点权限
│   ├── guide-auth.tsx             # 引导页权限
│   └── component-wrapper.tsx      # 组件级包装
│
└── assets/                        # SVG、图片、动效资源
```

### 3.2 路由架构

路由集中定义在 `apps/platform/config/routes.ts`：

```ts
export const routes = [
  {
    path: '/',
    wrappers: ['@/wrappers/theme-wrapper', '@/wrappers/login-auth'],
    component: '@/modules/layout/layout.view',
    routes: [
      { path: '/', component: 'new-home', wrappers: ['@/wrappers/center-auth'] },
      { path: '/home', component: 'new-home', wrappers: ['@/wrappers/center-auth'] },
      { path: '/dag', component: 'dag', wrappers: ['@/wrappers/p2p-center-auth', '@/wrappers/component-wrapper'] },
      { path: '/record', component: 'record', wrappers: ['@/wrappers/p2p-center-auth', '@/wrappers/component-wrapper'] },
      { path: '/model-submission', component: 'model-submission', wrappers: ['@/wrappers/p2p-center-auth', '@/wrappers/component-wrapper'] },
      { path: '/periodic-task-detail', component: 'periodic-task-detail', wrappers: ['@/wrappers/p2p-center-auth', '@/wrappers/component-wrapper'] },
      { path: '/node', component: 'new-node', wrappers: ['@/wrappers/edge-auth', '@/wrappers/component-wrapper'] },
      { path: '/my-node', component: 'my-node', wrappers: ['@/wrappers/basic-node-auth', '@/wrappers/p2p-edge-center-auth'] },
      { path: '/message', component: 'message', wrappers: ['@/wrappers/basic-node-auth', '@/wrappers/p2p-edge-center-auth', '@/wrappers/component-wrapper'] },
      { path: '/edge', component: 'edge', wrappers: ['@/wrappers/basic-node-auth', '@/wrappers/p2p-login-auth'] },
      { path: '/*', redirect: '/login' },
    ],
  },
  {
    path: '/',
    wrappers: ['@/wrappers/theme-wrapper', '@/wrappers/login-auth', '@/wrappers/guide-auth'],
    component: '@/modules/layout/layout.view',
    routes: [{ path: '/guide', component: 'guide' }],
  },
  {
    path: '/login',
    wrappers: ['@/wrappers/theme-wrapper', '@/wrappers/login-wrapper'],
    component: 'login',
  },
];
```

**路由包装器职责**：

| 包装器 | 职责 |
|--------|------|
| `theme-wrapper` | 注入 Antd `ConfigProvider`、主题 token、`zh_CN` 语言包 |
| `login-auth` | 校验 `User-Token` 与 `neverLogined`，未登录跳转 `/login` |
| `login-wrapper` | 登录页专用包装 |
| `center-auth` | 仅中心端可访问 |
| `p2p-center-auth` | P2P 或中心端可访问 |
| `edge-auth` | 仅边缘端可访问 |
| `basic-node-auth` | 基础节点权限 |
| `guide-auth` | 引导流程权限 |
| `component-wrapper` | 通用组件包装 |

---

## 4. 技术栈

| 类别 | 技术 | 版本 | 说明 |
|------|------|------|------|
| 框架 | React | 18.x | UI 框架 |
| 应用框架 | Umi | 4.0.64+ | 路由、构建、请求、约定式目录 |
| 组件库 | Ant Design | 5.20.5 | UI 组件 |
| 语言 | TypeScript | 4.9.5 | 类型安全 |
| 状态管理 | Valtio | 1.10.7 | Proxy 驱动响应式 |
| 图引擎 | @antv/x6 | 2.11.1 | DAG 渲染 |
| 图插件 | x6-plugin-keyboard / x6-plugin-selection / x6-react-shape | — | 键盘、框选、React 节点 |
| 表格 | @antv/s2 / s2-react | 1.52 / 1.44 | 多维表格 |
| 图表 | @antv/g2 | 4.2.9 | 可视化图表 |
| 图布局 | @antv/layout | 0.3.23 | 自动布局 |
| Hooks 库 | ahooks | 3.7.8 | 通用 React Hooks |
| 编辑器 | monaco-editor | 0.41.0 | 日志/代码编辑器 |
| 密码加密 | crypto-js | 4.1.1 | SHA-256 |
| 日期 | dayjs | 1.11.8 | — |
| 工具 | lodash | 4.17.21 | — |
| 路由请求 | umi-request | 1.4.0 | 基于 fetch 的请求库 |
| 样式 | Less + CSS Modules | — | 模块级样式 |
| 构建 | Umi + tsup + Nx | — | 应用/包分别构建 |
| 代码规范 | ESLint + Prettier + Stylelint + Husky + lint-staged | — | — |
| 测试 | Jest | 29.5.0 | `@secretflow/testing` |

---

## 5. 状态管理

### 5.1 Valtio 模型模式

前端每个功能模块通常包含：

- `xxx.view.tsx`：React 视图组件；
- `xxx.service.ts`：服务层（API 调用 + 局部状态）；
- `xxx.model.ts`（可选）：更重的状态模型。

基础工具：`src/util/valtio-helper.ts`

```ts
class Model {
  constructor() {
    return proxy(this);
  }
}

const getModel = <T>(model: new () => T): T => { ... };
const useModel = <T>(model: new () => T): T => { ... };
```

- `Model` 基类将实例转为 Valtio `proxy`；
- `getModel(Class)` 返回单例，存储在 `WeakMap` 中；
- `useModel(Class)` 在组件中使用 `useSnapshot` 订阅变化。

### 5.2 典型数据流

```
用户操作
   │
   ▼
View Component
   │
   ▼
Service / Model (Valtio proxy)
   │
   ▼
services/secretpad/Controller.ts
   │
   ▼
umi-request (拦截器注入 token/trace-id)
   │
   ▼
SecretPad Backend (/api/v1alpha1/...)
```

---

## 6. 核心功能模块

### 6.1 登录与认证

- **入口**：`src/modules/login/index.tsx`
- **表单**：`src/modules/login/component/login-form/index.tsx`
- **服务**：`src/modules/login/login.service.ts`
- **流程**：
  1. 用户输入账号密码；
  2. `LoginService.login` 使用 `crypto-js/sha256` 对密码哈希；
  3. 调用 `API.AuthController.login`；
  4. 存储 `User-Token` 与 `userInfo` 到 localStorage / Valtio；
  5. 根据平台类型（`CENTER`、`EDGE`、`AUTONOMY`）跳转对应首页。

### 6.2 项目管理

- **列表**：`src/modules/project-list/`
- **创建**：`src/modules/create-project/`
- **能力**：项目列表、搜索、过滤、创建/编辑/删除、进入 DAG、计算模式徽章（`MPC` / `TEE`）。

### 6.3 节点管理

- **入口**：`src/modules/node/`
- **我的节点**：`src/modules/my-node/`
- **引导节点**：`src/modules/guide-node/`
- **能力**：节点列表、当前节点选择、数据/结果 Tab、Token 刷新。

### 6.4 数据管理

- **入口**：`src/modules/data-manager/`
- **能力**：数据表列表、数据源类型（OSS / HTTP / LOCAL / ODPS / MySQL）、授权项目、加密上传 TEE、状态刷新。
- **子模块**：`data-table-add`、`data-table-info`、`data-table-tree`。

### 6.5 DAG / 流水线编辑器

这是最复杂的核心功能，代码分布在 `@secretflow/dag` 包与 `apps/platform/src/modules` 中。

#### 6.5.1 平台侧模块

| 模块 | 职责 |
|------|------|
| `main-dag/` | 完整 DAG 编辑器 |
| `dag-record/` | 只读记录 DAG |
| `dag-submit/` | 提交 DAG |
| `component-tree/` | 左侧可拖拽组件面板 |
| `component-config/` | 右侧组件配置抽屉/表单 |
| `dag-result/` | 结果/报告展示 |
| `dag-log/` | Monaco 日志查看器 |
| `pipeline/` | 流水线列表、创建、模板、复制/删除/重命名 |
| `dag-modal-manager/` | 集中管理抽屉/弹窗状态 |

#### 6.5.2 MainDag 架构

```
MainDag extends DAG
├── dataService: GraphDataService      # 节点/边内存 CRUD + saveDag
├── requestService: GraphRequestService # 图相关 API 调用
└── hookService: GraphHookService       # 创建端口/结果钩子
```

关键文件：

- `src/modules/main-dag/dag.ts`：`MainDag extends DAG`
- `src/modules/main-dag/graph.tsx`：React 组件，按 `dagId` + `mode` 初始化图
- `src/modules/main-dag/graph-service.ts`：节点点击、边连接、结果点击、保存配置、粘贴、自定义组件逻辑
- `src/modules/main-dag/graph-request-service.tsx`：图 CRUD、状态、运行/停止/继续、节点输出、日志
- `src/modules/main-dag/toolbar.tsx`、`toolbutton.tsx`：画布工具栏

#### 6.5.3 @secretflow/dag 包架构

```
packages/dag/src/
├── index.ts              # DAG 类门面 + 重新导出
├── protocol.ts           # DAGProtocol 接口
├── context.ts            # DAGContext 基类
├── manager/
│   └── graph-manager.ts  # DefaultGraphManager：X6 初始化、插件、事件、动作
├── data/
│   └── data-service.ts   # 节点/边内存 CRUD + saveDag
├── request/
│   └── request.ts        # DefaultRequestService（可扩展）
├── hooks/
│   └── hooks.ts          # createPort / createResult 钩子
├── actions/              # ~25 个图动作（add-node、add-edge、run-all 等）
├── shapes/               # 节点/边 React 形状 + 样式
├── vis/                  # 结果可视化组件
└── types/                # GraphNode、GraphEdge、NodeStatus 等
```

**核心设计模式**：

- **ActionHub**：命令注册表，按 `ActionType` 注册动作；
- **EventHub**：事件注册表，注册图事件处理器；
- **DefaultGraphManager.executeAction(...)**：统一分发动作。

### 6.6 任务执行与结果

- **执行 API**：`GraphController.ts` 提供 `startGraph`、`stopGraphNode`、`listGraphNodeStatus`；
- **状态轮询**：`GraphRequestService.queryStatus` 将后端状态映射为 `NodeStatus`；
- **进度支持**：`sgb_train`、`ss_glm_train`、`ss_xgb_train`、`ss_sgd_train` 等训练节点支持进度；
- **结果可视化**：`CorrMatrix`、`GroupPivotTable`、`PVAChart`、`OutputTable`、`RegressionTable` 等。

### 6.7 周期任务

- **模块**：`src/modules/periodic-task-detail/`
- **后端控制器**：`ScheduledController`
- **能力**：周期任务创建、详情、历史实例查看。

### 6.8 模型管理

- **模型管理**：`src/modules/model-management/`
- **模型提交**：`src/modules/model-submission/`
- **后端控制器**：`ModelManagementController`、`ModelExportController`

---

## 7. 组件设计

### 7.1 共享 UI 组件

位于 `apps/platform/src/components/`：

| 组件 | 用途 |
|------|------|
| `monaco-editor/` | Monaco 编辑器封装 |
| `popover-copy/` | 复制到剪贴板气泡 |
| `react-hight-lighter/` | 语法高亮 |
| `switch-card/` | 卡片切换器 |
| `text-ellipsis.tsx` | 文本截断 |
| `vote-insts-graph/` | 机构投票关系图 |
| `platform-wrapper.tsx` | 平台/模式访问控制工具（`hasAccess`、`AccessWrapper`、`PadMode`、`Platform`） |
| `edge-wrapper-auth.tsx` | 边缘端权限包装 |
| `comfirm-delete.tsx` | 删除确认 |
| `table-column-search.tsx` | 表格列搜索 |

### 7.2 平台/模式访问控制

```ts
// platform-wrapper.tsx
enum Platform { CENTER, EDGE, AUTONOMY }
enum PadMode { TEE, MPC, ALL_IN_ONE }

function hasAccess({ type, mode }: AccessOptions): boolean;
function AccessWrapper({ children, ...access }: AccessProps): ReactElement;
```

### 7.3 自定义 Hooks

- `src/util/valtio-helper.ts`：`useModel` / `getModel`；
- `ahooks` 广泛使用，例如 `useSize`（在 `graph.tsx` 中监听容器尺寸）；
- 各模块内自定义 hooks，如 `src/modules/dag-model-submission/hooks.ts`。

---

## 8. API 集成

### 8.1 请求层

全局请求配置：`src/app.ts`

```ts
// 请求拦截器
request.interceptors.request.use((url, options) => {
  options.headers['User-Token'] = localStorage.getItem('User-Token');
  options.headers['Trace-Id'] = uuid();
  options.headers['Content-Type'] = 'application/json';
  options.credentials = 'include';
  return { url, options };
});

// 响应拦截器
request.interceptors.response.use((response) => {
  const { status } = await response.clone().json();
  if (status.code === '202011602') {
    history.push('/login');
  }
  return response;
});
```

### 8.2 自动生成的 API 客户端

- 目录：`src/services/secretpad/`
- 入口：`index.ts` 聚合所有控制器
- 类型：`typings.d.ts`，包含 `API.*` 命名空间下所有类型定义（2600+ 行）
- 生成工具：`@umijs/openapi`，配置 `config/openapi.config.js`
- 当前配置示例指向 PetStore，生产环境通常使用后端 OpenAPI 或 OneAPI 生成

### 8.3 主要控制器

| 控制器 | 后端端点 |
|--------|----------|
| `AuthController` | `/api/login`、`/api/logout` |
| `UserController` | 用户信息 |
| `ProjectController` | 项目 CRUD、任务 |
| `GraphController` | 图 CRUD、组件、运行/停止/状态/日志/输出 |
| `DatatableController` | 数据表 CRUD |
| `NodeController` / `P2pNodeController` | 节点管理 |
| `MessageController` / `VoteSyncController` / `ApprovalController` | 消息/投票/审批 |
| `ModelManagementController` / `ModelExportController` | 模型管理/导出 |
| `ScheduledController` | 周期任务 |
| `CloudLogController` | 日志参与方 |

### 8.4 通信方式

- **HTTP REST**：所有后端通信均通过 `umi-request`；
- **无 WebSocket / SSE / EventSource**：日志与任务状态使用轮询（约 2 秒间隔）；
- **无 protobuf / gRPC-Web**：前端不直接调用 gRPC。

---

## 9. 样式与主题

### 9.1 样式方案

- **主要方案**：Less + CSS Modules
- **使用方式**：`import styles from './index.less';`
- 约 114 个 `.less` 文件；
- 无 Tailwind / CSS-in-JS / styled-components。

### 9.2 全局样式

- `src/global.less`：CSS reset、Antd Drawer 关闭按钮覆盖、`#root` 最小宽度 1024px。

### 9.3 主题配置

`src/platform.config.tsx`：

```ts
export const platformConfig = {
  color: '#0068fa',
  logo: '...',
  slogan: '...',
  guide: true,
};
```

`theme-wrapper.tsx` 注入 Antd `ConfigProvider`：

```tsx
<ConfigProvider
  locale={zh_CN}
  theme={{
    token: { colorPrimary: '#0068fa' },
    components: { ... },
  }}
>
```

### 9.4 图标

- Ant Design Icons：`@ant-design/icons`；
- SVG：大量 SVG 资源，Umi SVGR 支持直接作为 React 组件导入。

---

## 10. DAG 包设计详解

### 10.1 核心类

```ts
// packages/dag/src/index.ts
class DAG {
  ActionHub: Registry<(...args: any[]) => any>;
  EventHub: Registry<(...args: any[]) => any>;
  graphManager: DefaultGraphManager;
  dataService: DataService;
  requestService: RequestService;
  hookService: HookService;
}
```

### 10.2 GraphManager

`DefaultGraphManager` 负责：

- 初始化 `@antv/x6` 图实例；
- 注册键盘插件（`x6-plugin-keyboard`）；
- 注册框选插件（`x6-plugin-selection`）；
- 绑定节点/边/画布事件；
- 执行 `ActionHub` 中的动作。

### 10.3 动作系统

`packages/dag/src/actions/` 包含约 25 个动作，例如：

- `add-node`：添加组件节点；
- `add-edge`：连接节点；
- `delete-node` / `delete-edge`；
- `run-all` / `run-selected`；
- `stop` / `continue`；
- `save`：保存图；
- `zoom-in` / `zoom-out` / `fit`；
- `undo` / `redo`。

### 10.4 数据服务

`DataService` 维护内存中的节点/边模型，提供：

- `addNode`、`updateNode`、`removeNode`；
- `addEdge`、`removeEdge`；
- `getNodes`、`getEdges`；
- `saveDag`：将当前内存状态持久化到后端。

### 10.5 形状与样式

`packages/dag/src/shapes/`：

- 节点 React 形状；
- 边样式（虚线/实线、动画、状态色）；
- 端口（port）定义。

### 10.6 可视化

`packages/dag/src/vis/`：

- 结果表格、图表、回归结果、相关矩阵等组件。

---

## 11. 组件配置表单

### 11.1 配置流程

```
Backend Component Spec
        │
        ▼
ComponentConfigRegistry
        │
        ▼
DefaultComponentConfigService.getComponentConfig()
        │
        ▼
ConfigFormComponent (Antd Form)
        │
        ├─► ConfigRenderRegistry ──► 字段渲染器
        │
        ├─► customSerializerRegistry ──► protobuf 类型序列化
        │
        ▼
    onSaveConfig()
        │
        ▼
   updateGraphNode API
```

### 11.2 关键文件

- `src/modules/component-config/config-form-view.tsx`：配置表单主组件；
- `src/modules/component-config/component-config-service.ts`：将组件 spec 树扁平化为原子配置节点；
- `ConfigRenderRegistry`：根据字段类型渲染不同 Antd 表单项；
- `customSerializerRegistry`：处理 protobuf 风格的复杂类型。

---

## 12. 构建与工程化

### 12.1 Umi 配置

`apps/platform/config/config.ts` 核心配置：

```ts
export default defineConfig({
  routes,
  npmClient: 'pnpm',
  svgr: {},
  title: '隐语开放平台',
  favicons: ['/favicon.ico'],
  extraBabelPlugins: [
    'babel-plugin-transform-typescript-metadata',
    'babel-plugin-parameter-decorator',
  ],
  mfsu: false,
  codeSplitting: { jsStrategy: 'granularChunks' },
  esbuildMinifyIIFE: true,
  proxy: { '/api': { target: PROXY_URL, changeOrigin: true } },
});
```

### 12.2 开发代理

开发时需在 `apps/platform/.env` 中配置：

```
PROXY_URL=http://localhost:8080
```

所有 `/api` 请求会代理到后端服务。

### 12.3 Lint / Format

| 工具 | 配置 |
|------|------|
| ESLint | 根 `.eslintrc.js` 扩展 `@secretflow/config-eslint`（推荐 + TS + React + Prettier + import/order + react-hooks） |
| Prettier | `.prettierrc.js`：printWidth 88、singleQuote、trailingComma all、proseWrap always |
| Stylelint | `.stylelintrc.js` 扩展 `@secretflow/config-stylelint` |
| Husky | `.husky/` + `lint-staged` |

### 12.4 TypeScript

- 共享配置：`tooling/tsconfig/tsconfig.json`
- 应用配置：`apps/platform/tsconfig.json`
- Umi 生成：`src/.umi/tsconfig.json`，路径别名 `@/*` → `src/*`，`@@/*` → `src/.umi/*`

### 12.5 CI

- **GitHub Actions**：`.github/workflows/ci.yml`
  - Node 16.x、pnpm ^8.8、`pnpm install --ignore-scripts`、Nx affected lint
- **CircleCI**：`.circleci/config.yml`
  - cimg/node:lts-browsers、pnpm 8.8、`pnpm run ci`

---

## 13. 关键设计模式

| 模式 | 使用场景 |
|------|----------|
| **Model-View-Service + Valtio** | 每个功能模块包含 `View`、`Service`、`Model`，通过 `useModel` / `getModel` 管理状态 |
| **Registry 注册表** | `packages/utils/src/registry.ts` 用于 DAG Action、Event、组件配置、字段渲染器、命令注册 |
| **Emitter 发布订阅** | `packages/utils/src/emitter.ts` 用于跨模块通信（组件拖拽、配置保存、流水线变更、节点状态变更） |
| **Command 命令** | `src/util/command.ts` 的 `CommandRegistry` 管理流水线命令（复制/删除/重命名/创建） |
| **DAG Facade + 服务注入** | `DAG` 类组合 `RequestService`、`HookService`、`DataService`、`GraphManager`；平台子类注入自定义实现 |
| **组件配置模型驱动** | 后端组件 spec 驱动 Antd 表单渲染，支持自定义渲染器和序列化器 |
| **平台/部署模式抽象** | `Platform`（CENTER/EDGE/AUTONOMY）与 `PadMode`（TEE/MPC/ALL_IN_ONE）控制访问 |
| **Modal Manager** | `dag-modal-manager` 集中管理抽屉/弹窗状态 |

---

## 14. 数据流总览

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser (React 18)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │    Routes    │  │   Wrappers   │  │  Layout / Modules     │  │
│  │  routes.ts   │  │ login-auth   │  │ project-list, dag,    │  │
│  │              │  │ center-auth  │  │ data-manager, etc.    │  │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬───────────┘  │
│         └─────────────────┴──────────────────────┘              │
│                            │                                     │
│                Valtio Models (useModel / getModel)              │
│                            │                                     │
│                Services (API calls + local state)               │
│                            │                                     │
│                umi-request interceptors                         │
│                            │                                     │
│           ┌────────────────┼────────────────┐                   │
│           ▼                ▼                ▼                   │
│     /api/login       /api/v1alpha1/...     localStorage         │
│           │                │                                    │
│           └────────────────┴────────────────► SecretPad Backend │
└─────────────────────────────────────────────────────────────────┘
```

### DAG 内部数据流

```
┌──────────────────────────────────────────────────┐
│                      DAG                          │
│  ┌─────────────┐  ┌────────────────────────────┐ │
│  │  ActionHub  │  │        EventHub            │ │
│  │  (Registry) │  │       (Registry)           │ │
│  └──────┬──────┘  └─────────────┬──────────────┘ │
│         │                       │                │
│  ┌──────▼──────┐  ┌─────────────▼─────────────┐  │
│  │GraphManager │  │  RequestService            │  │
│  │  (@antv/x6) │  │  DataService               │  │
│  │  Keyboard   │  │  HookService               │  │
│  │  Selection  │  │                            │  │
│  └──────┬──────┘  └─────────────┬──────────────┘  │
│         │                       │                 │
│         └──────────┬────────────┘                 │
│                    ▼                              │
│            X6 Graph Canvas                        │
└──────────────────────────────────────────────────┘
```

---

## 15. 国际化

- 前端 UI 以中文为主，硬编码在组件中；
- Antd 语言包设置为 `zh_CN`；
- 组件元数据（名称、描述、参数说明）的翻译来自后端接口 `listComponentI18n`；
- 翻译映射键格式：`${domain}/${name}:${version}`，区分 MPC / TEE 模式。

---

## 16. 注意事项

- **无微前端运行时**：通过 pnpm workspace + Nx 共享包；
- **MFSU 已禁用**：`mfsu: false`，避免复杂依赖兼容问题；
- **代码分割启用**：`granularChunks` 策略优化首屏加载；
- **测试暂未纳入 CI**：`pnpm ci` 只运行 lint；
- **OpenAPI 生成器占位**：当前 openapi.config.js 使用 PetStore 示例，生产可能使用后端 Spec 或 OneAPI；
- **轮询而非 WebSocket**：日志与任务状态通过定时轮询获取。

---

## 17. 总结

SecretPad 前端采用 **Monorepo + Umi + React + Valtio + @antv/x6** 的现代化前端架构：

1. **Monorepo**：`apps/platform` 主应用 + `packages/dag` 可复用图编辑器 + `packages/utils` 工具库；
2. **状态管理**：Valtio 代理模式实现轻量、响应式、模块级状态；
3. **路由权限**：Umi wrappers 实现登录态、平台角色、部署模式多级访问控制；
4. **可视化核心**：`@secretflow/dag` 包通过 ActionHub / EventHub / GraphManager 提供可扩展的 DAG 编辑能力；
5. **组件配置**：后端组件 spec 驱动表单渲染，支持自定义字段和序列化；
6. **工程化**：pnpm + Nx + ESLint + Prettier + Stylelint + Husky 保证代码质量与构建效率；
7. **后端集成**：HTTP REST + 自动生成的 TypeScript API 客户端 + umi-request 拦截器。

整体设计兼顾了隐私计算场景下的复杂 DAG 交互需求与多平台部署（CENTER/EDGE/AUTONOMY、MPC/TEE）的访问控制需求。
