---
name: sfwork-workspace
description: Work in the sfwork mono-repo workspace containing Kuscia, SecretFlow, SecretPad backend, and SecretPad frontend. Use for any task that spans multiple sub-projects, needs environment setup, build/test commands, or cross-project integration. Also use when the user asks about the overall workspace structure, ports, or how to run everything locally.
---

# SFWork Workspace

The sfwork workspace bundles four main projects: Kuscia (Go), SecretFlow (Python), SecretPad backend (Java/Spring Boot), and SecretPad frontend (TypeScript/React/Umi).

## Workspace Layout

```
sfwork/
├── kuscia/                 # Go orchestration engine
├── secretflow/             # Python privacy-preserving ML framework
├── secretpad/              # Java backend + frontend-src
├── secretpad-frontend/     # Legacy frontend copy (inactive)
├── privacy-java-sdk/       # Java local privacy SDK
├── privacy-go-sdk/         # Go local privacy SDK
├── privacy-local-agent/    # Python REST/gRPC privacy agent
├── deploy/                 # Docker Compose deployment
├── scripts/                # Dev scripts (run-all-no-docker.sh, etc.)
├── docs/doc-center/        # Centralized documentation archive
└── AGENTS.md               # Agent guide for this workspace
```

## Critical Environment

- **Python**: conda env `sf310`, Python 3.10
- **Node.js**: v22.22.1, pnpm 8.8.0
- **Java**: 17
- **Go**: 1.24.7
- **Frontend dev**: `http://localhost:8000`
- **Backend**: `https://localhost:8443`, HTTP `http://localhost:8080`, inner `http://localhost:9001`
- **Kuscia API gRPC**: `127.0.0.1:18083`
- **Kuscia Gateway**: `127.0.0.1:13081`
- **Login**: `admin` / `12345678`

## Key Commands

```bash
# Run all locally (non-Docker)
bash scripts/run-all-no-docker.sh

# Stop all
bash scripts/run-all-no-docker.sh --stop

# Build Kuscia
cd kuscia && make build

# Build SecretFlow
cd secretflow && pip install -e .

# Build SecretPad backend
cd secretpad && mvn clean package -DskipTests

# Bootstrap frontend
cd secretpad/frontend-src && pnpm bootstrap

# Dev frontend
cd secretpad/frontend-src && pnpm --filter secretpad dev
```

## Cross-Project Contracts

- **Frontend ↔ Backend**: REST JSON under `/api/v1alpha1/*`
- **Backend ↔ Kuscia**: gRPC via `secretpad-api/client-java-kusciaapi`
- **Kuscia ↔ SecretFlow**: Kuscia schedules containers; SecretFlow reads DomainData via DataMesh
- **DataMesh ↔ SecretFlow**: gRPC + Apache Arrow Flight

## Workflow

1. Check `AGENTS.md` and `docs/doc-center/README.md` for context.
2. Identify which sub-project owns the change.
3. Make changes, build/test in the relevant sub-project.
4. For frontend/backend integration, restart both services.
5. For Kuscia changes, rebuild the Kuscia binary and restart.

## Safety

- Do not run `git commit/push/reset/rebase` unless explicitly asked.
- Do not modify files outside the working directory.
- Local Kuscia may need `sudo` for ports 53/80.
