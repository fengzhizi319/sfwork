---
name: doc-center-reader
description: Read and navigate the centralized documentation archive in docs/doc-center. Use when the user asks about project documentation, architecture, deployment, frontend/backend/kuscia development guides, privacy algorithms, or any topic covered by the sfwork documentation. Also use when you need to confirm conventions, find the right document, or answer questions about how the system works.
---

# Doc Center Reader

Use this skill to quickly find and reference the right documentation in `docs/doc-center/`.

## Quick Navigation

- **Start here**: `docs/doc-center/README.md`
- **Project overview**: `docs/doc-center/00-项目总览/`
- **Architecture**: `docs/doc-center/01-架构设计/`
- **Frontend**: `docs/doc-center/02-前端开发/`
- **Backend**: `docs/doc-center/03-后端开发/`
- **Kuscia**: `docs/doc-center/04-Kuscia/`
- **Algorithms & Privacy**: `docs/doc-center/05-算法与隐私/`
- **Deployment & Ops**: `docs/doc-center/06-部署运维/`
- **Dev Conventions**: `docs/doc-center/07-开发规范/`
- **Troubleshooting**: `docs/doc-center/08-问题排查/`
- **Reference**: `docs/doc-center/99-参考杂项/`

## How to Use

1. When a question is broad, read `docs/doc-center/README.md` first to identify the category.
2. Read the `index.md` in the relevant category directory.
3. Read the specific document. Prefer local copies in `docs/doc-center/` over source-tree originals.
4. For cross-cutting topics (e.g., DataMesh, FL flow), check both backend and Kuscia categories.

## Key Documents by Task

| Task | Document |
|---|---|
| Understand the full privacy computing stack | `00-项目总览/数据分类分级与本地隐私原语-团队汇报与落地白皮书.md` |
| Presentation / reporting | `00-项目总览/数据分类分级与本地隐私原语-汇报PPT.html` |
| Frontend page requirements | `02-前端开发/index.md` → PRD files |
| Backend API / integration | `03-后端开发/index.md` |
| Kuscia deployment | `04-Kuscia/index.md` → deployment files |
| Classification / DP algorithms | `05-算法与隐私/index.md` |
| Local non-Docker run | `06-部署运维/sfwork-无docker运行说明.md` |
| FAQ / bug localization | `08-问题排查/index.md` |

## Notes

- The doc-center contains copies of docs from `sfwork/docs/`, `secretpad/docs/`, `secretpad-frontend/`, `kuscia/docs/`, and `privacy-local-agent/docs/`.
- Source prefixes (`sfwork-`, `secretpad-`, `kuscia-`, `frontend-`, `privacy-local-agent-`) indicate origin.
