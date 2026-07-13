---
name: secretpad-frontend-dev
description: Develop the SecretPad frontend. Use when the user asks about frontend code changes, UI components, pages, DAG canvas, theming, build, lint, tests, or frontend-backend integration. This skill covers both secretpad/frontend-src (active) and secretpad-frontend (legacy copy).
---

# SecretPad Frontend Development

The active frontend is in `secretpad/frontend-src/`. `secretpad-frontend/` is a legacy copy.

## Stack

- Node.js >= 16.14.0, pnpm 8.8.0
- React 18, Umi 4, Ant Design 5
- TypeScript 4.9
- Valtio for state management
- Nx monorepo, tsup for shared packages
- Jest + React Testing Library

## Project Structure

```
secretpad/frontend-src/
├── apps/
│   ├── platform/          # Main SecretPad web app
│   └── docs/              # Dumi documentation site
├── packages/
│   ├── dag/               # @secretflow/dag DAG engine
│   └── utils/             # @secretflow/utils
├── tooling/               # Shared eslint/stylelint/tsconfig/jest/tsup
└── apps/docs/docs/dev-doc/# Frontend dev docs (also in docs/doc-center)
```

## Key Commands

```bash
cd secretpad/frontend-src

# Install deps and build shared packages
pnpm bootstrap

# Dev server (http://localhost:8000)
pnpm --filter secretpad dev

# Build
pnpm --filter secretpad build

# Test
pnpm --filter secretpad test

# Lint / format
pnpm --filter secretpad lint:js
pnpm --filter secretpad lint:css
pnpm --filter secretpad lint:typing
pnpm fix
pnpm format-all
```

## Conventions

- Prettier: printWidth 88, singleQuote, trailingComma all
- State management: Valtio via `src/util/valtio-helper.ts`, not Dva
- REST API: umi-request, OpenAPI codegen from backend Swagger
- Path alias: `@/` points to `apps/platform/src/`
- Login session stored via `LoginService`

## Common Workflows

1. **Add a page**: See `docs/doc-center/02-前端开发/frontend-new-page.md`
2. **Add a module**: See `docs/doc-center/02-前端开发/frontend-new-module.md`
3. **Theme change**: `apps/platform/src/styles/theme.ts` and Ant Design theme config
4. **DAG changes**: `packages/dag/`
5. **Backend API change**: Regenerate OpenAPI client via `frontend-openAPI.md`

## Important Paths

- Main app: `apps/platform/src/`
- Routes: `apps/platform/src/pages/` or config in `.umirc.ts`
- Services: `apps/platform/src/modules/*/`
- Shared DAG: `packages/dag/`
- Dev docs: `apps/docs/docs/dev-doc/`
