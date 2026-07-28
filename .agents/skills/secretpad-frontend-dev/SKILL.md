---
name: secretpad-frontend-dev
description: Develop the SecretPad frontend. Use when the user asks about frontend code changes, UI components, pages, DAG canvas, theming, build, lint, tests, or frontend-backend integration. The active frontend is the independent repo secretpad-frontend cloned at secretpad/frontend-src/ (umi 4 + Ant Design app at apps/platform); the old Vite frontend at secretpad/web/ has been removed.
---

# SecretPad Frontend Development

The active frontend is the independent repository `secretpad-frontend`, cloned into `secretpad/frontend-src/`. The real application is `apps/platform` (package name `secretpad`, built with umi). The previous Vite frontend at `secretpad/web/` has been deprecated and removed.

## Stack

- Node.js >= 16.14.0, pnpm 8.8.0 (managed by `packageManager`)
- umi 4.x (React 18), Ant Design 5
- TypeScript
- Valtio for state management (via `src/util/valtio-helper.ts`)
- Nx + pnpm workspace monorepo
- Jest + React Testing Library

## Project Structure

```
secretpad/frontend-src/
├── apps/
│   ├── platform/               # Main SecretPad web app (umi 4 + React 18 + Ant Design, package name `secretpad`)
│   └── docs/                   # Documentation site
├── packages/
│   ├── dag/                    # @secretflow/dag DAG canvas engine
│   └── utils/                  # @secretflow/utils shared utilities
└── tooling/                    # Shared eslint / jest / stylelint / tsconfig / tsup configs
```

## Key Commands

```bash
cd secretpad/frontend-src

# Install dependencies
corepack pnpm install

# Dev server (http://localhost:8000), active app is apps/platform (package name secretpad)
corepack pnpm --filter secretpad dev

# Build all packages and the main app (nx run-many --target=build)
corepack pnpm run build

# Test
corepack pnpm test

# Lint / format
corepack pnpm run lint
```

## Conventions

- Prettier: printWidth 88, singleQuote, trailingComma all
- State management: Valtio via `src/util/valtio-helper.ts` (`Model` / `getModel` / `useModel`)
- REST API: OpenAPI-generated client under `src/services/secretpad/`
- Routing: umi routes in `config/routes.ts`, with `@/wrappers/*` for auth/theme
- Feature code lives in `src/modules/<feature>/` following a `*.view.tsx` + `*-service.ts` pattern
- Conventional Commits enforced by Husky/commitlint; lint-staged runs prettier/stylelint/eslint on commit

## Common Workflows

1. **Add a page**: Create the page component under `apps/platform/src/pages/`, register it in `apps/platform/config/routes.ts` (with the appropriate `@/wrappers/*`).
2. **Add/modify a feature**: Work in `apps/platform/src/modules/<feature>/` — a `*.view.tsx` for the UI plus a `*-service.ts` (Valtio model) for state and API calls.
3. **DAG changes**: `packages/dag/src/` (the `@secretflow/dag` canvas engine), consumed by `src/modules/main-dag/`.
4. **Backend API change**: Update `config/openapi.config.js` and regenerate the client with `corepack pnpm --filter secretpad openapi`, keeping `src/services/secretpad/` in sync.

## Important Paths

- Main app: `apps/platform/src/`
- Routes: `apps/platform/config/routes.ts`
- Pages: `apps/platform/src/pages/`
- Feature modules: `apps/platform/src/modules/`
- API client: `apps/platform/src/services/secretpad/`
- Valtio helper: `apps/platform/src/util/valtio-helper.ts`
- DAG engine: `packages/dag/src/`
---
name: secretpad-frontend-dev
description: Develop the SecretPad frontend. Use when the user asks about frontend code changes, UI components, pages, DAG canvas, theming, build, lint, tests, or frontend-backend integration. The active frontend lives in secretpad/web/; secretpad/frontend-src and secretpad-frontend are legacy copies that have been removed/deprecated.
---

# SecretPad Frontend Development

The active frontend is in `secretpad/web/`. Legacy frontend directories (`secretpad/frontend-src/`, `secretpad-frontend/`) have been removed/deprecated as part of the migration.

## Stack

- Node.js >= 18.0.0, pnpm >= 8.8.0 (managed by `packageManager`, currently pnpm@11.7.0)
- React 18, Vite 5, Tailwind CSS
- TypeScript 5.x
- TanStack Router + TanStack Query v5
- Zustand for state management
- pnpm workspace monorepo
- Vitest + React Testing Library

## Project Structure

```
secretpad/web/
├── apps/
│   └── secretpad/              # Main SecretPad web app (Vite 5 + React 18)
├── packages/
│   ├── design-system/          # @secretpad/design-system component library
│   ├── api-client/             # @secretpad/api-client OpenAPI-generated client + schemas
│   ├── dag-next/               # @secretpad/dag-next DAG canvas engine
│   └── utils/                  # @secretpad/utils shared utilities
├── tooling/
│   └── tsconfig/               # Shared TypeScript configs
└── docs/                       # Frontend migration / consistency docs
```

## Key Commands

```bash
cd secretpad/web

# Install dependencies
corepack pnpm install

# Dev server (http://localhost:8000)
corepack pnpm --filter @secretpad/app dev

# Build all packages and the main app
corepack pnpm run build

# Typecheck
corepack pnpm typecheck

# Test
corepack pnpm test

# Lint / format
corepack pnpm run lint
```

## Conventions

- Prettier: printWidth 88, singleQuote, trailingComma all
- State management: Zustand (auth/theme), TanStack Query (server state)
- REST API: `openapi-typescript` + `openapi-fetch` via `@secretpad/api-client`
- Path alias: use relative imports or workspace package names (`@secretpad/*`)
- Runtime schema validation: Zod `unwrapValidated`/`validated`
- All user-visible text through `shared/lib/i18n` dictionaries (zh-CN / en-US)

## Common Workflows

1. **Add a page**: Create `apps/secretpad/src/pages/<page>/index.tsx`, register in `apps/secretpad/src/router.tsx`, add sidebar entry and i18n keys.
2. **Add a DAG template**: Create `apps/secretpad/src/features/dag-templates/templates/<name>.ts`, register in `apps/secretpad/src/features/dag-templates/registry.ts`, add i18n keys.
3. **Theme change**: Tailwind classes + dark variants; no Ant Design theme config.
4. **DAG changes**: `packages/dag-next/src/`.
5. **Backend API change**: Update `openapi/secretpad.openapi.json`, regenerate types/client if needed; keep `packages/api-client/src/schemas/index.ts` in sync.

## Important Paths

- Main app: `apps/secretpad/src/`
- Routes: `apps/secretpad/src/router.tsx`
- Pages: `apps/secretpad/src/pages/`
- Features: `apps/secretpad/src/features/`
- Shared: `apps/secretpad/src/shared/`
- API client: `packages/api-client/src/`
- DAG engine: `packages/dag-next/src/`
- i18n dictionaries: `apps/secretpad/src/shared/lib/i18n/dictionaries.ts`
- Migration docs: `secretpad/web/docs/frontend-migration-consistency.md`
