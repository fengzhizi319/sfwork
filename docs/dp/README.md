# 本地隐私保护原语（DP / K-匿名 / 脱敏 / 查询混淆）扩展设计文档

> 本文档基于 `docs/algorithm/匿名脱敏等本地隐私保护原语与实现方案V1.md`，针对“操作对象”与“隐私处理参数”两个核心实现问题，输出可指导研发落地的方案、产品与代码建议。

## 文档清单

| 文件 | 内容 |
|---|---|
| [01-扩展设计方案](./01-design-scheme.md) | 操作对象抽象、批量/本地双模架构、参数配置与治理方案 |
| [02-产品需求文档](./02-product-requirements.md) | 用户场景、功能需求、交互设计、非功能性需求 |
| [03-代码实现建议](./03-implementation-suggestions.md) | 目录结构、核心接口、本地 SDK、REST/gRPC 封装、参数解析示例 |

## 本地 SDK / Agent 项目

为支持 Java/Go 后端直接调用以及多语言 Sidecar 场景，这三个项目已拆分为独立仓库维护，不再纳入 sfwork 根仓库：

| 项目 | 语言 | 形态 | 仓库地址 |
|---|---|---|---|
| privacy-java-sdk | Java | 本地 SDK（函数库） | [fengzhizi319/privacy-java-sdk](https://github.com/fengzhizi319/privacy-java-sdk) |
| privacy-go-sdk | Go | 本地 SDK（Go module） | [fengzhizi319/privacy-go-sdk](https://github.com/fengzhizi319/privacy-go-sdk) |
| privacy-local-agent | Python | REST + gRPC Sidecar | [fengzhizi319/privacy-local-agent](https://github.com/fengzhizi319/privacy-local-agent) |

## 选型差异

| 维度 | Java / Go 本地 SDK | Python 本地 Agent |
|---|---|---|
| 部署方式 | 作为依赖直接引入业务进程 | 独立进程 / Sidecar / 容器 |
| 网络开销 | 无 | REST/gRPC 本机或局域网调用 |
| 适用语言 | Java、Go | 任意支持 HTTP/gRPC 的语言 |
| 并发模型 | 由业务进程线程模型决定 | 独立线程池、连接池、可单独限流 |
| 隐私预算台账 | 与业务进程共享命名空间 | 独立命名空间，可多客户端共享 |
| 推荐场景 | 同语言后端、低延迟、核心链路 | 多语言、异构系统、需要统一服务边界 |

> 原则：**能直接嵌入 SDK 时优先使用本地 SDK；仅在无法嵌入 SDK 或需要统一 Sidecar 服务时使用 Agent。**

各项目均包含 PRD、设计文档、实现文档、测试文档与使用手册，详见对应仓库的 `docs/` 目录。

> 本地开发时可将上述仓库克隆到 sfwork 根目录同级，sfwork 根仓库已通过 `.gitignore` 屏蔽这三个目录。

## 核心问题

1. **操作对象不同**：
   - 批量模式：直接对 DataMesh / Kuscia 中的数据库表进行操作（与现有 sfwork 项目一致）。
   - 本地模式：对单条/小批量数据在应用本地进行处理，需要统一的本地函数接口，并考虑跨语言、跨数据格式。

2. **隐私处理参数如何设置**：
   - 请求时参数从哪里来？自动推荐、手动配置、配置文件、策略模板还是混合模式？
   - 参数如何治理？版本、校验、审计、密钥隔离。
